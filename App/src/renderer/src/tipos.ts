import type { KitApi } from '../../preload'

declare global { interface Window { kit: KitApi } }

export type Tono = 'ok' | 'aviso' | 'error'
export interface Resultado { ok: boolean; mensaje: string }

export interface Elemento {
  id: string; titulo: string; descripcion: string; categoria: string; pagina: string; grupo: string; oculta: boolean
  peligro: boolean; publicoOk?: boolean; tipo: 'exe' | 'script' | 'run' | 'cmd' | 'html' | 'uri' | 'accion' | 'informe'
  accion: string | null; ayuda: string | null; icono: string | null; soportado: boolean; disponible: boolean
}
export interface Catalogo { paginas: Record<string, string[]>; soluciones: Record<string, string[]>; elementos: Elemento[] }

export interface Disco { nombre: string; tipo: string; gb: number; salud: string; estado: string }
export interface Volumen { letra: string; etiqueta: string; totalGb: number; libreGb: number }
export interface Resumen {
  equipo: string; modelo: string; cpu: string; nucleos: number; hilos: number; ramGb: number
  windows: string; version: string; arranque: string; bios: string; discos: Disco[]; volumenes: Volumen[]
  bateria: { carga: number; estado: number } | null
  biosFecha?: string; placa?: string; graficas?: { nombre: string; driver: string }[]; arquitectura?: string; instalado?: string; edicion?: string; compilacion?: string
}
export interface Vivo { cpu: number; cpuTemp?: number | null; cpuMotivo?: string; ramUsadaGb: number; ramGb: number; gpu?: { uso: number; temp: number | null; watios: number | null; ventilador?: number | null; relojNucleo?: number | null; relojMemoria?: number | null; vramUsadaMb?: number | null; vramTotalMb?: number | null } | null }
/** Un ajuste de Windows tal como lo devuelve Ajustes_Para_App.ps1: el estado actual, el de fábrica y el recomendado (null = cuestión de gusto). */
/** Si la app está elevada con otra cuenta de administrador, HKCU sería el de esa cuenta: Ajustes_Para_App.ps1 lo detecta y no aplica nada. */
export interface OtraCuenta { otra: boolean; proceso?: string; sesion?: string }
export interface AjusteInfo {
  id: string; grupo: string; titulo: string; descripcion: string; efecto: string; nota: string; tipo: 'interruptor' | 'lista'; activado: string
  opciones: { k: string; t: string; v: number }[]; def: string; rec: string | null; actual: string; raw: number | null
  ruta: string; nombre: string; tipoReg: string; aplicable: boolean; minBuild: number
}
export type IdPerfil = 'ahorro' | 'equilibrado' | 'juego'
export interface Estado { instalada?: boolean; hayInstalacion?: boolean; puedeInstalar?: boolean; memoriaAuto?: boolean; perfil?: IdPerfil | null; arranque?: boolean; preguntado?: boolean; admin: boolean; ocultarPeligro?: boolean; antivirus?: boolean; tema: 'oscuro' | 'claro' | 'sistema'; modo: 'sencillo' | 'tecnico'; ultima?: Ultima | null; favoritos: string[]; kit: string; zoom?: number }

/** Herramienta esperando en la cola de ejecución (se ejecuta al terminar la que está en marcha). */
export interface EnCola { id: string; titulo: string }

export interface Ejecucion {
  id: string; titulo: string; limite: number; lineas: string[]; aviso: string | null; t0: number; clase?: string
  progreso?: { actual: number; total: number; texto: string } | null   // barra de avance: lo emite el script con Write-Progreso (sin él, la barra es indeterminada)
  informe: { ruta: string; html: string } | null
  fin: null | { motivo: string; seg: number; correcto: boolean; cancelado?: boolean; registro: string | null }
}

/** Herramientas que ocupan el ejecutor de scripts: solo una a la vez. */
export const usaEjecutor = (e: Pick<Elemento, 'tipo'>) => e.tipo === 'script' || e.tipo === 'informe'

/** Qué hace el botón de una fila, según el tipo de herramienta. */
export const verbo = (e: Pick<Elemento, 'tipo'>) => (e.tipo === 'script' || e.tipo === 'cmd' || e.tipo === 'informe' ? 'Ejecutar' : 'Abrir')

