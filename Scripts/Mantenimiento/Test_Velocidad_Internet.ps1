# =====================================================================
#  Test_Velocidad_Internet.ps1 - ¿Qué velocidad real tiene la conexión a Internet? (Nitrit0)
#  Mide la latencia, la bajada y la subida contra el servidor público de pruebas de Cloudflare (speed.cloudflare.com). Solo se conecta cuando lo
#  ejecutas tú: descarga unos 30 MB y sube unos 8 MB de datos de relleno. No envía nada de tu equipo, solo lo que mide.
#  Límite: mide el camino hasta Cloudflare; hacia otros sitios la velocidad puede ser distinta.
#  Salida: 0 bien · 1 no se pudo medir
# =====================================================================
[CmdletBinding()]
param()
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
Write-Output "========================================================"
Write-Output "  $($E.Cohete) TEST DE VELOCIDAD DE INTERNET"
Write-Output "========================================================"
Write-Output "  $($E.Info) Se conecta a speed.cloudflare.com y usa unos 40 MB de datos. Cierra descargas y vídeos para que no falsee la medida."

# El adaptador con el que sale a Internet
try {
    foreach ($a in @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object Status -eq 'Up')) { Write-Output "  $($E.Info) Enlace: $($a.Name) ($($a.InterfaceDescription)) a $($a.LinkSpeed)" }
} catch { }

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
Add-Type -AssemblyName System.Net.Http
$cli = New-Object System.Net.Http.HttpClient
$cli.Timeout = [TimeSpan]::FromSeconds(45)
$base = 'https://speed.cloudflare.com'
function Measure-Mbps([long]$bytes, [double]$seg) { if ($seg -le 0) { 0 } else { [math]::Round(($bytes * 8) / $seg / 1e6, 1) } }

# 1) Latencia: la primera petición paga el handshake TLS, así que se descarta
Write-Output "`n  $($E.Reloj) [1/3] Midiendo la latencia…"
$lat = @()
try {
    for ($i = 0; $i -lt 7; $i++) {
        $sw = [Diagnostics.Stopwatch]::StartNew(); [void]$cli.GetByteArrayAsync("$base/__down?bytes=0").Result; $sw.Stop()
        if ($i -gt 0) { $lat += $sw.Elapsed.TotalMilliseconds }
    }
} catch { Write-Output "  $($E.Error) No se pudo conectar con el servidor de pruebas: $($_.Exception.GetBaseException().Message)"; Write-Output "  $($E.Info) Sin Internet, con el cortafuegos bloqueando speed.cloudflare.com o con un proxy que lo impide."; Write-Log 'Test_Velocidad_Internet: sin conexión' 'WARN'; $cli.Dispose(); exit 1 }
$lat = @($lat | Sort-Object); $med = [math]::Round($lat[[int]($lat.Count / 2)], 0); $var = [math]::Round($lat[-1] - $lat[0], 0)
Write-Output "  $(if ($med -lt 60) { $E.OK } else { $E.Aviso }) Latencia: $med ms (variación entre mediciones: $var ms)."

# 2) Bajada: 3 descargas de 10 MB
Write-Output "`n  $($E.Reloj) [2/3] Midiendo la bajada (3 descargas de 10 MB)…"
$bajadas = @()
for ($i = 1; $i -le 3; $i++) {
    try { $sw = [Diagnostics.Stopwatch]::StartNew(); $b = $cli.GetByteArrayAsync("$base/__down?bytes=10000000").Result; $sw.Stop(); $m = Measure-Mbps $b.Length $sw.Elapsed.TotalSeconds; $bajadas += $m; Write-Output "      Descarga $i`: $m Mbit/s" }
    catch { Write-Output "      Descarga $i`: falló ($($_.Exception.GetBaseException().Message))" }
}
# 3) Subida: 2 envíos de 4 MB
Write-Output "`n  $($E.Reloj) [3/3] Midiendo la subida (2 envíos de 4 MB)…"
$subidas = @(); $datos = New-Object byte[] 4000000
for ($i = 1; $i -le 2; $i++) {
    try { $sw = [Diagnostics.Stopwatch]::StartNew(); $r = $cli.PostAsync("$base/__up", (New-Object System.Net.Http.ByteArrayContent(, $datos))).Result; $sw.Stop(); [void]$r.EnsureSuccessStatusCode(); $m = Measure-Mbps $datos.Length $sw.Elapsed.TotalSeconds; $subidas += $m; Write-Output "      Subida $i`: $m Mbit/s" }
    catch { Write-Output "      Subida $i`: falló ($($_.Exception.GetBaseException().Message))" }
}
$cli.Dispose()

if (-not $bajadas.Count -and -not $subidas.Count) { Write-Output "`n  $($E.Error) No se pudo medir ni la bajada ni la subida."; Write-Log 'Test_Velocidad_Internet: sin datos' 'WARN'; exit 1 }
$bMax = if ($bajadas.Count) { ($bajadas | Measure-Object -Maximum).Maximum } else { 0 }; $bMed = if ($bajadas.Count) { [math]::Round(($bajadas | Measure-Object -Average).Average, 1) } else { 0 }
$sMax = if ($subidas.Count) { ($subidas | Measure-Object -Maximum).Maximum } else { 0 }
Write-Output "`n========================================================"
Write-Output "  Bajada: $bMax Mbit/s (media $bMed)   ·   Subida: $sMax Mbit/s   ·   Latencia: $med ms"
Write-Output "========================================================"
if ($bMax -gt 0 -and $bMax -lt 10) { Write-Output "  $($E.Aviso) La bajada es baja (menos de 10 Mbit/s): vídeo en alta calidad o descargas grandes irán lentos." }
if ($sMax -gt 0 -and $bMax -gt 0 -and $sMax -lt ($bMax / 20)) { Write-Output "  $($E.Info) La subida es muy inferior a la bajada: normal en ADSL o cable, pero molesta en videollamadas y copias a la nube." }
if ($med -ge 100) { Write-Output "  $($E.Aviso) La latencia es alta (100 ms o más): suele notarse en videollamadas y juegos. Prueba con cable en vez de Wi-Fi." }
if ($var -ge 50) { Write-Output "  $($E.Aviso) La latencia varía mucho entre mediciones: típico de un Wi-Fi saturado o con poca cobertura." }
Write-Output "  $($E.Info) Una medición suelta no es definitiva: repítela en otro momento del día. Hacia otros sitios la velocidad puede ser distinta."
Write-Log "Test_Velocidad_Internet: bajada $bMax Mbit/s, subida $sMax Mbit/s, latencia $med ms"
exit 0
