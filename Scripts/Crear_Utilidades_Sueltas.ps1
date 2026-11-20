# =====================================================================
#  Crear_Utilidades_Sueltas.ps1 - Genera «Clonar disco», «Desinstalador de apps», «Limpieza profunda» y «Ajustes rápidos» como programas independientes (Nitrit0)
#  Cada uno es una carpeta portátil: <Nombre>.exe (pide administrador) + Scripts\Comun.ps1 + su script + Datos\Integridad.json.
#  No necesitan el kit ni la app. Salen en una carpeta APARTE, fuera del kit. Compila con el csc de .NET Framework 4 (viene con Windows).
#  Uso:  powershell.exe -NoProfile -ExecutionPolicy Bypass -File Scripts\Crear_Utilidades_Sueltas.ps1 [-Destino <carpeta>]
# =====================================================================
[CmdletBinding()]
param([string]$Destino)
$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
if (-not $Destino) { $Destino = Join-Path (Split-Path -Parent $raiz) 'Nitrit0_Utilidades' }
$csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc)) { throw "No se encuentra el compilador de .NET Framework: $csc" }
$fuente = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Recursos\Suelta_fuente.cs') -Raw -Encoding UTF8
$ico = Join-Path $raiz 'App\build\icono.ico'
$manifiesto = @'
<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3"><security><requestedPrivileges><requestedExecutionLevel level="requireAdministrator" uiAccess="false" /></requestedPrivileges></security></trustInfo>
</assembly>
'@
$utilidades = @(
    @{ Nombre = 'Clonar_Disco'; Script = 'Clonar_Disco.ps1'; Titulo = 'Clonar disco' }
    @{ Nombre = 'Desinstalar_a_Fondo'; Script = 'Desinstalar_Total.ps1'; Titulo = 'Desinstalador de apps' }
    @{ Nombre = 'Limpieza_Profunda'; Script = 'Limpiar_Espacio_Windows.ps1'; Titulo = 'Limpieza profunda de Windows' }
    @{ Nombre = 'Ajustes_Rapidos'; Script = 'Ajustes_Rapidos_Soporte.ps1'; Titulo = 'Ajustes rápidos de soporte' }
)
New-Item -ItemType Directory -Force $Destino | Out-Null
$tmp = Join-Path $env:TEMP ('Nitrit0_suelta_' + [guid]::NewGuid().ToString('N').Substring(0, 8)); New-Item -ItemType Directory $tmp | Out-Null
try {
    foreach ($u in $utilidades) {
        $dest = Join-Path $Destino "Nitrit0_$($u.Nombre)"
        # Solo se borra una carpeta de utilidad que cuelgue de $Destino
        if (Test-Path -LiteralPath $dest) {
            $r = (Resolve-Path -LiteralPath $dest).Path
            if (-not $r.StartsWith($Destino.TrimEnd('\') + '\') -or ((Split-Path $r -Leaf) -ne "Nitrit0_$($u.Nombre)")) { throw "No borro $r" }
            Remove-Item -LiteralPath $r -Recurse -Force
        }
        New-Item -ItemType Directory -Force (Join-Path $dest 'Scripts\Mantenimiento'), (Join-Path $dest 'Datos') | Out-Null
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Comun.ps1'), (Join-Path $PSScriptRoot 'Regenerar_Integridad.ps1') -Destination (Join-Path $dest 'Scripts')
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot "Mantenimiento\$($u.Script)") -Destination (Join-Path $dest 'Scripts\Mantenimiento')
        # Compilación: el título y el script se sustituyen en la fuente
        $cs = Join-Path $tmp "$($u.Nombre).cs"; $man = Join-Path $tmp 'app.manifest'
        [IO.File]::WriteAllText($cs, $fuente.Replace('@SCRIPT@', $u.Script).Replace('@TITULO@', $u.Titulo), (New-Object Text.UTF8Encoding($true)))
        [IO.File]::WriteAllText($man, $manifiesto, (New-Object Text.UTF8Encoding($false)))
        $exe = Join-Path $dest "$($u.Nombre).exe"
        $a = @('/nologo', '/target:exe', "/out:$exe", "/win32manifest:$man", $cs); if (Test-Path -LiteralPath $ico) { $a += "/win32icon:$ico" }
        & $csc @a; if ($LASTEXITCODE -ne 0) { throw "csc falló compilando $($u.Nombre) (código $LASTEXITCODE)" }
        # Huellas: sin Integridad.json el exe se niega a ejecutar el script
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dest 'Scripts\Regenerar_Integridad.ps1') | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "No se pudo generar la integridad de $($u.Nombre)" }
        Write-Host "OK  $exe" -ForegroundColor Green
    }
} finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host "Listo: $Destino" -ForegroundColor Cyan
