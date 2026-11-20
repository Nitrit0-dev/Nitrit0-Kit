# Salud de cada disco físico en JSON para la pantalla «Discos» de la app. Solo lee, no cambia nada.
# Temperatura, horas encendido y desgaste salen de los contadores de fiabilidad de Windows; algunos discos (USB, ciertos NVMe) no los dan: salen como null.
# No se incluye el número de serie.
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$lista = foreach ($d in Get-PhysicalDisk) {
    $c = $d | Get-StorageReliabilityCounter
    $letras = @()
    $num = $null
    if ($d.DeviceId -match '^\d+$') { $num = [int]$d.DeviceId; $letras = @(Get-Partition -DiskNumber $num | Where-Object DriveLetter | ForEach-Object { [string]$_.DriveLetter }) }
    [pscustomobject]@{
        nombre = [string]$d.FriendlyName; tipo = [string]$d.MediaType; bus = [string]$d.BusType; gb = [math]::Round($d.Size / 1GB)
        salud = [string]$d.HealthStatus; estado = [string]$d.OperationalStatus; firmware = [string]$d.FirmwareVersion; letras = $letras
        temperatura = $(if ($null -ne $c.Temperature) { [int]$c.Temperature } else { $null })
        horas = $(if ($null -ne $c.PowerOnHours) { [int]$c.PowerOnHours } else { $null })
        desgaste = $(if ($null -ne $c.Wear) { [int]$c.Wear } else { $null })
        erroresLectura = $(if ($null -ne $c.ReadErrorsTotal) { [long]$c.ReadErrorsTotal } else { $null })
        erroresEscritura = $(if ($null -ne $c.WriteErrorsTotal) { [long]$c.WriteErrorsTotal } else { $null })
        arranques = $(if ($null -ne $c.StartStopCycleCount) { [int]$c.StartStopCycleCount } else { $null })
    }
}
ConvertTo-Json -InputObject @($lista) -Depth 4 -Compress
