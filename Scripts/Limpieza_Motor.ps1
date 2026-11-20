# =====================================================================
#  Limpieza_Motor.ps1 - Motor de datos de «Nitrit0 Limpieza» (limpiador y programas de inicio)
#  Lo llama la interfaz: cada acción escribe UNA línea JSON por evento en la salida (sin texto para personas).
#    Analizar     -> {evento:'categoria', id, grupo, nombre, ayuda, marcada, riesgo, bytes, archivos, admin}  y  {evento:'fin', bytes}
#    Limpiar -Ids -> {evento:'inicio'|'categoria'|'error'|'fin', ...}   (solo borra las categorías pedidas)
#    InicioListar -> {evento:'inicio', tipo, id, nombre, ambito, orden, activo}
#    InicioCambiar -Tipo -Id -Activar -> {evento:'fin', ok}   (interruptor reversible, no borra nada)
#  Salida: 0 bien · 1 error · 2 cancelado
# =====================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Analizar', 'Limpiar', 'InicioListar', 'InicioCambiar', 'ProgramasListar', 'DesinstalarFondo', 'RegistroAnalizar', 'RegistroLimpiar')][string]$Accion,
    [string[]]$Ids = @(),
    [string]$Tipo = '', [string]$Id = '', [bool]$Activar = $true, [string[]]$Nombres = @(), [ValidateSet('Auto', 'Manual')][string]$Modo = 'Auto'
)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Comun.ps1'); Initialize-Kit (Split-Path -Parent $PSScriptRoot) }
function Emit($o) { [Console]::Out.WriteLine(($o | ConvertTo-Json -Compress -Depth 4)) }

# ---------- Limpiador ----------
function Get-ArchivosRuta([string]$r) {
    # Con -Path y -Recurse PowerShell no desciende a carpetas que casan con el comodín: se recorren aparte
    foreach ($i in @(Get-ChildItem -Path $r -Force -ErrorAction SilentlyContinue)) { if ($i.PSIsContainer) { Get-ChildItem -LiteralPath $i.FullName -File -Recurse -Force -ErrorAction SilentlyContinue } else { $i } }
}
function Get-Medida([string[]]$rutas, [int]$dias) {
    $limite = (Get-Date).AddDays(-$dias); $b = [int64]0; $n = 0
    foreach ($r in $rutas) { foreach ($f in @(Get-ArchivosRuta $r)) { if ($dias -eq 0 -or $f.LastWriteTime -lt $limite) { $b += $f.Length; $n++ } } }
    [pscustomobject]@{ Bytes = $b; Archivos = $n }
}

$perfiles = @(Get-ChildItem -Path (Split-Path -Parent $env:PUBLIC) -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin 'Public', 'Default', 'Default User', 'All Users' })
function Get-RutasPerfil([string[]]$sub) { foreach ($u in $perfiles) { foreach ($s in $sub) { Join-Path $u.FullName $s } } }
$cacheChromium = 'Cache', 'Code Cache', 'GPUCache', 'Media Cache', 'DawnCache', 'Service Worker\CacheStorage', 'Service Worker\ScriptCache'
function Get-CachesChromium([string[]]$bases) { foreach ($b in $bases) { foreach ($p in 'Default', 'Profile *') { foreach ($c in $cacheChromium) { "$b\$p\$c\*" } } } }
$unidad = $env:SystemDrive.TrimEnd(':')

