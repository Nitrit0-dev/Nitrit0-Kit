import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react'
import { notaSalud } from './componentes/Basicos'
import type { Dx, Elemento, EstadoPrueba } from './tipos'

export type EstadoPaso = 'espera' | 'curso' | 'ok' | 'aviso' | 'fallo' | 'noeval'
export type Marca = 'bien' | 'mal' | 'omitido'
export interface PasoRev { id: 'diag' | 'gpu' | 'cpu'; titulo: string; estado: EstadoPaso; texto: string; pct: number }
export interface RevTotal { modo: 'chequeo' | 'fondo'; fase: 'pasos' | 'manual' | 'fin'; pasos: PasoRev[]; paso: number; manual: Record<string, Marca>; t0: number; parada: boolean }
export interface Area { nombre: string; estado: 'ok' | 'aviso' | 'fallo' | 'noeval'; detalle: string }

/** Mientras hay una revisión en marcha, el diagnóstico que lanza no debe llevarse la pantalla a «Diagnóstico». */
export const revisionActiva = { actual: false }

const TITULO_GPU = 'Placa de vídeo (GPU)', TITULO_CPU = 'Prueba de procesador'
const PASOS = {
  chequeo: [{ id: 'diag', titulo: 'Diagnóstico rápido (17 pruebas)' }, { id: 'gpu', titulo: 'Placa de vídeo (1 min)' }, { id: 'cpu', titulo: 'Procesador (30 s)' }],
  fondo: [{ id: 'diag', titulo: 'Diagnóstico profundo (22 pruebas)' }, { id: 'cpu', titulo: 'Procesador (5 min)' }, { id: 'gpu', titulo: 'Placa de vídeo (5 min)' }]
} as const
const OPCIONES: Record<string, Record<string, number>> = {
  'chequeo:gpu': { duracionSeg: 60, memMB: 1024 }, 'chequeo:cpu': { hilos: navigator.hardwareConcurrency || 4, duracionSeg: 30 },
  'fondo:gpu': { duracionSeg: 300, memMB: 1024 }, 'fondo:cpu': { hilos: navigator.hardwareConcurrency || 4, duracionSeg: 300 }
}
const peor = (a: Area['estado'], b: Area['estado']): Area['estado'] => { const o = ['ok', 'noeval', 'aviso', 'fallo'] as const; return o.indexOf(a) >= o.indexOf(b) ? a : b }
const DE_PRUEBA: Record<EstadoPrueba, Area['estado']> = { OK: 'ok', Info: 'ok', Aviso: 'aviso', Fallo: 'fallo' }

/** Resumen de la revisión: semáforo por área, nota y texto para copiar. Lo que no se pudo evaluar no resta. */
export function resumenRevision(rev: RevTotal, dx: Dx | null, manual: Elemento[]) {
  const areas: Area[] = []
  let fallos = 0, avisos = 0
  if (dx) {
    const grupos = new Map<string, Area>()
    for (const p of dx.plan) {
      const r = dx.resultados[p.id]; if (!r) continue
      const est = DE_PRUEBA[r.estado]
      if (est === 'fallo') fallos++; else if (est === 'aviso') avisos++
      const a = grupos.get(p.grupo) ?? { nombre: p.grupo, estado: 'ok' as const, detalle: '' }
      a.estado = peor(a.estado, est)
      if (est !== 'ok') a.detalle += `${a.detalle ? ' · ' : ''}${p.nombre}: ${r.resumen}`
      grupos.set(p.grupo, a)
    }
    areas.push(...grupos.values())
  }
  for (const p of rev.pasos) {
    if (p.id === 'diag') continue
    const est: Area['estado'] = p.estado === 'ok' ? 'ok' : p.estado === 'aviso' ? 'aviso' : p.estado === 'fallo' ? 'fallo' : 'noeval'
    if (est === 'fallo') fallos++; else if (est === 'aviso') avisos++
    areas.push({ nombre: p.id === 'gpu' ? 'Placa de vídeo (prueba de carga)' : 'Procesador (prueba de carga)', estado: est, detalle: p.texto })
  }
  if (manual.length) {
    const marcas = manual.map((e) => rev.manual[e.id] ?? 'omitido'), mal = manual.filter((e, i) => marcas[i] === 'mal')
    fallos += mal.length
    areas.push({ nombre: 'Periféricos (comprobación manual)', estado: mal.length ? 'fallo' : marcas.every((m) => m === 'omitido') ? 'noeval' : 'ok',
      detalle: mal.length ? `Mal: ${mal.map((e) => e.titulo).join(', ')}` : `${marcas.filter((m) => m === 'bien').length} de ${manual.length} comprobados` })
  }
  const nota = notaSalud(fallos, avisos)
  const ET = { ok: 'OK', aviso: 'AVISO', fallo: 'FALLO', noeval: 'NO EVALUADO' }
  const texto = [`REVISIÓN TOTAL (${rev.modo === 'chequeo' ? 'chequeo de salud' : 'a fondo'}) ${new Date().toLocaleString('es-ES')}`, `Salud: ${nota}/100 · ${fallos} fallo(s), ${avisos} aviso(s)`, '',
    ...areas.map((a) => `[${ET[a.estado]}] ${a.nombre}${a.detalle ? ': ' + a.detalle : ''}`)].join('\n')
  return { areas, fallos, avisos, nota, texto }
}

