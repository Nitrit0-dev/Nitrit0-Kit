# =====================================================================
#  Limpiar_Espacio_Windows.ps1 - Limpieza profunda de Windows con estimación previa (Nitrit0)
#  Complementa a «Limpiar temporales»: aquí se ve CUÁNTO ocupa cada cosa ANTES de borrar, y se elige. Categorías:
#    · Miniaturas del Explorador (se regeneran)      · Registros CBS de Windows         · Caché de Delivery Optimization
#    · Volcados de memoria (los usan los técnicos para ver por qué hubo pantallazos azules; sin marcar)
#    · Registros del Visor de eventos (la historia del equipo; sin marcar, no se puede deshacer)
#    · Windows.old, la copia de la versión anterior de Windows (sin marcar: al quitarla ya no se puede volver atrás)
#    · Cachés de shaders de la GPU, caché de certificados, cachés de apps de la Tienda, logs ETL de Windows Update y restos de instaladores (se regeneran solos)
#    · Informes de errores de Windows (WER) y caché de instalación de drivers (INFCACHE.1): opcionales, sin marcar
#  Las estimaciones y los borrados no entran en enlaces de carpeta (junctions/symlinks), para no contar ni tocar lo que vive en otro sitio.
#  Parámetro: -SoloAnalizar (calcula y enseña los tamaños, no borra nada)
# =====================================================================
[CmdletBinding()]
param([switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$esAdmin = Test-EsAdmin
if (-not $esAdmin -and -not $SoloAnalizar) { Write-Output "$($E.Aviso) Hace falta administrador para limpiar. Ábrelo desde el kit o usa -SoloAnalizar."; exit 1 }
function Format-Tam([int64]$b) { if ($b -ge 1GB) { '{0:N1} GB' -f ($b / 1GB) } elseif ($b -ge 1MB) { '{0:N0} MB' -f ($b / 1MB) } else { '{0:N0} KB' -f ($b / 1KB) } }
$esEnlace = { param($i) [bool]($i.Attributes -band [IO.FileAttributes]::ReparsePoint) }
# Suma el tamaño de lo que coincide con cada ruta (admite comodines) sin entrar en enlaces de carpeta: en PowerShell 5.1 Get-ChildItem -Recurse los sigue y contaría (o borraría) lo de otro sitio.
function Get-TamArchivos($rutas) {
    $t = [int64]0
    foreach ($r in $rutas) {
        try {
            foreach ($i in @(Get-Item -Path $r -Force -ErrorAction SilentlyContinue)) {
                if (& $esEnlace $i) { continue }
                if (-not $i.PSIsContainer) { $t += $i.Length; continue }
                $pila = New-Object Collections.Generic.Stack[string]; $pila.Push($i.FullName)
                while ($pila.Count) {
                    foreach ($h in @(Get-ChildItem -LiteralPath $pila.Pop() -Force -ErrorAction SilentlyContinue)) {
                        if (& $esEnlace $h) { continue }
                        if ($h.PSIsContainer) { $pila.Push($h.FullName) } else { $t += $h.Length }
                    }
                }
            }
        } catch { }
    }
    $t
}
# Borra lo que coincide con cada ruta; un enlace de carpeta en la ruta se salta (no se sigue). shortcut: un enlace anidado dentro de una carpeta que se borra lo sigue Remove-Item -Recurse; en estas rutas no los hay, revisar si se añaden rutas nuevas.
function Remove-Rutas($rutas) { foreach ($r in $rutas) { foreach ($i in @(Get-Item -Path $r -Force -ErrorAction SilentlyContinue)) { if (-not (& $esEnlace $i)) { Remove-Item -LiteralPath $i.FullName -Recurse -Force -ErrorAction SilentlyContinue } } } }

$sys = $env:SystemRoot; $sd = $env:SystemDrive
$cat = @(
    [pscustomobject]@{ Id = 'miniaturas'; Nombre = 'Miniaturas del Explorador'; Aviso = 'Se regeneran solas al abrir carpetas con imágenes.'; Marcado = $true
        Rutas = @("$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db"); Tam = 0 }
    [pscustomobject]@{ Id = 'cbs'; Nombre = 'Registros CBS de Windows'; Aviso = 'Registros de las actualizaciones; Windows crea otros nuevos.'; Marcado = $true
        Rutas = @("$sys\Logs\CBS\*.log", "$sys\Logs\CBS\*.cab"); Tam = 0 }
    [pscustomobject]@{ Id = 'delivery'; Nombre = 'Caché de Delivery Optimization'; Aviso = 'Trozos de actualizaciones guardados para compartirlos; se vuelven a bajar si hace falta.'; Marcado = $true
        Rutas = @("$sys\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache\*"); Tam = 0 }
    [pscustomobject]@{ Id = 'shaders'; Nombre = 'Cachés de shaders de la GPU (DirectX, NVIDIA, AMD, Intel)'; Aviso = 'Se regeneran solas; la primera vez que abras un juego o programa gráfico puede tardar algo más.'; Marcado = $true
        Rutas = @("$env:LOCALAPPDATA\D3DSCache\*", "$env:LOCALAPPDATA\NVIDIA\DXCache\*", "$env:LOCALAPPDATA\NVIDIA\GLCache\*", "$env:LOCALAPPDATA\NVIDIA Corporation\NV_Cache\*", "$env:ProgramData\NVIDIA Corporation\NV_Cache\*", "$env:LOCALAPPDATA\AMD\DxCache\*", "$env:ProgramData\Intel\ShaderCache\*"); Tam = 0 }
    [pscustomobject]@{ Id = 'cripto'; Nombre = 'Caché de comprobación de certificados'; Aviso = 'Respuestas guardadas de comprobaciones de certificados (CRL/OCSP); Windows las vuelve a pedir.'; Marcado = $true
        Rutas = @("$env:USERPROFILE\AppData\LocalLow\Microsoft\CryptnetUrlCache\Content\*", "$env:USERPROFILE\AppData\LocalLow\Microsoft\CryptnetUrlCache\MetaData\*"); Tam = 0 }
    [pscustomobject]@{ Id = 'uwp'; Nombre = 'Cachés de apps de la Tienda (temporales)'; Aviso = 'Solo las carpetas temporales de cada app (INetCache, Temp, TempState). No se toca LocalState ni LocalCache, donde algunas apps guardan datos.'; Marcado = $true
        Rutas = @("$env:LOCALAPPDATA\Packages\*\AC\INetCache\*", "$env:LOCALAPPDATA\Packages\*\AC\Temp\*", "$env:LOCALAPPDATA\Packages\*\TempState\*"); Tam = 0 }
    [pscustomobject]@{ Id = 'etl'; Nombre = 'Logs ETL de Windows Update'; Aviso = 'Trazas técnicas de las actualizaciones; Windows crea otras nuevas. No se tocan los registros del Visor de eventos.'; Marcado = $true
        Rutas = @("$env:ProgramData\USOShared\Logs\*.etl", "$sys\Logs\WindowsUpdate\*.etl"); Tam = 0 }
    [pscustomobject]@{ Id = 'instaladores'; Nombre = 'Restos de instaladores'; Aviso = 'Temporales .tmp de Windows Installer y ficheros sueltos que dejan los instaladores de Visual C++ en la raíz del disco. No se toca ningún .msi ni .msp.'; Marcado = $true
        Rutas = @("$sys\Installer\*.tmp", "$sd\VC_RED.cab", "$sd\VC_RED.MSI", "$sd\eula*.txt", "$sd\globdata.ini", "$sd\install.ini", "$sd\vcredist.bmp"); Tam = 0 }
    [pscustomobject]@{ Id = 'wer'; Nombre = 'Informes de errores de Windows (WER)'; Aviso = 'Historial de fallos de programas que algunos técnicos consultan para diagnosticar. Quítalos solo si ya está resuelto.'; Marcado = $false
        Rutas = @("$env:ProgramData\Microsoft\Windows\WER\ReportArchive\*", "$env:ProgramData\Microsoft\Windows\WER\ReportQueue\*", "$env:ProgramData\Microsoft\Windows\WER\Temp\*", "$sys\pchealth\ERRORREP\*"); Tam = 0 }
    [pscustomobject]@{ Id = 'infcache'; Nombre = 'Caché de instalación de drivers (INFCACHE.1)'; Aviso = 'Solo si falla instalar una impresora o un driver («no se encuentra el archivo»). Windows la reconstruye al instalar el siguiente driver.'; Marcado = $false
        Rutas = @("$sys\INF\INFCACHE.1", "$sys\System32\DriverStore\INFCACHE.1"); Tam = 0 }
    [pscustomobject]@{ Id = 'volcados'; Nombre = 'Volcados de memoria (pantallazos azules)'; Aviso = 'Los técnicos los usan para saber por qué falló el equipo. Quítalos solo si ya está arreglado.'; Marcado = $false
        Rutas = @("$sys\Minidump\*", "$sys\MEMORY.DMP", "$sys\LiveKernelReports\*.dmp"); Tam = 0 }
    [pscustomobject]@{ Id = 'eventos'; Nombre = 'Registros del Visor de eventos'; Aviso = 'Es la historia de lo que ha pasado en el equipo y sirve para diagnosticar. NO se puede deshacer.'; Marcado = $false
        Rutas = @("$sys\System32\winevt\Logs\*.evtx"); Tam = 0 }
    [pscustomobject]@{ Id = 'windowsold'; Nombre = 'Windows.old (versión anterior de Windows)'; Aviso = 'Al quitarlo ya NO se puede volver a la versión anterior de Windows. Windows lo borra solo a los 10 días.'; Marcado = $false
        Rutas = @("$sd\Windows.old"); Tam = 0 }
)
# Perfiles de usuario sin uso en 90 días: ni el actual, ni los cargados, ni los de administración. Windows a veces pone LastUseTime a «ahora» sin que nadie inicie sesión,
# así que se exige además que NTUSER.DAT lleve más de 90 días sin tocarse (ante la duda, el perfil se deja).
function Get-PerfilesInactivos {
    $usuario = ''; try { $u = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName; if ($u) { $usuario = ($u -split '\\')[-1].ToLower() } } catch { }
    $limite = (Get-Date).AddDays(-90)
    foreach ($p in @(Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue | Where-Object { -not $_.Special -and -not $_.Loaded -and $_.LocalPath -like "$sd\Users\*" })) {
        $n = (Split-Path -Leaf $p.LocalPath).ToLower()
        if (($n -in @('administrator', 'administrador', 'default', 'public')) -or $n -like '*admin*' -or $n -eq $usuario) { continue }
        $nt = Get-Item -LiteralPath (Join-Path $p.LocalPath 'NTUSER.DAT') -Force -ErrorAction SilentlyContinue
        $ult = @($p.LastUseTime, $(if ($nt) { $nt.LastWriteTime })) | Where-Object { $_ } | Sort-Object -Descending | Select-Object -First 1
        if ($ult -and $ult -lt $limite -and (Test-Path -LiteralPath $p.LocalPath)) { [pscustomobject]@{ Perfil = $p; Nombre = $n; Ultimo = $ult } }
    }
}
# Archivos de OneDrive que están descargados del todo en el disco (los marcados como «solo en la nube» no ocupan). Devuelve carpeta -> bytes.
function Get-OneDriveLocal {
    $r = [ordered]@{}
    foreach ($u in @(Get-ChildItem -LiteralPath "$sd\Users" -Directory -Force -ErrorAction SilentlyContinue)) {
        foreach ($od in @(Get-ChildItem -LiteralPath $u.FullName -Directory -Filter 'OneDrive*' -Force -ErrorAction SilentlyContinue)) {
            $b = [int64]0; $pila = New-Object Collections.Generic.Stack[string]; $pila.Push($od.FullName)
            while ($pila.Count) {
                foreach ($h in @(Get-ChildItem -LiteralPath $pila.Pop() -Force -ErrorAction SilentlyContinue)) {
                    if ($h.PSIsContainer) { if (-not (& $esEnlace $h)) { $pila.Push($h.FullName) } }
                    elseif (-not ($h.Attributes -band 0x1000) -and -not ($h.Attributes -band 0x400000)) { $b += $h.Length }   # 0x1000 Offline, 0x400000 RecallOnDataAccess: ya están solo en la nube
                }
            }
            if ($b -gt 0) { $r[$od.FullName] = $b }
        }
    }
    $r
}
$perfiles = @(Get-PerfilesInactivos)
$onedrive = Get-OneDriveLocal
$cat += [pscustomobject]@{ Id = 'onedrive'; Nombre = 'OneDrive: liberar lo descargado (los archivos siguen en la nube)'; Aviso = 'Los archivos pasan a «solo en la nube» y se bajan al abrirlos, con conexión. Los que aún no se han subido no se tocan hasta que sincronicen.'; Marcado = $false
    Rutas = @(); Tam = 0; Datos = $onedrive }
$cat += [pscustomobject]@{ Id = 'perfiles'; Nombre = "Perfiles de usuario sin uso en 90 días ($($perfiles.Count))"; Aviso = "Se quitan PARA SIEMPRE con todos sus archivos: $((($perfiles | ForEach-Object { $_.Nombre }) -join ', ')). NO se puede deshacer."; Marcado = $false
    Rutas = @(); Tam = 0; Datos = $perfiles }
Write-Output "  $($E.Lupa) Calculando cuánto ocupa cada cosa (Windows.old puede tardar un poco)…"
foreach ($c in $cat) { $c.Tam = Get-TamArchivos $c.Rutas }
$od = $cat | Where-Object Id -eq 'onedrive'; $od.Tam = [int64]($od.Datos.Values | Measure-Object -Sum).Sum
$pf = $cat | Where-Object Id -eq 'perfiles'; foreach ($x in $pf.Datos) { $pf.Tam += Get-TamArchivos @([WildcardPattern]::Escape($x.Perfil.LocalPath)) }
$cat = @($cat | Where-Object { $_.Tam -gt 0 })
if (-not $cat.Count) { Write-Output "  $($E.OK) No hay nada de esto que limpiar."; Write-Log 'Limpiar_Espacio_Windows: nada'; return }
Write-Output "  $($E.Info) Se puede recuperar hasta $(Format-Tam ([int64]($cat | Measure-Object Tam -Sum).Sum)) en estas categorías (las sin marcar son opcionales y delicadas):"
foreach ($c in $cat) { Write-Output ("    {0} {1} · {2}" -f $(if ($c.Marcado) { '[propuesto]' } else { '[opcional] ' }), $c.Nombre, (Format-Tam $c.Tam)) }
if ($SoloAnalizar) { Write-Output "`n  $($E.Info) Solo análisis: no se ha borrado nada."; return }

function Show-Categorias($items) {
    $f = New-Object Windows.Forms.Form; $f.Text = 'Limpieza profunda'; $f.Size = New-Object Drawing.Size(1000, 520); $f.StartPosition = 'CenterScreen'; $f.TopMost = $true; $f.Font = New-Object Drawing.Font('Segoe UI', 9.5)
    $t = New-Object Windows.Forms.Label; $t.Text = 'Qué quieres limpiar'; $t.Font = New-Object Drawing.Font('Segoe UI Semibold', 14); $t.AutoSize = $true; $t.Location = New-Object Drawing.Point(20, 14)
    $lv = New-Object Windows.Forms.ListView; $lv.View = 'Details'; $lv.CheckBoxes = $true; $lv.FullRowSelect = $true; $lv.Location = New-Object Drawing.Point(20, 56); $lv.Size = New-Object Drawing.Size(944, 340); $lv.Anchor = 'Top,Bottom,Left,Right'
    foreach ($c in @(@('Qué es', 300), @('Ocupa', 90), @('Qué pasa si lo quitas', 530))) { [void]$lv.Columns.Add($c[0], $c[1]) }
    foreach ($x in $items) { $i = New-Object Windows.Forms.ListViewItem($x.Nombre); [void]$i.SubItems.Add((Format-Tam $x.Tam)); [void]$i.SubItems.Add($x.Aviso); $i.Tag = $x; $i.Checked = $x.Marcado; [void]$lv.Items.Add($i) }
    $ok = New-Object Windows.Forms.Button; $ok.Text = 'Limpiar lo marcado'; $ok.Size = New-Object Drawing.Size(200, 36); $ok.Location = New-Object Drawing.Point(764, 420); $ok.Anchor = 'Bottom,Right'; $ok.DialogResult = 'OK'
    $no = New-Object Windows.Forms.Button; $no.Text = 'No limpiar nada'; $no.Size = New-Object Drawing.Size(140, 36); $no.Location = New-Object Drawing.Point(614, 420); $no.Anchor = 'Bottom,Right'; $no.DialogResult = 'Cancel'
    $lbl = New-Object Windows.Forms.Label; $lbl.AutoSize = $true; $lbl.Location = New-Object Drawing.Point(22, 430); $lbl.Anchor = 'Bottom,Left'
    $cuenta = { $b = [int64]0; foreach ($it in $lv.CheckedItems) { $b += $it.Tag.Tam }; $lbl.Text = "Se liberarán unos $(Format-Tam $b)" }; & $cuenta; $lv.Add_ItemChecked($cuenta)
    $f.Controls.AddRange(@($t, $lv, $lbl, $ok, $no)); $f.AcceptButton = $ok; $f.CancelButton = $no
    if ($f.ShowDialog() -ne 'OK') { return @() }
    @($lv.CheckedItems | ForEach-Object { $_.Tag })
}
$elegidos = @(Show-Categorias $cat)
if (-not $elegidos.Count) { Exit-Kit 'Cancelado' 'No se limpia nada.' }
foreach ($d in @($elegidos | Where-Object { $_.Id -in 'windowsold', 'eventos', 'perfiles' })) {
    if (-not (Confirm-Accion "«$($d.Nombre)»`n`n$($d.Aviso)`n`n¿Seguro que quieres quitarlo?" 'Nitrit0 Kit' -Siempre)) { $elegidos = @($elegidos | Where-Object { $_.Id -ne $d.Id }); Write-Output "  $($E.Info) Se deja «$($d.Nombre)»." }
}
if (-not $elegidos.Count) { Exit-Kit 'Cancelado' 'No se limpia nada.' }

$libreAntes = (Get-PSDrive -Name ($sd.TrimEnd(':'))).Free
$errores = 0
[void](Start-OperacionSegura 'Limpiar espacio de Windows' -SinPuntoRestauracion)
foreach ($c in $elegidos) { Save-Informativo "Se limpió: $($c.Nombre)" 'No se puede deshacer (Windows.old, los registros de eventos y los informes WER no vuelven; las cachés se regeneran solas).' }
foreach ($c in $elegidos) {
    Write-Output "  $($E.Reloj) $($c.Nombre)…"
    try {
        switch ($c.Id) {
            'delivery' { try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop } catch { Remove-Rutas $c.Rutas } }
            'eventos' { foreach ($n in @(& (Join-Path $env:SystemRoot 'System32\wevtutil.exe') el 2>$null)) { if ($n -and $n -ne 'Security') { & (Join-Path $env:SystemRoot 'System32\wevtutil.exe') cl $n 2>&1 | Out-Null } } }
            'windowsold' {
                & (Join-Path $env:SystemRoot 'System32\icacls.exe') "$sd\Windows.old" /setowner '*S-1-5-32-544' /t /c /q 2>&1 | Out-Null   # takeown /d depende del idioma de Windows (s/y/j…); el SID de Administradores no
                & (Join-Path $env:SystemRoot 'System32\icacls.exe') "$sd\Windows.old" /grant "*S-1-5-32-544:(F)" /t /c /q 2>&1 | Out-Null
                Remove-Item -LiteralPath "$sd\Windows.old" -Recurse -Force -ErrorAction SilentlyContinue
            }
            'onedrive' {
                foreach ($carpeta in $c.Datos.Keys) { [void](Invoke-Proceso (Join-Path $env:SystemRoot 'System32\attrib.exe') "+U -P `"$carpeta\*`" /s /d" 900 'Liberar OneDrive' 30) }
            }
            'perfiles' {
                foreach ($x in $c.Datos) {
                    try { Remove-CimInstance -InputObject $x.Perfil -ErrorAction Stop; Write-Output "    $($E.OK) Perfil quitado: $($x.Nombre) (último uso $($x.Ultimo.ToString('dd/MM/yyyy')))." }
                    catch { $errores++; Write-Output "    $($E.Aviso) No se pudo quitar el perfil $($x.Nombre): $($_.Exception.Message)" }
                }
            }
            default { Remove-Rutas $c.Rutas }
        }
        Write-Log "Limpiar_Espacio_Windows: $($c.Nombre) ($(Format-Tam $c.Tam) estimados)"
    } catch { $errores++; Write-Output "  $($E.Aviso) $($c.Nombre): $($_.Exception.Message)" }
}
$liberado = [Math]::Max([int64]0, (Get-PSDrive -Name ($sd.TrimEnd(':'))).Free - $libreAntes)
Write-Output "`n$($E.OK) Limpieza terminada: se han liberado $(Format-Tam $liberado) en $sd (lo que había en uso por programas se ha dejado)."
if ($elegidos.Id -contains 'windowsold' -and (Test-Path "$sd\Windows.old")) { Write-Output "  $($E.Aviso) Windows.old no se ha podido quitar del todo (queda algo en uso). Reinicia y repite, o usa «Liberador de espacio en disco» de Windows." }
if ($errores) { Exit-Kit 'Error' "Limpieza terminada con $errores categoría(s) con error." }