# Id, grupo, nombre, ayuda, marcada por defecto, riesgo (bajo/medio), días mínimos, requiere administrador, procesos a cerrar, rutas
$cats = @(
    @{ Id = 'temp-usuario'; Grupo = 'Windows'; Nombre = 'Archivos temporales del usuario'; Ayuda = 'Restos que dejan los programas al trabajar. Se regeneran solos.'; On = $true; Riesgo = 'bajo'; Dias = 0; Admin = $false; Cierra = @(); Rutas = @("$env:LOCALAPPDATA\Temp\*", "$env:LOCALAPPDATA\CrashDumps\*") }
    @{ Id = 'temp-windows'; Grupo = 'Windows'; Nombre = 'Archivos temporales de Windows'; Ayuda = 'Carpeta Temp del sistema.'; On = $true; Riesgo = 'bajo'; Dias = 0; Admin = $true; Cierra = @(); Rutas = @("$env:SystemRoot\Temp\*", "$env:SystemDrive\TEMP\*") }
    @{ Id = 'miniaturas'; Grupo = 'Windows'; Nombre = 'Caché de miniaturas'; Ayuda = 'Vistas previas del Explorador. Se vuelven a crear al abrir las carpetas.'; On = $true; Riesgo = 'bajo'; Dias = 0; Admin = $false; Cierra = @(); Rutas = @("$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db", "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db") }
    @{ Id = 'informes-error'; Grupo = 'Windows'; Nombre = 'Informes de errores de Windows'; Ayuda = 'Informes de cuelgues ya enviados o en cola.'; On = $true; Riesgo = 'bajo'; Dias = 0; Admin = $true; Cierra = @(); Rutas = @("$env:ProgramData\Microsoft\Windows\WER\ReportArchive\*", "$env:ProgramData\Microsoft\Windows\WER\ReportQueue\*") }
    @{ Id = 'volcados'; Grupo = 'Windows'; Nombre = 'Volcados de memoria tras un error grave'; Ayuda = 'MEMORY.DMP y minivolcados. Bórralos si no vas a analizar una pantalla azul.'; On = $false; Riesgo = 'medio'; Dias = 0; Admin = $true; Cierra = @(); Rutas = @("$env:SystemRoot\Minidump\*", "$env:SystemRoot\MEMORY.DMP", "$env:SystemRoot\LiveKernelReports\*") }
    @{ Id = 'windows-update'; Grupo = 'Windows'; Nombre = 'Descargas de Windows Update ya instaladas'; Ayuda = 'Se detiene el servicio un momento. Windows las baja otra vez si hacen falta.'; On = $true; Riesgo = 'bajo'; Dias = 0; Admin = $true; Cierra = @(); Rutas = @("$env:SystemRoot\SoftwareDistribution\Download\*") }
    @{ Id = 'registros'; Grupo = 'Windows'; Nombre = 'Registros de Windows de más de 30 días'; Ayuda = 'Se conservan los recientes (CBS, DISM) por si hace falta diagnosticar.'; On = $true; Riesgo = 'bajo'; Dias = 30; Admin = $true; Cierra = @(); Rutas = @("$env:SystemRoot\Logs\*") }
    @{ Id = 'papelera'; Grupo = 'Windows'; Nombre = 'Papelera de reciclaje (todas las cuentas)'; Ayuda = 'Lo que hay en la Papelera se pierde para siempre.'; On = $false; Riesgo = 'medio'; Dias = 0; Admin = $false; Cierra = @(); Rutas = @(); Especial = 'papelera' }
    @{ Id = 'nav-chrome'; Grupo = 'Navegadores'; Nombre = 'Google Chrome: caché'; Ayuda = 'No toca contraseñas, cookies ni historial. Cierra Chrome.'; On = $true; Riesgo = 'bajo'; Dias = 0; Admin = $false; Cierra = @('chrome'); Rutas = @(Get-RutasPerfil (Get-CachesChromium 'AppData\Local\Google\Chrome\User Data')) }
    @{ Id = 'nav-edge'; Grupo = 'Navegadores'; Nombre = 'Microsoft Edge: caché'; Ayuda = 'No toca contraseñas, cookies ni historial. Cierra Edge.'; On = $true; Riesgo = 'bajo'; Dias = 0; Admin = $false; Cierra = @('msedge'); Rutas = @(Get-RutasPerfil ((Get-CachesChromium 'AppData\Local\Microsoft\Edge\User Data') + 'AppData\Local\Microsoft\Windows\INetCache\*')) }
    @{ Id = 'nav-firefox'; Grupo = 'Navegadores'; Nombre = 'Mozilla Firefox: caché'; Ayuda = 'No toca contraseñas, cookies ni historial. Cierra Firefox.'; On = $true; Riesgo = 'bajo'; Dias = 0; Admin = $false; Cierra = @('firefox'); Rutas = @(Get-RutasPerfil 'AppData\Local\Mozilla\Firefox\Profiles\*\cache2\*', 'AppData\Local\Mozilla\Firefox\Profiles\*\startupCache\*', 'AppData\Local\Mozilla\Firefox\Profiles\*\thumbnails\*') }
    @{ Id = 'nav-otros'; Grupo = 'Navegadores'; Nombre = 'Brave, Vivaldi y Opera: caché'; Ayuda = 'No toca contraseñas, cookies ni historial. Cierra esos navegadores.'; On = $true; Riesgo = 'bajo'; Dias = 0; Admin = $false; Cierra = @('brave', 'vivaldi', 'opera')
        Rutas = @(Get-RutasPerfil ((Get-CachesChromium 'AppData\Local\BraveSoftware\Brave-Browser\User Data', 'AppData\Local\Vivaldi\User Data') + @(foreach ($b in 'AppData\Roaming\Opera Software\Opera Stable', 'AppData\Roaming\Opera Software\Opera GX Stable', 'AppData\Local\Opera Software\Opera Stable', 'AppData\Local\Opera Software\Opera GX Stable') { foreach ($c in $cacheChromium) { "$b\$c\*" } }))) }
    @{ Id = 'apps-cache'; Grupo = 'Aplicaciones'; Nombre = 'Cachés de aplicaciones'; Ayuda = 'Spotify, Discord, Slack, WhatsApp, VS Code, Cursor, Claude y Steam. Solo caché: no se cierra ninguna sesión.'; On = $true; Riesgo = 'bajo'; Dias = 0; Admin = $false; Cierra = @()
        Rutas = @(Get-RutasPerfil (@(foreach ($a in 'WhatsApp', 'discord', 'Slack', 'Code', 'Cursor', 'Claude') { foreach ($s in 'Cache', 'Code Cache', 'GPUCache') { "AppData\Roaming\$a\$s\*" } }) + @('AppData\Local\Spotify\Data\*', 'AppData\Local\Spotify\Storage\*', 'AppData\Local\Steam\htmlcache\*'))) }
    @{ Id = 'nvidia-instaladores'; Grupo = 'Aplicaciones'; Nombre = 'Instaladores de NVIDIA ya extraídos'; Ayuda = 'Carpeta C:\NVIDIA que dejan los instaladores de drivers.'; On = $true; Riesgo = 'bajo'; Dias = 0; Admin = $true; Cierra = @(); Rutas = @("$env:SystemDrive\NVIDIA\DisplayDriver\*") }
)

