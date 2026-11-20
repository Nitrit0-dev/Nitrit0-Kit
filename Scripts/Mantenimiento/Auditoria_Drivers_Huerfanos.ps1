# =====================================================================
# Auditoria_Drivers_Huerfanos.ps1 (Módulo Senior - Nitrit0_Kit)
# Detecta dispositivos con errores (ConfigManagerErrorCode != 0),
# hardware sin driver instalado y enumera los drivers en DriverStore.
# =====================================================================

[CmdletBinding()]
param()

if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
Write-Log 'Drivers con fallo: auditoría ejecutada'
$ErrorActionPreference = "SilentlyContinue"
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "   AUDITORÍA DE DRIVERS EN CONFLICTO Y DISPOSITIVOS CON FALLO    " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

$CodigosErrorPnP = @{
    1  = "Código 1: El dispositivo no está configurado correctamente."
    3  = "Código 3: El controlador de este dispositivo puede estar dañado o el sistema tiene poca memoria."
    10 = "Código 10: Este dispositivo no puede iniciar (Fallo de driver o hardware)."
    12 = "Código 12: Este dispositivo no encuentra suficientes recursos libres."
    14 = "Código 14: Este dispositivo no puede funcionar hasta que reinicies el equipo."
    18 = "Código 18: Vuelve a instalar los controladores de este dispositivo."
    19 = "Código 19: Windows no puede iniciar este dispositivo porque la información del Registro está incompleta."
    22 = "Código 22: Este dispositivo está deshabilitado."
    24 = "Código 24: Este dispositivo no está presente o no funciona correctamente."
    28 = "Código 28: Los controladores de este dispositivo no están instalados (Falta Driver)."
    31 = "Código 31: Este dispositivo no funciona correctamente porque Windows no puede cargar sus controladores."
    37 = "Código 37: Windows no puede inicializar el controlador de dispositivo para este hardware."
    39 = "Código 39: Windows no puede cargar el controlador de dispositivo (Archivo corrupto o ausente)."
    43 = "Código 43: Windows detuvo este dispositivo porque informó de problemas (Crítico en GPUs y USBs)."
    45 = "Código 45: Actualmente, este dispositivo de hardware no está conectado al equipo."
    48 = "Código 48: El software para este dispositivo se ha bloqueado porque tiene problemas con Windows."
    52 = "Código 52: Windows no puede comprobar la firma digital de los controladores necesarios."
}

# Si WMI falla no se puede decir "0 errores": se avisa y se sale con error
try { $DispositivosConFallo = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop | Where-Object { $_.ConfigManagerErrorCode -ne 0 }) }
catch { Exit-Kit 'Error' "No se pudo consultar el Administrador de dispositivos (WMI): $($_.Exception.Message)" }

if ($DispositivosConFallo) {
    Write-Host "`n[!] SE HAN DETECTADO $($DispositivosConFallo.Count) DISPOSITIVOS CON PROBLEMAS:" -ForegroundColor Red
    foreach ($d in $DispositivosConFallo) {
        $descErr = $CodigosErrorPnP[[int]$d.ConfigManagerErrorCode]
        if (-not $descErr) { $descErr = "Código $($d.ConfigManagerErrorCode): Error desconocido en Administrador de Dispositivos." }
        $hwId = if ($d.HardwareID) { $d.HardwareID[0] } else { $d.DeviceID }
        Write-Host "-----------------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host " Dispositivo : $($d.Name)" -ForegroundColor Yellow
        Write-Host " Clase       : $($d.PNPClass)" -ForegroundColor Gray
        Write-Host " Hardware ID : $hwId" -ForegroundColor Cyan
        Write-Host " Diagnóstico : $descErr" -ForegroundColor Red
    }
} else {
    Write-Host "`n[OK] Todos los dispositivos PnP conectados funcionan correctamente (0 errores en Administrador de Dispositivos)." -ForegroundColor Green
}

Write-Host "`n[*] Calculando espacio ocupado en DriverStore (FileRepository)..." -ForegroundColor Cyan
$RepoPath = "$env:SystemRoot\System32\DriverStore\FileRepository"
if (Test-Path $RepoPath) {
    $SizeBytes = (Get-ChildItem -Path $RepoPath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    $SizeGB = [math]::Round($SizeBytes / 1GB, 2)
    Write-Host "    Tamaño actual de DriverStore: $SizeGB GB" -ForegroundColor White
    if ($SizeGB -gt 8) {
        Write-Host "    [Recomendación] El repositorio supera los 8 GB. Puedes limpiar paquetes antiguos con: pnputil /enum-drivers" -ForegroundColor Yellow
    }
}
