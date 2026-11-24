# =====================================================================
#  DNS_Mas_Rapido.ps1 - Mide varios DNS públicos y pone el más rápido (Nitrit0)
#  Cuándo usarlo: webs que tardan en empezar a cargar, ping alto a servidores de juegos,
#  cortes de DNS de la operadora. Mide con consultas reales desde ESTE equipo y esta red.
#  Qué toca: solo el DNS de los adaptadores físicos activos con puerta de enlace. Nada más.
#  Qué NO toca: IP, puerta, DHCP, ni equipos de dominio (se mide pero no se cambia).
#  Parámetros:
#    -Aplicar        pone el mejor sin preguntar (si mejora de forma clara)
#    -SinPreguntas   solo mide y enseña la tabla, no cambia nada (salvo con -Aplicar)
# =====================================================================
[CmdletBinding()]
param([switch]$Aplicar, [switch]$SinPreguntas, [Alias('Simular')][switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E

# Servidores IPv4 (principal, secundario). Públicos y sin registro obligatorio.
$Candidatos = @(
    @{ Nombre = 'Cloudflare';          Ips = @('1.1.1.1', '1.0.0.1') }
    @{ Nombre = 'Google';              Ips = @('8.8.8.8', '8.8.4.4') }
    @{ Nombre = 'Quad9';               Ips = @('9.9.9.9', '149.112.112.112') }
    @{ Nombre = 'OpenDNS';             Ips = @('208.67.222.222', '208.67.220.220') }
    @{ Nombre = 'AdGuard';             Ips = @('94.140.14.14', '94.140.15.15') }
    @{ Nombre = 'CleanBrowsing';       Ips = @('185.228.168.9', '185.228.169.9') }
    @{ Nombre = 'Control D';           Ips = @('76.76.2.0', '76.76.10.0') }
    @{ Nombre = 'DNS.SB';              Ips = @('185.222.222.222', '45.11.45.11') }
)
$Dominios = @('www.microsoft.com', 'www.google.com', 'www.wikipedia.org', 'www.amazon.com', 'store.steampowered.com')
$Rondas = 3

function Get-Mediana([double[]]$v) {
    $s = @($v | Sort-Object); if ($s.Count -eq 0) { return $null }
    $m = [math]::Floor($s.Count / 2)
    if ($s.Count % 2) { $s[$m] } else { ($s[$m - 1] + $s[$m]) / 2 }
}
function Measure-Dns([string]$Ip) {
    $t = New-Object Collections.Generic.List[double]; $fallos = 0
    $null = Resolve-DnsName -Name $Dominios[0] -Server $Ip -DnsOnly -QuickTimeout -ErrorAction SilentlyContinue   # calentamiento
    for ($r = 0; $r -lt $Rondas; $r++) {
        foreach ($d in $Dominios) {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $x = Resolve-DnsName -Name $d -Server $Ip -DnsOnly -QuickTimeout -ErrorAction SilentlyContinue
            $sw.Stop()
            if ($x) { $t.Add($sw.Elapsed.TotalMilliseconds) } else { $fallos++ }
        }
        if ($r -eq 0 -and $t.Count -eq 0) { break }   # no contesta: no se pierde más tiempo
    }
    [pscustomobject]@{ Ms = (Get-Mediana $t.ToArray()); Fallos = $fallos; Total = $Dominios.Count * $Rondas }
}

# --- Adaptadores sobre los que se podría actuar
$Adaptadores = @()
try {
    $Adaptadores = @(Get-NetIPConfiguration -ErrorAction Stop | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
        Where-Object { (Get-NetAdapter -InterfaceIndex $_.InterfaceIndex -Physical -ErrorAction SilentlyContinue) })
} catch { }
if ($Adaptadores.Count -eq 0) { Write-Output "$($E.Error) No hay ningún adaptador físico conectado con salida a Internet."; Write-Log 'DNS más rápido: sin adaptador' 'ERROR'; exit 1 }
$Actual = @($Adaptadores | ForEach-Object { $_.DNSServer | Where-Object { $_.AddressFamily -eq 2 } | ForEach-Object { $_.ServerAddresses } } | Select-Object -Unique)
Write-Output "$($E.Info) Adaptadores: $(($Adaptadores | ForEach-Object { $_.InterfaceAlias }) -join ', ')"
Write-Output "$($E.Info) DNS actual: $(if ($Actual) { $Actual -join ', ' } else { 'automático (el que da el router)' })"

# --- Medición
$Lista = @()
if ($Actual) { $Lista += @{ Nombre = 'Tu DNS actual'; Ips = @($Actual | Select-Object -First 2); Actual = $true } }
foreach ($c in $Candidatos) { if (-not ($Actual -contains $c.Ips[0])) { $Lista += $c } }
Write-Output "$($E.Reloj) Midiendo $($Lista.Count) servidores ($($Dominios.Count) webs x $Rondas rondas cada uno). Tarda un minuto o dos..."
$Res = @()
foreach ($s in $Lista) {
    $m = Measure-Dns $s.Ips[0]
    $Res += [pscustomobject]@{ Nombre = $s.Nombre; Ips = $s.Ips; Ms = $m.Ms; Fallos = $m.Fallos; Total = $m.Total; Actual = [bool]$s.Actual }
    Write-Output ("  {0,-16} {1,-16} {2}" -f $s.Nombre, $s.Ips[0], $(if ($null -eq $m.Ms) { 'sin respuesta' } else { ('{0:N0} ms (fallos {1}/{2})' -f $m.Ms, $m.Fallos, $m.Total) }))
}
# Válidos: contestan y fallan menos de un tercio
$Validos = @($Res | Where-Object { $null -ne $_.Ms -and $_.Fallos -lt ($_.Total / 3) } | Sort-Object Ms, @{ Expression = { -not $_.Actual } })   # a igualdad, gana el actual
if ($Validos.Count -eq 0) { Write-Output "$($E.Error) Ningún servidor respondió: parece que no hay Internet o el puerto 53 está bloqueado."; Write-Log 'DNS más rápido: nada responde' 'ERROR'; exit 1 }
$Mejor = $Validos[0]
$ActualRes = $Res | Where-Object { $_.Actual } | Select-Object -First 1
Write-Output ''
Write-Output "$($E.OK) Más rápido: $($Mejor.Nombre) ($($Mejor.Ips -join ' / ')) con una mediana de $('{0:N0}' -f $Mejor.Ms) ms."

# --- ¿Merece el cambio?
if ($Mejor.Actual) { Write-Output "$($E.OK) Ya usas el más rápido de los probados. No hay nada que cambiar."; Write-Log 'DNS más rápido: ya óptimo'; return }
if ($ActualRes -and $null -ne $ActualRes.Ms) {
    $ganancia = $ActualRes.Ms - $Mejor.Ms
    Write-Output "$($E.Info) Tu DNS actual: $('{0:N0}' -f $ActualRes.Ms) ms. Ganancia: $('{0:N0}' -f $ganancia) ms por consulta."
    if ($ganancia -lt 3 -or $ganancia / $ActualRes.Ms -lt 0.15) { Write-Output "$($E.OK) La diferencia es pequeña: no compensa cambiar. No se toca nada."; Write-Log 'DNS más rápido: ganancia pequeña'; return }
}

# --- Equipos de dominio: el DNS lo da el servidor de la empresa
$enDominio = $false; try { $enDominio = [bool](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).PartOfDomain } catch { }
if ($SoloAnalizar) { Exit-Kit 'Ok' ("Modo análisis: el DNS más rápido sería $($Mejor.Nombre) ($($Mejor.Ips -join ' / ')); no se ha cambiado nada." + $(if ($enDominio) { ' El equipo está en un dominio: al aplicar no se cambiaría.' } else { '' })) }
if ($enDominio) { Write-Output "$($E.Aviso) El equipo está en un dominio: su DNS lo necesita para encontrar el servidor de la empresa. No se cambia."; Write-Log 'DNS más rápido: dominio, no se cambia' 'WARN'; exit 2 }
$admin = Test-EsAdmin
if (-not $admin -and -not ($SinPreguntas -and -not $Aplicar)) { Exit-Kit 'Error' 'Hace falta administrador para aplicar el DNS (sin él solo se puede medir con -SinPreguntas). Abre el kit como administrador.' }

# --- Aplicar (con pregunta salvo -Aplicar o -SinPreguntas)
if (-not $Aplicar) {
    if ($SinPreguntas) { Write-Output "$($E.Info) Solo medición (sin -Aplicar). No se ha cambiado nada."; return }
    Add-Type -AssemblyName System.Windows.Forms
    $txt = "Poner $($Mejor.Nombre) ($($Mejor.Ips -join ' / ')) como DNS en: $(($Adaptadores | ForEach-Object { $_.InterfaceAlias }) -join ', ')`n`nSe guarda el DNS actual y puedes volver con Mantenimiento > Deshacer cambios.`nLas webs que visites las verá ese proveedor en lugar de la operadora."
    if ([Windows.Forms.MessageBox]::Show($txt, 'DNS más rápido', 'YesNo', 'Question') -ne 'Yes') { Write-Output "$($E.Info) Cancelado: no se ha cambiado nada."; exit 2 }
}
$null = Start-OperacionSegura 'DNS más rápido' -SinPuntoRestauracion
$previos = @{}
foreach ($a in $Adaptadores) {
    $previos[$a.InterfaceIndex] = @((Get-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses)
    try { Set-DnsSeguro $a.InterfaceIndex $Mejor.Ips; Write-Output "$($E.OK) DNS puesto en '$($a.InterfaceAlias)'." }
    catch { Write-Output "$($E.Error) No se pudo cambiar '$($a.InterfaceAlias)': $($_.Exception.Message)" }
}
try { Clear-DnsClientCache } catch { }
# Comprobación: si con el DNS nuevo no se resuelve nada, se devuelve el anterior
$ok = $false
foreach ($d in $Dominios) { if (Resolve-DnsName -Name $d -DnsOnly -QuickTimeout -ErrorAction SilentlyContinue) { $ok = $true; break } }
if (-not $ok) {
    foreach ($a in $Adaptadores) {
        if (@($previos[$a.InterfaceIndex]).Count) { Set-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex -ServerAddresses $previos[$a.InterfaceIndex] -ErrorAction SilentlyContinue }
        else { Set-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex -ResetServerAddresses -ErrorAction SilentlyContinue }
    }
    try { Clear-DnsClientCache } catch { }
    Write-Output "$($E.Error) Con el DNS nuevo no se resolvía nada: se ha devuelto el anterior."
    Write-Log 'DNS más rápido: revertido por fallo de resolución' 'ERROR'; exit 1
}
Write-Output "$($E.OK) Hecho: el equipo ya resuelve con $($Mejor.Nombre). Para volver atrás: Mantenimiento > Deshacer cambios."
Write-Log "DNS más rápido: $($Mejor.Nombre) $($Mejor.Ips -join '/') ($('{0:N0}' -f $Mejor.Ms) ms)"
