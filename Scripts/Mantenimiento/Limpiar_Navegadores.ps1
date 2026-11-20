# =====================================================================
#  Limpiar_Navegadores.ps1 - Limpia caché, historial, cookies y datos guardados de los navegadores (Nitrit0)
#  Para «el navegador va lento», «una web no carga bien» o dejar un equipo limpio antes de entregarlo.
#  Detecta Edge, Chrome, Brave, Vivaldi, Opera, Opera GX y Firefox y deja elegir, por navegador y por tipo de dato.
#  Por defecto vienen marcados la caché y el historial. Cookies (cierran sesiones), formularios, contraseñas y sesión van SIN marcar;
#  esos tres últimos piden además una confirmación que ningún modo automático salta.
#  Límites: Firefox no ofrece «historial» (comparte archivo con los marcadores y no hay forma de separarlos sin SQLite); en los demás,
#  el historial incluye la lista de descargas (los archivos descargados no se tocan). Los marcadores NUNCA se borran.
#  Solo limpia el perfil del usuario con el que corre (si el kit va elevado con otra cuenta, avisa).
#  Parámetros: -SoloAnalizar (solo cuenta lo que hay)  -SinPreguntas (aplica solo lo marcado por defecto, sin ventana)
#  Salida: 0 bien · 1 error · 2 cancelado
# =====================================================================
[CmdletBinding()]
param([switch]$SoloAnalizar, [switch]$SinPreguntas)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
function Format-Tam([int64]$b) { if ($b -ge 1GB) { '{0:N1} GB' -f ($b / 1GB) } elseif ($b -ge 1MB) { '{0:N0} MB' -f ($b / 1MB) } else { '{0:N0} KB' -f ($b / 1KB) } }
function Get-TamRutas([string[]]$rutas) {
    [int64]$t = 0
    foreach ($r in $rutas) {
        $i = Get-Item -LiteralPath $r -Force -ErrorAction SilentlyContinue; if (-not $i) { continue }
        if ($i.PSIsContainer) { $s = (Get-ChildItem -LiteralPath $r -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum; if ($s) { $t += [int64]$s } } else { $t += $i.Length }
    }
    $t
}
function Close-Programa([string[]]$nombres) {   # cierra con educación; devuelve $true si ya no queda ninguno
    $ps = @(Get-Process -Name $nombres -ErrorAction SilentlyContinue); if (-not $ps.Count) { return $true }
    foreach ($p in $ps) { try { [void]$p.CloseMainWindow() } catch { } }
    $fin = (Get-Date).AddSeconds(10); while ((Get-Date) -lt $fin -and (Get-Process -Name $nombres -ErrorAction SilentlyContinue)) { Start-Sleep -Milliseconds 500 }
    -not (Get-Process -Name $nombres -ErrorAction SilentlyContinue)
}

# ---------------------------------------------------------------- Qué se puede limpiar
$loc = $env:LOCALAPPDATA; $roa = $env:APPDATA
$navegadores = @(
    @{ N = 'Microsoft Edge'; Tipo = 'chromium'; Proc = 'msedge';  Base = "$loc\Microsoft\Edge\User Data" }
    @{ N = 'Google Chrome';  Tipo = 'chromium'; Proc = 'chrome';  Base = "$loc\Google\Chrome\User Data" }
    @{ N = 'Brave';          Tipo = 'chromium'; Proc = 'brave';   Base = "$loc\BraveSoftware\Brave-Browser\User Data" }
    @{ N = 'Vivaldi';        Tipo = 'chromium'; Proc = 'vivaldi'; Base = "$loc\Vivaldi\User Data" }
    @{ N = 'Opera';          Tipo = 'chromium'; Proc = 'opera';   Base = "$roa\Opera Software\Opera Stable"; Directo = $true }
    @{ N = 'Opera GX';       Tipo = 'chromium'; Proc = 'opera';   Base = "$roa\Opera Software\Opera GX Stable"; Directo = $true }
    @{ N = 'Firefox';        Tipo = 'firefox';  Proc = 'firefox'; Base = "$roa\Mozilla\Firefox\Profiles" }
)
# Marcado = viene marcado; Peligro = pide confirmación fuerte (se pierde algo que no es recuperable del propio sitio)
$cats = @(
    @{ Id = 'cache'; T = 'Caché de internet';                   M = $true;  P = $false; D = 'Imágenes y archivos temporales de las páginas; se vuelven a descargar.' }
    @{ Id = 'hist';  T = 'Historial de navegación y descargas'; M = $true;  P = $false; D = 'Páginas visitadas y lista de descargas. Los archivos descargados no se tocan.' }
    @{ Id = 'cook';  T = 'Cookies';                             M = $false; P = $false; D = 'Cierra las sesiones abiertas en todas las webs.' }
    @{ Id = 'forms'; T = 'Datos de formularios guardados';      M = $false; P = $true;  D = 'Autorrelleno de direcciones, tarjetas y formularios.' }
    @{ Id = 'pass';  T = 'Contraseñas guardadas';               M = $false; P = $true;  D = 'Se pierden si no están sincronizadas con la cuenta del navegador.' }
    @{ Id = 'ses';   T = 'Sesión (pestañas abiertas)';          M = $false; P = $true;  D = 'Las pestañas que se restaurarían al abrir el navegador.' }
    @{ Id = 'bkp';   T = 'Copia de seguridad de los marcadores'; M = $false; P = $false; D = 'Copia los marcadores a la carpeta de cambios del kit. No borra nada.' }
)
$relChromium = @{
    cache = 'Cache', 'Code Cache', 'GPUCache', 'Service Worker\CacheStorage', 'Service Worker\ScriptCache'
    hist  = 'History', 'History-journal', 'Visited Links', 'Top Sites', 'Top Sites-journal', 'Shortcuts', 'Shortcuts-journal'
    cook  = 'Network\Cookies', 'Network\Cookies-journal', 'Cookies', 'Cookies-journal'
    forms = 'Web Data', 'Web Data-journal'
    pass  = 'Login Data', 'Login Data-journal', 'Login Data For Account', 'Login Data For Account-journal'
    ses   = 'Sessions', 'Current Session', 'Current Tabs', 'Last Session', 'Last Tabs'
    bkp   = 'Bookmarks'
}
$relFirefox = @{
    cache = 'cache2', 'startupCache', 'jumpListCache'
    cook  = 'cookies.sqlite', 'cookies.sqlite-wal', 'cookies.sqlite-shm'
    forms = 'formhistory.sqlite', 'formhistory.sqlite-wal', 'formhistory.sqlite-shm'
    pass  = 'logins.json', 'key4.db'
    ses   = 'sessionstore.jsonlz4', 'sessionstore-backups'
}
function Get-Perfiles($b) {
    if (-not (Test-Path -LiteralPath $b.Base)) { return @() }
    if ($b.Directo) { return @($b.Base) }
    if ($b.Tipo -eq 'firefox') { return @(Get-ChildItem -LiteralPath $b.Base -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) }
    @(Get-ChildItem -LiteralPath $b.Base -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(Default|Profile \d+)$' } | ForEach-Object { $_.FullName })
}
function Get-Rutas($b, [string]$cat) {
    $rel = if ($b.Tipo -eq 'firefox') { $relFirefox[$cat] } else { $relChromium[$cat] }
    if (-not $rel) { return @() }
    $salida = @()
    foreach ($p in (Get-Perfiles $b)) {
        $raiz = $p
        if ($b.Tipo -eq 'firefox' -and $cat -eq 'cache') { $raiz = Join-Path "$loc\Mozilla\Firefox\Profiles" (Split-Path $p -Leaf) }   # la caché de Firefox vive en LocalAppData
        foreach ($r in $rel) { $x = Join-Path $raiz $r; if (Test-Path -LiteralPath $x) { $salida += $x } }
    }
    $salida
}

# ---------------------------------------------------------------- Estado
Write-Output "  $($E.Lupa) Qué navegadores hay"
$cs = $null; try { $cs = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName } catch { }
if ($cs) { $interactivo = ($cs -split '\\')[-1]; if ($interactivo -ne $env:USERNAME) { Write-Output "  $($E.Aviso) El kit corre como «$($env:USERNAME)» pero la sesión abierta es de «${interactivo}»: se limpiarían los navegadores del perfil de «$($env:USERNAME)», no los del usuario del equipo." } }
$items = @(); $mapa = @{}
foreach ($b in $navegadores) {
    $perfiles = @(Get-Perfiles $b); if (-not $perfiles.Count) { continue }
    foreach ($c in $cats) {
        $rutas = @(Get-Rutas $b $c.Id); if (-not $rutas.Count) { continue }
        $tam = Get-TamRutas $rutas; if ($c.Id -ne 'bkp' -and $tam -le 0) { continue }
        $id = "$($b.N)|$($c.Id)"; $mapa[$id] = @{ B = $b; C = $c; Rutas = $rutas; Tam = $tam }
        $det = "$(Format-Tam $tam) · $($perfiles.Count) perfil(es). $($c.D)"; if ($c.Id -eq 'bkp') { $det = "$($perfiles.Count) perfil(es). $($c.D)" }
        $items += [pscustomobject]@{ Id = $id; Texto = "$($b.N) · $($c.T)"; Detalle = $det; Marcado = $c.M }
    }
    Write-Output "    $($E.OK) $($b.N): $($perfiles.Count) perfil(es)$(if (Get-Process -Name $b.Proc -ErrorAction SilentlyContinue) { ' (abierto ahora)' })"
}
if (-not $items.Count) { Exit-Kit 'Ok' 'No hay datos de navegador que limpiar (o no se detecta ninguno).' }
if ($SoloAnalizar) {
    foreach ($i in $items) { Write-Output "    $(if ($i.Marcado) { '[por defecto]' } else { '[opcional]  ' }) $($i.Texto): $($i.Detalle)" }
    Exit-Kit 'Ok' 'Solo análisis: no se ha borrado nada.'
}

# ---------------------------------------------------------------- Elegir
if ($SinPreguntas) { $elegidos = @($items | Where-Object { $_.Marcado }) }
else { $elegidos = Show-Marcables 'Limpiar navegadores' 'Marca lo que quieres limpiar. Los navegadores abiertos se cierran con educación: guarda antes lo que tengas en pestañas. Los marcadores nunca se borran.' $items 'Limpiar lo marcado' }
if ($null -eq $elegidos -or -not @($elegidos).Count) { Exit-Kit 'Cancelado' 'No se cambia nada.' }
$ids = @($elegidos | ForEach-Object { $_.Id })
$peligrosos = @($ids | Where-Object { $mapa[$_].C.P })
if ($peligrosos.Count) {
    $lista = ($peligrosos | ForEach-Object { "  · $($mapa[$_].B.N): $($mapa[$_].C.T)" }) -join "`n"
    if (-not (Confirm-Accion "Vas a borrar datos que NO se pueden recuperar:`n`n$lista`n`n¿Seguro?" 'Nitrit0 Kit' -Siempre)) { Exit-Kit 'Cancelado' 'No se cambia nada.' }
}

# ---------------------------------------------------------------- Limpiar
$dir = Start-OperacionSegura 'Limpiar navegadores' -SinPuntoRestauracion
$errores = 0
foreach ($n in ($ids | ForEach-Object { $mapa[$_].B } | Sort-Object { $_.N } -Unique)) {
    if (Get-Process -Name $n.Proc -ErrorAction SilentlyContinue) {
        if (Close-Programa $n.Proc) { Write-Output "  $($E.Info) $($n.N) cerrado." } else { Write-Output "  $($E.Aviso) $($n.N) sigue en marcha (también en segundo plano): lo que esté en uso se dejará." }
    }
}
foreach ($id in $ids) {
    $m = $mapa[$id]; $b = $m.B; $c = $m.C
    if ($c.Id -eq 'bkp') {
        $n = 0
        foreach ($r in $m.Rutas) {
            $dest = Join-Path $dir ('Marcadores\' + ($b.N -replace '\s', '_') + '_' + ((Split-Path (Split-Path $r -Parent) -Leaf) -replace '\s', '_'))
            try { New-Item -ItemType Directory -Force $dest | Out-Null; Copy-Item -LiteralPath $r -Destination $dest -Force -ErrorAction Stop; $n++ } catch { $errores++; Write-Output "    $($E.Error) $($b.N): no se pudo copiar los marcadores ($($_.Exception.Message))." }
        }
        if ($n) { Write-Output "    $($E.OK) $($b.N): copia de marcadores de $n perfil(es) en $dir\Marcadores"; Write-Log "Limpiar_Navegadores: copia de marcadores de $($b.N) en $dir" }
        continue
    }
    $en = 0
    foreach ($r in $m.Rutas) { try { Remove-Item -LiteralPath $r -Recurse -Force -ErrorAction Stop } catch { if (Test-Path -LiteralPath $r) { $en++ } } }
    $quedan = $en
    Write-Output "    $(if ($quedan) { $E.Aviso } else { $E.OK }) $($b.N) · $($c.T): $(Format-Tam $m.Tam)$(if ($quedan) { " ($quedan elemento(s) en uso se han dejado: cierra el navegador del todo y repite)" })"
    Write-Log "Limpiar_Navegadores: $($b.N) $($c.Id) ($quedan sin quitar)"
    Save-Informativo "Limpiado: $($b.N) · $($c.T)" 'Borrado definitivo: no hay forma de deshacerlo desde el kit.'
}
if ($errores) { Exit-Kit 'Error' "Terminado con $errores error(es)." }
Exit-Kit 'Ok' 'Navegadores limpios. Los marcadores no se han tocado.'
