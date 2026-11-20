# =====================================================================
#  Ventana_Diagnostico.ps1 - Ventana del diagnóstico del equipo (Nitrit0)
#  Solo es la interfaz: las pruebas las hace Motor_Diagnostico.ps1 en un hilo aparte.
#  Guarda cada diagnóstico en el historial, lo compara con el anterior y ofrece la solución del kit en cada fila con problema.
# =====================================================================

# El motor define $script:Pruebas (la lista de pruebas) y Start-Diagnostico
. (Join-Path $PSScriptRoot 'Motor_Diagnostico.ps1')

$script:FichaCliente = @{
    Cliente  = ''
    Telefono = ''
    Motivo   = ''
    Notas    = ''
}

function Show-FichaCliente {
    $f = New-Object Windows.Forms.Form
    $f.Text = 'Ficha de Recepción del Equipo (Modo Taller)'
    $f.Size = New-Object Drawing.Size([int](480 * $script:K), [int](390 * $script:K))
    $f.StartPosition = 'CenterParent'
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false
    $f.BackColor = Get-Tc 'Fondo'; $f.ForeColor = Get-Tc 'Texto'
    $f.Font = New-Object Drawing.Font($script:Fuentes.UI, 9.5)
    $f.Add_HandleCreated({ [Nit.NativeUx]::SetDarkTitleBar($f.Handle, ($script:TemaActual -eq 'oscuro')) })

    $k = $script:K
    $script:y = [int](18 * $k)
    function Add-Campo($titulo, $valor, $alto=28, $multi=$false) {
        $l = New-Object Windows.Forms.Label; $l.Text = $titulo; $l.AutoSize = $true
        $l.ForeColor = Get-Tc 'Acento'; $l.Font = New-Object Drawing.Font($script:Fuentes.Semi, 9.5)
        $l.Location = New-Object Drawing.Point([int](22 * $k), $script:y)
        $f.Controls.Add($l)
        $script:y += [int](22 * $k)
        $tb = New-Object Windows.Forms.TextBox; $tb.Text = $valor; $tb.Multiline = $multi
        $tb.BorderStyle = 'FixedSingle'; $tb.BackColor = Get-Tc 'Tarjeta'; $tb.ForeColor = Get-Tc 'Texto'
        $tb.Size = New-Object Drawing.Size([int](418 * $k), [int]($alto * $k))
        $tb.Location = New-Object Drawing.Point([int](22 * $k), $script:y)
        $f.Controls.Add($tb)
        $script:y += [int](($alto + 14) * $k)
        $tb
    }

    $tbCli = Add-Campo 'Nombre del cliente o empresa:' $script:FichaCliente.Cliente
    $tbTel = Add-Campo 'Teléfono / Contacto / Nº Orden:' $script:FichaCliente.Telefono
    $tbMot = Add-Campo 'Síntoma o avería que indica el cliente:' $script:FichaCliente.Motivo 54 $true
    $tbNot = Add-Campo 'Observaciones del técnico (golpes, cargador, contraseña):' $script:FichaCliente.Notas 54 $true

    $btnOk = New-Object BotonPro; $btnOk.Text = 'Guardar ficha'; $btnOk.Size = New-Object Drawing.Size([int](145 * $k), [int](38 * $k))
    $btnOk.Location = New-Object Drawing.Point([int](295 * $k), $script:y); $btnOk.ColorFondo = Get-Tc 'Acento'; $btnOk.ColorTexto = Get-Tc 'TextoAcento'
    $btnOk.Add_Click({
        $script:FichaCliente.Cliente  = $tbCli.Text.Trim()
        $script:FichaCliente.Telefono = $tbTel.Text.Trim()
        $script:FichaCliente.Motivo   = $tbMot.Text.Trim()
        $script:FichaCliente.Notas    = $tbNot.Text.Trim()
        $f.DialogResult = 'OK'; $f.Close()
    })
    $f.Controls.Add($btnOk)
    [void]$f.ShowDialog()
}

