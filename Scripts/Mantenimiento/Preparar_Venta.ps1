# =====================================================================
#  Preparar_Venta.ps1 - Deja el equipo listo para venderlo, regalarlo o devolverlo (Nitrit0)
#  Repasa lo que hay que hacer ANTES de borrar (datos, cuentas, BitLocker, licencia) y abre el
#  restablecimiento de fábrica de Windows. El borrado lo hace el asistente de Windows, no este script,
#  y solo empieza cuando el técnico lo confirma en sus pantallas.
#  Parámetro: -SoloComprobar (repasa la lista y no abre el restablecimiento)
# =====================================================================
[CmdletBinding()]
param([Alias('SoloAnalizar')][switch]$SoloComprobar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
Write-Output "  $($E.Lupa) Repaso antes de borrar el equipo:`n"

# 1. Datos de los usuarios
$raizUsuarios = Split-Path $env:USERPROFILE -Parent
foreach ($u in Get-ChildItem -LiteralPath $raizUsuarios -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin 'Public', 'Default', 'Default User', 'All Users' }) {
    $tam = 0; foreach ($c in 'Desktop', 'Documents', 'Pictures', 'Videos', 'Music', 'Downloads') { $p = Join-Path $u.FullName $c; if (Test-Path -LiteralPath $p) { $tam += (Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue 2>$null | Measure-Object Length -Sum).Sum } }
    Write-Output ("  $(if ($tam -gt 50MB) { $E.Aviso } else { $E.OK }) Usuario {0}: {1:N1} GB en sus carpetas personales" -f $u.Name, ($tam / 1GB))
}
Write-Output "      Si el cliente quiere conservar algo, haz antes «Copia de datos del usuario». Después no se puede recuperar."

# 2. Cuentas Microsoft
$ctas = @(); try { $ctas = @(Get-LocalUser -ErrorAction Stop | Where-Object { $_.Enabled -and $_.PrincipalSource -eq 'MicrosoftAccount' }) } catch { }
if ($ctas.Count) { Write-Output "`n  $($E.Aviso) Cuentas Microsoft en el equipo: $($ctas.Name -join ', ')"; Write-Output "      Después de borrar, el dueño debe quitar el equipo en account.microsoft.com/devices para que no siga a su nombre." }
else { Write-Output "`n  $($E.OK) No hay cuentas Microsoft vinculadas (solo cuentas locales)." }

# 3. BitLocker
try {
    $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
    if ($bl.ProtectionStatus -eq 'On' -or $bl.VolumeStatus -ne 'FullyDecrypted') { Write-Output "`n  $($E.Info) El disco está cifrado con BitLocker ($($bl.VolumeStatus)). Es bueno para la venta: lo borrado no se puede recuperar. El restablecimiento lo quita solo." }
    else { Write-Output "`n  $($E.Info) El disco no está cifrado: en el asistente elige «Limpiar la unidad» para que los datos no se puedan recuperar." }
} catch { Write-Output "`n  $($E.Info) No se pudo consultar BitLocker (edición Home sin cifrado de dispositivo o falta el módulo)." }

# 4. Licencia de Windows
$oem = ''; try { $oem = (Get-CimInstance SoftwareLicensingService -ErrorAction Stop).OA3xOriginalProductKey } catch { }
if ($oem) { Write-Output "`n  $($E.OK) La licencia de Windows va grabada en la placa: se reactiva sola después de borrar." }
else { Write-Output "`n  $($E.Aviso) No hay clave de Windows en la placa. Si la licencia es digital sigue ligada al equipo; si es una clave comprada aparte, guárdala con «Licencias y BitLocker»." }

# 5. Tipo de disco
try { foreach ($d in Get-PhysicalDisk -ErrorAction Stop | Where-Object { $_.BusType -ne 'USB' }) { Write-Output "`n  $($E.Info) Disco $($d.FriendlyName) ($($d.MediaType), $([math]::Round($d.Size / 1GB)) GB)$(if ($d.MediaType -eq 'HDD') { ': en un disco mecánico «Limpiar la unidad» puede tardar varias horas.' })" } } catch { }

Write-Output "`n  $($E.Info) Recuerda también: cerrar sesión en Office, iCloud, Steam y navegadores, y quitar tarjetas SD y pendrives del cliente."
Write-Log 'Preparar para venta: repaso hecho'
if ($SoloComprobar) { return }

Add-Type -AssemblyName System.Windows.Forms
$msg = "Se va a abrir el restablecimiento de fábrica de Windows.`n`nEn sus pantallas elige:`n  1. «Quitar todo»`n  2. «Reinstalación local»`n  3. Cambiar configuración > «¿Limpiar datos?» = Sí`n`nSe borran TODOS los datos y programas de este equipo. Conéctalo a la corriente.`n`n¿Abrir el asistente de Windows ahora?"
if ([Windows.Forms.MessageBox]::Show($msg, 'Preparar para venta', 'YesNo', 'Warning', 'Button2') -ne 'Yes') { Exit-Kit 'Cancelado' 'No se ha abierto el restablecimiento. No se ha cambiado nada.' }
try { Start-Process (Join-Path $env:SystemRoot 'System32\systemreset.exe') -ArgumentList '-factoryreset' -ErrorAction Stop; Write-Output "`n  $($E.OK) Asistente de Windows abierto. El borrado empieza solo cuando lo confirmes allí."; Write-Log 'Preparar para venta: abierto systemreset -factoryreset' 'AVISO' }
catch { Write-Output "`n  $($E.Error) No se pudo abrir el restablecimiento: $($_.Exception.Message). Ábrelo desde Configuración > Sistema > Recuperación."; exit 1 }
