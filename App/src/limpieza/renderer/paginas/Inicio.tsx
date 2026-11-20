import { useState } from 'react'
import { PageHeader, Vacio } from '../../../renderer/src/componentes/Basicos'

export interface ItemInicio { tipo: 'registro' | 'tarea'; id: string; nombre: string; ambito: string; orden: string; activo: boolean; icono?: string }
export interface Arranque { segundos: number; escritorio: number; fecha: string; lentos: string[] }
type Filtro = 'todos' | 'activos' | 'apagados'

export default function Inicio({ items, arranque, admin, ocupado, alRecargar, alCambiar }: {
  items: ItemInicio[] | null; arranque: Arranque | null; admin: boolean; ocupado: boolean; alRecargar: () => void; alCambiar: (it: ItemInicio, activar: boolean) => void
}) {
  const [filtro, setFiltro] = useState<Filtro>('todos')
  const lista = items ?? []
  const activos = lista.filter((i) => i.activo).length
  const visibles = lista.filter((i) => filtro === 'todos' || (filtro === 'activos' ? i.activo : !i.activo))
    .sort((a, b) => Number(b.activo) - Number(a.activo) || a.nombre.localeCompare(b.nombre, 'es'))
  // Lo de todos los usuarios y las tareas programadas piden administrador; si falta, el interruptor se bloquea con su motivo
  const necesitaAdmin = (i: ItemInicio) => i.tipo === 'tarea' || i.ambito.startsWith('Todos')
  const chip = (id: Filtro, texto: string, n: number) => <button className="chip" aria-pressed={filtro === id} onClick={() => setFiltro(id)}>{texto}<span className="cuenta num">{n}</span></button>

  return (
    <div className="pagina">
      <PageHeader titulo="Inicio de Windows" subtitulo="Lo que se carga al encender el equipo. Desactivar no desinstala nada y se puede volver a activar cuando quieras. En la duda, deja el antivirus y los drivers de audio y táctil."
        acciones={<button className="boton" disabled={ocupado} onClick={alRecargar}>Actualizar la lista</button>} />
      {arranque && (
        <div className="resumen-barra" role="status">
          <span className="grande num">{arranque.segundos} s</span>
          <span className="sub">el último arranque completo{arranque.escritorio > 0 ? `, con el escritorio listo a los ${arranque.escritorio} s` : ''} (medido por Windows el {arranque.fecha.split('-').reverse().join('/')}){arranque.lentos.length > 0 && <> · Según Windows lo ralentizaron: <b>{arranque.lentos.join(', ')}</b></>}</span>
        </div>
      )}
      <div className="filtros" role="group" aria-label="Qué ver">
        {chip('todos', 'Todos', lista.length)}{chip('activos', 'Se cargan', activos)}{chip('apagados', 'Desactivados', lista.length - activos)}
      </div>
      {items === null || (ocupado && !lista.length) ? <p className="vacio" role="status">Leyendo los programas de inicio…</p>
        : !visibles.length ? <Vacio>No hay nada en esta lista.</Vacio>
        : <section className="grupo" aria-label="Programas de inicio">
            {visibles.map((i) => {
              const bloqueado = necesitaAdmin(i) && !admin
              return (
                <div key={`${i.tipo}|${i.id}`} className={`fila-i ${i.activo ? '' : 'apagada'}`}>
                  <div className="con-icono">
                    {i.icono ? <img className="icono-app" src={i.icono} alt="" /> : <span className="icono-app vacio-i" aria-hidden="true" />}
                    <div>
                    <h3>{i.nombre}{i.tipo === 'tarea' && <span className="etiqueta info">Tarea programada</span>}</h3>
                    <div className="amb">{i.tipo === 'tarea' ? (bloqueado ? 'Necesita administrador para cambiarlo' : 'Se inicia con Windows') : i.ambito}{bloqueado && i.tipo !== 'tarea' && ' · necesita administrador para cambiarlo'}</div>
                    {i.orden && <div className="ruta">{i.orden}</div>}
                    </div>
                  </div>
                  <label className="interruptor" title={i.activo ? 'Se carga al iniciar: pulsa para desactivarlo' : 'No se carga al iniciar: pulsa para activarlo'}>
                    <input type="checkbox" role="switch" checked={i.activo} disabled={ocupado || bloqueado} aria-label={`${i.nombre}: se carga al iniciar Windows`} onChange={(e) => alCambiar(i, e.target.checked)} />
                    <span />
                  </label>
                </div>
              )
            })}
          </section>}
    </div>
  )
}
