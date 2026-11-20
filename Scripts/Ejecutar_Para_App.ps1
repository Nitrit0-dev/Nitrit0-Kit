# Ejecuta UN script de Mantenimiento para la app Electron, igual que el Ejecutor del lanzador:
# carga Comun.ps1, inicializa el kit, trae al frente las ventanas que abra el script y devuelve su código de salida.
# La app lo lanza con la salida redirigida y sin teclado; la unidad del kit llega en NIT_RAIZ.
param([Parameter(Mandatory)][string]$Script)
$ErrorActionPreference = 'Continue'
$t0 = [Diagnostics.Stopwatch]::StartNew()   # cuánto tarda en estar listo el script (un equipo recién instalado o actualizándose puede tardar minutos)
# Traza de arranque en %TEMP%\Nitrit0_Cache\Logs\arranque.log: si un script «no hace nada», ahí se ve en qué fase se quedó (aunque la consola esté en blanco)
function Write-Traza([string]$m) { try { $f = Join-Path $env:TEMP 'Nitrit0_Cache\Logs\arranque.log'; New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null; if ((Test-Path -LiteralPath $f) -and (Get-Item -LiteralPath $f).Length -gt 200KB) { Remove-Item -LiteralPath $f -Force }; Add-Content -LiteralPath $f -Value ('{0} {1,6:N1} s  {2}' -f (Get-Date -Format 'HH:mm:ss'), $t0.Elapsed.TotalSeconds, $m) } catch { } }
Write-Traza "PowerShell en marcha: $([IO.Path]::GetFileName($Script))"
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) } catch { }
$env:NIT_EJEC = '1'
$env:NIT_APP = '1'   # los informes HTML no abren el navegador: la app los muestra en su ventana (ver Open-Informe en Comun.ps1)
$global:dirScripts = $PSScriptRoot
# Si el arranque va lento, se dice qué se está haciendo (si no, la consola se queda en blanco y parece colgada)
function Write-Lento([string]$Paso) { if ($t0.Elapsed.TotalSeconds -gt 3) { Write-Host ("  $($Global:E.Reloj) $Paso ({0:N0} s desde que se pidió). El equipo va lento o está ocupado (actualizando, antivirus): es normal en un equipo recién instalado." -f $t0.Elapsed.TotalSeconds) } }
. (Join-Path $PSScriptRoot 'Comun.ps1')
Write-Lento 'Kit cargado'; Write-Traza 'Comun.ps1 cargado'
Initialize-Kit $env:NIT_RAIZ
Write-Lento 'Kit inicializado'; Write-Traza 'Kit inicializado'
. (Join-Path $PSScriptRoot 'Ejecutor.ps1')   # solo define Nit.Ventanas y Get-PidsArbol
Write-Lento 'Preparando las ventanas'; Write-Traza 'Ejecutor.ps1 cargado (DLL o compilación)'

# Vigía: cada segundo trae al frente las ventanas nuevas del script (casillas, avisos), que si no quedan detrás de la app.
# Con el diagnóstico y el cuello de botella no se arranca: consulta WMI cada segundo y ensuciaría las mediciones (y esos motores no abren ventanas).
if (-not $env:NIT_DX_MODO -and -not $env:NIT_EQ_PERFIL) {
$rs = [runspacefactory]::CreateRunspace(); $rs.Open()
$vigia = [powershell]::Create(); $vigia.Runspace = $rs
[void]$vigia.AddScript("function Get-PidsArbol { ${function:Get-PidsArbol} }`n`$vistas = New-Object 'Collections.Generic.HashSet[long]'`nwhile (`$true) { try { [void][Nit.Ventanas]::TraerAlFrente((Get-PidsArbol $PID), `$vistas) } catch { }; Start-Sleep -Seconds 1 }")
[void]$vigia.BeginInvoke()
}

$motivo = Test-ScriptAutorizado $Script
if ($motivo) {
    Write-Host "$($Global:E.Error) ERROR CRÍTICO: no se ejecuta $([IO.Path]::GetFileName($Script)): $motivo. Si lo has actualizado tú, ejecuta Regenerar_Integridad.ps1; si no, no uses este kit hasta revisarlo."
    try { Write-Log "Ejecución bloqueada de $([IO.Path]::GetFileName($Script)): $motivo" 'ERROR' } catch { }
    exit 1
}
Write-Lento "Abriendo $([IO.Path]::GetFileName($Script))"
try { Write-Log ("Arranque de $([IO.Path]::GetFileName($Script)): {0:N1} s hasta ejecutarlo" -f $t0.Elapsed.TotalSeconds) } catch { }
Write-Traza 'Integridad comprobada: se ejecuta el script'
$global:LASTEXITCODE = 0
try { & $Script } catch {
    Write-Host ("$($Global:E.Error) Error no controlado: " + $_.Exception.Message + "  (" + $_.InvocationInfo.ScriptName + ":" + $_.InvocationInfo.ScriptLineNumber + ")")
    try { Write-Log ("Error no controlado en $([IO.Path]::GetFileName($Script)): " + $_.Exception.Message) 'ERROR' } catch { }
    exit 1
}
$cod = $LASTEXITCODE
if ($cod -eq 0 -and (Test-ReinicioPendiente)) { Write-Host "$($Global:E.Aviso) Windows tiene un reinicio pendiente: reinicia el equipo para completar los cambios." }
exit $cod
