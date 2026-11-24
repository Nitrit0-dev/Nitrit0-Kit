# =====================================================================
#  Componentes del kit - Nitrit0
#  Controlador de sensores PawnIO (se ofrece instalar la primera vez en cada equipo),
#  estado de smartmontools y LibreHardwareMonitor, y ajustes guardados en Datos\Ajustes.json
# =====================================================================

function Get-Ajustes {
    $p = Join-Path $dirDatos 'Ajustes.json'
    $a = @{ SensoresDriver = 'preguntar'; QuitarDriverAlSalir = $false; Tecnico = $env:USERNAME }
    try { if (Test-Path -LiteralPath $p) { $j = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json; foreach ($n in $j.PSObject.Properties.Name) { $a[$n] = $j.$n } } } catch { }
    $a
}
function Set-Ajustes($a) { try { $a | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dirDatos 'Ajustes.json') -Encoding UTF8 } catch { } }

function Get-EstadoComponentes {
    $setup = Join-Path $dirApps 'Componentes\PawnIO_setup.exe'
    [pscustomobject]@{
        Driver        = [bool](Get-Service -Name PawnIO -ErrorAction SilentlyContinue)
        DriverSetup   = (Test-Path -LiteralPath $setup)
        SetupRuta     = $setup
        Smartctl      = (Test-Path -LiteralPath (Join-Path $dirApps 'Disk\smartmontools\bin\smartctl.exe'))
        Sensores      = (Test-Path -LiteralPath (Join-Path $dirApps 'HW Info\LibreHardwareMonitor\LibreHardwareMonitorLib.dll'))
    }
}

# Instala (o quita) el controlador PawnIO. El lanzador ya se ejecuta como administrador.
function Invoke-Pawnio([string]$accion) {
    $e = Get-EstadoComponentes
    if (-not $e.DriverSetup) { return [pscustomobject]@{ Ok = $false; Mensaje = 'Falta Apps\Componentes\PawnIO_setup.exe.' } }
    # Se ejecuta como administrador: antes se comprueba su huella contra Datos\Integridad.json
    $m = Test-ScriptAutorizado $e.SetupRuta; if ($m) { return [pscustomobject]@{ Ok = $false; Mensaje = "No se ejecuta PawnIO_setup.exe: $m." } }
    try {
        $arg = if ($accion -eq 'instalar') { '-install -silent' } else { '-uninstall -silent' }
        $setup = $e.SetupRuta; try { $setup = Copy-AlCache $e.SetupRuta } catch { Write-Log "No se pudo copiar PawnIO a la caché: $($_.Exception.Message)" 'AVISO' }   # se ejecuta desde %TEMP%, no desde el pendrive
        $p = Start-Process -FilePath $setup -ArgumentList $arg -PassThru -WindowStyle Hidden
        if (-not $p.WaitForExit(120000)) { try { $p.Kill() } catch { }; return [pscustomobject]@{ Ok = $false; Mensaje = 'El instalador tardó demasiado.' } }
        $ahora = [bool](Get-Service -Name PawnIO -ErrorAction SilentlyContinue)
        $ok = if ($accion -eq 'instalar') { $ahora } else { -not $ahora }
        [pscustomobject]@{ Ok = $ok; Mensaje = $(if ($ok) { 'Hecho.' } else { "El instalador terminó con código $($p.ExitCode) y el estado no cambió." }) }
    } catch { [pscustomobject]@{ Ok = $false; Mensaje = $_.Exception.Message } }
}

