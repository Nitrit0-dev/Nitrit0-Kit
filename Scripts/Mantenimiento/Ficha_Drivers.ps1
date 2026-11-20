# =====================================================================
#  Ficha_Drivers.ps1 - Qué driver tiene cada dispositivo y cuáles hay que mirar (Nitrit0)
#  Lista los dispositivos del equipo (placa, gráfica, red, audio, USB, almacenamiento) con su Hardware ID, el chip que lleva,
#  el driver instalado (proveedor, versión y fecha) y los clasifica: con problema, con driver genérico de Windows, antiguos y correctos.
#  Para cada uno deja un enlace al Catálogo de Microsoft Update con su Hardware ID, para buscar el driver concreto.
#  SOLO LEE: no instala, no descarga y no cambia nada. El enlace solo se abre si lo pulsas en el informe.
#  Informe: Datos\Informes\Drivers_<equipo>_<fecha>.html (en el pack público, en la carpeta temporal del kit).
#  Parámetro: -NoAbrir (no abre el informe al terminar)
# =====================================================================
[CmdletBinding()]
param([switch]$NoAbrir)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
function Esc($t) { [Net.WebUtility]::HtmlEncode([string]$t) }

# Fabricantes de chips más habituales (orientativo: el número de fabricante viene del propio dispositivo; los que no están se muestran como «VEN xxxx»)
$fabricantes = @{
    '10DE' = 'NVIDIA'; '1002' = 'AMD (ATI)'; '1022' = 'AMD'; '8086' = 'Intel'; '10EC' = 'Realtek'; '14E4' = 'Broadcom'; '168C' = 'Qualcomm Atheros'
    '1969' = 'Qualcomm Atheros'; '17CB' = 'Qualcomm'; '14C3' = 'MediaTek'; '1B21' = 'ASMedia'; '1912' = 'Renesas'; '1B4B' = 'Marvell'
    '144D' = 'Samsung'; '15B7' = 'SanDisk'; '1987' = 'Phison'; '1C5C' = 'SK hynix'; '1344' = 'Micron'; '1E0F' = 'KIOXIA'; '1414' = 'Microsoft'
    '0BDA' = 'Realtek'; '0CF3' = 'Qualcomm Atheros'; '0E8D' = 'MediaTek'; '8087' = 'Intel'; '04CA' = 'Lite-On'; '0489' = 'Foxconn'; '13D3' = 'IMC Networks'
}
$clasesRevisar = 'DISPLAY', 'NET', 'BLUETOOTH', 'MEDIA', 'SYSTEM', 'HDC', 'SCSIADAPTER', 'USB', 'CAMERA', 'IMAGE'

Write-Output "  $($E.Lupa) Leyendo dispositivos y drivers (puede tardar un momento)…"
$ent = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.PNPDeviceID })
$drv = @{}; foreach ($d in @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue | Where-Object { $_.DeviceID })) { $drv[$d.DeviceID] = $d }
if (-not $ent.Count) { Write-Output "$($E.Error) No se pudo leer la lista de dispositivos (¿falta administrador?)."; Write-Log 'Ficha_Drivers: sin dispositivos' 'ERROR'; exit 1 }

