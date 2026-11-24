# =====================================================================
#  Actualizar_Version_Windows.ps1 - Sube Windows 11 a la última versión (Nitrit0)
#  Cuando la versión instalada ya no recibe parches de seguridad. Usa el Asistente de instalación oficial
#  de Windows 11 de Microsoft (se comprueba su firma digital). Conserva programas y archivos.
#  La actualización tarda entre 30 y 90 minutos y reinicia el equipo (el asistente avisa antes).
# =====================================================================
[CmdletBinding()]
param([Alias('SoloAnalizar')][switch]$Simular)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
if (-not $Simular) { Assert-Admin 'actualizar la versión de Windows' }
Write-Output "========================================================"
Write-Output "  $($E.Refresh) ACTUALIZAR A LA ÚLTIMA VERSIÓN DE WINDOWS 11"
Write-Output "========================================================"
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
Write-Output "  Versión instalada: $($cv.ProductName) $($cv.DisplayVersion) (compilación $($cv.CurrentBuild).$($cv.UBR))"
if ([int]$cv.CurrentBuild -lt 22000) { Write-Output "  $($E.Aviso) Este equipo tiene Windows 10: este asistente es para Windows 11. Comprueba la compatibilidad antes de pasar a Windows 11."; exit 1 }

# Requisitos
$libre = (Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))).Free / 1GB
Write-Output ("  Espacio libre en {0}: {1:N1} GB" -f $env:SystemDrive, $libre)
if ($libre -lt 15) { Write-Output "  $($E.Error) Hace falta al menos 15 GB libres. Libera espacio (Limpiar temporales / Analizar espacio) y repite."; exit 1 }
$bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
if ($bat -and $bat.BatteryStatus -eq 1 -and $bat.EstimatedChargeRemaining -lt 50) { Write-Output "  $($E.Error) Conecta el cargador antes de actualizar (batería al $($bat.EstimatedChargeRemaining) %)."; exit 1 }
try { if ((Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop).ProtectionStatus -eq 'On') { Write-Output "  $($E.Aviso) El disco del sistema tiene BitLocker activo: asegúrate de tener la clave de recuperación guardada antes de seguir." } } catch { }
if (-not (Test-Internet)) { Write-Output "  $($E.Error) Sin conexión a Internet."; exit 1 }
$pend = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
if ($pend) { Write-Output "  $($E.Aviso) Hay un reinicio pendiente. Reinicia el equipo y vuelve a ejecutar esto."; exit 1 }

if (-not (Confirm-Accion "Esto actualiza Windows a la última versión: tarda entre 30 y 90 minutos y reinicia el equipo.`nGuarda antes tu trabajo y conecta el cargador.`n
¿Continuar?")) { Exit-Kit 'Cancelado' 'Cancelado: no se ha cambiado nada.' }
if (-not $Simular) { Confirm-EquipoListo 'actualizar la versión de Windows'; [void](Start-OperacionSegura 'Actualizar versión de Windows') }   # punto de restauración antes del asistente de actualización
$dest = Join-Path $Global:NitKit.Cache 'Windows11InstallationAssistant.exe'
Write-Output "  $($E.Cohete) Descargando el Asistente de instalación de Windows 11 (≈ 4 MB, de microsoft.com)…"
if ($Simular) { Write-Output "  (simulación) se descargaría y ejecutaría el asistente."; return }
Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
if (-not (Get-Descarga 'https://go.microsoft.com/fwlink/?linkid=2171764' $dest 300 3 'Asistente de Windows 11')) { Write-Output "  $($E.Error) No se pudo descargar el asistente."; exit 1 }
$sig = Get-AuthenticodeSignature -LiteralPath $dest
if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft') { Write-Output "  $($E.Error) La firma digital no es de Microsoft ($($sig.Status)). No se ejecuta."; Write-Log "Asistente Win11: firma no válida $($sig.Status)" 'ERROR'; exit 1 }
Write-Output "  $($E.OK) Firma de Microsoft verificada."
Write-Output "  $($E.Reloj) Iniciando la actualización (puede tardar 30-90 min y reiniciará el equipo)…"
Write-Log 'Asistente de Windows 11 iniciado'
$p = Start-Process -FilePath $dest -ArgumentList '/QuietInstall /SkipEULA /Auto Upgrade' -PassThru
[void]$p.WaitForExit(30000)
# El asistente solo prepara y lanza el motor de la actualización (Windows10UpgraderApp) y se cierra enseguida con código 0.
# El trabajo real lo hace ese motor, así que se vigila él.
$motor = $null
for ($i = 0; $i -lt 30 -and -not $motor; $i++) { $motor = Get-Process -Name Windows10UpgraderApp -ErrorAction SilentlyContinue | Select-Object -First 1; if (-not $motor) { Start-Sleep -Seconds 2 } }
if (-not $motor) {
    Write-Output "  $($E.Aviso) El asistente terminó (código $($p.ExitCode)) pero no se detecta el motor de la actualización."
    Write-Output "  $($E.Info) Causas posibles: ya tienes la última versión disponible para este equipo, el equipo no es compatible, o Windows lo bloquea. Se abre Windows Update para ver el estado."
    Write-Log 'Asistente Win11: no se detectó el motor de actualización' 'AVISO'
    try { Start-Process 'ms-settings:windowsupdate' } catch { }
    exit 1
}
Write-Output "  $($E.OK) La actualización está en marcha (proceso $($motor.Id)). No hace falta que hagas nada: no apagues el equipo, se reiniciará cuando haga falta."
Write-Output "  $($E.Info) Primero descarga y prepara en segundo plano (sin ventanas); puede tardar de 30 a 90 minutos."
$t0 = Get-Date
while (-not $motor.HasExited -and ((Get-Date) - $t0).TotalMinutes -lt 80) {
    Start-Sleep -Seconds 60; $motor.Refresh()
    $min = [int]((Get-Date) - $t0).TotalMinutes
    $ult = ''; try { $lg = Get-ChildItem -LiteralPath 'C:\$GetCurrent\Logs' -File -Force -ErrorAction Stop | Sort-Object LastWriteTime -Descending | Select-Object -First 1; if ($lg) { $ult = ' | registro: ' + $lg.Name } } catch { }
    Write-Output "    $($E.Reloj) Actualización en curso… $min min$ult"
}
if ($motor.HasExited) { Write-Output "  $($E.OK) El motor de la actualización terminó. Si no se reinició solo, reinicia el equipo y comprueba la versión en Configuración > Windows Update." }
else { Write-Output "  $($E.Info) Sigue en segundo plano (más de 80 min). Déjalo trabajar y no apagues el equipo." }
Write-Log 'Asistente Win11: seguimiento terminado'