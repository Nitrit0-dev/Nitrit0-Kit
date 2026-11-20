# =====================================================================
# Script: Diagnostico_Completo.ps1 (Ejecución Local - Nitrit0)
# =====================================================================

if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$CarpetaDestino = Get-CarpetaSalida 'Informes\Diagnostico'
if (-not (Test-Path $CarpetaDestino)) {
    New-Item -ItemType Directory -Force -Path $CarpetaDestino | Out-Null
}

$E = @{
    OK      = [char]::ConvertFromUtf32(0x2705)
    Error   = [char]::ConvertFromUtf32(0x274C)
    Aviso   = [char]::ConvertFromUtf32(0x26A0)
    Info    = [char]::ConvertFromUtf32(0x2139)
    PC      = [char]::ConvertFromUtf32(0x1F5A5)
    Reloj   = [char]::ConvertFromUtf32(0x23F3)
    Disco   = [char]::ConvertFromUtf32(0x1F4BE)
    Bateria = [char]::ConvertFromUtf32(0x1F50B)
    Red     = [char]::ConvertFromUtf32(0x1F310)
    Lupa    = [char]::ConvertFromUtf32(0x1F50D)
}

$MotorLocal = {
    $CompSystem = Get-CimInstance Win32_ComputerSystem
    $Bios       = Get-CimInstance Win32_BIOS
    $OS         = Get-CimInstance Win32_OperatingSystem
    $User       = $CompSystem.UserName
    if (-not $User) { $User = "Ninguno (Pantalla de Bloqueo)" }

    $PhysicalRAM = Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum
    $TotalRAM_GB = [math]::Ceiling($PhysicalRAM.Sum / 1GB)
    
    $DiskC         = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
    $TotalDiskC_GB = [math]::Round($DiskC.Size / 1GB, 2)
    $FreeDiskC_GB  = [math]::Round($DiskC.FreeSpace / 1GB, 2)

    Write-Output "=================================================="
    Write-Output "  $($E.PC) DIAGNÓSTICO DE HARDWARE Y SISTEMA (NITRIT0)"
    Write-Output "=================================================="
    Write-Output " EQUIPO      : $($env:COMPUTERNAME)"
    Write-Output " MARCA       : $($CompSystem.Manufacturer)"
    Write-Output " MODELO      : $($CompSystem.Model)"
    Write-Output " Nº SERIE    : $($Bios.SerialNumber)"
    Write-Output " VERSIÓN BIOS: $($Bios.SMBIOSBIOSVersion)"
    Write-Output " USR. ACTUAL : $User"
    Write-Output " S. OPERATIVO: $($OS.Caption) (Build $($OS.Version))"
    Write-Output " INSTALADO EL: $($OS.InstallDate.ToString('dd/MM/yyyy'))"
    Write-Output "--------------------------------------------------"
    Write-Output " RAM FÍSICA TOTAL    : $TotalRAM_GB GB"
    Write-Output " DISCO PRINCIPAL (C:): $TotalDiskC_GB GB"
    Write-Output "=================================================="

    Write-Output "`n--- $($E.Reloj) 1. TIEMPO DE ACTIVIDAD ---"
    $Uptime = (Get-Date) - $OS.LastBootUpTime
    if ($Uptime.Days -ge 15) { Write-Output "  $($E.Aviso) Uptime: $($Uptime.Days) días, $($Uptime.Hours) horas." }
    else { Write-Output "  $($E.OK) Uptime: $($Uptime.Days) días, $($Uptime.Hours) horas." }

    Write-Output "`n--- $($E.Disco) 2. ALMACENAMIENTO LÓGICO (C:) ---"
    $PercentFree = [math]::Round(($DiskC.FreeSpace / $DiskC.Size) * 100, 2)
    if ($PercentFree -lt 15) { Write-Output "  $($E.Error) Espacio crítico. Libre: $PercentFree% ($FreeDiskC_GB GB libres)." }
    else { Write-Output "  $($E.OK) Espacio saludable. Libre: $PercentFree% ($FreeDiskC_GB GB libres)." }

    Write-Output "`n--- $($E.Info) 3. SATURACIÓN DE RAM ---"
    $TotalVisible_GB = [math]::Round($OS.TotalVisibleMemorySize / 1MB, 2)
    $FreeRAM_GB      = [math]::Round($OS.FreePhysicalMemory / 1MB, 2)
    $UsedRAMPercent  = [math]::Round((($TotalVisible_GB - $FreeRAM_GB) / $TotalVisible_GB) * 100, 2)
    if ($UsedRAMPercent -ge 85) { Write-Output "  $($E.Aviso) Uso de RAM alto: $UsedRAMPercent%." }
    else { Write-Output "  $($E.OK) Uso de RAM estable: $UsedRAMPercent%." }

    Write-Output "`n--- $($E.Bateria) 4. ESTADO DE BATERÍA ---"
    $Battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
    if ($Battery) {
        Write-Output "  $($E.Info) Nivel de carga actual: $($Battery.EstimatedChargeRemaining)%."
        try {
            $TempXml = "$env:TEMP\$([Guid]::NewGuid()).xml"
            powercfg /batteryreport /xml /output $TempXml | Out-Null
            if (Test-Path $TempXml) {
                [xml]$BatReport = Get-Content $TempXml
                $Node = $BatReport.BatteryReport.Batteries.Battery | Select-Object -First 1
                if ($Node.DesignCapacity -and $Node.FullChargeCapacity) {
                    $designCap = [double]$Node.DesignCapacity
                    $fullCap   = [double]$Node.FullChargeCapacity
                    $cycles    = $Node.CycleCount
                    $Health    = if ($designCap -gt 0) { [math]::Round(($fullCap / $designCap) * 100, 2) } else { 0 }
                    if ($Health -lt 80) { Write-Output "  $($E.Aviso) Batería degradada al $Health%." }
                    else { Write-Output "  $($E.OK) Salud de la batería: $Health%." }
                    Write-Output "    - Capacidad actual : $fullCap mWh (De fábrica: $designCap mWh)"
                    Write-Output "    - Ciclos de carga  : $cycles"
                }
                Remove-Item $TempXml -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    } else { Write-Output "  $($E.Info) Equipo de sobremesa o batería ausente." }

    Write-Output "`n--- $($E.Red) 5. ESTADO DE RED ---"
    $NetProfile = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1
    if ($NetProfile) {
        Write-Output "  $($E.OK) Red conectada. IP: $($NetProfile.IPv4Address.IPAddress) | Puerta Enlace: $($NetProfile.IPv4DefaultGateway.NextHop)"
    } else { Write-Output "  $($E.Error) No se detecta red local ni puerta de enlace." }

    Write-Output "`n--- $($E.Aviso) 6. EVENTOS Y BSOD (Últimos 7 días) ---"
    $Apagones = Get-WinEvent -FilterHashtable @{LogName='System'; Id=41; StartTime=(Get-Date).AddDays(-7)} -ErrorAction SilentlyContinue
    if ($Apagones) { Write-Output "  $($E.Error) $($Apagones.Count) apagado(s) inesperado(s) detectado(s)." }
    else { Write-Output "  $($E.OK) Ningún apagado crítico detectado." }

    $Dumps = Get-ChildItem -Path "$env:SystemRoot\Minidump" -Filter "*.dmp" -ErrorAction SilentlyContinue
    if ($Dumps) { Write-Output "  $($E.Error) Se encontraron $($Dumps.Count) archivo(s) de volcado BSOD." }
    else { Write-Output "  $($E.OK) No hay volcados de memoria por pantallazos azules." }

    Write-Output "`n--- $($E.Lupa) 7. SALUD DEL DISCO (S.M.A.R.T) ---"
    $DiscosFisicos = Get-PhysicalDisk -ErrorAction SilentlyContinue
    if ($DiscosFisicos) {
        foreach ($DiscoF in $DiscosFisicos) {
            Write-Output "  • Disco [$($DiscoF.FriendlyName) - $($DiscoF.BusType)]: Estado $($DiscoF.HealthStatus)"
        }
    }

    Write-Output "`n--- $($E.Lupa) 8. TOP 5 PROCESOS EN EJECUCIÓN (RAM / CPU) ---"
    $TopRAM = Get-Process -ErrorAction SilentlyContinue | Sort-Object WorkingSet64 -Descending | Select-Object -First 5
    Write-Output "  [Top 5 Consumo de Memoria RAM]:"
    foreach ($p in $TopRAM) {
        $mb = [math]::Round($p.WorkingSet64 / 1MB, 1)
        Write-Output ("    • {0,-25} (PID: {1,-6}) : {2,8} MB" -f $p.ProcessName, $p.Id, $mb)
    }
    $TopCPU = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.CPU -gt 0 } | Sort-Object CPU -Descending | Select-Object -First 5
    Write-Output "`n  [Top 5 Tiempo Acumulado de CPU]:"
    foreach ($c in $TopCPU) {
        $cpuSec = [math]::Round($c.CPU, 1)
        Write-Output ("    • {0,-25} (PID: {1,-6}) : {2,8} s" -f $c.ProcessName, $c.Id, $cpuSec)
    }
}

$Salida = & $MotorLocal
$TextoFinal = $Salida -join "`r`n"
Write-Output $TextoFinal

$NombreArchivo = "Diagnostico_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$RutaFinal = Join-Path -Path $CarpetaDestino -ChildPath $NombreArchivo
$TextoFinal | Out-File -FilePath $RutaFinal -Encoding utf8
Write-Output "`n$($E.Disco) Log exportado correctamente a: $RutaFinal"
