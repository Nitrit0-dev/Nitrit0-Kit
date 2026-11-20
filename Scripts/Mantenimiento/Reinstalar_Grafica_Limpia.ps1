# =====================================================================
#  Reinstalar_Grafica_Limpia.ps1 - Reinstalación limpia del driver de la gráfica (Nitrit0)
#  Para pantallazos, parpadeos, artefactos, bajo rendimiento o un driver corrupto (NVIDIA, AMD/Radeon e Intel).
#  Panel guiado en 5 pasos: copia de seguridad del driver actual, conseguir el driver nuevo, limpiar con DDU
#  (Display Driver Uninstaller) e instalar el nuevo. DDU no se abre hasta tener copia hecha y driver nuevo a mano
#  (instalador guardado o Internet para bajarlo), para no dejar el equipo con la resolución básica de Microsoft.
#  No cambia nada por sí solo: cada paso lo pulsa el técnico. El panel se puede volver a abrir después del
#  reinicio de DDU: detecta que la gráfica quedó sin driver y recomienda el paso 5.
#  Parámetro: -SinPreguntas (solo muestra la gráfica detectada y qué herramientas hay; no abre ventanas ni cambia nada)
# =====================================================================
[CmdletBinding()]
param([switch]$SinPreguntas)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

# ---------------------------------------------------------------------
#  Utilidades
# ---------------------------------------------------------------------
function Say([string]$t, [string]$nivel = 'INFO') { Write-Host $t; Write-Log (($t -replace '^\s+', '')) $nivel }

# El driver de NVIDIA se publica como 551.23, pero Windows lo guarda como 31.0.15.5123: se toman las 5 últimas cifras
function Format-VersionGpu([string]$marca, [string]$ver) {
    if ($marca -eq 'NVIDIA' -and $ver -match '^\d+\.\d+\.\d+\.\d+$') { $d = $ver -replace '\.', ''; if ($d.Length -ge 5) { $d = $d.Substring($d.Length - 5); return "$($d.Substring(0, 3)).$($d.Substring(3))" } }
    $ver
}

function Get-Gpus {
    $firmados = @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue | Where-Object { $_.DeviceClass -eq 'DISPLAY' })
    $res = @()
    foreach ($v in @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)) {
        if ($v.Name -match 'Virtual|Remote|Hyper-V|Parsec|Citrix|VMware|DisplayLink|Indirect|Miracast|spacedesk') { continue }
        $marca = if ($v.PNPDeviceID -match 'VEN_10DE') { 'NVIDIA' } elseif ($v.PNPDeviceID -match 'VEN_1002') { 'AMD' } elseif ($v.PNPDeviceID -match 'VEN_8086') { 'Intel' } else { '' }
        $fw = $firmados | Where-Object { $_.DeviceID -eq $v.PNPDeviceID } | Select-Object -First 1
        $basico = ($v.Name -match 'Basic Display|Básico de pantalla') -or ($fw -and $fw.DriverProviderName -match 'Microsoft')
        if (-not $marca -and -not $basico) { continue }
        $res += [pscustomobject]@{
            Nombre = [string]$v.Name; Marca = $marca; Basico = [bool]$basico
            Version = $(if ($fw) { Format-VersionGpu $marca ([string]$fw.DriverVersion) } else { [string]$v.DriverVersion })
            Fecha = $(if ($fw -and $fw.DriverDate) { $fw.DriverDate.ToString('dd/MM/yyyy') } else { 's/f' })
            Inf = $(if ($fw) { [string]$fw.InfName } else { '' })
        }
    }
    $res
}
function Get-TextoGpus($gpus) {
    if (-not $gpus.Count) { return 'No se ha detectado ninguna gráfica (solo el adaptador virtual o ninguna).' }
    (($gpus | ForEach-Object {
            if ($_.Basico) { "$($_.Nombre)`r`n    SIN driver del fabricante: Windows usa el controlador básico (por eso la resolución es baja)." }
            else { "$($_.Nombre)`r`n    Driver $($_.Version)  ·  $($_.Fecha)" }
        }) -join "`r`n")
}
# Solo se ejecuta lo que venga firmado por quien debe: una descarga cortada o manipulada no se abre
function Test-Firma([string]$Ruta, [string]$Patron) {
    try { $s = Get-AuthenticodeSignature -LiteralPath $Ruta -ErrorAction Stop; ($s.Status -eq 'Valid') -and ($s.SignerCertificate.Subject -match $Patron) } catch { $false }
}

