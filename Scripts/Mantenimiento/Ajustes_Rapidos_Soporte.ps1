# =====================================================================
#  Ajustes_Rapidos_Soporte.ps1 - Pocos ajustes de soporte que evitan sustos en equipos de clientes (Nitrit0)
#  Se ve cuáles ya están puestos y se eligen los que faltan. Todo se registra y se deshace con «Deshacer cambios».
#    · Sin autoejecución en USB y unidades (corta el malware que arranca solo al conectar un pendrive)
#    · Windows Update no instala drivers (para que no pise los del fabricante que se instalaron a mano)
#    · Sin reinicio automático por actualizaciones con una sesión abierta (no pierde el trabajo del cliente)
#    · Apagar la hibernación y borrar hiberfil.sys (libera varios GB; sin marcar: también quita el inicio rápido)
#    · Servicio de Registro remoto desactivado (que nadie lea ni cambie el registro por red) y, sin marcar, el servicio de telemetría DiagTrack
#  No toca Defender, el firewall, UAC ni SmartScreen.
#  Parámetros: -SoloAnalizar (solo dice cuáles están puestos)  ·  -Aplicar <ids> (sin ventana; ids: autoplay, driverswu, sinreinicio, hibernacion, registroremoto, diagtrack)
# =====================================================================
[CmdletBinding()]
param(
    [Alias('Simular', 'SoloMirar')][switch]$SoloAnalizar,
    [ValidateSet('autoplay', 'driverswu', 'sinreinicio', 'hibernacion', 'registroremoto', 'diagtrack')][string[]]$Aplicar
)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E

function Get-InicioServicio([string]$n) { (Get-CimInstance Win32_Service -Filter "Name='$n'" -ErrorAction SilentlyContinue).StartMode }   # $null si no existe
function Get-Valor([string]$Ruta, [string]$Nombre) { try { (Get-ItemProperty -LiteralPath $Ruta -Name $Nombre -ErrorAction Stop).$Nombre } catch { $null } }
$rExplorer = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
$rWU = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$rAU = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
$rPower = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'

$ajustes = @(
    [pscustomobject]@{ Id = 'autoplay'; Nombre = 'Sin autoejecución en USB y unidades'; Marcado = $true
        Aviso = 'Al conectar un pendrive ya no se ejecuta nada solo. Los programas se abren a mano y todo lo demás funciona igual.'
        Puesto = { (Get-Valor $rExplorer 'NoDriveTypeAutoRun') -eq 255 }
        Poner = { Set-ValorSeguro $rExplorer 'NoDriveTypeAutoRun' 255 }; Admin = $true }
    [pscustomobject]@{ Id = 'driverswu'; Nombre = 'Windows Update no instala drivers'; Marcado = $false
        Aviso = 'Útil tras instalar los drivers del fabricante a mano. Contrapartida: los drivers dejan de llegar por Windows Update (se actualizan a mano o con las herramientas del kit).'
        Puesto = { (Get-Valor $rWU 'ExcludeWUDriversInQualityUpdate') -eq 1 }
        Poner = { Set-ValorSeguro $rWU 'ExcludeWUDriversInQualityUpdate' 1 }; Admin = $true }
    [pscustomobject]@{ Id = 'sinreinicio'; Nombre = 'Sin reinicio automático con una sesión abierta'; Marcado = $true
        Aviso = 'Windows Update no reinicia solo mientras haya alguien con la sesión iniciada: avisa y espera. Los parches se aplican igual al reiniciar tú.'
        Puesto = { (Get-Valor $rAU 'NoAutoRebootWithLoggedOnUsers') -eq 1 }
        Poner = { Set-ValorSeguro $rAU 'NoAutoRebootWithLoggedOnUsers' 1 }; Admin = $true }
    [pscustomobject]@{ Id = 'hibernacion'; Nombre = 'Apagar la hibernación (libera hiberfil.sys)'; Marcado = $false
        Aviso = 'Libera varios GB (el tamaño de la RAM), pero quita Hibernar y el inicio rápido de Windows. En portátiles no suele convenir. Para volver: powercfg /hibernate on.'
        Puesto = { (Get-Valor $rPower 'HibernateEnabled') -eq 0 }
        Poner = {
            & (Join-Path $env:SystemRoot 'System32\powercfg.exe') /hibernate off 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "powercfg /hibernate off devolvió el código $LASTEXITCODE" }
            Save-Informativo 'Hibernación desactivada (hiberfil.sys borrado)' 'Para volver a activarla: powercfg /hibernate on'
        }; Admin = $true }
    [pscustomobject]@{ Id = 'registroremoto'; Nombre = 'Servicio de Registro remoto desactivado'; Marcado = $true
        Aviso = 'Impide que otros equipos lean o cambien el registro de este por la red. Casi nadie lo usa; en una red de empresa con administración remota puede hacer falta (se revierte desde «Deshacer cambios»).'
        Puesto = { $m = Get-InicioServicio 'RemoteRegistry'; (-not $m) -or $m -eq 'Disabled' }
        Poner = { if (-not (Set-ServicioSeguro 'RemoteRegistry' 'Disabled' -Detener)) { throw 'el servicio no existe' } }; Admin = $true }
    [pscustomobject]@{ Id = 'diagtrack'; Nombre = 'Servicio de telemetría (DiagTrack) desactivado'; Marcado = $false
        Aviso = 'Windows deja de enviar datos de diagnóstico y uso a Microsoft por este servicio. Windows funciona igual; algunas herramientas de diagnóstico de Microsoft dejan de recibir datos.'
        Puesto = { $m = Get-InicioServicio 'DiagTrack'; (-not $m) -or $m -eq 'Disabled' }
        Poner = { if (-not (Set-ServicioSeguro 'DiagTrack' 'Disabled' -Detener)) { throw 'el servicio no existe' } }; Admin = $true }
)

