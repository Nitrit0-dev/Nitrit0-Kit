# =====================================================================
#  Instalar_Impresora_Red.ps1 - Añade una impresora de red por su dirección IP (Nitrit0)
#  Pide la IP, comprueba que la impresora responde, crea el puerto TCP/IP y la instala con el mejor
#  controlador que ya haya en el equipo (o el que se elija). No descarga nada.
#  Parámetros: -IP <dirección> -Nombre <nombre> -Driver <controlador>  (sin ellos, pregunta en una ventana)
# =====================================================================
[CmdletBinding()]
param([string]$IP, [string]$Nombre, [string]$Driver, [Alias('Simular')][switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
if (-not $SoloAnalizar) { Assert-Admin 'instalar la impresora' }

Write-Output "========================================================"
Write-Output "  $($E.Lupa) INSTALAR IMPRESORA DE RED POR IP"
Write-Output "========================================================"

if ((Get-Service Spooler -ErrorAction SilentlyContinue).Status -ne 'Running') {
    if ($SoloAnalizar) { Exit-Kit 'Ok' 'Modo análisis: el servicio de impresión está parado; se iniciaría antes de instalar. No se ha cambiado nada.' }
    try { Start-Service Spooler -ErrorAction Stop; Write-Output "  $($E.Aviso) El servicio de impresión estaba parado: se ha iniciado." }
    catch { Write-Output "  $($E.Error) El servicio de impresión no arranca: $($_.Exception.Message). Pasa antes «Reparar impresoras»."; exit 1 }
}

# Controladores ya instalados. Se descartan los que no imprimen en papel (PDF, XPS, fax, OneNote).
$drivers = @(Get-PrinterDriver -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch 'PDF|XPS|Fax|OneNote|Remote Desktop|Send To' } | Select-Object -ExpandProperty Name | Sort-Object -Unique)
if (-not $drivers.Count) { Write-Output "  $($E.Error) No hay ningún controlador de impresora utilizable en este equipo. Instala primero el del fabricante."; exit 1 }
# Preferencia: el universal del fabricante si está; si no, el genérico IPP de Windows (sirve para casi todas las impresoras modernas)
$preferidos = 'Universal', 'PCL ?6', 'PCL6', 'UFR', 'Microsoft IPP Class Driver', 'PostScript|\bPS\b', 'PCL'
$recomendado = $null; foreach ($p in $preferidos) { $recomendado = $drivers | Where-Object { $_ -match $p } | Select-Object -First 1; if ($recomendado) { break } }
if (-not $recomendado) { $recomendado = $drivers[0] }

if (-not $IP -and $SoloAnalizar) { Exit-Kit 'Ok' "Modo análisis: controlador recomendado «$recomendado» entre $($drivers.Count) disponibles. Indica -IP para simular la instalación; no se ha cambiado nada." }
if (-not $IP) {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $f = New-Object Windows.Forms.Form; $f.Text = 'Instalar impresora de red'; $f.ClientSize = New-Object Drawing.Size(460, 250); $f.StartPosition = 'CenterScreen'
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false; $f.Font = New-Object Drawing.Font('Segoe UI', 9.5)
    $mk = { param($t, $y) $l = New-Object Windows.Forms.Label; $l.Text = $t; $l.AutoSize = $true; $l.Location = New-Object Drawing.Point(18, $y); $f.Controls.Add($l) }
    & $mk 'Dirección IP de la impresora (mírala en su pantalla o en la hoja de configuración):' 14
    $tIp = New-Object Windows.Forms.TextBox; $tIp.Location = New-Object Drawing.Point(20, 38); $tIp.Width = 200; $f.Controls.Add($tIp)
    & $mk 'Nombre con el que aparecerá (opcional):' 72
    $tNom = New-Object Windows.Forms.TextBox; $tNom.Location = New-Object Drawing.Point(20, 96); $tNom.Width = 420; $f.Controls.Add($tNom)
    & $mk 'Controlador:' 130
    $cb = New-Object Windows.Forms.ComboBox; $cb.DropDownStyle = 'DropDownList'; $cb.Location = New-Object Drawing.Point(20, 154); $cb.Width = 420
    [void]$cb.Items.AddRange([object[]]$drivers); $cb.SelectedItem = $recomendado; $f.Controls.Add($cb)
    $ok = New-Object Windows.Forms.Button; $ok.Text = 'Instalar'; $ok.Size = New-Object Drawing.Size(100, 30); $ok.Location = New-Object Drawing.Point(234, 204); $ok.DialogResult = 'OK'
    $ca = New-Object Windows.Forms.Button; $ca.Text = 'Cancelar'; $ca.Size = New-Object Drawing.Size(100, 30); $ca.Location = New-Object Drawing.Point(340, 204); $ca.DialogResult = 'Cancel'
    $f.Controls.AddRange(@($ok, $ca)); $f.AcceptButton = $ok; $f.CancelButton = $ca
    if ($f.ShowDialog() -ne 'OK') { Exit-Kit 'Cancelado' 'Cancelado: no se ha instalado nada.' }
    $IP = $tIp.Text.Trim(); $Nombre = $tNom.Text.Trim(); $Driver = [string]$cb.SelectedItem
}
if (-not $Driver) { $Driver = $recomendado }

$ipObj = $null
if (-not ([Net.IPAddress]::TryParse($IP, [ref]$ipObj)) -or $ipObj.AddressFamily -ne 'InterNetwork' -or $IP -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
    Write-Output "  $($E.Error) «$IP» no es una dirección IP válida (ejemplo: 192.168.1.50)."; exit 1
}
if ($drivers -notcontains $Driver) { Write-Output "  $($E.Error) El controlador «$Driver» no está instalado en este equipo."; exit 1 }
if (-not $Nombre) { $Nombre = "Impresora de red ($IP)" }

# ¿Responde la impresora? Se prueban los puertos de impresión habituales (9100 RAW, 631 IPP, 515 LPR)
function Test-Puerto([string]$h, [int]$p) { try { $c = New-Object Net.Sockets.TcpClient; $r = $c.BeginConnect($h, $p, $null, $null); $ok = $r.AsyncWaitHandle.WaitOne(2000) -and $c.Connected; $c.Close(); $ok } catch { $false } }
Write-Output "  $($E.Reloj) Comprobando que $IP responde…"
$abiertos = @(9100, 631, 515 | Where-Object { Test-Puerto $IP $_ })
if ($abiertos.Count) { Write-Output "  $($E.OK) La impresora responde (puerto $($abiertos -join ', '))." }
else {
    $ping = Test-Connection -ComputerName $IP -Count 2 -Quiet -ErrorAction SilentlyContinue
    Write-Output "  $($E.Aviso) $IP no responde en los puertos de impresión$(if ($ping) { ', aunque sí al ping: puede que esa IP no sea de una impresora' } else { ' ni al ping: comprueba que está encendida, en la misma red y que la IP es correcta' })."
    Add-Type -AssemblyName System.Windows.Forms
    if (-not $SoloAnalizar -and [Windows.Forms.MessageBox]::Show("La impresora no responde en $IP.`n`n¿Instalarla de todos modos? (quedará instalada pero no imprimirá hasta que esa IP responda)", 'Impresora de red', 'YesNo', 'Warning', 'Button2') -ne 'Yes') { Write-Output "  $($E.Info) Cancelado: no se ha instalado nada."; exit 2 }
}

if ($SoloAnalizar) { Exit-Kit 'Ok' "Modo análisis: se crearía el puerto IP_$IP y se instalaría «$Nombre» con el controlador «$Driver». No se ha cambiado nada." }
[void](Start-OperacionSegura 'Instalar impresora de red' -SinPuntoRestauracion)
$puerto = "IP_$IP"
try {
    if (Get-PrinterPort -Name $puerto -ErrorAction SilentlyContinue) { Write-Output "  $($E.Info) Ya existía el puerto ${puerto}: se reutiliza." }
    else {
        # Si solo responde por LPR (515) se crea el puerto en ese modo; lo normal es RAW 9100
        if ($abiertos.Count -and $abiertos -notcontains 9100 -and $abiertos -contains 515) { Add-PrinterPort -Name $puerto -LprHostAddress $IP -LprQueueName 'lp' -ErrorAction Stop }
        else { Add-PrinterPort -Name $puerto -PrinterHostAddress $IP -ErrorAction Stop }
        Write-Output "  $($E.OK) Puerto TCP/IP $puerto creado."
    }
    if (Get-Printer -Name $Nombre -ErrorAction SilentlyContinue) { Write-Output "  $($E.Info) Ya hay una impresora llamada «$Nombre»: no se duplica." }
    else {
        Add-Printer -Name $Nombre -PortName $puerto -DriverName $Driver -ErrorAction Stop
        Write-Output "  $($E.OK) Impresora «$Nombre» instalada con el controlador «$Driver»."
        Save-Informativo "Impresora de red instalada: $Nombre ($IP)" 'Para quitarla: Configuración > Bluetooth y dispositivos > Impresoras y escáneres > Quitar (el puerto IP_<ip> puede quedar).'
        Write-Log "Impresora de red instalada: $Nombre ($IP, $Driver)"
    }
} catch {
    Write-Output "  $($E.Error) No se pudo instalar: $($_.Exception.Message)"; Write-Log "Impresora de red: fallo al instalar $IP - $($_.Exception.Message)" 'ERROR'; exit 1
}

if ($abiertos.Count -and -not $PSBoundParameters.ContainsKey('IP')) {
    if ([Windows.Forms.MessageBox]::Show("¿Imprimir una página de prueba en «$Nombre»?", 'Impresora de red', 'YesNo', 'Question') -eq 'Yes') {
        $pi = Get-CimInstance Win32_Printer -Filter ("Name='{0}'" -f ($Nombre -replace "'", "''")) -ErrorAction SilentlyContinue
        $r = if ($pi) { Invoke-CimMethod -InputObject $pi -MethodName PrintTestPage -ErrorAction SilentlyContinue }
        Write-Output "  $(if ($r -and $r.ReturnValue -eq 0) { $E.OK + ' Página de prueba enviada.' } else { $E.Aviso + ' No se pudo enviar la página de prueba.' })"
    }
}
Write-Output "  $($E.Info) Si sale texto raro o símbolos, el controlador no es el adecuado: quita la impresora en Configuración > Impresoras e instala el del fabricante."
Write-Output "  $($E.Info) Para quitarla: Configuración > Bluetooth y dispositivos > Impresoras y escáneres > «$Nombre» > Quitar."
