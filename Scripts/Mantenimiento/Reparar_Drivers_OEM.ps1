# =====================================================================
#  Reparar_Drivers_OEM.ps1 - Drivers y BIOS oficiales del fabricante (Nitrit0)
#  Para equipos HP y Lenovo con fallos de pantalla externa, Wi-Fi/Ethernet que se corta o puertos USB que
#  se desconectan. Compara lo instalado con el catálogo oficial del fabricante para ESE modelo, descarga lo
#  que esté anticuado, comprueba la firma digital y lo instala en orden: chipset/USB, vídeo, red y, solo si
#  se marca, la BIOS. En ASUS, MSI, Gigabyte y Dell no hay catálogo público por modelo: se instala o abre la
#  herramienta oficial de la marca (DriverHub/MyASUS, MSI Center, página de Gigabyte, Dell Command | Update).
#  Antes de instalar crea un punto de restauración y pide confirmación con la lista de paquetes.
#  Parámetros: -SoloConsulta (compara y no instala nada)   -SinPreguntas (consulta de todo, sin ventanas)
# =====================================================================
[CmdletBinding()]
param([Alias('SoloAnalizar')][switch]$SoloConsulta, [switch]$SinPreguntas)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E

# ---------------------------------------------------------------------
#  Qué revisar
# ---------------------------------------------------------------------
$Opt = @{ USB = $true; Video = $true; Red = $true; BIOS = $false; AhorroUSB = $false; Consulta = [bool]$SoloConsulta }
if ($SinPreguntas) { $Opt.BIOS = $true; $Opt.Consulta = $true }
else {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $f = New-Object Windows.Forms.Form; $f.Text = 'Drivers y BIOS del fabricante'; $f.ClientSize = New-Object Drawing.Size(500, 330); $f.StartPosition = 'CenterScreen'
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false; $f.Font = New-Object Drawing.Font('Segoe UI', 9.5)
    $l = New-Object Windows.Forms.Label; $l.Text = 'Qué comprobar contra el catálogo oficial del fabricante:'; $l.AutoSize = $true; $l.Location = New-Object Drawing.Point(18, 14); $f.Controls.Add($l)
    $y = 44; $chk = @{}
    foreach ($o in @(
            @('USB', 'Chipset, puertos USB y Thunderbolt', $true),
            @('Video', 'Vídeo y gráficos (pantallas externas, parpadeos)', $true),
            @('Red', 'Red: Wi-Fi y Ethernet (cortes, lentitud)', $true),
            @('BIOS', 'BIOS (solo HP; con el cargador puesto; se aplica al reiniciar)', $false),
            @('AhorroUSB', 'Quitar el ahorro de energía de los USB (dispositivos que se desconectan)', $false),
            @('Consulta', 'Solo consultar: comparar versiones y no instalar nada', [bool]$SoloConsulta))) {
        $c = New-Object Windows.Forms.CheckBox; $c.Text = $o[1]; $c.Checked = $o[2]; $c.AutoSize = $true; $c.Location = New-Object Drawing.Point(26, $y); $f.Controls.Add($c); $chk[$o[0]] = $c
        $y += $(if ($o[0] -eq 'AhorroUSB') { 44 } else { 32 })
    }
    $ok = New-Object Windows.Forms.Button; $ok.Text = 'Continuar'; $ok.Size = New-Object Drawing.Size(110, 32); $ok.Location = New-Object Drawing.Point(258, 282); $ok.DialogResult = 'OK'
    $ca = New-Object Windows.Forms.Button; $ca.Text = 'Cancelar'; $ca.Size = New-Object Drawing.Size(100, 32); $ca.Location = New-Object Drawing.Point(378, 282); $ca.DialogResult = 'Cancel'
    $f.Controls.AddRange(@($ok, $ca)); $f.AcceptButton = $ok; $f.CancelButton = $ca
    if ($f.ShowDialog() -ne 'OK') { Write-Output "$($E.Info) Cancelado: no se ha cambiado nada."; exit 2 }
    foreach ($k in @($chk.Keys)) { $Opt[$k] = $chk[$k].Checked }
}