function Show-Diagnostico([string]$Modo = 'Rapido', [bool]$AutoStart = $false, [bool]$PedirFicha = $false) {
    if ($PedirFicha) { Show-FichaCliente }

    $k = $script:K
    $dx = New-Object Windows.Forms.Form
    $dx.Text = 'Diagnóstico del equipo'
    $dx.Size = New-Object Drawing.Size([int](980 * $k), [int](690 * $k))
    $dx.StartPosition = 'CenterParent'
    $dx.BackColor = Get-Tc 'Fondo'; $dx.ForeColor = Get-Tc 'Texto'
    $dx.Font = New-Object Drawing.Font($script:Fuentes.UI, 9.5)
    if ($bmpLogo) { try { $dx.Icon = [Drawing.Icon]::FromHandle($bmpLogo.GetHicon()) } catch { } }
    $dx.Add_HandleCreated({ [Nit.NativeUx]::SetDarkTitleBar($dx.Handle, ($script:TemaActual -eq 'oscuro')) })

    # Panel Superior (Cabecera con Anillo de Progreso y Botones Fluent)
    $top = New-Object Windows.Forms.Panel; $top.Dock = 'Top'; $top.Height = [int](195 * $k); $top.BackColor = Get-Tc 'Cab'
    $top.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($top, $true, $null)

    $script:DxPct = 0
    $script:DxEstado = 'Listo'
    $script:DxModo = $Modo
    $script:DxRunning = $false

    $top.Add_Paint({
        param($s, $e)
        $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'ClearTypeGridFit'; $k = $script:K
        # Anillo circular de progreso
        $cx = [int](26 * $k); $cy = [int](22 * $k); $d = [int](146 * $k)
        $rRing = New-Object Drawing.Rectangle $cx, $cy, $d, $d
        $penBg = New-Object Drawing.Pen (Get-Tc 'Borde'), (10 * $k)
        $g.DrawArc($penBg, $rRing, 0, 360)
        if ($script:DxPct -gt 0) {
            $penFg = New-Object Drawing.Pen (Get-Tc 'Acento'), (10 * $k)
            $penFg.StartCap = 'Round'; $penFg.EndCap = 'Round'
            $sweep = [int]([Math]::Min(360, ($script:DxPct * 3.6)))
            $g.DrawArc($penFg, $rRing, -90, $sweep)
            $penFg.Dispose()
        }
        $fPct = New-Object Drawing.Font($script:Fuentes.Display, 21)
        $fSub = New-Object Drawing.Font($script:Fuentes.UI, 9)
        $sf = New-Object Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
        $bTxt = New-Object Drawing.SolidBrush (Get-Tc 'Texto')
        $bSuave = New-Object Drawing.SolidBrush (Get-Tc 'TextoSuave')
        $g.DrawString("$($script:DxPct) %", $fPct, $bTxt, (New-Object Drawing.RectangleF $cx, ($cy + 36 * $k), $d, (44 * $k)), $sf)
        $g.DrawString($script:DxEstado, $fSub, $bSuave, (New-Object Drawing.RectangleF $cx, ($cy + 82 * $k), $d, (26 * $k)), $sf)

        # Textos principales
        $fTit = New-Object Drawing.Font($script:Fuentes.Display, 17)
        $g.DrawString("Diagnóstico $(if ($script:DxModo -eq 'Completo') { 'profundo' } else { 'rápido' }) del sistema", $fTit, $bTxt, (200 * $k), (18 * $k))
        $g.DrawString('Windows, procesador, memoria, discos, batería, drivers, sucesos y seguridad. Solo lee: no cambia nada en el equipo.', $fSub, $bSuave, (202 * $k), (54 * $k))
        foreach ($o in $penBg, $fPct, $fSub, $sf, $bTxt, $bSuave, $fTit) { $o.Dispose() }
    })

    function New-DxBtn($txt, $x, $y, $w, $primario=$false) {
        $b = New-Object BotonPro; $b.Text = $txt
        $b.Size = New-Object Drawing.Size([int]($w * $k), [int](38 * $k))
        $b.Location = New-Object Drawing.Point([int]($x * $k), [int]($y * $k))
        $b.ColorFondo = if ($primario) { Get-Tc 'Acento' } else { Get-Tc 'Tarjeta' }
        $b.ColorTexto = if ($primario) { Get-Tc 'TextoAcento' } else { Get-Tc 'Texto' }
        $b.ColorBorde = if ($primario) { [Drawing.Color]::Transparent } else { Get-Tc 'Borde' }
        $b.Radio = 10
        $b
    }

    $btnModoRap = New-DxBtn 'Rápido (~1 min)' 202 86 155 ($Modo -eq 'Rapido')
    $btnModoCom = New-DxBtn 'Profundo (~10 min)' 366 86 165 ($Modo -eq 'Completo')
    $btnFicha   = New-DxBtn 'Ficha del cliente' 540 86 155 $false

    $btnIniciar = New-DxBtn 'Iniciar diagnóstico' 202 136 175 $true
    $btnGuardar = New-DxBtn 'Abrir informe HTML' 386 136 165 $false
    $btnCopiar  = New-DxBtn 'Copiar resumen' 560 136 150 $false

    $top.Controls.AddRange(@($btnModoRap, $btnModoCom, $btnFicha, $btnIniciar, $btnGuardar, $btnCopiar))

    # Lista de tarjetas de chequeo (sin barra de scroll blanca fea: usamos rueda del ratón suave y barra lateral custom)
    $body = New-Object Windows.Forms.Panel; $body.Dock = 'Fill'; $body.BackColor = Get-Tc 'Fondo'; $body.AutoScroll = $true
    $body.Padding = New-Object Windows.Forms.Padding([int](22 * $k), [int](14 * $k), [int](22 * $k), [int](14 * $k))

    $stDx = New-Object Windows.Forms.StatusStrip; $stDx.BackColor = Get-Tc 'Cab'; $stDx.SizingGrip = $false
    $lblSt = New-Object Windows.Forms.ToolStripStatusLabel; $lblSt.ForeColor = Get-Tc 'TextoSuave'; $lblSt.Text = 'Preparado para analizar el equipo.'
    [void]$stDx.Items.Add($lblSt)

    # Si una prueba sale con aviso o fallo, su fila muestra «Solucionar» con las herramientas del kit que la arreglan
    # o la investigan a fondo. Las claves son los Id del motor; los nombres, los del lanzador (las que no existan no se listan).
    $Soluciones = @{
        sistema         = 'Actualizar Windows', 'Inventario del equipo'
        win11           = 'Actualizar versión de Windows', 'Actualizar Windows'
        cpu             = 'Tareas', 'Monitor recursos', 'Programas de inicio', 'HWMonitor'
        sensores        = 'HWMonitor', 'LibreHardwareMonitor', 'Core Temp', 'Componentes'
        memoria         = 'Gestión de memoria RAM', 'Programas de inicio', 'TestMem5', 'Memoria Windows'
        discos          = 'Analizar espacio en disco', 'Limpiar temporales', 'WizTree', 'CrystalDiskInfo', 'Copia de datos del usuario'
        bateria         = 'Batería', 'Control de energía'
        gpu             = 'Placa de vídeo (GPU)', 'GPU-Z', 'Drivers con fallo'
        dispositivos    = 'Drivers con fallo', 'Dispositivos', 'Actualizar Windows'
        perifericos     = 'Webcam', 'Audio y micrófono', 'Bluetooth', 'Dispositivos'
        red             = 'Reparar red', 'Latencia de red', 'Wi-Fi y claves', 'Test de red'
        eventos         = 'Pantallazos y eventos', 'Restablecer Windows Update', 'Reparar TPM', 'Asesor de BIOS', 'Confiabilidad', 'Visor de eventos', 'TestMem5'
        smart           = 'CrystalDiskInfo', 'SMART detallado', 'Copia de datos del usuario', 'HDDScan'
        integridad      = 'Reparar Windows y Tienda', 'DISM', 'SFC'
        seguridad       = 'Activar seguridad de Windows', 'Restablecer Windows Update', 'Asesor de BIOS', 'KVRT', 'AdwCleaner'
        actualizaciones = 'Actualizar Windows', 'Restablecer Windows Update'
        arranque        = 'Programas de inicio', 'Autoruns', 'Tareas'
        ram_prueba      = 'TestMem5', 'MemTest64', 'Memoria Windows'
        cpu_estres      = 'Prueba de procesador', 'HWMonitor', 'Prime95', 'OCCT'
        disco_vel       = 'CrystalDiskMark', 'CrystalDiskInfo'
        chkdsk          = 'Comprobar disco', 'Reparar Windows y Tienda', 'Copia de datos del usuario'
        sfc             = 'Reparar Windows y Tienda', 'SFC', 'DISM'
    }

    # Estado de la ventana: los manejadores de eventos lo comparten por referencia
    $S = @{ Modo = $Modo; Filas = [ordered]@{}; Res = [ordered]@{}; Ejecutando = $false; Cola = $null; Hecho = 0.0; Total = 0.0; Actual = $null }
    $rutaMotor = Join-Path $PSScriptRoot 'Motor_Diagnostico.ps1'
    $script:UltimoHtmlDx = $null

    $PintarFila = {
        param($s, $e)
        $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'ClearTypeGridFit'; $k = $script:K
        $item = $s.Tag
        $r = New-Object Drawing.Rectangle 1, 1, ($s.ClientSize.Width - 3), ($s.ClientSize.Height - 3)
        $path = [UiHelper]::RoundRect($r, [int](14 * $k))
        $bBg = New-Object Drawing.SolidBrush (Get-Tc 'Tarjeta')
        $colEstado = switch ($item.Nivel) { 'OK' { Get-Tc 'Ok' } 'Aviso' { Get-Tc 'Aviso' } 'Error' { Get-Tc 'Error' } 'Curso' { Get-Tc 'Acento' } 'Info' { Get-Tc 'Tenue' } default { Get-Tc 'Borde' } }
        $pen = New-Object Drawing.Pen $colEstado, $(if ($item.Nivel -in 'Neutro', 'Info') { 1.0 } else { 1.5 })
        $g.FillPath($bBg, $path); $g.DrawPath($pen, $path)

        $rDot = New-Object Drawing.Rectangle ([int](18 * $k)), ([int](16 * $k)), ([int](36 * $k)), ([int](36 * $k))
        $bDot = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(38, $colEstado))
        $g.FillEllipse($bDot, $rDot)
        # Iconos de línea de Segoe MDL2 Assets
        $simbolo = [string][char]$(switch ($item.Nivel) { 'OK' { 0xE73E } 'Aviso' { 0xE7BA } 'Error' { 0xE711 } 'Curso' { 0xE72C } 'Info' { 0xE946 } default { 0x20 } })
        $fSim = New-Object Drawing.Font('Segoe MDL2 Assets', 11)
        $bSim = New-Object Drawing.SolidBrush $colEstado
        $sfC = New-Object Drawing.StringFormat; $sfC.Alignment = 'Center'; $sfC.LineAlignment = 'Center'
        $g.DrawString($simbolo, $fSim, $bSim, [Drawing.RectangleF]$rDot, $sfC)

        $fT = New-Object Drawing.Font($script:Fuentes.Semi, 10.2)
        $fD = New-Object Drawing.Font($script:Fuentes.UI, 8.8)
        $fC = New-Object Drawing.Font($script:Fuentes.UI, 8)
        $bT = New-Object Drawing.SolidBrush (Get-Tc 'Texto')
        $bD = New-Object Drawing.SolidBrush (Get-Tc 'TextoSuave')
        $g.DrawString($item.Tit, $fT, $bT, [single](68 * $k), [single](12 * $k))
        # El resumen va en una sola línea y se recorta con puntos suspensivos; el texto completo sale al pulsar la fila
        $sfD = New-Object Drawing.StringFormat; $sfD.Trimming = 'EllipsisCharacter'; $sfD.FormatFlags = 'NoWrap'
        $g.DrawString([string]$item.Detalle, $fD, $bD, (New-Object Drawing.RectangleF ([single](68 * $k)), ([single](36 * $k)), ([single]($r.Width - 84 * $k)), ([single](22 * $k))), $sfD)
        if (-not $item.Btn.Visible) { $sfR = New-Object Drawing.StringFormat; $sfR.Alignment = 'Far'; $g.DrawString($item.Cat, $fC, $bD, [single]($r.Right - 16 * $k), [single](14 * $k), $sfR); $sfR.Dispose() }
        foreach ($o in $path, $bBg, $pen, $bDot, $fSim, $bSim, $sfC, $fT, $fD, $fC, $bT, $bD, $sfD) { $o.Dispose() }
    }

    # Al pulsar una fila se abre su detalle completo (lo que el motor ha encontrado, línea a línea)
    $VerDetalle = {
        param($item)
        if (-not $item.Largo) { return }
        $d = New-Object Windows.Forms.Form; $d.Text = $item.Tit; $d.Size = New-Object Drawing.Size([int](720 * $script:K), [int](460 * $script:K)); $d.StartPosition = 'CenterParent'
        $d.BackColor = Get-Tc 'Fondo'; $d.MinimizeBox = $false; $d.ShowIcon = $false
        $d.Add_HandleCreated({ [Nit.NativeUx]::SetDarkTitleBar($this.Handle, ($script:TemaActual -eq 'oscuro')) })
        $t = New-Object Windows.Forms.TextBox; $t.Multiline = $true; $t.ReadOnly = $true; $t.ScrollBars = 'Vertical'; $t.Dock = 'Fill'; $t.BorderStyle = 'None'
        $t.BackColor = Get-Tc 'DetalleFondo'; $t.ForeColor = Get-Tc 'DetalleTexto'; $t.Font = New-Object Drawing.Font($script:Fuentes.Mono, 9.5)
        $t.Text = ("{0}`r`n`r`n{1}" -f $item.Detalle, ($item.Largo -replace "(?<!`r)`n", "`r`n")); $t.Select(0, 0)
        $w = New-Object Windows.Forms.Panel; $w.Dock = 'Fill'; $w.Padding = New-Object Windows.Forms.Padding([int](16 * $script:K)); $w.BackColor = Get-Tc 'DetalleFondo'; $w.Controls.Add($t)
        $d.Controls.Add($w); [void]$d.ShowDialog($dx)
    }

    $AjustarAnchos = {
        foreach ($it in $S.Filas.Values) { $it.Pan.Width = $body.ClientSize.Width - [int](44 * $script:K); $it.Btn.Left = $it.Pan.Width - $it.Btn.Width - [int](14 * $script:K); $it.Pan.Invalidate() }
    }

    # Una fila por prueba del motor, según el modo elegido
    $CargarFilas = {
        $k = $script:K
        $body.SuspendLayout(); $body.AutoScrollPosition = New-Object Drawing.Point 0, 0
        foreach ($c in @($body.Controls)) { $body.Controls.Remove($c); $c.Dispose() }
        $S.Filas.Clear(); $S.Res.Clear(); $py = [int](14 * $k)
        foreach ($p in @($script:Pruebas | Where-Object { $S.Modo -eq 'Completo' -or $_.Modo -eq 'Rapido' })) {
            $it = @{ Id = $p.Id; Tit = $p.Nombre; Cat = $p.Grupo; Detalle = 'Pendiente'; Largo = ''; Nivel = 'Neutro'; Seg = [double]$p.Seg }
            $pan = New-Object Windows.Forms.Panel
            $pan.Size = New-Object Drawing.Size(($body.ClientSize.Width - [int](44 * $k)), [int](68 * $k))
            $pan.Location = New-Object Drawing.Point([int](22 * $k), $py)
            $pan.BackColor = Get-Tc 'Fondo'; $pan.Tag = $it
            $pan.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($pan, $true, $null)
            $pan.Add_Paint($PintarFila)
            $pan.Add_Click({ & $VerDetalle $this.Tag })
            $bs = New-Object BotonPro; $bs.Text = 'Solucionar'; $bs.Visible = $false; $bs.Tag = $p.Id
            $bs.Size = New-Object Drawing.Size([int](104 * $k), [int](26 * $k)); $bs.Location = New-Object Drawing.Point(($pan.Width - $bs.Width - [int](14 * $k)), [int](8 * $k))
            $bs.ColorFondo = Get-Tc 'HeroBtn'; $bs.ColorTexto = Get-Tc 'Texto'; $bs.ColorBorde = Get-Tc 'HeroBorde'; $bs.Radio = 12
            $bs.Add_Click({
                $menu = New-Object Windows.Forms.ContextMenuStrip
                foreach ($nombre in $Soluciones[[string]$this.Tag]) {
                    $h = $Herramientas | Where-Object { $_.N -eq $nombre } | Select-Object -First 1
                    if (-not $h) { continue }
                    $mi = $menu.Items.Add($nombre); $mi.Tag = $h; $mi.ToolTipText = [string]$h.D
                    $mi.Add_Click({ Start-Herramienta $this.Tag $null })
                }
                if ($menu.Items.Count) { $menu.Show($this, 0, $this.Height) }
            })
            $pan.Controls.Add($bs); $it.Pan = $pan; $it.Btn = $bs; $S.Filas[$p.Id] = $it
            $body.Controls.Add($pan); $py += [int](78 * $k)
        }
        $body.ResumeLayout()
        $script:DxPct = 0; $script:DxEstado = 'Listo'; $top.Invalidate()
        $lblSt.Text = "$($S.Filas.Count) pruebas preparadas. Ninguna modifica el equipo."
    }

    $GenerarInforme = {
        try {
            New-Item -ItemType Directory -Path $dirInformes -Force | Out-Null
            $outF = Join-Path $dirInformes ("Diagnostico_{0}_{1}.html" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmm'))
            $enc = { param($t) [Net.WebUtility]::HtmlEncode([string]$t) }
            $sig = { param($id) @($Soluciones[$id] | Where-Object { $n = $_; $Herramientas | Where-Object { $_.N -eq $n } }) -join ' · ' }
            $filasHtml = ($S.Res.Values | ForEach-Object {
                $paso = if ($_.Estado -in 'Aviso', 'Fallo') { & $sig $_.Id } else { '' }
                $colB = switch ($_.Estado) { 'OK' { '#16a34a' } 'Aviso' { '#b45309' } 'Fallo' { '#dc2626' } default { '#525252' } }
                "<tr><td><b>$(& $enc $_.Nombre)</b></td><td><span style='color:$colB;font-weight:600;'>$(& $enc $_.Estado)</span></td><td>$(& $enc $_.Resumen)$(if ($_.Detalle -and $_.Estado -in 'Aviso', 'Fallo') { "<pre>$(& $enc $_.Detalle)</pre>" })$(if ($paso) { "<div style='margin-top:6px;font-size:12px;color:#0369a1;'><b>Siguiente paso:</b> $(& $enc $paso)</div>" })</td></tr>"
            }) -join "`n"
            $bloqueCliente = if ($script:FichaCliente.Cliente -or $script:FichaCliente.Motivo) {
                "<div class='card'><h2>Ficha del cliente</h2><p><b>Cliente:</b> $(& $enc $script:FichaCliente.Cliente) · <b>Contacto:</b> $(& $enc $script:FichaCliente.Telefono)</p><p><b>Motivo:</b> $(& $enc $script:FichaCliente.Motivo)</p><p><b>Notas:</b> $(& $enc $script:FichaCliente.Notas)</p></div>"
            } else { '' }
            $htmlDx = @"
<!doctype html><html lang='es'><head><meta charset='utf-8'><title>Diagnóstico $env:COMPUTERNAME</title>
<style>body{font-family:'Segoe UI',sans-serif;background:#fafafa;color:#171717;margin:0}.wrap{max-width:980px;margin:24px auto;padding:0 24px}h1{font-size:22px;font-weight:600;margin:0 0 4px}h2{font-size:14px;font-weight:600;margin:0 0 8px}.sub{color:#525252;font-size:13px;margin:0 0 20px}.card{background:#fff;border:1px solid #e4e4e7;border-radius:12px;padding:20px;margin-bottom:16px}table{width:100%;border-collapse:collapse;font-size:13px}th,td{text-align:left;padding:8px 12px 8px 0;border-bottom:1px solid #e4e4e7;vertical-align:top}th{color:#525252;font-weight:600}pre{font-family:'Cascadia Mono',Consolas,monospace;font-size:12px;color:#525252;white-space:pre-wrap;margin:6px 0 0}</style></head>
<body><div class='wrap'><h1>Diagnóstico del equipo $env:COMPUTERNAME</h1><p class='sub'>$(Get-Date -Format 'dd/MM/yyyy HH:mm') · modo $(if ($S.Modo -eq 'Completo') { 'profundo' } else { 'rápido' })</p>
$bloqueCliente<div class='card'><table><thead><tr><th>Prueba</th><th>Estado</th><th>Resultado</th></tr></thead><tbody>$filasHtml</tbody></table></div></div></body></html>
"@
            [IO.File]::WriteAllText($outF, $htmlDx, (New-Object Text.UTF8Encoding($true)))
            $script:UltimoHtmlDx = $outF
        } catch { }
    }

    $Terminar = {
        param([bool]$cancelado)
        $S.Timer.Stop(); $S.Ejecutando = $false
        try { $S.Ps.Dispose(); $S.Rs.Dispose() } catch { }
        $btnIniciar.Text = 'Iniciar diagnóstico'; $btnIniciar.Invalidate()
        foreach ($it in $S.Filas.Values) { if ($it.Nivel -eq 'Curso') { $it.Nivel = 'Neutro'; $it.Detalle = 'Detenida'; $it.Pan.Invalidate() } }
        $seg = [int]((Get-Date) - $S.Inicio).TotalSeconds
        $nF = @($S.Res.Values | Where-Object { $_.Estado -eq 'Fallo' }).Count; $nA = @($S.Res.Values | Where-Object { $_.Estado -eq 'Aviso' }).Count
        if ($cancelado) { $script:DxEstado = 'Detenido'; $top.Invalidate(); $lblSt.Text = "Detenido a los $seg s. $($S.Res.Count) de $($S.Filas.Count) pruebas hechas; no se guarda en el historial."; return }
        $cmpTxt = 'No se pudo guardar en el historial'
        try {
            $rutaH = Save-Historial $S.Res $S.Modo $script:FichaCliente $seg
            if ($rutaH) { $ant = Get-HistorialAnterior $rutaH; $cmpTxt = if ($ant) { (Get-Comparacion $S.Res $ant).Resumen } else { 'Primer diagnóstico guardado de este equipo' } }
        } catch { }
        & $GenerarInforme
        $script:DxPct = 100; $script:DxEstado = if ($nF) { "$nF fallo(s)" } elseif ($nA) { "$nA aviso(s)" } else { 'Todo correcto' }; $top.Invalidate()
        $lblSt.Text = "Terminado en $seg s · $nF fallo(s), $nA aviso(s) · $cmpTxt. Pulsa una fila para ver su detalle."
        # Se salta al primer problema para que se vea sin buscar
        $primero = $S.Filas.Values | Where-Object { $_.Nivel -in 'Error', 'Aviso' } | Select-Object -First 1
        if ($primero) { $body.ScrollControlIntoView($primero.Pan) }
    }

    $S.Timer = New-Object Windows.Forms.Timer; $S.Timer.Interval = 150
    $S.Timer.Add_Tick({
        $m = $null
        while ($S.Cola -and $S.Cola.TryDequeue([ref]$m)) {
            if ($m.Tipo -eq 'Inicio') {
                $it = $S.Filas[$m.Id]; $it.Nivel = 'Curso'; $it.Detalle = 'Comprobando…'; $it.Btn.Visible = $false; $it.Pan.Invalidate(); $body.ScrollControlIntoView($it.Pan)
                $S.Actual = $it; $S.TActual = Get-Date; $lblSt.Text = "Comprobando: $($it.Tit)…"
            } elseif ($m.Tipo -eq 'Fin') {
                $it = $S.Filas[$m.Id]
                $it.Nivel = switch ([string]$m.Estado) { 'OK' { 'OK' } 'Aviso' { 'Aviso' } 'Fallo' { 'Error' } default { 'Info' } }
                $it.Detalle = [string]$m.Resumen; $it.Largo = [string]$m.Detalle; $it.Btn.Visible = ($m.Estado -in 'Aviso', 'Fallo')
                $it.Pan.Cursor = $(if ($it.Largo) { 'Hand' } else { 'Default' }); $it.Pan.Invalidate()
                $S.Res[$m.Id] = @{ Id = [string]$m.Id; Nombre = $it.Tit; Estado = [string]$m.Estado; Resumen = [string]$m.Resumen; Detalle = [string]$m.Detalle; Metricas = $m.Metricas }
                $S.Hecho += $it.Seg; $S.Actual = $null
            } elseif ($m.Tipo -eq 'Terminado') { & $Terminar $false; return }
            elseif ($m.Tipo -eq 'Cancelado') { & $Terminar $true; return }
        }
        if ($S.Ejecutando -and $S.Total -gt 0) {
            $parcial = 0; if ($S.Actual) { $parcial = [Math]::Min(((Get-Date) - $S.TActual).TotalSeconds, $S.Actual.Seg * 0.9) }
            $script:DxPct = [Math]::Min(99, [int](($S.Hecho + $parcial) / $S.Total * 100)); $script:DxEstado = 'Analizando…'; $top.Invalidate()
        }
    })

    $Detener = {
        $S.Ctl.Cancelar = $true
        try { [void]$S.Ps.BeginStop($null, $null) } catch { }
        Get-Process sfc, powercfg -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        & $Terminar $true
    }

    # Las pruebas corren en un hilo aparte (la ventana no se queda congelada) y dejan sus resultados en una cola
    $Iniciar = {
        if ($S.Ejecutando) { & $Detener; return }
        if (-not (Test-Path -LiteralPath $rutaMotor)) { [void][Windows.Forms.MessageBox]::Show('Falta Scripts\Motor_Diagnostico.ps1.', 'Diagnóstico', 0, 16); return }
        & $CargarFilas
        $S.Total = [double](($S.Filas.Values | ForEach-Object { $_.Seg } | Measure-Object -Sum).Sum); $S.Hecho = 0.0; $S.Actual = $null; $S.Inicio = Get-Date
        $S.Cola = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
        $S.Ctl = [hashtable]::Synchronized(@{ Cancelar = $false })
        $S.Rs = [runspacefactory]::CreateRunspace(); $S.Rs.ApartmentState = 'STA'; $S.Rs.Open()
        $S.Ps = [powershell]::Create(); $S.Ps.Runspace = $S.Rs
        [void]$S.Ps.AddScript('param($motor,$modo,$cola,$ctl) Set-Location $env:TEMP; . $motor; Start-Diagnostico -Modo $modo -Cola $cola -Ctl $ctl').AddArgument($rutaMotor).AddArgument($S.Modo).AddArgument($S.Cola).AddArgument($S.Ctl)
        $S.Ejecutando = $true; $btnIniciar.Text = 'Detener'; $btnIniciar.Invalidate()
        [void]$S.Ps.BeginInvoke(); $S.Timer.Start()
    }

    $MarcarModo = {
        $script:DxModo = $S.Modo
        foreach ($par in @(@($btnModoRap, 'Rapido'), @($btnModoCom, 'Completo'))) {
            $sel = ($S.Modo -eq $par[1]); $par[0].ColorFondo = Get-Tc $(if ($sel) { 'Acento' } else { 'Tarjeta' }); $par[0].ColorTexto = Get-Tc $(if ($sel) { 'TextoAcento' } else { 'Texto' }); $par[0].Invalidate()
        }
        $top.Invalidate()
    }
    $btnModoRap.Add_Click({ if ($S.Ejecutando) { return }; $S.Modo = 'Rapido'; & $MarcarModo; & $CargarFilas })
    $btnModoCom.Add_Click({ if ($S.Ejecutando) { return }; $S.Modo = 'Completo'; & $MarcarModo; & $CargarFilas })
    $btnFicha.Add_Click({ Show-FichaCliente })
    $btnIniciar.Add_Click({ & $Iniciar })
    $btnGuardar.Add_Click({ if ($script:UltimoHtmlDx -and (Test-Path -LiteralPath $script:UltimoHtmlDx)) { Start-Process explorer.exe -ArgumentList "`"$($script:UltimoHtmlDx)`"" } else { $lblSt.Text = 'Todavía no hay informe: pasa primero el diagnóstico.' } })
    $btnCopiar.Add_Click({
        $t = New-Object Text.StringBuilder
        [void]$t.AppendLine("DIAGNÓSTICO $env:COMPUTERNAME - $(Get-Date -Format 'dd/MM/yyyy HH:mm')")
        foreach ($r in $S.Res.Values) { [void]$t.AppendLine(("[{0}] {1}: {2}" -f $r.Estado.ToUpper(), $r.Nombre, $r.Resumen)) }
        try { [Windows.Forms.Clipboard]::SetText($t.ToString()); $lblSt.Text = 'Resumen copiado al portapapeles.' } catch { }
    })

    $body.Add_Resize({ & $AjustarAnchos })
    $dx.Controls.AddRange(@($body, $stDx, $top))
    $dx.Add_FormClosing({
        param($origen, $ev)
        if ($S.Ejecutando) {
            if ([Windows.Forms.MessageBox]::Show('Hay un diagnóstico en curso. ¿Detenerlo y cerrar?', 'Diagnóstico', 'YesNo', 'Question') -ne 'Yes') { $ev.Cancel = $true; return }
            & $Detener
        }
        $S.Timer.Stop()
    })
    $dx.Add_Shown({ & $CargarFilas; if ($AutoStart) { & $Iniciar } })
    [void]$dx.ShowDialog()
}
