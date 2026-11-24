# =====================================================================
#  Quitar_IA_Windows.ps1 - Desactiva Copilot, Recall y funciones de IA de Windows 11 (Nitrit0)
#  Muestra una lista con casillas: eliges qué se desactiva y puedes añadir otras apps por su nombre.
#  Usa directivas de equipo (HKLM, valen para todos los usuarios), desactiva la característica Recall
#  y sus tareas, y desinstala apps. NO toca el almacén de componentes (CBS), no usa TrustedInstaller
#  ni instala paquetes falsos de actualización: lo que Windows protege se bloquea con directivas.
#  Parámetros: -SinPreguntas (aplica todo sin ventana)   -SoloEstado (solo muestra, no cambia nada)
#  Claves y nombres de paquetes tomados del proyecto RemoveWindowsAI de zoicware (MIT).
# =====================================================================
[CmdletBinding()]
param([switch]$SinPreguntas, [Alias('SoloAnalizar')][switch]$SoloEstado)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E   # OK, Error, Aviso, Info, Lupa, Reloj, Refresh, Disco, Cohete
Assert-Admin 'leer y cambiar el estado de las apps de IA de Windows'

$Pol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows'
$Paint = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint'
# Cada opción: Tipo Dir (directivas [ruta, nombre, valor que desactiva]), Recall, Tareas o App
$Opciones = New-Object System.Collections.Generic.List[object]
function Add-Opcion($tipo, $texto, $datos) { $Opciones.Add([pscustomobject]@{ Tipo = $tipo; Texto = $texto; Datos = $datos }) }
Add-Opcion 'Dir' 'Copilot: desactivar en Windows' @(, @("$Pol\WindowsCopilot", 'TurnOffWindowsCopilot', 1))
Add-Opcion 'Dir' 'Recall: impedir que guarde instantáneas y que se active' @(
    @("$Pol\WindowsAI", 'DisableAIDataAnalysis', 1), @("$Pol\WindowsAI", 'AllowRecallEnablement', 0), @("$Pol\WindowsAI", 'TurnOffSavingSnapshots', 1))
Add-Opcion 'Dir' 'Click to Do (acciones de IA sobre lo que hay en pantalla)' @(, @("$Pol\WindowsAI", 'DisableClickToDo', 1))
Add-Opcion 'Dir' 'Agentes de IA (Configuración, conectores y espacios de trabajo)' @(
    @("$Pol\WindowsAI", 'DisableSettingsAgent', 1), @("$Pol\WindowsAI", 'DisableAgentConnectors', 1),
    @("$Pol\WindowsAI", 'DisableAgentWorkspaces', 1), @("$Pol\WindowsAI", 'DisableRemoteAgentConnectors', 1))
Add-Opcion 'Dir' 'Paint: Image Creator y Cocreator' @(@($Paint, 'DisableImageCreator', 1), @($Paint, 'DisableCocreator', 1))
$Edge = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'   # directivas documentadas en Microsoft Edge Browser Policy Documentation (learn.microsoft.com/deployedge/microsoft-edge-policies); 0 = función desactivada
Add-Opcion 'Dir' 'Edge: Copilot, barra lateral, redactar con IA y API de IA integradas' @(
    @($Edge, 'HubsSidebarEnabled', 0), @($Edge, 'CopilotCDPPageContext', 0), @($Edge, 'Microsoft365CopilotChatIconEnabled', 0),
    @($Edge, 'ComposeInlineEnabled', 0), @($Edge, 'BuiltInAIAPIsEnabled', 0), @($Edge, 'ShareBrowsingHistoryWithCopilotSearchAllowed', 0))
Add-Opcion 'Recall' 'Recall: desactivar la característica de Windows' $null
Add-Opcion 'Tareas' 'Recall: desactivar sus tareas programadas' $null
foreach ($n in 'Microsoft.Copilot', 'Microsoft.Windows.Ai.Copilot.Provider') { Add-Opcion 'App' "Desinstalar la app $n" $n }
# Windows protege estas apps: no se fuerzan, solo se informa (las directivas las dejan inactivas)
$Protegidas = @('MicrosoftWindows.Client.AIX', 'MicrosoftWindows.Client.CoreAI')

function Test-Aplicada($o) {
    switch ($o.Tipo) {
        'Dir' {
            foreach ($d in $o.Datos) {
                $v = $null; try { $v = (Get-ItemProperty -LiteralPath $d[0] -Name $d[1] -ErrorAction Stop).($d[1]) } catch { }
                if ($v -ne $d[2]) { return $false }
            }
            return $true
        }
        'Recall' { try { return ((Get-WindowsOptionalFeature -Online -FeatureName Recall -ErrorAction Stop).State -eq 'Disabled') } catch { return $true } }
        'Tareas' { return (@(Get-TareasIA | Where-Object { $_.State -ne 'Disabled' }).Count -eq 0) }
        'App' { return (-not (Get-AppxPackage -AllUsers -Name "*$($o.Datos)*" -ErrorAction SilentlyContinue)) }
    }
}
function Get-TareasIA { @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -like '*WindowsAI*' -or $_.TaskName -like '*Recall*' }) }

