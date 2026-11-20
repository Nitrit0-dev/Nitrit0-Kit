# =====================================================================
#  Control_Energia.ps1 (Edición Personal Nitrit0 - 100% Local)
# =====================================================================
[CmdletBinding()]
param([Alias('Simular')][switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }

if (-not $Global:E) {
    $Global:E = @{
        OK = [char]::ConvertFromUtf32(0x2705); Error = [char]::ConvertFromUtf32(0x274C); Aviso = [char]::ConvertFromUtf32(0x26A0)
        Info = [char]::ConvertFromUtf32(0x2139); PC = [char]::ConvertFromUtf32(0x1F5A5); Cohete = [char]::ConvertFromUtf32(0x1F680)
        Reloj = [char]::ConvertFromUtf32(0x23F3); Rayo = [char]::ConvertFromUtf32(0x26A1)
    }
}
$E = $Global:E

Write-Output "`n========================================================"
Write-Output "  $($E.Rayo) CONTROL DE ENERGÍA Y ARRANQUE AVANZADO - NITRIT0"
Write-Output "========================================================`n"

if ($SoloAnalizar) { Exit-Kit 'Ok' 'Modo análisis: la ventana ofrece reiniciar, reiniciar a BIOS/UEFI o a WinRE, apagar, avisar de un reinicio en 5 minutos y cancelar una orden pendiente. No se ha ejecutado ninguna.' }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "Opciones de Energía - Nitrit0"
$Form.Size = New-Object System.Drawing.Size(370, 335)
$Form.StartPosition = "CenterScreen"
$Form.FormBorderStyle = "FixedDialog"
$Form.MaximizeBox = $false
$Form.TopMost = $true
$Form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

$Label = New-Object System.Windows.Forms.Label
$Label.Text = "Selecciona la acción a realizar en este equipo ($env:COMPUTERNAME):"
$Label.Location = New-Object System.Drawing.Point(20, 15)
$Label.AutoSize = $true
$Form.Controls.Add($Label)

$script:OpcionSeleccionada = "CANCELAR"

$BtnReinicio = New-Object System.Windows.Forms.Button
$BtnReinicio.Text = "Reinicio Inmediato"
$BtnReinicio.Location = New-Object System.Drawing.Point(20, 45)
$BtnReinicio.Size = New-Object System.Drawing.Size(150, 40)
$BtnReinicio.Add_Click({ $script:OpcionSeleccionada = "REINICIO"; $Form.Close() })
$Form.Controls.Add($BtnReinicio)

$BtnBios = New-Object System.Windows.Forms.Button
$BtnBios.Text = "Reiniciar a BIOS UEFI"
$BtnBios.Location = New-Object System.Drawing.Point(180, 45)
$BtnBios.Size = New-Object System.Drawing.Size(150, 40)
$BtnBios.BackColor = "LightYellow"
$BtnBios.Add_Click({ $script:OpcionSeleccionada = "BIOS"; $Form.Close() })
$Form.Controls.Add($BtnBios)

$BtnApagar = New-Object System.Windows.Forms.Button
$BtnApagar.Text = "Apagar Equipo"
$BtnApagar.Location = New-Object System.Drawing.Point(20, 95)
$BtnApagar.Size = New-Object System.Drawing.Size(150, 40)
$BtnApagar.Add_Click({ $script:OpcionSeleccionada = "APAGAR"; $Form.Close() })
$Form.Controls.Add($BtnApagar)

$BtnAbortar = New-Object System.Windows.Forms.Button
$BtnAbortar.Text = "Abortar Apagado (/a)"
$BtnAbortar.Location = New-Object System.Drawing.Point(180, 95)
$BtnAbortar.Size = New-Object System.Drawing.Size(150, 40)
$BtnAbortar.BackColor = "LightCyan"
$BtnAbortar.Add_Click({ $script:OpcionSeleccionada = "ABORTAR"; $Form.Close() })
$Form.Controls.Add($BtnAbortar)

$BtnWinRE = New-Object System.Windows.Forms.Button
$BtnWinRE.Text = "Reiniciar en Opciones Avanzadas / Modo Seguro"
$BtnWinRE.Location = New-Object System.Drawing.Point(20, 145)
$BtnWinRE.Size = New-Object System.Drawing.Size(310, 38)
$BtnWinRE.BackColor = "Lavender"
$BtnWinRE.Add_Click({ $script:OpcionSeleccionada = "WINRE"; $Form.Close() })
$Form.Controls.Add($BtnWinRE)

$BtnAviso = New-Object System.Windows.Forms.Button
$BtnAviso.Text = "Reinicio Programado (5 minutos)"
$BtnAviso.Location = New-Object System.Drawing.Point(20, 193)
$BtnAviso.Size = New-Object System.Drawing.Size(310, 38)
$BtnAviso.BackColor = "LightGreen"
$BtnAviso.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$BtnAviso.Add_Click({ $script:OpcionSeleccionada = "AVISO"; $Form.Close() })
$Form.Controls.Add($BtnAviso)

$BtnSalir = New-Object System.Windows.Forms.Button
$BtnSalir.Text = "Cancelar"
$BtnSalir.Location = New-Object System.Drawing.Point(20, 242)
$BtnSalir.Size = New-Object System.Drawing.Size(310, 32)
$BtnSalir.BackColor = "LightCoral"
$BtnSalir.Add_Click({ $script:OpcionSeleccionada = "CANCELAR"; $Form.Close() })
$Form.Controls.Add($BtnSalir)

[void]$Form.ShowDialog()

if ($script:OpcionSeleccionada -eq "CANCELAR") { Exit-Kit 'Cancelado' 'Operación cancelada.' }

if ($script:OpcionSeleccionada -in @("REINICIO", "BIOS", "APAGAR", "WINRE")) {
    $Resp = [System.Windows.Forms.MessageBox]::Show("Se va a ejecutar '$($script:OpcionSeleccionada)' inmediatamente en este equipo.`n`nGuarda tus documentos antes. ¿Continuar?", "Confirmar acción", "YesNo", "Warning", "Button2")
    if ($Resp -ne "Yes") { Exit-Kit 'Cancelado' 'Operación cancelada.' }
}

try {
    switch ($script:OpcionSeleccionada) {
        "REINICIO" { & shutdown.exe /r /f /t 20 /c "Nitrit0: guarda tu trabajo, el equipo actuará en 20 segundos. Para cancelar: shutdown /a" }
        "BIOS"     { & shutdown.exe /r /fw /f /t 20 /c "Nitrit0: guarda tu trabajo, el equipo actuará en 20 segundos. Para cancelar: shutdown /a" }
        "WINRE"    { & shutdown.exe /r /o /f /t 20 /c "Nitrit0: guarda tu trabajo, el equipo actuará en 20 segundos. Para cancelar: shutdown /a" }
        "APAGAR"   { & shutdown.exe /s /f /t 20 /c "Nitrit0: guarda tu trabajo, el equipo actuará en 20 segundos. Para cancelar: shutdown /a" }
        "ABORTAR"  { & shutdown.exe /a }
        "AVISO"    { & shutdown.exe /r /t 300 /c "Nitrit0: El equipo se reiniciara en 5 minutos. Guarde sus documentos." }
    }
    if ($LASTEXITCODE -ne 0 -and -not ($script:OpcionSeleccionada -eq "ABORTAR" -and $LASTEXITCODE -eq 1116)) {
        throw "shutdown.exe devolvió el código $LASTEXITCODE"
    }
    Write-Output "  $($E.OK) Orden '$($script:OpcionSeleccionada)' ejecutada correctamente."
} catch {
    Exit-Kit 'Error' "Error al ejecutar la orden: $($_.Exception.Message)"
}