# =====================================================================
#  Desinstalar_Bloatware_Win11.ps1 (Lanzador Nitrit0 - 100% Local)
#  Muestra una lista con casillas de las apps preinstaladas (Bloatware)
#  que están actualmente en el PC para desinstalarlas limpiamente.
#  Nunca toca Microsoft Store, Calculadora, Fotos ni Seguridad.
# =====================================================================
[CmdletBinding()]
param([Alias('Simular')][switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }

if (-not $Global:E) {
    $Global:E = @{
        OK = [char]::ConvertFromUtf32(0x2705); Error = [char]::ConvertFromUtf32(0x274C); Aviso = [char]::ConvertFromUtf32(0x26A0)
        Info = [char]::ConvertFromUtf32(0x2139); Cohete = [char]::ConvertFromUtf32(0x1F680); Lupa = [char]::ConvertFromUtf32(0x1F50D)
        Disco = [char]::ConvertFromUtf32(0x1F4BE); Reloj = [char]::ConvertFromUtf32(0x23F3); Basura = [char]::ConvertFromUtf32(0x1F5D1)
    }
}
$E = $Global:E
if (-not $E.Basura) { $E['Basura'] = [char]::ConvertFromUtf32(0x1F5D1) }

# Diccionario de Bloatware habitual en Windows 10/11
$CandidatosBloat = [ordered]@{
    "Clipchamp.Clipchamp"                    = "Clipchamp (Editor de vídeo web)"
    "Microsoft.BingNews"                     = "Microsoft Noticias (Bing News)"
    "Microsoft.BingWeather"                  = "El Tiempo (Bing Weather)"
    "Microsoft.BingFinance"                  = "Dinero / Finanzas (Bing Finance)"
    "Microsoft.GetHelp"                      = "Obtener Ayuda (Get Help)"
    "Microsoft.Getstarted"                   = "Sugerencias de Windows (Tips)"
    "Microsoft.MicrosoftSolitaireCollection" = "Colección de Solitarios (Juegos con anuncios)"
    "Microsoft.WindowsFeedbackHub"           = "Centro de opiniones (Feedback Hub)"
    "Microsoft.People"                       = "Contactos (People)"
    "Microsoft.PowerAutomateDesktop"         = "Power Automate Desktop"
    "Microsoft.Todos"                        = "Microsoft To Do"
    "Microsoft.WindowsMaps"                  = "Mapas de Windows"
    "Microsoft.YourPhone"                    = "Enlace Móvil (Phone Link)"
    "Microsoft.549981C3F5F10"                = "Cortana"
    "MicrosoftTeams"                         = "Microsoft Teams (Personal/Chat)"
    "Microsoft.OutlookForWindows"            = "Nuevo Outlook (Web wrapper)"
    "Microsoft.ZuneMusic"                    = "Reproductor Multimedia / Groove Música"
    "Microsoft.ZuneVideo"                    = "Películas y TV"
    "Disney.37853FC22B2CE"                   = "Disney+ (Promocionado)"
    "SpotifyAB.SpotifyMusic"                 = "Spotify (Versión Store preinstalada)"
    "BytedancePte.Ltd.TikTok"                = "TikTok (Promocionado)"
    "Microsoft.BingSearch"                   = "Bing Search (resultados web en Inicio y Búsqueda)"
    "Microsoft.MicrosoftOfficeHub"           = "Microsoft 365 (Office Hub, anuncio de suscripción)"
    "Microsoft.SkypeApp"                     = "Skype (versión Store antigua)"
    "Microsoft.Microsoft3DViewer"            = "Visor 3D"
    "Microsoft.MixedReality.Portal"          = "Portal de realidad mixta"
    "Microsoft.Windows.DevHome"              = "Dev Home / Configuración avanzada de Windows"
    "MicrosoftCorporationII.MicrosoftFamily" = "Microsoft Family Safety (Seguridad familiar)"
    "microsoft.windowscommunicationsapps"    = "Correo y Calendario (sustituidos por el nuevo Outlook)"
}

# Sin administrador, Get-AppxPackage -AllUsers da «acceso denegado» y parecería que el equipo está limpio
Assert-Admin 'listar y quitar las apps preinstaladas de todos los usuarios'
Write-Output "`n$($E.Lupa) Buscando aplicaciones preinstaladas (Bloatware) presentes en este PC..."
$InstaladasAhora = New-Object System.Collections.Generic.List[object]

foreach ($item in $CandidatosBloat.GetEnumerator()) {
    $pkg = Get-AppxPackage -AllUsers -Name "*$($item.Key)*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pkg) {
        $InstaladasAhora.Add([PSCustomObject]@{
            Patron      = $item.Key
            Descripcion = $item.Value
            NombreReal  = $pkg.Name
        })
    }
}

