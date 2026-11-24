import { app, BrowserWindow, dialog, ipcMain, Menu, nativeTheme, session } from 'electron'
import { pathToFileURL } from 'node:url'
import { basename, dirname, join, relative, resolve } from 'node:path'
import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { spawn, type ChildProcess } from 'node:child_process'
import os from 'node:os'
import { createHash } from 'node:crypto'

// «Nitrit0 Limpieza»: segunda interfaz sobre el mismo kit. No tiene lógica propia de borrado: pide a Scripts\Limpieza_Motor.ps1
// (con huella comprobada) y pinta los eventos JSON que devuelve.
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
const POWERSHELL = join(process.env.SystemRoot ?? 'C:\\Windows', 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
const TASKKILL = join(process.env.SystemRoot ?? 'C:\\Windows', 'System32', 'taskkill.exe')
// NIT_AUTO y compañía saltan las confirmaciones de Comun.ps1: un entorno sucio no debe poder activarlas en el motor.
const entornoLimpio = (): NodeJS.ProcessEnv => { const { NIT_AUTO: _a, NIT_SIN_PREGUNTAS: _s, NIT_AUTO_PRUEBA: _p, NIT_AUTO_PRUEBA_MAX: _m, NIT_AUTO_PRUEBA_CUBRE: _c, NIT_AUTO_FORZAR: _f, NIT_OPT_MODO: _o, ...resto } = process.env; return resto }
/** El motor lanza desinstaladores y procesos hijos: se cierra el árbol entero, no solo el PowerShell que lo llama. */
const matarArbol = (pid: number | undefined) => {
  if (!pid) return
  try { spawn(TASKKILL, ['/PID', String(pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore' }).on('error', () => { /* ya había terminado o sin permisos */ }).unref() } catch { /* ya había terminado */ }
}
if (!dev) app.setPath('userData', join(os.tmpdir(), 'Nitrit0_Cache', 'ElectronLimpieza'))

const leerJson = <T,>(ruta: string, por: T): T => { try { return JSON.parse(quitarBom(readFileSync(ruta, 'utf8'))) as T } catch { return por } }
type ModoTema = 'oscuro' | 'claro' | 'sistema'
const modoTema = (): ModoTema => { const a = leerJson<{ Tema?: string; TemaModo?: string }>(join(datos, 'Ajustes.json'), {}); return a.TemaModo === 'sistema' || a.TemaModo === 'claro' || a.TemaModo === 'oscuro' ? a.TemaModo : a.Tema === 'claro' ? 'claro' : 'oscuro' }
const temaEfectivo = (m: ModoTema): 'oscuro' | 'claro' => (m === 'sistema' ? (nativeTheme.shouldUseDarkColors ? 'oscuro' : 'claro') : m)
const colores = { oscuro: { color: '#0F0F10', symbolColor: '#EDEDED' }, claro: { color: '#FFFFFF', symbolColor: '#171717' } }

// ---------- Lista blanca: el motor y Comun.ps1 deben figurar en Datos\Integridad.json con su huella ----------
let manifiesto: Map<string, string> | null = null
function motivoBloqueo(ruta: string): string | null {
  const m = comprobarHuella(ruta)
  if (!m) return null
  manifiesto = null   // regenerar la integridad con la app abierta no debe obligar a reiniciarla: se relee una vez antes de bloquear
  return comprobarHuella(ruta)
}
/** Ficheros .ps1 que un script ya verificado carga con Join-Path $PSScriptRoot '…' (el motor usa Desinstalar_Total y Limpiar_Registro_Huerfano): también deben figurar en la integridad y coincidir. */
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

// ---------- Motor ----------
const q = (s: string) => `'${s.replace(/['‘’‚‛]/g, (c) => c + c)}'`   // PowerShell tambien trata ‘ ’ ‚ ‛ como comilla simple
const ID_CATEGORIA = /^[a-z0-9-]{1,40}$/
let ventana: BrowserWindow
let marcha: ChildProcess | null = null
let opActual = ''
let cancelado = false
// Solo lo que mira y no borra se puede cortar a la fuerza sin riesgo; limpiar, desinstalar o tocar el registro no.
const SE_PUEDE_CORTAR = ['Analizar', 'ProgramasListar', 'InicioListar', 'RegistroAnalizar']

/** Acciones y parámetros permitidos: lo que llega de la interfaz se valida aquí, no se confía en ello. */
function argumentos(op: string, p: { ids?: unknown; tipo?: unknown; id?: unknown; activar?: unknown; nombres?: unknown; modo?: unknown }): string | null {
  if (op === 'Analizar' || op === 'InicioListar' || op === 'ProgramasListar' || op === 'RegistroAnalizar') return `-Accion ${op}`
  if (op === 'RegistroLimpiar') return `-Accion RegistroLimpiar -Modo ${p.modo === 'Manual' ? 'Manual' : 'Auto'}`
  if (op === 'DesinstalarFondo') {
    const n = Array.isArray(p.nombres) ? p.nombres.filter((x): x is string => typeof x === 'string' && x.length > 0 && x.length <= 300).slice(0, 100) : []
    return n.length ? `-Accion DesinstalarFondo -Nombres ${n.map(q).join(',')}` : null
  }
  if (op === 'Limpiar') {
    const ids = Array.isArray(p.ids) ? p.ids.filter((x): x is string => typeof x === 'string' && ID_CATEGORIA.test(x)) : []
    return ids.length ? `-Accion Limpiar -Ids ${ids.map(q).join(',')}` : null
  }
  if (op === 'InicioCambiar') {
    if ((p.tipo !== 'registro' && p.tipo !== 'tarea') || typeof p.id !== 'string' || !p.id || p.id.length > 400) return null
    return `-Accion InicioCambiar -Tipo ${p.tipo} -Id ${q(p.id)} -Activar $${p.activar === true ? 'true' : 'false'}`
  }
  return null
}

/** Ruta del programa de una línea de inicio (con o sin comillas, con variables %X%): solo rutas locales que existen. */
function rutaDeOrden(orden: string): string | null {
  const sin = orden.replace(/%([^%]+)%/g, (m, v: string) => process.env[v] ?? m)
  const m = /^\s*"([^"]+)"/.exec(sin) ?? /^\s*(.+?\.(?:exe|lnk|bat|cmd))(?=\s|$)/i.exec(sin)
  return m && /^[a-z]:[\\/]/i.test(m[1]) && existsSync(m[1]) ? m[1] : null
}

function ejecutarMotor(op: string, params: Parameters<typeof argumentos>[1]): Promise<{ ok: boolean; mensaje: string; codigo: number | null }> {
  if (marcha) return Promise.resolve({ ok: false, mensaje: 'Ya hay una operación en marcha.', codigo: null })
  const args = argumentos(op, params)
  if (!args) return Promise.resolve({ ok: false, mensaje: 'Petición no válida.', codigo: null })
  const comun = join(raiz, 'Scripts', 'Comun.ps1'), motor = join(raiz, 'Scripts', 'Limpieza_Motor.ps1')
  let bloqueo: string | null = null
  for (const r of [comun, motor, ...dependencias(motor)]) { const m = motivoBloqueo(r); if (m) { bloqueo = `${basename(r)} ${m}`; break } }
  if (bloqueo) return Promise.resolve({ ok: false, mensaje: `No se ejecuta: ${bloqueo}. Si has cambiado el kit, ejecuta Regenerar_Integridad.ps1.`, codigo: null })
  // La orden va en el propio -Command: no se escribe ningún .ps1 temporal que se pueda cambiar antes de correr como administrador
  const orden = `try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) } catch { }; $env:NIT_EJEC='1'; . ${q(comun)}; Initialize-Kit ${q(raiz)}; $m = Test-ScriptAutorizado ${q(motor)}; if ($m) { Write-Output ('{"evento":"error","mensaje":"No se ejecuta: ' + $m + '"}'); exit 1 }; $global:LASTEXITCODE = 0; & ${q(motor)} ${args}; exit $LASTEXITCODE`
  return new Promise((fin) => {
    const proc = spawn(POWERSHELL, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-Command', orden], { cwd: raiz, env: { ...entornoLimpio(), NIT_RAIZ: raiz }, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'], windowsVerbatimArguments: false })
    marcha = proc; opActual = op; cancelado = false
    let resto = ''
    // Un motor colgado (un desinstalador esperando algo) no puede dejar la app bloqueada para siempre: a los 60 min se cierra su árbol
    let acabado = false
    let reloj: NodeJS.Timeout
    const acabar = (r: { ok: boolean; mensaje: string; codigo: number | null }) => { if (acabado) return; acabado = true; clearTimeout(reloj); marcha = null; proc.stdout.destroy(); proc.stderr.destroy(); fin(r) }
    reloj = setTimeout(() => { matarArbol(proc.pid); acabar({ ok: false, mensaje: 'El motor tardó más de 60 minutos y se ha cerrado para no bloquear la app.', codigo: null }) }, 60 * 60 * 1000)
    const enviar = (v: Record<string, unknown>) => { if (!ventana.isDestroyed()) ventana.webContents.send('motor:evento', v) }
    // Los iconos llegan de forma asíncrona: la operación no se da por terminada hasta que sus eventos hayan salido (si no, una recarga inmediata recibiría elementos de la anterior)
    const iconos: Promise<void>[] = []
    const alAcabar = (r: { ok: boolean; mensaje: string; codigo: number | null }) => { void Promise.race([Promise.allSettled(iconos), new Promise((ok) => setTimeout(ok, 3000))]).then(() => acabar(r)) }
    const linea = (t: string) => {
      if (acabado) return   // un hijo que heredó las tuberías puede seguir escribiendo tras darse la operación por terminada: no se cuela en la siguiente
      const s = t.trim(); if (!s.startsWith('{')) return
      let v: Record<string, unknown>
      try { v = { op, ...JSON.parse(s) } } catch { return }   // línea que no es JSON
      // Programas de inicio: el icono real del programa (o del acceso directo), sacado aquí porque solo el proceso principal puede pedírselo a Windows
      const ruta = op === 'InicioListar' && v.evento === 'inicio' && typeof v.orden === 'string' ? rutaDeOrden(v.orden) : null
      if (ruta) iconos.push(app.getFileIcon(ruta, { size: 'normal' }).then((i) => enviar({ ...v, icono: i.toDataURL() })).catch(() => enviar(v)))
      else enviar(v)
    }
    proc.stdout.setEncoding('utf8').on('data', (d: string) => { resto += d; const l = resto.split(/\r?\n/); resto = l.pop() ?? ''; l.forEach(linea) })
    // stderr va en tubería: si nadie lo lee, el hijo se bloquea al llenar el búfer (64 KB) y la app se queda con «Ya hay una operación en marcha»
    proc.stderr.setEncoding('utf8').on('data', () => { /* avisos de PowerShell: se drenan y se descartan */ })
    const resultado = (codigo: number | null): { ok: boolean; mensaje: string; codigo: number | null } => cancelado ? { ok: false, mensaje: 'Cancelado.', codigo: null } : ({ ok: codigo === 0, mensaje: codigo === 0 ? '' : `El motor terminó con código ${codigo}.`, codigo })
    proc.on('error', (e) => acabar({ ok: false, mensaje: `No se pudo lanzar PowerShell: ${e.message}`, codigo: null }))
    proc.on('close', (codigo) => { if (resto) linea(resto); alAcabar(resultado(codigo)) })
    // Si un desinstalador hereda las tuberías, 'close' puede no llegar: con el proceso ya muerto se cierra tras un margen
    proc.once('exit', (codigo) => { setTimeout(() => alAcabar(resultado(codigo)), 1500) })
  })
}

function crearVentana() {
  const t = temaEfectivo(modoTema())
  ventana = new BrowserWindow({
    width: 1120, height: 760, minWidth: 880, minHeight: 560, backgroundColor: t === 'claro' ? '#FAFAFA' : '#141415', title: 'Nitrit0 Limpieza',
    icon: app.isPackaged ? join(process.resourcesPath, 'icono.png') : join(__dirname, '../../../build/icono-256.png'),
    titleBarStyle: 'hidden', titleBarOverlay: { ...colores[t], height: 40 },
    webPreferences: { preload: join(__dirname, '../preload/index.js'), contextIsolation: true, sandbox: true }
  })
  nativeTheme.on('updated', () => { if (modoTema() === 'sistema' && !ventana.isDestroyed()) ventana.setTitleBarOverlay({ ...colores[temaEfectivo('sistema')], height: 40 }) })
  ventana.on('close', (ev) => { if (marcha) { ev.preventDefault(); ventana.webContents.send('motor:cerrando') } })
  // Si la interfaz se cae, el aviso de cierre nunca llega y la ventana no se podría cerrar: se pregunta desde el proceso principal
  let interfazCaida = false
  ventana.webContents.on('render-process-gone', () => { interfazCaida = true })
  // Colgada (no caída): Electron avisa con 'unresponsive' y vuelve con 'responsive'
  ventana.on('unresponsive', () => { interfazCaida = true })
  ventana.on('responsive', () => { interfazCaida = false })
  ventana.on('close', (ev) => {
    if (!marcha || !interfazCaida) return
    ev.preventDefault()
    void dialog.showMessageBox(ventana, { type: 'warning', buttons: ['Seguir esperando', 'Cerrar de todos modos'], defaultId: 0, cancelId: 0, title: 'Operación en marcha', message: 'La ventana dejó de responder.', detail: '¿Cerrar la app y cancelar lo que está en marcha? Lo que ya se borró no se recupera.' })
      .then((r) => { if (r.response === 1) { matarArbol(marcha?.pid); app.exit(0) } })
  })
  ventana.webContents.setWindowOpenHandler(() => ({ action: 'deny' }))
  const propia = dev && process.env.ELECTRON_RENDERER_URL ? process.env.ELECTRON_RENDERER_URL : pathToFileURL(join(__dirname, '../renderer/index.html')).href
  // Se compara la URL entera (protocolo, equipo y ruta), no su texto: «http://localhost:5173.evil.com» empieza igual que la propia
  const esPropia = (url: string) => { try { const a = new URL(url), b = new URL(propia); return a.protocol === b.protocol && a.host === b.host && a.pathname === b.pathname } catch { return false } }
  ventana.webContents.on('will-navigate', (ev, url) => { if (!esPropia(url)) ev.preventDefault() })
  if (!dev) Menu.setApplicationMenu(null)
  if (dev && process.env.ELECTRON_RENDERER_URL) void ventana.loadURL(process.env.ELECTRON_RENDERER_URL)
  else void ventana.loadFile(join(__dirname, '../renderer/index.html'))
  // Solo desarrollo (como en Nitrit0): NITRIT0_CAPTURA=<png> guarda la ventana y sale; NITRIT0_CLIC=<selector> [ >> otro] pulsa antes de capturar
  const captura = dev ? process.env.NITRIT0_CAPTURA : undefined
  if (captura) {
    ventana.webContents.once('did-finish-load', () => setTimeout(async () => {
      try { for (const sel of (process.env.NITRIT0_CLIC ?? '').split(' >> ').filter(Boolean)) { await ventana.webContents.executeJavaScript(`document.querySelector(${JSON.stringify(sel)})?.click()`); await new Promise((ok) => setTimeout(ok, 3000)) } } catch { /* sin clic */ }
      writeFileSync(captura, (await ventana.webContents.capturePage()).toPNG()); app.quit()
    }, Number(process.env.NITRIT0_ESPERA ?? 6) * 1000))
  }
}

/** Endurecimiento (guía de seguridad de Electron): solo se atiende al marco principal de la ventana propia (ni subventanas ni iframes) y se deniega todo permiso del navegador salvo copiar al portapapeles. */
const deMiVentana = (f: Electron.WebFrameMain | null) => f !== null && !!ventana && !ventana.isDestroyed() && f === ventana.webContents.mainFrame
const handle = (canal: string, fn: Parameters<typeof ipcMain.handle>[1]) => ipcMain.handle(canal, (e, ...a) => { if (!deMiVentana(e.senderFrame)) throw new Error('Origen no permitido'); return fn(e, ...a) })
const soloPortapapeles = (permiso: string) => permiso === 'clipboard-sanitized-write'
function cerrarPermisos() { session.defaultSession.setPermissionRequestHandler((_w, permiso, cb) => cb(soloPortapapeles(permiso))); session.defaultSession.setPermissionCheckHandler((_w, permiso) => soloPortapapeles(permiso)) }

if (!app.requestSingleInstanceLock()) app.quit()
else {
  app.on('second-instance', () => { if (ventana) { if (ventana.isMinimized()) ventana.restore(); ventana.focus() } })
  app.whenReady().then(() => {
    cerrarPermisos()
    handle('motor', (_e, op: string, params: Parameters<typeof argumentos>[1]) => ejecutarMotor(op, params ?? {}))
    handle('estado', () => ({ tema: modoTema(), kit: raiz, publico: leerJson<{ OcultarPeligro?: boolean }>(join(datos, 'Ajustes.json'), { OcultarPeligro: true }).OcultarPeligro === true }))
    handle('cerrar', () => { matarArbol(marcha?.pid); app.exit(0) })
    handle('cancelarAnalisis', () => { if (!marcha || !SE_PUEDE_CORTAR.includes(opActual)) return false; cancelado = true; matarArbol(marcha.pid); return true })
    crearVentana()
  })
  app.on('window-all-closed', () => app.quit())
}
