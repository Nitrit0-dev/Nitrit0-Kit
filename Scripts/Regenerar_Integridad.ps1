# =====================================================================
# Regenerar_Integridad.ps1 (Utilidad de Desarrollador - Nitrit0_Kit)
# Recalcula las rutas relativas ("R") y longitudes en bytes ("L") de
# todos los archivos de Scripts y Apps y actualiza Datos\Integridad.json
# =====================================================================

[CmdletBinding()]
param()

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir   = Split-Path -Parent $ScriptDir
$OutJson   = Join-Path $RootDir "Datos\Integridad.json"
. (Join-Path $ScriptDir 'Comun.ps1')   # Test-HuellaRequerida: misma regla que Salud del pendrive

Write-Host "Recalculando manifiesto Datos\Integridad.json en $RootDir ..." -ForegroundColor Cyan

$Carpetas = @("Scripts", "Apps", "App\datos")   # App\datos: el catálogo de la app decide qué se ejecuta, así que lleva huella
$Lista = @()

foreach ($c in $Carpetas) {
    $PathCarpeta = Join-Path $RootDir $c
    if (Test-Path $PathCarpeta) {
        $Archivos = Get-ChildItem -Path $PathCarpeta -Recurse -File
        foreach ($f in $Archivos) {
            $RelPath = $f.FullName.Substring($RootDir.Length + 1)
            # SHA-256 de Scripts y de los ejecutables/código de Apps; el resto de recursos pesados, solo por tamaño
            $Lista += [ordered]@{
                R = $RelPath
                L = $f.Length
                H = $(if (Test-HuellaRequerida $RelPath) { (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash } else { '' })
            }
        }
    }
}

# El ejecutable de la app en la raíz (si está): con huella, para que «Salud del pendrive» detecte que lo han cambiado
foreach ($n in 'Nitrit0.exe', 'Nitrit0_Limpieza.exe', 'Nitrit0_Antivirus.exe', 'Nitrit0_Clonador.exe', 'App\MotorAntivirus\Nitrit0 Antivirus.exe', 'App\MotorAntivirus\resources\app.asar', 'App\MotorClonador\Nitrit0 Clonador.exe', 'App\MotorClonador\resources\app.asar', 'App\Motor\Nitrit0 Kit.exe', 'App\Motor\resources\app.asar', 'App\MotorLimpieza\Nitrit0 Limpieza.exe', 'App\MotorLimpieza\resources\app.asar') {
    $f = Join-Path $RootDir $n
    if (Test-Path -LiteralPath $f -PathType Leaf) { $Lista += [ordered]@{ R = $n; L = (Get-Item -LiteralPath $f).Length; H = (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash } }
}

$JsonStr = $Lista | ConvertTo-Json -Compress
[System.IO.File]::WriteAllText($OutJson, $JsonStr, (New-Object System.Text.UTF8Encoding($true)))
Write-Host "[OK] Integridad.json actualizado correctamente con $($Lista.Count) archivos." -ForegroundColor Green
