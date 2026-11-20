# =====================================================================
#  Prueba_Puertos_USB.ps1 - Mide la velocidad real de un puerto USB, puerto por puerto (Nitrit0)
#  Escribe y lee un archivo temporal de 256 MB en un pendrive o disco USB que tú elijas y dice si el conjunto puerto + cable + dispositivo
#  rinde como USB 3 o como USB 2 (o peor). Después te deja cambiar el dispositivo de puerto y repetir; al final da una tabla.
#  No toca tus archivos: usa un archivo propio que borra al terminar. Nunca usa el disco de Windows ni el del kit.
#  Para saber si un PUERTO es USB 3, usa un dispositivo USB 3 conocido y un cable corto; con uno USB 2 siempre saldrá USB 2.
#  Parámetros: -SoloAnalizar (lista los dispositivos USB y no escribe nada) · -Unidad <letra> -SinPreguntas (una sola medida, sin ventanas) · -MB <tamaño> (por defecto 256)
# =====================================================================
[CmdletBinding()]
param([Alias('Simular', 'SoloMirar')][switch]$SoloAnalizar, [ValidatePattern('^[A-Za-z]$')][string]$Unidad, [switch]$SinPreguntas, [ValidateRange(32, 2048)][int]$MB = 256)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
function Format-Tam([int64]$b) { if ($b -ge 1GB) { '{0:N1} GB' -f ($b / 1GB) } elseif ($b -ge 1MB) { '{0:N0} MB' -f ($b / 1MB) } else { '{0:N0} KB' -f ($b / 1KB) } }

function Get-Candidatas {
    $sistema = $env:SystemDrive.TrimEnd(':'); $kit = (Split-Path -Qualifier (Get-KitRaiz)).TrimEnd(':')
    $usb = @{}
    foreach ($d in @(Get-Disk -ErrorAction SilentlyContinue | Where-Object { $_.BusType -eq 'USB' })) { foreach ($p in @(Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter })) { $usb[[string]$p.DriveLetter] = [string]$d.FriendlyName } }
    foreach ($v in @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.Size -gt 0 })) {
        $l = [string]$v.DriveLetter
        if ($l -eq $sistema -or $l -eq $kit) { continue }
        if ($v.DriveType -eq 'Removable' -or $usb.ContainsKey($l)) { [pscustomobject]@{ Letra = $l; Nombre = $(if ($usb[$l]) { $usb[$l] } else { [string]$v.FileSystemLabel }); Total = [int64]$v.Size; Libre = [int64]$v.SizeRemaining } }
    }
}
$cand = @(Get-Candidatas)
Write-Output "  $($E.Lupa) Controladores USB del equipo:"
foreach ($c in @(Get-PnpDevice -Class USB -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'Host Controller|xHCI|Controlador de host' })) { Write-Output "    · $($c.FriendlyName)" }
Write-Output "  $($E.Lupa) Dispositivos USB de almacenamiento que se pueden medir (no el disco de Windows ni el del kit):"
if (-not $cand.Count) { Exit-Kit 'Cancelado' 'No hay ningún pendrive o disco USB conectado que se pueda medir. Conecta uno en el puerto que quieras probar.' }
foreach ($c in $cand) { Write-Output ("    {0}:  {1} · {2} · {3} libres" -f $c.Letra, $(if ($c.Nombre) { $c.Nombre } else { 'sin nombre' }), (Format-Tam $c.Total), (Format-Tam $c.Libre)) }
if ($SoloAnalizar) { Write-Output "`n  $($E.Info) Solo análisis: no se ha escrito nada."; return }

