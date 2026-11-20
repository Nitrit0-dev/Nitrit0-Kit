# =====================================================================
#  Latencia_DPC.ps1 - Carga de DPC e interrupciones del equipo (Nitrit0)
#  Para tirones de audio/vídeo, ratón a saltos o latencia alta en juegos: mide cuánto tiempo pasa la CPU
#  atendiendo drivers (DPC) e interrupciones de hardware. Solo mide: no cambia nada.
#  Parámetro: -Segundos (duración de la medición, 10-120; por defecto 20)
# =====================================================================
[CmdletBinding()]
param([ValidateRange(10, 120)][int]$Segundos = 20)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E

# Clase CIM en vez de Get-Counter: los nombres de los contadores se traducen al idioma de Windows y la clase no
$clase = 'Win32_PerfFormattedData_PerfOS_Processor'
Write-Output "$($E.Reloj) Midiendo $Segundos s (no uses el equipo para que el resultado sea fiable)..."
$dpc = @(); $isr = @(); $dpcs = @(); $ints = @()
try {
    for ($i = 0; $i -lt $Segundos; $i++) {
        $m = Get-CimInstance $clase -Filter "Name='_Total'" -ErrorAction Stop
        $dpc += [double]$m.PercentDPCTime; $isr += [double]$m.PercentInterruptTime
        $dpcs += [double]$m.DPCsQueuedPersec; $ints += [double]$m.InterruptsPersec
        Start-Sleep -Seconds 1
    }
} catch { Write-Output "$($E.Error) No se pudieron leer los contadores de rendimiento: $($_.Exception.Message)"; Write-Log "Latencia_DPC: $($_.Exception.Message)" 'ERROR'; exit 1 }

function Resumen($v) { $o = $v | Measure-Object -Average -Maximum; [pscustomobject]@{ Media = [math]::Round($o.Average, 2); Max = [math]::Round($o.Maximum, 2) } }
$d = Resumen $dpc; $n = Resumen $isr; $q = Resumen $dpcs; $t = Resumen $ints
Write-Output "$($E.Info) Tiempo en DPC (drivers):        media $($d.Media) %   pico $($d.Max) %"
Write-Output "$($E.Info) Tiempo en interrupciones:       media $($n.Media) %   pico $($n.Max) %"
Write-Output "$($E.Info) DPC en cola por segundo:        media $($q.Media)   pico $($q.Max)"
Write-Output "$($E.Info) Interrupciones por segundo:     media $($t.Media)   pico $($t.Max)"

# Umbrales orientativos (no hay norma): >10 % de media ya se nota en audio en tiempo real
$suma = $d.Media + $n.Media
if ($suma -ge 20 -or $d.Max -ge 40) { Write-Output "$($E.Error) Carga alta: un driver está acaparando la CPU. Prueba a actualizar o desactivar red/Wi-Fi, audio, USB y gráfica, uno a uno, y repite la medición." }
elseif ($suma -ge 10 -or $d.Max -ge 20) { Write-Output "$($E.Aviso) Carga algo elevada. Si hay tirones, sospecha de Wi-Fi/Bluetooth, controladoras USB o drivers de audio antiguos." }
else { Write-Output "$($E.OK) Carga de DPC e interrupciones normal: no es la causa de los tirones." }
Write-Output "$($E.Info) Esta medición no dice QUÉ driver lo causa; para señalarlo hace falta una traza (LatencyMon o xperf)."
Write-Log "Latencia_DPC: DPC media $($d.Media)% pico $($d.Max)%, interrupciones media $($n.Media)% pico $($n.Max)%"
