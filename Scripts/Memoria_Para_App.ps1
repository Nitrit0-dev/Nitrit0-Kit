# =====================================================================
#  Memoria_Para_App.ps1 - Libera memoria RAM de procesos inactivos (lo lanza la app y el icono de la bandeja)
#  Vacía el «conjunto de trabajo» de los procesos: Windows manda a disco lo que no se usa y lo recarga si hace falta.
#  Es un alivio momentáneo, no cambia nada del sistema ni cierra programas. No toca el programa que tienes delante,
#  ni procesos de Windows, seguridad o audio. Nada que deshacer.
#  Salida: una línea  ##MEM##<json>  con la memoria libre antes y después.
# =====================================================================
param()
$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) } catch { }
function Salir([object]$o) { Write-Output ('##MEM##' + ($o | ConvertTo-Json -Depth 4 -Compress)) }
try {
    . (Join-Path $PSScriptRoot 'Comun.ps1'); Initialize-Kit $env:NIT_RAIZ
    # Se lanza directamente (sin pasar por Ejecutar_Para_App): se comprueba aquí la huella de este mismo script
    $motivo = Test-ScriptAutorizado $PSCommandPath
    if ($motivo) { Salir @{ ok = $false; mensaje = "Este script $motivo." }; exit 1 }
} catch { Salir @{ ok = $false; mensaje = "No se pudo preparar el kit: $($_.Exception.Message)" }; exit 1 }

try {
    Add-Type -Namespace Nit -Name Mem -MemberDefinition @'
[DllImport("psapi.dll")] public static extern bool EmptyWorkingSet(IntPtr h);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
'@
    $libreMb = { [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1KB) }
    $antes = & $libreMb
    $delante = [uint32]0; [void][Nit.Mem]::GetWindowThreadProcessId([Nit.Mem]::GetForegroundWindow(), [ref]$delante)
    # Procesos que nunca se tocan: el de Windows, seguridad, audio, escritorio y esta misma app
    $salvo = 'Idle', 'System', 'Registry', 'smss', 'csrss', 'wininit', 'winlogon', 'services', 'lsass', 'svchost', 'dwm', 'audiodg', 'fontdrvhost', 'MsMpEng', 'NisSrv', 'SecurityHealthService', 'MemCompression', 'Nitrit0', 'Nitrit0 Kit', 'explorer', 'sihost', 'taskhostw', 'ctfmon', 'SearchHost', 'StartMenuExperienceHost', 'ShellExperienceHost', 'nvcontainer', 'NVDisplay.Container', 'AMDRSServ', 'vmwp', 'vmmem', 'EasyAntiCheat', 'EasyAntiCheat_EOS', 'BEService', 'vgc'
    $n = 0
    foreach ($p in Get-Process) {
        if ($p.Id -eq $PID -or $p.Id -eq $delante -or $salvo -contains $p.ProcessName -or $p.WorkingSet64 -lt 20MB) { continue }   # los de menos de 20 MB no compensan el coste de recargarlos
        try { if ([Nit.Mem]::EmptyWorkingSet($p.Handle)) { $n++ } } catch { }
    }
    Start-Sleep -Milliseconds 800
    $despues = & $libreMb
    Write-Log "Memoria liberada: libre $antes MB -> $despues MB ($n procesos)"
    Salir @{ ok = $true; antesMb = $antes; despuesMb = $despues; procesos = $n }
} catch { Salir @{ ok = $false; mensaje = $_.Exception.Message }; exit 1 }
