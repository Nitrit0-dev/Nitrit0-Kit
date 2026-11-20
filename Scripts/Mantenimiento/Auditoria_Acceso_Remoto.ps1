# =====================================================================
#  Auditoria_Acceso_Remoto.ps1 - ¿Puede alguien entrar o controlar este equipo a distancia? (Nitrit0)
#  Solo lee: no cambia ni borra nada. Revisa lo que suele quedar tras una estafa de «soporte técnico», un acceso olvidado o un equipo prestado:
#   1) programas de control remoto instalados o en marcha (AnyDesk, TeamViewer, RustDesk, ScreenConnect, VNC, RMM…),
#   2) funciones de Windows que permiten entrar (Escritorio remoto, Asistencia remota, WinRM, SSH) y puertos de escucha típicos,
#   3) cuentas: administradores, cuentas ocultas de la pantalla de inicio de sesión y cuentas con «$»,
#   4) puertas traseras clásicas en la pantalla de bloqueo (sethc, utilman…) y proxy forzado,
#   5) tareas programadas que ejecutan órdenes ocultas o desde carpetas temporales.
#  Que algo salga como «revisar» no prueba que haya un problema: puede ser tuyo. Sirve para saber qué mirar.
#  Salida: 0 bien
# =====================================================================
[CmdletBinding()]
param()
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
$revisar = New-Object Collections.Generic.List[string]
function Add-Revisar([string]$t) { $revisar.Add($t) }
function Write-Seccion([string]$t) { Write-Output "`n  $($E.Lupa) $t" }
Write-Output "========================================================"
Write-Output "  $($E.Cohete) AUDITORÍA DE ACCESO REMOTO"
Write-Output "========================================================"
Write-Output "  $($E.Info) Solo lectura: no se cambia nada. $(if (-not (Test-EsAdmin)) { 'Sin administrador algunos datos (procesos de otros usuarios, tareas del sistema) pueden faltar.' })"

# ---------------------------------------------------------------- 1) Programas de control remoto
Write-Seccion '1) Programas de control remoto'
$patron = '(?i)anydesk|teamviewer|rustdesk|screenconnect|connectwise|splashtop|logmein|ultraviewer|ammyy|\bsupremo\b|\bradmin\b|tightvnc|ultravnc|realvnc|tigervnc|\bvnc\b|chrome remote|chromoting|dwservice|dwagent|meshagent|mesh agent|\batera\b|ninjarmm|ninja ?rmm|\bn-able\b|\bkaseya\b|\bdatto\b|zoho assist|zohoassist|gotoassist|gotomypc|beyondtrust|\bbomgar\b|\bparsec\b|nomachine|remote utilities|remoteutilities|aeroadmin|\bgetscreen\b|\bsimplehelp\b|\baction1\b|pdq connect|level\.io|\bhopto\b|\bngrok\b|\bzerotier\b|\btailscale\b|rdpwrap|rdp wrapper|\bnetsupport\b|ammyadmin|remotepc|anyviewer|helpwire'
$encontrados = New-Object Collections.Generic.List[object]
foreach ($r in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*') {
    foreach ($i in @(Get-ItemProperty -Path $r -ErrorAction SilentlyContinue)) { if ($i.DisplayName -and $i.DisplayName -match $patron) { $encontrados.Add([pscustomobject]@{ Donde = 'Instalado'; Nombre = "$($i.DisplayName) $($i.DisplayVersion)".Trim(); Detalle = [string]$i.Publisher }) } }
}
foreach ($s in @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue)) {
    if (("$($s.Name) $($s.DisplayName)" -match $patron) -or ($s.PathName -and $s.PathName -match $patron)) { $encontrados.Add([pscustomobject]@{ Donde = "Servicio ($($s.State), inicio $($s.StartMode))"; Nombre = $s.DisplayName; Detalle = [string]$s.PathName }) }
}
foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
    if ($p.ProcessName -match $patron) { $ruta = ''; try { $ruta = $p.Path } catch { }; $encontrados.Add([pscustomobject]@{ Donde = 'En marcha ahora'; Nombre = $p.ProcessName; Detalle = $ruta }) }
}
if (-not $encontrados.Count) { Write-Output "    $($E.OK) No hay programas de control remoto conocidos instalados ni en marcha." }
else {
    foreach ($g in ($encontrados | Group-Object Nombre | Sort-Object Name)) {
        Write-Output "    $($E.Aviso) $($g.Name)  ·  $((@($g.Group | ForEach-Object { $_.Donde } | Select-Object -Unique)) -join ' · ')"
        $det = @($g.Group | Where-Object Detalle | Select-Object -First 1); if ($det) { Write-Output "         $($det.Detalle)" }
        Add-Revisar "Programa de control remoto: $($g.Name)"
    }
    Write-Output "    $($E.Info) Si no lo instalaste tú o no lo usas, desinstálalo y cambia las contraseñas que se hayan podido ver."
}

