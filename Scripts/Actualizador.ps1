# =====================================================================
#  Actualizador de herramientas - Nitrit0
#  Comprueba y actualiza las apps del kit desde sus fuentes oficiales.
#  Las que no tienen descarga directa estable se abren en su página oficial.
#  Antes de reemplazar nada guarda una copia de la versión anterior en Datos\Respaldo.
#  Cada descarga se verifica (firma digital o SHA-256 publicado) antes de instalarse.
# =====================================================================

$script:CatalogoUpd = @(
    @{ N = 'smartmontools';        Carpeta = 'Disk\smartmontools';            Exe = 'Disk\smartmontools\bin\smartctl.exe';              Tipo = 'nsis'; Repo = 'smartmontools/smartmontools'; Asset = 'win32-setup\.exe$'; Firma = 'SignPath' }
    @{ N = 'LibreHardwareMonitor'; Carpeta = 'HW Info\LibreHardwareMonitor'; Exe = 'HW Info\LibreHardwareMonitor\LibreHardwareMonitor.exe'; Tipo = 'zip'; Repo = 'LibreHardwareMonitor/LibreHardwareMonitor'; Asset = '^LibreHardwareMonitor\.zip$' }
    @{ N = 'WinDirStat';           Carpeta = 'Disk\WinDirStat';               Exe = 'Disk\WinDirStat\x64\WinDirStat.exe';                Tipo = 'zip'; Repo = 'windirstat/windirstat'; Asset = '^WinDirStat\.zip$' }
    @{ N = 'Autoruns';             Carpeta = 'Sistema\Autoruns';              Exe = 'Sistema\Autoruns\Autoruns64.exe';                   Tipo = 'zip'; Url = 'https://download.sysinternals.com/files/Autoruns.zip'; Firma = 'Microsoft' }
    @{ N = 'KVRT (Kaspersky)';     Carpeta = 'Malware';                       Exe = 'Malware\KVRT.exe';                                  Tipo = 'exe'; Url = 'https://devbuilds.s.kaspersky-labs.com/devbuilds/KVRT/latest/full/KVRT.exe'; Firma = 'Kaspersky'; Fichero = 'KVRT.exe' }
    @{ N = 'AdwCleaner';           Carpeta = 'Malware';                       Exe = 'Malware\adwcleaner.exe';                            Tipo = 'exe'; Url = 'https://adwcleaner.malwarebytes.com/adwcleaner?channel=release'; Firma = 'Malwarebytes'; Fichero = 'adwcleaner.exe' }
    @{ N = 'CPU-Z';                Exe = 'CPU\cpu-z_*\cpuz_x64.exe';             Tipo = 'pagina'; Pagina = 'https://www.cpuid.com/softwares/cpu-z.html' }
    @{ N = 'HWMonitor';            Exe = 'HW Info\hwmonitor_*\HWMonitor_x64.exe';     Tipo = 'pagina'; Pagina = 'https://www.cpuid.com/softwares/hwmonitor.html' }
    @{ N = 'HWiNFO';               Exe = 'HW Info\hwi_*\HWiNFO64.exe';                 Tipo = 'pagina'; Pagina = 'https://www.hwinfo.com/download/' }
    @{ N = 'GPU-Z';                Exe = 'GPU\GPU-Z.exe';                                Tipo = 'pagina'; Pagina = 'https://www.techpowerup.com/gpuz/' }
    @{ N = 'Core Temp';            Exe = 'HW Info\CoreTemp64\Core Temp.exe';             Tipo = 'pagina'; Pagina = 'https://www.alcpu.com/CoreTemp/' }
    @{ N = 'CrystalDiskInfo';      Exe = 'Disk\CrystalDiskInfo*\DiskInfo64.exe';     Tipo = 'pagina'; Pagina = 'https://crystalmark.info/en/software/crystaldiskinfo/' }
    @{ N = 'CrystalDiskMark';      Exe = 'Disk\CrystalDiskMark*\DiskMark64.exe';     Tipo = 'pagina'; Pagina = 'https://crystalmark.info/en/software/crystaldiskmark/' }
    @{ N = 'WizTree';              Exe = 'Disk\wiztree_*\WizTree64.exe';     Tipo = 'pagina'; Pagina = 'https://www.diskanalyzer.com/download' }
    @{ N = 'HDDScan';              Exe = 'Disk\HDDScan\HDDScan.exe';                     Tipo = 'pagina'; Pagina = 'https://hddscan.com/' }
    @{ N = 'OCCT';                 Exe = 'Stress Test\OCCT.exe';                         Tipo = 'pagina'; Pagina = 'https://www.ocbase.com/download' }
    @{ N = 'FurMark';              Exe = 'Stress Test\FurMark_*\FurMark_win64\FurMark_GUI.exe'; Tipo = 'pagina'; Pagina = 'https://geeks3d.com/furmark/downloads/' }
    @{ N = 'Prime95';              Exe = 'Stress Test\p95v*\prime95.exe';    Tipo = 'pagina'; Pagina = 'https://www.mersenne.org/download/' }
    @{ N = 'MemTest64';            Exe = 'Memoria\MemTest64.exe';                        Tipo = 'pagina'; Pagina = 'https://www.techpowerup.com/memtest64/' }
    @{ N = 'MemTest86';            Exe = 'Memoria\memtest86-usb\imageUSB.exe';           Tipo = 'pagina'; Pagina = 'https://www.memtest86.com/download.htm' }
    @{ N = 'CRU (resoluciones)';   Exe = 'Pantalla\cru-*\CRU.exe';                  Tipo = 'pagina'; Pagina = 'https://www.monitortests.com/forum/Thread-Custom-Resolution-Utility-CRU' }
    @{ N = 'MonTest (PassMark)';   Exe = 'Pantalla\montest.exe';                         Tipo = 'pagina'; Pagina = 'https://www.passmark.com/products/monitortest/' }
)