if ($InstaladasAhora.Count -eq 0) {
    Write-Output "  $($E.OK) ¡Este equipo ya está limpio! No se encontró ninguna de las apps de bloatware habituales."
    return
}

if ($SoloAnalizar) {
    Write-Output "  $($E.Lupa) Apps de bloatware que se podrían quitar ($($InstaladasAhora.Count)):"
    foreach ($b in $InstaladasAhora) { Write-Output "    · $($b.Descripcion)" }
    Exit-Kit 'Ok' 'Modo análisis: solo se han listado; no se ha desinstalado nada.'
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Colores del tema del kit (Datos\Ajustes.json), como en Instalador_Basico
$oscuro = $true; try { $aj = Join-Path (Get-KitDatos) 'Ajustes.json'; if (Test-Path -LiteralPath $aj) { $oscuro = ((Get-Content -LiteralPath $aj -Raw -Encoding UTF8 | ConvertFrom-Json).Tema -ne 'claro') } } catch { }
$cF = if ($oscuro) { '#12151C' } else { '#F3F5F9' }; $cL = if ($oscuro) { '#1E2330' } else { '#FFFFFF' }; $cT = if ($oscuro) { '#F0F3FA' } else { '#1B2230' }; $cA = if ($oscuro) { '#2BC4D8' } else { '#087F91' }; $cAT = if ($oscuro) { '#06222A' } else { '#FFFFFF' }
$c = { param($h) [System.Drawing.ColorTranslator]::FromHtml($h) }
$Form = New-Object System.Windows.Forms.Form
$Form.BackColor = & $c $cF
$Form.Text = "Limpiador de Bloatware Windows 11 - Nitrit0"
$Form.Size = New-Object System.Drawing.Size(500, 440)
$Form.StartPosition = "CenterScreen"
$Form.FormBorderStyle = "FixedDialog"
$Form.MaximizeBox = $false
$Form.TopMost = $true
$Form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

$Lbl = New-Object System.Windows.Forms.Label
$Lbl.Text = "Marca las apps preinstaladas que quieras ELIMINAR de este PC:"
$Lbl.Location = New-Object System.Drawing.Point(16, 12)
$Lbl.AutoSize = $true
$Lbl.ForeColor = & $c $cT
$Lbl.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$Form.Controls.Add($Lbl)

$Lista = New-Object System.Windows.Forms.CheckedListBox
$Lista.CheckOnClick = $true
$Lista.Location = New-Object System.Drawing.Point(16, 38)
$Lista.Size = New-Object System.Drawing.Size(450, 290)
$Lista.BorderStyle = 'None'; $Lista.BackColor = & $c $cL; $Lista.ForeColor = & $c $cT
foreach ($app in $InstaladasAhora) {
    [void]$Lista.Items.Add("$($app.Descripcion)  [$($app.NombreReal)]", $false)   # nada marcado: la persona elige qué quitar
}
$Form.Controls.Add($Lista)

$BtnQuitar = New-Object System.Windows.Forms.Button
$BtnQuitar.Text = "Desinstalar Marcadas"
$BtnQuitar.Location = New-Object System.Drawing.Point(262, 345)
$BtnQuitar.Size = New-Object System.Drawing.Size(204, 38)
$BtnQuitar.FlatStyle = 'Flat'; $BtnQuitar.BackColor = & $c $cA; $BtnQuitar.ForeColor = & $c $cAT
$BtnQuitar.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$BtnQuitar.DialogResult = [System.Windows.Forms.DialogResult]::OK
$Form.Controls.Add($BtnQuitar)

# Recomendadas: juegos con anuncios, Bing (Noticias, Tiempo, Finanzas), Solitario, TikTok, Disney+, Clipchamp y Feedback Hub.
# Enlace Móvil, Teams, Nuevo Outlook y lo demás se quedan sin marcar: la persona decide.
$Recomendadas = @('Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.BingFinance', 'Microsoft.MicrosoftSolitaireCollection', 'BytedancePte.Ltd.TikTok', 'Disney.37853FC22B2CE', 'Clipchamp.Clipchamp', 'Microsoft.WindowsFeedbackHub')
$BtnRec = New-Object System.Windows.Forms.Button
$BtnRec.Text = "Marcar recomendadas"; $BtnRec.Location = New-Object System.Drawing.Point(16, 345); $BtnRec.Size = New-Object System.Drawing.Size(130, 38)
$BtnRec.FlatStyle = 'Flat'; $BtnRec.ForeColor = & $c $cT
$BtnRec.Add_Click({ for ($i = 0; $i -lt $InstaladasAhora.Count; $i++) { $Lista.SetItemChecked($i, ($Recomendadas -contains $InstaladasAhora[$i].Patron)) } })
$BtnNada = New-Object System.Windows.Forms.Button
$BtnNada.Text = "Desmarcar todo"; $BtnNada.Location = New-Object System.Drawing.Point(152, 345); $BtnNada.Size = New-Object System.Drawing.Size(104, 38)
$BtnNada.FlatStyle = 'Flat'; $BtnNada.ForeColor = & $c $cT
$BtnNada.Add_Click({ for ($i = 0; $i -lt $Lista.Items.Count; $i++) { $Lista.SetItemChecked($i, $false) } })
$Form.Controls.AddRange(@($BtnRec, $BtnNada))

if ($Form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { Exit-Kit 'Cancelado' 'Operación cancelada.' }

$AEliminar = @()
for ($i = 0; $i -lt $InstaladasAhora.Count; $i++) {
    if ($Lista.GetItemChecked($i)) { $AEliminar += $InstaladasAhora[$i] }
}

if ($AEliminar.Count -eq 0) {
    Write-Output "  $($E.Info) No se marcó ninguna aplicación."
    return
}

Write-Output "`n========================================================"
Write-Output "  $($E.Basura) ELIMINANDO $($AEliminar.Count) APLICACIONES PREINSTALADAS"
Write-Output "========================================================`n"

[void](Start-OperacionSegura 'Desinstalar bloatware de Windows 11')
$Quitadas = 0
foreach ($app in $AEliminar) {
    foreach ($pk in @(Get-AppxPackage -AllUsers -Name "*$($app.Patron)*" -ErrorAction SilentlyContinue)) { Save-Informativo "App quitada: $($pk.Name)" $pk.PackageFullName }
    Write-Output "  $($E.Reloj) Quitando: $($app.Descripcion)..."
    try {
        Get-AppxPackage -AllUsers -Name "*$($app.Patron)*" -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
        Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*$($app.Patron)*" } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
        Write-Output "    $($E.OK) Eliminada correctamente."
        $Quitadas++
    } catch {
        Write-Output "    $($E.Aviso) No se pudo quitar del todo: $($_.Exception.Message)"
    }
}

Write-Output "`n========================================================"
Write-Output "  $($E.OK) LIMPIEZA DE BLOATWARE TERMINADA ($Quitadas eliminadas)"
Write-Output "  $($E.Info) Se creó un punto de restauración y la lista de apps quitadas está en Datos\Respaldo\Cambios. Para reinstalar una: búscala en Microsoft Store."
Write-Output "========================================================"