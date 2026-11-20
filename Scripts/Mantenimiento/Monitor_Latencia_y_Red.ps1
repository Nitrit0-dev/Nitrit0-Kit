# =====================================================================
# Monitor_Latencia_y_Red.ps1 (Módulo Senior Telemetría de Red - Nitrit0_Kit)
# Distingue si los cortes de Internet son culpa del Wi-Fi/Router local
# o de la operadora (ISP), midiendo Jitter, pérdida de paquetes y velocidad DNS.
# =====================================================================

[CmdletBinding()]
param([switch]$Silencioso)

if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
Write-Log 'Latencia de red: medición ejecutada'
$ErrorActionPreference = "SilentlyContinue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir   = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$InformesDir = if (Get-Command Get-CarpetaSalida -ErrorAction SilentlyContinue) { Get-CarpetaSalida Informes } else { Join-Path $RootDir "Datos\Informes" }
if (-not (Test-Path $InformesDir)) { New-Item -ItemType Directory -Path $InformesDir -Force | Out-Null }

$FechaStr = Get-Date -Format "yyyyMMdd_HHmm"
$Equipo   = $env:COMPUTERNAME
$OutHtml  = Join-Path $InformesDir "Telemetria_Red_${Equipo}_${FechaStr}.html"

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "   TELEMETRÍA DE RED: ROUTER LOCAL VS OPERADORA + JITTER + DNS   " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# 1. Detectar Puerta de Enlace (Router local)
$Gateway = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Sort-Object RouteMetric | Select-Object -First 1).NextHop
if (-not $Gateway) { Write-Host "  AVISO: este equipo no tiene puerta de enlace (ruta por defecto): no hay router al que medir." -ForegroundColor Yellow; $Gateway = "(sin puerta de enlace)" }   # antes se medía un router inventado (192.168.1.1)

Write-Host "[1/3] Midiendo estabilidad hacia tu Router ($Gateway) y hacia Internet (1.1.1.1 y 8.8.8.8)..." -ForegroundColor Yellow

function Measure-TargetPing([string]$Target, [string]$Nombre) {
    $pings = Test-Connection -ComputerName $Target -Count 15 -ErrorAction SilentlyContinue
    $recibidos = @($pings).Count
    $perdidos  = 15 - $recibidos
    $pctPerdida = [math]::Round(($perdidos / 15) * 100, 1)
    if ($recibidos -gt 0) {
        $tiempos = @($pings | ForEach-Object { $_.ResponseTime })
        $min = ($tiempos | Measure-Object -Minimum).Minimum
        $max = ($tiempos | Measure-Object -Maximum).Maximum
        $avg = [math]::Round(($tiempos | Measure-Object -Average).Average, 1)
        # Jitter = media de variación entre pings consecutivos
        $diffs = @()
        for ($i = 1; $i -lt $tiempos.Count; $i++) {
            $diffs += [math]::Abs($tiempos[$i] - $tiempos[$i-1])
        }
        $jitter = if ($diffs.Count -gt 0) { [math]::Round(($diffs | Measure-Object -Average).Average, 1) } else { 0 }
    } else {
        $min = 0; $max = 0; $avg = 999; $jitter = 999
    }
    [PSCustomObject]@{
        Nodo       = $Nombre
        IP         = $Target
        MediaMs    = $avg
        MinMs      = $min
        MaxMs      = $max
        JitterMs   = $jitter
        PerdidaPct = $pctPerdida
    }
}

$ResRouter     = Measure-TargetPing $Gateway "1. Tu Router Local (Wi-Fi / Cable)"
$ResCloudflare = Measure-TargetPing "1.1.1.1" "2. Cloudflare (Salida a Internet)"
$ResGoogle     = Measure-TargetPing "8.8.8.8" "3. Google DNS (Contraste Global)"
$TablaPings    = @($ResRouter, $ResCloudflare, $ResGoogle)

# 2. Benchmark de servidores DNS
Write-Host "[2/3] Comparando velocidad de respuesta DNS (Operadora actual vs Cloudflare vs Google vs Quad9)..." -ForegroundColor Yellow
$ServidoresDNS = @(
    @{ Nombre = "Cloudflare DNS"; IP = "1.1.1.1" }
    @{ Nombre = "Google Public DNS"; IP = "8.8.8.8" }
    @{ Nombre = "Quad9 Security DNS"; IP = "9.9.9.9" }
)
# El DNS que usa ahora mismo el equipo (normalmente el del router/operadora) entra en la comparación
$DnsActual = @((Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses } | Select-Object -First 1).ServerAddresses)[0]
if ($DnsActual -and $DnsActual -notin @($ServidoresDNS | ForEach-Object { $_.IP })) { $ServidoresDNS = @(@{ Nombre = "Tu DNS actual"; IP = $DnsActual }) + $ServidoresDNS }
$ResultadosDNS = @()
foreach ($sd in $ServidoresDNS) {
    $null = Resolve-DnsName -Name "www.microsoft.com" -Server $sd.IP -DnsOnly -QuickTimeout -ErrorAction SilentlyContinue   # calentamiento: la primera consulta no es representativa
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $rd = Resolve-DnsName -Name "www.microsoft.com" -Server $sd.IP -DnsOnly -QuickTimeout -ErrorAction SilentlyContinue
    $sw.Stop()
    $ResultadosDNS += [PSCustomObject]@{
        Proveedor = $sd.Nombre
        Servidor  = $sd.IP
        TiempoMs  = $(if ($rd) { $sw.ElapsedMilliseconds } else { 9999 })   # 9999 = sin respuesta (queda al final del ranking)
    }
}
$ResultadosDNS = $ResultadosDNS | Sort-Object TiempoMs