$ddu = Resolve-ExeKit 'GPU\DDU\DDU v*\Display Driver Uninstaller.exe'
$nvc = Resolve-ExeKit 'GPU\NVCleanstall*.exe'
$tieneDdu = (Test-Path -LiteralPath $ddu) -and (Test-Firma $ddu 'Wagnardsoft')
$tieneNvc = (Test-Path -LiteralPath $nvc) -and (Test-Firma $nvc 'TechPowerUp')
$gpus = @(Get-Gpus)

# ---------------------------------------------------------------------
#  Sin preguntas: solo informa
# ---------------------------------------------------------------------
if ($SinPreguntas) {
    Write-Output "========================================================"
    Write-Output "  $($E.Lupa) GRÁFICA: REINSTALACIÓN LIMPIA (solo consulta)"
    Write-Output "========================================================"
    foreach ($g in $gpus) { Write-Output "  $($E.Info) $($g.Nombre)  ·  $(if ($g.Basico) { 'sin driver del fabricante' } else { "driver $($g.Version) ($($g.Fecha))" })" }
    if (-not $gpus.Count) { Write-Output "  $($E.Aviso) No se ha detectado ninguna gráfica." }
    Write-Output "  $(if ($tieneDdu) { $E.OK } else { $E.Aviso }) DDU: $(if ($tieneDdu) { 'presente y con firma de Wagnardsoft' } else { 'no está en Apps\GPU\DDU o su firma no es válida' })"
    Write-Output "  $(if ($tieneNvc) { $E.OK } else { $E.Aviso }) NVCleanstall: $(if ($tieneNvc) { 'presente y con firma de TechPowerUp' } else { 'no está en Apps\GPU o su firma no es válida' })"
    Write-Output "  $(if (Test-Internet) { $E.OK } else { $E.Aviso }) Internet: $(if (Test-Internet) { 'disponible' } else { 'sin conexión' })"
    Write-Output "  $($E.Info) Sin preguntas no se abre el panel ni se cambia nada."
    Write-Log "Gráfica limpia (consulta): $(($gpus | ForEach-Object { "$($_.Marca) $($_.Version)" }) -join '; ')"
    exit 0
}
if (-not $tieneDdu) {
    Write-Output "  $($E.Error) Falta DDU (Display Driver Uninstaller) en Apps\GPU\DDU o su firma digital no es válida: sin él no se puede hacer la limpieza."
    Write-Log 'Gráfica limpia: DDU no disponible' 'ERROR'; exit 1
}

# ---------------------------------------------------------------------
#  Panel
# ---------------------------------------------------------------------
$script:CopiaHecha = $false; $script:Instalador = $null; $script:Acciones = New-Object Collections.Generic.List[string]
$marcas = @($gpus | Where-Object { $_.Marca } | ForEach-Object { $_.Marca } | Select-Object -Unique)
if (-not $marcas.Count) { $marcas = @('NVIDIA', 'AMD', 'Intel') }
$marcaIni = if ($marcas -contains 'NVIDIA') { 'NVIDIA' } elseif ($marcas -contains 'AMD') { 'AMD' } else { $marcas[0] }

$f = New-Object Windows.Forms.Form; $f.Text = 'Reinstalar gráfica (limpio)'; $f.ClientSize = New-Object Drawing.Size(660, 644); $f.StartPosition = 'CenterScreen'
$f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false; $f.Font = New-Object Drawing.Font('Segoe UI', 9.5)
$l1 = New-Object Windows.Forms.Label; $l1.Text = 'Gráfica detectada:'; $l1.AutoSize = $true; $l1.Location = New-Object Drawing.Point(18, 14); $f.Controls.Add($l1)
$lGpu = New-Object Windows.Forms.Label; $lGpu.Location = New-Object Drawing.Point(18, 38); $lGpu.Size = New-Object Drawing.Size(624, 78); $lGpu.Text = (Get-TextoGpus $gpus); $lGpu.BackColor = [Drawing.Color]::FromArgb(238, 238, 238); $lGpu.Padding = New-Object Windows.Forms.Padding(8, 6, 8, 6); $f.Controls.Add($lGpu)
$l2 = New-Object Windows.Forms.Label; $l2.Text = 'Fabricante a limpiar:'; $l2.AutoSize = $true; $l2.Location = New-Object Drawing.Point(18, 130); $f.Controls.Add($l2)
$cb = New-Object Windows.Forms.ComboBox; $cb.DropDownStyle = 'DropDownList'; $cb.Location = New-Object Drawing.Point(160, 126); $cb.Size = New-Object Drawing.Size(140, 28)
[void]$cb.Items.AddRange($marcas); $cb.SelectedItem = $marcaIni; $f.Controls.Add($cb)

