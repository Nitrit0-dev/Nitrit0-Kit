import { useEffect, useId, useRef, useState, type ReactNode } from 'react'
import { Check, ChevronDown } from 'lucide-react'

/**
 * Desplegable de una sola elección (como el «Elige tu modo» de Winhance), con teclado: Enter, Espacio o ↓ abren; ↑↓ mueven; Enter elige; Escape cierra.
 * Se usa donde hay tres o más opciones; con dos opciones es un interruptor.
 */
export default function Desplegable({ etiqueta, valor, opciones, alElegir, deshabilitado, icono, textoBoton, lateral }: {
  etiqueta: string; valor: string; opciones: { k: string; t: string }[]; alElegir: (k: string) => void; deshabilitado?: boolean
  icono?: ReactNode; textoBoton?: string; lateral?: boolean   // lateral: ocupa todo el ancho como un botón del menú y se abre hacia arriba
}) {
  const [abierto, setAbierto] = useState(false)
  const [activa, setActiva] = useState(0)
  const caja = useRef<HTMLDivElement>(null)
  const boton = useRef<HTMLButtonElement>(null)
  const id = useId()
  const actual = opciones.find((o) => o.k === valor)
  const abrir = () => { setActiva(Math.max(0, opciones.findIndex((o) => o.k === valor))); setAbierto(true) }
  const cerrar = () => { setAbierto(false); boton.current?.focus() }
  const elegir = (k: string) => { setAbierto(false); boton.current?.focus(); if (k !== valor) alElegir(k) }

  useEffect(() => {
    if (!abierto) return
    const fuera = (e: MouseEvent) => { if (caja.current && !caja.current.contains(e.target as Node)) setAbierto(false) }
    document.addEventListener('mousedown', fuera)
    return () => document.removeEventListener('mousedown', fuera)
  }, [abierto])
  useEffect(() => { if (abierto) document.getElementById(`${id}-${activa}`)?.focus() }, [abierto, activa, id])

  const tecla = (e: React.KeyboardEvent) => {
    if (!abierto) { if (['Enter', ' ', 'ArrowDown'].includes(e.key)) { e.preventDefault(); abrir() } return }
    if (e.key === 'Escape') { e.preventDefault(); cerrar() }
    else if (e.key === 'ArrowDown') { e.preventDefault(); setActiva((a) => (a + 1) % opciones.length) }
    else if (e.key === 'ArrowUp') { e.preventDefault(); setActiva((a) => (a - 1 + opciones.length) % opciones.length) }
    else if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); elegir(opciones[activa].k) }
    else if (e.key === 'Tab') setAbierto(false)
  }

  return (
    <div className={`desplegable${lateral ? ' en-menu' : ''}`} ref={caja} onKeyDown={tecla}>
      <button ref={boton} type="button" disabled={deshabilitado} aria-haspopup="listbox" aria-expanded={abierto} aria-label={`${etiqueta}: ${actual?.t ?? 'otro valor'}`} onClick={() => (abierto ? setAbierto(false) : abrir())}>
        {icono}<span>{textoBoton ?? actual?.t ?? 'Otro valor'}</span><ChevronDown size={16} strokeWidth={1.75} aria-hidden="true" />
      </button>
      {abierto && (
        <div className="lista-desplegable" role="listbox" aria-label={etiqueta}>
          {opciones.map((o, i) => (
            <div key={o.k} id={`${id}-${i}`} role="option" tabIndex={-1} aria-selected={o.k === valor} onClick={() => elegir(o.k)} onMouseEnter={() => setActiva(i)}>
              {o.t}<Check size={15} strokeWidth={1.75} className="marca" aria-hidden="true" />
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
