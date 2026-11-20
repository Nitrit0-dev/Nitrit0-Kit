# =====================================================================
#  Instalar_Driver_Catalogo.ps1 - Busca el driver de UN dispositivo en el Catálogo de Microsoft Update y lo instala (Nitrit0)
#  Para el dispositivo con problema o con driver genérico: busca por su Hardware ID, enseña lo que hay para tu Windows (fecha, versión y
#  tamaño), descarga el .cab, comprueba que viene de servidores de Microsoft y que cada catálogo (.cat) lleva firma válida de Microsoft
#  y solo entonces, con tu confirmación y tras un punto de restauración, lo instala con pnputil.
#  Qué NO hace: no instala nada sin preguntar, no toca otros dispositivos y no usa programas de terceros.
#  Parámetros: -HardwareId "PCI\VEN_xxxx&DEV_xxxx" (si no, eliges el dispositivo en una ventana)
#              -SoloBuscar (lista lo que hay y no descarga)   -SoloDescargar (descarga y verifica la firma, sin instalar)
#              -SinPreguntas (equivale a -SoloBuscar; esta herramienta nunca instala sin que lo confirmes tú)
#              -Faltantes (busca de una vez el driver de TODOS los dispositivos que no tienen: los lista, los marcas, y se descargan, verifican e instalan)
# =====================================================================
[CmdletBinding()]
param([string]$HardwareId = '', [Alias('SoloBuscar')][switch]$SoloAnalizar, [switch]$SoloDescargar, [switch]$SinPreguntas, [switch]$Faltantes)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
if ($SinPreguntas) { $SoloAnalizar = $true }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
$esAdmin = Test-EsAdmin
if (-not $esAdmin -and -not $SoloAnalizar) { Write-Output "$($E.Aviso) Hace falta administrador para instalar drivers. Ábrelo desde el kit o usa -SoloBuscar."; exit 1 }
if (-not (Test-Internet)) { Write-Output "$($E.Error) No hay conexión a Internet: sin ella no se puede consultar el Catálogo de Microsoft."; Write-Log 'Instalar_Driver_Catalogo: sin Internet' 'AVISO'; exit 1 }

function Format-Tam([int64]$b) { if ($b -ge 1GB) { '{0:N1} GB' -f ($b / 1GB) } elseif ($b -ge 1MB) { '{0:N0} MB' -f ($b / 1MB) } else { '{0:N0} KB' -f ($b / 1KB) } }
function Get-IdGeneral([string]$h) { if ($h -match '^(PCI\\VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4}|ACPI\\VEN_[0-9A-Z]{3,4}&DEV_[0-9A-F]{4}|(?:USB|HID)\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4}|HDAUDIO\\FUNC_\d+&VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4})') { $Matches[1] } else { '' } }