# Croquis de las opciones de DDU (ventana «Opciones»). Los textos son los de DDU 18.1.x en español; el criterio de cada casilla es el recomendado para un equipo de cliente
function Show-OpcionesDdu([string]$marca) {
    $filas = @(
        @('General', 'Eliminar los monitores visibles y ocultos', 'MARCAR', 'Quita restos de pantallas antiguas (en 18.1.6.2 también reinicia la escala guardada).'),
        @('General', 'Guardar archivos de registro en la ruta de arranque', 'MARCAR', 'Deja constancia de lo que se borró, útil si algo falla.'),
        @('General', 'Crear un punto de restauración de sistema', 'MARCAR', 'Redundante con el paso 1, pero inofensivo.'),
        @('General', 'Guardar el archivo de configuración en la carpeta «roaming»', 'DESMARCAR', 'No dejar ajustes de DDU en el perfil del cliente.'),
        @('General', 'Buscar actualizaciones automáticamente al iniciar DDU', 'DESMARCAR', 'La versión la controla el kit: evita avisos y descargas en un equipo ajeno.'),
        @('General', 'Eliminar librerías Vulkan', 'MARCAR', 'Parte de la limpieza completa; el driver nuevo las trae.'),
        @('General', 'Mostrar ofertas de nuestros socios', 'DESMARCAR', 'Publicidad.'),
        @('General', 'Remember last selected GPU', 'DESMARCAR', 'Mejor elegir la gráfica cada vez.'),
        @('NVIDIA', 'Eliminar las carpetas de controladores «C:\NVIDIA»', 'DESMARCAR', 'DDU la marca «NO recomendado». Solo si el instalador falla por restos.'),
        @('NVIDIA', 'Eliminar PhysX', 'DESMARCAR', 'Lo necesitan juegos antiguos.'),
        @('NVIDIA', 'Eliminar 3DTV Play', 'MARCAR', 'Obsoleto: no afecta a nada.'),
        @('NVIDIA', "Eliminar 'GeForce Experience' (GFE)", 'SEGÚN CASO', 'Márcala si el driver nuevo se instala sin GFE (NVCleanstall); no si el cliente lo usa.'),
        @('NVIDIA', 'Remove NVIDIA Broadcast', 'DESMARCAR', 'Es una app del cliente (RTX): solo si da problemas.'),
        @('NVIDIA', '(DCH driver) Remove the NVIDIA Control Panel installed from the Microsoft Store', 'MARCAR', 'Limpieza completa. Luego comprueba que vuelve el Panel de control de NVIDIA (si falta, Microsoft Store).'),
        @('NVIDIA', 'Keep NVIDIA Control Panel Global / Program Settings', 'SEGÚN CASO', 'Márcala para conservar los perfiles del cliente; sin marcar si sospechas de perfiles corruptos.'),
        @('AMD', 'Eliminar las carpetas de controladores «C:\AMD»', 'DESMARCAR', 'DDU la marca «NO recomendado».'),
        @('AMD', 'Eliminar el controlador/filtro AMDKMPFD', 'DESMARCAR', 'Solo con copia de seguridad en equipos con chipset AMD.'),
        @('AMD', 'Eliminar Bus de Audio AMD', 'DESMARCAR', 'Solo si hay problemas con el audio HDMI.'),
        @('AMD', "Eliminar carpeta de caché 'Shader Crimson' de AMD", 'MARCAR', 'Evita errores con la caché vieja.'),
        @('AMD', '(DCH driver) Remove the AMD Control Panel installed from the Microsoft Store', 'MARCAR', 'Limpieza completa.'),
        @('Intel', 'Remove Intel Control Panel, Arc Control / Graphics Software, oneAPI Level Zero SDK y Endurance Gaming', 'MARCAR', 'Limpieza completa de Intel. Cuidado: en portátiles con gráfica híbrida limpia solo la que vas a reinstalar.'),
        @('Intel', 'Remove Intel NPU', 'DESMARCAR', 'No es de la gráfica.'),
        @('Intel', 'Extensiones del fabricante (pestaña «Expert options»)', 'DESMARCAR', 'En portátiles DDU las conserva por defecto: quítalas solo si puedes reinstalar el paquete del fabricante.'),
        @('Avanzadas', 'Habilitar el cuadro de diálogo para el Modo Seguro', 'DESMARCAR', 'DDU solo lo aconseja después de probar el Modo seguro a mano.'),
        @('Avanzadas', 'Impedir descargas de controladores desde «Windows Update»', 'MARCAR', 'DDU exige bloquear Windows Update o desconectar Internet hasta instalar el driver nuevo. Si no quieres dejar ese cambio, desconecta la red.')
    )
    $w = New-Object Windows.Forms.Form; $w.Text = "Opciones recomendadas de DDU ($marca)"; $w.ClientSize = New-Object Drawing.Size(780, 600); $w.StartPosition = 'CenterParent'; $w.Font = New-Object Drawing.Font('Segoe UI', 9.5); $w.MaximizeBox = $false; $w.MinimizeBox = $false; $w.FormBorderStyle = 'FixedDialog'
    $r = New-Object Windows.Forms.RichTextBox; $r.ReadOnly = $true; $r.BorderStyle = 'None'; $r.BackColor = [Drawing.Color]::White; $r.Location = New-Object Drawing.Point(12, 12); $r.Size = New-Object Drawing.Size(756, 530); $r.DetectUrls = $false
    $w.Controls.Add($r)
    $ap = { param($t, $c, $neg, $sangria = 0) $r.SelectionStart = $r.TextLength; $r.SelectionIndent = $sangria; $r.SelectionTabs = [int[]]@(120); $r.SelectionColor = $c; $r.SelectionFont = New-Object Drawing.Font('Segoe UI', 9.5, $(if ($neg) { [Drawing.FontStyle]::Bold } else { [Drawing.FontStyle]::Regular })); $r.AppendText($t) }
    $negro = [Drawing.Color]::FromArgb(30, 30, 30)
    & $ap "PROCEDIMIENTO (según el Readme de DDU)`r`n" $negro $true
    & $ap ("  1. Ten ya guardado el instalador del driver nuevo.`r`n  2. Desconecta Internet (o bloquea Windows Update) hasta instalarlo.`r`n  3. Lo mejor es hacerlo en Modo seguro; en modo normal: limpia, reinicia, limpia otra vez y reinicia.`r`n  4. Excluye la carpeta de DDU del antivirus si da problemas.`r`n  5. Abre «Opciones» en DDU, ajusta lo de abajo y elige GPU + fabricante ($marca).`r`n") $negro $false
    $color = @{ 'MARCAR' = [Drawing.Color]::FromArgb(0, 120, 40); 'DESMARCAR' = [Drawing.Color]::FromArgb(180, 30, 30); 'SEGÚN CASO' = [Drawing.Color]::FromArgb(190, 110, 0) }
    foreach ($sec in @('General', $marca, 'Avanzadas')) {
        $it = @($filas | Where-Object { $_[0] -eq $sec }); if (-not $it.Count) { continue }
        & $ap "`r`n$($sec.ToUpper())`r`n" $negro $true
        foreach ($x in $it) {
            & $ap "$($x[2])`t" $color[$x[2]] $true
            & $ap "$($x[1])`r`n" $negro $true
            & $ap "$($x[3])`r`n" ([Drawing.Color]::FromArgb(90, 90, 90)) $false 120
        }
    }
    $w.Add_Shown({ $r.SelectionStart = 0; $r.SelectionLength = 0; $r.ScrollToCaret() })
    $ok = New-Object Windows.Forms.Button; $ok.Text = 'Cerrar'; $ok.Size = New-Object Drawing.Size(110, 32); $ok.Location = New-Object Drawing.Point(658, 556); $ok.DialogResult = 'OK'; $w.Controls.Add($ok); $w.AcceptButton = $ok
    [void]$w.ShowDialog($f)
}

