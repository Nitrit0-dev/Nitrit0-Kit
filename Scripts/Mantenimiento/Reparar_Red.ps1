# =====================================================================
#  Reparar_Red.ps1 - Repara la conexión de red (Nitrit0)
#  Vacía la caché DNS, renueva la IP y restablece Winsock y TCP/IP. Puede pedir reinicio al terminar.
#  ANTES guarda la configuración de red de forma que se puede REPONER: un archivo de «netsh dump» (con IP fija, DNS y rutas)
#  y la lista de DNS por adaptador. Para volver atrás:  Reparar_Red.ps1 -RestaurarRed "archivo.netsh"
#  Si hay una sesión remota (escritorio remoto, AnyDesk, TeamViewer…), avisa: cortar la red la deja colgada.
#  Parámetros: -SoloAnalizar (enseña el estado de la red y no cambia nada)   -RestaurarRed "archivo" (repone una copia)
#  Salida: 0 bien · 1 error (o sigue sin haber conexión) · 2 cancelado
# =====================================================================
[CmdletBinding()]
param([switch]$SoloAnalizar, [string]$RestaurarRed = '')
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
if (-not $SoloAnalizar) { Assert-Admin 'reparar la red' }
$dirBk = Join-Path $Global:NitKit.Cache 'Informes'   # nunca va al pendrive: puede llevar la IP de un cliente

