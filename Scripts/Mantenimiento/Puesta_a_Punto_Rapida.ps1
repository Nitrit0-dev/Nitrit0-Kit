# =====================================================================
#  Puesta_a_Punto_Rapida.ps1 - Puesta a punto en un clic (Nitrit0)
#  El «Boost» sencillo: enseña el estado (RAM, temporales, programas de inicio, disco), pide una sola
#  confirmación y hace lo seguro: borra los temporales con más de un día y libera la RAM de los procesos
#  inactivos. No cierra programas ni navegadores y no toca el registro, los servicios ni los datos del usuario.
#  Los temporales borrados no se recuperan (son archivos desechables). Para más a fondo: «Limpiar temporales»,
#  «Optimizador personal» y «Programas de inicio».
#  Parámetros: -SinPreguntas (hace las dos acciones sin ventana)   -SoloEstado (solo muestra el estado, no cambia nada)
# =====================================================================
[CmdletBinding()]
param([switch]$SinPreguntas, [Alias('SoloAnalizar')][switch]$SoloEstado)
if ($env:NIT_AUTO) { $SinPreguntas = $true }   # la revisión automática de la app no puede contestar ventanas
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Namespace Nit -Name Mem -MemberDefinition '[System.Runtime.InteropServices.DllImport("psapi.dll")] public static extern bool EmptyWorkingSet(System.IntPtr h);' -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------
#  Estado
# ---------------------------------------------------------------------
function Get-Ram { $o = Get-CimInstance Win32_OperatingSystem; [pscustomobject]@{ TotalMB = [int]($o.TotalVisibleMemorySize / 1KB); LibreMB = [int]($o.FreePhysicalMemory / 1KB) } }
function Get-TemporalesViejos {
    $lim = (Get-Date).AddDays(-1)
    $dirs = @($env:TEMP, (Join-Path $env:SystemRoot 'Temp')) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
    foreach ($d in $dirs) { Get-ChildItem -LiteralPath $d -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $lim } }
}
function Get-DiscoC { $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" -ErrorAction SilentlyContinue; if ($d) { [pscustomobject]@{ LibreGB = [math]::Round($d.FreeSpace / 1GB, 1); TotalGB = [math]::Round($d.Size / 1GB, 1) } } }

$ram0 = Get-Ram; $disco0 = Get-DiscoC
$temp = @(Get-TemporalesViejos); $tempMB = [math]::Round((($temp | Measure-Object Length -Sum).Sum) / 1MB, 1)
$inicio = @(Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue).Count
$ramPct0 = [int](100 * ($ram0.TotalMB - $ram0.LibreMB) / [math]::Max(1, $ram0.TotalMB))

Write-Output "========================================================"
Write-Output "  $($E.Cohete) PUESTA A PUNTO RÁPIDA"
Write-Output "========================================================"
Write-Output "  $($E.Info) Memoria: $ramPct0 % en uso ($([math]::Round(($ram0.TotalMB - $ram0.LibreMB) / 1024, 1)) de $([math]::Round($ram0.TotalMB / 1024, 1)) GB)"
Write-Output "  $($E.Info) Temporales con más de un día: $($temp.Count) archivos, $tempMB MB"
Write-Output "  $($E.Info) Programas que se cargan al iniciar: $inicio$(if ($inicio -gt 12) { '  (son bastantes: revisa «Programas de inicio»)' })"
if ($disco0) { Write-Output "  $($E.Info) Disco ${env:SystemDrive} $($disco0.LibreGB) GB libres de $($disco0.TotalGB) GB" }
if ($SoloEstado) { Write-Log "Puesta a punto (solo estado): RAM $ramPct0 %, temporales $tempMB MB, inicio $inicio"; Write-Output "`n  $($E.OK) Solo consulta: no se ha cambiado nada."; exit 0 }

# ---------------------------------------------------------------------
#  Una sola confirmación
# ---------------------------------------------------------------------
$haceTemp = $true; $haceRam = $true
if (-not $SinPreguntas) {
    $f = New-Object Windows.Forms.Form; $f.Text = 'Puesta a punto rápida'; $f.ClientSize = New-Object Drawing.Size(500, 300); $f.StartPosition = 'CenterScreen'
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false; $f.Font = New-Object Drawing.Font('Segoe UI', 9.5)
    $l = New-Object Windows.Forms.Label; $l.Location = New-Object Drawing.Point(18, 14); $l.Size = New-Object Drawing.Size(464, 96); $l.BackColor = [Drawing.Color]::FromArgb(238, 238, 238); $l.Padding = New-Object Windows.Forms.Padding(8, 6, 8, 6)
    $l.Text = "Memoria: $ramPct0 % en uso`r`nTemporales con más de un día: $tempMB MB ($($temp.Count) archivos)`r`nProgramas al iniciar: $inicio`r`nDisco ${env:SystemDrive} $(if ($disco0) { "$($disco0.LibreGB) GB libres" } else { 's/d' })"
    $f.Controls.Add($l)
    $c1 = New-Object Windows.Forms.CheckBox; $c1.Text = 'Borrar los temporales con más de un día (no se recuperan)'; $c1.Checked = $true; $c1.AutoSize = $true; $c1.Location = New-Object Drawing.Point(22, 126); $f.Controls.Add($c1)
    $c2 = New-Object Windows.Forms.CheckBox; $c2.Text = 'Liberar la RAM de los procesos inactivos'; $c2.Checked = $true; $c2.AutoSize = $true; $c2.Location = New-Object Drawing.Point(22, 156); $f.Controls.Add($c2)
    $n = New-Object Windows.Forms.Label; $n.Location = New-Object Drawing.Point(18, 192); $n.Size = New-Object Drawing.Size(464, 52); $n.ForeColor = [Drawing.Color]::FromArgb(90, 90, 90)
    $n.Text = 'No cierra programas ni navegadores y no toca el registro ni tus archivos. Liberar RAM es un alivio momentáneo: Windows vuelve a cargar lo que se use.'; $f.Controls.Add($n)
    $ok = New-Object Windows.Forms.Button; $ok.Text = 'Poner a punto'; $ok.Size = New-Object Drawing.Size(130, 34); $ok.Location = New-Object Drawing.Point(232, 252); $ok.DialogResult = 'OK'
    $ca = New-Object Windows.Forms.Button; $ca.Text = 'Cancelar'; $ca.Size = New-Object Drawing.Size(100, 34); $ca.Location = New-Object Drawing.Point(382, 252); $ca.DialogResult = 'Cancel'
    $f.Controls.AddRange(@($ok, $ca)); $f.AcceptButton = $ok; $f.CancelButton = $ca
    if ($f.ShowDialog() -ne 'OK') { Write-Output "`n  $($E.Info) Cancelado: no se ha cambiado nada."; exit 2 }
    $haceTemp = $c1.Checked; $haceRam = $c2.Checked
}
if (-not $haceTemp -and -not $haceRam) { Write-Output "`n  $($E.Info) No se marcó nada: no se ha cambiado nada."; exit 2 }

# ---------------------------------------------------------------------
#  Hacerlo
# ---------------------------------------------------------------------
[void](Start-OperacionSegura 'Puesta a punto rápida' -SinPuntoRestauracion)
Write-Output ""
$borrados = 0; $bytes = 0L
if ($haceTemp) {
    Write-Output "  $($E.Reloj) Borrando temporales con más de un día…"
    foreach ($a in $temp) { try { $len = $a.Length; [IO.File]::Delete($a.FullName); $bytes += $len; $borrados++ } catch { } }
    # carpetas que quedan vacías y también son antiguas
    $lim = (Get-Date).AddDays(-1)
    foreach ($d in @($env:TEMP, (Join-Path $env:SystemRoot 'Temp')) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique) {
        foreach ($sub in @(Get-ChildItem -LiteralPath $d -Recurse -Directory -Force -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending)) {
            if ($sub.LastWriteTime -lt $lim -and -not (Get-ChildItem -LiteralPath $sub.FullName -Force -ErrorAction SilentlyContinue)) { try { Remove-Item -LiteralPath $sub.FullName -Force -ErrorAction Stop } catch { } }
        }
    }
    Write-Output "  $($E.OK) Temporales: $borrados archivos borrados, $([math]::Round($bytes / 1MB, 1)) MB liberados$(if ($borrados -lt $temp.Count) { " ($($temp.Count - $borrados) estaban en uso y se han dejado)" })."
    Save-Informativo "Temporales borrados: $borrados archivos ($([math]::Round($bytes / 1MB, 1)) MB)" 'No se deshace: eran archivos temporales con más de un día.'
}
if ($haceRam) {
    Write-Output "  $($E.Reloj) Liberando RAM de procesos inactivos…"
    $n = 0; foreach ($p in Get-Process -ErrorAction SilentlyContinue) { if ($p.Id -in 0, 4) { continue }; try { if ([Nit.Mem]::EmptyWorkingSet($p.Handle)) { $n++ } } catch { } }
    Start-Sleep -Seconds 2
    $ram1 = Get-Ram; $ramPct1 = [int](100 * ($ram1.TotalMB - $ram1.LibreMB) / [math]::Max(1, $ram1.TotalMB))
    Write-Output "  $($E.OK) RAM: $ramPct0 % → $ramPct1 % en uso ($([math]::Round(($ram1.LibreMB - $ram0.LibreMB) / 1024, 1)) GB más libres, $n procesos). Es momentáneo: Windows recarga lo que se use."
    Save-Informativo "RAM liberada de $n procesos ($ramPct0 % → $ramPct1 %)" 'Solo vacía el conjunto de trabajo; no se cierra nada ni hay nada que deshacer.'
}
$d1 = Get-DiscoC
if ($haceTemp -and $disco0 -and $d1) { Write-Output "  $($E.Disco) Disco ${env:SystemDrive} $($disco0.LibreGB) → $($d1.LibreGB) GB libres." }
if ($inicio -gt 12) { Write-Output "  $($E.Info) Tienes $inicio programas al iniciar: «Programas de inicio» deja desactivar los que no hagan falta." }
Write-Log "Puesta a punto rápida: temporales $borrados archivos ($([math]::Round($bytes / 1MB, 1)) MB), RAM $(if ($haceRam) { "$ramPct0 % -> $ramPct1 %" } else { 'sin tocar' })"
