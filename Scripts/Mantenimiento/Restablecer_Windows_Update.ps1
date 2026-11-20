# =====================================================================
#  Restablecer_Windows_Update.ps1 - Arregla Windows Update atascado (Nitrit0)
#  Detiene los servicios, renombra SoftwareDistribution y catroot2, vuelve a registrar los componentes y reinicia los servicios.
#  No borra nada: las carpetas antiguas se conservan con el sufijo .bak_<fecha>.
# =====================================================================
[CmdletBinding()]
param([Alias('Simular')][switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
if ($SoloAnalizar) {
    Write-Output "  $($E.Info) Modo análisis: se pararían wuauserv, bits, cryptSvc y msiserver; SoftwareDistribution y catroot2 se renombrarían a .bak_<fecha>; se registrarían de nuevo 19 componentes DLL, se haría «winsock reset» (no se deshace solo) y se volverían a iniciar los servicios."
    Exit-Kit 'Ok' 'No se ha cambiado nada.'
}
Assert-Admin 'restablecer Windows Update'
[void](Start-OperacionSegura 'Restablecer Windows Update')   # punto de restauración antes de vaciar la caché de actualizaciones
$serv = 'wuauserv', 'bits', 'cryptSvc', 'msiserver'
Write-Output "  $($E.Reloj) Deteniendo servicios de actualización…"
foreach ($s in $serv) { try { Stop-Service $s -Force -ErrorAction Stop; Write-Output "    parado: $s" } catch { Write-Output "    $($E.Aviso) $s : $($_.Exception.Message)" } }
Start-Sleep -Seconds 2
$marca = Get-Date -Format 'yyyyMMdd_HHmmss'
foreach ($c in "$env:SystemRoot\SoftwareDistribution", "$env:SystemRoot\System32\catroot2") {
    if (Test-Path -LiteralPath $c) { try { Rename-Item -LiteralPath $c -NewName ((Split-Path $c -Leaf) + ".bak_$marca") -ErrorAction Stop; Write-Output "  $($E.OK) $c renombrada" } catch { Write-Output "  $($E.Error) No se pudo renombrar ${c}: $($_.Exception.Message)" } }
}
Write-Output "  $($E.Refresh) Registrando de nuevo los componentes…"
foreach ($d in 'atl.dll', 'urlmon.dll', 'mshtml.dll', 'shdocvw.dll', 'browseui.dll', 'jscript.dll', 'vbscript.dll', 'scrrun.dll', 'msxml3.dll', 'msxml6.dll', 'actxprxy.dll', 'softpub.dll', 'wintrust.dll', 'initpki.dll', 'wuapi.dll', 'wuaueng.dll', 'wups.dll', 'wups2.dll', 'wuwebv.dll') { [void](Invoke-Proceso 'regsvr32.exe' "/s $d" 30 "regsvr32 $d" 60) }
[void](Invoke-Proceso 'netsh.exe' 'winsock reset' 60 'Winsock' 60)
Write-Output "  $($E.Reloj) Iniciando servicios…"
foreach ($s in $serv) { try { Start-Service $s -ErrorAction Stop; Write-Output "    iniciado: $s" } catch { Write-Output "    $($E.Aviso) $s : $($_.Exception.Message)" } }
Write-Output "`n  $($E.OK) Hecho. Reinicia el equipo y busca actualizaciones de nuevo."
Write-Log 'Windows Update restablecido'