# ---------------------------------------------------------------------
#  Utilidades
# ---------------------------------------------------------------------
function Get-XmlWeb([string]$Url) {
    $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 25 -ErrorAction Stop
    $t = if ($r.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($r.Content) } else { [string]$r.Content }
    [xml]($t.TrimStart([char]0xFEFF))
}
function ConvertTo-Ver([string]$t) {
    if ([string]::IsNullOrWhiteSpace($t)) { return $null }
    $m = [regex]::Match($t, '\d+(\.\d+){1,3}'); if ($m.Success) { try { return [version]$m.Value } catch { } }
    $null
}
function Get-Marca([string]$n) { foreach ($m in 'Intel', 'Realtek', 'NVIDIA', 'MediaTek', 'Qualcomm', 'Broadcom') { if ($n -match $m) { return $m } }; if ($n -match 'AMD|Radeon') { return 'AMD' }; '' }
# Solo se ejecuta lo que venga firmado por el fabricante: una descarga cortada o manipulada no se instala
function Test-FirmaFabricante([string]$Ruta, [string]$Patron = 'HP Inc|Hewlett|Lenovo') {
    try { $s = Get-AuthenticodeSignature -LiteralPath $Ruta -ErrorAction Stop; ($s.Status -eq 'Valid') -and ($s.SignerCertificate.Subject -match $Patron) } catch { $false }
}
# Descompone una orden del XML de Lenovo en ejecutable + argumentos, sin cmd.exe. El .exe tiene que estar dentro de la carpeta del paquete
# (sin «..» ni rutas UNC) y llevar una firma Authenticode válida; .bat/.cmd/.msi y encadenados con && no se ejecutan.
function Resolve-OrdenLenovo([string]$Orden, [string]$Dir) {
    $o = ($Orden -replace '%PACKAGEPATH%', $Dir).Trim()
    if ($o -match '^"([^"]+)"\s*(.*)$') { $prog = $Matches[1]; $argumentos = $Matches[2] } elseif ($o -match '^(\S+)\s*(.*)$') { $prog = $Matches[1]; $argumentos = $Matches[2] } else { throw 'la ficha del paquete trae una orden vacía' }
    if ($prog -match '^\\\\|^//|(^|[\\/])\.\.([\\/]|$)|%') { throw "la orden usa una ruta no permitida ($prog)" }
    $base = [IO.Path]::GetFullPath($Dir).TrimEnd('\') + '\'
    $exe = [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($prog)) { $prog } else { Join-Path $Dir $prog }))
    if (-not $exe.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { throw "la orden sale de la carpeta del paquete ($prog)" }
    if ([IO.Path]::GetExtension($exe) -ne '.exe') { throw "la orden no es un .exe ($prog): instálalo con Lenovo Vantage o Lenovo System Update" }
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "la orden apunta a un archivo que no existe en el paquete ($prog)" }
    $s = Get-AuthenticodeSignature -LiteralPath $exe
    if ($s.Status -ne 'Valid') { throw "$([IO.Path]::GetFileName($exe)) no lleva una firma digital válida ($($s.Status)): no se ejecuta" }
    [pscustomobject]@{ Exe = $exe; Argumentos = $argumentos }
}
$Cola = New-Object Collections.Generic.List[object]
function Add-Cola([hashtable]$p) { if (-not ($Cola | Where-Object { $_.Id -eq $p.Id })) { $Cola.Add([pscustomobject]$p) } }
# Registro de lo que este kit ya instaló en el equipo, para no repetir paquetes que no dejan número de versión comparable
$dirMarca = Join-Path $env:ProgramData 'Nitrit0'; $fMarca = Join-Path $dirMarca 'DriversOEM.json'; $Hechos = @{}
try { if (Test-Path -LiteralPath $fMarca) { (Get-Content -LiteralPath $fMarca -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $Hechos[$_.Name] = [string]$_.Value } } } catch { }
function Save-Hecho([string]$Id, [string]$Ver) { $Hechos[$Id] = $Ver; try { New-Item -ItemType Directory -Force $dirMarca | Out-Null; ($Hechos | ConvertTo-Json) | Set-Content -LiteralPath $fMarca -Encoding UTF8 } catch { } }

$cs = Get-CimInstance Win32_ComputerSystem; $bios = Get-CimInstance Win32_BIOS; $os = Get-CimInstance Win32_OperatingSystem
$fab = ([string]$cs.Manufacturer).Trim(); $esW11 = [int]$os.BuildNumber -ge 22000
$esHP = $fab -match '^HP|Hewlett'; $esLenovo = $fab -match 'LENOVO'
$modelo = if ($esLenovo) { "$($cs.SystemFamily) ($($cs.Model))" } else { $cs.Model }
$swSetup = Join-Path $env:SystemDrive 'SWSetup'
$dirDesc = Join-Path $Global:NitKit.Cache 'Drivers'

Write-Output "========================================================"
Write-Output "  $($E.Lupa) DRIVERS Y BIOS OFICIALES DEL FABRICANTE"
Write-Output "========================================================"
Write-Output "  Equipo: $fab $modelo  ·  BIOS $($bios.SMBIOSBIOSVersion)  ·  $($os.Caption -replace '^Microsoft\s+', '')"
Write-Output "  Modo: $(if ($Opt.Consulta) { 'solo consulta (no se instala nada)' } else { 'comprobar, descargar e instalar en orden' })"

# ---------------------------------------------------------------------
Write-Output "`n  [1/4] Dispositivos y controladores instalados"
$conFallo = @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 -and -not ($_.ConfigManagerErrorCode -eq 22 -and $_.Name -match 'VPN|Miniport|Virtual|AnyConnect|Fortinet') })
if ($conFallo.Count) { foreach ($d in $conFallo) { Write-Output "    $($E.Error) Con fallo: $($d.Name) (código $($d.ConfigManagerErrorCode)$(if ($d.ConfigManagerErrorCode -eq 22) { ', desactivado a mano' } elseif ($d.ConfigManagerErrorCode -eq 28) { ', sin controlador' }))" } }
else { Write-Output "    $($E.OK) Ningún dispositivo con error en el Administrador de dispositivos." }

$firmados = @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue)
$fecha = { param($d) if ($d.DriverDate) { $d.DriverDate.ToString('dd/MM/yyyy') } else { 's/f' } }
if ($Opt.USB) {
    foreach ($u in ($firmados | Where-Object { $_.DeviceClass -eq 'USB' -and $_.DeviceName -match 'Host Controller|Controlador de host|eXtensible|Thunderbolt' })) { Write-Output "    $($E.Info) USB    $($u.DeviceName)  ·  $($u.DriverVersion) ($(& $fecha $u))" }
}
$clases = @(); if ($Opt.Video) { $clases += 'DISPLAY' }; if ($Opt.Red) { $clases += 'NET' }
$instalados = @($firmados | Where-Object { ($_.DeviceClass -in $clases) -and ($_.DeviceName -notmatch 'Virtual|WAN Miniport|Bluetooth|Hyper-V|Loopback|VPN|Fortinet|Cisco|Citrix|VMware|TAP-|Juniper|Zscaler|Miracast|Indirect|DisplayLink|Kernel Debug|USB Ethernet|Wi-Fi Direct|Remote Display|Basic Display|Básico de pantalla') } | Sort-Object DeviceClass)
foreach ($d in $instalados) { Write-Output "    $($E.Info) $(if ($d.DeviceClass -eq 'DISPLAY') { 'VÍDEO' } else { 'RED  ' })  $($d.DeviceName)  ·  $($d.DriverVersion) ($(& $fecha $d))  ·  $($d.DriverProviderName)" }
if ($instalados | Where-Object { $_.DeviceClass -eq 'DISPLAY' -and $_.DriverProviderName -match 'Microsoft' }) { Write-Output "    $($E.Aviso) La gráfica usa el controlador básico de Microsoft: falta el del fabricante (por eso puede ir a baja resolución o sin segunda pantalla)." }

