import { useCallback, useEffect, useState } from 'react'

type Sesion = Awaited<ReturnType<typeof window.kit.historialCambios>>[number]
const cuando = (iso: string) => { const d = new Date(iso); return Number.isNaN(d.getTime()) ? iso : d.toLocaleString('es-ES', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' }) }

/**
 * Lo que los scripts del kit han cambiado en este equipo, del más reciente al más antiguo. «Deshacer» devuelve esa tanda a como estaba
 * (la hace Deshacer_Cambios.ps1: punto de restauración y valores anteriores guardados). Lo ya deshecho se muestra apagado.
 */
export default function HistorialCambios({ ocupado = false }: { ocupado?: boolean }) {
  const [lista, setLista] = useState<Sesion[] | null>(null)
  const [aviso, setAviso] = useState('')
  const [errorLectura, setErrorLectura] = useState(false)
  const [deshaciendo, setDeshaciendo] = useState('')
  const leer = useCallback(() => { void window.kit.historialCambios().then((l) => { setErrorLectura(false); setLista(l) }).catch(() => { setErrorLectura(true); setLista((a) => a ?? []) }) }, [])
  useEffect(() => { leer() }, [leer])
  useEffect(() => window.kit.alTerminar(() => leer()), [leer])

  const deshacer = async (s: Sesion) => {
    if (deshaciendo) return   // doble clic: la segunda orden se ignora hasta que la primera se lance
    setAviso(''); setDeshaciendo(s.id)
    try { const r = await window.kit.deshacerCambio(s.id); if (!r.ok) setAviso(r.mensaje) } catch { setAviso('No se pudo iniciar «Deshacer cambios».') } finally { setDeshaciendo('') }
  }

  return (
    <section className="bloque" aria-label="Historial de cambios">
      <h2>Historial de cambios del kit</h2>
      <p className="nota-vacia">Lo que las herramientas del kit han cambiado en este equipo. Cada tanda se puede devolver a como estaba; antes de deshacer se crea un punto de restauración.</p>
      {aviso && <p className="aviso-txt" role="alert">{aviso}</p>}
      {lista === null && <p className="nota-vacia">Leyendo…</p>}
      {errorLectura && <p className="aviso-txt" role="alert">No se pudo leer el historial de cambios; lo que ves puede estar incompleto.</p>}
      {lista !== null && lista.length === 0 && !errorLectura && <p className="nota-vacia">Todavía no hay cambios registrados en este equipo.</p>}
      {(lista ?? []).map((s) => (
        <div className="fila-simple" key={s.id}>
          <div>
            <div>{s.nombre.replace(/_/g, ' ')}</div>
            <div className="sub-linea">{cuando(s.fecha)} · {s.cambios} cambio{s.cambios === 1 ? '' : 's'}{s.deshecho ? ' · ya deshecho' : ''}</div>
          </div>
          {s.deshecho ? <span className="sub-linea">Deshecho</span> : <button className="boton" disabled={ocupado || deshaciendo !== ''} onClick={() => void deshacer(s)}>Deshacer</button>}
        </div>
      ))}
    </section>
  )
}
