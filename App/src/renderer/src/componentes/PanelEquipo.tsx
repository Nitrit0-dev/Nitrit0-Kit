import { useEffect, useRef, useState } from 'react'
import { ChevronUp } from 'lucide-react'
import { Medidor } from './Basicos'
import { diasEncendido, leerResumen, numero } from '../equipo'
import type { Resumen, Tono, Vivo } from '../tipos'

const tono = (pct: number): Tono | undefined => (pct > 95 ? 'error' : pct > 90 ? 'aviso' : undefined)

/**
 * «Este equipo» en el lateral: cómo está ahora mismo la máquina, sin salir de la pantalla en la que estés.
 * La memoria se lee cada pocos segundos (barata); el resto (procesador, discos) sale de la lectura del equipo, que se pide al abrir.
 */
export default function PanelEquipo({ admin, alVerEstado }: { admin?: boolean; alVerEstado: () => void }) {
  const [abierto, setAbierto] = useState(false)
  const [v, setV] = useState<Vivo | null>(null)
  const [r, setR] = useState<Resumen | null>(null)
  const [fallo, setFallo] = useState(false)
  const [pos, setPos] = useState<{ left: number; bottom: number } | null>(null)
  const caja = useRef<HTMLDivElement>(null)
  const panel = useRef<HTMLDivElement>(null)
  const boton = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    const t = () => { void window.kit.vivo().then(setV).catch(() => undefined) }
    t()
    const id = setInterval(t, 3000)
    return () => clearInterval(id)
  }, [])

  useEffect(() => {
    if (!abierto) return
    setFallo(false)
    // El lateral recorta lo que sobresale: el panel va en posición fija, pegado encima del botón
    const b = boton.current?.getBoundingClientRect()
    if (b) setPos({ left: b.left, bottom: window.innerHeight - b.top + 6 })
    leerResumen().then(setR).catch(() => setFallo(true))
    requestAnimationFrame(() => panel.current?.focus())   // el foco entra en el panel (Escape lo cierra y devuelve el foco al botón)
    const fuera = (e: MouseEvent) => { if (caja.current && !caja.current.contains(e.target as Node)) setAbierto(false) }
    const tecla = (e: KeyboardEvent) => { if (e.key === 'Escape') { setAbierto(false); boton.current?.focus() } }
    document.addEventListener('mousedown', fuera)
    document.addEventListener('keydown', tecla)
    return () => { document.removeEventListener('mousedown', fuera); document.removeEventListener('keydown', tecla) }
  }, [abierto])

  const ramPct = v && v.ramGb > 0 ? Math.round((v.ramUsadaGb / v.ramGb) * 100) : null
  const dias = r ? diasEncendido(r) : NaN
  // El disco del sistema primero; el resto, por letra
  const volumenes = (r?.volumenes ?? []).filter((x) => x.totalGb > 0).sort((a, b) => (a.letra.toUpperCase() === 'C' ? -1 : b.letra.toUpperCase() === 'C' ? 1 : a.letra.localeCompare(b.letra))).slice(0, 3)

  return (
    <div className="equipo-wrap" ref={caja}>
      <button ref={boton} className="nav" aria-haspopup="dialog" aria-expanded={abierto} onClick={() => setAbierto((a) => !a)}
        aria-label={`Este equipo${ramPct !== null ? `, memoria al ${ramPct} %` : ''}`}>
        <span className={`punto ${ramPct !== null && ramPct > 90 ? 'aviso' : ''}`} aria-hidden="true" />Este equipo
        {ramPct !== null && <span className="cuenta num" aria-hidden="true">{ramPct} %</span>}
        <ChevronUp size={14} strokeWidth={1.75} aria-hidden="true" className="equipo-chev" data-abierto={abierto} />
      </button>
      {abierto && (
        <div className="panel-equipo" ref={panel} tabIndex={-1} role="dialog" aria-label="Estado de este equipo" style={pos ? { left: pos.left, bottom: pos.bottom } : undefined}>
          <div className="pe-cab">
            <b>{r?.equipo || 'Este equipo'}</b>
            <span>{admin === undefined ? '' : admin ? 'Con permisos de administrador' : 'Sin permisos de administrador'}</span>
          </div>
          <div className="medida">
            <div><span>Procesador</span><span className="num">{v ? `${v.cpu} %` : '–'}</span></div>
            <Medidor etiqueta="Uso del procesador" valor={v?.cpu ?? 0} tono={tono(v?.cpu ?? 0)} />
            {r?.cpu && <small className="num">{r.cpu.replace(/\s*\d+-Core Processor/, '')} · {r.nucleos} núcleos / {r.hilos} hilos</small>}
          </div>
          <div className="medida">
            <div><span>Memoria</span><span className="num">{v ? `${numero(v.ramUsadaGb)} / ${numero(v.ramGb)} GB` : '–'}</span></div>
            <Medidor etiqueta="Memoria en uso" valor={v?.ramUsadaGb ?? 0} max={v?.ramGb || 1} tono={tono(ramPct ?? 0)} />
          </div>
          {volumenes.map((x) => {
            const usado = x.totalGb - x.libreGb, pct = (usado / x.totalGb) * 100
            return (
              <div className="medida" key={x.letra}>
                <div><span>Disco {x.letra}:</span><span className="num">{numero(x.libreGb, 0)} GB libres</span></div>
                <Medidor etiqueta={`Espacio usado en ${x.letra}:`} valor={usado} max={x.totalGb} tono={tono(pct)} />
              </div>
            )
          })}
          {!r && !fallo && <p className="nota-vacia">Leyendo procesador y discos, tarda unos segundos…</p>}
          {fallo && <p className="aviso-txt" role="alert">No se pudo leer el procesador ni los discos.</p>}
          {r?.bateria && <div className="medida"><div><span>Batería</span><span className="num">{Math.round(r.bateria.carga)} %</span></div></div>}
          {Number.isFinite(dias) && <p className="nota-vacia">Encendido desde hace {dias < 1 ? `${Math.max(1, Math.round(dias * 24))} h` : `${numero(dias)} días`}.</p>}
          <button className="enlace" onClick={() => { setAbierto(false); alVerEstado() }}>Ver el estado completo</button>
        </div>
      )}
    </div>
  )
}
