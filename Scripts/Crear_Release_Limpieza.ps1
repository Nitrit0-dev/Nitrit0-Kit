# =====================================================================
#  Crear_Release_Limpieza.ps1 - Paquete suelto «Nitrit0 Limpieza» para una Release de GitHub, con su SHA-256 (Nitrit0)
#  Parte del pack Lite ya construido (Crear_Packs.ps1 -Lite) y copia SOLO lo que necesita la app de limpieza:
#    Nitrit0_Limpieza.exe + App\MotorLimpieza + Datos (kit.id, Integridad.json, Ajustes.json) + los 4 scripts que usa
#    (Comun.ps1, Limpieza_Motor.ps1, Desinstalar_Total.ps1, Limpiar_Registro_Huerfano.ps1).
#  Antes de comprimir hace una prueba real del motor en la carpeta resultante (Analizar = solo mide, no borra nada).
#  Genera en <Destino>: Nitrit0_Limpieza_v<versión>.7z y .sha256.txt. No sube nada.
#  Uso:  powershell.exe -NoProfile -ExecutionPolicy Bypass -File Scripts\Crear_Release_Limpieza.ps1 -Version 0.1.0 [-Carpeta <pack Lite>] [-Destino <carpeta>]
# =====================================================================
[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version, [string]$Carpeta, [string]$Destino)
$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
$packs = Join-Path (Split-Path -Parent $raiz) 'Nitrit0_Packs'
if (-not $Carpeta) { $Carpeta = Join-Path $packs 'Nitrit0_Kit_Lite' }
if (-not $Destino) { $Destino = Join-Path $packs 'Release' }
$sz = (Get-Command 7z.exe -ErrorAction SilentlyContinue).Source
if (-not $sz) { foreach ($c in "$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe") { if (Test-Path -LiteralPath $c) { $sz = $c; break } } }
if (-not $sz) { throw 'Falta 7-Zip (7z.exe). Instálalo desde https://www.7-zip.org' }

$archivos = 'Nitrit0_Limpieza.exe', 'Datos\kit.id', 'Datos\Integridad.json', 'Datos\Ajustes.json', 'Scripts\Comun.ps1', 'Scripts\Limpieza_Motor.ps1', 'Scripts\Mantenimiento\Desinstalar_Total.ps1', 'Scripts\Mantenimiento\Limpiar_Registro_Huerfano.ps1'
foreach ($a in $archivos + 'App\MotorLimpieza\Nitrit0 Limpieza.exe') { if (-not (Test-Path -LiteralPath (Join-Path $Carpeta $a))) { throw "Falta $a en $Carpeta. Genera antes el pack: Scripts\Crear_Packs.ps1 -Lite" } }

New-Item -ItemType Directory -Force $Destino | Out-Null
$tmp = Join-Path $Destino "_limpieza_v$Version"; if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
$pk = Join-Path $tmp 'Nitrit0_Limpieza'; New-Item -ItemType Directory -Force $pk | Out-Null
foreach ($a in $archivos) { $d = Join-Path $pk $a; New-Item -ItemType Directory -Force (Split-Path -Parent $d) | Out-Null; Copy-Item -LiteralPath (Join-Path $Carpeta $a) -Destination $d -Force }
Copy-Item -LiteralPath (Join-Path $Carpeta 'App\MotorLimpieza') -Destination (Join-Path $pk 'App\MotorLimpieza') -Recurse -Force

$leeme = @'
NITRIT0 LIMPIEZA - LÉEME
=====================================================
Qué es
  Una app para liberar espacio y ordenar Windows: limpiador de archivos temporales, desinstalador de programas,
  limpieza del registro y gestión de los programas que arrancan con Windows. Todo con explicaciones en castellano.

Cómo se usa
  1. Descomprime esta carpeta entera donde quieras (no hace falta instalar).
  2. Abre "Nitrit0_Limpieza.exe". Pide permisos de administrador porque limpia zonas del sistema.
  3. Windows puede avisar de «editor desconocido» (SmartScreen): el programa no está firmado.
     Comprueba que el SHA-256 del .7z coincide con el publicado en la Release antes de abrirlo.

Qué hace y qué no
  - Analiza primero y te enseña cuánto ocupa cada categoría; solo borra lo que marques y confirmes.
  - No envía datos de tu equipo a ningún sitio.
  - Haz copia de lo importante antes de limpiar el registro o desinstalar programas: ningún programa es infalible.

Responsabilidad
  Se entrega tal cual, sin garantía y bajo licencia MIT. Úsalo en equipos tuyos o con permiso de su dueño.
'@
[IO.File]::WriteAllText((Join-Path $pk 'LEEME.txt'), ($leeme -replace "`r?`n", "`r`n"), (New-Object Text.UTF8Encoding($true)))

# Prueba real del motor en la carpeta resultante: Analizar solo mide
Write-Host 'Probando el motor de limpieza en la carpeta del paquete (solo analiza)...' -ForegroundColor Cyan
$orden = "`$env:NIT_EJEC='1'; . '$pk\Scripts\Comun.ps1'; Initialize-Kit '$pk'; & '$pk\Scripts\Limpieza_Motor.ps1' -Accion Analizar"
$salida = & powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -Command $orden 2>&1
$lineas = @($salida | ForEach-Object { "$_" } | Where-Object { $_ -match '^\{' })
$fin = $lineas | Where-Object { $_ -match '"evento":"fin"' } | Select-Object -First 1
if ($LASTEXITCODE -ne 0 -or -not $fin) { Write-Host ($salida | Select-Object -First 12 | Out-String); throw "El motor no funciona en el paquete suelto (código $LASTEXITCODE, $($lineas.Count) líneas JSON)." }
Write-Host "  Motor OK: $($lineas.Count) eventos, fin = $fin" -ForegroundColor Green
Remove-Item -LiteralPath (Join-Path $pk 'Datos\Logs') -Recurse -Force -ErrorAction SilentlyContinue   # el análisis puede dejar registro: no se publica

$base = Join-Path $Destino "Nitrit0_Limpieza_v$Version"
Get-ChildItem -LiteralPath $Destino -Filter "Nitrit0_Limpieza_v$Version*" -File | Remove-Item -Force
& $sz a -t7z -mx=9 -m0=lzma2 -md=64m -ms=on -bso0 -bsp0 "$base.7z" (Join-Path $tmp '*')
if ($LASTEXITCODE -ne 0) { throw "7-Zip falló (código $LASTEXITCODE)" }
$a7 = Get-Item -LiteralPath "$base.7z"
if ($a7.Length -gt 1900MB) { throw 'El .7z pasa de 1,9 GB: GitHub admite 2 GB por archivo.' }
$huellas = "$base.sha256.txt"
$l = @("Nitrit0 Limpieza v$Version - SHA-256 ($(Get-Date -Format 'yyyy-MM-dd'))", 'Comprueba con: Get-FileHash <archivo> -Algorithm SHA256', ('{0}  {1}' -f (Get-FileHash -LiteralPath $a7.FullName -Algorithm SHA256).Hash.ToLower(), $a7.Name))
[IO.File]::WriteAllText($huellas, ($l -join "`r`n") + "`r`n", (New-Object Text.UTF8Encoding($false)))
Remove-Item -LiteralPath $tmp -Recurse -Force
Write-Host "`nListo en $Destino" -ForegroundColor Green
Write-Host ('  {0}  {1:N0} MB' -f $a7.Name, ($a7.Length / 1MB)); Write-Host "  $(Split-Path $huellas -Leaf)"