foreach ($a in $ajustes) { $a | Add-Member -NotePropertyName Hecho -NotePropertyValue ([bool](& $a.Puesto)) }
Write-Output "  $($E.Lupa) Estado de los ajustes rápidos:"
foreach ($a in $ajustes) { Write-Output ("    {0} {1}" -f $(if ($a.Hecho) { "$($E.OK) puesto   " } else { "$($E.Info) sin poner" }), $a.Nombre) }
if ($SoloAnalizar) { Write-Output "`n  $($E.Info) Solo análisis: no se ha cambiado nada."; return }

$pendientes = @($ajustes | Where-Object { -not $_.Hecho })
if (-not $pendientes.Count) { Write-Output "`n  $($E.OK) Ya está todo puesto."; Write-Log 'Ajustes_Rapidos_Soporte: nada que poner'; return }
Assert-Admin 'cambiar estos ajustes'

if ($Aplicar) { $elegidos = @($pendientes | Where-Object { $_.Id -in $Aplicar }) }
else {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    [Windows.Forms.Application]::EnableVisualStyles()
    $f = New-Object Windows.Forms.Form; $f.Text = 'Ajustes rápidos de soporte'; $f.Size = New-Object Drawing.Size(980, 400); $f.StartPosition = 'CenterScreen'; $f.TopMost = $true; $f.Font = New-Object Drawing.Font('Segoe UI', 9.5)
    $t = New-Object Windows.Forms.Label; $t.Text = 'Qué quieres poner'; $t.Font = New-Object Drawing.Font('Segoe UI Semibold', 14); $t.AutoSize = $true; $t.Location = New-Object Drawing.Point(20, 14)
    $lv = New-Object Windows.Forms.ListView; $lv.View = 'Details'; $lv.CheckBoxes = $true; $lv.FullRowSelect = $true; $lv.Location = New-Object Drawing.Point(20, 56); $lv.Size = New-Object Drawing.Size(924, 240); $lv.Anchor = 'Top,Bottom,Left,Right'
    foreach ($c in @(@('Ajuste', 300), @('Qué pasa', 610))) { [void]$lv.Columns.Add($c[0], $c[1]) }
    foreach ($x in $pendientes) { $i = New-Object Windows.Forms.ListViewItem($x.Nombre); [void]$i.SubItems.Add($x.Aviso); $i.Tag = $x; $i.Checked = $x.Marcado; [void]$lv.Items.Add($i) }
    $ok = New-Object Windows.Forms.Button; $ok.Text = 'Poner lo marcado'; $ok.Size = New-Object Drawing.Size(200, 36); $ok.Location = New-Object Drawing.Point(744, 316); $ok.Anchor = 'Bottom,Right'; $ok.DialogResult = 'OK'
    $no = New-Object Windows.Forms.Button; $no.Text = 'No cambiar nada'; $no.Size = New-Object Drawing.Size(140, 36); $no.Location = New-Object Drawing.Point(594, 316); $no.Anchor = 'Bottom,Right'; $no.DialogResult = 'Cancel'
    $f.Controls.AddRange(@($t, $lv, $ok, $no)); $f.AcceptButton = $ok; $f.CancelButton = $no
    $elegidos = if ($f.ShowDialog() -eq 'OK') { @($lv.CheckedItems | ForEach-Object { $_.Tag }) } else { @() }
}
if (-not $elegidos.Count) { Exit-Kit 'Cancelado' 'No se cambia nada.' }

[void](Start-OperacionSegura 'Ajustes rápidos de soporte')
$errores = 0
foreach ($a in $elegidos) {
    try { & $a.Poner; Write-Output "  $($E.OK) $($a.Nombre)"; Write-Log "Ajustes_Rapidos_Soporte: $($a.Id)" }
    catch { $errores++; Write-Output "  $($E.Aviso) $($a.Nombre): $($_.Exception.Message)" }
}
Write-Output "`n$($E.OK) Hecho. Se pueden deshacer desde «Deshacer cambios»."
if ($errores) { Exit-Kit 'Error' "$errores ajuste(s) no se pudieron poner." }
