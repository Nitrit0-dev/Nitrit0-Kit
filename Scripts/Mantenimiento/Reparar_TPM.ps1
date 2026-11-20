# =====================================================================
#  Reparar_TPM.ps1 - Diagnóstico y reparación del chip TPM (Nitrit0)
#  Para «este equipo no cumple los requisitos de Windows 11», «TPM no detectado» o BitLocker/Windows Hello
#  que dejan de funcionar. Revisa el TPM, el arranque seguro (Secure Boot) y el modo UEFI; arranca el
#  servicio TBS, reactiva el dispositivo en Windows y, en equipos HP y Lenovo, puede pedir a la BIOS que
#  encienda el chip (se aplica al reiniciar).
#  NUNCA borra el TPM: borrarlo deja inservibles las claves de BitLocker y de Windows Hello.
#  Parámetros: -SinPreguntas (solo diagnostica y repara la parte de Windows; no toca la BIOS)
#              -SoloAnalizar (diagnostica y dice qué haría, sin cambiar nada)
# =====================================================================
[CmdletBinding()]
param([switch]$SinPreguntas, [Alias('Simular')][switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E

Assert-Admin 'leer el TPM y el arranque seguro (sin administrador Windows no los deja leer y el resultado sería falso)'

# El registro de cambios (Deshacer cambios) se abre la primera vez que algo se va a modificar, no antes
$script:opTpm = $false
function Initialize-OpTpm { if (-not $script:opTpm) { [void](Start-OperacionSegura 'Reparar TPM' -SinPuntoRestauracion); $script:opTpm = $true } }
$cs = Get-CimInstance Win32_ComputerSystem; $bios = Get-CimInstance Win32_BIOS
$fab = ([string]$cs.Manufacturer).ToUpper()
Write-Output "========================================================"
Write-Output "  $($E.Lupa) TPM, ARRANQUE SEGURO Y REQUISITOS DE WINDOWS 11"
Write-Output "========================================================"
Write-Output "  Equipo: $($cs.Manufacturer) $($cs.Model)  ·  BIOS $($bios.SMBIOSBIOSVersion)"

# Lee el estado del TPM por WMI (funciona aunque Get-Tpm falle porque el servicio TBS esté parado)
function Get-EstadoTpm {
    $r = [ordered]@{ Presente = $false; Habilitado = $false; Activado = $false; Version = ''; Fabricante = ''; Listo = $false }
    try {
        $w = Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction Stop
        if ($w) {
            $r.Presente = $true; $r.Habilitado = [bool]$w.IsEnabled_InitialValue; $r.Activado = [bool]$w.IsActivated_InitialValue
            $r.Version = (([string]$w.SpecVersion) -split ',')[0].Trim(); $r.Fabricante = [string]$w.ManufacturerIdTxt
        }
    } catch { }
    try { $t = Get-Tpm -ErrorAction Stop; if ($t.TpmPresent) { $r.Presente = $true }; $r.Listo = [bool]$t.TpmReady } catch { }
    [pscustomobject]$r
}

# ---------------------------------------------------------------------
Write-Output "`n  [1/4] Estado actual"
$tpm = Get-EstadoTpm
if ($tpm.Presente) {
    Write-Output "    $($E.OK) Chip TPM detectado: versión $($tpm.Version) ($($tpm.Fabricante))  ·  habilitado: $(if ($tpm.Habilitado) { 'sí' } else { 'NO' })  ·  activado: $(if ($tpm.Activado) { 'sí' } else { 'NO' })  ·  listo: $(if ($tpm.Listo) { 'sí' } else { 'NO' })"
    if ($tpm.Version -and $tpm.Version -notmatch '^2') { Write-Output "    $($E.Aviso) Es un TPM $($tpm.Version): Windows 11 exige la versión 2.0. En algunos equipos se cambia en la BIOS (fTPM/PTT) o con una actualización de firmware del fabricante." }
} else { Write-Output "    $($E.Aviso) Windows no ve ningún chip TPM (apagado en la BIOS, driver desactivado o el equipo no lo tiene)." }

# Modo de arranque: Windows lo publica en la variable firmware_type (UEFI / Legacy); el valor del registro no existe en todos los equipos
$uefi = $null
if ($env:firmware_type) { $uefi = ($env:firmware_type -eq 'UEFI') }
else { try { $pe = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -ErrorAction Stop).PEFirmwareType; if ($pe) { $uefi = ($pe -eq 2) } } catch { } }
$sb = $null; try { $sb = [bool](Confirm-SecureBootUEFI -ErrorAction Stop) } catch { }
$gpt = $null
try { $gpt = ((Get-Partition -DriveLetter $env:SystemDrive[0] -ErrorAction Stop | Get-Disk).PartitionStyle -eq 'GPT') } catch { }
Write-Output "    $(if ($uefi) { $E.OK } else { $E.Aviso }) Modo de arranque: $(if ($uefi) { 'UEFI' } elseif ($null -eq $uefi) { 'no se pudo leer' } else { 'BIOS heredada (Legacy/CSM)' })"
Write-Output "    $(if ($gpt) { $E.OK } else { $E.Aviso }) Disco de Windows: $(if ($gpt) { 'GPT' } elseif ($null -eq $gpt) { 'no se pudo leer' } else { 'MBR' })"
Write-Output "    $(if ($sb) { $E.OK } else { $E.Aviso }) Arranque seguro (Secure Boot): $(if ($sb) { 'activado' } elseif ($uefi) { 'DESACTIVADO' } else { 'no disponible en modo heredado' })"

# ---------------------------------------------------------------------
Write-Output "`n  [2/4] Servicio y dispositivo en Windows"
try {
    $svc = Get-CimInstance Win32_Service -Filter "Name='TBS'" -ErrorAction Stop
    if (-not $svc) { Write-Output "    $($E.OK) Servicios básicos de TPM (TBS): integrados en Windows en esta versión, no hay servicio que reparar." }
    elseif ($svc.State -ne 'Running') {
        if ($SoloAnalizar) { Write-Output "    $($E.Info) Modo análisis: el servicio TBS está $($svc.State) ($($svc.StartMode)); se arrancaría$(if ($svc.StartMode -eq 'Disabled') { ' tras dejarlo en manual' })." }
        else {
            Initialize-OpTpm
            if ($svc.StartMode -eq 'Disabled') { [void](Set-ServicioSeguro 'TBS' 'Manual'); Write-Output "    $($E.Aviso) El servicio TBS estaba desactivado: se ha dejado en manual (su valor de fábrica)." }
            Start-Service -Name TBS -ErrorAction Stop; Write-Output "    $($E.OK) Servicio TBS iniciado."
            Save-Informativo 'Servicio TBS iniciado' 'Para deshacerlo, para el servicio «Servicios básicos de TPM» (TBS) en services.msc; se vuelve a arrancar solo cuando hace falta.'
            Write-Log 'TPM: servicio TBS iniciado'
        }
    } else { Write-Output "    $($E.OK) Servicio TBS en marcha." }
} catch { Write-Output "    $($E.Aviso) No se pudo iniciar el servicio TBS: $($_.Exception.Message)" }

$disp = @(Get-PnpDevice -Class SecurityDevices -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'TPM|Trusted Platform|plataforma segura' })
if ($disp.Count) {
    foreach ($d in $disp) {
        if ($d.Status -eq 'OK') { Write-Output "    $($E.OK) $($d.FriendlyName): funcionando." }
        else {
            if ($SoloAnalizar) { Write-Output "    $($E.Info) Modo análisis: $($d.FriendlyName) está en estado $($d.Status) (código $($d.ConfigManagerErrorCode)); se intentaría reactivar." }
            else {
                Write-Output "    $($E.Aviso) $($d.FriendlyName): estado $($d.Status) (código $($d.ConfigManagerErrorCode)). Se intenta reactivar…"
                Initialize-OpTpm
                try { Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction Stop; Write-Output "      $($E.OK) Dispositivo reactivado."; Save-Informativo "Dispositivo reactivado: $($d.FriendlyName)" 'Para deshacerlo, deshabilítalo en el Administrador de dispositivos (Dispositivos de seguridad).'; Write-Log "TPM: dispositivo $($d.FriendlyName) reactivado" }
                catch { Write-Output "      $($E.Aviso) No se pudo reactivar: $($_.Exception.Message)" }
            }
        }
    }
} else {
    if ($SoloAnalizar) { Write-Output "    $($E.Info) Modo análisis: no aparece ningún TPM en el Administrador de dispositivos; se buscarían cambios de hardware." }
    else {
        Write-Output "    $($E.Info) No aparece ningún TPM en el Administrador de dispositivos. Se buscan cambios de hardware…"
        $r = Invoke-Proceso "$env:SystemRoot\System32\pnputil.exe" '/scan-devices' 120 'Búsqueda de hardware' 30
        if ($r.Codigo -ne 0) { Write-Output "    $($E.Aviso) La búsqueda de hardware terminó con código $($r.Codigo)." }
        Start-Sleep -Seconds 3
    }
}
if ($SoloAnalizar) { Write-Output "    $($E.Info) Modo análisis: se activaría la preparación automática del TPM." }
else {
    Initialize-OpTpm
    try { Enable-TpmAutoProvisioning -ErrorAction Stop | Out-Null; Write-Output "    $($E.OK) Preparación automática del TPM activada (Windows lo deja listo solo, sin borrarlo)."; Save-Informativo 'Preparación automática del TPM activada' 'Para deshacerlo, ejecuta Disable-TpmAutoProvisioning en PowerShell como administrador.' } catch { }
}

