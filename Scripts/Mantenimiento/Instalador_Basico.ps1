# =====================================================================
#  Instalador_Basico.ps1 - Instalación desatendida de programas (Nitrit0)
#  Elige los programas en una ventana y los instala con winget; si winget falla, descarga el instalador oficial.
#  Resistente a cortes: tiempo máximo por instalación, reintentos, instaladores y licencias copiados a la caché
#  local (el pendrive puede desconectarse sin colgar el proceso) y registro de cada paso en Datos\Logs.
#  Parámetros:  -Todos (sin ventana, instala los marcados por defecto)  -Ids "Google.Chrome","VideoLAN.VLC"  -Simular
# =====================================================================
[CmdletBinding()]
param([string[]]$Ids, [switch]$Todos, [Alias('SoloAnalizar')][switch]$Simular)

if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
if (-not $Simular) { Assert-Admin 'instalar programas' }   # instala en Archivos de programa y copia la licencia de WinRAR ahí
if ($Ids) { $Ids = @($Ids | ForEach-Object { $_ -split '[,;]' } | Where-Object { $_ }) }   # admite -Ids "a,b" desde la línea de comandos
$TiempoWinget = 900      # s máximos por instalación con winget
$TiempoDirecto = 600     # s máximos por instalador descargado
$TiempoOffice = 2400     # s máximos para Office 2013

