# =====================================================================
#  Sensores reales (temperaturas, ventiladores, potencia) - Nitrit0
#  Usa LibreHardwareMonitorLib.dll (carpeta "HW Info\LibreHardwareMonitor").
#  Para leer la CPU y la placa necesita permisos de administrador y, en las versiones
#  recientes, el controlador PawnIO. Sin ellos devuelve solo lo que Windows permite
#  (discos, batería, algunas gráficas) y lo indica en .Motivo.
#  Todo es de solo lectura.
# =====================================================================

function Open-Sensores {
    param([string]$Raiz)
    $dir = Join-Path $Raiz 'Apps\HW Info\LibreHardwareMonitor'
    $lib = Join-Path $dir 'LibreHardwareMonitorLib.dll'
    if (-not (Test-Path -LiteralPath $lib)) { return [pscustomobject]@{ Ok = $false; Motivo = 'No está LibreHardwareMonitor en el kit.'; Equipo = $null } }
    # Las bibliotecas se cargan en este proceso: solo si su huella consta en la lista de integridad
    if (Get-Command Test-ScriptAutorizado -ErrorAction SilentlyContinue) {
        foreach ($d in 'HidSharp.dll', 'LibreHardwareMonitorLib.dll') { $m = Test-ScriptAutorizado (Join-Path $dir $d); if ($m) { return [pscustomobject]@{ Ok = $false; Motivo = "No se cargan los sensores: $d $m."; Equipo = $null } } }
    }
    try {
        foreach ($d in 'HidSharp.dll', 'LibreHardwareMonitorLib.dll') { [void][Reflection.Assembly]::LoadFrom((Join-Path $dir $d)) }
        $c = New-Object LibreHardwareMonitor.Hardware.Computer
        $c.IsCpuEnabled = $true; $c.IsGpuEnabled = $true; $c.IsMotherboardEnabled = $true; $c.IsStorageEnabled = $true
        $c.IsBatteryEnabled = $true; $c.IsControllerEnabled = $true; $c.IsMemoryEnabled = $false; $c.IsNetworkEnabled = $false
        $c.Open()
        [pscustomobject]@{ Ok = $true; Motivo = ''; Equipo = $c }
    } catch { [pscustomobject]@{ Ok = $false; Motivo = "No se pudo iniciar la lectura de sensores: $($_.Exception.Message)"; Equipo = $null } }
}

function Close-Sensores($s) { try { if ($s -and $s.Equipo) { $s.Equipo.Close() } } catch { } }

# Devuelve una lectura con los valores más útiles. $s es lo que devuelve Open-Sensores.
function Read-Sensores($s) {
    $r = [ordered]@{ Disponible = $false; Motivo = ''; CpuTemp = $null; CpuNucleos = @(); CpuPotenciaW = $null; CpuMHzMax = $null; CpuMHzMin = $null; GpuTemp = $null; GpuNombre = ''; Ventiladores = @(); Discos = @(); PlacaTemps = @(); Todos = @() }
    if (-not $s -or -not $s.Ok) { $r.Motivo = if ($s) { $s.Motivo } else { 'Sin sensores' }; return [pscustomobject]$r }
    try {
        $lista = New-Object System.Collections.Generic.List[object]
        $visitar = $null
        $visitar = { param($hw) $hw.Update(); foreach ($sn in $hw.Sensors) { $lista.Add([pscustomobject]@{ Hw = "$($hw.HardwareType)"; HwNombre = $hw.Name; Tipo = "$($sn.SensorType)"; Nombre = $sn.Name; Valor = $sn.Value }) }; foreach ($sub in $hw.SubHardware) { & $visitar $sub } }
        foreach ($hw in $s.Equipo.Hardware) { & $visitar $hw }
        $r.Todos = $lista.ToArray()
        $cpu = @($lista | Where-Object { $_.Hw -eq 'Cpu' })
        $tc = @($cpu | Where-Object { $_.Tipo -eq 'Temperature' -and $null -ne $_.Valor -and $_.Valor -gt 0 })   # sin permisos o sin PawnIO los sensores de la CPU salen a 0 °C: eso no es una lectura
        if ($tc) {
            $pk = $tc | Where-Object { $_.Nombre -match 'Package|Tctl|Core Max|Average' } | Select-Object -First 1
            $r.CpuTemp = if ($pk) { [math]::Round($pk.Valor) } else { [math]::Round(($tc | Measure-Object Valor -Maximum).Maximum) }
            $r.CpuNucleos = @($tc | Where-Object { $_.Nombre -match 'Core #' } | ForEach-Object { [math]::Round($_.Valor) })
        }
        $pw = $cpu | Where-Object { $_.Tipo -eq 'Power' -and $_.Nombre -match 'Package' -and $null -ne $_.Valor } | Select-Object -First 1; if ($pw) { $r.CpuPotenciaW = [math]::Round($pw.Valor, 1) }
        $ck = @($cpu | Where-Object { $_.Tipo -eq 'Clock' -and $_.Nombre -match 'Core #' -and $null -ne $_.Valor } | ForEach-Object { [double]$_.Valor })
        if ($ck) { $r.CpuMHzMax = [math]::Round(($ck | Measure-Object -Maximum).Maximum); $r.CpuMHzMin = [math]::Round(($ck | Measure-Object -Minimum).Minimum) }
        $gpu = @($lista | Where-Object { $_.Hw -match '^Gpu' -and $_.Tipo -eq 'Temperature' -and $null -ne $_.Valor })
        if ($gpu) { $g = $gpu | Where-Object { $_.Nombre -match 'Core|GPU' } | Select-Object -First 1; if (-not $g) { $g = $gpu[0] }; $r.GpuTemp = [math]::Round($g.Valor); $r.GpuNombre = $g.HwNombre }
        $r.Ventiladores = @($lista | Where-Object { $_.Tipo -eq 'Fan' -and $null -ne $_.Valor } | ForEach-Object { [pscustomobject]@{ Nombre = "$($_.HwNombre) · $($_.Nombre)"; RPM = [math]::Round($_.Valor) } })
        $r.Discos = @($lista | Where-Object { $_.Hw -eq 'Storage' -and $_.Tipo -eq 'Temperature' -and $null -ne $_.Valor } | Group-Object HwNombre | ForEach-Object { $pr = $_.Group | Where-Object { $_.Nombre -eq 'Temperature' } | Select-Object -First 1; if (-not $pr) { $pr = $_.Group | Select-Object -First 1 }; $otros = ($_.Group | Where-Object { $_.Nombre -ne $pr.Nombre } | ForEach-Object { "$($_.Nombre) $([math]::Round($_.Valor)) °C" }) -join ', '; [pscustomobject]@{ Nombre = $_.Name; Temp = [math]::Round($pr.Valor); Otros = $otros } })
        $r.PlacaTemps = @($lista | Where-Object { $_.Hw -in 'Motherboard', 'SuperIO', 'EmbeddedController' -and $_.Tipo -eq 'Temperature' -and $null -ne $_.Valor } | ForEach-Object { [pscustomobject]@{ Nombre = $_.Nombre; Temp = [math]::Round($_.Valor) } })
        $r.Disponible = ($null -ne $r.CpuTemp) -or ($null -ne $r.GpuTemp) -or ($r.Discos.Count -gt 0) -or ($r.Ventiladores.Count -gt 0)
        if ($null -eq $r.CpuTemp) { $r.Motivo = 'La temperatura de la CPU no es accesible (hace falta ejecutar como administrador y el controlador PawnIO).' }
    } catch { $r.Motivo = "Error al leer sensores: $($_.Exception.Message)" }
    [pscustomobject]$r
}
