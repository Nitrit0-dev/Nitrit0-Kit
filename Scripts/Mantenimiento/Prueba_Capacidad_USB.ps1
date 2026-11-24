# =====================================================================
#  Prueba_Capacidad_USB.ps1 - Comprueba si un pendrive, tarjeta o disco externo guarda de verdad lo que dice (Nitrit0)
#  Los falsificados anuncian «1 TB» y guardan solo unos GB: lo que pasa de ahí se pierde o pisa lo anterior.
#  Cómo: llena el ESPACIO LIBRE con archivos de prueba (cada bloque de 1 MB lleva su número), los vuelve a leer y compara.
#  Los archivos de prueba van en una carpeta propia y se borran al terminar; tus archivos no se tocan, pero en un dispositivo
#  falsificado lo que ya tuviera guardado puede estropearse: haz copia antes. Solo se prueba el espacio libre.
#  Nunca prueba el disco de Windows ni el disco donde está el kit. Tarda según la velocidad (de 5 a 10 min por cada 10 GB en un pendrive básico).
#  Parámetros: -SoloAnalizar (lista los dispositivos candidatos y no escribe nada) · -Unidad <letra> -SinPreguntas (sin ventanas)
# =====================================================================
[CmdletBinding()]
param([Alias('Simular', 'SoloMirar')][switch]$SoloAnalizar, [ValidatePattern('^[A-Za-z]$')][string]$Unidad, [switch]$SinPreguntas)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
function Format-Tam([int64]$b) { if ($b -ge 1GB) { '{0:N1} GB' -f ($b / 1GB) } elseif ($b -ge 1MB) { '{0:N0} MB' -f ($b / 1MB) } else { '{0:N0} KB' -f ($b / 1KB) } }

# USB (por bus) o extraíbles; nunca la unidad del sistema ni la del kit
function Get-Candidatas {
    $sistema = $env:SystemDrive.TrimEnd(':'); $kit = (Split-Path -Qualifier (Get-KitRaiz)).TrimEnd(':')
    $usb = @{}
    foreach ($d in @(Get-Disk -ErrorAction SilentlyContinue | Where-Object { $_.BusType -eq 'USB' })) { foreach ($p in @(Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter })) { $usb[[string]$p.DriveLetter] = $true } }
    foreach ($v in @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.Size -gt 0 })) {
        $l = [string]$v.DriveLetter
        if ($l -eq $sistema -or $l -eq $kit) { continue }
        if ($v.DriveType -eq 'Removable' -or $usb.ContainsKey($l)) { [pscustomobject]@{ Letra = $l; Etiqueta = [string]$v.FileSystemLabel; Total = [int64]$v.Size; Libre = [int64]$v.SizeRemaining } }
    }
}
$cand = @(Get-Candidatas)
Write-Output "  $($E.Lupa) Dispositivos que se pueden probar (USB o extraíbles; no el disco de Windows ni el del kit):"
if (-not $cand.Count) { Exit-Kit 'Cancelado' 'No hay ningún pendrive, tarjeta o disco externo conectado que se pueda probar.' }
foreach ($c in $cand) { Write-Output ("    {0}:  {1} · {2} en total · {3} libres" -f $c.Letra, $(if ($c.Etiqueta) { $c.Etiqueta } else { 'sin etiqueta' }), (Format-Tam $c.Total), (Format-Tam $c.Libre)) }
if ($SoloAnalizar) { Write-Output "`n  $($E.Info) Solo análisis: no se ha escrito nada."; return }

