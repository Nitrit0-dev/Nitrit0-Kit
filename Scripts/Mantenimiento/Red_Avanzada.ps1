# =====================================================================
#  Red_Avanzada.ps1 - Diagnóstico de red más fino que «Reparar red» (Nitrit0)
#  Para «el Wi-Fi se corta solo», «no veo equipos ni impresoras de la red», «hay Internet pero no cargan páginas» o «un puerto
#  no responde». Comprueba por separado: proxy colgado, ahorro de energía del adaptador, servicios de compartir archivos (SMB),
#  reglas del firewall para la red privada, resolución de nombres y alcance de varios puertos. Cada reparación se elige aparte;
#  no restablece toda la pila de red (para eso está «Reparar red»).
#  Parámetros: -SoloAnalizar (solo mide y enseña)  -Puertos "host:puerto,host:puerto" (pruebas extra)
#  Salida: 0 bien · 1 error · 2 cancelado
# =====================================================================
[CmdletBinding()]
param([switch]$SoloAnalizar, [string]$Puertos = '')
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
if (-not $SoloAnalizar) { Assert-Admin 'reparar la configuración de red' }

function Test-Puerto([string]$hostname, [int]$puerto, [int]$esperaMs = 3000) {
    $c = New-Object Net.Sockets.TcpClient
    try { $a = $c.BeginConnect($hostname, $puerto, $null, $null); if (-not $a.AsyncWaitHandle.WaitOne($esperaMs, $false)) { return $false }; $c.EndConnect($a); return $c.Connected } catch { return $false } finally { $c.Close() }
}

# ---------------------------------------------------------------- 1. Proxy
Write-Output "  $($E.Lupa) Proxy"
$ie = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$proxyOn = $false; $proxyMuerto = $false; $proxySrv = ''; $pac = ''
try { $cfg = Get-ItemProperty -LiteralPath $ie -ErrorAction Stop; $proxyOn = ($cfg.ProxyEnable -eq 1); $proxySrv = [string]$cfg.ProxyServer; $pac = [string]$cfg.AutoConfigURL } catch { }
if ($proxyOn -and $proxySrv) {
    $primero = ($proxySrv -split ';')[0] -replace '^\w+=', '' -replace '^https?://', ''
    $h, $p = $primero -split ':', 2; $pn = 0; if (-not [int]::TryParse($p, [ref]$pn)) { $pn = 8080 }
    $vivo = Test-Puerto $h $pn
    if (-not $vivo) { $proxyMuerto = $true }
    Write-Output "    $(if ($vivo) { $E.OK } else { $E.Aviso }) Proxy activo: $proxySrv · $(if ($vivo) { 'responde' } else { 'NO responde (si no lo usas, bloquea la navegación)' })"
} elseif ($pac) { Write-Output "    $($E.Info) Script de configuración automática: $pac" } else { Write-Output "    $($E.OK) Sin proxy configurado." }

# ---------------------------------------------------------------- 2. Adaptadores y ahorro de energía
Write-Output "  $($E.Lupa) Adaptadores de red"
$ahorro = @()
$adaptadores = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
if (-not $adaptadores.Count) { Write-Output "    $($E.Aviso) Ningún adaptador físico conectado." }
foreach ($a in $adaptadores) {
    $pm = $null; try { $pm = Get-NetAdapterPowerManagement -Name $a.Name -ErrorAction Stop } catch { Write-Output "    $($E.Info) $($a.Name): no se pudo leer el ahorro de energía$(if (-not (Test-EsAdmin)) { ' (hace falta administrador)' })." }
    $apaga = $pm -and ([string]$pm.AllowComputerToTurnOffDevice -eq 'Enabled')
    if ($apaga) { $ahorro += $a }
    Write-Output ("    {0} {1} · {2} · {3}" -f $(if ($apaga) { $E.Aviso } else { $E.OK }), $a.Name, $a.LinkSpeed, $(if ($apaga) { 'Windows puede apagarlo para ahorrar energía (causa cortes de Wi-Fi)' } else { 'sin ahorro de energía agresivo' }))
}

