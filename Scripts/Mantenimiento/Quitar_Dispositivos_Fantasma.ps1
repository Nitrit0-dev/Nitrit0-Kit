# =====================================================================
#  Quitar_Dispositivos_Fantasma.ps1 - Dispositivos que ya no están conectados pero siguen registrados (Nitrit0)
#  Cada pendrive, ratón, móvil o monitor que se ha enchufado alguna vez deja una entrada en Windows aunque ya no esté. Con los
#  años se acumulan cientos y a veces causan conflictos (letras de unidad ocupadas, drivers USB raros, monitores duplicados).
#  Esta herramienta los lista, marca los que suelen ser seguros de quitar (USB, móviles, discos externos, monitores) y deja los demás
#  sin marcar. Quitar la entrada no borra nada del dispositivo: Windows la recrea al volver a enchufarlo.
#  Antes de quitar crea un punto de restauración. Usa «pnputil /remove-device» (Windows 10 versión 2004 o superior).
#  Parámetros: -SoloAnalizar (lista y no quita nada)   -Auto (sin ventana: quita solo los marcados por defecto)
# =====================================================================
[CmdletBinding()]
param([switch]$SoloAnalizar, [switch]$Auto)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$esAdmin = Test-EsAdmin
if (-not $esAdmin -and -not $SoloAnalizar) { Write-Output "$($E.Aviso) Hace falta administrador para quitar dispositivos. Ábrelo desde el kit o usa -SoloAnalizar."; exit 1 }

# Qué se considera: solo enumeradores donde los «fantasmas» son habituales y quitar la entrada es inocuo. Nunca placa, procesador, discos del sistema ni controladores.
$enumeradores = 'USB', 'USBSTOR', 'HID', 'BTH', 'BTHENUM', 'WPDBUSENUM', 'SCSI', 'STORAGE', 'MONITOR', 'DISPLAY'
$marcadosPorDefecto = 'USB', 'WPD', 'DiskDrive', 'Monitor', 'HIDClass', 'Image', 'USBDevice', 'CDROM'
Write-Output "  $($E.Lupa) Buscando dispositivos que ya no están conectados…"
try { $todos = @(Get-PnpDevice -ErrorAction Stop) } catch { Write-Output "$($E.Error) No se pudo leer la lista de dispositivos: $($_.Exception.Message)"; exit 1 }
$fantasmas = @($todos | Where-Object { -not $_.Present -and (([string]$_.InstanceId -split '\\')[0] -in $enumeradores) -and [string]$_.Class -notin 'Volume', 'VolumeSnapshot' })   # las instantáneas de volumen (copias de seguridad) no se tocan
Write-Output "  $($E.Info) $($todos.Count) dispositivos registrados; $(@($todos | Where-Object { -not $_.Present }).Count) no presentes, de ellos $($fantasmas.Count) de los tipos que esta herramienta trata."
if (-not $fantasmas.Count) { Write-Output "  $($E.OK) No hay dispositivos fantasma de esos tipos."; Write-Log 'Quitar_Dispositivos_Fantasma: ninguno'; return }
$lista = @($fantasmas | ForEach-Object { [pscustomobject]@{ Clase = [string]$_.Class; Nombre = [string]$_.FriendlyName; Id = [string]$_.InstanceId; Marcado = ([string]$_.Class -in $marcadosPorDefecto) } } | Sort-Object Clase, Nombre)
foreach ($g in ($lista | Group-Object Clase | Sort-Object Count -Descending)) { Write-Output ("    - {0}: {1}" -f $(if ($g.Name) { $g.Name } else { '(sin clase)' }), $g.Count) }
if ($SoloAnalizar) { foreach ($x in $lista) { Write-Output ("    [{0}] {1} · {2}" -f $(if ($x.Marcado) { 'se propone quitar' } else { 'sin marcar' }), $x.Nombre, $x.Id) }; Write-Output "`n  $($E.Info) Solo análisis: no se ha quitado nada."; return }

