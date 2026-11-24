# =====================================================================
#  LimpiarTemporalesEquipo.ps1 - Limpia temporales, cachés de navegadores y Papelera de TODAS las cuentas (Nitrit0)
#  Antes de borrar calcula cuánto se va a liberar y pide confirmación. Los navegadores se cierran con aviso (cierre normal primero;
#  solo se fuerzan los que no responden, y se dice cuáles). Se conservan los registros recientes de Windows (CBS, DISM): solo se
#  borran los de más de 30 días. NO se toca Prefetch ni C:\Windows\Installer.
#  Parámetro: -SoloAnalizar (calcula y enseña lo que se liberaría, no borra nada)
#  Salida: 0 bien · 1 error · 2 cancelado
# =====================================================================
[CmdletBinding()]
param([switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
if (-not $SoloAnalizar) { Assert-Admin 'limpiar los temporales de todo el equipo' }
function Format-Tam([int64]$b) { if ($b -ge 1GB) { '{0:N1} GB' -f ($b / 1GB) } elseif ($b -ge 1MB) { '{0:N0} MB' -f ($b / 1MB) } else { '{0:N0} KB' -f ($b / 1KB) } }
# Archivos de una ruta con comodín final («carpeta\*»): con -Path y -Recurse, PowerShell no desciende a las carpetas que casan con el comodín, así que se recorren aparte
function Get-ArchivosRuta([string]$r) {
    # Los enlaces (junctions y simbólicos) no se recorren: con -Recurse en PowerShell 5.1 se entra en ellos y se borraría fuera de la ruta prevista
    foreach ($i in @(Get-ChildItem -Path $r -Force -ErrorAction SilentlyContinue)) {
        if ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        if ($i.PSIsContainer) { Get-ArchivosSinEnlaces $i.FullName } else { $i }
    }
}
function Get-ArchivosSinEnlaces([string]$dir) {
    foreach ($i in @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)) {
        if ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        if ($i.PSIsContainer) { Get-ArchivosSinEnlaces $i.FullName } else { $i }
    }
}
function Get-TamRutas([string[]]$rutas, [int]$DiasMinimo = 0) {
    $t = [int64]0; $limite = (Get-Date).AddDays(-$DiasMinimo)
    foreach ($r in $rutas) { try { $t += [int64](Get-ArchivosRuta $r | Where-Object { $DiasMinimo -eq 0 -or $_.LastWriteTime -lt $limite } | Measure-Object Length -Sum).Sum } catch { } }
    $t
}

$unidad = $env:SystemDrive.TrimEnd(':')
$perfiles = @(Get-ChildItem -Path (Split-Path -Parent $env:PUBLIC) -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin 'Public', 'Default', 'Default User', 'All Users' })
# Navegadores Chromium: todos los perfiles (Default y Profile N) y todas sus cachés; Opera guarda el perfil directamente en Roaming
$cacheChromium = 'Cache', 'Code Cache', 'GPUCache', 'Media Cache', 'DawnCache', 'Service Worker\CacheStorage', 'Service Worker\ScriptCache'
$baseChromium = 'AppData\Local\Google\Chrome\User Data', 'AppData\Local\Microsoft\Edge\User Data', 'AppData\Local\BraveSoftware\Brave-Browser\User Data', 'AppData\Local\Vivaldi\User Data'
$subCache = @(foreach ($b in $baseChromium) { foreach ($p in 'Default', 'Profile *') { foreach ($c in $cacheChromium) { "$b\$p\$c\*" } } })
$subCache += @(foreach ($b in 'AppData\Roaming\Opera Software\Opera Stable', 'AppData\Roaming\Opera Software\Opera GX Stable', 'AppData\Local\Opera Software\Opera Stable', 'AppData\Local\Opera Software\Opera GX Stable') { foreach ($c in $cacheChromium) { "$b\$c\*" } })
$subCache += 'AppData\Local\Microsoft\Windows\INetCache\*', 'AppData\Local\Mozilla\Firefox\Profiles\*\cache2\*', 'AppData\Local\Mozilla\Firefox\Profiles\*\startupCache\*', 'AppData\Local\Mozilla\Firefox\Profiles\*\thumbnails\*'
$rutasNav = @(foreach ($u in $perfiles) { foreach ($s in $subCache) { Join-Path $u.FullName $s } })
# Cachés de aplicaciones: solo Cache/Code Cache/GPUCache de apps Electron y la caché de Spotify/Steam; nunca Local Storage, Cookies ni sesiones (no cierra la sesión de nadie)
$appsElectron = 'WhatsApp', 'discord', 'Slack', 'Code', 'Cursor', 'Claude'
$rutasApps = @(foreach ($u in $perfiles) {
    foreach ($a in $appsElectron) { foreach ($s in 'Cache', 'Code Cache', 'GPUCache') { Join-Path $u.FullName "AppData\Roaming\$a\$s\*" } }
    Join-Path $u.FullName 'AppData\Local\Spotify\Data\*'; Join-Path $u.FullName 'AppData\Local\Spotify\Storage\*'; Join-Path $u.FullName 'AppData\Local\Steam\htmlcache\*'
}) + @("$env:SystemDrive\NVIDIA\DisplayDriver\*")   # instaladores de NVIDIA ya extraídos

