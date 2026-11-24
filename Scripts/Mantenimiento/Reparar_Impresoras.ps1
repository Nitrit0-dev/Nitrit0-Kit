# =====================================================================
#  Reparar_Impresoras.ps1 - Desatasca la cola de impresión (Nitrit0)
#  Lista las impresoras y su estado, borra los trabajos atascados, reinicia el servicio de impresión,
#  quita el modo «sin conexión» y ofrece imprimir una página de prueba. No desinstala nada.
#  Parámetro: -SinPreguntas (no ofrece la página de prueba)
# =====================================================================
[CmdletBinding()]
param([switch]$SinPreguntas, [Alias('Simular')][switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
if (-not $SoloAnalizar) { Assert-Admin 'reparar las impresoras' }
$estados = @{ 1 = 'Otro'; 2 = 'Desconocido'; 3 = 'Lista'; 4 = 'Imprimiendo'; 5 = 'Calentando'; 6 = 'Detenida'; 7 = 'Sin conexión' }

function Show-Impresoras {
    $imps = @(Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue)
    if (-not $imps.Count) { Write-Host "    $($E.Aviso) No hay ninguna impresora instalada (o el servicio de impresión no responde)." }
    foreach ($i in $imps) {
        $est = if ($i.WorkOffline) { 'Sin conexión' } else { $estados[[int]$i.PrinterStatus] }
        $ico = if ($i.WorkOffline -or $i.PrinterStatus -in 6, 7) { $E.Aviso } else { $E.OK }
        Write-Host "    $ico $($i.Name)$(if ($i.Default) { ' (predeterminada)' })  ·  $est  ·  puerto $($i.PortName)  ·  driver $($i.DriverName)"
    }
    $imps
}

Write-Output "  $($E.Lupa) Impresoras instaladas:"
[void](Show-Impresoras)

$cola = Join-Path $env:SystemRoot 'System32\spool\PRINTERS'
$atascados = @(Get-ChildItem -LiteralPath $cola -File -Force -ErrorAction SilentlyContinue).Count
Write-Output "`n  $($E.Info) Trabajos en la cola: $atascados"
if ($SoloAnalizar) { Exit-Kit 'Ok' "Modo análisis: se reiniciaría el servicio de impresión, se vaciarían $atascados trabajo(s) de la cola y se quitaría el modo «sin conexión». No se ha cambiado nada." }

Write-Output "  $($E.Refresh) Reiniciando el servicio de impresión y vaciando la cola…"
$fallo = $false
[void](Start-OperacionSegura 'Reparar impresoras' -SinPuntoRestauracion)
try {
    $svc = Get-CimInstance Win32_Service -Filter "Name='Spooler'"
    if ($svc.StartMode -eq 'Disabled') { [void](Set-ServicioSeguro 'Spooler' 'Automatic'); Write-Output "    $($E.Aviso) El servicio de impresión estaba desactivado: se ha puesto en automático." }
    Stop-Service Spooler -Force -ErrorAction Stop
    (Get-Service Spooler).WaitForStatus('Stopped', [timespan]::FromSeconds(30))
    # Solo se borran los trabajos pendientes (.SHD/.SPL); las impresoras y sus drivers no se tocan
    Get-ChildItem -LiteralPath $cola -File -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    if ($atascados) { Save-Informativo "Cola de impresión vaciada ($atascados trabajo(s))" 'No se puede deshacer: hay que volver a imprimir los documentos pendientes.' }
    Start-Service Spooler -ErrorAction Stop
    (Get-Service Spooler).WaitForStatus('Running', [timespan]::FromSeconds(30))
    Write-Output "    $($E.OK) Cola vaciada ($atascados trabajo(s)) y servicio en marcha."
} catch {
    $fallo = $true
    Write-Output "    $($E.Error) No se pudo reiniciar el servicio de impresión: $($_.Exception.Message)"
    try { Start-Service Spooler -ErrorAction SilentlyContinue } catch { }
}

Start-Sleep -Seconds 3
foreach ($i in @(Get-CimInstance Win32_Printer -Filter 'WorkOffline=TRUE' -ErrorAction SilentlyContinue)) {
    try { Set-CimInstance -InputObject $i -Property @{ WorkOffline = $false } -ErrorAction Stop; Write-Output "    $($E.OK) Quitado el modo «sin conexión» de $($i.Name)." }
    catch { Write-Output "    $($E.Aviso) $($i.Name) sigue sin conexión: comprueba el cable, la Wi-Fi de la impresora o su IP." }
}

Write-Output "`n  $($E.Lupa) Estado después de la reparación:"
$imps = @(Show-Impresoras)
$pred = $imps | Where-Object Default | Select-Object -First 1

if ($pred -and -not $SinPreguntas -and -not $fallo) {
    Add-Type -AssemblyName System.Windows.Forms
    if ([Windows.Forms.MessageBox]::Show("¿Imprimir una página de prueba en «$($pred.Name)»?", 'Impresoras', 'YesNo', 'Question') -eq 'Yes') {
        $r = Invoke-CimMethod -InputObject $pred -MethodName PrintTestPage -ErrorAction SilentlyContinue
        Write-Output "  $(if ($r.ReturnValue -eq 0) { $E.OK + ' Página de prueba enviada.' } else { $E.Aviso + ' No se pudo enviar la página de prueba.' })"
    }
}
Write-Output "  $($E.Info) Si una impresora sigue sin imprimir: apágala y enciéndela, y si es de red comprueba que su IP no ha cambiado."
Write-Log "Impresoras: cola vaciada ($atascados trabajos), servicio reiniciado$(if ($fallo) { ' CON ERRORES' })"
if ($fallo) { exit 1 }