# Primera vez en un equipo: ofrece instalar el controlador de sensores
function Invoke-OfertaDriver {
    $a = Get-Ajustes; $e = Get-EstadoComponentes
    if ($e.Driver -or -not $e.DriverSetup -or -not $e.Sensores -or $a.SensoresDriver -eq 'no') { return }
    $txt = "Para medir la temperatura real de la CPU, los ventiladores y la potencia hace falta instalar el controlador de sensores PawnIO (firmado, de código abierto).`n`n" +
           "• Sí: instalarlo ahora (se puede quitar desde «Componentes»).`n• No: ahora no (se volverá a preguntar la próxima vez).`n• Cancelar: no preguntar más en este kit.`n`n" +
           "Sin él todo funciona igual, pero la temperatura de la CPU no será fiable."
    $r = [Windows.Forms.MessageBox]::Show($txt, 'Sensores de temperatura', 'YesNoCancel', 'Question')
    if ($r -eq 'Cancel') { $a.SensoresDriver = 'no'; Set-Ajustes $a; return }
    if ($r -eq 'Yes') {
        $form.Cursor = 'WaitCursor'; $res = Invoke-Pawnio 'instalar'; $form.Cursor = 'Default'
        if ($res.Ok) { $script:DriverInstaladoEnSesion = $true; $lbl.Text = 'Controlador de sensores instalado.' }
        else { [void][Windows.Forms.MessageBox]::Show("No se pudo instalar el controlador:`n$($res.Mensaje)", 'Sensores', 0, 48) }
    }
}

