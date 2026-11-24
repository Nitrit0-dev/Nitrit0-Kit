# =====================================================================
#  Punto_Restauracion.ps1 - Crea un punto de restauración de Windows antes de tocar nada (Nitrit0)
#  Activa la protección del sistema en C: si estaba desactivada y salta el límite de 1 punto cada 24 h.
#  Parámetro: -Nombre "texto del punto"
# =====================================================================
[CmdletBinding()]
param([string]$Nombre = "Nitrit0 - antes de mantenimiento")
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
Assert-Admin 'crear el punto de restauración'
Write-Output "  $($E.Lupa) Punto de restauración en $env:SystemDrive …"
# New-PuntoRestauracionSeguro corta a los 180 s si el servicio de instantáneas (VSS) está atascado y restaura el límite de 24 h al terminar
if (New-PuntoRestauracionSeguro $Nombre) { exit 0 }
Write-Output "  $($E.Info) Si la protección del sistema está bloqueada por directiva o el disco es solo de lectura, no es posible."
exit 1