# --- Elegir dispositivo ---
if ($Unidad) { $sel = $cand | Where-Object { $_.Letra -eq $Unidad.ToUpper() } | Select-Object -First 1; if (-not $sel) { Exit-Kit 'Error' "${Unidad}: no es un dispositivo que se pueda probar (¿es el disco de Windows o el del kit?)." } }
elseif ($SinPreguntas) { Exit-Kit 'Error' 'Con -SinPreguntas hay que indicar -Unidad <letra>.' }
else {
    $f = New-Object Windows.Forms.Form; $f.Text = 'Prueba de capacidad real'; $f.Size = New-Object Drawing.Size(760, 380); $f.StartPosition = 'CenterScreen'; $f.TopMost = $true; $f.Font = New-Object Drawing.Font('Segoe UI', 9.5)
    $t = New-Object Windows.Forms.Label; $t.Text = 'Qué dispositivo quieres comprobar'; $t.Font = New-Object Drawing.Font('Segoe UI Semibold', 14); $t.AutoSize = $true; $t.Location = New-Object Drawing.Point(20, 14)
    $lv = New-Object Windows.Forms.ListView; $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.MultiSelect = $false; $lv.Location = New-Object Drawing.Point(20, 56); $lv.Size = New-Object Drawing.Size(704, 190)
    foreach ($c in @(@('Unidad', 70), @('Nombre', 260), @('Tamaño', 120), @('Libre', 120))) { [void]$lv.Columns.Add($c[0], $c[1]) }
    foreach ($x in $cand) { $i = New-Object Windows.Forms.ListViewItem("$($x.Letra):"); [void]$i.SubItems.Add($(if ($x.Etiqueta) { $x.Etiqueta } else { '(sin etiqueta)' })); [void]$i.SubItems.Add((Format-Tam $x.Total)); [void]$i.SubItems.Add((Format-Tam $x.Libre)); $i.Tag = $x; [void]$lv.Items.Add($i) }
    $lv.Items[0].Selected = $true
    $n = New-Object Windows.Forms.Label; $n.Text = 'Se llena el espacio libre con archivos de prueba y se borran al terminar. Haz copia de lo importante antes.'; $n.AutoSize = $true; $n.Location = New-Object Drawing.Point(22, 262)
    $ok = New-Object Windows.Forms.Button; $ok.Text = 'Probar'; $ok.Size = New-Object Drawing.Size(140, 36); $ok.Location = New-Object Drawing.Point(584, 292); $ok.DialogResult = 'OK'
    $no = New-Object Windows.Forms.Button; $no.Text = 'Cancelar'; $no.Size = New-Object Drawing.Size(140, 36); $no.Location = New-Object Drawing.Point(434, 292); $no.DialogResult = 'Cancel'
    $f.Controls.AddRange(@($t, $lv, $n, $ok, $no)); $f.AcceptButton = $ok; $f.CancelButton = $no
    if ($f.ShowDialog() -ne 'OK' -or -not $lv.SelectedItems.Count) { Exit-Kit 'Cancelado' 'No se ha probado nada.' }
    $sel = $lv.SelectedItems[0].Tag
}
$L = $sel.Letra; $bloque = 1MB; $porArchivo = 256
$nBloques = [int64][math]::Floor(($sel.Libre - 32MB) / $bloque)
if ($nBloques -lt 8) { Exit-Kit 'Cancelado' "${L}: tiene muy poco espacio libre ($(Format-Tam $sel.Libre)): libera espacio y vuelve a probar." }
if (-not $SinPreguntas -and -not (Confirm-Accion "Se van a escribir unos $(Format-Tam ($nBloques * $bloque)) de archivos de prueba en ${L}: ($(if ($sel.Etiqueta) { $sel.Etiqueta } else { 'sin etiqueta' })) y se borrarán al terminar.`n`nTus archivos no se tocan, pero si el dispositivo es falsificado lo que ya tenga guardado podría estropearse.`n`n¿Hacer copia de lo importante antes y continuar?" 'Nitrit0 Kit' -Siempre)) { Exit-Kit 'Cancelado' 'No se ha probado nada.' }