# Categorías: Nombre, rutas, antigüedad mínima en días (0 = todo)
$cats = @(
    [pscustomobject]@{ Id = 'temp'; Nombre = 'Temporales de Windows y del usuario'; Rutas = @("$env:SystemRoot\Temp\*", "$env:LOCALAPPDATA\Temp\*", "$env:LOCALAPPDATA\CrashDumps\*"); Dias = 0 }
    [pscustomobject]@{ Id = 'wu'; Nombre = 'Descargas de Windows Update ya instaladas'; Rutas = @("$env:SystemRoot\SoftwareDistribution\Download\*"); Dias = 0 }
    [pscustomobject]@{ Id = 'logs'; Nombre = 'Registros de Windows de más de 30 días'; Rutas = @("$env:SystemRoot\Logs\*"); Dias = 30 }
    [pscustomobject]@{ Id = 'nav'; Nombre = 'Cachés de navegadores (todas las cuentas)'; Rutas = $rutasNav; Dias = 0 }
    [pscustomobject]@{ Id = 'apps'; Nombre = 'Cachés de aplicaciones (Spotify, Discord, Slack, WhatsApp, VS Code, Cursor, Claude, Steam) e instaladores de NVIDIA'; Rutas = $rutasApps; Dias = 0 }
)
Write-Output "  $($E.Lupa) Calculando cuánto se puede liberar…"
foreach ($c in $cats) { $c | Add-Member -NotePropertyName Tam -NotePropertyValue (Get-TamRutas $c.Rutas $c.Dias) }
$papelera = [int64]0; try { $papelera = [int64](Get-ChildItem -LiteralPath "$unidad`:\`$Recycle.Bin" -Force -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum } catch { }
$total = [int64]($cats | Measure-Object Tam -Sum).Sum + $papelera
foreach ($c in $cats) { Write-Output ("    · {0}: {1}" -f $c.Nombre, (Format-Tam $c.Tam)) }
Write-Output ("    · Papelera de reciclaje (todas las cuentas): {0}" -f (Format-Tam $papelera))
Write-Output "  $($E.Info) Se liberarían unos $(Format-Tam $total)."
if ($SoloAnalizar) { Write-Output "`n  $($E.Info) Solo análisis: no se ha borrado nada."; Write-Log "LimpiarTemporalesEquipo: análisis, $(Format-Tam $total) estimados"; Exit-Kit 'Ok' }

if (-not (Confirm-Accion "Se van a liberar unos $(Format-Tam $total):`ntemporales, cachés de navegadores y de aplicaciones, registros antiguos y la Papelera de TODAS las cuentas.`nLos navegadores abiertos se cerrarán (con aviso). No se puede deshacer.`n`n¿Continuar?")) { Exit-Kit 'Cancelado' 'Cancelado: no se ha borrado nada.' }
$libreAntes = (Get-PSDrive -Name $unidad).Free
[void](Start-OperacionSegura 'Limpiar temporales del equipo' -SinPuntoRestauracion)
Save-Informativo 'Se borraron temporales, cachés de navegadores y aplicaciones, registros antiguos y la Papelera de todas las cuentas' 'No se puede deshacer: son archivos que Windows y los programas vuelven a generar.'
$errores = 0

# 1) Navegadores: cierre normal y, solo si no responden, forzado
Write-Output "  $($E.Reloj) Cerrando navegadores…"
$forzados = @()
try {
    $procs = @('chrome', 'msedge', 'firefox', 'brave', 'opera') | ForEach-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue }
    foreach ($p in $procs) { try { [void]$p.CloseMainWindow() } catch { } }
    $fin = (Get-Date).AddSeconds(8)
    while ((Get-Date) -lt $fin -and @($procs | Where-Object { -not $_.HasExited }).Count) { Start-Sleep -Milliseconds 500 }
    foreach ($p in @($procs | Where-Object { -not $_.HasExited })) { try { Stop-Process -Id $p.Id -Force -ErrorAction Stop; $forzados += $p.ProcessName } catch { } }
} catch { $errores++; Write-Output "  $($E.Aviso) No se pudieron cerrar los navegadores: $($_.Exception.Message)" }
if ($forzados) { Write-Output "  $($E.Aviso) No respondieron y se forzó el cierre de: $((@($forzados | Sort-Object -Unique)) -join ', ')." } else { Write-Output "  $($E.OK) Navegadores cerrados con normalidad (o no estaban abiertos)." }

