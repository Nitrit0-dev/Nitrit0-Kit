import { useEffect, useRef, useState } from 'react'
import { PageHeader } from '../componentes/Basicos'
import type { Ejecucion as Marcha, EnCola } from '../tipos'

const reloj = (s: number) => `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`

export default function Ejecucion({ e, alCancelar, alVolver, alMensaje, siguiente, cola = [], alQuitarDeCola, alVaciarCola, detallesAbiertos = false }: { detallesAbiertos?: boolean; e: Marcha; alCancelar: () => void; alVolver: () => void; alMensaje: (m: string) => void; siguiente?: { texto: string; accion: () => void } | null; cola?: EnCola[]; alQuitarDeCola?: (id: string) => void; alVaciarCola?: () => void }) {
  const [seg, setSeg] = useState(() => Math.round((Date.now() - e.t0) / 1000))
  const [pestana, setPestana] = useState<'informe' | 'salida'>('salida')
  const caja = useRef<HTMLDivElement>(null)
  const pegado = useRef(true)

  useEffect(() => {
    if (e.fin) return
    const id = setInterval(() => setSeg(Math.round((Date.now() - e.t0) / 1000)), 1000)
    return () => clearInterval(id)
  }, [e.fin, e.t0])

  // Cuando llega un informe se enseña enseguida; la salida sigue a un clic.
  const hayInforme = !!e.informe
  useEffect(() => { if (hayInforme) setPestana('informe') }, [hayInforme])

  // Sigue la salida salvo que la persona haya subido a leer.
  useEffect(() => { const c = caja.current; if (c && pegado.current) c.scrollTop = c.scrollHeight }, [e.lineas, pestana])

  const [copiado, setCopiado] = useState(false)
  const copiar = async () => {
    try { await navigator.clipboard.writeText(e.lineas.join('\n')); setCopiado(true); setTimeout(() => setCopiado(false), 2500) } catch { alMensaje('No se pudo copiar al portapapeles.') }
  }

  const estado = e.fin
    ? `${e.fin.motivo} · ${reloj(e.fin.seg)}`
    : `En marcha · ${reloj(seg)} de máximo ${Math.round(e.limite / 60)} min`

  // Barra de avance: con los pasos que informa el script es exacta; sin ellos se mueve sin porcentaje (indeterminada) y debajo va la última línea de la salida.
  // El registro completo queda en «Ver detalles» (abierto de entrada solo en el modo técnico).
  const [detalle, setDetalle] = useState(detallesAbiertos)
  const pr = e.progreso
  const conPasos = !!pr && pr.total > 0
  const pct = e.fin ? (e.fin.correcto || !conPasos ? 100 : Math.round((100 * pr!.actual) / pr!.total)) : conPasos ? Math.min(100, Math.round((100 * pr!.actual) / pr!.total)) : null
  const tono = e.fin ? (e.fin.cancelado ? 'neutro' : e.fin.correcto ? 'ok' : 'mal') : ''
  const ultima = e.fin ? '' : ([...e.lineas].reverse().find((l) => l.trim() && !/^[\s=\-─]+$/.test(l)) ?? '').trim()
  const titularBarra = e.fin ? e.fin.motivo : pr?.texto || 'Trabajando…'

  return (
    <div className="pagina">
      <PageHeader
        titulo={e.titulo}
        acciones={e.fin
          ? <>
              <button className="boton" onClick={() => void copiar()}>{copiado ? 'Copiado' : 'Copiar salida'}</button>
              {e.informe && <button className="boton" onClick={() => void window.kit.abrirInforme(e.informe!.ruta).then((r: { mensaje: string }) => alMensaje(r.mensaje)).catch(() => alMensaje('No se pudo abrir el informe.'))}>Abrir en el navegador</button>}
              {e.informe && <button className="boton" onClick={() => void window.kit.informePdf(e.informe!.ruta).then((r: { mensaje: string }) => alMensaje(r.mensaje)).catch(() => alMensaje('No se pudo crear el PDF.'))}>Guardar como PDF</button>}
              {e.fin.registro && <button className="boton" onClick={() => void window.kit.abrirRegistro(e.fin!.registro!).then((r: { mensaje: string }) => alMensaje(r.mensaje)).catch(() => alMensaje('No se pudo abrir el registro.'))}>Abrir registro</button>}
              {siguiente && e.fin.correcto && <button className="boton principal-b" onClick={siguiente.accion}>{siguiente.texto}</button>}
              <button className={siguiente && e.fin.correcto ? 'boton' : 'boton principal-b'} onClick={alVolver}>Volver al kit</button>
            </>
          : <>
              <button className="boton" onClick={() => void copiar()}>{copiado ? 'Copiado' : 'Copiar salida'}</button>
              <button className="boton peligro-b" onClick={alCancelar}>Cancelar ejecución</button>
            </>}
      />
      {/* El reloj cambia cada segundo: se oculta a los lectores de pantalla y solo se anuncia el inicio y el final */}
      <div className={`estado-ejec ${e.fin ? (e.fin.cancelado ? 'neutro' : e.fin.correcto ? 'ok' : 'mal') : ''}`} aria-hidden={!e.fin}>{estado}</div>
      <div className="solo-lector" role="status">{e.fin ? estado : `${e.titulo} en marcha`}</div>
      {cola.length > 0 && (
        <div className="nota-opcion" role="region" aria-label="Cola de ejecución">
          <strong>En cola ({cola.length}):</strong> empiezan una tras otra al terminar{e.fin ? '; la siguiente arranca en unos segundos' : ' esta'}. Si cancelas, la cola se vacía.
          <ol>
            {cola.map((c) => <li key={c.id}>{c.titulo}{alQuitarDeCola && <> · <button className="enlace" onClick={() => alQuitarDeCola(c.id)} aria-label={`Quitar ${c.titulo} de la cola`}>Quitar</button></>}</li>)}
          </ol>
          {alVaciarCola && <button className="boton" onClick={alVaciarCola}>Vaciar la cola</button>}
        </div>
      )}
      {e.informe && (
        <div className="filtros" role="group" aria-label="Qué ver">
          <button className="chip" aria-pressed={pestana === 'informe'} onClick={() => setPestana('informe')}>Informe</button>
          <button className="chip" aria-pressed={pestana === 'salida'} onClick={() => setPestana('salida')}>Salida del script</button>
        </div>
      )}
      {!(e.informe && pestana === 'informe') && (
        <div className="progreso-bloque">
          <div className="progreso-texto">{titularBarra}{conPasos && !e.fin ? ` · ${Math.min(pr!.actual + 1, pr!.total)} de ${pr!.total}` : ''}</div>
          <div className={`progreso ${tono}`} role="progressbar" aria-label={`Avance de ${e.titulo}`} aria-valuemin={0} aria-valuemax={100} aria-valuenow={pct ?? undefined}>
            <div className={`progreso-relleno${pct === null ? ' indeterminado' : ''}`} style={pct !== null ? { width: `${pct}%` } : undefined} />
          </div>
          {ultima && <div className="progreso-ultima" aria-hidden="true">{ultima}</div>}
          {!e.lineas.length && !e.fin && seg >= 6 && <div className="progreso-ultima">Arrancando… En un equipo nuevo o con el antivirus analizando puede tardar la primera vez. Si se abre una ventana para elegir, búscala en la barra de tareas. No cierres esta ventana.</div>}
          <button className="enlace" aria-expanded={detalle} onClick={() => setDetalle((d) => !d)}>{detalle ? 'Ocultar detalles' : 'Ver detalles'}</button>
        </div>
      )}
      {e.informe && pestana === 'informe'
        // Sin scripts (sandbox sin allow-scripts): el informe es un documento, no una página con vida propia.
        ? <iframe className="hoja" title={`Informe de ${e.titulo}`} sandbox="" srcDoc={e.informe.html} />
        : detalle && <div className="consola" ref={caja} tabIndex={0} role="log" aria-live="off" aria-label={`Salida de ${e.titulo}`}
            onScroll={(ev) => { const c = ev.currentTarget; pegado.current = c.scrollHeight - c.scrollTop - c.clientHeight < 40 }}>
            {e.lineas.length ? e.lineas.join('\n') : seg >= 6 ? 'Arrancando… En un equipo nuevo, actualizándose o con el antivirus analizando puede tardar varios minutos la primera vez. Si la herramienta abre una ventana para elegir opciones, búscala en la barra de tareas: puede haber quedado detrás. No cierres esta ventana.' : 'Esperando la primera línea…'}
          </div>}
    </div>
  )
}
