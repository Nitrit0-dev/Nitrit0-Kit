import { useCallback, useEffect, useState } from 'react'
import { Check, Circle, CircleAlert, Heart, Info } from 'lucide-react'
import { PageHeader, Sello } from '../componentes/Basicos'
import Desplegable from '../componentes/Desplegable'
import HistorialCambios from '../componentes/HistorialCambios'
import type { AjusteInfo, OtraCuenta } from '../tipos'

type Est = 'rec' | 'pred' | 'pers' | 'gusto' | 'otro'
/** Una sola etiqueta por ajuste: dónde está respecto a lo recomendado y a lo que trae Windows. Siempre icono y texto, nunca solo color. */
const estadoDe = (a: AjusteInfo): Est => (a.actual === 'otro' ? 'otro' : a.rec && a.actual === a.rec ? 'rec' : a.actual === a.def ? 'pred' : a.rec ? 'pers' : 'gusto')
const ETIQUETA: Record<Est, { texto: string; icono: typeof Check }> = {
  rec: { texto: 'Como recomendamos', icono: Check }, pred: { texto: 'Valor de Windows', icono: Circle },
  pers: { texto: 'Valor distinto', icono: CircleAlert }, gusto: { texto: 'Elegido por ti', icono: Heart }, otro: { texto: 'Otro valor', icono: CircleAlert }
}
const limpiar = (e: unknown) => String(e).replace(/^Error: (Error invoking remote method '[^']+': )?(Error: )?/, '')
const nombreOpcion = (a: AjusteInfo, k: string | null) => a.opciones.find((o) => o.k === k)?.t ?? '—'
const valorOpcion = (a: AjusteInfo, k: string | null) => { const v = a.opciones.find((o) => o.k === k)?.v; return v === undefined ? '—' : String(v) }

/**
 * Ajustes de Windows con su estado real: cómo está cada uno ahora, cuál recomendamos y cuál trae Windows.
 * Solo lo que figura en la lista blanca de Ajustes_Para_App.ps1; cada cambio guarda el valor anterior y se deshace desde «Deshacer los últimos cambios».
 */
export default function Ajustes() {
  const [lista, setLista] = useState<AjusteInfo[] | null>(null)
  const [build, setBuild] = useState(0)
  const [cuenta, setCuenta] = useState<OtraCuenta | null>(null)
  const [error, setError] = useState('')
  const [leyendo, setLeyendo] = useState(false)
  const [ocupados, setOcupados] = useState<string[]>([])
  const [avisos, setAvisos] = useState<Record<string, string>>({})
  const [soloMio, setSoloMio] = useState(true)
  const [detalles, setDetalles] = useState(false)
  const [soloDif, setSoloDif] = useState(false)

  const leer = useCallback(() => {
    setError(''); setLeyendo(true)
    window.kit.ajustes({ accion: 'leer' })
      .then((r: { ok: boolean; build?: number; otraCuenta?: OtraCuenta; ajustes?: AjusteInfo[]; mensaje?: string }) => { if (r.ok && r.ajustes) { setLista(r.ajustes); setBuild(r.build ?? 0); setCuenta(r.otraCuenta ?? null) } else setError(r.mensaje ?? 'No se pudieron leer los ajustes.') })
      .catch((e: unknown) => setError(limpiar(e)))
      .finally(() => setLeyendo(false))
  }, [])
  useEffect(() => { leer() }, [leer])

  const aplicar = async (a: AjusteInfo, opcion: string) => {
    setOcupados((o) => [...o, a.id]); setAvisos((v) => { const { [a.id]: _, ...resto } = v; return resto })
    try {
      const r: { ok: boolean; ajuste?: AjusteInfo; mensaje?: string } = await window.kit.ajustes({ accion: 'aplicar', id: a.id, opcion })
      if (r.ok && r.ajuste) setLista((l) => (l ? l.map((x) => (x.id === a.id ? r.ajuste! : x)) : l))
      else setAvisos((v) => ({ ...v, [a.id]: r.mensaje ?? 'No se pudo cambiar.' }))
    } catch (e) { setAvisos((v) => ({ ...v, [a.id]: limpiar(e) })) }
    finally { setOcupados((o) => o.filter((x) => x !== a.id)) }
  }

  if (error && !lista) return (
    <div className="pagina"><PageHeader titulo="Ajustes de Windows" subtitulo="No se pudieron leer los ajustes." /><p className="vacio">{error}</p><div><button className="boton" onClick={leer}>Volver a intentarlo</button></div></div>
  )
  if (!lista) return <div className="pagina"><PageHeader titulo="Ajustes de Windows" subtitulo="Leyendo cómo está cada ajuste en este equipo…" /></div>

  const ocultos = lista.filter((a) => !a.aplicable).length
  const visibles = lista.filter((a) => (!soloMio || a.aplicable) && (!soloDif || (!!a.rec && a.actual !== a.rec)))
  const grupos = [...new Set(visibles.map((a) => a.grupo))]
  const conRec = lista.filter((a) => a.aplicable && a.rec), bien = conRec.filter((a) => a.actual === a.rec).length

  return (
    <div className="pagina">
      <PageHeader titulo="Ajustes de Windows" subtitulo="Cómo está cada ajuste ahora mismo en este equipo y cuál recomendamos. Cada cambio guarda el valor anterior: se puede deshacer desde el «Historial de cambios» del final de esta página."
        acciones={<button className="boton" onClick={leer} disabled={leyendo}>{leyendo ? 'Leyendo…' : 'Volver a leer'}</button>} />
      {cuenta?.otra && <div className="aj-nota aviso" role="alert"><CircleAlert size={16} strokeWidth={1.75} aria-hidden="true" />La app está abierta con otra cuenta ({cuenta.proceso}) y el escritorio es de {cuenta.sesion}: estos ajustes cambiarían el perfil equivocado, así que no se pueden cambiar desde aquí. Ábrela con tu propia cuenta de administrador.</div>}
      <div className="aj-resumen" role="status">
        {conRec.length > 0 ? <><b className="n">{bien} de {conRec.length}</b> como recomendamos · el resto es cuestión de gusto: no hay una opción mejor.</> : 'Todo lo de aquí es cuestión de gusto.'}
      </div>
      <div className="filtros" role="group" aria-label="Filtrar">
        <button className="chip" aria-pressed={soloMio} onClick={() => setSoloMio((x) => !x)}>Solo lo que existe en mi Windows<span className="cuenta num">{build}</span></button>
        <button className="chip" aria-pressed={soloDif} onClick={() => setSoloDif((x) => !x)}>Solo lo que no está como recomendamos</button>
        <button className="chip" aria-pressed={detalles} onClick={() => setDetalles((x) => !x)}>Detalles técnicos</button>
      </div>
      {soloMio && ocultos > 0 && <p className="nota-vacia">{ocultos === 1 ? 'Hay 1 ajuste oculto' : `Hay ${ocultos} ajustes ocultos`} porque no existen en tu versión de Windows (compilación {build}).</p>}
      {visibles.length === 0 && <p className="nota-vacia">No hay ajustes con ese filtro.</p>}
      {grupos.map((g) => (
        <section className="bloque" key={g} aria-label={g}>
          <h2>{g}</h2>
          <div className="aj-lista">
            {visibles.filter((a) => a.grupo === g).map((a) => {
              const est = estadoDe(a), { texto, icono: Icono } = ETIQUETA[est]
              const ocupado = ocupados.includes(a.id)
              const otra = a.opciones.find((o) => o.k !== a.activado)?.k ?? ''
              const activo = a.actual === a.activado
              return (
                <article className="aj-fila" key={a.id} aria-busy={ocupado}>
                  <div><h3>{a.titulo}{a.rec && <Sello tipo="acento" ayuda="Es el valor que recomendamos para la mayoría de equipos.">Recomendado</Sello>}<Sello tipo="ok" ayuda="Guarda el valor anterior: se deshace desde «Deshacer los últimos cambios».">Reversible</Sello></h3><p>{a.descripcion}</p></div>
                  <div className="aj-control">
                    {a.tipo === 'interruptor'
                      ? <button className="interruptor" role="switch" aria-checked={activo} aria-label={a.titulo} disabled={ocupado || !!cuenta?.otra} onClick={() => void aplicar(a, activo ? otra : a.activado)}>
                          <span className="pista" /><span className="texto">{nombreOpcion(a, activo ? a.activado : otra)}</span>
                        </button>
                      : <Desplegable etiqueta={a.titulo} valor={a.actual} opciones={a.opciones} deshabilitado={ocupado || !!cuenta?.otra} alElegir={(k) => void aplicar(a, k)} />}
                  </div>
                  <div className="aj-linea">
                    <span className={`aj-estado ${est}`}><Icono size={14} strokeWidth={1.75} aria-hidden="true" />{texto}</span>
                    <span>{a.rec ? <>Recomendado: <b>{nombreOpcion(a, a.rec)}</b> · </> : null}Windows: {nombreOpcion(a, a.def)}</span>
                    {a.rec && a.actual !== a.rec && <button className="enlace" disabled={ocupado || !!cuenta?.otra} onClick={() => void aplicar(a, a.rec!)}>Poner «{nombreOpcion(a, a.rec)}»</button>}
                    {ocupado && <span aria-live="polite">Cambiando…</span>}
                  </div>
                  {avisos[a.id] && <div className="aj-nota aviso" role="alert"><CircleAlert size={16} strokeWidth={1.75} aria-hidden="true" />{avisos[a.id]}</div>}
                  {a.nota && <div className="aj-nota"><Info size={16} strokeWidth={1.75} aria-hidden="true" />{a.nota}</div>}
                  <details className="aj-detalles" key={`${a.id}-${detalles}`} open={detalles}>
                    <summary>Detalles técnicos</summary>
                    <dl>
                      <dt>Ruta</dt><dd>{a.ruta}</dd>
                      <dt>Valor</dt><dd>{a.nombre} ({a.tipoReg})</dd>
                      <dt>Ahora</dt><dd>{a.raw === null ? '(sin valor: vale el de Windows)' : String(a.raw)}</dd>
                      {a.rec && <><dt>Recomendado</dt><dd>{valorOpcion(a, a.rec)}</dd></>}
                      <dt>Windows</dt><dd>{valorOpcion(a, a.def)}</dd>
                      <dt>Efecto</dt><dd>{a.efecto}</dd>
                    </dl>
                  </details>
                </article>
              )
            })}
          </div>
        </section>
      ))}
      <HistorialCambios ocupado={ocupados.length > 0} />
    </div>
  )
}
