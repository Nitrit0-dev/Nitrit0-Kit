# =====================================================================
#  Limpiar_Almacen_Drivers.ps1 - Quita del almacén de drivers las versiones antiguas que ya no usa nada (Nitrit0)
#  Con los años, cada actualización de gráfica, audio o impresora deja su paquete anterior en DriverStore (a veces decenas de GB).
#  Clasifica los paquetes de terceros (oemNN.inf) y solo propone borrar los que ningún dispositivo está usando:
#    · «Versión antigua»: hay una versión más nueva del mismo driver que SÍ está en uso (viene marcada).
#    · «Sin dispositivo»: no lo usa ningún dispositivo ahora (un móvil, una impresora o un adaptador que no está conectado). Viene sin marcar.
#  Nunca toca los de Windows (inbox), los que usa algún dispositivo, los de arranque (BootCritical) ni los de clase Extension, impresora o firmware.
#  Antes de borrar: punto de restauración y copia de cada paquete en Datos\Drivers\Almacen_<fecha>\ (se reinstala con pnputil /add-driver).
#  Se borra con «pnputil /delete-driver» SIN /force: si Windows lo está usando, se niega.
#  Parámetros: -SoloAnalizar (lista y no borra nada)   -Auto (sin ventana: solo las «Versión antigua»)
# =====================================================================
[CmdletBinding()]
param([switch]$SoloAnalizar, [switch]$Auto)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$esAdmin = Test-EsAdmin
if (-not $esAdmin) { Write-Output "$($E.Aviso) Hace falta administrador para leer y limpiar el almacén de drivers. Ábrelo desde el kit."; exit 1 }

function Get-Ver([string]$v) { try { [version]$v } catch { [version]'0.0' } }
function Get-TamDir([string]$d) { if ($d -and (Test-Path -LiteralPath $d)) { [int64](Get-ChildItem -LiteralPath $d -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum } else { [int64]0 } }
function Format-Tam([int64]$b) { if ($b -ge 1GB) { '{0:N1} GB' -f ($b / 1GB) } elseif ($b -ge 1MB) { '{0:N0} MB' -f ($b / 1MB) } else { '{0:N0} KB' -f ($b / 1KB) } }

# ---------------------------------------------------------------- Análisis
Write-Output "  $($E.Lupa) Leyendo el almacén de drivers (puede tardar un minuto)…"
try { $todos = @(Get-WindowsDriver -Online -All -ErrorAction Stop) } catch { Write-Output "$($E.Error) No se pudo leer el almacén de drivers: $($_.Exception.Message)"; Write-Log "Limpiar_Almacen_Drivers: error de lectura $($_.Exception.Message)" 'ERROR'; exit 1 }
$usados = @{}; foreach ($d in @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue)) { if ($d.InfName) { $usados[([string]$d.InfName).ToLower()] = $true } }
if (-not $usados.Count) { Write-Output "$($E.Error) No pude saber qué drivers están en uso, así que no propongo borrar nada."; exit 1 }