function Test-Velocidad($letra, [int]$mb, [bool]$expulsarCache) {
    $ruta = Join-Path "${letra}:\" 'Nitrit0_VelocidadUSB.tmp'
    $buf = New-Object byte[] 1MB; (New-Object Security.Cryptography.RNGCryptoServiceProvider).GetBytes($buf)   # datos aleatorios: los controladores no los pueden comprimir
    $r = [ordered]@{ Escritura = 0.0; Lectura = 0.0; LecturaFiable = $false }
    try {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $fs = New-Object IO.FileStream($ruta, 'Create', 'Write', 'None', 1MB, 'WriteThrough')
        for ($i = 0; $i -lt $mb; $i++) { $fs.Write($buf, 0, $buf.Length) }
        $fs.Flush($true); $fs.Dispose(); $sw.Stop()
        $r.Escritura = [math]::Round($mb / [math]::Max($sw.Elapsed.TotalSeconds, 0.001), 1)
        # Sin expulsar la caché de Windows la lectura sale de la RAM y se infla: se desmonta el volumen (solo con administrador); el siguiente acceso lo vuelve a montar solo
        if ($expulsarCache) {
            & (Join-Path $env:SystemRoot 'System32\fsutil.exe') volume dismount "${letra}:" 2>&1 | Out-Null
            $r.LecturaFiable = ($LASTEXITCODE -eq 0)
        }
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $fs = New-Object IO.FileStream($ruta, 'Open', 'Read', 'Read', 1MB, 'SequentialScan')
        $leido = 0; while (($n = $fs.Read($buf, 0, $buf.Length)) -gt 0) { $leido += $n }
        $fs.Dispose(); $sw.Stop()
        $r.Lectura = [math]::Round(($leido / 1MB) / [math]::Max($sw.Elapsed.TotalSeconds, 0.001), 1)
    } finally { if ($fs) { try { $fs.Dispose() } catch { } }; Remove-Item -LiteralPath $ruta -Force -ErrorAction SilentlyContinue }
    [pscustomobject]$r
}
function Get-Veredicto([double]$lec, [bool]$fiable) {
    if (-not $fiable) { return 'lectura no fiable (sin administrador no se puede vaciar la caché de Windows): fíate solo de la escritura' }
    if ($lec -ge 110) { return 'USB 3 (5 Gbps o más)' }
    if ($lec -ge 60) { return 'USB 3 con un dispositivo o cable que no da más' }
    if ($lec -ge 20) { return 'típico de USB 2.0 (o un dispositivo USB 3 lento)' }
    if ($lec -ge 5) { return 'MUY lento: USB 2.0 con problemas, hub o cable malo, o dispositivo en mal estado' }
    'casi inutilizable: USB 1.1, puerto o cable defectuoso'
}

