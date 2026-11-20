# =====================================================================
#  Auditoria_Seguridad.ps1 - Revisión de seguridad de solo lectura (Nitrit0)
#  Para «¿este equipo está protegido?», «creo que tiene algo raro» o antes de entregarlo. NO cambia nada: mira y avisa.
#    · Antivirus (Defender u otro), protección en tiempo real y antigüedad de las firmas.
#    · Firewall por perfil, UAC, inicio de sesión automático con contraseña guardada, Escritorio remoto, SMB1.
#    · Tareas programadas y servicios de arranque que ejecutan programas desde carpetas de usuario o temporales
#      (lo típico del malware y de programas mal instalados; puede haber falsos positivos legítimos).
#    · Cuentas de administrador locales y certificados raíz caducados.
#  Algunas lecturas son más completas con administrador. Salida: 0 bien · 1 error
# =====================================================================
[CmdletBinding()]
param()
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
$avisos = 0
function Say([string]$nivel, [string]$t) { if ($nivel -eq 'aviso') { $script:avisos++ }; $i = switch ($nivel) { 'ok' { $E.OK } 'aviso' { $E.Aviso } default { $E.Info } }; Write-Output "    $i $t" }
if (-not (Test-EsAdmin)) { Write-Output "  $($E.Info) Sin administrador algunas lecturas pueden salir incompletas." }

Write-Output "  $($E.Lupa) Antivirus"
try {
    $av = @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop)
    if ($av.Count) { Say 'info' ("Productos registrados: " + (($av | ForEach-Object { $_.displayName }) -join ', ')) } else { Say 'aviso' 'Windows no tiene ningún antivirus registrado.' }
} catch { Say 'info' 'No se pudo leer el Centro de seguridad (en Windows Server no existe).' }
try {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    if ($null -eq $mp.RealTimeProtectionEnabled) { throw 'Defender no informa de su estado' }
    Say $(if ($mp.RealTimeProtectionEnabled) { 'ok' } else { 'aviso' }) "Defender · protección en tiempo real: $(if ($mp.RealTimeProtectionEnabled) { 'activa' } else { 'DESACTIVADA' })"
    $edad = if ($mp.AntivirusSignatureLastUpdated) { [int]((Get-Date) - $mp.AntivirusSignatureLastUpdated).TotalDays } else { 999 }
    Say $(if ($edad -le 7) { 'ok' } else { 'aviso' }) "Defender · firmas de hace $edad día(s)$(if ($edad -gt 7) { ' (desactualizadas)' })"
    $esc = $mp.QuickScanEndTime; if ($esc) { Say 'info' "Último análisis rápido: $($esc.ToString('dd/MM/yyyy'))" }
} catch { Say 'info' 'Defender no responde (puede haber otro antivirus que lo sustituye).' }

Write-Output "  $($E.Lupa) Configuración de seguridad"
try { foreach ($p in Get-NetFirewallProfile -ErrorAction Stop) { Say $(if ($p.Enabled -eq 'True') { 'ok' } else { 'aviso' }) "Firewall · perfil $($p.Name): $(if ($p.Enabled -eq 'True') { 'activo' } else { 'DESACTIVADO' })" } } catch { Say 'info' 'No se pudo leer el firewall.' }
$sys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
# Una lectura que falla no es «todo bien»: se dice que no se pudo leer en vez de dar el verde
$lua = $null; $luaOk = $false; try { $lua = (Get-ItemProperty -LiteralPath $sys -Name EnableLUA -ErrorAction Stop).EnableLUA; $luaOk = $true } catch { }
if (-not $luaOk) { Say 'info' 'Control de cuentas de usuario (UAC): no se pudo leer el ajuste.' } else { Say $(if ($lua -eq 0) { 'aviso' } else { 'ok' }) "Control de cuentas de usuario (UAC): $(if ($lua -eq 0) { 'DESACTIVADO' } else { 'activo' })" }
$wl = $null; try { $wl = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction Stop } catch { }
if (-not $wl) { Say 'info' 'Inicio de sesión automático: no se pudo leer el ajuste.' }
elseif ($wl.AutoAdminLogon -eq '1') { Say 'aviso' "Inicio de sesión automático activado$(if ($wl.DefaultPassword) { ' con la contraseña guardada en claro en el registro' })." } else { Say 'ok' 'Sin inicio de sesión automático.' }
$rdp = $null; $rdpOk = $false; try { $rdp = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -ErrorAction Stop).fDenyTSConnections; $rdpOk = $true } catch { }
if (-not $rdpOk) { Say 'info' 'Escritorio remoto: no se pudo leer el ajuste.' } else { Say $(if ($rdp -eq 0) { 'aviso' } else { 'ok' }) "Escritorio remoto: $(if ($rdp -eq 0) { 'ACTIVADO (comprueba que es intencionado)' } else { 'desactivado' })" }
try { if ((Get-SmbServerConfiguration -ErrorAction Stop).EnableSMB1Protocol) { Say 'aviso' 'SMB1 (protocolo obsoleto) activado.' } else { Say 'ok' 'SMB1 desactivado.' } } catch { }

