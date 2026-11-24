# =====================================================================
#  Crear_Lanzador.ps1 - Compila el lanzador fino de una app Electron ya descomprimida (Nitrit0)
#  El .exe «portable» de electron-builder descomprime la app entera (~360 MB) en %TEMP% en cada arranque: en un equipo lento o con antivirus tarda
#  minutos. El pack lleva la app descomprimida en una carpeta (App\Motor) y este lanzador de pocos KB: arranca al instante y mantiene el icono y la
#  petición de administrador. Compila con el csc de .NET Framework 4 (viene con Windows).
#  Uso:  Crear_Lanzador.ps1 -Salida <ruta .exe> -Destino 'App\Motor\Nitrit0 Kit.exe' -Titulo 'Nitrit0 Kit' [-SinAdmin] [-Argumentos '--clonar']
#  (-SinAdmin: manifiesto normal, solo para probar sin que salga el aviso de permisos)
# =====================================================================
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Salida, [Parameter(Mandatory)][string]$Destino, [Parameter(Mandatory)][string]$Titulo, [switch]$SinAdmin, [string]$Argumentos = '')
$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
$csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc)) { throw "No se encuentra el compilador de .NET Framework: $csc" }
$fuente = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Recursos\Lanzador_motor.cs') -Raw -Encoding UTF8
$ico = Join-Path $raiz 'App\build\icono.ico'
$nivel = if ($SinAdmin) { 'asInvoker' } else { 'requireAdministrator' }
$manifiesto = @"
<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3"><security><requestedPrivileges><requestedExecutionLevel level="$nivel" uiAccess="false" /></requestedPrivileges></security></trustInfo>
</assembly>
"@
$tmp = Join-Path $env:TEMP ('Nitrit0_lanz_' + [guid]::NewGuid().ToString('N').Substring(0, 8)); New-Item -ItemType Directory $tmp | Out-Null
try {
    $cs = Join-Path $tmp 'Lanzador.cs'; $man = Join-Path $tmp 'app.manifest'
    $escCs = { param([string]$s) $s.Replace('\', '\\').Replace('"', '\"') }   # los tres van dentro de cadenas de C#
    [IO.File]::WriteAllText($cs, $fuente.Replace('@DESTINO@', (& $escCs $Destino)).Replace('@TITULO@', (& $escCs $Titulo)).Replace('@ARGS@', (& $escCs $Argumentos)), (New-Object Text.UTF8Encoding($true)))
    [IO.File]::WriteAllText($man, $manifiesto, (New-Object Text.UTF8Encoding($false)))
    $a = @('/nologo', '/target:winexe', "/out:$Salida", "/win32manifest:$man", '/reference:System.Windows.Forms.dll', $cs); if (Test-Path -LiteralPath $ico) { $a += "/win32icon:$ico" }
    & $csc @a; if ($LASTEXITCODE -ne 0) { throw "csc falló compilando el lanzador (código $LASTEXITCODE)" }
    Write-Host "OK  $Salida ($([math]::Round((Get-Item -LiteralPath $Salida).Length / 1KB)) KB)" -ForegroundColor Green
} finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
