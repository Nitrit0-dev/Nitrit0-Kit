# =====================================================================
#  Reparar_Inicio_Barra_Explorador.ps1 - Arregla el menú Inicio, la barra de tareas y el Explorador de Windows (Nitrit0)
#  Para «el menú Inicio no abre», «la barra de tareas no responde o está en blanco», «los iconos salen en blanco o mal» o «el
#  Explorador se cuelga». Comprueba el estado y deja elegir qué reparar, cada cosa por separado:
#    · Reiniciar el Explorador (la interfaz se recarga en segundos).
#    · Volver a registrar los paquetes de la interfaz (Inicio, barra, búsqueda): la reparación estándar de Microsoft.
#    · Reconstruir la caché de iconos y miniaturas (se regenera sola).
#    · Reiniciar el servicio de búsqueda de Windows.
#  No borra documentos ni cambia ajustes. Parámetro: -SoloAnalizar (solo enseña el estado)
#  Salida: 0 bien · 1 error · 2 cancelado
# =====================================================================
[CmdletBinding()]
param([switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
if (-not $SoloAnalizar) { Assert-Admin 'reparar la interfaz de Windows' }
function Format-Tam([int64]$b) { if ($b -ge 1GB) { '{0:N1} GB' -f ($b / 1GB) } elseif ($b -ge 1MB) { '{0:N0} MB' -f ($b / 1MB) } else { '{0:N0} KB' -f ($b / 1KB) } }

# ---------------------------------------------------------------- Estado
Write-Output "  $($E.Lupa) Estado de la interfaz de Windows"
# Solo el explorador de esta sesión: en un equipo con varias sesiones abiertas no se toca el de las demás personas
$miSesion = (Get-Process -Id $PID).SessionId
function Get-ExploradorSesion { @(Get-Process -Name explorer -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $miSesion }) }
$explorer = Get-ExploradorSesion
Write-Output "    $(if ($explorer.Count) { $E.OK } else { $E.Aviso }) Explorador: $(if ($explorer.Count) { "en marcha ($($explorer.Count) proceso(s))" } else { 'NO está en marcha' })"
$nombres = 'Microsoft.Windows.ShellExperienceHost', 'Microsoft.Windows.StartMenuExperienceHost', 'MicrosoftWindows.Client.CBS', 'Microsoft.Windows.Search', 'MicrosoftWindows.Client.Core'
$paquetes = @(); $mal = 0
foreach ($n in $nombres) {
    try { $p = @(Get-AppxPackage -AllUsers -Name $n -ErrorAction Stop | Select-Object -First 1) } catch { $p = @() }
    if (-not $p.Count) { continue }
    $paquetes += $p[0]
    $manifiesto = Join-Path $p[0].InstallLocation 'AppXManifest.xml'
    $bien = ([string]$p[0].Status -eq 'Ok') -and (Test-Path -LiteralPath $manifiesto)
    if (-not $bien) { $mal++ }
    Write-Output ("    {0} {1} v{2} · estado {3}{4}" -f $(if ($bien) { $E.OK } else { $E.Aviso }), $n, $p[0].Version, $p[0].Status, $(if (-not (Test-Path -LiteralPath $manifiesto)) { ' · falta su manifiesto' } else { '' }))
}
if (-not $paquetes.Count) { Write-Output "    $($E.Info) No se pudieron leer los paquetes de la interfaz$(if (-not (Test-EsAdmin)) { ' (hace falta administrador para listarlos)' })." }
$ws = Get-Service -Name WSearch -ErrorAction SilentlyContinue
Write-Output "    $(if ($ws -and $ws.Status -eq 'Running') { $E.OK } else { $E.Aviso }) Servicio de búsqueda (WSearch): $(if ($ws) { $ws.Status } else { 'no existe' })"
$cacheIconos = @("$env:LOCALAPPDATA\IconCache.db") + @(Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" -Filter '*cache_*.db' -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
$tamCache = [int64]0; foreach ($c in $cacheIconos) { if (Test-Path -LiteralPath $c) { $tamCache += (Get-Item -LiteralPath $c -Force).Length } }
Write-Output "    $($E.Info) Caché de iconos y miniaturas: $(Format-Tam $tamCache)"
if ($SoloAnalizar) { Write-Output "`n  $($E.Info) Solo análisis: no se ha cambiado nada."; Write-Log "Reparar_Inicio_Barra_Explorador: análisis ($mal paquetes con problema)"; Exit-Kit 'Ok' }

# ---------------------------------------------------------------- Elegir qué reparar
$items = @(
    [pscustomobject]@{ Id = 'explorer'; Texto = 'Reiniciar el Explorador'; Detalle = 'La barra de tareas y el escritorio desaparecen un momento y se recargan solos.'; Marcado = $true }
    [pscustomobject]@{ Id = 'paquetes'; Texto = 'Volver a registrar los paquetes de la interfaz'; Detalle = "Inicio, barra de tareas y búsqueda ($($paquetes.Count) encontrados, $mal con problema). La reparación estándar de Microsoft."; Marcado = ($mal -gt 0) }
    [pscustomobject]@{ Id = 'iconos'; Texto = 'Reconstruir la caché de iconos y miniaturas'; Detalle = 'Soluciona iconos en blanco o equivocados. Se regenera sola, pero las carpetas con muchas fotos o vídeos tardan en recargar sus miniaturas.'; Marcado = $false }
    [pscustomobject]@{ Id = 'busqueda'; Texto = 'Reiniciar el servicio de búsqueda de Windows'; Detalle = 'Si la búsqueda del menú Inicio no encuentra nada o no responde.'; Marcado = ($ws -and $ws.Status -ne 'Running') }
)
$elegidos = Show-Marcables 'Reparar Inicio, barra de tareas y Explorador' 'Marca lo que quieres reparar. Cada cosa es independiente y ninguna borra tus archivos.' $items 'Reparar lo marcado'
if ($null -eq $elegidos -or -not $elegidos.Count) { Exit-Kit 'Cancelado' 'No se repara nada.' }
$ids = @($elegidos | ForEach-Object { $_.Id }); $errores = 0

function Stop-Explorador {
    Get-ExploradorSesion | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}
function Wait-Explorador {   # Windows lo vuelve a lanzar solo (con la sesión de la persona); no se arranca a mano desde aquí para no abrirlo con permisos de administrador
    $fin = (Get-Date).AddSeconds(12); while ((Get-Date) -lt $fin) { if (Get-ExploradorSesion) { return $true }; Start-Sleep -Milliseconds 500 }; $false
}
try {
    if ('iconos' -in $ids) {
        Write-Output "  $($E.Reloj) Reconstruyendo la caché de iconos y miniaturas…"
        Stop-Explorador
        $quitados = 0; foreach ($c in $cacheIconos) { try { if (Test-Path -LiteralPath $c) { Remove-Item -LiteralPath $c -Force -ErrorAction Stop; $quitados++ } } catch { } }
        Write-Output "    $($E.OK) $quitados archivo(s) de caché eliminados."
        if (Wait-Explorador) { Write-Output "    $($E.OK) El Explorador se ha recargado." } else { Write-Output "    $($E.Aviso) El Explorador no ha vuelto solo: pulsa Ctrl+Mayús+Esc, «Ejecutar nueva tarea» y escribe explorer.exe." }
        Write-Log "Reparar_Inicio_Barra_Explorador: caché de iconos ($quitados archivos)"
    }
    if ('explorer' -in $ids -and 'iconos' -notin $ids) {
        Write-Output "  $($E.Reloj) Reiniciando el Explorador…"
        Stop-Explorador
        if (Wait-Explorador) { Write-Output "    $($E.OK) El Explorador se ha reiniciado." } else { Write-Output "    $($E.Aviso) El Explorador no ha vuelto solo: pulsa Ctrl+Mayús+Esc, «Ejecutar nueva tarea» y escribe explorer.exe." }
        Write-Log 'Reparar_Inicio_Barra_Explorador: Explorador reiniciado'
    }
    if ('paquetes' -in $ids) {
        Write-Output "  $($E.Reloj) Volviendo a registrar los paquetes de la interfaz (puede tardar)…"
        # Windows relanza estos procesos al instante; con ellos abiertos el registro falla (0x80073D02, recursos en uso)
        Get-Process -Name StartMenuExperienceHost, ShellExperienceHost, SearchHost, SearchApp -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        foreach ($p in $paquetes) {
            $m = Join-Path $p.InstallLocation 'AppXManifest.xml'
            try { Add-AppxPackage -DisableDevelopmentMode -Register $m -ErrorAction Stop; Write-Output "    $($E.OK) $($p.Name)" }
            catch { $errores++; Write-Output "    $($E.Aviso) $($p.Name): $($_.Exception.Message)" }
        }
        Write-Log "Reparar_Inicio_Barra_Explorador: paquetes registrados ($($paquetes.Count), $errores con error)"
    }
    if ('busqueda' -in $ids) {
        Write-Output "  $($E.Reloj) Reiniciando el servicio de búsqueda…"
        try { Restart-Service -Name WSearch -Force -ErrorAction Stop; Write-Output "    $($E.OK) Servicio de búsqueda reiniciado." } catch { $errores++; Write-Output "    $($E.Aviso) No se pudo reiniciar WSearch: $($_.Exception.Message)" }
    }
} catch { Exit-Kit 'Error' "La reparación se interrumpió: $($_.Exception.Message)" }
if ($errores) { Exit-Kit 'Error' "Terminado con $errores problema(s). Si el fallo continúa, cierra sesión y vuelve a entrar o reinicia." }
$interactivo = [string](Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName
if ('paquetes' -in $ids -and $interactivo -and $interactivo -notlike "*\$env:USERNAME") { Write-Output "  $($E.Aviso) Los paquetes se han registrado para $env:USERNAME, pero la sesión abierta es de ${interactivo}: si el fallo es de esa cuenta, ejecuta la herramienta desde ella." }
Exit-Kit 'Ok' 'Reparación terminada. Si el fallo continúa, cierra sesión y vuelve a entrar.'