function Show-Componentes {
    $K = $script:K; $cFondo = Get-Tc 'Fondo'; $cTexto = Get-Tc 'TextoSuave'; $cFlat = Get-Tc 'Boton'; $cAcento = Get-Tc 'Acento'
    $dlg = New-Object Windows.Forms.Form; $dlg.Text = 'Componentes del kit'; $dlg.Size = New-Object Drawing.Size([int](760 * $K), [int](520 * $K)); $dlg.StartPosition = 'CenterParent'; $dlg.BackColor = $cFondo; $dlg.Font = New-Object Drawing.Font($script:Fuentes.UI, 9.5); $dlg.FormBorderStyle = 'FixedDialog'; $dlg.MaximizeBox = $false
    if ($form.Icon) { $dlg.Icon = $form.Icon }
    $tit = New-Object Windows.Forms.Label; $tit.Text = 'Componentes del kit'; $tit.ForeColor = (Get-Tc 'Texto'); $tit.Font = New-Object Drawing.Font($script:Fuentes.Display, 16); $tit.AutoSize = $true; $tit.Location = New-Object Drawing.Point([int](24 * $K), [int](16 * $K))
    $sub = New-Object Windows.Forms.Label; $sub.Text = 'Piezas opcionales que amplían el diagnóstico. Todo se instala solo si tú lo apruebas.'; $sub.ForeColor = $cTexto; $sub.AutoSize = $true; $sub.Location = New-Object Drawing.Point([int](26 * $K), [int](58 * $K))
    $dlg.Controls.AddRange(@($tit, $sub))
    $filas = @{}
    $y = [int](100 * $K)
    foreach ($n in @(@('driver', 'Controlador de sensores (PawnIO)', 'Permite leer la temperatura real de la CPU, ventiladores y potencia. Necesita instalarse una vez por equipo.'), @('smart', 'smartmontools (smartctl)', 'SMART detallado de los discos. Va incluido en el kit, no necesita instalación.'), @('lhm', 'LibreHardwareMonitor', 'Biblioteca de lectura de sensores. Va incluida en el kit.'))) {
        $p = New-Object Windows.Forms.Panel; $p.Size = New-Object Drawing.Size([int](700 * $K), [int](88 * $K)); $p.Location = New-Object Drawing.Point([int](24 * $K), $y); $p.BackColor = Get-Tc 'Tarjeta'
        $l1 = New-Object Windows.Forms.Label; $l1.Text = $n[1]; $l1.ForeColor = (Get-Tc 'Texto'); $l1.Font = New-Object Drawing.Font($script:Fuentes.Semi, 11); $l1.AutoSize = $true; $l1.Location = New-Object Drawing.Point([int](14 * $K), [int](10 * $K))
        $l2 = New-Object Windows.Forms.Label; $l2.Text = $n[2]; $l2.ForeColor = $cTexto; $l2.Size = New-Object Drawing.Size([int](470 * $K), [int](40 * $K)); $l2.Location = New-Object Drawing.Point([int](14 * $K), [int](38 * $K))
        $est = New-Object Windows.Forms.Label; $est.AutoSize = $false; $est.Size = New-Object Drawing.Size([int](150 * $K), [int](24 * $K)); $est.Location = New-Object Drawing.Point([int](500 * $K), [int](10 * $K)); $est.TextAlign = 'MiddleRight'; $est.Font = New-Object Drawing.Font($script:Fuentes.Semi, 10)
        $p.Controls.AddRange(@($l1, $l2, $est)); $dlg.Controls.Add($p); $filas[$n[0]] = @{ Panel = $p; Estado = $est }; $y += [int](98 * $K)
    }
    $btn = New-Object Windows.Forms.Button; $btn.Size = New-Object Drawing.Size([int](150 * $K), [int](34 * $K)); $btn.FlatStyle = 'Flat'; $btn.Font = New-Object Drawing.Font($script:Fuentes.Semi, 9.5); $btn.Cursor = 'Hand'; $btn.FlatAppearance.BorderColor = Get-Tc 'Borde'
    $btn.Location = New-Object Drawing.Point([int](528 * $K), [int](46 * $K)); $filas['driver'].Panel.Controls.Add($btn); $btn.BringToFront()
    $chk = New-Object Windows.Forms.CheckBox; $chk.Text = 'Quitar el controlador al cerrar el lanzador (recomendado en equipos de clientes)'; $chk.ForeColor = (Get-Tc 'Texto'); $chk.AutoSize = $true; $chk.Location = New-Object Drawing.Point([int](26 * $K), [int](400 * $K))
    $cerrar = New-Object Windows.Forms.Button; $cerrar.Text = 'Cerrar'; $cerrar.Size = New-Object Drawing.Size([int](120 * $K), [int](36 * $K)); $cerrar.Location = New-Object Drawing.Point([int](604 * $K), [int](430 * $K)); $cerrar.FlatStyle = 'Flat'; $cerrar.BackColor = $cFlat; $cerrar.ForeColor = (Get-Tc 'Texto'); $cerrar.FlatAppearance.BorderColor = Get-Tc 'Borde'; $cerrar.DialogResult = 'OK'
    $dlg.Controls.AddRange(@($chk, $cerrar)); $dlg.AcceptButton = $cerrar
    $a = Get-Ajustes; $chk.Checked = [bool]$a.QuitarDriverAlSalir
    $Refrescar = {
        $e = Get-EstadoComponentes
        $filas['driver'].Estado.Text = $(if ($e.Driver) { 'Instalado' } else { 'No instalado' }); $filas['driver'].Estado.ForeColor = $(if ($e.Driver) { Get-Tc 'Ok' } else { Get-Tc 'Aviso' })
        $filas['smart'].Estado.Text = $(if ($e.Smartctl) { 'Incluido' } else { 'Falta' }); $filas['smart'].Estado.ForeColor = $(if ($e.Smartctl) { Get-Tc 'Ok' } else { Get-Tc 'Fallo' })
        $filas['lhm'].Estado.Text = $(if ($e.Sensores) { 'Incluida' } else { 'Falta' }); $filas['lhm'].Estado.ForeColor = $(if ($e.Sensores) { Get-Tc 'Ok' } else { Get-Tc 'Fallo' })
        $btn.Text = $(if ($e.Driver) { 'Quitar controlador' } else { 'Instalar controlador' }); $btn.BackColor = $(if ($e.Driver) { $cFlat } else { $cAcento }); $btn.ForeColor = $(if ($e.Driver) { (Get-Tc 'Texto') } else { Get-Tc 'TextoAcento' }); $btn.Enabled = $e.DriverSetup
    }
    & $Refrescar
    $btn.Add_Click({
        $dlg.Cursor = 'WaitCursor'; $e = Get-EstadoComponentes
        $res = Invoke-Pawnio $(if ($e.Driver) { 'quitar' } else { 'instalar' })
        if ($res.Ok -and -not $e.Driver) { $script:DriverInstaladoEnSesion = $true }
        $dlg.Cursor = 'Default'; & $Refrescar
        if (-not $res.Ok) { [void][Windows.Forms.MessageBox]::Show($res.Mensaje, 'Componentes', 0, 48) }
    })
    $dlg.Add_FormClosing({ $a = Get-Ajustes; $a.QuitarDriverAlSalir = $chk.Checked; Set-Ajustes $a })
    [void]$dlg.ShowDialog($form)
}
