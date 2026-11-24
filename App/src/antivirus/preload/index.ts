import { contextBridge, ipcRenderer, webUtils } from 'electron'

export interface Hallazgo { motor: 'Defender' | 'ClamAV'; nombre: string; archivo: string }
export interface Defender { estado: 'limpio' | 'amenaza' | 'no-disponible'; amenaza?: string; detalle?: string; hallazgos?: Hallazgo[] }
export interface Clam { estado: 'limpio' | 'amenaza' | 'error'; amenaza?: string; detalle?: string; hallazgos?: Hallazgo[] }
export interface ResultadoCarpeta { ruta: string; defender: Defender; clam: Clam | null; hallazgos: Hallazgo[]; tono: 'ok' | 'aviso' | 'error'; titulo: string; detalle: string }
export interface Firma { estado: 'firmado' | 'sin-firma' | 'invalida' | 'no-confiable' | 'error'; firmante?: string }
export type VT = { estado: 'conocido'; malicioso: number; sospechoso: number; limpio: number; total: number; etiqueta?: string; fecha?: number } | { estado: 'desconocido' | 'sin-clave' | 'clave-invalida' | 'limite' | 'error'; detalle?: string }
export interface Version { archivo: string; producto: string; nombre: string; empresa: string }
export interface Resultado { ruta: string; tam: number; modificado: number; version: Version | null; sha256: string; defender: Defender; clam: Clam | null; firma: Firma | null; vt: VT; tono: 'ok' | 'aviso' | 'error'; titulo: string; detalle: string }

const api = {
  estado: (): Promise<{ tema: 'oscuro' | 'claro' | 'sistema'; clave: boolean; defender: boolean; clam: { fecha: string; dias: number } | null }> => ipcRenderer.invoke('estado'),
  elegir: (): Promise<string[]> => ipcRenderer.invoke('elegir'),
  analizar: (ruta: string): Promise<Resultado> => ipcRenderer.invoke('analizar', ruta),
  elegirCarpeta: (): Promise<string> => ipcRenderer.invoke('elegirCarpeta'),
  esCarpeta: (ruta: string): Promise<boolean> => ipcRenderer.invoke('esCarpeta', ruta),
  analizarCarpeta: (ruta: string): Promise<ResultadoCarpeta> => ipcRenderer.invoke('analizarCarpeta', ruta),
  guardarClave: (c: string): Promise<'ok' | 'formato' | 'sin-kit' | 'escritura'> => ipcRenderer.invoke('guardarClave', c),
  alFase: (cb: (t: string) => void) => { const f = (_e: unknown, t: string) => cb(t); ipcRenderer.on('fase', f); return () => { ipcRenderer.removeListener('fase', f) } },
  motores: (): Promise<{ defender: { activo: boolean; version: string; fecha: string; dias: number } | null; clam: { fecha: string; dias: number } | null; hayClam: boolean }> => ipcRenderer.invoke('motores'),
  actualizar: (motor: 'defender' | 'clam'): Promise<{ ok: boolean; mensaje: string }> => ipcRenderer.invoke('actualizar', motor),
  abrirClaveVT: (): Promise<void> => ipcRenderer.invoke('abrirClaveVT'),
  cancelar: (): Promise<void> => ipcRenderer.invoke('cancelar'),
  abrirVT: (hash: string): Promise<void> => ipcRenderer.invoke('abrirVT', hash),
  rutaDe: (f: File): string => webUtils.getPathForFile(f)
}
contextBridge.exposeInMainWorld('antivirus', api)
export type AntivirusApi = typeof api