# ---------------------------------------------------------------- 1) Elegir el dispositivo
function Show-Dispositivos {
    $ent = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.PNPDeviceID -match '^(PCI|USB|HDAUDIO|ACPI)\\' -and $_.HardwareID })
    $drv = @{}; foreach ($d in @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue | Where-Object DeviceID)) { $drv[$d.DeviceID] = $d }
    $filas = foreach ($e in $ent) {
        $id = Get-IdGeneral ([string]($e.HardwareID | Where-Object { Get-IdGeneral ([string]$_) } | Select-Object -First 1)); if (-not $id) { continue }
        $prov = if ($drv[$e.PNPDeviceID]) { [string]$drv[$e.PNPDeviceID].DriverProviderName } else { '' }; $clase = ([string]$e.PNPClass).ToUpper()
        $estado = if ($e.ConfigManagerErrorCode -ne 0 -and $e.ConfigManagerErrorCode -ne 22) { 'Problema' } elseif ($prov -match 'Microsoft' -and $clase -in 'DISPLAY', 'NET') { 'Genérico' } else { 'Correcto' }
        [pscustomobject]@{ Estado = $estado; Nombre = [string]$e.Name; Clase = $clase; Id = $id; Driver = $(if ($drv[$e.PNPDeviceID]) { "$prov $($drv[$e.PNPDeviceID].DriverVersion)" } else { 'sin driver' }) }
    }
    $f = New-Object Windows.Forms.Form; $f.Text = 'Elige el dispositivo'; $f.Size = New-Object Drawing.Size(1000, 640); $f.StartPosition = 'CenterScreen'; $f.TopMost = $true; $f.Font = New-Object Drawing.Font('Segoe UI', 9.5)
    $t = New-Object Windows.Forms.Label; $t.Text = '¿Para qué dispositivo buscas driver?'; $t.Font = New-Object Drawing.Font('Segoe UI Semibold', 14); $t.AutoSize = $true; $t.Location = New-Object Drawing.Point(20, 14)
    $ck = New-Object Windows.Forms.CheckBox; $ck.Text = 'Mostrar también los que están bien'; $ck.AutoSize = $true; $ck.Location = New-Object Drawing.Point(20, 50)
    $lv = New-Object Windows.Forms.ListView; $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.MultiSelect = $false; $lv.HideSelection = $false; $lv.Location = New-Object Drawing.Point(20, 80); $lv.Size = New-Object Drawing.Size(944, 440); $lv.Anchor = 'Top,Bottom,Left,Right'
    foreach ($c in @(@('Estado', 80), @('Dispositivo', 330), @('Tipo', 90), @('Driver actual', 230), @('Hardware ID', 200))) { [void]$lv.Columns.Add($c[0], $c[1]) }
    $rellenar = { $lv.Items.Clear(); foreach ($x in ($filas | Where-Object { $ck.Checked -or $_.Estado -ne 'Correcto' } | Sort-Object { @{ Problema = 0; Genérico = 1; Correcto = 2 }[$_.Estado] }, Nombre)) { $i = New-Object Windows.Forms.ListViewItem($x.Estado); foreach ($v in @($x.Nombre, $x.Clase, $x.Driver, $x.Id)) { [void]$i.SubItems.Add([string]$v) }; $i.Tag = $x; [void]$lv.Items.Add($i) } }
    & $rellenar; $ck.Add_CheckedChanged($rellenar)
    $ok = New-Object Windows.Forms.Button; $ok.Text = 'Buscar driver'; $ok.Size = New-Object Drawing.Size(160, 36); $ok.Location = New-Object Drawing.Point(804, 545); $ok.Anchor = 'Bottom,Right'; $ok.DialogResult = 'OK'
    $no = New-Object Windows.Forms.Button; $no.Text = 'Cancelar'; $no.Size = New-Object Drawing.Size(110, 36); $no.Location = New-Object Drawing.Point(684, 545); $no.Anchor = 'Bottom,Right'; $no.DialogResult = 'Cancel'
    $f.Controls.AddRange(@($t, $ck, $lv, $ok, $no)); $f.AcceptButton = $ok; $f.CancelButton = $no
    if ($f.ShowDialog() -ne 'OK' -or -not $lv.SelectedItems.Count) { return $null }
    $lv.SelectedItems[0].Tag
}

# ---------------------------------------------------------------- 2) Buscar en el Catálogo
# El Catálogo no etiqueta los drivers de Windows 11 solo como «Windows 11»: muchos dicen «Windows - Client, version 21H2 and later» o «Windows 10, Vibranium and later».
# Se aceptan esas etiquetas en Windows 11 (build 22000 o más); en Windows 10 solo las de Windows 10. Los que son solo de Server se descartan.
function Test-ProductoCompatible([string]$productos, [int]$build) {
    if ($productos -match '(?i)\bServer\b' -and $productos -notmatch '(?i)Windows 1[01]|Windows - Client') { return $false }
    if ($build -ge 22000) { return [bool]($productos -match '(?i)Windows 11|Windows - Client|Windows 10.*(Vibranium|and later)') }
    [bool]($productos -match '(?i)Windows 10')
}
function Search-Catalogo([string]$id) {
    $r = Invoke-WebRequest -Uri ('https://www.catalog.update.microsoft.com/Search.aspx?q=' + [Uri]::EscapeDataString($id)) -UseBasicParsing -UserAgent $UA -TimeoutSec 40
    $build = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber
    $res = foreach ($m in [regex]::Matches($r.Content, '(?s)<tr id="([0-9a-f\-]{36})_R\d+"[^>]*>(.*?)</tr>')) {
        $c = @([regex]::Matches($m.Groups[2].Value, '(?s)<td[^>]*>(.*?)</td>') | ForEach-Object { [Net.WebUtility]::HtmlDecode(($_.Groups[1].Value -replace '<[^>]+>', ' ' -replace '\s+', ' ').Trim()) })
        if ($c.Count -lt 7) { continue }
        $f = $null; try { $f = [datetime]::ParseExact($c[4], 'M/d/yyyy', [Globalization.CultureInfo]::InvariantCulture) } catch { }
        $tam = [int64]0; if ($c[6] -match '(\d+)\s*$') { $tam = [int64]$Matches[1] }   # la última cifra es el tamaño exacto en bytes
        [pscustomobject]@{ Id = $m.Groups[1].Value; Titulo = $c[1]; Productos = $c[2]; Clase = $c[3]; Fecha = $f; Version = $c[5]; Tam = $tam; DeMiWindows = (Test-ProductoCompatible $c[2] $build) -and ($c[3] -match 'Driver') }
    }
    @($res | Where-Object DeMiWindows | Sort-Object Fecha, Version -Descending | Group-Object Titulo, Version, Tam | ForEach-Object { $_.Group[0] })
}