Write-Output "`n$($E.Lupa) Estado de las funciones de IA de Windows..."
$Estado = @{}
foreach ($o in $Opciones) { $Estado[$o.Texto] = Test-Aplicada $o }
foreach ($o in $Opciones) { Write-Output "  $(if ($Estado[$o.Texto]) { $E.OK } else { $E.Info }) $($o.Texto): $(if ($Estado[$o.Texto]) { 'ya aplicado o no presente' } else { 'pendiente' })" }
$prot = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $Protegidas -contains $_.Name -or $_.Name -like 'WindowsWorkload.*' } | ForEach-Object Name | Select-Object -Unique)
if ($prot.Count) { Write-Output "  $($E.Info) Componentes de IA protegidos por Windows (no se fuerzan): $($prot -join ', ')." }
if ($SoloEstado) { return }

$Elegidas = @($Opciones | Where-Object { -not $Estado[$_.Texto] })
if (-not $SinPreguntas) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = 'Quitar IA de Windows - Nitrit0'; $Form.Size = New-Object System.Drawing.Size(580, 520)
    $Form.StartPosition = 'CenterScreen'; $Form.FormBorderStyle = 'FixedDialog'; $Form.MaximizeBox = $false; $Form.TopMost = $true
    $Form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $Lbl = New-Object System.Windows.Forms.Label
    $Lbl.Text = 'Marca lo que quieras DESACTIVAR (lo ya aplicado viene sin marcar):'
    $Lbl.Location = New-Object System.Drawing.Point(16, 12); $Lbl.AutoSize = $true
    $Lbl.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold); $Form.Controls.Add($Lbl)
    $Lista = New-Object System.Windows.Forms.CheckedListBox
    $Lista.CheckOnClick = $true; $Lista.Location = New-Object System.Drawing.Point(16, 38); $Lista.Size = New-Object System.Drawing.Size(530, 290)
    $Form.Controls.Add($Lista)
    $Cola = New-Object System.Collections.Generic.List[object]
    function Add-Fila($o, [bool]$marcada, [string]$nota) { $Cola.Add($o); [void]$Lista.Items.Add("$($o.Texto)$nota", $marcada) }
    foreach ($o in $Opciones) { Add-Fila $o (-not $Estado[$o.Texto]) $(if ($Estado[$o.Texto]) { '   [ya aplicado]' } else { '' }) }

    $LblAdd = New-Object System.Windows.Forms.Label
    $LblAdd.Text = 'Añadir otra app a desinstalar (nombre del paquete, p. ej. Microsoft.Windows.Photos):'
    $LblAdd.Location = New-Object System.Drawing.Point(16, 340); $LblAdd.AutoSize = $true; $Form.Controls.Add($LblAdd)
    $Txt = New-Object System.Windows.Forms.TextBox
    $Txt.Location = New-Object System.Drawing.Point(16, 362); $Txt.Size = New-Object System.Drawing.Size(410, 24); $Form.Controls.Add($Txt)
    $BtnAdd = New-Object System.Windows.Forms.Button
    $BtnAdd.Text = 'Añadir'; $BtnAdd.Location = New-Object System.Drawing.Point(436, 360); $BtnAdd.Size = New-Object System.Drawing.Size(110, 28); $Form.Controls.Add($BtnAdd)
    $BtnAdd.Add_Click({
        $n = $Txt.Text.Trim()
        if ($n -notmatch '^[\w\.\-]+$') { [void][Windows.Forms.MessageBox]::Show('Escribe solo el nombre del paquete (letras, números, puntos y guiones).', 'Nitrit0', 'OK', 'Information'); return }
        # El nombre se busca como «contiene»: un término corto o genérico («Microsoft», «Windows») casaría con decenas de apps del sistema, así que se pide un nombre concreto y se enseña cuántas coinciden
        if ($n.Length -lt 5) { [void][Windows.Forms.MessageBox]::Show('Escribe un nombre más concreto (al menos 5 caracteres), por ejemplo Microsoft.Copilot.', 'Nitrit0', 'OK', 'Information'); return }
        $coinciden = @(Get-AppxPackage -AllUsers -Name "*$n*" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name -Unique)
        if (-not $coinciden.Count) { [void][Windows.Forms.MessageBox]::Show("No hay ninguna app instalada que coincida con «$n».", 'Nitrit0', 'OK', 'Information'); return }
        if ($coinciden.Count -gt 3) { [void][Windows.Forms.MessageBox]::Show("«$n» coincide con $($coinciden.Count) apps (por ejemplo: $(($coinciden | Select-Object -First 4) -join ', ')). Escribe un nombre más concreto.", 'Nitrit0', 'OK', 'Warning'); return }
        if ([Windows.Forms.MessageBox]::Show("Se desinstalarán estas apps:`n`n$($coinciden -join "`n")`n`n¿Añadirlas?", 'Nitrit0', 'YesNo', 'Question') -ne 'Yes') { return }
        Add-Fila ([pscustomobject]@{ Tipo = 'App'; Texto = "Desinstalar la app $n (añadida a mano)"; Datos = $n }) $true ''
        $Txt.Text = ''
    })
    $BtnOk = New-Object System.Windows.Forms.Button
    $BtnOk.Text = 'Aplicar marcadas'; $BtnOk.Location = New-Object System.Drawing.Point(330, 420); $BtnOk.Size = New-Object System.Drawing.Size(216, 38)
    $BtnOk.BackColor = 'LightCoral'; $BtnOk.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $BtnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK; $Form.Controls.Add($BtnOk)
    $Info = New-Object System.Windows.Forms.Label
    $Info.Text = 'Se crea un punto de restauración antes y todo se puede deshacer (Mantenimiento > Deshacer cambios).'
    $Info.Location = New-Object System.Drawing.Point(16, 430); $Info.Size = New-Object System.Drawing.Size(300, 36); $Form.Controls.Add($Info)

    if ($Form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { Write-Output "  $($E.Aviso) Operación cancelada."; exit 2 }
    $Elegidas = @(); for ($i = 0; $i -lt $Cola.Count; $i++) { if ($Lista.GetItemChecked($i)) { $Elegidas += $Cola[$i] } }
}
if (-not $Elegidas.Count) { Write-Output "  $($E.Info) No hay nada que aplicar."; return }

$fallos = 0
[void](Start-OperacionSegura 'Quitar IA de Windows')
foreach ($o in $Elegidas) {
    Write-Output "`n$($E.Reloj) $($o.Texto)..."
    switch ($o.Tipo) {
        'Dir' {
            foreach ($d in $o.Datos) {
                try { Set-ValorSeguro $d[0] $d[1] $d[2] } catch { $fallos++; Write-Output "  $($E.Aviso) No se pudo escribir $($d[1]): $($_.Exception.Message)" }
            }
            Write-Output "  $($E.OK) Directivas aplicadas."
        }
        'Recall' {
            try {
                [void](Disable-WindowsOptionalFeature -Online -FeatureName Recall -NoRestart -ErrorAction Stop)
                Save-Informativo 'Característica Recall desactivada' 'Para volver: Enable-WindowsOptionalFeature -Online -FeatureName Recall'
                Write-Output "  $($E.OK) Recall desactivado (se conserva el contenido por si se reactiva)."
            } catch { Write-Output "  $($E.Info) Recall no está instalado o no se puede cambiar en este Windows: $($_.Exception.Message)" }
        }
        'Tareas' {
            $ts = Get-TareasIA
            if (-not $ts.Count) { Write-Output "  $($E.OK) No hay tareas de IA/Recall en este equipo." }
            foreach ($t in $ts) {
                try {
                    [void](Disable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction Stop)
                    Save-Informativo "Tarea desactivada: $($t.TaskPath)$($t.TaskName)" "Para volver: Enable-ScheduledTask -TaskPath '$($t.TaskPath)' -TaskName '$($t.TaskName)'"
                    Write-Output "  $($E.OK) Tarea desactivada: $($t.TaskName)"
                } catch { Write-Output "  $($E.Info) La tarea $($t.TaskName) está protegida por Windows; la directiva de Recall ya la deja sin efecto." }
            }
        }
        'App' {
            $pks = @(Get-AppxPackage -AllUsers -Name "*$($o.Datos)*" -ErrorAction SilentlyContinue)
            if (-not $pks.Count) { Write-Output "  $($E.OK) No está instalada." }
            foreach ($pk in $pks) {
                Save-Informativo "App quitada: $($pk.Name)" $pk.PackageFullName
                try {
                    Remove-AppxPackage -Package $pk.PackageFullName -AllUsers -ErrorAction Stop
                    Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $pk.Name } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
                    Write-Output "  $($E.OK) Desinstalada: $($pk.Name). Para reinstalarla: búscala en Microsoft Store."
                } catch { $fallos++; Write-Output "  $($E.Aviso) No se pudo quitar $($pk.Name) (Windows puede protegerla): $($_.Exception.Message)" }
            }
        }
    }
}

Write-Log "Quitar IA de Windows terminado ($($Elegidas.Count) opciones, $fallos avisos)"
Write-Output "`n$($E.OK) Hecho. Reinicia el equipo para que todo surta efecto."
Write-Output "  $($E.Info) Las opciones de IA de Notepad y Office se ajustan a mano en cada programa."
if ($fallos) { exit 1 }
