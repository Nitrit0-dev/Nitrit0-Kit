import { contextBridge, ipcRenderer } from 'electron'

export interface Disco { Numero: number; Nombre: string; GB: number; Estilo: string; Sistema: boolean; Kit: boolean; Serie: string; Id: string; Bus: string; USB: boolean; TieneWindows: boolean; Letras: string }
export interface Peticion { extra?: 'Windows' | 'Datos'; op: 'listar' | 'simular' | 'ejecutar' | 'limpiar'; origen?: number; destino?: number; origenId?: string; destinoId?: string; carpeta?: string; confirmo?: string }
export interface Fin { op: string; codigo: number | null; cancelado: boolean }

const suscribir = <T,>(canal: string, cb: (v: T) => void) => { const f = (_e: unknown, v: T) => cb(v); ipcRenderer.on(canal, f); return () => { ipcRenderer.removeListener(canal, f) } }

const api = {
  estado: (): Promise<{ tema: 'oscuro' | 'claro' | 'sistema'; hayScript: boolean; kit: boolean }> => ipcRenderer.invoke('estado'),
  correr: (p: Peticion): Promise<{ ok: boolean; mensaje: string }> => ipcRenderer.invoke('correr', p),
  cancelar: (): Promise<void> => ipcRenderer.invoke('cancelar'),
  carpeta: (): Promise<string> => ipcRenderer.invoke('carpeta'),
  guardarRegistro: (lineas: string[]): Promise<string> => ipcRenderer.invoke('guardarRegistro', lineas),
  alLinea: (cb: (l: string) => void) => suscribir<string>('clon:linea', cb),
  alDiscos: (cb: (d: Disco[]) => void) => suscribir<Disco[]>('clon:discos', cb),
  alFase: (cb: (n: number) => void) => suscribir<number>('clon:fase', cb),
  alFin: (cb: (f: Fin) => void) => suscribir<Fin>('clon:fin', cb)
}
contextBridge.exposeInMainWorld('clonador', api)
export type ClonadorApi = typeof api
