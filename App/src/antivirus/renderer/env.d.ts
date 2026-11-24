/// <reference types="vite/client" />
import type { AntivirusApi } from '../preload'

declare global {
  interface Window { antivirus: AntivirusApi }
}
