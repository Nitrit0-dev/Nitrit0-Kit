# =====================================================================
#  Cambiar_IP.ps1 - Cambia la IP, el DNS o el DHCP de un adaptador de red (Nitrit0)
#  Ventana con los adaptadores, su configuración actual, perfiles de IP guardados (Datos\Perfiles_IP.json),
#  IP manual, DHCP, activar/desactivar adaptador y liberar/renovar. Lo anterior queda guardado:
#  Mantenimiento > «Deshacer cambios» devuelve la IP y el DNS a como estaban.
#  Sin ventana: -Dhcp  o  -IP <ip> [-Mascara 255.255.255.0] [-Puerta <ip>] [-Dns <ip>,<ip>]  y -Adaptador <nombre>
#  (si solo hay un adaptador conectado, -Adaptador es opcional).  -Captura <ruta.png> guarda una imagen de la ventana.
# =====================================================================
[CmdletBinding()]
param([string]$Adaptador, [string]$IP, [string]$Mascara = '255.255.255.0', [string]$Puerta, [string[]]$Dns, [switch]$Dhcp, [string]$Captura, [Alias('Simular')][switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$esAdmin = Test-EsAdmin

# ---------- validación ----------
function Test-Ipv4([string]$s) { $o = $null; ($s -match '^\d{1,3}(\.\d{1,3}){3}$') -and [Net.IPAddress]::TryParse($s, [ref]$o) -and $o.AddressFamily -eq 'InterNetwork' }
# Máscara -> longitud de prefijo; -1 si no es una máscara válida (255.255.0.255, 0.0.0.0...)
function ConvertTo-Prefijo([string]$m) {
    if (-not (Test-Ipv4 $m)) { return -1 }
    $bits = (([Net.IPAddress]::Parse($m)).GetAddressBytes() | ForEach-Object { [Convert]::ToString($_, 2).PadLeft(8, '0') }) -join ''
    if ($bits -notmatch '^1+0*$') { return -1 }
    $bits.TrimEnd('0').Length
}
function ConvertFrom-Prefijo([int]$p) { $b = ('1' * $p).PadRight(32, '0'); (0..3 | ForEach-Object { [Convert]::ToInt32($b.Substring($_ * 8, 8), 2) }) -join '.' }
# Devuelve el texto del primer error de los datos, o $null si son válidos
function Test-DatosIp([string]$ip, [string]$mask, [string]$gw, [string[]]$dns) {
    if (-not (Test-Ipv4 $ip)) { return "«$ip» no es una dirección IP válida (ejemplo: 192.168.1.50)." }
    if ((ConvertTo-Prefijo $mask) -lt 0) { return "«$mask» no es una máscara válida (ejemplo: 255.255.255.0)." }
    if ($gw -and -not (Test-Ipv4 $gw)) { return "La puerta de enlace «$gw» no es una IP válida." }
    foreach ($d in $dns) { if ($d -and -not (Test-Ipv4 $d)) { return "El DNS «$d» no es una IP válida." } }
    $null
}

# ---------- red ----------
$script:op = $false
function Start-Cambio { if (-not $script:op) { [void](Start-OperacionSegura 'Cambiar IP' -SinPuntoRestauracion); $script:op = $true } }
function Get-Estado([int]$i) {
    $dh = (Get-NetIPInterface -InterfaceIndex $i -AddressFamily IPv4 -ErrorAction SilentlyContinue).Dhcp
    $a = Get-NetIPAddress -InterfaceIndex $i -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1
    $g = (Get-NetRoute -InterfaceIndex $i -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Select-Object -First 1).NextHop
    $d = @((Get-DnsClientServerAddress -InterfaceIndex $i -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses)
    [pscustomobject]@{ Dhcp = ($dh -eq 'Enabled'); Ip = $a.IPAddress; Prefijo = $a.PrefixLength; Puerta = $g; Dns = $d }
}
function Clear-IpManual([int]$i) {
    Remove-NetRoute -InterfaceIndex $i -DestinationPrefix '0.0.0.0/0' -Confirm:$false -ErrorAction SilentlyContinue
    Get-NetIPAddress -InterfaceIndex $i -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '169.254.*' } | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
}
function Save-EstadoIp([int]$i) { $e = Get-Estado $i; Save-Cambio @{ Tipo = 'Ip'; Interfaz = $i; Dhcp = $e.Dhcp; Ip = $e.Ip; Prefijo = $e.Prefijo; Puerta = $e.Puerta } }
function Set-IpManual([int]$i, [string]$ip, [string]$mask, [string]$gw, [string[]]$dns) {
    Start-Cambio; Save-EstadoIp $i
    $antes = Get-Estado $i
    try {
        Set-NetIPInterface -InterfaceIndex $i -AddressFamily IPv4 -Dhcp Disabled -ErrorAction Stop
        Clear-IpManual $i
        $p = @{ InterfaceIndex = $i; IPAddress = $ip; PrefixLength = (ConvertTo-Prefijo $mask); ErrorAction = 'Stop' }; if ($gw) { $p.DefaultGateway = $gw }
        [void](New-NetIPAddress @p)
    } catch {
        # Si algo falla a medias, el adaptador no se queda sin IP: se vuelve a lo que tenía
        $err = $_
        try {
            if ($antes.Dhcp) { Set-NetIPInterface -InterfaceIndex $i -AddressFamily IPv4 -Dhcp Enabled -ErrorAction Stop }
            elseif ($antes.Ip) { $q = @{ InterfaceIndex = $i; IPAddress = $antes.Ip; PrefixLength = $antes.Prefijo; ErrorAction = 'Stop' }; if ($antes.Puerta) { $q.DefaultGateway = $antes.Puerta }; [void](New-NetIPAddress @q) }
        } catch { }
        throw $err
    }
    $dns = @($dns | Where-Object { $_ }); if ($dns.Count) { Set-DnsSeguro -Interfaz $i -Servidores $dns }
}
function Set-IpDhcp([int]$i) {
    Start-Cambio; Save-EstadoIp $i
    if (-not (Get-Estado $i).Dhcp) { Clear-IpManual $i }
    Set-NetIPInterface -InterfaceIndex $i -AddressFamily IPv4 -Dhcp Enabled -ErrorAction Stop
    Set-DnsSeguro -Interfaz $i -Automatico
    $n = (Get-NetAdapter -InterfaceIndex $i).Name
    [void](Invoke-Proceso (Join-Path $env:SystemRoot 'System32\ipconfig.exe') "/renew `"$n`"" 60 'Renovar DHCP')
}

# ---------- modo sin ventana ----------
if ($Dhcp -or $IP) {
    if (-not $esAdmin -and -not $SoloAnalizar) { Exit-Kit 'Error' 'Hace falta ejecutar como administrador para cambiar la red.' }
    $lista = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'Not Present' })
    $ad = @(if ($Adaptador) { $lista | Where-Object { $_.Name -eq $Adaptador } } else { $lista | Where-Object { $_.Status -eq 'Up' } })   # @() envuelve: con un solo adaptador el if devolvía el objeto suelto y .Count no valía
    if ($ad.Count -ne 1) { Write-Output "$($E.Error) $(if ($Adaptador) { "No existe el adaptador «$Adaptador»." } else { 'Hay 0 o varios adaptadores conectados: indica cuál con -Adaptador.' }) Disponibles: $(($lista.Name) -join ', ')"; exit 1 }
    try {
        if ($SoloAnalizar) {
            if ($Dhcp) { Write-Output "$($E.Info) Modo análisis: $($ad[0].Name) pasaría a IP y DNS automáticos (DHCP) y se renovaría la concesión." }
            else {
                $err = Test-DatosIp $IP $Mascara $Puerta $Dns; if ($err) { Exit-Kit 'Error' $err }
                Write-Output "$($E.Info) Modo análisis: $($ad[0].Name) tendría IP $IP, máscara $Mascara$(if ($Puerta) { ", puerta $Puerta" })$(if ($Dns) { ", DNS $($Dns -join ', ')" })."
            }
            Exit-Kit 'Ok' 'No se ha cambiado nada.'
        }
        if ($Dhcp) { Set-IpDhcp $ad[0].ifIndex; Write-Output "$($E.OK) $($ad[0].Name): IP y DNS automáticos (DHCP)." }
        else {
            $err = Test-DatosIp $IP $Mascara $Puerta $Dns; if ($err) { Write-Output "$($E.Error) $err"; exit 1 }
            Set-IpManual $ad[0].ifIndex $IP $Mascara $Puerta $Dns; Write-Output "$($E.OK) $($ad[0].Name): IP $IP, máscara $Mascara$(if ($Puerta) { ", puerta $Puerta" })."
        }
        Write-Log "Cambiar_IP (sin ventana): $($ad[0].Name)"
    } catch { Write-Output "$($E.Error) $($_.Exception.Message)"; Write-Log "Cambiar_IP: $($_.Exception.Message)" 'ERROR'; exit 1 }
    return
}

# Sin ventana y sin datos: -SoloAnalizar solo muestra los adaptadores
if ($SoloAnalizar) {
    foreach ($a in @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'Not Present' } | Sort-Object Name)) {
        $e = Get-Estado $a.ifIndex
        Write-Output "  $($E.Lupa) $($a.Name) [$($a.Status)] · $(if ($e.Dhcp) { 'DHCP' } else { 'IP manual' }) · IP $($e.Ip)/$($e.Prefijo) · puerta $($e.Puerta) · DNS $($e.Dns -join ', ')"
    }
    Exit-Kit 'Ok' 'Modo análisis: solo se han mostrado los adaptadores; no se ha cambiado nada.'
}

# ---------- perfiles ----------
$ficheroPerfiles = Join-Path (Get-BaseTrabajo) 'Perfiles_IP.json'   # pack público: en la caché del PC, no en el pendrive
# En 5.1 ConvertFrom-Json entrega el array entero como UN objeto: se guarda en una variable y se vuelve a abrir con @()
function Get-Perfiles { try { $j = Get-Content -LiteralPath $ficheroPerfiles -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json; @($j | Where-Object { $_ }) } catch { @() } }
function Save-Perfiles($l) { try { ConvertTo-Json -InputObject @($l) -Depth 3 | Set-Content -LiteralPath $ficheroPerfiles -Encoding UTF8 } catch { Write-Log "Perfiles_IP: $($_.Exception.Message)" 'AVISO' } }

# ---------- ventana ----------
function New-Etiqueta($t, $x, $y, $w = 0) { $l = New-Object Windows.Forms.Label; $l.Text = $t; $l.Location = New-Object Drawing.Point($x, $y); if ($w) { $l.Width = $w } else { $l.AutoSize = $true }; $l }
function New-Boton($t, $x, $y, $w, $h = 32) { $b = New-Object Windows.Forms.Button; $b.Text = $t; $b.Location = New-Object Drawing.Point($x, $y); $b.Size = New-Object Drawing.Size($w, $h); $b }

# Pide los datos de una IP; devuelve un hashtable o $null si se cancela
function Show-DialogoIp([string]$titulo, [bool]$conNombre) {
    $d = New-Object Windows.Forms.Form; $d.Text = $titulo; $d.ClientSize = New-Object Drawing.Size(400, $(if ($conNombre) { 290 } else { 256 })); $d.StartPosition = 'CenterParent'
    $d.FormBorderStyle = 'FixedDialog'; $d.MaximizeBox = $false; $d.MinimizeBox = $false; $d.Font = New-Object Drawing.Font('Segoe UI', 9.5); $d.TopMost = $true
    $y = 14; $cajas = @{}
    $campos = @(); if ($conNombre) { $campos += , @('Nombre', 'Descripción') }
    $campos += , @('Ip', 'Dirección IP'), @('Mascara', 'Máscara de subred'), @('Puerta', 'Puerta de enlace'), @('Dns', 'DNS preferido'), @('Dns2', 'DNS alternativo')
    foreach ($c in $campos) {
        $d.Controls.Add((New-Etiqueta $c[1] 16 ($y + 3) 130)); $t = New-Object Windows.Forms.TextBox; $t.Location = New-Object Drawing.Point(160, $y); $t.Width = 220
        if ($c[0] -eq 'Mascara') { $t.Text = '255.255.255.0' }; $d.Controls.Add($t); $cajas[$c[0]] = $t; $y += 34
    }
    $ok = New-Boton 'Aceptar' 174 ($y + 6) 100 30; $ca = New-Boton 'Cancelar' 280 ($y + 6) 100 30; $ca.DialogResult = 'Cancel'
    $d.Controls.AddRange(@($ok, $ca)); $d.AcceptButton = $ok; $d.CancelButton = $ca
    $ok.Add_Click({
        $err = Test-DatosIp $cajas.Ip.Text.Trim() $cajas.Mascara.Text.Trim() $cajas.Puerta.Text.Trim() @($cajas.Dns.Text.Trim(), $cajas.Dns2.Text.Trim())
        if (-not $err -and $conNombre -and -not $cajas.Nombre.Text.Trim()) { $err = 'Escribe una descripción para el perfil.' }
        if ($err) { [void][Windows.Forms.MessageBox]::Show($d, $err, $titulo, 'OK', 'Warning') } else { $d.DialogResult = 'OK' }
    }.GetNewClosure())
    if ($d.ShowDialog() -ne 'OK') { return $null }
    $r = @{}; foreach ($k in $cajas.Keys) { $r[$k] = $cajas[$k].Text.Trim() }; $r
}

$f = New-Object Windows.Forms.Form; $f.Text = 'Cambiar IP'; $f.ClientSize = New-Object Drawing.Size(760, 590); $f.StartPosition = 'CenterScreen'; $f.TopMost = $true
$f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.Font = New-Object Drawing.Font('Segoe UI', 9.5)
$f.Controls.Add((New-Etiqueta 'Elige el adaptador de red:' 20 12))
$cb = New-Object Windows.Forms.ComboBox; $cb.DropDownStyle = 'DropDownList'; $cb.Location = New-Object Drawing.Point(20, 36); $cb.Width = 570; $f.Controls.Add($cb)
$bAct = New-Boton 'Actualizar lista' 600 34 140 28; $f.Controls.Add($bAct)
$v = @{}; $y = 76
foreach ($c in @(@('Mac', 'Dirección MAC'), @('Estado', 'Estado de la red'), @('Dhcp', 'DHCP'))) { $f.Controls.Add((New-Etiqueta "$($c[1]):" 20 $y)); $v[$c[0]] = New-Etiqueta '-' 170 $y 300; $f.Controls.Add($v[$c[0]]); $y += 24 }

$lv = New-Object Windows.Forms.ListView; $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.GridLines = $true; $lv.MultiSelect = $false; $lv.Location = New-Object Drawing.Point(20, 156); $lv.Size = New-Object Drawing.Size(720, 170)
foreach ($c in @(@('Descripción', 150), @('IP', 110), @('Máscara', 110), @('Puerta', 110), @('DNS', 110), @('DNS alt.', 110))) { [void]$lv.Columns.Add($c[0], $c[1]) }
$f.Controls.Add($lv)
$bAdd = New-Boton 'Añadir perfil…' 20 332 140; $bApl = New-Boton 'Aplicar perfil' 170 332 140; $bDel = New-Boton 'Borrar perfil' 320 332 140; $f.Controls.AddRange(@($bAdd, $bApl, $bDel))

$g = New-Object Windows.Forms.GroupBox; $g.Text = 'Configuración actual'; $g.Location = New-Object Drawing.Point(20, 380); $g.Size = New-Object Drawing.Size(380, 170); $f.Controls.Add($g)
$y = 24; foreach ($c in @(@('Ip', 'Dirección IP'), @('Mask', 'Máscara de subred'), @('Gw', 'Puerta de enlace'), @('D1', 'DNS preferido'), @('D2', 'DNS alternativo'))) {
    $g.Controls.Add((New-Etiqueta "$($c[1]):" 14 $y)); $v[$c[0]] = New-Etiqueta '-' 170 $y 200; $g.Controls.Add($v[$c[0]]); $y += 28 }
$bMan = New-Boton 'IP manual…' 420 384 150 36; $bDhcp = New-Boton 'Activar DHCP' 590 384 150 36
$bAda = New-Boton 'Desactivar adaptador' 420 428 150 36; $bRel = New-Boton 'Liberar DHCP' 590 428 150 36
$bRen = New-Boton 'Renovar DHCP' 590 472 150 36; $bCer = New-Boton 'Cerrar' 590 516 150 36; $bCer.DialogResult = 'Cancel'
$f.Controls.AddRange(@($bMan, $bDhcp, $bAda, $bRel, $bRen, $bCer)); $f.CancelButton = $bCer
$msg = New-Etiqueta '' 20 560 720; $f.Controls.Add($msg)
$acciones = @($bMan, $bDhcp, $bAda, $bRel, $bRen, $bAdd, $bApl, $bDel)

$script:adaps = @()
function Get-IdxSel { if ($cb.SelectedIndex -ge 0) { [int]$script:adaps[$cb.SelectedIndex].ifIndex } else { -1 } }
function Update-Lista {
    $script:adaps = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'Not Present' } | Sort-Object Name)
    $cb.Items.Clear(); foreach ($a in $script:adaps) { [void]$cb.Items.Add("$($a.Name)  -  $($a.InterfaceDescription)") }
    $up = @($script:adaps | Where-Object { $_.Status -eq 'Up' }); $cb.SelectedIndex = $(if ($script:adaps.Count) { [array]::IndexOf($script:adaps, $(if ($up.Count) { $up[0] } else { $script:adaps[0] })) } else { -1 })
}
function Update-Datos {
    $i = Get-IdxSel; $hay = $i -ge 0
    foreach ($b in $acciones) { $b.Enabled = $hay }
    if (-not $hay) { foreach ($k in $v.Keys) { $v[$k].Text = '-' }; $v.Estado.Text = 'Ningún adaptador seleccionado'; return }
    $a = Get-NetAdapter -InterfaceIndex $i -ErrorAction SilentlyContinue; $e = Get-Estado $i
    $v.Mac.Text = [string]$a.MacAddress; $v.Estado.Text = switch ([string]$a.Status) { 'Up' { 'Conectado' } 'Disabled' { 'Desactivado' } 'Disconnected' { 'Sin cable / sin conexión' } default { [string]$a.Status } }
    $v.Dhcp.Text = $(if ($e.Dhcp) { 'Activado' } else { 'Desactivado (IP manual)' })
    $v.Ip.Text = $(if ($e.Ip) { $e.Ip } else { '-' }); $v.Mask.Text = $(if ($e.Prefijo) { ConvertFrom-Prefijo $e.Prefijo } else { '-' }); $v.Gw.Text = $(if ($e.Puerta) { $e.Puerta } else { '-' })
    $v.D1.Text = $(if ($e.Dns.Count -gt 0) { $e.Dns[0] } else { '-' }); $v.D2.Text = $(if ($e.Dns.Count -gt 1) { $e.Dns[1] } else { '-' })
    $bAda.Text = $(if ($a.Status -eq 'Disabled') { 'Activar adaptador' } else { 'Desactivar adaptador' })
    $bDhcp.Enabled = -not $e.Dhcp; $bRel.Enabled = $e.Dhcp; $bRen.Enabled = $e.Dhcp
}
function Update-Perfiles { $lv.Items.Clear(); foreach ($p in (Get-Perfiles)) { $it = New-Object Windows.Forms.ListViewItem([string]$p.Nombre); foreach ($k in 'Ip', 'Mascara', 'Puerta', 'Dns', 'Dns2') { [void]$it.SubItems.Add([string]$p.$k) }; $it.Tag = $p; [void]$lv.Items.Add($it) } }
function Get-SesionRemota {
    if ($env:SESSIONNAME -like 'RDP-*') { return 'sesión de Escritorio remoto' }
    $p = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(AnyDesk|TeamViewer|TeamViewer_Service|rustdesk|ScreenConnect\.ClientService|SunloginClient|ConnectWiseControl\.Client)$' } | Select-Object -ExpandProperty ProcessName -Unique)
    if ($p.Count) { "programa de acceso remoto activo: $($p -join ', ')" } else { $null }
}function Invoke-Accion([string]$titulo, [scriptblock]$cuerpo) {
    if (-not $esAdmin) { [void][Windows.Forms.MessageBox]::Show($f, 'Hace falta abrir el kit como administrador para cambiar la red.', $titulo, 'OK', 'Warning'); return }
    # Cambiar la IP o el DHCP puede cortar la conexión con la que el técnico está trabajando (RDP o programas de acceso remoto)
    $remoto = Get-SesionRemota
    if ($remoto -and $titulo -ne 'Activar adaptador' -and -not (Get-Pregunta "Parece que estás trabajando en remoto ($remoto). Cambiar la red puede cortar la conexión y dejarte sin acceso a este equipo.`n`n¿Continuar con «$titulo»?")) { return }
    $f.Cursor = 'WaitCursor'
    try { & $cuerpo; $msg.Text = "${titulo}: hecho."; Write-Log "Cambiar_IP: $titulo" }
    catch { $msg.Text = "${titulo}: falló ($($_.Exception.Message))"; Write-Log "Cambiar_IP ${titulo}: $($_.Exception.Message)" 'ERROR'; [void][Windows.Forms.MessageBox]::Show($f, $_.Exception.Message, $titulo, 'OK', 'Error') }
    finally { Start-Sleep -Milliseconds 800; $f.Cursor = 'Default'; Update-Datos }
}
function Get-Pregunta([string]$t) { [Windows.Forms.MessageBox]::Show($f, $t, 'Cambiar IP', 'YesNo', 'Question') -eq 'Yes' }
function Invoke-Aplicar($d) { $i = Get-IdxSel; Invoke-Accion 'IP manual' { Set-IpManual $i $d.Ip $d.Mascara $d.Puerta @($d.Dns, $d.Dns2) } }

$cb.Add_SelectedIndexChanged({ Update-Datos }); $bAct.Add_Click({ Update-Lista })
$bMan.Add_Click({ $d = Show-DialogoIp 'IP manual' $false; if ($d) { Invoke-Aplicar $d } })
$bAdd.Add_Click({ $d = Show-DialogoIp 'Nuevo perfil de IP' $true; if ($d) { $l = @(Get-Perfiles); $l += [pscustomobject]$d; Save-Perfiles $l; Update-Perfiles } })
$bApl.Add_Click({ if ($lv.SelectedItems.Count) { $p = $lv.SelectedItems[0].Tag; if (Get-Pregunta "¿Aplicar «$($p.Nombre)» ($($p.Ip)) a este adaptador?") { Invoke-Aplicar $p } } })
$lv.Add_DoubleClick({ $bApl.PerformClick() })
$bDel.Add_Click({ if ($lv.SelectedItems.Count) { $n = $lv.SelectedItems[0].Index; $l = @(Get-Perfiles); if (Get-Pregunta "¿Borrar el perfil «$($l[$n].Nombre)»?") { Save-Perfiles @($l | Where-Object { $_ -ne $l[$n] }); Update-Perfiles } } })
$bDhcp.Add_Click({ $i = Get-IdxSel; Invoke-Accion 'Activar DHCP' { Set-IpDhcp $i } })
$bAda.Add_Click({
    $i = Get-IdxSel; $a = Get-NetAdapter -InterfaceIndex $i -ErrorAction SilentlyContinue; if (-not $a) { return }
    if ($a.Status -eq 'Disabled') { Invoke-Accion 'Activar adaptador' { Enable-NetAdapter -InterfaceAlias $a.Name -Confirm:$false -ErrorAction Stop } }
    elseif (Get-Pregunta "¿Desactivar «$($a.Name)»? Si es el que da acceso a Internet o a este equipo en remoto, se cortará la conexión.") { Invoke-Accion 'Desactivar adaptador' { Disable-NetAdapter -InterfaceAlias $a.Name -Confirm:$false -ErrorAction Stop } }
})
$bRel.Add_Click({ $i = Get-IdxSel; Invoke-Accion 'Liberar DHCP' { [void](Invoke-Proceso (Join-Path $env:SystemRoot 'System32\ipconfig.exe') "/release `"$((Get-NetAdapter -InterfaceIndex $i).Name)`"" 60 'Liberar DHCP') } })
$bRen.Add_Click({ $i = Get-IdxSel; Invoke-Accion 'Renovar DHCP' { [void](Invoke-Proceso (Join-Path $env:SystemRoot 'System32\ipconfig.exe') "/renew `"$((Get-NetAdapter -InterfaceIndex $i).Name)`"" 60 'Renovar DHCP') } })

Update-Lista; Update-Datos; Update-Perfiles
if (-not $esAdmin) { $msg.Text = 'Sin permisos de administrador: solo se puede consultar.' }
if ($Captura) { $f.Add_Shown({ $bmp = New-Object Drawing.Bitmap $f.Width, $f.Height; $f.DrawToBitmap($bmp, (New-Object Drawing.Rectangle 0, 0, $f.Width, $f.Height)); $bmp.Save($Captura); $f.Close() }) }
[void]$f.ShowDialog()
Write-Log 'Cambiar_IP: ventana cerrada'
Write-Output "$($E.OK) Ventana cerrada.$(if ($script:op) { ' Los cambios se pueden deshacer en Mantenimiento > Deshacer cambios.' })"
