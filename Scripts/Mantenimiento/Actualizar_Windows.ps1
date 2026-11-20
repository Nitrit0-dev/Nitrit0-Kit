# =====================================================================
# Script: Actualizar_Windows.ps1 (Local - Nitrit0)
# =====================================================================
[CmdletBinding()]
param([Alias('Simular')][switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
Write-Output ""
Write-Output "========================================================"
Write-Output "  $($Global:E.Refresh) ACTUALIZADOR DE WINDOWS Y DRIVERS (NITRIT0)"
Write-Output "========================================================"
Write-Output ""

if ($SoloAnalizar) {
    if (Get-Module -ListAvailable -Name PSWindowsUpdate) {
        Assert-Admin 'consultar las actualizaciones disponibles'
        Import-Module PSWindowsUpdate
        Write-Output "  $($Global:E.Lupa) Actualizaciones disponibles (solo se listan):"
        try { Get-WindowsUpdate -MicrosoftUpdate -ErrorAction Stop | Select-Object KB, Size, Title | Format-Table -AutoSize | Out-String -Width 200 | Write-Output }
        catch { Exit-Kit 'Error' "No se pudo consultar Windows Update: $($_.Exception.Message)" }
    } else { Write-Output "  $($Global:E.Info) Modo análisis: se instalaría el módulo PSWindowsUpdate y después las actualizaciones de Windows y drivers." }
    Exit-Kit 'Ok' 'Modo análisis: no se ha instalado nada.'
}
[void](Start-OperacionSegura 'Actualizar Windows y drivers')   # punto de restauración antes de instalar actualizaciones
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Write-Output "  $($Global:E.Reloj) Instalando módulo PSWindowsUpdate (puede tardar un poco)..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    if (-not (Test-Internet)) { Write-Output "  $($Global:E.Error) Sin conexión a Internet: no se puede descargar PSWindowsUpdate."; exit 1 }
    Invoke-Reintento -Nombre 'Instalación de PSWindowsUpdate' -Intentos 3 -EsperaSeg 5 -Accion {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction SilentlyContinue | Out-Null
        Install-Module -Name PSWindowsUpdate -RequiredVersion 2.2.1.5 -Force -AcceptLicense -AllowClobber -ErrorAction Stop
    }
    Write-Output "  $($Global:E.OK) Módulo instalado correctamente."
}

Import-Module PSWindowsUpdate

Write-Output "  $($Global:E.Cohete) Registrando servicio de Microsoft Update (Drivers y otros productos)..."
Add-WUServiceManager -ServiceID "7971f918-a847-4430-9279-4a52d1efe18d" -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

Write-Output "  $($Global:E.Lupa) Buscando y descargando actualizaciones (Windows + Drivers)..."
try { Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot -Verbose -ErrorAction Stop }
catch { Exit-Kit 'Error' "Windows Update no terminó la instalación: $($_.Exception.Message)" }

Write-Output ""
Write-Output "========================================================"
Write-Output "  $($Global:E.OK) ACTUALIZACIÓN DE SISTEMA FINALIZADA"
Write-Output "  $($Global:E.Aviso) NOTA: Recuerda reiniciar el equipo al terminar tu mantenimiento."
Write-Output "========================================================"
Write-Output ""
