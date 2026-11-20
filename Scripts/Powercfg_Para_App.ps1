# Informes de batería y de energía de Windows (powercfg) para la app. Se guardan solo en %TEMP%\Nitrit0_Cache\Informes (llevan nombre del equipo, serie de batería y procesos: no deben quedar en el pendrive) y la app los muestra en su propia ventana.
# Entrada por entorno: NIT_POWERCFG (battery | energy). El nombre del equipo se limpia y powercfg se llama por ruta absoluta, sin cmd.
$modo = if ($env:NIT_POWERCFG -eq 'energy') { 'energy' } else { 'battery' }
$dir = Join-Path $Global:NitKit.Cache 'Informes'
New-Item -ItemType Directory -Force $dir | Out-Null
$equipo = $env:COMPUTERNAME -replace '[^\w\-]', '_'
$exe = Join-Path $env:SystemRoot 'System32\powercfg.exe'
if ($modo -eq 'battery') {
    $f = Join-Path $dir "Bateria_$equipo.html"
    Write-Output "  $($Global:E.Lupa) Generando el informe de batería…"
    & $exe /batteryreport /output $f | ForEach-Object { Write-Output "  $_" }
} else {
    $f = Join-Path $dir "Energia_$equipo.html"
    Write-Output "  $($Global:E.Lupa) Midiendo la energía durante 60 segundos: no uses el equipo mientras tanto…"
    & $exe /energy /output $f | ForEach-Object { Write-Output "  $_" }
}
if (Test-Path -LiteralPath $f) { Write-Output "  $($Global:E.OK) Informe guardado en: $f"; Open-Informe $f }
else { Write-Output "  $($Global:E.Error) No se generó el informe."; exit 1 }
