// Bichobit: la criatura del equipo, un ordenador de sobremesa en pixel art sobre una rejilla de 20x20.
// Cada pieza del cuerpo es una comprobación y su color cuenta cómo salió. Sin dependencias, para poder probarlo en Node.

export type Estado = 'sin' | 'bien' | 'mal' | 'arreglado'
// cara = pantalla, ojos = memoria, voz = sonido, corazon = led de encendido (procesador), barriga = teclado (disco),
// manos = ratón, antenas = red, aura = temperatura
export type Pieza = 'cara' | 'ojos' | 'corazon' | 'barriga' | 'manos' | 'voz' | 'antenas' | 'aura'
export type Etapa = 0 | 1 | 2 | 3   // cría, joven, adulta, superbit (dorado)
export type Piezas = Partial<Record<Pieza, Estado>>
export type Pixel = { x: number; y: number; c: string }

export const PIEZAS: Pieza[] = ['cara', 'ojos', 'corazon', 'barriga', 'manos', 'voz', 'antenas', 'aura']
export const NOMBRE_ETAPA = ['Cría', 'Joven', 'Adulta', 'Superbit']

// X contorno, s carcasa, p pupila, b botón de encendido; el resto de letras son piezas (ver PIEZA_DE)
const CUERPO = [
  '....a..........a....',
  '...XXXXXXXXXXXXXX...',
  '...XssssssssssssX...',
  '...XsXXXXXXXXXXsX...',
  '...XsXcOOccOOcXsX...',
  '...XsXcOpccOpcXsX...',
  '...XsXccccccccXsX...',
  '...XsXccmmmmccXsX...',
  '...XsXccccccccXsX...',
  '...XsXXXXXXXXXXsX...',
  '...XsssggssssbbsX...',
  '...XXXXXXXXXXXXXX...',
  '.........XX.........',
  '.......XXXXXX.......',
  '.XXXXXXXXXXXXXX.XXX.',
  '.XkkSkkSkkSkkSX.XrX.',
  '.XSkkSkkSkkSkkX.XrX.',
  '.XXXXXXXXXXXXXX.XXX.',
  '....................',
  '....................',
]

const COLOR: Record<string, Record<Estado, string>> = {
  c: { sin: '#3b4552', bien: '#22d3ee', mal: '#ef4444', arreglado: '#34d399' },
  O: { sin: '#6b7280', bien: '#ffffff', mal: '#fecaca', arreglado: '#d1fae5' },
  g: { sin: '#4b5563', bien: '#4ade80', mal: '#dc2626', arreglado: '#fbbf24' },
  k: { sin: '#c9c3b0', bien: '#f4efe0', mal: '#d6a77a', arreglado: '#d9f99d' },
  S: { sin: '#9c967f', bien: '#b8ad8c', mal: '#a8744a', arreglado: '#a3c96b' },
  r: { sin: '#9c967f', bien: '#67e8f9', mal: '#a16207', arreglado: '#86efac' },
  m: { sin: '#2a313c', bien: '#334155', mal: '#7f1d1d', arreglado: '#0f766e' },
  a: { sin: '#4b5563', bien: '#a5f3fc', mal: '#b45309', arreglado: '#a7f3d0' },
}
const PIEZA_DE: Record<string, Pieza> = { c: 'cara', O: 'ojos', g: 'corazon', k: 'barriga', S: 'barriga', r: 'manos', m: 'voz', a: 'antenas' }
const AURA: Record<Estado, string> = { sin: '#1f2630', bien: '#164e63', mal: '#7f1d1d', arreglado: '#14532d' }
const FIJO: Record<string, string> = { X: '#0b1117', s: '#e7dfc8', p: '#0b1117', b: '#fb923c' }
const ORO: Record<string, string> = { X: '#78350f', s: '#fbbf24', p: '#ffffff', b: '#ef4444', c: '#fde047', O: '#ffffff', g: '#f97316', k: '#fcd34d', S: '#f59e0b', r: '#fcd34d', m: '#b45309', a: '#fef08a' }