function Show-Fantasmas($items) {
    $f = New-Object Windows.Forms.Form; $f.Text = 'Dispositivos fantasma'; $f.Size = New-Object Drawing.Size(1000, 680); $f.StartPosition = 'CenterScreen'; $f.TopMost = $true; $f.Font = New-Object Drawing.Font('Segoe UI', 9.5)
    $t = New-Object Windows.Forms.Label; $t.Text = 'Dispositivos que ya no están conectados'; $t.Font = New-Object Drawing.Font('Segoe UI Semibold', 14); $t.AutoSize = $true; $t.Location = New-Object Drawing.Point(20, 14)
    $s = New-Object Windows.Forms.Label; $s.Text = 'Marca los que quieres quitar del registro de Windows. No se borra nada del dispositivo: Windows lo vuelve a registrar si lo enchufas otra vez.'; $s.AutoSize = $false; $s.Size = New-Object Drawing.Size(940, 36); $s.Location = New-Object Drawing.Point(20, 46)
    $lv = New-Object Windows.Forms.ListView; $lv.View = 'Details'; $lv.CheckBoxes = $true; $lv.FullRowSelect = $true; $lv.ShowGroups = $true; $lv.Location = New-Object Drawing.Point(20, 88); $lv.Size = New-Object Drawing.Size(944, 480); $lv.Anchor = 'Top,Bottom,Left,Right'
    foreach ($c in @(@('Dispositivo', 420), @('Identificador', 500))) { [void]$lv.Columns.Add($c[0], $c[1]) }
    $gr = @{}
    foreach ($x in $items) {
        $k = if ($x.Clase) { $x.Clase } else { '(sin clase)' }
        if (-not $gr.ContainsKey($k)) { $gr[$k] = New-Object Windows.Forms.ListViewGroup($k); [void]$lv.Groups.Add($gr[$k]) }
        $i = New-Object Windows.Forms.ListViewItem($(if ($x.Nombre) { $x.Nombre } else { '(sin nombre)' })); [void]$i.SubItems.Add($x.Id); $i.Group = $gr[$k]; $i.Tag = $x; $i.Checked = $x.Marcado; [void]$lv.Items.Add($i)
    }
    $ok = New-Object Windows.Forms.Button; $ok.Text = 'Quitar lo marcado'; $ok.Size = New-Object Drawing.Size(200, 36); $ok.Location = New-Object Drawing.Point(764, 585); $ok.Anchor = 'Bottom,Right'; $ok.DialogResult = 'OK'
    $no = New-Object Windows.Forms.Button; $no.Text = 'No quitar nada'; $no.Size = New-Object Drawing.Size(130, 36); $no.Location = New-Object Drawing.Point(624, 585); $no.Anchor = 'Bottom,Right'; $no.DialogResult = 'Cancel'
    $lbl = New-Object Windows.Forms.Label; $lbl.AutoSize = $true; $lbl.Location = New-Object Drawing.Point(22, 595); $lbl.Anchor = 'Bottom,Left'
    $cuenta = { $lbl.Text = "$(@($lv.CheckedItems).Count) de $($lv.Items.Count) marcados" }; & $cuenta; $lv.Add_ItemChecked($cuenta)
    $f.Controls.AddRange(@($t, $s, $lv, $lbl, $ok, $no)); $f.AcceptButton = $ok; $f.CancelButton = $no
    if ($f.ShowDialog() -ne 'OK') { return @() }
    @($lv.CheckedItems | ForEach-Object { $_.Tag })
}
$elegidos = if ($Auto) { @($lista | Where-Object Marcado) } else { @(Show-Fantasmas $lista) }
if (-not $elegidos.Count) { Write-Output "  $($E.Aviso) No se quita nada."; return }
$soporta = ((& (Join-Path $env:SystemRoot 'System32\pnputil.exe') /? 2>&1) | Out-String) -match 'remove-device'
if (-not $soporta) { Write-Output "$($E.Error) Este Windows no tiene «pnputil /remove-device» (hace falta Windows 10 versión 2004 o superior)."; exit 1 }
[void](New-PuntoRestauracionSeguro 'Nitrit0 - antes de quitar dispositivos fantasma')
$ok = 0; $fallos = 0
foreach ($x in $elegidos) {
    $r = Invoke-Proceso (Join-Path $env:SystemRoot 'System32\pnputil.exe') ('/remove-device "{0}"' -f $x.Id) 120 'Quitar dispositivo' 60
    if ($r.Codigo -eq 0) { $ok++; Write-Log "Quitar_Dispositivos_Fantasma: quitado $($x.Id)" } else { $fallos++; Write-Output "  $($E.Aviso) No se pudo quitar: $($x.Nombre) ($($x.Id)), código $($r.Codigo)."; Write-Log "Quitar_Dispositivos_Fantasma: fallo $($x.Id) código $($r.Codigo)" 'AVISO' }
}
Write-Output "`n$($E.OK) Quitados $ok dispositivos fantasma$(if ($fallos) { "; $fallos no se pudieron quitar" } else { '' })."
if ($fallos) { exit 1 }