$esAdmin = Test-EsAdmin
$resultados = New-Object Collections.Generic.List[object]
$puerto = 0
do {
    $cand = @(Get-Candidatas)
    if ($Unidad) { $sel = $cand | Where-Object { $_.Letra -eq $Unidad.ToUpper() } | Select-Object -First 1; if (-not $sel) { Exit-Kit 'Error' "${Unidad}: no es un dispositivo USB que se pueda medir (¿es el disco de Windows o el del kit?)." } }
    elseif ($SinPreguntas) { Exit-Kit 'Error' 'Con -SinPreguntas hay que indicar -Unidad <letra>.' }
    elseif ($cand.Count -eq 1) { $sel = $cand[0] }
    else {
        $f = New-Object Windows.Forms.Form; $f.Text = 'Velocidad del puerto USB'; $f.Size = New-Object Drawing.Size(720, 340); $f.StartPosition = 'CenterScreen'; $f.TopMost = $true; $f.Font = New-Object Drawing.Font('Segoe UI', 9.5)
        $t = New-Object Windows.Forms.Label; $t.Text = 'Qué dispositivo mides'; $t.Font = New-Object Drawing.Font('Segoe UI Semibold', 14); $t.AutoSize = $true; $t.Location = New-Object Drawing.Point(20, 14)
        $lv = New-Object Windows.Forms.ListView; $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.MultiSelect = $false; $lv.Location = New-Object Drawing.Point(20, 56); $lv.Size = New-Object Drawing.Size(660, 170)
        foreach ($c in @(@('Unidad', 70), @('Nombre', 330), @('Tamaño', 110), @('Libre', 110))) { [void]$lv.Columns.Add($c[0], $c[1]) }
        foreach ($x in $cand) { $i = New-Object Windows.Forms.ListViewItem("$($x.Letra):"); [void]$i.SubItems.Add($(if ($x.Nombre) { $x.Nombre } else { '(sin nombre)' })); [void]$i.SubItems.Add((Format-Tam $x.Total)); [void]$i.SubItems.Add((Format-Tam $x.Libre)); $i.Tag = $x; [void]$lv.Items.Add($i) }
        $lv.Items[0].Selected = $true
        $ok = New-Object Windows.Forms.Button; $ok.Text = 'Medir'; $ok.Size = New-Object Drawing.Size(140, 36); $ok.Location = New-Object Drawing.Point(540, 246); $ok.DialogResult = 'OK'
        $no = New-Object Windows.Forms.Button; $no.Text = 'Cancelar'; $no.Size = New-Object Drawing.Size(140, 36); $no.Location = New-Object Drawing.Point(390, 246); $no.DialogResult = 'Cancel'
        $f.Controls.AddRange(@($t, $lv, $ok, $no)); $f.AcceptButton = $ok; $f.CancelButton = $no
        if ($f.ShowDialog() -ne 'OK' -or -not $lv.SelectedItems.Count) { break }
        $sel = $lv.SelectedItems[0].Tag
    }
    if ($sel.Libre -lt (($MB + 16) * 1MB)) { Write-Output "  $($E.Aviso) $($sel.Letra): tiene poco espacio libre ($(Format-Tam $sel.Libre)): libera espacio o baja -MB."; break }
    $puerto++
    Write-Output "  $($E.Reloj) Puerto $puerto · $($sel.Letra): ($(if ($sel.Nombre) { $sel.Nombre } else { 'sin nombre' })): escribiendo y leyendo $MB MB…"
    $m = Test-Velocidad $sel.Letra $MB $esAdmin
    $veredicto = Get-Veredicto $m.Lectura $m.LecturaFiable
    Write-Output ("    Escritura {0:N1} MB/s · Lectura {1:N1} MB/s -> {2}" -f $m.Escritura, $m.Lectura, $veredicto)
    $resultados.Add([pscustomobject]@{ Puerto = $puerto; Unidad = $sel.Letra; Escritura = $m.Escritura; Lectura = $m.Lectura; Veredicto = $veredicto })
    Write-Log "Prueba_Puertos_USB puerto $puerto $($sel.Letra): escritura $($m.Escritura) MB/s, lectura $($m.Lectura) MB/s"
    $otro = $false
    if (-not $SinPreguntas -and -not $Unidad) { $otro = [bool](Confirm-Accion "Puerto $puerto medido: lectura $($m.Lectura) MB/s ($veredicto).`n`n¿Quieres probar otro puerto? Cambia el dispositivo de puerto, espera a que Windows lo reconozca y pulsa Sí." 'Nitrit0 Kit' -Siempre) }
} while ($otro)

if (-not $resultados.Count) { Exit-Kit 'Cancelado' 'No se ha medido nada.' }
Write-Output "`n$($E.OK) Resumen de puertos medidos:"
foreach ($r in $resultados) { Write-Output ("    Puerto {0} ({1}:)  escritura {2:N1} MB/s · lectura {3:N1} MB/s · {4}" -f $r.Puerto, $r.Unidad, $r.Escritura, $r.Lectura, $r.Veredicto) }
$lentos = @($resultados | Where-Object { $_.Lectura -lt 20 })
if ($resultados.Count -gt 1 -and ($resultados | Measure-Object Lectura -Maximum).Maximum -ge 60 -and $lentos.Count) { Write-Output "  $($E.Aviso) Hay puertos mucho más lentos que otros con el mismo dispositivo: los de $(($lentos.Puerto | ForEach-Object { "puerto $_" }) -join ', ') pueden ser USB 2.0 o estar mal." }
Write-Output "  $($E.Info) Mide el conjunto puerto + cable + dispositivo. Si todos salen lentos, prueba con otro dispositivo USB 3 antes de culpar a los puertos."
