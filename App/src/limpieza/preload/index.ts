import { contextBridge, ipcRenderer } from 'electron'

const api = {
  motor: (op: 'Analizar' | 'Limpiar' | 'InicioListar' | 'InicioCambiar' | 'ProgramasListar' | 'DesinstalarFondo' | 'RegistroAnalizar' | 'RegistroLimpiar', params: { ids?: string[]; tipo?: string; id?: string; activar?: boolean; nombres?: string[]; modo?: 'Auto' | 'Manual' } = {}): Promise<{ ok: boolean; mensaje: string; codigo: number | null }> => ipcRenderer.invoke('motor', op, params),
  estado: (): Promise<{ tema: 'oscuro' | 'claro' | 'sistema'; kit: string; publico: boolean }> => ipcRenderer.invoke('estado'),
  cerrar: () => ipcRenderer.invoke('cerrar'),
  cancelarAnalisis: (): Promise<boolean> => ipcRenderer.invoke('cancelarAnalisis'),
  alEvento: (cb: (v: Record<string, unknown> & { op: string; evento: string }) => void) => {
    const f = (_e: unknown, v: Record<string, unknown> & { op: string; evento: string }) => cb(v)
    ipcRenderer.on('motor:evento', f)
    return () => { ipcRenderer.removeListener('motor:evento', f) }
  },
  alCerrando: (cb: () => void) => { const f = () => cb(); ipcRenderer.on('motor:cerrando', f); return () => { ipcRenderer.removeListener('motor:cerrando', f) } }
}
contextBridge.exposeInMainWorld('limpieza', api)
export type LimpiezaApi = typeof api