# ---------------------------------------------------------------- 2) Funciones de Windows y puertos
Write-Seccion '2) Funciones de Windows que permiten entrar'
$ts = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
try {
    $deny = (Get-ItemProperty -LiteralPath $ts -Name fDenyTSConnections -ErrorAction Stop).fDenyTSConnections
    if ($deny -eq 0) {
        $nla = (Get-ItemProperty -LiteralPath "$ts\WinStations\RDP-Tcp" -Name UserAuthentication -ErrorAction SilentlyContinue).UserAuthentication
        $pt = (Get-ItemProperty -LiteralPath "$ts\WinStations\RDP-Tcp" -Name PortNumber -ErrorAction SilentlyContinue).PortNumber
        Write-Output "    $($E.Aviso) Escritorio remoto ACTIVADO (puerto $pt$(if ($pt -ne 3389) { ', no es el habitual' }); autenticación a nivel de red: $(if ($nla -eq 1) { 'sí' } else { 'NO' }))."
        Add-Revisar 'Escritorio remoto activado'; if ($nla -ne 1) { Add-Revisar 'Escritorio remoto sin autenticación a nivel de red' }
    } else { Write-Output "    $($E.OK) Escritorio remoto desactivado." }
} catch { Write-Output "    $($E.Info) No se pudo leer el estado del Escritorio remoto." }
try { $ra = (Get-ItemProperty -LiteralPath $ts -Name fAllowToGetHelp -ErrorAction Stop).fAllowToGetHelp; if ($ra -eq 1) { Write-Output "    $($E.Aviso) Asistencia remota permitida."; Add-Revisar 'Asistencia remota permitida' } else { Write-Output "    $($E.OK) Asistencia remota no permitida." } } catch { }
foreach ($sv in @(@('WinRM', 'Administración remota de Windows (WinRM)'), @('sshd', 'Servidor SSH'), @('TlntSvr', 'Servidor Telnet'), @('RemoteRegistry', 'Registro remoto'), @('TermService', 'Servicios de Escritorio remoto'))) {
    $s = Get-Service -Name $sv[0] -ErrorAction SilentlyContinue
    if ($s -and $s.Status -eq 'Running') { if ($sv[0] -eq 'TermService') { continue }; Write-Output "    $($E.Aviso) $($sv[1]) en marcha."; Add-Revisar "$($sv[1]) en marcha" }
}
$puertos = @{ 3389 = 'Escritorio remoto'; 5900 = 'VNC'; 5901 = 'VNC'; 5902 = 'VNC'; 5938 = 'TeamViewer'; 7070 = 'AnyDesk'; 22 = 'SSH'; 23 = 'Telnet'; 5985 = 'WinRM'; 5986 = 'WinRM (HTTPS)'; 21115 = 'RustDesk'; 21116 = 'RustDesk'; 21118 = 'RustDesk'; 8040 = 'ScreenConnect' }
try {
    $esc = @(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object { $puertos.ContainsKey([int]$_.LocalPort) -and $_.LocalAddress -notin '127.0.0.1', '::1' })
    if ($esc) { foreach ($c in ($esc | Sort-Object LocalPort -Unique)) { $pn = ''; try { $pn = (Get-Process -Id $c.OwningProcess -ErrorAction Stop).ProcessName } catch { }; Write-Output "    $($E.Aviso) Escuchando en el puerto $($c.LocalPort) ($($puertos[[int]$c.LocalPort]))$(if ($pn) { " · $pn" })."; Add-Revisar "Puerto $($c.LocalPort) ($($puertos[[int]$c.LocalPort])) a la escucha" } }
    else { Write-Output "    $($E.OK) Ningún puerto de acceso remoto habitual está a la escucha desde fuera del equipo." }
} catch { Write-Output "    $($E.Info) No se pudo mirar los puertos a la escucha." }

# ---------------------------------------------------------------- 3) Cuentas
Write-Seccion '3) Cuentas'
try {
    $admins = @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop)
    Write-Output "    $($E.Info) Administradores de este equipo ($($admins.Count)):"
    foreach ($a in $admins) {
        $corto = ($a.Name -split '\\')[-1]; $u = $null; try { $u = Get-LocalUser -Name $corto -ErrorAction Stop } catch { }
        $est = if ($u) { "$(if ($u.Enabled) { 'activa' } else { 'desactivada' }), último acceso: $(if ($u.LastLogon) { $u.LastLogon.ToString('dd/MM/yyyy') } else { 'nunca' })" } else { 'cuenta de dominio o de grupo' }
        Write-Output "         · $($a.Name)  ($est)"
        if ($u -and $u.Enabled -and $a.Name -notmatch "(?i)\\$([regex]::Escape($env:USERNAME))$") { Add-Revisar "Administrador activo: $($a.Name)" }
    }
} catch { Write-Output "    $($E.Info) No se pudieron leer los administradores." }
try {
    $ocultas = New-Object Collections.Generic.List[string]
    $ul = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList'
    if (Test-Path -LiteralPath $ul) { $k = Get-Item -LiteralPath $ul; foreach ($n in $k.GetValueNames()) { if ([int]$k.GetValue($n) -eq 0) { $ocultas.Add($n) } } }
    foreach ($u in @(Get-LocalUser -ErrorAction Stop)) { if ($u.Name.EndsWith('$')) { $ocultas.Add("$($u.Name) (nombre con «$»)") } }
    if ($ocultas.Count) { foreach ($o in ($ocultas | Select-Object -Unique)) { Write-Output "    $($E.Aviso) Cuenta oculta de la pantalla de inicio de sesión: $o"; Add-Revisar "Cuenta oculta: $o" } }
    else { Write-Output "    $($E.OK) No hay cuentas ocultas de la pantalla de inicio de sesión." }
} catch { }

