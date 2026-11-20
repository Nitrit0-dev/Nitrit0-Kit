# =====================================================================
#  Actualizar_Software.ps1 - Actualiza los programas instalados con winget (Nitrit0)
#  Con tiempo máximo, comprobación de Internet y registro en Datos\Logs.
# =====================================================================
[CmdletBinding()]
param([Alias('Simular')][switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
if (-not $SoloAnalizar) { [void](Start-OperacionSegura 'Actualizar programas') }   # punto de restauración antes de actualizar con winget

Write-Output ""
Write-Output "========================================================"
Write-Output "  $($E.Cohete) ACTUALIZADOR DE SOFTWARE (WINGET)"
Write-Output "========================================================"

$winget = Get-Command winget.exe -ErrorAction SilentlyContinue
if (-not $winget) { Write-Output "  $($E.Error) winget no está disponible en este equipo (instala «App Installer» desde la Microsoft Store)."; exit 1 }
if (-not (Test-Internet)) { Write-Output "  $($E.Error) Sin conexión a Internet."; exit 1 }

Write-Output "  $($E.Refresh) Actualizando el catálogo (máx. 2 min)…"
$r = Invoke-Proceso $winget.Source 'source update --disable-interactivity' 120 'Catálogo winget' 30
if ($r.Codigo -ne 0) { Write-Output "  $($E.Aviso) El catálogo no respondió (código $($r.Codigo)); se intenta igualmente." }

Write-Output "  $($E.Lupa) Programas con actualización disponible:"
[void](Invoke-Proceso $winget.Source 'upgrade --source winget --accept-source-agreements --disable-interactivity' 180 'Lista de actualizaciones' 30 -MostrarSalida)
if ($SoloAnalizar) { Exit-Kit 'Ok' 'Modo análisis: solo se ha listado lo que se actualizaría; no se ha actualizado nada.' }

Write-Output "  $($E.Reloj) Actualizando todo en silencio (máx. 60 min)…"
$u = Invoke-Proceso $winget.Source 'upgrade --all --source winget --include-unknown --silent --accept-package-agreements --accept-source-agreements --disable-interactivity' 3600 'Actualización de programas' 30 -MostrarSalida
if ($u.TiempoAgotado) { Write-Output "  $($E.Aviso) Se alcanzó el tiempo máximo. Vuelve a ejecutarlo para continuar."; exit 1 }
if ($u.Codigo -eq 0 -or $u.Codigo -eq -1978335189) { Write-Output "  $($E.OK) Programas al día." } else { Write-Output "  $($E.Aviso) winget terminó con código $($u.Codigo) (algún programa pudo no actualizarse: ciérralo y repite)."; exit 1 }