$limiteAntiguo = (Get-Date).AddYears(-4)
$filas = New-Object Collections.Generic.List[object]
foreach ($e in $ent) {
    $id = [string]$e.PNPDeviceID
    if ($id -notmatch '^(PCI|USB|HDAUDIO|ACPI|SCSI|NVME|BTH|BTHENUM)\\' -and $e.ConfigManagerErrorCode -eq 0) { continue }   # lo demás son dispositivos de software
    if ($id -match '^USB\\ROOT_HUB' -and $e.ConfigManagerErrorCode -eq 0) { continue }
    $hw = @($e.HardwareID | Where-Object { $_ })
    $ven = ''; if ($hw.Count -and ($hw[0] -match '(?:VEN|VID)_([0-9A-Fa-f]{4})')) { $ven = $Matches[1].ToUpper() }
    $chip = if ($ven) { if ($fabricantes.ContainsKey($ven)) { $fabricantes[$ven] } else { "VEN $ven" } } else { '' }
    # Búsqueda en el Catálogo de Microsoft: el ID general (fabricante + modelo) da más resultados que el que lleva subsistema y revisión
    $consulta = ''
    foreach ($h in $hw) { if ($h -match '^(PCI\\VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4}|ACPI\\VEN_[0-9A-Z]{3,4}&DEV_[0-9A-F]{4}|(?:USB|HID)\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4}|HDAUDIO\\FUNC_\d+&VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4})') { $consulta = $Matches[1]; break } }   # ACPI y HID: chipset, touchpads I2C y botones de portátil
    $s = $drv[$id]
    $clase = ([string]$e.PNPClass).ToUpper(); $prov = if ($s) { [string]$s.DriverProviderName } else { '' }
    $fecha = $null; if ($s -and $s.DriverDate) { try { $fecha = [datetime]$s.DriverDate } catch { } }   # un .inf con la fecha mal formada no debe parar la ficha
    $estado = 'Correcto'; $nota = ''
    if ($e.ConfigManagerErrorCode -eq 22) { $estado = 'Desactivado'; $nota = 'Está desactivado (no es un fallo).' }
    elseif ($e.ConfigManagerErrorCode -ne 0) { $estado = 'Problema'; $nota = "Código $($e.ConfigManagerErrorCode)$(if ($e.ConfigManagerErrorCode -eq 28) { ': no tiene driver instalado' } elseif ($e.ConfigManagerErrorCode -eq 43) { ': Windows lo detuvo por un fallo' } else { '' })." }
    elseif ($prov -match 'Microsoft' -and $ven -ne '1414' -and ($clase -in 'DISPLAY', 'NET' -or ($clase -eq 'BLUETOOTH' -and [string]$e.Name -match 'Generic|gen[eé]ric') -or ($clase -eq 'MEDIA' -and $id -match '^(PCI|HDAUDIO)\\')) -and $id -match '^(PCI|USB|HDAUDIO)\\') {   # el audio y las cámaras USB usan el driver de Windows con normalidad: no se avisa
        $estado = 'Genérico'
        $nota = if ($clase -eq 'MEDIA') { 'Usa el driver de Windows: suele bastar, pero el del fabricante añade funciones.' } else { 'Usa el driver básico de Windows: conviene el del fabricante del chip o del equipo.' }
    }
    elseif ($fecha -and $prov -and $prov -notmatch 'Microsoft' -and $fecha -lt $limiteAntiguo -and $clase -in $clasesRevisar) { $estado = 'Antiguo'; $nota = 'Driver de hace más de 4 años (no siempre es malo: si funciona, mejor no tocarlo).' }
    $url = if ($consulta -and $estado -ne 'Correcto' -and $estado -ne 'Desactivado') { 'https://www.catalog.update.microsoft.com/Search.aspx?q=' + [Uri]::EscapeDataString($consulta) } else { '' }
    $filas.Add([pscustomobject]@{
            Estado = $estado; Dispositivo = [string]$e.Name; Clase = $clase; Chip = $chip; Proveedor = $prov
            Version = $(if ($s) { [string]$s.DriverVersion } else { '' }); Fecha = $(if ($fecha) { $fecha.ToString('yyyy-MM-dd') } else { '' })
            HardwareID = $(if ($hw.Count) { $hw[0] } else { '' }); Consulta = $consulta; Url = $url; Nota = $nota
        })
}
$orden = @{ Problema = 0; Genérico = 1; Antiguo = 2; Desactivado = 3; Correcto = 4 }
$lista = @($filas | Sort-Object { $orden[$_.Estado] }, Clase, Dispositivo)
$n = @{}; foreach ($k in $orden.Keys) { $n[$k] = @($lista | Where-Object Estado -eq $k).Count }