# ---------------------------------------------------------------- 4) Puertas traseras en la pantalla de bloqueo y proxy
Write-Seccion '4) Puertas traseras y desvío del tráfico'
$ifeo = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'; $mal = 0
foreach ($exe in 'sethc.exe', 'utilman.exe', 'osk.exe', 'narrator.exe', 'magnify.exe', 'displayswitch.exe', 'atbroker.exe') {
    $dbg = $null; try { $dbg = (Get-ItemProperty -LiteralPath "$ifeo\$exe" -Name Debugger -ErrorAction Stop).Debugger } catch { }
    if ($dbg) { $mal++; Write-Output "    $($E.Error) $exe tiene un «depurador» que lo sustituye: $dbg (así se abre una consola de administrador desde la pantalla de inicio de sesión)."; Add-Revisar "Puerta trasera en $exe" }
}
try {
    $hCmd = (Get-FileHash -LiteralPath "$env:SystemRoot\System32\cmd.exe" -Algorithm SHA256).Hash
    foreach ($exe in 'sethc.exe', 'utilman.exe') { $f = "$env:SystemRoot\System32\$exe"; if ((Test-Path -LiteralPath $f) -and ((Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash -eq $hCmd)) { $mal++; Write-Output "    $($E.Error) $exe es una copia de cmd.exe: puerta trasera en la pantalla de inicio de sesión."; Add-Revisar "$exe es una copia de cmd.exe" } }
} catch { }
if (-not $mal) { Write-Output "    $($E.OK) Sin sustituciones en la pantalla de bloqueo (sethc, utilman, osk…)." }
$prox = 0
foreach ($rp in 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings') {
    try { $ps = Get-ItemProperty -LiteralPath $rp -ErrorAction Stop; if ($ps.ProxyEnable -eq 1 -and $ps.ProxyServer) { $prox++; Write-Output "    $($E.Aviso) Proxy activado ($($rp.Substring(0, 4))): $($ps.ProxyServer)"; Add-Revisar "Proxy forzado: $($ps.ProxyServer)" }; if ($ps.AutoConfigURL) { $prox++; Write-Output "    $($E.Aviso) Script de configuración automática del proxy: $($ps.AutoConfigURL)"; Add-Revisar 'Proxy con script automático' } } catch { }
}
if (-not $prox) { Write-Output "    $($E.OK) Sin proxy forzado en el navegador/Windows." }

# ---------------------------------------------------------------- 5) Tareas programadas sospechosas
Write-Seccion '5) Tareas programadas que no son de Microsoft'
$sosp = 0
try {
    foreach ($t in @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskPath -notlike '\Microsoft\*' -and $_.State -ne 'Disabled' })) {
        foreach ($a in @($t.Actions)) {
            $linea = "$($a.Execute) $($a.Arguments)"
            $motivo = $null
            if ($linea -match '(?i)-enc(odedcommand)?\s|frombase64string|downloadstring|invoke-expression|\biex\b|-w(indowstyle)?\s+hidden|-nop\b.*-w\b') { $motivo = 'orden oculta o codificada' }
            elseif ($a.Execute -match '(?i)\\(Temp|Downloads)\\|\\AppData\\Local\\Temp\\|\\Users\\Public\\') { $motivo = 'se ejecuta desde una carpeta temporal o pública' }
            elseif ($linea -match $patron) { $motivo = 'es un programa de control remoto' }
            if ($motivo) { $sosp++; Write-Output "    $($E.Aviso) $($t.TaskName): $motivo"; Write-Output "         $($linea.Trim())"; Add-Revisar "Tarea «$($t.TaskName)»: $motivo" }
        }
    }
    if (-not $sosp) { Write-Output "    $($E.OK) Ninguna tarea con órdenes ocultas ni que se ejecute desde carpetas temporales." }
} catch { Write-Output "    $($E.Info) No se pudieron leer las tareas programadas." }

# ---------------------------------------------------------------- Resumen
Write-Output "`n========================================================"
if ($revisar.Count) {
    Write-Output "  $($E.Aviso) $($revisar.Count) cosa(s) para REVISAR:"
    foreach ($r in $revisar) { Write-Output "     · $r" }
    Write-Output "`n  $($E.Info) «Revisar» no es «infectado»: un administrador o un programa remoto pueden ser tuyos. Si no reconoces algo, desactívalo y cambia las contraseñas desde otro equipo."
} else { Write-Output "  $($E.OK) No se ha visto nada que permita el acceso remoto sin que lo sepas." }
Write-Output "========================================================"
Write-Log "Auditoria_Acceso_Remoto: $($revisar.Count) puntos a revisar"
exit 0
