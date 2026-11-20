import { Camera, ChevronRight, CircuitBoard, Cpu, Gamepad2, Keyboard, Monitor, Mic, Mouse, Wrench } from 'lucide-react'
import { PageHeader } from '../componentes/Basicos'
import type { Elemento } from '../tipos'

const ICONO = [[/pantalla/i, Monitor], [/teclado/i, Keyboard], [/webcam/i, Camera], [/audio|micr/i, Mic], [/rat[oó]n|t[aá]ctil/i, Mouse], [/mando/i, Gamepad2], [/procesador/i, Cpu], [/gpu|v[ií]deo/i, CircuitBoard]] as const

/** Pruebas del equipo (pantalla, teclado, ratón, webcam, audio): se abren dentro de la app. */
export default function Pruebas({ elementos, alAbrir, alHerramientas }: { elementos: Elemento[]; alAbrir: (e: Elemento) => void; alHerramientas: () => void }) {
  const pruebas = elementos.filter((e) => e.tipo === 'html' && e.soportado && e.disponible)
  return (
    <div className="pagina">
      <PageHeader titulo="Pruebas del equipo" subtitulo="Comprueba que la pantalla, el teclado, el ratón, la webcam, el audio, el mando, el procesador y la placa de vídeo funcionan. Se abren aquí dentro y no cambian nada del equipo." />
      <div className="tarjetas" role="group" aria-label="Pruebas">
        {pruebas.map((e) => {
          const Icono = ICONO.find(([r]) => r.test(e.titulo))?.[1] ?? Wrench
          return (
            <button key={e.id} className="tarjeta" onClick={() => alAbrir(e)}>
              <span className="tarjeta-ficha" aria-hidden="true"><Icono size={20} strokeWidth={1.75} /></span>
              <b>{e.titulo}</b>
              <span className="tarjeta-texto">{e.descripcion}</span>
              <ChevronRight className="tarjeta-flecha" size={18} strokeWidth={1.75} aria-hidden="true" />
            </button>
          )
        })}
      </div>
      {pruebas.length === 0 && <p className="nota-vacia">Este pack no lleva las pruebas.</p>}
      <div><button className="boton" onClick={alHerramientas}>Más comprobaciones en Herramientas</button></div>
    </div>
  )
}