function Get-VersionInstalada($e) {
    try { $p = Resolve-ExeKit $e.Exe; if (Test-Path -LiteralPath $p) { $v = (Get-Item -LiteralPath $p).VersionInfo; $x = if ($v.ProductVersion) { $v.ProductVersion } else { $v.FileVersion }; return (("$x").Trim() -replace '\+.*$', '' -replace '\.\s+', '.') } } catch { }
    $null
}
function ConvertTo-Numerico([string]$s) { $s = $s -replace '_', '.'; if ($s -match '(\d+(?:\.\d+){1,3})') { try { return [version]$matches[1] } catch { } }; $null }

function Get-Versiones { $p = Join-Path $dirDatos 'Versiones.json'; try { if (Test-Path -LiteralPath $p) { return (Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json) } } catch { }; [pscustomobject]@{} }
function Set-Version([string]$nombre, [string]$remoto) {
    $v = Get-Versiones; $h = @{}; foreach ($n in $v.PSObject.Properties.Name) { $h[$n] = $v.$n }
    $h[$nombre] = @{ Fecha = (Get-Date -Format 'yyyy-MM-dd HH:mm'); Remoto = $remoto }
    try { $h | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $dirDatos 'Versiones.json') -Encoding UTF8 } catch { }
}

# Consulta la fuente oficial. Devuelve @{ Version; Etiqueta; Url; Digest; Tam; Fecha }
function Get-Remoto($e) {
    $h = @{ 'User-Agent' = 'Mozilla/5.0 Nitrit0-Diagnostico' }
    try {
        if ($e.Repo) {
            $r = Invoke-Reintento -Nombre "Consulta de $($e.N)" -Intentos 2 -EsperaSeg 3 -Accion { Invoke-RestMethod "https://api.github.com/repos/$($e.Repo)/releases/latest" -Headers ($h + @{ Accept = 'application/vnd.github+json' }) -TimeoutSec 25 -ErrorAction Stop }
            $a = @($r.assets | Where-Object { $_.name -match $e.Asset }) | Select-Object -First 1
            if (-not $a) { return [pscustomobject]@{ Error = 'No se encontró el archivo en la última versión.' } }
            return [pscustomobject]@{ Version = (ConvertTo-Numerico $r.tag_name); Etiqueta = $r.tag_name; Url = $a.browser_download_url; Digest = $a.digest; Tam = $a.size; Fecha = $r.published_at; Error = $null }
        }
        if ($e.Url) {
            $r = Invoke-WebRequest $e.Url -Method Head -UseBasicParsing -Headers $h -TimeoutSec 25 -MaximumRedirection 5
            $mod = "$($r.Headers['Last-Modified'])"; $tam = 0; [void][long]::TryParse("$($r.Headers['Content-Length'])", [ref]$tam)
            return [pscustomobject]@{ Version = $null; Etiqueta = $mod; Url = $e.Url; Digest = $null; Tam = $tam; Fecha = $mod; Error = $null }
        }
    } catch { return [pscustomobject]@{ Error = $_.Exception.Message } }
    [pscustomobject]@{ Error = 'Sin fuente automática' }
}

