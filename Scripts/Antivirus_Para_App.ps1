# Análisis rápido de virus con el antivirus de Windows (Microsoft Defender), para la app de Nitrit0.
# Actualiza las definiciones, lanza el análisis rápido, espera con avisos de progreso y cuenta lo que ha encontrado.
# Defender trata las amenazas por sí solo (cuarentena o eliminación) según su configuración; aquí solo se lanza y se cuenta.
# Si el equipo usa otro antivirus no se toca: se avisa. Códigos de salida: 0 analizado, 1 no se pudo, 2 hay otro antivirus.
[CmdletBinding()]
param()
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Comun.ps1'); Initialize-Kit (Split-Path -Parent $PSScriptRoot) }
$E = $Global:E
$ErrorActionPreference = 'Continue'

$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $esAdmin) { Write-Output "$($E.Error) Hace falta abrir la app como administrador para analizar con el antivirus."; exit 1 }

# ¿Hay otro antivirus gestionando el equipo? (productState: bit 0x1000 = activo)
$otros = @()
try { $otros = @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop | Where-Object { $_.displayName -notmatch 'Defender' -and (([int]$_.productState -band 0x1000) -ne 0) }) } catch { }
if ($otros.Count) {
    Write-Output "$($E.Info) Otro antivirus: $($otros[0].displayName)"
    Write-Output "$($E.Info) Este equipo usa otro antivirus. Ábrelo y haz el análisis desde su propia ventana."
    exit 2
}
try { $estado = Get-MpComputerStatus -ErrorAction Stop } catch { Write-Output "$($E.Error) El antivirus de Windows no está disponible: $($_.Exception.Message)"; exit 1 }
if (-not $estado.AntivirusEnabled) { Write-Output "$($E.Aviso) El antivirus de Windows estaba apagado: se intenta analizar igualmente." }

Write-Output "$($E.Reloj) Actualizando las definiciones del antivirus (máximo 2 minutos)…"
$act = Start-Job { Update-MpSignature -ErrorAction Stop }
if (Wait-Job $act -Timeout 120) { try { Receive-Job $act -ErrorAction Stop | Out-Null; Write-Output "$($E.OK) Definiciones al día." } catch { Write-Output "$($E.Aviso) No se pudieron actualizar: $($_.Exception.Message)" } }
else { Stop-Job $act; Write-Output "$($E.Aviso) La actualización tardó demasiado (¿sin Internet?). Se analiza con las definiciones que hay." }
Remove-Job $act -Force -ErrorAction SilentlyContinue

$inicio = Get-Date
Write-Output "$($E.Lupa) Analizando el equipo (análisis rápido)…"
$job = Start-Job { Start-MpScan -ScanType QuickScan -ErrorAction Stop }
while (-not (Wait-Job $job -Timeout 15)) {
    $s = [int]((Get-Date) - $inicio).TotalSeconds
    Write-Output ('Analizando… {0}:{1:00} (puede tardar varios minutos)' -f [math]::Floor($s / 60), ($s % 60))
}
try { Receive-Job $job -ErrorAction Stop | Out-Null } catch { Remove-Job $job -Force -ErrorAction SilentlyContinue; Write-Output "$($E.Error) El análisis no se pudo completar: $($_.Exception.Message)"; Write-Log "Análisis de virus falló: $($_.Exception.Message)" 'ERROR'; exit 1 }
Remove-Job $job -Force -ErrorAction SilentlyContinue

# Amenazas: las detectadas durante este análisis y las que sigan activas
$nombres = @{}; $activas = @()
try { foreach ($t in @(Get-MpThreat -ErrorAction Stop)) { $nombres[[string]$t.ThreatID] = [string]$t.ThreatName; if ($t.IsActive) { $activas += $t } } } catch { }
$detectadas = @(); try { $detectadas = @(Get-MpThreatDetection -ErrorAction Stop | Where-Object { $_.InitialDetectionTime -ge $inicio.AddMinutes(-1) }) } catch { }
$vistas = @{}; $n = 0
foreach ($d in $detectadas) {
    $id = [string]$d.ThreatID; if ($vistas[$id]) { continue }; $vistas[$id] = $true; $n++
    $recurso = @($d.Resources)[0] -replace '^[a-z]+:_', ''
    Write-Output ("$($E.Aviso) Amenaza: {0} · {1} · {2}" -f $(if ($nombres[$id]) { $nombres[$id] } else { "n.º $id" }), $recurso, $(if ($d.ActionSuccess) { 'tratada por el antivirus' } else { 'pendiente de tratar' }))
}
foreach ($t in $activas) {
    $id = [string]$t.ThreatID; if ($vistas[$id]) { continue }; $vistas[$id] = $true; $n++
    Write-Output ("$($E.Aviso) Amenaza: {0} · sigue activa" -f $t.ThreatName)
}
Write-Output "Amenazas encontradas: $n"
if ($n -eq 0) { Write-Output "$($E.OK) No se ha encontrado ninguna amenaza." }
Write-Log "Análisis de virus (Defender, rápido): $n amenaza(s)"
exit 0
