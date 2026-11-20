# =====================================================================
#  Reparar_Office_y_Caches.ps1 - Reparación rápida de Office y limpieza de cachés de Teams y OneDrive (Nitrit0)
#  Para «Word/Excel/Outlook se cuelgan o no abren», «Teams va lento o no deja entrar» o «OneDrive no sincroniza».
#  Detecta qué hay instalado y deja elegir, cada cosa por separado:
#    · Reparación rápida de Office (Click-to-Run, sin conexión; no toca tus documentos ni tu correo).
#    · Limpiar la caché de Teams (clásico y nuevo): tendrás que volver a iniciar sesión.
#    · Limpiar la caché de archivos de Office (cola de subida de OneDrive/SharePoint).
#    · Restablecer OneDrive (no borra archivos; vuelve a sincronizar todo).
#  Los programas se cierran con educación; si alguno tiene algo sin guardar o no se cierra, esa tarea se salta y se dice.
#  La caché de autocompletado de Outlook NO se toca. Parámetro: -SoloAnalizar   Salida: 0 bien · 1 error · 2 cancelado
# =====================================================================
[CmdletBinding()]
param([switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
if (-not $SoloAnalizar) { Assert-Admin 'reparar Office y limpiar cachés' }
function Format-Tam([int64]$b) { if ($b -ge 1GB) { '{0:N1} GB' -f ($b / 1GB) } elseif ($b -ge 1MB) { '{0:N0} MB' -f ($b / 1MB) } else { '{0:N0} KB' -f ($b / 1KB) } }
function Get-TamCarpeta([string]$r) { if (-not (Test-Path -LiteralPath $r)) { return [int64]0 }; $s = (Get-ChildItem -LiteralPath $r -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum; if ($s) { [int64]$s } else { [int64]0 } }
# Cierra con educación; devuelve $true si ya no queda ninguno en marcha
function Close-Programa([string[]]$nombres) {
    $ps = @(Get-Process -Name $nombres -ErrorAction SilentlyContinue); if (-not $ps.Count) { return $true }
    foreach ($p in $ps) { try { [void]$p.CloseMainWindow() } catch { } }
    $fin = (Get-Date).AddSeconds(12); while ((Get-Date) -lt $fin -and (Get-Process -Name $nombres -ErrorAction SilentlyContinue)) { Start-Sleep -Milliseconds 500 }
    -not (Get-Process -Name $nombres -ErrorAction SilentlyContinue)
}

# ---------------------------------------------------------------- Estado
Write-Output "  $($E.Lupa) Qué hay instalado"
$c2r = $null; try { $c2r = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction Stop } catch { }
$exeC2R = Join-Path $env:ProgramFiles 'Common Files\Microsoft Shared\ClickToRun\OfficeClickToRun.exe'
$hayOffice = [bool]($c2r -and (Test-Path -LiteralPath $exeC2R))
if ($hayOffice) { Write-Output "    $($E.OK) Microsoft 365 / Office (Click-to-Run) versión $($c2r.VersionToReport) · $($c2r.Platform) · idioma $($c2r.ClientCulture)" } else { Write-Output "    $($E.Info) No se detecta Office Click-to-Run (la reparación rápida no está disponible; las versiones MSI antiguas se reparan desde «Programas y características»)." }
$teamsClasico = Join-Path $env:APPDATA 'Microsoft\Teams'
$teamsNuevo = Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams'
$cacheOffice = Join-Path $env:LOCALAPPDATA 'Microsoft\Office\16.0\OfficeFileCache'
$onedrive = Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'
if (-not (Test-Path -LiteralPath $onedrive)) { $alt = Join-Path ${env:ProgramFiles} 'Microsoft OneDrive\OneDrive.exe'; if (Test-Path -LiteralPath $alt) { $onedrive = $alt } }
$tamTeams = (Get-TamCarpeta $teamsClasico) + (Get-TamCarpeta $teamsNuevo)
$tamOff = Get-TamCarpeta $cacheOffice
Write-Output "    $(if ($tamTeams -gt 0) { $E.OK } else { $E.Info }) Teams: $(if ($tamTeams -gt 0) { "caché de $(Format-Tam $tamTeams)" } else { 'sin datos de caché' })"
Write-Output "    $(if (Test-Path -LiteralPath $onedrive) { $E.OK } else { $E.Info }) OneDrive: $(if (Test-Path -LiteralPath $onedrive) { 'instalado' } else { 'no se encuentra' })"
Write-Output "    $($E.Info) Caché de archivos de Office: $(Format-Tam $tamOff)"
if ($SoloAnalizar) { Write-Output "`n  $($E.Info) Solo análisis: no se ha cambiado nada."; Write-Log "Reparar_Office_y_Caches: análisis (Office $hayOffice, Teams $(Format-Tam $tamTeams))"; Exit-Kit 'Ok' }

# ---------------------------------------------------------------- Elegir qué hacer
$items = @()
if ($hayOffice) { $items += [pscustomobject]@{ Id = 'office'; Texto = 'Reparación rápida de Office'; Detalle = 'Cierra Word, Excel, PowerPoint y Outlook y los repara sin conexión (unos minutos). No toca documentos ni correo.'; Marcado = $false } }
if ($tamTeams -gt 0) { $items += [pscustomobject]@{ Id = 'teams'; Texto = 'Limpiar la caché de Teams'; Detalle = "Libera $(Format-Tam $tamTeams) y arregla Teams lento o que no deja entrar. Tendrás que iniciar sesión otra vez."; Marcado = $false } }
if ($tamOff -gt 0) { $items += [pscustomobject]@{ Id = 'cacheoffice'; Texto = 'Limpiar la caché de archivos de Office'; Detalle = "Libera $(Format-Tam $tamOff). Si hay cambios pendientes de subir a OneDrive/SharePoint, guárdalos antes."; Marcado = $false } }
if (Test-Path -LiteralPath $onedrive) { $items += [pscustomobject]@{ Id = 'onedrive'; Texto = 'Restablecer OneDrive'; Detalle = 'No borra tus archivos: reinicia la sincronización y vuelve a comparar todo (puede tardar).'; Marcado = $false } }
if (-not $items.Count) { Exit-Kit 'Ok' 'No hay nada que reparar en este equipo (no se detecta Office, Teams ni OneDrive).' }
$elegidos = Show-Marcables 'Reparar Office y cachés' 'Marca lo que quieres hacer. Se cierran los programas afectados; guarda antes tu trabajo.' $items 'Hacer lo marcado'
if ($null -eq $elegidos -or -not $elegidos.Count) { Exit-Kit 'Cancelado' 'No se cambia nada.' }
$ids = @($elegidos | ForEach-Object { $_.Id }); $errores = 0

function Remove-Contenido([string]$ruta) { # vacía la carpeta sin borrar la carpeta en sí; devuelve cuántos elementos no se pudieron quitar
    $fallos = 0; if (-not (Test-Path -LiteralPath $ruta)) { return 0 }
    foreach ($i in @(Get-ChildItem -LiteralPath $ruta -Force -ErrorAction SilentlyContinue)) { try { Remove-Item -LiteralPath $i.FullName -Recurse -Force -ErrorAction Stop } catch { $fallos++ } }
    $fallos
}
try {
    if ('teams' -in $ids) {
        Write-Output "  $($E.Reloj) Limpiando la caché de Teams…"
        if (-not (Close-Programa 'ms-teams', 'Teams')) { $errores++; Write-Output "    $($E.Aviso) Teams no se cerró: ciérralo (también desde la bandeja) y repite. No se ha tocado su caché." }
        else {
            $f = 0; foreach ($sub in 'Cache', 'blob_storage', 'databases', 'GPUCache', 'IndexedDB', 'Local Storage', 'tmp', 'Code Cache') { $f += Remove-Contenido (Join-Path $teamsClasico $sub) }
            foreach ($sub in 'EBWebView\Default\Cache', 'EBWebView\Default\Code Cache', 'EBWebView\Default\GPUCache', 'Logs') { $f += Remove-Contenido (Join-Path $teamsNuevo $sub) }
            Write-Output "    $(if ($f) { $E.Aviso } else { $E.OK }) Caché de Teams limpiada$(if ($f) { " ($f elemento(s) en uso se han dejado)" })."; Write-Log "Reparar_Office_y_Caches: caché de Teams ($f sin quitar)"
        }
    }
    if ('cacheoffice' -in $ids) {
        Write-Output "  $($E.Reloj) Limpiando la caché de archivos de Office…"
        if (-not (Close-Programa 'WINWORD', 'EXCEL', 'POWERPNT', 'OUTLOOK', 'ONENOTE', 'MSACCESS', 'MSPUB', 'VISIO')) { $errores++; Write-Output "    $($E.Aviso) Hay programas de Office abiertos (¿algo sin guardar?): ciérralos y repite. No se ha tocado la caché." }
        else { $f = Remove-Contenido $cacheOffice; Write-Output "    $(if ($f) { $E.Aviso } else { $E.OK }) Caché de archivos de Office limpiada$(if ($f) { " ($f elemento(s) en uso se han dejado)" })."; Write-Log "Reparar_Office_y_Caches: caché de archivos de Office ($f sin quitar)" }
    }
    if ('onedrive' -in $ids) {
        Write-Output "  $($E.Reloj) Restableciendo OneDrive…"
        [void](Close-Programa 'OneDrive')
        $r = Invoke-Proceso $onedrive '/reset' 60 'Restablecer OneDrive' 30
        # no se relanza desde aquí: este script va elevado y OneDrive elevado rompe la sincronización con el Explorador; OneDrive se reinicia solo en contexto de usuario
        Write-Output "    $($E.OK) OneDrive restablecido; se reinicia solo en un minuto (si no, ábrelo desde el menú Inicio) y vuelve a sincronizar."; Write-Log "Reparar_Office_y_Caches: OneDrive /reset (código $($r.Codigo))"
    }
    if ('office' -in $ids) {
        Write-Output "  $($E.Reloj) Reparación rápida de Office (puede tardar varios minutos)…"
        if (-not (Close-Programa 'WINWORD', 'EXCEL', 'POWERPNT', 'OUTLOOK', 'ONENOTE', 'MSACCESS', 'MSPUB', 'VISIO')) { $errores++; Write-Output "    $($E.Aviso) Hay programas de Office abiertos (¿algo sin guardar?): ciérralos y repite." }
        else {
            $plat = if ($c2r.Platform -eq 'x86') { 'x86' } else { 'x64' }; $cult = if ($c2r.ClientCulture) { $c2r.ClientCulture } else { 'es-es' }
            $r = Invoke-Proceso $exeC2R "scenario=Repair platform=$plat culture=$cult RepairType=QuickRepair forceappshutdown=False DisplayLevel=False" 1800 'Reparación rápida de Office' 30
            if ($r.TiempoAgotado -or $r.Codigo -ne 0) { $errores++; Write-Output "    $($E.Aviso) La reparación rápida no terminó bien (código $($r.Codigo)). Prueba la reparación «en línea» desde Configuración > Aplicaciones > Microsoft 365 > Modificar." }
            else { Write-Output "    $($E.OK) Reparación rápida terminada." }
            Write-Log "Reparar_Office_y_Caches: reparación rápida (código $($r.Codigo))"
        }
    }
} catch { Exit-Kit 'Error' "Se interrumpió: $($_.Exception.Message)" }
if ($errores) { Exit-Kit 'Error' "Terminado con $errores tarea(s) sin completar." }
Exit-Kit 'Ok' 'Hecho. Abre de nuevo los programas y comprueba si el fallo continúa.'
