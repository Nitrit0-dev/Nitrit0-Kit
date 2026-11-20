# =====================================================================
#  Crear_Release.ps1 - Comprime el pack Lite para una Release de GitHub y calcula su SHA-256 (Nitrit0)
#  Parte de la carpeta que deja `Crear_Packs.ps1 -Lite` (Nitrit0_Kit_Lite). Genera en <Destino>:
#    Nitrit0_Kit_Lite_v<versión>.7z   (o .7z.001, .002… si pasa de 1,9 GB: GitHub admite 2 GB como máximo por archivo)
#    Nitrit0_Kit_Lite_v<versión>.sha256.txt
#  Hace falta 7-Zip (7z.exe). No sube nada.
#  Uso:  powershell.exe -NoProfile -ExecutionPolicy Bypass -File Scripts\Crear_Release.ps1 -Version 1.0.0 [-Carpeta <pack Lite>] [-Destino <carpeta>]
# =====================================================================
[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version, [string]$Carpeta, [string]$Destino)
$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
$packs = Join-Path (Split-Path -Parent $raiz) 'Nitrit0_Packs'
if (-not $Carpeta) { $Carpeta = Join-Path $packs 'Nitrit0_Kit_Lite' }
if (-not $Destino) { $Destino = Join-Path $packs 'Release' }
if (-not (Test-Path -LiteralPath (Join-Path $Carpeta 'Nitrit0.exe'))) { throw "No encuentro $Carpeta\Nitrit0.exe. Genera antes el pack: Scripts\Crear_Packs.ps1 -Lite" }
if (Test-Path -LiteralPath (Join-Path $Carpeta 'Scripts\Mantenimiento\Clonar_Disco.ps1')) { throw 'El pack lleva Clonar_Disco.ps1: no es un pack público.' }
if (Test-Path -LiteralPath (Join-Path $Carpeta 'Apps\Disk')) { throw 'El pack lleva herramientas de terceros en Apps: no es un pack Lite.' }
$sz = (Get-Command 7z.exe -ErrorAction SilentlyContinue).Source
if (-not $sz) { foreach ($c in "$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe") { if (Test-Path -LiteralPath $c) { $sz = $c; break } } }
if (-not $sz) { throw 'Falta 7-Zip (7z.exe). Instálalo desde https://www.7-zip.org' }

New-Item -ItemType Directory -Force $Destino | Out-Null
$base = Join-Path $Destino "Nitrit0_Kit_Lite_v$Version"
Get-ChildItem -LiteralPath $Destino -Filter "Nitrit0_Kit_Lite_v$Version*" -File | Remove-Item -Force   # solo los de esta versión
$origen = Join-Path $Carpeta '*'
Write-Host "Comprimiendo $Carpeta ..." -ForegroundColor Cyan
& $sz a -t7z -mx=9 -m0=lzma2 -md=64m -ms=on -bso0 -bsp0 "$base.7z" $origen
if ($LASTEXITCODE -ne 0) { throw "7-Zip falló (código $LASTEXITCODE)" }
if ((Get-Item -LiteralPath "$base.7z").Length -gt 1900MB) {
    Write-Host 'Más de 1,9 GB: se divide en partes de 1.900 MB.' -ForegroundColor Yellow
    Remove-Item -LiteralPath "$base.7z" -Force
    & $sz a -t7z -mx=9 -m0=lzma2 -md=64m -ms=on -v1900m -bso0 -bsp0 "$base.7z" $origen
    if ($LASTEXITCODE -ne 0) { throw "7-Zip falló dividiendo (código $LASTEXITCODE)" }
}
$archivos = @(Get-ChildItem -LiteralPath $Destino -Filter "Nitrit0_Kit_Lite_v$Version.7z*" -File | Sort-Object Name)
$l = New-Object Collections.Generic.List[string]
$l.Add("Nitrit0 Kit Lite v$Version - SHA-256 ($(Get-Date -Format 'yyyy-MM-dd'))")
$l.Add('Comprueba con: Get-FileHash <archivo> -Algorithm SHA256')
foreach ($a in $archivos) { $l.Add(('{0}  {1}' -f (Get-FileHash -LiteralPath $a.FullName -Algorithm SHA256).Hash.ToLower(), $a.Name)) }
$huellas = Join-Path $Destino "Nitrit0_Kit_Lite_v$Version.sha256.txt"
[IO.File]::WriteAllText($huellas, ($l -join "`r`n") + "`r`n", (New-Object Text.UTF8Encoding($false)))
Write-Host "`nListo en $Destino" -ForegroundColor Green
foreach ($a in $archivos) { Write-Host ('  {0}  {1:N0} MB' -f $a.Name, ($a.Length / 1MB)) }
Write-Host "  $(Split-Path $huellas -Leaf)"