# 3. Diagnóstico inteligente automático
$DiagnosticoRed = "CONEXIÓN EXCELENTE: Tu red local y la salida a Internet tienen baja latencia, bajo jitter y 0% de pérdida."
$ColorDiag = "#10b981"
# Algunos routers no contestan a ping: si Internet sí responde, eso no es un fallo de la red local
$RouterMudo = ($ResRouter.PerdidaPct -ge 100 -and $ResCloudflare.PerdidaPct -lt 100)
if ($ResRouter.PerdidaPct -ge 100 -and $ResCloudflare.PerdidaPct -ge 100) {
    $DiagnosticoRed = "SIN CONEXIÓN: no responden ni el router ($Gateway) ni Internet. Comprueba que el Wi-Fi o el cable estén conectados y que el router esté encendido."
    $ColorDiag = "#ef4444"
} elseif ($RouterMudo -and ($ResCloudflare.PerdidaPct -gt 0 -or $ResCloudflare.JitterMs -gt 25)) {
    $DiagnosticoRed = "CONEXIÓN INESTABLE: hay micro-cortes o picos de latencia hacia Internet. Tu router ($Gateway) no responde a ping, así que no se puede saber si el fallo es del Wi-Fi o de la operadora: repite la prueba conectado por cable."
    $ColorDiag = "#f59e0b"
} elseif ($RouterMudo) {
    $DiagnosticoRed = "CONEXIÓN CORRECTA hacia Internet (baja latencia y 0% de pérdida). Tu router ($Gateway) no responde a ping, algo normal en algunos modelos, así que el tramo local no se ha podido medir."
} elseif ($ResRouter.PerdidaPct -gt 0 -or $ResRouter.JitterMs -gt 15) {
    $DiagnosticoRed = "PROBLEMA EN TU WIFI O CABLE LOCAL: Se detecta pérdida ($($ResRouter.PerdidaPct)%) o alta inestabilidad ($($ResRouter.JitterMs) ms de Jitter) antes siquiera de salir del router ($Gateway). Acércate al router, usa la banda 5 GHz o revisa el cable Ethernet."
    $ColorDiag = "#ef4444"
} elseif ($ResCloudflare.PerdidaPct -gt 0 -or $ResCloudflare.JitterMs -gt 25) {
    $DiagnosticoRed = "PROBLEMA EN LA OPERADORA (ISP): La conexión entre tu PC y el router va perfecta ($($ResRouter.MediaMs) ms), pero hay micro-cortes o picos de latencia de la calle hacia fuera."
    $ColorDiag = "#f59e0b"
}

$FilasPingHtml = ($TablaPings | ForEach-Object {
    "<tr><td><b>$($_.Nodo)</b></td><td>$($_.IP)</td><td><b>$($_.MediaMs) ms</b></td><td>$($_.MinMs) / $($_.MaxMs) ms</td><td>$($_.JitterMs) ms</td><td>$($_.PerdidaPct)%</td></tr>"
}) -join "`n"

$FilasDnsHtml = ($ResultadosDNS | ForEach-Object {
    "<tr><td><b>$($_.Proveedor)</b></td><td>$($_.Servidor)</td><td><b>$(if ($_.TiempoMs -ge 9999) { 'Sin respuesta' } else { "$($_.TiempoMs) ms" })</b></td></tr>"
}) -join "`n"

$Html = @"
<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<title>Telemetría de Red - $Equipo</title>
<style>
  body { font-family: 'Segoe UI', sans-serif; margin: 0; background: #0f172a; color: #f8fafc; }
  header { background: #020617; padding: 22px 32px; border-bottom: 2px solid #1e293b; }
  header h1 { margin: 0; font-size: 21px; color: #38bdf8; }
  .container { max-width: 1000px; margin: 24px auto; padding: 0 24px; }
  .veredicto { padding: 16px 20px; border-radius: 10px; background: #1e293b; border-left: 6px solid $ColorDiag; margin-bottom: 24px; font-weight: 600; }
  .card { background: #1e293b; border-radius: 10px; padding: 20px; margin-bottom: 20px; border: 1px solid #334155; }
  .card h2 { margin-top: 0; font-size: 16px; color: #38bdf8; border-bottom: 1px solid #334155; padding-bottom: 8px; }
  table { width: 100%; border-collapse: collapse; font-size: 13.5px; }
  th, td { text-align: left; padding: 10px; border-bottom: 1px solid #334155; }
  th { background: #0f172a; color: #94a3b8; }
</style>
</head>
<body>
<header>
  <h1>KIT NITRIT0 · Diagnóstico Comparativo de Red (Wi-Fi Local vs Operadora + Jitter)</h1>
</header>
<div class="container">
  <div class="veredicto">$DiagnosticoRed</div>
  <div class="card">
    <h2>1. Prueba de Estabilidad (15 muestras por tramo)</h2>
    <table>
      <thead><tr><th>Tramo Evaluado</th><th>Dirección IP</th><th>Latencia Media</th><th>Mín / Máx</th><th>Jitter (Oscilación)</th><th>Paquetes Perdidos</th></tr></thead>
      <tbody>$FilasPingHtml</tbody>
    </table>
  </div>
  <div class="card">
    <h2>2. Ranking de Velocidad de Servidores DNS desde tu Conexión</h2>
    <table>
      <thead><tr><th>Proveedor DNS</th><th>IP Primaria</th><th>Tiempo de Resolución</th></tr></thead>
      <tbody>$FilasDnsHtml</tbody>
    </table>
  </div>
</div>
</body>
</html>
"@

[System.IO.File]::WriteAllText($OutHtml, $Html, (New-Object System.Text.UTF8Encoding($true)))
if (-not $Silencioso) { Open-Informe $OutHtml }
Write-Host "[OK] Informe de Telemetría de Red generado en: $OutHtml" -ForegroundColor Green
