/// <reference types="vite/client" />
import type { ClonadorApi } from '../preload'

declare global {
  interface Window { clonador: ClonadorApi }
}
