# =====================================================================
#  Que_Esta_Frenando_Ahora.ps1 - Qué proceso está saturando el equipo AHORA MISMO (Nitrit0)
#  Para «va lento ahora», «el ventilador no para» o «el disco está al 100 %». Mide unos segundos (CPU, disco y memoria por
#  proceso, con contadores de Windows: no depende del idioma) y enseña los que más consumen. Después deja marcar qué hacer:
#    · Cerrar un proceso (primero con educación; solo a la fuerza si no responde, y se dice cuál).
#    · Parar un servicio de Windows que no es imprescindible (hasta el próximo reinicio: no se desactiva).
#  Nunca ofrece procesos del sistema (System, csrss, lsass, dwm, el Explorador…) ni el antivirus.
#  Parámetros: -SoloAnalizar (solo mide y enseña)  -Segundos (duración de la medición, 5-30; por defecto 8)
#  Salida: 0 bien · 1 error · 2 cancelado
# =====================================================================
[CmdletBinding()]
param([Alias('SoloMirar')][switch]$SoloAnalizar, [ValidateRange(5, 30)][int]$Segundos = 8)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
if (-not $SoloAnalizar) { Assert-Admin 'cerrar procesos y parar servicios' }
function Format-Tam([int64]$b) { if ($b -ge 1GB) { '{0:N1} GB' -f ($b / 1GB) } elseif ($b -ge 1MB) { '{0:N0} MB' -f ($b / 1MB) } else { '{0:N0} KB' -f ($b / 1KB) } }

$protegidos = 'idle', 'system', 'registry', 'memory compression', 'smss', 'csrss', 'wininit', 'winlogon', 'services', 'lsass', 'lsm', 'fontdrvhost', 'dwm', 'explorer', 'sihost', 'ctfmon', 'msmpeng', 'nissrv', 'securityhealthservice', 'securityhealthsystray', 'sgrmbroker', 'wudfhost', 'spoolsv', 'audiodg', 'taskhostw', 'runtimebroker', 'startmenuexperiencehost', 'shellexperiencehost', 'searchhost', 'claude', 'nitrit0'
# Servicios que se pueden parar sin riesgo hasta el próximo reinicio
$serviciosPrescindibles = @{ WSearch = 'Búsqueda de Windows (indexador)'; SysMain = 'SysMain (Superfetch)'; DiagTrack = 'Telemetría y experiencias del usuario'; wuauserv = 'Windows Update'; BITS = 'Transferencia en segundo plano (BITS)'; DoSvc = 'Optimización de distribución (DoSvc)'; UsoSvc = 'Orquestador de actualizaciones'; WerSvc = 'Informe de errores de Windows'; WMPNetworkSvc = 'Uso compartido de Windows Media Player'; MapsBroker = 'Mapas descargados' }