function Get-UrlDescarga([string]$updateId) {
    $cuerpo = 'updateIDs=' + [Uri]::EscapeDataString("[{`"size`":0,`"languages`":`"`",`"uidInfo`":`"$updateId`",`"updateID`":`"$updateId`"}]")
    $d = Invoke-WebRequest -Uri 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx' -Method Post -Body $cuerpo -ContentType 'application/x-www-form-urlencoded' -UseBasicParsing -UserAgent $UA -TimeoutSec 40
    @([regex]::Matches($d.Content, "downloadInformation\[\d+\]\.files\[\d+\]\.url\s*=\s*'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
}

# ---------------------------------------------------------------- Modo -Faltantes: todos los dispositivos sin driver de una vez
if ($Faltantes) {
    Write-Output "  $($E.Lupa) Buscando dispositivos sin driver (código 28 o sin configurar)…"
    $prob = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.ConfigManagerErrorCode -in 28, 1 })
    if (-not $prob.Count) { Write-Output "  $($E.OK) Todos los dispositivos tienen driver instalado: no falta ninguno."; Write-Log 'Instalar_Driver_Catalogo: -Faltantes sin dispositivos'; exit 0 }
    $porId = [ordered]@{}
    foreach ($d in $prob) {
        $gid = Get-IdGeneral ([string]($d.HardwareID | Where-Object { Get-IdGeneral ([string]$_) } | Select-Object -First 1))
        if (-not $gid) { continue }
        if (-not $porId.Contains($gid)) { $porId[$gid] = New-Object Collections.Generic.List[string] }
        $porId[$gid].Add($(if ($d.Name) { [string]$d.Name } else { 'Dispositivo desconocido' }))
    }
    Write-Output "  $($E.Info) $($prob.Count) dispositivo(s) sin driver; $($porId.Count) Hardware ID distinto(s) que el Catálogo de Microsoft entiende."
    $hay = New-Object Collections.Generic.List[object]; $sinDriver = New-Object Collections.Generic.List[string]; $n = 0
    foreach ($gid in @($porId.Keys)) {
        $n++; $nom = ($porId[$gid] | Select-Object -Unique) -join ' / '
        try { $r = @(Search-Catalogo $gid) } catch { Write-Output "    $($E.Aviso) [$n/$($porId.Count)] $nom ($gid): no se pudo consultar ($($_.Exception.Message))"; $sinDriver.Add("$nom ($gid)"); continue }
        if ($r.Count) {
            $g = $r[0]; Write-Output ("    $($E.OK) [{0}/{1}] {2}: {3} v{4}" -f $n, $porId.Count, $nom, $g.Titulo, $g.Version)
            $hay.Add([pscustomobject]@{ Id = $gid; Nombres = $nom; Elegido = $g; Texto = "$nom"; Detalle = ("{0} · v{1} · {2} · {3}" -f $g.Titulo, $g.Version, $(if ($g.Fecha) { $g.Fecha.ToString('dd/MM/yyyy') } else { '?' }), (Format-Tam $g.Tam)); Marcado = $true })
        } else { Write-Output "    $($E.Info) [$n/$($porId.Count)] $nom ($gid): el Catálogo no tiene driver para tu Windows."; $sinDriver.Add("$nom ($gid)") }
    }
    if ($sinDriver.Count) { Write-Output "`n  $($E.Info) Sin driver en el Catálogo: $($sinDriver.Count). Para esos, mira «Drivers del fabricante» o la web del fabricante (a veces son controladores del propio equipo, p. ej. de Lenovo o ASUS)." }
    if (-not $hay.Count) { Write-Output "`n  $($E.Aviso) El Catálogo no tiene drivers para ninguno de estos dispositivos."; Write-Log "Instalar_Driver_Catalogo: -Faltantes sin resultados ($($porId.Count) IDs)"; exit 0 }
    if ($SoloAnalizar) { Write-Output "`n  $($E.Info) Solo búsqueda: no se ha descargado ni instalado nada ($($hay.Count) driver(s) disponibles)."; Write-Log "Instalar_Driver_Catalogo: -Faltantes búsqueda, $($hay.Count) disponibles"; exit 0 }
    $sel = Show-Marcables 'Drivers que faltan' "Estos drivers están en el Catálogo de Microsoft Update para tu Windows, con firma de Microsoft. Marca los que quieres instalar; se crea un punto de restauración antes y cada uno se verifica antes de instalarse." @($hay) 'Instalar lo marcado'
    if ($null -eq $sel -or -not $sel.Count) { Write-Output "  $($E.Info) Cancelado: no se ha cambiado nada."; exit 2 }
    $base = Join-Path (Get-BaseTrabajo) 'Drivers\Catalogo'
    $paraInstalar = New-Object Collections.Generic.List[object]; $fallos = 0; $k = 0
    foreach ($s in $sel) {
        $k++; $g = $s.Elegido
        Write-Output "`n  $($E.Reloj) [$k/$($sel.Count)] $($s.Nombres): descargando $($g.Titulo) ($(Format-Tam $g.Tam))…"
        try {
            $urls = @(Get-UrlDescarga $g.Id | Where-Object { $_ -match '^https://[A-Za-z0-9\.\-]+\.(windowsupdate\.com|delivery\.mp\.microsoft\.com|download\.microsoft\.com)/.+\.cab$' })
            if (-not $urls.Count) { throw 'el Catálogo no devolvió un archivo de un servidor de Microsoft' }
            $dirD = Join-Path $base ($s.Id -replace '[^A-Za-z0-9_&\-]', '_'); New-Item -ItemType Directory -Force $dirD | Out-Null
            $libre = (Get-PSDrive -Name (Split-Path $dirD -Qualifier).TrimEnd(':') -ErrorAction SilentlyContinue).Free
            if ($libre -and $libre -lt ($g.Tam * 3)) { throw "no hay sitio (hacen falta unos $(Format-Tam ($g.Tam * 3)) libres)" }
            $cab = Join-Path $dirD ([IO.Path]::GetFileName($urls[0]))
            if (-not (Get-Descarga $urls[0] $cab 3600 2 'Descarga del driver')) { throw 'la descarga falló' }
            $ext = Join-Path $dirD 'extraido'; Remove-Item -LiteralPath $ext -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force $ext | Out-Null
            $x = Invoke-Proceso (Join-Path $env:SystemRoot 'System32\expand.exe') ('-F:* "{0}" "{1}"' -f $cab, $ext) 1800 'Descomprimir' 30
            $infs = @(Get-ChildItem -LiteralPath $ext -Recurse -Filter *.inf -File -ErrorAction SilentlyContinue); $cats = @(Get-ChildItem -LiteralPath $ext -Recurse -Filter *.cat -File -ErrorAction SilentlyContinue)
            if ($x.Codigo -ne 0 -or -not $infs.Count) { throw 'el archivo descargado no contiene un driver válido' }
            $malos = @($cats | Where-Object { $sg = Get-AuthenticodeSignature -LiteralPath $_.FullName; $sg.Status -ne 'Valid' -or $sg.SignerCertificate.Subject -notmatch 'O=Microsoft' })
            if (-not $cats.Count -or $malos.Count) { throw "la firma no es válida ($($malos.Count) de $($cats.Count) catálogos sin firma de Microsoft)" }
            Write-Output "    $($E.OK) Verificado: $($infs.Count) .inf y $($cats.Count) catálogo(s) con firma de Microsoft."
            $paraInstalar.Add([pscustomobject]@{ S = $s; Ext = $ext })
        } catch { $fallos++; Write-Output "    $($E.Error) $($s.Nombres): $($_.Exception.Message). No se instala."; Write-Log "Instalar_Driver_Catalogo: -Faltantes fallo en $($s.Id): $($_.Exception.Message)" 'ERROR' }
    }
    if (-not $paraInstalar.Count) { Write-Output "`n  $($E.Error) Ningún driver superó la descarga y la verificación. No se ha cambiado nada."; exit 1 }
    [void](New-PuntoRestauracionSeguro 'Nitrit0 - antes de instalar los drivers que faltan')
    $ok = 0; $reinicio = $false; $k = 0
    foreach ($p in $paraInstalar) {
        $k++; Write-Output "`n  $($E.Reloj) [$k/$($paraInstalar.Count)] Instalando $($p.S.Elegido.Titulo)…"
        $i = Invoke-Proceso (Join-Path $env:SystemRoot 'System32\pnputil.exe') ('/add-driver "{0}\*.inf" /subdirs /install' -f $p.Ext) 1800 'Instalar driver' 30 -MostrarSalida
        if ($i.Codigo -eq 0 -or $i.Codigo -eq 3010) { $ok++; if ($i.Codigo -eq 3010) { $reinicio = $true }; Write-Output "    $($E.OK) Instalado."; Write-Log "Instalar_Driver_Catalogo: -Faltantes instalado $($p.S.Elegido.Titulo) para $($p.S.Id) (código $($i.Codigo))" }
        else { $fallos++; Write-Output "    $($E.Error) pnputil no pudo instalarlo (código $($i.Codigo))."; Write-Log "Instalar_Driver_Catalogo: -Faltantes fallo pnputil $($i.Codigo) para $($p.S.Id)" 'ERROR' }
    }
    Start-Sleep -Seconds 3
    $quedan = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.ConfigManagerErrorCode -in 28, 1 }).Count
    Write-Output "`n  $($E.Disco) Resultado: $ok instalado(s), $fallos con problema. Dispositivos que siguen sin driver: $quedan (antes $($prob.Count))."
    if ($reinicio) { Write-Output "  $($E.Aviso) Reinicia el equipo para terminar la instalación." }
    if ($quedan) { Write-Output "  $($E.Info) Windows puede tardar un momento en reconocer los dispositivos; si siguen igual tras reiniciar, vuelve a abrir la «Ficha de drivers»." }
    if ($ok -eq 0) { exit 1 }; exit 0
}

