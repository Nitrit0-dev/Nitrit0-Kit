# =====================================================================
#  Gestion_Memoria_RAM.ps1 (Edición Personal Nitrit0 - 100% Local)
#  Unifica:
#   1. Auditoría de módulos RAM instalados, velocidad MHz y ranuras libres.
#   2. Liberador instantáneo de RAM en uso (Working Set de procesos).
#   3. Ajuste de SysMain (en SSD/NVMe) y Compresión de Memoria (MMAgent).
# =====================================================================
[CmdletBinding()]
# -Accion salta el formulario (TODO por defecto si NIT_AUTO está activo)
param([ValidateSet('', 'TODO', 'LIBERAR', 'INFO', 'SYSMAIN')][string]$Accion = '', [Alias('Simular')][switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }

if (-not $Global:E) {
    $Global:E = @{
        OK = [char]::ConvertFromUtf32(0x2705); Error = [char]::ConvertFromUtf32(0x274C); Aviso = [char]::ConvertFromUtf32(0x26A0)
        Info = [char]::ConvertFromUtf32(0x2139); PC = [char]::ConvertFromUtf32(0x1F5A5); Cohete = [char]::ConvertFromUtf32(0x1F680)
        Fin = [char]::ConvertFromUtf32(0x1F3AF); Lupa = [char]::ConvertFromUtf32(0x1F50D); Disco = [char]::ConvertFromUtf32(0x1F4BE)
        Reloj = [char]::ConvertFromUtf32(0x23F3); Refresh = [char]::ConvertFromUtf32(0x1F504)
    }
}
$E = $Global:E

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if ($SoloAnalizar) { $Accion = 'INFO' }   # solo la auditoría de RAM: no libera memoria ni toca SysMain ni la compresión
if (-not $Accion -and $env:NIT_AUTO) { $Accion = 'TODO' }
if ($Accion -and $Accion -ne 'INFO') { Assert-Admin 'liberar memoria' }
$script:AccionRAM = 'CANCELAR'
if ($Accion) { $script:AccionRAM = $Accion }
else {
    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = "Memoria y Rendimiento RAM - Nitrit0"
    $Form.Size = New-Object System.Drawing.Size(450, 310)
    $Form.StartPosition = "CenterScreen"
    $Form.FormBorderStyle = "FixedDialog"
    $Form.MaximizeBox = $false
    $Form.TopMost = $true
    $Form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $Lbl = New-Object System.Windows.Forms.Label
    $Lbl.Text = "Selecciona qué operación de memoria deseas realizar:"
    $Lbl.Location = New-Object System.Drawing.Point(20, 14)
    $Lbl.AutoSize = $true
    $Lbl.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $Form.Controls.Add($Lbl)

    $script:AccionRAM = "CANCELAR"
    $Botones = @(
        @{ Txt = "⚡ 1. Hacer TODO (Ver RAM + Liberar RAM + Optimizar SysMain)"; Tag = "TODO";    Color = "PaleGreen" }
        @{ Txt = "2. Liberar Memoria RAM al instante (Vaciar Working Set)";     Tag = "LIBERAR"; Color = "LightCyan" }
        @{ Txt = "3. Ver módulos de RAM física, velocidad y ranuras libres";    Tag = "INFO";    Color = "Lavender" }
        @{ Txt = "4. Ajustar SysMain (según SSD/HDD) y Compresión de Memoria";  Tag = "SYSMAIN"; Color = "LightYellow" }
        @{ Txt = "Cancelar";                                                    Tag = "CANCELAR";Color = "LightCoral" }
    )
    $y = 42
    foreach ($b in $Botones) {
        $Btn = New-Object System.Windows.Forms.Button
        $Btn.Text = $b.Txt; $Btn.Tag = $b.Tag; $Btn.BackColor = $b.Color
        if ($b.Tag -eq "TODO") { $Btn.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold) }
        $Btn.Location = New-Object System.Drawing.Point(20, $y)
        $Btn.Size = New-Object System.Drawing.Size(395, 38)
        $Btn.Add_Click({ $script:AccionRAM = $this.Tag; $Form.Close() })
        $Form.Controls.Add($Btn)
        $y += 44
    }
    [void]$Form.ShowDialog()
}

if ($script:AccionRAM -eq "CANCELAR") { Exit-Kit 'Cancelado' 'Operación cancelada.' }

# --- 1. INFORMACIÓN DE RAM FÍSICA Y RANURAS LIBRES ---
if ($script:AccionRAM -in @("INFO", "TODO")) {
    Write-Output "`n========================================================"
    Write-Output "  $($E.Lupa) AUDITORÍA DE MEMORIA RAM FÍSICA E INSTALACIÓN"
    Write-Output "========================================================"
    $ArrayRAM   = Get-CimInstance Win32_PhysicalMemoryArray -ErrorAction SilentlyContinue | Select-Object -First 1
    $TotalSlots = if ($ArrayRAM) { [int]$ArrayRAM.MemoryDevices } else { 0 }
    $Modulos    = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
    $SumaTotal  = 0

    $Tabla = foreach ($m in $Modulos) {
        $cap = [math]::Round($m.Capacity / 1GB, 2)
        $SumaTotal += $cap
        [PSCustomObject]@{
            Ranura          = $m.DeviceLocator
            Fabricante      = $m.Manufacturer
            "Capacidad(GB)" = $cap
            "Velocidad(MHz)"= $m.ConfiguredClockSpeed
            PartNumber      = ($m.PartNumber).Trim()
        }
    }
    $Tabla | Format-Table -AutoSize | Out-String | ForEach-Object { $_.TrimEnd() } | Write-Output
    $Libres = if ($TotalSlots -ge $Modulos.Count) { $TotalSlots - $Modulos.Count } else { 0 }
    Write-Output "--------------------------------------------------------"
    Write-Output "  $($E.OK) TOTAL INSTALADA : $SumaTotal GB"
    Write-Output "  $($E.Info) RANURAS EN PLACA: $($Modulos.Count) ocupadas de $TotalSlots ($Libres ranura/s libre/s para ampliar)"
    Write-Output "--------------------------------------------------------"
}

