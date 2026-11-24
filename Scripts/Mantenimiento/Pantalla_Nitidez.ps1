# =====================================================================
#  Pantalla_Nitidez.ps1
#  Diagnostica por qué una pantalla "se ve borrosa" y, si quieres, aplica lo recomendado:
#   - Resolución nativa del monitor (leída de su EDID) frente a la que está usando Windows.
#   - Frecuencia (Hz) actual frente a la máxima que admite a esa resolución.
#   - Escalado de Windows (DPI) y suavizado de fuentes (ClearType).
#   - Driver de vídeo (adaptador básico de Microsoft = sin driver propio).
#  Solo funciona en el equipo donde se ejecuta y con la sesión del usuario abierta.
# =====================================================================
[CmdletBinding()]
param([Alias('Simular')][switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }

if (-not $Global:E) {
    $Global:E = @{
        OK = [char]::ConvertFromUtf32(0x2705); Error = [char]::ConvertFromUtf32(0x274C); Aviso = [char]::ConvertFromUtf32(0x26A0)
        Info = [char]::ConvertFromUtf32(0x2139); Lupa = [char]::ConvertFromUtf32(0x1F50D); Cohete = [char]::ConvertFromUtf32(0x1F680)
        PC = [char]::ConvertFromUtf32(0x1F5A5)
    }
}

if (-not ('PantallaApi' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class PantallaApi
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DEVMODE
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public ushort dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
        public uint dmFields;
        public int dmPositionX, dmPositionY;
        public uint dmDisplayOrientation, dmDisplayFixedOutput;
        public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public ushort dmLogPixels;
        public uint dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
        public uint dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DISPLAY_DEVICE
    {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }

    [DllImport("user32.dll", CharSet = CharSet.Ansi)] static extern bool EnumDisplaySettings(string dev, int modo, ref DEVMODE dm);
    [DllImport("user32.dll", CharSet = CharSet.Ansi)] static extern int ChangeDisplaySettingsEx(string dev, ref DEVMODE dm, IntPtr hwnd, uint flags, IntPtr lp);
    [DllImport("user32.dll", CharSet = CharSet.Ansi)] static extern bool EnumDisplayDevices(string dev, uint i, ref DISPLAY_DEVICE dd, uint flags);
    [DllImport("user32.dll")] static extern bool SystemParametersInfo(uint accion, uint p1, ref uint p2, uint flags);
    [DllImport("user32.dll")] static extern bool SystemParametersInfo(uint accion, uint p1, IntPtr p2, uint flags);

    static DEVMODE Nuevo() { DEVMODE dm = new DEVMODE(); dm.dmSize = (ushort)Marshal.SizeOf(typeof(DEVMODE)); return dm; }

    // Pantallas activas: [0]=nombre (\\.\DISPLAY1), [1]=adaptador, [2]=id del monitor (MONITOR\DELA0F1\...)
    public static List<string[]> Pantallas()
    {
        var r = new List<string[]>();
        for (uint i = 0; ; i++)
        {
            var d = new DISPLAY_DEVICE(); d.cb = Marshal.SizeOf(d);
            if (!EnumDisplayDevices(null, i, ref d, 0)) break;
            if ((d.StateFlags & 1) == 0) continue;
            var m = new DISPLAY_DEVICE(); m.cb = Marshal.SizeOf(m);
            string idMon = EnumDisplayDevices(d.DeviceName, 0, ref m, 0) ? m.DeviceID : "";
            r.Add(new[] { d.DeviceName, d.DeviceString, idMon });
        }
        return r;
    }

    // [0]=ancho, [1]=alto, [2]=Hz, [3]=bits
    public static uint[] Actual(string dev)
    {
        var dm = Nuevo();
        if (!EnumDisplaySettings(dev, -1, ref dm)) return null;
        return new[] { dm.dmPelsWidth, dm.dmPelsHeight, dm.dmDisplayFrequency, dm.dmBitsPerPel };
    }

    public static List<uint[]> Modos(string dev)
    {
        var r = new List<uint[]>();
        var dm = Nuevo();
        for (int i = 0; EnumDisplaySettings(dev, i, ref dm); i++)
            if (dm.dmBitsPerPel >= 32) r.Add(new[] { dm.dmPelsWidth, dm.dmPelsHeight, dm.dmDisplayFrequency });
        return r;
    }

    // Devuelve 0 si se aplicó; otro valor = código DISP_CHANGE_*
    // guardar = false: cambio temporal (no toca el registro); si nadie lo confirma y el proceso muere, al reiniciar o cerrar sesión Windows vuelve a la resolución de antes
    public static int Aplicar(string dev, uint w, uint h, uint hz, bool guardar = true)
    {
        var dm = Nuevo();
        if (!EnumDisplaySettings(dev, -1, ref dm)) return -99;
        dm.dmPelsWidth = w; dm.dmPelsHeight = h; dm.dmDisplayFrequency = hz;
        dm.dmFields = 0x80000 | 0x100000 | 0x400000;   // ancho | alto | frecuencia
        int t = ChangeDisplaySettingsEx(dev, ref dm, IntPtr.Zero, 0x2, IntPtr.Zero);   // CDS_TEST
        if (t != 0) return t;
        return ChangeDisplaySettingsEx(dev, ref dm, IntPtr.Zero, guardar ? 0x1u : 0u, IntPtr.Zero);    // CDS_UPDATEREGISTRY o solo temporal
    }

    public static bool ClearTypeActivo()
    {
        uint suave = 0, tipo = 0;
        SystemParametersInfo(0x4A, 0, ref suave, 0);     // SPI_GETFONTSMOOTHING
        SystemParametersInfo(0x200A, 0, ref tipo, 0);    // SPI_GETFONTSMOOTHINGTYPE (2 = ClearType)
        return suave != 0 && tipo == 2;
    }

    public static void ActivarClearType()
    {
        SystemParametersInfo(0x4B, 1, IntPtr.Zero, 3);                    // SPI_SETFONTSMOOTHING
        SystemParametersInfo(0x200B, 0, (IntPtr)2, 3);                    // SPI_SETFONTSMOOTHINGTYPE = ClearType
    }
}
'@
}

function Get-ResolucionNativaEdid {
    <# Lee el EDID del monitor (clave de registro DISPLAY\<código>) y devuelve ancho x alto del primer modo detallado (el nativo). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CodigoMonitor)

    $base = 'HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY\' + $CodigoMonitor
    if (-not (Test-Path $base)) { return $null }
    foreach ($inst in Get-ChildItem $base -ErrorAction SilentlyContinue) {
        $edid = (Get-ItemProperty -Path (Join-Path $inst.PSPath 'Device Parameters') -Name EDID -ErrorAction SilentlyContinue).EDID
        if ($edid -and $edid.Length -ge 128 -and ($edid[54] -ne 0 -or $edid[55] -ne 0)) {
            $ancho = $edid[56] + (($edid[58] -band 0xF0) -shl 4)
            $alto  = $edid[59] + (($edid[61] -band 0xF0) -shl 4)
            if ($ancho -gt 0 -and $alto -gt 0) { return [pscustomobject]@{ Ancho = [uint32]$ancho; Alto = [uint32]$alto } }
        }
    }
    $null
}

function Confirm-Cambio {
    <# Ventana con cuenta atrás: si nadie pulsa "Mantener" en 15 s, devuelve $false (se revierte). #>
    [CmdletBinding()]
    param([string]$Texto)
    Add-Type -AssemblyName System.Windows.Forms
    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'Pantalla'; $f.Size = New-Object System.Drawing.Size(420, 170); $f.StartPosition = 'CenterScreen'
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false; $f.TopMost = $true
    $l = New-Object System.Windows.Forms.Label; $l.Location = New-Object System.Drawing.Point(15, 15); $l.Size = New-Object System.Drawing.Size(380, 60)
    $f.Controls.Add($l)
    $ok = New-Object System.Windows.Forms.Button; $ok.Text = 'Mantener'; $ok.Location = New-Object System.Drawing.Point(80, 90); $ok.DialogResult = 'Yes'
    $no = New-Object System.Windows.Forms.Button; $no.Text = 'Revertir'; $no.Location = New-Object System.Drawing.Point(230, 90); $no.DialogResult = 'No'
    $f.Controls.AddRange(@($ok, $no)); $f.AcceptButton = $ok
    $script:segundos = 15
    $t = New-Object System.Windows.Forms.Timer; $t.Interval = 1000
    $t.Add_Tick({ $script:segundos--; $l.Text = "$Texto`r`n`r`nSe revertirá solo en $script:segundos s si no confirmas."; if ($script:segundos -le 0) { $f.DialogResult = 'No' } })
    $l.Text = "$Texto`r`n`r`nSe revertirá solo en 15 s si no confirmas."
    $t.Start()
    $res = $f.ShowDialog(); $t.Stop(); $t.Dispose(); $f.Dispose()
    $res -eq 'Yes'
}

Write-Output ''
Write-Output '========================================================'
Write-Output "  $($Global:E.PC) DIAGNÓSTICO DE NITIDEZ DE PANTALLA"
Write-Output '========================================================'

$propuestas = @()
try {
    foreach ($p in [PantallaApi]::Pantallas()) {
        $dev = $p[0]; $act = [PantallaApi]::Actual($dev)
        if (-not $act) { continue }
        $modos = [PantallaApi]::Modos($dev)
        $maxPx = $modos | Sort-Object { [uint64]$_[0] * $_[1] }, { $_[2] } | Select-Object -Last 1
        $codigo = if ($p[2] -match '^MONITOR\\([^\\]+)\\') { $Matches[1] } else { $null }
        $nativa = if ($codigo) { Get-ResolucionNativaEdid -CodigoMonitor $codigo } else { $null }

        # Resolución objetivo: la nativa del EDID si Windows la ofrece; si no, la mayor disponible
        $objW = $maxPx[0]; $objH = $maxPx[1]
        if ($nativa -and ($modos | Where-Object { $_[0] -eq $nativa.Ancho -and $_[1] -eq $nativa.Alto })) { $objW = $nativa.Ancho; $objH = $nativa.Alto }
        $objHz = ($modos | Where-Object { $_[0] -eq $objW -and $_[1] -eq $objH } | ForEach-Object { $_[2] } | Measure-Object -Maximum).Maximum

        Write-Output ''
        Write-Output "$($Global:E.Lupa) $dev  -  $($p[1])"
        Write-Output "   Resolución actual : $($act[0]) x $($act[1]) a $($act[2]) Hz"
        if ($nativa) { Write-Output "   Resolución nativa : $($nativa.Ancho) x $($nativa.Alto) (según el EDID del monitor)" }
        else         { Write-Output "   Resolución nativa : no se pudo leer el EDID; se usa la mayor disponible" }
        Write-Output "   Recomendada       : $objW x $objH a $objHz Hz"

        $okRes = ($act[0] -eq $objW -and $act[1] -eq $objH)
        $okHz  = ($act[2] -ge $objHz)
        if ($okRes -and $okHz) { Write-Output "   $($Global:E.OK) Resolución y frecuencia correctas." }
        else {
            if (-not $okRes) { Write-Output "   $($Global:E.Aviso) NO usa la resolución nativa: es la causa más habitual de imagen borrosa." }
            if (-not $okHz)  { Write-Output "   $($Global:E.Aviso) Frecuencia por debajo de la máxima ($objHz Hz)." }
            $propuestas += [pscustomobject]@{ Dev = $dev; W = $objW; H = $objH; Hz = $objHz; Antes = $act }
        }
        if ($p[1] -match 'Basic Display|Básico|Basic Render') { Write-Output "   $($Global:E.Aviso) Usa el adaptador básico de Microsoft: falta el driver de la gráfica." }
    }

    # Escalado y suavizado de fuentes
    $dpi = (Get-ItemProperty 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name AppliedDPI -ErrorAction SilentlyContinue).AppliedDPI
    if (-not $dpi) { $dpi = 96 }
    Write-Output ''
    Write-Output "$($Global:E.Info) Escalado de Windows: $([math]::Round($dpi / 96 * 100)) %  (100/125/150 % son valores limpios; otros dan texto borroso en algunas apps)"
    $ct = [PantallaApi]::ClearTypeActivo()
    Write-Output "$($Global:E.Info) Suavizado de fuentes ClearType: $(if ($ct) { 'activado' } else { 'DESACTIVADO' })"
    $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -First 3
    foreach ($g in $gpu) { Write-Output "$($Global:E.Info) Driver: $($g.Name) v$($g.DriverVersion) ($(if ($g.DriverDate) { $g.DriverDate.ToString('dd/MM/yyyy') } else { 'sin fecha' }))" }

    if ($propuestas.Count -eq 0 -and $ct) { Write-Output "`n$($Global:E.OK) Nada que corregir. Si sigue borroso: revisar cable/adaptador (VGA, conversores) y el menú del monitor (Auto-ajuste)."; return }

    if ($SoloAnalizar) {
        $que = @($propuestas | ForEach-Object { "$($_.Dev): $($_.W)x$($_.H) a $($_.Hz) Hz" }); if (-not $ct) { $que += 'activar ClearType' }
        Exit-Kit 'Ok' "Modo análisis: se aplicaría $($que -join '; '). No se ha cambiado nada."
    }
    Add-Type -AssemblyName System.Windows.Forms
    $resumen = ($propuestas | ForEach-Object { "$($_.Dev): $($_.W)x$($_.H) $($_.Hz) Hz" }) -join "`n"
    if (-not $ct) { $resumen += "`nActivar ClearType" }
    $r = [System.Windows.Forms.MessageBox]::Show("¿Aplicar los ajustes recomendados?`n`n$resumen`n`nPodrás revertir.", 'Pantalla', 'YesNo', 'Question')
    if ($r -ne 'Yes') { Exit-Kit 'Cancelado' 'No se aplicó ningún cambio.' }

    if (-not $ct) { [PantallaApi]::ActivarClearType(); Write-Output "$($Global:E.OK) ClearType activado." }
    foreach ($c in $propuestas) {
        $cod = [PantallaApi]::Aplicar($c.Dev, $c.W, $c.H, $c.Hz, $false)   # primero temporal: solo se guarda si la persona confirma que se ve bien
        if ($cod -ne 0) { Write-Output "$($Global:E.Error) $($c.Dev): Windows rechazó el cambio (código $cod)."; continue }
        if (Confirm-Cambio -Texto "$($c.Dev) ahora en $($c.W)x$($c.H) a $($c.Hz) Hz. ¿Se ve bien?") {
            [void][PantallaApi]::Aplicar($c.Dev, $c.W, $c.H, $c.Hz, $true)
            Write-Output "$($Global:E.OK) $($c.Dev): $($c.W)x$($c.H) a $($c.Hz) Hz aplicado."
        } else {
            [void][PantallaApi]::Aplicar($c.Dev, $c.Antes[0], $c.Antes[1], $c.Antes[2])
            Write-Output "$($Global:E.Aviso) $($c.Dev): revertido a $($c.Antes[0])x$($c.Antes[1]) $($c.Antes[2]) Hz."
        }
    }
}
catch {
    Exit-Kit 'Error' "Error: $($_.Exception.Message)"
}