$PF = $env:ProgramFiles; $PF86 = ${env:ProgramFiles(x86)}
$CatalogoApps = @(
    @{ Id = 'Google.Chrome';                    Nombre = 'Google Chrome (navegador)';                    Defecto = $true;  Rutas = @("$PF\Google\Chrome\Application\chrome.exe", "$PF86\Google\Chrome\Application\chrome.exe")
       Url = 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi'; Dominio = 'dl.google.com'; Firmante = 'Google LLC'; Tipo = 'MSI'; Args = '/qn /norestart' }
    @{ Id = 'Mozilla.Firefox';                  Nombre = 'Mozilla Firefox (navegador)';                  Defecto = $true;  Rutas = @("$PF\Mozilla Firefox\firefox.exe", "$PF86\Mozilla Firefox\firefox.exe")
       Url = 'https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=es-ES'; Dominio = 'download.mozilla.org'; Firmante = 'Mozilla Corporation'; Tipo = 'EXE'; Args = '/S' }
    @{ Id = 'Brave.Brave';                      Nombre = 'Brave (navegador sin anuncios)';               Defecto = $false; Rutas = @("$PF\BraveSoftware\Brave-Browser\Application\brave.exe")
       Url = 'https://laptop-updates.brave.com/latest/winx64'; Dominio = 'laptop-updates.brave.com'; Firmante = 'Brave Software'; Tipo = 'EXE'; Args = '--install --silent --system-level' }
    @{ Id = 'RARLab.WinRAR';                    Nombre = $(if (Test-ModoPublico) { 'WinRAR (compresor en versión de prueba)' } else { 'WinRAR (con licencia si el pack la lleva)' });  Defecto = $true;  Rutas = @("$PF\WinRAR\WinRAR.exe", "$PF86\WinRAR\WinRAR.exe")
       Url = 'https://www.rarlab.com/rar/winrar-x64-701es.exe'; Dominio = 'www.rarlab.com'; Firmante = 'win\.rar GmbH'; Tipo = 'EXE'; Args = '/S' }
    @{ Id = '7zip.7zip';                        Nombre = '7-Zip (compresor gratuito)';                   Defecto = $false; Rutas = @("$PF\7-Zip\7zFM.exe")
       GitHub = 'ip7z/7zip'; AssetRegex = '^7z.*-x64\.exe$'; Url = 'https://www.7-zip.org/a/7z2606-x64.exe'; Dominio = 'www.7-zip.org'; Sha256 = '9B697F65ECC2D9B0152F5EE96D72DDE522A7827690349D9307935DACF40F42EC'; Tipo = 'EXE'; Args = '/S' }
    @{ Id = 'Foxit.FoxitReader';                Nombre = 'Foxit PDF Reader';                             Defecto = $true;  Rutas = @("$PF86\Foxit Software\Foxit PDF Reader\FoxitPDFReader.exe", "$PF\Foxit Software\Foxit PDF Reader\FoxitPDFReader.exe") }
    @{ Id = 'VideoLAN.VLC';                     Nombre = 'VLC media player';                             Defecto = $true;  Rutas = @("$PF\VideoLAN\VLC\vlc.exe", "$PF86\VideoLAN\VLC\vlc.exe")
       UrlIndice = 'https://get.videolan.org/vlc/last/win64/'; Patron = 'vlc-[\d.]+-win64\.exe'; Dominio = 'get.videolan.org'; Firmante = 'VideoLAN'; Tipo = 'EXE'; Args = '/S' }
    @{ Id = 'CodecGuide.K-LiteCodecPack.Basic'; Nombre = 'K-Lite Codec Pack Basic';                      Defecto = $true;  Rutas = @("$PF86\K-Lite Codec Pack\CodecTweakTool.exe") }
    @{ Id = 'AnyDeskSoftwareGmbH.AnyDesk';      Nombre = 'AnyDesk (solo si alguien de confianza te lo pide)'; Defecto = $false; Rutas = @("$PF86\AnyDesk\AnyDesk.exe", "$PF\AnyDesk\AnyDesk.exe")
       Url = 'https://download.anydesk.com/AnyDesk.exe'; Dominio = 'download.anydesk.com'; Firmante = 'AnyDesk|philandro'; Tipo = 'EXE'; Args = "--install `"$PF86\AnyDesk`" --silent" }
    @{ Id = 'Notepad++.Notepad++';              Nombre = 'Notepad++ (editor de texto)';                  Defecto = $true;  Rutas = @("$PF\Notepad++\notepad++.exe", "$PF86\Notepad++\notepad++.exe") }
    @{ Id = 'Microsoft.PowerShell';             Nombre = 'PowerShell 7';                                 Defecto = $false; Rutas = @("$PF\PowerShell\7\pwsh.exe") }
    @{ Id = 'Discord.Discord';                  Nombre = 'Discord (chat y voz)';                         Defecto = $false; Rutas = @("$env:LOCALAPPDATA\Discord\Update.exe") }
    @{ Id = 'Valve.Steam';                      Nombre = 'Steam (juegos)';                               Defecto = $false; Rutas = @("$PF86\Steam\steam.exe") }
)
# Office 2013 y la licencia de WinRAR solo existen en el pack personal: sin la carpeta, la opción no aparece
if (Test-Path -LiteralPath (Join-Path (Get-KitRaiz) 'Apps\Instaladores\Office2013')) { $CatalogoApps += @{ Id = 'OFFICE2013_LOCAL'; Nombre = 'Microsoft Office 2013 ProPlus (desde el pendrive, con su clave)'; Defecto = $false } }

# ---------- Selección ----------
$Seleccionados = @()
if ($Ids) { $Seleccionados = @($CatalogoApps | Where-Object { $Ids -contains $_.Id }) }
elseif ($Todos) { $Seleccionados = @($CatalogoApps | Where-Object { $_.Defecto }) }
else {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    [Windows.Forms.Application]::EnableVisualStyles()
    $oscuro = $true; try { $aj = Join-Path (Get-KitDatos) 'Ajustes.json'; if (Test-Path -LiteralPath $aj) { $oscuro = ((Get-Content -LiteralPath $aj -Raw -Encoding UTF8 | ConvertFrom-Json).Tema -ne 'claro') } } catch { }
    $cF = if ($oscuro) { '#12151C' } else { '#F3F5F9' }; $cL = if ($oscuro) { '#1E2330' } else { '#FFFFFF' }; $cT = if ($oscuro) { '#F0F3FA' } else { '#1B2230' }; $cA = if ($oscuro) { '#2BC4D8' } else { '#087F91' }; $cAT = if ($oscuro) { '#06222A' } else { '#FFFFFF' }
    $c = { param($h) [Drawing.ColorTranslator]::FromHtml($h) }
    $f = New-Object Windows.Forms.Form; $f.Text = 'Instalar programas - Nitrit0'; $f.Size = New-Object Drawing.Size(520, 560); $f.StartPosition = 'CenterScreen'; $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.TopMost = $true
    $f.Font = New-Object Drawing.Font('Segoe UI', 10); $f.BackColor = & $c $cF
    $l = New-Object Windows.Forms.Label; $l.Text = 'Marca los programas que quieres instalar en este equipo'; $l.AutoSize = $true; $l.Location = '20,16'; $l.Font = New-Object Drawing.Font('Segoe UI Semibold', 11); $l.ForeColor = & $c $cT
    $lb = New-Object Windows.Forms.CheckedListBox; $lb.CheckOnClick = $true; $lb.Location = '20,50'; $lb.Size = '466,382'; $lb.BorderStyle = 'None'; $lb.BackColor = & $c $cL; $lb.ForeColor = & $c $cT; $lb.Font = New-Object Drawing.Font('Segoe UI', 10.5)
    foreach ($a in $CatalogoApps) { [void]$lb.Items.Add($a.Nombre, $a.Defecto) }
    $bt = New-Object Windows.Forms.Button; $bt.Text = 'Marcar todo'; $bt.Location = '20,444'; $bt.Size = '110,34'; $bt.FlatStyle = 'Flat'; $bt.ForeColor = & $c $cT; $bt.Add_Click({ for ($i = 0; $i -lt $lb.Items.Count; $i++) { $lb.SetItemChecked($i, $true) } })
    $bn = New-Object Windows.Forms.Button; $bn.Text = 'Ninguno'; $bn.Location = '138,444'; $bn.Size = '90,34'; $bn.FlatStyle = 'Flat'; $bn.ForeColor = & $c $cT; $bn.Add_Click({ for ($i = 0; $i -lt $lb.Items.Count; $i++) { $lb.SetItemChecked($i, $false) } })
    $bi = New-Object Windows.Forms.Button; $bi.Text = 'Instalar seleccionados'; $bi.Location = '270,444'; $bi.Size = '216,38'; $bi.FlatStyle = 'Flat'; $bi.BackColor = & $c $cA; $bi.ForeColor = & $c $cAT; $bi.Font = New-Object Drawing.Font('Segoe UI Semibold', 10); $bi.DialogResult = 'OK'
    $f.Controls.AddRange(@($l, $lb, $bt, $bn, $bi)); $f.AcceptButton = $bi
    $r = $f.ShowDialog()
    if ($r -eq 'OK') { for ($i = 0; $i -lt $CatalogoApps.Count; $i++) { if ($lb.GetItemChecked($i)) { $Seleccionados += $CatalogoApps[$i] } } }
    $f.Dispose()
    if ($r -ne 'OK') { Exit-Kit 'Cancelado' 'Instalación cancelada.' }
}
if (-not $Seleccionados) { Exit-Kit 'Cancelado' 'No hay programas seleccionados.' }
if (-not $Simular) { Confirm-EquipoListo 'instalar programas'; [void](Start-OperacionSegura 'Instalar programas') }   # punto de restauración antes de instalar

# ---------- Utilidades ----------
$Resumen = @{ Ok = 0; Ya = 0; Fallo = 0; Reinicio = 0; Detalle = New-Object Collections.Generic.List[string] }
function Test-AppInstalada($a) { if ($a.Rutas) { foreach ($r in $a.Rutas) { if ($r -and (Test-Path -LiteralPath $r)) { return $true } } }; $false }
$CodigosOk = @(0, 3010, 1641)
$CodigosYa = @(-1978335189, -1978335188, -1978335212, -1978335135)   # winget: ya instalado / sin actualización aplicable

function Copy-LicenciaWinRAR($lic) {
    if (-not $lic -or -not (Test-Path -LiteralPath $lic)) { Write-Output "    $($E.Aviso) No hay licencia rarreg.key en Apps\Licencias: WinRAR queda en modo de prueba."; return }
    foreach ($d in @("$PF\WinRAR", "$PF86\WinRAR")) {
        if (Test-Path -LiteralPath $d) { try { Copy-Item -LiteralPath $lic -Destination (Join-Path $d 'rarreg.key') -Force -ErrorAction Stop; Write-Output "    $($E.OK) Licencia de WinRAR activada."; Write-Log 'Licencia WinRAR copiada'; return } catch { Write-Output "    $($E.Aviso) No se pudo copiar la licencia: $($_.Exception.Message)" } }
    }
}

function Install-Directo($a) {
    if (-not ($a.Url -or $a.UrlIndice)) { return $false }
    $url = $a.Url
    # VLC cambia de versión y retira la anterior: el nombre del instalador se lee del listado oficial
    if ($a.UrlIndice) { try { $m = [regex]::Match((Invoke-WebRequest -Uri $a.UrlIndice -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop).Content, $a.Patron); if ($m.Success) { $url = $a.UrlIndice + $m.Value } } catch { } }
    if (-not $url) { Write-Host "    $($E.Error) No se pudo averiguar la versión actual de $($a.Nombre)."; return $false }
    $dominio = $a.Dominio; $sha256 = $a.Sha256
    # Última versión desde GitHub, solo si publica su SHA-256 (7-Zip no lleva firma); si la API no responde, queda la URL fija de 7-zip.org con su huella
    if ($a.GitHub) {
        try {
            $rel = Invoke-RestMethod "https://api.github.com/repos/$($a.GitHub)/releases/latest" -Headers @{ 'User-Agent' = 'Mozilla/5.0 Nitrit0-Diagnostico'; Accept = 'application/vnd.github+json' } -TimeoutSec 20 -ErrorAction Stop
            $as = @($rel.assets | Where-Object { $_.name -match $a.AssetRegex }) | Select-Object -First 1
            if ($as -and "$($as.digest)" -match '^sha256:([0-9A-Fa-f]{64})$') { $url = $as.browser_download_url; $dominio = 'github.com'; $sha256 = $Matches[1] }
        } catch { }
    }
    $uri = [Uri]$url
    if ($uri.Scheme -ne 'https' -or $uri.Host -ne $dominio) { Write-Host "    $($E.Error) La dirección de descarga no es HTTPS del dominio oficial ($dominio). No se descarga."; Write-Log "Dominio inesperado para $($a.Id): $url" 'ERROR'; return $false }
    Write-Host "    $($E.Cohete) Descargando el instalador oficial de $($a.Nombre)…"
    $ext = if ($a.Tipo -eq 'MSI') { '.msi' } else { '.exe' }
    $tmp = Join-Path $Global:NitKit.Cache ("Descargas\{0}{1}" -f ($a.Id -replace '[^\w\.\-]', '_'), $ext)
    if ($Simular) { Write-Host "    (simulación) se descargaría $url"; return $false }
    try {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        if (-not (Get-Descarga $url $tmp 240 3 "Descarga de $($a.Id)")) { Write-Host "    $($E.Error) No se pudo descargar (¿hay Internet?)."; return $false }
        Write-Host ("    $($E.OK) Descargado ({0:N1} MB). Verificando firma digital…" -f ((Get-Item -LiteralPath $tmp).Length / 1MB))
        if ($sha256) {
            # Sin firma Authenticode (7-Zip): la huella SHA-256 de esta versión concreta, comprobada contra el instalador de su GitHub oficial
            $hash = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash
            if ($hash -ne $sha256) { Write-Host "    $($E.Error) La huella SHA-256 no coincide con la esperada ($hash). No se instala."; Write-Log "Huella inesperada en $($a.Id): $hash" 'ERROR'; return $false }
        } else {
            $sig = Get-AuthenticodeSignature -LiteralPath $tmp
            if ($sig.Status -ne 'Valid') { Write-Host "    $($E.Error) La firma digital no es válida ($($sig.Status)). No se instala."; Write-Log "Firma no válida en $($a.Id): $($sig.Status)" 'ERROR'; return $false }
            # Además de válida, la firma tiene que ser del editor esperado de esa aplicación (un instalador firmado por otro, aunque sea válido, no se ejecuta)
            $firmante = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { '' }
            if (-not $a.Firmante -or $firmante -notmatch $a.Firmante) { Write-Host "    $($E.Error) El instalador no está firmado por el editor esperado ($($a.Firmante)): $firmante. No se instala."; Write-Log "Firmante inesperado en $($a.Id): $firmante" 'ERROR'; return $false }
        }
        Write-Host "    $($E.Reloj) Instalando en silencio (máx. $TiempoDirecto s)…"
        $r = if ($a.Tipo -eq 'MSI') { Invoke-Proceso (Join-Path $env:SystemRoot 'System32\msiexec.exe') "/i `"$tmp`" $($a.Args)" $TiempoDirecto "Instalación de $($a.Id)" } else { Invoke-Proceso $tmp $a.Args $TiempoDirecto "Instalación de $($a.Id)" }
        if (@(3010, 1641) -contains $r.Codigo) { $Resumen.Reinicio++ }`r`n        return (($CodigosOk -contains $r.Codigo) -or (Test-AppInstalada $a))
    } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

function Install-Office2013 {
    Write-Output "`n  $($E.Lupa) Microsoft Office 2013 ProPlus…"
    if ((Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Office15.PROPLUS') -or (Test-Path 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Office15.PROPLUS')) { Write-Output "    $($E.Info) Ya está instalado."; $Resumen.Ya++; return }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration') { Write-Output "    $($E.Aviso) Hay Office Click-to-Run/365 instalado: se omite Office 2013."; return }
    $cand = New-Object Collections.Generic.List[string]
    $cand.Add((Join-Path (Get-KitRaiz) 'Apps\Instaladores\Office2013'))
    foreach ($u in [IO.DriveInfo]::GetDrives()) { try { if ($u.IsReady) { if ($u.DriveType -eq 'CDRom') { $cand.Add($u.RootDirectory.FullName) } else { $cand.Add((Join-Path $u.RootDirectory.FullName 'Apps\Programas\office 2013')) } } } catch { } }
    $origen = $null
    foreach ($r in $cand) { if (Test-Path -LiteralPath $r) { $s = Get-ChildItem -LiteralPath $r -Filter setup.exe -File -Recurse -Depth 2 -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.DirectoryName 'proplus.ww') } | Select-Object -First 1; if ($s) { $origen = $s.DirectoryName; break } } }
    if (-not $origen) { Write-Output "    $($E.Aviso) No se encontró el instalador de Office 2013 (Apps\Instaladores\Office2013 o Apps\Programas\office 2013)."; $Resumen.Fallo++; return }
    $clave = $null
    foreach ($c in @($origen, (Split-Path $origen -Parent))) { foreach ($f in (Get-ChildItem -LiteralPath $c -Filter 'office*.txt' -File -ErrorAction SilentlyContinue)) { $m = [regex]::Match((Get-Content -LiteralPath $f.FullName -Raw), '(?i)(?:[A-Z0-9]{5}-){4}[A-Z0-9]{5}'); if ($m.Success) { $clave = $m.Value.ToUpper(); break } }; if ($clave) { break } }
    $cfg = Join-Path $Global:NitKit.Cache 'office2013.xml'
    $xml = @('<Configuration Product="ProPlus">', '  <Display Level="none" CompletionNotice="no" SuppressModal="yes" AcceptEULA="yes" />', '  <Setting Id="SETUP_REBOOT" Value="Never" />')
    if ($clave) { $xml += "  <PIDKEY Value=`"$($clave -replace '-', '')`" />" }; $xml += '</Configuration>'
    if ($Simular) { Write-Output "    (simulación) se instalaría desde $origen"; return }
    Set-Content -LiteralPath $cfg -Value $xml -Encoding UTF8   # lleva la clave de producto en claro: se borra siempre al terminar (el equipo es del cliente)
    try {
        for ($i = 1; $i -le 2; $i++) {
            Write-Output "    $($E.Reloj) Instalando desde $origen (intento $i de 2, máx. $([int]($TiempoOffice / 60)) min)…"
            $r = Invoke-Proceso (Join-Path $origen 'setup.exe') "/config `"$cfg`"" $TiempoOffice 'Office 2013' 30
            if (@(3010, 1641) -contains $r.Codigo) { $Resumen.Reinicio++ }; if ($CodigosOk -contains $r.Codigo) { Write-Output "    $($E.OK) Office 2013 instalado."; $Resumen.Ok++; $Resumen.Detalle.Add('Office 2013: instalado'); return }
            Write-Output "    $($E.Aviso) Código $($r.Codigo). Comprobando la unidad antes de reintentar…"
            if (-not (Wait-Kit 180)) { break }
        }
        Write-Output "    $($E.Error) No se pudo instalar Office 2013."; $Resumen.Fallo++; $Resumen.Detalle.Add('Office 2013: FALLÓ')
    } finally { Remove-Item -LiteralPath $cfg -Force -ErrorAction SilentlyContinue }
}