$dir = Join-Path "${L}:\" 'Nitrit0_PruebaCapacidad'
# Restos de una prueba anterior cancelada a la fuerza (el «finally» no corre al cancelar): son solo archivos .bin de esta herramienta
if (Test-Path -LiteralPath $dir -PathType Container) { Get-ChildItem -LiteralPath $dir -Filter '*.bin' -File -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue; Remove-Item -LiteralPath $dir -Force -ErrorAction SilentlyContinue }
$md5 = [Security.Cryptography.MD5]::Create()
$rng = New-Object Security.Cryptography.RNGCryptoServiceProvider
$buf = New-Object byte[] $bloque; $rng.GetBytes($buf)
$nonce = New-Object byte[] 8; $rng.GetBytes($nonce); [Buffer]::BlockCopy($nonce, 0, $buf, 8, 8)   # distingue este intento de restos de uno anterior
$hashes = New-Object 'string[]' $nBloques
$escritos = $nBloques; $malos = 0; $primerMalo = -1; $leidos = 0
$t0 = Get-Date
try {
    New-Item -ItemType Directory -Force $dir | Out-Null
    Write-Output "  $($E.Reloj) Escribiendo en ${L}: ($(Format-Tam ($nBloques * $bloque)) en archivos de $porArchivo MB)…"
    $fs = $null
    for ($i = 0; $i -lt $nBloques; $i++) {
        try {
            if ($i % $porArchivo -eq 0) { if ($fs) { $fs.Flush($true); $fs.Dispose() }; $fs = New-Object IO.FileStream((Join-Path $dir ('{0:D6}.bin' -f [int]($i / $porArchivo))), 'Create', 'Write', 'None', $bloque, 'WriteThrough') }
            [Buffer]::BlockCopy([BitConverter]::GetBytes([int64]$i), 0, $buf, 0, 8)
            $hashes[$i] = [BitConverter]::ToString($md5.ComputeHash($buf))
            $fs.Write($buf, 0, $bloque)
        } catch [IO.IOException] { $escritos = $i; Write-Output "  $($E.Aviso) El dispositivo dejó de aceptar datos tras $(Format-Tam ($i * $bloque)) ($($_.Exception.Message))."; break }
        if ($i % 128 -eq 0) { Write-Progreso ([int]$i) ([int]$nBloques) "Escribiendo ${L}: $(Format-Tam ($i * $bloque))" }
    }
    if ($fs) { try { $fs.Flush($true) } catch { }; $fs.Dispose(); $fs = $null }
    if ($escritos -lt 1) { Exit-Kit 'Error' "No se pudo escribir nada en ${L}: (¿protegido contra escritura o con errores?)." }

    # Con poco volumen respecto a la RAM, Windows puede servir la lectura desde su caché: se pide desconectar y reconectar para que lea del dispositivo
    $ram = [int64](Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).TotalPhysicalMemory
    if (-not $SinPreguntas -and $ram -gt 0 -and ($escritos * $bloque) -lt ($ram * 0.7)) {
        [void][Windows.Forms.MessageBox]::Show("Para que la comprobación sea fiable:`n`n1. Expulsa el dispositivo con «Quitar hardware de forma segura».`n2. Vuelve a conectarlo.`n3. Pulsa Aceptar aquí.", 'Nitrit0 Kit', 'OK', 'Information')
        $nueva = @(Get-Volume | Where-Object { $_.DriveLetter -and (Test-Path -LiteralPath "$($_.DriveLetter):\Nitrit0_PruebaCapacidad") } | Select-Object -First 1)
        if ($nueva.Count) { $dir = Join-Path "$($nueva[0].DriveLetter):\" 'Nitrit0_PruebaCapacidad' } else { Write-Output "  $($E.Aviso) No encuentro los archivos de prueba tras reconectar: se lee sin reconectar (el resultado puede ser menos fiable)." }
    }

    Write-Output "  $($E.Lupa) Leyendo y comparando…"
    $leer = New-Object byte[] $bloque
    $archivos = @(Get-ChildItem -LiteralPath $dir -Filter '*.bin' -File | Sort-Object Name)
    $i = 0
    foreach ($a in $archivos) {
        $rs = $null
        try { $rs = New-Object IO.FileStream($a.FullName, 'Open', 'Read', 'Read', $bloque, 'SequentialScan') } catch { }
        for ($k = 0; $k -lt $porArchivo -and $i -lt $escritos; $k++, $i++) {
            $bien = $false
            if ($rs) { try { $n = 0; while ($n -lt $bloque) { $r = $rs.Read($leer, $n, $bloque - $n); if ($r -le 0) { break }; $n += $r }; $bien = ($n -eq $bloque -and [BitConverter]::ToString($md5.ComputeHash($leer)) -eq $hashes[$i]) } catch { } }
            $leidos++
            if (-not $bien) { $malos++; if ($primerMalo -lt 0) { $primerMalo = $i } }
            if ($i % 128 -eq 0) { Write-Progreso ([int]$i) ([int]$escritos) "Comprobando ${L}: $(Format-Tam ($i * $bloque))" }
        }
        if ($rs) { $rs.Dispose() }
    }
} finally {
    if ($fs) { try { $fs.Dispose() } catch { } }
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $dir) { Write-Output "  $($E.Aviso) No se pudo borrar la carpeta de prueba ${dir}: bórrala a mano." }
}

$min = [math]::Round(((Get-Date) - $t0).TotalMinutes, 1)
$probado = Format-Tam ($leidos * $bloque)
if ($malos -eq 0 -and $leidos -gt 0) {
    Write-Output "`n$($E.OK) Capacidad confirmada: se escribieron y leyeron bien $probado de los $(Format-Tam $sel.Libre) libres de ${L}: ($(Format-Tam $sel.Total) anunciados) en $min min."
    Write-Output "  $($E.Info) Solo se prueba el espacio libre: si el dispositivo estaba casi lleno, la parte ocupada no se ha comprobado."
    Write-Log "Prueba_Capacidad_USB ${L}: OK $probado"
} else {
    $realGb = if ($primerMalo -gt 0) { Format-Tam ($primerMalo * $bloque) } else { 'casi nada' }
    Write-Output "`n$($E.Error) POSIBLE FALSIFICACIÓN en ${L}: de $probado comprobados, $malos bloques de 1 MB no coinciden."
    Write-Output "  $($E.Info) Los datos dejan de ser fiables a partir de unos $realGb (anunciados: $(Format-Tam $sel.Total)). No guardes nada importante en este dispositivo."
    Write-Log "Prueba_Capacidad_USB ${L}: FALLO $malos bloques, primero en $primerMalo"
    Exit-Kit 'Error' "Capacidad real inferior a la anunciada: fiable hasta unos $realGb de $(Format-Tam $sel.Total)."
}
