# =====================================================================
#  Motor del diagnóstico completo - Nitrit0
#  Define $Pruebas (lista de pruebas). Cada una devuelve Estado (OK / Aviso / Fallo / Info),
#  Resumen y Detalle. Ninguna prueba modifica el equipo ni borra datos.
#  Modo 'Rapido' (~1 min) y 'Completo' (añade pruebas largas: RAM, CPU en carga, disco, SFC...).
# =====================================================================

# --- Código C# para las pruebas de carga de CPU y de RAM ---
$script:CsCodigo = @'
using System;
using System.Threading;

public static class NitEstres
{
    private static Thread[] hs;
    private static long total;
    public static void Iniciar(int segundos)
    {
        int n = Environment.ProcessorCount;
        DateTime fin = DateTime.UtcNow.AddSeconds(segundos);
        total = 0;
        hs = new Thread[n];
        for (int i = 0; i < n; i++)
        {
            hs[i] = new Thread(delegate ()
            {
                double x = 1.0001; long c = 0;
                while (DateTime.UtcNow < fin)
                {
                    for (int k = 0; k < 200000; k++) { x = Math.Sqrt(x * 1.000001 + k); }
                    c += 200000;
                }
                Interlocked.Add(ref total, c);
            });
            hs[i].IsBackground = true;
            hs[i].Start();
        }
    }
    public static bool Activo { get { if (hs == null) return false; foreach (Thread h in hs) { if (h.IsAlive) return true; } return false; } }
    public static long Total { get { return Interlocked.Read(ref total); } }
}

public static class NitRam
{
    // Devuelve { errores, MB probados }
    public static long[] Probar(int mb)
    {
        long n = (long)mb * 1024 * 1024 / 8;
        long[] a = new long[n];
        long errores = 0;
        long[] patrones = new long[] { 0x5555555555555555L, unchecked((long)0xAAAAAAAAAAAAAAAAUL), 0L, -1L };
        foreach (long p in patrones)
        {
            for (long i = 0; i < n; i++) a[i] = p;
            for (long i = 0; i < n; i++) if (a[i] != p) errores++;
        }
        for (long i = 0; i < n; i++) a[i] = i;
        for (long i = 0; i < n; i++) if (a[i] != i) errores++;
        return new long[] { errores, mb };
    }
}
'@

