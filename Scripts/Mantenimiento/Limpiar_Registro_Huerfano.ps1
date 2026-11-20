# =====================================================================
#  Limpiar_Registro_Huerfano.ps1 - Restos de programas ya borrados (Nitrit0)
#  Busca entradas que apuntan a archivos que ya no existen: «Aplicaciones instaladas» sin programa, rutas de aplicación,
#  programas de inicio, caché de nombres (MuiCache), servicios y tareas programadas de programas desaparecidos, y además DLL compartidas,
#  archivos de ayuda, fuentes, reglas del cortafuegos, complementos del navegador (BHO) y extensiones sin tipo registrado.
#  No toca «Interfaz» (COM/TypeLib), instaladores ni eventos de sonido: poco beneficio para el riesgo.
#  NO toca claves de Windows ni de controladores, ni rutas de unidades que no están conectadas (un pendrive fuera no es un resto).
#  Cada cambio exporta antes su .reg a la misma cuarentena que «Desinstalador de apps»: se deshace con su modo de restaurar.
#  Parámetros: -SoloAnalizar (no borra nada) -Auto (sin ventana: borra solo lo de confianza Alta)
# =====================================================================
[CmdletBinding()]
param([switch]$SoloAnalizar, [switch]$Auto)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$RaizCuarentena = 'Nitrit0_Cuarentena'

$esAdmin = Test-EsAdmin
if (-not $esAdmin -and -not $SoloAnalizar) { Write-Output "$($E.Aviso) Hace falta administrador para borrar entradas de HKLM, servicios y tareas. Ábrelo desde el kit o usa -SoloAnalizar."; exit 1 }

# ---------------------------------------------------------------- Utilidades
function Convert-RegPath([string]$p) {
    $p = $p -replace '^Microsoft\.PowerShell\.Core\\Registry::', ''
    $p = $p -replace '^HKEY_LOCAL_MACHINE', 'HKLM' -replace '^HKEY_CURRENT_USER', 'HKCU'
    $p -replace '^(HK[A-Z]+):\\', '$1\'
}
# Ejecutable de una línea de órdenes (con o sin comillas). $null si no se puede saber con certeza: ahí no se propone nada.
function Get-ExeDeComando([string]$c) {
    if (-not $c) { return $null }
    # Variables del perfil (se expandirían al del administrador, no al dueño) y alias de la Store (WindowsApps): no se puede saber
    if ($c -match '(?i)%(USERPROFILE|APPDATA|LOCALAPPDATA|USERNAME|HOMEPATH|TEMP|TMP)%|\\WindowsApps\\') { return $null }
    $c = [Environment]::ExpandEnvironmentVariables($c.Trim())
    if ($c -match '(?i)^"?(msiexec|rundll32|cmd|powershell|wscript|cscript|regsvr32|mshta)(\.exe)?"?(\s|$)') { return $null }
    if ($c.StartsWith('"')) { $i = $c.IndexOf('"', 1); if ($i -gt 1) { $c = $c.Substring(1, $i - 1) } else { return $null } }
    elseif ($c -match '^(?<p>[A-Za-z]:\\.*?\.(exe|bat|cmd|com|scr|lnk))(\s|$)') { $c = $Matches['p'] }
    else { return $null }
    if ($c -notmatch '^[A-Za-z]:\\' -or $c -match '[%*?]') { return $null }
    $c
}
# $true solo si la unidad es fija, está lista y el archivo no existe: una unidad ausente (pendrive, red) no demuestra nada.
function Test-Ausente([string]$ruta) {
    if (-not $ruta -or $ruta -notmatch '^[A-Za-z]:\\') { return $false }
    try { $u = New-Object IO.DriveInfo($ruta.Substring(0, 2)); if (-not $u.IsReady -or $u.DriveType -ne 'Fixed') { return $false } } catch { return $false }
    -not (Test-Path -LiteralPath $ruta)
}
$restos = New-Object Collections.Generic.List[object]
function Add-Resto([string]$grupo, [string]$tipo, [string]$ruta, [string]$valor, [string]$det, [string]$conf) {
    $restos.Add([pscustomobject]@{ Grupo = $grupo; Tipo = $tipo; Ruta = $ruta; Valor = $valor; Detalle = $det; Conf = $conf })
}

