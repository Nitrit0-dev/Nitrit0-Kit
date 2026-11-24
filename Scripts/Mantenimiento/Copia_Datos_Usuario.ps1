# =====================================================================
#  Copia_Datos_Usuario.ps1 - Copia de seguridad de los datos del usuario (Nitrit0)
#  Escritorio, Documentos, Imágenes, Vídeos, Música, Descargas y marcadores de Chrome/Edge/Firefox con robocopy
#  (reintentos, reanuda si el destino se desconecta y deja un registro). Pide la carpeta de destino.
#  Parámetros: -Destino "carpeta"  -Usuario "nombre" (por defecto el actual)  -Simular
# =====================================================================
[CmdletBinding()]
param([string]$Destino, [string]$Usuario = $env:USERNAME, [Alias('SoloAnalizar')][switch]$Simular)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
if ($Usuario -match '[\\/:*?"<>|]' -or $Usuario -match '^[ .]*$' -or $Usuario -match '[ .]$') { Exit-Kit 'Error' "El nombre de usuario «$Usuario» no es válido (lleva separadores de ruta o caracteres que Windows no admite en un nombre)." }   # sin «\», «/» ni «..»: no se sale de C:\Users
$perfil = Join-Path (Split-Path $env:USERPROFILE -Parent) $Usuario
if (-not (Test-Path -LiteralPath $perfil)) { Write-Output "  $($E.Error) No existe el perfil $perfil"; exit 1 }
if (-not $Destino) {
    Add-Type -AssemblyName System.Windows.Forms
    $fb = New-Object Windows.Forms.FolderBrowserDialog; $fb.Description = 'Elige dónde guardar la copia (un disco externo o el pendrive)'; $fb.ShowNewFolderButton = $true
    if ($fb.ShowDialog() -ne 'OK') { Exit-Kit 'Cancelado' 'Cancelado: no se ha copiado nada.' }
    $Destino = $fb.SelectedPath
}
$Destino = Join-Path $Destino ("Copia_{0}_{1}_{2}" -f $env:COMPUTERNAME, $Usuario, (Get-Date -Format 'yyyyMMdd'))
if (([IO.Path]::GetFullPath($Destino) + '\').StartsWith(([IO.Path]::GetFullPath($perfil)).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { Exit-Kit 'Error' 'El destino está dentro del perfil que se copia: la copia se copiaría a sí misma hasta llenar el disco. Elige otra unidad o una carpeta fuera de C:\Users\<usuario>.' }
New-Item -ItemType Directory -Force $Destino | Out-Null
$carpetas = @('Desktop', 'Documents', 'Pictures', 'Videos', 'Music', 'Downloads', 'Favorites')
$extra = @{ 'Chrome_Marcadores' = "AppData\Local\Google\Chrome\User Data\Default"; 'Edge_Marcadores' = "AppData\Local\Microsoft\Edge\User Data\Default" }
Write-Output "  $($E.Info) Origen: $perfil"; Write-Output "  $($E.Info) Destino: $Destino"
$tam = 0; foreach ($c in $carpetas) { $p = Join-Path $perfil $c; if (Test-Path -LiteralPath $p) { $tam += (Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue 2>$null | Measure-Object Length -Sum).Sum } }   # 2>$null: PowerShell 5.1 saca un Win32Exception por archivos en la nube (OneDrive) aunque se pida SilentlyContinue
Write-Output ("  $($E.Info) Tamaño a copiar: {0:N1} GB" -f ($tam / 1GB))
try { $libre = (New-Object IO.DriveInfo((Split-Path $Destino -Qualifier))).AvailableFreeSpace; if ($libre -lt $tam * 1.05) { Write-Output "  $($E.Error) No hay espacio suficiente en el destino ($([math]::Round($libre/1GB,1)) GB libres)."; exit 1 } } catch { }
$errores = 0
foreach ($c in $carpetas) {
    $o = Join-Path $perfil $c; if (-not (Test-Path -LiteralPath $o)) { continue }
    Write-Output "  $($E.Reloj) Copiando $c …"
    $ra = @($o, (Join-Path $Destino $c), '/E', '/COPY:DAT', '/R:3', '/W:5', '/MT:4', '/XJ', '/NP', '/NFL', '/NDL', "/LOG+:$(Join-Path $Destino 'robocopy.log')")
    if ($Simular) { $ra += '/L' }
    $raTxt = ($ra | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' '
    $r = Invoke-Proceso 'robocopy.exe' $raTxt 7200 "Copia de $c" 30
    if ($r.Codigo -ge 8 -or $r.TiempoAgotado) { $errores++; Write-Output "    $($E.Error) $c terminó con código $($r.Codigo)." } else { Write-Output "    $($E.OK) $c copiada." }
}
# Del navegador solo se copian los favoritos (Bookmarks): nunca Login Data, Cookies (ni Network\Cookies, Cookies-journal, Extension Cookies), Web Data ni Local State,
# que permitirían clonar sesiones iniciadas o descifrar datos guardados desde otro equipo.
foreach ($k in $extra.Keys) { $o = Join-Path $perfil $extra[$k]; foreach ($f in 'Bookmarks') { if ((Test-Path -LiteralPath (Join-Path $o $f)) -and -not $Simular) { New-Item -ItemType Directory -Force (Join-Path $Destino $k) | Out-Null; try { Copy-Item -LiteralPath (Join-Path $o $f) (Join-Path $Destino $k) -Force } catch { } } } }
Write-Output "`n  $(if ($errores) { $E.Aviso + " Terminado con $errores carpeta(s) con errores." } else { $E.OK + ' Copia terminada sin errores.' })  Registro: $(Join-Path $Destino 'robocopy.log')"
Write-Log "Copia de datos de $Usuario a $Destino ($errores errores)"
if ($errores) { exit 1 }
