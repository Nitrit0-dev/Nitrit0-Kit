# =====================================================================
#  Inventario_Equipo.ps1 - Informe HTML del equipo para entregar al cliente (Nitrit0)
#  Hardware, Windows, discos, red, programas instalados, controladores con problemas y antivirus.
#  Se guarda en Datos\Informes\Inventario_<equipo>_<fecha>.html y se abre en el navegador.
# =====================================================================
[CmdletBinding()]
param([switch]$NoAbrir)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
Write-Output "  $($E.Lupa) Recopilando datos del equipo…"
function Esc($t) { [Net.WebUtility]::HtmlEncode([string]$t) }
function Tabla($objs) { $objs = @($objs); if (-not $objs) { return '<p class="m">Sin datos.</p>' }; $p = $objs[0].PSObject.Properties.Name; $s = '<table><tr>' + (($p | ForEach-Object { "<th>$(Esc $_)</th>" }) -join '') + '</tr>'; foreach ($o in $objs) { $s += '<tr>' + (($p | ForEach-Object { "<td>$(Esc $o.$_)</td>" }) -join '') + '</tr>' }; $s + '</table>' }
function Intenta($b) { try { & $b } catch { @() } }

$cs = Get-CimInstance Win32_ComputerSystem; $os = Get-CimInstance Win32_OperatingSystem; $bios = Get-CimInstance Win32_BIOS; $bb = Get-CimInstance Win32_BaseBoard
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$sec = @()
$sec += '<h2>Equipo</h2>' + (Tabla ([pscustomobject]@{ Nombre = $env:COMPUTERNAME; Fabricante = $cs.Manufacturer; Modelo = $cs.Model; 'N.º de serie' = $bios.SerialNumber; BIOS = "$($bios.SMBIOSBIOSVersion) ($(('{0:yyyy-MM-dd}' -f $bios.ReleaseDate)))"; Placa = "$($bb.Manufacturer) $($bb.Product)" }))
$sec += '<h2>Windows</h2>' + (Tabla ([pscustomobject]@{ Edición = $os.Caption; Versión = "$($os.Version) (compilación $($os.BuildNumber))"; Instalado = ('{0:yyyy-MM-dd}' -f $os.InstallDate); 'Último arranque' = ('{0:yyyy-MM-dd HH:mm}' -f $os.LastBootUpTime); Usuario = $env:USERNAME }))
$sec += '<h2>Procesador y memoria</h2>' + (Tabla ([pscustomobject]@{ CPU = ("$($cpu.Name)").Trim(); Núcleos = $cpu.NumberOfCores; Hilos = $cpu.NumberOfLogicalProcessors; 'RAM total (GB)' = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1) }))
$sec += Tabla (Intenta { Get-CimInstance Win32_PhysicalMemory | Select-Object @{n = 'Ranura'; e = { $_.BankLabel } }, @{n = 'GB'; e = { $_.Capacity / 1GB } }, @{n = 'MHz'; e = { $_.Speed } }, Manufacturer, PartNumber })
$sec += '<h2>Gráficos</h2>' + (Tabla (Intenta { Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, @{n = 'VRAM (GB)'; e = { [math]::Round($_.AdapterRAM / 1GB, 1) } } }))
$sec += '<h2>Discos</h2>' + (Tabla (Intenta { Get-PhysicalDisk | Select-Object FriendlyName, MediaType, BusType, @{n = 'GB'; e = { [math]::Round($_.Size / 1GB) } }, HealthStatus }))
$sec += Tabla (Intenta { Get-Volume | Where-Object DriveLetter | Select-Object @{n = 'Unidad'; e = { $_.DriveLetter } }, FileSystemLabel, FileSystem, @{n = 'Libre (GB)'; e = { [math]::Round($_.SizeRemaining / 1GB, 1) } }, @{n = 'Total (GB)'; e = { [math]::Round($_.Size / 1GB, 1) } } })
$sec += '<h2>Red</h2>' + (Tabla (Intenta { Get-NetAdapter -Physical | Where-Object Status -eq 'Up' | Select-Object Name, InterfaceDescription, LinkSpeed, MacAddress }))
$sec += '<h2>Antivirus</h2>' + (Tabla (Intenta { Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct | Select-Object @{n = 'Producto'; e = { $_.displayName } } }))
$sec += '<h2>Dispositivos con problemas</h2>' + (Tabla (Intenta { Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 } | Select-Object Name, @{n = 'Código'; e = { $_.ConfigManagerErrorCode } } }))
Write-Output "  $($E.Lupa) Leyendo programas instalados…"
$claves = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
$progs = Get-ItemProperty $claves -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -and -not $_.SystemComponent } | Sort-Object DisplayName -Unique | Select-Object @{n = 'Programa'; e = { $_.DisplayName } }, @{n = 'Versión'; e = { $_.DisplayVersion } }, @{n = 'Editor'; e = { $_.Publisher } }
$sec += "<h2>Programas instalados ($(@($progs).Count))</h2>" + (Tabla $progs)

$dir = Get-CarpetaSalida 'Informes'; $f = Join-Path $dir ("Inventario_{0}_{1}.html" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmm'))
$css = 'body{font:14px Segoe UI,sans-serif;margin:0;background:#f3f5f9;color:#1b2230}header{background:#0d1016;color:#fff;padding:22px 32px}header h1{margin:0;font-size:22px}header p{margin:4px 0 0;color:#9aa3b8}main{padding:8px 32px 40px;max-width:1100px}h2{margin:28px 0 8px;color:#087f91;font-size:16px}table{border-collapse:collapse;width:100%;background:#fff;border-radius:8px;overflow:hidden;margin-bottom:8px}th,td{text-align:left;padding:7px 12px;border-bottom:1px solid #e1e6ef}th{background:#e8eef6;font-weight:600}.m{color:#4f5a70}@media(prefers-color-scheme:dark){body{background:#12151c;color:#f0f3fa}table{background:#1e2330}th{background:#272d3f}td,th{border-color:#2e3548}h2{color:#2bc4d8}}'
$html = "<!doctype html><html lang=es><head><meta charset=utf-8><title>Inventario $(Esc $env:COMPUTERNAME)</title><style>$css</style></head><body><header><h1>Inventario del equipo $(Esc $env:COMPUTERNAME)</h1><p>Generado el $(Get-Date -Format 'dd/MM/yyyy HH:mm') · Nitrit0</p></header><main>$($sec -join "`n")</main></body></html>"
[IO.File]::WriteAllText($f, $html, (New-Object Text.UTF8Encoding($true)))
Write-Log "Inventario generado: $f"
Write-Output "  $($E.OK) Informe guardado en: $f"
if (-not $NoAbrir -and -not $env:NIT_SIN_ABRIR) { if ($env:NIT_APP) { Open-Informe $f } else { Start-Process explorer.exe -ArgumentList "`"$f`"" } }
