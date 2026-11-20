import { useState } from 'react'
import { PageHeader } from '../componentes/Basicos'

/** Los pasos y sus ids son los del script Arreglo_Automatico_Para_App.ps1: aquí solo se eligen, nunca se ejecuta nada que no esté allí. */
const PASOS: { id: string; titulo: string; que: string; min: number; nota?: string }[] = [
  { id: 'limpieza', titulo: 'Liberar espacio y memoria', que: 'Borra los temporales con más de un día y libera memoria. No toca documentos ni cierra programas.', min: 2 },
  { id: 'limpieza_profunda', titulo: 'Limpieza a fondo de temporales y navegadores', que: 'Borra temporales del sistema y la caché de los navegadores.', min: 5, nota: 'Cierra los navegadores antes.' },
  { id: 'red', titulo: 'Reparar la conexión a Internet', que: 'Vacía la caché de nombres, renueva la dirección y restablece la configuración de red.', min: 2, nota: 'Puede cortar la conexión unos segundos.' },
  { id: 'seguridad', titulo: 'Activar la protección de Windows', que: 'Enciende el antivirus y el firewall y actualiza sus firmas. Si hay otro antivirus, no lo toca.', min: 3 },
  { id: 'antivirus', titulo: 'Buscar virus con el antivirus de Windows', que: 'Análisis rápido con Microsoft Defender; el antivirus trata lo que encuentre.', min: 8, nota: 'Necesita administrador.' },
  { id: 'wu', titulo: 'Reparar Windows Update', que: 'Restablece los componentes de actualización. No borra nada: guarda copia de las carpetas antiguas.', min: 3 },
  { id: 'actualizar', titulo: 'Instalar las actualizaciones de Windows', que: 'Descarga e instala las actualizaciones pendientes. No reinicia solo.', min: 45, nota: 'Puede tardar más de una hora.' },
  { id: 'actualizar_programas', titulo: 'Actualizar los programas instalados', que: 'Actualiza con winget todo lo que lo permita, en silencio.', min: 20 },
  { id: 'integridad', titulo: 'Reparar los archivos de Windows', que: 'Comprueba el disco y repara los archivos del sistema dañados (DISM y SFC).', min: 25, nota: 'Es lo que más tarda.' },
  { id: 'optimizar', titulo: 'Optimizar el rendimiento de Windows', que: 'Ajusta arranque y memoria virtual, optimiza el disco y limpia restos de actualizaciones.', min: 15, nota: 'Se deshace con «Deshacer los últimos cambios».' }
]
const PAQUETES: { id: string; titulo: string; texto: string; pasos: string[] }[] = [
  { id: 'puesta', titulo: 'Puesta a punto', texto: 'Limpia y deja el equipo ligero.', pasos: ['limpieza', 'limpieza_profunda', 'optimizar'] },
  { id: 'windows', titulo: 'Reparar Windows', texto: 'Arregla las actualizaciones y los archivos dañados.', pasos: ['wu', 'integridad'] },
  { id: 'internet', titulo: 'Internet y protección', texto: 'Repara la red, activa la protección y busca virus.', pasos: ['red', 'seguridad', 'antivirus'] },
  { id: 'completo', titulo: 'Mantenimiento completo', texto: 'Todo lo anterior, sin instalar actualizaciones.', pasos: ['limpieza', 'limpieza_profunda', 'red', 'seguridad', 'antivirus', 'wu', 'integridad', 'optimizar'] }
]
const minutos = (ids: string[]) => ids.reduce((s, id) => s + (PASOS.find((p) => p.id === id)?.min ?? 0), 0)
const mismos = (a: string[], b: string[]) => a.length === b.length && a.every((x) => b.includes(x))

export default function Combos({ ocupado, alEjecutar, alPedir }: { ocupado: boolean; alEjecutar: (pasos: string[]) => void; alPedir: (d: { titulo: string; texto: string; ok: string; no?: string; alAceptar: () => void }) => void }) {
  const [elegidos, setElegidos] = useState<string[]>([])
  const alternar = (id: string) => setElegidos((e) => (e.includes(id) ? e.filter((x) => x !== id) : [...e, id]))
  const orden = PASOS.map((p) => p.id).filter((id) => elegidos.includes(id))   // siempre en el orden del script, da igual en cuál se marcaran

  return (
    <div className="pagina">
      <PageHeader titulo="Combos" subtitulo="Elige un paquete o marca los pasos que quieras, juntos o de uno en uno. Se aplican en orden, cada uno con su tiempo máximo, y al final sale un informe." />
      <section aria-label="Paquetes" className="paquetes">
        {PAQUETES.map((p) => (
          <button key={p.id} className="paquete" aria-pressed={mismos(elegidos, p.pasos)} onClick={() => setElegidos(mismos(elegidos, p.pasos) ? [] : [...p.pasos])}>
            <b>{p.titulo}</b>
            <span className="det">{p.texto}</span>
            <span className="sub-linea num">{p.pasos.length} pasos · unos {minutos(p.pasos)} min</span>
          </button>
        ))}
      </section>
      <section className="grupo" aria-label="Pasos">
        <h2>Pasos sueltos<span className="num">{PASOS.length}</span></h2>
        {PASOS.map((p) => (
          <label className="paso-elegible" key={p.id}>
            <input type="checkbox" checked={elegidos.includes(p.id)} onChange={() => alternar(p.id)} />
            <span className="cuerpo"><b>{p.titulo}</b><span className="det">{p.que}{p.nota ? ` ${p.nota}` : ''}</span></span>
            <span className="sub-linea num">~{p.min} min</span>
          </label>
        ))}
      </section>
      <div className="barra-accion">
        <span>{orden.length === 0 ? 'Elige un paquete o marca algún paso.' : `${orden.length} ${orden.length === 1 ? 'paso' : 'pasos'} · unos ${minutos(orden)} min`}</span>
        <button className="boton" disabled={orden.length === 0} onClick={() => setElegidos([])}>Quitar selección</button>
        <button className="boton principal-b" disabled={orden.length === 0 || ocupado} onClick={() => { const ir = () => alEjecutar(orden); if (minutos(orden) >= 30) alPedir({ titulo: 'Combo largo', texto: `Esto puede tardar unos ${minutos(orden)} minutos. Puedes dejar el ordenador trabajando. ¿Empezamos?`, ok: 'Sí, empezar', no: 'Ahora no', alAceptar: ir }); else ir() }}>{orden.length === 1 ? 'Hacerlo' : `Hacer los ${orden.length} pasos`}</button>
      </div>
      {orden.length > 0 && <p className="nota-opcion">Si algún paso cambia el sistema, antes se crea un punto de restauración. {ocupado ? 'Hay otra cosa en marcha: espera a que termine.' : ''}</p>}
    </div>
  )
}
