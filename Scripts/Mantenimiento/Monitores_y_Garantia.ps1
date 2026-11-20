# =====================================================================
#  Monitores_y_Garantia.ps1 - Pantallas conectadas, número de serie y garantía (Nitrit0)
#  Lee de cada pantalla (EDID) la marca, el modelo, el número de serie, el año de fabricación, el tamaño
#  y el tipo de conexión; muestra el número de serie del equipo y abre la web de garantía del fabricante
#  con el número ya copiado al portapapeles. Solo lee: no cambia nada.
#  Parámetro: -SinPreguntas (no ofrece abrir la web de garantía)
# =====================================================================
[CmdletBinding()]
param([switch]$SinPreguntas)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E

$cs = Get-CimInstance Win32_ComputerSystem; $bios = Get-CimInstance Win32_BIOS
$serie = ([string]$bios.SerialNumber).Trim()
$sinSerie = (-not $serie) -or ($serie -match '^(To be filled|Default string|System Serial|0+|None|N/A|Not Specified)')
Write-Output "========================================================"
Write-Output "  $($E.Lupa) PANTALLAS, NÚMERO DE SERIE Y GARANTÍA"
Write-Output "========================================================"
Write-Output "  Equipo: $($cs.Manufacturer) $($cs.Model)"
Write-Output "  Número de serie: $(if ($sinSerie) { 'el fabricante no lo grabó en la placa (habitual en equipos montados por piezas)' } else { $serie })"
if ($bios.ReleaseDate) { Write-Output "  BIOS: $($bios.SMBIOSBIOSVersion) del $(([datetime]$bios.ReleaseDate).ToString('dd/MM/yyyy'))" } else { Write-Output "  BIOS: $($bios.SMBIOSBIOSVersion)" }

# Código de 3 letras del fabricante (registro PnP) -> marca
$marcas = @{ AAC = 'Acer'; ACI = 'Asus'; ACR = 'Acer'; AOC = 'AOC'; APP = 'Apple'; AUO = 'AU Optronics (panel)'; AUS = 'Asus'; BNQ = 'BenQ'; BOE = 'BOE (panel)'; CMN = 'Innolux (panel)'; CSO = 'CSOT (panel)'
    DEL = 'Dell'; EIZ = 'EIZO'; ENC = 'EIZO'; FUJ = 'Fujitsu'; GBT = 'Gigabyte'; GSM = 'LG'; HKC = 'HKC'; HPN = 'HP'; HWP = 'HP'; HSD = 'HannStar'; IVM = 'Iiyama'; IVO = 'InfoVision (panel)'; LEN = 'Lenovo'; LGD = 'LG Display (panel)'
    MEI = 'Panasonic'; MSI = 'MSI'; NEC = 'NEC'; PHL = 'Philips'; SAM = 'Samsung'; SDC = 'Samsung Display (panel)'; SEC = 'Samsung (panel)'; SHP = 'Sharp (panel)'; SNY = 'Sony'; TOS = 'Toshiba'; VSC = 'ViewSonic'; XMI = 'Xiaomi' }
$conexiones = @{ 0 = 'VGA'; 4 = 'DVI'; 5 = 'HDMI'; 6 = 'LVDS (interna)'; 9 = 'SDI'; 10 = 'DisplayPort'; 11 = 'eDP (interna)'; 12 = 'UDI'; 13 = 'UDI'; 14 = 'SDTV'; 15 = 'Miracast (inalámbrica)'; 16 = 'cable interno'; 17 = 'virtual (USB/DisplayLink)' }
$txt = { param($a) if ($a) { (-join ($a | Where-Object { $_ -gt 31 -and $_ -lt 127 } | ForEach-Object { [char]$_ })).Trim() } else { '' } }