function Get-Papelera { try { Get-ChildItem -LiteralPath "$unidad`:\`$Recycle.Bin" -Force -Recurse -File -ErrorAction SilentlyContinue } catch { @() } }

if ($Accion -eq 'Analizar') {
    $total = [int64]0
    foreach ($c in $cats) {
        if ($c.Especial -eq 'papelera') { $f = @(Get-Papelera); $m = [pscustomobject]@{ Bytes = [int64]($f | Measure-Object Length -Sum).Sum; Archivos = $f.Count } } else { $m = Get-Medida $c.Rutas $c.Dias }
        $total += $m.Bytes
        Emit @{ evento = 'categoria'; id = $c.Id; grupo = $c.Grupo; nombre = $c.Nombre; ayuda = $c.Ayuda; marcada = $c.On; riesgo = $c.Riesgo; bytes = $m.Bytes; archivos = $m.Archivos; admin = $c.Admin }
    }
    Emit @{ evento = 'fin'; bytes = $total; esAdmin = (Test-EsAdmin) }
    Write-Log "Limpieza_Motor: análisis, $([int64]($total / 1MB)) MB estimados"
    exit 0
}

if ($Accion -eq 'Limpiar') {
    $pedidas = @($cats | Where-Object { $Ids -contains $_.Id })
    if (-not $pedidas.Count) { Emit @{ evento = 'error'; mensaje = 'No se ha marcado ninguna categoría.' }; exit 1 }
    if ($pedidas | Where-Object Admin) { if (-not (Test-EsAdmin)) { Emit @{ evento = 'error'; mensaje = 'Hace falta administrador para limpiar las categorías de Windows. Abre la app como administrador.' }; exit 1 } }
    $libreAntes = (Get-PSDrive -Name $unidad).Free; $errores = 0
    Emit @{ evento = 'inicio'; categorias = $pedidas.Count }
    # Cierre de navegadores: normal primero y solo se fuerzan los que no responden
    $nombresProc = @($pedidas | ForEach-Object { $_.Cierra } | Sort-Object -Unique)
    if ($nombresProc.Count) {
        $procs = @($nombresProc | ForEach-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue })
        foreach ($p in $procs) { try { [void]$p.CloseMainWindow() } catch { } }
        $fin = (Get-Date).AddSeconds(8); while ((Get-Date) -lt $fin -and @($procs | Where-Object { -not $_.HasExited }).Count) { Start-Sleep -Milliseconds 500 }
        $forzados = @(); foreach ($p in @($procs | Where-Object { -not $_.HasExited })) { try { Stop-Process -Id $p.Id -Force -ErrorAction Stop; $forzados += $p.ProcessName } catch { } }
        if ($forzados) { Emit @{ evento = 'aviso'; mensaje = 'No respondían y se forzó el cierre de: ' + ((@($forzados | Sort-Object -Unique)) -join ', ') } }
    }
    foreach ($c in $pedidas) {
        $servicios = @(); $enUso = 0; $liberado = [int64]0
        try {
            if ($c.Id -eq 'windows-update') { foreach ($s in 'wuauserv', 'bits') { $sv = Get-Service -Name $s -ErrorAction SilentlyContinue; if ($sv -and $sv.Status -eq 'Running') { $servicios += $s; Stop-Service -Name $s -Force -ErrorAction SilentlyContinue } } }
            if ($c.Especial -eq 'papelera') { $liberado = [int64](Get-Papelera | Measure-Object Length -Sum).Sum; Clear-RecycleBin -Force -ErrorAction Stop }
            else {
                $limite = (Get-Date).AddDays(-$c.Dias)
                foreach ($r in $c.Rutas) {
                    foreach ($f in @(Get-ArchivosRuta $r)) {
                        if ($c.Dias -gt 0 -and $f.LastWriteTime -ge $limite) { continue }
                        $t = $f.Length; try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $liberado += $t } catch { $enUso++ }
                    }
                    # Carpetas que han quedado vacías (sin borrar la propia carpeta base)
                    if ($c.Dias -eq 0 -and $r.EndsWith('\*')) { Get-ChildItem -Path $r -Directory -Force -ErrorAction SilentlyContinue | Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force -Recurse -ErrorAction SilentlyContinue) } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
                }
            }
            Emit @{ evento = 'categoria'; id = $c.Id; bytes = $liberado; enUso = $enUso }
        } catch { $errores++; Emit @{ evento = 'error'; id = $c.Id; mensaje = $_.Exception.Message } }
        finally { foreach ($s in $servicios) { try { Start-Service -Name $s -ErrorAction SilentlyContinue } catch { } } }
    }
    Start-Sleep -Seconds 1
    $real = [Math]::Max([int64]0, (Get-PSDrive -Name $unidad).Free - $libreAntes)
    Emit @{ evento = 'fin'; bytes = $real; errores = $errores }
    Write-Log "Limpieza_Motor: limpieza de $($pedidas.Count) categorías, $([int64]($real / 1MB)) MB liberados, $errores errores" $(if ($errores) { 'WARN' } else { 'INFO' })
    exit $(if ($errores) { 1 } else { 0 })
}

