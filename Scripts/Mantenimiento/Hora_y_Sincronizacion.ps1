# =====================================================================
#  Hora_y_Sincronizacion.ps1 - Arregla la hora del equipo y su sincronización (Nitrit0)
#  Para «la hora va mal», «se desajusta al apagar», «da errores de certificado o de inicio de sesión por la fecha». Mide cuánto se
#  desvía el reloj contra un servidor de hora de Internet (consulta NTP directa: no depende del idioma de Windows), comprueba el
#  servicio de hora (w32time) y la zona horaria, y deja elegir qué reparar:
#    · Poner el servicio de hora en automático y arrancarlo.
#    · Configurar los servidores de hora (time.windows.com y pool.ntp.org).
#    · Sincronizar ahora.
#  Si la hora se desajusta cada vez que se apaga el equipo, suele ser la pila de la placa base (CMOS): la herramienta lo avisa.
#  Parámetro: -SoloAnalizar (solo mide y enseña)   Salida: 0 bien · 1 error · 2 cancelado
# =====================================================================
[CmdletBinding()]
param([switch]$SoloAnalizar, [switch]$SinPreguntas)   # -SinPreguntas repara lo que la ventana trae marcado
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
if (-not $SoloAnalizar) { Assert-Admin 'cambiar la hora y su sincronización' }

# Consulta NTP (SNTP) directa por UDP 123: devuelve cuánto va el reloj local respecto al servidor (milisegundos; positivo = el equipo va ATRASADO)
function Get-DesfaseNtp([string]$servidor, [int]$esperaMs = 3000) {
    $u = $null
    try {
        $paq = New-Object byte[] 48; $paq[0] = 0x1B
        $u = New-Object Net.Sockets.UdpClient; $u.Client.ReceiveTimeout = $esperaMs; $u.Connect($servidor, 123)
        $t1 = [DateTime]::UtcNow; [void]$u.Send($paq, 48); $ep = $null; $r = $u.Receive([ref]$ep); $t4 = [DateTime]::UtcNow
        if ($r.Length -lt 48) { return $null }
        $seg = [BitConverter]::ToUInt32([byte[]]@($r[43], $r[42], $r[41], $r[40]), 0); $fra = [BitConverter]::ToUInt32([byte[]]@($r[47], $r[46], $r[45], $r[44]), 0)
        $srv = (New-Object DateTime(1900, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)).AddMilliseconds(([double]$seg * 1000) + ([double]$fra * 1000 / 4294967296))
        $rtt = ($t4 - $t1).TotalMilliseconds
        [pscustomobject]@{ Servidor = $servidor; DesfaseMs = (($srv - $t4).TotalMilliseconds + $rtt / 2); IdaVueltaMs = $rtt }
    } catch { $null } finally { if ($u) { $u.Close() } }
}
function Measure-Hora {
    foreach ($s in 'time.windows.com', 'pool.ntp.org', 'time.cloudflare.com') { $r = Get-DesfaseNtp $s; if ($r) { return $r } }
    $null
}

# ---------------------------------------------------------------- Estado
Write-Output "  $($E.Lupa) Hora del equipo"
$tz = Get-TimeZone
Write-Output "    $($E.Info) Ahora: $((Get-Date).ToString('dd/MM/yyyy HH:mm:ss')) · zona horaria: $($tz.Id) ($($tz.DisplayName))"
$sv = Get-Service -Name w32time -ErrorAction SilentlyContinue
$modo = (Get-CimInstance Win32_Service -Filter "Name='w32time'" -ErrorAction SilentlyContinue).StartMode
$svOk = $sv -and $sv.Status -eq 'Running'
Write-Output "    $(if ($svOk) { $E.OK } else { $E.Aviso }) Servicio de hora (w32time): $(if ($sv) { "$($sv.Status), inicio $modo" } else { 'no existe' })"
$m = Measure-Hora
$desfase = $null
if ($m) {
    $desfase = [math]::Round($m.DesfaseMs / 1000, 1)
    $nivel = if ([math]::Abs($desfase) -lt 2) { 'ok' } elseif ([math]::Abs($desfase) -lt 60) { 'aviso' } else { 'mal' }
    Write-Output ("    {0} Desfase respecto a {1}: {2} s ({3}){4}" -f $(if ($nivel -eq 'ok') { $E.OK } elseif ($nivel -eq 'aviso') { $E.Aviso } else { $E.Error }), $m.Servidor, $desfase, $(if ($desfase -gt 0) { 'el equipo va atrasado' } elseif ($desfase -lt 0) { 'el equipo va adelantado' } else { 'exacto' }), $(if ($nivel -eq 'mal') { ' · esto causa errores de certificados y de inicio de sesión' } else { '' }))
} else { Write-Output "    $($E.Aviso) No se pudo consultar ningún servidor de hora (¿sin Internet o puerto UDP 123 bloqueado?)." }
if ($SoloAnalizar) { Write-Output "`n  $($E.Info) Solo análisis: no se ha cambiado nada."; Write-Log "Hora_y_Sincronizacion: análisis (desfase $desfase s, servicio $svOk)"; Exit-Kit 'Ok' }

