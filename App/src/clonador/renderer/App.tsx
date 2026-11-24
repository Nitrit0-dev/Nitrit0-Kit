import { useEffect, useRef, useState } from 'react'
import logo from '../../renderer/src/recursos/logo-nitrit0.png'
import { ErrorBoundary, Medidor, PageHeader, Veredicto } from '../../renderer/src/componentes/Basicos'
import type { Disco, Fin } from '../preload'

const limpiar = (e: unknown) => String(e).replace(/^Error: (Error invoking remote method '[^']+': )?(Error: )?/, '')
const serieCorta = (d: Disco) => (d.Serie ? `serie …${d.Serie.slice(-8)}` : 'sin serie')
const textoDisco = (d: Disco) => `${d.Numero} · ${d.Nombre} · ${d.GB} GB · ${d.Bus || d.Estilo} · ${serieCorta(d)}${d.Letras ? ` · ${d.Letras}:` : ''}${d.Sistema ? ' · Windows en marcha' : ''}${d.Kit ? ' · este kit' : ''}`
const MAX_LINEAS = 3000
type Par = { o: number; d: number; oId: string; dId: string; carpeta: string; extra: 'Windows' | 'Datos' }
const NOMBRE_FASE = ['', 'Instantánea de Windows', 'Capturando Windows', 'Preparando el destino', 'Aplicando la imagen', 'Copiando datos y recuperación', 'Arranque']
const hms = (s: number) => `${Math.floor(s / 3600) ? `${Math.floor(s / 3600)} h ` : ''}${Math.floor((s % 3600) / 60)} min ${s % 60} s`

export default function App() {
  const [oscuro, setOscuro] = useState(true)
  const [hayScript, setHayScript] = useState(true)
  const [discos, setDiscos] = useState<Disco[] | null>(null)
  const [origen, setOrigen] = useState('')
  const [destino, setDestino] = useState('')
  const [carpeta, setCarpeta] = useState('')
  const [lineas, setLineas] = useState<string[]>([])
  const [ocupado, setOcupado] = useState(false)
  const [op, setOp] = useState('')
  const [simOk, setSimOk] = useState<Par | null>(null)   // el último par simulado con éxito: «Clonar de verdad» solo se abre para ese mismo par
  const [resultado, setResultado] = useState<{ tono: 'ok' | 'aviso' | 'error'; titulo: string; detalle: string } | null>(null)
  const [pie, setPie] = useState('')
  const [pidiendo, setPidiendo] = useState(false)
  const [cortando, setCortando] = useState(false)
  const [frase, setFrase] = useState('')
  const [extra, setExtra] = useState<'Windows' | 'Datos'>('Windows')
  const [fase, setFase] = useState(0)
  const [segundos, setSegundos] = useState(0)
  const opRef = useRef('')
  const parLanzado = useRef<Par | null>(null)
  const consola = useRef<HTMLDivElement>(null)
  const dialogo = useRef<HTMLDialogElement>(null)
  const dialogoCortar = useRef<HTMLDialogElement>(null)
  const ponOp = (x: string) => { opRef.current = x; setOp(x) }

  const o = origen === '' ? null : Number(origen), d = destino === '' ? null : Number(destino)
  const dO = discos?.find((x) => x.Numero === o) ?? null, dD = discos?.find((x) => x.Numero === d) ?? null
  const par: Par | null = dO && dD ? { o: dO.Numero, d: dD.Numero, oId: dO.Id, dId: dD.Id, carpeta: carpeta.trim(), extra } : null
  const mismoPar = (a: Par | null, b: Par | null) => !!a && !!b && a.o === b.o && a.d === b.d && a.oId === b.oId && a.dId === b.dId && a.carpeta === b.carpeta && a.extra === b.extra
  const fraseNecesaria = d === null ? '' : `BORRAR DISCO ${d}`
  const gemelo = !!dD && !!discos && discos.some((x) => x.Numero !== dD.Numero && x.Nombre === dD.Nombre && x.GB === dD.GB)

  useEffect(() => {
    void window.clonador.estado().then((e) => {
      setHayScript(e.hayScript)
      if (e.tema !== 'sistema') { setOscuro(e.tema === 'oscuro'); return }
      const mq = window.matchMedia('(prefers-color-scheme: dark)')
      setOscuro(mq.matches)
      mq.addEventListener('change', (ev) => setOscuro(ev.matches))   // vive lo que la ventana: no hace falta quitarlo
    })
  }, [])
  useEffect(() => { document.documentElement.dataset.tema = oscuro ? 'oscuro' : 'claro' }, [oscuro])
  useEffect(() => {
    const quitar = [
      window.clonador.alLinea((l) => { if (opRef.current !== 'listar') setLineas((a) => [...a, l].slice(-MAX_LINEAS)) }),
      window.clonador.alDiscos(setDiscos),
      window.clonador.alFase((n) => setFase((a) => Math.max(a, n))),
      window.clonador.alFin((f: Fin) => {
        if (f.op === 'listar') { setOcupado(false); ponOp(''); if (f.codigo !== 0) { setDiscos((x) => x ?? []); setPie('No se pudieron leer los discos (hace falta administrador).') } return }
        if (f.op === 'limpiar') { setOcupado(false); ponOp(''); setPie(f.codigo === 0 ? 'Cancelado y limpiado.' : 'La limpieza de restos terminó con errores: mira el registro.'); return }
        const sim = f.op === 'simular'
        if (f.cancelado) { setOcupado(true); ponOp('limpiar') }   // el proceso principal limpia enseguida lo que deja el corte: hasta entonces no se admite otra operación
        else { setOcupado(false); ponOp('') }
        setResultado(f.cancelado ? { tono: 'aviso', titulo: 'Cancelado', detalle: sim ? 'No se ha cambiado nada.' : 'El disco origen no se ha modificado. Si ya había empezado a escribir, el destino puede haber quedado a medias: repite el clonado.' }
          : f.codigo === 0 ? { tono: 'ok', titulo: sim ? 'La simulación encaja' : 'Clonado terminado', detalle: sim ? 'No se ha cambiado nada. Si el plan es el que quieres, pulsa «Clonar de verdad…».' : 'Apaga, desconecta el disco antiguo (o elígelo en el menú de arranque) y prueba a arrancar con el nuevo: es la única prueba definitiva.' }
          : { tono: 'error', titulo: sim ? 'No se puede clonar así' : 'El clonado falló', detalle: sim ? 'No se ha cambiado nada. Mira los motivos en el registro.' : 'El disco origen no se ha modificado. Mira en el registro si el destino llegó a tocarse y repite.' })
        if (sim && f.codigo === 0 && !f.cancelado) setSimOk(parLanzado.current)
        setPie(f.cancelado ? 'Cancelado: limpiando restos…' : f.codigo === 0 ? 'Terminado.' : 'Terminó con errores.')
      })
    ]
    ponOp('listar'); setOcupado(true)
    void window.clonador.correr({ op: 'listar' }).then((r) => { if (!r.ok) { setOcupado(false); ponOp(''); setDiscos([]); setPie(r.mensaje) } })
    return () => quitar.forEach((q) => q())
  }, [])
  useEffect(() => { consola.current?.scrollTo({ top: consola.current.scrollHeight }) }, [lineas])
  useEffect(() => {   // tiempo transcurrido mientras simula o clona
    if (op !== 'simular' && op !== 'ejecutar') return
    const t0 = Date.now(); setSegundos(0)
    const id = setInterval(() => setSegundos(Math.floor((Date.now() - t0) / 1000)), 1000)
    return () => clearInterval(id)
  }, [op])
  useEffect(() => {
    const el = dialogo.current
    if (!el) return
    if (pidiendo && !el.open) el.showModal()
    if (!pidiendo && el.open) el.close()
  }, [pidiendo])
  useEffect(() => {
    const el = dialogoCortar.current
    if (!el) return
    if (cortando && !el.open) el.showModal()
    if (!cortando && el.open) el.close()
  }, [cortando])

  const lanzar = async (tipo: 'simular' | 'ejecutar', confirmo?: string) => {
    if (!par) return
    parLanzado.current = par
    if (tipo === 'ejecutar') setSimOk(null)   // cada clonado de verdad exige una simulación nueva
    ponOp(tipo); setLineas([]); setResultado(null); setOcupado(true); setFase(0)
    setPie(tipo === 'simular' ? 'Simulando…' : 'Clonando: tarda; no desconectes ni apagues nada.')
    try {
      const r = await window.clonador.correr({ op: tipo, origen: par.o, destino: par.d, origenId: par.oId, destinoId: par.dId, carpeta: par.carpeta || undefined, extra: par.extra, confirmo })
      if (!r.ok) { setOcupado(false); ponOp(''); setPie(r.mensaje); setResultado({ tono: 'error', titulo: 'No se pudo empezar', detalle: r.mensaje }) }
    } catch (e) { setOcupado(false); ponOp(''); setPie(limpiar(e)) }
  }
  const elegirCarpeta = async () => { try { const c = await window.clonador.carpeta(); if (c) setCarpeta(c) } catch (e) { setPie(limpiar(e)) } }
  const refrescar = () => {
    // Los números de disco pueden cambiar al conectar o quitar un USB: tras volver a leer hay que elegir de nuevo
    setOrigen(''); setDestino(''); setSimOk(null); setResultado(null)
    ponOp('listar'); setOcupado(true); setDiscos(null)
    void window.clonador.correr({ op: 'listar' }).then((r) => { if (!r.ok) { setOcupado(false); ponOp(''); setDiscos([]); setPie(r.mensaje) } })
  }
  const guardar = async () => { try { setPie(`Registro guardado en ${await window.clonador.guardarRegistro(lineas)}`) } catch (e) { setPie(limpiar(e)) } }

  const mismo = o !== null && o === d
  const listo = !!par && !mismo && !ocupado
  const puedeClonar = listo && mismoPar(par, simOk)
  const corriendo = ocupado && (op === 'simular' || op === 'ejecutar')

  return (
    <div className="app simple">
      <div className="barra-titulo"><img src={logo} alt="" /><b>Nitrit0 Clonador</b></div>
      <main className="principal">
        <ErrorBoundary>
          <div className="pagina">
            <PageHeader titulo="Clonar disco" subtitulo="Copia un Windows (GPT/UEFI) a otro disco, incluso más pequeño, y deja el arranque listo. El disco origen no se modifica." comoUsar={['Elige origen y destino.', 'Pulsa «Simular»: enseña el plan y no cambia nada.', 'Si encaja, «Clonar de verdad…» y escribe la confirmación.']} />
            {!hayScript && <p className="aviso-txt" role="alert">Este pack no lleva Clonar_Disco.ps1: el clonado es solo del pack personal.</p>}
            <section className="bloque" aria-label="Discos">
              <h2>Discos</h2>
              <div className="selectores">
                <label className="campo">Disco ORIGEN (se copia; no se modifica)
                  <select value={origen} onChange={(e) => { setOrigen(e.target.value); setSimOk(null) }} disabled={ocupado || !discos}>
                    <option value="">{discos ? 'Elige un disco…' : 'Leyendo discos…'}</option>
                    {(discos ?? []).map((x) => <option key={x.Numero} value={x.Numero} disabled={!x.TieneWindows}>{textoDisco(x)}{x.TieneWindows ? '' : ' (sin Windows)'}</option>)}
                  </select>
                </label>
                <label className="campo">Disco DESTINO (se BORRA ENTERO)
                  <select className="destino" value={destino} onChange={(e) => { setDestino(e.target.value); setSimOk(null) }} disabled={ocupado || !discos}>
                    <option value="">{discos ? 'Elige un disco…' : 'Leyendo discos…'}</option>
                    {(discos ?? []).map((x) => <option key={x.Numero} value={x.Numero} disabled={x.Sistema || x.Kit}>{textoDisco(x)}{x.Sistema || x.Kit ? ' (no se puede borrar)' : ''}</option>)}
                  </select>
                </label>
              </div>
              {discos && discos.length < 2 && <p className="aviso-txt" role="alert">Hace falta al menos otro disco conectado para clonar.</p>}
              {mismo && <p className="aviso-txt" role="alert">El origen y el destino son el mismo disco.</p>}
              {gemelo && <p className="aviso-txt" role="alert">Hay otro disco idéntico conectado (mismo modelo y tamaño): comprueba la serie y que el destino es el que quieres borrar.</p>}
              {dD?.USB && <p className="aviso-txt" role="alert">El destino es un disco USB: casi siempre es un error, y el clonado será lento. Asegúrate de que es el disco nuevo.</p>}
              <div className="fila-acciones"><button className="boton" disabled={ocupado} onClick={refrescar}>Volver a leer los discos</button></div>
            </section>
            <section className="bloque" aria-label="Imagen temporal">
              <h2>Imagen temporal</h2>
              <div className="carpeta">
                <input value={carpeta} onChange={(e) => { setCarpeta(e.target.value); setSimOk(null) }} placeholder="Vacío = elegir sola un disco con sitio libre" aria-label="Carpeta para la imagen temporal" spellCheck={false} disabled={ocupado} />
                <button className="boton" disabled={ocupado} onClick={() => void elegirCarpeta()}>Examinar…</button>
              </div>
              <label className="campo">Si el destino es mayor, el espacio sobrante va a…
                <select value={extra} onChange={(e) => { setExtra(e.target.value === 'Datos' ? 'Datos' : 'Windows'); setSimOk(null) }} disabled={ocupado}>
                  <option value="Windows">La partición de Windows (C:)</option>
                  <option value="Datos">La última partición de datos (Windows conserva lo necesario)</option>
                </select>
              </label>
              <p className="nota-vacia">Windows se captura en una imagen temporal (más o menos lo que ocupa) en OTRO disco que no sea ni el origen ni el destino; se borra al terminar. El destino no se toca hasta que la imagen está hecha.</p>
            </section>
            <div className="acciones-clon">
              <button className="boton principal-b grande" disabled={!listo || !hayScript} onClick={() => void lanzar('simular')}>Simular (no cambia nada)</button>
              <button className="boton peligro-b grande" disabled={!puedeClonar || !hayScript} title={listo && !puedeClonar ? 'Primero simula este mismo par de discos' : undefined} onClick={() => { setFrase(''); setPidiendo(true) }}>Clonar de verdad…</button>
              {corriendo && <button className="boton" onClick={() => setCortando(true)}>Cancelar</button>}
              {listo && !puedeClonar && <span className="nota-vacia">Para clonar de verdad, simula antes este mismo par de discos.</span>}
            </div>
            {corriendo && op === 'ejecutar' && (
              <section className="bloque" aria-label="Avance">
                <h2>Avance · fase {fase || 1} de 6{NOMBRE_FASE[fase] ? ` · ${NOMBRE_FASE[fase]}` : ''} · {hms(segundos)}</h2>
                <Medidor valor={fase} max={6} etiqueta="Fase del clonado" rol="progressbar" />
                <p className="nota-vacia">Las fases 2 y 4 (capturar y aplicar Windows) son las largas; el registro de abajo cuenta cómo va.</p>
              </section>
            )}
            {resultado && <Veredicto tono={resultado.tono} titulo={resultado.titulo}>{resultado.detalle}</Veredicto>}
            <section className="bloque" aria-label="Registro">
              <h2>Registro</h2>
              <div className="consola clon" ref={consola} role="log" aria-live="polite" tabIndex={0}>{lineas.length ? lineas.join('\n') : 'Aquí aparece el plan y el avance.'}</div>
              <div className="fila-acciones"><button className="boton" disabled={!lineas.length} onClick={() => void guardar()}>Guardar registro…</button></div>
            </section>
          </div>
        </ErrorBoundary>
      </main>
      <dialog ref={dialogo} className="frase" onCancel={(e) => { e.preventDefault(); setPidiendo(false) }} aria-labelledby="dlg-clon">
        <h2 id="dlg-clon">Confirmar borrado del disco destino</h2>
        <p><b>Origen (no se modifica):</b> {dO ? textoDisco(dO) : ''}</p>
        <p><b>Destino (SE BORRA ENTERO):</b> {dD ? textoDisco(dD) : ''}</p>
        <p>No se puede deshacer. Para continuar escribe exactamente: <code>{fraseNecesaria}</code></p>
        <input value={frase} onChange={(e) => setFrase(e.target.value)} aria-label="Frase de confirmación" autoComplete="off" spellCheck={false} />
        <div className="pie-dialogo">
          <button className="boton" autoFocus onClick={() => setPidiendo(false)}>Cancelar</button>
          <button className="boton peligro-b" disabled={frase !== fraseNecesaria || !fraseNecesaria} onClick={() => { setPidiendo(false); void lanzar('ejecutar', frase) }}>Borrar y clonar</button>
        </div>
      </dialog>
      <dialog ref={dialogoCortar} onCancel={(e) => { e.preventDefault(); setCortando(false) }} aria-labelledby="dlg-cortar">
        <h2 id="dlg-cortar">¿Cortar la operación?</h2>
        <p>Si ya estaba escribiendo en el destino, quedará a medias y habrá que repetir el clonado desde el principio. El disco origen no se modifica. Después se limpian los restos (imagen temporal, instantáneas).</p>
        <div className="pie-dialogo">
          <button className="boton" autoFocus onClick={() => setCortando(false)}>Seguir</button>
          <button className="boton peligro-b" onClick={() => { setCortando(false); void window.clonador.cancelar() }}>Cortar</button>
        </div>
      </dialog>
      <div className="pie-estado" role="status" aria-live="polite"><span>{pie}</span></div>
    </div>
  )
}
