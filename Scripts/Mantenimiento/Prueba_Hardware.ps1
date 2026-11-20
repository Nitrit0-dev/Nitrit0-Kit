# =====================================================================
#  Prueba_Hardware.ps1 - Prueba manual de un portátil o sobremesa (Nitrit0)
#  Pantalla (píxeles muertos), altavoces (izquierdo/derecho), micrófono (graba y reproduce), cámara, teclado y batería.
#  El técnico prueba cada cosa y marca «Bien» o «Falla»; el resultado queda en el registro del kit.
#  No cambia nada en el equipo.
# =====================================================================
[CmdletBinding()]
param()
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
if (-not ('NitMci' -as [type])) {
    Add-Type -Name NitMci -Namespace '' -MemberDefinition '[DllImport("winmm.dll", CharSet = CharSet.Auto)] public static extern int mciSendString(string orden, System.Text.StringBuilder resp, int largo, IntPtr h);'
}

# --- Batería (solo lectura) ---
$bateria = 'No tiene batería (sobremesa) o no informa de su capacidad'
try {
    $dis = (Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction Stop | Select-Object -First 1).DesignedCapacity
    $act = (Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction Stop | Select-Object -First 1).FullChargedCapacity
    if ($dis -gt 0 -and $act -gt 0) { $pct = [math]::Min(100, [math]::Round(100 * $act / $dis)); $bateria = "Salud $pct % ($act de $dis mWh)$(if ($pct -lt 60) { ' · conviene cambiarla' })" }
} catch { }

function Test-Pixeles {
    $colores = @([Drawing.Color]::Black, [Drawing.Color]::White, [Drawing.Color]::Red, [Drawing.Color]::Lime, [Drawing.Color]::Blue)
    $f = New-Object Windows.Forms.Form
    $f.FormBorderStyle = 'None'; $f.StartPosition = 'Manual'; $f.Bounds = [Windows.Forms.Screen]::PrimaryScreen.Bounds; $f.TopMost = $true; $f.BackColor = $colores[0]; $f.Tag = 0
    $f.Add_Click({ $this.Tag = [int]$this.Tag + 1; if ($this.Tag -ge $colores.Count) { $this.Close() } else { $this.BackColor = $colores[$this.Tag] } })
    $f.Add_KeyDown({ if ($_.KeyCode -eq 'Escape') { $this.Close() } })
    [void]$f.ShowDialog()
}

function Test-Altavoces {
    # Un segundo de tono por el altavoz izquierdo y otro por el derecho
    $hz = 44100; $ms = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter($ms); $n = $hz * 2
    $w.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $w.Write([int](36 + $n * 4)); $w.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
    $w.Write([int]16); $w.Write([int16]1); $w.Write([int16]2); $w.Write([int]$hz); $w.Write([int]($hz * 4)); $w.Write([int16]4); $w.Write([int16]16)
    $w.Write([Text.Encoding]::ASCII.GetBytes('data')); $w.Write([int]($n * 4))
    for ($i = 0; $i -lt $n; $i++) { $v = [int16](9000 * [math]::Sin(2 * [math]::PI * 440 * $i / $hz)); if ($i -lt $hz) { $w.Write($v); $w.Write([int16]0) } else { $w.Write([int16]0); $w.Write($v) } }
    $ms.Position = 0; (New-Object Media.SoundPlayer($ms)).PlaySync()
}