Write-Output "  $($E.Lupa) Cuentas y certificados"
$nombresAdm = $null
try { $nombresAdm = @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop | ForEach-Object { $_.Name }) } catch {
    # Get-LocalGroupMember falla si el grupo tiene un SID huérfano (cuentas de dominio o Entra ID borradas): se lee por ADSI
    try { $g = [ADSI]'WinNT://./Administrators,group'; $nombresAdm = @($g.Invoke('Members') | ForEach-Object { $_.GetType().InvokeMember('Name', 'GetProperty', $null, $_, $null) }) } catch { }
}
if ($null -ne $nombresAdm) { Say $(if ($nombresAdm.Count -gt 3) { 'aviso' } else { 'info' }) ("Administradores locales ($($nombresAdm.Count)): " + ($nombresAdm -join ', ')) } else { Say 'info' 'No se pudo listar el grupo de administradores.' }
try { $cad = @(Get-ChildItem Cert:\LocalMachine\Root -ErrorAction Stop | Where-Object { $_.NotAfter -lt (Get-Date) }); Say 'info' "Certificados raíz caducados: $($cad.Count) (normal que haya algunos antiguos)." } catch { }

# Rutas donde un programa legítimo casi nunca debería arrancar solo
$sospechosa = '(?i)\\(AppData|Temp|Users\\Public|Downloads|Local\\Temp)\\|^"?[A-Z]:\\ProgramData\\(?!Microsoft\\)'
# Actualizadores conocidos que viven en AppData: se muestran como información, no como aviso
$conocidos = '(?i)\\(Google|Microsoft|Opera( GX| Software)?|BraveSoftware|Discord|Spotify|Zoom|Slack|OneDrive|Programs\\Opera[^\\]*)\\'
# Intérpretes que el malware usa para lanzar un script desde una carpeta de usuario o con comando codificado
$interprete = '(?i)\\(powershell|pwsh|cmd|wscript|cscript|mshta|rundll32|regsvr32)(\.exe)?$'
$argSospechoso = '(?i)-e(nc|ncodedcommand)\b|\\(AppData|Temp|Users\\Public|Downloads)\\'
Write-Output "  $($E.Lupa) Tareas programadas y servicios que arrancan desde carpetas de usuario"
$halladas = 0
try {
    foreach ($t in @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.State -ne 'Disabled' -and $_.TaskPath -notlike '\Microsoft\*' })) {
        foreach ($a in @($t.Actions)) {
            $ex = [Environment]::ExpandEnvironmentVariables([string]$a.Execute); $args1 = [string]$a.Arguments
            if ($ex -match $interprete -and $args1 -match $argSospechoso) { $halladas++; Say 'aviso' "Tarea «$($t.TaskName)»: $ex $args1"; break }
            if ($ex -match $sospechosa) { $halladas++; Say $(if ($ex -match $conocidos) { 'info' } else { 'aviso' }) "Tarea «$($t.TaskName)»: $ex$(if ($ex -match $conocidos) { ' (actualizador conocido)' })"; break }
        }
    }
} catch { Say 'info' 'No se pudieron leer las tareas programadas.' }
foreach ($s in @(Get-CimInstance Win32_Service -Filter "StartMode='Auto'" -ErrorAction SilentlyContinue)) {
    $ruta = [string]$s.PathName; if ($ruta -match $sospechosa) { $halladas++; Say $(if ($ruta -match $conocidos) { 'info' } else { 'aviso' }) "Servicio «$($s.DisplayName)» ($($s.Name)): $ruta" }
}
if (-not $halladas) { Say 'ok' 'Ninguna tarea ni servicio arranca desde carpetas de usuario o temporales.' }

Write-Output "`n  $(if ($avisos) { $E.Aviso + " $avisos punto(s) a revisar (no tienen por qué ser un problema: míralos con calma)." } else { $E.OK + ' Sin puntos que revisar.' })"
Write-Log "Auditoria_Seguridad: $avisos aviso(s)"
Exit-Kit 'Ok'