# ---------------------------------------------------------------- Búsqueda
function Find-Huerfanos {
    # 1) Aplicaciones instaladas cuyo desinstalador y carpeta ya no existen
    Write-Output "  $($E.Lupa) Aplicaciones instaladas sin programa…"
    foreach ($r in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall') {
        foreach ($k in @(Get-ChildItem -LiteralPath $r -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
            if (-not $p -or -not $p.DisplayName -or $p.SystemComponent -eq 1 -or $p.WindowsInstaller -eq 1 -or [string]$p.UninstallString -match '(?i)msiexec') { continue }
            $exe = Get-ExeDeComando ([string]$p.UninstallString)
            if (-not $exe -or -not (Test-Ausente $exe)) { continue }
            $loc = ([string]$p.InstallLocation).Trim('"')
            if ($loc -and -not (Test-Ausente $loc) -and (Test-Path -LiteralPath $loc)) { continue }   # la carpeta sigue ahí: no es un resto seguro
            Add-Resto 'Aplicaciones instaladas' 'Registro' $k.PSPath '' "$($p.DisplayName): su desinstalador ya no existe" $(if ($loc) { 'Alta' } else { 'Media' })
        }
    }
    # 2) Rutas de aplicación y programas de inicio que apuntan a un archivo borrado
    Write-Output "  $($E.Lupa) Rutas de aplicación y programas de inicio…"
    foreach ($ap in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths') {
        foreach ($k in @(Get-ChildItem -LiteralPath $ap -ErrorAction SilentlyContinue)) {
            $v = [string](Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue).'(default)'
            $exe = Get-ExeDeComando $v   # si no se sabe con certeza cuál es el archivo, no se propone nada
            if ($exe -and (Test-Ausente $exe)) { Add-Resto 'Rutas de aplicación' 'Registro' $k.PSPath '' "$($k.PSChildName): $exe ya no existe" 'Alta' }
        }
    }
    foreach ($run in 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce') {
        $it = Get-Item -LiteralPath $run -ErrorAction SilentlyContinue; if (-not $it) { continue }
        foreach ($n in $it.GetValueNames()) {
            if (-not $n) { continue }
            $exe = Get-ExeDeComando ([string]$it.GetValue($n)); if ($exe -and (Test-Ausente $exe)) { Add-Resto 'Programas de inicio' 'ValorRegistro' $run $n "Se iniciaba con Windows pero $exe ya no existe" 'Alta' }
        }
    }
    # 3) Caché de nombres de programas (no afecta a nada: Windows la rehace)
    Write-Output "  $($E.Lupa) Caché de nombres de programas…"
    $mui = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache'
    $it = Get-Item -LiteralPath $mui -ErrorAction SilentlyContinue
    if ($it) { foreach ($n in $it.GetValueNames()) { $ruta = ($n -replace '\.(FriendlyAppName|ApplicationCompany)$', ''); if (Test-Ausente $ruta) { Add-Resto 'Caché de nombres (MuiCache)' 'ValorRegistro' $mui $n "$ruta ya no existe" 'Alta' } } }
    # 4) Servicios y tareas de programas desaparecidos: más delicado, vienen sin marcar
    Write-Output "  $($E.Lupa) Servicios y tareas programadas…"
    $win = $env:windir.TrimEnd('\')
    foreach ($s in @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { $_.PathName -and $_.ServiceType -in 'Own Process', 'Share Process' })) {
        $exe = Get-ExeDeComando ([string]$s.PathName); if (-not $exe -or $exe.StartsWith($win + '\', [StringComparison]::OrdinalIgnoreCase)) { continue }
        if (Test-Ausente $exe) { Add-Resto 'Servicios' 'Servicio' $s.Name '' "$($s.DisplayName): $exe ya no existe" 'Media' }
    }
    foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -notlike '\Microsoft\*' })) {
        foreach ($a in @($t.Actions)) {
            $exe = Get-ExeDeComando ([string]$a.Execute); if ($exe -and (Test-Ausente $exe)) { Add-Resto 'Tareas programadas' 'Tarea' ($t.TaskPath + $t.TaskName) '' "$($t.TaskName): $exe ya no existe" 'Media'; break }
        }
    }
    # 5) Categorías ampliadas (inspiradas en los limpiadores de registro clásicos; reglas propias, todas con comprobación de archivo ausente)
    Write-Output "  $($E.Lupa) DLL compartidas, ayuda, fuentes, cortafuegos, extensiones y complementos del navegador…"
    foreach ($sd in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SharedDLLs', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\SharedDLLs') {
        $it = Get-Item -LiteralPath $sd -ErrorAction SilentlyContinue; if (-not $it) { continue }
        foreach ($n in $it.GetValueNames()) { if ($n -match '^[A-Za-z]:\\' -and $n -notmatch '[%*?]' -and (Test-Ausente $n)) { Add-Resto 'DLL compartidas' 'ValorRegistro' $sd $n "$n ya no existe" 'Alta' } }
    }
    foreach ($h in 'HKLM:\SOFTWARE\Microsoft\Windows\Help', 'HKLM:\SOFTWARE\Microsoft\Windows\HTML Help') {
        $it = Get-Item -LiteralPath $h -ErrorAction SilentlyContinue; if (-not $it) { continue }
        foreach ($n in $it.GetValueNames()) {
            $d = [string]$it.GetValue($n); if (-not $n -or $d -notmatch '^[A-Za-z]:\\' -or $d -match '[%*?]') { continue }
            $f = Join-Path $d $n; if (Test-Ausente $f) { Add-Resto 'Archivos de ayuda' 'ValorRegistro' $h $n "$f ya no existe" 'Alta' }
        }
    }
    $fu = Get-Item -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts' -ErrorAction SilentlyContinue
    if ($fu) {
        foreach ($n in $fu.GetValueNames()) {
            $d = [string]$fu.GetValue($n); if (-not $n -or -not $d -or $d -match '[&|%*?]') { continue }
            $f = if ($d -match '^[A-Za-z]:\\') { $d } else { Join-Path "$env:windir\Fonts" $d }
            if (Test-Ausente $f) { Add-Resto 'Fuentes' 'ValorRegistro' $fu.PSPath $n "${n}: $f ya no existe" 'Media' }
        }
    }
    $fw = Get-Item -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules' -ErrorAction SilentlyContinue
    if ($fw) {
        foreach ($n in $fw.GetValueNames()) {
            $v = [string]$fw.GetValue($n); if ($v -notmatch '\|App=([^|]+)\|' -or $v -match '\|Svc=') { continue }
            $exe = Get-ExeDeComando $Matches[1]; if (-not $exe -or $exe.StartsWith($win + '\', [StringComparison]::OrdinalIgnoreCase)) { continue }
            if (Test-Ausente $exe) { $nm = if ($v -match '\|Name=([^|]+)\|') { $Matches[1] } else { $n }; Add-Resto 'Reglas del cortafuegos' 'ValorRegistro' $fw.PSPath $n "Regla «$nm»: $exe ya no existe" 'Media' }
        }
    }
    foreach ($b in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Browser Helper Objects', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\Browser Helper Objects') {
        foreach ($k in @(Get-ChildItem -LiteralPath $b -ErrorAction SilentlyContinue)) {
            $srv = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Classes\CLSID\$($k.PSChildName)\InprocServer32" -ErrorAction SilentlyContinue
            $dll = [Environment]::ExpandEnvironmentVariables(([string]$srv.'(default)').Trim('"'))
            if ($dll -match '^[A-Za-z]:\\' -and $dll -notmatch '[%*?]' -and (Test-Ausente $dll)) { Add-Resto 'Complementos del navegador (BHO)' 'Registro' $k.PSPath '' "$($k.PSChildName): $dll ya no existe" 'Media' }
        }
    }
    # Extensiones cuyo tipo de archivo (ProgID) ya no está registrado en ninguna parte
    foreach ($e in @(Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Classes' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\.[A-Za-z0-9_\-]+$' })) {
        $prog = [string](Get-ItemProperty -LiteralPath $e.PSPath -ErrorAction SilentlyContinue).'(default)'
        # Solo extensiones «vacías» (sin subclaves como OpenWithProgids) con un ProgID de nombre técnico: así no se tocan las de Windows ni nombres descriptivos
        if (-not $prog -or $prog -notmatch '^[A-Za-z0-9_.\-]+$' -or $prog -match '^(?i:CLSID)' -or $e.SubKeyCount -gt 0) { continue }
        if (-not (Test-Path -LiteralPath "HKLM:\SOFTWARE\Classes\$prog") -and -not (Test-Path -LiteralPath "HKCU:\Software\Classes\$prog")) { Add-Resto 'Extensiones de archivo no válidas' 'Registro' $e.PSPath '' "$($e.PSChildName) apunta al tipo «$prog», que ya no existe" 'Media' }
    }
}

# ---------------------------------------------------------------- Ventana de selección
function Show-Huerfanos($lista) {
    $f = New-Object Windows.Forms.Form; $f.Text = 'Restos en el registro'; $f.Size = New-Object Drawing.Size(1100, 700); $f.StartPosition = 'CenterScreen'; $f.TopMost = $true; $f.Font = New-Object Drawing.Font('Segoe UI', 9.5)
    $t = New-Object Windows.Forms.Label; $t.Text = 'Entradas que apuntan a algo que ya no existe'; $t.Font = New-Object Drawing.Font('Segoe UI Semibold', 14); $t.AutoSize = $true; $t.Location = New-Object Drawing.Point(20, 14)
    $s = New-Object Windows.Forms.Label; $s.Text = 'Marca lo que quieres limpiar. Antes de borrar cada una se guarda su copia (.reg) en la cuarentena y se puede restaurar. Servicios y tareas («Media») vienen sin marcar: revísalos.'; $s.AutoSize = $true; $s.Location = New-Object Drawing.Point(22, 46)
    $lv = New-Object Windows.Forms.ListView; $lv.View = 'Details'; $lv.CheckBoxes = $true; $lv.FullRowSelect = $true; $lv.ShowGroups = $true; $lv.Location = New-Object Drawing.Point(20, 80); $lv.Size = New-Object Drawing.Size(1044, 500); $lv.Anchor = 'Top,Bottom,Left,Right'
    foreach ($c in @(@('Qué es', 560), @('Dónde', 380), @('Confianza', 80))) { [void]$lv.Columns.Add($c[0], $c[1]) }
    $grupos = @{}
    foreach ($r in $lista) {
        if (-not $grupos.ContainsKey($r.Grupo)) { $grupos[$r.Grupo] = New-Object Windows.Forms.ListViewGroup($r.Grupo); [void]$lv.Groups.Add($grupos[$r.Grupo]) }
        $i = New-Object Windows.Forms.ListViewItem($r.Detalle); [void]$i.SubItems.Add(($r.Ruta + $(if ($r.Valor) { "  [$($r.Valor)]" } else { '' }))); [void]$i.SubItems.Add($r.Conf)
        $i.Group = $grupos[$r.Grupo]; $i.Tag = $r; $i.Checked = ($r.Conf -eq 'Alta'); [void]$lv.Items.Add($i)
    }
    $ok = New-Object Windows.Forms.Button; $ok.Text = 'Limpiar lo marcado'; $ok.Size = New-Object Drawing.Size(220, 36); $ok.Location = New-Object Drawing.Point(844, 600); $ok.Anchor = 'Bottom,Right'; $ok.DialogResult = 'OK'
    $no = New-Object Windows.Forms.Button; $no.Text = 'No borrar nada'; $no.Size = New-Object Drawing.Size(130, 36); $no.Location = New-Object Drawing.Point(704, 600); $no.Anchor = 'Bottom,Right'; $no.DialogResult = 'Cancel'
    $lbl = New-Object Windows.Forms.Label; $lbl.AutoSize = $true; $lbl.Location = New-Object Drawing.Point(22, 610); $lbl.Anchor = 'Bottom,Left'
    $cuenta = { $lbl.Text = "$(@($lv.CheckedItems).Count) de $($lv.Items.Count) marcados" }; & $cuenta; $lv.Add_ItemChecked($cuenta)
    $f.Controls.AddRange(@($t, $s, $lv, $lbl, $ok, $no)); $f.AcceptButton = $ok; $f.CancelButton = $no
    if ($f.ShowDialog() -ne 'OK') { return @() }
    @($lv.CheckedItems | ForEach-Object { $_.Tag })
}

# ---------------------------------------------------------------- Flujo principal
Write-Output "========================================================"
Write-Output "  $($E.Cohete) LIMPIAR REGISTRO: RESTOS DE PROGRAMAS BORRADOS"
Write-Output "========================================================"
Find-Huerfanos
if (-not $restos.Count) { Write-Output "`n  $($E.OK) No hay entradas huérfanas: el registro está limpio en lo que este script revisa."; Write-Log 'Limpiar_Registro_Huerfano: sin restos'; return }
Write-Output "`n  $($E.Info) Encontradas $($restos.Count) entradas que apuntan a algo que ya no existe:"
foreach ($g in ($restos | Group-Object Grupo)) { Write-Output "    - $($g.Name): $($g.Count)" }
if ($SoloAnalizar) { foreach ($r in $restos) { Write-Output "    [$($r.Conf)] $($r.Grupo): $($r.Detalle)" }; Write-Output "`n  $($E.Info) Solo análisis: no se ha borrado nada."; return }

$elegidos = if ($Auto) { @($restos | Where-Object { $_.Conf -eq 'Alta' }) } else { @(Show-Huerfanos $restos) }
if (-not $elegidos.Count) { Write-Output "  $($E.Aviso) No se borra nada."; return }

try { Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue; Checkpoint-Computer -Description 'Nitrit0 - antes de limpiar el registro' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop; Write-Output "  $($E.OK) Punto de restauración creado." }
catch { Write-Output "  $($E.Aviso) No se creó punto de restauración (Windows solo permite uno cada 24 h). La copia en .reg de cada entrada sí se guarda." }

$sesion = (Get-Date -Format 'yyyyMMdd_HHmmss') + '_Registro'
$q = Join-Path (Join-Path $env:ProgramData $RaizCuarentena) $sesion
New-Item -ItemType Directory -Force (Join-Path $q 'Registro') | Out-Null
$ok = 0; $fallos = 0; $n = 0
$exportadas = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($x in $elegidos) {
    $n++
    try {
        switch ($x.Tipo) {
            { $_ -in 'Registro', 'ValorRegistro' } {
                # Una sola copia por clave, hecha antes de tocar ninguno de sus valores (así guarda el estado original completo)
                if ($exportadas.Add($x.Ruta)) {
                    & reg.exe export (Convert-RegPath $x.Ruta) ("$q\Registro\{0:D3}.reg" -f $n) /y 2>&1 | Out-Null
                    if ($LASTEXITCODE -ne 0) { [void]$exportadas.Remove($x.Ruta); throw 'no se pudo guardar la copia, no se borra' }
                }
                if ($x.Tipo -eq 'Registro') { Remove-Item -LiteralPath $x.Ruta -Recurse -Force -ErrorAction Stop } else { Remove-ItemProperty -LiteralPath $x.Ruta -Name $x.Valor -ErrorAction Stop }
            }
            'Servicio' {
                & reg.exe export "HKLM\SYSTEM\CurrentControlSet\Services\$($x.Ruta)" ("$q\Registro\{0:D3}_servicio.reg" -f $n) /y 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { throw 'no se pudo guardar la copia, no se borra' }
                Stop-Service -Name $x.Ruta -Force -ErrorAction SilentlyContinue; & sc.exe delete $x.Ruta | Out-Null; if ($LASTEXITCODE -ne 0) { throw "sc delete código $LASTEXITCODE" }
            }
            'Tarea' {
                $tn = Split-Path $x.Ruta -Leaf; $path = $x.Ruta.Substring(0, $x.Ruta.Length - $tn.Length)
                Export-ScheduledTask -TaskName $tn -TaskPath $path | Out-File ("$q\Registro\{0:D3}_tarea.xml" -f $n) -Encoding UTF8 -ErrorAction Stop
                Unregister-ScheduledTask -TaskName $tn -TaskPath $path -Confirm:$false -ErrorAction Stop
            }
        }
        $ok++; Write-Output "    $($E.OK) $($x.Grupo): $($x.Detalle)"
    } catch { $fallos++; Write-Output "    $($E.Error) $($x.Grupo): $($x.Detalle) -> $($_.Exception.Message)" }
}
Write-Log "Limpiar_Registro_Huerfano: sesión $sesion - $ok limpiadas, $fallos con error"
Write-Output "`n  $($E.OK) Limpiadas $ok entradas ($fallos con error). Copia en: $q"
Write-Output "  $($E.Info) Para deshacerlo: «Desinstalador de apps» > restaurar desde la cuarentena (elige la sesión $sesion)."
if ($fallos) { exit 1 }
