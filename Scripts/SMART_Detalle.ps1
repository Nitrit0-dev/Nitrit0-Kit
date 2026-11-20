# SMART detallado de todos los discos con smartctl (se abre en una consola; el lanzador ya va como administrador).
$kit = Split-Path -Parent $PSScriptRoot
$smartctl = Join-Path $kit 'Apps\Disk\smartmontools\bin\smartctl.exe'
if (-not (Test-Path -LiteralPath $smartctl)) { Write-Host 'No se encuentra smartctl en Apps\Disk\smartmontools\bin.' -ForegroundColor Red; Read-Host 'Pulsa Intro para cerrar'; exit }
Write-Host '=== smartctl --scan ===' -ForegroundColor Cyan
$scan = & $smartctl --scan
$scan
foreach ($l in $scan) {
    if ($l -match '^(\S+)\s+-d\s+(\S+)') {
        Write-Host ''
        Write-Host "=================== $($matches[1]) ($($matches[2])) ===================" -ForegroundColor Cyan
        & $smartctl -a $matches[1] -d $matches[2]
    }
}
Write-Host ''
Read-Host 'Pulsa Intro para cerrar'