# ---------------------------------------------------------------- Reponer una copia
if ($RestaurarRed) {
    if (-not (Test-Path -LiteralPath $RestaurarRed)) { Exit-Kit 'Error' "No encuentro el archivo $RestaurarRed." }
    if (-not (Confirm-Accion "Se repondrá la configuración de red guardada en:`n$RestaurarRed`n`nPuedes perder la conexión unos segundos. ¿Continuar?")) { Exit-Kit 'Cancelado' 'Cancelado: no se ha cambiado nada.' }
    try {
        $r = Invoke-Proceso 'netsh.exe' ('-f "{0}"' -f $RestaurarRed) 120 'Reponer la red' 30
        if ($r.Codigo -ne 0) { Exit-Kit 'Error' "netsh no pudo reponer la configuración (código $($r.Codigo))." }
    } catch { Exit-Kit 'Error' "No se pudo reponer: $($_.Exception.Message)" }
    # netsh no siempre repone los DNS: se reaplican los guardados junto a la copia (.dns.json) si difieren de los actuales
    if (Test-Path -LiteralPath "$RestaurarRed.dns.json") {
        try {
            foreach ($d in @(Get-Content -LiteralPath "$RestaurarRed.dns.json" -Raw -Encoding UTF8 | ConvertFrom-Json)) {
                if (-not $d) { continue }
                $guardados = @(([string]$d.ServerAddresses) -split ',' | Where-Object { $_ }); if (-not $guardados.Count) { continue }
                $actuales = @((Get-DnsClientServerAddress -InterfaceAlias $d.InterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses)
                if (($actuales -join ',') -ne ($guardados -join ',')) { Set-DnsClientServerAddress -InterfaceAlias $d.InterfaceAlias -ServerAddresses $guardados -ErrorAction Stop; Write-Output "  $($E.OK) DNS repuestos en $($d.InterfaceAlias): $($guardados -join ', ')" }
            }
        } catch { Write-Output "  $($E.Aviso) No se pudieron reponer los DNS guardados: $($_.Exception.Message)" }
    }
    Write-Log "Reparar_Red: configuración repuesta desde $RestaurarRed"
    Exit-Kit 'Ok' 'Configuración de red repuesta. Si algo no cuadra, reinicia el equipo.'
}

# ---------------------------------------------------------------- Estado
Write-Output "  $($E.Lupa) Estado de la red"
try {
    foreach ($a in @(Get-NetAdapter -Physical -ErrorAction Stop | Sort-Object Name)) {
        $ip = Get-NetIPConfiguration -InterfaceIndex $a.ifIndex -ErrorAction SilentlyContinue
        $dhcp = (Get-NetIPInterface -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).Dhcp
        Write-Output ("    {0} {1} · {2} · IP {3} · puerta {4} · DNS {5} · {6}" -f $(if ($a.Status -eq 'Up') { $E.OK } else { $E.Info }), $a.Name, $a.Status, (($ip.IPv4Address.IPAddress) -join ','), (($ip.IPv4DefaultGateway.NextHop) -join ','), (($ip.DnsServer.ServerAddresses) -join ','), $(if ($dhcp -eq 'Enabled') { 'DHCP' } elseif ($dhcp) { 'IP fija' } else { '' }))
    }
} catch { Write-Output "    $($E.Aviso) No se pudo leer el estado de los adaptadores: $($_.Exception.Message)" }
$hayRed = Test-Internet
Write-Output "    $(if ($hayRed) { $E.OK } else { $E.Aviso }) Internet: $(if ($hayRed) { 'responde' } else { 'no responde' })"
if ($SoloAnalizar) { Write-Output "`n  $($E.Info) Solo análisis: no se ha cambiado nada."; Exit-Kit 'Ok' }

# ---------------------------------------------------------------- Aviso de sesión remota y confirmación
$remoto = @(Get-Process -Name AnyDesk, TeamViewer, TeamViewer_Service, rustdesk, ScreenConnect.ClientService -ErrorAction SilentlyContinue | ForEach-Object { $_.ProcessName } | Sort-Object -Unique)
$avisoRemoto = if ($env:SESSIONNAME -like 'RDP-*') { "`n`nESTÁS CONECTADO POR ESCRITORIO REMOTO: la conexión se cortará y quizá no puedas volver a entrar." } elseif ($remoto) { "`n`nHAY UNA HERRAMIENTA DE CONTROL REMOTO ABIERTA ($($remoto -join ', ')): se cortará al restablecer la red." } else { '' }
if (-not (Confirm-Accion "Esto restablece la red del equipo (DNS, IP, Winsock y TCP/IP).`nAntes se guarda la configuración actual para poder reponerla.`nPuedes quedarte sin conexión hasta reiniciar.$avisoRemoto`n`n¿Continuar?")) { Exit-Kit 'Cancelado' 'Cancelado: no se ha cambiado nada.' }

# ---------------------------------------------------------------- Copia que se puede reponer
$marca = Get-Date -Format 'yyyyMMdd_HHmmss'; $bk = Join-Path $dirBk ("Backup_Red_{0}_{1}.netsh" -f ($env:COMPUTERNAME -replace '[^\w\-]', '_'), $marca)
try {
    New-Item -ItemType Directory -Force $dirBk | Out-Null
    & cmd.exe /d /c ('netsh.exe -c interface dump > "{0}"' -f $bk) 2>&1 | Out-Null   # el volcado se guarda tal cual lo emite netsh para poder reponerlo con «netsh -f»
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $bk) -or (Get-Item -LiteralPath $bk).Length -lt 50) { throw 'el volcado de netsh salió vacío' }
    Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object InterfaceAlias, @{ n = 'ServerAddresses'; e = { $_.ServerAddresses -join ',' } } | ConvertTo-Json | Set-Content -LiteralPath "$bk.dns.json" -Encoding UTF8
    Write-Output "  $($E.OK) Configuración guardada en: $bk"
    Write-Output "  $($E.Info) Para volver atrás:  Reparar_Red.ps1 -RestaurarRed `"$bk`""
    Write-Log "Reparar_Red: copia en $bk"
} catch {
    if (-not (Confirm-Accion "No se pudo guardar la copia de la configuración de red ($($_.Exception.Message)).`n`nSi tenías una IP fija, no se podrá reponer sola. ¿Sigues igualmente?" 'Nitrit0 Kit' -Siempre)) { Exit-Kit 'Cancelado' 'Cancelado: no se ha cambiado nada.' }
}

# ---------------------------------------------------------------- Reparar, paso a paso
Write-Output "  $($E.Refresh) Reparando la red…"
$pasos = @(@('Vaciar caché DNS', 'ipconfig.exe', '/flushdns'), @('Liberar IP', 'ipconfig.exe', '/release'), @('Renovar IP', 'ipconfig.exe', '/renew'), @('Registrar DNS', 'ipconfig.exe', '/registerdns'),
           @('Restablecer Winsock', 'netsh.exe', 'winsock reset'), @('Restablecer TCP/IP', 'netsh.exe', 'int ip reset'))
$bien = 0
foreach ($p in $pasos) {
    try { $r = Invoke-Proceso $p[1] $p[2] 90 $p[0] 60; if ($r.Codigo -eq 0) { $bien++ }; Write-Output "  $(if ($r.Codigo -eq 0) { $E.OK } else { $E.Aviso }) $($p[0])$(if ($r.Codigo -ne 0) { " (código $($r.Codigo))" })" }
    catch { Write-Output "  $($E.Aviso) $($p[0]): $($_.Exception.Message)" }
}
Write-Output "  $($E.Info) $bien de $($pasos.Count) pasos terminaron bien."
Write-Output "  $($E.Reloj) Comprobando la conexión…"
Start-Sleep -Seconds 4
Write-Log "Reparar_Red: $bien de $($pasos.Count) pasos bien"
if (Test-Internet) { Write-Output "  $($E.Info) Reinicia el equipo para completar el restablecimiento de Winsock y TCP/IP."; Exit-Kit 'Ok' 'Hay conexión a Internet.' }
Exit-Kit 'Error' "Sigue sin haber conexión: reinicia el equipo y prueba otro cable o punto Wi-Fi. La configuración anterior está en $bk."
