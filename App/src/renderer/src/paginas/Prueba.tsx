import { useEffect, useState } from 'react'
import { PageHeader } from '../componentes/Basicos'

/** Una prueba del kit (teclado, ratón, pantalla, webcam, audio) dentro de la app: página local del kit en un marco, sin salir al navegador. Al salir de esta vista el marco se destruye y la cámara o el micrófono se sueltan. */
export default function Prueba({ titulo, url, alVolver }: { titulo: string; url: string; alVolver: () => void }) {
  const media: 'camera' | 'microphone' | null = /webcam/i.test(titulo) ? 'camera' : /audio|micr/i.test(titulo) ? 'microphone' : null
  const nombre = media === 'microphone' ? 'micrófono' : 'cámara'
  const [estado, setEstado] = useState('unknown')
  const [intento, setIntento] = useState(0)
  useEffect(() => { void window.kit.pruebaEntrar(); return () => { void window.kit.pruebaSalir() } }, [])   // mientras el marco está montado el proceso principal concede cámara/micrófono/pantalla completa; al salir, deja de hacerlo
  useEffect(() => { if (media) void window.kit.mediaEstado(media).then(setEstado).catch(() => setEstado('unknown')) }, [media, intento])
  return (
    <div className="pagina prueba-pagina">
      <PageHeader titulo={titulo} subtitulo="Prueba dentro de la app. No se guarda ni se envía nada; la cámara y el micrófono, si los usa, solo se activan mientras esta pantalla está abierta."
        acciones={<button className="boton" onClick={alVolver}>Volver</button>} />
      {media && (
        <div className={`aviso-media${estado === 'denied' || estado === 'restricted' ? ' mal' : ''}`} role="status">
          <span>{estado === 'granted' ? `Windows permite a esta app usar el ${nombre}.`
            : estado === 'denied' || estado === 'restricted' ? `Windows está bloqueando el ${nombre} a las aplicaciones de escritorio: actívalo en Configuración → Privacidad y seguridad y pulsa «Recargar la prueba».`
            : `Si la prueba dice «permiso denegado», activa el ${nombre} para las aplicaciones de escritorio en los ajustes de Windows y pulsa «Recargar la prueba».`}</span>
          <button className="boton" onClick={() => void window.kit.ajustesPrivacidad(media)}>Abrir los ajustes de {nombre} de Windows</button>
          <button className="boton" onClick={() => setIntento((n) => n + 1)}>Recargar la prueba</button>
        </div>
      )}
      <iframe key={intento} className="prueba-marco" title={titulo} src={url} sandbox="allow-scripts allow-same-origin" allow="camera *; microphone *; fullscreen *; gamepad *" allowFullScreen />
    </div>
  )
}