# ---------------------------------------------------------------- 3. SMB y compartir
Write-Output "  $($E.Lupa) Compartir archivos e impresoras (SMB)"
$srvSmb = @(); foreach ($n in 'LanmanWorkstation', 'LanmanServer', 'lmhosts', 'FDResPub', 'fdPHost') {
    $s = Get-Service -Name $n -ErrorAction SilentlyContinue; if (-not $s) { continue }
    $ok = $s.Status -eq 'Running'; if (-not $ok) { $srvSmb += $n }
    Write-Output ("    {0} Servicio {1}: {2}" -f $(if ($ok) { $E.OK } else { $E.Aviso }), $n, $s.Status)
}
try { if ((Get-SmbServerConfiguration -ErrorAction Stop).EnableSMB1Protocol) { Write-Output "    $($E.Aviso) El protocolo SMB1 (obsoleto e inseguro) está activo. Se avisa pero no se cambia desde aquí." } else { Write-Output "    $($E.OK) SMB1 desactivado." } } catch { }

# ---------------------------------------------------------------- 4. Firewall (red privada)
Write-Output "  $($E.Lupa) Firewall para la red privada"
$reglasFw = @()
foreach ($g in @(@('@FirewallAPI.dll,-32752', 'Detección de redes'), @('@FirewallAPI.dll,-28502', 'Compartir archivos e impresoras'))) {
    try {
        $r = @(Get-NetFirewallRule -Group $g[0] -ErrorAction Stop | Where-Object { [string]$_.Profile -match 'Private|Any|All' })
        $act = @($r | Where-Object { [string]$_.Enabled -eq 'True' })
        # Windows trae muchas reglas del grupo desactivadas a propósito: solo es problema si NINGUNA está activa en la red privada
        if ($r.Count -and -not $act.Count) { $reglasFw += [pscustomobject]@{ Grupo = $g[0]; Nombre = $g[1]; Cuantas = $r.Count } }
        Write-Output ("    {0} {1}: {2}" -f $(if ($r.Count -and -not $act.Count) { $E.Aviso } else { $E.OK }), $g[1], $(if ($r.Count -and -not $act.Count) { 'todas las reglas desactivadas en la red privada (no verás otros equipos ni impresoras)' } else { "$($act.Count) regla(s) activas" }))
    } catch { Write-Output "    $($E.Info) $($g[1]): no se pudo leer." }
}

# ---------------------------------------------------------------- 5. Nombres y puertos
Write-Output "  $($E.Lupa) Salida a Internet"
$gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1).NextHop
if ($gw) { Write-Output "    $(if (Test-Connection -ComputerName $gw -Count 1 -Quiet -ErrorAction SilentlyContinue) { $E.OK } else { $E.Aviso }) Puerta de enlace $gw" } else { Write-Output "    $($E.Aviso) No hay puerta de enlace (sin red)." }
$dnsOk = $false; try { [void](Resolve-DnsName -Name 'www.microsoft.com' -Type A -DnsOnly -QuickTimeout -ErrorAction Stop); $dnsOk = $true } catch { }
Write-Output "    $(if ($dnsOk) { $E.OK } else { $E.Aviso }) Resolución de nombres (DNS): $(if ($dnsOk) { 'bien' } else { 'FALLA' })"
$pruebas = @(@('1.1.1.1', 443, 'Internet (HTTPS) por IP'), @('www.microsoft.com', 443, 'Web por nombre (HTTPS)'), @('8.8.8.8', 53, 'DNS público'))
foreach ($x in ($Puertos -split ',' | Where-Object { $_ -match '^\s*[^:\s]+:\d+\s*$' })) { $h, $p = ($x.Trim() -split ':'); $pruebas += , @($h, [int]$p, "Prueba pedida ${h}:$p") }
$caidos = 0
foreach ($t in $pruebas) { $ok = Test-Puerto $t[0] $t[1]; if (-not $ok) { $caidos++ }; Write-Output ("    {0} {1} ({2}:{3})" -f $(if ($ok) { $E.OK } else { $E.Aviso }), $t[2], $t[0], $t[1]) }
$hayProblemas = $proxyMuerto -or $ahorro.Count -or $srvSmb.Count -or $reglasFw.Count -or -not $dnsOk -or $caidos
Write-Log "Red_Avanzada: análisis (proxy muerto $proxyMuerto, ahorro $($ahorro.Count), servicios SMB $($srvSmb.Count), reglas FW $($reglasFw.Count), DNS $dnsOk, puertos caídos $caidos)"
if ($SoloAnalizar) { Write-Output "`n  $($E.Info) Solo análisis: no se ha cambiado nada."; Exit-Kit 'Ok' }

