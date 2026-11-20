# =====================================================================
#  Desinstalar_Total.ps1 - Desinstalador completo (Nitrit0)
#  0) Puedes marcar varios programas a la vez: se confirma una sola vez y se van quitando uno tras otro.
#  1) Desinstala el programa con su desinstalador oficial (silencioso si es posible).
#  2) Busca lo que deja atrás: carpetas, claves de registro, servicios, tareas, reglas de firewall,
#     programas de inicio y accesos directos.
#  3) Te muestra los restos para que marques lo que se borra, y lo manda a una CUARENTENA reversible
#     (carpetas movidas, registro exportado en .reg). Así, si algo sale mal, se puede restaurar.
#  Parámetros: -Nombre "texto","otro" (uno o varios) -Auto (sin ventanas) -Datos (borra también datos y configuración)
#              -SoloAnalizar (no borra nada) -SinDesinstalar -Forzar (componentes compartidos)
#              -Restaurar (deshace una limpieza desde la cuarentena) -VaciarCuarentena
# =====================================================================
[CmdletBinding()]
param([string[]]$Nombre, [switch]$Auto, [switch]$Datos, [switch]$SoloAnalizar, [switch]$SinDesinstalar, [switch]$Forzar, [switch]$Restaurar, [switch]$VaciarCuarentena)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$RaizCuarentena = 'Nitrit0_Cuarentena'

# ---------------------------------------------------------------- Tema (el mismo que el lanzador)
$oscuro = $true; try { $aj = Join-Path (Get-KitDatos) 'Ajustes.json'; if (Test-Path -LiteralPath $aj) { $oscuro = ((Get-Content -LiteralPath $aj -Raw -Encoding UTF8 | ConvertFrom-Json).Tema -ne 'claro') } } catch { }
$P = if ($oscuro) { @{ Fondo = '#12151C'; Panel = '#1E2330'; Texto = '#F0F3FA'; Suave = '#9AA3B8'; Acento = '#2BC4D8'; TAc = '#06222A'; Boton = '#272D3F'; Aviso = '#FFB020' } } else { @{ Fondo = '#F3F5F9'; Panel = '#FFFFFF'; Texto = '#1B2230'; Suave = '#4F5A70'; Acento = '#087F91'; TAc = '#FFFFFF'; Boton = '#E3E8F1'; Aviso = '#9A5F00' } }
function C($k) { [Drawing.ColorTranslator]::FromHtml($P[$k]) }
function Nuevo-Boton($t, $x, $y, $w, $acento) { $b = New-Object Windows.Forms.Button; $b.Text = $t; $b.Location = New-Object Drawing.Point($x, $y); $b.Size = New-Object Drawing.Size($w, 36); $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderColor = (C 'Suave'); $b.Cursor = 'Hand'; $b.Font = New-Object Drawing.Font('Segoe UI Semibold', 9.5); if ($acento) { $b.BackColor = (C 'Acento'); $b.ForeColor = (C 'TAc') } else { $b.BackColor = (C 'Boton'); $b.ForeColor = (C 'Texto') }; $b }

