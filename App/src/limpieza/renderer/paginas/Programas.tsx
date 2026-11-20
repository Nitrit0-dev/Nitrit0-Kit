import { useMemo, useState } from 'react'
import { Search } from 'lucide-react'
import { Confirmar, Medidor, PageHeader, Vacio } from '../../../renderer/src/componentes/Basicos'

export interface Programa { nombre: string; editor: string; version: string; mb: number; fecha: string; ambito: string; ultimoUso: string }
type Orden = 'nombre' | 'tamano' | 'uso'

const fechaCorta = (f: string) => (/^\d{8}$/.test(f) ? `${f.slice(6, 8)}/${f.slice(4, 6)}/${f.slice(0, 4)}` : '')
const tamMb = (mb: number) => (mb >= 1024 ? `${(mb / 1024).toFixed(1)} GB` : mb > 0 ? `${mb} MB` : '')
const fechaIso = (f: string) => (f ? `${f.slice(8, 10)}/${f.slice(5, 7)}/${f.slice(0, 4)}` : '')
const SEIS_MESES = 183 * 86400000
const clave = (p: Programa) => `${p.nombre}|${p.version}|${p.ambito}`

export default function Programas({ lista, admin, ocupado, marcha, salida, alRecargar, alDesinstalar }: {
  lista: Programa[] | null; admin: boolean; ocupado: boolean; marcha: boolean; salida: string[]; alRecargar: () => void; alDesinstalar: (l: Programa[]) => void
}) {
  const [consulta, setConsulta] = useState('')
  const [orden, setOrden] = useState<Orden>('nombre')
  const [sinUsar, setSinUsar] = useState(false)
  const [grandes, setGrandes] = useState(false)
  const [marcados, setMarcados] = useState<Set<string>>(new Set())
  const [confirmar, setConfirmar] = useState(false)
  const visibles = useMemo(() => {
    const q = consulta.trim().toLowerCase()
    const limite = Date.now() - SEIS_MESES
    // «Sin usar»: solo cuenta lo que tiene fecha y es anterior a seis meses; sin datos no se da por no usado
    const l = (lista ?? []).filter((p) => (!q || p.nombre.toLowerCase().includes(q) || p.editor.toLowerCase().includes(q)) && (!sinUsar || (p.ultimoUso !== '' && new Date(p.ultimoUso).getTime() < limite)) && (!grandes || p.mb >= 500))
    // Último uso: el más antiguo primero y los que no tienen fecha al final
    return l.sort((a, b) => orden === 'tamano' ? b.mb - a.mb : orden === 'uso' ? (a.ultimoUso || '9999').localeCompare(b.ultimoUso || '9999') : a.nombre.localeCompare(b.nombre, 'es'))
  }, [lista, consulta, orden, sinUsar, grandes])
  const conFecha = (lista ?? []).filter((p) => p.ultimoUso).length
  const nSinUsar = (lista ?? []).filter((p) => p.ultimoUso && new Date(p.ultimoUso).getTime() < Date.now() - SEIS_MESES).length
  // Lo marcado se conserva aunque la búsqueda lo esconda; solo cuenta lo que sigue instalado
  const elegidos = (lista ?? []).filter((p) => marcados.has(clave(p)))
  const mbTotal = elegidos.reduce((s, p) => s + p.mb, 0)
  const marcar = (p: Programa, on: boolean) => setMarcados((s) => { const n = new Set(s); if (on) n.add(clave(p)); else n.delete(clave(p)); return n })
  // El avance sale de las líneas del propio script: «Programa n de m: nombre», «[i/N] …» al mover los restos
  const ultimaProg = [...salida].reverse().find((l) => /^Programa \d+ de \d+:/.test(l))
  const m = ultimaProg ? /^Programa (\d+) de (\d+)/.exec(ultimaProg) : null
  const hecho = m ? Number(m[1]) - 1 : 0
  const total = m ? Number(m[2]) : 0
  const fase = salida.some((l) => l.includes('Moviendo')) ? 'Eliminando los restos' : salida.some((l) => l.includes('Quedan')) ? 'Esperando que elijas los restos a borrar en la ventana que se ha abierto' : ultimaProg ? ultimaProg : 'Preparando…'
  const chip = (id: Orden, texto: string) => <button className="chip" aria-pressed={orden === id} onClick={() => setOrden(id)}>{texto}</button>

  return (
    <div className="pagina">
      <PageHeader titulo="Programas" subtitulo="Marca uno o varios y desinstálalos de una vez. Cada uno se quita con su desinstalador y después se buscan sus restos; lo que se borra va a una cuarentena que se puede restaurar."
        acciones={<>
          <button className="boton" disabled={ocupado} onClick={alRecargar}>Actualizar la lista</button>
          <button className="boton principal-b" disabled={ocupado || !elegidos.length} onClick={() => setConfirmar(true)}>{elegidos.length ? `Desinstalar a fondo (${elegidos.length})` : 'Desinstalar a fondo'}</button>
        </>} />
      {(marcha || salida.length > 0) && (
        <div className="resumen-barra" role="status" style={{ display: 'block' }}>
          <div className="grande">{marcha ? 'Desinstalando…' : 'Terminado'}{total > 0 && <span className="sub num"> · {marcha ? `programa ${Math.min(hecho + 1, total)} de ${total}` : `${total} programa(s)`}</span>}</div>
          <div className="sub" style={{ margin: '4px 0 8px' }}>{marcha ? fase : 'Revisa abajo cómo ha ido. Lo borrado está en la cuarentena y se puede restaurar.'}</div>
          {marcha && (total > 0 ? <Medidor valor={hecho} max={total} etiqueta="Programas desinstalados" rol="progressbar" /> : <Medidor valor={0} etiqueta="Desinstalando" rol="progressbar" indeterminado />)}
          <div className="consola" role="log" aria-label="Avance de la desinstalación" style={{ marginTop: 10, maxHeight: 220, overflowY: 'auto' }}>{salida.join('\n')}</div>
        </div>
      )}
      <div className="filtros" role="group" aria-label="Buscar y ordenar">
        <label className="buscador" style={{ minWidth: 260 }}><Search size={16} strokeWidth={1.75} aria-hidden="true" /><input value={consulta} onChange={(e) => setConsulta(e.target.value)} placeholder="Buscar por nombre o editor" aria-label="Buscar programas" /></label>
        {chip('nombre', 'Por nombre')}{chip('tamano', 'Los que más ocupan')}{chip('uso', 'Último uso')}
        <button className="chip" aria-pressed={sinUsar} disabled={!conFecha} onClick={() => setSinUsar(!sinUsar)}>Sin usar en 6 meses<span className="cuenta num">{nSinUsar}</span></button>
        <button className="chip" aria-pressed={grandes} onClick={() => setGrandes(!grandes)}>Más de 500 MB</button>
        {elegidos.length > 0 && <button className="chip" disabled={ocupado} onClick={() => setMarcados(new Set())}>Quitar la selección</button>}
      </div>
      {lista !== null && lista.length > 0 && (admin
        ? <p className="sub-linea">{conFecha ? `La fecha de último uso sale de los registros de Windows (BAM y Prefetch) y es orientativa: ${conFecha} de ${lista.length} programas tienen dato. Que un programa no tenga fecha no significa que no se use.` : 'Windows no guarda fechas de uso de ninguno de estos programas.'}</p>
        : <p className="aviso-txt">Abre la app como administrador para ver cuándo se usó cada programa por última vez.</p>)}
      {lista === null || (ocupado && !lista.length) ? <p className="vacio" role="status">Leyendo los programas instalados…</p>
        : !visibles.length ? <Vacio>Ningún programa coincide con la búsqueda.</Vacio>
        : <section className="grupo" aria-label="Programas instalados">
            <h2>{visibles.length} programas{elegidos.length > 0 && <span> · {elegidos.length} marcados{mbTotal > 0 ? `, unos ${tamMb(mbTotal)}` : ''}</span>}</h2>
            {visibles.map((p) => (
              <label key={clave(p)} className="fila-c">
                <input type="checkbox" checked={marcados.has(clave(p))} disabled={ocupado} onChange={(e) => marcar(p, e.target.checked)} />
                <div>
                  <h3>{p.nombre}</h3>
                  <p>{[p.editor, p.version && `v${p.version}`, fechaCorta(p.fecha) && `instalado ${fechaCorta(p.fecha)}`].filter(Boolean).join(' · ')}</p>
                  <div className="nota">{p.ultimoUso ? `Último uso: ${fechaIso(p.ultimoUso)}` : admin ? 'Sin datos de uso' : ''}</div>
                </div>
                <div className={`tam ${p.mb ? '' : 'cero'}`}>{tamMb(p.mb) || '—'}</div>
              </label>
            ))}
          </section>}
      <Confirmar abierto={confirmar} titulo={elegidos.length === 1 ? 'Desinstalar a fondo' : `Desinstalar ${elegidos.length} programas`}
        texto={`Se desinstalarán uno tras otro y se buscarán sus restos: ${elegidos.slice(0, 6).map((p) => p.nombre).join(', ')}${elegidos.length > 6 ? ` y ${elegidos.length - 6} más` : ''}.`}
        detalle="Se desinstalan uno tras otro (en silencio cuando se puede) y al final se abre UNA ventana con todos los restos de todos los programas, con «Marcar todo». Se crea un punto de restauración antes de empezar." textoOk="Continuar" textoNo="Cancelar"
        alAceptar={() => { setConfirmar(false); const l = elegidos; setMarcados(new Set()); alDesinstalar(l) }} alCancelar={() => setConfirmar(false)} />
    </div>
  )
}
