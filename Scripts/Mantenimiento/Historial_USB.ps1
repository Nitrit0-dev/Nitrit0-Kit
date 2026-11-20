# =====================================================================
#  Historial_USB.ps1 - Qué unidades USB, móviles y cámaras se han conectado a este equipo (Nitrit0)
#  Solo lee: no cambia nada. Para cada unidad USB de almacenamiento que Windows recuerda dice cuándo se conectó por primera vez,
#  la última vez que se conectó y la última vez que se retiró, con su número de serie. Además lista los móviles y cámaras (dispositivos portátiles).
#  Útil para saber si alguien copió datos con un pendrive o para reconocer un dispositivo que no es tuyo.
#  Límite: Windows no guarda cada conexión, solo la primera, la última y la última retirada de cada dispositivo.
#  Parámetro: -Dias N (solo marca como «reciente» lo conectado en los últimos N días; por defecto 30)
#  Salida: 0 bien
# =====================================================================
[CmdletBinding()]
param([int]$Dias = 30)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
if ($Dias -lt 1 -or $Dias -gt 3650) { $Dias = 30 }
Write-Output "========================================================"
Write-Output "  $($E.Cohete) HISTORIAL DE USB CONECTADOS"
Write-Output "========================================================"
Write-Output "  $($E.Info) Solo lectura: no se cambia nada."

function Get-Fecha($id, [string]$clave) {
    try { $v = (Get-PnpDeviceProperty -InstanceId $id -KeyName $clave -ErrorAction Stop).Data; if ($v -is [datetime]) { return $v } } catch { }
    $null
}
function Format-Fecha($f) { if ($f) { $f.ToString('dd/MM/yyyy HH:mm') } else { '—' } }

$lista = New-Object Collections.Generic.List[object]
foreach ($d in @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'USBSTOR\*' })) {
    $serieCompleta = ($d.InstanceId -split '\\')[-1]
    $serie = ($serieCompleta -replace '&\d+$', '')
    $propia = -not ($serie -match '^.&')   # Windows inventa el número cuando la unidad no trae uno propio: empieza por «&» en el 2º carácter
    $lista.Add([pscustomobject]@{
        Nombre = $(if ($d.FriendlyName) { $d.FriendlyName } else { 'Unidad USB' }); Serie = $serie; SerieReal = $propia
        Primera = (Get-Fecha $d.InstanceId 'DEVPKEY_Device_FirstInstallDate'); Ultima = (Get-Fecha $d.InstanceId 'DEVPKEY_Device_LastArrivalDate'); Retirada = (Get-Fecha $d.InstanceId 'DEVPKEY_Device_LastRemovalDate')
        Conectada = ($d.Status -eq 'OK')
    })
}
$limite = (Get-Date).AddDays(-$Dias)
if (-not $lista.Count) { Write-Output "`n  $($E.OK) Windows no recuerda ninguna unidad USB de almacenamiento en este equipo (o el historial se ha borrado)." }
else {
    $ordenada = @($lista | Sort-Object { if ($_.Ultima) { $_.Ultima } else { [datetime]::MinValue } } -Descending)
    $recientes = @($ordenada | Where-Object { $_.Ultima -and $_.Ultima -gt $limite })
    Write-Output "`n  $($E.Lupa) Unidades de almacenamiento USB que Windows recuerda: $($lista.Count)  ·  conectadas en los últimos $Dias días: $($recientes.Count)  ·  conectadas ahora: $(@($lista | Where-Object Conectada).Count)"
    foreach ($u in $ordenada) {
        $marca = if ($u.Conectada) { $E.OK } elseif ($u.Ultima -and $u.Ultima -gt $limite) { $E.Aviso } else { $E.Info }
        Write-Output "`n  $marca $($u.Nombre)$(if ($u.Conectada) { '  (conectada ahora)' } elseif ($u.Ultima -and $u.Ultima -gt $limite) { '  (reciente)' })"
        Write-Output "       Serie: $($u.Serie)$(if (-not $u.SerieReal) { '  (la unidad no trae número propio: Windows le puso uno interno)' })"
        Write-Output "       Primera vez: $(Format-Fecha $u.Primera)   ·   Última conexión: $(Format-Fecha $u.Ultima)   ·   Última retirada: $(Format-Fecha $u.Retirada)"
    }
}

$moviles = @(Get-PnpDevice -Class WPD -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName } | Sort-Object FriendlyName -Unique)
if ($moviles.Count) {
    Write-Output "`n  $($E.Lupa) Móviles, cámaras y otros dispositivos portátiles ($($moviles.Count)):"
    foreach ($m in $moviles) {
        $ult = Get-Fecha $m.InstanceId 'DEVPKEY_Device_LastArrivalDate'
        Write-Output "       $(if ($m.Status -eq 'OK') { $E.OK } else { $E.Info }) $($m.FriendlyName)$(if ($ult) { "  ·  última conexión: $(Format-Fecha $ult)" })$(if ($m.Status -eq 'OK') { '  (conectado ahora)' })"
    }
}
Write-Output "`n  $($E.Info) Windows guarda solo la primera conexión, la última y la última retirada de cada unidad: no se sabe cuántas veces se conectó ni qué se copió."
Write-Output "  $($E.Info) Si ves una unidad que no reconoces, apunta su serie: sirve para comprobar si volvió a conectarse."
Write-Log "Historial_USB: $($lista.Count) unidades recordadas, $($moviles.Count) dispositivos portátiles"
exit 0
