# Elimina definitivamente la cuarentena de Desinstalar_Total (libera espacio; ya no se podrá restaurar).
# La confirmación (sesiones y MB) la pide Desinstalar_Total. Salida: 0 bien · 1 error · 2 cancelado.
[CmdletBinding()]
param([Alias('Simular')][switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
Assert-Admin 'vaciar la cuarentena (está en ProgramData)'
$global:LASTEXITCODE = 0
try { $m = Test-ScriptAutorizado (Join-Path $PSScriptRoot 'Desinstalar_Total.ps1'); if ($m) { throw "Desinstalar_Total.ps1 $m" }; & (Join-Path $PSScriptRoot 'Desinstalar_Total.ps1') -VaciarCuarentena -SoloAnalizar:$SoloAnalizar } catch { Exit-Kit 'Error' "No se pudo vaciar la cuarentena: $($_.Exception.Message)" }
exit $LASTEXITCODE
