/// <reference types="vite/client" />
import type { LimpiezaApi } from '../preload'

declare global {
  interface Window { limpieza: LimpiezaApi }
}
