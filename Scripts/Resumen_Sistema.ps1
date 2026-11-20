# Resumen del equipo en JSON para la pantalla de inicio de la app. Solo lee, no cambia nada.
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$cs = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$os = Get-CimInstance Win32_OperatingSystem
$bios = Get-CimInstance Win32_BIOS
$discos = foreach ($d in Get-PhysicalDisk) {
    [pscustomobject]@{ nombre = $d.FriendlyName; tipo = [string]$d.MediaType; gb = [math]::Round($d.Size / 1GB); salud = [string]$d.HealthStatus; estado = [string]$d.OperationalStatus }
}
$volumenes = foreach ($v in Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.Size -gt 0 }) {   # una unidad bloqueada o sin formato (tamaño 0) no se puede medir
    [pscustomobject]@{ letra = [string]$v.DriveLetter; etiqueta = $v.FileSystemLabel; totalGb = [math]::Round($v.Size / 1GB, 1); libreGb = [math]::Round($v.SizeRemaining / 1GB, 1) }
}
$bat = Get-CimInstance Win32_Battery | Select-Object -First 1
$placa = Get-CimInstance Win32_BaseBoard | Select-Object -First 1
$gpus = @(Get-CimInstance Win32_VideoController | Where-Object { $_.Name -and $_.Name -notmatch 'Basic|Remote|Virtual' } | ForEach-Object { [pscustomobject]@{ nombre = [string]$_.Name; driver = [string]$_.DriverVersion } })
[pscustomobject]@{
    equipo = $env:COMPUTERNAME
    modelo = ('{0} {1}' -f $cs.Manufacturer, $cs.Model).Trim()
    cpu = ("$($cpu.Name)").Trim(); nucleos = $cpu.NumberOfCores; hilos = $cpu.NumberOfLogicalProcessors
    ramGb = [math]::Round($cs.TotalPhysicalMemory / 1GB)
    windows = $os.Caption; version = $os.Version
    arranque = $(if ($os.LastBootUpTime) { $os.LastBootUpTime.ToString('s') } else { '' })
    bios = [string](@($bios.SMBIOSBIOSVersion)[0])
    biosFecha = $(if ($bios.ReleaseDate) { $bios.ReleaseDate.ToString('yyyy-MM-dd') } else { '' })
    placa = ('{0} {1}' -f $placa.Manufacturer, $placa.Product).Trim()
    graficas = @($gpus)
    arquitectura = [string]$os.OSArchitecture
    instalado = $(if ($os.InstallDate) { $os.InstallDate.ToString('yyyy-MM-dd') } else { '' })
    discos = @($discos); volumenes = @($volumenes)
    bateria = if ($bat) { [pscustomobject]@{ carga = $bat.EstimatedChargeRemaining; estado = $bat.BatteryStatus } } else { $null }
} | ConvertTo-Json -Depth 4 -Compress
