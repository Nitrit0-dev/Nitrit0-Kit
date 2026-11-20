# =====================================================================
#  Informe_Rapido.ps1 - Informe de texto del equipo (hardware, discos, batería y errores recientes)
#  Define New-Informe. Lo usa el lanzador (dot-source) y la app (ejecutado como script: imprime el informe).
#  Usa $dirInformes; si no existe, Datos\Informes del kit.
# =====================================================================
function New-Informe {
    $f = Join-Path $dirInformes ("Informe_{0}_{1}.txt" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmmss'))
    New-Item -ItemType Directory -Path $dirInformes -Force | Out-Null
    $sb = New-Object Text.StringBuilder
    function Sec($t, $o) { [void]$sb.AppendLine(("`r`n=== {0} ===" -f $t)); try { [void]$sb.AppendLine((($o | Out-String -Width 200).TrimEnd())) } catch { [void]$sb.AppendLine("(no disponible: $($_.Exception.Message))") } }
    [void]$sb.AppendLine("INFORME RÁPIDO - $env:COMPUTERNAME - $(Get-Date -Format 'dd/MM/yyyy HH:mm')")
    $os = Get-CimInstance Win32_OperatingSystem
    Sec 'Sistema' (Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer, Model, @{n='RAM_GB';e={[math]::Round($_.TotalPhysicalMemory/1GB,1)}})
    Sec 'Windows' ($os | Select-Object Caption, Version, @{n='Arranque';e={$_.LastBootUpTime}}, @{n='Instalado';e={$_.InstallDate}})
    Sec 'BIOS / Placa' ((Get-CimInstance Win32_BIOS | Select-Object SMBIOSBIOSVersion, ReleaseDate), (Get-CimInstance Win32_BaseBoard | Select-Object Manufacturer, Product))
    Sec 'CPU' (Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed)
    Sec 'Módulos de RAM' (Get-CimInstance Win32_PhysicalMemory | Select-Object BankLabel, @{n='GB';e={$_.Capacity/1GB}}, Speed, Manufacturer, PartNumber)
    Sec 'GPU' (Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, @{n='VRAM_GB';e={[math]::Round($_.AdapterRAM/1GB,1)}})
    Sec 'Discos (estado)' (Get-PhysicalDisk | Select-Object FriendlyName, MediaType, @{n='GB';e={[math]::Round($_.Size/1GB)}}, HealthStatus, OperationalStatus)
    Sec 'Volúmenes' (Get-Volume | Where-Object DriveLetter | Select-Object DriveLetter, FileSystemLabel, @{n='Libre_GB';e={[math]::Round($_.SizeRemaining/1GB,1)}}, @{n='Total_GB';e={[math]::Round($_.Size/1GB,1)}})
    $bat = Get-CimInstance Win32_Battery
    Sec 'Batería' $(if ($bat) { $bat | Select-Object EstimatedChargeRemaining, BatteryStatus } else { 'Sin batería (sobremesa)' })
    Sec 'Dispositivos con error' (Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 } | Select-Object Name, ConfigManagerErrorCode)
    Sec 'Errores críticos del sistema (7 días)' (Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=(Get-Date).AddDays(-7)} -MaxEvents 25 -ErrorAction SilentlyContinue | Select-Object TimeCreated, ProviderName, Id, @{n='Mensaje';e={($_.Message -split "`n")[0]}})
    [IO.File]::WriteAllText($f, $sb.ToString(), (New-Object Text.UTF8Encoding($true)))
    $f
}

# Ejecutado desde la app (Ejecutar_Para_App.ps1): crea el informe y lo muestra en la salida
if ($env:NIT_APP) {
    $dirInformes = Get-CarpetaSalida 'Informes'   # pack público: %TEMP%; personal: Datos\Informes
    $f = New-Informe
    Write-Output "  $($Global:E.OK) Informe guardado en: $f"
    Write-Output ''
    Get-Content -LiteralPath $f -Encoding UTF8 | ForEach-Object { Write-Output $_ }
}