# --- 2. LIBERAR MEMORIA RAM (WORKING SET) ---
if ($script:AccionRAM -in @("LIBERAR", "TODO")) {
    Write-Output "`n========================================================"
    Write-Output "  $($E.Cohete) LIBERADOR DE MEMORIA RAM EN VIVO"
    Write-Output "========================================================"
    if (-not ('RamCleaner' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RamCleaner {
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetProcessWorkingSetSize(IntPtr hProcess, IntPtr dwMinimumWorkingSetSize, IntPtr dwMaximumWorkingSetSize);
}
'@
    }
    $osAntes    = Get-CimInstance Win32_OperatingSystem
    $libreAntes = [math]::Round($osAntes.FreePhysicalMemory / 1MB, 2)
    $totalGB    = [math]::Round($osAntes.TotalVisibleMemorySize / 1MB, 2)
    Write-Output "  $($E.Lupa) RAM libre antes : $libreAntes GB de $totalGB GB"

    $Protegidos = @('System','Idle','Registry','Memory Compression','smss','csrss','wininit','winlogon','services','lsass','fontdrvhost','svchost','dwm','MsMpEng','SecurityHealthService')
    $Optimizados = 0
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
        try {
            if ($p.Id -ne $PID -and $p.SessionId -ne 0 -and $Protegidos -notcontains $p.ProcessName -and $p.Handle -ne [IntPtr]::Zero) {
                if ([RamCleaner]::SetProcessWorkingSetSize($p.Handle, [IntPtr](-1), [IntPtr](-1))) { $Optimizados++ }
            }
        } catch {}
        finally { if ($p) { $p.Dispose() } }
    }
    [System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers()
    Start-Sleep -Milliseconds 700
    $osDespues    = Get-CimInstance Win32_OperatingSystem
    $libreDespues = [math]::Round($osDespues.FreePhysicalMemory / 1MB, 2)
    $recuperado   = [math]::Max(0, [math]::Round($libreDespues - $libreAntes, 2))
    Write-Output "  $($E.OK) Procesos optimizados: $Optimizados"
    Write-Output "  $($E.Refresh) RAM libre ahora : $libreDespues GB  (Recuperados: +$recuperado GB)"
}

# --- 3. AJUSTE DE SYSMAIN Y COMPRESIÓN DE MEMORIA ---
if ($script:AccionRAM -in @("SYSMAIN", "TODO")) {
    Write-Output "`n========================================================"
    Write-Output "  $($E.Disco) AJUSTE DE SYSMAIN Y COMPRESIÓN DE MEMORIA"
    Write-Output "========================================================"
    [void](Start-OperacionSegura 'Ajuste de memoria (SysMain)' -SinPuntoRestauracion)
    $letra = $env:SystemDrive.TrimEnd(':', '\')
    $esSSD = $false; $tipoDisco = "Desconocido"; $detectado = $false
    try {
        $num = (Get-Partition -DriveLetter $letra -ErrorAction Stop | Select-Object -First 1).DiskNumber
        $d   = Get-PhysicalDisk -DeviceNumber $num -ErrorAction Stop
        $tipoDisco = "$($d.FriendlyName) ($($d.MediaType) - $($d.BusType))"
        $esSSD = ($d.MediaType -in @('SSD', 'SCM')) -or ($d.BusType -eq 'NVMe')
        $detectado = ($d.MediaType -in @('SSD', 'SCM', 'HDD')) -or ($d.BusType -eq 'NVMe')   # «Unspecified» no es un HDD
    } catch {}
    Write-Output "  $($E.Info) Disco del sistema: $tipoDisco"

    $svc = Get-Service -Name 'SysMain' -ErrorAction SilentlyContinue
    if ($svc) {
        if (-not $detectado) {
            Write-Output "  $($E.Aviso) No se pudo saber si el disco es SSD o HDD: no se cambia SysMain."
        } elseif ($esSSD) {
            [void](Set-ServicioSeguro 'SysMain' 'Disabled' -Detener)
            Write-Output "  $($E.OK) Disco SSD/NVMe detectado -> Servicio SysMain desactivado para evitar escrituras y consumo en segundo plano."
        } else {
            Write-Output "  $($E.Info) Disco HDD detectado -> Se conserva SysMain activo porque acelera la carga en discos mecánicos."
        }
    }
    try {
        $mm = Get-MMAgent -ErrorAction Stop
        if (-not $mm.MemoryCompression) {
            Save-Informativo 'Compresión de memoria activada (antes estaba desactivada)' 'Para desactivarla: Disable-MMAgent -MemoryCompression'
            Enable-MMAgent -MemoryCompression -ErrorAction Stop
            Write-Output "  $($E.OK) Compresión de memoria RAM activada."
        } else {
            Write-Output "  $($E.OK) La compresión de memoria RAM ya estaba activa."
        }
    } catch { Write-Output "  $($E.Aviso) No se pudo ajustar la compresión de memoria: $($_.Exception.Message)" }
}