# ---------------------------------------------------------------------
Write-Output "`n  [3/4] Encendido del chip en la BIOS"
$tpm = Get-EstadoTpm
$pendienteReinicio = $false
if ($tpm.Presente -and $tpm.Habilitado -and $tpm.Activado) { Write-Output "    $($E.OK) El chip ya está encendido: no hay que tocar la BIOS." }
elseif ($SinPreguntas -or $SoloAnalizar) { Write-Output "    $($E.Info) $(if ($SoloAnalizar) { 'Modo análisis' } else { 'Modo sin preguntas' }): no se cambia nada en la BIOS." }
else {
    $esLenovo = $fab -match 'LENOVO'; $esHP = $fab -match '^HP|HEWLETT'
    $setLen = $null; $setHP = $null
    if ($esLenovo) { $setLen = Get-CimInstance -Namespace root\wmi -ClassName Lenovo_SetBiosSetting -ErrorAction SilentlyContinue }
    if ($esHP) { $setHP = Get-CimInstance -Namespace root\HP\InstrumentedBIOS -ClassName HP_BiosSettingInterface -ErrorAction SilentlyContinue }
    if (-not $setLen -and -not $setHP) {
        Write-Output "    $($E.Info) Este equipo no permite cambiar la BIOS desde Windows. Hay que hacerlo a mano:"
    } else {
        Add-Type -AssemblyName System.Windows.Forms
        $resp = [Windows.Forms.MessageBox]::Show("El chip TPM está apagado o sin activar.`n`n¿Pedir a la BIOS de este $($cs.Manufacturer) que lo encienda?`n`nEl cambio se aplica al reiniciar. Si la BIOS tiene contraseña de administrador, no se podrá hacer desde aquí.", 'TPM', 'YesNo', 'Question')
        if ($resp -ne 'Yes') { Write-Output "    $($E.Info) No se ha cambiado nada en la BIOS." }
        else {
            Initialize-OpTpm
            $hechos = 0
            if ($setLen) {
                # Los nombres del ajuste cambian según el modelo: se prueban los conocidos y se guardan los que la BIOS acepta
                foreach ($par in 'SecurityChip,Active', 'SecurityChip,Enable', 'SecurityChip,Enabled', 'TCGSecurityDevice,Enable', 'AMDfTPM,Enable', 'IntelPTT,Enable') {
                    $x = Invoke-CimMethod -InputObject $setLen -MethodName SetBiosSetting -Arguments @{ parameter = $par } -ErrorAction SilentlyContinue
                    if ($x.return -eq 'Success') { $hechos++; Write-Output "    $($E.OK) BIOS Lenovo: $($par -replace ',', ' = ')"; Save-Informativo "BIOS Lenovo: $par" 'Para deshacerlo, cambia el ajuste en la BIOS (F1 al arrancar > Security > Security Chip).' }
                }
                if ($hechos) {
                    $sv = Get-CimInstance -Namespace root\wmi -ClassName Lenovo_SaveBiosSettings -ErrorAction SilentlyContinue
                    $x = Invoke-CimMethod -InputObject $sv -MethodName SaveBiosSettings -Arguments @{ parameter = '' } -ErrorAction SilentlyContinue
                    if ($x.return -ne 'Success') { $hechos = 0; Write-Output "    $($E.Aviso) La BIOS no guardó el cambio ($($x.return)). Suele ser por la contraseña de administrador de la BIOS." }
                }
            }
            if ($setHP) {
                foreach ($par in @(@('TPM Device', 'Available'), @('TPM State', 'Enable'), @('Embedded Security Device Availability', 'Available'), @('Activate Embedded Security On Next Boot', 'Enable'))) {
                    $x = Invoke-CimMethod -InputObject $setHP -MethodName SetBiosSetting -Arguments @{ Name = $par[0]; Value = $par[1]; Password = '' } -ErrorAction SilentlyContinue
                    if ($x -and $x.Return -eq 0) { $hechos++; Write-Output "    $($E.OK) BIOS HP: $($par[0]) = $($par[1])"; Save-Informativo "BIOS HP: $($par[0]) = $($par[1])" 'Para deshacerlo, cambia el ajuste en la BIOS (F10 al arrancar > Security > TPM Embedded Security).' }
                    elseif ($x -and $x.Return -eq 6) { Write-Output "    $($E.Aviso) La BIOS rechaza el cambio: tiene contraseña de administrador."; break }
                }
            }
            if ($hechos) { $pendienteReinicio = $true; Write-Log "TPM: $hechos ajuste(s) de BIOS enviados ($($cs.Manufacturer))" }
            else { Write-Output "    $($E.Aviso) La BIOS no aceptó ningún ajuste. Hay que hacerlo a mano:" }
        }
    }
    if (-not $pendienteReinicio) {
        $tecla = if ($fab -match 'LENOVO') { 'F1 (o Enter y luego F1)' } elseif ($fab -match '^HP|HEWLETT') { 'F10 (o Esc y luego F10)' } elseif ($fab -match 'DELL') { 'F2' } elseif ($fab -match 'ASUS|ACER|MICRO-STAR|MSI|GIGABYTE|ASROCK') { 'Supr o F2' } else { 'F2, Supr, F10 o Esc según la marca' }
        Write-Output "      · Reinicia y entra en la BIOS con $tecla. También vale «Control de energía > Reiniciar a BIOS UEFI» de este kit."
        Write-Output "      · Busca Security o Advanced y activa: «TPM», «Security Chip», «Intel PTT» (Intel) o «AMD fTPM» (AMD)."
        Write-Output "      · Guarda con F10 y vuelve a pasar esta herramienta."
    }
}