# ---------- Proceso ----------
Write-Output ""
Write-Output "========================================================"
Write-Output "  $($E.Cohete) INSTALANDO $($Seleccionados.Count) PROGRAMA(S)$(if ($Simular) { ' (SIMULACIÓN)' })"
Write-Output "========================================================"
Write-Log "Instalador: $($Seleccionados.Count) programas seleccionados: $(($Seleccionados | ForEach-Object { $_.Id }) -join ', ')"

$hayRed = Test-Internet
if (-not $hayRed) { Write-Output "  $($E.Aviso) Sin conexión a Internet: solo se podrán instalar programas que ya estén en caché." }
$licencia = $null
if ($Seleccionados.Id -contains 'RARLab.WinRAR') {
    $orig = Join-Path (Get-KitRaiz) 'Apps\Licencias\rarreg.key'
    try { $licencia = Copy-AlCache $orig } catch { Write-Output "  $($E.Aviso) No se pudo leer la licencia de WinRAR del pendrive: $($_.Exception.Message)" }
}
$winget = (Get-Command winget.exe -ErrorAction SilentlyContinue)
if ($winget -and $hayRed -and -not $Simular) {
    Write-Output "  $($E.Refresh) Actualizando el catálogo de winget (máx. 120 s)…"
    $r = Invoke-Proceso $winget.Source 'source update --disable-interactivity' 120 'Catálogo winget' 30
    if ($r.TiempoAgotado -or $r.Codigo -ne 0) { Write-Output "  $($E.Aviso) El catálogo de winget no respondió (código $($r.Codigo)). Se usará descarga directa donde sea posible."; $winget = $null }
}
elseif (-not $winget) { Write-Output "  $($E.Aviso) winget no está disponible en este equipo: se usará descarga directa." }

