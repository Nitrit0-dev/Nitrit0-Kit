import { describir, pintar, type Etapa, type Piezas } from './criatura'

// Pixel art en SVG: cada píxel es un cuadrado de la rejilla, sin suavizado
export function Bichobit({ etapa, piezas, escala = 10 }: { etapa: Etapa; piezas: Piezas; escala?: number }) {
  return (
    <svg viewBox="0 0 20 20" width={20 * escala} height={20 * escala} shapeRendering="crispEdges" role="img" aria-label={describir(etapa, piezas)}>
      {pintar(etapa, piezas).map((p) => <rect key={`${p.x}-${p.y}`} x={p.x} y={p.y} width={1} height={1} fill={p.c} />)}
    </svg>
  )
}
