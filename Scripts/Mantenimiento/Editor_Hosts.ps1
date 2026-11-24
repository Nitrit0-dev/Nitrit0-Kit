# =====================================================================
#  Editor_Hosts.ps1 - Ver y corregir el archivo HOSTS de Windows (Nitrit0)
#  El archivo HOSTS fuerza a que un nombre de web (por ejemplo, una página de antivirus o de Windows Update) vaya a otra dirección.
#  Lo usan bloqueos de anuncios, y también virus y programas viejos para desviar o bloquear páginas. Esta herramienta lo enseña,
#  marca lo sospechoso, y deja guardar cambios o restaurar el contenido original de Windows.
#  Antes de guardar hace una copia en Datos\Respaldo\Hosts\ y se puede volver atrás copiándola de nuevo.
#  Parámetros: -SoloLeer (solo analiza, no abre el editor)   -Archivo "ruta" (para pruebas; por defecto el HOSTS de Windows)
#              -NuevoContenido "archivo.txt" (sin ventana: sustituye el HOSTS por ese texto, con copia previa)
# =====================================================================
[CmdletBinding()]
param([Alias('SoloLeer')][switch]$SoloAnalizar, [string]$Archivo = '', [string]$NuevoContenido = '')
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
if (-not $Archivo) { $Archivo = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts' }
$esAdmin = Test-EsAdmin

$TextoWindows = "# Copyright (c) 1993-2009 Microsoft Corp.`r`n#`r`n# Este es un archivo HOSTS de ejemplo usado por Microsoft TCP/IP para Windows.`r`n#`r`n# Cada entrada debe ir en una linea: primero la direccion IP y luego el nombre de host.`r`n#`r`n# El propio Windows ya resuelve localhost: no hace falta ninguna entrada.`r`n#`r`n#`t127.0.0.1       localhost`r`n#`t::1             localhost`r`n"
# Nombres que un virus suele desviar o bloquear (no son malos: lo malo es redirigirlos a otra dirección)
$Delicados = 'windowsupdate', 'update.microsoft', 'microsoft.com', 'live.com', 'google', 'avast', 'avg.com', 'kaspersky', 'eset', 'malwarebytes', 'mcafee', 'norton', 'bitdefender', 'defender', 'virustotal', 'paypal', 'bbva', 'santander', 'caixabank', 'facebook', 'amazon'
function Get-Analisis([string]$texto) {
    $act = New-Object Collections.Generic.List[object]
    foreach ($l in ($texto -split "`r?`n")) {
        $s = ($l -replace '#.*$', '').Trim(); if (-not $s) { continue }
        $p = $s -split '\s+'; if ($p.Count -lt 2) { continue }
        $ip = $p[0]; foreach ($n in $p[1..($p.Count - 1)]) {
            $bloqueo = $ip -in '0.0.0.0', '127.0.0.1', '::1', '::'
            $delicado = [bool]($Delicados | Where-Object { $n -like "*$_*" })
            $estado = if ($delicado -and -not $bloqueo) { 'SOSPECHOSA' } elseif ($delicado) { 'bloquea un nombre delicado' } elseif ($bloqueo) { 'bloqueo' } else { 'redirige' }
            $act.Add([pscustomobject]@{ Ip = $ip; Nombre = $n; Estado = $estado })
        }
    }
    $act
}
function Save-Hosts([string]$contenido) {
    $dirResp = Join-Path (Get-BaseTrabajo) 'Respaldo\Hosts'; New-Item -ItemType Directory -Force $dirResp | Out-Null
    $copia = Join-Path $dirResp ('hosts_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
    if (Test-Path -LiteralPath $Archivo) { Copy-Item -LiteralPath $Archivo -Destination $copia -Force }
    [void](Start-OperacionSegura 'Editar HOSTS' -SinPuntoRestauracion)
    Save-Informativo "HOSTS modificado ($Archivo)" "Para deshacerlo, restaura la copia guardada en $copia (o «Valores de Windows» en esta herramienta)."
    $attr = $null; if (Test-Path -LiteralPath $Archivo) { $attr = (Get-Item -LiteralPath $Archivo -Force).Attributes; (Get-Item -LiteralPath $Archivo -Force).Attributes = 'Normal' }
    try { [IO.File]::WriteAllText($Archivo, $contenido, (New-Object Text.UTF8Encoding($false))) }
    finally { if ($null -ne $attr -and (Test-Path -LiteralPath $Archivo)) { try { (Get-Item -LiteralPath $Archivo -Force).Attributes = $attr } catch { } } }
    if ([IO.File]::ReadAllText($Archivo) -ne $contenido) { throw 'Lo escrito no coincide con lo que se quería guardar.' }
    if ($Archivo -like "$env:SystemRoot*") { & ipconfig.exe /flushdns 2>&1 | Out-Null }
    Write-Log "Editor_Hosts: guardado ($Archivo); copia en $copia"
    $copia
}

if (-not (Test-Path -LiteralPath $Archivo)) { Write-Output "$($E.Aviso) No existe $Archivo (Windows funciona igual sin él)."; $actual = '' } else { $actual = [IO.File]::ReadAllText($Archivo) }
$ana = @(Get-Analisis $actual)
$sosp = @($ana | Where-Object Estado -eq 'SOSPECHOSA')
Write-Output "  $($E.Lupa) $Archivo"
Write-Output "  $($E.Info) $($ana.Count) entradas activas: $(@($ana | Where-Object Estado -eq 'bloqueo').Count) bloqueos, $(@($ana | Where-Object Estado -eq 'redirige').Count) redirecciones, $($sosp.Count) sospechosas."
foreach ($x in $sosp) { Write-Output "    $($E.Aviso) $($x.Nombre) -> $($x.Ip)  (un nombre delicado desviado a otra dirección)" }
foreach ($x in ($ana | Where-Object Estado -eq 'bloquea un nombre delicado')) { Write-Output "    $($E.Aviso) $($x.Nombre) bloqueado (¿a propósito?)" }
if (-not $ana.Count) { Write-Output "  $($E.OK) El HOSTS está como lo deja Windows: sin entradas." }
if ($SoloAnalizar) { Exit-Kit 'Ok' 'Modo análisis: no se ha cambiado nada.' }
if ($NuevoContenido) {
    if (-not $esAdmin -and $Archivo -like "$env:SystemRoot*") { Write-Output "$($E.Aviso) Hace falta administrador para cambiar el HOSTS de Windows."; exit 1 }
    $c = Save-Hosts ([IO.File]::ReadAllText($NuevoContenido)); Write-Output "  $($E.OK) HOSTS sustituido. Copia del anterior: $c"; return
}
if (-not $esAdmin -and $Archivo -like "$env:SystemRoot*") { Write-Output "$($E.Aviso) Sin administrador solo se puede mirar. Ábrelo desde el kit para guardar cambios."; $soloVer = $true } else { $soloVer = $false }

# ---------------------------------------------------------------- Editor
$f = New-Object Windows.Forms.Form; $f.Text = 'Archivo HOSTS'; $f.Size = New-Object Drawing.Size(900, 660); $f.StartPosition = 'CenterScreen'; $f.TopMost = $true; $f.Font = New-Object Drawing.Font('Segoe UI', 9.5)
$t = New-Object Windows.Forms.Label; $t.Text = 'Archivo HOSTS de Windows'; $t.Font = New-Object Drawing.Font('Segoe UI Semibold', 14); $t.AutoSize = $true; $t.Location = New-Object Drawing.Point(20, 12)
$r = New-Object Windows.Forms.Label; $r.AutoSize = $false; $r.Size = New-Object Drawing.Size(840, 40); $r.Location = New-Object Drawing.Point(20, 46)
$r.Text = "$($ana.Count) entradas activas, $($sosp.Count) sospechosas. Una línea por entrada: la dirección IP y el nombre; lo que empieza por # es un comentario. Se guarda una copia antes de cambiar nada."
$r.ForeColor = if ($sosp.Count) { [Drawing.Color]::Firebrick } else { [Drawing.Color]::DimGray }
$tb = New-Object Windows.Forms.TextBox; $tb.Multiline = $true; $tb.ScrollBars = 'Both'; $tb.WordWrap = $false; $tb.Font = New-Object Drawing.Font('Consolas', 10); $tb.Location = New-Object Drawing.Point(20, 92); $tb.Size = New-Object Drawing.Size(840, 450); $tb.Anchor = 'Top,Bottom,Left,Right'; $tb.Text = $actual; $tb.ReadOnly = $soloVer; $tb.Select(0, 0)
$gu = New-Object Windows.Forms.Button; $gu.Text = 'Guardar'; $gu.Size = New-Object Drawing.Size(120, 36); $gu.Location = New-Object Drawing.Point(740, 560); $gu.Anchor = 'Bottom,Right'; $gu.Enabled = -not $soloVer
$re = New-Object Windows.Forms.Button; $re.Text = 'Valores de Windows'; $re.Size = New-Object Drawing.Size(160, 36); $re.Location = New-Object Drawing.Point(20, 560); $re.Anchor = 'Bottom,Left'; $re.Enabled = -not $soloVer
$ce = New-Object Windows.Forms.Button; $ce.Text = 'Cerrar'; $ce.Size = New-Object Drawing.Size(110, 36); $ce.Location = New-Object Drawing.Point(620, 560); $ce.Anchor = 'Bottom,Right'; $ce.DialogResult = 'Cancel'
$re.Add_Click({ if ([Windows.Forms.MessageBox]::Show('Se pone el contenido original de Windows (sin entradas). Aún no se guarda hasta que pulses «Guardar».', 'Valores de Windows', 'OKCancel', 'Question') -eq 'OK') { $tb.Text = $TextoWindows } })
$gu.Add_Click({
    try { $c = Save-Hosts $tb.Text; [void][Windows.Forms.MessageBox]::Show("Guardado. Copia del anterior:`n$c", 'HOSTS', 'OK', 'Information'); $f.Close() }
    catch { [void][Windows.Forms.MessageBox]::Show("No se pudo guardar: $($_.Exception.Message)`n`nSi el antivirus protege el HOSTS (Defender «protección contra alteraciones»), desactívala un momento.", 'HOSTS', 'OK', 'Warning') }
})
$f.Controls.AddRange(@($t, $r, $tb, $gu, $re, $ce)); $f.CancelButton = $ce
[void]$f.ShowDialog()
