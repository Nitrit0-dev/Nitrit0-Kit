# =====================================================================
#  Certificados_Arranque_Seguro.ps1 - Certificados de Secure Boot 2023 (Nitrit0)
#  Los certificados de Microsoft de 2011 caducan en 2026. Si el equipo no tiene los de 2023, puede quedarse sin recibir
#  actualizaciones de arranque. Aquí se mira qué certificados hay, el estado de la actualización de Windows y, si faltan,
#  se ofrece lanzarla (con BitLocker suspendido y punto de restauración). Por defecto solo mira.
#  Parámetro: -SoloAnalizar (mira y no ofrece cambiar nada)
#  Idea tomada de Soporte OnSite (Bitlocker.ps1), sin nada de su entorno.
# =====================================================================
[CmdletBinding()]
param([switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E

Write-Output "========================================================"
Write-Output "  $($E.Lupa) CERTIFICADOS DE ARRANQUE SEGURO (2023)"
Write-Output "========================================================"
Assert-Admin 'leer los certificados de arranque seguro (Windows solo los deja leer a un administrador)'

$sb = $null
try { $sb = Confirm-SecureBootUEFI -ErrorAction Stop } catch { }
if ($null -eq $sb) { Write-Output "  $($E.Info) Este equipo no arranca en modo UEFI con Secure Boot, o Windows no lo informa. No aplica."; Write-Log 'Certificados_Arranque_Seguro: sin UEFI'; exit 0 }
if (-not $sb) { Write-Output "  $($E.Aviso) Secure Boot está desactivado en la BIOS: sin él no hay nada que actualizar. Actívalo si el equipo lo admite."; Write-Log 'Certificados_Arranque_Seguro: Secure Boot desactivado'; exit 0 }
Write-Output "  $($E.OK) Secure Boot activo."

# Busca un nombre de certificado dentro de una variable UEFI (db o KEK). $null = no se pudo leer.
function Test-CertUEFI([string]$Variable, [string]$Texto) {
    try {
        $b = (Get-SecureBootUEFI -Name $Variable -ErrorAction Stop).Bytes
        if (-not $b) { return $null }
        [Text.Encoding]::ASCII.GetString($b) -match [regex]::Escape($Texto)
    } catch { $null }
}
$db = Test-CertUEFI 'db' 'Windows UEFI CA 2023'
$kek = Test-CertUEFI 'KEK' 'Microsoft Corporation KEK 2K CA 2023'
$icono = { param($v) if ($v -eq $true) { $E.OK } elseif ($v -eq $false) { $E.Aviso } else { $E.Info } }
$texto = { param($v) if ($v -eq $true) { 'sí' } elseif ($v -eq $false) { 'NO' } else { 'no se pudo leer' } }
Write-Output "  $(& $icono $db) La base de firmas (db) tiene «Windows UEFI CA 2023»: $(& $texto $db)"
Write-Output "  $(& $icono $kek) La clave de intercambio (KEK) tiene la de 2023: $(& $texto $kek)"

# Estado que deja Windows al aplicar la actualización
$ruta = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot'
$estado = Get-ItemProperty "$ruta\Servicing" -ErrorAction SilentlyContinue
$pend = (Get-ItemProperty $ruta -ErrorAction SilentlyContinue).AvailableUpdates
if ($estado -and $estado.UEFICA2023Status) { Write-Output "  $($E.Info) Estado de la actualización en Windows: $($estado.UEFICA2023Status)." }
if ($estado -and $estado.UEFICA2023Error) { Write-Output "  $($E.Aviso) Último error de la actualización: $($estado.UEFICA2023Error)." }
if ($null -ne $pend) { Write-Output ("  {0} Actualizaciones pendientes de aplicar: 0x{1:X4}" -f $E.Info, [int]$pend) }
$tarea = Get-ScheduledTask -TaskPath '\Microsoft\Windows\PI\' -TaskName 'Secure-Boot-Update' -ErrorAction SilentlyContinue
if ($tarea) {
    $ti = $tarea | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
    if ($ti -and $ti.LastRunTime.Year -gt 2000) { Write-Output "  $($E.Info) La tarea de Windows que la aplica se ejecutó por última vez el $($ti.LastRunTime.ToString('dd/MM/yyyy HH:mm'))." }
} else { Write-Output "  $($E.Aviso) Falta la tarea de Windows que aplica la actualización: el equipo no tiene las actualizaciones acumulativas recientes." }

Write-Output ""
if ($db -eq $true -and $kek -eq $true) {
    Write-Output "  $($E.OK) Los certificados de 2023 ya están instalados."
    Write-Log 'Certificados_Arranque_Seguro: al día'
    exit 0
}
if ($null -eq $db -and $null -eq $kek) { Write-Output "  $($E.Info) No se pudieron leer las variables UEFI: no se puede decir si faltan."; Write-Log 'Certificados_Arranque_Seguro: ilegible'; exit 0 }
Write-Output "  $($E.Aviso) Faltan certificados de 2023. Instala primero las actualizaciones de Windows; si siguen faltando, se puede lanzar la actualización a mano."
Write-Log 'Certificados_Arranque_Seguro: faltan certificados'
if ($SoloAnalizar -or -not $tarea) { exit 0 }

$msg = "Se lanzará la actualización de certificados de arranque seguro de Microsoft.`n`nAntes se suspende BitLocker durante 2 reinicios y se crea un punto de restauración. Después hay que reiniciar el equipo (puede hacer falta más de una vez).`n`nEn algún equipo la BIOS pide la clave de BitLocker al reiniciar: ten la clave de recuperación a mano.`n`n¿Continuar?"
if (-not (Confirm-Accion $msg)) { Exit-Kit 'Cancelado' 'Cancelado: no se ha cambiado nada.' }
[void](Start-OperacionSegura 'Certificados de arranque seguro')
try {
    $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
    if ($bl.ProtectionStatus -eq 'On') { Suspend-BitLocker -MountPoint $env:SystemDrive -RebootCount 2 -ErrorAction Stop | Out-Null; Write-Output "  $($E.OK) BitLocker suspendido durante 2 reinicios." }
} catch { Write-Output "  $($E.Aviso) No se pudo comprobar o suspender BitLocker: $($_.Exception.Message)" }
try {
    Set-ValorSeguro $ruta 'AvailableUpdates' 0x5944
    Start-ScheduledTask -TaskPath '\Microsoft\Windows\PI\' -TaskName 'Secure-Boot-Update' -ErrorAction Stop
    Start-Sleep -Seconds 20
    $ti = Get-ScheduledTask -TaskPath '\Microsoft\Windows\PI\' -TaskName 'Secure-Boot-Update' | Get-ScheduledTaskInfo
    Write-Output ("  {0} Tarea lanzada (resultado 0x{1:X}). Reinicia el equipo y vuelve a ejecutar esto para comprobarlo." -f $E.OK, [uint32]$ti.LastTaskResult)
    Write-Log 'Certificados_Arranque_Seguro: actualización lanzada'
} catch { Write-Output "  $($E.Error) No se pudo lanzar la actualización: $($_.Exception.Message)"; Write-Log "Certificados_Arranque_Seguro: error $($_.Exception.Message)"; exit 1 }