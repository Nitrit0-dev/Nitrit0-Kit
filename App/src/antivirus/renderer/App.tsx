import { useEffect, useRef, useState } from 'react'
import logo from '../../renderer/src/recursos/logo-nitrit0.png'
import { ErrorBoundary, PageHeader, Veredicto } from '../../renderer/src/componentes/Basicos'
import type { Resultado, ResultadoCarpeta, VT } from '../preload'

interface Item { id: number; ruta: string; carpeta?: boolean; estado: 'espera' | 'analizando' | 'listo' | 'fallo'; r?: Resultado; c?: ResultadoCarpeta; error?: string }

const nombreDe = (ruta: string) => ruta.split(/[\\/]/).pop() ?? ruta
const tamano = (b: number) => (b >= 2 ** 30 ? `${(b / 2 ** 30).toFixed(1)} GB` : b >= 2 ** 20 ? `${(b / 2 ** 20).toFixed(1)} MB` : `${Math.max(1, Math.round(b / 1024))} KB`)
const limpiar = (e: unknown) => String(e).replace(/^Error: (Error invoking remote method '[^']+': )?(Error: )?/, '')

function textoVT(vt: VT): string {
  switch (vt.estado) {
    case 'conocido': return `VirusTotal: ${vt.malicioso} malicioso${vt.malicioso === 1 ? '' : 's'}, ${vt.sospechoso} sospechoso${vt.sospechoso === 1 ? '' : 's'}, ${vt.limpio} sin detección (de ${vt.total} motores)${vt.etiqueta ? ` · ${vt.etiqueta}` : ''}.`
    case 'desconocido': return 'VirusTotal: no conoce este archivo.'
    case 'sin-clave': return 'VirusTotal: sin clave, no consultado.'
    case 'clave-invalida': return 'VirusTotal: la clave no es válida.'
    case 'limite': return 'VirusTotal: límite de consultas por minuto alcanzado, repite en un minuto.'
    default: return `VirusTotal: ${vt.detalle ?? 'no disponible'}`
  }
}
const textoClam = (r: Resultado) => !r.clam ? '' : r.clam.estado === 'limpio' ? 'ClamAV: sin amenazas.' : r.clam.estado === 'amenaza' ? `ClamAV: amenaza${r.clam.amenaza ? ` (${r.clam.amenaza})` : ''}.` : `ClamAV: ${r.clam.detalle ?? 'no disponible'}`
const textoFirma = (r: Resultado) => !r.firma ? '' : r.firma.estado === 'firmado' ? `Firma digital: válida${r.firma.firmante ? ` (${r.firma.firmante})` : ''}.` : r.firma.estado === 'sin-firma' ? 'Firma digital: no lleva.' : r.firma.estado === 'invalida' ? 'Firma digital: NO coincide con el archivo.' : r.firma.estado === 'no-confiable' ? `Firma digital: presente pero Windows no se fía${r.firma.firmante ? ` (${r.firma.firmante})` : ''}.` : 'Firma digital: no se pudo comprobar.'
const textoVersion = (r: Resultado) => {
  const v = r.version
  if (!v) return 'Versión: este tipo de archivo no la indica.'
  const num = v.archivo || v.producto
  const nombre = [v.nombre, v.empresa].filter(Boolean).join(' · ')
  return `Versión: ${num || 'sin número'}${nombre ? ` (${nombre})` : ''} · modificado el ${new Date(r.modificado).toLocaleDateString('es-ES')}`
}
const textoDefender = (r: Resultado) => r.defender.estado === 'limpio' ? 'Defender: sin amenazas.' : r.defender.estado === 'amenaza' ? `Defender: amenaza${r.defender.amenaza ? ` (${r.defender.amenaza})` : ''}.` : `Defender: ${r.defender.detalle ?? 'no disponible'}`

export default function App() {
  const [oscuro, setOscuro] = useState(true)
  const [items, setItems] = useState<Item[]>([])
  const [clave, setClave] = useState(false)
  const [defender, setDefender] = useState(true)
  const [motores, setMotores] = useState<Awaited<ReturnType<typeof window.antivirus.motores>> | null>(null)
  const [actualizando, setActualizando] = useState<'' | 'defender' | 'clam'>('')
  const [campo, setCampo] = useState('')
  const [pie, setPie] = useState('')
  const [encima, setEncima] = useState(false)
  const [fase, setFase] = useState('')
  const siguiente = useRef(1)
  const activas = useRef(new Set<string>())
  const cola = useRef<Promise<void>>(Promise.resolve())
  const cancelarTodo = useRef(false)   // «Cancelar» corta el análisis en curso Y vacía lo que esperaba en la cola
  const pendientes = useRef(0)

  useEffect(() => {
    void window.antivirus.estado().then((e) => {
      setClave(e.clave); setDefender(e.defender)
      if (e.tema !== 'sistema') { setOscuro(e.tema === 'oscuro'); return }
      const mq = window.matchMedia('(prefers-color-scheme: dark)')
      setOscuro(mq.matches)
      mq.addEventListener('change', (ev) => setOscuro(ev.matches))   // vive lo que la ventana: no hace falta quitarlo
    })
  }, [])
  const cargarMotores = () => { void window.antivirus.motores().then(setMotores).catch(() => setMotores(null)) }
  useEffect(() => { cargarMotores() }, [])
  useEffect(() => window.antivirus.alFase(setFase), [])
  useEffect(() => { document.documentElement.dataset.tema = oscuro ? 'oscuro' : 'claro' }, [oscuro])

  const revisar = (rutas: string[], sinRuta = 0, carpetas: string[] = []) => {
    if (actualizando) { setPie('Espera a que termine la actualización.'); return }
    const vistos = activas.current
    const unicas = rutas.filter((r, i) => !vistos.has(r.toLowerCase()) && rutas.findIndex((o) => o.toLowerCase() === r.toLowerCase()) === i)
    const lote = unicas.slice(0, 50)
    const omitidos = sinRuta + (rutas.length - unicas.length) + (unicas.length - lote.length)
    if (omitidos) setPie(`${omitidos} archivo${omitidos === 1 ? '' : 's'} sin revisar (repetidos, ya en cola, más de 50 de golpe o sin ruta en disco: guárdalos primero).`)
    lote.forEach((r) => activas.current.add(r.toLowerCase()))
    const nuevos = lote.map((ruta) => ({ id: siguiente.current++, ruta, carpeta: carpetas.includes(ruta), estado: 'espera' as const }))
    if (!nuevos.length) return
    setItems((a) => [...nuevos, ...a])
    setTimeout(() => document.getElementById('resultados')?.scrollIntoView({ behavior: 'smooth', block: 'start' }), 50)   // la lista queda debajo de la zona de soltar: sin esto parece que no pasa nada
    for (const it of nuevos) {
      // Uno detrás de otro: Defender y las consultas a VirusTotal no deben pisarse
      pendientes.current++
      cola.current = cola.current.then(async () => {
        if (cancelarTodo.current) {
          setItems((a) => a.map((x) => (x.id === it.id ? { ...x, estado: 'fallo', error: 'Cancelado.' } : x)))
          activas.current.delete(it.ruta.toLowerCase())
          if (--pendientes.current <= 0) cancelarTodo.current = false
          return
        }
        setItems((a) => a.map((x) => (x.id === it.id ? { ...x, estado: 'analizando' } : x)))
        try {
          if (it.carpeta) {
            const c = await window.antivirus.analizarCarpeta(it.ruta)
            setItems((a) => a.map((x) => (x.id === it.id ? { ...x, estado: 'listo', c } : x)))
          } else {
            const r = await window.antivirus.analizar(it.ruta)
            setItems((a) => a.map((x) => (x.id === it.id ? { ...x, estado: 'listo', r } : x)))
          }
          setPie('Revisión terminada. Puedes revisar otro archivo.')
        } catch (e) { setItems((a) => a.map((x) => (x.id === it.id ? { ...x, estado: 'fallo', error: limpiar(e) } : x))); setPie(/cancelad/i.test(limpiar(e)) ? 'Revisión cancelada. Puedes revisar otro archivo.' : 'No se pudo revisar ese archivo. Puedes probar con otro.') }
        finally { activas.current.delete(it.ruta.toLowerCase()); if (--pendientes.current <= 0) cancelarTodo.current = false }
      })
    }
  }
  const actualizar = async (motor: 'defender' | 'clam') => {
    setActualizando(motor); setPie(motor === 'defender' ? 'Actualizando Defender…' : 'Actualizando ClamAV (puede tardar unos minutos)…')
    try { const r = await window.antivirus.actualizar(motor); setPie(r.mensaje) } catch (e) { setPie(limpiar(e)) }
    setActualizando(''); cargarMotores()
  }
  const repetir = (it: Item) => { setItems((a) => a.filter((x) => x.id !== it.id)); revisar([it.ruta], 0, it.carpeta ? [it.ruta] : []) }
  const elegir = async () => { try { revisar(await window.antivirus.elegir()) } catch (e) { setPie(`No se pudo abrir el selector: ${limpiar(e)}`) } }
  const elegirCarpeta = async () => { try { const c = await window.antivirus.elegirCarpeta(); if (c) revisar([c], 0, [c]) } catch (e) { setPie(`No se pudo abrir el selector: ${limpiar(e)}`) } }
  const soltar = async (e: React.DragEvent) => {
    e.preventDefault(); setEncima(false)
    const todas = Array.from(e.dataTransfer.files).map((f) => window.antivirus.rutaDe(f))
    const rutas = todas.filter(Boolean)
    const carpetas = (await Promise.all(rutas.map(async (r) => ((await window.antivirus.esCarpeta(r).catch(() => false)) ? r : '')))).filter(Boolean)
    revisar(rutas, todas.length - rutas.length, carpetas)
  }
  const guardar = async () => {
    const r = await window.antivirus.guardarClave(campo.trim())
    if (r === 'ok') { setClave(campo.trim() !== ''); setCampo(''); setPie(campo.trim() ? 'Clave guardada en este kit.' : 'Clave borrada.') }
    else setPie(r === 'formato' ? 'La clave no tiene el formato de VirusTotal (letras y números, sin espacios).' : r === 'sin-kit' ? 'No encuentro la carpeta Datos del kit: la clave no se guarda fuera de él.' : 'No se pudo escribir en Datos (¿pendrive protegido contra escritura?).')
  }

  const resultados = (
            <section className="bloque" id="resultados" aria-label="Resultados">
              <h2>Resultados</h2>
              {items.some((x) => x.estado === 'listo' || x.estado === 'fallo') && <div><button className="boton" onClick={() => setItems((a) => a.filter((x) => x.estado === 'espera' || x.estado === 'analizando'))}>Limpiar resultados</button></div>}
              {items.length === 0 && <p className="nota-vacia">Todavía no has revisado ningún archivo.</p>}
              <div className="resultados">
                {items.map((it) => (
                  <div className="resultado" key={it.id}>
                    <div className="nombre">{nombreDe(it.ruta)}</div>
                    <div className="sub">{it.ruta}</div>
                    {it.estado === 'espera' && <p className="nota-vacia">En cola…</p>}
                    {it.estado === 'analizando' && <div className="fila-acciones"><p className="nota-vacia" role="status">{fase || 'Analizando… un archivo grande puede tardar un rato.'}</p><button className="boton" onClick={() => { cancelarTodo.current = true; void window.antivirus.cancelar() }}>Cancelar</button></div>}
                    {it.estado === 'fallo' && (<><p className="aviso-txt" role="alert">No se pudo revisar: {it.error}</p><div className="fila-acciones"><button className="boton" onClick={() => repetir(it)}>Volver a revisar</button><button className="boton principal-b" onClick={() => void elegir()}>Revisar otro archivo</button></div></>)}
                    {it.c && (
                      <>
                        <Veredicto tono={it.c.tono} titulo={it.c.titulo}>{it.c.detalle}</Veredicto>
                        {it.c.hallazgos.length > 0 && <ul className="sub">{it.c.hallazgos.map((h, i) => <li key={i}>{h.motor}: {h.nombre} · {h.archivo}</li>)}</ul>}
                        <div className="sub">{it.c.defender.estado === 'limpio' ? 'Defender: sin amenazas.' : it.c.defender.estado === 'amenaza' ? 'Defender: amenazas encontradas.' : `Defender: ${it.c.defender.detalle ?? 'no disponible'}`}</div>
                        {it.c.clam && <div className="sub">{it.c.clam.estado === 'limpio' ? 'ClamAV: sin amenazas.' : it.c.clam.estado === 'amenaza' ? 'ClamAV: amenazas encontradas.' : `ClamAV: ${it.c.clam.detalle ?? 'no disponible'}`}</div>}
                        <div className="sub">Carpeta completa: no se consulta VirusTotal ni la firma archivo por archivo.</div>
                        <div className="fila-acciones">
                          <button className="boton" onClick={() => repetir(it)}>Volver a revisar</button>
                          <button className="boton principal-b" onClick={() => void elegirCarpeta()}>Revisar otra carpeta</button>
                        </div>
                      </>
                    )}
                    {it.r && (
                      <>
                        <Veredicto tono={it.r.tono} titulo={it.r.titulo}>{it.r.detalle}</Veredicto>
                        <div className="sub">{textoDefender(it.r)}</div>
                        {it.r.clam && <div className="sub">{textoClam(it.r)}</div>}
                        <div className="sub">{textoVT(it.r.vt)}</div>
                        {it.r.firma && <div className="sub">{textoFirma(it.r)}</div>}
                        <div className="sub">{textoVersion(it.r)}</div>
                        <div className="sub num">{tamano(it.r.tam)}</div>
                        <div className="hash">SHA-256 {it.r.sha256}</div>
                        <div className="fila-acciones">
                          <button className="boton" onClick={() => void window.antivirus.abrirVT(it.r!.sha256)}>Ver en VirusTotal</button>
                          <button className="boton" onClick={() => void navigator.clipboard.writeText(it.r!.sha256).then(() => setPie('Huella copiada.')).catch(() => undefined)}>Copiar huella</button>
                          <button className="boton" onClick={() => repetir(it)}>Volver a revisar</button>
                          <button className="boton principal-b" onClick={() => void elegir()}>Revisar otro archivo</button>
                        </div>
                      </>
                    )}
                  </div>
                ))}
              </div>
              <p className="nota-vacia">Ningún análisis garantiza que un archivo esté limpio: «sin amenazas conocidas» solo dice que hoy nadie lo ha marcado.</p>
            </section>
  )

  return (
    <div className="app simple">
      <div className="barra-titulo"><img src={logo} alt="" /><b>Nitrit0 Antivirus</b></div>
      <main className="principal">
        <ErrorBoundary>
          <div className="pagina">
            <PageHeader titulo="Revisar archivos" subtitulo="Comprueba un archivo con Microsoft Defender y con VirusTotal antes de abrirlo, o una carpeta entera con Defender y ClamAV." comoUsar={['Suelta aquí archivos o carpetas, o pulsa un botón.', 'Espera el veredicto.', 'Si dice «no lo abras», no lo abras.']} />
            {items.length > 0 && resultados}
            <section className="bloque" aria-label="Motores de análisis">
              <h2>Motores de análisis</h2>
              <div className="fila-simple">
                <div>Microsoft Defender
                  <div className={motores?.defender && motores.defender.activo && motores.defender.dias <= 3 ? 'sub-linea' : 'aviso-txt'}>
                    {!motores ? 'Leyendo…' : !motores.defender ? 'No se pudo leer su estado (¿lo gestiona otro antivirus?).' : !motores.defender.activo ? 'Está desactivado.' : `Firmas del ${motores.defender.fecha} (versión ${motores.defender.version})${motores.defender.dias > 3 ? `: ${motores.defender.dias} días sin actualizar, conviene actualizar` : ': al día'}.`}
                  </div>
                </div>
                <button className="boton" disabled={!!actualizando || items.some((x) => x.estado === 'analizando' || x.estado === 'espera')} onClick={() => void actualizar('defender')}>{actualizando === 'defender' ? 'Actualizando…' : 'Actualizar Defender'}</button>
              </div>
              {motores?.hayClam && (
                <div className="fila-simple">
                  <div>ClamAV
                    <div className={motores.clam && motores.clam.dias <= 7 ? 'sub-linea' : 'aviso-txt'}>
                      {!motores.clam ? 'No se encuentra su base de firmas.' : `Base del ${motores.clam.fecha}${motores.clam.dias > 7 ? `: ${motores.clam.dias} días sin actualizar, conviene actualizar` : ': al día'}.`}
                    </div>
                  </div>
                  <button className="boton" disabled={!!actualizando || items.some((x) => x.estado === 'analizando' || x.estado === 'espera')} onClick={() => void actualizar('clam')}>{actualizando === 'clam' ? 'Actualizando…' : 'Actualizar ClamAV'}</button>
                </div>
              )}
              {actualizando && <div><button className="boton" onClick={() => void window.antivirus.cancelar()}>Cancelar actualización</button></div>}
              <p className="nota-vacia">Actualizar necesita Internet. Defender se actualiza solo con Windows Update; aquí puedes forzarlo.</p>
            </section>
            {!defender && <p className="aviso-txt" role="alert">No se encuentra Microsoft Defender en este equipo: solo se podrá consultar VirusTotal.</p>}
            <div className={`zona-suelta ${encima ? 'encima' : ''}`} onDragOver={(e) => { e.preventDefault(); setEncima(true) }} onDragLeave={(e) => { if (!e.currentTarget.contains(e.relatedTarget as Node)) setEncima(false) }} onDrop={soltar}>
              <b>Suelta aquí archivos o carpetas</b>
              <span>No se suben a ningún sitio: VirusTotal solo recibe la huella (SHA-256) de cada archivo. Las carpetas se revisan enteras con Defender y ClamAV.</span>
              <div className="fila-acciones">
                <button className="boton principal-b" onClick={() => void elegir()}>Elegir archivos…</button>
                <button className="boton principal-b" onClick={() => void elegirCarpeta()}>Elegir carpeta…</button>
              </div>
            </div>
            <section className="bloque" aria-label="VirusTotal">
              <h2>VirusTotal {clave ? '· clave guardada' : '· sin clave'}</h2>
              <div className="campo-clave">
                <input type="password" value={campo} onChange={(e) => setCampo(e.target.value)} placeholder={clave ? 'Pega otra clave para cambiarla (vacío y Guardar la borra)' : 'Pega aquí tu clave de la API de VirusTotal'} aria-label="Clave de la API de VirusTotal" autoComplete="off" spellCheck={false} />
                <button className="boton" onClick={() => void guardar()} disabled={!campo && !clave}>Guardar</button>
                <button className="boton" onClick={() => void window.antivirus.abrirClaveVT()}>Sacar mi clave en virustotal.com</button>
              </div>
              <p className="nota-vacia">La clave es gratuita: el botón abre virustotal.com/gui/my-apikey, inicias sesión (o creas la cuenta gratis) y copias la «API key». Se guarda en la carpeta Datos del kit, no en el equipo del cliente. Límite gratuito: 4 consultas por minuto.</p>
            </section>
            {items.length === 0 && resultados}
          </div>
        </ErrorBoundary>
      </main>
      <div className="pie-estado" role="status" aria-live="polite"><span>{pie}</span></div>
    </div>
  )
}
