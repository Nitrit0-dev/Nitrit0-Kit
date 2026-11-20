# =====================================================================
#  Compilar_Recursos.ps1 - Precompila el C# que Ejecutor.ps1 compilaba en cada arranque (Nitrit0)
#  Ejecutor.ps1 llevaba una clase C# (Nit.Ventanas y Nit.Lanzado) que Add-Type compilaba con csc.exe CADA VEZ que se lanzaba un script desde la app.
#  En un equipo recién instalado (actualizando, con antivirus y .NET aún sin optimizar) eso tardaba minutos con la consola en «Esperando la primera línea…».
#  Este script extrae ese código, lo compila UNA vez a Scripts\Recursos\Nit.Ejecutor.dll y guarda la huella del código fuente en Nit.Ejecutor.src.sha256;
#  Ejecutor.ps1 carga la DLL (con su huella de Integridad.json) y solo compila si la DLL falta o no es de confianza.
#  Ejecútalo después de cambiar el C# de Ejecutor.ps1 y antes de Regenerar_Integridad.ps1. Validar_Kit avisa si la DLL se ha quedado vieja.
#  Uso:  powershell.exe -NoProfile -ExecutionPolicy Bypass -File Scripts\Compilar_Recursos.ps1
# =====================================================================
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$ej = Join-Path $PSScriptRoot 'Ejecutor.ps1'
$texto = Get-Content -LiteralPath $ej -Raw -Encoding UTF8
$m = [regex]::Match($texto, "(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@")
if (-not $m.Success) { throw 'No encuentro el bloque C# (Add-Type -TypeDefinition @'' ... ''@) en Ejecutor.ps1.' }
$cs = $m.Groups[1].Value
$sha = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes(($cs -replace "`r`n", "`n")))).Replace('-', '')
$csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc)) { throw "No se encuentra el compilador de .NET Framework: $csc" }
$dir = Join-Path $PSScriptRoot 'Recursos'; New-Item -ItemType Directory -Force $dir | Out-Null
$dll = Join-Path $dir 'Nit.Ejecutor.dll'
$tmp = Join-Path $env:TEMP ('Nitrit0_rec_' + [guid]::NewGuid().ToString('N').Substring(0, 8)); New-Item -ItemType Directory $tmp | Out-Null
try {
    $f = Join-Path $tmp 'Nit.Ejecutor.cs'; [IO.File]::WriteAllText($f, $cs, (New-Object Text.UTF8Encoding($true)))
    & $csc /nologo /target:library "/out:$dll" /reference:System.dll /reference:System.Core.dll /reference:System.Windows.Forms.dll /reference:System.Drawing.dll $f
    if ($LASTEXITCODE -ne 0) { throw "csc falló (código $LASTEXITCODE)" }
} finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
[IO.File]::WriteAllText((Join-Path $dir 'Nit.Ejecutor.src.sha256'), $sha, (New-Object Text.UTF8Encoding($false)))
Write-Host "OK  $dll ($([math]::Round((Get-Item -LiteralPath $dll).Length / 1KB)) KB). Ahora: Regenerar_Integridad.ps1" -ForegroundColor Green
