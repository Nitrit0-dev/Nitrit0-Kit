# =====================================================================
#  Ventana_Equilibrio.ps1 - Analizador de Cuellos de Botella Fluent UI v5.0
#  Explica y mide con claridad qué pieza frena al ordenador (CPU vs GPU vs
#  RAM en Single/Dual Channel vs Velocidad de Disco) y monitoriza en vivo.
# =====================================================================

function Show-Equilibrio([string]$Vista = 'Config') {
    $k = $script:K
    $eq = New-Object Windows.Forms.Form
    $eq.Text = 'Cuello de botella'
    $eq.Size = New-Object Drawing.Size([int](960 * $k), [int](660 * $k))
    $eq.StartPosition = 'CenterParent'
    $eq.BackColor = Get-Tc 'Fondo'; $eq.ForeColor = Get-Tc 'Texto'
    $eq.Font = New-Object Drawing.Font($script:Fuentes.UI, 9.5)
    if ($bmpLogo) { try { $eq.Icon = [Drawing.Icon]::FromHandle($bmpLogo.GetHicon()) } catch { } }
    $eq.Add_HandleCreated({ [Nit.NativeUx]::SetDarkTitleBar($eq.Handle, ($script:TemaActual -eq 'oscuro')) })

    # Recopilar datos reales de las 4 piezas clave
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $gpus = @(Get-CimInstance Win32_VideoController)
    $gpu = $gpus | Sort-Object AdapterRAM -Descending | Select-Object -First 1
    $modsRam = @(Get-CimInstance Win32_PhysicalMemory)
    $os = Get-CimInstance Win32_OperatingSystem
    $ramGb = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $dualChannel = ($modsRam.Count -ge 2)
    $ramMhz = ($modsRam | Select-Object -First 1).Speed
    # El disco principal es el que contiene Windows, no el primero de la lista (que puede ser el pendrive del kit)
    $dks = @(Get-PhysicalDisk)
    $dkPrincipal = $null
    try { $nd = (Get-Partition -DriveLetter $env:SystemDrive.TrimEnd(':') -ErrorAction Stop).DiskNumber; $dkPrincipal = $dks | Where-Object { [string]$_.DeviceId -eq [string]$nd } | Select-Object -First 1 } catch { }
    if (-not $dkPrincipal) { $dkPrincipal = $dks | Where-Object { $_.BusType -ne 'USB' } | Select-Object -First 1 }
    if (-not $dkPrincipal) { $dkPrincipal = $dks | Select-Object -First 1 }
    $tipoDisco = switch ($dkPrincipal.MediaType) { 'SSD' { if ($dkPrincipal.BusType -eq 'NVMe') { 'SSD NVMe' } else { 'SSD' } } 'HDD' { 'Disco mecánico (HDD)' } default { 'Tipo no identificado' } }

    # Calcular puntuaciones de equilibrio (0 - 100) y detectar cuellos de botella
    $scoreCpu = [Math]::Min(100, [int]($cpu.NumberOfLogicalProcessors * 7 + 25))
    $vramGb = [math]::Round($gpu.AdapterRAM / 1GB, 1)
    $esIntegrada = ($gpu.Name -match 'UHD|Iris|Vega|Radeon\(TM\) Graphics|Intel\(R\) HD')
    $scoreGpu = if ($esIntegrada) { 45 } else { [Math]::Min(100, [int](55 + $vramGb * 6)) }
    $scoreRam = if ($ramGb -lt 8) { 35 } elseif (-not $dualChannel) { 62 } elseif ($ramGb -ge 16) { 95 } else { 80 }
    $scoreDisk = switch ($dkPrincipal.MediaType) { 'SSD' { 92 } 'HDD' { 28 } default { 60 } }

    # Determinar veredicto de cuello de botella en lenguaje claro
    $cuellos = @()
    if ($dkPrincipal.MediaType -eq 'HDD') {
        $cuellos += "CRÍTICO (DISCO MECÁNICO HDD): El disco principal es un HDD tradicional. Frena el arranque, la apertura de programas y todo el procesador. Sustituir por un SSD NVMe multiplicará por 5 la agilidad."
    }
    if (-not $dualChannel -and $modsRam.Count -eq 1) {
        $cuellos += "CUELLO DE BOTELLA EN RAM (SINGLE CHANNEL): Solo tienes 1 módulo de memoria instalado ($ramGb GB). Añadir un segundo módulo igual activará el Doble Canal (Dual Channel) y dará hasta un +25% de rendimiento a la CPU y gráfica."
    }
    if ($ramGb -lt 8) {
        $cuellos += "MEMORIA RAM INSUFICIENTE ($ramGb GB): Windows 11 necesita mínimo 8 GB (recomendado 16 GB) para no usar el disco como memoria virtual lenta."
    }
    if ($esIntegrada -and $scoreCpu -ge 75) {
        $cuellos += "GRÁFICA INTEGRADA ($($gpu.Name)): Tienes un procesador muy potente ($($cpu.NumberOfCores) núcleos), pero una gráfica integrada pensada para ofimática. En juegos o edición 3D la gráfica hará cuello de botella al 100%."
    }
    if ($cuellos.Count -eq 0) {
        $cuellos += "EQUIPO BIEN EQUILIBRADO: Procesador, Memoria RAM en doble canal, Gráfica y disco están compensados: no se ve ningún cuello de botella en las características."
    }

    $top = New-Object Windows.Forms.Panel; $top.Dock = 'Top'; $top.Height = [int](155 * $k); $top.BackColor = Get-Tc 'Cab'
    $top.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($top, $true, $null)
    $top.Add_Paint({
        param($s, $e)
        $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'ClearTypeGridFit'; $k = $script:K
        $fTit = New-Object Drawing.Font($script:Fuentes.Display, 16.5)
        $fSub = New-Object Drawing.Font($script:Fuentes.UI, 9.5)
        $fVer = New-Object Drawing.Font($script:Fuentes.Semi, 9.8)
        $bTxt = New-Object Drawing.SolidBrush (Get-Tc 'Texto')
        $bSuave = New-Object Drawing.SolidBrush (Get-Tc 'TextoSuave')
        $g.DrawString('Analizador de Cuello de Botella (CPU · GPU · RAM · Disco)', $fTit, $bTxt, (24 * $k), (16 * $k))
        $g.DrawString('Compara las características de las cuatro piezas clave. Es una lectura rápida de lo instalado, no una prueba de rendimiento.', $fSub, $bSuave, (24 * $k), (50 * $k))

        $rBox = New-Object Drawing.Rectangle ([int](24 * $k)), ([int](82 * $k)), ($s.ClientSize.Width - [int](48 * $k)), ([int](56 * $k))
        $pBox = [UiHelper]::RoundRect($rBox, [int](12 * $k))
        $colAlerta = if ($cuellos[0] -match '^EQUIPO BIEN') { Get-Tc 'Ok' } else { Get-Tc 'Aviso' }
        $bBox = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(30, $colAlerta))
        $penBox = New-Object Drawing.Pen $colAlerta, 1.4
        $g.FillPath($bBox, $pBox); $g.DrawPath($penBox, $pBox)
        $bVer = New-Object Drawing.SolidBrush $colAlerta
        $g.DrawString($cuellos[0], $fVer, $bVer, (New-Object Drawing.RectangleF (38 * $k), (91 * $k), ($rBox.Width - 28 * $k), (42 * $k)))
        foreach ($o in $fTit, $fSub, $fVer, $bTxt, $bSuave, $pBox, $bBox, $penBox, $bVer) { $o.Dispose() }
    })

    $body = New-Object Windows.Forms.Panel; $body.Dock = 'Fill'; $body.BackColor = Get-Tc 'Fondo'; $body.Padding = New-Object Windows.Forms.Padding([int](24 * $k))

    $Piezas = @(
        @{ Nombre='PROCESADOR (CPU)'; Modelo=$cpu.Name.Trim(); Detalle="$($cpu.NumberOfCores) núcleos físicos / $($cpu.NumberOfLogicalProcessors) hilos lógicos · Máx $($cpu.MaxClockSpeed) MHz"; Score=$scoreCpu; Vivo=0 }
        @{ Nombre='TARJETA GRÁFICA (GPU)'; Modelo=$gpu.Name; Detalle="VRAM detectada: $(if ($vramGb -gt 0) {"$vramGb GB"} else {'Compartida'}) · Tipo: $(if ($esIntegrada) {'Integrada (Ofimática/Multimedia)'} else {'Dedicada'})"; Score=$scoreGpu; Vivo=0 }
        @{ Nombre='MEMORIA RAM Y CANALES'; Modelo="$ramGb GB DDR ($ramMhz MHz)"; Detalle="Configuración instalada: $($modsRam.Count) módulo(s) · $(if ($dualChannel) {'Dos o más módulos (doble canal probable)'} else {'Canal Simple (Single Channel - Frena a la CPU)'})"; Score=$scoreRam; Vivo=0 }
        @{ Nombre='DISCO PRINCIPAL'; Modelo=$dkPrincipal.FriendlyName; Detalle="$tipoDisco · $([math]::Round($dkPrincipal.Size / 1GB)) GB · Estado: $(if ($dkPrincipal.HealthStatus -eq 'Healthy') { 'Correcto' } else { $dkPrincipal.HealthStatus })"; Score=$scoreDisk; Vivo=0 }
    )

    $panelesPieza = @()
    $yP = [int](14 * $k)
    foreach ($pz in $Piezas) {
        $pan = New-Object Windows.Forms.Panel
        $pan.Size = New-Object Drawing.Size(($eq.ClientSize.Width - [int](64 * $k)), [int](96 * $k))
        $pan.Location = New-Object Drawing.Point([int](24 * $k), $yP)
        $pan.Tag = $pz
        $pan.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($pan, $true, $null)
        $pan.Add_Paint({
            param($s, $e)
            $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'ClearTypeGridFit'; $k = $script:K
            $it = $s.Tag
            $r = New-Object Drawing.Rectangle 1, 1, ($s.ClientSize.Width - 3), ($s.ClientSize.Height - 3)
            $p = [UiHelper]::RoundRect($r, [int](14 * $k))
            $bBg = New-Object Drawing.SolidBrush (Get-Tc 'Tarjeta')
            $colBar = if ($it.Score -ge 75) { Get-Tc 'Ok' } elseif ($it.Score -ge 55) { Get-Tc 'Acento' } else { Get-Tc 'Aviso' }
            $pen = New-Object Drawing.Pen (Get-Tc 'Borde'), 1.1
            $g.FillPath($bBg, $p); $g.DrawPath($pen, $p)

            $fCat = New-Object Drawing.Font($script:Fuentes.Semi, 8.2)
            $fMod = New-Object Drawing.Font($script:Fuentes.Semi, 11)
            $fDet = New-Object Drawing.Font($script:Fuentes.UI, 9)
            $bAc  = New-Object Drawing.SolidBrush $colBar
            $bTx  = New-Object Drawing.SolidBrush (Get-Tc 'Texto')
            $bSv  = New-Object Drawing.SolidBrush (Get-Tc 'TextoSuave')

            $g.DrawString($it.Nombre, $fCat, $bAc, (20 * $k), (11 * $k))
            $g.DrawString($it.Modelo, $fMod, $bTx, (20 * $k), (28 * $k))
            $g.DrawString($it.Detalle, $fDet, $bSv, (20 * $k), (53 * $k))

            # Barra de nivel a la derecha
            $bw = [int](210 * $k); $bh = [int](10 * $k); $bx = $r.Right - $bw - [int](24 * $k); $by = [int](68 * $k)
            $rBarBg = New-Object Drawing.Rectangle $bx, $by, $bw, $bh
            $bBarBg = New-Object Drawing.SolidBrush (Get-Tc 'Fondo')
            $g.FillRectangle($bBarBg, $rBarBg)
            $wFill = [int](($bw * $it.Score) / 100)
            if ($wFill -gt 0) {
                $rBarFg = New-Object Drawing.Rectangle $bx, $by, $wFill, $bh
                $g.FillRectangle($bAc, $rBarFg)
            }
            $sfR = New-Object Drawing.StringFormat; $sfR.Alignment = 'Far'
            $g.DrawString("Índice de equilibrio: $($it.Score)/100", $fCat, $bTx, ($r.Right - 24 * $k), (46 * $k), $sfR)

            foreach ($o in $p, $bBg, $pen, $fCat, $fMod, $fDet, $bAc, $bTx, $bSv, $bBarBg, $sfR) { $o.Dispose() }
        })
        $body.Controls.Add($pan)
        $panelesPieza += $pan
        $yP += [int](108 * $k)
    }

    # El ancho de las tarjetas sigue al de la ventana (antes se cortaban por la derecha en pantallas pequeñas)
    $body.Add_Resize({ foreach ($pp in $panelesPieza) { $pp.Width = $body.ClientSize.Width - [int](48 * $script:K); $pp.Invalidate() } })
    $eq.Controls.AddRange(@($body, $top))
    [void]$eq.ShowDialog()
}