// Lista de píxeles con su color. La etapa decide qué partes del cuerpo han salido ya:
// cría = monitor; joven = peana y teclado; adulta = ratón y antenas; superbit = todo en oro con corona.
export function pintar(etapa: Etapa, piezas: Piezas): Pixel[] {
  const px: Pixel[] = []
  const est = (p: Pieza): Estado => piezas[p] ?? 'sin'
  const oro = etapa === 3
  CUERPO.forEach((fila, y) => {
    if (fila.length !== 20) throw new Error(`Fila ${y} del cuerpo mide ${fila.length}, debe medir 20`)
    ;[...fila].forEach((ch, x) => {
      if (ch === '.') return
      if (etapa < 1 && y >= 12) return
      if (etapa < 2 && (ch === 'r' || ch === 'a' || (y >= 14 && x >= 16))) return   // ratón con su contorno
      let c: string
      if (oro) c = ORO[ch]
      else if (FIJO[ch]) c = FIJO[ch]
      else c = COLOR[ch][est(PIEZA_DE[ch])]
      px.push({ x, y, c })
    })
  })
  // Aura: píxeles sueltos alrededor, que se encienden según la temperatura
  const huecos: [number, number][] = [[0, 3], [1, 6], [0, 9], [19, 3], [18, 7], [19, 10], [0, 15], [19, 12], [3, 13]]
  const ca = oro ? '#a16207' : AURA[est('aura')]
  huecos.forEach(([x, y]) => { if (etapa >= 1 || y < 12) px.push({ x, y, c: ca }) })
  // Corona del Superbit, sobre las antenas
  if (oro) [[8, 0], [10, 0], [9, 0]].forEach(([x, y]) => px.push({ x, y, c: '#fde047' }))
  return px
}

type AreaRev = { nombre: string; estado: 'ok' | 'aviso' | 'fallo' | 'noeval'; detalle: string }
const DE_AREA: Record<AreaRev['estado'], Estado> = { ok: 'bien', aviso: 'mal', fallo: 'mal', noeval: 'sin' }
const PEOR: Estado[] = ['sin', 'bien', 'mal']   // lo que está mal manda sobre lo que está bien

// Qué pieza del cuerpo corresponde a cada área de la revisión (por el nombre del grupo del diagnóstico)
const PIEZA_AREA: [RegExp, Pieza][] = [
  [/procesador/i, 'corazon'], [/memoria/i, 'ojos'], [/almacenamiento|disco/i, 'barriga'], [/gr[aá]fic|gpu|v[ií]deo|pantalla/i, 'cara'],
  [/\bred(es)?\b/i, 'antenas'], [/dispositivos|perif[eé]ricos/i, 'manos'],
]

export function piezasDeAreas(areas: AreaRev[]): Piezas {
  const out: Piezas = {}
  const poner = (p: Pieza, e: Estado) => { const a = out[p]; if (!a || PEOR.indexOf(e) > PEOR.indexOf(a)) out[p] = e }
  for (const a of areas) {
    const destino = PIEZA_AREA.find(([re]) => re.test(a.nombre))
    if (destino) poner(destino[1], DE_AREA[a.estado])
    // Los registros de Windows hablan de disco y de apagados inesperados: cuentan contra la barriga (disco) y el corazón (energía)
    if (/registros/i.test(a.nombre) && a.estado !== 'ok' && a.estado !== 'noeval') {
        if (/disco|sistema de archivos/i.test(a.detalle)) poner('barriga', 'mal')
        if (/apagado|cuelgue/i.test(a.detalle)) poner('corazon', 'mal')
    }
    const malo = a.estado === 'aviso' || a.estado === 'fallo'   // un área sana que nombra el audio o la temperatura no cuenta contra la pieza
    if (malo && /sonido|audio|altavoz/i.test(a.nombre + ' ' + a.detalle)) poner('voz', 'mal')
    if (malo && /temperatur|calor|t[eé]rmic|sobrecalent/i.test(a.nombre + ' ' + a.detalle)) poner('aura', 'mal')
  }
  // Sin avisos de calor, el aura queda bien una vez evaluado el procesador; la voz, bien si se comprobaron los periféricos
  if (!out.aura && out.corazon && out.corazon !== 'sin') out.aura = 'bien'
  if (!out.voz && out.manos && out.manos !== 'sin') out.voz = out.manos === 'bien' ? 'bien' : 'sin'
  return out
}

