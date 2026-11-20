# Restaura lo que Desinstalar_Total movió a la cuarentena (carpetas y registro). Salida: 0 bien · 1 error · 2 cancelado.
[CmdletBinding()]
param([Alias('Simular')][switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
Assert-Admin 'restaurar desde la cuarentena (carpetas del sistema y registro)'
$global:LASTEXITCODE = 0
try { & (Join-Path $PSScriptRoot 'Desinstalar_Total.ps1') -Restaurar -SoloAnalizar:$SoloAnalizar } catch { Exit-Kit 'Error' "No se pudo restaurar: $($_.Exception.Message)" }
exit $LASTEXITCODE
