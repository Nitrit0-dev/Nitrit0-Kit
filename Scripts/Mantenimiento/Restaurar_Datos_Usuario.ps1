# =====================================================================
#  Restaurar_Datos_Usuario.ps1 - Vuelca una copia hecha con «Copia de datos del usuario» (Nitrit0)
#  Devuelve Escritorio, Documentos, Imágenes, Vídeos, Música, Descargas y Favoritos al perfil del usuario,
#  en este equipo o en uno nuevo. Nunca sobrescribe: los archivos que ya existen se dejan como están.
#  Los marcadores de Chrome y Edge solo se restauran si el navegador no tiene ya los suyos.
#  Parámetros: -Origen "carpeta Copia_..."  -Usuario "nombre" (por defecto el actual)  -SoloAnalizar (alias -Simular: no copia nada)
#  Salida: 0 bien · 1 error · 2 cancelado
# =====================================================================
[CmdletBinding()]
param([string]$Origen, [string]$Usuario = $env:USERNAME, [Alias('Simular')][switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
if ($Usuario -ne $env:USERNAME) { Assert-Admin 'restaurar en el perfil de otro usuario' }
$perfil = Join-Path (Split-Path $env:USERPROFILE -Parent) $Usuario
if (-not (Test-Path -LiteralPath $perfil)) { Exit-Kit 'Error' "No existe el perfil $perfil" }
if (-not $Origen) {
    Add-Type -AssemblyName System.Windows.Forms
    try { $fb = New-Object Windows.Forms.FolderBrowserDialog; $fb.Description = 'Elige la carpeta de la copia (se llama Copia_EQUIPO_USUARIO_FECHA)'; $fb.ShowNewFolderButton = $false
        if ($fb.ShowDialog() -ne 'OK') { Exit-Kit 'Cancelado' 'Cancelado: no se ha copiado nada.' }
        $Origen = $fb.SelectedPath } catch { Exit-Kit 'Error' "No se pudo abrir el selector de carpetas: $($_.Exception.Message)" }
}
$carpetas = @('Desktop', 'Documents', 'Pictures', 'Videos', 'Music', 'Downloads', 'Favorites') | Where-Object { Test-Path -LiteralPath (Join-Path $Origen $_) }
if (-not $carpetas) { Exit-Kit 'Error' "En $Origen no hay una copia del kit (faltan Desktop, Documents…). Elige la carpeta Copia_… completa." }
Write-Output "  $($E.Info) Copia: $Origen"; Write-Output "  $($E.Info) Destino: $perfil"
$errores = 0
foreach ($c in $carpetas) {
    Write-Output "  $($E.Reloj) $(if ($SoloAnalizar) { 'Analizando' } else { 'Restaurando' }) $c …"
    # /XC /XN /XO: solo copia lo que no existe en el destino, así nunca pisa un archivo del usuario
    $ra = @((Join-Path $Origen $c), (Join-Path $perfil $c), '/E', '/COPY:DAT', '/XC', '/XN', '/XO', '/R:3', '/W:5', '/MT:4', '/XJ', '/NP', '/NFL', '/NDL')
    if ($SoloAnalizar) { $ra += '/L' }
    $raTxt = ($ra | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' '
    try { $r = Invoke-Proceso 'robocopy.exe' $raTxt 7200 "Restaurar $c" 30 } catch { $errores++; Write-Output "    $($E.Error) ${c}: $($_.Exception.Message)"; continue }
    if ($r.Codigo -ge 8 -or $r.TiempoAgotado) { $errores++; Write-Output "    $($E.Error) $c terminó con código $($r.Codigo)." } else { Write-Output "    $($E.OK) $c $(if ($SoloAnalizar) { 'analizada (no se ha copiado nada)' } else { 'restaurada' })." }
}
$nav = @{ 'Chrome_Marcadores' = 'AppData\Local\Google\Chrome\User Data\Default'; 'Edge_Marcadores' = 'AppData\Local\Microsoft\Edge\User Data\Default' }
foreach ($k in $nav.Keys) {
    $o = Join-Path $Origen "$k\Bookmarks"; $d = Join-Path $perfil $nav[$k]
    if (-not (Test-Path -LiteralPath $o)) { continue }
    $nombre = $k -replace '_Marcadores', ''
    if (-not (Test-Path -LiteralPath $d)) { Write-Output "    $($E.Info) Marcadores de ${nombre}: abre el navegador una vez y vuelve a ejecutar esta herramienta." }
    elseif (Test-Path -LiteralPath (Join-Path $d 'Bookmarks')) { Write-Output "    $($E.Info) Marcadores de ${nombre}: el navegador ya tiene los suyos, no se tocan. Están en $o" }
    elseif (-not $SoloAnalizar) { try { Copy-Item -LiteralPath $o -Destination $d -ErrorAction Stop; Write-Output "    $($E.OK) Marcadores de $nombre restaurados (cierra y abre el navegador)." } catch { Write-Output "    $($E.Aviso) No se pudieron copiar los marcadores de $nombre." } }
}
Write-Output "  $($E.Info) Las contraseñas guardadas del navegador no se pueden pasar a otro equipo con esta copia: usa la sincronización de la cuenta."
Write-Output "`n  $(if ($errores) { $E.Aviso + " Terminado con $errores carpeta(s) con errores." } else { $E.OK + $(if ($SoloAnalizar) { ' Análisis terminado: no se ha copiado nada.' } else { ' Datos restaurados sin errores.' }) })"
Write-Log "Restauración de datos de $Origen a $perfil ($errores errores)"
if ($errores) { exit 1 }
