import { useState } from 'react'
import { Confirmar, Medidor, PageHeader } from '../../../renderer/src/componentes/Basicos'

export interface Categoria { id: string; grupo: string; nombre: string; ayuda: string; marcada: boolean; riesgo: string; bytes: number; archivos: number; admin: boolean; abiertos?: string[] }
const NOMBRE_PROC: Record<string, string> = { chrome: 'Chrome', msedge: 'Edge', firefox: 'Firefox', brave: 'Brave', vivaldi: 'Vivaldi', opera: 'Opera' }
export interface Resultado { bytes: number; enUso: number; error?: string }

export const tam = (b: number) => (b >= 1073741824 ? `${(b / 1073741824).toFixed(1)} GB` : b >= 1048576 ? `${Math.round(b / 1048576)} MB` : b >= 1024 ? `${Math.round(b / 1024)} KB` : `${b} B`)
const GRUPOS = ['Windows', 'Navegadores', 'Aplicaciones']

export default function Limpiador({ cats, sel, alSel, fase, resultados, liberado, avisos, admin, ocupado, alAnalizar, alLimpiar, alCancelar }: {
  cats: Categoria[]; sel: Set<string>; alSel: (s: Set<string>) => void; fase: 'analizando' | 'listo' | 'limpiando' | 'hecho'; resultados: Record<string, Resultado>
  liberado: number | null; avisos: string[]; admin: boolean; ocupado: boolean; alAnalizar: () => void; alLimpiar: () => void; alCancelar: () => void
}) {
  const [confirmar, setConfirmar] = useState(false)
  // Sin administrador, las categorías de Windows no se pueden borrar: se ven (con su tamaño) pero no se marcan
  const puede = (c: Categoria) => !c.admin || admin
  const elegidas = cats.filter((c) => sel.has(c.id) && puede(c))
  const total = elegidas.reduce((s, c) => s + c.bytes, 0)
  const cambiar = (id: string, on: boolean) => { const s = new Set(sel); if (on) s.add(id); else s.delete(id); alSel(s) }
  const marcarSeguras = () => alSel(new Set(cats.filter((c) => c.marcada && puede(c)).map((c) => c.id)))
  const quitarTodas = () => alSel(new Set())
  const mostrarResultado = fase === 'limpiando' || fase === 'hecho'
  const hayMedio = elegidas.some((c) => c.riesgo === 'medio')
  // Navegadores que están abiertos justo ahora y que se cerrarán (el que no responda en 8 s se fuerza: se pierde lo que haya sin guardar)
  const abiertos = [...new Set(elegidas.flatMap((c) => c.abiertos ?? []))].map((p) => NOMBRE_PROC[p] ?? p)

  return (
    <div className="pagina">
      <PageHeader titulo="Limpiador" subtitulo="Marca lo que quieres borrar. Antes de tocar nada se calcula cuánto se libera; tus documentos, fotos y descargas no se tocan."
        acciones={<>
          {fase === 'analizando' && <button className="boton" onClick={alCancelar}>Cancelar análisis</button>}
          <button className="boton" disabled={ocupado} onClick={alAnalizar}>{fase === 'analizando' ? 'Analizando…' : 'Analizar de nuevo'}</button>
          <button className="boton principal-b" disabled={ocupado || !elegidas.length} onClick={() => setConfirmar(true)}>{fase === 'limpiando' ? 'Limpiando…' : 'Limpiar lo marcado'}</button>
        </>} />

      <div className="resumen-barra" role="status">
        {fase === 'analizando' && <><span className="grande">Analizando…</span><span className="sub">Calculando cuánto ocupa cada cosa</span><div className="linea-completa"><Medidor valor={0} etiqueta="Analizando el equipo" rol="progressbar" indeterminado /></div></>}
        {fase === 'limpiando' && <><span className="grande">Limpiando…</span><span className="sub">No cierres la ventana hasta que termine</span><div className="linea-completa"><Medidor valor={0} etiqueta="Limpiando" rol="progressbar" indeterminado /></div></>}
        {fase === 'hecho' && <><span className="grande num">{liberado === null ? '' : tam(liberado)}</span><span className="sub">{liberado === null ? 'La limpieza no terminó.' : 'liberados en el disco del sistema'}</span></>}
        {fase === 'listo' && <><span className="grande num">{tam(total)}</span><span className="sub">se liberarían con lo marcado ({elegidas.length} de {cats.length} categorías)</span></>}
        <span className="hueco" />
        <div className="mini-acciones">
          <button className="chip" disabled={ocupado} onClick={marcarSeguras}>Marcar las recomendadas</button>
          <button className="chip" disabled={ocupado} onClick={quitarTodas}>Desmarcar todo</button>
        </div>
      </div>
      {avisos.map((a) => <div key={a} className="aviso-banda" role="alert">{a}</div>)}

      {GRUPOS.map((g) => {
        const lista = cats.filter((c) => c.grupo === g).sort((a, b) => b.bytes - a.bytes)
        if (!lista.length) return null
        return (
          <section className="grupo" key={g} aria-label={g}>
            <h2>{g}</h2>
            {lista.map((c) => {
              const r = mostrarResultado ? resultados[c.id] : undefined
              const bloqueada = !puede(c)
              return (
                <label key={c.id} className={`fila-c ${r ? (r.error ? 'fallo' : 'hecha') : ''}`}>
                  <input type="checkbox" checked={sel.has(c.id) && !bloqueada} disabled={ocupado || bloqueada} onChange={(e) => cambiar(c.id, e.target.checked)} />
                  <div>
                    <h3>{c.nombre}</h3>
                    <p>{c.ayuda}</p>
                    {bloqueada && <div className="nota aviso">Necesita abrir la app como administrador</div>}
                    {c.riesgo === 'medio' && !bloqueada && <div className="nota aviso">Se pierde para siempre: revísalo antes de marcarlo</div>}
                    {r?.error && <div className="nota aviso">{r.error}</div>}
                    {r && !r.error && r.enUso > 0 && <div className="nota">{r.enUso} elemento(s) en uso se han dejado</div>}
                  </div>
                  <div className={`tam ${c.bytes === 0 && !r ? 'cero' : ''}`}>
                    {r ? (r.error ? 'Error' : `−${tam(r.bytes)}`) : tam(c.bytes)}
                    {!r && c.archivos > 0 && <small>{c.archivos.toLocaleString('es-ES')} archivos</small>}
                  </div>
                </label>
              )
            })}
          </section>
        )
      })}

      <Confirmar abierto={confirmar} titulo="Limpiar lo marcado" texto={`Se borrarán unos ${tam(total)} de ${elegidas.length} categoría(s). No se puede deshacer.${abiertos.length ? ` Ahora mismo están abiertos y se cerrarán: ${abiertos.join(', ')}. Si alguno no responde en 8 segundos se fuerza el cierre y se pierde lo que tenga sin guardar (formularios, pestañas): avisa al cliente antes.` : ''}`}
        detalle={hayMedio ? 'Has marcado algo que se pierde para siempre (papelera, volcados de memoria o la carpeta C:\\TEMP).' : null} textoOk="Sí, limpiar" textoNo="Cancelar"
        alAceptar={() => { setConfirmar(false); alLimpiar() }} alCancelar={() => setConfirmar(false)} />
    </div>
  )
}
