import { useEffect, useRef, useState } from 'react'
import { numero } from '../equipo'
import type { Resumen, Tono, Vivo } from '../tipos'

const MUESTRAS = 150   // 5 minutos a una lectura cada 2 s
const C = 2 * Math.PI * 26
const tono = (pct: number, [aviso, error]: readonly [number, number]): Tono | undefined => (pct > error ? 'error' : pct > aviso ? 'aviso' : undefined)
const UMBRAL_USO = [90, 95] as const      // procesador, gráfica y memoria: un pico alto es normal
const UMBRAL_DISCO = [85, 93] as const   // espacio ocupado: por encima de 85 % ya conviene mirar

/** Anillo con el porcentaje dentro. El texto lleva el dato; el color solo refuerza. */
function Anillo({ pct, etiqueta, umbral = UMBRAL_USO }: { pct: number | null; etiqueta: string; umbral?: readonly [number, number] }) {
  const p = pct === null ? 0 : Math.max(0, Math.min(100, pct))
  return (
    <div className={`anillo ${pct === null ? '' : tono(p, umbral) ?? ''}`} role="meter" aria-label={etiqueta} aria-valuenow={pct === null ? undefined : Math.round(p)} aria-valuemin={0} aria-valuemax={100}>
      <svg viewBox="0 0 64 64" aria-hidden="true"><circle className="pista" cx="32" cy="32" r="26" /><circle className="arco" cx="32" cy="32" r="26" transform="rotate(-90 32 32)" strokeDasharray={`${(p / 100) * C} ${C}`} /></svg>
      <span className="num">{pct === null ? '–' : `${Math.round(p)}`}<small>{pct === null ? '' : ' %'}</small></span>
    </div>
  )
}

function Ficha({ titulo, pct, etiqueta, umbral, children }: { titulo: string; pct: number | null; etiqueta: string; umbral?: readonly [number, number]; children: React.ReactNode }) {
  return <div className="rend-ficha"><Anillo pct={pct} etiqueta={etiqueta} umbral={umbral} /><div className="rend-datos"><b>{titulo}</b>{children}</div></div>
}

const SERIES = [
  { clave: 'cpu', nombre: 'Procesador', trazo: '' },
  { clave: 'ram', nombre: 'Memoria', trazo: '6 4' },
  { clave: 'gpu', nombre: 'Gráfica', trazo: '2 4' }
] as const
type Clave = (typeof SERIES)[number]['clave']
type Rango = { min: number; max: number }

/** Lecturas de la gráfica en una lista: valor actual y mínimo/máximo desde que se abrió la app. Solo lectura: no controla nada. */
function lecturas(g: NonNullable<Vivo['gpu']>) {
  return [
    { id: 'temp', nombre: 'Temperatura', v: g.temp, u: '°C' },
    { id: 'uso', nombre: 'Uso', v: g.uso, u: '%' },
    { id: 'vent', nombre: 'Ventilador', v: g.ventilador ?? null, u: '%' },
    { id: 'w', nombre: 'Consumo', v: g.watios, u: 'W' },
    { id: 'rn', nombre: 'Reloj del núcleo', v: g.relojNucleo ?? null, u: 'MHz' },
    { id: 'rm', nombre: 'Reloj de la memoria', v: g.relojMemoria ?? null, u: 'MHz' },
    { id: 'vram', nombre: 'Memoria de vídeo usada', v: g.vramUsadaMb ?? null, u: 'MB' }
  ]
}

/**
 * Panel de estadísticas en vivo: procesador, gráfica, memoria y disco del sistema, más la curva de los últimos minutos.
 * Lo que el equipo no informa (temperatura del procesador, gráficas que no son NVIDIA) se dice con una frase, no se inventa.
 */
