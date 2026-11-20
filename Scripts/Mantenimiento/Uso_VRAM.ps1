# =====================================================================
#  Uso_VRAM.ps1 - Memoria de vídeo (VRAM) en uso y quién la gasta (Nitrit0)
#  Para juegos que van a tirones, pantallas negras o "memoria de vídeo insuficiente": muestra la VRAM
#  dedicada y compartida de cada gráfica y los procesos que más usan. Solo mide: no cierra ni cambia nada.
#  Parámetro: -Top (cuántos procesos listar; por defecto 10)
# =====================================================================
[CmdletBinding()]
param([ValidateRange(1, 50)][int]$Top = 10)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E

function MB($b) { [math]::Round([double]$b / 1MB) }

# Clases CIM de los contadores de GPU (Windows 10 1709+ con driver WDDM 2.x); no dependen del idioma
try {
    $adap = @(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory -ErrorAction Stop)
    $proc = @(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUProcessMemory -ErrorAction Stop)
} catch { Write-Output "$($E.Aviso) Este Windows o este driver gráfico no ofrece contadores de memoria de vídeo ($($_.Exception.Message))."; Write-Log "Uso_VRAM: sin contadores" 'AVISO'; exit 2 }
if (-not $adap.Count) { Write-Output "$($E.Aviso) No hay contadores de GPU disponibles (¿driver básico de Microsoft o máquina virtual?)."; exit 2 }

Write-Output "$($E.Info) Gráficas (el nombre completo está en Inventario_Equipo):"
Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object { Write-Output "   - $($_.Name)" }
foreach ($a in ($adap | Sort-Object DedicatedUsage -Descending)) {
    $id = $a.Name -replace '_phys_\d+$', ''
    Write-Output "$($E.Info) Adaptador ${id}: VRAM dedicada $(MB $a.DedicatedUsage) MB, compartida $(MB $a.SharedUsage) MB"
}

# Un proceso puede aparecer varias veces (una por motor/adaptador): se suma por PID
$porPid = $proc | ForEach-Object { if ($_.Name -match '^pid_(\d+)_') { [pscustomobject]@{ Pid = [int]$Matches[1]; Ded = [double]$_.DedicatedUsage; Comp = [double]$_.SharedUsage } } } |
    Group-Object Pid | ForEach-Object { [pscustomobject]@{ Pid = [int]$_.Name; Ded = ($_.Group | Measure-Object Ded -Sum).Sum; Comp = ($_.Group | Measure-Object Comp -Sum).Sum } } |
    Where-Object { $_.Ded -gt 0 } | Sort-Object Ded -Descending | Select-Object -First $Top
Write-Output "$($E.Lupa) Procesos que más VRAM dedicada usan:"
foreach ($p in $porPid) {
    $nombre = try { (Get-Process -Id $p.Pid -ErrorAction Stop).ProcessName } catch { 'terminado' }
    Write-Output ("   {0,6} MB  {1} (PID {2})" -f (MB $p.Ded), $nombre, $p.Pid)
}
$tot = ($adap | Measure-Object DedicatedUsage -Maximum).Maximum
Write-Output "$($E.OK) Lectura hecha. Si la dedicada se acerca al total de la tarjeta, cierra lo que más gasta (navegador y vídeo suelen ser lo primero) o baja texturas y resolución."
Write-Log "Uso_VRAM: dedicada máxima $(MB $tot) MB, $($porPid.Count) procesos listados"
