# =====================================================================
#  Por_Que_Falla_Windows_Update.ps1 - Dice POR QUÉ falla Windows Update, no solo lo reinicia (Nitrit0)
#  Para «no se instala una actualización», «se queda en 0 %» o «error 0x80...». Solo lectura. Reúne:
#    · Los últimos fallos del registro de Windows Update, con el código de error y su significado habitual.
#    · El estado de los servicios (wuauserv, BITS, CryptSvc, TrustedInstaller), el espacio libre y si hay un reinicio pendiente.
#  Y recomienda qué herramienta del kit usar (SFC/DISM, Restablecer Windows Update…). No cambia nada.
#  Parámetro: -Dias (cuántos días atrás mirar; por defecto 30)   Salida: 0 bien · 1 error
# =====================================================================
[CmdletBinding()]
param([ValidateRange(1, 365)][int]$Dias = 30)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E

# Códigos frecuentes -> causa y qué hacer. El mensaje del evento depende del idioma; el código no.
$causas = @{
    '0x80070005' = 'Acceso denegado: un antivirus, permisos dañados o una directiva bloquean la actualización. Prueba «Restablecer Windows Update» y revisa el antivirus.'
    '0x80070057' = 'Parámetro no válido: suele ser un almacén de componentes dañado. Ejecuta DISM y luego SFC.'
    '0x80070070' = 'No hay espacio en disco suficiente. Libera espacio («Limpieza profunda de Windows»).'
    '0x80070422' = 'El servicio de Windows Update está desactivado. Actívalo (abajo se ve su estado).'
    '0x800f0922' = 'Falló al preparar la actualización: poco espacio en la partición reservada del sistema o conflicto de componentes.'
    '0x800f081f' = 'Faltan archivos de origen del componente. Ejecuta DISM /RestoreHealth (herramienta «DISM»).'
    '0x80073712' = 'Archivo de componentes dañado o ausente. Ejecuta DISM y luego SFC.'
    '0x80073701' = 'Falta un componente referenciado por la actualización. Ejecuta DISM y SFC.'
    '0x8007371b' = 'Una transacción de componentes está dañada. Ejecuta DISM y SFC.'
    '0x80240fff' = 'Error genérico de Windows Update: restablece sus componentes.'
    '0x80244022' = 'El servidor devolvió un error temporal (503). Suele resolverse solo; reintenta más tarde.'
    '0x8024402c' = 'No se resuelve el servidor de actualizaciones: revisa DNS, proxy o firewall («Red avanzada»).'
    '0x80072ee2' = 'Tiempo de espera agotado hablando con Microsoft: revisa la conexión, el proxy o el firewall.'
    '0x80072efe' = 'Se cortó la conexión con el servidor de actualizaciones: revisa la red o un proxy.'
    '0x800705b4' = 'Tiempo de espera agotado: puede ser lentitud de red o un servicio colgado. Reintenta o restablece Windows Update.'
    '0x80200053' = 'Fallo de integridad de la descarga (BITS): restablece Windows Update.'
    '0x8007000d' = 'Datos no válidos: archivo de actualización o componentes corruptos. Restablece Windows Update y ejecuta DISM.'
    '0xc1900101' = 'Un driver falló durante la actualización de versión. Quita drivers antiguos o de terceros y reintenta.'
    '0x80004005' = 'Error no especificado: mira la lista de abajo y el resto de pruebas.'
}

Write-Output "  $($E.Lupa) Estado de Windows Update"
$problemas = 0
foreach ($n in 'wuauserv', 'BITS', 'CryptSvc', 'TrustedInstaller', 'UsoSvc') {
    $s = Get-CimInstance Win32_Service -Filter "Name='$n'" -ErrorAction SilentlyContinue; if (-not $s) { continue }
    $mal = $s.StartMode -eq 'Disabled'; if ($mal) { $problemas++ }
    Write-Output ("    {0} {1}: {2}, inicio {3}{4}" -f $(if ($mal) { $E.Aviso } else { $E.OK }), $n, $s.State, $s.StartMode, $(if ($mal) { ' · DESACTIVADO: no podrá actualizar' } else { '' }))
}
$drv = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':')) -ErrorAction SilentlyContinue
if ($drv -and $null -ne $drv.Free) {
    $libre = [int64]$drv.Free
    Write-Output ("    {0} Espacio libre en {1}: {2:N1} GB{3}" -f $(if ($libre -lt 10GB) { $E.Aviso } else { $E.OK }), $env:SystemDrive, ($libre / 1GB), $(if ($libre -lt 10GB) { ' (poco para actualizar)' } else { '' }))
    if ($libre -lt 10GB) { $problemas++ }
} else { Write-Output "    $($E.Info) No se pudo leer el espacio libre de $env:SystemDrive." }
$pend = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations')
Write-Output "    $(if ($pend) { $E.Aviso } else { $E.OK }) Reinicio pendiente: $(if ($pend) { 'SÍ: reinicia antes de volver a intentarlo' } else { 'no' })"
if ($pend) { $problemas++ }

Write-Output "  $($E.Lupa) Fallos de los últimos $Dias días"
$desde = (Get-Date).AddDays(-$Dias); $codigos = @{}
try {
    $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-WindowsUpdateClient/Operational'; Id = 20, 24, 25, 31; StartTime = $desde } -ErrorAction Stop | Sort-Object TimeCreated -Descending)
    if (-not $ev.Count) { Write-Output "    $($E.OK) Sin fallos registrados en ese periodo." }
    foreach ($x in ($ev | Select-Object -First 8)) {
        $cod = if ($x.Message -match '0x[0-9A-Fa-f]{8}') { $Matches[0].ToLower() } else { '' }
        if ($cod) { $codigos[$cod] = 1 + [int]$codigos[$cod] }
        $linea = ($x.Message -split "`r?`n")[0]; if ($linea.Length -gt 150) { $linea = $linea.Substring(0, 150) + '…' }
        Write-Output "    $($E.Aviso) $($x.TimeCreated.ToString('dd/MM/yyyy HH:mm')) · $linea"
    }
    if ($ev.Count) { $problemas++ }
    foreach ($x in ($ev | Select-Object -Skip 8)) { if ($x.Message -match '0x[0-9A-Fa-f]{8}') { $c = $Matches[0].ToLower(); $codigos[$c] = 1 + [int]$codigos[$c] } }
} catch {
    if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { Write-Output "    $($E.OK) Sin fallos registrados en ese periodo." } else { Write-Output "    $($E.Info) No se pudo leer el registro de Windows Update: $($_.Exception.Message)" }
}

if ($codigos.Count) {
    Write-Output "  $($E.Lupa) Qué significan"
    foreach ($c in ($codigos.GetEnumerator() | Sort-Object Value -Descending)) {
        $texto = if ($causas.ContainsKey($c.Key)) { $causas[$c.Key] } else { 'Código sin explicación en el kit: búscalo en la web de Microsoft («Windows Update error ' + $c.Key + '»).' }
        Write-Output "    $($E.Info) $($c.Key) (×$($c.Value)): $texto"
    }
    $problemas++
}
Write-Output "`n  $(if ($problemas) { $E.Aviso + ' Pistas encontradas arriba. Si no hay causa clara: DISM, luego SFC y «Restablecer Windows Update».' } else { $E.OK + ' No se ve ninguna causa de fallo ahora mismo.' })"
Write-Log "Por_Que_Falla_Windows_Update: $problemas pistas, códigos $($codigos.Keys -join ',')"
Exit-Kit 'Ok'
