import { app, BrowserWindow, dialog, ipcMain, Menu, nativeTheme, powerSaveBlocker, session } from 'electron'
import { pathToFileURL } from 'node:url'
import { basename, dirname, isAbsolute, join, relative, resolve } from 'node:path'
import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from 'node:fs'
import { spawn, type ChildProcess } from 'node:child_process'
import os from 'node:os'
import { createHash } from 'node:crypto'

// «Nitrit0 Clonador»: app aparte para clonar un disco con Windows (GPT/UEFI) a otro. No tiene lógica de borrado propia:
// llama a Scripts\Mantenimiento\Clonar_Disco.ps1 (con huella comprobada) y enseña su salida. Por defecto solo simula.
const dev = !app.isPackaged
const quitarBom = (t: string) => t.replace(/^﻿/, '')

function resolverRaiz(): string {
  const inicio = dev ? resolve(app.getAppPath(), '..') : (process.env.PORTABLE_EXECUTABLE_DIR ?? dirname(process.execPath))
  let d = inicio
  for (let i = 0; i < 4; i++) { if (existsSync(join(d, 'Datos', 'kit.id'))) return d; const p = dirname(d); if (p === d) break; d = p }
  return inicio
}
const raiz = resolverRaiz()
const datos = join(raiz, 'Datos')
const sys32 = join(process.env.SystemRoot ?? 'C:\\Windows', 'System32')
const POWERSHELL = join(sys32, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
const TASKKILL = join(sys32, 'taskkill.exe')
const SCRIPT = join(raiz, 'Scripts', 'Mantenimiento', 'Clonar_Disco.ps1')
if (!dev) app.setPath('userData', join(os.tmpdir(), 'Nitrit0_Cache', 'ElectronClonador'))

// NIT_AUTO y compañía saltan las confirmaciones de Comun.ps1: un entorno sucio no debe poder activarlas.
const entornoLimpio = (): NodeJS.ProcessEnv => { const { NIT_AUTO: _a, NIT_SIN_PREGUNTAS: _s, NIT_AUTO_PRUEBA: _p, NIT_AUTO_PRUEBA_MAX: _m, NIT_AUTO_PRUEBA_CUBRE: _c, NIT_AUTO_FORZAR: _f, NIT_OPT_MODO: _o, ...resto } = process.env; return resto }
const matarArbol = (pid: number | undefined) => {
  if (!pid) return
  try { spawn(TASKKILL, ['/PID', String(pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore' }).on('error', () => { /* ya había terminado */ }).unref() } catch { /* ya había terminado */ }
}

const leerJson = <T,>(ruta: string, por: T): T => { try { return JSON.parse(quitarBom(readFileSync(ruta, 'utf8'))) as T } catch { return por } }
type ModoTema = 'oscuro' | 'claro' | 'sistema'
const modoTema = (): ModoTema => { const a = leerJson<{ Tema?: string; TemaModo?: string }>(join(datos, 'Ajustes.json'), {}); return a.TemaModo === 'sistema' || a.TemaModo === 'claro' || a.TemaModo === 'oscuro' ? a.TemaModo : a.Tema === 'claro' ? 'claro' : 'oscuro' }
const temaEfectivo = (m: ModoTema): 'oscuro' | 'claro' => (m === 'sistema' ? (nativeTheme.shouldUseDarkColors ? 'oscuro' : 'claro') : m)
const colores = { oscuro: { color: '#0F0F10', symbolColor: '#EDEDED' }, claro: { color: '#FFFFFF', symbolColor: '#171717' } }

// ---------- Lista blanca: Comun.ps1 y el script (y lo que cargue) deben figurar en Datos\Integridad.json con su huella ----------
let manifiesto: Map<string, string> | null = null
function motivoBloqueo(ruta: string): string | null {
  const m = comprobarHuella(ruta)
  if (!m) return null
  manifiesto = null   // regenerar la integridad con la app abierta no debe obligar a reiniciarla: se relee una vez antes de bloquear
  return comprobarHuella(ruta)
}
function dependencias(ruta: string, vistos = new Map<string, string>()): string[] {
  try {
    for (const m of readFileSync(ruta, 'utf8').matchAll(/Join-Path \$PSScriptRoot '([^']+\.ps1)'/g)) {
      const d = resolve(dirname(ruta), m[1])
      if (vistos.has(d.toLowerCase()) || vistos.size >= 30 || !existsSync(d)) continue
      vistos.set(d.toLowerCase(), d); dependencias(d, vistos)
    }
  } catch { /* si no se lee, ya lo bloquea la comprobación del propio script */ }
  return [...vistos.values()]
}
function comprobarHuella(ruta: string): string | null {
  try {
    if (!manifiesto) {
      const lista = JSON.parse(quitarBom(readFileSync(join(datos, 'Integridad.json'), 'utf8'))) as { R: string; H?: string }[]
      manifiesto = new Map(lista.filter((x) => x.H).map((x) => [x.R.toLowerCase(), x.H!.toUpperCase()]))
    }
    const esperado = manifiesto.get(relative(raiz, ruta).toLowerCase())
    if (!esperado) return 'no figura en Datos\\Integridad.json'
    return createHash('sha256').update(readFileSync(ruta)).digest('hex').toUpperCase() === esperado ? null : 'su contenido ha cambiado desde que se generó la integridad'
  } catch (err) { return `no se pudo comprobar su integridad (${(err as Error).message})` }
}

// ---------- Ejecución del script ----------
const q = (s: string) => `'${s.replace(/['‘’‚‛]/g, (c) => c + c)}'`   // PowerShell también trata ‘ ’ ‚ ‛ como comilla simple
let ventana: BrowserWindow
let marcha: ChildProcess | null = null
let cancelando = false
let opActual = ''
const enviar = (canal: string, carga: unknown) => { try { if (!ventana.isDestroyed() && !ventana.webContents.isDestroyed()) ventana.webContents.send(canal, carga) } catch { /* ventana cerrándose */ } }

interface Peticion { extra?: unknown; op?: unknown; origen?: unknown; destino?: unknown; origenId?: unknown; destinoId?: unknown; carpeta?: unknown; confirmo?: unknown }
// UniqueId de un disco (formato de Windows: letras, números y símbolos de rutas/GUID); se pasa entre comillas simples tras validarlo
const ID_DISCO = /^[^\r\n\0]{1,200}$/
const esDisco = (n: unknown): n is number => Number.isInteger(n) && (n as number) >= 0 && (n as number) < 128

/** Lo que llega de la interfaz se valida aquí; nada va al script sin pasar por esta función. */
function argumentos(p: Peticion): string | null {
  if (p.op === 'listar') return '-ListarDiscos'
  if (p.op === 'limpiar') return '-LimpiarRestos'
  if (p.op !== 'simular' && p.op !== 'ejecutar') return null
  if (!esDisco(p.origen) || !esDisco(p.destino)) return null
  // Los identificadores únicos son obligatorios: el script comprueba que el disco con ese número sigue siendo el que el técnico vio
  if (typeof p.origenId !== 'string' || typeof p.destinoId !== 'string' || !ID_DISCO.test(p.origenId) || !ID_DISCO.test(p.destinoId)) return null
  let a = `-Origen ${p.origen} -Destino ${p.destino} -OrigenId ${q(p.origenId)} -DestinoId ${q(p.destinoId)}`
  if (p.extra === 'Datos') a += ' -Extra Datos'   // cualquier otro valor = por defecto (Windows)
  if (typeof p.carpeta === 'string' && p.carpeta) {
    if (p.carpeta.length > 240 || !isAbsolute(p.carpeta) || /[\r\n"]/.test(p.carpeta)) return null
    a += ` -CarpetaImagen ${q(p.carpeta)}`
  }
  if (p.op === 'ejecutar') {
    if (p.confirmo !== `BORRAR DISCO ${p.destino}`) return null   // la frase se exige también aquí, no solo en la interfaz
    a += ` -Ejecutar -Confirmo ${q(String(p.confirmo))}`
  }
  return a
}

function correr(p: Peticion): { ok: boolean; mensaje: string } {
  if (marcha) return { ok: false, mensaje: 'Ya hay una operación en marcha.' }
  const args = argumentos(p)
  if (!args) return { ok: false, mensaje: 'Petición no válida.' }
  if (!existsSync(SCRIPT)) return { ok: false, mensaje: 'Este pack no lleva Clonar_Disco.ps1 (el clonado es solo del pack personal).' }
  const comun = join(raiz, 'Scripts', 'Comun.ps1')
  for (const r of [comun, SCRIPT, ...dependencias(SCRIPT)]) {
    const m = motivoBloqueo(r)
    if (m) return { ok: false, mensaje: `Error crítico: no se ejecuta ${basename(r)} porque ${m}. Si has cambiado el kit, ejecuta Regenerar_Integridad.ps1; si no, revisa el kit antes de usarlo.` }
  }
  // La orden va en el propio -Command: no se escribe ningún .ps1 temporal que se pueda cambiar antes de correr como administrador
  const orden = `try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) } catch { }; $env:NIT_EJEC='1'; . ${q(comun)}; Initialize-Kit ${q(raiz)}; $m = Test-ScriptAutorizado ${q(SCRIPT)}; if ($m) { Write-Output ('Error: no se ejecuta: ' + $m); exit 1 }; $global:LASTEXITCODE = 0; & ${q(SCRIPT)} ${args}; exit $LASTEXITCODE`
  const proc = spawn(POWERSHELL, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-Command', orden], { cwd: os.tmpdir(), env: { ...entornoLimpio(), NIT_RAIZ: raiz }, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] })
  marcha = proc; cancelando = false
  const operacion = String(p.op); opActual = operacion
  // Un clonado dura horas: si el equipo se suspende a mitad, el destino queda a medias. Solo mientras clona o simula.
  const bloqueoSuspension = operacion === 'simular' || operacion === 'ejecutar' ? powerSaveBlocker.start('prevent-app-suspension') : -1
  const restos = ['', '']
  let acabado = false
  const linea = (l: string) => {
    if (/^\W{0,3}#< CLIXML/.test(l) || /^\W{0,3}<Objs /.test(l) || !l.trim()) return
    const d = /^##DISCOS##(.+)$/.exec(l.trim())
    if (d) { try { enviar('clon:discos', JSON.parse(d[1])) } catch { /* línea cortada */ } return }
    const pro = /^##PROGRESO##/.test(l.trim()); if (pro) return
    const fase = /\b([1-6])\/6\b/.exec(l); if (fase) enviar('clon:fase', Number(fase[1]))   // el script marca cada paso como «N/6»
    enviar('clon:linea', l)
  }
  const alimentar = (i: 0 | 1) => (t: string) => { if (acabado) return; const partes = (restos[i] + t).split(/\r?\n/); restos[i] = partes.pop() ?? ''; partes.forEach(linea) }
  proc.stdout.setEncoding('utf8').on('data', alimentar(0))
  proc.stderr.setEncoding('utf8').on('data', alimentar(1))
  // Un clonado largo es normal (horas), pero no infinito: a las 8 h se corta el árbol entero para no dejar la app bloqueada
  const reloj = setTimeout(() => { cancelando = true; matarArbol(proc.pid); enviar('clon:linea', 'Error: pasaron más de 8 horas y se cortó la operación.') }, 8 * 3600 * 1000)
  const fin = (codigo: number | null) => {
    if (acabado) return
    acabado = true; clearTimeout(reloj)
    restos.forEach((r) => { if (r) linea(r) })
    proc.stdout.destroy(); proc.stderr.destroy(); marcha = null
    if (bloqueoSuspension >= 0) powerSaveBlocker.stop(bloqueoSuspension)
    const cortado = cancelando
    // Contrato de los scripts: 0 bien, 1 error, 2 cancelado
    enviar('clon:fin', { op: operacion, codigo, cancelado: cortado || codigo === 2 })
    // Un proceso matado no ejecuta su «finally»: se deshace lo que deja (instantáneas, imagen temporal, registro cargado, servicio parado)
    if (cortado && (operacion === 'simular' || operacion === 'ejecutar')) setTimeout(() => {
      enviar('clon:linea', 'Limpiando lo que dejó el corte…')
      const r = correr({ op: 'limpiar' })
      if (!r.ok) { enviar('clon:linea', `No se pudo limpiar: ${r.mensaje}`); enviar('clon:fin', { op: 'limpiar', codigo: 1, cancelado: false }) }
    }, 800)
  }
  proc.on('error', (e) => { enviar('clon:linea', `Error: no se pudo lanzar PowerShell: ${e.message}`); fin(null) })
  proc.on('close', fin)
  proc.once('exit', (c) => { setTimeout(() => fin(c), 1500) })   // un hijo que hereda las tuberías puede impedir 'close'
  return { ok: true, mensaje: '' }
}

// ---------- Ventana ----------
function crearVentana() {
  const t = temaEfectivo(modoTema())
  ventana = new BrowserWindow({
    width: 1060, height: 780, minWidth: 780, minHeight: 560, backgroundColor: t === 'claro' ? '#FAFAFA' : '#141415', title: 'Nitrit0 Clonador',
    icon: app.isPackaged ? join(process.resourcesPath, 'icono.png') : join(__dirname, '../../../build/icono-256.png'),
    titleBarStyle: 'hidden', titleBarOverlay: { ...colores[t], height: 40 },
    webPreferences: { preload: join(__dirname, '../preload/index.js'), contextIsolation: true, sandbox: true }
  })
  nativeTheme.on('updated', () => { if (modoTema() === 'sistema' && !ventana.isDestroyed()) ventana.setTitleBarOverlay({ ...colores[temaEfectivo('sistema')], height: 40 }) })
  // Cerrar a mitad de un clonado deja el destino a medias: se pregunta antes y se corta el árbol de procesos
  ventana.on('close', (ev) => {
    if (!marcha || (opActual !== 'ejecutar' && opActual !== 'simular')) return   // leer discos o limpiar restos no merece la pregunta
    ev.preventDefault()
    void dialog.showMessageBox(ventana, { type: 'warning', buttons: ['Seguir', 'Cancelar y cerrar'], defaultId: 0, cancelId: 0, title: 'Operación en marcha', message: 'Hay un clonado en marcha.', detail: 'Si lo cortas, el disco destino puede quedar a medias y habrá que repetir el clonado. El disco origen no se modifica.' })
      .then((r) => { if (r.response === 1) { matarArbol(marcha?.pid); app.exit(0) } })
  })
  ventana.webContents.setWindowOpenHandler(() => ({ action: 'deny' }))
  const propia = dev && process.env.ELECTRON_RENDERER_URL ? process.env.ELECTRON_RENDERER_URL : pathToFileURL(join(__dirname, '../renderer/index.html')).href
  const esPropia = (url: string) => { try { const a = new URL(url), b = new URL(propia); return a.protocol === b.protocol && a.host === b.host && a.pathname === b.pathname } catch { return false } }
  ventana.webContents.on('will-navigate', (ev, url) => { if (!esPropia(url)) ev.preventDefault() })
  if (!dev) Menu.setApplicationMenu(null)
  if (dev && process.env.ELECTRON_RENDERER_URL) void ventana.loadURL(process.env.ELECTRON_RENDERER_URL)
  else void ventana.loadFile(join(__dirname, '../renderer/index.html'))
  const captura = dev ? process.env.NITRIT0_CAPTURA : undefined
  if (captura) {
    ventana.webContents.once('did-finish-load', () => setTimeout(async () => {
      writeFileSync(captura, (await ventana.webContents.capturePage()).toPNG()); app.quit()
    }, Number(process.env.NITRIT0_ESPERA ?? 6) * 1000))
  }
}

const deMiVentana = (f: Electron.WebFrameMain | null) => f !== null && !!ventana && !ventana.isDestroyed() && f === ventana.webContents.mainFrame
const handle = (canal: string, fn: Parameters<typeof ipcMain.handle>[1]) => ipcMain.handle(canal, (e, ...a) => { if (!deMiVentana(e.senderFrame)) throw new Error('Origen no permitido'); return fn(e, ...a) })
const soloPortapapeles = (permiso: string) => permiso === 'clipboard-sanitized-write'
function cerrarPermisos() { session.defaultSession.setPermissionRequestHandler((_w, permiso, cb) => cb(soloPortapapeles(permiso))); session.defaultSession.setPermissionCheckHandler((_w, permiso) => soloPortapapeles(permiso)) }

if (!dev && !app.requestSingleInstanceLock()) app.quit()
else {
  app.on('second-instance', () => { if (ventana) { if (ventana.isMinimized()) ventana.restore(); ventana.focus() } })
  app.whenReady().then(() => {
    cerrarPermisos()
    handle('estado', () => ({ tema: modoTema(), hayScript: existsSync(SCRIPT), kit: existsSync(join(datos, 'kit.id')) }))
    handle('correr', (_e, p: Peticion) => correr(p ?? {}))
    handle('cancelar', () => { cancelando = true; matarArbol(marcha?.pid) })
    handle('guardarRegistro', (_e, lineas: unknown) => {
      if (!Array.isArray(lineas) || lineas.length > 20000 || lineas.some((l) => typeof l !== 'string')) throw new Error('Registro no válido.')
      const d = new Date(), p2 = (n: number) => String(n).padStart(2, '0')
      const nombre = `Clonado_${d.getFullYear()}${p2(d.getMonth() + 1)}${p2(d.getDate())}_${p2(d.getHours())}${p2(d.getMinutes())}${p2(d.getSeconds())}.txt`
      const carpeta = existsSync(join(datos, 'kit.id')) ? join(datos, 'Informes') : join(os.tmpdir(), 'Nitrit0_Cache')   // nunca se crea Datos en una unidad ajena
      mkdirSync(carpeta, { recursive: true })
      const ruta = join(carpeta, nombre)
      writeFileSync(ruta, '﻿' + (lineas as string[]).join('\r\n'), 'utf8')
      return ruta
    })
    handle('carpeta', async () => {
      const r = await dialog.showOpenDialog(ventana, { title: 'Carpeta para la imagen temporal (otro disco con sitio libre)', properties: ['openDirectory', 'createDirectory'] })
      if (r.canceled || !r.filePaths[0]) return ''
      try { return statSync(r.filePaths[0]).isDirectory() ? r.filePaths[0] : '' } catch { return '' }
    })
    crearVentana()
  })
  app.on('window-all-closed', () => { if (marcha) matarArbol(marcha.pid); app.quit() })
}
