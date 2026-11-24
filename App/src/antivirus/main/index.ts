import { app, BrowserWindow, dialog, ipcMain, Menu, nativeTheme, session, shell } from 'electron'
import { pathToFileURL } from 'node:url'
import { basename, dirname, extname, isAbsolute, join, relative, resolve } from 'node:path'
import { createReadStream, existsSync, readdirSync, readFileSync, realpathSync, renameSync, statSync, writeFileSync, type ReadStream } from 'node:fs'
import { execFile, spawn, spawnSync, type ChildProcess, type ExecFileOptions } from 'node:child_process'
import { createHash } from 'node:crypto'
import os from 'node:os'

// «Nitrit0 Antivirus»: revisa archivos con el Defender del propio equipo (solo informa, no borra ni pone en cuarentena)
// y, si hay clave, pregunta a VirusTotal por la huella SHA-256. El archivo nunca se sube: solo viaja la huella.
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
if (!dev) app.setPath('userData', join(os.tmpdir(), 'Nitrit0_Cache', 'ElectronAntivirus'))

const leerJson = <T,>(ruta: string, por: T): T => { try { return JSON.parse(quitarBom(readFileSync(ruta, 'utf8'))) as T } catch { return por } }
type ModoTema = 'oscuro' | 'claro' | 'sistema'
const modoTema = (): ModoTema => { const a = leerJson<{ Tema?: string; TemaModo?: string }>(join(datos, 'Ajustes.json'), {}); return a.TemaModo === 'sistema' || a.TemaModo === 'claro' || a.TemaModo === 'oscuro' ? a.TemaModo : a.Tema === 'claro' ? 'claro' : 'oscuro' }
const temaEfectivo = (m: ModoTema): 'oscuro' | 'claro' => (m === 'sistema' ? (nativeTheme.shouldUseDarkColors ? 'oscuro' : 'claro') : m)
const colores = { oscuro: { color: '#0F0F10', symbolColor: '#EDEDED' }, claro: { color: '#FFFFFF', symbolColor: '#171717' } }

// ---------- Clave de VirusTotal ----------
// Va en Datos\Antivirus.json del propio kit (no en el equipo del cliente). Datos no se copia a los packs; la interfaz solo sabe si hay clave, nunca la lee.
const rutaClave = join(datos, 'Antivirus.json')
const leerClave = (): string => { const c = leerJson<{ ClaveVT?: string }>(rutaClave, {}).ClaveVT; return typeof c === 'string' && /^[A-Za-z0-9]{32,128}$/.test(c) ? c : '' }
function guardarClave(c: string): 'ok' | 'formato' | 'sin-kit' | 'escritura' {
  if (c && !/^[A-Za-z0-9]{32,128}$/.test(c)) return 'formato'
  if (!existsSync(join(datos, 'kit.id'))) return 'sin-kit'   // nunca se crea Datos en una unidad ajena
  try { writeFileSync(rutaClave + '.tmp', '﻿' + JSON.stringify({ ClaveVT: c }), 'utf8'); renameSync(rutaClave + '.tmp', rutaClave); return 'ok' } catch { return 'escritura' }
}

