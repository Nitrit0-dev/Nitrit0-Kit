# =====================================================================
#  Red_WiFi_y_Claves.ps1 (Nitrit0 - 100% Local)
#   1. Muestra todas las redes Wi-Fi guardadas en el PC y sus contraseñas (leídas del XML que exporta netsh, no de texto traducido).
#   2. Configura DNS rápidos (Cloudflare 1.1.1.1 / Google 8.8.8.8 / Auto).
#   3. Reseteo completo de Red (DNS, DHCP, TCP/IP y Winsock): pide confirmación y no se deshace solo.
#  Parámetros: -Accion WIFI|DNS_CF|DNS_GOOGLE|DNS_AUTO|RESET (salta la ventana)  -SoloAnalizar (dice qué ofrece/haría; no cambia nada
#  ni muestra contraseñas). Salida: 0 bien · 1 error · 2 cancelado.
# =====================================================================
[CmdletBinding()]
param([ValidateSet('', 'WIFI', 'DNS_CF', 'DNS_GOOGLE', 'DNS_AUTO', 'RESET')][string]$Accion = '', [Alias('Simular')][switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
# Iconos propios de esta herramienta que Comun.ps1 no define
if (-not $E.Candado) { $E['Candado'] = [char]::ConvertFromUtf32(0x1F512) }
if (-not $E.Red) { $E['Red'] = [char]::ConvertFromUtf32(0x1F310) }

$descripciones = [ordered]@{
    WIFI       = 'Ver las contraseñas de las redes Wi-Fi guardadas (necesita administrador).'
    DNS_CF     = 'Poner el DNS de Cloudflare (1.1.1.1 / 1.0.0.1) en los adaptadores conectados; el anterior queda guardado en «Deshacer cambios».'
    DNS_GOOGLE = 'Poner el DNS de Google (8.8.8.8 / 8.8.4.4) en los adaptadores conectados; el anterior queda guardado en «Deshacer cambios».'
    DNS_AUTO   = 'Devolver el DNS a automático (el del router) en los adaptadores conectados.'
    RESET      = 'Reseteo profundo de red: vaciar caché DNS, renovar IP, «netsh int ip reset» y «netsh winsock reset». No se deshace solo y hay que reiniciar.'
}
if ($SoloAnalizar) {
    $ver = if ($Accion) { @($Accion) } else { @($descripciones.Keys) }
    Write-Output "  $($E.Info) Modo análisis: esta herramienta $(if ($Accion) { 'haría' } else { 'ofrece' }):"
    foreach ($a in $ver) { Write-Output "    · $($descripciones[$a])" }
    Exit-Kit 'Ok' 'No se ha cambiado nada ni se ha mostrado ninguna contraseña.'
}

$script:AccionRed = 'CANCELAR'
if ($Accion) { $script:AccionRed = $Accion }
else {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = "Red, Wi-Fi y DNS - Nitrit0"
    $Form.Size = New-Object System.Drawing.Size(450, 310)
    $Form.StartPosition = "CenterScreen"
    $Form.FormBorderStyle = "FixedDialog"
    $Form.MaximizeBox = $false
    $Form.TopMost = $true
    $Form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $Lbl = New-Object System.Windows.Forms.Label
    $Lbl.Text = "Selecciona la herramienta de Red y Conectividad:"
    $Lbl.Location = New-Object System.Drawing.Point(20, 14)
    $Lbl.AutoSize = $true
    $Lbl.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $Form.Controls.Add($Lbl)

    $Botones = @(
        @{ Txt = "1. Ver Contraseñas de todas las redes Wi-Fi guardadas";     Tag = "WIFI";       Color = "LightCyan" }
        @{ Txt = "2. Poner DNS Rápidos Cloudflare (1.1.1.1 / 1.0.0.1)";       Tag = "DNS_CF";     Color = "PaleGreen" }
        @{ Txt = "3. Poner DNS de Google (8.8.8.8) o Restaurar a Automático"; Tag = "DNS_GOOGLE"; Color = "Lavender" }
        @{ Txt = "4. Reparar y Resetear Red completa (DNS, TCP/IP y Winsock)";Tag = "RESET";      Color = "PeachPuff" }
        @{ Txt = "Cancelar";                                                  Tag = "CANCELAR";   Color = "LightCoral" }
    )
    $y = 42
    foreach ($b in $Botones) {
        $Btn = New-Object System.Windows.Forms.Button
        $Btn.Text = $b.Txt; $Btn.Tag = $b.Tag; $Btn.BackColor = $b.Color
        $Btn.Location = New-Object System.Drawing.Point(20, $y)
        $Btn.Size = New-Object System.Drawing.Size(395, 38)
        $Btn.Add_Click({ $script:AccionRed = $this.Tag; $Form.Close() })
        $Form.Controls.Add($Btn)
        $y += 44
    }
    [void]$Form.ShowDialog()
}

if ($script:AccionRed -eq "CANCELAR") { Exit-Kit 'Cancelado' 'Operación cancelada.' }

# --- 1. VER CLAVES WI-FI GUARDADAS ---
if ($script:AccionRed -eq "WIFI") {
    # Sin administrador netsh no incluye la clave en el XML: se vería «sin clave» en redes que sí la tienen
    Assert-Admin 'leer las contraseñas Wi-Fi guardadas (sin administrador Windows no las muestra)'
    Write-Output "`n========================================================"
    Write-Output "  $($E.Candado) REDES WI-FI Y CONTRASEÑAS GUARDADAS EN ESTE PC"
    Write-Output "========================================================`n"
    # El XML que exporta netsh no depende del idioma de Windows (el texto de «netsh wlan show» sí)
    # Restos de ejecuciones anteriores cortadas (con las claves en claro): se borran antes de empezar
    Get-ChildItem -LiteralPath $env:TEMP -Directory -Filter 'Nitrit0_wifi_*' -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    $dir = Join-Path $env:TEMP ('Nitrit0_wifi_' +[guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    try {
        $r = Invoke-Proceso (Join-Path $env:SystemRoot 'System32\netsh.exe') "wlan export profile key=clear folder=`"$dir`"" 60 'Exportar perfiles Wi-Fi'
        $ficheros = @(Get-ChildItem -LiteralPath $dir -Filter *.xml -ErrorAction SilentlyContinue)
        if (-not $ficheros.Count) {
            if ($r.Codigo -ne 0) {
                # Sin tarjeta Wi-Fi (sobremesa) netsh falla con el servicio WLAN parado: eso no es un error del equipo
                if (-not @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.PhysicalMediaType -match '802\.11' }).Count) { Exit-Kit 'Ok' 'Este equipo no tiene adaptador Wi-Fi: no hay contraseñas que mostrar.' }
                Exit-Kit 'Error' "No se pudieron leer los perfiles Wi-Fi (netsh, código $($r.Codigo)): el servicio WLAN puede estar parado."
            }
            Exit-Kit 'Ok' 'No hay perfiles Wi-Fi guardados o este equipo no tiene tarjeta Wi-Fi.'
        }
        $tabla = foreach ($f in $ficheros) {
            $ssid = $f.BaseName; $clave = '(no se pudo leer este perfil)'
            try {
                $x = New-Object System.Xml.XmlDocument; $x.Load($f.FullName)
                $p = $x.WLANProfile; $ssid = [string]$p.name
                $auth = [string]$p.MSM.security.authEncryption.authentication
                $km = [string]$p.MSM.security.sharedKey.keyMaterial
                $clave = if ($km) { $km } elseif ($auth -eq 'open') { '(red abierta, sin clave)' } else { '(sin clave guardada: red de empresa o no legible)' }
            } catch { }
            [PSCustomObject]@{ "Red Wi-Fi (SSID)" = $ssid; "Contraseña" = $clave }
        }
        $tabla | Format-Table -AutoSize | Out-String | ForEach-Object { $_.TrimEnd() } | Write-Output
        Write-Log "Red_WiFi: contraseñas mostradas ($(@($ficheros).Count) redes)"
        Exit-Kit 'Ok' "Total de redes Wi-Fi recuperadas: $(@($ficheros).Count)"
    } finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
}

# --- 2 y 3. CAMBIAR DNS ---
if ($script:AccionRed -in @("DNS_CF", "DNS_GOOGLE", "DNS_AUTO")) {
    Assert-Admin 'cambiar el DNS'
    $modo = $script:AccionRed
    if ($modo -eq 'DNS_GOOGLE' -and -not $Accion) {
        $r = [System.Windows.Forms.MessageBox]::Show("¿Quieres poner los DNS de Google (8.8.8.8 / 8.8.4.4)?`n`nPulsa 'Sí' para DNS Google, o 'No' para dejar los DNS en Automático (DHCP del router).", "Configurar DNS", "YesNoCancel", "Question")
        if ($r -eq 'No') { $modo = 'DNS_AUTO' } elseif ($r -ne 'Yes') { Exit-Kit 'Cancelado' 'No se ha cambiado el DNS.' }
    }
    $Adaptadores = @(Get-NetAdapter | Where-Object { $_.Status -eq 'Up' })
    if ($Adaptadores.Count -eq 0) { Exit-Kit 'Error' 'No se encontró ningún adaptador de red conectado.' }
    [void](Start-OperacionSegura 'Cambiar DNS (Wi-Fi y claves)' -SinPuntoRestauracion)
    $ips = switch ($modo) { 'DNS_CF' { @('1.1.1.1', '1.0.0.1') } 'DNS_GOOGLE' { @('8.8.8.8', '8.8.4.4') } default { $null } }
    $nombreDns = switch ($modo) { 'DNS_CF' { 'DNS Cloudflare (1.1.1.1 / 1.0.0.1)' } 'DNS_GOOGLE' { 'DNS Google (8.8.8.8 / 8.8.4.4)' } default { 'DNS en Automático (DHCP)' } }
    $fallos = 0
    foreach ($a in $Adaptadores) {
        try { if ($ips) { Set-DnsSeguro $a.ifIndex $ips } else { Set-DnsSeguro $a.ifIndex -Automatico } }
        catch { $fallos++; Write-Output "  $($E.Error) No se pudo cambiar el DNS en '$($a.Name)': $($_.Exception.Message)"; continue }
        Write-Output "  $($E.OK) $nombreDns aplicados en '$($a.Name)'."
    }
    Clear-DnsClientCache -ErrorAction SilentlyContinue
    Write-Output "  $($E.Info) Para volver al DNS anterior: Mantenimiento > Deshacer cambios."
    if ($fallos) { Exit-Kit 'Error' "$fallos adaptador(es) sin cambiar." }
    Exit-Kit 'Ok'
}

# --- 4. RESET DE RED ---
if ($script:AccionRed -eq "RESET") {
    Assert-Admin 'resetear la red'
    if (-not (Confirm-Accion "Se va a resetear la red: caché DNS, IP por DHCP, pila TCP/IP y catálogo Winsock.`n`nEl reset de Winsock desactiva componentes de terceros (VPN, filtros de antivirus) y «Deshacer cambios» no puede revertirlo; hay que reiniciar el equipo.`n`n¿Continuar?" 'Resetear la red')) { Exit-Kit 'Cancelado' 'Cancelado: no se ha cambiado la red.' }
    [void](Start-OperacionSegura 'Resetear la red')
    Save-Informativo 'Reset de la pila TCP/IP y de Winsock' 'No se deshace solo: reinicia el equipo; si una VPN o un filtro de antivirus deja de funcionar, reinstálalo.'
    Write-Output "`n========================================================"
    Write-Output "  $($E.Red) RESETEO PROFUNDO DE RED, IP Y DNS"
    Write-Output "========================================================`n"
    $fallos = 0
    Write-Output "  $($E.Reloj) [1/4] Vaciando caché DNS..."
    Clear-DnsClientCache -ErrorAction SilentlyContinue
    & ipconfig.exe /flushdns | Out-Null; if ($LASTEXITCODE -ne 0) { $fallos++; Write-Output "    $($E.Aviso) ipconfig /flushdns terminó con código $LASTEXITCODE." }

    Write-Output "  $($E.Reloj) [2/4] Renovando dirección IP (DHCP)..."
    & ipconfig.exe /renew | Out-Null; if ($LASTEXITCODE -ne 0) { Write-Output "    $($E.Aviso) ipconfig /renew terminó con código $LASTEXITCODE (sin DHCP en algún adaptador es normal; no cuenta como fallo)." }

    Write-Output "  $($E.Reloj) [3/4] Restableciendo pila TCP/IP..."
    & netsh.exe int ip reset | Out-Null; if ($LASTEXITCODE -ne 0) { $fallos++; Write-Output "    $($E.Error) netsh int ip reset terminó con código $LASTEXITCODE." }

    Write-Output "  $($E.Reloj) [4/4] Restableciendo catálogo Winsock..."
    & netsh.exe winsock reset | Out-Null; if ($LASTEXITCODE -ne 0) { $fallos++; Write-Output "    $($E.Error) netsh winsock reset terminó con código $LASTEXITCODE." }

    Write-Log "Red_WiFi: reset de red terminado con $fallos aviso(s)"
    if ($fallos) { Exit-Kit 'Error' "Red restablecida con $fallos paso(s) con error. Reinicia el equipo y vuelve a comprobarlo." }
    Exit-Kit 'Ok' 'Red restablecida. Reinicia el equipo para completar los cambios.'
}
