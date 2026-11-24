# =====================================================================
#  Actualizar_Herramientas.ps1 - Comprueba y actualiza las apps de Apps\ desde su fuente oficial (Nitrit0)
#  Es la antigua ventana «Actualizar herramientas» del lanzador, ahora dentro de la app. Cada programa se consulta en su fuente oficial
#  (GitHub o la web del autor), la descarga se verifica (hash SHA-256 publicado o firma digital del autor) y, antes de reemplazar nada,
#  se guarda una copia de la versión anterior en Datos\Respaldo. Los programas sin descarga directa estable solo se listan con su web oficial.
#  Parámetro: -SoloComprobar (consulta versiones y no descarga ni cambia nada)
# =====================================================================
[CmdletBinding()]
param([Alias('SoloComprobar')][switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$global:dirApps = Join-Path (Get-KitRaiz) 'Apps'; $global:dirDatos = Get-KitDatos   # los usan las funciones del archivo que se carga a continuación
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Actualizador.ps1')   # catálogo de fuentes y funciones (Get-Remoto, Update-Herramienta...)
if (-not (Test-Internet)) { Write-Output "$($E.Error) No hay conexión a Internet: sin ella no se pueden comprobar versiones."; exit 1 }

Write-Output "  $($E.Lupa) Comprobando versiones en las fuentes oficiales…"
$verStore = Get-Versiones
$filas = New-Object Collections.Generic.List[object]; $manuales = New-Object Collections.Generic.List[object]
foreach ($e in $script:CatalogoUpd) {
    if ($e.Tipo -eq 'pagina') { $manuales.Add($e); continue }
    $inst = Get-VersionInstalada $e
    if (-not $inst) { Write-Output "    · $($e.N): no está en el kit (se omite)"; continue }
    $r = Get-Remoto $e
    if ($r.Error) { Write-Output "    $($E.Aviso) $($e.N): no se pudo comprobar ($($r.Error))"; continue }
    $hay = $false; $texto = ''
    if ($e.Repo) {
        $vi = ConvertTo-Numerico $inst
        $hay = if ($r.Version -and $vi) { $r.Version -gt $vi } else { $true }
        $texto = if ($hay) { "disponible $($r.Etiqueta) (tienes $inst)" } else { "al día ($($r.Etiqueta))" }
    } else {
        $reg = $verStore.($e.N)
        if ($reg -and $reg.Remoto -eq $r.Etiqueta) { $texto = "al día (web: $($r.Etiqueta))" }
        elseif ($reg) { $hay = $true; $texto = "hay versión nueva en la web ($($r.Etiqueta))" }
        else { $hay = $true; $texto = "última en la web: $($r.Etiqueta); se puede reinstalar para asegurarte" }
    }
    Write-Output ("    {0} {1}: {2}" -f $(if ($hay) { $E.Aviso } else { $E.OK }), $e.N, $texto)
    $filas.Add([pscustomobject]@{ E = $e; R = $r; Hay = $hay; Instalada = $inst; Texto = $texto })
}
$nuevas = @($filas | Where-Object Hay)
Write-Output "`n  $($E.Info) $($nuevas.Count) con actualización disponible, $(@($filas | Where-Object { -not $_.Hay }).Count) al día."
if ($manuales.Count) {
    Write-Output "  $($E.Info) Sin descarga automática (se actualizan desde su web oficial):"
    foreach ($m in $manuales) { Write-Output "    · $($m.N): $($m.Pagina)" }
}
Write-Log "Actualizar_Herramientas: $($nuevas.Count) disponibles, $($filas.Count) comprobadas"
if ($SoloAnalizar -or -not $nuevas.Count) { if ($SoloAnalizar) { Write-Output "  $($E.Info) Solo comprobación: no se ha descargado nada." }; return }

# ---------------------------------------------------------------- Elegir qué actualizar
$f = New-Object Windows.Forms.Form; $f.Text = 'Actualizar herramientas'; $f.Size = New-Object Drawing.Size(900, 520); $f.StartPosition = 'CenterScreen'; $f.TopMost = $true; $f.Font = New-Object Drawing.Font('Segoe UI', 9.5)
$t = New-Object Windows.Forms.Label; $t.Text = 'Actualizaciones disponibles'; $t.Font = New-Object Drawing.Font('Segoe UI Semibold', 14); $t.AutoSize = $true; $t.Location = New-Object Drawing.Point(20, 14)
$s = New-Object Windows.Forms.Label; $s.Text = 'Se descargan de su fuente oficial, se verifican (SHA-256 o firma digital) y se guarda una copia de la versión anterior en Datos\Respaldo.'; $s.AutoSize = $false; $s.Size = New-Object Drawing.Size(840, 36); $s.Location = New-Object Drawing.Point(20, 46)
$lv = New-Object Windows.Forms.ListView; $lv.View = 'Details'; $lv.CheckBoxes = $true; $lv.FullRowSelect = $true; $lv.Location = New-Object Drawing.Point(20, 88); $lv.Size = New-Object Drawing.Size(844, 320); $lv.Anchor = 'Top,Bottom,Left,Right'
foreach ($c in @(@('Programa', 260), @('Instalada', 200), @('Qué hay', 360))) { [void]$lv.Columns.Add($c[0], $c[1]) }
foreach ($x in $nuevas) { $i = New-Object Windows.Forms.ListViewItem($x.E.N); [void]$i.SubItems.Add([string]$x.Instalada); [void]$i.SubItems.Add($x.Texto); $i.Tag = $x; $i.Checked = $true; [void]$lv.Items.Add($i) }
$ok = New-Object Windows.Forms.Button; $ok.Text = 'Actualizar lo marcado'; $ok.Size = New-Object Drawing.Size(200, 36); $ok.Location = New-Object Drawing.Point(664, 430); $ok.Anchor = 'Bottom,Right'; $ok.DialogResult = 'OK'
$no = New-Object Windows.Forms.Button; $no.Text = 'No actualizar'; $no.Size = New-Object Drawing.Size(130, 36); $no.Location = New-Object Drawing.Point(524, 430); $no.Anchor = 'Bottom,Right'; $no.DialogResult = 'Cancel'
$f.Controls.AddRange(@($t, $s, $lv, $ok, $no)); $f.AcceptButton = $ok; $f.CancelButton = $no
if ($f.ShowDialog() -ne 'OK') { Exit-Kit 'Cancelado' 'No se actualiza nada.' }
$elegidas = @($lv.CheckedItems | ForEach-Object { $_.Tag })
if (-not $elegidas.Count) { Exit-Kit 'Cancelado' 'No se actualiza nada.' }

$bien = 0; $mal = 0
foreach ($x in $elegidas) {
    Write-Output "  $($E.Reloj) $($x.E.N)…"
    $res = Update-Herramienta $x.E $x.R { param($m) Write-Output "      $m" }
    if ($res.Ok) { $bien++; Write-Output "  $($E.OK) $($x.E.N) actualizada: ahora $(Get-VersionInstalada $x.E)." ; Write-Log "Actualizar_Herramientas: $($x.E.N) actualizada" }
    else { $mal++; Write-Output "  $($E.Aviso) $($x.E.N) no se actualizó: $($res.Mensaje)"; Write-Log "Actualizar_Herramientas: $($x.E.N) falló ($($res.Mensaje))" 'AVISO' }
}
Write-Output "`n$($E.OK) $bien actualizada(s)$(if ($mal) { ", $mal con error" }). La versión anterior de cada una está en Datos\Respaldo."
# La lista de integridad guarda la huella de cada archivo: tras actualizar, las herramientas nuevas no coinciden y el kit puede avisar de manipulación
if ($bien) { Write-Output "  $($E.Aviso) Falta un paso: ejecuta Scripts\Regenerar_Integridad.ps1 en tu equipo de trabajo para que las herramientas actualizadas consten como válidas. No se hace solo para que nadie dé por buena una descarga sin mirarla." }
if ($mal) { exit 1 }