# ---------------------------------------------------------------- Flujo
$id = Get-IdGeneral $HardwareId.ToUpper()
if ($HardwareId -and -not $id) { Write-Output "$($E.Error) «$HardwareId» no parece un Hardware ID (por ejemplo PCI\VEN_10DE&DEV_1B80)."; exit 1 }
$nombre = $id
if (-not $id) {
    if ($SoloAnalizar) { Write-Output "$($E.Aviso) Indica el Hardware ID con -HardwareId (o abre la herramienta sin -SoloBuscar para elegir el dispositivo)."; exit 2 }
    $sel = Show-Dispositivos; if (-not $sel) { Write-Output "$($E.Info) Cancelado: no se ha cambiado nada."; exit 2 }
    $id = $sel.Id; $nombre = "$($sel.Nombre) ($id)"
}
Write-Output "  $($E.Lupa) Buscando en el Catálogo de Microsoft Update: $id"
try { $res = @(Search-Catalogo $id) } catch { Write-Output "$($E.Error) No se pudo consultar el Catálogo: $($_.Exception.Message)"; Write-Log "Instalar_Driver_Catalogo: consulta fallida $($_.Exception.Message)" 'ERROR'; exit 1 }
if (-not $res.Count) { Write-Output "$($E.Aviso) El Catálogo no tiene un driver de ese dispositivo para tu Windows. Prueba con «Drivers del fabricante» o con la web del fabricante."; Write-Log "Instalar_Driver_Catalogo: sin resultados para $id"; exit 0 }
Write-Output "  $($E.OK) $($res.Count) opciones para tu Windows (de la más reciente a la más antigua):"
foreach ($x in ($res | Select-Object -First 8)) { Write-Output ("    · {0} · v{1} · {2} · {3}" -f $x.Titulo, $x.Version, $(if ($x.Fecha) { $x.Fecha.ToString('yyyy-MM-dd') } else { '?' }), (Format-Tam $x.Tam)) }
if ($SoloAnalizar) { Write-Output "`n  $($E.Info) Solo búsqueda: no se ha descargado ni instalado nada."; Write-Log "Instalar_Driver_Catalogo: búsqueda $id ($($res.Count) opciones)"; exit 0 }