$n = 0; $total = @($Seleccionados).Count
foreach ($a in $Seleccionados) {
    $n++
    $nombreCorto = $a.Nombre -replace '\s*\(.*$', ''   # «Google Chrome (navegador)» -> «Google Chrome»
    Write-Progreso ($n - 1) $total "Instalando $nombreCorto"   # barra de la app
    if ($a.Id -eq 'OFFICE2013_LOCAL') { continue }
    Write-Output "`n  [$n/$($Seleccionados.Count)] $($E.Lupa) $($a.Nombre)"
    if (Test-AppInstalada $a) { Write-Output "    $($E.Info) Ya está instalado."; $Resumen.Ya++; $Resumen.Detalle.Add("$($a.Nombre): ya estaba"); if ($a.Id -eq 'RARLab.WinRAR') { Copy-LicenciaWinRAR $licencia }; continue }
    if (-not (Test-KitDisponible)) { Write-Output "    $($E.Aviso) El pendrive no está conectado (no se necesita para esta instalación)." }
    $ok = $false
    if ($winget -and $hayRed) {
        for ($i = 1; $i -le 2 -and -not $ok; $i++) {
            Write-Output "    $($E.Reloj) winget (intento $i de 2, máx. $([int]($TiempoWinget / 60)) min)…"
            if ($Simular) { Write-Output "    (simulación) winget install --id $($a.Id)"; break }
            $r = Invoke-Proceso $winget.Source "install --id $($a.Id) --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity" $TiempoWinget "winget $($a.Id)" 20
            $cod = $r.Codigo; if ($cod -gt 2147483647) { $cod -= 4294967296 }
            if (@(3010, 1641) -contains $cod) { $Resumen.Reinicio++ }; if ($CodigosOk -contains $cod -or (Test-AppInstalada $a)) { $ok = $true; Write-Output "    $($E.OK) Instalado con winget."; $Resumen.Ok++; $Resumen.Detalle.Add("$($a.Nombre): instalado (winget)") }
            elseif ($CodigosYa -contains $cod) { $ok = $true; Write-Output "    $($E.Info) Ya estaba instalado."; $Resumen.Ya++; $Resumen.Detalle.Add("$($a.Nombre): ya estaba") }
            elseif ($cod -eq -1978335215) { Write-Output "    $($E.Aviso) winget sin catálogo en este equipo."; $winget = $null; break }
            else { Write-Output "    $($E.Aviso) winget no pudo instalarlo (código $cod)$(if ($r.TiempoAgotado) { ' por tiempo agotado' })." }
        }
    }
    if (-not $ok -and $hayRed) {
        if (Install-Directo $a) { $ok = $true; Write-Output "    $($E.OK) Instalado con el instalador oficial."; $Resumen.Ok++; $Resumen.Detalle.Add("$($a.Nombre): instalado (descarga directa)") }
    }
    if (-not $ok -and -not $Simular) { Write-Output "    $($E.Error) No se pudo instalar $($a.Nombre)."; $Resumen.Fallo++; $Resumen.Detalle.Add("$($a.Nombre): FALLÓ") }
    if (($ok -or (Test-AppInstalada $a)) -and $a.Id -eq 'RARLab.WinRAR') { Copy-LicenciaWinRAR $licencia }
}
if ($Seleccionados.Id -contains 'OFFICE2013_LOCAL') { Write-Progreso ($total - 1) $total 'Instalando Microsoft Office 2013 (tarda)'; Install-Office2013 }
Write-Progreso $total $total 'Terminado'
if ($licencia) { Remove-Item -LiteralPath $licencia -Force -ErrorAction SilentlyContinue }   # copia de la licencia de WinRAR en la caché del PC: no se deja en el equipo del cliente

Write-Output ""
Write-Output "========================================================"
Write-Output "  $($E.Disco) RESUMEN: $($Resumen.Ok) instalados | $($Resumen.Ya) ya estaban | $($Resumen.Fallo) fallidos"
Write-Output "========================================================"
if ($Resumen.Reinicio) { Write-Output "  $($E.Aviso) $($Resumen.Reinicio) programa(s) piden reiniciar el equipo para terminar la instalación." }
Write-Log "Instalador terminado: $($Resumen.Ok) instalados, $($Resumen.Ya) ya estaban, $($Resumen.Fallo) fallidos. $($Resumen.Detalle -join ' | ')"
if ($Resumen.Fallo -gt 0) { exit 1 }