# ---------------------------------------------------------------------
Write-Output "`n  [2/4] Comparación con el catálogo oficial"
if (-not ($esHP -or $esLenovo)) {
    # Marca real: en sobremesas montadas el fabricante del equipo es genérico («System manufacturer»), así que se mira también la placa y la BIOS
    $placa = Get-CimInstance Win32_BaseBoard
    $marcaTxt = "$fab $($placa.Manufacturer) $($bios.Manufacturer)"
    $marcaOtra = if ($marcaTxt -match 'ASUS') { 'ASUS' } elseif ($marcaTxt -match 'Micro-Star|\bMSI\b') { 'MSI' } elseif ($marcaTxt -match 'Gigabyte') { 'Gigabyte' } elseif ($marcaTxt -match 'Dell') { 'Dell' } else { '' }
    $esPortatil = [bool](@(Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue | ForEach-Object { $_.ChassisTypes }) | Where-Object { $_ -in 8, 9, 10, 14, 30, 31, 32 })
    $hecho = $false
    $pregunta = { param($t) (-not $Opt.Consulta) -and ([Windows.Forms.MessageBox]::Show($t, 'Drivers del fabricante', 'YesNo', 'Question', 'Button2') -eq 'Yes') }
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    $tipoEquipo = $(if ($esPortatil) { 'portátil' } else { 'sobremesa' })
    if ($marcaOtra) { Write-Output "    $($E.Info) Marca detectada: $marcaOtra ($tipoEquipo). No publica un catálogo por modelo que este kit pueda leer; se usa su herramienta oficial." }
    else { Write-Output "    $($E.Info) $fab no publica un catálogo por modelo que se pueda consultar desde aquí." }
    switch ($marcaOtra) {
        'ASUS' {
            if ($esPortatil) {
                Write-Output "      · Portátil ASUS: la herramienta oficial es MyASUS (Microsoft Store), con su pestaña de actualizaciones de drivers y BIOS."
                if (& $pregunta 'Se abrirá la Microsoft Store en MyASUS para instalarla o actualizarla. ¿Abrir?') { Start-Process 'ms-windows-store://search/?query=MyASUS'; $hecho = $true }
            } else {
                $inst = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'DriverHub' } | Select-Object -First 1
                $hub = Resolve-ExeKit 'Instaladores\Fabricantes\ASUS-DriverHub-Installer.exe'
                if ($inst) { Write-Output "      · ASUS DriverHub ya está instalado ($($inst.DisplayVersion))." }
                else { Write-Output "      · Placa ASUS: la herramienta oficial es ASUS DriverHub (compara chipset, audio, red y BIOS con el catálogo de ASUS). Deja un servicio residente en el equipo: desinstálalo después si no es tuyo." }
                if (-not $Opt.Consulta) {
                    if ($inst) { if (& $pregunta 'Se abrirá la página de ASUS DriverHub (driverhub.asus.com), donde se ven las actualizaciones pendientes. ¿Abrir?') { Start-Process 'https://driverhub.asus.com/en'; $hecho = $true } }
                    elseif ((Test-Path -LiteralPath $hub) -and (Test-FirmaFabricante $hub 'ASUSTeK')) {
                        if (& $pregunta 'Se instalará ASUS DriverHub (instalador firmado por ASUSTeK, con asistente en pantalla). Después se abre su página para pulsar «Install All». ¿Continuar?') {
                            $p = Start-Process -FilePath $hub -PassThru; [void]$p.WaitForExit(600000)
                            Start-Process 'https://driverhub.asus.com/en'; $hecho = $true
                        }
                    } else {
                        Write-Output "      $($E.Aviso) No hay instalador firmado en Apps\Instaladores\Fabricantes (o su firma no es de ASUSTeK). Se abre driverhub.asus.com, que ofrece la descarga."
                        if (& $pregunta 'Se abrirá driverhub.asus.com para descargar ASUS DriverHub. ¿Abrir?') { Start-Process 'https://driverhub.asus.com/en'; $hecho = $true }
                    }
                }
            }
        }
        'MSI' {
            Write-Output "      · MSI: la herramienta oficial es MSI Center (módulo «Live Update»)."
            if ($winget -and (& $pregunta 'Se instalará MSI Center con winget (MSI.MSICenter). Después abre «Live Update» y actualiza. ¿Instalar?')) {
                $r = Invoke-Proceso $winget.Source 'install --id MSI.MSICenter -e --silent --accept-package-agreements --accept-source-agreements' 1200 'MSI Center' 30
                Write-Output "      $(if ($r.Codigo -eq 0) { $E.OK } else { $E.Aviso }) MSI Center: winget terminó con código $($r.Codigo)$(if ($r.Codigo -eq 0) { '. Ábrelo y usa Live Update.' } else { '. Si ya estaba instalado, ábrelo desde el menú Inicio.' })"; $hecho = $true
            } elseif (-not $winget) { Write-Output "      $($E.Aviso) No hay winget en este equipo: descarga MSI Center de la página de soporte de MSI para este modelo." }
        }
        'Gigabyte' {
            Write-Output "      · Gigabyte: busca el modelo de la placa ($($placa.Product)) en su página de soporte; ofrece los drivers y, si la placa lo admite, GIGABYTE Control Center."
            if (& $pregunta "Se abrirá la página de soporte de Gigabyte. Busca la placa «$($placa.Product)». ¿Abrir?") { Start-Process 'https://www.gigabyte.com/Support'; $hecho = $true }
        }
        'Dell' {
            Write-Output "      · Dell: la herramienta oficial en línea de comandos es Dell Command | Update (no probada en este kit)."
            $dcu = @("$env:ProgramFiles\Dell\CommandUpdate\dcu-cli.exe", "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
            if (-not $dcu -and $winget -and (& $pregunta 'Dell Command | Update no está instalado. ¿Instalarlo con winget (Dell.CommandUpdate)?')) {
                [void](Invoke-Proceso $winget.Source 'install --id Dell.CommandUpdate -e --silent --accept-package-agreements --accept-source-agreements' 1200 'Dell Command Update' 30)
                $dcu = @("$env:ProgramFiles\Dell\CommandUpdate\dcu-cli.exe", "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
            }
            if ($dcu) {
                $r = Invoke-Proceso $dcu '/scan -silent' 900 'Dell Command Update (búsqueda)' 30
                Write-Output "      $($E.Info) Búsqueda de Dell terminada (código $($r.Codigo))."
                if (($r.Codigo -in 0, 500) -and -not $Opt.Consulta -and (& $pregunta 'Dell Command | Update instalará los drivers y la BIOS pendientes sin reiniciar el equipo. ¿Aplicar ahora?')) {
                    [void](Start-OperacionSegura 'Drivers del fabricante (Dell)')
                    $r = Invoke-Proceso $dcu '/applyUpdates -silent -reboot=disable' 3600 'Dell Command Update (instalación)' 30
                    Save-Informativo 'Actualizaciones de Dell aplicadas con Dell Command | Update' 'Para volver atrás: Revertir controlador en el Administrador de dispositivos o el punto de restauración.'
                    Write-Output "      $(if ($r.Codigo -in 0, 1, 5) { $E.OK } else { $E.Aviso }) Dell Command | Update terminó con código $($r.Codigo) (1 y 5 indican que hace falta reiniciar)."; $hecho = $true
                }
            } else { Write-Output "      $($E.Aviso) Instala Dell Command | Update desde dell.com/support para este modelo." }
        }
        default {
            Write-Output "      · «Actualizar Windows» de este kit instala también los controladores que el fabricante publica en Windows Update."
            Write-Output "      · O la herramienta del propio fabricante (Acer Care Center, Samsung Update, etc.)."
        }
    }
    if ($marcaOtra) { Write-Output "      · Los drivers por fabricante de CHIP (AMD/Intel chipset, NVIDIA/AMD gráfica, Realtek) valen en cualquier marca; para la gráfica usa «Reinstalar gráfica»." }
    if ($conFallo.Count) { Write-Output "      · Para los dispositivos con fallo, «Drivers con fallo» muestra su identificador de hardware para buscar el controlador exacto." }
    if ($hecho -and -not $conFallo.Count -and -not $Opt.AhorroUSB) { Write-Log "Drivers OEM: $fab $modelo ($marcaOtra), herramienta oficial lanzada"; exit 0 }
}
elseif (-not (Test-Internet)) { Write-Output "    $($E.Error) Sin conexión a Internet: no se puede consultar el catálogo de $fab. Conecta el equipo (cable o móvil por USB) y repite."; exit 1 }
elseif ($esHP) {
    $id = ([string](Get-CimInstance Win32_BaseBoard).Product).Trim().ToLower()
    $paquetes = @()
    try {
        $tmp = Join-Path $dirDesc "hp_$id"; Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force $tmp | Out-Null
        $cab = Join-Path $tmp "$id.cab"
        # El catálogo de HP va por versión de Windows: primero la de este equipo y después las anteriores
        $dv = ([string](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).DisplayVersion).ToLower()
        $vers = if ($esW11) { @($dv, '25h2', '24h2', '23h2', '22h2') } else { @($dv, '22h2', '21h2') }
        $urls = @($vers | Where-Object { $_ } | Select-Object -Unique | ForEach-Object { "https://hpia.hpcloud.hp.com/ref/$id/${id}_64_$(if ($esW11) { '11.0' } else { '10.0' }).$_.cab" })
        $urlOk = $null
        foreach ($u in $urls) { try { Invoke-WebRequest -Uri $u -OutFile $cab -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop; if ((Get-Item -LiteralPath $cab).Length -gt 1KB) { $urlOk = $u; break } } catch { } }
        if (-not $urlOk) { Write-Output "    $($E.Aviso) HP no tiene catálogo para la placa $($id.ToUpper()) con este Windows (modelo de consumo o demasiado antiguo). Usa «Actualizar Windows» o HP Support Assistant." }
        else {
            # El archivo de dentro se llama igual que el .cab: hay que extraerlo en otra carpeta o expand se niega («hacia sí mismo»)
            $ext = Join-Path $tmp 'x'; New-Item -ItemType Directory -Force $ext | Out-Null
            [void](Invoke-Proceso "$env:SystemRoot\System32\expand.exe" "`"$cab`" -F:* `"$ext`"" 60 'Catálogo HP' 60)
            $xf = Get-ChildItem -LiteralPath $ext -File | Sort-Object Length -Descending | Select-Object -First 1
            if (-not $xf) { throw 'no se pudo descomprimir el catálogo' }
            $b = [IO.File]::ReadAllBytes($xf.FullName)
            $txt = if ($b.Length -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE) { [Text.Encoding]::Unicode.GetString($b, 2, $b.Length - 2) } else { [Text.Encoding]::UTF8.GetString($b).TrimStart([char]0xFEFF) }
            $campo = { param($bloque, $n) [regex]::Match($bloque, "<$n>(.*?)</$n>").Groups[1].Value.Trim() }
            $paquetes = @(foreach ($m in [regex]::Matches($txt, '(?s)<UpdateInfo\b[^>]*>(.*?)</UpdateInfo>')) {
                    $u = & $campo $m.Value 'Url'
                    [pscustomobject]@{ Id = (& $campo $m.Value 'Id'); Nombre = (& $campo $m.Value 'Name'); Version = (& $campo $m.Value 'Version'); Fecha = (& $campo $m.Value 'DateReleased'); Url = $(if ($u -match '^http') { $u } else { "https://$u" }) }
                })
            Write-Output "    $($E.OK) Catálogo de HP para la placa $($id.ToUpper()): $($paquetes.Count) paquetes."
        }
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    } catch { Write-Output "    $($E.Error) No se pudo leer el catálogo de HP: $($_.Exception.Message)" }
    $porFecha = { try { [datetime]$_.Fecha } catch { [datetime]::MinValue } }

    if ($paquetes.Count -and $Opt.USB) {
        # El más reciente de cada tipo (chipset, Serial IO, Thunderbolt), no solo uno de los tres
        foreach ($tipo in 'Chipset', 'Serial IO', 'Thunderbolt') {
            $sp = $paquetes | Where-Object { $_.Nombre -match $tipo -and $_.Nombre -notmatch 'Dock|BIOS|Audio|Camera|Keyboard|Mouse|Firmware|Secure Connect' } | Sort-Object $porFecha -Descending | Select-Object -First 1
            if (-not $sp) { continue }
            if ($tipo -eq 'Thunderbolt' -and -not ($firmados | Where-Object { $_.DeviceName -match 'Thunderbolt' })) { continue }   # el modelo puede venderse sin Thunderbolt
            if ((Test-Path -LiteralPath (Join-Path $swSetup $sp.Id)) -or $Hechos[$sp.Id]) { Write-Output "    $($E.OK) CHIPSET/USB  $($sp.Nombre) $($sp.Version): ya instalado ($($sp.Id))." }
            else { Write-Output "    $($E.Aviso) CHIPSET/USB  $($sp.Nombre) $($sp.Version) ($($sp.Id)): pendiente."; Add-Cola @{ Orden = 1; Tipo = 'Chipset/USB'; Fab = 'HP'; Id = $sp.Id; Nombre = $sp.Nombre; Version = $sp.Version; Url = $sp.Url } }
        }
    }
    foreach ($d in $(if ($paquetes.Count) { $instalados } else { @() })) {
        $video = $d.DeviceClass -eq 'DISPLAY'; $marca = Get-Marca $d.DeviceName
        $filtro = if ($video) { 'Graphics|Video|Display' } elseif ($d.DeviceName -match 'Wi-?Fi|Wireless|WLAN|\bAX\d+|\bBE\d+|\bAC ?\d+') { 'WLAN|Wireless|Wi-Fi' } else { 'Ethernet|GbE|(?<!W)LAN\b|\bNIC\b' }
        $esCable = -not $video -and $filtro -notmatch 'WLAN'
        if (-not $marca) { continue }   # sin marca reconocida no se puede asegurar que el paquete sea el de este dispositivo
        $c = $paquetes | Where-Object { $_.Nombre -match $filtro -and $_.Nombre -match $marca -and $_.Nombre -notmatch 'BIOS|Firmware|Hotkey|Bluetooth|WWAN|Mobile Broadband|Dock|Audio' -and -not ($esCable -and $_.Nombre -match 'WLAN|Wireless|Wi-Fi') } | Sort-Object { $v = ConvertTo-Ver $_.Version; if ($v) { $v } else { [version]'0.0' } } -Descending | Select-Object -First 1
        if (-not $c) { continue }
        $vi = ConvertTo-Ver $d.DriverVersion; $vo = ConvertTo-Ver $c.Version
        $et = if ($video) { 'VÍDEO' } else { 'RED' }
        if ($vi -and $vo -and $vi -lt $vo) { Write-Output "    $($E.Aviso) $et  $($d.DeviceName): instalado $vi, HP publica $vo ($($c.Fecha), $($c.Id))."; Add-Cola @{ Orden = $(if ($video) { 2 } else { 3 }); Tipo = $(if ($video) { 'Vídeo' } else { 'Red' }); Fab = 'HP'; Id = $c.Id; Nombre = $c.Nombre; Version = [string]$vo; Url = $c.Url } }
        else { Write-Output "    $($E.OK) $et  $($d.DeviceName): al día ($vi; HP publica $vo)." }
    }
    if ($Opt.BIOS) {
        try {
            $x = Get-XmlWeb "https://ftp.hp.com/pub/pcbios/$($id.ToUpper())/$($id.ToUpper()).xml"
            $rel = $x.BIOS.Rel | Sort-Object { try { [datetime]$_.Date } catch { [datetime]::MinValue } } -Descending | Select-Object -First 1
            if ($rel) {
                $vi = ConvertTo-Ver ([string]$bios.SMBIOSBIOSVersion); $vu = ConvertTo-Ver ([string]$rel.Ver)
                if ($vi -and $vu -and $vi -lt $vu) {
                    $spb = $paquetes | Where-Object { $_.Nombre -match 'BIOS' -and $_.Nombre -notmatch 'Dock' } | Sort-Object $porFecha -Descending | Select-Object -First 1
                    if ($spb) { Write-Output "    $($E.Aviso) BIOS  instalada $vi, HP publica $vu ($($rel.Date), $($spb.Id))."; Add-Cola @{ Orden = 4; Tipo = 'BIOS'; Fab = 'HP'; Id = $spb.Id; Nombre = "BIOS HP $($rel.Ver)"; Version = [string]$vu; Url = $spb.Url } }
                    else { Write-Output "    $($E.Aviso) BIOS  instalada $vi, HP publica $vu, pero no está en el catálogo de descargas. Bájala a mano de support.hp.com con el número de serie $($bios.SerialNumber)." }
                } else { Write-Output "    $($E.OK) BIOS  al día ($vi; HP publica $vu)." }
            }
        } catch { Write-Output "    $($E.Aviso) No se pudo consultar la BIOS de HP: $($_.Exception.Message)" }
    }
}
else {
    # --- Lenovo: catálogo por tipo de máquina (los 4 primeros caracteres del modelo), el mismo que usa Lenovo System Update ---
    $mtm = ([string]$cs.Model); $mtm = $mtm.Substring(0, [Math]::Min(4, $mtm.Length)).ToUpper(); $so = if ($esW11) { 'Win11' } else { 'Win10' }
    try {
        $cat = Get-XmlWeb "https://download.lenovo.com/catalog/${mtm}_${so}.xml"
        $cats = @(); if ($Opt.USB) { $cats += 'USB Device|Motherboard Devices' }; if ($Opt.Video) { $cats += 'Display and Video Graphics' }; if ($Opt.Red) { $cats += 'Networking: Wireless LAN|Networking: LAN \(Ethernet\)' }; if ($Opt.BIOS) { $cats += 'BIOS' }
        $lista = @($cat.packages.package | Where-Object { $cats.Count -and $_.category -match ($cats -join '|') })
        Write-Output "    $($E.OK) Catálogo de Lenovo para el tipo $mtm ($so): $($lista.Count) paquetes en las categorías elegidas."
        $biosNueva = $null
        foreach ($p in $lista) {
            try {
                $pk = (Get-XmlWeb $p.location).Package
                $tit = [string]$pk.Title.Desc.'#text'; if (-not $tit) { $tit = [string]$pk.Title.Desc }
                $ver = [string]$pk.version; $fr = [datetime]$pk.ReleaseDate
                $base = $p.location.Substring(0, $p.location.LastIndexOf('/') + 1); $exe = [string]$pk.Files.Installer.File.Name
                if (-not $exe) { continue }
                if ($p.category -match 'BIOS') { if (-not $biosNueva -or $fr -gt $biosNueva.Fecha) { $biosNueva = @{ Fecha = $fr; Version = (($ver -split '/')[0]).Trim(); Titulo = $tit } }; continue }
                $item = @{ Fab = 'LENOVO'; Id = [IO.Path]::GetFileNameWithoutExtension($exe); Nombre = $tit; Version = $ver; Url = "$base$exe"; Exe = $exe
                    Extraer = [string]$pk.ExtractCommand; Instalar = [string]$pk.Install.Cmdline.'#text'; Inf = [string]$pk.Install.INFCmd.INFfile; Rc = [string]$pk.Install.rc; Reinicio = [string]$pk.Reboot.type }
                if ($p.category -match 'USB|Motherboard') {
                    if ($tit -notmatch 'USB|Thunderbolt|Chipset' -or $tit -match 'Dock|Audio|Camera') { continue }
                    if ($Hechos[$item.Id] -eq $ver) { Write-Output "    $($E.OK) CHIPSET/USB  $tit ${ver}: ya instalado por este kit." }
                    else { Write-Output "    $($E.Aviso) CHIPSET/USB  $tit $ver ($($fr.ToString('dd/MM/yyyy'))): pendiente."; $item.Orden = 1; $item.Tipo = 'Chipset/USB'; Add-Cola $item }
                    continue
                }
                $video = $p.category -match 'Display'; $marca = Get-Marca $tit; if (-not $marca) { continue }
                $loc = $instalados | Where-Object { $_.DeviceClass -eq $(if ($video) { 'DISPLAY' } else { 'NET' }) -and (Get-Marca $_.DeviceName) -eq $marca } | Select-Object -First 1
                if (-not $loc) { continue }
                $vi = ConvertTo-Ver $loc.DriverVersion; $vo = ConvertTo-Ver $ver; $et = if ($video) { 'VÍDEO' } else { 'RED' }
                if ($vi -and $vo -and $vi -lt $vo) { Write-Output "    $($E.Aviso) $et  $($loc.DeviceName): instalado $vi, Lenovo publica $vo ($($fr.ToString('dd/MM/yyyy')))."; $item.Orden = $(if ($video) { 2 } else { 3 }); $item.Tipo = $(if ($video) { 'Vídeo' } else { 'Red' }); Add-Cola $item }
                else { Write-Output "    $($E.OK) $et  $($loc.DeviceName): al día ($vi; Lenovo publica $vo)." }
            } catch { }
        }
        if ($Opt.BIOS -and $biosNueva) {
            $vi = ConvertTo-Ver "$($bios.SystemBiosMajorVersion).$($bios.SystemBiosMinorVersion)"; $vu = ConvertTo-Ver $biosNueva.Version
            if ($vi -and $vu -and $vi -lt $vu) { Write-Output "    $($E.Aviso) BIOS  instalada $vi, Lenovo publica $vu ($($biosNueva.Fecha.ToString('dd/MM/yyyy'))). Este kit no la instala en Lenovo: hazlo con Lenovo Vantage o Lenovo System Update, con el cargador puesto." }
            else { Write-Output "    $($E.OK) BIOS  al día ($vi; Lenovo publica $vu)." }
        }
    } catch { Write-Output "    $($E.Error) No se pudo leer el catálogo de Lenovo para el tipo ${mtm}: $($_.Exception.Message). En modelos de consumo (IdeaPad) usa Lenovo Vantage." }
}

$pend = @($Cola | Sort-Object Orden)
if ($Opt.Consulta) {
    Write-Output "`n  $($E.Info) Consulta terminada: $($pend.Count) paquete(s) por actualizar y $($conFallo.Count) dispositivo(s) con fallo. No se ha cambiado nada."
    Write-Log "Drivers OEM (consulta): $fab $modelo, pendientes=$($pend.Count), con fallo=$($conFallo.Count)"
    exit 0
}

# ---------------------------------------------------------------------
#  A partir de aquí se cambia el equipo
# ---------------------------------------------------------------------
$hayBios = [bool]($pend | Where-Object { $_.Orden -eq 4 })
if ($hayBios) {
    $bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($bat -and $bat.BatteryStatus -eq 1) { Write-Output "`n  $($E.Aviso) El equipo está con batería: la BIOS NO se actualiza sin el cargador puesto (si se apaga a medias, la placa queda inservible)."; $pend = @($pend | Where-Object { $_.Orden -ne 4 }); $hayBios = $false }
}
if ($pend.Count) {
    $txt = "Se van a descargar e instalar, en este orden:`n`n" + (($pend | ForEach-Object { "  · [$($_.Tipo)] $($_.Nombre) $($_.Version)" }) -join "`n") + "`n`nSe crea antes un punto de restauración. La pantalla puede parpadear y la red cortarse unos segundos."
    if ($hayBios) { $txt += "`n`nLA BIOS se aplica al reiniciar: NO apagues ni desenchufes el equipo durante ese arranque. BitLocker se suspende para ese reinicio." }
    if ([Windows.Forms.MessageBox]::Show("$txt`n`n¿Continuar?", 'Drivers del fabricante', 'YesNo', 'Warning', 'Button2') -ne 'Yes') { Write-Output "`n  $($E.Info) Cancelado: no se ha instalado nada."; exit 2 }
}
if (-not $pend.Count -and -not $Opt.AhorroUSB -and -not $conFallo.Count) { Write-Output "`n  $($E.OK) Todo está al día y sin fallos: no hay nada que instalar."; Write-Log "Drivers OEM: $fab $modelo, todo al día"; exit 0 }

[void](Start-OperacionSegura 'Drivers del fabricante' -SinPuntoRestauracion:(-not $pend.Count))

Write-Output "`n  [3/4] Descarga y comprobación de firma"
$listos = New-Object Collections.Generic.List[object]
foreach ($p in $pend) {
    $dest = Join-Path $dirDesc $(if ($p.Exe) { $p.Exe } else { "$($p.Id).exe" })
    Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
    Write-Output "    $($E.Disco) $($p.Nombre) ($($p.Id))…"
    if (-not (Get-Descarga $p.Url $dest 1200 3 "Descarga $($p.Id)")) { Write-Output "      $($E.Error) No se pudo descargar: se omite."; continue }
    if (-not (Test-FirmaFabricante $dest)) { Write-Output "      $($E.Error) El archivo no lleva una firma digital válida de $($p.Fab): NO se instala."; Write-Log "Drivers OEM: firma no válida en $($p.Id) ($($p.Url))" 'ERROR'; Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue; continue }
    Write-Output ("      $($E.OK) Descargado ({0:N0} MB) y firma de $($p.Fab) verificada." -f ((Get-Item -LiteralPath $dest).Length / 1MB))
    $p | Add-Member -NotePropertyName Archivo -NotePropertyValue $dest -Force; $listos.Add($p)
}
if (-not $pend.Count) { Write-Output "    $($E.OK) No hay paquetes que descargar." }

Write-Output "`n  [4/4] Reparación e instalación"
$fallos = 0; $reinicio = $false
foreach ($d in ($conFallo | Where-Object { $_.ConfigManagerErrorCode -notin 22, 28 })) {
    try { Disable-PnpDevice -InstanceId $d.DeviceID -Confirm:$false -ErrorAction Stop; Start-Sleep -Seconds 2; Enable-PnpDevice -InstanceId $d.DeviceID -Confirm:$false -ErrorAction Stop; Write-Output "    $($E.Refresh) Reiniciado el dispositivo con fallo: $($d.Name)." }
    catch { Write-Output "    $($E.Aviso) No se pudo reiniciar $($d.Name): $($_.Exception.Message)" }
}
if ($Opt.AhorroUSB) {
    $sub = '2a737441-1930-4402-8d77-b2bebba308a3'; $aj = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
    & powercfg.exe /SETACVALUEINDEX SCHEME_CURRENT $sub $aj 0 | Out-Null; & powercfg.exe /SETDCVALUEINDEX SCHEME_CURRENT $sub $aj 0 | Out-Null; & powercfg.exe /SETACTIVE SCHEME_CURRENT | Out-Null
    Save-Informativo 'Suspensión selectiva de USB desactivada en el plan de energía actual' 'Para deshacerlo: Opciones de energía > Cambiar la configuración avanzada > Configuración de USB > Suspensión selectiva > Habilitado.'
    $n = 0
    foreach ($h in @(Get-CimInstance -Namespace root\wmi -ClassName MSPower_DeviceEnable -ErrorAction SilentlyContinue | Where-Object { $_.InstanceName -match '^USB' -and $_.Enable })) { try { Set-CimInstance -InputObject $h -Property @{ Enable = $false } -ErrorAction Stop; $n++ } catch { } }
    if ($n) { Save-Informativo "Ahorro de energía desactivado en $n concentradores USB" 'Para deshacerlo: Administrador de dispositivos > cada «Concentrador raíz USB» > Administración de energía > marcar «Permitir que el equipo apague este dispositivo».' }
    Write-Output "    $($E.OK) USB: suspensión selectiva desactivada$(if ($n) { " y ahorro de energía quitado en $n concentradores" }). Gasta algo más de batería."
}
foreach ($p in ($listos | Sort-Object Orden)) {
    Write-Output "    $($E.Cohete) [$($p.Tipo)] $($p.Nombre) $($p.Version)…"
    try {
        if ($p.Fab -eq 'HP') {
            $dir = Join-Path $swSetup $p.Id
            $r = Invoke-Proceso $p.Archivo "/s /e /f `"$dir`"" 600 "Extracción de $($p.Id)" 30
            if (-not (Test-Path -LiteralPath $dir)) { throw "no se pudo extraer (código $($r.Codigo))" }
            if ($p.Orden -eq 4) {
                $upd = Get-ChildItem -LiteralPath $dir -Recurse -Include 'HpFirmwareUpdRec64.exe', 'HPBIOSUPDREC64.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
                if (-not $upd) { throw "el paquete no trae el actualizador de BIOS; queda extraído en $dir" }
                try { $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop; if ($bl.ProtectionStatus -eq 'On') { Suspend-BitLocker -MountPoint $env:SystemDrive -RebootCount 1 -ErrorAction Stop | Out-Null; Write-Output "      $($E.Info) BitLocker suspendido para el próximo reinicio (se reactiva solo)." } } catch { }
                $r = Invoke-Proceso $upd.FullName '-s -r -b' 900 'Preparación de la BIOS' 30
                if ($r.Codigo -in 0, 3010, 282, 273) { $reinicio = $true; Save-Informativo "BIOS HP actualizada de $($bios.SMBIOSBIOSVersion) a $($p.Version)" 'No se deshace desde Windows. HP guarda la versión anterior y la recupera sola si el arranque falla.'; Write-Output "      $($E.OK) BIOS preparada: se instala al REINICIAR. No apagues ni desenchufes el equipo durante ese arranque." }
                else { throw "el actualizador de BIOS terminó con código $($r.Codigo) (si la BIOS tiene contraseña de administrador, hay que quitarla o actualizar desde la propia BIOS)" }
            } else {
                $r = Invoke-Proceso "$env:SystemRoot\System32\pnputil.exe" "/add-driver `"$dir\*.inf`" /subdirs /install" 900 "Instalación de $($p.Id)" 30
                if ($r.Codigo -in 0, 3010, 259) { if ($r.Codigo -eq 3010) { $reinicio = $true }; Save-Hecho $p.Id ([string]$p.Version); Save-Informativo "Controlador instalado: $($p.Nombre) $($p.Version)" 'Para volver al anterior: Administrador de dispositivos > el dispositivo > Controlador > Revertir al controlador anterior, o el punto de restauración.'; Write-Output "      $($E.OK) Instalado$(if ($r.Codigo -eq 259) { ' (Windows ya tenía esta versión o una más nueva)' })." }
                else { throw "pnputil terminó con código $($r.Codigo)" }
            }
        } else {
            # Lenovo: cada paquete trae en su ficha la orden de extracción y la de instalación (la misma que usa Lenovo System Update)
            $dir = Join-Path $dirDesc $p.Id; New-Item -ItemType Directory -Force $dir | Out-Null
            $local = Join-Path $dir $p.Exe; Move-Item -LiteralPath $p.Archivo -Destination $local -Force
            # Las órdenes vienen del XML del fabricante (sin firma): no pasan por cmd.exe; solo se lanza un .exe de dentro del paquete con firma válida
            Push-Location -LiteralPath $dir   # la orden original hacía «cd /d <paquete>»: Start-Process hereda esta carpeta
            try {
                if ($p.Extraer) { $o = Resolve-OrdenLenovo $p.Extraer $dir; $r = Invoke-Proceso $o.Exe $o.Argumentos 600 "Extracción de $($p.Id)" 30; if ($r.Codigo -ne 0) { throw "no se pudo extraer (código $($r.Codigo))" } }
                if ($p.Instalar) { $o = Resolve-OrdenLenovo $p.Instalar $dir; $r = Invoke-Proceso $o.Exe $o.Argumentos 1200 "Instalación de $($p.Id)" 30 }
            } finally { Pop-Location }
            if (-not $p.Instalar) {
                if ($p.Inf) { $r = Invoke-Proceso "$env:SystemRoot\System32\pnputil.exe" "/add-driver `"$(Join-Path $dir $p.Inf)`" /install" 900 "Instalación de $($p.Id)" 30 }
                else { throw 'la ficha del paquete no indica cómo instalarlo' }
            }
            $buenos = @(0, 3010) + @(($p.Rc -split ',') | Where-Object { $_ -match '^\s*\d+\s*$' } | ForEach-Object { [int]$_ })
            if ($r.Codigo -in $buenos) { if ($r.Codigo -eq 3010 -or $p.Reinicio -in '1', '3', '4', '5') { $reinicio = $true }; Save-Hecho $p.Id ([string]$p.Version); Save-Informativo "Paquete Lenovo instalado: $($p.Nombre) $($p.Version)" 'Para volver atrás: Revertir controlador en el Administrador de dispositivos o el punto de restauración.'; Write-Output "      $($E.OK) Instalado." }
            else { throw "el instalador terminó con código $($r.Codigo)" }
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    } catch { $fallos++; Write-Output "      $($E.Error) No se instaló: $($_.Exception.Message)"; Write-Log "Drivers OEM: fallo en $($p.Id) - $($_.Exception.Message)" 'ERROR' }
    finally { if ($p.Archivo) { Remove-Item -LiteralPath $p.Archivo -Force -ErrorAction SilentlyContinue } }
}
[void](Invoke-Proceso "$env:SystemRoot\System32\pnputil.exe" '/scan-devices' 120 'Búsqueda de hardware' 60)
$quedan = @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -notin 0, 22 })
Write-Output "`n  $(if ($fallos -or $quedan.Count) { $E.Aviso } else { $E.OK }) Terminado: $($listos.Count - $fallos) paquete(s) instalado(s), $fallos con error, $($quedan.Count) dispositivo(s) siguen con fallo."
foreach ($d in $quedan) { Write-Output "      · $($d.Name) (código $($d.ConfigManagerErrorCode))" }
if ($quedan.Count) { Write-Output "    $($E.Info) Para los que siguen con fallo: «Drivers con fallo» da su identificador de hardware, y «Actualizar Windows» suele traer el controlador que falta." }
if ($reinicio) { Write-Output "    $($E.Refresh) REINICIA el equipo para terminar$(if ($hayBios) { ' (la BIOS se instala en ese arranque: no lo interrumpas)' })." }
Write-Log "Drivers OEM: $fab $modelo, instalados=$($listos.Count - $fallos), errores=$fallos, con fallo=$($quedan.Count), reinicio=$reinicio"
if ($fallos) { exit 1 }