# ---------------------------------------------------------------- Elegir qué reparar
$items = @()
if ($proxyOn) { $items += [pscustomobject]@{ Id = 'proxy'; Texto = 'Desactivar el proxy del usuario'; Detalle = "Proxy actual: $proxySrv. Si la empresa lo necesita, déjalo. Se puede deshacer."; Marcado = $proxyMuerto } }
if ($ahorro.Count) { $items += [pscustomobject]@{ Id = 'energia'; Texto = 'Quitar el ahorro de energía de los adaptadores'; Detalle = ($ahorro | ForEach-Object { $_.Name }) -join ' · '; Marcado = $true } }
if ($srvSmb.Count) { $items += [pscustomobject]@{ Id = 'smb'; Texto = 'Poner en marcha los servicios de compartir'; Detalle = $srvSmb -join ' · '; Marcado = $true } }
if ($reglasFw.Count) { $items += [pscustomobject]@{ Id = 'firewall'; Texto = 'Activar las reglas de red privada del firewall'; Detalle = (($reglasFw | ForEach-Object { "$($_.Nombre) ($($_.Cuantas))" }) -join ' · ') + '. Solo si esta red es de confianza (casa u oficina).'; Marcado = $false } }
if (-not $items.Count) { if ($hayProblemas) { Exit-Kit 'Error' 'La red sigue con problemas y no hay nada que se pueda reparar desde aquí: mira los avisos de arriba (DNS o puertos suelen depender del router o del proveedor).' } else { Exit-Kit 'Ok' 'La red está bien: no hay nada que reparar.' } }
$elegidos = Show-Marcables 'Red avanzada' 'Marca lo que quieres reparar. Cada cosa es independiente.' $items 'Reparar lo marcado'
if ($null -eq $elegidos -or -not $elegidos.Count) { Exit-Kit 'Cancelado' 'No se cambia nada.' }
$ids = @($elegidos | ForEach-Object { $_.Id }); $errores = 0
try {
    Start-OperacionSegura 'Red avanzada' -SinPuntoRestauracion
    if ('proxy' -in $ids) { try { Set-ValorSeguro $ie 'ProxyEnable' 0 'DWord'; Write-Output "    $($E.OK) Proxy desactivado (el servidor configurado se conserva: $proxySrv)."; Write-Log 'Red_Avanzada: proxy desactivado' } catch { $errores++; Write-Output "    $($E.Aviso) No se pudo desactivar el proxy: $($_.Exception.Message)" } }
    if ('energia' -in $ids) { foreach ($a in $ahorro) { try { Set-NetAdapterPowerManagement -Name $a.Name -AllowComputerToTurnOffDevice Disabled -ErrorAction Stop; Write-Output "    $($E.OK) Ahorro de energía quitado en $($a.Name)."; Save-Informativo "Ahorro de energía quitado en $($a.Name)" "Para volver: Set-NetAdapterPowerManagement -Name '$($a.Name)' -AllowComputerToTurnOffDevice Enabled"; Write-Log "Red_Avanzada: ahorro de energía quitado en $($a.Name)" } catch { $errores++; Write-Output "    $($E.Aviso) $($a.Name): $($_.Exception.Message)" } } }
    if ('smb' -in $ids) { foreach ($n in $srvSmb) { try { [void](Set-ServicioSeguro $n 'Automatic'); Start-Service -Name $n -ErrorAction Stop; Write-Output "    $($E.OK) Servicio $n en marcha."; Write-Log "Red_Avanzada: servicio $n arrancado" } catch { $errores++; Write-Output "    $($E.Aviso) $n : $($_.Exception.Message)" } } }
    if ('firewall' -in $ids) { foreach ($g in $reglasFw) { try { Get-NetFirewallRule -Group $g.Grupo -ErrorAction Stop | Where-Object { [string]$_.Profile -match 'Private|Any|All' } | Enable-NetFirewallRule -ErrorAction Stop; Write-Output "    $($E.OK) Reglas activadas para la red privada: $($g.Nombre)."; Save-Informativo "Reglas de firewall activadas: $($g.Nombre)" "Para volver: Disable-NetFirewallRule -Group '$($g.Grupo)'"; Write-Log "Red_Avanzada: firewall $($g.Nombre) activado en perfil privado" } catch { $errores++; Write-Output "    $($E.Aviso) $($g.Nombre): $($_.Exception.Message)" } } }
} catch { Exit-Kit 'Error' "La reparación se interrumpió: $($_.Exception.Message)" }
if ($errores) { Exit-Kit 'Error' "Terminado con $errores problema(s)." }
Exit-Kit 'Ok' 'Reparación terminada. Si sigue sin ir, ejecuta «Reparar red» (restablece la pila completa).'