# Extensiones (efectos de audio y similares), impresoras y firmware se usan sin figurar como driver de un dispositivo: no se proponen nunca
$clasesProtegidas = 'Extension', 'Printer', 'PrintQueue', 'PrinterUpgrade', 'Firmware'
$terceros = @($todos | Where-Object { -not $_.Inbox -and $_.Driver -match '^oem\d+\.inf$' })
$claves = @{}; foreach ($p in $terceros) { $k = "$($p.ClassName)|$($p.ProviderName)|$([IO.Path]::GetFileName($p.OriginalFileName))".ToLower(); if (-not $claves.ContainsKey($k)) { $claves[$k] = New-Object Collections.Generic.List[object] }; $claves[$k].Add($p) }
$lista = New-Object Collections.Generic.List[object]; $protegidos = 0; $enUso = 0
foreach ($p in $terceros) {
    if ($usados.ContainsKey($p.Driver.ToLower())) { $enUso++; continue }
    if ($p.BootCritical) { $protegidos++; continue }
    if ($p.ClassName -in $clasesProtegidas) { $protegidos++; continue }   # no se pueden ligar a un dispositivo: Windows no siempre dice si se usan
    $k = "$($p.ClassName)|$($p.ProviderName)|$([IO.Path]::GetFileName($p.OriginalFileName))".ToLower()
    $vp = Get-Ver $p.Version
    $reemplazo = @($claves[$k] | Where-Object { $usados.ContainsKey($_.Driver.ToLower()) -and ((Get-Ver $_.Version) -gt $vp -or ((Get-Ver $_.Version) -eq $vp -and $_.Date -ge $p.Date)) } | Select-Object -First 1)
    $tipo = if ($reemplazo.Count) { 'Versión antigua' } else { 'Sin dispositivo' }
    $tam = Get-TamDir (Split-Path -Parent $p.OriginalFileName)
    $lista.Add([pscustomobject]@{ Tipo = $tipo; Inf = $p.Driver; Clase = $p.ClassName; Proveedor = $p.ProviderName; Version = $p.Version; Fecha = $(try { $p.Date.ToString('yyyy-MM-dd') } catch { '' }); Tam = $tam; Detalle = $(if ($reemplazo.Count) { "sustituido por $($reemplazo[0].Driver) v$($reemplazo[0].Version) (en uso)" } else { 'ningún dispositivo lo usa ahora' }) })
}
Write-Output "  $($E.Info) $($terceros.Count) paquetes de terceros: $enUso en uso, $protegidos de arranque, impresora o extensión (no se tocan) y $($lista.Count) sin uso."
if (-not $lista.Count) { Write-Output "  $($E.OK) No hay nada que limpiar: todos los drivers de terceros están en uso."; Write-Log 'Limpiar_Almacen_Drivers: nada que limpiar'; return }
$antiguos = @($lista | Where-Object Tipo -eq 'Versión antigua'); $sinDisp = @($lista | Where-Object Tipo -eq 'Sin dispositivo')
$tamA = [int64](($antiguos | Measure-Object Tam -Sum).Sum); $tamS = [int64](($sinDisp | Measure-Object Tam -Sum).Sum)
Write-Output "    - Versiones antiguas ya sustituidas: $($antiguos.Count) ($(Format-Tam $tamA))"
Write-Output "    - Sin dispositivo ahora: $($sinDisp.Count) ($(Format-Tam $tamS))"
if ($SoloAnalizar) {
    foreach ($x in ($lista | Sort-Object Tipo, Clase, Proveedor, Fecha)) { Write-Output ("    [{0}] {1} · {2} · {3} v{4} ({5}) · {6} · {7}" -f $x.Tipo, $x.Inf, $x.Clase, $x.Proveedor, $x.Version, $x.Fecha, (Format-Tam $x.Tam), $x.Detalle) }
    Write-Output "`n  $($E.Info) Solo análisis: no se ha borrado nada."; Write-Log "Limpiar_Almacen_Drivers: análisis $($antiguos.Count) antiguas, $($sinDisp.Count) sin dispositivo"; return
}

# ---------------------------------------------------------------- Selección
function Show-Paquetes($items) {
    $f = New-Object Windows.Forms.Form; $f.Text = 'Almacén de drivers'; $f.Size = New-Object Drawing.Size(1150, 700); $f.StartPosition = 'CenterScreen'; $f.TopMost = $true; $f.Font = New-Object Drawing.Font('Segoe UI', 9.5)
    $t = New-Object Windows.Forms.Label; $t.Text = 'Drivers que ya no usa ningún dispositivo'; $t.Font = New-Object Drawing.Font('Segoe UI Semibold', 14); $t.AutoSize = $true; $t.Location = New-Object Drawing.Point(20, 14)
    $s = New-Object Windows.Forms.Label; $s.Text = 'Marca lo que quieres quitar. Antes se crea un punto de restauración y se guarda una copia de cada paquete. Las «Versión antigua» vienen marcadas; las «Sin dispositivo» no (pueden ser de un móvil o una impresora que no está enchufada).'; $s.AutoSize = $false; $s.Size = New-Object Drawing.Size(1090, 40); $s.Location = New-Object Drawing.Point(20, 46)
    $lv = New-Object Windows.Forms.ListView; $lv.View = 'Details'; $lv.CheckBoxes = $true; $lv.FullRowSelect = $true; $lv.ShowGroups = $true; $lv.Location = New-Object Drawing.Point(20, 92); $lv.Size = New-Object Drawing.Size(1094, 490); $lv.Anchor = 'Top,Bottom,Left,Right'
    foreach ($c in @(@('Driver', 230), @('Tipo de dispositivo', 150), @('Fabricante', 190), @('Versión', 110), @('Fecha', 90), @('Tamaño', 80), @('Por qué', 230))) { [void]$lv.Columns.Add($c[0], $c[1]) }
    $grupos = @{}; foreach ($n in 'Versión antigua', 'Sin dispositivo') { $grupos[$n] = New-Object Windows.Forms.ListViewGroup($n); [void]$lv.Groups.Add($grupos[$n]) }
    foreach ($x in ($items | Sort-Object Clase, Proveedor, Fecha)) {
        $i = New-Object Windows.Forms.ListViewItem($x.Inf); foreach ($v in @($x.Clase, $x.Proveedor, $x.Version, $x.Fecha, (Format-Tam $x.Tam), $x.Detalle)) { [void]$i.SubItems.Add([string]$v) }
        $i.Group = $grupos[$x.Tipo]; $i.Tag = $x; $i.Checked = ($x.Tipo -eq 'Versión antigua'); [void]$lv.Items.Add($i)
    }
    $ok = New-Object Windows.Forms.Button; $ok.Text = 'Quitar lo marcado'; $ok.Size = New-Object Drawing.Size(200, 36); $ok.Location = New-Object Drawing.Point(914, 600); $ok.Anchor = 'Bottom,Right'; $ok.DialogResult = 'OK'
    $no = New-Object Windows.Forms.Button; $no.Text = 'No quitar nada'; $no.Size = New-Object Drawing.Size(130, 36); $no.Location = New-Object Drawing.Point(774, 600); $no.Anchor = 'Bottom,Right'; $no.DialogResult = 'Cancel'
    $lbl = New-Object Windows.Forms.Label; $lbl.AutoSize = $true; $lbl.Location = New-Object Drawing.Point(22, 610); $lbl.Anchor = 'Bottom,Left'
    $cuenta = { $b = [int64]0; foreach ($it in $lv.CheckedItems) { $b += $it.Tag.Tam }; $lbl.Text = "$(@($lv.CheckedItems).Count) de $($lv.Items.Count) marcados · se liberarán unos $(Format-Tam $b)" }; & $cuenta; $lv.Add_ItemChecked($cuenta)
    $f.Controls.AddRange(@($t, $s, $lv, $lbl, $ok, $no)); $f.AcceptButton = $ok; $f.CancelButton = $no
    if ($f.ShowDialog() -ne 'OK') { return @() }
    @($lv.CheckedItems | ForEach-Object { $_.Tag })
}
$elegidos = if ($Auto) { $antiguos } else { @(Show-Paquetes $lista) }
if (-not $elegidos.Count) { Exit-Kit 'Cancelado' 'No se quita nada.' }

