# =====================================================================
#  Programas_Inicio.ps1 - Qué se carga al encender el equipo (Nitrit0)
#  Lista los programas de inicio (registro y carpetas de Inicio) y las tareas programadas al iniciar sesión.
#  Deja elegir cuáles desactivar. Usa el mismo interruptor que el Administrador de tareas: no borra nada
#  y se deshace desde Mantenimiento > Deshacer cambios.
#  Parámetro: -SoloListar (no pregunta ni cambia nada)
# =====================================================================
[CmdletBinding()]
param([Alias('SoloAnalizar')][switch]$SoloListar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
$cv = 'SOFTWARE\Microsoft\Windows\CurrentVersion'
$ap = "$cv\Explorer\StartupApproved"
$fuentes = @(
    @{ Amb = 'Todos los usuarios'; Run = "HKLM:\$cv\Run"; Ap = "HKLM:\$ap\Run" }
    @{ Amb = 'Todos (32 bits)'; Run = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; Ap = "HKLM:\$ap\Run32" }
    @{ Amb = "Usuario $env:USERNAME"; Run = "HKCU:\$cv\Run"; Ap = "HKCU:\$ap\Run" }
    @{ Amb = 'Todos los usuarios'; Dir = [Environment]::GetFolderPath('CommonStartup'); Ap = "HKLM:\$ap\StartupFolder" }
    @{ Amb = "Usuario $env:USERNAME"; Dir = [Environment]::GetFolderPath('Startup'); Ap = "HKCU:\$ap\StartupFolder" }
)

# Activo si no hay marca o si su primer byte es par (02 = activado, 03 = desactivado)
function Test-Activo([string]$clave, [string]$nombre) {
    try { $b = (Get-Item -LiteralPath $clave -ErrorAction Stop).GetValue($nombre, $null); if ($b -is [byte[]] -and $b.Length) { return ($b[0] % 2) -eq 0 } } catch { }
    $true
}

$items = @()
foreach ($f in $fuentes) {
    if ($f.Run) {
        if (-not (Test-Path -LiteralPath $f.Run)) { continue }
        $k = Get-Item -LiteralPath $f.Run
        foreach ($n in $k.GetValueNames()) { if ($n) { $items += [pscustomobject]@{ Nombre = $n; Ambito = $f.Amb; Orden = [string]$k.GetValue($n); Ap = $f.Ap; Activo = (Test-Activo $f.Ap $n) } } }
    } elseif ($f.Dir -and (Test-Path -LiteralPath $f.Dir)) {
        foreach ($a in Get-ChildItem -LiteralPath $f.Dir -File -Force -ErrorAction SilentlyContinue) { if ($a.Name -ne 'desktop.ini') { $items += [pscustomobject]@{ Nombre = $a.Name; Ambito = "$($f.Amb) (carpeta Inicio)"; Orden = $a.FullName; Ap = $f.Ap; Activo = (Test-Activo $f.Ap $a.Name) } } }
    }
}

Write-Output "  $($E.Lupa) Programas que se cargan al iniciar ($(@($items | Where-Object Activo).Count) activos de $($items.Count)):"
foreach ($i in $items | Sort-Object @{ Expression = 'Activo'; Descending = $true }, Nombre) {
    Write-Output "    $(if ($i.Activo) { $E.OK } else { $E.Info + ' (desactivado)' }) $($i.Nombre)  ·  $($i.Ambito)"
    Write-Output "         $($i.Orden)"
}

$tareas = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.State -ne 'Disabled' -and $_.TaskPath -notlike '\Microsoft\*' -and ($_.Triggers | Where-Object { $_.CimClass.CimClassName -in 'MSFT_TaskLogonTrigger', 'MSFT_TaskBootTrigger' }) })
if ($tareas.Count) {
    Write-Output "`n  $($E.Lupa) Tareas programadas al arrancar o iniciar sesión (solo se listan):"
    foreach ($t in $tareas) { Write-Output "    $($E.Info) $($t.TaskName)  ·  $(@($t.Actions | ForEach-Object { $_.Execute }) -join ', ')" }
}

$activos = @($items | Where-Object Activo)
if ($SoloListar -or -not $activos.Count) { Write-Log "Programas de inicio listados ($($items.Count))"; return }

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$form = New-Object Windows.Forms.Form
$form.Text = 'Programas de inicio'; $form.Size = New-Object Drawing.Size(640, 480); $form.StartPosition = 'CenterScreen'; $form.Font = New-Object Drawing.Font('Segoe UI', 9.5); $form.TopMost = $true
$lbl = New-Object Windows.Forms.Label; $lbl.Dock = 'Top'; $lbl.Height = 46; $lbl.Padding = New-Object Windows.Forms.Padding(8)
$lbl.Text = 'Marca lo que NO debe cargarse al encender. No se desinstala nada y se puede deshacer. En la duda, déjalo sin marcar (antivirus, drivers de audio y táctil).'
$lista = New-Object Windows.Forms.CheckedListBox; $lista.Dock = 'Fill'; $lista.CheckOnClick = $true
foreach ($i in $activos) { [void]$lista.Items.Add("$($i.Nombre)   ($($i.Ambito))") }
$btn = New-Object Windows.Forms.Button; $btn.Text = 'Desactivar los marcados'; $btn.Dock = 'Bottom'; $btn.Height = 40; $btn.DialogResult = 'OK'
$form.Controls.AddRange(@($lista, $lbl, $btn)); $form.AcceptButton = $btn
if ($form.ShowDialog() -ne 'OK' -or -not $lista.CheckedIndices.Count) { Exit-Kit 'Cancelado' 'No se ha cambiado nada.' }

[void](Start-OperacionSegura 'Programas de inicio' -SinPuntoRestauracion)
$n = 0
foreach ($ix in $lista.CheckedIndices) {
    $i = $activos[$ix]
    try { Set-ValorSeguro $i.Ap $i.Nombre ([byte[]](3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) 'Binary'; $n++; Write-Output "  $($E.OK) Desactivado: $($i.Nombre)" }
    catch { Write-Output "  $($E.Error) No se pudo desactivar $($i.Nombre): $($_.Exception.Message)" }
}
Write-Output "`n  $($E.Info) $n programa(s) dejarán de cargarse en el próximo arranque. Para volver atrás: Mantenimiento > Deshacer cambios."
Write-Log "Programas de inicio: $n desactivados"