export interface Ficha { Cliente: string; Telefono: string; Motivo: string; Notas: string }
export const fichaVacia: Ficha = { Cliente: '', Telefono: '', Motivo: '', Notas: '' }

export type EstadoPrueba = 'OK' | 'Aviso' | 'Fallo' | 'Info'
export interface PruebaPlan { id: string; grupo: string; nombre: string; seg: number }
export interface PruebaRes { estado: EstadoPrueba; resumen: string; detalle: string; seg: number }
export interface Dx {
  modo: 'Rapido' | 'Completo'; plan: PruebaPlan[]; resultados: Record<string, PruebaRes>; actual: string | null
  fin: null | { seg: number; historial: string | null; comparacion: { estado: string; resumen: string; detalle: string } | null; fallos: number; avisos: number; interrumpido: boolean; motivo?: string }
}

export interface EqComponente { clave: string; nombre: string; detalle: string; score: number; gama: string; anio: number | null }
export interface EqHallazgo { id: string; componente: string; estado: EstadoPrueba; titulo: string; resumen: string; detalle: string; siguiente: string }
export interface EqAnalisis { perfil: string; portatil: boolean; veredicto: string; clase: 'OK' | 'Aviso' | 'Fallo'; pieza: string | null; componentes: EqComponente[]; hallazgos: EqHallazgo[] }
export interface Eq { perfil: string; analisis: EqAnalisis | null; error: string | null; trabajando: boolean }

/** Revisar y arreglar: lo que el script automático cuenta mientras trabaja y al terminar. */
export interface AutoDetectado { id: string; nombre: string; estado: EstadoPrueba; resumen: string; llano?: string; arreglado?: boolean }
export interface AutoLinea { tipo: '' | 'ok' | 'aviso' | 'error'; texto: string }
export type EstadoPaso = 'espera' | 'activo' | 'ok' | 'aviso' | 'saltado' | 'tiempo' | 'nohecho'
export interface PasoVivo {
  id: string; titulo: string; que: string; hecho?: string; min: number; estado: EstadoPaso; texto: string; lineas: AutoLinea[]
  desde: number | null; silencio: number; resultado?: string; seg?: number; despues?: { id: string; nombre: string; estado: EstadoPrueba; resumen: string }[]
}
export interface AutoAtencion { id: string; nombre: string; estado: EstadoPrueba; resumen: string; llano?: string; consejo: string; intentado: boolean }
/** Lo último que se pidió y cómo acabó, para repetirlo con un clic y recordarlo al volver a la portada. */
export interface Ultima { titular: string; hora: number; enfoque: string; actualizar: boolean; antivirus: boolean; cliente: string }
export interface AutoResultado {
  equipo: string; modo?: 'auto' | 'combo'; soloMirar?: boolean; enfoque?: string; seg: number; revisadas: number; titular: string; reiniciar: boolean; informe: string | null
  detectados: AutoDetectado[]; pasos: PasoVivo[]; atencion: AutoAtencion[]
  antivirus?: { analizado: boolean; amenazas: number; otro: string | null; lista: string[] } | null
}
export interface Auto {
  fase: 'analisis' | 'confirmar' | 'arreglando' | 'verificando' | 'fin' | 'error'
  hechas: number; total: number; actual: string; revisadas: number
  detectados: AutoDetectado[]; pasos: PasoVivo[]; resultado: AutoResultado | null; error: string | null; cancelado?: boolean; combo?: boolean; t0: number
}
export const autoNuevo = (): Auto => ({ fase: 'analisis', hechas: 0, total: 0, actual: '', revisadas: 0, detectados: [], pasos: [], resultado: null, error: null, t0: Date.now() })

/** Un disco físico tal como lo devuelve Discos_Para_App.ps1. Los contadores son null si Windows no los da (USB, algunos NVMe) o si falta administrador. */
export interface DiscoFicha {
  nombre: string; tipo: string; bus: string; gb: number; salud: string; estado: string; firmware: string; letras: string[]
  temperatura: number | null; horas: number | null; desgaste: number | null; erroresLectura: number | null; erroresEscritura: number | null; arranques: number | null
}