# ---------------------------------------------------------------- Copia y borrado
[void](New-PuntoRestauracionSeguro 'Nitrit0 - antes de limpiar el almacén de drivers')
$respaldo = Join-Path (Get-BaseTrabajo) ('Drivers\Almacen_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Force $respaldo | Out-Null
$ok = 0; $fallos = 0; $liberado = [int64]0
foreach ($x in $elegidos) {
    $copia = Join-Path $respaldo ($x.Inf -replace '\.inf$', '')
    New-Item -ItemType Directory -Force $copia | Out-Null
    $r = Invoke-Proceso (Join-Path $env:SystemRoot 'System32\pnputil.exe') ('/export-driver {0} "{1}"' -f $x.Inf, $copia) 300 "Copia de $($x.Inf)" 60
    if ($r.Codigo -ne 0 -or -not (Get-ChildItem -LiteralPath $copia -Filter *.inf -ErrorAction SilentlyContinue)) { $fallos++; Write-Output "  $($E.Aviso) $($x.Inf): no se pudo guardar la copia, no se borra."; Write-Log "Limpiar_Almacen_Drivers: sin copia de $($x.Inf)" 'AVISO'; continue }
    $b = Invoke-Proceso (Join-Path $env:SystemRoot 'System32\pnputil.exe') ('/delete-driver {0}' -f $x.Inf) 300 "Quitar $($x.Inf)" 60
    if ($b.Codigo -eq 0) { $ok++; $liberado += $x.Tam; Write-Output "  $($E.OK) $($x.Inf) quitado ($($x.Clase), $($x.Proveedor) v$($x.Version))."; Write-Log "Limpiar_Almacen_Drivers: quitado $($x.Inf)" }
    else { $fallos++; Write-Output "  $($E.Aviso) $($x.Inf): Windows no lo quita (probablemente lo usa algo). No se ha cambiado."; Write-Log "Limpiar_Almacen_Drivers: $($x.Inf) rechazado (código $($b.Codigo))" 'AVISO' }
}
Write-Output ''
Write-Output "$($E.OK) Quitados $ok paquetes, unos $(Format-Tam $liberado) liberados$(if ($fallos) { "; $fallos no se pudieron quitar" } else { '' })."
Write-Output "$($E.Info) Copia de lo quitado en: $respaldo"
Write-Output "$($E.Info) Para recuperar uno: pnputil /add-driver `"$respaldo\oemNN\*.inf`" /install"
if ($fallos) { exit 1 }
