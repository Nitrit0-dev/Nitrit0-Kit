import { useEffect, useRef, type ReactNode } from 'react'
import { Gamepad2, Leaf, Scale } from 'lucide-react'
import type { IdPerfil } from '../tipos'

const PERFILES: { id: IdPerfil; titulo: string; texto: string; icono: ReactNode }[] = [
  { id: 'ahorro', titulo: 'Ahorro', texto: 'Poco consumo: internet y poco más.', icono: <Leaf size={22} strokeWidth={1.75} /> },
  { id: 'equilibrado', titulo: 'Equilibrado', texto: 'Lo normal de Windows, sin extremos.', icono: <Scale size={22} strokeWidth={1.75} /> },
  { id: 'juego', titulo: 'Juego', texto: 'Máximo rendimiento para jugar.', icono: <Gamepad2 size={22} strokeWidth={1.75} /> }
]

/** Los tres perfiles como tarjetas; el activo queda marcado. Cada uno crea un punto de restauración y se puede deshacer con «Revertir» del Optimizador personal. */
export function PerfilTarjetas({ actual, ocupado, alElegir }: { actual: IdPerfil | null; ocupado: boolean; alElegir: (id: IdPerfil) => void }) {
  return (
    <div className="tarjetas" role="group" aria-label="Modo del equipo">
      {PERFILES.map((p) => (
        <button key={p.id} className="tarjeta" aria-pressed={actual === p.id} disabled={ocupado} onClick={() => alElegir(p.id)}>
          <span className="tarjeta-ficha" aria-hidden="true">{p.icono}</span>
          <b>{p.titulo}{actual === p.id ? ' · activo' : ''}</b>
          <span className="tarjeta-texto">{p.texto}</span>
        </button>
      ))}
    </div>
  )
}

/** Pregunta de la primera vez: para qué se va a usar el equipo. Se puede dejar para más tarde y cambiar cuando se quiera desde Inicio o el icono junto al reloj. */
export function PerfilDialogo({ abierto, alElegir, alCerrar }: { abierto: boolean; alElegir: (id: IdPerfil) => void; alCerrar: () => void }) {
  const ref = useRef<HTMLDialogElement>(null)
  useEffect(() => {
    const d = ref.current
    if (!d) return
    if (abierto && !d.open) { d.showModal(); d.querySelector<HTMLButtonElement>('.pie-dialogo button')?.focus() }   // el foco inicial en «Ahora no»: un Intro sin querer no debe aplicar un modo
    if (!abierto && d.open) d.close()
  }, [abierto])
  return (
    <dialog ref={ref} className="ancho" onCancel={(e) => { e.preventDefault(); alCerrar() }} aria-labelledby="dlg-perfil">
      <h2 id="dlg-perfil">¿Para qué vas a usar este equipo?</h2>
      <p>Puedes cambiarlo cuando quieras desde Inicio o desde el icono junto al reloj.</p>
      <div className="perfil-lista">
        {PERFILES.map((p) => (
          <button key={p.id} className="tarjeta" onClick={() => alElegir(p.id)}>
            <span className="tarjeta-ficha" aria-hidden="true">{p.icono}</span>
            <b>{p.titulo}</b>
            <span className="tarjeta-texto">{p.texto}</span>
          </button>
        ))}
      </div>
      <div className="pie-dialogo"><button className="boton" onClick={alCerrar}>Ahora no</button></div>
    </dialog>
  )
}
