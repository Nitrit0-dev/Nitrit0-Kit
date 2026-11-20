# =====================================================================
#  Reparar_Audio_y_Privacidad.ps1 - Arregla el sonido que desaparece y los permisos de micrófono y cámara (Nitrit0)
#  Para «no hay sonido», «el audio desapareció tras una actualización o al cambiar de pantalla HDMI», «el micrófono no funciona
#  en ninguna aplicación» o «la cámara sale bloqueada». Comprueba los servicios de audio, los dispositivos desactivados y los
#  permisos de privacidad de micrófono y cámara, y deja elegir qué reparar (cada cosa por separado, con copia para deshacer).
#  Si una directiva de la organización bloquea el micrófono o la cámara, SOLO se avisa: no se toca.
#  Parámetro: -SoloAnalizar (solo enseña el estado)   Salida: 0 bien · 1 error · 2 cancelado
# =====================================================================
[CmdletBinding()]
param([switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
if (-not $SoloAnalizar) { Assert-Admin 'reparar el audio y la privacidad' }

# ---------------------------------------------------------------- Estado
Write-Output "  $($E.Lupa) Servicios de audio"
$servicios = @(@('AudioEndpointBuilder', 'Generador de extremos de audio'), @('Audiosrv', 'Audio de Windows'))
$parados = @()
foreach ($s in $servicios) {
    $sv = Get-Service -Name $s[0] -ErrorAction SilentlyContinue
    $ok = $sv -and $sv.Status -eq 'Running'; if (-not $ok) { $parados += $s[0] }
    Write-Output ("    {0} {1} ({2}): {3}" -f $(if ($ok) { $E.OK } else { $E.Error }), $s[1], $s[0], $(if ($sv) { $sv.Status } else { 'no existe' }))
}
Write-Output "  $($E.Lupa) Dispositivos de sonido"
$tarjetas = @(Get-CimInstance Win32_SoundDevice -ErrorAction SilentlyContinue)
foreach ($t in $tarjetas) { Write-Output ("    {0} {1} · estado {2}" -f $(if ($t.Status -eq 'OK') { $E.OK } else { $E.Aviso }), $t.Name, $t.Status) }
if (-not $tarjetas.Count) { Write-Output "    $($E.Aviso) Windows no ve ninguna tarjeta de sonido: revisa el driver en «Ficha de drivers»." }
$desactivados = @()
try { $desactivados = @(Get-PnpDevice -Class AudioEndpoint -ErrorAction Stop | Where-Object { $_.Problem -eq 'CM_PROB_DISABLED' }) } catch { }
foreach ($d in $desactivados) { Write-Output "    $($E.Aviso) Desactivado: $($d.FriendlyName)" }
if (-not $desactivados.Count) { Write-Output "    $($E.OK) No hay entradas ni salidas de audio desactivadas." }

Write-Output "  $($E.Lupa) Permisos de privacidad"
$ruta = 'SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore'
$permisos = New-Object Collections.Generic.List[object]
foreach ($cap in @(@('microphone', 'Micrófono'), @('webcam', 'Cámara'))) {
    foreach ($raiz in @(@('HKCU', 'tu cuenta'), @('HKLM', 'todo el equipo'))) {
        $k = "$($raiz[0]):\$ruta\$($cap[0])"
        $v = $null; try { $v = (Get-ItemProperty -LiteralPath $k -Name Value -ErrorAction Stop).Value } catch { }
        if ($v) { Write-Output ("    {0} {1} en {2}: {3}" -f $(if ($v -eq 'Allow') { $E.OK } else { $E.Aviso }), $cap[1], $raiz[1], $v); if ($v -ne 'Allow') { $permisos.Add([pscustomobject]@{ Ruta = $k; Nombre = $cap[1]; Ambito = $raiz[1] }) } }
    }
}
$directivas = @()
foreach ($d in @(@('LetAppsAccessMicrophone', 'micrófono'), @('LetAppsAccessCamera', 'cámara'))) {
    $v = $null; try { $v = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' -Name $d[0] -ErrorAction Stop).($d[0]) } catch { }
    if ($v -eq 2) { $directivas += $d[1]; Write-Output "    $($E.Aviso) Una directiva del equipo (o de la organización) bloquea el $($d[1]) para las aplicaciones: no se cambia desde aquí." }
}
if ($SoloAnalizar) { Write-Output "`n  $($E.Info) Solo análisis: no se ha cambiado nada."; Write-Log "Reparar_Audio_y_Privacidad: análisis ($($parados.Count) servicios parados, $($desactivados.Count) desactivados, $($permisos.Count) permisos en contra)"; Exit-Kit 'Ok' }

# ---------------------------------------------------------------- Elegir qué reparar
$items = @(
    [pscustomobject]@{ Id = 'servicios'; Texto = 'Reiniciar los servicios de audio'; Detalle = $(if ($parados.Count) { "Parados ahora: $($parados -join ', ')." } else { 'Están en marcha; reiniciarlos suele devolver el sonido que se quedó mudo.' }); Marcado = ($parados.Count -gt 0) }
    [pscustomobject]@{ Id = 'dispositivos'; Texto = 'Activar los dispositivos de audio desactivados'; Detalle = $(if ($desactivados.Count) { ($desactivados | ForEach-Object { $_.FriendlyName }) -join ' · ' } else { 'Ninguno desactivado ahora.' }); Marcado = $false }
    [pscustomobject]@{ Id = 'permisos'; Texto = 'Permitir el micrófono y la cámara a las aplicaciones'; Detalle = $(if ($permisos.Count) { ($permisos | ForEach-Object { "$($_.Nombre) ($($_.Ambito))" }) -join ' · ' } else { 'Los permisos ya están en «Permitir».' }); Marcado = ($permisos.Count -gt 0) }
)
$elegidos = Show-Marcables 'Reparar audio y privacidad' 'Marca lo que quieres reparar. Los permisos se guardan para poder deshacerlos desde «Deshacer cambios».' $items 'Reparar lo marcado'
if ($null -eq $elegidos -or -not $elegidos.Count) { Exit-Kit 'Cancelado' 'No se repara nada.' }
$ids = @($elegidos | ForEach-Object { $_.Id }); $errores = 0

try {
    if ('permisos' -in $ids) { Start-OperacionSegura 'Reparar audio y privacidad' -SinPuntoRestauracion }
    if ('servicios' -in $ids) {
        Write-Output "  $($E.Reloj) Reiniciando los servicios de audio…"
        try { Stop-Service -Name Audiosrv -Force -ErrorAction SilentlyContinue; Restart-Service -Name AudioEndpointBuilder -Force -ErrorAction Stop; Start-Service -Name Audiosrv -ErrorAction Stop; Write-Output "    $($E.OK) Servicios de audio reiniciados."; Write-Log 'Reparar_Audio_y_Privacidad: servicios reiniciados' }
        catch { $errores++; Write-Output "    $($E.Aviso) No se pudieron reiniciar: $($_.Exception.Message)" }
    }
    if ('dispositivos' -in $ids) {
        foreach ($d in $desactivados) {
            try { Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction Stop; Write-Output "    $($E.OK) Activado: $($d.FriendlyName)"; Write-Log "Reparar_Audio_y_Privacidad: activado $($d.InstanceId)" }
            catch { $errores++; Write-Output "    $($E.Aviso) No se pudo activar $($d.FriendlyName): $($_.Exception.Message)" }
        }
    }
    if ('permisos' -in $ids) {
        foreach ($p in $permisos) {
            try { Set-ValorSeguro ($p.Ruta -replace '^(HK[A-Z]+):\\', '$1:\') 'Value' 'Allow' 'String'; Write-Output "    $($E.OK) $($p.Nombre) permitido en $($p.Ambito)." ; Write-Log "Reparar_Audio_y_Privacidad: $($p.Ruta) -> Allow" }
            catch { $errores++; Write-Output "    $($E.Aviso) No se pudo cambiar $($p.Nombre): $($_.Exception.Message)" }
        }
        if ($directivas.Count) { Write-Output "    $($E.Info) Sigue habiendo una directiva que bloquea: $($directivas -join ', '). Quien administra el equipo debe cambiarla." }
    }
} catch { Exit-Kit 'Error' "La reparación se interrumpió: $($_.Exception.Message)" }
if ($errores) { Exit-Kit 'Error' "Terminado con $errores problema(s)." }
Exit-Kit 'Ok' 'Reparación terminada. Si sigue sin sonar, prueba otra salida (altavoces, HDMI) en la bandeja de sonido de Windows.'