# ---------------------------------------------------------------------
Write-Output "`n  [4/4] Resultado"
$tpm = Get-EstadoTpm
$w11 = $tpm.Presente -and $tpm.Habilitado -and $tpm.Activado -and ($tpm.Version -match '^2') -and $uefi -and $sb
if ($pendienteReinicio) { Write-Output "    $($E.Refresh) REINICIA el equipo para que la BIOS encienda el chip (puede pedir confirmación con una tecla al arrancar). Después vuelve a pasar esta herramienta." }
elseif ($w11) { Write-Output "    $($E.OK) TPM 2.0, UEFI y arranque seguro correctos: por esta parte el equipo cumple los requisitos de Windows 11." }
else {
    Write-Output "    $($E.Aviso) Aún falta para cumplir los requisitos de Windows 11:"
    if (-not ($tpm.Presente -and $tpm.Habilitado -and $tpm.Activado)) { Write-Output "      · Encender el TPM en la BIOS (pasos de arriba)." }
    if ($tpm.Presente -and $tpm.Version -notmatch '^2') { Write-Output "      · El TPM tiene que ser 2.0." }
    if ($null -eq $uefi -or ($uefi -and $null -eq $sb)) { Write-Output "      · No se pudo leer el modo de arranque o el arranque seguro: compruébalo en «Info del sistema» (msinfo32)." }
    if ($uefi -eq $false -or $gpt -eq $false) { Write-Output "      · El disco está en MBR o el arranque en modo heredado. Se convierte sin perder datos con «mbr2gpt /validate /allowFullOS» y luego «mbr2gpt /convert /allowFullOS»; después hay que cambiar la BIOS a UEFI. Haz antes una copia de los datos." }
    if ($uefi -and $sb -eq $false) { Write-Output "      · Activar Secure Boot en la BIOS (Boot o Security > Secure Boot > Enabled). No borra nada." }
}
if ($tpm.Presente -and $tpm.Habilitado -and $tpm.Activado -and -not $tpm.Listo -and -not $pendienteReinicio) {
    Write-Output "    $($E.Info) El chip está encendido pero Windows aún no lo ha preparado: normalmente se arregla solo tras reiniciar."
    Write-Output "      Si sigue igual, el último recurso es borrar el TPM (tpm.msc > Borrar TPM). ANTES guarda las claves de BitLocker con «Licencias y BitLocker»: sin ellas se pierden los datos cifrados."
}
Write-Log "TPM: presente=$($tpm.Presente) habilitado=$($tpm.Habilitado) activado=$($tpm.Activado) version=$($tpm.Version) uefi=$uefi secureboot=$sb reinicioPendiente=$pendienteReinicio"