function Test-Descarga([string]$ruta, $e, $remoto) {
    # 1) hash publicado por GitHub, 2) firma digital con el firmante esperado
    if ($remoto.Digest -match '^sha256:(.+)$') { $h = (Get-FileHash -LiteralPath $ruta -Algorithm SHA256).Hash.ToLower(); if ($h -ne $matches[1].ToLower()) { return 'El SHA-256 no coincide con el publicado.' } }
    if ($e.Firma -and $e.Tipo -ne 'zip') { $s = Get-AuthenticodeSignature -LiteralPath $ruta; if ($s.Status -ne 'Valid' -or $s.SignerCertificate.Subject -notmatch [regex]::Escape($e.Firma)) { return "La firma digital no es válida o no es de $($e.Firma) (estado: $($s.Status))." } }
    # Sin nada con qué verificar (ni SHA-256 publicado ni firma esperada) no se instala: la cabecera promete que cada descarga se verifica
    $verificada = ($remoto.Digest -match '^sha256:') -or [bool]$e.Firma   # en los zip con firma esperada (Autoruns) se comprueba la del programa tras descomprimir
    if (-not $verificada) { return 'No hay SHA-256 publicado ni firma esperada para comprobar la descarga; no se instala.' }
    $null
}

# Descarga, verifica, respalda lo anterior e instala. Devuelve @{ Ok; Mensaje }
function Update-Herramienta($e, $remoto, [scriptblock]$Progreso) {
    $destino = Join-Path $dirApps $e.Carpeta
    $work = Join-Path $env:TEMP ('Nitrit0_upd_' + [guid]::NewGuid().ToString('N').Substring(0, 8)); New-Item -ItemType Directory $work | Out-Null
    try {
        $en = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path -like "$destino*" })
        if ($e.Tipo -eq 'exe') { $en += @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq (Join-Path $destino $e.Fichero) }) }
        if ($en.Count) { return [pscustomobject]@{ Ok = $false; Mensaje = "Cierra $($en[0].ProcessName) antes de actualizar." } }
        & $Progreso 'Descargando…'
        $fich = Join-Path $work $(if ($e.Fichero) { $e.Fichero } else { [IO.Path]::GetFileName(([uri]$remoto.Url).AbsolutePath) })
        if ([IO.Path]::GetFileName($fich) -eq '') { $fich = Join-Path $work 'descarga.bin' }
        Invoke-Reintento -Nombre "Descarga de $($e.N)" -Intentos 3 -EsperaSeg 4 -Accion { Invoke-WebRequest $remoto.Url -OutFile $fich -UseBasicParsing -Headers @{ 'User-Agent' = 'Mozilla/5.0 Nitrit0-Diagnostico' } -TimeoutSec 300 -ErrorAction Stop }
        & $Progreso 'Verificando…'
        $mal = Test-Descarga $fich $e $remoto; if ($mal) { return [pscustomobject]@{ Ok = $false; Mensaje = $mal } }
        $stage = $null
        if ($e.Tipo -eq 'zip') {
            & $Progreso 'Descomprimiendo y verificando…'; Add-Type -AssemblyName System.IO.Compression.FileSystem
            # Anti Zip-Slip: ninguna entrada puede salirse de la carpeta de destino
            $zip = [IO.Compression.ZipFile]::OpenRead($fich)
            try { $mala = @($zip.Entries | Where-Object { $_.FullName -match '(^|[\\/])\.\.([\\/]|$)' -or $_.FullName -match '^[\\/]' -or $_.FullName -match '^[A-Za-z]:' } | Select-Object -First 1) } finally { $zip.Dispose() }
            if ($mala.Count) { return [pscustomobject]@{ Ok = $false; Mensaje = "El ZIP descargado contiene una ruta no permitida ($($mala[0].FullName)) y no se instala." } }
            $stage = Join-Path $work 'stage'; [IO.Compression.ZipFile]::ExtractToDirectory($fich, $stage)
            if (-not $e.Firma -and $remoto.Digest -notmatch '^sha256:') {
                # Sin hash ni firma que comprobar: al menos que el programa principal exista y no sea un archivo vacío o recortado
                $chk0 = Get-ChildItem -LiteralPath $stage -Recurse -Filter (Split-Path $e.Exe -Leaf) -File -ErrorAction SilentlyContinue | Select-Object -First 1
                if (-not $chk0 -or $chk0.Length -lt 50KB) { return [pscustomobject]@{ Ok = $false; Mensaje = 'El archivo descargado no contiene el programa esperado (o está incompleto).' } }
            }
            if ($e.Firma) {
                $chk = Get-ChildItem -LiteralPath $stage -Recurse -Filter (Split-Path $e.Exe -Leaf) -ErrorAction SilentlyContinue | Select-Object -First 1
                if (-not $chk) { return [pscustomobject]@{ Ok = $false; Mensaje = 'El archivo descargado no contiene el programa esperado.' } }
                $sg = Get-AuthenticodeSignature -LiteralPath $chk.FullName
                if ($sg.Status -ne 'Valid' -or $sg.SignerCertificate.Subject -notmatch [regex]::Escape($e.Firma)) { return [pscustomobject]@{ Ok = $false; Mensaje = "La firma digital del programa no es válida o no es de $($e.Firma) (estado: $($sg.Status))." } }
            }
        }
        # El pendrive tiene que estar presente para guardar la copia y colocar la versión nueva: si se ha desconectado, se espera a que vuelva
        if (-not (Wait-Kit 180 { param($m) & $Progreso $m })) { return [pscustomobject]@{ Ok = $false; Mensaje = 'La unidad del kit no está disponible (se descargó, pero no se instaló).' } }
        $destino = Join-Path (Join-Path $Global:NitKit.Raiz 'Apps') $e.Carpeta; $dirDatos = $Global:NitKit.Datos
        $resp = Join-Path $dirDatos 'Respaldo'; New-Item -ItemType Directory -Force $resp | Out-Null
        $marca = Get-Date -Format 'yyyyMMdd_HHmmss'; $nombreSeg = ($e.N -replace '[^\w\-\.]+', '_')
        & $Progreso 'Guardando la versión anterior…'
        if ($e.Tipo -eq 'exe') {
            $viejo = Join-Path $destino $e.Fichero; if (Test-Path -LiteralPath $viejo) { Invoke-Reintento -Nombre 'Guardar versión anterior' -EsperarKit -Accion { Move-Item -LiteralPath $viejo (Join-Path $resp "${nombreSeg}_$marca.exe") -Force -ErrorAction Stop } }
            Invoke-Reintento -Nombre 'Copiar al kit' -EsperarKit -Accion { Copy-Item -LiteralPath $fich -Destination $viejo -Force -ErrorAction Stop }
        }
        else {
            $bak = $null
            if (Test-Path -LiteralPath $destino) { $bak = Join-Path $resp "${nombreSeg}_$marca"; Invoke-Reintento -Nombre 'Guardar versión anterior' -EsperarKit -Accion { Move-Item -LiteralPath $destino -Destination $bak -Force -ErrorAction Stop } }
            try {
                if ($e.Tipo -eq 'zip') { & $Progreso 'Instalando…'; New-Item -ItemType Directory -Force (Split-Path $destino) | Out-Null; Invoke-Reintento -Nombre 'Copiar al kit' -Intentos 3 -EsperarKit -Accion { if (Test-Path -LiteralPath $destino) { Remove-Item -LiteralPath $destino -Recurse -Force }; Copy-Item -LiteralPath $stage -Destination $destino -Recurse -Force -ErrorAction Stop } }
                elseif ($e.Tipo -eq 'nsis') { & $Progreso 'Instalando…'; $p = Start-Process -FilePath $fich -ArgumentList "/S /D=$destino" -PassThru; if (-not $p.WaitForExit(300000)) { Stop-Arbol $p.Id; throw 'El instalador tardó más de 5 minutos y se canceló.' }; if ($p.ExitCode -ne 0) { throw "El instalador terminó con código $($p.ExitCode)." } }
            } catch {
                # Si algo falla a medias (p. ej. el pendrive se desconecta), se restaura la versión anterior
                Write-Log "Actualización de $($e.N) falló ($($_.Exception.Message)); se restaura la versión anterior" 'ERROR'
                if ($bak) { try { [void](Wait-Kit 60); if (Test-Path -LiteralPath $destino) { Remove-Item -LiteralPath $destino -Recurse -Force }; Move-Item -LiteralPath $bak -Destination $destino -Force } catch { } }
                throw
            }
        }
        Set-Version $e.N $(if ($remoto.Etiqueta) { $remoto.Etiqueta } else { '' })
        [pscustomobject]@{ Ok = $true; Mensaje = 'Actualizada.' }
    } catch { [pscustomobject]@{ Ok = $false; Mensaje = $_.Exception.Message } }
    finally { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
}

