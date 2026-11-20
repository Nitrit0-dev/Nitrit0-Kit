# =====================================================================
#  Comprobar_WMI_y_Runtimes.ps1 - Salud de WMI y de los runtimes de Windows (Nitrit0)
#  Para «el kit o un programa dice que WMI falla», «faltan DLL de Visual C++» o «una aplicación pide .NET». Comprueba:
#    · WMI/CIM: que responda (consultas básicas con tiempo) y el servicio winmgmt. Si falla, ofrece SALVAR el repositorio
#      (reconstruye lo que se pueda leer; no lo restablece de cero).
#    · Visual C++ Redistributable (2005-2022) y .NET Framework 4.x instalados, y .NET moderno si lo hay.
#  Los runtimes solo se informan: instalarlos o repararlos es cosa del instalador oficial.
#  Parámetro: -SoloAnalizar (solo comprueba)   Salida: 0 bien · 1 error · 2 cancelado
# =====================================================================
[CmdletBinding()]
param([switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
if (-not $SoloAnalizar) { Assert-Admin 'reparar WMI' }

Write-Output "  $($E.Lupa) WMI"
$sv = Get-Service -Name winmgmt -ErrorAction SilentlyContinue
Write-Output "    $(if ($sv -and $sv.Status -eq 'Running') { $E.OK } else { $E.Aviso }) Servicio winmgmt: $(if ($sv) { $sv.Status } else { 'no existe' })"
$fallos = 0
foreach ($c in 'Win32_OperatingSystem', 'Win32_ComputerSystem', 'Win32_BIOS', 'Win32_LogicalDisk', 'Win32_Service', 'Win32_Processor') {
    $t0 = Get-Date
    try { $r = @(Get-CimInstance -ClassName $c -OperationTimeoutSec 20 -ErrorAction Stop); $ms = [int]((Get-Date) - $t0).TotalMilliseconds; Write-Output ("    {0} {1}: {2} resultado(s) en {3} ms" -f $(if ($ms -lt 5000) { $E.OK } else { $E.Aviso }), $c, $r.Count, $ms) }
    catch { $fallos++; Write-Output "    $($E.Error) ${c}: $($_.Exception.Message.Trim())" }
}

Write-Output "  $($E.Lupa) Runtimes"
$vc = @(); foreach ($raiz in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall') {
    $vc += @(Get-ChildItem -LiteralPath $raiz -ErrorAction SilentlyContinue | ForEach-Object { Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue } | Where-Object { $_.DisplayName -match 'Microsoft Visual C\+\+ .*Redistributable' } | ForEach-Object { "$($_.DisplayName) $($_.DisplayVersion)" })
}
$vc = @($vc | Sort-Object -Unique)
if ($vc.Count) { foreach ($v in $vc) { Write-Output "    $($E.OK) $v" } } else { Write-Output "    $($E.Aviso) No se ve ningún Visual C++ Redistributable instalado." }
$rel = $null; try { $rel = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release -ErrorAction Stop).Release } catch { }
$nombreNet = if ($rel -ge 533320) { '4.8.1' } elseif ($rel -ge 528040) { '4.8' } elseif ($rel -ge 461808) { '4.7.2' } elseif ($rel -ge 460798) { '4.7' } elseif ($rel -ge 394802) { '4.6.2' } elseif ($rel -ge 378389) { '4.5.x-4.6' } else { $null }
Write-Output "    $(if ($nombreNet) { $E.OK } else { $E.Aviso }) .NET Framework 4: $(if ($nombreNet) { "$nombreNet (release $rel)" } else { 'no se detecta' })"
$dn = Join-Path $env:ProgramFiles 'dotnet\shared'
if (Test-Path -LiteralPath $dn) { foreach ($d in Get-ChildItem -LiteralPath $dn -Directory -ErrorAction SilentlyContinue) { $vs = (Get-ChildItem -LiteralPath $d.FullName -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) -join ', '; Write-Output "    $($E.Info) $($d.Name): $vs" } }

if ($fallos -eq 0) { Write-Log 'Comprobar_WMI_y_Runtimes: WMI responde'; Exit-Kit 'Ok' $(if ($SoloAnalizar) { 'WMI responde bien. No se ha cambiado nada.' } else { 'WMI responde bien: no hay nada que reparar.' }) }
Write-Output "`n  $($E.Aviso) $fallos consulta(s) WMI fallan."
if ($SoloAnalizar) { Write-Log "Comprobar_WMI_y_Runtimes: $fallos consultas fallan (análisis)"; Exit-Kit 'Error' 'WMI falla. Ejecuta la herramienta sin «solo analizar» para intentar salvar el repositorio.' }
$elegidos = Show-Marcables 'Reparar WMI' 'WMI no responde bien. Salvar el repositorio reconstruye lo que se pueda leer y conserva lo demás; es el método suave de Microsoft.' @([pscustomobject]@{ Id = 'salvar'; Texto = 'Salvar el repositorio WMI'; Detalle = 'Para y reinicia el servicio winmgmt. Algún programa que registraba datos en WMI puede tener que volver a registrarlos.'; Marcado = $true }) 'Reparar lo marcado'
if ($null -eq $elegidos -or -not $elegidos.Count) { Exit-Kit 'Cancelado' 'No se cambia nada.' }
Start-OperacionSegura 'Reparar WMI' -SinPuntoRestauracion
$r = Invoke-Proceso (Join-Path $env:SystemRoot 'System32\wbem\winmgmt.exe') '/salvagerepository' 300 'Salvar repositorio WMI' 30
Restart-Service -Name winmgmt -Force -ErrorAction SilentlyContinue
$ok = $false; try { [void](Get-CimInstance -ClassName Win32_OperatingSystem -OperationTimeoutSec 30 -ErrorAction Stop); $ok = $true } catch { }
Write-Log "Comprobar_WMI_y_Runtimes: salvage (código $($r.Codigo)), responde después: $ok"
if ($ok) { Exit-Kit 'Ok' 'Repositorio salvado y WMI responde.' }
Exit-Kit 'Error' 'WMI sigue sin responder tras salvar el repositorio. El siguiente paso (restablecerlo de cero) es más agresivo: hazlo con una copia y a mano.'