# ---------------------------------------------------------------- Medición
Write-Output "  $($E.Reloj) Midiendo $Segundos segundos (CPU, disco y memoria por proceso)…"
$nucleos = [math]::Max(1, [int](Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).NumberOfLogicalProcessors)
$muestras = @{}; $cpuTotal = @(); $discoTotal = @(); $n = [math]::Max(3, [int]($Segundos / 2))
for ($i = 0; $i -lt $n; $i++) {
    try {
        foreach ($p in (Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -ErrorAction Stop)) {
            if ($p.Name -in '_Total', 'Idle') { continue }
            $k = [string]$p.IDProcess
            if (-not $muestras.ContainsKey($k)) { $muestras[$k] = [pscustomobject]@{ Id = [int]$p.IDProcess; Nombre = ($p.Name -replace '#\d+$', ''); Cpu = 0.0; Io = 0.0; Mem = [int64]0; N = 0 } }
            $m = $muestras[$k]; $m.Cpu += [double]$p.PercentProcessorTime / $nucleos; $m.Io += [double]$p.IODataBytesPersec; $m.Mem = [int64]$p.WorkingSetPrivate; $m.N++
        }
        $cpuTotal += [double](Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction Stop).PercentProcessorTime
        $discoTotal += [double](Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'" -ErrorAction Stop).PercentDiskTime
    } catch { }
    if ($i -lt $n - 1) { Start-Sleep -Seconds 2 }
}
if (-not $muestras.Count) { Exit-Kit 'Error' 'No se pudieron leer los contadores de rendimiento de Windows. Prueba a ejecutar «lodctr /R» como administrador y reintenta.' }
$lista = @($muestras.Values | ForEach-Object { $_.Cpu = [math]::Round($_.Cpu / [math]::Max(1, $_.N), 1); $_.Io = $_.Io / [math]::Max(1, $_.N); $_ })
$cpuMed = if ($cpuTotal.Count) { [math]::Round(($cpuTotal | Measure-Object -Average).Average, 0) } else { $null }
$disMed = if ($discoTotal.Count) { [math]::Min(100, [math]::Round(($discoTotal | Measure-Object -Average).Average, 0)) } else { $null }
$os = Get-CimInstance Win32_OperatingSystem
$ramPct = [math]::Round(100 - ($os.FreePhysicalMemory / $os.TotalVisibleMemorySize * 100), 0)

Write-Output "  $($E.Lupa) Estado general"
Write-Output ("    {0} Procesador: {1}" -f $(if ($null -ne $cpuMed -and $cpuMed -ge 85) { $E.Aviso } else { $E.OK }), $(if ($null -ne $cpuMed) { "$cpuMed % de media" } else { 'sin dato' }))
Write-Output ("    {0} Disco: {1}" -f $(if ($null -ne $disMed -and $disMed -ge 85) { $E.Aviso } else { $E.OK }), $(if ($null -ne $disMed) { "$disMed % de actividad" } else { 'sin dato' }))
Write-Output ("    {0} Memoria: {1} % en uso ({2} libres de {3})" -f $(if ($ramPct -ge 85) { $E.Aviso } else { $E.OK }), $ramPct, (Format-Tam ([int64]$os.FreePhysicalMemory * 1KB)), (Format-Tam ([int64]$os.TotalVisibleMemorySize * 1KB)))

# Servicios de cada proceso (svchost agrupa varios)
$serv = @{}; foreach ($s in (Get-CimInstance Win32_Service -Filter "State='Running'" -ErrorAction SilentlyContinue)) { if ($s.ProcessId) { if (-not $serv.ContainsKey([int]$s.ProcessId)) { $serv[[int]$s.ProcessId] = @() }; $serv[[int]$s.ProcessId] += $s } }

$porCpu = @($lista | Sort-Object Cpu -Descending | Select-Object -First 5 | Where-Object { $_.Cpu -ge 1 })
$porDisco = @($lista | Sort-Object Io -Descending | Select-Object -First 5 | Where-Object { $_.Io -ge 100KB })
$porMem = @($lista | Sort-Object Mem -Descending | Select-Object -First 5)
function Show-Top($titulo, $items, $texto) {
    Write-Output "  $($E.Lupa) $titulo"
    if (-not $items.Count) { Write-Output "    $($E.OK) Ninguno destaca."; return }
    foreach ($x in $items) { Write-Output ("    {0} {1} (PID {2}): {3}" -f $E.Info, $x.Nombre, $x.Id, (& $texto $x)) }
}
Show-Top 'Los que más procesador usan' $porCpu { param($x) "$($x.Cpu) % de CPU" }
Show-Top 'Los que más disco usan' $porDisco { param($x) "$(Format-Tam ([int64]$x.Io))/s" }
Show-Top 'Los que más memoria usan' $porMem { param($x) (Format-Tam $x.Mem) }
if ($SoloAnalizar) { Write-Output "`n  $($E.Info) Solo análisis: no se ha cerrado ni parado nada."; Write-Log "Que_Esta_Frenando_Ahora: análisis (CPU $cpuMed %, disco $disMed %, RAM $ramPct %)"; Exit-Kit 'Ok' }

# ---------------------------------------------------------------- Elegir qué hacer
$candidatos = @($porCpu + $porDisco + $porMem | Sort-Object Id -Unique)
$items = New-Object Collections.Generic.List[object]
foreach ($x in $candidatos) {
    if ($x.Nombre.ToLower() -in $protegidos) { continue }
    if ($x.Nombre -eq 'svchost') {
        foreach ($s in @($serv[$x.Id] | Where-Object { $serviciosPrescindibles.ContainsKey($_.Name) })) {
            $items.Add([pscustomobject]@{ Id = "srv:$($s.Name)"; Texto = "Parar el servicio «$($serviciosPrescindibles[$s.Name])»"; Detalle = "Está dentro del proceso svchost (PID $($x.Id)) que más recursos usa. Se vuelve a iniciar solo al reiniciar el equipo."; Marcado = $false })
        }
        continue
    }
    $detalle = "PID $($x.Id) · $($x.Cpu) % CPU · $(Format-Tam ([int64]$x.Io))/s de disco · $(Format-Tam $x.Mem) de memoria. Se cierra con educación; solo a la fuerza si no responde."
    $items.Add([pscustomobject]@{ Id = "pid:$($x.Id)"; Texto = "Cerrar $($x.Nombre)"; Detalle = $detalle; Marcado = $false })
}
if (-not $items.Count) { Exit-Kit 'Ok' 'Ningún proceso se puede cerrar con seguridad desde aquí (solo destacan procesos del sistema).' }
$elegidos = Show-Marcables 'Qué lo está frenando ahora' 'Marca lo que quieres cerrar o parar. Guarda antes tu trabajo en esos programas.' @($items) 'Hacer lo marcado'
if ($null -eq $elegidos -or -not $elegidos.Count) { Exit-Kit 'Cancelado' 'No se cierra ni se para nada.' }
$errores = 0
foreach ($e in $elegidos) {
    if ($e.Id -like 'srv:*') {
        $nom = $e.Id.Substring(4)
        try { Stop-Service -Name $nom -Force -ErrorAction Stop; Write-Output "    $($E.OK) Servicio parado: $($serviciosPrescindibles[$nom])"; Write-Log "Que_Esta_Frenando_Ahora: servicio $nom parado" } catch { $errores++; Write-Output "    $($E.Aviso) No se pudo parar $nom : $($_.Exception.Message)" }
    } else {
        $id = [int]$e.Id.Substring(4)
        $proc = Get-Process -Id $id -ErrorAction SilentlyContinue
        if ($proc -and $e.Texto -ne "Cerrar $($proc.ProcessName)") { $proc = $null }   # el PID pudo reutilizarse por otro programa mientras se elegía
        if (-not $proc) { Write-Output "    $($E.Info) $($e.Texto): ya no estaba en marcha."; continue }
        try {
            [void]$proc.CloseMainWindow(); $cerrado = $proc.WaitForExit(8000)
            if (-not $cerrado) { Stop-Process -Id $id -Force -ErrorAction Stop; Write-Output "    $($E.Aviso) $($proc.ProcessName) no respondía y se cerró a la fuerza (puede perder lo no guardado)."; Write-Log "Que_Esta_Frenando_Ahora: $($proc.ProcessName) ($id) cerrado a la fuerza" }
            else { Write-Output "    $($E.OK) $($proc.ProcessName) cerrado."; Write-Log "Que_Esta_Frenando_Ahora: $($proc.ProcessName) ($id) cerrado" }
        } catch { $errores++; Write-Output "    $($E.Aviso) No se pudo cerrar $($proc.ProcessName): $($_.Exception.Message)" }
    }
}
if ($errores) { Exit-Kit 'Error' "Terminado con $errores problema(s)." }
Exit-Kit 'Ok' 'Hecho. Si el equipo sigue lento, vuelve a medir: puede que el culpable sea otro.'