# ---------------------------------------------------------------- Utilidades de rutas y registro
function Convert-RegPath([string]$p) {
    $p = $p -replace '^Microsoft\.PowerShell\.Core\\Registry::', ''
    $p = $p -replace '^HKEY_LOCAL_MACHINE', 'HKLM' -replace '^HKEY_CURRENT_USER', 'HKCU' -replace '^HKEY_CLASSES_ROOT', 'HKCR'
    $p -replace '^(HK[A-Z]+):\\', '$1\'
}
function Test-RutaProtegida([string]$r) {
    if (-not $r) { return $true }
    $x = $r.TrimEnd('\').ToLowerInvariant()
    if ($x -match '^[a-z]:?$') { return $true }
    $prot = @($env:SystemDrive, $env:windir, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, (Split-Path $env:USERPROFILE -Parent), $env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA,
              (Join-Path $env:LOCALAPPDATA 'Programs'), (Join-Path $env:ProgramFiles 'Common Files'), (Join-Path ${env:ProgramFiles(x86)} 'Common Files'), (Join-Path $env:ProgramFiles 'WindowsApps'),
              (Join-Path $env:USERPROFILE 'Desktop'), (Join-Path $env:USERPROFILE 'Documents'), (Join-Path $env:LOCALAPPDATA 'Packages')) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\').ToLowerInvariant() }
    if ($prot -contains $x) { return $true }
    if ($x -like ($env:windir.TrimEnd('\').ToLowerInvariant() + '\*')) { return $true }
    $hoja = (Split-Path $x -Leaf)
    if ($hoja -in 'microsoft', 'windows', 'common files', 'windowsapps', 'system32', 'microsoft.net', 'windows nt', 'internet explorer', 'windows defender', 'windowspowershell', 'packages', 'temp', 'programs', 'desktop', 'documents', 'modifiableapps', 'installer') { return $true }
    $false
}
$Genericos = @('microsoft', 'windows', 'google', 'apple', 'adobe', 'intel', 'amd', 'nvidia', 'realtek', 'oracle', 'java', 'python', 'program', 'programs', 'software', 'setup', 'update', 'updater', 'driver', 'drivers', 'tools', 'common')
function Get-NombreLimpio([string]$n) { $x = $n -replace '\(.*?\)', '' -replace '(?i)\b(x64|x86|64-bit|32-bit|64 bits|32 bits|64bit|32bit)\b', '' -replace '(?i)\bv?\d+(\.\d+)+\b', '' -replace '[\-–,]\s*$', ''; ($x -replace '\s+', ' ').Trim() }
function Get-EditorLimpio([string]$e) { if (-not $e) { return '' }; (($e -replace '(?i),?\s*\b(inc|ltd|llc|gmbh|corp|corporation|s\.?a\.?|software|limited|co|company)\b\.?', '' -replace '[,\.]+$', '') -replace '\s+', ' ').Trim() }

# ---------------------------------------------------------------- Lista de programas instalados
function Get-Programas {
    $res = New-Object Collections.Generic.List[object]
    $claves = @(@{ R = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'; A = 'Equipo' }, @{ R = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'; A = 'Equipo (32 bits)' }, @{ R = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'; A = 'Usuario' })
    foreach ($c in $claves) {
        foreach ($i in @(Get-ItemProperty -Path $c.R -ErrorAction SilentlyContinue)) {
            if (-not $i.DisplayName -or $i.SystemComponent -eq 1 -or $i.ParentKeyName -or -not ($i.UninstallString -or $i.QuietUninstallString)) { continue }
            $loc = $null; if ($i.InstallLocation) { $loc = ([string]$i.InstallLocation).Trim('"', ' ', '\') }
            if (-not $loc -and $i.DisplayIcon) { $ic = (([string]$i.DisplayIcon) -replace ',\s*-?\d+$', '').Trim('"'); if ($ic -match '(?i)\.exe$' -and (Test-Path -LiteralPath $ic)) { $loc = Split-Path $ic -Parent } }
            if ($loc -and ((Test-RutaProtegida $loc) -or -not (Test-Path -LiteralPath $loc))) { $loc = $null }
            $res.Add([pscustomobject]@{ Nombre = [string]$i.DisplayName; Editor = [string]$i.Publisher; Version = [string]$i.DisplayVersion; Ubicacion = $loc; Desinst = [string]$i.UninstallString; Silencioso = [string]$i.QuietUninstallString
                    Clave = $i.PSPath; Ambito = $c.A; Tipo = 'Programa'; Id = $i.PSChildName; MB = $(if ($i.EstimatedSize) { [math]::Round($i.EstimatedSize / 1024) } else { 0 }) })
        }
    }
    try {
        foreach ($a in @(Get-AppxPackage -ErrorAction Stop | Where-Object { -not $_.IsFramework -and -not $_.NonRemovable -and $_.SignatureKind -eq 'Store' })) {
            $res.Add([pscustomobject]@{ Nombre = [string]$a.Name; Editor = ([string]$a.Publisher -replace '^CN=([^,]+).*', '$1'); Version = [string]$a.Version; Ubicacion = $null; Desinst = ''; Silencioso = ''; Clave = $null; Ambito = 'Tienda'; Tipo = 'Tienda'; Id = [string]$a.PackageFullName; Familia = [string]$a.PackageFamilyName; MB = 0 })
        }
    } catch { }
    @($res | Sort-Object Nombre, Version -Unique | Sort-Object Nombre)
}

# ---------------------------------------------------------------- Escaneo de restos
$script:Restos = $null
function Add-Resto([string]$tipo, [string]$ruta, [string]$conf, [bool]$datos, [string]$det, [string]$valor) {
    if (@($script:Restos | Where-Object { $_.Tipo -eq $tipo -and $_.Ruta -eq $ruta -and $_.Valor -eq $valor }).Count) { return }
    $script:Restos.Add([pscustomobject]@{ Tipo = $tipo; Ruta = $ruta; Conf = $conf; Datos = $datos; Detalle = $det; Valor = $valor })
}
function Find-Restos($p) {
    $script:Restos = New-Object Collections.Generic.List[object]
    $limpio = Get-NombreLimpio $p.Nombre; $editor = Get-EditorLimpio $p.Editor
    $sinEditor = $limpio; if ($editor -and $limpio -like "$editor *") { $sinEditor = $limpio.Substring($editor.Length).Trim() }
    $nombres = @($limpio, ($limpio -replace '\s', ''), ($limpio -replace '[^\w]', ''), $sinEditor) | Where-Object { $_ -and $_.Length -ge 4 -and $Genericos -notcontains $_.ToLowerInvariant() } | Select-Object -Unique
    $loc = $p.Ubicacion

    # --- Carpetas
    $perfiles = @(Get-ChildItem (Split-Path $env:USERPROFILE -Parent) -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin 'Public', 'Default', 'Default User', 'All Users' })
    $raices = @(@{ R = $env:ProgramFiles; D = $false }, @{ R = ${env:ProgramFiles(x86)}; D = $false }, @{ R = $env:ProgramData; D = $true }, @{ R = (Join-Path $env:LOCALAPPDATA 'Programs'); D = $false })
    foreach ($pf in $perfiles) { $raices += @{ R = (Join-Path $pf.FullName 'AppData\Roaming'); D = $true }; $raices += @{ R = (Join-Path $pf.FullName 'AppData\Local'); D = $true }; $raices += @{ R = (Join-Path $pf.FullName 'AppData\Local\Programs'); D = $false } }
    if ($loc) { Add-Resto 'Carpeta' $loc 'Alta' $false 'Carpeta de instalación' '' }
    foreach ($r in $raices) {
        if (-not $r.R -or -not (Test-Path -LiteralPath $r.R)) { continue }
        foreach ($n in $nombres) {
            $cands = @((Join-Path $r.R $n)); if ($editor) { $cands += (Join-Path (Join-Path $r.R $editor) $n) }
            foreach ($c in $cands) { if ((Test-Path -LiteralPath $c) -and -not (Test-RutaProtegida $c)) { Add-Resto 'Carpeta' $c 'Alta' $r.D $(if ($r.D) { 'Datos y configuración' } else { 'Archivos del programa' }) '' } }
        }
        if ($limpio.Length -ge 6) {
            foreach ($d in @(Get-ChildItem -LiteralPath $r.R -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$limpio*" })) { if (-not (Test-RutaProtegida $d.FullName)) { Add-Resto 'Carpeta' $d.FullName 'Media' $r.D 'Nombre parecido (revisar)' '' } }
        }
    }
    if ($p.Familia) { foreach ($pf in $perfiles) { $d = Join-Path $pf.FullName "AppData\Local\Packages\$($p.Familia)"; if (Test-Path -LiteralPath $d) { Add-Resto 'Carpeta' $d 'Alta' $true 'Datos de la app de la Tienda' '' } } }

    # --- Accesos directos (menú Inicio y escritorio)
    try {
        $ws = New-Object -ComObject WScript.Shell
        $dirsLnk = @((Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'), (Join-Path $env:PUBLIC 'Desktop')); foreach ($pf in $perfiles) { $dirsLnk += (Join-Path $pf.FullName 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs'); $dirsLnk += (Join-Path $pf.FullName 'Desktop') }
        foreach ($d in $dirsLnk) {
            if (-not (Test-Path -LiteralPath $d)) { continue }
            foreach ($l in @(Get-ChildItem -LiteralPath $d -Filter *.lnk -Recurse -ErrorAction SilentlyContinue)) {
                $t = ''; try { $t = $ws.CreateShortcut($l.FullName).TargetPath } catch { }
                $porRuta = ($loc -and $t -and $t.StartsWith($loc, [StringComparison]::OrdinalIgnoreCase)); $porNombre = ($nombres -contains $l.BaseName)
                if ($porRuta -or $porNombre) { Add-Resto 'Archivo' $l.FullName 'Alta' $false 'Acceso directo' '' }
            }
            foreach ($n in $nombres) { foreach ($c in @((Join-Path $d $n), $(if ($editor) { Join-Path (Join-Path $d $editor) $n }))) { if ($c -and (Test-Path -LiteralPath $c -PathType Container) -and -not (Test-RutaProtegida $c)) { Add-Resto 'Carpeta' $c 'Alta' $false 'Carpeta del menú Inicio' '' } } }
        }
    } catch { }

    # --- Registro
    $raicesReg = @('HKCU:\SOFTWARE', 'HKLM:\SOFTWARE', 'HKLM:\SOFTWARE\WOW6432Node')
    $malasClaves = @('microsoft', 'windows', 'classes', 'policies', 'clients', 'registeredapplications', 'wow6432node', 'google', 'intel', 'adobe', 'apple', 'nvidia', 'amd', 'realtek', 'oracle', 'javasoft', 'python', 'mozilla')
    foreach ($rr in $raicesReg) {
        foreach ($n in $nombres) {
            $cands = @((Join-Path $rr $n)); if ($editor) { $cands += (Join-Path (Join-Path $rr $editor) $n) }
            foreach ($c in $cands) { if ((Test-Path -LiteralPath $c) -and ($malasClaves -notcontains (Split-Path $c -Leaf).ToLowerInvariant())) { Add-Resto 'Registro' $c 'Alta' $true 'Configuración en el registro' '' } }
        }
        if ($editor -and $malasClaves -notcontains $editor.ToLowerInvariant()) {
            $pk = Join-Path $rr $editor
            if (Test-Path -LiteralPath $pk) {
                $hijos = @(Get-ChildItem -LiteralPath $pk -ErrorAction SilentlyContinue); $propios = @($hijos | Where-Object { $nombres -contains $_.PSChildName })
                $vals = @((Get-Item -LiteralPath $pk).GetValueNames())
                if ($hijos.Count -gt 0 -and $hijos.Count -eq $propios.Count -and -not $vals.Count) { Add-Resto 'Registro' $pk 'Alta' $true 'Clave del fabricante (solo contenía esta app)' '' }
                elseif ($hijos.Count -eq 0 -and -not $vals.Count) { Add-Resto 'Registro' $pk 'Alta' $true 'Clave del fabricante vacía' '' }
            }
        }
    }
    if ($p.Clave -and (Test-Path -LiteralPath $p.Clave)) { Add-Resto 'Registro' $p.Clave 'Alta' $false 'Entrada de «Aplicaciones instaladas» que dejó el desinstalador' '' }
    # App Paths y Run
    if ($loc) {
        foreach ($ap in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths') {
            foreach ($k in @(Get-ChildItem -LiteralPath $ap -ErrorAction SilentlyContinue)) { $v = [string](Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue).'(default)'; if ($v -and $v.Trim('"').StartsWith($loc, [StringComparison]::OrdinalIgnoreCase)) { Add-Resto 'Registro' $k.PSPath 'Alta' $false 'Ruta de aplicación' '' } }
        }
    }
    foreach ($run in 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run') {
        if (-not (Test-Path -LiteralPath $run)) { continue }
        $it = Get-ItemProperty -LiteralPath $run -ErrorAction SilentlyContinue
        foreach ($pn in $it.PSObject.Properties) { if ($pn.Name -like 'PS*') { continue }; $v = [string]$pn.Value
            if (($loc -and $v -like "*$loc*") -or ($nombres | Where-Object { $v -match [regex]::Escape("\$_\") })) { Add-Resto 'ValorRegistro' $run 'Alta' $false "Se inicia con Windows: $($pn.Name)" $pn.Name } }
    }

    # --- Servicios, tareas y firewall (solo con la ruta de instalación conocida o nombre exacto)
    try { foreach ($s in @(Get-CimInstance Win32_Service -ErrorAction Stop)) { if ($loc -and $s.PathName -and $s.PathName.Trim('"') -like "$loc*") { Add-Resto 'Servicio' $s.Name 'Alta' $false "Servicio: $($s.DisplayName)" '' } } } catch { }
    try {
        foreach ($t in @(Get-ScheduledTask -ErrorAction Stop)) {
            $ex = ($t.Actions | ForEach-Object { $_.Execute }) -join ' '
            $porRuta = ($loc -and $ex -and $ex.Trim('"') -like "$loc*"); $porNombre = ($nombres -contains $t.TaskName)
            if ($porRuta -or $porNombre) { Add-Resto 'Tarea' ($t.TaskPath + $t.TaskName) 'Alta' $false "Tarea programada: $($t.TaskName)" '' }
        }
    } catch { }
    if ($loc) {
        try { foreach ($f in @(Get-NetFirewallApplicationFilter -ErrorAction Stop | Where-Object { $_.Program -and $_.Program -like "$loc*" })) { $reg = $f | Get-NetFirewallRule -ErrorAction SilentlyContinue; if ($reg) { Add-Resto 'Firewall' $reg.Name 'Alta' $false "Regla de firewall: $($reg.DisplayName)" '' } } } catch { }
    }
    $script:Restos.ToArray()
}

# ---------------------------------------------------------------- Desinstalación oficial
function Split-Comando([string]$c) {
    $c = $c.Trim()
    if ($c.StartsWith('"')) { $i = $c.IndexOf('"', 1); if ($i -gt 0) { return @($c.Substring(1, $i - 1), $c.Substring($i + 1).Trim()) } }
    if ($c -match '(?i)^(?<e>.*?\.exe)\s*(?<a>.*)$') { return @($Matches.e.Trim('"'), $Matches.a) }
    @($c, '')
}
# ¿El ejecutable lleva la firma de un tipo de instalador conocido? Se mira el principio del archivo (los desinstaladores son pequeños).
function Test-Instalador([string]$exe, [string]$marca) {
    try {
        if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { return $false }
        $fs = [IO.File]::OpenRead($exe)
        try { $n = [int][Math]::Min($fs.Length, 3MB); $b = New-Object byte[] $n; [void]$fs.Read($b, 0, $n) } finally { $fs.Dispose() }
        ([Text.Encoding]::GetEncoding(28591).GetString($b)).Contains($marca)
    } catch { $false }
}
# Cómo se desinstala un programa: silencioso siempre que se pueda (orden silenciosa del programa, MSI, Inno Setup, NSIS); si no, con su ventana.
function Get-ModoDesinst($p) {
    if ($p.Tipo -eq 'Tienda') { return [pscustomobject]@{ Exe = ''; Args = ''; Interactivo = $false } }
    $cmd = if ($p.Silencioso) { $p.Silencioso } else { $p.Desinst }
    if ($cmd -match '(?i)msiexec' -and $cmd -match '\{[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}\}') { return [pscustomobject]@{ Exe = 'msiexec.exe'; Args = "/x $($Matches[0]) /qn /norestart"; Interactivo = $false } }
    $s = Split-Comando $cmd; $exe = $s[0]; $argu = $s[1]; $inter = $false
    if (-not $p.Silencioso) {
        if ((Split-Path $exe -Leaf) -match '(?i)^unins\d+\.exe$' -or (Test-Instalador $exe 'Inno Setup')) { $argu = "$argu /VERYSILENT /NORESTART /SUPPRESSMSGBOXES" }
        elseif (Test-Instalador $exe 'Nullsoft') { $argu = "$argu /S" }
        else { $inter = $true }
    }
    [pscustomobject]@{ Exe = $exe; Args = $argu; Interactivo = $inter }
}
function Invoke-Desinstalacion($p) {
    Write-Host "  $($E.Reloj) Desinstalando «$($p.Nombre)»…"
    if ($p.Ubicacion) {
        foreach ($pr in @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($p.Ubicacion, [StringComparison]::OrdinalIgnoreCase) })) { try { Stop-Process -Id $pr.Id -Force -ErrorAction Stop; Write-Host "    proceso cerrado: $($pr.ProcessName)" } catch { } }
    }
    if ($p.Tipo -eq 'Tienda') {
        try { Get-AppxPackage -AllUsers -Name $p.Nombre -ErrorAction Stop | Remove-AppxPackage -AllUsers -ErrorAction Stop; Write-Host "  $($E.OK) App de la Tienda desinstalada."; return $true } catch { Write-Host "  $($E.Aviso) No se pudo quitar con Remove-AppxPackage: $($_.Exception.Message)"; return $false }
    }
    $modo = Get-ModoDesinst $p; $exe = $modo.Exe; $argu = $modo.Args; $interactivo = $modo.Interactivo
    Write-Host "    $(if ($interactivo) { 'Se abrirá el desinstalador del programa: sigue sus pasos (máx. 20 min).' } else { 'Modo silencioso (máx. 20 min).' })"
    try {
        $sp = @{ FilePath = $exe; PassThru = $true }; if ($argu) { $sp.ArgumentList = $argu }; if (-not $interactivo) { $sp.WindowStyle = 'Hidden' }
        $pr = Start-Process @sp
        if (-not $pr.WaitForExit(1200000)) { Stop-Process -Id $pr.Id -Force -ErrorAction SilentlyContinue; Write-Host "  $($E.Aviso) El desinstalador tardó más de 20 min y se canceló."; return $false }
        Write-Host "    El desinstalador terminó (código $($pr.ExitCode))."
    } catch { Write-Host "  $($E.Aviso) No se pudo ejecutar el desinstalador: $($_.Exception.Message)"; return $false }
    if ($p.Clave) { for ($i = 0; $i -lt 30 -and (Test-Path -LiteralPath $p.Clave); $i++) { Start-Sleep -Seconds 2 } }   # algunos desinstaladores terminan en un proceso aparte
    if ($p.Clave -and (Test-Path -LiteralPath $p.Clave)) { Write-Host "  $($E.Aviso) El programa sigue figurando como instalado (se limpiará como resto)." } else { Write-Host "  $($E.OK) Desinstalador oficial completado." }
    $true
}

# ---------------------------------------------------------------- Cuarentena
function Get-DirCuarentena([string]$sesion, [string]$ruta) {
    $unidad = if ($ruta -match '^[A-Za-z]:') { $ruta.Substring(0, 2) } else { $env:SystemDrive }
    $base = if ($unidad -ieq $env:SystemDrive) { Join-Path $env:ProgramData $RaizCuarentena } else { Join-Path "$unidad\" $RaizCuarentena }
    Join-Path $base $sesion
}
function Remove-Restos($lista, [string]$sesion) {
    $qSis = Get-DirCuarentena $sesion $env:SystemDrive; New-Item -ItemType Directory -Force "$qSis\Registro" | Out-Null
    $indice = New-Object Collections.Generic.List[string]; $ok = 0; $fallos = 0; $n = 0
    foreach ($x in $lista) {
        $n++
        try {
            switch ($x.Tipo) {
                { $_ -in 'Carpeta', 'Archivo' } {
                    $q = Get-DirCuarentena $sesion $x.Ruta; New-Item -ItemType Directory -Force "$q\Carpetas" | Out-Null
                    $dest = Join-Path "$q\Carpetas" ("{0:D3}_{1}" -f $n, (Split-Path $x.Ruta -Leaf))
                    Move-Item -LiteralPath $x.Ruta -Destination $dest -Force -ErrorAction Stop
                    $indice.Add("$($x.Ruta)|$dest")
                    $pad = Split-Path $x.Ruta -Parent   # subir borrando carpetas vacías (p. ej. Google\Chrome vacío)
                    while ($pad -and -not (Test-RutaProtegida $pad) -and (Test-Path -LiteralPath $pad) -and -not @(Get-ChildItem -LiteralPath $pad -Force -ErrorAction SilentlyContinue).Count) { Remove-Item -LiteralPath $pad -Force -ErrorAction SilentlyContinue; $pad = Split-Path $pad -Parent }
                }
                { $_ -in 'Registro', 'ValorRegistro' } {
                    $rp = Convert-RegPath $x.Ruta; & reg.exe export $rp ("$qSis\Registro\{0:D3}.reg" -f $n) /y 2>&1 | Out-Null
                    if ($x.Tipo -eq 'Registro') { Remove-Item -LiteralPath $x.Ruta -Recurse -Force -ErrorAction Stop } else { Remove-ItemProperty -LiteralPath $x.Ruta -Name $x.Valor -ErrorAction Stop }
                }
                'Servicio' { & reg.exe export "HKLM\SYSTEM\CurrentControlSet\Services\$($x.Ruta)" ("$qSis\Registro\{0:D3}_servicio.reg" -f $n) /y 2>&1 | Out-Null; Stop-Service -Name $x.Ruta -Force -ErrorAction SilentlyContinue; & sc.exe delete $x.Ruta | Out-Null; if ($LASTEXITCODE -ne 0) { throw "sc delete código $LASTEXITCODE" } }
                'Tarea' { $tn = Split-Path $x.Ruta -Leaf; $path = ($x.Ruta.Substring(0, $x.Ruta.Length - $tn.Length)); try { Export-ScheduledTask -TaskName $tn -TaskPath $path | Out-File ("$qSis\Registro\{0:D3}_tarea.xml" -f $n) -Encoding UTF8 } catch { }; Unregister-ScheduledTask -TaskName $tn -TaskPath $path -Confirm:$false -ErrorAction Stop }
                'Firewall' { Remove-NetFirewallRule -Name $x.Ruta -ErrorAction Stop }
            }
            $ok++; Write-Host "    $($E.OK) [$n/$(@($lista).Count)] $($x.Tipo): $($x.Ruta)"
        } catch { $fallos++; Write-Host "    $($E.Error) [$n/$(@($lista).Count)] $($x.Tipo): $($x.Ruta) -> $($_.Exception.Message)" }
    }
    if ($indice.Count) { Set-Content -LiteralPath "$qSis\indice.txt" -Value $indice -Encoding UTF8 }
    Write-Log "Desinstalar_Total: sesión $sesion - $ok eliminados, $fallos con error"
    [pscustomobject]@{ Ok = $ok; Fallos = $fallos; Carpeta = $qSis }
}
function Get-Sesiones { $r = @(); foreach ($u in [IO.DriveInfo]::GetDrives()) { try { if ($u.IsReady) { $b = if ($u.Name -ieq "$env:SystemDrive\") { Join-Path $env:ProgramData $RaizCuarentena } else { Join-Path $u.Name $RaizCuarentena }; if (Test-Path -LiteralPath $b) { $r += @(Get-ChildItem -LiteralPath $b -Directory -ErrorAction SilentlyContinue) } } } catch { } }; @($r | Sort-Object Name -Descending) }

# ---------------------------------------------------------------- Ventanas
function Show-Selector($programas) {
    $f = New-Object Windows.Forms.Form; $f.Text = 'Desinstalar por completo'; $f.Size = New-Object Drawing.Size(980, 700); $f.StartPosition = 'CenterScreen'; $f.BackColor = (C 'Fondo'); $f.Font = New-Object Drawing.Font('Segoe UI', 9.5); $f.TopMost = $true
    $t = New-Object Windows.Forms.Label; $t.Text = 'Marca los programas a quitar por completo'; $t.ForeColor = (C 'Texto'); $t.Font = New-Object Drawing.Font('Segoe UI Semibold', 14); $t.AutoSize = $true; $t.Location = New-Object Drawing.Point(20, 14)
    $s = New-Object Windows.Forms.Label; $s.Text = 'Se desinstala con su desinstalador oficial y después se buscan los restos para que decidas qué borrar. Todo lo borrado va a una cuarentena reversible.'; $s.ForeColor = (C 'Suave'); $s.AutoSize = $true; $s.Location = New-Object Drawing.Point(22, 46)
    $b = New-Object Windows.Forms.TextBox; $b.Location = New-Object Drawing.Point(20, 76); $b.Size = New-Object Drawing.Size(400, 26); $b.BackColor = (C 'Panel'); $b.ForeColor = (C 'Texto'); $b.BorderStyle = 'FixedSingle'
    $lv = New-Object Windows.Forms.ListView; $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.CheckBoxes = $true; $lv.MultiSelect = $false; $lv.HideSelection = $false; $lv.Location = New-Object Drawing.Point(20, 112); $lv.Size = New-Object Drawing.Size(924, 440); $lv.Anchor = 'Top,Bottom,Left,Right'
    $lv.BackColor = (C 'Panel'); $lv.ForeColor = (C 'Texto'); $lv.BorderStyle = 'None'; $lv.Font = New-Object Drawing.Font('Segoe UI', 10)
    foreach ($c in @(@('Programa', 330), @('Editor', 220), @('Versión', 110), @('Tamaño', 80), @('Origen', 150))) { [void]$lv.Columns.Add($c[0], $c[1]) }
    $chk = New-Object Windows.Forms.CheckBox; $chk.Text = 'Borrar también mis datos y configuración (instalación limpia al reinstalar)'; $chk.Checked = $false; $chk.ForeColor = (C 'Texto'); $chk.AutoSize = $true; $chk.Location = New-Object Drawing.Point(20, 566); $chk.Anchor = 'Bottom,Left'
    $aviso = New-Object Windows.Forms.Label; $aviso.Text = 'Atención: en navegadores, correo o gestores de contraseñas los datos incluyen marcadores y perfiles. Si dudas, desmarca esta casilla.'; $aviso.ForeColor = (C 'Aviso'); $aviso.AutoSize = $true; $aviso.Location = New-Object Drawing.Point(40, 592); $aviso.Anchor = 'Bottom,Left'
    $ok = Nuevo-Boton 'Desinstalar y buscar restos' 700 620 244 $true; $ok.Anchor = 'Bottom,Right'; $ok.Enabled = $false
    $no = Nuevo-Boton 'Cancelar' 580 620 110 $false; $no.Anchor = 'Bottom,Right'; $no.DialogResult = 'Cancel'
    $f.Controls.AddRange(@($t, $s, $b, $lv, $chk, $aviso, $ok, $no)); $f.CancelButton = $no
    $est = @{ Cargando = $false }; $marc = @{}   # $marc: programas marcados (sobreviven al filtrar por texto)
    $llenar = { $lv.BeginUpdate(); $est.Cargando = $true; $lv.Items.Clear(); $q = $b.Text.Trim(); foreach ($p in $programas) { if ($q -and $p.Nombre -notlike "*$q*" -and $p.Editor -notlike "*$q*") { continue }; $i = New-Object Windows.Forms.ListViewItem($p.Nombre); [void]$i.SubItems.Add($p.Editor); [void]$i.SubItems.Add($p.Version); [void]$i.SubItems.Add($(if ($p.MB) { "$($p.MB) MB" } else { '' })); [void]$i.SubItems.Add($p.Ambito); $i.Tag = $p; $i.Checked = $marc.ContainsKey("$($p.Ambito)|$($p.Id)"); [void]$lv.Items.Add($i) }; $est.Cargando = $false; $lv.EndUpdate() }
    $lv.Add_ItemChecked({ param($o, $ev)
        if ($est.Cargando) { return }
        $k = "$($ev.Item.Tag.Ambito)|$($ev.Item.Tag.Id)"; if ($ev.Item.Checked) { $marc[$k] = $ev.Item.Tag } else { $marc.Remove($k) }
        $ok.Enabled = ($marc.Count -gt 0); $ok.Text = $(if ($marc.Count -gt 1) { "Desinstalar $($marc.Count) y buscar restos" } else { 'Desinstalar y buscar restos' })
    })
    & $llenar; $b.Add_TextChanged($llenar); $ok.DialogResult = 'OK'
    $lv.Add_DoubleClick({ if ($lv.SelectedItems.Count -and -not $marc.Count) { $marc["$($lv.SelectedItems[0].Tag.Ambito)|$($lv.SelectedItems[0].Tag.Id)"] = $lv.SelectedItems[0].Tag; $f.DialogResult = 'OK' } })
    $f.ShowInTaskbar = $true; $f.Add_Shown({ $f.Activate(); $f.BringToFront() })   # sin esto la ventana puede abrirse detrás de la app y parece que el script se ha colgado
    Write-Host "  $($E.Info) Elige los programas en la ventana «Desinstalar por completo» (si no la ves, búscala en la barra de tareas)."
    if ($f.ShowDialog() -ne 'OK' -or -not $marc.Count) { return $null }
    [pscustomobject]@{ Programas = @($marc.Values | Sort-Object Nombre); Datos = $chk.Checked }
}
function Show-Restos($p, $restos, [bool]$conDatos) {
    $f = New-Object Windows.Forms.Form; $f.Text = "Restos de $($p.Nombre)"; $f.Size = New-Object Drawing.Size(1100, 700); $f.StartPosition = 'CenterScreen'; $f.BackColor = (C 'Fondo'); $f.Font = New-Object Drawing.Font('Segoe UI', 9.5); $f.TopMost = $true
    $t = New-Object Windows.Forms.Label; $t.Text = "Restos encontrados de «$($p.Nombre)»"; $t.ForeColor = (C 'Texto'); $t.Font = New-Object Drawing.Font('Segoe UI Semibold', 14); $t.AutoSize = $true; $t.Location = New-Object Drawing.Point(20, 14)
    $s = New-Object Windows.Forms.Label; $s.Text = 'Marca lo que quieres eliminar. Va a la cuarentena (se puede restaurar). Las coincidencias de confianza «Media» vienen sin marcar: revísalas.'; $s.ForeColor = (C 'Suave'); $s.AutoSize = $true; $s.Location = New-Object Drawing.Point(22, 46)
    $lv = New-Object Windows.Forms.ListView; $lv.View = 'Details'; $lv.CheckBoxes = $true; $lv.FullRowSelect = $true; $lv.Location = New-Object Drawing.Point(20, 80); $lv.Size = New-Object Drawing.Size(1044, 500); $lv.Anchor = 'Top,Bottom,Left,Right'; $lv.BackColor = (C 'Panel'); $lv.ForeColor = (C 'Texto'); $lv.BorderStyle = 'None'; $lv.Font = New-Object Drawing.Font('Segoe UI', 9.5); $lv.ShowGroups = $true
    foreach ($c in @(@('Ruta', 600), @('Qué es', 270), @('Confianza', 90))) { [void]$lv.Columns.Add($c[0], $c[1]) }
    $grupos = @{}; foreach ($g in 'Archivos del programa', 'Datos y configuración', 'Registro', 'Servicios, tareas, firewall e inicio', 'Accesos directos') { $grupos[$g] = New-Object Windows.Forms.ListViewGroup($g); [void]$lv.Groups.Add($grupos[$g]) }
    foreach ($r in $restos) {
        $gn = switch ($r.Tipo) { { $_ -in 'Carpeta', 'Archivo' } { if ($r.Detalle -like 'Acceso*' -or $r.Detalle -like 'Carpeta del menú*') { 'Accesos directos' } elseif ($r.Datos) { 'Datos y configuración' } else { 'Archivos del programa' } } { $_ -in 'Registro' } { 'Registro' } default { 'Servicios, tareas, firewall e inicio' } }
        $i = New-Object Windows.Forms.ListViewItem(($r.Ruta + $(if ($r.Valor) { "  [$($r.Valor)]" } else { '' }))); [void]$i.SubItems.Add($r.Detalle); [void]$i.SubItems.Add($r.Conf); $i.Group = $grupos[$gn]; $i.Tag = $r
        $i.Checked = ($r.Conf -eq 'Alta' -and ($conDatos -or -not $r.Datos)); [void]$lv.Items.Add($i)
    }
    $ok = Nuevo-Boton 'Eliminar lo marcado' 820 600 244 $true; $ok.Anchor = 'Bottom,Right'; $ok.DialogResult = 'OK'
    $no = Nuevo-Boton 'No borrar nada' 690 600 120 $false; $no.Anchor = 'Bottom,Right'; $no.DialogResult = 'Cancel'
    $lbl = New-Object Windows.Forms.Label; $lbl.ForeColor = (C 'Suave'); $lbl.AutoSize = $true; $lbl.Location = New-Object Drawing.Point(22, 610); $lbl.Anchor = 'Bottom,Left'
    $cuenta = { $lbl.Text = "$(@($lv.CheckedItems).Count) de $($lv.Items.Count) marcados" }; & $cuenta; $lv.Add_ItemChecked($cuenta)
    $f.Controls.AddRange(@($t, $s, $lv, $lbl, $ok, $no)); $f.AcceptButton = $ok; $f.CancelButton = $no
    $f.ShowInTaskbar = $true; $f.Add_Shown({ $f.Activate(); $f.BringToFront() })
    Write-Host "  $($E.Info) Revisa los restos en la ventana «Restos de $($p.Nombre)» (si no la ves, búscala en la barra de tareas)."
    if ($f.ShowDialog() -ne 'OK') { return @() }
    @($lv.CheckedItems | ForEach-Object { $_.Tag })
}

function Show-RestosTodos($restos, [bool]$conDatos) {
    $progs = @($restos | ForEach-Object { $_.Prog } | Select-Object -Unique)
    $f = New-Object Windows.Forms.Form; $f.Text = $(if ($progs.Count -gt 1) { "Restos de $($progs.Count) programas" } else { "Restos de $($progs[0])" }); $f.Size = New-Object Drawing.Size(1100, 720); $f.StartPosition = 'CenterScreen'; $f.BackColor = (C 'Fondo'); $f.Font = New-Object Drawing.Font('Segoe UI', 9.5); $f.TopMost = $true
    $t = New-Object Windows.Forms.Label; $t.Text = $(if ($progs.Count -gt 1) { "Restos de los $($progs.Count) programas desinstalados" } else { "Restos encontrados de «$($progs[0])»" }); $t.ForeColor = (C 'Texto'); $t.Font = New-Object Drawing.Font('Segoe UI Semibold', 14); $t.AutoSize = $true; $t.Location = New-Object Drawing.Point(20, 14)
    $s = New-Object Windows.Forms.Label; $s.Text = 'Marca lo que quieres eliminar (carpetas, registro, servicios, tareas…). Todo va a la cuarentena y se puede restaurar. Las coincidencias de confianza «Media» vienen sin marcar: revísalas.'; $s.ForeColor = (C 'Suave'); $s.AutoSize = $true; $s.Location = New-Object Drawing.Point(22, 46)
    $lv = New-Object Windows.Forms.ListView; $lv.View = 'Details'; $lv.CheckBoxes = $true; $lv.FullRowSelect = $true; $lv.ShowGroups = $true; $lv.Location = New-Object Drawing.Point(20, 80); $lv.Size = New-Object Drawing.Size(1044, 520); $lv.Anchor = 'Top,Bottom,Left,Right'; $lv.BackColor = (C 'Panel'); $lv.ForeColor = (C 'Texto'); $lv.BorderStyle = 'None'; $lv.Font = New-Object Drawing.Font('Segoe UI', 9.5)
    foreach ($c in @(@('Ruta', 580), @('Qué es', 280), @('Confianza', 90))) { [void]$lv.Columns.Add($c[0], $c[1]) }
    $grupos = @{}; foreach ($g in $progs) { $grupos[$g] = New-Object Windows.Forms.ListViewGroup($g); [void]$lv.Groups.Add($grupos[$g]) }
    $lv.BeginUpdate()
    foreach ($r in $restos) {
        $i = New-Object Windows.Forms.ListViewItem(($r.Ruta + $(if ($r.Valor) { "  [$($r.Valor)]" } else { '' }))); [void]$i.SubItems.Add("$($r.Tipo): $($r.Detalle)"); [void]$i.SubItems.Add($r.Conf); $i.Group = $grupos[$r.Prog]; $i.Tag = $r
        $i.Checked = ($r.Conf -eq 'Alta' -and ($conDatos -or -not $r.Datos)); [void]$lv.Items.Add($i)
    }
    $lv.EndUpdate()
    $ok = Nuevo-Boton 'Eliminar lo marcado' 820 620 244 $true; $ok.Anchor = 'Bottom,Right'; $ok.DialogResult = 'OK'
    $no = Nuevo-Boton 'No borrar nada' 690 620 120 $false; $no.Anchor = 'Bottom,Right'; $no.DialogResult = 'Cancel'
    $bTodo = Nuevo-Boton 'Marcar todo' 20 620 130 $false; $bTodo.Anchor = 'Bottom,Left'
    $bNada = Nuevo-Boton 'Desmarcar todo' 160 620 140 $false; $bNada.Anchor = 'Bottom,Left'
    $bSeg = Nuevo-Boton 'Solo los seguros' 310 620 150 $false; $bSeg.Anchor = 'Bottom,Left'
    $lbl = New-Object Windows.Forms.Label; $lbl.ForeColor = (C 'Suave'); $lbl.AutoSize = $true; $lbl.Location = New-Object Drawing.Point(22, 604); $lbl.Anchor = 'Bottom,Left'
    $cuenta = { $lbl.Text = "$(@($lv.CheckedItems).Count) de $($lv.Items.Count) marcados" }; & $cuenta; $lv.Add_ItemChecked($cuenta)
    $marcar = { param($todo, $solo) $lv.BeginUpdate(); foreach ($i in $lv.Items) { $i.Checked = $(if ($solo) { $i.Tag.Conf -eq 'Alta' -and ($conDatos -or -not $i.Tag.Datos) } else { $todo }) }; $lv.EndUpdate() }.GetNewClosure()
    $bTodo.Add_Click({ & $marcar $true $false }.GetNewClosure()); $bNada.Add_Click({ & $marcar $false $false }.GetNewClosure()); $bSeg.Add_Click({ & $marcar $false $true }.GetNewClosure())
    $f.Controls.AddRange(@($t, $s, $lv, $lbl, $bTodo, $bNada, $bSeg, $ok, $no)); $f.AcceptButton = $ok; $f.CancelButton = $no
    $f.ShowInTaskbar = $true; $f.Add_Shown({ $f.Activate(); $f.BringToFront() })
    Write-Host "  $($E.Info) Elige en la ventana que se ha abierto (si no la ves, búscala en la barra de tareas)."
    if ($f.ShowDialog() -ne 'OK') { return @() }
    @($lv.CheckedItems | ForEach-Object { $_.Tag })
}

# ---------------------------------------------------------------- Modos auxiliares
if ($VaciarCuarentena) {
    if ($SoloAnalizar) { Exit-Kit 'Ok' 'Modo análisis: no se ha borrado nada de la cuarentena.' }
    $ses = @(Get-Sesiones); if (-not $ses) { Write-Output "  $($E.Info) La cuarentena está vacía."; return }
    $mb = ($ses | ForEach-Object { (Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum } | Measure-Object -Sum).Sum / 1MB
    # Irreversible: -Siempre obliga a preguntar también con -Auto
    if (-not (Confirm-Accion "Se eliminarán DEFINITIVAMENTE $($ses.Count) sesión(es) de cuarentena ($([math]::Round($mb)) MB). Ya no se podrá restaurar nada.`n`n¿Continuar?" 'Vaciar cuarentena' -Siempre)) { Exit-Kit 'Cancelado' 'Cancelado: no se ha borrado nada.' }
    $fallos = 0
    foreach ($s in $ses) { try { Remove-Item -LiteralPath $s.FullName -Recurse -Force -ErrorAction Stop; Write-Output "  $($E.OK) Eliminada $($s.Name)" } catch { $fallos++; Write-Output "  $($E.Aviso) No se pudo eliminar $($s.Name): $($_.Exception.Message)" } }
    Write-Log "Cuarentena vaciada ($fallos fallos)"; if ($fallos) { Exit-Kit 'Error' "$fallos sesión(es) no se pudieron eliminar (algo las tiene en uso)." } else { return }
}
if ($Restaurar) {
    if ($SoloAnalizar) { Exit-Kit 'Ok' 'Modo análisis: no se ha restaurado nada.' }
    $ses = @(Get-Sesiones); if (-not $ses) { Write-Output "  $($E.Info) No hay nada en cuarentena."; return }
    $sel = $ses[0]
    if (-not $Auto) {
        $f = New-Object Windows.Forms.Form; $f.Text = 'Restaurar desde la cuarentena'; $f.Size = New-Object Drawing.Size(640, 420); $f.StartPosition = 'CenterScreen'; $f.BackColor = (C 'Fondo'); $f.TopMost = $true
        $lb = New-Object Windows.Forms.ListBox; $lb.Dock = 'Fill'; $lb.BackColor = (C 'Panel'); $lb.ForeColor = (C 'Texto'); $lb.Font = New-Object Drawing.Font('Segoe UI', 11); foreach ($s in $ses) { [void]$lb.Items.Add($s.Name) }; $lb.SelectedIndex = 0
        $pn = New-Object Windows.Forms.Panel; $pn.Dock = 'Bottom'; $pn.Height = 56; $pn.BackColor = (C 'Fondo'); $ok = Nuevo-Boton 'Restaurar la seleccionada' 380 10 220 $true; $ok.DialogResult = 'OK'; $pn.Controls.Add($ok); $f.Controls.AddRange(@($lb, $pn)); $f.AcceptButton = $ok
        if ($f.ShowDialog() -ne 'OK') { return }; $sel = $ses | Where-Object { $_.Name -eq $lb.SelectedItem } | Select-Object -First 1
    }
    Write-Output "  $($E.Refresh) Restaurando $($sel.Name)…"
    $dirs = @($sel.FullName); foreach ($u in [IO.DriveInfo]::GetDrives()) { try { if ($u.IsReady -and $u.Name -ine "$env:SystemDrive\") { $c = Join-Path (Join-Path $u.Name $RaizCuarentena) $sel.Name; if (Test-Path -LiteralPath $c) { $dirs += $c } } } catch { } }
    foreach ($d in ($dirs | Select-Object -Unique)) {
        $idx = Join-Path $d 'indice.txt'
        if (Test-Path -LiteralPath $idx) { foreach ($l in Get-Content -LiteralPath $idx -Encoding UTF8) { $o, $q = $l -split '\|', 2; try { New-Item -ItemType Directory -Force (Split-Path $o -Parent) | Out-Null; if (Test-Path -LiteralPath $o) { Write-Output "    $($E.Aviso) Ya existe, se omite: $o" } else { Move-Item -LiteralPath $q -Destination $o -Force -ErrorAction Stop; Write-Output "    $($E.OK) $o" } } catch { Write-Output "    $($E.Error) $o -> $($_.Exception.Message)" } } }
        foreach ($r in @(Get-ChildItem -LiteralPath (Join-Path $d 'Registro') -Filter *.reg -ErrorAction SilentlyContinue)) { & reg.exe import $r.FullName 2>&1 | Out-Null; Write-Output "    $(if ($LASTEXITCODE -eq 0) { $E.OK } else { $E.Error }) Registro: $($r.Name)" }
        foreach ($r in @(Get-ChildItem -LiteralPath (Join-Path $d 'Registro') -Filter *_tarea.xml -ErrorAction SilentlyContinue)) { try { Register-ScheduledTask -TaskName ([IO.Path]::GetFileNameWithoutExtension($r.Name)) -Xml (Get-Content -LiteralPath $r.FullName -Raw) -ErrorAction Stop | Out-Null; Write-Output "    $($E.OK) Tarea restaurada: $($r.Name)" } catch { Write-Output "    $($E.Aviso) Tarea no restaurada: $($_.Exception.Message)" } }
    }
    Write-Output "`n  $($E.OK) Restauración terminada. Puede hacer falta reinstalar el programa si se desinstaló."; Write-Log "Restaurada cuarentena $($sel.Name)"; return
}

# ---------------------------------------------------------------- Flujo principal
Write-Output "========================================================"
Write-Output "  $($E.Cohete) DESINSTALADOR COMPLETO"
Write-Output "========================================================"
Write-Output "  $($E.Lupa) Leyendo los programas instalados…"
$programas = @(Get-Programas)
$seleccion = @(); $borrarDatos = [bool]$Datos
if ($Nombre) {
    foreach ($nom in @($Nombre)) {
        $sel = @($programas | Where-Object { $_.Nombre -eq $nom } | Select-Object -First 1)[0]
        if (-not $sel) { $sel = @($programas | Where-Object { $_.Nombre -like "*$nom*" } | Select-Object -First 1)[0] }
        if (-not $sel) { Write-Output "  $($E.Error) No se encontró ningún programa que coincida con «$nom»."; if (@($Nombre).Count -eq 1) { exit 1 }; continue }
        if ($seleccion -notcontains $sel) { $seleccion += $sel }
    }
    if (-not $seleccion.Count) { exit 1 }
}
elseif ($Auto) { Write-Output "  $($E.Error) Con -Auto hay que indicar -Nombre."; exit 1 }
else { $r = Show-Selector $programas; if (-not $r) { Exit-Kit 'Cancelado' 'Cancelado.' }; $seleccion = @($r.Programas); $borrarDatos = $r.Datos }

# Componentes compartidos: otros programas pueden depender de ellos (se pregunta uno a uno y se omite el que no se confirme)
$seguir = @()
foreach ($sel in $seleccion) {
    if (($sel.Nombre -match '(?i)redistributable|runtime|\.NET|Visual C\+\+|WebView2|DirectX|Framework|Windows SDK|Driver|Controlador') -and -not $Forzar) {
        if ($Auto) { Write-Output "  $($E.Error) «$($sel.Nombre)» parece un componente compartido. Usa -Forzar si estás seguro."; exit 1 }
        $q = [Windows.Forms.MessageBox]::Show("«$($sel.Nombre)» parece un componente compartido (runtime, controlador o similar). Otros programas pueden necesitarlo y quitarlo puede romperlos.`n`n¿Seguir de todos modos?", 'Componente compartido', 'YesNo', 'Warning', 'Button2')
        if ($q -ne 'Yes') { Write-Output "  $($E.Aviso) Se omite «$($sel.Nombre)»."; continue }
    }
    $seguir += $sel
}
$seleccion = @($seguir)
if (-not $seleccion.Count) { Exit-Kit 'Cancelado' 'Cancelado.' }
if (-not $Auto -and -not $SoloAnalizar) {
    $lista = ($seleccion | ForEach-Object { "• $($_.Nombre)" }) -join "`n"
    $que = if ($seleccion.Count -gt 1) { "Se van a desinstalar $($seleccion.Count) programas" } else { 'Se va a desinstalar un programa' }
    $q = [Windows.Forms.MessageBox]::Show("$que y a buscar sus restos:`n`n$lista`n`n$(if ($borrarDatos) { 'Se propondrá borrar también tus datos y configuración.' } else { 'Tus datos y configuración se conservarán.' })`nLo que borres irá a una cuarentena reversible.`n`n¿Continuar?", 'Desinstalar por completo', 'YesNo', 'Question')
    if ($q -ne 'Yes') { Exit-Kit 'Cancelado' 'Cancelado.' }
}

if (-not $SoloAnalizar -and -not $SinDesinstalar) {
    $desc = if ($seleccion.Count -gt 1) { "$($seleccion.Count) programas" } else { $seleccion[0].Nombre }   # un solo punto: Windows limita a uno cada 24 h
    try { Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue; Checkpoint-Computer -Description "Nitrit0 - antes de desinstalar $desc" -RestorePointType APPLICATION_UNINSTALL -ErrorAction Stop; Write-Output "  $($E.OK) Punto de restauración creado." } catch { Write-Output "  $($E.Info) No se creó punto de restauración ($($_.Exception.Message -replace '\r?\n', ' '))." }
}

$fallosTotal = 0; $n = 0; $todos = New-Object Collections.Generic.List[object]
# Primero los que se desinstalan en silencio; los que abren su propia ventana, al final (así no hay que estar delante durante el resto)
$seleccion = @($seleccion | Sort-Object @{ Expression = { if ((Get-ModoDesinst $_).Interactivo) { 1 } else { 0 } } }, Nombre)
$abren = @($seleccion | Where-Object { (Get-ModoDesinst $_).Interactivo }).Count
if ($seleccion.Count -gt 1 -and $abren) { Write-Output "  $($E.Info) $($seleccion.Count - $abren) se quitan en silencio y $abren abrirán su propio desinstalador (van al final)." }
foreach ($sel in $seleccion) {
    $n++
    Write-Output "`n--------------------------------------------------------"
    Write-Output "  Programa $n de $($seleccion.Count): $($sel.Nombre)  $($sel.Version)  ($($sel.Editor))"
    if ($sel.Ubicacion) { Write-Output "  Carpeta de instalación: $($sel.Ubicacion)" }
    if (-not $SoloAnalizar -and -not $SinDesinstalar) { [void](Invoke-Desinstalacion $sel) }
    Write-Output "  $($E.Lupa) Buscando restos…"
    $restos = @(Find-Restos $sel)
    Write-Output "  $($E.Info) Encontrados $($restos.Count) resto(s): $(@($restos | Where-Object Conf -eq 'Alta').Count) de confianza alta, $(@($restos | Where-Object Conf -eq 'Media').Count) media."
    foreach ($r in $restos) { $r | Add-Member -NotePropertyName Prog -NotePropertyValue $sel.Nombre -Force; $todos.Add($r); Write-Output ("    [{0}] {1}: {2}{3}" -f $r.Conf, $r.Tipo, $r.Ruta, $(if ($r.Datos) { '  (datos)' } else { '' })) }
}
Write-Output "`n========================================================"
if ($SoloAnalizar) { Write-Output "  $($E.Info) Modo análisis: no se ha borrado nada."; return }
Write-Output "  $($E.OK) Desinstalación terminada ($($seleccion.Count) programa$(if ($seleccion.Count -ne 1) { 's' }))."
if (-not $todos.Count) { Write-Output "  $($E.OK) No queda ningún rastro."; return }
Write-Output "  $($E.Info) Quedan $($todos.Count) resto(s) en total. $(if (-not $Auto) { 'Elige cuáles se borran en la ventana que se ha abierto.' })"
$aBorrar = if ($Auto) { @($todos | Where-Object { $_.Conf -eq 'Alta' -and ($borrarDatos -or -not $_.Datos) }) } else { @(Show-RestosTodos $todos $borrarDatos) }
if (-not $aBorrar.Count) { Write-Output "  $($E.Info) No se borró ningún resto."; return }
# Orden seguro: primero servicios, tareas y firewall; después carpetas; al final el registro
$orden = @{ Servicio = 0; Tarea = 1; Firewall = 2; ValorRegistro = 3; Archivo = 4; Carpeta = 5; Registro = 6 }
$aBorrar = @($aBorrar | Sort-Object { $orden[$_.Tipo] })
$sesion = "{0}_{1}" -f (Get-Date -Format 'yyyyMMdd_HHmmss'), $(if ($seleccion.Count -eq 1) { ($seleccion[0].Nombre -replace '[^\w\-]', '_') -replace '_+', '_' } else { "Varios_$($seleccion.Count)_programas" })
Write-Output "  $($E.Reloj) Moviendo $($aBorrar.Count) resto(s) a la cuarentena…"
$res = Remove-Restos $aBorrar $sesion
$fallosTotal += [int]$res.Fallos
Write-Output "  $($E.Disco) RESULTADO: $($res.Ok) eliminados, $($res.Fallos) con error"
Write-Output "  Cuarentena: $($res.Carpeta)"
Write-Output "`n========================================================"
Write-Output "  Para deshacerlo: «Desinstalar Total» con -Restaurar. Para liberar espacio: -VaciarCuarentena."
if ($fallosTotal) { Write-Output "  $($E.Aviso) Los que dieron error suelen estar en uso: reinicia el equipo y vuelve a ejecutar el análisis." }
Write-Output "========================================================"
if ($fallosTotal) { exit 1 }