$script:RaizKit = Split-Path -Parent $PSScriptRoot
# --- Preludio común: se antepone al código de cada prueba ---
$script:Prelude = @"
`$ErrorActionPreference = 'Stop'
function Res([string]`$e, [string]`$r, [string]`$d = '', `$m = `$null) { [pscustomobject]@{ Estado = `$e; Resumen = `$r; Detalle = `$d; Metricas = `$m } }
function Sube([string]`$actual, [string]`$nuevo) { `$o = @{ OK = 0; Info = 0; Aviso = 1; Fallo = 2 }; if (`$o[`$nuevo] -gt `$o[`$actual]) { `$nuevo } else { `$actual } }
`$RaizKit = '$($script:RaizKit)'
if (Test-Path (Join-Path `$RaizKit 'Scripts\Sensores.ps1')) { . (Join-Path `$RaizKit 'Scripts\Sensores.ps1') }
function Ev(`$f) { @(Get-WinEvent -FilterHashtable `$f -ErrorAction SilentlyContinue) }
function CargarCs { if (-not ('NitEstres' -as [type])) { Add-Type -TypeDefinition `$CsCodigo } }
`$CsCodigo = @'
$($script:CsCodigo)
'@
"@

$script:Pruebas = @(

@{ Id='sistema'; Grupo='Sistema'; Nombre='Sistema y Windows'; Modo='Rapido'; Seg=8; Codigo=@'
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$bios = Get-CimInstance Win32_BIOS
$e = 'OK'; $av = @()
$dias = [math]::Floor(((Get-Date) - $os.LastBootUpTime).TotalDays)
if ($dias -gt 30) { $e = 'Aviso'; $av += "Lleva $dias días sin reiniciarse" }
$pend = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
if ($pend) { $e = 'Aviso'; $av += 'Hay un reinicio pendiente' }
$lic = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'" | Select-Object -First 1
if ($lic -and $lic.LicenseStatus -ne 1) { $e = 'Aviso'; $av += 'Windows no está activado' }
$d = @(
  "Equipo: $($cs.Manufacturer) $($cs.Model)",
  "Nº de serie: $($bios.SerialNumber)",
  ("BIOS: {0} ({1:dd/MM/yyyy})" -f $bios.SMBIOSBIOSVersion, $bios.ReleaseDate),
  "Windows: $($os.Caption) $($os.Version) (compilación $($os.BuildNumber))",
  ("Instalado: {0:dd/MM/yyyy}" -f $os.InstallDate),
  ("Último arranque: {0:dd/MM/yyyy HH:mm} (hace $dias días)" -f $os.LastBootUpTime)
) -join "`n"
$res = if ($av) { $av -join '. ' } else { "$($cs.Manufacturer) $($cs.Model) · $($os.Caption)" }
Res $e $res $d
'@ },

@{ Id='win11'; Grupo='Windows'; Nombre='Compatibilidad y soporte de Windows'; Modo='Rapido'; Seg=6; Codigo=@'
$os = Get-CimInstance Win32_OperatingSystem; $cs = Get-CimInstance Win32_ComputerSystem; $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$build = [int]$os.BuildNumber; $empresa = ($os.Caption -match 'Enterprise|Education|Empresa|Educaci')
$d = @(); $falta = @(); $av = @()
# --- Fin de soporte según el calendario de Microsoft (ediciones Home/Pro) ---
$fin = @{ 19045 = '14/10/2025'; 22000 = '10/10/2023'; 22621 = '08/10/2024'; 22631 = '11/11/2025'; 26100 = '13/10/2026'; 26200 = '13/10/2027' }
$versiones = @{ 19045 = 'Windows 10 22H2'; 22000 = 'Windows 11 21H2'; 22621 = 'Windows 11 22H2'; 22631 = 'Windows 11 23H2'; 26100 = 'Windows 11 24H2'; 26200 = 'Windows 11 25H2' }
$nombreV = if ($versiones[$build]) { $versiones[$build] } else { "$($os.Caption) (compilación $build)" }
$d += "Versión instalada: $nombreV"
$estado = 'OK'; $texto = "$nombreV"
if ($fin[$build] -and -not $empresa) {
  $f = [datetime]::ParseExact($fin[$build], 'dd/MM/yyyy', $null)
  if ($f -lt (Get-Date)) { $estado = 'Aviso'; $av += "$nombreV ya no recibe actualizaciones de seguridad (terminó el $($fin[$build]) para Home/Pro)" } else { $d += "Soporte hasta el $($fin[$build]) (ediciones Home/Pro)." }
} elseif ($empresa) { $d += 'Edición Enterprise/Education: el calendario de soporte es más largo; consúltalo en Microsoft.' }
# --- Requisitos de Windows 11 ---
$ramGB = $cs.TotalPhysicalMemory / 1GB; if ($ramGB -lt 3.9) { $falta += "RAM insuficiente ($([math]::Round($ramGB,1)) GB; mínimo 4 GB)" }
try { $v = Get-Volume -DriveLetter $env:SystemDrive[0]; if ($v.Size / 1GB -lt 64) { $falta += "Disco de menos de 64 GB" } } catch { }
if ($cpu.NumberOfCores -lt 2) { $falta += 'Menos de 2 núcleos' }; if ($cpu.MaxClockSpeed -lt 1000) { $falta += 'Frecuencia inferior a 1 GHz' }; if ($cpu.AddressWidth -ne 64) { $falta += 'Procesador de 32 bits' }
$nom = $cpu.Name; $cpuOk = $null
if ($nom -match 'Core\(TM\)\s*i[3579]-(\d{3,5})') { $n = $matches[1]; $g = if ($n.Length -eq 5) { [int]$n.Substring(0, 2) } elseif ($n.Length -eq 4 -and $n.StartsWith('1')) { [int]$n.Substring(0, 2) } elseif ($n.Length -eq 3) { 1 } else { [int]$n.Substring(0, 1) }; $cpuOk = ($g -ge 8); if (-not $cpuOk) { $falta += "Procesador Intel de $g.ª generación (se necesita 8.ª o posterior)" } }
elseif ($nom -match 'Ryzen\s*\d\s*(?:PRO\s*)?(\d)\d{3}') { $cpuOk = ([int]$matches[1] -ge 2); if (-not $cpuOk) { $falta += 'Procesador Ryzen de 1.ª generación (se necesita Zen+ / serie 2000 o posterior)' } }
elseif ($nom -match 'Ultra|Snapdragon|Core\(TM\)\s*[3579]\s') { $cpuOk = $true }
$d += "Procesador: $nom → " + $(if ($null -eq $cpuOk) { 'no se puede confirmar con la lista oficial' } elseif ($cpuOk) { 'generación compatible' } else { 'generación NO compatible' })
$tpm2 = $false; try { $t = Get-CimInstance -Namespace root/cimv2/security/microsofttpm -ClassName Win32_Tpm -ErrorAction Stop; $tpm2 = ($t.SpecVersion -match '^2\.') ; $d += "TPM: versión $($t.SpecVersion)" } catch { $d += 'TPM: no detectado' }
if (-not $tpm2) { $falta += 'No hay TPM 2.0' }
$uefi = $true; $sb = $null
try { $sb = Confirm-SecureBootUEFI -ErrorAction Stop; $d += "Arranque UEFI: sí · Arranque seguro: $(if ($sb) { 'activado' } else { 'desactivado (puede activarse en la BIOS)' })"; if (-not $sb) { $falta += 'Arranque seguro desactivado (activable en la BIOS)' } } catch { $uefi = $false; $d += 'Arranque: BIOS heredada (Legacy), no UEFI'; $falta += 'El equipo arranca en modo Legacy (necesita UEFI + arranque seguro)' }
$d += ("RAM: {0:N1} GB · Disco del sistema: {1}" -f $ramGB, $(try { '{0:N0} GB' -f ((Get-Volume -DriveLetter $env:SystemDrive[0]).Size / 1GB) } catch { 'n/d' }))
$yaW11 = ($build -ge 22000)
if ($yaW11) { $d += 'Este equipo ya ejecuta Windows 11.' }
elseif ($falta.Count) { $d += "No cumple los requisitos de Windows 11:"; $falta | ForEach-Object { $d += "  · $_" } } else { $d += 'Cumple los requisitos de Windows 11: puede actualizarse.' }
if ($av) { return (Res 'Aviso' ($av -join '. ') ($d -join "`n") @{ Windows = $nombreV; Compatible11 = (-not $falta.Count) }) }
if ($yaW11) { return (Res 'OK' "$nombreV con soporte vigente" ($d -join "`n") @{ Windows = $nombreV; Compatible11 = $true }) }
if ($falta.Count) { return (Res 'Info' "$nombreV · no compatible con Windows 11 ($($falta.Count) requisito(s) sin cumplir)" ($d -join "`n") @{ Windows = $nombreV; Compatible11 = $false }) }
Res 'OK' "$nombreV · cumple los requisitos de Windows 11" ($d -join "`n") @{ Windows = $nombreV; Compatible11 = $true }
'@ },

@{ Id='cpu'; Grupo='Procesador'; Nombre='Procesador (CPU)'; Modo='Rapido'; Seg=10; Codigo=@'
$c = Get-CimInstance Win32_Processor | Select-Object -First 1
# Se espera (máx. ~5 s) a que la carga baje por debajo del 20 %: el propio diagnóstico calienta la CPU y no cuenta como reposo
$cargas = @(); for ($i = 0; $i -lt 7; $i++) { Start-Sleep -Milliseconds 700; $x = (Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average; $cargas += $x; if ($cargas.Count -ge 2 -and $x -lt 20 -and $cargas[-2] -lt 20) { break } }
$carga = [math]::Round((@($cargas | Select-Object -Last 2) | Measure-Object -Average).Average)
$reposo = ($carga -lt 20)
$temp = $null; $origen = ''
try { $sens = Open-Sensores $RaizKit; $lec = Read-Sensores $sens; Close-Sensores $sens; if ($lec -and $null -ne $lec.CpuTemp -and $lec.CpuTemp -ge 15) { $temp = $lec.CpuTemp; $origen = 'sensor real' } } catch { }
if ($null -eq $temp) {
  try {
    $t = @(Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop | ForEach-Object { [math]::Round($_.CurrentTemperature / 10 - 273.15) })
    if ($t -and ($t | Measure-Object -Maximum).Maximum -ge 15) { $temp = ($t | Measure-Object -Maximum).Maximum; $origen = 'zona ACPI, orientativa' }   # por debajo de 15 °C el sensor miente: se trata como sin sensor
  } catch { }
}
$e = 'OK'; $av = @()
if ($c.Status -and $c.Status -ne 'OK') { $e = 'Fallo'; $av += "Estado del procesador: $($c.Status)" }
if ($null -ne $temp) {
  if ($temp -ge 95) { $e = 'Fallo'; $av += "Temperatura crítica ($temp °C)" }
  elseif ($reposo -and $temp -ge 85) { $e = Sube $e 'Aviso'; $av += "Temperatura alta en reposo ($temp °C con carga del $carga %)" }
}
if ($carga -ge 90) { $e = Sube $e 'Aviso'; $av += "Carga muy alta y sostenida ($carga %)" }
$tTxt = if ($null -ne $temp) { "$temp °C ($origen)" } else { 'sin sensor accesible (instala el controlador desde «Componentes» o usa HWiNFO)' }
$d = @(
  "Modelo: $($c.Name.Trim())",
  "Núcleos: $($c.NumberOfCores) · Hilos: $($c.NumberOfLogicalProcessors)",
  "Frecuencia: $($c.CurrentClockSpeed) MHz (máx. $($c.MaxClockSpeed) MHz)",
  ("Carga medida: $carga % " + $(if ($reposo) { '(reposo)' } else { '(el equipo estaba ocupado: esta temperatura NO es de reposo; solo se avisa a partir de 95 °C)' })),
  "Temperatura: $tTxt"
) -join "`n"
$res = if ($av) { $av -join '. ' } else { "$($c.Name.Trim()) · $(if ($reposo) { 'reposo' } else { 'con actividad' }) (carga $carga %)" + $(if ($null -ne $temp) { $(if ($origen -eq 'sensor real') { " · $temp °C" } else { " · ~$temp °C (ACPI)" }) } else { '' }) }
Res $e $res $d @{ TempCpuC = $temp; CargaReposoPct = $carga; EnReposo = $reposo }
'@ },

@{ Id='sensores'; Grupo='Procesador'; Nombre='Temperaturas y ventiladores (sensores reales)'; Modo='Rapido'; Seg=8; Codigo=@'
$cg = 0; try { $cg = [int](Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average } catch { }; $reposoS = ($cg -lt 20)
$sens = Open-Sensores $RaizKit
$lec = Read-Sensores $sens
Close-Sensores $sens
if (-not $lec.Disponible) { return (Res 'Info' ('Sin lectura de sensores avanzados. ' + $lec.Motivo) 'Abre la tarjeta «Componentes» del lanzador para instalar el controlador de sensores (solo hace falta una vez por equipo) o usa HWiNFO.') }
$e = 'OK'; $av = @(); $d = @()
if ($null -ne $lec.CpuTemp -and $lec.CpuTemp -ge 15) {
  $d += "CPU: $($lec.CpuTemp) °C" + $(if ($lec.CpuNucleos.Count) { " (núcleos: " + ($lec.CpuNucleos -join ', ') + ')' } else { '' })
  if ($lec.CpuTemp -ge 95) { $e = 'Fallo'; $av += "CPU a temperatura crítica ($($lec.CpuTemp) °C)" } elseif ($lec.CpuTemp -ge 80 -and $reposoS) { $e = Sube $e 'Aviso'; $av += "CPU muy caliente en reposo ($($lec.CpuTemp) °C con carga del $cg %)" } elseif ($lec.CpuTemp -ge 80) { $d += "Carga del $cg %: la CPU estaba trabajando, esta temperatura no es de reposo." }
} else { $d += 'CPU: temperatura no accesible' }
if ($null -ne $lec.CpuPotenciaW) { $d += "Potencia del procesador: $($lec.CpuPotenciaW) W" }
if ($null -ne $lec.GpuTemp) { $d += "GPU ($($lec.GpuNombre)): $($lec.GpuTemp) °C"; if ($lec.GpuTemp -ge 90) { $e = 'Fallo'; $av += "GPU a temperatura crítica ($($lec.GpuTemp) °C)" } elseif ($lec.GpuTemp -ge 80) { $e = Sube $e 'Aviso'; $av += "GPU muy caliente en reposo ($($lec.GpuTemp) °C)" } }
$maxDisco = $null
foreach ($x in $lec.Discos) { $d += "Disco $($x.Nombre): $($x.Temp) °C" + $(if ($x.Otros) { " (otros sensores del controlador: $($x.Otros))" } else { '' }); if ($null -eq $maxDisco -or $x.Temp -gt $maxDisco) { $maxDisco = $x.Temp }; if ($x.Temp -ge 75) { $e = Sube $e 'Aviso'; $av += "Disco $($x.Nombre) caliente ($($x.Temp) °C)" } }
foreach ($x in $lec.PlacaTemps) { $d += "Placa · $($x.Nombre): $($x.Temp) °C" }
foreach ($x in $lec.Ventiladores) { $d += "Ventilador $($x.Nombre): $($x.RPM) rpm" }
$parados = @($lec.Ventiladores | Where-Object { $_.RPM -eq 0 })
if ($parados.Count -and $null -ne $lec.CpuTemp -and $lec.CpuTemp -ge 70) { $e = Sube $e 'Aviso'; $av += 'Hay ventiladores parados con la CPU caliente' }
if ($lec.Motivo) { $d += "Nota: $($lec.Motivo)" }
$res = if ($av) { $av -join '. ' } else { 'Temperaturas normales' + $(if ($null -ne $lec.CpuTemp) { " · CPU $($lec.CpuTemp) °C" } else { '' }) + $(if ($null -ne $lec.GpuTemp) { " · GPU $($lec.GpuTemp) °C" } else { '' }) + $(if ($lec.Ventiladores.Count) { " · $($lec.Ventiladores.Count) ventilador(es)" } else { '' }) }
Res $e $res ($d -join "`n") @{ TempCpuSensorC = $lec.CpuTemp; TempGpuC = $lec.GpuTemp; TempDiscoMaxC = $maxDisco }
'@ },

@{ Id='memoria'; Grupo='Memoria'; Nombre='Memoria RAM (estado)'; Modo='Rapido'; Seg=3; Codigo=@'
$os = Get-CimInstance Win32_OperatingSystem
$total = $os.TotalVisibleMemorySize / 1MB
$libre = $os.FreePhysicalMemory / 1MB
$uso = [math]::Round((1 - $libre / $total) * 100)
$mods = @(Get-CimInstance Win32_PhysicalMemory)
$e = 'OK'; $av = @()
if ($uso -ge 85) { $e = 'Aviso'; $av += "Memoria casi llena ($uso % en uso)" }
$l = @("Total: {0:N1} GB · En uso: $uso %" -f $total)
foreach ($m in $mods) { $l += ("  {0}: {1} GB · {2} MHz · {3} {4}" -f $m.BankLabel, ($m.Capacity / 1GB), $m.Speed, $m.Manufacturer, ($m.PartNumber + '').Trim()) }
$res = if ($av) { $av -join '. ' } else { ("{0:N1} GB · {1} módulo(s) · {2} % en uso" -f $total, $mods.Count, $uso) }
Res $e $res ($l -join "`n") @{ MemUsoPct = $uso; MemTotalGB = [math]::Round($total, 1) }
'@ },

@{ Id='discos'; Grupo='Almacenamiento'; Nombre='Discos y espacio libre'; Modo='Rapido'; Seg=10; Codigo=@'
$e = 'OK'; $av = @(); $d = @(); $metr = @{}
$pds = @(Get-PhysicalDisk)
foreach ($pd in $pds) {
  $rel = $null; try { $rel = $pd | Get-StorageReliabilityCounter -ErrorAction Stop } catch { }
  $l = "$($pd.FriendlyName) · $($pd.MediaType) · $([math]::Round($pd.Size / 1GB)) GB · Salud: $($pd.HealthStatus)"
  if ($pd.HealthStatus -ne 'Healthy') { $e = 'Fallo'; $av += "$($pd.FriendlyName): estado de salud $($pd.HealthStatus)" }
  elseif (($pd.OperationalStatus -join ',') -ne 'OK') { $e = Sube $e 'Aviso'; $av += "$($pd.FriendlyName): estado operativo $($pd.OperationalStatus -join ',')" }
  if ($rel) {
    if ($null -ne $rel.Wear) {
      $l += " · Desgaste: $($rel.Wear) %"; $metr["DesgastePct"] = [int]$rel.Wear
      if ($rel.Wear -ge 90) { $e = 'Fallo'; $av += "$($pd.FriendlyName): desgaste del $($rel.Wear) % (casi agotado)" }
      elseif ($rel.Wear -ge 80) { $e = Sube $e 'Aviso'; $av += "$($pd.FriendlyName): desgaste del $($rel.Wear) %" }
    }
    if ($null -ne $rel.Temperature -and $rel.Temperature -gt 0) {
      $l += " · $($rel.Temperature) °C"; $metr["TempDiscoC"] = [int]$rel.Temperature
      if ($rel.Temperature -ge 90) { $e = 'Fallo'; $av += "$($pd.FriendlyName): temperatura crítica ($($rel.Temperature) °C)" }
      elseif ($rel.Temperature -ge 80) { $e = Sube $e 'Aviso'; $av += "$($pd.FriendlyName): temperatura alta ($($rel.Temperature) °C)" }
    }
    if ($null -ne $rel.PowerOnHours) { $l += " · $($rel.PowerOnHours) h encendido"; $metr["HorasEncendido"] = [int]$rel.PowerOnHours }
    if ($rel.ReadErrorsUncorrected -gt 0) { $e = Sube $e 'Aviso'; $av += "$($pd.FriendlyName): $($rel.ReadErrorsUncorrected) errores de lectura sin corregir" }
  }
  $d += $l
}
try {
  $pf = @(Get-CimInstance -Namespace root/wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction Stop | Where-Object { $_.PredictFailure })
  if ($pf) { $e = 'Fallo'; $av += 'SMART predice un fallo inminente de un disco' }
} catch { }
$d += ''
$libreC = $null
foreach ($v in @(Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter })) {
  $p = if ($v.Size -gt 0) { [math]::Round($v.SizeRemaining / $v.Size * 100) } else { 0 }
  $d += ("Unidad {0}: {1:N0} GB libres de {2:N0} GB ({3} % libre)" -f $v.DriveLetter, ($v.SizeRemaining / 1GB), ($v.Size / 1GB), $p)
  if ($v.DriveLetter -eq 'C') { $libreC = $p; $metr["LibreCPct"] = $p }
  if ($p -lt 5) { $e = 'Fallo'; $av += "Unidad $($v.DriveLetter): casi sin espacio ($p % libre)" }
  elseif ($p -lt 10) { $e = Sube $e 'Aviso'; $av += "Unidad $($v.DriveLetter): poco espacio ($p % libre)" }
}
$res = if ($av) { $av -join '. ' } else { "$($pds.Count) disco(s) sanos" + $(if ($null -ne $libreC) { " · C: $libreC % libre" } else { '' }) }
Res $e $res ($d -join "`n") $metr
'@ },

@{ Id='bateria'; Grupo='Batería'; Nombre='Batería'; Modo='Rapido'; Seg=3; Codigo=@'
$b = @(Get-CimInstance Win32_Battery)
if (-not $b) { return (Res 'Info' 'No hay batería (equipo de sobremesa o no detectada).') }
$dis = $null; $full = $null; $cic = $null
# powercfg da los datos reales en todos los equipos (WMI falla en muchos portátiles)
$xmlRuta = Join-Path $env:TEMP 'nit_bateria.xml'
try {
  & powercfg.exe /batteryreport /xml /output $xmlRuta *> $null
  $x = [xml](Get-Content -LiteralPath $xmlRuta -Raw)
  $bt = @($x.BatteryReport.Batteries.Battery)[0]
  if ($bt) { $dis = [int]$bt.DesignCapacity; $full = [int]$bt.FullChargeCapacity; if ($bt.CycleCount -and [int]$bt.CycleCount -gt 0) { $cic = [int]$bt.CycleCount } }
} catch { } finally { Remove-Item $xmlRuta -Force -ErrorAction SilentlyContinue }
$d = @("Carga actual: $($b[0].EstimatedChargeRemaining) %")
if ($dis) { $d += "Capacidad de diseño: $dis mWh" }
if ($full) { $d += "Capacidad actual a plena carga: $full mWh" }
if ($cic) { $d += "Ciclos de carga: $cic" }
if ($dis -and $full -and $dis -gt 0) {
  $salud = [math]::Round($full / $dis * 100)
  $d += "Salud de la batería: $salud %"
  $m = @{ BateriaSaludPct = $salud; BateriaCiclos = $cic; BateriaCapacidadmWh = $full }
  if ($salud -lt 60) { return (Res 'Fallo' "Batería muy degradada ($salud % de su capacidad original). Conviene sustituirla." ($d -join "`n") $m) }
  if ($salud -lt 80) { return (Res 'Aviso' "Batería desgastada ($salud % de su capacidad original)." ($d -join "`n") $m) }
  return (Res 'OK' "Batería en buen estado ($salud % de capacidad)" ($d -join "`n") $m)
}
Res 'Info' "Batería detectada ($($b[0].EstimatedChargeRemaining) %), pero Windows no da su capacidad. Usa la tarjeta Batería." ($d -join "`n")
'@ },

@{ Id='gpu'; Grupo='Gráficos'; Nombre='Tarjeta gráfica'; Modo='Rapido'; Seg=3; Codigo=@'
$gs = @(Get-CimInstance Win32_VideoController)
$e = 'OK'; $av = @(); $d = @()
foreach ($g in $gs) {
  $d += ("{0} · Controlador {1} ({2:dd/MM/yyyy})" -f $g.Name, $g.DriverVersion, $g.DriverDate)
  if ($g.ConfigManagerErrorCode -ne 0) { $e = 'Fallo'; $av += "$($g.Name): error de dispositivo código $($g.ConfigManagerErrorCode)" }
  if ($g.Name -match 'Basic Display|B.sico de Microsoft') { $e = Sube $e 'Aviso'; $av += 'Usa el controlador gráfico genérico de Windows (falta el del fabricante)' }
}
$res = if ($av) { $av -join '. ' } elseif ($gs) { ($gs | ForEach-Object { $_.Name }) -join ' + ' } else { 'No se detecta ninguna tarjeta gráfica' }
if (-not $gs) { $e = 'Fallo' }
Res $e $res ($d -join "`n")
'@ },

@{ Id='dispositivos'; Grupo='Dispositivos'; Nombre='Dispositivos con errores'; Modo='Rapido'; Seg=6; Codigo=@'
$bad = @(Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0')
$desact = @($bad | Where-Object { $_.ConfigManagerErrorCode -eq 22 })
$mal = @($bad | Where-Object { $_.ConfigManagerErrorCode -ne 22 })
$d = @()
foreach ($x in $mal) { $d += "ERROR $($x.ConfigManagerErrorCode): $($x.Name) [$($x.PNPClass)]" }
foreach ($x in $desact) { $d += "Desactivado: $($x.Name) [$($x.PNPClass)]" }
if ($mal.Count -gt 0) { return (Res 'Fallo' "$($mal.Count) dispositivo(s) con error: $((@($mal | Select-Object -First 3 | ForEach-Object { '{0} (código {1})' -f $_.Name, $_.ConfigManagerErrorCode })) -join '; ')" ($d -join "`n")) }
if ($desact.Count -gt 0) { return (Res 'Info' "Sin errores ($($desact.Count) dispositivo(s) desactivado(s) a propósito)" ($d -join "`n")) }
Res 'OK' 'Ningún dispositivo con errores'
'@ },

@{ Id='perifericos'; Grupo='Dispositivos'; Nombre='Cámara, audio y Bluetooth'; Modo='Rapido'; Seg=5; Codigo=@'
$e = 'OK'; $av = @(); $d = @()
$grupos = [ordered]@{ 'Cámara' = @('Camera', 'Image'); 'Audio' = @('AudioEndpoint'); 'Bluetooth' = @('Bluetooth') }
$resumen = @()
foreach ($k in $grupos.Keys) {
  $lista = @(Get-PnpDevice -Class $grupos[$k] -PresentOnly -ErrorAction SilentlyContinue)
  $resumen += "$k $($lista.Count)"
  if ($lista.Count -eq 0) { $d += "${k}: no detectado" }
  foreach ($x in $lista) {
    $d += "${k}: $($x.FriendlyName) [$($x.Status)]"
    if ($x.Status -ne 'OK') { $e = Sube $e 'Aviso'; $av += "$k '$($x.FriendlyName)' en estado $($x.Status)" }
  }
}
$res = if ($av) { $av -join '. ' } else { 'Detectados: ' + ($resumen -join ' · ') }
Res $e $res ($d -join "`n")
'@ },

@{ Id='red'; Grupo='Red'; Nombre='Conexión de red'; Modo='Rapido'; Seg=15; Codigo=@'
$e = 'OK'; $av = @(); $d = @()
$cfgs = @(Get-NetIPConfiguration | Where-Object { $_.NetAdapter.Status -eq 'Up' -and $_.IPv4Address })
if (-not $cfgs) { return (Res 'Aviso' 'Sin conexión de red activa (ni cable ni Wi-Fi).') }
foreach ($c in $cfgs) {
  $d += "$($c.InterfaceAlias): IP $($c.IPv4Address.IPAddress) · Puerta de enlace $($c.IPv4DefaultGateway.NextHop) · $($c.NetAdapter.LinkSpeed)"
}
$gw = ($cfgs | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1).IPv4DefaultGateway.NextHop
if ($gw) {
  $pg = @(Test-Connection -ComputerName $gw -Count 3 -ErrorAction SilentlyContinue)
  if ($pg.Count -eq 0) { $e = 'Fallo'; $av += "No responde la puerta de enlace ($gw)" } else { $d += "Router ($gw): respuesta media $([math]::Round(($pg | Measure-Object ResponseTime -Average).Average)) ms" }
}
$pi = @(Test-Connection -ComputerName 1.1.1.1 -Count 4 -ErrorAction SilentlyContinue)
if ($pi.Count -eq 0) { $e = Sube $e 'Aviso'; $av += 'Sin acceso a internet' }
else {
  $media = [math]::Round(($pi | Measure-Object ResponseTime -Average).Average)
  $perd = [math]::Round((4 - $pi.Count) / 4 * 100)
  $d += "Internet (1.1.1.1): $media ms · pérdida de paquetes $perd %"
  if ($perd -gt 0) { $e = Sube $e 'Aviso'; $av += "Pérdida de paquetes ($perd %)" }
  if ($media -gt 150) { $e = Sube $e 'Aviso'; $av += "Latencia alta ($media ms)" }
  try { [void][System.Net.Dns]::GetHostAddresses('www.microsoft.com'); $d += 'DNS: resuelve nombres correctamente' }
  catch { $e = Sube $e 'Aviso'; $av += 'Falla la resolución de nombres (DNS)'; $d += 'DNS: FALLA' }
}
$w = (netsh wlan show interfaces 2>$null | Select-String -Pattern '(Se.al|Signal)\s*:\s*(\d+)%' | Select-Object -First 1)
if ($w) {
  $s = [int]$w.Matches[0].Groups[2].Value
  $d += "Señal Wi-Fi: $s %"
  if ($s -lt 30) { $e = Sube $e 'Aviso'; $av += "Señal Wi-Fi débil ($s %)" }
}
$res = if ($av) { $av -join '. ' } else { 'Conexión correcta' + $(if ($pi.Count) { " · $media ms" } else { '' }) }
Res $e $res ($d -join "`n")
'@ },

@{ Id='eventos'; Grupo='Registros'; Nombre='Errores graves y apagados inesperados'; Modo='Rapido'; Seg=12; Codigo=@'
$desde30 = (Get-Date).AddDays(-30); $desde7 = (Get-Date).AddDays(-7)
$e = 'OK'; $av = @(); $d = @()
$bsod = Ev @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = $desde30 }
if ($bsod.Count) { $e = 'Fallo'; $av += "$($bsod.Count) pantallazo(s) azul(es) en 30 días"; $bsod | Select-Object -First 5 | ForEach-Object { $d += ("Pantallazo azul {0:dd/MM HH:mm}: {1}" -f $_.TimeCreated, (($_.Message -split "`n")[0])) } }
$disco = Ev @{ LogName = 'System'; ProviderName = 'disk', 'Ntfs'; Id = 7, 11, 51, 52, 55, 153; StartTime = $desde30 }
if ($disco.Count) { $e = 'Fallo'; $av += "$($disco.Count) error(es) de disco o sistema de archivos en 30 días"; $disco | Select-Object -First 5 | ForEach-Object { $d += ("Disco {0:dd/MM HH:mm} (Id {1}): {2}" -f $_.TimeCreated, $_.Id, (($_.Message -split "`n")[0])) } }
$whea = Ev @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $desde30 }
if ($whea.Count) {
  $graves = @($whea | Where-Object { $_.Level -le 2 })
  if ($graves.Count) { $e = 'Fallo'; $av += "$($graves.Count) error(es) de hardware (WHEA) graves" } else { $e = Sube $e 'Aviso'; $av += "$($whea.Count) aviso(s) de hardware (WHEA, corregidos)" }
  $whea | Select-Object -First 3 | ForEach-Object { $d += ("Hardware {0:dd/MM HH:mm}: {1}" -f $_.TimeCreated, (($_.Message -split "`n")[0])) }
}
$kp = Ev @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $desde30 }
if ($kp.Count) { $e = Sube $e 'Aviso'; $av += "$($kp.Count) apagado(s) inesperado(s) (corte de energía o cuelgue) en 30 días"; $kp | Select-Object -First 3 | ForEach-Object { $d += ("Apagado inesperado: {0:dd/MM/yyyy HH:mm}" -f $_.TimeCreated) } }
$graves7 = Ev @{ LogName = 'System'; Level = 1, 2; StartTime = $desde7 }
$d += ''
$d += "Errores/críticos del sistema en 7 días: $($graves7.Count)"
$graves7 | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object { $d += "  $($_.Count) × $($_.Name)" }
if ($graves7.Count -gt 100) { $e = Sube $e 'Aviso'; $av += "Muchos errores en el registro del sistema ($($graves7.Count) en 7 días)" }
$res = if ($av) { $av -join '. ' } else { "Sin pantallazos azules, errores de disco ni fallos de hardware ($($graves7.Count) errores menores en 7 días)" }
Res $e $res ($d -join "`n") @{ Errores7d = $graves7.Count; Pantallazos30d = $bsod.Count; ErroresDisco30d = $disco.Count; ApagadosInesperados30d = $kp.Count }
'@ },

@{ Id='smart'; Grupo='Almacenamiento'; Nombre='SMART detallado de los discos (smartctl)'; Modo='Rapido'; Seg=12; Codigo=@'
$smartctl = Join-Path $RaizKit 'Apps\Disk\smartmontools\bin\smartctl.exe'
if (-not (Test-Path -LiteralPath $smartctl)) { return (Res 'Info' 'smartmontools no está en el kit (carpeta Disk\smartmontools).') }
$scan = (& $smartctl --scan 2>&1 | Out-String)
$devs = @(); foreach ($l in ($scan -split "`n")) { if ($l -match '^(\S+)\s+-d\s+(\S+)') { $devs += [pscustomobject]@{ Dev = $matches[1]; Tipo = $matches[2] } } }
if (-not $devs) { return (Res 'Info' 'smartctl no encontró discos (probablemente faltan permisos de administrador).' $scan) }
$e = 'OK'; $av = @(); $d = @(); $m = @{}; $i = 0; $vistos = @{}
foreach ($dv in $devs) {
  $raw = (& $smartctl -a -j $dv.Dev -d $dv.Tipo 2>&1 | Out-String)
  try { $j = $raw | ConvertFrom-Json } catch { $d += "$($dv.Dev): no se pudo leer ($($raw.Substring(0, [Math]::Min(120, $raw.Length))))"; continue }
  $clave = "$($j.serial_number)|$($j.model_name)"; if ($j.serial_number -and $vistos[$clave]) { continue }; $vistos[$clave] = $true
  $nom = if ($j.model_name) { $j.model_name } else { $dv.Dev }
  $cap = if ($j.user_capacity.bytes) { "{0:N0} GB" -f ($j.user_capacity.bytes / 1GB) } else { '' }
  $d += "== $nom  $cap  (serie $($j.serial_number), firmware $($j.firmware_version))"
  if ($j.smartctl.messages | Where-Object { $_.string -match 'ermission|denied|Administrator' }) { $d += '   Sin permisos: ejecuta el lanzador como administrador.'; continue }
  $pas = $j.smart_status.passed
  if ($null -ne $pas) { $d += "   Evaluación SMART global: $(if ($pas) { 'CORRECTA' } else { 'FALLO' })"; if (-not $pas) { $e = 'Fallo'; $av += "${nom}: SMART global en FALLO" } }
  $t = $j.temperature.current; if ($null -ne $t) { $d += "   Temperatura: $t °C"; if ($t -ge 75) { $e = Sube $e 'Aviso'; $av += "${nom}: temperatura alta ($t °C)" } }
  $h = $j.power_on_time.hours; if ($null -ne $h) { $d += "   Horas encendido: $h (≈ $([math]::Round($h / 24)) días)" }
  $metricas = @{}
  if ($j.nvme_smart_health_information_log) {
    $n = $j.nvme_smart_health_information_log
    $d += "   NVMe: aviso crítico $($n.critical_warning) · repuesto disponible $($n.available_spare) % (umbral $($n.available_spare_threshold) %) · uso $($n.percentage_used) %"
    $d += "   Errores de medio: $($n.media_errors) · entradas de error: $($n.num_err_log_entries) · apagados inesperados: $($n.unsafe_shutdowns) · ciclos de encendido: $($n.power_cycles)"
    if ($n.data_units_written) { $d += ("   Datos escritos: {0:N1} TB" -f ($n.data_units_written * 512000 / 1TB)) }
    if ($n.critical_warning -gt 0) { $e = 'Fallo'; $av += "${nom}: aviso crítico NVMe ($($n.critical_warning))" }
    if ($n.media_errors -gt 0) { $e = Sube $e 'Aviso'; $av += "${nom}: $($n.media_errors) errores de medio" }
    if ($n.available_spare -lt $n.available_spare_threshold) { $e = 'Fallo'; $av += "${nom}: repuesto por debajo del umbral" }
    if ($n.percentage_used -ge 90) { $e = 'Fallo'; $av += "${nom}: desgaste del $($n.percentage_used) %" } elseif ($n.percentage_used -ge 80) { $e = Sube $e 'Aviso'; $av += "${nom}: desgaste del $($n.percentage_used) %" }
    $metricas = @{ SmartDesgastePct = $n.percentage_used; SmartErroresMedio = $n.media_errors; SmartApagadosInesperados = $n.unsafe_shutdowns; SmartHoras = $h }
  }
  elseif ($j.ata_smart_attributes.table) {
    $tab = @{}; foreach ($a in $j.ata_smart_attributes.table) { $tab[[int]$a.id] = $a }
    $rea = $tab[5]; $pen = $tab[197]; $unc = $tab[198]; $crc = $tab[199]
    $reaV = if ($rea) { [int]$rea.raw.value } else { 0 }; $penV = if ($pen) { [int]$pen.raw.value } else { 0 }; $uncV = if ($unc) { [int]$unc.raw.value } else { 0 }; $crcV = if ($crc) { [int]$crc.raw.value } else { 0 }
    $d += "   Sectores reasignados: $reaV · pendientes: $penV · incorregibles: $uncV · errores CRC de cable: $crcV"
    if ($reaV -gt 0) { $e = Sube $e 'Aviso'; $av += "${nom}: $reaV sectores reasignados" }; if ($reaV -ge 100) { $e = 'Fallo' }
    if ($penV -gt 0 -or $uncV -gt 0) { $e = 'Fallo'; $av += "${nom}: sectores pendientes/incorregibles ($penV/$uncV): haz copia de seguridad ya" }
    if ($crcV -gt 0) { $e = Sube $e 'Aviso'; $av += "${nom}: errores CRC ($crcV): revisa el cable SATA" }
    $vida = $null; foreach ($id in 231, 233) { if ($tab[$id]) { $vida = [int]$tab[$id].value } }
    if ($null -eq $vida -and $tab[177]) { $vida = [int]$tab[177].value }
    if ($null -ne $vida) { $d += "   Vida restante estimada (SSD): $vida %"; if ($vida -le 10) { $e = 'Fallo'; $av += "${nom}: vida restante $vida %" } elseif ($vida -le 25) { $e = Sube $e 'Aviso'; $av += "${nom}: vida restante $vida %" } }
    $metricas = @{ SmartReasignados = $reaV; SmartPendientes = $penV; SmartDesgastePct = $(if ($null -ne $vida) { 100 - $vida } else { $null }); SmartHoras = $h }
  } else { $d += '   Este disco no expone atributos SMART detallados.' }
  if ($i -eq 0) { $m = $metricas }; $i++
}
$res = if ($av) { $av -join '. ' } else { "$i disco(s) con SMART correcto" }
Res $e $res ($d -join "`n") $m
'@ },

@{ Id='integridad'; Grupo='Windows'; Nombre='Integridad de la imagen de Windows'; Modo='Rapido'; Seg=15; Codigo=@'
$r = Repair-WindowsImage -Online -CheckHealth
switch ("$($r.ImageHealthState)") {
  'Healthy'     { Res 'OK' 'La imagen de Windows está sana' "Estado: Healthy" }
  'Repairable'  { Res 'Aviso' 'La imagen de Windows está dañada pero es reparable (ejecuta DISM /RestoreHealth y SFC)' "Estado: Repairable" }
  default       { Res 'Fallo' "Imagen de Windows en estado: $($r.ImageHealthState)" "Estado: $($r.ImageHealthState)" }
}
'@ },

@{ Id='seguridad'; Grupo='Seguridad'; Nombre='Antivirus, firewall y cifrado'; Modo='Rapido'; Seg=8; Codigo=@'
$e = 'OK'; $av = @(); $d = @()
try {
  $avs = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop)
  foreach ($a in $avs) { $d += "Antivirus: $($a.displayName)" }
} catch { }
try {
  $m = Get-MpComputerStatus -ErrorAction Stop
  $d += "Microsoft Defender: protección en tiempo real $(if ($m.RealTimeProtectionEnabled) { 'activa' } else { 'DESACTIVADA' }) · firmas de hace $($m.AntivirusSignatureAge) día(s)"
  if (-not $m.RealTimeProtectionEnabled -and -not ($avs | Where-Object { $_.displayName -notmatch 'Defender' })) { $e = 'Aviso'; $av += 'Defender sin protección en tiempo real y sin otro antivirus' }
  if ($m.AntivirusSignatureAge -gt 7) { $e = Sube $e 'Aviso'; $av += "Firmas del antivirus desactualizadas ($($m.AntivirusSignatureAge) días)" }
} catch { $d += 'Defender no disponible (puede haber otro antivirus gestionándolo)' }
try {
  $fw = @(Get-NetFirewallProfile -ErrorAction Stop)
  foreach ($p in $fw) { $d += "Firewall $($p.Name): $(if ($p.Enabled) { 'activo' } else { 'DESACTIVADO' })" }
  if ($fw | Where-Object { -not $_.Enabled }) { $e = Sube $e 'Aviso'; $av += 'Hay perfiles del firewall desactivados' }
} catch { }
try { $d += "Arranque seguro (Secure Boot): $(if (Confirm-SecureBootUEFI) { 'activado' } else { 'desactivado' })" } catch { $d += 'Arranque seguro: no compatible o BIOS heredada' }
try { $t = Get-Tpm -ErrorAction Stop; $d += "TPM: $(if ($t.TpmPresent) { if ($t.TpmReady) { 'presente y listo' } else { 'presente, no listo' } } else { 'no presente' })" } catch { }
try { $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop; $d += "BitLocker en $($env:SystemDrive): $($bl.ProtectionStatus)" } catch { }
$res = if ($av) { $av -join '. ' } else { 'Antivirus y firewall activos' }
Res $e $res ($d -join "`n")
'@ },

@{ Id='actualizaciones'; Grupo='Windows'; Nombre='Actualizaciones de Windows'; Modo='Rapido'; Seg=8; Codigo=@'
# Historial real de Windows Update (Get-HotFix no recoge muchas actualizaciones acumulativas)
$hist = @()
try {
  $s = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
  $n = $s.GetTotalHistoryCount()
  if ($n -gt 0) { $hist = @($s.QueryHistory(0, [math]::Min($n, 60)) | Where-Object { $_.ResultCode -eq 2 -and $_.Title -and $_.Title -notmatch 'Defender|inteligencia de seguridad|Security Intelligence|Malicious Software|eliminaci.n de software' } | Sort-Object Date -Descending) }
} catch { }
if ($hist.Count) {
  $dias = [math]::Floor(((Get-Date) - $hist[0].Date).TotalDays)
  $d = ($hist | Select-Object -First 8 | ForEach-Object { "{0:dd/MM/yyyy}  {1}" -f $_.Date, $_.Title }) -join "`n"
  if ($dias -gt 90) { return (Res 'Aviso' "La última actualización instalada con éxito fue hace $dias días. Revisa Windows Update." $d @{ DiasUltimaActualizacion = $dias }) }
  return (Res 'OK' "Última actualización instalada hace $dias días" $d @{ DiasUltimaActualizacion = $dias })
}
$u = @(Get-HotFix | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending)
if (-not $u) { return (Res 'Info' 'No se puede determinar la fecha de la última actualización.') }
$dias = [math]::Floor(((Get-Date) - $u[0].InstalledOn).TotalDays)
$d = ($u | Select-Object -First 8 | ForEach-Object { ("{0:dd/MM/yyyy}  {1}  {2}" -f $_.InstalledOn, $_.HotFixID, $_.Description) }) -join "`n"
if ($dias -gt 90) { return (Res 'Aviso' "Última actualización registrada hace $dias días (según el historial de revisiones)" $d) }
Res 'OK' "Última actualización hace $dias días ($($u[0].HotFixID))" $d
'@ },

@{ Id='arranque'; Grupo='Windows'; Nombre='Programas de inicio'; Modo='Rapido'; Seg=3; Codigo=@'
$s = @(Get-CimInstance Win32_StartupCommand)
$d = ($s | Sort-Object Name | ForEach-Object { "$($_.Name)  [$($_.Location)]" }) -join "`n"
if ($s.Count -gt 25) { return (Res 'Aviso' "Demasiados programas al arrancar ($($s.Count)); pueden ralentizar el inicio. Revisa Autoruns." $d) }
Res 'OK' "$($s.Count) programas de inicio" $d
'@ },

# ---------------- Pruebas largas (solo modo Completo) ----------------

@{ Id='ram_prueba'; Grupo='Memoria'; Nombre='Prueba de memoria RAM (parcial)'; Modo='Completo'; Seg=40; Codigo=@'
CargarCs
$libreMB = [int]((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1KB)
$mb = [math]::Min(1024, [int]($libreMB * 0.4))
if ($mb -lt 64) { return (Res 'Info' "Poca memoria libre ($libreMB MB) para hacer la prueba. Cierra programas y repite.") }
$sw = [Diagnostics.Stopwatch]::StartNew()
$r = [NitRam]::Probar($mb)
$sw.Stop()
$d = "Probados $($r[1]) MB con patrones 0x55, 0xAA, 0x00, 0xFF y direccionamiento en $([math]::Round($sw.Elapsed.TotalSeconds)) s.`nEs una prueba parcial desde Windows: no revisa toda la RAM. Para una comprobación completa usa MemTest86 (USB)."
if ($r[0] -gt 0) { return (Res 'Fallo' "$($r[0]) errores de lectura/escritura en la RAM. Repite con MemTest86 y prueba cada módulo por separado." $d) }
Res 'OK' "Sin errores en $($r[1]) MB probados" $d
'@ },

@{ Id='cpu_estres'; Grupo='Procesador'; Nombre='CPU bajo carga (20 s)'; Modo='Completo'; Seg=32; Codigo=@'
CargarCs
function TempAcpi { try { $t = @(Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop | ForEach-Object { $_.CurrentTemperature / 10 - 273.15 }); [math]::Round(($t | Measure-Object -Maximum).Maximum) } catch { $null } }
$max0 = (Get-CimInstance Win32_Processor | Select-Object -First 1).MaxClockSpeed
function FrecActual { try { $pp = (Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'" -ErrorAction Stop).PercentProcessorPerformance; if ($pp) { [int]($max0 * $pp / 100) } else { $null } } catch { $null } }
for ($i = 0; $i -lt 10; $i++) { $x = (Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average; if ($x -lt 20) { break }; Start-Sleep -Seconds 1 }   # esperar a que baje la carga antes de medir el reposo
$t0 = TempAcpi
$sens = $null; try { $sens = Open-Sensores $RaizKit } catch { }
try { $l0 = Read-Sensores $sens; if ($l0 -and $null -ne $l0.CpuTemp) { $t0 = $l0.CpuTemp } } catch { }
$realT = $false; $pot = @()
[NitEstres]::Iniciar(20)
$clk = @(); $tmp = @()
Start-Sleep -Milliseconds 1500
while ([NitEstres]::Activo) {
  $lec = $null; if ($sens) { try { $lec = Read-Sensores $sens } catch { } }
  if ($lec -and $lec.CpuMHzMax) { $clk += $lec.CpuMHzMax } else { $fx = FrecActual; if ($fx) { $clk += $fx } }
  if ($lec -and $null -ne $lec.CpuTemp -and $lec.CpuTemp -ge 15) { $tmp += $lec.CpuTemp; $realT = $true } else { $tx = TempAcpi; if ($null -ne $tx) { $tmp += $tx } }
  if ($lec -and $null -ne $lec.CpuPotenciaW) { $pot += $lec.CpuPotenciaW }
  Start-Sleep -Seconds 2
}
$ops = [NitEstres]::Total
try { Close-Sensores $sens } catch { }
$e = 'OK'; $av = @()
$clkMin = if ($clk) { ($clk | Measure-Object -Minimum).Minimum } else { $null }
$clkMax = if ($clk) { ($clk | Measure-Object -Maximum).Maximum } else { $null }
$tMax = if ($tmp) { ($tmp | Measure-Object -Maximum).Maximum } else { $null }
$sensorFijo = (-not $realT -and $tmp.Count -gt 2 -and @($tmp | Select-Object -Unique).Count -eq 1)
if ($null -ne $tMax -and -not $sensorFijo) {
  if ($tMax -ge 100) { $e = 'Fallo'; $av += "Temperatura crítica bajo carga ($tMax °C)" }
  elseif ($tMax -ge 92) { $e = 'Aviso'; $av += "Temperatura muy alta bajo carga ($tMax °C)" }
}
if ($clk -and $clkMin -lt ($max0 * 0.6)) { $e = Sube $e 'Aviso'; $av += "La frecuencia cae a $clkMin MHz bajo carga (base $max0 MHz): posible límite térmico o de energía" }
$lT = if ($null -eq $tMax) { 'Temperatura: sin sensor accesible por WMI (usa HWiNFO o Core Temp)' }
      elseif ($sensorFijo) { "Temperatura: el sensor ACPI marca siempre $tMax °C: no es fiable (usa HWiNFO o Core Temp)" }
      else { "Temperatura: $t0 °C antes → $tMax °C máxima bajo carga" }
$lF = if ($clk) { "Frecuencia durante la carga: $clkMin - $clkMax MHz (base $max0 MHz)" } else { 'Frecuencia durante la carga: no medible en este equipo' }
$lP = if ($pot.Count) { "Potencia del procesador: media {0} W · máx. {1} W" -f [math]::Round(($pot | Measure-Object -Average).Average, 1), [math]::Round(($pot | Measure-Object -Maximum).Maximum, 1) } else { $null }
$d = @(("Operaciones: {0:N0} millones" -f ($ops / 1e6)), $lF, $lT, $lP, $(if ($realT) { '(Temperatura y frecuencia leídas con sensores reales)' } else { $null })) | Where-Object { $_ } | ForEach-Object { $_ }; $d = $d -join "`n"
$res = if ($av) { $av -join '. ' } else { 'Estable durante 20 s' + $(if ($clk) { " · $clkMin-$clkMax MHz" } else { '' }) + $(if ($null -ne $tMax -and -not $sensorFijo) { " · reposo $t0 °C → máx. $tMax °C con carga" } else { '' }) }
Res $e $res $d @{ TempCpuMaxCargaC = $tMax; FrecMinCargaMHz = $clkMin; FrecMaxCargaMHz = $clkMax; PotenciaMediaW = $(if ($pot.Count) { [math]::Round(($pot | Measure-Object -Average).Average, 1) } else { $null }) }
'@ },

@{ Id='disco_vel'; Grupo='Almacenamiento'; Nombre='Velocidad del disco (256 MB)'; Modo='Completo'; Seg=15; Codigo=@'
$ruta = Join-Path $env:TEMP 'nit_disco_prueba.bin'
$mb = 256
$buf = New-Object byte[] 1048576
(New-Object Random).NextBytes($buf)
try {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $fs = New-Object IO.FileStream($ruta, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None, 1048576, [IO.FileOptions]::WriteThrough)
  for ($i = 0; $i -lt $mb; $i++) { $fs.Write($buf, 0, $buf.Length) }
  $fs.Flush(); $fs.Close(); $sw.Stop()
  $w = [math]::Round($mb / $sw.Elapsed.TotalSeconds)
  $sw.Restart()
  $fs = New-Object IO.FileStream($ruta, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None, 1048576, [IO.FileOptions]::SequentialScan)
  while ($fs.Read($buf, 0, $buf.Length) -gt 0) { }
  $fs.Close(); $sw.Stop()
  $r = [math]::Round($mb / $sw.Elapsed.TotalSeconds)
} finally { Remove-Item $ruta -Force -ErrorAction SilentlyContinue }
$d = "Escritura secuencial: $w MB/s`nLectura secuencial: $r MB/s (puede estar ayudada por la caché)`nPrueba rápida en $env:TEMP; para medidas precisas usa CrystalDiskMark."
if ($w -lt 10 -or $r -lt 10) { return (Res 'Fallo' "Disco extremadamente lento (escritura $w MB/s, lectura $r MB/s)" $d) }
if ($w -lt 40 -or $r -lt 40) { return (Res 'Aviso' "Disco lento (escritura $w MB/s, lectura $r MB/s)" $d) }
Res 'OK' "Escritura $w MB/s · lectura $r MB/s" $d
'@ },

@{ Id='chkdsk'; Grupo='Almacenamiento'; Nombre='Comprobación del sistema de archivos (C:)'; Modo='Completo'; Seg=120; Codigo=@'
$r = "$(Repair-Volume -DriveLetter C -Scan)"
if ($r -eq 'NoErrorsFound') { return (Res 'OK' 'No se encontraron errores en la unidad C:' "Resultado: $r") }
Res 'Fallo' "Se detectaron errores en la unidad C: ($r). Ejecuta chkdsk /f tras guardar tus datos." "Resultado: $r"
'@ },

@{ Id='sfc'; Grupo='Windows'; Nombre='Archivos del sistema (SFC)'; Modo='Completo'; Seg=600; Codigo=@'
# sfc escribe en la página de códigos OEM: se lee con esa codificación para no romper las tildes
$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = "$env:WINDIR\System32\sfc.exe"; $psi.Arguments = '/verifyonly'
$psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.CreateNoWindow = $true
$pr = [Diagnostics.Process]::Start($psi)
$ms = New-Object IO.MemoryStream; $pr.StandardOutput.BaseStream.CopyTo($ms); $pr.WaitForExit()
$b = $ms.ToArray(); $nulos = 0; foreach ($x in $b) { if ($x -eq 0) { $nulos++ } }
$o = if ($nulos -gt ($b.Length / 4)) { [Text.Encoding]::Unicode.GetString($b) } else { [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage).GetString($b) }
$o = $o -replace "`0", ''
$lineas = @(($o -replace "`r", '') -split "`n" | Where-Object { $_.Trim() -and $_ -notmatch 'comprobaci.n de \d+%|verification \d+% complete' })
$o2 = $lineas -join "`n"
if ($o -match 'no encontr|did not find|not find any') { return (Res 'OK' 'No se encontraron archivos del sistema dañados' $o2) }
if ($o -match 'encontr|found') {
  $cbs = ''
  try { $cbs = (Select-String -Path "$env:WINDIR\Logs\CBS\CBS.log" -Pattern '\[SR\] (Cannot repair|Repairing corrupted|Could not reproject|Hashes? for file)' -ErrorAction Stop | Select-Object -Last 10 | ForEach-Object { $_.Line -replace '^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d, ', '' }) -join "`n" } catch { }
  $extra = if ($cbs) { "`n`nArchivos señalados en CBS.log:`n$cbs" } else { "`n`nEl detalle por archivo está en C:\Windows\Logs\CBS\CBS.log." }
  return (Res 'Aviso' 'SFC detecta archivos de Windows con la integridad alterada (software, no hardware). Ejecuta DISM /RestoreHealth y después SFC /scannow.' ($o2 + $extra))
}
Res 'Info' 'SFC no devolvió un resultado claro' $o2
'@ }

)

# --- Ejecución sin interfaz (se usa desde la ventana y para pruebas por consola) ---
# Ejecuta las pruebas en secuencia y va dejando resultados en $Cola (ConcurrentQueue).
function Start-Diagnostico {
    param([string]$Modo, $Cola, $Ctl, [string[]]$Ids)
    $lista = @($script:Pruebas | Where-Object { ($Modo -eq 'Completo' -or $_.Modo -eq 'Rapido') -and (-not $Ids -or $_.Id -in $Ids) })
    foreach ($p in $lista) {
        if ($Ctl.Cancelar) { $Cola.Enqueue(@{ Tipo = 'Cancelado' }); return }
        $Cola.Enqueue(@{ Tipo = 'Inicio'; Id = $p.Id })
        $sw = [Diagnostics.Stopwatch]::StartNew()
        # Cada prueba corre en su propio hilo con tiempo máximo: una consulta WMI o un smartctl colgados no paran el resto del diagnóstico.
        $limite = [math]::Max(60, [int]$p.Seg * 3)
        $hilo = $null; $rs = $null; $ps = $null
        try {
            $rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'STA'; $rs.Open()
            $ps = [powershell]::Create(); $ps.Runspace = $rs
            [void]$ps.AddScript($script:Prelude + "`n" + $p.Codigo)
            $hilo = $ps.BeginInvoke()
            if ($hilo.AsyncWaitHandle.WaitOne($limite * 1000)) {
                $r = @($ps.EndInvoke($hilo)) | Where-Object { $_ -and $_.Estado } | Select-Object -Last 1
                if (-not $r) { $r = [pscustomobject]@{ Estado = 'Info'; Resumen = 'La prueba no devolvió resultado'; Detalle = (@($ps.Streams.Error | ForEach-Object { "$_" }) -join "`n") } }
                $ps.Dispose(); $rs.Dispose()
            } else {
                # Se abandona el hilo (no se espera a que muera) y se cierran los programas de consola que dejó lanzados
                [void]$ps.BeginStop($null, $null)
                Get-CimInstance Win32_Process -Filter "ParentProcessId=$PID" -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match '^(smartctl|dism|sfc|chkdsk|powercfg|netsh|ipconfig|ping|systeminfo|wevtutil|typeperf|driverquery|bcdedit|manage-bde)\.exe$' } |
                    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
                $r = [pscustomobject]@{ Estado = 'Info'; Resumen = "La prueba no respondió en $limite s y se ha saltado"; Detalle = 'Windows tardó demasiado en contestar a esta consulta. El resto de pruebas no se ve afectado.' }
            }
        } catch {
            $r = [pscustomobject]@{ Estado = 'Info'; Resumen = 'No se pudo completar la prueba'; Detalle = ($_ | Out-String).Trim() }
        }
        $sw.Stop()
        $Cola.Enqueue(@{ Tipo = 'Fin'; Id = $p.Id; Estado = $r.Estado; Resumen = $r.Resumen; Detalle = $r.Detalle; Metricas = $r.Metricas; Seg = [math]::Round($sw.Elapsed.TotalSeconds, 1) })
    }
    $Cola.Enqueue(@{ Tipo = 'Terminado' })
}
