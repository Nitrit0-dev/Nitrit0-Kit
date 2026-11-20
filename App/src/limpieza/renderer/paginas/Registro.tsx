import { useState } from 'react'
import { Confirmar, PageHeader, Vacio } from '../../../renderer/src/componentes/Basicos'

export interface Resto { conf: string; grupo: string; detalle: string }

export default function Registro({ restos, salida, fase, admin, ocupado, alAnalizar, alLimpiar }: {
  restos: Resto[] | null; salida: string[]; fase: 'inicial' | 'analizando' | 'listo' | 'limpiando' | 'hecho'; admin: boolean; ocupado: boolean
  alAnalizar: () => void; alLimpiar: (modo: 'Auto' | 'Manual') => void
}) {
  const [confirmar, setConfirmar] = useState<'Auto' | 'Manual' | null>(null)
  const lista = restos ?? []
  const altas = lista.filter((r) => r.conf === 'Alta').length
  const grupos = [...new Set(lista.map((r) => r.grupo))]

  return (
    <div className="pagina">
      <PageHeader titulo="Registro" subtitulo="Entradas del registro de Windows que apuntan a programas que ya no existen. Nunca se toca lo del sistema ni los controladores, y todo lo que se borra se guarda antes en una cuarentena que se puede restaurar."
        acciones={<>
          <button className="boton" disabled={ocupado} onClick={alAnalizar}>{fase === 'analizando' ? 'Analizando…' : fase === 'inicial' ? 'Analizar el registro' : 'Analizar de nuevo'}</button>
          <button className="boton" disabled={ocupado || !admin || !lista.length} onClick={() => setConfirmar('Manual')}>Elegir a mano…</button>
          <button className="boton principal-b" disabled={ocupado || !admin || !altas} onClick={() => setConfirmar('Auto')}>{altas ? `Limpiar las seguras (${altas})` : 'Limpiar las seguras'}</button>
        </>} />
      {!admin && fase !== 'inicial' && <p className="aviso-txt">Para borrar hace falta abrir la app como administrador. Analizar se puede sin él.</p>}
      {fase === 'inicial' && <Vacio><b>Todavía no se ha mirado nada.</b> Pulsa «Analizar el registro»: solo lee, no cambia nada.</Vacio>}
      {fase === 'analizando' && <p className="vacio" role="status">Revisando el registro, tarda un minuto…</p>}
      {fase === 'listo' && !lista.length && <Vacio>No hay entradas huérfanas: el registro está limpio en lo que se revisa.</Vacio>}
      {fase === 'listo' && lista.length > 0 && (
        <div className="resumen-barra" role="status"><span className="grande num">{lista.length}</span><span className="sub">entradas encontradas · {altas} de confianza alta (se limpian con «Limpiar las seguras»); el resto es para revisar a mano</span></div>
      )}
      {fase === 'limpiando' && <p className="vacio" role="status">Limpiando… no cierres la ventana. Si has elegido «a mano», sigue los pasos de la ventana que se ha abierto.</p>}
      {(fase === 'hecho' || fase === 'limpiando') && salida.length > 0 && <div className="consola" role="log" aria-label="Resultado de la limpieza">{salida.join('\n')}</div>}
      {fase === 'listo' && grupos.map((g) => (
        <section className="grupo" key={g} aria-label={g}>
          <h2>{g}<span> · {lista.filter((r) => r.grupo === g).length}</span></h2>
          {lista.filter((r) => r.grupo === g).map((r, i) => (
            <div key={`${g}${i}`} className="fila-i">
              <div><h3>{r.detalle}</h3></div>
              <span className={`etiqueta ${r.conf === 'Alta' ? 'info' : 'aviso'}`}>Confianza {r.conf.toLowerCase()}</span>
            </div>
          ))}
        </section>
      ))}
      <Confirmar abierto={confirmar !== null} titulo={confirmar === 'Auto' ? 'Limpiar las entradas seguras' : 'Elegir a mano'}
        texto={confirmar === 'Auto' ? `Se borrarán ${altas} entrada(s) de confianza alta. Cada una se guarda antes en la cuarentena y se crea un punto de restauración.` : 'Se abre una ventana con la lista para que marques qué se borra. Cada entrada se guarda antes en la cuarentena.'}
        detalle="Para deshacerlo, usa «Desinstalador de apps» y restaura desde la cuarentena." textoOk="Continuar" textoNo="Cancelar"
        alAceptar={() => { const m = confirmar; setConfirmar(null); if (m) alLimpiar(m) }} alCancelar={() => setConfirmar(null)} />
    </div>
  )
}