# ---------------------------------------------------------------- Elegir qué reparar
$necesita = (-not $svOk) -or ($modo -ne 'Auto') -or ($null -ne $desfase -and [math]::Abs($desfase) -ge 2)
$items = @(
    [pscustomobject]@{ Id = 'servicio'; Texto = 'Poner el servicio de hora en automático y arrancarlo'; Detalle = $(if ($svOk -and $modo -eq 'Auto') { 'Ya está en marcha y en automático.' } else { 'Sin él la hora no se actualiza sola.' }); Marcado = (-not $svOk -or $modo -ne 'Auto') }
    [pscustomobject]@{ Id = 'servidores'; Texto = 'Configurar los servidores de hora (time.windows.com y pool.ntp.org)'; Detalle = 'Cambia el origen de hora de Windows. Útil si no sincroniza o apunta a un servidor que ya no existe. En equipos de un dominio no hace falta.'; Marcado = $false }
    [pscustomobject]@{ Id = 'sincronizar'; Texto = 'Sincronizar la hora ahora'; Detalle = $(if ($null -ne $desfase) { "Corrige el desfase de $desfase s." } else { 'Fuerza una sincronización inmediata.' }); Marcado = $necesita }
)
$elegidos = if ($SinPreguntas) { @($items | Where-Object { $_.Marcado }) } else { Show-Marcables 'Hora y sincronización' 'Marca lo que quieres reparar. La zona horaria no se cambia desde aquí.' $items 'Reparar lo marcado' }
if ($null -eq $elegidos -or -not $elegidos.Count) { Exit-Kit 'Cancelado' 'No se cambia nada.' }
$ids = @($elegidos | ForEach-Object { $_.Id }); $errores = 0
$w32 = Join-Path $env:SystemRoot 'System32\w32tm.exe'
try {
    Start-OperacionSegura 'Hora y sincronización' -SinPuntoRestauracion
    if ('servicio' -in $ids) {
        try { Set-ServicioSeguro 'w32time' 'Automatic'; Start-Service -Name w32time -ErrorAction Stop; Write-Output "    $($E.OK) Servicio de hora en automático y en marcha."; Write-Log 'Hora_y_Sincronizacion: w32time automático y arrancado' }
        catch { $errores++; Write-Output "    $($E.Aviso) No se pudo poner en marcha el servicio de hora: $($_.Exception.Message)" }
    }
    if ('servidores' -in $ids) {
        $r = Invoke-Proceso $w32 '/config /manualpeerlist:"time.windows.com,0x9 pool.ntp.org,0x9" /syncfromflags:manual /reliable:yes /update' 60 'Configurar servidores de hora' 30
        if ($r.Codigo -eq 0) { Write-Output "    $($E.OK) Servidores de hora configurados."; Write-Log 'Hora_y_Sincronizacion: servidores configurados (time.windows.com, pool.ntp.org)'; Save-Informativo 'Servidores de hora cambiados' 'Para volver a los de un dominio: w32tm /config /syncfromflags:domhier /update' }
        else { $errores++; Write-Output "    $($E.Aviso) No se pudieron configurar los servidores (código $($r.Codigo))." }
    }
    if ('sincronizar' -in $ids) {
        $r = Invoke-Proceso $w32 '/resync /force' 60 'Sincronizar la hora' 30
        $despues = Measure-Hora
        if ($despues) { Write-Output ("    {0} Desfase tras sincronizar: {1} s." -f $(if ([math]::Abs($despues.DesfaseMs) -lt 2000) { $E.OK } else { $E.Aviso }), [math]::Round($despues.DesfaseMs / 1000, 1)) }
        if ($r.Codigo -ne 0) { $errores++; Write-Output "    $($E.Aviso) Windows no pudo sincronizar (código $($r.Codigo)): comprueba la conexión a Internet y que el puerto UDP 123 no esté bloqueado." }
        elseif ($despues -and [math]::Abs($despues.DesfaseMs) -ge 2000) { $errores++; Write-Output "    $($E.Aviso) Sincronizó, pero la hora sigue desviada: si se repite al apagar, cambia la pila de la placa base (CMOS)." }
        Write-Log "Hora_y_Sincronizacion: sincronización (código $($r.Codigo))"
    }
} catch { Exit-Kit 'Error' "La reparación se interrumpió: $($_.Exception.Message)" }
if ($errores) { Exit-Kit 'Error' "Terminado con $errores problema(s)." }
Exit-Kit 'Ok' 'Hora reparada.'