function Test-Microfono {
    $wav = Join-Path $env:TEMP 'nitrit0_micro.wav'; Remove-Item -LiteralPath $wav -Force -ErrorAction SilentlyContinue
    if ([NitMci]::mciSendString('open new Type waveaudio Alias nitmic', $null, 0, [IntPtr]::Zero) -ne 0) { [void][Windows.Forms.MessageBox]::Show('No se ha encontrado ningún micrófono.', 'Micrófono'); return }
    [void][NitMci]::mciSendString('record nitmic', $null, 0, [IntPtr]::Zero)
    Start-Sleep -Seconds 4
    [void][NitMci]::mciSendString("save nitmic `"$wav`"", $null, 0, [IntPtr]::Zero); [void][NitMci]::mciSendString('close nitmic', $null, 0, [IntPtr]::Zero)
    if (Test-Path -LiteralPath $wav) { (New-Object Media.SoundPlayer($wav)).PlaySync(); Remove-Item -LiteralPath $wav -Force -ErrorAction SilentlyContinue }
}

function Test-Teclado {
    $exe = Resolve-ExeKit 'Perifericos\keyboardtestutility.exe'
    if (Test-Path -LiteralPath $exe) { Start-Process $exe } else { [void][Windows.Forms.MessageBox]::Show('Falta Apps\Perifericos\keyboardtestutility.exe. Abre el Bloc de notas y pulsa todas las teclas.', 'Teclado') }
}

$pruebas = @(
    @{ N = 'Pantalla'; D = 'Pantalla completa en negro, blanco, rojo, verde y azul. Clic para cambiar de color, Esc para salir. Busca puntos que no cambian.'; A = { Test-Pixeles } }
    @{ N = 'Altavoces'; D = 'Suena un tono primero por el altavoz izquierdo y después por el derecho.'; A = { Test-Altavoces } }
    @{ N = 'Micrófono'; D = 'Graba 4 segundos (habla al pulsar) y los reproduce a continuación.'; A = { Test-Microfono } }
    @{ N = 'Cámara'; D = 'Abre la app Cámara de Windows. Comprueba imagen y enfoque, y ciérrala.'; A = { Start-Process 'microsoft.windows.camera:' } }
    @{ N = 'Teclado'; D = 'Abre el test de teclado del kit. Pulsa todas las teclas, también Fn y las del panel táctil.'; A = { Test-Teclado } }
)

$form = New-Object Windows.Forms.Form
$form.Text = 'Prueba de hardware'; $form.ClientSize = New-Object Drawing.Size(720, (96 + 64 * $pruebas.Count)); $form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI', 9.5); $form.FormBorderStyle = 'FixedDialog'; $form.MaximizeBox = $false
$lb = New-Object Windows.Forms.Label; $lb.Text = "Batería: $bateria"; $lb.Location = New-Object Drawing.Point(16, 12); $lb.Size = New-Object Drawing.Size(688, 22); $form.Controls.Add($lb)
$estado = @{}; $y = 44
foreach ($p in $pruebas) {
    $t = New-Object Windows.Forms.Label; $t.Text = $p.N; $t.Font = New-Object Drawing.Font('Segoe UI Semibold', 10.5); $t.Location = New-Object Drawing.Point(16, $y); $t.Size = New-Object Drawing.Size(110, 22)
    $d = New-Object Windows.Forms.Label; $d.Text = $p.D; $d.Location = New-Object Drawing.Point(16, ($y + 22)); $d.Size = New-Object Drawing.Size(420, 36); $d.ForeColor = [Drawing.Color]::DimGray
    $r = New-Object Windows.Forms.Label; $r.Text = 'Sin probar'; $r.Location = New-Object Drawing.Point(130, ($y + 2)); $r.Size = New-Object Drawing.Size(120, 20); $r.ForeColor = [Drawing.Color]::Gray
    $estado[$p.N] = $r
    $bp = New-Object Windows.Forms.Button; $bp.Text = 'Probar'; $bp.Location = New-Object Drawing.Point(448, ($y + 6)); $bp.Size = New-Object Drawing.Size(84, 34); $bp.Tag = $p.A
    $bp.Add_Click({ $this.Enabled = $false; try { & $this.Tag } catch { [void][Windows.Forms.MessageBox]::Show("No se pudo hacer la prueba: $($_.Exception.Message)", 'Prueba de hardware') }; $this.Enabled = $true })
    $bb = New-Object Windows.Forms.Button; $bb.Text = 'Bien'; $bb.Location = New-Object Drawing.Point(540, ($y + 6)); $bb.Size = New-Object Drawing.Size(76, 34); $bb.Tag = $r
    $bb.Add_Click({ $this.Tag.Text = 'Bien'; $this.Tag.ForeColor = [Drawing.Color]::SeaGreen })
    $bf = New-Object Windows.Forms.Button; $bf.Text = 'Falla'; $bf.Location = New-Object Drawing.Point(624, ($y + 6)); $bf.Size = New-Object Drawing.Size(76, 34); $bf.Tag = $r
    $bf.Add_Click({ $this.Tag.Text = 'Falla'; $this.Tag.ForeColor = [Drawing.Color]::Firebrick })
    $form.Controls.AddRange(@($t, $r, $d, $bp, $bb, $bf)); $y += 64
}
$fin = New-Object Windows.Forms.Button; $fin.Text = 'Terminar y guardar el resultado'; $fin.Location = New-Object Drawing.Point(16, ($y + 4)); $fin.Size = New-Object Drawing.Size(688, 38); $fin.DialogResult = 'OK'
$form.Controls.Add($fin)
if ($form.ShowDialog() -ne 'OK') { Exit-Kit 'Cancelado' 'Cerrada sin pulsar «Terminar y guardar»: no se registra ningún resultado.' }   # antes se guardaba todo «Sin probar» al cerrar con la X

Write-Output "  $($E.Info) Batería: $bateria"
$fallan = 0; $txt = @()
foreach ($p in $pruebas) {
    $v = $estado[$p.N].Text; $txt += "$($p.N)=$v"
    $ico = switch ($v) { 'Bien' { $E.OK } 'Falla' { $fallan++; $E.Error } default { $E.Aviso } }
    Write-Output "  $ico $($p.N): $v"
}
Write-Log "Prueba de hardware: $($txt -join '; '); Batería: $bateria"
if ($fallan) { exit 1 }   # 1 = hay pruebas marcadas «Falla» (resultado del diagnóstico, no un error del script)