export function useRevisionTotal(p: { dx: Dx | null; elementos: Elemento[]; empezarDx: (m: 'Rapido' | 'Completo') => Promise<void> }): {
  rev: RevTotal | null; marco: ReactNode; iniciar: (m: 'chequeo' | 'fondo') => void; detener: () => void; marcar: (id: string, m: Marca) => void; terminarManual: () => void; reiniciar: () => void
} {
  const [rev, setRev] = useState<RevTotal | null>(null)
  const [url, setUrl] = useState<string | null>(null)
  const ref = useRef<HTMLIFrameElement>(null)
  const revRef = useRef<RevTotal | null>(null); revRef.current = rev
  const pRef = useRef(p); pRef.current = p   // siempre lo último: el catálogo puede llegar después de crear el hook
  const arrancarRef = useRef<(i: number, r: RevTotal) => Promise<void>>(async () => undefined)
  const esperaDx = useRef(false), opcionesMarco = useRef<Record<string, number>>({})
  const parche = useCallback((i: number, c: Partial<PasoRev>) => setRev((r) => (r ? { ...r, pasos: r.pasos.map((x, k) => (k === i ? { ...x, ...c } : x)) } : r)), [])

  const siguiente = useCallback((i: number) => {
    const r = revRef.current; if (!r) return
    if (r.parada) { setRev((q) => (q ? { ...q, fase: 'fin', pasos: q.pasos.map((x, k) => (k > i && x.estado === 'espera' ? { ...x, estado: 'noeval', texto: 'No se hizo: revisión detenida.' } : x)) } : q)); revisionActiva.actual = false; return }
    if (i + 1 < r.pasos.length) { setRev((q) => (q ? { ...q, paso: i + 1 } : q)); void arrancarRef.current(i + 1, r) }
    else { revisionActiva.actual = false; setRev((q) => (q ? { ...q, fase: 'manual' } : q)) }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const arrancar = async (i: number, r: RevTotal) => {
    const paso = r.pasos[i]; parche(i, { estado: 'curso', texto: 'Empezando…', pct: 0 })
    if (paso.id === 'diag') {
      esperaDx.current = true
      await pRef.current.empezarDx(r.modo === 'chequeo' ? 'Rapido' : 'Completo')
      setTimeout(() => { if (esperaDx.current && revRef.current?.paso === i && revRef.current.pasos[i].estado === 'curso') { esperaDx.current = false; parche(i, { estado: 'noeval', texto: 'No se pudo arrancar el diagnóstico (¿hay otra cosa en marcha?).' }); siguiente(i) } }, 10000)
      return
    }
    const el = pRef.current.elementos.find((e) => e.titulo === (paso.id === 'gpu' ? TITULO_GPU : TITULO_CPU))
    const u = el ? await window.kit.pruebaUrl(el.id).catch(() => null) : null
    if (!u?.ok || !u.url) { parche(i, { estado: 'noeval', texto: u?.mensaje || (el ? 'No se pudo abrir la prueba.' : 'Esta prueba no está disponible en este pack.') }); siguiente(i); return }
    opcionesMarco.current = OPCIONES[`${r.modo}:${paso.id}`]; setUrl(u.url)
  }

  arrancarRef.current = arrancar

  // Fin del diagnóstico: se espera a ver el estado nuevo (sin «fin») antes de fiarse de un «fin»: el anterior seguiría ahí
  useEffect(() => {
    const r = rev, d = p.dx; if (!r || r.fase !== 'pasos') return
    const i = r.paso, paso = r.pasos[i]; if (paso?.id !== 'diag' || paso.estado !== 'curso' || !d) return
    if (!d.fin) { esperaDx.current = false; const hechos = Object.keys(d.resultados).length; parche(i, { pct: d.plan.length ? Math.round((hechos / d.plan.length) * 100) : 0, texto: `${hechos} de ${d.plan.length || '…'} pruebas` }); return }
    if (esperaDx.current) return
    const f = d.fin
    parche(i, { pct: 100, estado: f.interrumpido ? 'noeval' : f.fallos ? 'fallo' : f.avisos ? 'aviso' : 'ok',
      texto: f.interrumpido ? `Detenido: ${f.motivo ?? 'sin terminar'}` : f.fallos || f.avisos ? `${f.fallos} fallo(s) y ${f.avisos} aviso(s)` : 'Todo correcto' })
    siguiente(i)
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [p.dx])

  // Mensajes del marco oculto (Prueba_GPU / Prueba_CPU): listo -> arrancar; progreso; resultado
  useEffect(() => {
    const alMensaje = (e: MessageEvent) => {
      const m = e.data as { nit?: string; pct?: number; estado?: string; resultado?: { tipo?: string; titulo?: string; texto?: string } } | null
      if (!ref.current || e.source !== ref.current.contentWindow || !m || typeof m.nit !== 'string') return
      const r = revRef.current; if (!r) return
      if (m.nit === 'listo') ref.current.contentWindow?.postMessage({ nit: 'arrancar', opciones: opcionesMarco.current }, '*')
      else if (m.nit === 'progreso') parche(r.paso, { pct: Math.round(Number(m.pct) || 0), texto: String(m.estado ?? '').slice(0, 80) })
      else if (m.nit === 'resultado') {
        const x = m.resultado ?? {}, est: EstadoPaso = x.tipo === 'pasa' ? (/aviso/i.test(String(x.titulo)) ? 'aviso' : 'ok') : x.tipo === 'falla' ? 'fallo' : 'noeval'
        parche(r.paso, { estado: est, pct: 100, texto: String(x.texto ?? '').slice(0, 260) })
        setUrl(null); siguiente(r.paso)
      }
    }
    window.addEventListener('message', alMensaje)
    return () => window.removeEventListener('message', alMensaje)
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // El marco oculto cuenta como prueba abierta mientras exista (también si se cancela la revisión a medias): entrar/salir van siempre por parejas
  useEffect(() => { if (!url) return; void window.kit.pruebaEntrar(); return () => { void window.kit.pruebaSalir() } }, [url])

  const iniciar = (modo: 'chequeo' | 'fondo') => {
    const r: RevTotal = { modo, fase: 'pasos', paso: 0, manual: {}, t0: Date.now(), parada: false, pasos: PASOS[modo].map((x) => ({ ...x, estado: 'espera', texto: '', pct: 0 })) }
    revisionActiva.actual = true; revRef.current = r; setRev(r); void arrancarRef.current(0, r)
  }
  const detener = () => {
    const r = revRef.current; if (!r || r.fase !== 'pasos') return
    const parada = { ...r, parada: true }; revRef.current = parada; setRev(parada)
    const paso = r.pasos[r.paso]
    if (paso.id === 'diag') void window.kit.cancelar()
    else if (ref.current) ref.current.contentWindow?.postMessage({ nit: 'detener' }, '*')
  }
  const marcar = (id: string, m: Marca) => setRev((r) => (r ? { ...r, manual: { ...r.manual, [id]: m } } : r))
  const terminarManual = () => setRev((r) => (r ? { ...r, fase: 'fin' } : r))
  const reiniciar = () => { revisionActiva.actual = false; esperaDx.current = false; setUrl(null); setRev(null) }

  const marco = url ? <iframe ref={ref} title="Prueba en curso" src={url} sandbox="allow-scripts allow-same-origin" allow="camera *; microphone *; fullscreen *; gamepad *" tabIndex={-1} aria-hidden="true"
    style={{ position: 'fixed', left: -10000, top: 0, width: 800, height: 600, border: 0 }} /> : null
  return { rev, marco, iniciar, detener, marcar, terminarManual, reiniciar }
}
