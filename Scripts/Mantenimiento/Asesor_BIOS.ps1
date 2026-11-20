# =====================================================================
#  Asesor_BIOS.ps1 - Qué opciones de la BIOS conviene tocar en este equipo (Nitrit0)
#  Lee lo que Windows puede ver de la BIOS/UEFI (RAM a su velocidad, doble canal, virtualización,
#  Secure Boot, TPM, enlace PCIe de la gráfica, Resizable BAR en NVIDIA) y dice qué opción activar
#  y dónde suele estar según la marca de la placa. SOLO LEE: no cambia nada, ni en Windows ni en la BIOS.
#  Parámetro: -SinPreguntas (no pregunta nada; este script nunca pide teclado, se admite por coherencia)
# =====================================================================
[CmdletBinding()]
param([switch]$SinPreguntas)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Motor_Equilibrio.ps1')
$E = $Global:E

$h = New-Object System.Collections.Generic.List[object]
function Add-H([string]$Estado, [string]$Texto, [string]$Opcion = '') { $h.Add([pscustomobject]@{ Estado = $Estado; Texto = $Texto; Opcion = $Opcion }) }

$bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue | Select-Object -First 1
$placa = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue | Select-Object -First 1
$sis = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue | Select-Object -First 1
$fab = ("$($placa.Manufacturer) $($sis.Manufacturer)").ToUpper()
$chasis = @((Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue).ChassisTypes)
$portatil = [bool]($chasis | Where-Object { $_ -in 8, 9, 10, 11, 12, 14, 30, 31, 32 }) -or [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
$marcaOC = [bool]($fab -match 'ASUS|MSI|MICRO-STAR|GIGABYTE|ASROCK|BIOSTAR')   # placas de sobremesa con perfiles XMP/EXPO en su BIOS

# Dónde está cada opción según la marca (aproximado: cambia entre modelos y versiones de BIOS)
$dondeXmp = if ($fab -match 'ASUS') { 'Ai Tweaker > Ai Overclock Tuner > XMP / D.O.C.P. / EXPO' }
    elseif ($fab -match 'MSI|MICRO-STAR') { 'OC > A-XMP (Intel) o EXPO / DOCP (AMD)' }
    elseif ($fab -match 'GIGABYTE') { 'Tweaker > Extreme Memory Profile (X.M.P.)' }
    elseif ($fab -match 'ASROCK') { 'OC Tweaker > DRAM Configuration > Load XMP / EXPO Setting' }
    else { 'la sección de overclock o memoria (XMP en Intel, DOCP / EXPO en AMD)' }
$dondeBar = if ($fab -match 'ASUS') { 'Advanced > PCI Subsystem Settings: Above 4G Decoding y Re-Size BAR Support' }
    elseif ($fab -match 'MSI|MICRO-STAR') { 'Settings > Advanced > PCIe/PCI Subsystem: Above 4G Memory y Re-Size BAR Support' }
    elseif ($fab -match 'GIGABYTE') { 'Settings > IO Ports: Above 4G Decoding y Re-Size BAR Support' }
    elseif ($fab -match 'ASROCK') { 'Advanced > PCI Configuration: Above 4G Decoding y Re-Size BAR Support' }
    else { 'Above 4G Decoding y Re-Size BAR Support (en PCI / PCIe / Advanced)' }

Write-Output "$($E.Info) Placa: $(($placa.Manufacturer + ' ' + $placa.Product).Trim()) · BIOS $($bios.SMBIOSBIOSVersion) ($(if ($bios.ReleaseDate) { $bios.ReleaseDate.ToString('dd/MM/yyyy') }))$(if ($portatil) { ' · portátil' } else { ' · sobremesa' })"

# --- RAM a su velocidad (XMP / DOCP / EXPO) y doble canal
try {
    $ram = Get-InfoRam
    if ($ram.Soldada) { Add-H 'Info' "Memoria $($ram.Tipo) soldada a la placa: no hay perfil de velocidad que activar." }
    elseif ($ram.VelConfig -gt 0 -and $ram.VelNominal -gt 0 -and $ram.VelConfig -lt $ram.VelNominal * 0.95) {
        if ($portatil -or -not $marcaOC) { Add-H 'Info' "La RAM trabaja a $($ram.VelConfig) MHz y los módulos admiten $($ram.VelNominal). En portátiles y equipos de marca la BIOS casi nunca deja cambiarlo." }
        else { Add-H 'Mejora' "La RAM trabaja a $($ram.VelConfig) MHz y los módulos admiten $($ram.VelNominal) MHz: el perfil XMP/DOCP/EXPO está desactivado." "Activa el perfil de memoria: $dondeXmp. Guarda y reinicia; si no arranca, la placa vuelve sola a valores seguros (o borra la CMOS)." }
    }
    elseif ($ram.VelConfig -gt 0) { Add-H 'OK' "RAM a $($ram.VelConfig) MHz, su velocidad nominal." }
    if (-not $ram.Soldada) {
        if ($ram.Modulos -eq 1 -and $ram.Ranuras -ge 2) { Add-H 'Info' "Un solo módulo de RAM para $($ram.Ranuras) ranuras: va en canal simple. No es de la BIOS: añade un segundo módulo igual." }
        elseif ($ram.Modulos -ge 2 -and $ram.CanalesConocidos -and $ram.CanalesDistintos -lt 2) { Add-H 'Info' 'Los módulos están en el mismo canal. No es de la BIOS: muévelos a las ranuras de canales distintos (ver manual de la placa).' }
    }
} catch { Add-H 'Info' "No se pudo leer la RAM ($($_.Exception.Message))." }

# --- Virtualización (VT-x / SVM). Con Hyper-V activo Windows ya la está usando.
try {
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    if ($sis.HypervisorPresent -or $cpu.VirtualizationFirmwareEnabled) { Add-H 'OK' 'Virtualización activada.' }
    else { Add-H 'Mejora' 'Virtualización desactivada. Hace falta para Hyper-V, WSL2, Sandbox, emuladores Android y Aislamiento de núcleo.' 'Actívala: Intel Virtualization Technology (VT-x) en Intel, SVM Mode en AMD (suele estar en Advanced > CPU Configuration).' }
} catch { }

# --- UEFI y arranque seguro (requiere administrador para leerse)
$esAdmin = Test-EsAdmin
if (-not $esAdmin) { Add-H 'Info' 'Sin administrador no se puede leer Secure Boot ni TPM; ejecuta el kit elevado para verlos.' }
else {
    try { $sb = Confirm-SecureBootUEFI -ErrorAction Stop
        if ($sb) { Add-H 'OK' 'Arranque UEFI con Secure Boot activado.' }
        else { Add-H 'Mejora' 'Arranque UEFI con Secure Boot desactivado. Windows 11 y algunos anticheats lo exigen.' 'Actívalo en Security / Boot > Secure Boot (puede pedir poner el modo en «Windows UEFI» y restaurar claves de fábrica).' }
    } catch { Add-H 'Mejora' 'Arranca en modo Legacy/CSM, no en UEFI. Windows 11 no se instala así y se pierde Secure Boot y Resizable BAR.' 'No lo cambies sin más: el disco debe estar en GPT (convertir con mbr2gpt) antes de desactivar CSM/Legacy.' }
    try { $t = Get-Tpm -ErrorAction Stop
        if ($t.TpmPresent -and $t.TpmReady) { Add-H 'OK' 'TPM presente y listo.' }
        elseif ($t.TpmPresent) { Add-H 'Info' 'TPM presente pero no listo. Mantenimiento > «Reparar TPM».' }
        else { Add-H 'Mejora' 'No se detecta TPM. Windows 11 lo necesita.' 'Actívalo: fTPM / PSP fTPM en AMD, PTT en Intel (Security > Trusted Computing).' }
    } catch { }
}

# --- Gráfica: enlace PCIe y Resizable BAR
try {
    $gpu = (Get-InfoGpu).Dedicada
    if ($gpu) {
        $p = Get-EnlacePcie $gpu.Nombre
        if ($p) {
            $txt = "$($gpu.Nombre): PCIe Gen$($p.VelActual) x$($p.AnchoActual) (máximo Gen$($p.VelMax) x$($p.AnchoMax))"
            if ($p.AnchoActual -lt $p.AnchoMax -and $p.AnchoActual -le 4) { Add-H 'Mejora' "$txt. Va con muy pocas líneas: mal asentada, ranura equivocada o limitada por la BIOS." 'Revisa la ranura PCIe de la gráfica y en la BIOS que la ranura esté en «Auto» (no x4/x8 ni Gen1/Gen2 forzado). Mídelo con la gráfica trabajando: en reposo baja por ahorro de energía.' }
            else { Add-H 'Info' "$txt. En reposo el enlace baja por ahorro de energía: mídelo con la gráfica trabajando." }
        }
        if ($gpu.Nombre -match 'GTX\s*(9|10)\d\d|GT\s*\d|MX\s*\d' -and $gpu.Nombre -notmatch 'RTX') { Add-H 'Info' 'Resizable BAR: esta gráfica es anterior a la serie RTX y no lo soporta; no hay nada que activar.' }
        elseif ($gpu.Nombre -match 'NVIDIA|GeForce|RTX|GTX') {
            $smi = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue; if ($smi) { $smi = $smi.Source } else { $smi = Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe' }
            if (Test-Path -LiteralPath $smi) {
                $r = Invoke-Proceso $smi '-q -d MEMORY' 30 'nvidia-smi' -LatidoSeg 60
                $fb = [regex]::Match($r.Salida, 'FB Memory Usage\s+Total\s*:\s*(\d+)\s*MiB'); $b1 = [regex]::Match($r.Salida, 'BAR1 Memory Usage\s+Total\s*:\s*(\d+)\s*MiB')
                if ($fb.Success -and $b1.Success) {
                    if ([int]$b1.Groups[1].Value -ge [int]$fb.Groups[1].Value * 0.9) { Add-H 'OK' 'Resizable BAR activado (BAR1 igual a la VRAM).' }
                    else { Add-H 'Mejora' "Resizable BAR desactivado (BAR1 $($b1.Groups[1].Value) MiB frente a $($fb.Groups[1].Value) MiB de VRAM). Da algo de rendimiento en juegos compatibles; requiere UEFI y gráfica RTX." "Actívalo: $dondeBar. Primero Above 4G, luego Re-Size BAR." }
                } else { Add-H 'Info' 'No se pudo leer Resizable BAR con nvidia-smi.' }
            } else { Add-H 'Info' 'Resizable BAR: no se puede comprobar sin nvidia-smi (driver oficial de NVIDIA).' }
        } else { Add-H 'Info' 'Resizable BAR / Smart Access Memory: solo se comprueba en NVIDIA. En AMD mira en el Software Adrenalin > Rendimiento.' }
    }
} catch { Add-H 'Info' "No se pudo leer la gráfica ($($_.Exception.Message))." }

# --- Antigüedad de la BIOS
if ($bios.ReleaseDate -and $bios.ReleaseDate -lt (Get-Date).AddYears(-3)) { Add-H 'Info' "BIOS de hace más de 3 años ($($bios.ReleaseDate.ToString('MM/yyyy'))). Mira en la web del fabricante si hay versión nueva con mejoras de memoria o CPU; no la actualices si el equipo va bien." }

# --- Resultado
foreach ($x in $h) {
    $ic = switch ($x.Estado) { 'OK' { $E.OK } 'Mejora' { $E.Aviso } default { $E.Info } }
    Write-Output "$ic $($x.Texto)"
    if ($x.Opcion) { Write-Output "      → $($x.Opcion)" }
}
$mejoras = @($h | Where-Object { $_.Estado -eq 'Mejora' }).Count
if ($mejoras) {
    $bl = $null; try { $bl = @(Get-BitLockerVolume -ErrorAction Stop | Where-Object { $_.ProtectionStatus -eq 'On' }) } catch { }
    if ($bl) { Write-Output "$($E.Aviso) BitLocker está activo: antes de entrar en la BIOS suspéndelo un reinicio (si no, pedirá la clave de recuperación). En PowerShell: Suspend-BitLocker -MountPoint $env:SystemDrive -RebootCount 1" }
    Write-Output "$($E.Info) Para entrar en la BIOS: Mantenimiento > «Control de energía» > Reiniciar a BIOS UEFI. Cambia de una en una, guarda y comprueba que arranca antes de seguir con la siguiente."
}
Write-Output "$($E.OK) Lectura hecha: $mejoras opción(es) de la BIOS por mejorar. No se ha cambiado nada."
Write-Log "Asesor_BIOS: $($h.Count) comprobaciones, $mejoras mejoras sugeridas"