# ---------- Programas instalados ----------
if ($Accion -eq 'ProgramasListar') {
    $claves = @(@{ R = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'; A = 'Equipo' }, @{ R = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'; A = 'Equipo (32 bits)' }, @{ R = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'; A = 'Usuario' })
    $vistos = @{}
    # Último uso (aproximado): Windows no lo guarda por programa. Se cruzan dos fuentes que solo se leen con administrador:
    #  - BAM: última ejecución de cada .exe por ruta (Windows 10 1709+).  - Prefetch: última ejecución por nombre de .exe (si está activado).
    $bam = @{}; $pf = @{}
    foreach ($base in 'HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings', 'HKLM:\SYSTEM\CurrentControlSet\Services\bam\UserSettings') {
        if (-not (Test-Path -LiteralPath $base)) { continue }
        foreach ($sid in @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue)) {
            foreach ($n in $sid.GetValueNames()) {
                if ($n -notlike '\Device\HarddiskVolume*') { continue }
                $b = $sid.GetValue($n); if ($b -isnot [byte[]] -or $b.Length -lt 8) { continue }
                $ft = [BitConverter]::ToInt64($b, 0); if ($ft -le 0 -or $ft -gt 2650467743999999999) { continue }
                $k = ($n -replace '^\\Device\\HarddiskVolume\d+', '').ToLowerInvariant(); $d = [DateTime]::FromFileTimeUtc($ft)
                if (-not $bam.ContainsKey($k) -or $bam[$k] -lt $d) { $bam[$k] = $d }
            }
        }
    }
    foreach ($f in @(Get-ChildItem -Path "$env:SystemRoot\Prefetch\*.pf" -ErrorAction SilentlyContinue)) {
        $k = ($f.Name -replace '-[0-9A-F]{8}\.pf$', '').ToLowerInvariant(); $d = $f.LastWriteTimeUtc
        if (-not $pf.ContainsKey($k) -or $pf[$k] -lt $d) { $pf[$k] = $d }
    }
    $raices = @($env:SystemDrive, $env:windir, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\').ToLowerInvariant() }
    function Get-UltimoUso($i) {
        $loc = $null; if ($i.InstallLocation) { $loc = ([string]$i.InstallLocation).Trim('"', ' ', '\') }
        if (-not $loc -and $i.DisplayIcon) { $ic = (([string]$i.DisplayIcon) -replace ',\s*-?\d+$', '').Trim('"'); if ($ic -match '(?i)\.exe$') { $loc = Split-Path $ic -Parent } }
        # Sin carpeta propia (o una carpeta general del sistema) no se puede atribuir ningún .exe al programa
        if (-not $loc -or $loc.Length -lt 6 -or ($raices -contains $loc.TrimEnd('\').ToLowerInvariant()) -or -not (Test-Path -LiteralPath $loc)) { return $null }
        $mejor = $null; $pre = $loc.Substring(2).TrimEnd('\').ToLowerInvariant() + '\'
        foreach ($k in $bam.Keys) { if ($k.StartsWith($pre) -and ($null -eq $mejor -or $mejor -lt $bam[$k])) { $mejor = $bam[$k] } }
        if ($pf.Count) { foreach ($e in @(Get-ChildItem -LiteralPath $loc -Filter *.exe -File -Depth 1 -ErrorAction SilentlyContinue)) { $k = $e.Name.ToLowerInvariant(); if ($pf.ContainsKey($k) -and ($null -eq $mejor -or $mejor -lt $pf[$k])) { $mejor = $pf[$k] } } }
        $mejor
    }
    foreach ($c in $claves) {
        foreach ($i in @(Get-ItemProperty -Path $c.R -ErrorAction SilentlyContinue)) {
            # Mismos filtros que «Desinstalador de apps»: sin componentes del sistema, sin actualizaciones y solo lo que tiene desinstalador
            if (-not $i.DisplayName -or $i.SystemComponent -eq 1 -or $i.ParentKeyName -or -not ($i.UninstallString -or $i.QuietUninstallString)) { continue }
            if ($i.DisplayName -like 'Paquete de controladores de Windows*' -or $i.DisplayName -like 'Windows Driver Package*') { continue }   # drivers: se gestionan desde «Limpiar almacén de drivers»
            $clave = ([string]$i.DisplayName + '|' + [string]$i.DisplayVersion).ToLowerInvariant(); if ($vistos[$clave]) { continue }; $vistos[$clave] = $true
            Emit @{ evento = 'programa'; nombre = [string]$i.DisplayName; editor = [string]$i.Publisher; version = [string]$i.DisplayVersion; mb = $(if ($i.EstimatedSize) { [int][math]::Round($i.EstimatedSize / 1024) } else { 0 }); fecha = [string]$i.InstallDate; ambito = $c.A; ultimoUso = $(try { $u = Get-UltimoUso $i; if ($u) { $u.ToLocalTime().ToString('yyyy-MM-dd') } else { '' } } catch { '' }) }
        }
    }
    Emit @{ evento = 'fin'; esAdmin = (Test-EsAdmin) }
    exit 0
}

# ---------- Registro: restos de programas borrados ----------
# Todo el borrado (copia .reg en cuarentena, punto de restauración) lo hace Limpiar_Registro_Huerfano.ps1; aquí solo se lanza y se cuenta lo que dice.
if ($Accion -eq 'RegistroAnalizar' -or $Accion -eq 'RegistroLimpiar') {
    $script = Join-Path $PSScriptRoot 'Mantenimiento\Limpiar_Registro_Huerfano.ps1'
    $m = Test-ScriptAutorizado $script
    if ($m) { Emit @{ evento = 'error'; mensaje = "No se ejecuta Limpiar_Registro_Huerfano.ps1: $m" }; exit 1 }
    if ($Accion -eq 'RegistroAnalizar') {
        foreach ($l in @(& $script -SoloAnalizar *>&1 | ForEach-Object { [string]$_ })) {
            if ($l -match '^\s+\[(Alta|Media|Baja)\]\s+(.+?):\s+(.*)$') { Emit @{ evento = 'resto'; conf = $Matches[1]; grupo = $Matches[2]; detalle = $Matches[3] } }
        }
        Emit @{ evento = 'fin'; esAdmin = (Test-EsAdmin) }
        exit 0
    }
    if (-not (Test-EsAdmin)) { Emit @{ evento = 'error'; mensaje = 'Hace falta administrador para limpiar el registro. Abre la app como administrador.' }; exit 1 }
    Emit @{ evento = 'inicio' }
    $global:LASTEXITCODE = 0
    if ($Modo -eq 'Manual') { & $script | Out-Null } else { & $script -Auto *>&1 | ForEach-Object { $s = ([string]$_).Trim(); if ($s) { Emit @{ evento = 'salida'; texto = $s } } } }
    $c = $LASTEXITCODE
    Emit @{ evento = 'fin'; codigo = $c }
    exit $c
}

# «Desinstalador de apps» tiene su propia ventana (restos, cuarentena reversible): aquí solo se abre sobre el programa elegido
if ($Accion -eq 'DesinstalarFondo') {
    $script = Join-Path $PSScriptRoot 'Mantenimiento\Desinstalar_Total.ps1'
    $m = Test-ScriptAutorizado $script
    if ($m) { Emit @{ evento = 'error'; mensaje = "No se ejecuta Desinstalar_Total.ps1: $m" }; exit 1 }
    if (-not $Nombres.Count -or ($Nombres | Where-Object { -not $_ -or $_.Length -gt 300 })) { Emit @{ evento = 'error'; mensaje = 'Falta el nombre del programa.' }; exit 1 }
    Emit @{ evento = 'inicio' }
    $global:LASTEXITCODE = 0
    # El script cuenta lo que hace (programa n de m, restos, cuarentena): se reenvía línea a línea para que la ventana muestre el avance
    & $script -Nombre $Nombres *>&1 | ForEach-Object { $s = ([string]$_).Trim(); if ($s) { Emit @{ evento = 'salida'; texto = $s } } }
    $c = $LASTEXITCODE
    Emit @{ evento = 'fin'; codigo = $c }
    exit $c
}

# ---------- Programas de inicio ----------
$cv = 'SOFTWARE\Microsoft\Windows\CurrentVersion'; $ap = "$cv\Explorer\StartupApproved"
$fuentes = @(
    @{ Amb = 'Todos los usuarios'; Run = "HKLM:\$cv\Run"; Ap = "HKLM:\$ap\Run" }
    @{ Amb = 'Todos (32 bits)'; Run = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Ap = "HKLM:\$ap\Run32" }
    @{ Amb = "Usuario $env:USERNAME"; Run = "HKCU:\$cv\Run"; Ap = "HKCU:\$ap\Run" }
    @{ Amb = 'Todos los usuarios (carpeta Inicio)'; Dir = [Environment]::GetFolderPath('CommonStartup'); Ap = "HKLM:\$ap\StartupFolder" }
    @{ Amb = "Usuario $env:USERNAME (carpeta Inicio)"; Dir = [Environment]::GetFolderPath('Startup'); Ap = "HKCU:\$ap\StartupFolder" }
)
# Activo si no hay marca o su primer byte es par (02 = activado, 03 = desactivado): el mismo interruptor del Administrador de tareas
function Test-Activo([string]$clave, [string]$nombre) {
    try { $b = (Get-Item -LiteralPath $clave -ErrorAction Stop).GetValue($nombre, $null); if ($b -is [byte[]] -and $b.Length) { return ($b[0] % 2) -eq 0 } } catch { }
    $true
}

if ($Accion -eq 'InicioListar') {
    foreach ($f in $fuentes) {
        if ($f.Run) {
            if (-not (Test-Path -LiteralPath $f.Run)) { continue }
            $k = Get-Item -LiteralPath $f.Run
            foreach ($n in $k.GetValueNames()) { if ($n) { Emit @{ evento = 'inicio'; tipo = 'registro'; id = "$($f.Ap)|$n"; nombre = $n; ambito = $f.Amb; orden = [string]$k.GetValue($n); activo = (Test-Activo $f.Ap $n) } } }
        } elseif ($f.Dir -and (Test-Path -LiteralPath $f.Dir)) {
            foreach ($a in Get-ChildItem -LiteralPath $f.Dir -File -Force -ErrorAction SilentlyContinue) { if ($a.Name -ne 'desktop.ini') { Emit @{ evento = 'inicio'; tipo = 'registro'; id = "$($f.Ap)|$($a.Name)"; nombre = $a.Name; ambito = $f.Amb; orden = $a.FullName; activo = (Test-Activo $f.Ap $a.Name) } } }
        }
    }
    foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -notlike '\Microsoft\*' -and ($_.Triggers | Where-Object { $_.CimClass.CimClassName -in 'MSFT_TaskLogonTrigger', 'MSFT_TaskBootTrigger' }) })) {
        Emit @{ evento = 'inicio'; tipo = 'tarea'; id = "$($t.TaskPath)|$($t.TaskName)"; nombre = $t.TaskName; ambito = 'Tarea programada'; orden = (@($t.Actions | ForEach-Object { $_.Execute }) -join ', '); activo = ($t.State -ne 'Disabled') }
    }
    # Último arranque medido por el propio Windows (Diagnostics-Performance) y qué lo ralentizó; solo se informa si el registro lo permite leer
    try {
        $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 100, 101, 102, 103 } -MaxEvents 60 -ErrorAction Stop)
        $b = $ev | Where-Object Id -eq 100 | Select-Object -First 1
        if ($b) {
            $dato = @{}; foreach ($d in ([xml]$b.ToXml()).Event.EventData.Data) { $dato[[string]$d.Name] = [string]$d.'#text' }
            $lentos = @(foreach ($e in ($ev | Where-Object { $_.Id -in 101, 102, 103 -and [math]::Abs(($_.TimeCreated - $b.TimeCreated).TotalSeconds) -lt 180 })) {
                $v = @{}; foreach ($d in ([xml]$e.ToXml()).Event.EventData.Data) { $v[[string]$d.Name] = [string]$d.'#text' }
                $n = if ($v['FriendlyName']) { $v['FriendlyName'] } else { $v['Name'] }; if ($n) { $n }
            }) | Select-Object -Unique
            if ($dato['BootTime'] -match '^\d+$') {
                Emit @{ evento = 'arranque'; segundos = [int]([int64]$dato['BootTime'] / 1000); escritorio = $(if ($dato['MainPathBootTime'] -match '^\d+$') { [int]([int64]$dato['MainPathBootTime'] / 1000) } else { 0 }); fecha = $b.TimeCreated.ToString('yyyy-MM-dd'); lentos = @($lentos | Select-Object -First 6) }
            }
        }
    } catch { }
    Emit @{ evento = 'fin'; esAdmin = (Test-EsAdmin) }
    exit 0
}

if ($Accion -eq 'InicioCambiar') {
    try {
        [void](Start-OperacionSegura 'Programas de inicio (Limpieza)' -SinPuntoRestauracion)
        $partes = $Id -split '\|', 2
        if ($Tipo -eq 'registro') {
            if ($partes.Count -ne 2 -or $partes[0] -notmatch '^HK(LM|CU):\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\') { throw 'Elemento de inicio no válido.' }
            if ($partes[0] -like 'HKLM:*' -and -not (Test-EsAdmin)) { throw 'Hace falta administrador para cambiar los programas de todos los usuarios.' }
            Set-ValorSeguro $partes[0] $partes[1] ([byte[]]($(if ($Activar) { 2 } else { 3 }), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) 'Binary'
        } elseif ($Tipo -eq 'tarea') {
            if ($partes.Count -ne 2 -or -not (Test-EsAdmin)) { throw 'Hace falta administrador para cambiar tareas programadas.' }
            # Sin comodines ni «..»: la ruta empieza por «\» y el nombre no lleva separadores (así no se toca más de una tarea)
            if ($partes[0] -notmatch '^\\' -or $partes[0] -match '[\*\?]|\.\.' -or $partes[1] -match '[\*\?\\/]' -or -not $partes[1].Trim()) { throw 'Tarea programada no válida.' }
            if ($Activar) { Enable-ScheduledTask -TaskPath $partes[0] -TaskName $partes[1] -ErrorAction Stop | Out-Null } else { Disable-ScheduledTask -TaskPath $partes[0] -TaskName $partes[1] -ErrorAction Stop | Out-Null }
        } else { throw 'Tipo de inicio no válido.' }
        Emit @{ evento = 'fin'; ok = $true }
        Write-Log "Limpieza_Motor: inicio $Tipo '$Id' -> $(if ($Activar) { 'activado' } else { 'desactivado' })"
        exit 0
    } catch { Emit @{ evento = 'error'; mensaje = $_.Exception.Message }; exit 1 }
}