$lEstado = New-Object Windows.Forms.Label; $lEstado.Location = New-Object Drawing.Point(18, 502); $lEstado.Size = New-Object Drawing.Size(624, 84); $lEstado.BackColor = [Drawing.Color]::FromArgb(255, 248, 225); $lEstado.Padding = New-Object Windows.Forms.Padding(8, 6, 8, 6)
$f.Controls.Add($lEstado)

function Set-Estado {
    $hayBasico = [bool]($gpus | Where-Object { $_.Basico })
    $t = if ($hayBasico -and -not $script:CopiaHecha) { 'La gráfica parece ya sin driver del fabricante: pasa directamente al paso 5 e instala el nuevo.' }
    elseif (-not $script:CopiaHecha) { 'Empieza por el paso 1 (copia de seguridad). DDU no se abre hasta tenerla.' }
    elseif (-not $script:Instalador -and -not $script:Descarga) { 'Paso 2 o 3: consigue el driver nuevo (o elige el instalador que ya tengas guardado).' }
    else { 'Listo para el paso 4 (DDU). Después del reinicio vuelve a abrir esta herramienta y pulsa el paso 5.' }
    $lEstado.Text = $t + $(if ($script:Instalador) { "`r`nInstalador elegido: $(Split-Path $script:Instalador -Leaf)" } else { '' })
}