export default function PanelRendimiento({ r, v }: { r: Resumen; v: Vivo | null }) {
  const [hist, setHist] = useState<Record<Clave, (number | null)[]>>({ cpu: [], ram: [], gpu: [] })
  const ultima = useRef<Vivo | null>(null)
  const [rangos, setRangos] = useState<Record<string, Rango>>({})

  useEffect(() => {
    if (!v || ultima.current === v) return
    ultima.current = v
    const ramPct = v.ramGb > 0 ? (v.ramUsadaGb / v.ramGb) * 100 : 0
    if (v.gpu) setRangos((r) => { const n = { ...r }; for (const l of lecturas(v.gpu!)) if (l.v !== null) n[l.id] = n[l.id] ? { min: Math.min(n[l.id].min, l.v), max: Math.max(n[l.id].max, l.v) } : { min: l.v, max: l.v }; return n })
    setHist((h) => ({ cpu: [...h.cpu, v.cpu].slice(-MUESTRAS), ram: [...h.ram, Math.round(ramPct)].slice(-MUESTRAS), gpu: [...h.gpu, v.gpu ? v.gpu.uso : null].slice(-MUESTRAS) }))
  }, [v])

  const ramPct = v && v.ramGb > 0 ? Math.round((v.ramUsadaGb / v.ramGb) * 100) : null
  const sis = r.volumenes.filter((x) => x.totalGb > 0).sort((a, b) => (a.letra.toUpperCase() === 'C' ? -1 : b.letra.toUpperCase() === 'C' ? 1 : a.letra.localeCompare(b.letra)))[0]
  const discoPct = sis ? Math.round(((sis.totalGb - sis.libreGb) / sis.totalGb) * 100) : null
  const gpu = v?.gpu ?? null
  const nombreGpu = (r.graficas ?? [])[0]?.nombre
  const hayGpu = hist.gpu.some((x) => x !== null)

  const traza = (datos: (number | null)[]) => {
    const n = datos.length
    if (n < 2) return ''
    const dx = 100 / (MUESTRAS - 1), x0 = 100 - (n - 1) * dx   // la curva entra por la derecha, como en un monitor
    return datos.map((d, i) => (d === null ? null : `${(x0 + i * dx).toFixed(2)},${(40 - (Math.max(0, Math.min(100, d)) / 100) * 40).toFixed(2)}`)).filter(Boolean).map((p, i) => `${i ? 'L' : 'M'}${p}`).join(' ')
  }
  const resumenGrafica = `Últimos minutos: procesador ${v?.cpu ?? '–'} %, memoria ${ramPct ?? '–'} %${hayGpu && gpu ? `, gráfica ${gpu.uso} %` : ''}.`

  return (
    <section className="bloque rend" aria-label="Estadísticas en vivo del equipo">
      <h2>En vivo</h2>
      <div className="rend-fichas">
        <Ficha titulo="Procesador" pct={v ? v.cpu : null} etiqueta="Uso del procesador">
          <span className="sub">{r.nucleos} núcleos · {r.hilos} hilos</span>
          <span className="sub num" title={v?.cpuMotivo || undefined}>{v?.cpuTemp != null ? `Temperatura: ${v.cpuTemp} °C` : v?.cpuMotivo ? 'Temperatura: no disponible en este equipo' : 'Temperatura: leyendo…'}</span>
        </Ficha>
        <Ficha titulo="Gráfica" pct={gpu ? gpu.uso : null} etiqueta="Uso de la gráfica">
          <span className="sub">{nombreGpu ?? 'Sin gráfica detectada'}</span>
          <span className="sub num">{gpu ? [gpu.temp !== null ? `${gpu.temp} °C` : '', gpu.watios !== null ? `${gpu.watios} W` : ''].filter(Boolean).join(' · ') || 'En marcha' : 'Uso y temperatura: solo con NVIDIA'}</span>
        </Ficha>
        <Ficha titulo="Memoria" pct={ramPct} etiqueta="Memoria en uso">
          <span className="sub num">{v ? `${numero(v.ramUsadaGb)} de ${numero(v.ramGb)} GB` : '–'}</span>
          <span className="sub">En uso ahora</span>
        </Ficha>
        <Ficha titulo={sis ? `Disco ${sis.letra}:` : 'Disco'} pct={discoPct} etiqueta="Espacio usado del disco del sistema" umbral={UMBRAL_DISCO}>
          <span className="sub num">{sis ? `${numero(sis.libreGb, 0)} GB libres` : 'Sin unidad medible'}</span>
          <span className="sub num">{sis ? `de ${numero(sis.totalGb, 0)} GB` : ''}</span>
        </Ficha>
      </div>
      <div className="rend-grafica">
        <div className="rend-leyenda">
          {SERIES.filter((s) => s.clave !== 'gpu' || hayGpu).map((s) => (
            <span key={s.clave} className={`ley ${s.clave}`}><svg width="22" height="6" aria-hidden="true"><line x1="0" y1="3" x2="22" y2="3" strokeDasharray={s.trazo} /></svg>{s.nombre}</span>
          ))}
          <span className="sub">Últimos 5 minutos</span>
        </div>
        <svg className="rend-curvas" viewBox="0 0 100 40" preserveAspectRatio="none" role="img" aria-label={resumenGrafica}>
          {[10, 20, 30].map((y) => <line key={y} className="guia" x1="0" x2="100" y1={y} y2={y} />)}
          {SERIES.filter((s) => s.clave !== 'gpu' || hayGpu).map((s) => <path key={s.clave} className={`curva ${s.clave}`} d={traza(hist[s.clave])} strokeDasharray={s.trazo} vectorEffect="non-scaling-stroke" />)}
        </svg>
        <div className="rend-eje" aria-hidden="true"><span>100 %</span><span>50 %</span><span>0 %</span></div>
      </div>
      {gpu && (
        <details className="rend-sensores">
          <summary>Sensores de la gráfica (solo lectura)</summary>
          <table aria-label="Lecturas de la gráfica: valor actual, mínimo y máximo desde que se abrió la app">
            <thead><tr><th scope="col">Sensor</th><th scope="col">Ahora</th><th scope="col">Mín.</th><th scope="col">Máx.</th></tr></thead>
            <tbody>
              {lecturas(gpu).filter((l) => l.v !== null).map((l) => (
                <tr key={l.id}><th scope="row">{l.nombre}</th><td className="num">{l.v} {l.u}</td><td className="num">{rangos[l.id]?.min ?? '–'} {l.u}</td><td className="num">{rangos[l.id]?.max ?? '–'} {l.u}</td></tr>
              ))}
            </tbody>
          </table>
          {gpu.ventilador == null && <p className="nota-vacia">Ventilador: este equipo no informa su velocidad (es lo normal en portátiles y en algunas gráficas).</p>}
          <p className="nota-vacia">Mín. y máx. son desde que abriste la app. La temperatura del procesador solo se lee si Windows la informa; no se instala ningún controlador extra.</p>
        </details>
      )}
    </section>
  )
}
