# =====================================================================
#  Activar_Seguridad_Windows.ps1 - Activa la seguridad de Windows (Nitrit0)
#  Defender (protección en tiempo real, firmas al día) y Firewall en los tres perfiles.
#  Si hay otro antivirus gestionando el equipo, NO se toca Defender (se avisa).
#  Si Windows bloquea el cambio (Protección contra alteraciones o directiva), lo indica y abre Seguridad de Windows.
# =====================================================================
[CmdletBinding()]
param([Alias('Simular')][switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
if ($SoloAnalizar) {
    Write-Output "  $($E.Lupa) Modo análisis: estado actual (no se cambia nada)"
    try { $m = Get-MpComputerStatus -ErrorAction Stop; Write-Output "    Defender: tiempo real $(if ($m.RealTimeProtectionEnabled) { 'ACTIVO' } else { 'DESACTIVADO' }) · firmas de hace $($m.AntivirusSignatureAge) día(s)" } catch { Write-Output "    Defender: no disponible (otro antivirus o bloqueado)" }
    try { Get-NetFirewallProfile -ErrorAction Stop | ForEach-Object { Write-Output "    Firewall $($_.Name): $(if ($_.Enabled) { 'activo' } else { 'DESACTIVADO' })" } } catch { Write-Output "    $($E.Aviso) No se pudo leer el firewall: $($_.Exception.Message)" }
    Exit-Kit 'Ok' 'Modo análisis: se quitarían las directivas que apagan Defender, se activaría la protección en tiempo real, se actualizarían las firmas y se activaría el firewall. No se ha cambiado nada.'
}
[void](Start-OperacionSegura 'Activar seguridad de Windows')   # punto de restauración antes de tocar servicios y Defender
Write-Output "========================================================"
Write-Output "  $($E.Cohete) ACTIVAR LA SEGURIDAD DE WINDOWS"
Write-Output "========================================================"
$problemas = 0

# --- ¿Hay otro antivirus? (productState: bit 0x1000 = activo)
$otros = @()
try { $otros = @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop | Where-Object { $_.displayName -notmatch 'Defender' -and (([int]$_.productState -band 0x1000) -ne 0) }) } catch { }
if ($otros) {
    Write-Output "  $($E.Info) Hay otro antivirus activo: $(($otros | ForEach-Object { $_.displayName }) -join ', '). Windows deja Defender en segundo plano; no se modifica."
} else {
    # Directivas que dejan Defender apagado (típico tras optimizadores o malware)
    foreach ($k in 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection') {
        foreach ($n in 'DisableAntiSpyware', 'DisableAntiVirus', 'DisableRealtimeMonitoring', 'DisableBehaviorMonitoring', 'DisableOnAccessProtection', 'DisableIOAVProtection') {
            try { $v = (Get-ItemProperty -Path $k -Name $n -ErrorAction Stop).$n; if ($v -eq 1) { Set-ValorSeguro $k $n 0 'DWord'; Write-Output "  $($E.OK) Directiva $n quitada (estaba a 1)."; Write-Log "Defender: directiva $n 1 -> 0" } } catch { }
        }
    }
    foreach ($s in 'WinDefend', 'WdNisSvc', 'Sense') {
        $sv = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($sv -and $sv.Status -ne 'Running' -and $s -ne 'Sense') { try { [void](Set-ServicioSeguro $s 'Automatic'); Start-Service $s -ErrorAction Stop; Write-Output "  $($E.OK) Servicio $s iniciado." } catch { Write-Output "  $($E.Aviso) No se pudo iniciar $s : $($_.Exception.Message)" } }
    }
    try {
        Set-MpPreference -DisableRealtimeMonitoring $false -DisableBehaviorMonitoring $false -DisableIOAVProtection $false -DisableScriptScanning $false -DisableBlockAtFirstSeen $false -ErrorAction Stop
        Write-Output "  $($E.OK) Protección en tiempo real activada."
    } catch {
        $problemas++
        Write-Output "  $($E.Error) Windows no permite cambiarlo desde aquí: $($_.Exception.Message)"
        Write-Output "  $($E.Info) Suele ser la «Protección contra alteraciones» o una directiva de empresa. Se abre Seguridad de Windows para activarlo a mano."
        try { Start-Process 'windowsdefender://threatsettings' } catch { }
    }
    Write-Output "  $($E.Reloj) Actualizando las firmas de Defender (máx. 3 min)…"
    $j = Start-Job { Update-MpSignature -ErrorAction Stop }
    if (Wait-Job $j -Timeout 180) { try { Receive-Job $j -ErrorAction Stop | Out-Null; Write-Output "  $($E.OK) Firmas actualizadas." } catch { Write-Output "  $($E.Aviso) No se pudieron actualizar: $($_.Exception.Message)" } } else { Stop-Job $j; Write-Output "  $($E.Aviso) La actualización de firmas tardó demasiado (¿sin Internet?)." }
    Remove-Job $j -Force -ErrorAction SilentlyContinue
}

# --- Firewall
foreach ($s in 'mpssvc', 'BFE') { $sv = Get-Service -Name $s -ErrorAction SilentlyContinue; if ($sv -and $sv.Status -ne 'Running') { try { [void](Set-ServicioSeguro $s 'Automatic'); Start-Service $s -ErrorAction Stop } catch { } } }
try { Set-NetFirewallProfile -Profile Domain, Private, Public -Enabled True -ErrorAction Stop; Write-Output "  $($E.OK) Firewall activado en los perfiles Dominio, Privado y Público." }
catch { $problemas++; Write-Output "  $($E.Error) No se pudo activar el firewall: $($_.Exception.Message)" }

# --- Resultado
Write-Output "`n  Estado final:"
try { $m = Get-MpComputerStatus -ErrorAction Stop; Write-Output "    Defender: tiempo real $(if ($m.RealTimeProtectionEnabled) { 'ACTIVO' } else { 'DESACTIVADO' }) · firmas de hace $($m.AntivirusSignatureAge) día(s)" } catch { Write-Output "    Defender: no disponible (otro antivirus o bloqueado)" }
try { Get-NetFirewallProfile | ForEach-Object { Write-Output "    Firewall $($_.Name): $(if ($_.Enabled) { 'activo' } else { 'DESACTIVADO' })" } } catch { }
Write-Log "Seguridad de Windows: activación terminada con $problemas problema(s)"
Write-Output "`n  $(if ($problemas) { $E.Aviso + ' Terminado con problemas.' } else { $E.OK + ' Hecho. Vuelve a pasar el diagnóstico para comprobarlo.' })"
if ($problemas) { exit 1 }
