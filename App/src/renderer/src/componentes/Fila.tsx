import { AppWindow, FolderOpen, SquareTerminal, Star, Wrench } from 'lucide-react'
import { usaEjecutor, verbo, type Elemento } from '../tipos'
import { Sello } from './Basicos'

// Sin icono propio del programa, el glifo dice qué clase de herramienta es.
const glifo = { script: Wrench, cmd: SquareTerminal, accion: FolderOpen, run: AppWindow, html: AppWindow, uri: AppWindow, exe: AppWindow, informe: Wrench } as const

export function Fila({ e, favorita, alFavorita, alLanzar, ocupado }: {
  e: Elemento; favorita: boolean; alFavorita: () => void; alLanzar: () => void; ocupado: boolean
}) {
  const Glifo = e.tipo === 'accion' && !e.accion?.startsWith('Abrir') ? SquareTerminal : glifo[e.tipo]
  const motivo = !e.soportado ? 'Solo en el lanzador clásico' : !e.disponible ? 'No está en la carpeta Apps' : null
  return (
    <div className="fila-h">
      <div className="icono-h" aria-hidden="true">
        {e.icono ? <img src={e.icono} alt="" /> : <Glifo size={19} strokeWidth={1.75} />}
      </div>
      <div>
        <h3>{e.titulo}{e.peligro && !motivo && <Sello tipo="error" ayuda="Cambia cosas importantes: pide confirmación antes de abrirse.">Avanzado</Sello>}</h3>
        <p title={e.descripcion}>{e.descripcion}</p>
        {e.peligro && !motivo && <div className="nota aviso">Pide confirmación antes de abrirse</div>}
      </div>
      <button className="fav" aria-pressed={favorita} aria-label={favorita ? `Quitar ${e.titulo} de favoritas` : `Marcar ${e.titulo} como favorita`} onClick={alFavorita}>
        <Star size={17} strokeWidth={1.75} fill={favorita ? 'currentColor' : 'none'} />
      </button>
      {motivo
        ? <span className="solo-lanzador">{motivo}</span>
        : <button className="boton" disabled={ocupado && usaEjecutor(e)} onClick={alLanzar} aria-label={`${verbo(e)} ${e.titulo}`}>{verbo(e)}</button>}
    </div>
  )
}