// ---------- Procesos hijos: se registran para poder cortarlos al cancelar o al cerrar (si no, clamscan/MpCmdRun siguen con el pendrive abierto) ----------
const TASKKILL = join(sys32, 'taskkill.exe')
const hijos = new Set<ChildProcess>()
let cancelado = false
let abortar: AbortController | null = null
let flujoActual: ReadStream | null = null
function lanzar(exe: string, args: string[], opciones: ExecFileOptions, fin: (err: Error | null, salida: string) => void) {
  const p = execFile(exe, args, opciones, (err, salida) => { hijos.delete(p); fin(err, String(salida)) })
  hijos.add(p)
  p.once('exit', () => hijos.delete(p))
}
function matarHijos() {
  for (const p of hijos) if (p.pid && p.exitCode === null && p.signalCode === null) { try { spawn(TASKKILL, ['/PID', String(p.pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore' }).on('error', () => { /* ya había terminado */ }).unref() } catch { /* ya había terminado */ } }
  hijos.clear()
}
/** Al salir no se puede dejar el taskkill a medias: si el proceso principal muere antes, clamscan o MpCmdRun siguen con el pendrive abierto. Aquí se espera (máx. 5 s). */
function matarHijosYa() {
  for (const p of hijos) if (p.pid && p.exitCode === null && p.signalCode === null) { try { spawnSync(TASKKILL, ['/PID', String(p.pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore', timeout: 5000 }) } catch { /* ya había terminado */ } }
  hijos.clear()
}
const PS_UTF8 = '[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); '   // PowerShell 5.1 escribe en la página OEM (CP850): sin esto «Telefónica» llega como «Telefnica»

// ---------- Defender ----------
function rutaDefender(): string | null {
  const base = join(process.env.ProgramData ?? 'C:\\ProgramData', 'Microsoft', 'Windows Defender', 'Platform')
  try {
    for (const v of readdirSync(base).sort((a, b) => b.localeCompare(a, undefined, { numeric: true }))) { const p = join(base, v, 'MpCmdRun.exe'); if (existsSync(p)) return p }
  } catch { /* sin carpeta de plataforma */ }
  const p = join(process.env.ProgramFiles ?? 'C:\\Program Files', 'Windows Defender', 'MpCmdRun.exe')
  return existsSync(p) ? p : null
}
// El nombre de la amenaza sale de Defender por PowerShell; la ruta va por variable de entorno, no dentro del texto del script.
const PS_AMENAZA = PS_UTF8 + '$e=[WildcardPattern]::Escape($env:NIT_RUTA); $d=Get-MpThreatDetection | Where-Object { $_.Resources -like "*$e*" } | Sort-Object InitialDetectionTime -Descending | Select-Object -First 1; if ($d) { (Get-MpThreat -ThreatID $d.ThreatID).ThreatName }'

// En una carpeta puede haber muchas detecciones: se listan las de esa ruta registradas desde que empezó el análisis.
const PS_AMENAZAS_CARPETA = PS_UTF8 + '$e=[WildcardPattern]::Escape($env:NIT_RUTA); $desde=[datetime]::Parse($env:NIT_DESDE,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime(); $d=@(Get-MpThreatDetection | Where-Object { $_.Resources -like "*$e*" -and $_.InitialDetectionTime.ToUniversalTime() -ge $desde } | Select-Object -First 50); $r=foreach ($x in $d) { @{ Amenaza = [string](Get-MpThreat -ThreatID $x.ThreatID | Select-Object -First 1).ThreatName; Archivo = [string]($x.Resources | Select-Object -First 1) } }; ConvertTo-Json -InputObject @($r) -Compress'
type Hallazgo = { motor: 'Defender' | 'ClamAV'; nombre: string; archivo: string }
type Defender = { estado: 'limpio' | 'amenaza' | 'no-disponible'; amenaza?: string; detalle?: string; hallazgos?: Hallazgo[] }
const MIN_CARPETA = 60   // una carpeta entera tarda mucho más que un archivo
function escanearDefender(ruta: string, carpeta = false): Promise<Defender> {
  const mp = rutaDefender()
  if (!mp) return Promise.resolve({ estado: 'no-disponible', detalle: 'No se encuentra Microsoft Defender en este equipo.' })
  const minutos = carpeta ? MIN_CARPETA : 10
  const desde = new Date(Date.now() - 60000).toISOString()
  // -DisableRemediation: solo informar. Códigos de salida (números, no texto traducido): 0 limpio, 2 amenaza encontrada. -File admite carpetas.
  return new Promise((ok) => lanzar(mp, ['-Scan', '-ScanType', '3', '-File', ruta, '-DisableRemediation'], { windowsHide: true, timeout: minutos * 60 * 1000 }, (err) => {
    const codigo = err ? (err as { code?: unknown }).code : 0
    if (codigo === 0) return ok({ estado: 'limpio' })
    if (codigo === 2) {
      if (carpeta) {
        return lanzar(POWERSHELL, ['-NoProfile', '-NonInteractive', '-Command', PS_AMENAZAS_CARPETA], { windowsHide: true, timeout: 60000, env: { ...process.env, NIT_RUTA: ruta, NIT_DESDE: desde } }, (_e, salida) => {
          let hallazgos: Hallazgo[] = []
          try { hallazgos = (JSON.parse(salida.trim()) as { Amenaza?: string; Archivo?: string }[]).map((x) => ({ motor: 'Defender' as const, nombre: x.Amenaza || 'amenaza sin nombre', archivo: (x.Archivo ?? '').replace(/^file:_/, '') })) } catch { /* Defender avisó pero no se pudo leer el detalle */ }
          ok({ estado: 'amenaza', amenaza: hallazgos[0]?.nombre, hallazgos })
        })
      }
      return lanzar(POWERSHELL, ['-NoProfile', '-NonInteractive', '-Command', PS_AMENAZA], { windowsHide: true, timeout: 30000, env: { ...process.env, NIT_RUTA: ruta } }, (_e, salida) => {
        ok({ estado: 'amenaza', amenaza: salida.trim().split(/\r?\n/)[0] || undefined })
      })
    }
    const agotado = !!err && (err as { killed?: boolean }).killed === true
    ok({ estado: 'no-disponible', detalle: agotado ? `Defender tardó más de ${minutos} minutos y se cortó.` : 'Defender no pudo analizarlo (puede estar desactivado por otro antivirus, faltar permisos o no poderse leer lo elegido).' })
  }))
}

// ---------- Firma digital (Authenticode) ----------
// Solo para lo que puede llevar firma. El estado sale del nombre del enumerado de Windows (Valid, NotSigned, HashMismatch…), no de texto traducido.
const EXT_FIRMABLES = new Set(['.exe', '.dll', '.msi', '.sys', '.ocx', '.scr', '.cab', '.ps1', '.msix', '.appx', '.cat'])
const PS_FIRMA = PS_UTF8 + '$s = Get-AuthenticodeSignature -LiteralPath $env:NIT_RUTA; @{ Estado = [string]$s.Status; Firmante = if ($s.SignerCertificate) { $s.SignerCertificate.Subject } else { \'\' } } | ConvertTo-Json -Compress'
type Firma = { estado: 'firmado' | 'sin-firma' | 'invalida' | 'no-confiable' | 'error'; firmante?: string }
function leerFirma(ruta: string): Promise<Firma | null> {
  if (!EXT_FIRMABLES.has(extname(ruta).toLowerCase())) return Promise.resolve(null)
  return new Promise((ok) => lanzar(POWERSHELL, ['-NoProfile', '-NonInteractive', '-Command', PS_FIRMA], { windowsHide: true, timeout: 60000, env: { ...process.env, NIT_RUTA: ruta } }, (err, salida) => {
    if (err) return ok({ estado: 'error' })
    try {
      const j = JSON.parse(salida.trim()) as { Estado?: string; Firmante?: string }
      const cn = /CN=("([^"]+)"|[^,]+)/.exec(j.Firmante ?? '')
      const firmante = cn ? (cn[2] ?? cn[1]).trim() : undefined
      ok({ estado: j.Estado === 'Valid' ? 'firmado' : j.Estado === 'NotSigned' ? 'sin-firma' : j.Estado === 'HashMismatch' ? 'invalida' : 'no-confiable', firmante })
    } catch { ok({ estado: 'error' }) }
  }))
}

// ---------- Versión del archivo (la que lleva dentro el .exe/.dll) ----------
// Sirve para saber QUÉ versión se ha revisado: el mismo nombre puede ser otra compilación. Solo lectura de los datos de versión.
const EXT_VERSION = new Set(['.exe', '.dll', '.sys', '.ocx', '.scr', '.msi'])
const PS_VERSION = PS_UTF8 + '$v = (Get-Item -LiteralPath $env:NIT_RUTA).VersionInfo; @{ Archivo = [string]$v.FileVersion; Producto = [string]$v.ProductVersion; Nombre = [string]$v.ProductName; Empresa = [string]$v.CompanyName } | ConvertTo-Json -Compress'
type Version = { archivo: string; producto: string; nombre: string; empresa: string }
function leerVersion(ruta: string): Promise<Version | null> {
  if (!EXT_VERSION.has(extname(ruta).toLowerCase())) return Promise.resolve(null)
  return new Promise((ok) => lanzar(POWERSHELL, ['-NoProfile', '-NonInteractive', '-Command', PS_VERSION], { windowsHide: true, timeout: 30000, env: { ...process.env, NIT_RUTA: ruta } }, (err, salida) => {
    if (err) return ok(null)
    try {
      const j = JSON.parse(salida.trim()) as { Archivo?: string; Producto?: string; Nombre?: string; Empresa?: string }
      const v = { archivo: (j.Archivo ?? '').trim(), producto: (j.Producto ?? '').trim(), nombre: (j.Nombre ?? '').trim(), empresa: (j.Empresa ?? '').trim() }
      ok(v.archivo || v.producto || v.nombre || v.empresa ? v : null)
    } catch { ok(null) }
  }))
}

// ---------- ClamAV (opcional: solo si el pack lleva Apps\Antivirus\ClamAV) ----------
const dirClam = join(raiz, 'Apps', 'Antivirus', 'ClamAV')
const exeClam = join(dirClam, 'clamscan.exe'), dbClam = join(dirClam, 'db')
const hayClam = () => existsSync(exeClam) && existsSync(dbClam)
// Los binarios de ClamAV se ejecutan desde el pendrive: igual que los scripts del kit, deben constar en Datos\Integridad.json con su huella (si cambian o faltan, no se lanzan)
let manifiesto: Map<string, string> | null = null
function huellaMala(ruta: string): string | null {
  const comprobar = (): string | null => {
    try {
      if (!manifiesto) {
        const lista = JSON.parse(quitarBom(readFileSync(join(datos, 'Integridad.json'), 'utf8'))) as { R: string; H?: string }[]
        manifiesto = new Map(lista.filter((x) => x.H).map((x) => [x.R.toLowerCase(), x.H!.toUpperCase()]))
      }
      const esperado = manifiesto.get(relative(raiz, ruta).toLowerCase())
      if (!esperado) return 'no figura en Datos\\Integridad.json'
      return createHash('sha256').update(readFileSync(ruta)).digest('hex').toUpperCase() === esperado ? null : 'su contenido ha cambiado desde que se generó la integridad'
    } catch (e) { return `no se pudo comprobar su integridad (${(e as Error).message})` }
  }
  const m = comprobar()
  if (!m) return null
  manifiesto = null   // regenerar la integridad con la app abierta no obliga a reiniciarla: se relee una vez
  return comprobar()
}
const fechaClam = (): { fecha: string; dias: number } | null => {
  try { const t = readdirSync(dbClam).filter((f) => /\.(cvd|cld)$/i.test(f)).map((f) => statSync(join(dbClam, f)).mtimeMs); if (!t.length) return null; const ms = Math.max(...t); return { fecha: new Date(ms).toLocaleDateString('es-ES'), dias: Math.floor((Date.now() - ms) / 86400000) } } catch { return null }
}
type Clam = { estado: 'limpio' | 'amenaza' | 'error'; amenaza?: string; detalle?: string; hallazgos?: Hallazgo[] }
function escanearClam(ruta: string, carpeta = false): Promise<Clam | null> {
  if (!hayClam()) return Promise.resolve(null)
  const mala = huellaMala(exeClam)
  if (mala) return Promise.resolve({ estado: 'error', detalle: `ClamAV no se ha ejecutado: clamscan.exe ${mala}. Si lo actualizaste tú, ejecuta Regenerar_Integridad.ps1.` })
  const minutos = carpeta ? MIN_CARPETA : 15
  // Códigos de salida de clamscan: 0 limpio, 1 infectado, otro error (en una carpeta, 2 también sale si algún archivo no se pudo leer). El nombre sale de «<ruta>: <Nombre> FOUND» (FOUND es fijo de ClamAV, no se traduce).
  return new Promise((ok) => lanzar(exeClam, ['--database=' + dbClam, '--no-summary', '--infected', ...(carpeta ? ['-r'] : []), ruta], { windowsHide: true, timeout: minutos * 60 * 1000, maxBuffer: 4 << 20 }, (err, salida) => {
    const codigo = err ? (err as { code?: unknown }).code : 0
    if (codigo === 0) return ok({ estado: 'limpio' })
    const hallazgos = [...salida.matchAll(/^(.+): (.+) FOUND\s*$/gm)].slice(0, 50).map((m) => ({ motor: 'ClamAV' as const, nombre: m[2], archivo: m[1] }))
    if (codigo === 1 || hallazgos.length) return ok({ estado: 'amenaza', amenaza: hallazgos[0]?.nombre, hallazgos })
    ok({ estado: 'error', detalle: (err as { killed?: boolean } | null)?.killed ? `ClamAV tardó más de ${minutos} minutos y se cortó.` : carpeta && codigo === 2 ? 'ClamAV terminó con errores (algún archivo no se pudo leer) y no vio amenazas en el resto.' : 'ClamAV no pudo analizarlo.' })
  }))
}

// ---------- Estado y actualización de los motores (Defender del equipo y ClamAV del pack) ----------
const PS_ESTADO_DEFENDER = PS_UTF8 + "$s = Get-MpComputerStatus; @{ Activo = [bool]$s.AntivirusEnabled; Version = [string]$s.AntivirusSignatureVersion; Fecha = $s.AntivirusSignatureLastUpdated.ToUniversalTime().ToString('o') } | ConvertTo-Json -Compress"
type EstadoDefender = { activo: boolean; version: string; fecha: string; dias: number } | null
function estadoDefender(): Promise<EstadoDefender> {
  return new Promise((ok) => lanzar(POWERSHELL, ['-NoProfile', '-NonInteractive', '-Command', PS_ESTADO_DEFENDER], { windowsHide: true, timeout: 30000 }, (err, salida) => {
    if (err) return ok(null)
    try {
      const j = JSON.parse(salida.trim()) as { Activo?: boolean; Version?: string; Fecha?: string }
      const ms = Date.parse(j.Fecha ?? '')
      ok(Number.isFinite(ms) ? { activo: !!j.Activo, version: String(j.Version ?? ''), fecha: new Date(ms).toLocaleDateString('es-ES'), dias: Math.max(0, Math.floor((Date.now() - ms) / 86400000)) } : null)
    } catch { ok(null) }
  }))
}
/** Defender: MpCmdRun -SignatureUpdate (código 0 = bien). ClamAV: freshclam con la configuración y la base del propio pack. Ambos necesitan Internet. */
function actualizarMotor(motor: unknown): Promise<{ ok: boolean; mensaje: string }> {
  if (motor === 'defender') {
    const mp = rutaDefender()
    if (!mp) return Promise.resolve({ ok: false, mensaje: 'No se encuentra Microsoft Defender en este equipo.' })
    return new Promise((ok) => lanzar(mp, ['-SignatureUpdate'], { windowsHide: true, timeout: 10 * 60 * 1000 }, (err) => {
      const codigo = err ? (err as { code?: unknown }).code : 0
      ok(codigo === 0 ? { ok: true, mensaje: 'Defender: firmas actualizadas.' } : { ok: false, mensaje: cancelado ? 'Actualización cancelada.' : 'No se pudo actualizar Defender: hace falta Internet y, a veces, abrir la app como administrador.' })
    }))
  }
  if (motor === 'clam') {
    if (!hayClam()) return Promise.resolve({ ok: false, mensaje: 'Este pack no lleva ClamAV.' })
    const fc = join(dirClam, 'freshclam.exe'), conf = join(dirClam, 'freshclam.conf')
    if (!existsSync(fc) || !existsSync(conf)) return Promise.resolve({ ok: false, mensaje: 'Falta freshclam.exe o freshclam.conf en la carpeta de ClamAV.' })
    const mala = huellaMala(fc)
    if (mala) return Promise.resolve({ ok: false, mensaje: `No se ejecuta freshclam.exe: ${mala}. Si lo actualizaste tú, ejecuta Regenerar_Integridad.ps1.` })
    return new Promise((ok) => lanzar(fc, ['--config-file=' + conf, '--datadir=' + dbClam], { windowsHide: true, timeout: 15 * 60 * 1000, maxBuffer: 4 << 20 }, (err) => {
      const codigo = err ? (err as { code?: unknown }).code : 0
      ok(codigo === 0 ? { ok: true, mensaje: 'ClamAV: base de firmas al día.' } : { ok: false, mensaje: cancelado ? 'Actualización cancelada.' : 'No se pudo actualizar ClamAV: hace falta Internet (o el pendrive no deja escribir).' })
    }))
  }
  return Promise.reject(new Error('Motor no válido.'))
}

// ---------- VirusTotal (solo huella, nunca el archivo) ----------
type VT = { estado: 'conocido'; malicioso: number; sospechoso: number; limpio: number; total: number; etiqueta?: string; fecha?: number } | { estado: 'desconocido' | 'sin-clave' | 'clave-invalida' | 'limite' | 'error'; detalle?: string }
const llamadasVT: number[] = []
let bloqueoVT = 0
const reloj = () => performance.now()   // monótono: un reloj de sistema atrasado no puede dejar la cola esperando horas
async function esperaVT(signal: AbortSignal) {   // plan gratuito: 4 consultas por minuto
  const ahora = reloj()
  while (llamadasVT.length && ahora - llamadasVT[0] > 60000) llamadasVT.shift()
  if (llamadasVT.length >= 4) {
    const ms = Math.min(61000, Math.max(0, 60000 - (ahora - llamadasVT[0]) + 500))
    await new Promise<void>((ok, no) => {
      const t = setTimeout(ok, ms)
      signal.addEventListener('abort', () => { clearTimeout(t); no(Object.assign(new Error('Análisis cancelado.'), { code: 'ECANCELED' })) }, { once: true })
    })
  }
  llamadasVT.push(reloj())
}
async function consultarVT(hash: string, signal: AbortSignal): Promise<VT> {
  const clave = leerClave()
  if (!clave) return { estado: 'sin-clave' }
  if (reloj() < bloqueoVT) return { estado: 'limite' }   // VirusTotal ya dijo que basta: no se gasta más cupo ni se espera
  await esperaVT(signal)
  try {
    const r = await fetch(`https://www.virustotal.com/api/v3/files/${hash}`, { headers: { 'x-apikey': clave, accept: 'application/json' }, signal: AbortSignal.any([signal, AbortSignal.timeout(20000)]) })
    if (r.status === 404) return { estado: 'desconocido' }
    if (r.status === 401) return { estado: 'clave-invalida' }
    if (r.status === 403) return { estado: 'error', detalle: 'VirusTotal rechazó la petición (clave restringida o sin permiso).' }
    if (r.status === 429) { bloqueoVT = reloj() + 60000; return { estado: 'limite' } }
    if (!r.ok) return { estado: 'error', detalle: `VirusTotal respondió ${r.status}.` }
    const a = ((await r.json()) as { data?: { attributes?: { last_analysis_stats?: Record<string, number>; last_analysis_date?: number; popular_threat_classification?: { suggested_threat_label?: string } } } }).data?.attributes
    const s = a?.last_analysis_stats
    if (!s) return { estado: 'desconocido' }
    if ((s.malicious ?? 0) + (s.suspicious ?? 0) + (s.undetected ?? 0) + (s.harmless ?? 0) === 0) return { estado: 'desconocido' }   // lo conoce pero aún no lo ha analizado nadie
    const n = (k: string) => (typeof s[k] === 'number' ? s[k] : 0)
    return { estado: 'conocido', malicioso: n('malicious'), sospechoso: n('suspicious'), limpio: n('undetected') + n('harmless'), total: n('malicious') + n('suspicious') + n('undetected') + n('harmless'), etiqueta: a?.popular_threat_classification?.suggested_threat_label, fecha: a?.last_analysis_date }
  } catch (e) { return { estado: 'error', detalle: (e as Error).name === 'TimeoutError' ? 'VirusTotal no respondió a tiempo.' : 'No se pudo conectar con VirusTotal.' } }
}

// ---------- Análisis de un archivo ----------
// Si el archivo deja de leerse 60 s (unidad de red caída, bloqueo) se corta: si no, «analizando» quedaría ocupado hasta reiniciar.
const sha256 = (ruta: string) => new Promise<string>((ok, no) => {
  const h = createHash('sha256'), f = createReadStream(ruta)
  flujoActual = f
  const corte = () => setTimeout(() => f.destroy(Object.assign(new Error('timeout'), { code: 'ETIMEDOUT' })), 60000)
  let t = corte()
  f.on('data', (d) => { h.update(d); clearTimeout(t); t = corte() }).on('error', (e) => { clearTimeout(t); no(e) }).on('end', () => { clearTimeout(t); ok(h.digest('hex')) })
})
const MOTIVOS: Record<string, string> = { ENOENT: 'El archivo ya no existe.', EACCES: 'No hay permiso para leerlo.', EPERM: 'No hay permiso para leerlo.', EBUSY: 'Está en uso por otro programa.', ETIMEDOUT: 'Dejó de responder al leerlo (¿unidad desconectada?).', ECANCELED: 'Análisis cancelado.' }

interface Resultado { ruta: string; tam: number; modificado: number; version: Version | null; sha256: string; defender: Defender; clam: Clam | null; firma: Firma | null; vt: VT; tono: 'ok' | 'aviso' | 'error'; titulo: string; detalle: string }
const BIDI = /[\u202A-\u202E\u2066-\u2069]/
const DOC = /\.(pdf|docx?|xlsx?|pptx?|txt|jpe?g|png|gif|zip|rar|mp[34])$/i
const EJECUTABLE = /\.(exe|scr|com|bat|cmd|msi|js|vbs|ps1|lnk|hta|jar)$/i
function veredicto(d: Defender, vt: VT, clam: Clam | null, firma: Firma | null, ruta: string): Pick<Resultado, 'tono' | 'titulo' | 'detalle'> {
  const v = veredictoBase(d, vt, clam, firma)
  const nombre = basename(ruta)
  // Camuflaje por el nombre: «factura\u202Efdp.exe» se ve como «facturaexe.pdf», y «factura.pdf.exe» parece un PDF
  if (v.tono !== 'error' && BIDI.test(nombre)) return { tono: 'error', titulo: 'El nombre usa caracteres que invierten el texto', detalle: 'Es un truco para que un programa parezca otro tipo de archivo. No lo abras.' }
  if (v.tono === 'ok' && EJECUTABLE.test(nombre) && DOC.test(nombre.replace(EJECUTABLE, ''))) return { tono: 'aviso', titulo: 'Doble extensión: parece un documento y es un programa', detalle: `${v.detalle} El nombre acaba en dos extensiones, como «factura.pdf.exe». Desconfía.` }
  // Una firma rota delata que lo modificaron después de firmarlo: pesa más que el resto. Sin firma solo se avisa si lo demás sale verde.
  if (firma?.estado === 'invalida' && v.tono !== 'error') return { tono: 'error', titulo: 'La firma digital no coincide con el archivo', detalle: 'Lo han modificado después de firmarlo. No lo abras.' }
  if (firma?.estado === 'no-confiable' && v.tono === 'ok') return { tono: 'aviso', titulo: 'La firma digital no es de confianza', detalle: `Lleva firma${firma.firmante ? ` de ${firma.firmante}` : ''}, pero Windows no se fía de ella (certificado caducado, revocado o desconocido). ${v.detalle}` }
  if (clam?.estado === 'error' && v.tono === 'ok') return { tono: 'aviso', titulo: 'ClamAV no ha podido revisarlo', detalle: `${clam.detalle ?? ''} ${v.detalle}`.trim() }
  if (firma?.estado === 'error' && v.tono === 'ok') return { ...v, detalle: `${v.detalle} No se pudo comprobar la firma digital.` }
  if (firma?.estado === 'sin-firma' && v.tono === 'ok') return { ...v, detalle: `${v.detalle} Ojo: no lleva firma digital, así que no se sabe quién lo publica.` }
  return v
}
function veredictoBase(d: Defender, vt: VT, clam: Clam | null, firma: Firma | null): Pick<Resultado, 'tono' | 'titulo' | 'detalle'> {
  void firma
  if (clam?.estado === 'amenaza') return { tono: 'error', titulo: 'ClamAV lo marca como amenaza', detalle: clam.amenaza ? `Detección: ${clam.amenaza}. No lo abras.` : 'No lo abras.' }
  if (d.estado === 'amenaza') return { tono: 'error', titulo: 'Defender lo marca como amenaza', detalle: d.amenaza ? `Detección: ${d.amenaza}. No lo abras.` : 'No lo abras.' }
  const defOk = d.estado === 'limpio'
  if (vt.estado === 'conocido') {
    const marcas = vt.malicioso + vt.sospechoso
    if (vt.malicioso >= 3 || (vt.malicioso >= 2 && vt.malicioso / vt.total >= 0.3)) return { tono: 'error', titulo: `${vt.malicioso} motores de VirusTotal lo marcan como malicioso`, detalle: 'No lo abras ni lo instales.' }
    if (marcas > 0) return { tono: 'aviso', titulo: `${marcas} de ${vt.total} motores de VirusTotal lo marcan`, detalle: 'Con tan pocos suele ser un falso positivo (programas sin firmar o que tocan el hardware), pero no lo des por bueno: mira quién lo publica y qué hace.' }
    if (vt.total < 5) return { tono: 'aviso', titulo: 'Pocos motores lo han analizado', detalle: 'No es concluyente: espera a que VirusTotal lo analice más.' }
    return defOk
      ? { tono: 'ok', titulo: 'Sin amenazas conocidas', detalle: `Defender y ${vt.total} motores de VirusTotal no ven nada.` }
      : { tono: 'aviso', titulo: 'Solo lo ha revisado VirusTotal', detalle: `${vt.total} motores no ven nada, pero Defender no ha podido revisarlo: ${d.detalle ?? 'sin respuesta'}` }
  }
  if (vt.estado === 'desconocido') return { tono: 'aviso', titulo: 'VirusTotal no conoce este archivo', detalle: defOk ? 'Defender no ve amenazas, pero un archivo desconocido no es lo mismo que un archivo seguro: puede ser nuevo, poco común o a medida.' : 'Es poco común o nuevo, y Defender no ha podido revisarlo.' }
  if (!defOk) return { tono: 'aviso', titulo: 'No se ha podido comprobar', detalle: 'Ni Defender ni VirusTotal han dado una respuesta.' }
  if (vt.estado === 'sin-clave') return { tono: 'ok', titulo: 'Sin amenazas conocidas', detalle: 'Defender no ve amenazas. VirusTotal no se ha consultado (falta la clave).' }
  return { tono: 'aviso', titulo: 'Defender no ve amenazas, pero VirusTotal no ha respondido', detalle: vt.estado === 'limite' ? 'Se alcanzó el límite de consultas: repite en un minuto.' : vt.estado === 'clave-invalida' ? 'La clave de VirusTotal no es válida.' : (vt.detalle ?? 'No se pudo consultar.') }
}

/** La interfaz manda una ruta; aquí se exige que sea un archivo normal existente, nunca una carpeta ni un nombre relativo. */
async function analizar(entrada: unknown): Promise<Resultado> {
  if (typeof entrada !== 'string' || entrada.length > 32000 || !isAbsolute(entrada)) throw new Error('Ruta no válida.')
  if (/:/.test(entrada.slice(2))) throw new Error('Ruta no válida (los flujos de datos alternativos «archivo:flujo» no se revisan).')
  cancelado = false
  abortar = new AbortController()
  const senal = abortar.signal
  const fase = (t: string) => { if (!ventana.isDestroyed()) ventana.webContents.send('fase', t) }
  const revisarCancelado = () => { if (cancelado) throw Object.assign(new Error('Análisis cancelado.'), { code: 'ECANCELED' }) }
  try {
    let ruta = entrada
    try { ruta = realpathSync.native(entrada) } catch { /* si no se puede resolver, ya fallará el stat con su motivo */ }   // enlaces y «C:/x» pasan a la ruta real que Defender registra
    if (/:/.test(ruta.replace(/^\\\\\?\\/, '').slice(2))) throw new Error('Ruta no válida (el enlace apunta a un flujo de datos alternativo).')   // un enlace puede apuntar a «archivo:flujo»
    const st = statSync(ruta)
    if (!st.isFile()) throw new Error('Solo se pueden revisar archivos, no carpetas.')
    fase('Leyendo el archivo y calculando su huella…')
    const hash = await sha256(ruta); revisarCancelado()
    const st2 = statSync(ruta)
    if (st2.size !== st.size || st2.mtimeMs !== st.mtimeMs) throw new Error('El archivo ha cambiado mientras se analizaba (¿se está descargando?). Repite cuando termine.')
    fase('Defender está escaneando…')
    const defender = await escanearDefender(ruta); revisarCancelado()
    if (defender.estado !== 'amenaza' && hayClam()) fase('ClamAV está escaneando (carga su base de firmas)…')
    const clam = defender.estado === 'amenaza' ? null : await escanearClam(ruta); revisarCancelado()   // ya hay veredicto rojo: no se gasta el tiempo de ClamAV
    fase('Comprobando la firma digital…')
    const firma = await leerFirma(ruta); revisarCancelado()
    const version = await leerVersion(ruta); revisarCancelado()
    const condenado = defender.estado === 'amenaza' || clam?.estado === 'amenaza'
    const vt: VT = condenado ? { estado: 'error', detalle: 'No consultado: ya lo marca otro motor.' } : await consultarVT(hash, senal)   // no se gasta cupo en lo ya condenado
    revisarCancelado()
    fase('')
    return { ruta, tam: st.size, modificado: st.mtimeMs, version, sha256: hash, defender, clam, firma, vt, ...veredicto(defender, vt, clam, firma, ruta) }
  } catch (e) { throw new Error(MOTIVOS[(e as NodeJS.ErrnoException).code ?? ''] ?? (e as Error).message) }
}

// ---------- Carpeta completa ----------
// Defender y ClamAV recorren la carpeta ellos solos. No se calcula huella, firma ni VirusTotal por archivo: con 4 consultas por minuto una carpeta no terminaría nunca.
interface ResultadoCarpeta { ruta: string; defender: Defender; clam: Clam | null; hallazgos: Hallazgo[]; tono: 'ok' | 'aviso' | 'error'; titulo: string; detalle: string }
async function analizarCarpeta(entrada: unknown): Promise<ResultadoCarpeta> {
  if (typeof entrada !== 'string' || entrada.length > 32000 || !isAbsolute(entrada)) throw new Error('Ruta no válida.')
  if (/:/.test(entrada.slice(2))) throw new Error('Ruta no válida.')
  cancelado = false
  const fase = (t: string) => { if (!ventana.isDestroyed()) ventana.webContents.send('fase', t) }
  const revisarCancelado = () => { if (cancelado) throw Object.assign(new Error('Análisis cancelado.'), { code: 'ECANCELED' }) }
  try {
    let ruta = entrada
    try { ruta = realpathSync.native(entrada) } catch { /* ya fallará el stat con su motivo */ }
    if (/:/.test(ruta.replace(/^\\\\\?\\/, '').slice(2))) throw new Error('Ruta no válida.')
    if (!statSync(ruta).isDirectory()) throw new Error('Eso no es una carpeta.')
    fase('Defender está escaneando la carpeta (puede tardar mucho si es grande)…')
    const defender = await escanearDefender(ruta, true); revisarCancelado()
    if (hayClam()) fase('ClamAV está escaneando la carpeta (carga su base de firmas)…')
    const clam = await escanearClam(ruta, true); revisarCancelado()
    fase('')
    const hallazgos = [...(defender.hallazgos ?? []), ...(clam?.hallazgos ?? [])]
    const base = { ruta, defender, clam, hallazgos }
    if (defender.estado === 'amenaza' || clam?.estado === 'amenaza') {
      const n = hallazgos.length
      return { ...base, tono: 'error', titulo: n ? `Se han encontrado ${n} amenaza${n === 1 ? '' : 's'} en la carpeta` : 'Un motor ha marcado algo en la carpeta', detalle: 'No abras esos archivos. La app solo informa: no borra ni pone nada en cuarentena.' }
    }
    if (defender.estado !== 'limpio' && clam?.estado !== 'limpio') return { ...base, tono: 'aviso', titulo: 'No se ha podido revisar la carpeta', detalle: `${defender.detalle ?? ''} ${clam?.detalle ?? ''}`.trim() }
    const parciales = [defender.estado !== 'limpio' && `Defender: ${defender.detalle}`, clam && clam.estado !== 'limpio' && `ClamAV: ${clam.detalle}`].filter(Boolean).join(' ')
    return { ...base, tono: parciales ? 'aviso' : 'ok', titulo: parciales ? 'Revisada solo con un motor' : 'Sin amenazas conocidas en la carpeta', detalle: parciales || `${clam ? 'Defender y ClamAV' : 'Defender'} no ven nada. Un archivo concreto que dude puedes revisarlo suelto para consultar también VirusTotal y su firma.` }
  } catch (e) { throw new Error(MOTIVOS[(e as NodeJS.ErrnoException).code ?? ''] ?? (e as Error).message) }
}

// ---------- Ventana ----------
let ventana: BrowserWindow
function crearVentana() {
  const t = temaEfectivo(modoTema())
  ventana = new BrowserWindow({
    width: 980, height: 740, minWidth: 720, minHeight: 520, backgroundColor: t === 'claro' ? '#FAFAFA' : '#141415', title: 'Nitrit0 Antivirus',
    icon: app.isPackaged ? join(process.resourcesPath, 'icono.png') : join(__dirname, '../../../build/icono-256.png'),
    titleBarStyle: 'hidden', titleBarOverlay: { ...colores[t], height: 40 },
    webPreferences: { preload: join(__dirname, '../preload/index.js'), contextIsolation: true, sandbox: true }
  })
  nativeTheme.on('updated', () => { if (modoTema() === 'sistema' && !ventana.isDestroyed()) ventana.setTitleBarOverlay({ ...colores[temaEfectivo('sistema')], height: 40 }) })
  // Si la interfaz se cae, la ventana quedaría en blanco y «analizando» atascado: se cortan los procesos y se recarga
  ventana.webContents.on('render-process-gone', () => { analizando = false; matarHijosYa(); if (!ventana.isDestroyed()) void ventana.webContents.reload() })
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

let analizando = false
if (!dev && !app.requestSingleInstanceLock()) app.quit()   // en desarrollo no hay bloqueo: se puede probar con la app de verdad abierta
else {
  app.on('second-instance', () => { if (ventana) { if (ventana.isMinimized()) ventana.restore(); ventana.focus() } })
  app.whenReady().then(() => {
    cerrarPermisos()
    handle('estado', () => ({ tema: modoTema(), clave: !!leerClave(), defender: !!rutaDefender(), clam: hayClam() ? (fechaClam() ?? { fecha: 'sin fecha', dias: 9999 }) : null }))
    handle('elegir', async () => { const r = await dialog.showOpenDialog(ventana, { title: 'Elige los archivos que quieres revisar', properties: ['openFile', 'multiSelections'] }); return r.canceled ? [] : r.filePaths })
    handle('analizar', async (_e, ruta: unknown) => {
      if (analizando) throw new Error('Ya hay un análisis en marcha.')
      analizando = true
      try { return await analizar(ruta) } finally { analizando = false }
    })
    handle('elegirCarpeta', async () => { const r = await dialog.showOpenDialog(ventana, { title: 'Elige la carpeta que quieres revisar entera', properties: ['openDirectory'] }); return r.canceled ? '' : r.filePaths[0] })
    handle('esCarpeta', (_e, ruta: unknown) => { try { return typeof ruta === 'string' && isAbsolute(ruta) && statSync(ruta).isDirectory() } catch { return false } })
    handle('analizarCarpeta', async (_e, ruta: unknown) => {
      if (analizando) throw new Error('Ya hay un análisis en marcha.')
      analizando = true
      try { return await analizarCarpeta(ruta) } finally { analizando = false }
    })
    handle('motores', async () => ({ defender: await estadoDefender(), clam: hayClam() ? fechaClam() : null, hayClam: hayClam() }))
    handle('actualizar', async (_e, motor: unknown) => {
      if (analizando) throw new Error('Espera a que termine lo que está en marcha.')
      analizando = true; cancelado = false
      try { return await actualizarMotor(motor) } finally { analizando = false }
    })
    handle('abrirClaveVT', () => { void shell.openExternal('https://www.virustotal.com/gui/my-apikey') })   // dirección fija: la interfaz no puede pedir otra
    handle('cancelar', () => { cancelado = true; abortar?.abort(); flujoActual?.destroy(Object.assign(new Error('cancelado'), { code: 'ECANCELED' })); matarHijos() })
    handle('guardarClave', (_e, c: unknown) => (typeof c === 'string' ? guardarClave(c.trim()) : 'formato'))
    handle('abrirVT', (_e, hash: unknown) => { if (typeof hash === 'string' && /^[a-f0-9]{64}$/.test(hash)) void shell.openExternal(`https://www.virustotal.com/gui/file/${hash}`) })
    crearVentana()
    // Solo desarrollo: NITRIT0_PRUEBA=<ruta>|<ruta> analiza esos archivos con el motor real, imprime el resultado y sale
    if (dev && process.env.NITRIT0_PRUEBA) {
      void (async () => {
        for (const r of process.env.NITRIT0_PRUEBA!.split('|')) {
          try { const x = await analizar(r); console.log('PRUEBA', JSON.stringify({ ruta: x.ruta, tono: x.tono, titulo: x.titulo, defender: x.defender.estado, firma: x.firma, version: x.version, modificado: x.modificado, vt: x.vt.estado })) }
          catch (e) { console.log('PRUEBA', JSON.stringify({ ruta: r, error: (e as Error).message })) }
        }
        app.quit()
      })()
    }
  })
  app.on('before-quit', matarHijosYa)
  app.on('window-all-closed', () => { matarHijosYa(); app.quit() })
}