# 2) Categorías de archivos
foreach ($c in $cats) {
    Write-Output "  $($E.Lupa) $($c.Nombre)…"
    $servicios = @()
    try {
        if ($c.Id -eq 'wu') { foreach ($s in 'wuauserv', 'bits') { $sv = Get-Service -Name $s -ErrorAction SilentlyContinue; if ($sv -and $sv.Status -eq 'Running') { $servicios += $s } }; foreach ($s in $servicios) { Stop-Service -Name $s -Force -ErrorAction SilentlyContinue } }
        $enUso = 0
        foreach ($r in $c.Rutas) {
            if ($c.Dias -gt 0) {
                $limite = (Get-Date).AddDays(-$c.Dias)
                Get-ArchivosRuta $r | Where-Object { $_.LastWriteTime -lt $limite } | ForEach-Object { try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop } catch { $enUso++ } }
            } else {
                $err = @(); Remove-Item -Path $r -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable +err; $enUso += $err.Count
            }
        }
        Write-Output "    $($E.OK) Hecho$(if ($enUso) { " ($enUso elementos en uso se han dejado)" })."
        Write-Log "LimpiarTemporalesEquipo: $($c.Nombre) ($(Format-Tam $c.Tam) estimados, $enUso en uso)"
    } catch { $errores++; Write-Output "    $($E.Aviso) $($c.Nombre): $($_.Exception.Message)"; Write-Log "LimpiarTemporalesEquipo: fallo en $($c.Nombre): $($_.Exception.Message)" 'ERROR' }
    finally { foreach ($s in $servicios) { try { Start-Service -Name $s -ErrorAction SilentlyContinue } catch { } } }
}

# 3) Papelera
Write-Output "  $($E.Info) Vaciando la Papelera…"
try { Clear-RecycleBin -DriveLetter $unidad -Force -ErrorAction Stop; Write-Output "    $($E.OK) Hecho." } catch { Write-Output "    $($E.Aviso) No se pudo vaciar la Papelera: $($_.Exception.Message)" }

Start-Sleep -Seconds 1
$liberado = [Math]::Max([int64]0, (Get-PSDrive -Name $unidad).Free - $libreAntes)
Write-Output "`n  $($E.Disco) Unidades ahora:"
foreach ($v in @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | Sort-Object DriveLetter)) { Write-Output ("    {0}: {1} libres de {2}" -f $v.DriveLetter, (Format-Tam ([int64]$v.SizeRemaining)), (Format-Tam ([int64]$v.Size))) }
Write-Log ("LimpiarTemporalesEquipo: {0} liberados en {1}: ({2} errores)" -f (Format-Tam $liberado), $unidad, $errores)
if ($errores) { Exit-Kit 'Error' "Limpieza terminada con $errores categoría(s) con error. Se liberaron $(Format-Tam $liberado) en $unidad`:." }
Exit-Kit 'Ok' "Limpieza completada: se han liberado $(Format-Tam $liberado) en $unidad`:."