$fantasmas = 0; try { $fantasmas = @(Get-PnpDevice -ErrorAction Stop | Where-Object { -not $_.Present -and (([string]$_.InstanceId -split '\\')[0] -in 'USB', 'USBSTOR', 'HID', 'BTH', 'BTHENUM', 'SCSI', 'STORAGE', 'MONITOR', 'DISPLAY') -and [string]$_.Class -notin 'Volume', 'VolumeSnapshot' }).Count } catch { }
# Tamaño del almacén de drivers (FileRepository): si pasa de 8 GB, «Limpiar almacén de drivers» recupera espacio
$almacenGB = $null; try { $almacenGB = [math]::Round(((Get-ChildItem -LiteralPath (Join-Path $env:SystemRoot 'System32\DriverStore\FileRepository') -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) / 1GB, 2) } catch { }
# ---------------------------------------------------------------- Consola
Write-Output "$($E.OK) $($lista.Count) dispositivos revisados: $($n.Problema) con problema, $($n['Genérico']) con driver genérico, $($n.Antiguo) con driver antiguo, $($n.Correcto) correctos."
foreach ($x in @($lista | Where-Object { $_.Estado -in 'Problema', 'Genérico' } | Select-Object -First 15)) {
    $icono = if ($x.Estado -eq 'Problema') { $E.Error } else { $E.Aviso }
    Write-Output "  $icono $($x.Estado): $($x.Dispositivo) ($($x.Chip)) $($x.Nota)"
}
if ($null -ne $almacenGB) { if ($almacenGB -gt 8) { Write-Output "  $($E.Aviso) El almacén de drivers ocupa $almacenGB GB (más de 8 GB): conviene pasar «Limpiar almacén de drivers»." } else { Write-Output "  $($E.Info) El almacén de drivers ocupa $almacenGB GB." } }
if ($fantasmas -gt 0) { Write-Output "  $($E.Info) Además hay $fantasmas dispositivos fantasma (ya no conectados) registrados: la herramienta «Dispositivos fantasma» los limpia." }
if ($n.Problema -eq 0 -and $n['Genérico'] -eq 0) { Write-Output "  $($E.OK) No hay dispositivos sin driver ni con driver genérico. Los antiguos son solo para valorar." }

# ---------------------------------------------------------------- Informe HTML
$cs = Get-CimInstance Win32_ComputerSystem; $bios = Get-CimInstance Win32_BIOS; $os = Get-CimInstance Win32_OperatingSystem
$cabecera = '<table><tr><th>Equipo</th><th>BIOS</th><th>Windows</th></tr><tr><td>' + (Esc "$($cs.Manufacturer) $($cs.Model)") + '</td><td>' + (Esc "$($bios.SMBIOSBIOSVersion) ($(('{0:yyyy-MM-dd}' -f $bios.ReleaseDate)))") + '</td><td>' + (Esc "$($os.Caption) $($os.Version)") + '</td></tr></table>'
$tr = New-Object Text.StringBuilder
foreach ($x in $lista) {
    $enlace = if ($x.Url) { "<a href=`"$(Esc $x.Url)`" target=_blank rel=noopener>Catálogo de Microsoft</a>" } else { '' }
    $driver = if ($x.Proveedor -or $x.Version) { Esc "$($x.Proveedor) · $($x.Version) · $($x.Fecha)" } else { '<span class=m>sin driver</span>' }
    [void]$tr.Append("<tr class=`"e-$(Esc $x.Estado)`"><td><b>$(Esc $x.Estado)</b></td><td>$(Esc $x.Dispositivo)<div class=m>$(Esc $x.Nota)</div></td><td>$(Esc $x.Clase)</td><td>$(Esc $x.Chip)</td><td>$driver</td><td class=id>$(Esc $x.HardwareID)</td><td>$enlace</td></tr>")
}
$css = 'body{font:14px Segoe UI,sans-serif;margin:0;background:#f3f5f9;color:#1b2230}header{background:#0d1016;color:#fff;padding:22px 32px}header h1{margin:0;font-size:22px}header p{margin:4px 0 0;color:#9aa3b8}main{padding:8px 32px 40px;max-width:1300px}h2{margin:26px 0 8px;font-size:17px}table{border-collapse:collapse;width:100%;background:#fff;border:1px solid #dfe4ee}th,td{padding:7px 10px;text-align:left;border-bottom:1px solid #edf0f6;vertical-align:top}th{background:#eef1f8;font-size:12px;text-transform:uppercase;letter-spacing:.04em}.m{color:#5f6b85;font-size:12px}.id{font:12px Consolas,monospace;word-break:break-all}.e-Problema td:first-child{color:#b00020}.e-Genérico td:first-child{color:#b25e00}.e-Antiguo td:first-child{color:#7a6400}.e-Correcto td:first-child{color:#1b7f3b}.e-Desactivado td:first-child{color:#5f6b85}.res span{display:inline-block;margin:0 14px 8px 0;padding:6px 12px;background:#fff;border:1px solid #dfe4ee;border-radius:8px}a{color:#0b5cd5}@media print{header{background:#fff;color:#000}}'
$resumen = "<p class=res><span><b>$($n.Problema)</b> con problema</span><span><b>$($n['Genérico'])</b> con driver genérico</span><span><b>$($n.Antiguo)</b> antiguos</span><span><b>$($n.Desactivado)</b> desactivados</span><span><b>$($n.Correcto)</b> correctos</span><span><b>$fantasmas</b> dispositivos fantasma</span>$(if ($null -ne $almacenGB) { "<span><b>$almacenGB GB</b> en el almacén de drivers$(if ($almacenGB -gt 8) { ' (conviene limpiarlo)' })</span>" })</p>"
$guia = '<p class=m>Cómo usarlo: busca primero los «Problema» y los «Genérico» de gráficas y red. El enlace abre el Catálogo de Microsoft Update con el Hardware ID del dispositivo; descarga solo drivers de la lista con firma de Microsoft o del fabricante. En equipos HP y Lenovo, la herramienta «Drivers del fabricante» del kit hace esto mismo con el catálogo oficial del modelo. Un driver antiguo que funciona no hace falta cambiarlo. Este informe no ha instalado ni cambiado nada.</p>'
$html = "<!doctype html><html lang=es><head><meta charset=utf-8><title>Drivers $(Esc $env:COMPUTERNAME)</title><style>$css</style></head><body><header><h1>Ficha de drivers de $(Esc $env:COMPUTERNAME)</h1><p>Generado el $(Get-Date -Format 'dd/MM/yyyy HH:mm') con Nitrit0 Kit</p></header><main><h2>Equipo</h2>$cabecera<h2>Resumen</h2>$resumen$guia<h2>Dispositivos</h2><table><tr><th>Estado</th><th>Dispositivo</th><th>Clase</th><th>Chip de</th><th>Driver instalado</th><th>Hardware ID</th><th>Buscar</th></tr>$($tr.ToString())</table></main></body></html>"
$dir = Get-CarpetaSalida 'Informes'; $f = Join-Path $dir ("Drivers_{0}_{1}.html" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmm'))
[IO.File]::WriteAllText($f, $html, (New-Object Text.UTF8Encoding($true)))
Write-Log "Ficha de drivers: $($lista.Count) dispositivos, $($n.Problema) con problema, $($n['Genérico']) genéricos -> $f"
Write-Output "  $($E.OK) Informe guardado en: $f"
if (-not $NoAbrir -and -not $env:NIT_SIN_ABRIR) { if ($env:NIT_APP) { Open-Informe $f } else { Start-Process explorer.exe -ArgumentList "`"$f`"" } }