// Última criatura de cada equipo, en el almacenamiento local de la app (no escribe en el pendrive)
export type Guardada = { etapa: Etapa; piezas: Piezas; fecha: number; arreglado?: boolean; entregado?: boolean }
const clave = (equipo: string) => `bichobit:${equipo.toLowerCase()}`   // COMPUTERNAME y hostname pueden diferir en mayúsculas
export function guardarCriatura(equipo: string, g: Guardada): void {
  const texto = JSON.stringify(g)
  try { localStorage.setItem(clave(equipo), texto) } catch { /* sin almacenamiento: no pasa nada */ }
  try { void window.kit?.criaturaGuardar(equipo, texto).catch(() => undefined) } catch { /* fuera de la app (pruebas en Node) */ }   // copia en Datos\Pasaporte del pack personal
}
// Si el almacenamiento local se vació (Limpiar temporales lo hace), recupera la criatura de la copia del pendrive. Devuelve true si la trajo.
export async function restaurarCriatura(equipo: string): Promise<boolean> {
  try {
    if (localStorage.getItem(clave(equipo))) return false
    const texto = await window.kit?.criaturaLeer(equipo); if (!texto) return false
    localStorage.setItem(clave(equipo), texto)
    return leerCriatura(equipo) !== null
  } catch { return false }
}
export function leerCriatura(equipo: string): Guardada | null {
  try {
    const t = localStorage.getItem(clave(equipo)); if (!t) return null
    const g = JSON.parse(t) as Guardada
    const estados: string[] = ['sin', 'bien', 'mal', 'arreglado']
    const valida = g && [0, 1, 2, 3].includes(g.etapa) && g.piezas && typeof g.piezas === 'object' && !Array.isArray(g.piezas) && Object.values(g.piezas).every((e) => estados.includes(e as string))
    return valida ? g : null
  } catch { return null }
}

// Etapa que muestra la criatura guardada: la de la revisión, adulta si ya se arregló algo y Superbit si se entregó sin nada en rojo
export function etapaGuardada(g: Guardada): Etapa {
  const estados = Object.values(g.piezas)
  const medida = estados.some((e) => e === 'bien' || e === 'arreglado')   // sin ninguna pieza medida no hay nada que premiar
  if (g.entregado && medida && !estados.includes('mal')) return 3
  if (g.arreglado || g.entregado) return Math.max(g.etapa, 2) as Etapa
  return g.etapa
}
// Anota que se hizo un arreglo o una entrega en este equipo. Tras arreglar, lo que estaba mal pasa a «arreglado»,
// salvo el disco (un fallo de disco no se arregla con un script); una revisión nueva lo vuelve a medir todo.
export function anotarHito(equipo: string, hito: 'arreglado' | 'entregado'): void {
  const g = leerCriatura(equipo); if (!g) return
  const piezas: Piezas = { ...g.piezas }
  if (hito === 'arreglado') for (const p of PIEZAS) if (piezas[p] === 'mal' && p !== 'barriga') piezas[p] = 'arreglado'
  guardarCriatura(equipo, { ...g, piezas, [hito]: true })
}
// Etapa que le toca según los pasos hechos del recorrido (0 a 4) y si todo salió bien
export function etapaDe(pasos: number, todoBien: boolean): Etapa {
  if (pasos >= 4 && todoBien) return 3
  return Math.max(0, Math.min(2, pasos - 1)) as Etapa
}

const PIEZA_TEXTO: Record<Pieza, string> = { cara: 'pantalla', ojos: 'memoria', corazon: 'procesador', barriga: 'disco', manos: 'periféricos', voz: 'sonido', antenas: 'red', aura: 'temperatura' }
// Texto para lectores de pantalla y para quien no distingue los colores: la etapa y las piezas con problemas
export function describir(etapa: Etapa, piezas: Piezas): string {
  const mal = PIEZAS.filter((p) => piezas[p] === 'mal').map((p) => PIEZA_TEXTO[p])
  return `Bichobit, ${NOMBRE_ETAPA[etapa].toLowerCase()}. ${mal.length ? `Con problemas: ${mal.join(', ')}.` : 'Sin problemas en lo medido.'}`
}
export function aSvg(etapa: Etapa, piezas: Piezas, escala = 12): string {
  const r = pintar(etapa, piezas).map((p) => `<rect x="${p.x}" y="${p.y}" width="1" height="1" fill="${p.c}"/>`).join('')
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" width="${20 * escala}" height="${20 * escala}" shape-rendering="crispEdges" role="img" aria-label="${describir(etapa, piezas)}">${r}</svg>`
}
