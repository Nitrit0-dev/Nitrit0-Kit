import { useMemo, useState } from 'react'
import { PageHeader, Medidor, NotaSalud, notaSalud } from '../componentes/Basicos'
import { usaEjecutor, type Dx, type Elemento, type EstadoPrueba, type Ficha, type Tono } from '../tipos'

const TONO: Record<EstadoPrueba, Tono | undefined> = { OK: undefined, Info: undefined, Aviso: 'aviso', Fallo: 'error' }
const ETIQUETA: Record<EstadoPrueba, string> = { OK: 'Correcto', Info: 'Información', Aviso: 'Aviso', Fallo: 'Fallo' }

interface Props {
  dx: Dx | null; funcionando: boolean; ocupado: boolean; ficha: Ficha; soluciones: Record<string, string[]>; elementos: Elemento[]
  alFicha: () => void; alTaller: () => void; alEmpezar: (modo: 'Rapido' | 'Completo') => void; alCancelar: () => void
  alLanzar: (e: Elemento) => void; alInformeEntrega: () => void
}

export default function Diagnostico({ dx, funcionando, ocupado, ficha, soluciones, elementos, alFicha, alTaller, alEmpezar, alCancelar, alLanzar, alInformeEntrega }: Props) {
  const [modo, setModo] = useState<'Rapido' | 'Completo'>('Rapido')
  const [copiado, setCopiado] = useState(false)
  const conFicha = !!(ficha.Cliente || ficha.Motivo || ficha.Telefono || ficha.Notas)

  const total = dx?.plan.reduce((s, p) => s + p.seg, 0) ?? 0
  const hecho = dx?.plan.filter((p) => dx.resultados[p.id]).reduce((s, p) => s + p.seg, 0) ?? 0
  const nHechas = dx ? Object.keys(dx.resultados).length : 0
  const actual = dx?.plan.find((p) => p.id === dx.actual)

  const grupos = useMemo(() => {
    const m = new Map<string, NonNullable<typeof dx>['plan']>()
    for (const p of dx?.plan ?? []) m.set(p.grupo, [...(m.get(p.grupo) ?? []), p])
    return [...m.entries()]
  }, [dx?.plan]) // eslint-disable-line react-hooks/exhaustive-deps

  const herramientas = (id: string) =>
    (soluciones[id] ?? []).map((t) => elementos.find((e) => e.titulo === t && e.soportado && e.disponible)).filter((e): e is Elemento => !!e).slice(0, 4)

  const copiar = async () => {
    if (!dx) return
    const lineas = dx.plan.filter((p) => dx.resultados[p.id]).map((p) => `[${dx.resultados[p.id].estado.toUpperCase()}] ${p.nombre}: ${dx.resultados[p.id].resumen}`)
    try { await navigator.clipboard.writeText(`DIAGNÓSTICO ${new Date().toLocaleString('es-ES')}\n${lineas.join('\n')}`); setCopiado(true); setTimeout(() => setCopiado(false), 2500) } catch { /* sin portapapeles */ }
  }

  const resumenFinal = dx?.fin
    ? dx.fin.interrumpido ? `${dx.fin.motivo ?? 'Detenido'} a los ${dx.fin.seg} s: ${nHechas} de ${dx.plan.length} pruebas hechas, no se guarda en el historial.`
      : dx.fin.fallos ? `${dx.fin.fallos} ${dx.fin.fallos === 1 ? 'fallo' : 'fallos'} y ${dx.fin.avisos} ${dx.fin.avisos === 1 ? 'aviso' : 'avisos'}`
      : dx.fin.avisos ? `${dx.fin.avisos} ${dx.fin.avisos === 1 ? 'aviso' : 'avisos'}, ningún fallo` : 'Todo correcto'
    : null

  return (
    <div className="pagina">
      <PageHeader
        titulo="Diagnóstico del equipo"
        subtitulo="Pasa las pruebas del kit y guarda el resultado en el historial del equipo. Ninguna prueba cambia nada."
        acciones={funcionando
          ? <button className="boton peligro-b" onClick={alCancelar}>Detener diagnóstico</button>
          : <>
              <button className="boton" disabled={ocupado} onClick={alTaller}>Modo taller</button>
              <button className="boton principal-b" disabled={ocupado} onClick={() => alEmpezar(modo)}>Empezar diagnóstico</button>
            </>}
      />

      {!funcionando && (
        <section className="opciones" aria-label="Opciones del diagnóstico">
          <div className="filtros" role="group" aria-label="Tipo de diagnóstico">
            <button className="chip" aria-pressed={modo === 'Rapido'} onClick={() => setModo('Rapido')}>Rápido<span className="cuenta">unos 2 min</span></button>
            <button className="chip" aria-pressed={modo === 'Completo'} onClick={() => setModo('Completo')}>Profundo<span className="cuenta">unos 16 min</span></button>
          </div>
          <p className="nota-opcion">{modo === 'Rapido'
            ? 'Sistema, CPU, memoria, discos, red, eventos, SMART, seguridad y actualizaciones.'
            : 'Todo lo del rápido y además prueba la RAM, la CPU en carga, la velocidad del disco, el sistema de archivos y los archivos de Windows (SFC). Tarda bastante más y carga el equipo.'}</p>
          <div className="ficha-linea">
            <button className="boton" onClick={alFicha}>{conFicha ? 'Editar ficha del cliente' : 'Rellenar ficha del cliente'}</button>
            {conFicha && <span className="num">{[ficha.Cliente, ficha.Telefono].filter(Boolean).join(' · ') || ficha.Motivo}</span>}
          </div>
        </section>
      )}

      {funcionando && dx && (
        <section aria-label="Progreso" role="status">
          <div className="estado-ejec">{actual ? `Comprobando: ${actual.nombre}` : 'Preparando las pruebas…'} · {nHechas} de {dx.plan.length || '…'}</div>
          <Medidor rol="progressbar" etiqueta="Progreso del diagnóstico" valor={hecho} max={Math.max(total, 1)} />
        </section>
      )}

      {dx?.fin && !funcionando && (
        <section className={`resumen-dx${dx.fin.interrumpido ? '' : ' con-nota'}`} aria-label="Resultado">
          {!dx.fin.interrumpido && <NotaSalud nota={notaSalud(dx.fin.fallos, dx.fin.avisos)} />}
          <div>
            <h2 className={dx.fin.fallos ? 'mal' : dx.fin.avisos ? 'aviso' : 'ok'}>{resumenFinal}</h2>
            {dx.fin.comparacion && <p>{dx.fin.comparacion.resumen}.</p>}
            {!dx.fin.comparacion && !dx.fin.interrumpido && dx.fin.historial && <p>Es el primer diagnóstico guardado de este equipo.</p>}
            {!dx.fin.interrumpido && !dx.fin.historial && <p className="aviso-txt">No se pudo guardar en el historial: revisa que el pendrive siga conectado.</p>}
            <div className="acciones">
              <button className="boton" onClick={copiar}>{copiado ? 'Copiado' : 'Copiar resumen'}</button>
              {!dx.fin.interrumpido && <button className="boton" disabled={ocupado} onClick={alInformeEntrega}>Informe de entrega</button>}
            </div>
          </div>
        </section>
      )}

      {dx && grupos.map(([grupo, pruebas]) => (
        <section className="grupo" key={grupo} aria-label={grupo}>
          <h2>{grupo}<span className="num">{pruebas.length}</span></h2>
          {pruebas.map((p) => {
            const r = dx.resultados[p.id]
            const tono = r ? TONO[r.estado] : undefined
            const trabajando = dx.actual === p.id && !r
            const sol = r && r.estado !== 'OK' ? herramientas(p.id) : []   // también en «Información»: suele ser algo que no se pudo medir y hay herramienta para verlo
            return (
              <details className="prueba" key={p.id} open={!!r && (r.estado === 'Fallo')}>
                <summary>
                  <span className={`punto ${r ? (tono ?? (r.estado === 'Info' ? 'info' : 'ok')) : 'espera'}`} role="img" aria-label={r ? ETIQUETA[r.estado] : trabajando ? 'Comprobando' : 'En cola'} />
                  <span className="cuerpo"><b>{p.nombre}</b><span className="det">{r ? r.resumen : trabajando ? 'Comprobando…' : 'En cola'}</span></span>
                  {r && <span className="num seg">{r.seg.toFixed(0)} s</span>}
                </summary>
                {r && (r.detalle || sol.length > 0) && (
                  <div className="prueba-detalle">
                    {r.detalle && <pre>{r.detalle}</pre>}
                    {sol.length > 0 && (
                      <div className="siguiente">
                        <span>Siguiente paso</span>
                        {sol.map((e) => <button key={e.id} className="boton" disabled={ocupado && usaEjecutor(e)} onClick={() => alLanzar(e)}>{e.titulo}</button>)}
                      </div>
                    )}
                  </div>
                )}
              </details>
            )
          })}
        </section>
      ))}
    </div>
  )
}