Write-Output "`n  Pantallas conectadas ahora:"
$ids = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue)
$tam = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBasicDisplayParams -ErrorAction SilentlyContinue)
$con = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams -ErrorAction SilentlyContinue)
if (-not $ids.Count) { Write-Output "    $($E.Aviso) Windows no devuelve datos de ninguna pantalla (controlador gráfico básico, escritorio remoto o máquina virtual)." }
$n = 0
foreach ($m in $ids) {
    $n++
    $cod = & $txt $m.ManufacturerName; $marca = if ($marcas[$cod]) { $marcas[$cod] } else { $cod }
    $mod = & $txt $m.UserFriendlyName; $ser = & $txt $m.SerialNumberID
    $t = $tam | Where-Object { $_.InstanceName -eq $m.InstanceName } | Select-Object -First 1
    $c = $con | Where-Object { $_.InstanceName -eq $m.InstanceName } | Select-Object -First 1
    $pulg = if ($t -and $t.MaxHorizontalImageSize -gt 0) { '{0:N1}"' -f ([math]::Sqrt([math]::Pow($t.MaxHorizontalImageSize, 2) + [math]::Pow($t.MaxVerticalImageSize, 2)) / 2.54) } else { 'tamaño desconocido' }
    $tipo = if ($c) { $v = [int64]$c.VideoOutputTechnology; if ($v -ge 2147483648) { 'interna' } elseif ($conexiones.ContainsKey([int]$v)) { $conexiones[[int]$v] } else { "tipo $v" } } else { 'conexión desconocida' }
    $interna = $tipo -match 'interna'
    Write-Output "    $($E.OK) Pantalla ${n}: $marca $(if ($mod) { $mod } elseif ($interna) { '(panel del portátil)' } else { '(modelo no indicado)' })  ·  $pulg  ·  $tipo"
    Write-Output "        Número de serie: $(if ($ser -and $ser -ne '0') { $ser } elseif ($interna) { 'no lo indica (es el panel del propio equipo)' } else { 'no lo indica (míralo en la etiqueta trasera)' })  ·  Fabricada: $(if ($m.YearOfManufacture -gt 1990) { "semana $($m.WeekOfManufacture) de $($m.YearOfManufacture)" } else { 'sin dato' })"
    if ($m.YearOfManufacture -gt 1990 -and ((Get-Date).Year - $m.YearOfManufacture) -ge 8 -and -not $interna) { Write-Output "        $($E.Info) Tiene $((Get-Date).Year - $m.YearOfManufacture) años: si parpadea o pierde brillo, puede ser desgaste de la retroiluminación y no el equipo." }
}
Write-Log "Monitores y garantía: $($ids.Count) pantalla(s), serie del equipo $(if ($sinSerie) { 'no disponible' } else { 'leída' })"

# Garantía: se abre la página oficial y el número va en el portapapeles (no en la dirección web)
$fab = [string]$cs.Manufacturer
$web = if ($fab -match '^HP|Hewlett') { 'https://support.hp.com/es-es/check-warranty' } elseif ($fab -match 'LENOVO') { 'https://pcsupport.lenovo.com/warrantylookup' } elseif ($fab -match 'Dell') { 'https://www.dell.com/support/home/es-es' } else { $null }
Write-Output ""
if ($sinSerie) { Write-Output "  $($E.Info) Sin número de serie no se puede consultar la garantía del equipo completo: va por la factura de cada pieza." }
elseif (-not $web) { Write-Output "  $($E.Info) Garantía: entra en la página de soporte de $fab y busca «garantía» con el número de serie $serie." }
elseif ($SinPreguntas) { Write-Output "  $($E.Info) Garantía: $web  (número de serie $serie)" }
else {
    Add-Type -AssemblyName System.Windows.Forms
    if ([Windows.Forms.MessageBox]::Show("¿Abrir la página de garantía de $fab?`n`nEl número de serie ($serie) se copia al portapapeles: pégalo con Ctrl+V.", 'Garantía', 'YesNo', 'Question') -eq 'Yes') {
        try { Set-Clipboard -Value $serie } catch { }
        Start-Process $web; Write-Output "  $($E.OK) Página de garantía abierta. Número de serie copiado: pégalo con Ctrl+V."
    }
}