function New-Paso([string]$texto, [int]$y, [scriptblock]$accion) {
    $b = New-Object Windows.Forms.Button; $b.Text = $texto; $b.Location = New-Object Drawing.Point(18, $y); $b.Size = New-Object Drawing.Size(624, 38); $b.TextAlign = 'MiddleLeft'; $b.Padding = New-Object Windows.Forms.Padding(8, 0, 0, 0)
    $b.Add_Click({ param($s, $e2) try { & $s.Tag; $f.Refresh() } catch { Say "  $($E.Error) $($_.Exception.Message)" 'ERROR'; [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Reinstalar gráfica', 'OK', 'Error') }; Set-Estado })
    $b.Tag = $accion; $f.Controls.Add($b); $b
}

# Paso 1: copia de seguridad del driver actual + punto de restauración
[void](New-Paso '1   Copia de seguridad del driver actual y punto de restauración' 166 {
        [void](Start-OperacionSegura 'Reinstalar gráfica (limpio)')
        $dir = Join-Path (Get-CarpetaSalida 'Respaldo') ('Drivers_Grafica_' + (Get-Date -Format 'yyyyMMdd_HHmmss')); New-Item -ItemType Directory -Force $dir | Out-Null
        $n = 0
        foreach ($g in ($gpus | Where-Object { $_.Inf -match '^oem\d+\.inf$' })) {
            $r = Invoke-Proceso "$env:SystemRoot\System32\pnputil.exe" "/export-driver $($g.Inf) `"$dir`"" 300 "Copia del driver $($g.Nombre)" 30
            if ($r.Codigo -eq 0) { $n++ }
        }
        $copiado = @(Get-ChildItem -LiteralPath $dir -Recurse -File -ErrorAction SilentlyContinue).Count
        if ($n -gt 0 -and $copiado) {
            Save-Informativo "Driver de la gráfica copiado a $dir" "Para volver a él: pnputil /add-driver `"$dir\*.inf`" /install /subdirs, o usa el punto de restauración de Nitrit0."
            Say "  $($E.OK) Driver actual guardado en $dir ($copiado archivos) y punto de restauración creado."
        } else {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
            Say "  $($E.Aviso) No había un driver del fabricante que copiar (el equipo usa el básico de Microsoft). Punto de restauración creado igualmente."
        }
        $script:CopiaHecha = $true; $script:Acciones.Add('Copia de seguridad hecha')
    })

# Paso 2: conseguir el driver nuevo
[void](New-Paso '2   Conseguir el driver nuevo (abre NVCleanstall o la página oficial)' 210 {
        $m = [string]$cb.SelectedItem
        if ($m -eq 'NVIDIA' -and $tieneNvc) {
            [void][Windows.Forms.MessageBox]::Show("Se abre NVCleanstall (TechPowerUp). Elige la versión del driver y, si ofrece guardar o crear el paquete de instalación, guárdalo en una carpeta para el paso 3.`r`n`r`nSi solo ofrece instalar, no lo instales todavía: ciérralo y usa el paso 4 primero; la instalación limpia se hace en el paso 5.", 'NVIDIA', 'OK', 'Information')
            Start-Process -FilePath $nvc -WorkingDirectory (Split-Path $nvc)
            $script:Descarga = $true; Say "  $($E.Info) NVCleanstall abierto."
        } else {
            $url = switch ($m) { 'NVIDIA' { 'https://www.nvidia.com/Download/index.aspx' } 'AMD' { 'https://www.amd.com/en/support/download/drivers.html' } default { 'https://www.intel.com/content/www/us/en/support/detect.html' } }
            Start-Process $url; $script:Descarga = $true
            Say "  $($E.Info) Abierta la página oficial de $m. Descarga el instalador del driver y guárdalo; luego elígelo en el paso 3."
        }
        $script:Acciones.Add("Descarga del driver ($m)")
    })

# Paso 3: elegir instalador guardado
[void](New-Paso '3   Elegir el instalador del driver que ya tengo guardado…' 254 {
        $d = New-Object Windows.Forms.OpenFileDialog; $d.Title = 'Instalador del driver de la gráfica'; $d.Filter = 'Instaladores (*.exe)|*.exe'
        $dl = Join-Path $env:USERPROFILE 'Downloads'; if (Test-Path -LiteralPath $dl) { $d.InitialDirectory = $dl }
        if ($d.ShowDialog() -ne 'OK') { return }
        if (-not (Test-Firma $d.FileName 'NVIDIA|Advanced Micro Devices|Intel|TechPowerUp')) { throw 'Ese archivo no lleva una firma digital válida de NVIDIA, AMD, Intel o TechPowerUp: no se usa.' }
        $script:Instalador = $d.FileName; Say "  $($E.OK) Instalador elegido y firma verificada: $($d.FileName)"; $script:Acciones.Add('Instalador elegido')
    })

# Croquis de opciones de DDU (solo informa)
[void](New-Paso '     Opciones recomendadas de DDU: qué marcar y qué no' 386 { Show-OpcionesDdu ([string]$cb.SelectedItem) })

# Paso 4: DDU
[void](New-Paso '4   Limpiar con DDU (Modo seguro recomendado; reinicia el equipo)' 298 {
        if (-not $script:CopiaHecha) { throw 'Haz primero el paso 1 (copia de seguridad): no se abre DDU sin ella.' }
        if (-not $script:Instalador -and -not (Test-Internet)) { throw 'No hay instalador guardado y tampoco Internet para bajar el driver después: el equipo se quedaría con la resolución básica. Elige un instalador (paso 3) o conecta Internet.' }
        $m = [string]$cb.SelectedItem
        $bit = ''; try { $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop; if ($bl.ProtectionStatus -eq 'On') { $bit = "`r`n`r`nOJO: BitLocker está activo. Ten a mano la clave de recuperación por si el arranque en Modo seguro la pide (la herramienta «Licencias y BitLocker» la guarda)." } } catch { }
        $txt = "DDU (Display Driver Uninstaller) se prepara en una copia local.`r`n`r`nAntes de limpiar: mira «Opciones recomendadas de DDU» en este panel y ajusta las casillas; en DDU elige «GPU» y el fabricante «$m».`r`n`r`nDDU EXIGE desconectar Internet (o bloquear Windows Update) hasta instalar el driver nuevo; si no, Windows puede poner uno genérico.`r`n`r`nLo mejor es el MODO SEGURO (Shift + Reiniciar > Solucionar problemas > Opciones avanzadas > Configuración de inicio > 4) y abrir DDU desde la ruta que se copia al portapapeles. En modo normal también vale: limpia, reinicia, limpia otra vez y reinicia.$bit`r`n`r`nGuarda tu trabajo antes de seguir.`r`n`r`nSí = abrir DDU ahora (modo normal)`r`nNo = solo dejar DDU preparado para el Modo seguro`r`nCancelar = no hacer nada"
        $resp = [Windows.Forms.MessageBox]::Show($txt, 'Limpiar con DDU', 'YesNoCancel', 'Warning', 'Button3')
        if ($resp -eq 'Cancel') { Say "  $($E.Info) DDU no se abrió."; return }
        # DDU escribe su configuración junto a su exe: se usa una copia local (que sigue ahí tras reiniciar en Modo seguro) para no tocar el pendrive
        $dst = Join-Path $env:ProgramData 'Nitrit0\DDU'
        Remove-Item -LiteralPath $dst -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force $dst | Out-Null
        Copy-Item -LiteralPath (Split-Path $ddu) -Destination $dst -Recurse -Force
        $exe = Join-Path (Join-Path $dst (Split-Path (Split-Path $ddu) -Leaf)) 'Display Driver Uninstaller.exe'
        try { Set-Clipboard -Value $exe } catch { }
        Save-Informativo "DDU preparado para limpiar el driver de $m" "DDU quedó copiado en $dst (se puede borrar después). La limpieza no se deshace: para volver al driver anterior usa la copia del paso 1 (pnputil /add-driver) o el punto de restauración."
        if ($resp -eq 'Yes') { Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe); Say "  $($E.Cohete) DDU abierto para limpiar $m. Tras el reinicio, abre esta herramienta y pulsa el paso 5." }
        else { Say "  $($E.OK) DDU preparado en: $exe (copiado al portapapeles). Reinicia en Modo seguro y ábrelo desde ahí." }
        $script:Acciones.Add("DDU $(if ($resp -eq 'Yes') { 'abierto' } else { 'preparado' }) ($m)")
    })

# Paso 5: instalar
[void](New-Paso '5   Instalar el driver nuevo' 342 {
        $m = [string]$cb.SelectedItem
        if ($script:Instalador) {
            Start-Process -FilePath $script:Instalador -WorkingDirectory (Split-Path $script:Instalador)
            Say "  $($E.Cohete) Instalador abierto: $(Split-Path $script:Instalador -Leaf). Elige «Personalizada» e «Instalación limpia» si el instalador lo ofrece, y reinicia al terminar."
            $script:Acciones.Add('Instalador lanzado')
        } elseif ($m -eq 'NVIDIA' -and $tieneNvc) {
            Start-Process -FilePath $nvc -WorkingDirectory (Split-Path $nvc); Say "  $($E.Info) NVCleanstall abierto: descarga e instala el driver desde ahí (marca «instalación limpia»)."; $script:Acciones.Add('NVCleanstall abierto')
        } else {
            $url = switch ($m) { 'NVIDIA' { 'https://www.nvidia.com/Download/index.aspx' } 'AMD' { 'https://www.amd.com/en/support/download/drivers.html' } default { 'https://www.intel.com/content/www/us/en/support/detect.html' } }
            Start-Process $url; Say "  $($E.Info) Abierta la página oficial de ${m}: descarga el driver e instálalo (o elígelo en el paso 3 y vuelve aquí)."; $script:Acciones.Add("Página oficial abierta ($m)")
        }
    })

$info = New-Object Windows.Forms.Label; $info.Location = New-Object Drawing.Point(18, 436); $info.Size = New-Object Drawing.Size(624, 58)
$info.Text = "Los pasos se pueden hacer en dos veces: 1-4 antes de reiniciar y 5 después. Alternativa de AMD a DDU: AMD Cleanup Utility (amd.com/cleanuninstall). En portátiles con gráfica híbrida conviene el driver del fabricante del equipo."
$f.Controls.Add($info)
$cerrar = New-Object Windows.Forms.Button; $cerrar.Text = 'Cerrar'; $cerrar.Size = New-Object Drawing.Size(110, 32); $cerrar.Location = New-Object Drawing.Point(532, 598); $cerrar.DialogResult = 'Cancel'; $f.Controls.Add($cerrar); $f.CancelButton = $cerrar
Set-Estado
Say "  $($E.Lupa) Panel de reinstalación limpia abierto. Gráfica: $(($gpus | ForEach-Object { "$($_.Marca) $($_.Version)" }) -join '; ')"
[void]$f.ShowDialog()

Write-Output ""
if ($script:Acciones.Count) { Write-Output "  $($E.OK) Acciones hechas: $($script:Acciones -join ' · ')." } else { Write-Output "  $($E.Info) No se ha hecho ningún paso: no se ha cambiado nada." }
Write-Log "Gráfica limpia: $(if ($script:Acciones.Count) { $script:Acciones -join ' | ' } else { 'sin acciones' })"
exit 0