$elegido = $res[0]
if (-not $SoloDescargar -and -not (Confirm-Accion ("Dispositivo: $nombre`n`nDriver más reciente para tu Windows:`n$($elegido.Titulo)`nVersión $($elegido.Version) · $(if ($elegido.Fecha) { $elegido.Fecha.ToString('dd/MM/yyyy') } else { '?' }) ·$(Format-Tam $elegido.Tam)`n`nSe descargará de Microsoft, se comprobará su firma y se instalará tras crear un punto de restauración. ¿Continúas?"))) { Write-Output "  $($E.Info) Cancelado: no se ha cambiado nada."; exit 2 }

$urls = @(Get-UrlDescarga $elegido.Id | Where-Object { $_ -match '^https://[A-Za-z0-9\.\-]+\.(windowsupdate\.com|delivery\.mp\.microsoft\.com|download\.microsoft\.com)/.+\.cab$' })
if (-not $urls.Count) { Write-Output "$($E.Error) El Catálogo no devolvió un archivo de descarga de un servidor de Microsoft. No se descarga nada."; Write-Log "Instalar_Driver_Catalogo: sin URL válida para $($elegido.Id)" 'ERROR'; exit 1 }
$dirDrv = Join-Path (Get-BaseTrabajo) ('Drivers\Catalogo\' + ($id -replace '[^A-Za-z0-9_&\-]', '_'))
$libre = (Get-PSDrive -Name (Split-Path $dirDrv -Qualifier).TrimEnd(':') -ErrorAction SilentlyContinue).Free
if ($libre -and $libre -lt ($elegido.Tam * 3)) { Write-Output "$($E.Error) No hay sitio: hacen falta unos $(Format-Tam ($elegido.Tam * 3)) libres (descarga y descompresión) y hay $(Format-Tam $libre)."; exit 1 }
New-Item -ItemType Directory -Force $dirDrv | Out-Null
$cab = Join-Path $dirDrv ([IO.Path]::GetFileName($urls[0]))
Write-Output "  $($E.Reloj) Descargando $(Format-Tam $elegido.Tam)…"
if (-not (Get-Descarga $urls[0] $cab 3600 2 'Descarga del driver')) { Write-Output "$($E.Error) La descarga falló."; exit 1 }
$ext = Join-Path $dirDrv 'extraido'; Remove-Item -LiteralPath $ext -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force $ext | Out-Null
$x = Invoke-Proceso (Join-Path $env:SystemRoot 'System32\expand.exe') ('-F:* "{0}" "{1}"' -f $cab, $ext) 1800 'Descomprimir' 30
$infs = @(Get-ChildItem -LiteralPath $ext -Recurse -Filter *.inf -File -ErrorAction SilentlyContinue); $cats = @(Get-ChildItem -LiteralPath $ext -Recurse -Filter *.cat -File -ErrorAction SilentlyContinue)
if ($x.Codigo -ne 0 -or -not $infs.Count) { Write-Output "$($E.Error) El archivo descargado no contiene un driver válido."; exit 1 }
# Firma: cada catálogo (.cat) debe ser válido y de Microsoft (los drivers certificados WHQL lo llevan)
$malos = @($cats | Where-Object { $s = Get-AuthenticodeSignature -LiteralPath $_.FullName; $s.Status -ne 'Valid' -or $s.SignerCertificate.Subject -notmatch 'O=Microsoft' })
if (-not $cats.Count -or $malos.Count) { Write-Output "$($E.Error) La firma del driver no es válida ($($malos.Count) de $($cats.Count) catálogos sin firma de Microsoft). No se instala."; Write-Log "Instalar_Driver_Catalogo: firma no válida para $id" 'ERROR'; exit 1 }
Write-Output "  $($E.OK) Verificado: $($infs.Count) archivo(s) .inf y $($cats.Count) catálogo(s) con firma válida de Microsoft."
if ($SoloDescargar) { Write-Output "`n  $($E.Info) Solo descarga: no se ha instalado nada. Driver en: $ext"; Write-Log "Instalar_Driver_Catalogo: descargado y verificado $id"; exit 0 }

[void](New-PuntoRestauracionSeguro "Nitrit0 - antes de instalar el driver $id")
$i = Invoke-Proceso (Join-Path $env:SystemRoot 'System32\pnputil.exe') ('/add-driver "{0}\*.inf" /subdirs /install' -f $ext) 1800 'Instalar driver' 30 -MostrarSalida
if ($i.Codigo -eq 0 -or $i.Codigo -eq 3010) {
    Write-Output "`n$($E.OK) Driver instalado: $($elegido.Titulo) v$($elegido.Version).$(if ($i.Codigo -eq 3010) { ' Reinicia el equipo para terminar.' } else { '' })"
    Write-Log "Instalar_Driver_Catalogo: instalado $($elegido.Titulo) v$($elegido.Version) para $id (código $($i.Codigo))"
} else { Write-Output "`n$($E.Error) pnputil no pudo instalarlo (código $($i.Codigo)). El equipo no se ha cambiado; el punto de restauración sigue disponible."; Write-Log "Instalar_Driver_Catalogo: fallo pnputil $($i.Codigo) para $id" 'ERROR'; exit 1 }
