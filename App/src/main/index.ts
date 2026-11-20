import { app, BrowserWindow, dialog, ipcMain, Menu, nativeImage, nativeTheme, Notification, session, shell, systemPreferences, Tray } from 'electron'
import { pathToFileURL } from 'node:url'
import { basename, dirname, join, relative, resolve } from 'node:path'
import { appendFileSync, copyFileSync, cpSync, existsSync, mkdirSync, readdirSync, readFileSync, realpathSync, renameSync, rmSync, statSync, unlinkSync, writeFileSync } from 'node:fs'
import { execFile, spawn, type ChildProcess } from 'node:child_process'
import os from 'node:os'
import { createHash } from 'node:crypto'

const dev = !app.isPackaged

// Raíz del kit: sube desde el exe (o desde App\ en desarrollo) hasta encontrar Datos\kit.id, así sirve con cualquier carpeta de empaquetado.
function resolverRaiz(): string {
  // Arrancada por la tarea de inicio con privilegios altos (--bandeja): la raíz es siempre la copia de Archivos de programa, nunca una variable de entorno que pueda cambiar un usuario sin privilegios
  const instalacion = join(process.env.ProgramFiles ?? 'C:\\Program Files', 'Nitrit0 Kit')
  if (!dev && process.argv.includes('--bandeja') && existsSync(join(instalacion, 'Datos', 'kit.id'))) return instalacion
  const inicio = dev ? resolve(app.getAppPath(), '..') : (process.env.PORTABLE_EXECUTABLE_DIR ?? dirname(process.execPath))   // PORTABLE_EXECUTABLE_DIR: carpeta del .exe único (electron-builder)
  let d = inicio
  for (let i = 0; i < 4; i++) { if (existsSync(join(d, 'Datos', 'kit.id'))) return d; const p = dirname(d); if (p === d) break; d = p }
  return inicio
}
const raiz = resolverRaiz()

