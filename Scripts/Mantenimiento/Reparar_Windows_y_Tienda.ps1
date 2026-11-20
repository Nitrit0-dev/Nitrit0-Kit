# =====================================================================
#  Reparar_Windows_y_Tienda.ps1 (Edición Nitrit0 - Con Latido en Vivo)
# =====================================================================
[CmdletBinding()]
param([Alias('Simular')][switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }

if (-not $Global:E) {
    $Global:E = @{
        OK = [char]::ConvertFromUtf32(0x2705); Error = [char]::ConvertFromUtf32(0x274C); Aviso = [char]::ConvertFromUtf32(0x26A0)
        Info = [char]::ConvertFromUtf32(0x2139); Cohete = [char]::ConvertFromUtf32(0x1F680); Lupa = [char]::ConvertFromUtf32(0x1F50D)
        Disco = [char]::ConvertFromUtf32(0x1F4BE); Reloj = [char]::ConvertFromUtf32(0x23F3); Refresh = [char]::ConvertFromUtf32(0x1F504)
    }
}
$E = $Global:E

# Ejecuta el proceso con tiempo máximo y aviso de progreso. Devuelve SOLO el código de salida
# (el progreso va por Write-Host: si fuera por Write-Output se mezclaría con el valor devuelto).
function Start-ProcesoConLatido([string]$Titulo, [string]$Ejecutable, [string]$Argumentos, [int]$Timeout = 3600) {
    $r = Invoke-Proceso $Ejecutable $Argumentos $Timeout $Titulo 20
    if ($r.TiempoAgotado) { Write-Host "    $($E.Aviso) $Titulo superó el tiempo máximo ($([int]($Timeout / 60)) min) y se canceló." }
    return [int]$r.Codigo
}
Write-Output "`n========================================================"
Write-Output "  $($E.Cohete) REPARACIÓN PROFUNDA DE WINDOWS Y MICROSOFT STORE"
Write-Output "========================================================`n"

# Comprobaciones previas: DISM y SFC no pueden trabajar a la vez que otra actualización o con un reinicio pendiente (se quedan parados sin avisar)
$ocupado = @()
if (Get-Process -Name Windows10UpgraderApp, SetupHost, SetupPrep, Windows11InstallationAssistant -ErrorAction SilentlyContinue) { $ocupado += 'hay una actualización de versión de Windows en marcha' }
if ((Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')) { $ocupado += 'hay un reinicio pendiente' }
if ($ocupado) {
    Write-Output "$($E.Aviso) No se ejecuta la reparación ahora: $($ocupado -join ' y ')."
    Write-Output "  $($E.Info) Reinicia el equipo, deja que termine de actualizarse y vuelve a lanzar la reparación (si no, DISM se queda parado sin avance)."
    Write-Log "Reparar Windows cancelado: $($ocupado -join ', ')" 'AVISO'
    exit 2
}
if ($SoloAnalizar) { Exit-Kit 'Ok' 'Modo análisis: se ejecutarían chkdsk /scan, DISM /RestoreHealth y SFC /scannow, y se vaciaría la caché de Microsoft Store. No se ha cambiado nada.' }
[void](Start-OperacionSegura 'Reparar Windows y Tienda')   # punto de restauración antes de DISM/SFC y de reregistrar la Tienda
$uSis = $env:SystemDrive   # Windows no siempre está en C:
Write-Output "$($E.Lupa) [1/4] Escaneando errores en el sistema de archivos de $uSis (chkdsk /scan)..."
try {
    $codChk = Start-ProcesoConLatido "Comprobación de disco (chkdsk)" "$env:SystemRoot\System32\chkdsk.exe" "$uSis /scan" 1800
    if ($codChk -eq 0) { Write-Output "  $($E.OK) El sistema de archivos de $uSis está sano." }
    elseif ($codChk -in 1, 2) { Write-Output "  $($E.Info) chkdsk encontró y corrigió incidencias menores (código $codChk)." }
    else { Write-Output "  $($E.Aviso) chkdsk detectó anomalías que requieren revisión (código $codChk). Puede hacer falta «chkdsk $uSis /f» con reinicio." }
} catch { Write-Output "  $($E.Aviso) No se pudo ejecutar chkdsk." }

Write-Output "`n$($E.Reloj) [2/4] Reparando almacén de componentes de Windows (DISM /RestoreHealth)..."
Write-Output "  $($E.Info) Suele tardar entre 10 y 30 minutos y puede quedarse varios minutos en el mismo porcentaje: es normal, no está colgado."
$codDism = -1
try {
    $codDism = Start-ProcesoConLatido "DISM /RestoreHealth" "$env:SystemRoot\System32\dism.exe" "/Online /Cleanup-Image /RestoreHealth /NoRestart" 3600   # sin /Quiet: así el latido puede mostrar el porcentaje
    if ($codDism -eq 0 -or $codDism -eq 3010) { Write-Output "  $($E.OK) Imagen de Windows verificada y reparada con éxito (DISM)." }
    else { Write-Output "  $($E.Aviso) DISM terminó con el código $codDism." }
} catch { Write-Output "  $($E.Error) Error al ejecutar DISM." }

# SFC repara copiando de la imagen de Windows: si la imagen no está sana (o hay un reinicio pendiente de DISM), ejecutarlo solo hace perder horas sin copias buenas de las que reparar
$sfcOmitido = $false
if ($codDism -eq 3010) {
    $sfcOmitido = $true
    Write-Output "`n$($E.Aviso) [3/4] Se deja SFC para después: DISM necesita reiniciar el equipo para terminar. Reinicia y vuelve a lanzar esta reparación."
} elseif ($codDism -ne 0) {
    $sfcOmitido = $true
    Write-Output "`n$($E.Aviso) [3/4] Se omite SFC: la imagen de Windows no se ha podido reparar (DISM, código $codDism), así que SFC no tendría copias buenas con las que arreglar nada."
    Write-Output "  $($E.Info) Qué hacer: reinicia y repite; si vuelve a fallar, repara con un medio de instalación de Windows (DISM /Source) o recurre a «Actualizar Windows en el sitio»."
    Write-Log "Reparar Windows: DISM falló (código $codDism), SFC omitido" 'AVISO'
} else {
    Write-Output "`n$($E.Reloj) [3/4] Comprobando y reparando archivos del sistema (SFC /scannow)..."
    try {
        $codSfc = Start-ProcesoConLatido "SFC /scannow" "$env:SystemRoot\System32\sfc.exe" "/scannow" 3600
        if ($codSfc -eq 0) { Write-Output "  $($E.OK) Comprobador de archivos de sistema (SFC) finalizado correctamente." }
        else { Write-Output "  $($E.Aviso) SFC terminó con código $codSfc." }
    } catch { Write-Output "  $($E.Error) Error al ejecutar SFC." }
}

Write-Output "`n$($E.Refresh) [4/4] Limpiando caché de Microsoft Store..."
$RutaStoreCache = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalCache"
if (Test-Path $RutaStoreCache) {
    Remove-Item -Path "$RutaStoreCache\*" -Recurse -Force -ErrorAction SilentlyContinue
    Save-Informativo 'Caché local de Microsoft Store vaciada' 'No hace falta deshacerla: la Tienda la regenera sola al abrirse.'
    Write-Output "  $($E.OK) Caché local de Microsoft Store vaciada."
}

Write-Output "`n========================================================"
if ($codDism -ne 0 -and $codDism -ne 3010) { Write-Output "  $($E.Aviso) REPARACIÓN TERMINADA SIN ARREGLAR LA IMAGEN DE WINDOWS"; Write-Output "========================================================"; exit 1 }
Write-Output "  $($E.OK) REPARACIÓN DEL SISTEMA $(if ($sfcOmitido) { 'PARCIAL (falta SFC tras reiniciar)' } else { 'COMPLETADA' })"
Write-Output "========================================================"