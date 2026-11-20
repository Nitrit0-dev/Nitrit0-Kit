# =====================================================================
#  Deshacer_Dano_Optimizadores.ps1 - Repara lo que dejan los «optimizadores» y scripts de debloat (Nitrit0)
#  Busca lo que esas herramientas suelen estropear y deja elegir qué devolver a su valor normal de Windows:
#   - servicios que Windows necesita puestos en «Deshabilitado» (actualizaciones, Tienda, antivirus, firewall, registro de eventos…),
#   - políticas que bloquean Windows Update, la Tienda o Microsoft Defender,
#   - servidores de Microsoft bloqueados en el archivo hosts (se comentan, no se borran),
#   - pausas de Windows Update que no caducan nunca.
#  Todo se registra y se deshace con «Deshacer cambios»; el archivo hosts se copia antes de tocarlo.
#  Parámetro: -SoloAnalizar (solo enseña lo que encuentra)
#  Salida: 0 bien · 1 error · 2 cancelado
# =====================================================================
[CmdletBinding()]
param([switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
if (-not $SoloAnalizar) { Assert-Admin 'devolver a Windows lo que otras herramientas desactivaron' }

# Servicios que Windows necesita y su inicio de fábrica (Manual o Automatic)
$servicios = [ordered]@{
    wuauserv = @('Windows Update', 'Manual'); BITS = @('Servicio de transferencia inteligente (BITS)', 'Manual'); UsoSvc = @('Orquestador de actualizaciones', 'Manual'); WaaSMedicSvc = @('Reparación de Windows Update', 'Manual')
    InstallService = @('Servicio de instalación de Microsoft Store', 'Manual'); ClipSVC = @('Licencias de aplicaciones de la Tienda', 'Manual'); AppXSvc = @('Implementación de aplicaciones (AppX)', 'Manual'); LicenseManager = @('Administrador de licencias', 'Manual')
    StateRepository = @('Repositorio de estado de aplicaciones', 'Manual'); TrustedInstaller = @('Instalador de módulos de Windows', 'Manual'); CryptSvc = @('Servicios criptográficos', 'Automatic'); Winmgmt = @('Instrumental de administración (WMI)', 'Automatic')
    EventLog = @('Registro de eventos de Windows', 'Automatic'); mpssvc = @('Firewall de Windows', 'Automatic'); WinDefend = @('Antivirus de Microsoft Defender', 'Automatic'); wscsvc = @('Centro de seguridad', 'Automatic')
}
# Políticas que bloquean funciones de Windows (se quitan: Windows vuelve a su comportamiento normal)
$politicas = @(
    @{ Ruta = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; Nombre = 'DisableWindowsUpdateAccess'; Mal = 1; Texto = 'Acceso a Windows Update bloqueado por política' }
    @{ Ruta = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; Nombre = 'DoNotConnectToWindowsUpdateInternetLocations'; Mal = 1; Texto = 'Windows Update sin poder conectar a Internet (política)' }
    @{ Ruta = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'; Nombre = 'NoAutoUpdate'; Mal = 1; Texto = 'Actualizaciones automáticas desactivadas por política' }
    @{ Ruta = 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore'; Nombre = 'RemoveWindowsStore'; Mal = 1; Texto = 'Microsoft Store desactivada por política' }
    @{ Ruta = 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore'; Nombre = 'DisableStoreApps'; Mal = 1; Texto = 'Aplicaciones de la Store bloqueadas por política' }
    @{ Ruta = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'; Nombre = 'DisableAntiSpyware'; Mal = 1; Texto = 'Microsoft Defender desactivado por política (solo tiene sentido con otro antivirus)' }
    @{ Ruta = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; Nombre = 'DisableRealtimeMonitoring'; Mal = 1; Texto = 'Protección en tiempo real de Defender desactivada por política' }
)
# Dominios de Microsoft sin los que fallan las actualizaciones, la Tienda o la cuenta
$dominiosMs = 'windowsupdate\.com$', 'update\.microsoft\.com$', 'delivery\.mp\.microsoft\.com$', 'displaycatalog\.mp\.microsoft\.com$', 'licensing\.mp\.microsoft\.com$', 'storeedgefd\.dl\.delivery\.mp\.microsoft\.com$', '^login\.live\.com$'
$hosts = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'

Write-Output "  $($E.Lupa) Buscando lo que otras herramientas han podido estropear…"
$hallazgos = New-Object Collections.Generic.List[object]
foreach ($k in $servicios.Keys) {
    $s = Get-CimInstance Win32_Service -Filter "Name='$k'" -ErrorAction SilentlyContinue
    if ($s -and $s.StartMode -eq 'Disabled') { $hallazgos.Add([pscustomobject]@{ Id = "srv:$k"; Tipo = 'Servicio'; Clave = $k; Texto = "Servicio «$($servicios[$k][0])» deshabilitado"; Detalle = "Se pone en $(if ($servicios[$k][1] -eq 'Automatic') { 'automático' } else { 'manual' }) (el valor de fábrica)."; Marcado = $true; Inicio = $servicios[$k][1] }) }
}
foreach ($p in $politicas) {
    try { $v = (Get-ItemProperty -LiteralPath $p.Ruta -Name $p.Nombre -ErrorAction Stop).($p.Nombre) } catch { continue }
    if ($v -eq $p.Mal) { $hallazgos.Add([pscustomobject]@{ Id = "pol:$($p.Ruta)|$($p.Nombre)"; Tipo = 'Politica'; Clave = $p; Texto = $p.Texto; Detalle = 'Se quita la política (Windows vuelve a su comportamiento normal). No la quites si tu empresa la gestiona.'; Marcado = ($p.Nombre -notin 'DisableAntiSpyware', 'DisableRealtimeMonitoring') }) }
}
# Pausas que no caducan: más de 120 días por delante
$ux = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
foreach ($n in 'PauseUpdatesExpiryTime', 'PauseFeatureUpdatesEndTime', 'PauseQualityUpdatesEndTime') {
    try { $v = [string](Get-ItemProperty -LiteralPath $ux -Name $n -ErrorAction Stop).$n; $f = [datetime]::Parse($v, [Globalization.CultureInfo]::InvariantCulture, 'AssumeUniversal,AdjustToUniversal') } catch { continue }
    if ($f -gt (Get-Date).AddDays(120)) { $hallazgos.Add([pscustomobject]@{ Id = "pau:$n"; Tipo = 'Pausa'; Clave = $n; Texto = "Windows Update pausado hasta el $($f.ToLocalTime().ToString('dd/MM/yyyy'))"; Detalle = 'La pausa normal de Windows dura como mucho 5 semanas: esta se puso a mano para que no caduque. Se quita.'; Marcado = $true }) }
}
# hosts
$lineasHosts = @()
if (Test-Path -LiteralPath $hosts) {
    $n = 0
    foreach ($l in @(Get-Content -LiteralPath $hosts -ErrorAction SilentlyContinue)) {
        $n++; $t = $l.Trim(); if (-not $t -or $t.StartsWith('#')) { continue }
        $p = $t -split '\s+'; if ($p.Count -lt 2 -or $p[0] -notin '0.0.0.0', '127.0.0.1', '::1', '::') { continue }
        $host1 = $p[1].ToLowerInvariant()
        if ($dominiosMs | Where-Object { $host1 -match $_ }) { $lineasHosts += [pscustomobject]@{ Linea = $n; Texto = $t } }
    }
    if ($lineasHosts.Count) { $hallazgos.Add([pscustomobject]@{ Id = 'hosts'; Tipo = 'Hosts'; Clave = $lineasHosts; Texto = "$($lineasHosts.Count) servidor(es) de Microsoft bloqueados en el archivo hosts"; Detalle = (($lineasHosts | Select-Object -First 3 | ForEach-Object { $_.Texto }) -join ' · '); Marcado = $true }) }
}

if (-not $hallazgos.Count) { Write-Output "  $($E.OK) No se ha encontrado nada de esto: servicios, políticas, hosts y pausas están como los deja Windows."; Write-Log 'Deshacer_Dano_Optimizadores: nada que reparar'; Exit-Kit 'Ok' }
Write-Output "  $($E.Aviso) Encontrado $($hallazgos.Count) elemento(s):"
foreach ($h in $hallazgos) { Write-Output "    · $($h.Texto)" }
if ($SoloAnalizar) { Write-Output "`n  $($E.Info) Solo análisis: no se ha cambiado nada."; Write-Log "Deshacer_Dano_Optimizadores: análisis, $($hallazgos.Count) hallazgos"; Exit-Kit 'Ok' }

$elegidos = Show-Marcables 'Deshacer el daño de otros optimizadores' 'Marca lo que quieres devolver a como lo deja Windows. Se registra todo y se puede deshacer; el archivo hosts se copia antes. Lo que no marques se queda como está.' @($hallazgos) 'Reparar lo marcado'
if ($null -eq $elegidos -or -not $elegidos.Count) { Exit-Kit 'Cancelado' 'No se cambia nada.' }

[void](Start-OperacionSegura 'Deshacer daño de optimizadores')
$ok = 0; $fallos = 0
# Quitar un valor de registro dejando constancia del anterior: «Deshacer cambios» lo vuelve a poner
function Remove-ValorSeguro([string]$Ruta, [string]$Nombre) {
    $it = Get-Item -LiteralPath $Ruta -ErrorAction Stop
    Save-Cambio @{ Tipo = 'Registro'; Ruta = $Ruta; Nombre = $Nombre; ClaveExistia = $true; PadreExistia = $true; ValorExistia = $true; Previo = $it.GetValue($Nombre, $null, 'DoNotExpandEnvironmentNames'); TipoPrevio = $it.GetValueKind($Nombre).ToString() }
    Remove-ItemProperty -LiteralPath $Ruta -Name $Nombre -Force -ErrorAction Stop
}
foreach ($h in $elegidos) {
    try {
        switch ($h.Tipo) {
            'Servicio' { if (-not (Set-ServicioSeguro $h.Clave $h.Inicio)) { throw 'el servicio ya no existe' }; if ((Get-CimInstance Win32_Service -Filter "Name='$($h.Clave)'").StartMode -eq 'Disabled') { throw 'Windows no ha dejado cambiarlo (¿protección contra manipulaciones?)' } }
            'Politica' { Remove-ValorSeguro $h.Clave.Ruta $h.Clave.Nombre }
            'Pausa' { Remove-ValorSeguro $ux $h.Clave }
            'Hosts' {
                $copia = Join-Path $Global:NitOp.Dir 'hosts.bak'; Copy-Item -LiteralPath $hosts -Destination $copia -Force
                $marcadas = @($h.Clave | ForEach-Object { $_.Linea })
                $n = 0; $nuevo = foreach ($l in @(Get-Content -LiteralPath $hosts)) { $n++; if ($n -in $marcadas) { '# Nitrit0 (desbloqueado): ' + $l } else { $l } }
                [IO.File]::WriteAllLines($hosts, [string[]]@($nuevo), (New-Object Text.UTF8Encoding($false)))
                Save-Informativo "Archivo hosts modificado: copia original en $copia" 'Para volver atrás, copia ese archivo sobre C:\Windows\System32\drivers\etc\hosts'
            }
        }
        $ok++; Write-Output "  $($E.OK) $($h.Texto): corregido."; Write-Log "Deshacer_Dano_Optimizadores: $($h.Texto) corregido"
    } catch { $fallos++; Write-Output "  $($E.Aviso) $($h.Texto): no se pudo ($($_.Exception.Message))."; Write-Log "Deshacer_Dano_Optimizadores: fallo en $($h.Texto): $($_.Exception.Message)" 'WARN' }
}
Write-Output "`n  $($E.Info) $ok corregido(s), $fallos con error. Los servicios que se acaban de volver a habilitar arrancan solos cuando Windows los necesita; si algo no responde, reinicia el equipo."
Write-Output "  $($E.Info) Para volver atrás: Mantenimiento > Deshacer cambios."
if ($fallos) { Exit-Kit 'Error' "$fallos elemento(s) no se pudieron corregir." }
Exit-Kit 'Ok' "$ok elemento(s) devueltos a su valor normal de Windows."