// Programas del sistema por ruta absoluta: con cwd en %TEMP%, un nombre suelto podría resolverse a un fichero plantado allí.
const sys32 = join(process.env.SystemRoot ?? 'C:\\Windows', 'System32')
const POWERSHELL = join(sys32, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
/** Entorno heredado sin las variables que saltan confirmaciones o activan ganchos de prueba: solo la revisión automática las pasa, y las pasa ella, explícitamente. */
const entornoLimpio = (): NodeJS.ProcessEnv => { const { NIT_AUTO: _a, NIT_SIN_PREGUNTAS: _s, NIT_AUTO_PRUEBA: _p, NIT_AUTO_PRUEBA_MAX: _m, NIT_AUTO_PRUEBA_CUBRE: _c, NIT_AUTO_FORZAR: _f, NIT_OPT_MODO: _o, ...resto } = process.env; return resto }
const CMD = join(sys32, 'cmd.exe')
const TASKKILL = join(sys32, 'taskkill.exe')
const FLTMC = join(sys32, 'fltmc.exe')
const SCHTASKS = join(sys32, 'schtasks.exe')
// En un equipo de cliente la app no debe dejar su caché de Chromium en %APPDATA%
if (!dev) app.setPath('userData', join(os.tmpdir(), 'Nitrit0_Cache', 'Electron'))
const datos = join(raiz, 'Datos')
const quitarBom = (t: string) => t.replace(/^﻿/, '')
const colores = {
  oscuro: { color: '#0F0F10', symbolColor: '#EDEDED' },
  claro: { color: '#FFFFFF', symbolColor: '#171717' }
}
let ventana: BrowserWindow
let salirDeVerdad = false
const enBandeja = process.argv.includes('--bandeja')   // arranque con Windows: la ventana no se muestra, solo el icono

// ---------- Catálogo ----------
interface Elemento {
  id: string; titulo: string; descripcion: string; categoria: string; pagina: string; grupo: string; oculta: boolean
  peligro: boolean; publicoOk?: boolean; tipo: string; exe?: Record<string, string>; script?: string; accion?: string; run?: string
  runArgs?: string; cmd?: string; html?: string; uri?: string; timeout?: number; ayuda?: string
}
const arq = process.arch === 'arm64' ? 'arm64' : process.arch === 'ia32' ? 'x86' : 'x64'
const ACCIONES_APP = ['AbrirHistorial', 'AbrirInformes', 'CmdBateria', 'CmdEnergia', 'SmartDetalle']
let catalogo: { paginas: Record<string, string[]>; soluciones: Record<string, string[]>; elementos: Elemento[] } | null = null

function leerCatalogo() {
  if (!catalogo) {
    const ruta = join(raiz, 'App', 'datos', 'herramientas.json')
    const motivo = motivoBloqueo(ruta)   // el catálogo decide qué se ejecuta: si lo cambian, no se carga
    if (motivo) throw new Error(`El catálogo de herramientas ${motivo}. Si lo has actualizado tú, ejecuta Regenerar_Integridad.ps1.`)
    catalogo = JSON.parse(quitarBom(readFileSync(ruta, 'utf8')))
  }
  return catalogo!
}

// ---------- Lista blanca: solo corre lo que figura en Datos\Integridad.json con su huella SHA-256 ----------
let manifiesto: Map<string, string> | null = null
/** null si el script es el que se generó; si no, el motivo por el que no debe ejecutarse. */
function motivoBloqueo(ruta: string): string | null {
  try {
    if (!manifiesto) {
      const lista = JSON.parse(quitarBom(readFileSync(join(datos, 'Integridad.json'), 'utf8'))) as { R: string; H?: string }[]
      manifiesto = new Map(lista.filter((x) => x.H).map((x) => [x.R.toLowerCase(), x.H!.toUpperCase()]))
    }
    const rel = relative(raiz, ruta).toLowerCase()   // funciona también si el kit está en la raíz de una unidad (E:\)
    const esperado = manifiesto.get(rel)
    if (!esperado) return 'no figura en Datos\\Integridad.json'
    return createHash('sha256').update(readFileSync(ruta)).digest('hex').toUpperCase() === esperado ? null : 'su contenido ha cambiado desde que se generó la integridad'
  } catch (err) { return `no se pudo comprobar su integridad (${(err as Error).message})` }
}

// shortcut: entre varias versiones gana el orden natural de la ruta (cpu-z_2.10 > cpu-z_2.9), no la versión interna del exe; subir si una app lo necesita.
function resolverExe(el: Elemento): string | null {
  const rel = el.exe?.[arq] ?? el.exe?.x64 ?? el.exe?.x86
  if (!rel) return null
  const tramos = rel.split('\\')
  let candidatos = [join(raiz, 'Apps')]
  for (const t of tramos) {
    const siguientes: string[] = []
    for (const base of candidatos) {
      if (!/[*?]/.test(t)) { siguientes.push(join(base, t)); continue }
      const re = new RegExp('^' + t.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*').replace(/\?/g, '.') + '$', 'i')
      try { for (const n of readdirSync(base)) if (re.test(n)) siguientes.push(join(base, n)) } catch { /* carpeta ausente */ }
    }
    candidatos = siguientes
  }
  const ok = candidatos.filter((c) => existsSync(c)).sort((a, b) => b.localeCompare(a, undefined, { numeric: true }))
  return ok[0] ?? null
}

// Traza de arranque de la app en %TEMP%\Nitrit0_Cache\Logs\arranque.log (el mismo archivo que usan los scripts): si abrir tarda, ahí se ve qué fase fue.
function trazaApp(m: string) {
  try { const f = join(os.tmpdir(), 'Nitrit0_Cache', 'Logs', 'arranque.log'); mkdirSync(dirname(f), { recursive: true }); appendFileSync(f, `${new Date().toTimeString().slice(0, 8)} ${process.uptime().toFixed(1).padStart(6)} s  [app] ${m}\n`) } catch { /* sin traza */ }
}
// Iconos de las herramientas: leerlos de cada .exe del pendrive tarda (y el antivirus analiza cada archivo la primera vez), así que se guardan en %TEMP%.
// La clave incluye tamaño y fecha del .exe: si se actualiza la herramienta, se vuelve a leer su icono.
type IconoGuardado = { s: number; m: number; d: string }
let iconosGuardados: Record<string, IconoGuardado> | null = null
let iconosCambiaron = false
const rutaIconos = () => join(os.tmpdir(), 'Nitrit0_Cache', 'iconos.json')
async function iconoDe(exe: string, contador: { cache: number; leidos: number }): Promise<string | null> {
  try {
    const st = statSync(exe); const m = Math.floor(st.mtimeMs); const k = exe.toLowerCase()
    iconosGuardados ??= leerJson<Record<string, IconoGuardado>>(rutaIconos(), {})
    const g = iconosGuardados[k]
    if (g && g.s === st.size && g.m === m && typeof g.d === 'string') { contador.cache++; return g.d }
    const d = (await app.getFileIcon(exe, { size: 'large' })).toDataURL()
    iconosGuardados[k] = { s: st.size, m, d }; iconosCambiaron = true; contador.leidos++
    return d
  } catch { return null }   // sin icono
}

async function listarCatalogo() {
  const c = leerCatalogo()
  const t0 = Date.now(); const contador = { cache: 0, leidos: 0 }
  trazaApp('Catálogo: empieza a listar herramientas e iconos')
  const elementos = await Promise.all(c.elementos.map(async (e) => {
    const exe = e.tipo === 'exe' ? resolverExe(e) : null
    const icono = exe ? await iconoDe(exe, contador) : null
    const soportado = e.tipo !== 'accion' || ACCIONES_APP.includes(e.accion ?? '')
    return { id: e.id, titulo: e.titulo, descripcion: e.descripcion, categoria: e.categoria, pagina: e.pagina, grupo: e.grupo, oculta: e.oculta, peligro: e.peligro, publicoOk: e.publicoOk === true, tipo: e.tipo, accion: e.accion ?? null, ayuda: e.ayuda ?? null, icono, soportado, disponible: (e.tipo !== 'exe' || !!exe) && (e.accion !== 'SmartDetalle' || existsSync(join(raiz, 'Apps', 'Disk', 'smartmontools', 'bin', 'smartctl.exe'))) }
  }))
  if (iconosCambiaron && iconosGuardados) { try { escribirJson(rutaIconos(), iconosGuardados); iconosCambiaron = false } catch { /* se vuelve a intentar la próxima vez */ } }
  trazaApp(`Catálogo listo en ${((Date.now() - t0) / 1000).toFixed(1)} s (${elementos.length} elementos; iconos: ${contador.cache} de la caché, ${contador.leidos} leídos de los .exe)`)
  return { paginas: c.paginas, soluciones: c.soluciones ?? {}, elementos }
}

// ---------- Registro de actividad (el mismo que usa el lanzador) ----------
const cacheKit = join(os.tmpdir(), 'Nitrit0_Cache')
/** Pack público = OcultarPeligro true en Ajustes.json. Si falta o no se puede leer se asume público: ante la duda, nada se guarda en el pendrive. */
function esPublico(): boolean { try { return JSON.parse(quitarBom(readFileSync(join(datos, 'Ajustes.json'), 'utf8'))).OcultarPeligro === true } catch { return true } }
/** Dónde van registros, historial y salidas de scripts: %TEMP%\Nitrit0_Cache en el público; Datos del pendrive en el personal. */
const baseTrabajo = () => (esPublico() ? cacheKit : datos)
function historial(texto: string) {
  try {
    const base = baseTrabajo()
    if (base === datos && !existsSync(join(datos, 'kit.id'))) return   // nunca se crea Datos en una unidad ausente o ajena
    mkdirSync(base, { recursive: true })
    const d = new Date(), p = (n: number) => String(n).padStart(2, '0')
    const f = `${p(d.getDate())}/${p(d.getMonth() + 1)}/${d.getFullYear()} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`
    appendFileSync(join(base, 'Historial_Diagnosticos.log'), `[${f}] ${os.userInfo().username} - ${texto}\r\n`, 'utf8')
  } catch { /* el pendrive puede no estar */ }
}

/** Línea en Datos\Logs\Kit_<fecha>_<equipo>.log con el formato de Write-Log (Comun.ps1); Informe_Entrega.ps1 la lee para «Trabajos realizados». */
function registroKit(mensaje: string, nivel = 'INFO') {
  try {
    const base = baseTrabajo()
    if (base === datos && !existsSync(join(datos, 'kit.id'))) return
    const d = new Date(), p = (n: number) => String(n).padStart(2, '0')
    const ymd = `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}`
    const fecha = `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`
    mkdirSync(join(base, 'Logs'), { recursive: true })
    appendFileSync(join(base, 'Logs', `Kit_${ymd}_${os.hostname().replace(/[^\w-]/g, '_')}.log`), `[${fecha}] [${nivel}] ${mensaje}\r\n`, 'utf8')
  } catch { /* el pendrive puede no estar */ }
}

// ---------- Lanzar apps y utilidades ----------
const esc = (s: string) => s.replace(/['‘’‚‛]/g, (c) => c + c)   // PowerShell tambien trata ‘ ’ ‚ ‛ como comilla simple: hay que duplicarlas igual
/** Nombre suelto de un programa de Windows (perfmon.exe, taskmgr.exe…) → ruta absoluta de System32, para no depender de PATH ni de la carpeta actual. */
const programaDelSistema = (n: string) => (/^[\w.-]+$/.test(n) && existsSync(join(sys32, n)) ? join(sys32, n) : n)
/** Proceso lanzado y soltado: un fallo al arrancar se anota, nunca tumba la app. */
function suelto(h: ChildProcess, quien: string) { h.on('error', (e) => historial(`Fallo al lanzar ${quien}: ${e.message}`)); h.unref() }
function psLanzar(exe: string, args: string[], cwd?: string, elevar = false) {
  const lista = args.length ? ` -ArgumentList ${args.map((a) => `'${esc(a)}'`).join(',')}` : ''
  const dir = cwd ? ` -WorkingDirectory '${esc(cwd)}'` : ''
  const verbo = elevar ? ' -Verb RunAs' : ''
  suelto(spawn(POWERSHELL, ['-NoProfile', '-Command', `Start-Process -FilePath '${esc(exe)}'${lista}${dir}${verbo}`], { windowsHide: true, stdio: 'ignore', detached: true }), exe)
}
/** Reabre la propia app con permisos de administrador (UAC). Si se cancela el permiso, esta ventana sigue como estaba. */
async function reabrirComoAdmin(): Promise<{ ok: boolean; mensaje: string }> {
  if (dev) return { ok: false, mensaje: 'En modo desarrollo no se puede: abre la app empaquetada.' }
  if (marcha) return { ok: false, mensaje: `Ya hay algo en marcha: ${marcha.titulo}. Espera a que termine.` }
  if (await esAdmin()) return { ok: false, mensaje: 'Ya tiene permisos de administrador.' }
  // Mismo .exe con el que se abrió: el lanzador fino de la carpeta del kit (Nitrit0.exe), el .exe único o, si no, el propio programa
  const lanzador = join(raiz, 'Nitrit0.exe')
  const exe = process.env.PORTABLE_EXECUTABLE_FILE ?? (existsSync(lanzador) ? lanzador : process.execPath)
  // La instancia nueva no arrancaría con la actual viva (una sola ventana): se suelta el bloqueo y, si se cancela el UAC, se recupera
  app.releaseSingleInstanceLock()
  const codigo = await new Promise<number>((ok) => {
    const h = spawn(POWERSHELL, ['-NoProfile', '-Command', `try { Start-Process -FilePath '${esc(exe)}' -Verb RunAs -ErrorAction Stop } catch { exit 1 }`], { windowsHide: true, stdio: 'ignore' })
    h.on('error', () => ok(1)); h.on('exit', (c) => ok(c ?? 1))
  })
  if (codigo !== 0) { app.requestSingleInstanceLock(); historial('Reabrir como administrador: cancelado o fallido'); return { ok: false, mensaje: 'No se concedió el permiso de administrador. Sigues con la ventana de antes.' } }
  historial('Reabierta con permisos de administrador')
  setTimeout(() => app.quit(), 400)
  return { ok: true, mensaje: 'Reabriendo como administrador…' }
}
const ventanaCmd = (orden: string) => psLanzar(CMD, ['/k', orden])

function lanzarApp(e: Elemento): { ok: boolean; mensaje: string } {
  const exe = resolverExe(e)
  if (!exe) return { ok: false, mensaje: `No encuentro ${e.titulo} en la carpeta Apps del kit.` }
  // Las herramientas portables de Apps\ llevan SHA-256 en Integridad.json: si el .exe ha cambiado o no consta, no se abre
  const bloqueo = motivoBloqueo(exe)
  if (bloqueo) { historial(`BLOQUEADO ${e.titulo}: ${bloqueo}`); return { ok: false, mensaje: `Error crítico: no se abre ${e.titulo} porque ${basename(exe)} ${bloqueo}. Si has actualizado la herramienta tú, ejecuta Regenerar_Integridad.ps1; si no, revisa el kit antes de usarlo.` } }
  const cwd = dirname(exe)
  const h = spawn(exe, [], { cwd, detached: true, stdio: 'ignore' })
  // Si la app pide administrador y la nuestra no lo es, Windows rechaza el arranque directo: se reintenta pidiendo permiso.
  h.once('error', (err: NodeJS.ErrnoException) => { if (err.code === 'ENOENT') historial(`No se pudo abrir ${e.titulo}: ${err.message}`); else psLanzar(exe, [], cwd, true) })
  h.unref()
  historial(`Abrió ${e.titulo} (${exe})`)
  return { ok: true, mensaje: `Abierto: ${e.titulo}.` }
}

/** shell.openPath devuelve un texto de error (vacío si fue bien): se pasa tal cual a la interfaz en vez de decir siempre «abierto». */
const abrirRuta = async (ruta: string, nombre: string) => { const err = await shell.openPath(ruta); return err ? { ok: false, mensaje: `No se pudo abrir ${nombre}: ${err}` } : { ok: true, mensaje: `Abierto: ${nombre}.` } }

async function lanzarOtro(e: Elemento): Promise<{ ok: boolean; mensaje: string }> {
  // Pack público (OcultarPeligro): los informes viven en %TEMP%; en el personal, en Datos\Informes del pendrive
  const informes = esPublico() ? informesTemp : join(datos, 'Informes')
  switch (e.tipo) {
    case 'run': {
      // Va por «cmd /c start»: ni el programa ni los argumentos del catálogo pueden llevar metacaracteres de cmd, comillas ni controles.
      // («cmd» es otra cosa: es una línea de shell a propósito y el catálogo lleva huella de integridad.)
      const argumentos = e.runArgs ? e.runArgs.split(' ').filter(Boolean) : []
      // Un nombre suelto se busca en System32: «cmd /c start perfmon.exe» no debe poder resolver un .exe plantado en %TEMP%
      const programa = programaDelSistema(e.run!)
      const SIN_META = /^[^\x00-\x1f&|<>^"]+$/
      if (![programa, ...argumentos].every((t) => SIN_META.test(t))) return { ok: false, mensaje: `No se lanza ${e.titulo}: la orden del catálogo lleva caracteres no permitidos (& | < > ^ comillas).` }
      const h = spawn(CMD, ['/c', 'start', '', programa, ...argumentos], { windowsHide: true, stdio: 'ignore', detached: true })
      suelto(h, e.titulo); historial(`Abrió ${e.titulo}`); return { ok: true, mensaje: `Abierto: ${e.titulo}.` }
    }
    case 'cmd': ventanaCmd(e.cmd!); historial(`Ejecutó ${e.titulo}`); return { ok: true, mensaje: `${e.titulo} en marcha en una ventana aparte.` }
    case 'html': {
      const rutaHtml = join(raiz, 'Scripts', e.html!), bloqueo = motivoBloqueo(rutaHtml)
      if (bloqueo) { historial(`BLOQUEADO ${e.titulo}: ${bloqueo}`); return { ok: false, mensaje: `Error crítico: no se abre ${e.titulo} porque ${basename(rutaHtml)} ${bloqueo}.` } }
      const r = await abrirRuta(rutaHtml, e.titulo); if (r.ok) historial(`Abrió ${e.titulo}`); return r }
    case 'uri':
      if (!/^https?:\/\//i.test(e.uri ?? '')) return { ok: false, mensaje: 'Enlace no permitido.' }
      void shell.openExternal(e.uri!); historial(`Abrió ${e.titulo}`); return { ok: true, mensaje: `Abierto: ${e.titulo}.` }
    case 'accion': {
      if (informes === informesTemp || existsSync(join(datos, 'kit.id'))) mkdirSync(informes, { recursive: true })   // nunca se crea Datos en una unidad ausente
      if (e.accion === 'AbrirHistorial') { const d = join(baseTrabajo(), 'Historial'); if (baseTrabajo() !== datos || existsSync(join(datos, 'kit.id'))) mkdirSync(d, { recursive: true }); return abrirRuta(d, 'la carpeta del historial') }
      if (e.accion === 'AbrirInformes') return abrirRuta(informes, 'la carpeta de informes')
      // powercfg se ejecuta sin pasar por cmd (ninguna ruta ni nombre de equipo llega a una línea de órdenes) y el informe se ve en la propia app
      if (e.accion === 'CmdBateria' || e.accion === 'CmdEnergia') {
        const bateria = e.accion === 'CmdBateria'
        return ejecutarScript({ id: 'powercfg', titulo: bateria ? 'Informe de batería' : 'Informe de energía (60 s)', script: 'Powercfg_Para_App.ps1', timeout: 300 } as Elemento, { NIT_POWERCFG: bateria ? 'battery' : 'energy' })
      }
      if (e.accion === 'SmartDetalle') { const bloqueo = motivoBloqueo(join(raiz, 'Scripts', 'SMART_Detalle.ps1')); if (bloqueo) return { ok: false, mensaje: `Error crítico: SMART_Detalle.ps1 ${bloqueo}.` }; psLanzar(POWERSHELL, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', join(raiz, 'Scripts', 'SMART_Detalle.ps1')]); historial('Abrió SMART detallado'); return { ok: true, mensaje: 'Abierto: SMART detallado.' } }
      break
    }
  }
  return { ok: false, mensaje: 'Esta herramienta todavía solo está en el lanzador clásico.' }
}

// ---------- Informes HTML: se muestran dentro de la app ----------
// Informes permitidos: los de Datos\ y los que solo viven en %TEMP%\Nitrit0_Cache\Informes (batería, energía, licencias: no se guardan en el pendrive).
const informesTemp = join(os.tmpdir(), 'Nitrit0_Cache', 'Informes')
const real = (p: string) => { try { return realpathSync.native(p).toLowerCase() } catch { return resolve(p).toLowerCase() } }   // expande nombres cortos 8.3 (ORDENA~1) y enlaces
const dentroDeDatos = (ruta: string, ext: string) => {
  const r = real(ruta)
  return r.endsWith(ext) && [datos, informesTemp].some((d) => r.startsWith(real(d) + '\\')) && existsSync(ruta)
}
function cargarInforme(ruta: string): { ruta: string; html: string } | null {
  try {
    if (!dentroDeDatos(ruta, '.html') || statSync(ruta).size > 8 << 20) return null
    return { ruta, html: quitarBom(readFileSync(ruta, 'utf8')) }
  } catch { return null }
}

/** Si el pendrive no estaba al terminar, se reintenta cada 2 s durante 3 minutos. El registro local sigue siendo válido mientras tanto; si al final no vuelve, se anota en el historial local. */
function copiarCuandoVuelva(local: string, nombre: string, intento = 0) {
  if (intento >= 90) { historial(`El pendrive no volvió a tiempo: el registro ${nombre} se queda en ${local}`); return }
  setTimeout(() => {
    try {
      if (existsSync(join(datos, 'kit.id'))) { const d = join(datos, 'Logs', 'Ejecuciones'); mkdirSync(d, { recursive: true }); copyFileSync(local, join(d, nombre)); try { unlinkSync(local) } catch { /* se queda */ } return }
    } catch { /* se reintenta */ }
    copiarCuandoVuelva(local, nombre, intento + 1)
  }, 2000)
}

// ---------- Scripts de mantenimiento con salida en vivo ----------
interface Marcha { proc: ChildProcess; id: string; titulo: string; t0: number; limite: number; clase: string; cancelado: boolean; agotado: boolean; forzado: boolean; lineas: string[]; cola: string[]; restos: [string, string]; temporizadores: NodeJS.Timeout[]; forzar?: () => void }
let marcha: Marcha | null = null
// Salida pedida por la persona mientras había un script en marcha: se cierra desde `terminar`, cuando el registro ya está escrito.
let salidaPendiente = false
// Cola de herramientas (scripts) pedidas mientras otra está en marcha: se ejecutan una tras otra al terminar. Solo en memoria: si la app se cierra, la cola se pierde.
interface EnCola { id: string; titulo: string }
const colaEjecucion: EnCola[] = []
const MAX_COLA = 10
const PAUSA_COLA_MS = 4000   // margen para leer cómo terminó lo anterior antes de que empiece lo siguiente
const avisarCola = () => enviar('ejec:cola', colaEjecucion.map((x) => ({ ...x })))
const enviar = (canal: string, carga: unknown) => { try { if (!ventana.isDestroyed() && !ventana.webContents.isDestroyed()) ventana.webContents.send(canal, carga) } catch { /* ventana cerrándose */ } }
const matar = (pid: number | undefined) => { if (pid) suelto(spawn(TASKKILL, ['/PID', String(pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore' }), 'taskkill') }
const stamp = () => { const d = new Date(), p = (n: number) => String(n).padStart(2, '0'); return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}_${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}` }

function ejecutarScript(e: Elemento, extraEnv: Record<string, string> = {}, clase: 'script' | 'diagnostico' | 'equilibrio' | 'auto' = 'script', alFin?: (correcto: boolean) => void): { ok: boolean; mensaje: string } {
  if (marcha) return { ok: false, mensaje: `Ya hay algo en marcha: ${marcha.titulo}. Espera a que termine o cancélalo.` }
  const ruta = join(raiz, 'Scripts', e.script!)
  if (!existsSync(ruta)) return { ok: false, mensaje: `No encuentro el script ${e.script}.` }
  // El lanzador (Ejecutar_Para_App) y Comun.ps1 se ejecutan antes de cualquier comprobación propia: se verifican aquí junto al script.
  for (const r of [ruta, join(raiz, 'Scripts', 'Ejecutar_Para_App.ps1'), join(raiz, 'Scripts', 'Comun.ps1')]) {
    const motivo = motivoBloqueo(r)
    if (motivo) { historial(`BLOQUEADO ${basename(r)}: ${motivo}`); return { ok: false, mensaje: `Error crítico: no se ejecuta ${basename(r)} porque ${motivo}. Si lo has actualizado tú, ejecuta Regenerar_Integridad.ps1; si no, revisa el kit antes de usarlo.` } }
  }
  const limite = (e.timeout ?? 1800) * 1000
  // NIT_AUTO / NIT_SIN_PREGUNTAS saltan las confirmaciones: solo los pasa la revisión automática (extraEnv), nunca se heredan del entorno.
  // También los ganchos de banco de pruebas de la revisión automática (NIT_AUTO_PRUEBA*, NIT_AUTO_FORZAR): no deben poder activarse desde el entorno
  const entorno = entornoLimpio()
  const proc = spawn(POWERSHELL,
    ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', join(raiz, 'Scripts', 'Ejecutar_Para_App.ps1'), '-Script', ruta],
    { cwd: os.tmpdir(), env: { ...entorno, ...extraEnv, NIT_RAIZ: raiz }, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] })
  const m: Marcha = { proc, id: e.id, titulo: e.titulo, t0: Date.now(), limite: limite / 1000, clase, cancelado: false, agotado: false, forzado: false, lineas: [], cola: [], restos: ['', ''], temporizadores: [] }
  marcha = m
  historial(`Ejecutó script ${e.script}`)

  const procesar = (l: string) => {
    {
      if (/^\W{0,3}#< CLIXML/.test(l) || /^\W{0,3}<Objs /.test(l)) return
      // Write-Progreso (Comun.ps1): «paso a de t» y un texto corto para la barra de avance; no se añade a la salida.
      const pro = /^##PROGRESO##(.+)$/.exec(l.trim())
      if (pro) { try { const j = JSON.parse(pro[1]); enviar('ejec:progreso', { actual: Math.max(0, Number(j.a) || 0), total: Math.max(0, Number(j.t) || 0), texto: String(j.x ?? '').slice(0, 120) }) } catch { /* línea cortada: se ignora */ } return }
      // Open-Informe (Comun.ps1) avisa con esta línea en vez de abrir el navegador.
      const inf = /^##INFORME##(.+)$/.exec(l.trim())
      if (inf) { const c = cargarInforme(inf[1]); if (c) enviar('ejec:informe', c); return }
      // Diagnostico_Para_App.ps1, Equilibrio_Para_App.ps1 y Arreglo_Automatico_Para_App.ps1 emiten sus resultados como JSON en una línea marcada.
      const dat = /^##(DX|EQ|AUTO)##(.+)$/.exec(l.trim())
      if (dat) {
        try {
          const j = JSON.parse(dat[2])
          enviar(dat[1] === 'DX' ? 'ejec:dx' : dat[1] === 'EQ' ? 'ejec:eq' : 'ejec:auto', j)
          if (dat[1] === 'AUTO') return   // la consola ya recibe el texto equivalente del propio script
          const r = dat[1] === 'EQ' ? `Cuello de botella (${j.perfil}): ${j.veredicto}`
            : j.t === 'fin' ? `[${String(j.estado).toUpperCase()}] ${j.id}: ${j.resumen}`
            : j.t === 'terminado' ? `Diagnóstico terminado en ${j.seg} s: ${j.fallos} fallo(s), ${j.avisos} aviso(s)` : null
          if (r) { m.lineas.push(r); m.cola.push(r) }
        } catch { /* línea cortada: se ignora */ }
        return
      }
      m.lineas.push(l); m.cola.push(l)
    }
  }
  // stdout y stderr llegan por separado: cada flujo tiene su búfer para no mezclar trozos de una línea partida
  const alimentar = (flujo: 0 | 1) => (trozo: string) => {
    const partes = (m.restos[flujo] + trozo).split(/\r?\n/)
    m.restos[flujo] = partes.pop() ?? ''
    for (const l of partes) procesar(l)
  }
  ;([proc.stdout!, proc.stderr!] as const).forEach((s, i) => { s.setEncoding('utf8'); s.on('data', alimentar(i as 0 | 1)) })
  const volcar = () => { if (m.cola.length) enviar('ejec:lineas', m.cola.splice(0)) }
  let sinUnidad = false
  m.temporizadores.push(setInterval(volcar, 150))
  m.temporizadores.push(setInterval(() => {
    const ok = existsSync(join(datos, 'kit.id'))
    if (!ok && !sinUnidad) { sinUnidad = true; enviar('ejec:aviso', 'La unidad del kit se ha desconectado. El script sigue, pero reconecta el pendrive cuanto antes.') }
    else if (ok && sinUnidad) { sinUnidad = false; enviar('ejec:aviso', 'La unidad del kit ha vuelto.') }
  }, 3000))
  m.temporizadores.push(setTimeout(() => {
    // Si ya terminó y solo falta la gracia de 'close', no es un tiempo agotado: su 'exit' lo cierra con el código real
    if (marcha !== m || proc.exitCode !== null) return
    m.agotado = true
    matar(proc.pid)
    m.forzar?.()
  }, limite))

  const terminar = (codigo: number | null) => {
    if (marcha !== m) return   // ya cerrada: por 'error', o por 'exit' antes de que llegara 'close'
    m.temporizadores.forEach((t) => { clearInterval(t); clearTimeout(t) })
    for (const r of m.restos) if (r) procesar(r)
    volcar()
    const seg = Math.round((Date.now() - m.t0) / 1000)
    const cancel = m.cancelado || codigo === 2   // contrato de los scripts: 0 bien, 1 error, 2 cancelado (no es un fallo)
    const motivo = cancel ? 'Cancelado' : m.agotado ? `Tiempo máximo agotado (${Math.round(limite / 60000)} min)` : codigo === 0 ? 'Terminó correctamente' : `Terminó con código ${codigo}`
    const nombre = `${stamp()}_${basename(e.script!, '.ps1').replace(/[^\w-]/g, '_')}.log`
    const local = join(os.tmpdir(), 'Nitrit0_Cache', 'Logs', nombre)
    let registro: string | null = null
    try {
      mkdirSync(dirname(local), { recursive: true })
      writeFileSync(local, '﻿' + m.lineas.join('\r\n'), 'utf8'); registro = local
      // El registro de la ejecución solo se copia al pendrive en el pack personal, y nunca si el script imprime claves (Wi-Fi, BitLocker); en el público se queda en %TEMP%
      const sensible = /Red_WiFi_y_Claves|Auditoria_Licencias_BitLocker/.test(e.script!)
      if (esPublico() || sensible) { /* queda solo en %TEMP%\Nitrit0_Cache\Logs */ }
      else if (existsSync(join(datos, 'kit.id'))) { const d = join(datos, 'Logs', 'Ejecuciones'); mkdirSync(d, { recursive: true }); copyFileSync(local, join(d, nombre)); registro = join(d, nombre); try { unlinkSync(local) } catch { /* se queda */ } }   // la salida puede llevar claves o datos del cliente: no se deja copia en el equipo ajeno
      else copiarCuandoVuelva(local, nombre)
    } catch { /* sin registro */ }
    historial(`Script ${e.script}: ${motivo} en ${seg} s`)
    registroKit(`Script ${e.script}: ${motivo} en ${seg} s`, (codigo === 0 || cancel) && !m.agotado ? 'INFO' : 'AVISO')
    marcha = null
    const correcto = !m.cancelado && !m.agotado && codigo === 0
    enviar('ejec:fin', { id: m.id, titulo: m.titulo, codigo, motivo, seg, correcto, cancelado: cancel, registro })
    alFin?.(correcto)
    siguienteDeLaCola(m.cancelado)   // si la persona canceló, la cola se descarta: no se sigue con lo demás
    if (salidaPendiente) { salidaPendiente = false; salirDeVerdad = true; app.quit() }   // el registro ya está escrito: ahora sí se puede salir
  }
  // taskkill puede fallar (permisos, pid ya reutilizado) y entonces ni 'exit' ni 'close' llegan: tras la gracia se libera el ejecutor
  m.forzar = () => {
    if (marcha !== m || m.forzado) return
    m.forzado = true
    m.temporizadores.push(setTimeout(() => { if (marcha === m) terminar(m.proc.exitCode) }, 5000))
  }
  proc.on('close', terminar)
  // Si un hijo del script hereda las tuberías, 'close' tarda en llegar o no llega: con el proceso ya muerto se cierra tras un margen para vaciar la salida.
  proc.once('exit', (codigo) => { setTimeout(() => terminar(codigo), 1500) })
  // Si PowerShell ni siquiera arranca no llega 'close': se libera el ejecutor para que la app no se quede bloqueada.
  proc.on('error', (err) => {
    if (marcha !== m) return
    m.temporizadores.forEach((t) => { clearInterval(t); clearTimeout(t) })
    marcha = null
    enviar('ejec:fin', { id: m.id, titulo: m.titulo, codigo: null, motivo: `No se pudo iniciar PowerShell: ${err.message}`, seg: 0, correcto: false, registro: null })
    alFin?.(false)
    siguienteDeLaCola(false)
  })
  enviar('ejec:inicio', { id: e.id, titulo: e.titulo, limite: limite / 1000, clase })
  return { ok: true, mensaje: `${e.titulo} en marcha.` }
}

// ---------- Ajustes de Windows: lectura y cambio con lista blanca (Ajustes_Para_App.ps1) ----------
// La interfaz solo manda un id y una clave de opción; qué clave del registro se toca y qué valores son válidos lo decide el script, que lleva huella en Integridad.json.
let colaAjustes: Promise<unknown> = Promise.resolve()
let pendientesAjustes = 0
function ajustesPs(args: string[]): Promise<unknown> {
  const script = join(raiz, 'Scripts', 'Ajustes_Para_App.ps1')
  for (const r of [script, join(raiz, 'Scripts', 'Comun.ps1')]) { const m = motivoBloqueo(r); if (m) return Promise.reject(new Error(`${basename(r)} bloqueado: ${m}`)) }
  const entorno = entornoLimpio()
  return new Promise((ok, fallo) =>
    execFile(POWERSHELL, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script, ...args],
      { windowsHide: true, maxBuffer: 2 << 20, timeout: 60000, cwd: os.tmpdir(), env: { ...entorno, NIT_RAIZ: raiz } },
      (err, salida) => {
        const linea = String(salida).split(/\r?\n/).find((l) => l.startsWith('##AJ##'))   // el script devuelve su error como JSON aunque salga con código 1
        if (!linea) return fallo(err ?? new Error('PowerShell no devolvió datos legibles.'))
        try { ok(JSON.parse(linea.slice(6))) } catch { fallo(new Error('Respuesta ilegible del script de ajustes.')) }
      })
  )
}

// ---------- Estado del equipo ----------
const resumen = () => leerJsonPs('Resumen_Sistema.ps1')
const discos = () => leerJsonPs('Discos_Para_App.ps1')
/** Script de solo lectura que imprime un JSON: se comprueba su huella antes de lanzarlo. */
function leerJsonPs(nombre: string): Promise<unknown> {
  const script = join(raiz, 'Scripts', nombre)
  const motivo = motivoBloqueo(script)
  if (motivo) return Promise.reject(new Error(`${nombre} bloqueado: ${motivo}`))
  return new Promise((ok, fallo) =>
    execFile(POWERSHELL, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script],
      { windowsHide: true, maxBuffer: 4 << 20, timeout: 60000, env: entornoLimpio() },
      (err, salida) => {
        if (err) return fallo(err)
        try { ok(JSON.parse(quitarBom(salida))) } catch { fallo(new Error('PowerShell no devolvió datos legibles.')) }
      })
  )
}
const esAdmin = () => new Promise<boolean>((ok) => execFile(FLTMC, [], { windowsHide: true }, (err) => ok(!err)))

let previa = os.cpus()
function vivo() {
  const ahora = os.cpus()
  let inactivo = 0, total = 0
  ahora.forEach((c, i) => {
    const p = previa[i].times, t = c.times
    inactivo += t.idle - p.idle
    total += (t.user - p.user) + (t.nice - p.nice) + (t.sys - p.sys) + (t.irq - p.irq) + (t.idle - p.idle)
  })
  previa = ahora
  return { cpu: total ? Math.round(100 * (1 - inactivo / total)) : 0, ramUsadaGb: +((os.totalmem() - os.freemem()) / 2 ** 30).toFixed(1), ramGb: +(os.totalmem() / 2 ** 30).toFixed(1) }
}

// ---------- Ajustes y favoritos (los mismos ficheros que el lanzador) ----------
const rutaAjustes = join(datos, 'Ajustes.json')
// Tema: «oscuro», «claro» o «sistema» (el de Windows). Ajustes.json guarda el modo elegido en TemaModo y, en Tema, el efectivo en ese momento (lo leen las herramientas antiguas de PowerShell, que solo conocen oscuro y claro).
type ModoTema = 'oscuro' | 'claro' | 'sistema'
const modoTema = (): ModoTema => { const a = leerJson<{ Tema?: string; TemaModo?: string }>(rutaAjustes, {}); return a.TemaModo === 'sistema' || a.TemaModo === 'claro' || a.TemaModo === 'oscuro' ? a.TemaModo : a.Tema === 'claro' ? 'claro' : 'oscuro' }
const temaEfectivo = (m: ModoTema): 'oscuro' | 'claro' => (m === 'sistema' ? (nativeTheme.shouldUseDarkColors ? 'oscuro' : 'claro') : m)
const rutaFavs = join(datos, 'Favoritos.json')
// Las mismas cinco que trae el lanzador cuando todavía no existe Favoritos.json
const FAVORITAS_INICIALES = ['Diagnóstico completo', 'Pantallazos y eventos', 'Licencias y BitLocker', 'Instalar apps básicas', 'Reparar Windows y Tienda']
function leerJson<T>(ruta: string, defecto: T): T { try { return JSON.parse(quitarBom(readFileSync(ruta, 'utf8'))) as T } catch { return defecto } }
// Se escribe a un temporal y se renombra: si el pendrive se suelta a medias, el fichero anterior queda intacto.
function escribirJson(ruta: string, valor: unknown) {
  try { writeFileSync(ruta + '.tmp', '﻿' + JSON.stringify(valor, null, 2), 'utf8'); renameSync(ruta + '.tmp', ruta) } catch { /* unidad no disponible */ }
}

/** Al terminar una ejecución: si hay cola y no se canceló, arranca la siguiente tras una pausa corta. Una que no se pueda lanzar se avisa y se pasa a la siguiente. */
function siguienteDeLaCola(descartar: boolean) {
  if (descartar) { if (colaEjecucion.length) { colaEjecucion.length = 0; avisarCola(); enviar('ejec:aviso', 'Has cancelado: se ha vaciado la cola.') } return }
  if (!colaEjecucion.length) return
  setTimeout(() => {
    if (marcha) return   // la persona ha lanzado otra cosa en la pausa: la cola sigue cuando esa termine
    const s = colaEjecucion.shift(); avisarCola()
    if (!s) return
    void lanzarId(s.id).then((r) => { if (!r.ok) { enviar('ejec:aviso', `De la cola: ${s.titulo} no se pudo iniciar. ${r.mensaje}`); siguienteDeLaCola(false) } })
  }, PAUSA_COLA_MS)
}

async function lanzarId(id: string): Promise<{ ok: boolean; mensaje: string }> {
  const e = leerCatalogo().elementos.find((x) => x.id === id)
  if (!e) return { ok: false, mensaje: 'Herramienta desconocida.' }
  if (e.peligro && !e.publicoOk && esPublico()) { historial(`BLOQUEADO ${e.titulo}: herramienta delicada en el pack público`); return { ok: false, mensaje: 'Esta herramienta está desactivada en este pack.' } }
  // Con un script normal en marcha, otro script se pone en cola (diagnóstico, cuello de botella y revisión automática no admiten cola)
  if (marcha && (e.tipo === 'script' || e.tipo === 'informe')) {
    if (marcha.clase !== 'script') return { ok: false, mensaje: `Ya hay algo en marcha: ${marcha.titulo}. Espera a que termine o cancélalo.` }
    if (colaEjecucion.some((x) => x.id === id)) return { ok: false, mensaje: `${e.titulo} ya está en la cola.` }
    if (colaEjecucion.length >= MAX_COLA) return { ok: false, mensaje: `La cola está llena (${MAX_COLA}).` }
    colaEjecucion.push({ id, titulo: e.titulo }); avisarCola(); historial(`En cola: ${e.titulo} (puesto ${colaEjecucion.length})`)
    return { ok: true, mensaje: `${e.titulo} en cola (puesto ${colaEjecucion.length}): empieza cuando termine ${marcha.titulo}.` }
  }
  try {
    if (e.tipo === 'informe') return ejecutarScript({ ...e, script: 'Informe_Rapido.ps1', timeout: 300 })   // el informe rápido vive fuera de Mantenimiento
    return e.tipo === 'script' ? ejecutarScript(e) : e.tipo === 'exe' ? lanzarApp(e) : await lanzarOtro(e)
  }
  catch (err) { return { ok: false, mensaje: `No se pudo abrir ${e.titulo}: ${(err as Error).message}` } }
}

// ---------- Perfil de uso (Ahorro / Equilibrado / Juego) y bandeja del sistema ----------
// Los tres son modos que ya trae Optimizador_Personal.ps1 (con punto de restauración y respaldo para Revertir); la interfaz y la bandeja solo eligen uno de esta lista cerrada.
const PERFILES = {
  ahorro: { titulo: 'Ahorro', ayuda: 'Internet y poco más', modo: 'PerfilAhorro' },
  equilibrado: { titulo: 'Equilibrado', ayuda: 'Lo que trae Windows', modo: 'PerfilEquilibrado' },
  juego: { titulo: 'Juego', ayuda: 'Máximo rendimiento', modo: 'PerfilJuego' }
} as const
type IdPerfil = keyof typeof PERFILES
const perfilActual = (): IdPerfil | null => { const v = leerJson<{ PerfilUso?: string }>(rutaAjustes, {}).PerfilUso; return v && v in PERFILES ? (v as IdPerfil) : null }
const avisar = (titulo: string, cuerpo: string) => { try { if (Notification.isSupported()) new Notification({ title: titulo, body: cuerpo }).show() } catch { /* sin avisos del sistema */ } }
const mostrarVentana = () => { if (!ventana || ventana.isDestroyed()) return; if (ventana.isMinimized()) ventana.restore(); ventana.show(); ventana.focus() }

function aplicarPerfil(id: unknown): { ok: boolean; mensaje: string } {
  if (typeof id !== 'string' || !(id in PERFILES)) return { ok: false, mensaje: 'Perfil no válido.' }
  const p = PERFILES[id as IdPerfil]
  const el = { id: 'perfil', titulo: `Perfil ${p.titulo}`, script: 'Mantenimiento\\Optimizador_Personal.ps1', timeout: 900 } as Elemento
  const r = ejecutarScript(el, { NIT_OPT_MODO: p.modo }, 'script', (correcto) => {
    if (correcto) { escribirJson(rutaAjustes, { ...leerJson<Record<string, unknown>>(rutaAjustes, {}), PerfilUso: id }); registroKit(`Perfil de uso: ${p.titulo}`); montarBandeja() }
    avisar('Nitrit0 Kit', correcto ? `Perfil ${p.titulo} aplicado.` : `No se pudo aplicar el perfil ${p.titulo}. Abre la app para ver el motivo.`)
  })
  if (!r.ok) avisar('Nitrit0 Kit', r.mensaje)
  return r
}

const NOMBRE_TAREA = 'Nitrit0 Kit Bandeja'
/** Un arranque con Windows que apunte a un pendrive fallaría cada vez que no esté puesto: se exige que la app esté en un disco fijo (también en el pack público, donde la persona lo activa a propósito). */
const enUnidadExtraible = (ruta: string) => new Promise<boolean>((ok) => {
  if (!/^[A-Za-z]:/.test(ruta)) return ok(true)   // ruta de red u otra cosa que no es una letra de unidad
  execFile(POWERSHELL, ['-NoProfile', '-Command', `(New-Object IO.DriveInfo '${ruta.slice(0, 2)}').DriveType`], { windowsHide: true, timeout: 15000 }, (err, so) => ok(!!err || /Removable|Network|CDRom/i.test(String(so))))
})
const tareaExiste = () => new Promise<boolean>((ok) => execFile(SCHTASKS, ['/query', '/tn', NOMBRE_TAREA], { windowsHide: true }, (err) => ok(!err)))
// `estado` se pide al arrancar y tras cada cambio de perfil: schtasks y fltmc son dos procesos por llamada, así que se guardan 10 s (se invalida al cambiar el arranque)
let cacheEstado: { t: number; arranque: boolean; admin: boolean } | null = null
const arranqueYAdmin = async () => { if (cacheEstado && Date.now() - cacheEstado.t < 10_000) return cacheEstado; const [arranque, admin] = await Promise.all([tareaExiste(), esAdmin()]); return (cacheEstado = { t: Date.now(), arranque, admin }) }
/** Arranque con Windows: tarea programada al iniciar sesión con privilegios altos (el .exe pide administrador y una clave Run se quedaría esperando el aviso de UAC). Solo la persona la activa y se quita con el mismo interruptor. */
async function ponerArranque(activar: boolean, exeDestino?: string, rutaAj: string = rutaAjustes): Promise<{ ok: boolean; mensaje: string }> {
  const lanzar = (args: string[]) => new Promise<{ ok: boolean; texto: string }>((ok) => execFile(SCHTASKS, args, { windowsHide: true, timeout: 20000 }, (err, so, se) => ok({ ok: !err, texto: String(se || so || err?.message || '').trim() })))
  if (!activar) {
    const r = await lanzar(['/delete', '/tn', NOMBRE_TAREA, '/f'])
    escribirJson(rutaAj, { ...leerJson<Record<string, unknown>>(rutaAj, {}), Bandeja: false })
    registroKit('Arranque con Windows desactivado')
    return r.ok || !(await tareaExiste()) ? { ok: true, mensaje: 'La app ya no arranca con Windows.' } : { ok: false, mensaje: `No se pudo quitar la tarea: ${r.texto}` }
  }
  if (dev) return { ok: false, mensaje: 'El arranque con Windows solo se activa con la app empaquetada.' }
  // La tarea corre con privilegios altos: solo se apunta a la copia de Archivos de programa (donde un usuario normal no puede cambiar el .exe ni los scripts)
  if (!exeDestino && !estaInstalada()) return { ok: false, mensaje: 'Para arrancar con Windows primero pulsa «Instalar en este equipo»: así el programa queda en Archivos de programa, donde nadie sin permisos de administrador puede modificarlo.' }
  const exe = exeDestino ?? process.env.PORTABLE_EXECUTABLE_FILE ?? process.execPath
  if (!existsSync(exe)) return { ok: false, mensaje: 'No encuentro el .exe de la app.' }
  if (await enUnidadExtraible(exe)) return { ok: false, mensaje: 'La app está en un pendrive o unidad externa: copia la carpeta del kit al disco del equipo, ábrela desde ahí y vuelve a activarlo.' }
  const r = await lanzar(['/create', '/tn', NOMBRE_TAREA, '/tr', `"${exe}" --bandeja`, '/sc', 'onlogon', '/rl', 'highest', '/f'])
  if (!r.ok) return { ok: false, mensaje: `No se pudo crear la tarea (hace falta administrador): ${r.texto}` }
  escribirJson(rutaAj, { ...leerJson<Record<string, unknown>>(rutaAj, {}), Bandeja: true })
  registroKit(`Arranque con Windows activado (${exe})`)
  return { ok: true, mensaje: 'Listo: la app arrancará con Windows y se quedará junto al reloj.' }
}

// ---------- Instalación pequeña en el equipo (Archivos de programa) ----------
// Copia la app, los scripts y el catálogo (sin Apps\, que es lo que pesa); Archivos de programa solo lo escribe un administrador, y la tarea de arranque corre con privilegios altos.
const dirInstalacion = join(process.env.ProgramFiles ?? 'C:\\Program Files', 'Nitrit0 Kit')
const accesoInicio = join(process.env.ProgramData ?? 'C:\\ProgramData', 'Microsoft', 'Windows', 'Start Menu', 'Programs', 'Nitrit0 Kit.lnk')
const estaInstalada = () => resolve(raiz).toLowerCase() === resolve(dirInstalacion).toLowerCase()
const hayInstalacion = () => existsSync(join(dirInstalacion, 'Nitrit0.exe'))
async function instalarEnEquipo(): Promise<{ ok: boolean; mensaje: string }> {
  if (dev) return { ok: false, mensaje: 'La instalación solo se hace con la app empaquetada.' }
  if (estaInstalada() || hayInstalacion()) return { ok: false, mensaje: 'Ya hay una instalación en este equipo.' }
  if (marcha) return { ok: false, mensaje: `Ya hay algo en marcha: ${marcha.titulo}. Espera a que termine.` }
  // Dos formas de ir empaquetada: .exe único portable (PORTABLE_EXECUTABLE_FILE) o carpeta App\Motor con un lanzador Nitrit0.exe fino (arranca sin descomprimir nada)
  const motor = join(raiz, 'App', 'Motor')
  const enCarpeta = !process.env.PORTABLE_EXECUTABLE_FILE && existsSync(join(motor, 'Nitrit0 Kit.exe')) && existsSync(join(raiz, 'Nitrit0.exe'))
  const exe = enCarpeta ? join(raiz, 'Nitrit0.exe') : process.env.PORTABLE_EXECUTABLE_FILE
  if (!exe || !existsSync(exe)) return { ok: false, mensaje: 'No encuentro el .exe de la app.' }
  const existia = existsSync(dirInstalacion)
  try {
    mkdirSync(dirInstalacion, { recursive: true })
    copyFileSync(exe, join(dirInstalacion, 'Nitrit0.exe'))
    if (enCarpeta) cpSync(motor, join(dirInstalacion, 'App', 'Motor'), { recursive: true })
    cpSync(join(raiz, 'Scripts'), join(dirInstalacion, 'Scripts'), { recursive: true })
    mkdirSync(join(dirInstalacion, 'App', 'datos'), { recursive: true })
    copyFileSync(join(raiz, 'App', 'datos', 'herramientas.json'), join(dirInstalacion, 'App', 'datos', 'herramientas.json'))
    const d = join(dirInstalacion, 'Datos'); mkdirSync(d, { recursive: true })
    for (const f of ['kit.id', 'Integridad.json', 'Ajustes.json']) if (existsSync(join(datos, f))) copyFileSync(join(datos, f), join(d, f))
    const nuevoExe = join(dirInstalacion, 'Nitrit0.exe')
    shell.writeShortcutLink(accesoInicio, 'create', { target: nuevoExe, description: 'Nitrit0 Kit', icon: nuevoExe, iconIndex: 0 })
    const r = await ponerArranque(true, nuevoExe, join(d, 'Ajustes.json'))
    registroKit(`Instalada en ${dirInstalacion}`)
    return { ok: true, mensaje: r.ok ? 'Instalada en Archivos de programa: arrancará con Windows y la tienes en el menú Inicio.' : `Instalada en el menú Inicio, pero sin arranque con Windows: ${r.mensaje}` }
  } catch (err) {
    try { unlinkSync(accesoInicio) } catch { /* aún no existía */ }
    if (!existia) { try { rmSync(dirInstalacion, { recursive: true, force: true }) } catch { /* se queda a medias: se quita a mano */ } }
    return { ok: false, mensaje: `No se pudo instalar: ${(err as Error).message}` }
  }
}
async function quitarInstalacion(): Promise<{ ok: boolean; mensaje: string }> {
  if (!hayInstalacion() || basename(dirInstalacion) !== 'Nitrit0 Kit') return { ok: false, mensaje: 'No hay una instalación que quitar.' }
  await ponerArranque(false, undefined, join(dirInstalacion, 'Datos', 'Ajustes.json'))
  try { unlinkSync(accesoInicio) } catch { /* sin acceso */ }
  registroKit('Instalación quitada')
  if (estaInstalada()) {   // el .exe en marcha no se puede borrar: se espera a que la app se cierre
    salirDeVerdad = true
    suelto(spawn(CMD, ['/d', '/s', '/c', `"ping -n 4 127.0.0.1 >nul & rmdir /s /q "${dirInstalacion}""`], { windowsHide: true, stdio: 'ignore', detached: true, windowsVerbatimArguments: true }), 'quitar instalación')
    setTimeout(() => app.quit(), 500)
    return { ok: true, mensaje: 'Quitando la instalación: la app se cierra.' }
  }
  try { rmSync(dirInstalacion, { recursive: true, force: true }); return { ok: true, mensaje: 'Instalación quitada.' } }
  catch (err) { return { ok: false, mensaje: `No se pudo quitar la carpeta: ${(err as Error).message}` } }
}

// ---------- Liberar memoria (a mano, desde la bandeja o sola cuando la RAM se llena) ----------
function memoriaPs(): Promise<{ ok: boolean; mensaje?: string; antesMb?: number; despuesMb?: number; procesos?: number }> {
  const script = join(raiz, 'Scripts', 'Memoria_Para_App.ps1')
  for (const r of [script, join(raiz, 'Scripts', 'Comun.ps1')]) { const m = motivoBloqueo(r); if (m) return Promise.resolve({ ok: false, mensaje: `${basename(r)} bloqueado: ${m}` }) }
  return new Promise((ok) => execFile(POWERSHELL, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script],
    { windowsHide: true, maxBuffer: 1 << 20, timeout: 60000, cwd: os.tmpdir(), env: { ...entornoLimpio(), NIT_RAIZ: raiz } },
    (err, salida) => {
      const l = String(salida).split(/\r?\n/).find((x) => x.startsWith('##MEM##'))
      if (!l) return ok({ ok: false, mensaje: err?.message ?? 'PowerShell no devolvió datos legibles.' })
      try { ok(JSON.parse(l.slice(7))) } catch { ok({ ok: false, mensaje: 'Respuesta ilegible del script de memoria.' }) }
    }))
}
let liberando = false
async function liberarMemoria(origen: 'manual' | 'auto'): Promise<{ ok: boolean; mensaje: string }> {
  if (liberando) return { ok: false, mensaje: 'Ya se está liberando memoria.' }
  liberando = true
  try {
    const r = await memoriaPs()
    if (!r.ok) return { ok: false, mensaje: r.mensaje ?? 'No se pudo liberar memoria.' }
    const mensaje = `Memoria liberada: ${Math.max(0, (r.despuesMb ?? 0) - (r.antesMb ?? 0))} MB más libres (${r.despuesMb} MB libres en total). Es un alivio momentáneo: Windows recarga lo que se vuelva a usar.`
    registroKit(`${mensaje} (${origen})`)
    return { ok: true, mensaje }
  } finally { liberando = false }
}
const memoriaAutoActiva = () => leerJson<{ MemoriaAuto?: boolean }>(rutaAjustes, {}).MemoriaAuto === true
let ultimaLimpiezaAuto = 0
/** Con la opción activada, si la RAM pasa del 90 % se libera sola (como mucho una vez cada 10 minutos y nunca con un script en marcha: falsearía sus mediciones). */
function vigilarMemoria() {
  setInterval(() => {
    if (!memoriaAutoActiva() || perfilActual() === 'juego' || liberando || marcha || Date.now() - ultimaLimpiezaAuto < 10 * 60_000) return
    const usado = 1 - os.freemem() / os.totalmem()
    if (usado < 0.9) return
    ultimaLimpiezaAuto = Date.now()
    void liberarMemoria('auto').then((r) => avisar('Nitrit0 Kit', r.ok ? `La memoria estaba al ${Math.round(usado * 100)} %. ${r.mensaje}` : r.mensaje))
  }, 30_000)
}

let bandeja: Tray | null = null
function limpiarDesdeBandeja() {
  void dialog.showMessageBox({ type: 'question', buttons: ['Cancelar', 'Limpiar'], defaultId: 0, cancelId: 0, title: 'Limpiar temporales', message: '¿Limpiar los archivos temporales de este equipo?', detail: 'Borra temporales de Windows, caché de navegadores y papelera. No toca documentos.' })
    .then((r) => { if (r.response === 1) { mostrarVentana(); void lanzarId('LimpiarTemporalesEquipo.ps1').then((x) => { if (!x.ok) avisar('Nitrit0 Kit', x.mensaje) }) } })
}
/** Cancelar la ejecución y salir en cuanto `terminar` escriba el registro: ni doble aviso ni pérdida del log. */
function cancelarYsalir() {
  if (!marcha) { salirDeVerdad = true; app.quit(); return }
  salidaPendiente = true
  marcha.cancelado = true
  matar(marcha.proc.pid)
  marcha.forzar?.()
}
/** Salir desde la bandeja: con un script en marcha se pregunta antes de matarlo (cerrar la ventana lo deja vivo y minimizado). */
function salirConAviso() {
  if (!marcha) { salirDeVerdad = true; app.quit(); return }
  void dialog.showMessageBox({ type: 'warning', buttons: ['Seguir en la app', 'Salir y cancelar'], defaultId: 0, cancelId: 0, title: 'Ejecución en curso', message: `${marcha.titulo} sigue en marcha.`, detail: '¿Salir y cancelarlo? Lo que ya cambió no se deshace solo.' })
    .then((r) => { if (r.response === 1) cancelarYsalir() })
}
function montarBandeja() {
  const actual = perfilActual()
  if (!bandeja) {
    const ruta = app.isPackaged ? join(process.resourcesPath, 'icono.png') : join(__dirname, '../../build/icono-256.png')
    bandeja = new Tray(nativeImage.createFromPath(ruta).resize({ width: 24, height: 24 }))
    bandeja.on('click', mostrarVentana)
  }
  bandeja.setToolTip(`Nitrit0 Kit${actual ? ` · modo ${PERFILES[actual].titulo}` : ''}`)
  bandeja.setContextMenu(Menu.buildFromTemplate([
    { label: 'Nitrit0 Kit', enabled: false },
    { type: 'separator' },
    ...(Object.keys(PERFILES) as IdPerfil[]).map((id) => ({ label: `${PERFILES[id].titulo} · ${PERFILES[id].ayuda}`, type: 'radio' as const, checked: actual === id, click: () => { aplicarPerfil(id) } })),
    { type: 'separator' },
    { label: 'Limpiar temporales…', click: limpiarDesdeBandeja },
    { label: 'Liberar memoria ahora', click: () => { void liberarMemoria('manual').then((r) => avisar('Nitrit0 Kit', r.mensaje)) } },
    { label: 'Liberar sola si la RAM pasa del 90 %', type: 'checkbox', checked: memoriaAutoActiva(), click: (i) => { escribirJson(rutaAjustes, { ...leerJson<Record<string, unknown>>(rutaAjustes, {}), MemoriaAuto: i.checked }); montarBandeja() } },
    { label: 'Abrir Nitrit0 Kit', click: mostrarVentana },
    { label: 'Salir', click: salirConAviso }
  ]))
}

function crearVentana() {
  // El tema guardado se aplica ya a los botones de la ventana, no solo al pulsar el botón de tema
  const tema0 = temaEfectivo(modoTema())
  ventana = new BrowserWindow({
    width: 1280, height: dev ? Number(process.env.NITRIT0_ALTO ?? 800) : 800, minWidth: 960, minHeight: 600, backgroundColor: tema0 === 'claro' ? '#FAFAFA' : '#141415', title: 'Nitrit0 Kit', show: !enBandeja, icon: app.isPackaged ? join(process.resourcesPath, 'icono.png') : join(__dirname, '../../build/icono-256.png'),
    titleBarStyle: 'hidden', titleBarOverlay: { ...colores[tema0], height: 40 },
    webPreferences: { preload: join(__dirname, '../preload/index.js'), contextIsolation: true, sandbox: true }
  })
  nativeTheme.on('updated', () => {
    if (modoTema() !== 'sistema' || !ventana || ventana.isDestroyed()) return
    const ef = temaEfectivo('sistema')
    ventana.setTitleBarOverlay({ ...colores[ef], height: 40 })   // Ajustes.json no se toca: es un cambio del sistema, no una acción de la persona (y en el pack público es el pendrive)
  })
  ventana.on('close', (ev) => {
    // Ya se pidió salir con un script en marcha: se espera a que `terminar` escriba el registro y cierre desde allí
    if (salidaPendiente) { ev.preventDefault(); return }
    // Con el arranque con Windows activado, cerrar la ventana la guarda junto al reloj (se sale desde el icono); un script en marcha sigue.
    if (!salirDeVerdad && (enBandeja || leerJson<{ Bandeja?: boolean }>(rutaAjustes, {}).Bandeja === true)) { ev.preventDefault(); ventana.hide(); return }
    if (!marcha) return
    ev.preventDefault()
    void dialog.showMessageBox(ventana, { type: 'warning', buttons: ['Seguir en la app', 'Cerrar y cancelar'], defaultId: 0, cancelId: 0, title: 'Ejecución en curso', message: `${marcha.titulo} sigue en marcha.`, detail: '¿Cerrar la ventana y cancelarlo? Lo que ya cambió no se deshace solo.' })
      .then((r) => { if (r.response === 1) cancelarYsalir() })
  })
  // La interfaz es local: ninguna navegación ni ventana nueva, para que una página externa nunca reciba window.kit.
  ventana.webContents.setWindowOpenHandler(() => ({ action: 'deny' }))
  const propia = dev && process.env.ELECTRON_RENDERER_URL ? process.env.ELECTRON_RENDERER_URL : pathToFileURL(join(__dirname, '../renderer/index.html')).href
  // Se compara la URL entera (protocolo, equipo y ruta), no su texto: «http://localhost:5173.evil.com» empieza igual que la propia
  const esPropia = (url: string) => { try { const a = new URL(url), b = new URL(propia); return a.protocol === b.protocol && a.host === b.host && a.pathname === b.pathname } catch { return false } }
  ventana.webContents.on('will-navigate', (ev, url) => { if (!esPropia(url)) ev.preventDefault() })
  // Sin menú de Electron (Ctrl+R recargaría la interfaz con un script en marcha y Ctrl+Mayús+I abriría las herramientas de desarrollo); el zoom se deja a mano
  if (!dev) Menu.setApplicationMenu(null)
  ventana.webContents.on('before-input-event', (ev, i) => {
    if (i.type !== 'keyDown' || !i.control) return
    const z = ventana.webContents.getZoomLevel()
    if (i.key === '+' || i.key === '=') { ventana.webContents.setZoomLevel(Math.min(z + 0.5, 3)); ev.preventDefault() }
    else if (i.key === '-') { ventana.webContents.setZoomLevel(Math.max(z - 0.5, -2)); ev.preventDefault() }
    else if (i.key === '0') { ventana.webContents.setZoomLevel(0); ev.preventDefault() }
  })
  if (dev && process.env.ELECTRON_RENDERER_URL) void ventana.loadURL(process.env.ELECTRON_RENDERER_URL)
  else void ventana.loadFile(join(__dirname, '../renderer/index.html'), { hash: dev ? process.env.NITRIT0_VISTA : undefined })
  ventana.webContents.once('did-finish-load', () => {
    trazaApp('Interfaz cargada')
    const z = leerJson<{ Zoom?: number }>(rutaAjustes, {}).Zoom
    if (typeof z === 'number' && z > 1 && z <= 1.5) ventana.webContents.setZoomFactor(z)
  })

  // Modo prueba, como -Captura del lanzador: guarda un PNG y sale.
  const captura = dev ? process.env.NITRIT0_CAPTURA : undefined   // ganchos de prueba solo en desarrollo
  if (captura) {
    const espera = Number(process.env.NITRIT0_ESPERA ?? 6) * 1000
    ventana.webContents.once('did-finish-load', () => {
      // Prueba de extremo a extremo: NITRIT0_LANZAR=<id> lanza esa herramienta como si se pulsara su botón.
      if (process.env.NITRIT0_LISTAR) void listarCatalogo().then((c) => c.elementos.filter((x) => x.tipo === 'exe').forEach((x) => console.log(`${x.disponible ? 'OK ' : 'FALTA'} ${x.icono ? 'icono' : 'sin-icono'} ${x.titulo}`)))
      // Varias herramientas separadas por coma se lanzan con 1,5 s de diferencia: sirve para probar la cola (la 2.ª entra mientras la 1.ª sigue en marcha)
      if (process.env.NITRIT0_LANZAR) process.env.NITRIT0_LANZAR.split(',').forEach((idx, i) => setTimeout(() => void lanzarId(idx.trim()).then((r) => console.log(JSON.stringify(r))), 2500 + i * 1500))
      setTimeout(async () => {
        // Solo desarrollo: NITRIT0_CLIC=<selector css> pulsa ese elemento antes de la captura (para ver un panel abierto)
        // Varios clics en cadena se separan con « >> » (por ejemplo, ir a una página y luego abrir un desplegable)
        if (process.env.NITRIT0_CLIC) { try { for (const sel of process.env.NITRIT0_CLIC.split(' >> ')) { await ventana.webContents.executeJavaScript(`document.querySelector(${JSON.stringify(sel)})?.click()`); await new Promise((ok) => setTimeout(ok, 4000)) } } catch { /* sin clic */ } }
        writeFileSync(captura, (await ventana.webContents.capturePage()).toPNG()); app.quit()
      }, espera)
    })
  }
}

// Una sola ventana: dos instancias podrían lanzar dos scripts a la vez sobre el mismo equipo.
const unica = app.requestSingleInstanceLock()
if (!unica) app.quit()
else app.on('second-instance', mostrarVentana)

/** Endurecimiento (guía de seguridad de Electron): solo se atiende al marco principal de la ventana propia (ni subventanas ni iframes) y se deniega todo permiso del navegador salvo copiar al portapapeles. */
const deMiVentana = (f: Electron.WebFrameMain | null) => f !== null && !!ventana && !ventana.isDestroyed() && f === ventana.webContents.mainFrame
const handle = (canal: string, fn: Parameters<typeof ipcMain.handle>[1]) => ipcMain.handle(canal, (e, ...a) => { if (!deMiVentana(e.senderFrame)) throw new Error('Origen no permitido'); return fn(e, ...a) })
const soloPortapapeles = (permiso: string) => permiso === 'clipboard-sanitized-write'
// Cámara, micrófono y pantalla completa solo para las pruebas del propio kit (Scripts\Pruebas, con huella comprobada al abrirlas): ninguna otra página ni marco los recibe.
const dePruebas = (url?: string) => !!url && url.toLowerCase().startsWith(`${pathToFileURL(join(raiz, 'Scripts', 'Pruebas')).href.toLowerCase()}/`)
// Marcos de prueba montados: pruebaEntrar suma y pruebaSalir resta. Es un contador y no un booleano: al pasar de una prueba a otra el cleanup de la anterior llega DESPUÉS de abrir la nueva y la dejaba sin permiso.
let pruebasAbiertas = 0
const permitido = (permiso: string, url?: string, principal?: boolean) => soloPortapapeles(permiso) || ((permiso === 'media' || permiso === 'fullscreen') && (dePruebas(url) || (principal === false && pruebasAbiertas > 0)))
function cerrarPermisos() {
  session.defaultSession.setPermissionRequestHandler((_w, permiso, cb, d) => {
    const ok = permitido(permiso, d.requestingUrl, d.isMainFrame)
    if (!ok && (permiso === 'media' || permiso === 'fullscreen')) trazaApp(`Permiso ${permiso} denegado (petición): url=${d.requestingUrl} principal=${d.isMainFrame} pruebas=${pruebasAbiertas}`)
    cb(ok)
  })
  session.defaultSession.setPermissionCheckHandler((_w, permiso, origen, d) => {
    const ok = permitido(permiso, d.requestingUrl || d.securityOrigin || origen, d.isMainFrame)
    if (!ok && (permiso === 'media' || permiso === 'fullscreen')) trazaApp(`Permiso ${permiso} denegado (comprobación): url=${d.requestingUrl} origen=${d.securityOrigin || origen} principal=${d.isMainFrame} pruebas=${pruebasAbiertas}`)
    return ok
  })
}

app.whenReady().then(() => {
  if (!unica) return
  trazaApp('Electron listo')
  cerrarPermisos()
  app.setAppUserModelId('es.nitrit0.kit')   // sin esto Windows puede descartar las notificaciones
  handle('catalogo', () => listarCatalogo())
  handle('resumen', () => resumen())
  handle('discos', () => discos())
  handle('ajustes', (_e, op: { accion?: unknown; id?: unknown; opcion?: unknown }) => {
    if (op?.accion === 'leer') return ajustesPs(['-Accion', 'Leer'])
    if (op?.accion === 'aplicar' && typeof op.id === 'string' && typeof op.opcion === 'string' && /^[a-z_]{1,30}$/.test(op.id) && /^[a-z]{1,30}$/.test(op.opcion)) {
      const { id, opcion } = op
      historial(`Ajuste de Windows ${id}: ${opcion}`)
      if (pendientesAjustes >= 5) return Promise.reject(new Error('Hay demasiados cambios seguidos: espera a que terminen los anteriores.'))
      pendientesAjustes++
      colaAjustes = colaAjustes.catch(() => undefined).then(() => ajustesPs(['-Accion', 'Aplicar', '-Id', id, '-Opcion', opcion])).finally(() => { pendientesAjustes-- })   // de uno en uno, con un máximo de 5 en espera
      return colaAjustes
    }
    return Promise.reject(new Error('Petición de ajuste no válida.'))
  })
  handle('vivo', () => vivo())
  handle('perfil', (_e, id: unknown) => aplicarPerfil(id))
  handle('perfilPreguntado', () => { escribirJson(rutaAjustes, { ...leerJson<Record<string, unknown>>(rutaAjustes, {}), PerfilPreguntado: true }) })
  handle('arranque', (_e, on: unknown) => ponerArranque(on === true).finally(() => { cacheEstado = null }))
  handle('memoria', () => liberarMemoria('manual'))
  handle('memoriaAuto', (_e, on: unknown) => { escribirJson(rutaAjustes, { ...leerJson<Record<string, unknown>>(rutaAjustes, {}), MemoriaAuto: on === true }); montarBandeja() })
  handle('elevar', () => reabrirComoAdmin())
  handle('instalar', () => instalarEnEquipo())
  handle('quitarInstalacion', () => quitarInstalacion())
  handle('estado', async () => { const c = await arranqueYAdmin(); return { instalada: estaInstalada(), hayInstalacion: hayInstalacion(), puedeInstalar: !dev, memoriaAuto: memoriaAutoActiva(), perfil: perfilActual(), preguntado: leerJson<{ PerfilPreguntado?: boolean }>(rutaAjustes, {}).PerfilPreguntado === true, arranque: c.arranque, admin: c.admin, ocultarPeligro: leerJson<{ OcultarPeligro?: boolean }>(rutaAjustes, {}).OcultarPeligro === true,tema: modoTema(), modo: leerJson<{ Modo?: string }>(rutaAjustes, {}).Modo === 'tecnico' ? 'tecnico' : 'sencillo', ultima: leerJson<{ Ultima?: unknown }>(rutaAjustes, {}).Ultima ?? null, favoritos: leerJson<string[]>(rutaFavs, FAVORITAS_INICIALES), kit: raiz, zoom: leerJson<{ Zoom?: number }>(rutaAjustes, {}).Zoom ?? 1 } })
  handle('ejecucionActual', () => (marcha ? { id: marcha.id, titulo: marcha.titulo, limite: marcha.limite, clase: marcha.clase, t0: marcha.t0, lineas: marcha.lineas.slice(-4000) } : null))
  handle('tema', (_e, t: unknown) => {
    const modo: ModoTema = t === 'claro' || t === 'sistema' ? t : 'oscuro'
    const efectivo = temaEfectivo(modo)
    ventana.setTitleBarOverlay({ ...colores[efectivo], height: 40 })
    escribirJson(rutaAjustes, { ...leerJson<Record<string, unknown>>(rutaAjustes, {}), Tema: efectivo, TemaModo: modo })
  })
  // Tamaño de letra: zoom de toda la interfaz (100/115/130/150 %), se recuerda entre usos
  handle('zoom', (_e, f: unknown) => {
    const v = [1, 1.15, 1.3, 1.5].includes(Number(f)) ? Number(f) : 1
    ventana.webContents.setZoomFactor(v)
    escribirJson(rutaAjustes, { ...leerJson<Record<string, unknown>>(rutaAjustes, {}), Zoom: v })
  })
  // Modo sencillo (una sola pantalla de ayuda) o técnico (todo el kit): se recuerda entre usos.
  handle('modo', (_e, m: string) => { escribirJson(rutaAjustes, { ...leerJson<Record<string, unknown>>(rutaAjustes, {}), Modo: m === 'tecnico' ? 'tecnico' : 'sencillo' }) })
  // Reinicio con 30 s de margen (Windows lo avisa en pantalla) y posibilidad de arrepentirse. Solo lo pide la interfaz tras confirmar.
  handle('guardarUltima', (_e, u: { titular?: unknown; hora?: unknown; enfoque?: unknown; actualizar?: unknown; antivirus?: unknown; cliente?: unknown }) => {
    const s = (v: unknown, n: number) => (typeof v === 'string' ? v.slice(0, n) : '')
    if (typeof u?.hora !== 'number') return
    escribirJson(rutaAjustes, { ...leerJson<Record<string, unknown>>(rutaAjustes, {}), Ultima: { titular: s(u.titular, 300), hora: u.hora, enfoque: s(u.enfoque, 20), actualizar: u.actualizar === true, antivirus: u.antivirus === true, cliente: s(u.cliente, 200) } })
  })
  handle('reiniciar', () => new Promise<{ ok: boolean; mensaje: string }>((ok) => {
    const h = spawn(join(sys32, 'shutdown.exe'), ['/r', '/t', '30', '/c', 'Nitrit0 Kit reinicia el equipo para terminar los arreglos.'], { windowsHide: true, stdio: 'ignore' })
    h.on('error', (e) => ok({ ok: false, mensaje: `No se pudo pedir el reinicio: ${e.message}` }))
    h.on('exit', (codigo) => {
      if (codigo !== 0) return ok({ ok: false, mensaje: `Windows no aceptó el reinicio (código ${codigo ?? '?'}).` })
      historial('Pidió reiniciar el equipo')
      ok({ ok: true, mensaje: 'El equipo se reiniciará en 30 segundos.' })
    })
  }))
  handle('cancelarReinicio', () => { suelto(spawn(join(sys32, 'shutdown.exe'), ['/a'], { windowsHide: true, stdio: 'ignore' }), 'shutdown'); return { ok: true, mensaje: 'Reinicio cancelado.' } })
  handle('favoritos', (_e, lista: string[]) => { if (Array.isArray(lista)) escribirJson(rutaFavs, lista.filter((x) => typeof x === 'string')) })
  // El renderer solo manda un id; todo lo que se ejecuta sale del catálogo, nunca de lo que envíe la interfaz.
  handle('lanzar', (_e, id: string) => lanzarId(id))
  // Pruebas de teclado, ratón, pantalla, webcam y audio: se muestran DENTRO de la app. La interfaz solo manda un id; la ruta sale del catálogo y se comprueba su huella.
  handle('pruebaEntrar', () => { pruebasAbiertas++ })   // lo llama el componente que monta el marco, y pruebaSalir al desmontarlo: el par queda siempre simétrico
  handle('pruebaSalir', () => { pruebasAbiertas = Math.max(0, pruebasAbiertas - 1) })
  // Cámara/micrófono: lo que Windows permite a las apps de escritorio (Configuración > Privacidad). La app no cambia ese ajuste: solo lo lee y abre la página de Windows donde la persona lo activa.
  handle('mediaEstado', (_e, tipo: unknown) => { try { return systemPreferences.getMediaAccessStatus(tipo === 'microphone' ? 'microphone' : 'camera') } catch { return 'unknown' } })
  handle('ajustesPrivacidad', (_e, tipo: unknown) => { void shell.openExternal(tipo === 'microphone' ? 'ms-settings:privacy-microphone' : 'ms-settings:privacy-webcam') })
  handle('pruebaUrl', (_e, id: unknown) => {
    const e = typeof id === 'string' ? leerCatalogo().elementos.find((x) => x.id === id) : undefined
    if (!e || e.tipo !== 'html' || !e.html || !/^Pruebas[\\/]/.test(e.html)) return { ok: false, mensaje: 'Prueba desconocida.' }
    const ruta = join(raiz, 'Scripts', e.html), bloqueo = motivoBloqueo(ruta)
    if (bloqueo) { historial(`BLOQUEADO ${e.titulo}: ${bloqueo}`); return { ok: false, mensaje: `Error crítico: no se abre ${e.titulo} porque ${basename(ruta)} ${bloqueo}.` } }
    historial(`Abrió ${e.titulo} (dentro de la app)`)
    return { ok: true, titulo: e.titulo, url: pathToFileURL(ruta).href, mensaje: '' }
  })
  // Diagnóstico y cuello de botella: la interfaz solo elige opciones de una lista cerrada; el motor es el del kit.
  handle('diagnostico', (_e, opc: { modo?: string; ficha?: Record<string, unknown> }) => {
    const modo = opc?.modo === 'Completo' ? 'Completo' : 'Rapido'
    const ficha: Record<string, string> = {}
    for (const k of ['Cliente', 'Telefono', 'Motivo', 'Notas']) { const v = opc?.ficha?.[k]; if (typeof v === 'string') ficha[k] = v.slice(0, 500) }
    const el = { id: 'diagnostico', titulo: modo === 'Completo' ? 'Diagnóstico profundo' : 'Diagnóstico rápido', script: 'Diagnostico_Para_App.ps1', timeout: modo === 'Completo' ? 3600 : 900 } as Elemento
    return ejecutarScript(el, { NIT_DX_MODO: modo, NIT_DX_FICHA: JSON.stringify(ficha) }, 'diagnostico')
  })
  handle('informeEntrega', (_e, d: { cliente?: unknown; notas?: unknown }) => {
    const t = (v: unknown) => (typeof v === 'string' ? v.slice(0, 500) : '')
    const el = leerCatalogo().elementos.find((x) => x.id === 'Informe_Entrega.ps1')
    if (!el) return { ok: false, mensaje: 'No encuentro el informe de entrega en el catálogo.' }
    return ejecutarScript(el, { NIT_CLIENTE: t(d?.cliente), NIT_NOTAS: t(d?.notas) })
  })
  handle('equilibrio', (_e, perfil: string) => {
    const p = ['General', 'Juegos', 'Creacion', 'Oficina'].includes(perfil) ? perfil : 'General'
    return ejecutarScript({ id: 'equilibrio', titulo: 'Cuello de botella', script: 'Equilibrio_Para_App.ps1', timeout: 300 } as Elemento, { NIT_EQ_PERFIL: p }, 'equilibrio')
  })
  // Revisar y arreglar: la interfaz solo manda si se instalan también las actualizaciones y el nombre del cliente; los pasos y sus tiempos máximos están en el script.
  handle('revisionAuto', (_e, opc: { actualizar?: unknown; antivirus?: unknown; cliente?: unknown; enfoque?: unknown }) => {
    const enfoque = ['lento', 'internet', 'avisos', 'virus', 'espacio'].includes(String(opc?.enfoque)) ? String(opc.enfoque) : 'todo'
    const cliente = typeof opc?.cliente === 'string' ? opc.cliente.trim().slice(0, 200) : ''
    const flag = join(os.tmpdir(), 'Nitrit0_Cache', 'saltar.flag')
    try { unlinkSync(flag) } catch { /* no había */ }
    const el = { id: 'auto', titulo: 'Revisar y arreglar el equipo', script: 'Arreglo_Automatico_Para_App.ps1', timeout: 4 * 3600 } as Elemento
    return ejecutarScript(el, { NIT_DX_MODO: 'Rapido', NIT_AUTO: '1', NIT_AUTO_SALTAR: flag, NIT_AUTO_ACTUALIZAR: opc?.actualizar === true ? '1' : '0', NIT_AUTO_CONFIRMAR: join(os.tmpdir(), 'Nitrit0_Cache', 'confirmar.json'), NIT_AUTO_ENFOQUE: enfoque, NIT_AUTO_ANTIVIRUS: opc?.antivirus === true ? '1' : '0', NIT_DX_FICHA: JSON.stringify({ Cliente: cliente }) }, 'auto')
  })
  // La persona responde al plan: qué pasos se hacen (lista cerrada) o ninguno. El script espera este fichero antes de cambiar nada.
  handle('autoConfirmar', (_e, ids: unknown) => {
    if (marcha?.clase !== 'auto') return { ok: false, mensaje: 'No hay una revisión esperando.' }
    const permitidos = ['restauracion', 'limpieza', 'limpieza_profunda', 'red', 'seguridad', 'antivirus', 'wu', 'actualizar', 'actualizar_programas', 'integridad', 'optimizar', ...(dev ? ['prueba'] : [])]   // «prueba» solo en desarrollo
    const lista = Array.isArray(ids) ? ids.filter((x): x is string => typeof x === 'string' && permitidos.includes(x)) : []
    try { mkdirSync(join(os.tmpdir(), 'Nitrit0_Cache'), { recursive: true }); writeFileSync(join(os.tmpdir(), 'Nitrit0_Cache', 'confirmar.json'), JSON.stringify({ ids: lista }), 'utf8'); return { ok: true, mensaje: 'Entendido.' } }
    catch (err) { return { ok: false, mensaje: `No se pudo enviar la respuesta: ${(err as Error).message}` } }
  })
  // Combos: la interfaz elige pasos de una lista cerrada (los del script); el resto lo decide el script.
  handle('combo', (_e, opc: { pasos?: unknown; cliente?: unknown }) => {
    const permitidos = ['limpieza', 'limpieza_profunda', 'red', 'seguridad', 'antivirus', 'wu', 'actualizar', 'actualizar_programas', 'integridad', 'optimizar', 'deshacer']
    const pasos = Array.isArray(opc?.pasos) ? [...new Set(opc.pasos.filter((x): x is string => typeof x === 'string' && permitidos.includes(x)))] : []
    if (!pasos.length) return { ok: false, mensaje: 'Elige al menos un paso.' }
    const cliente = typeof opc?.cliente === 'string' ? opc.cliente.trim().slice(0, 200) : ''
    const flag = join(os.tmpdir(), 'Nitrit0_Cache', 'saltar.flag')
    try { unlinkSync(flag) } catch { /* no había */ }
    const el = { id: 'auto', titulo: 'Combo de mantenimiento', script: 'Arreglo_Automatico_Para_App.ps1', timeout: 8 * 3600 } as Elemento
    return ejecutarScript(el, { NIT_DX_MODO: 'Rapido', NIT_AUTO: '1', NIT_AUTO_SALTAR: flag, NIT_COMBO: pasos.join(','), NIT_DX_FICHA: JSON.stringify({ Cliente: cliente }) }, 'auto')
  })
  // «Saltar este paso»: el script mira este fichero cada segundo y cierra el paso en curso (con sus procesos) para seguir con el siguiente.
  handle('autoSaltar', () => {
    if (marcha?.clase !== 'auto') return { ok: false, mensaje: 'No hay una revisión en marcha.' }
    try { mkdirSync(join(os.tmpdir(), 'Nitrit0_Cache'), { recursive: true }); writeFileSync(join(os.tmpdir(), 'Nitrit0_Cache', 'saltar.flag'), '1'); return { ok: true, mensaje: 'Saltando el paso actual…' } }
    catch (err) { return { ok: false, mensaje: `No se pudo saltar el paso: ${(err as Error).message}` } }
  })
  handle('cancelar', () => { if (marcha) { marcha.cancelado = true; matar(marcha.proc.pid); marcha.forzar?.() } if (colaEjecucion.length) { colaEjecucion.length = 0; avisarCola() } })
  handle('cola', () => colaEjecucion.map((x) => ({ ...x })))
  handle('colaQuitar', (_e, id: unknown) => { if (typeof id !== 'string') return; const i = colaEjecucion.findIndex((x) => x.id === id); if (i >= 0) { colaEjecucion.splice(i, 1); avisarCola() } })
  handle('colaVaciar', () => { if (colaEjecucion.length) { colaEjecucion.length = 0; avisarCola() } })
  handle('abrirInforme', (_e, ruta: string) => (typeof ruta === 'string' && dentroDeDatos(ruta, '.html') ? abrirRuta(ruta, 'el informe') : { ok: false, mensaje: 'Informe no permitido.' }))
  handle('abrirRegistro', (_e, ruta: string) => {
    if (typeof ruta !== 'string') return { ok: false, mensaje: 'Registro no permitido.' }
    const r = real(ruta)   // misma normalización que dentroDeDatos: expande 8.3 y enlaces antes de comparar (un junction bajo Logs no puede apuntar fuera)
    const permitidas = [join(datos, 'Logs', 'Ejecuciones'), join(os.tmpdir(), 'Nitrit0_Cache', 'Logs')].map((d) => real(d) + '\\')
    if (r.endsWith('.log') && permitidas.some((d) => r.startsWith(d)) && existsSync(ruta)) return abrirRuta(ruta, 'el registro')
    return { ok: false, mensaje: 'No encuentro el registro: puede que el pendrive no esté conectado.' }
  })
  crearVentana()
  montarBandeja()
  vigilarMemoria()
})
app.on('window-all-closed', () => { if (marcha) matar(marcha.proc.pid); app.quit() })