function Show-Actualizador {
    $K = $script:K; $cFondo = Get-Tc 'Fondo'; $cCab = Get-Tc 'Cab'; $cTexto = Get-Tc 'TextoSuave'; $cFlat = Get-Tc 'Boton'; $cAcento = Get-Tc 'Acento'; $cTarj = Get-Tc 'Tarjeta'
    $dlg = New-Object Windows.Forms.Form; $dlg.Text = 'Actualizar herramientas'; $dlg.Size = New-Object Drawing.Size([int](1060 * $K), 800); $dlg.MinimumSize = New-Object Drawing.Size([int](760 * $K), 560); $dlg.StartPosition = 'CenterParent'; $dlg.BackColor = $cFondo; $dlg.Font = New-Object Drawing.Font($script:Fuentes.UI, 9.5)
    if ($form.Icon) { $dlg.Icon = $form.Icon }
    $cab = New-Object Windows.Forms.Panel; $cab.Dock = 'Top'; $cab.BackColor = $cCab; $cab.Height = [int](132 * $K)
    $tit = New-Object Windows.Forms.Label; $tit.Text = 'Actualizar herramientas'; $tit.ForeColor = (Get-Tc 'Texto'); $tit.Font = New-Object Drawing.Font($script:Fuentes.Display, 18); $tit.AutoSize = $true; $tit.Location = New-Object Drawing.Point([int](24 * $K), [int](10 * $K))
    $sub = New-Object Windows.Forms.Label; $sub.Text = 'Se descargan de su fuente oficial, se verifican (firma digital o SHA-256) y se guarda copia de la versión anterior. Las que no tienen descarga directa abren su web.'; $sub.ForeColor = $cTexto; $sub.Size = New-Object Drawing.Size([int](980 * $K), [int](40 * $K)); $sub.Location = New-Object Drawing.Point([int](26 * $K), [int](52 * $K))
    function Nuevo-Boton([string]$t, [int]$w, $bg, $fg) { $b = New-Object Windows.Forms.Button; $b.Text = $t; $b.Size = New-Object Drawing.Size([int]($w * $K), [int](36 * $K)); $b.FlatStyle = 'Flat'; $b.BackColor = $bg; $b.ForeColor = $fg; $b.Font = New-Object Drawing.Font($script:Fuentes.Semi, 9.5); $b.Cursor = 'Hand'; $b.FlatAppearance.BorderColor = Get-Tc 'Borde'; $b }
    $btnComp = Nuevo-Boton 'Comprobar versiones' 190 $cAcento (Get-Tc 'TextoAcento'); $btnComp.Location = New-Object Drawing.Point([int](26 * $K), [int](88 * $K))
    $btnTodo = Nuevo-Boton 'Actualizar todo lo disponible' 240 $cFlat ((Get-Tc 'Texto')); $btnTodo.Location = New-Object Drawing.Point([int](226 * $K), [int](88 * $K)); $btnTodo.Enabled = $false
    $btnResp = Nuevo-Boton 'Abrir copias de seguridad' 210 $cFlat ((Get-Tc 'Texto')); $btnResp.Location = New-Object Drawing.Point([int](476 * $K), [int](88 * $K))
    $cab.Controls.AddRange(@($tit, $sub, $btnComp, $btnTodo, $btnResp))
    $st = New-Object Windows.Forms.StatusStrip; $st.BackColor = $cCab; $st.SizingGrip = $false; $lblEst = New-Object Windows.Forms.ToolStripStatusLabel; $lblEst.ForeColor = $cTexto; $lblEst.Text = 'Pulsa «Comprobar versiones» para ver qué hay nuevo.'; [void]$st.Items.Add($lblEst)
    $lista = New-Object Windows.Forms.FlowLayoutPanel; $lista.Dock = 'Fill'; $lista.FlowDirection = 'TopDown'; $lista.WrapContents = $false; $lista.AutoScroll = $true; $lista.BackColor = $cFondo; $lista.Padding = New-Object Windows.Forms.Padding([int](20 * $K), 8, 8, 12)
    $dlg.Controls.AddRange(@($lista, $st, $cab))
    $S = @{ Filas = @(); Remotos = @{} }
    foreach ($e in $script:CatalogoUpd) {
        $p = New-Object Windows.Forms.Panel; $p.Size = New-Object Drawing.Size([int](980 * $K), [int](62 * $K)); $p.BackColor = $cTarj; $p.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 8)
        $n = New-Object Windows.Forms.Label; $n.Text = $e.N; $n.ForeColor = (Get-Tc 'Texto'); $n.Font = New-Object Drawing.Font($script:Fuentes.Semi, 11); $n.AutoSize = $false; $n.Size = New-Object Drawing.Size([int](250 * $K), [int](26 * $K)); $n.Location = New-Object Drawing.Point([int](16 * $K), [int](8 * $K))
        $vi = Get-VersionInstalada $e
        $v = New-Object Windows.Forms.Label; $v.Text = $(if ($vi) { "Instalada: $vi" } else { 'No está en el kit' }); $v.ForeColor = $cTexto; $v.AutoSize = $false; $v.Size = New-Object Drawing.Size([int](400 * $K), [int](22 * $K)); $v.Location = New-Object Drawing.Point([int](16 * $K), [int](34 * $K))
        $es = New-Object Windows.Forms.Label; $es.Text = $(if ($e.Tipo -eq 'pagina') { 'Descarga manual (web oficial)' } else { 'Sin comprobar' }); $es.ForeColor = $cTexto; $es.AutoSize = $false; $es.TextAlign = 'MiddleLeft'; $es.Size = New-Object Drawing.Size([int](330 * $K), [int](46 * $K)); $es.Location = New-Object Drawing.Point([int](420 * $K), [int](8 * $K)); $es.Font = New-Object Drawing.Font($script:Fuentes.Semi, 9.5)
        $b = New-Object Windows.Forms.Button; $b.FlatStyle = 'Flat'; $b.Size = New-Object Drawing.Size([int](170 * $K), [int](34 * $K)); $b.Location = New-Object Drawing.Point([int](790 * $K), [int](14 * $K)); $b.Cursor = 'Hand'; $b.FlatAppearance.BorderColor = Get-Tc 'Borde'; $b.Font = New-Object Drawing.Font($script:Fuentes.Semi, 9.5)
        if ($e.Tipo -eq 'pagina') { $b.Text = 'Abrir web oficial'; $b.BackColor = $cFlat; $b.ForeColor = (Get-Tc 'Texto'); $b.Tag = $e; $b.Add_Click({ param($origen, $ev) Start-Process explorer.exe -ArgumentList $origen.Tag.Pagina }) }
        else { $b.Text = 'Reinstalar última'; $b.BackColor = $cFlat; $b.ForeColor = (Get-Tc 'Texto'); $b.Enabled = $false }
        $p.Controls.AddRange(@($n, $v, $es, $b)); $lista.Controls.Add($p)
        $S.Filas += [pscustomobject]@{ E = $e; Panel = $p; Estado = $es; Version = $v; Boton = $b; Instalada = $vi }
    }
    $Actualizar = {
        param($fila)
        $e = $fila.E; $r = $S.Remotos[$e.N]; if (-not $r -or $r.Error) { return }
        $fila.Boton.Enabled = $false; $btnComp.Enabled = $false; $btnTodo.Enabled = $false; $dlg.Cursor = 'WaitCursor'
        $res = Update-Herramienta $e $r { param($t) $fila.Estado.Text = $t; $fila.Estado.ForeColor = Get-Tc 'Acento'; [Windows.Forms.Application]::DoEvents() }
        $dlg.Cursor = 'Default'; $btnComp.Enabled = $true
        if ($res.Ok) { $fila.Estado.Text = 'Actualizada correctamente'; $fila.Estado.ForeColor = Get-Tc 'Ok'; $nv = Get-VersionInstalada $e; $fila.Version.Text = "Instalada: $nv" }
        else { $fila.Estado.Text = "No se actualizó: $($res.Mensaje)"; $fila.Estado.ForeColor = Get-Tc 'Fallo'; $fila.Boton.Enabled = $true }
        $lblEst.Text = "$($e.N): $($fila.Estado.Text)"
    }
    foreach ($f in $S.Filas) { if ($f.E.Tipo -ne 'pagina') { $f.Boton.Tag = $f; $f.Boton.Add_Click({ param($origen, $ev) & $Actualizar $origen.Tag }) } }
    $btnComp.Add_Click({
        $btnComp.Enabled = $false; $dlg.Cursor = 'WaitCursor'; $hay = 0; $verStore = Get-Versiones
        foreach ($f in $S.Filas) {
            if ($f.E.Tipo -eq 'pagina') { continue }
            $lblEst.Text = "Comprobando $($f.E.N)…"; [Windows.Forms.Application]::DoEvents()
            $r = Get-Remoto $f.E; $S.Remotos[$f.E.N] = $r
            if ($r.Error) { $f.Estado.Text = "No se pudo comprobar: $($r.Error)"; $f.Estado.ForeColor = Get-Tc 'Aviso'; continue }
            $hayNueva = $false
            if ($f.E.Repo) {
                $vi = ConvertTo-Numerico $f.Instalada
                if ($r.Version -and $vi) { $hayNueva = ($r.Version -gt $vi) } else { $hayNueva = $true }
                $f.Estado.Text = $(if ($hayNueva) { "Disponible: $($r.Etiqueta)" } else { "Al día ($($r.Etiqueta))" })
            }
            else {
                $reg = $verStore.($f.E.N)
                if ($reg -and $reg.Remoto -eq $r.Etiqueta) { $f.Estado.Text = "Al día (versión de la web: $($r.Etiqueta))" }
                elseif ($reg) { $hayNueva = $true; $f.Estado.Text = "Hay versión nueva en la web ($($r.Etiqueta))" }
                else { $hayNueva = $true; $f.Estado.Text = "Última en la web: $($r.Etiqueta). Se puede reinstalar para asegurarte" }
            }
            $f.Estado.ForeColor = if ($hayNueva) { Get-Tc 'Aviso' } else { Get-Tc 'Ok' }
            $f.Boton.Enabled = $true; $f.Boton.Text = $(if ($hayNueva) { 'Actualizar' } else { 'Reinstalar última' })
            if ($hayNueva) { $f.Boton.BackColor = $cAcento; $f.Boton.ForeColor = Get-Tc 'TextoAcento'; $hay++ }
        }
        $dlg.Cursor = 'Default'; $btnComp.Enabled = $true; $btnTodo.Enabled = ($hay -gt 0)
        $lblEst.Text = $(if ($hay) { "$hay herramienta(s) con actualización disponible." } else { 'Todo está al día (en las herramientas con descarga automática).' })
    })
    $btnTodo.Add_Click({ foreach ($f in $S.Filas) { if ($f.Boton.Enabled -and $f.Boton.Text -eq 'Actualizar') { & $Actualizar $f } }; $btnTodo.Enabled = $false })
    $btnResp.Add_Click({ $r = Join-Path $dirDatos 'Respaldo'; New-Item -ItemType Directory -Force $r | Out-Null; Start-Process explorer.exe -ArgumentList "`"$r`"" })
    [void]$dlg.ShowDialog($form)
}
