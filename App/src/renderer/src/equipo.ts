import type { Resumen } from './tipos'

// La lectura del equipo (WMI) tarda unos segundos: se conserva la última y las pantallas que la piden a la vez comparten una sola lectura.
export const REFRESCO_MS = 60_000
let enCurso: Promise<Resumen> | null = null
const CLAVE_CACHE = 'nitrit0.resumen'

/** Resumen_Sistema.ps1 ignora errores de WMI: un equipo dañado puede devolver campos vacíos, y no deben tumbar la pantalla. */
const limpio = (x: Resumen): Resumen => ({ ...x, cpu: String(x.cpu ?? ''), windows: String(x.windows ?? ''), modelo: String(x.modelo ?? ''), bios: String(x.bios ?? ''), discos: x.discos ?? [], volumenes: x.volumenes ?? [] })
// La primera lectura (WMI) tarda 5-8 s: la de la sesión anterior se enseña de inmediato (hora 0 = caducada, así que se refresca detrás). Vive en la caché de la app en %TEMP% de ESTE equipo.
let ultimo: { r: Resumen; hora: number } | null = (() => { try { const x = JSON.parse(localStorage.getItem(CLAVE_CACHE) ?? 'null'); return x && typeof x.equipo === 'string' ? { r: limpio(x as Resumen), hora: 0 } : null } catch { return null } })()

export const resumenGuardado = (): Resumen | null => ultimo?.r ?? null
export const resumenCaducado = (): boolean => !ultimo || Date.now() - ultimo.hora > REFRESCO_MS
export function leerResumen(): Promise<Resumen> {
  if (!enCurso) {
    enCurso = (window.kit.resumen() as Promise<Resumen>)
      .then((x) => { const r = limpio(x); ultimo = { r, hora: Date.now() }; try { localStorage.setItem(CLAVE_CACHE, JSON.stringify(r)) } catch { /* sin caché: solo se pierde la mejora de arranque */ } return r })
      .finally(() => { enCurso = null })
  }
  return enCurso
}

export const numero = (n: number, dec = 1) => n.toLocaleString('es-ES', { minimumFractionDigits: 0, maximumFractionDigits: dec })
export const diasEncendido = (r: Resumen) => (r.arranque ? (Date.now() - new Date(r.arranque).getTime()) / 864e5 : NaN)
