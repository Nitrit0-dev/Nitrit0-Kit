# =====================================================================
#  Lanzador Nitrit0 v5.2 Fluent UI - Suite Senior de Diagnóstico y Taller
#  Desarrollado por: Nitrit0
#  Diseño Visual Senior: Barra DWM nativa oscura, controles GDI+ redondeados,
#  buscador cápsula moderno, chips tipo píldora y tarjetas con relieve suave.
# =====================================================================

param([switch]$Auto, [string]$Captura, [string]$Tema)
$VersionKit = '5.2'

# --- 1. Auto-Elevación UAC inmediata (antes de cargar módulos pesados o temas para no abrir doble proceso) ---
$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $esAdmin -and -not $Captura) {
    $extraArgs = @()
    if ($Auto) { $extraArgs += '-Auto' }
    if ($Tema) { $extraArgs += "-Tema `"$Tema`"" }
    $argStr = "-NoProfile -ExecutionPolicy Bypass -STA -File `"$($MyInvocation.MyCommand.Path)`" " + ($extraArgs -join ' ')
    $psAbs = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    try { Start-Process $psAbs -Verb RunAs -WindowStyle Hidden -ArgumentList $argStr -ErrorAction Stop }
    catch {
        # Cancelar el aviso de Windows (UAC) ya no cierra el lanzador en silencio con «correcto»
        try { Add-Type -AssemblyName System.Windows.Forms; [void][Windows.Forms.MessageBox]::Show('El lanzador necesita administrador y no se ha abierto (¿se canceló el aviso de Windows?).', 'Nitrit0', 0, 48) } catch { }
        exit 2
    }
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction SilentlyContinue

# Instancia única: dos lanzadores a la vez podrían pisarse $Global:NitOp y los registros de Deshacer_Cambios
if (-not $Captura) {
    $nuevoMutex = $false
    try { $Global:MutexLanzador = New-Object Threading.Mutex($true, 'Global\Nitrit0_Lanzador_Mutex', [ref]$nuevoMutex) } catch { $nuevoMutex = $true }
    if (-not $nuevoMutex) { [void][Windows.Forms.MessageBox]::Show('El lanzador de Nitrit0 ya está abierto en este equipo.', 'Nitrit0', 0, 64); exit 0 }
}

$dirScripts = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($dirScripts)) { $dirScripts = Split-Path -Parent $MyInvocation.MyCommand.Path }
$raiz = Split-Path -Parent $dirScripts
$dirApps = Join-Path $raiz 'Apps'; $dirDatos = Join-Path $raiz 'Datos'
New-Item -ItemType Directory -Force $dirDatos | Out-Null

. (Join-Path $dirScripts 'Comun.ps1'); Initialize-Kit $raiz
Write-Log "Lanzador v$VersionKit iniciado en $raiz (equipo $env:COMPUTERNAME, usuario $env:USERNAME, administrador: $esAdmin)"
# El escalado de pantalla (DPI) hay que activarlo ANTES de cargar el tema: Tema.ps1 consulta las fuentes instaladas y,
# si Windows crea antes cualquier recurso gráfico, deja el proceso sin escalado y la ventana sale diminuta.
Add-Type -Name Dpi -Namespace Nit -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
[void][Nit.Dpi]::SetProcessDPIAware()
. (Join-Path $dirScripts 'Tema.ps1')
if ($Tema -in 'claro', 'oscuro') { Set-Tema $Tema }

trap {
    try { [IO.File]::AppendAllText((Join-Path $dirDatos 'Error_Lanzador.log'), "[$(Get-Date)] $($_ | Out-String)`r`n") } catch { }
    try { Add-Type -AssemblyName System.Windows.Forms; [void][Windows.Forms.MessageBox]::Show("No se pudo abrir el lanzador:`n$($_.Exception.Message)`n`nDetalle en Error_Lanzador.log", 'Lanzador', 0, 16) } catch { }
    exit 1
}

Add-Type -Name Win -Namespace Con -MemberDefinition '[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow(); [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);'
$hc = [Con.Win]::GetConsoleWindow(); if ($hc -ne [IntPtr]::Zero) { [void][Con.Win]::ShowWindow($hc, 0) }
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
# Carpeta de trabajo que solo escribe un administrador: con %TEMP% un cmd.exe/explorer.exe plantado allí se ejecutaría elevado al lanzar herramientas por nombre
Set-Location -LiteralPath $env:SystemRoot

$a = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
$arq = switch ($a) { 'AMD64' { 'x64' } 'ARM64' { 'arm64' } default { 'x86' } }

$dirInformes = Get-CarpetaSalida 'Informes'   # pack público: %TEMP%\Nitrit0_Cache\Informes; personal: Datos\Informes
$rutaLog = Join-Path (Get-BaseTrabajo) 'Historial_Diagnosticos.log'

# --- Catálogo de Herramientas: vive en Catalogo_Kit.ps1 (lo comparten este lanzador, Exportar_Catalogo.ps1 y Validar_Kit.ps1) ---
. (Join-Path $dirScripts 'Catalogo_Kit.ps1')
# Datos\Ajustes.json con "OcultarPeligro": true (pack público): las herramientas marcadas como peligrosas no se muestran
function Get-Visibles {
    if ($null -eq $script:OcultarPeligro) { $script:OcultarPeligro = $false; try { $script:OcultarPeligro = [bool](Get-Content -LiteralPath (Join-Path (Get-KitDatos) 'Ajustes.json') -Raw -Encoding UTF8 | ConvertFrom-Json).OcultarPeligro } catch { } }
    @($Herramientas | Where-Object { -not $_.Oculta -and -not ($script:OcultarPeligro -and $_.Peligro -and -not $_.PublicoOk) })
}

function Get-Exe($h) {
    if (-not $h.Exe) { return $null }
    foreach ($k in @($arq, 'x64', 'x86')) {
        if ($h.Exe[$k]) { $p = Resolve-ExeKit $h.Exe[$k]; if ($p -and (Test-Path -LiteralPath $p)) { return $p } }
    }
    $null
}

function Write-Historial([string]$txt) {
    try { [IO.File]::AppendAllText($rutaLog, "[$(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')] $env:USERNAME - $txt`r`n", [Text.Encoding]::UTF8) } catch { }
}

. (Join-Path $dirScripts 'Informe_Rapido.ps1')   # New-Informe (compartido con la app)

function Update-RutasKit {
    $r = $Global:NitKit.Raiz
    if ($script:raiz -ne $r) {
        $script:raiz = $r; $script:dirApps = Join-Path $r 'Apps'; $script:dirDatos = Join-Path $r 'Datos'; $script:dirScripts = Join-Path $r 'Scripts'
        $script:dirInformes = Get-CarpetaSalida 'Informes'; $script:rutaLog = Join-Path (Get-BaseTrabajo) 'Historial_Diagnosticos.log'
        Write-Log "Rutas del kit actualizadas a $r" 'AVISO'
    }
}

function Start-Herramienta($h, $btn) {
    if ($h.Peligro) {
        $r = [Windows.Forms.MessageBox]::Show("$($h.N)`n`n$($h.D)$(if ($h.Ayuda) { "`n`n" + $h.Ayuda.Trim() })`n`n¿Continuar?", 'Confirmación de seguridad', 'YesNo', 'Warning', 'Button2')
        if ($r -ne 'Yes') { return }
    }
    if (-not (Test-KitDisponible)) {
        $lbl.Text = 'La unidad del kit no está accesible: esperando reconexión…'
        if (-not (Show-EsperaUnidad 120)) { $lbl.Text = 'Cancelado: la unidad del kit no volvió.'; return }
        Update-RutasKit
    }
    try {
        $form.Cursor = 'WaitCursor'
        if ($h.Script) { $form.Cursor = 'Default'; Show-Ejecucion $h; $lbl.Text = "Terminado: $($h.N)" }
        elseif ($h.Informe) { $f = New-Informe; Start-Process notepad.exe $f; $lbl.Text = "Informe guardado en $f"; Write-Historial "Informe rápido: $f" }
        elseif ($h.Accion -eq 'Taller') { if (Get-Command Show-Diagnostico -ErrorAction SilentlyContinue) { Show-Diagnostico 'Rapido' $true $true } }
        elseif ($h.Accion -eq 'Actualizador') { if (Get-Command Show-Actualizador -ErrorAction SilentlyContinue) { Show-Actualizador } }
        elseif ($h.Accion -eq 'Componentes') { if (Get-Command Show-Componentes -ErrorAction SilentlyContinue) { Show-Componentes } }
        elseif ($h.Accion -eq 'Equilibrio') { if (Get-Command Show-Equilibrio -ErrorAction SilentlyContinue) { Show-Equilibrio 'Config'; Write-Historial 'Abrió Equilibrio' } }
        elseif ($h.Accion -eq 'SmartDetalle') { Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$(Join-Path $dirScripts 'SMART_Detalle.ps1')`""; $lbl.Text = "Abierto: $($h.N)"; Write-Historial "Abrió SMART detallado" }
        elseif ($h.Accion -eq 'AbrirHistorial') { $pHist = Join-Path $dirDatos 'Historial'; New-Item -ItemType Directory -Path $pHist -Force | Out-Null; Start-Process explorer.exe -ArgumentList "`"$pHist`""; $lbl.Text = "Abierto: Historial" }
        elseif ($h.Accion -eq 'AbrirInformes') { New-Item -ItemType Directory -Path $dirInformes -Force | Out-Null; Start-Process explorer.exe -ArgumentList "`"$dirInformes`""; $lbl.Text = "Abierto: Informes" }
        elseif ($h.Accion -eq 'CmdBateria') { New-Item -ItemType Directory -Path $dirInformes -Force | Out-Null; $outB = Join-Path $dirInformes "Bateria_$env:COMPUTERNAME.html"; Start-Process cmd.exe -ArgumentList '/k', "powercfg /batteryreport /output `"$outB`" && explorer.exe `"$outB`""; $lbl.Text = "Ejecutando: Batería"; Write-Historial "Ejecutó informe de Batería" }
        elseif ($h.Accion -eq 'CmdEnergia') { New-Item -ItemType Directory -Path $dirInformes -Force | Out-Null; $outE = Join-Path $dirInformes "Energia_$env:COMPUTERNAME.html"; Start-Process cmd.exe -ArgumentList '/k', "powercfg /energy /output `"$outE`" && explorer.exe `"$outE`""; $lbl.Text = "Ejecutando: Energía (60 s)"; Write-Historial "Ejecutó informe de Energía" }
        elseif ($h.Run) { if ($h.RunArgs) { Start-Process $h.Run -ArgumentList $h.RunArgs } else { Start-Process $h.Run }; $lbl.Text = "Abierto: $($h.N)"; Write-Historial "Abrió $($h.N)" }
        elseif ($h.Uri) { if ($h.Uri -match '^https?://') { Start-Process $h.Uri; Write-Historial "Abrió $($h.N)" } else { $lbl.Text = "Dirección no permitida: $($h.N)"; Write-Historial "Bloqueada dirección no http(s): $($h.N)" } }
        elseif ($h.Html) { Start-Process explorer.exe -ArgumentList "`"$(Join-Path $dirScripts $h.Html)`""; $lbl.Text = "Abierto: $($h.N)"; Write-Historial "Abrió $($h.N)" }
        elseif ($h.Cmd) { New-Item -ItemType Directory -Path $dirInformes -Force | Out-Null; Start-Process cmd.exe -ArgumentList '/k', $h.Cmd; $lbl.Text = "Ejecutando: $($h.N)"; Write-Historial "Ejecutó $($h.N)" }
        else { $e = Get-Exe $h; $va = @{}; if (-not $esAdmin) { $va.Verb = 'RunAs' }; Start-Process -FilePath $e -WorkingDirectory (Split-Path $e) @va; $lbl.Text = "Abierto: $($h.N)"; Write-Historial "Abrió $($h.N) ($e)" }
    } catch {
        [Windows.Forms.MessageBox]::Show("No se pudo abrir $($h.N):`n$($_.Exception.Message)", 'Error', 0, 16) | Out-Null
    } finally { $form.Cursor = 'Default' }
}

# --- API Nativa DWM (Barra de título oscura en Windows 10/11) + High DPI ---
Add-Type -Name NativeUx -Namespace Nit -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, int m, int w, string l);
[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
public static void SetDarkTitleBar(IntPtr handle, bool dark) {
    int val = dark ? 1 : 0;
    DwmSetWindowAttribute(handle, 20, ref val, 4);
    DwmSetWindowAttribute(handle, 19, ref val, 4);
}
'@
[void][Nit.NativeUx]::SetProcessDPIAware()

# --- Componentes Visuales Fluent UI en C# (TarjetaPro, ChipPro, BotonPro) ---
if (-not ('TarjetaPro' -as [type])) {
    Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Windows.Forms;

public static class UiHelper
{
    public static Color T(int i) { Color[] a = AppDomain.CurrentDomain.GetData("NitTema") as Color[]; return (a != null && i < a.Length) ? a[i] : Color.Gray; }
    public static float Z() { object o = AppDomain.CurrentDomain.GetData("NitZoom"); return o is float ? (float)o : 1f; }
    public static string F(int i) { string[] a = AppDomain.CurrentDomain.GetData("NitFuentes") as string[]; return (a != null && i < a.Length) ? a[i] : "Segoe UI"; }
    public static GraphicsPath RoundRect(Rectangle r, int d)
    {
        GraphicsPath p = new GraphicsPath();
        if (d <= 0) { p.AddRectangle(r); return p; }
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }
}

public class BotonPro : Control
{
    public Color ColorFondo = Color.FromArgb(43, 196, 216);
    public Color ColorTexto = Color.White;
    public Color ColorBorde = Color.Transparent;
    public bool EsPrimario = false;
    public int Radio = 14;
    private bool hover, pulsado;

    public BotonPro()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true);
        BackColor = Color.Transparent;
        Cursor = Cursors.Hand;
    }
    protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hover = false; pulsado = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseDown(MouseEventArgs e) { pulsado = true; Invalidate(); base.OnMouseDown(e); }
    protected override void OnMouseUp(MouseEventArgs e) { pulsado = false; Invalidate(); base.OnMouseUp(e); }

    protected override void OnPaint(PaintEventArgs pe)
    {
        Graphics g = pe.Graphics;
        float k = g.DpiX / 96f * UiHelper.Z();
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

        Rectangle r = new Rectangle(1, 1, Width - 3, Height - 3);
        if (pulsado) r.Offset(0, 1);

        Color cf = ColorFondo;
        if (hover)
        {
            cf = Color.FromArgb(cf.A, Math.Min(255, cf.R + 18), Math.Min(255, cf.G + 18), Math.Min(255, cf.B + 18));
        }

        using (GraphicsPath p = UiHelper.RoundRect(r, (int)(Radio * k)))
        {
            using (SolidBrush b = new SolidBrush(cf)) { g.FillPath(b, p); }
            if (ColorBorde != Color.Transparent)
            {
                using (Pen pen = new Pen(hover ? Color.FromArgb(200, ColorTexto) : ColorBorde, hover ? 1.5f : 1f))
                { g.DrawPath(pen, p); }
            }
        }

        using (Font f = new Font(UiHelper.F(1), 9.5f * UiHelper.Z()))
        using (SolidBrush bt = new SolidBrush(ColorTexto))
        using (StringFormat sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
        {
            g.DrawString(Text, f, bt, new RectangleF(0, 0, Width, Height), sf);
        }
    }
}

public class ChipPro : Control
{
    public string Categoria = "";
    public int Cantidad = 0;
    public bool Seleccionado = false;
    public Color Acento = Color.DeepSkyBlue;
    private bool hover;

    public ChipPro()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        Cursor = Cursors.Hand;
    }
    protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }

    protected override void OnPaint(PaintEventArgs pe)
    {
        Graphics g = pe.Graphics;
        float k = g.DpiX / 96f * UiHelper.Z();
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
        g.Clear(Parent != null ? Parent.BackColor : BackColor);

        Rectangle r = new Rectangle(1, 1, Width - 3, Height - 3);
        // Selección = un paso de superficie con el borde en el acento; nada más lleva color
        Color fondo = (Seleccionado || hover) ? UiHelper.T(2) : UiHelper.T(1);
        Color borde = Seleccionado ? Acento : UiHelper.T(3);
        Color texto = (Seleccionado || hover) ? UiHelper.T(4) : UiHelper.T(5);

        using (GraphicsPath p = UiHelper.RoundRect(r, (int)(16 * k)))
        using (SolidBrush b = new SolidBrush(fondo))
        using (Pen pen = new Pen(borde, 1f))
        {
            g.FillPath(b, p);
            g.DrawPath(pen, p);
        }

        using (Font f = new Font(UiHelper.F(0), 9f * UiHelper.Z()))
        using (SolidBrush bt = new SolidBrush(texto))
        using (StringFormat sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
        {
            string label = Cantidad > 0 ? string.Format("{0}  {1}", Text, Cantidad) : Text;
            g.DrawString(label, f, bt, new RectangleF(0, 0, Width, Height), sf);
        }
    }
}

public class TarjetaPro : Control
{
    public string Titulo = "", Desc = "", Glifo = "", EtiquetaCat = "";
    public Image Icono;
    public Color Acento = Color.SteelBlue;
    public bool Activa = true, Peligro, Favorito = false;
    public bool ClickEnEstrella = false;
    private bool hover, hoverStar, pulsada;

    public TarjetaPro()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        float k0; using (Graphics gg = Graphics.FromHwnd(IntPtr.Zero)) k0 = gg.DpiX / 96f * UiHelper.Z();
        Size = new Size((int)(292 * k0), (int)(104 * k0));
        Cursor = Cursors.Hand;
    }
    private Rectangle StarRect() {
        float k = 1f; using (Graphics g = CreateGraphics()) k = g.DpiX / 96f * UiHelper.Z();
        return new Rectangle(Width - (int)(36 * k), (int)(8 * k), (int)(28 * k), (int)(28 * k));
    }
    protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hover = false; hoverStar = false; pulsada = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseMove(MouseEventArgs e) {
        bool hs = StarRect().Contains(e.Location);
        if (hs != hoverStar) { hoverStar = hs; Invalidate(); }
        base.OnMouseMove(e);
    }
    protected override void OnMouseDown(MouseEventArgs e) {
        ClickEnEstrella = (e.Button == MouseButtons.Right) || StarRect().Contains(e.Location);
        pulsada = true; Invalidate(); base.OnMouseDown(e);
    }
    protected override void OnMouseUp(MouseEventArgs e) { pulsada = false; Invalidate(); base.OnMouseUp(e); }

    protected override void OnPaint(PaintEventArgs pe)
    {
        Graphics g = pe.Graphics;
        float k = g.DpiX / 96f * UiHelper.Z();
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
        g.Clear(Parent != null ? Parent.BackColor : BackColor);

        // Superficie: al pasar el ratón sube un paso de gris; al pulsar baja 1 px. Sin degradados ni bordes de color.
        Rectangle r = new Rectangle(1, 1, Width - 3, Height - 3);
        if (pulsada && Activa) r.Offset(0, 1);
        using (GraphicsPath p = UiHelper.RoundRect(r, (int)(24 * k)))
        using (SolidBrush b = new SolidBrush(hover && Activa ? UiHelper.T(2) : UiHelper.T(1)))
        using (Pen pen = new Pen(UiHelper.T(3), 1f))
        {
            g.FillPath(b, p);
            g.DrawPath(pen, p);
        }

        int alfa = Activa ? 255 : 110;
        int s40 = (int)(40 * k);
        Rectangle ib = new Rectangle(r.X + (int)(16 * k), r.Y + (int)(16 * k), s40, s40);

        if (Icono != null)
        {
            // Icono real del programa: es su marca, se respeta tal cual
            ColorMatrix cm = new ColorMatrix(); cm.Matrix33 = alfa / 255f;
            using (ImageAttributes ia = new ImageAttributes())
            {
                ia.SetColorMatrix(cm);
                int m4 = (int)(4 * k), s32 = (int)(32 * k);
                Rectangle dst = new Rectangle(ib.X + m4, ib.Y + m4, s32, s32);
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.DrawImage(Icono, dst, 0, 0, Icono.Width, Icono.Height, GraphicsUnit.Pixel, ia);
            }
        }
        else
        {
            // Icono de línea (fuente de iconos de Windows) en el gris del texto secundario
            using (GraphicsPath p = UiHelper.RoundRect(ib, (int)(16 * k)))
            using (SolidBrush b = new SolidBrush(UiHelper.T(0)))
            using (Pen penIco = new Pen(UiHelper.T(3), 1f))
            {
                g.FillPath(b, p);
                g.DrawPath(penIco, p);
            }
            if (Glifo.Length > 0)
            {
                using (Font f = new Font("Segoe MDL2 Assets", 13f * UiHelper.Z()))
                using (SolidBrush b = new SolidBrush(Color.FromArgb(alfa, UiHelper.T(5))))
                using (StringFormat sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
                { g.DrawString(Glifo, f, b, new RectangleF(ib.X, ib.Y + 1, ib.Width, ib.Height), sf); }
            }
        }

        int x = ib.Right + (int)(12 * k);
        int w = r.Right - x - (int)(16 * k);

        using (Font f = new Font(UiHelper.F(1), 10f * UiHelper.Z()))
        using (SolidBrush b = new SolidBrush(Color.FromArgb(alfa, UiHelper.T(4))))
        using (StringFormat sf = new StringFormat { FormatFlags = StringFormatFlags.NoWrap, Trimming = StringTrimming.EllipsisCharacter })
        {
            g.DrawString(Titulo, f, b, new RectangleF(x, r.Y + 14 * k, w - (Peligro ? 64 * k : 20 * k), 22 * k), sf);
        }

        using (Font f = new Font(UiHelper.F(0), 8.6f * UiHelper.Z()))
        using (SolidBrush b = new SolidBrush(Color.FromArgb(alfa, UiHelper.T(5))))
        using (StringFormat sf = new StringFormat { Trimming = StringTrimming.EllipsisWord, FormatFlags = StringFormatFlags.LineLimit })   // solo líneas enteras: nunca una línea cortada por la mitad
        {
            g.DrawString(Activa ? Desc : "No está en la carpeta Apps", f, b, new RectangleF(x, r.Y + 38 * k, w, r.Height - 46 * k), sf);
        }

        // Pide confirmación antes de ejecutarse: texto discreto en el color de aviso
        if (Peligro)
        {
            using (Font fb = new Font(UiHelper.F(0), 8f * UiHelper.Z()))
            using (SolidBrush tb = new SolidBrush(Color.FromArgb(alfa, UiHelper.T(7))))
            using (StringFormat sfb = new StringFormat { Alignment = StringAlignment.Far, LineAlignment = StringAlignment.Center })
            {
                g.DrawString("Aviso", fb, tb, new RectangleF(r.Right - 80 * k, r.Y + 14 * k, 44 * k, 20 * k), sfb);
            }
        }

        // Estrella de favoritos: rellena y en el acento si lo es; hueca al pasar el ratón
        if (Favorito || hover || hoverStar)
        {
            Color colStar = Favorito ? UiHelper.T(6) : (hoverStar ? UiHelper.T(4) : UiHelper.T(5));
            using (Font fs = new Font("Segoe MDL2 Assets", 9.5f * UiHelper.Z()))
            using (SolidBrush bs = new SolidBrush(colStar))
            using (StringFormat sfs = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
            {
                g.DrawString(Favorito ? "" : "", fs, bs, new RectangleF(r.Right - 32 * k, r.Y + 12 * k, 24 * k, 24 * k), sfs);
            }
        }
    }
}
'@
}

function Get-Color([string]$hex) { ConvertFrom-HexColor $hex }
$cFondo = Get-Tc 'Fondo'; $cCab = Get-Tc 'Cab'; $cTexto = Get-Tc 'TextoSuave'

$script:K = 1.0
try { $gk = [Drawing.Graphics]::FromHwnd([IntPtr]::Zero); $script:K = $gk.DpiX / 96; $gk.Dispose() } catch { }
# Zoom de la vista (0.7 a 1.3), guardado en Ajustes.json. $script:K es el escalado de pantalla; $script:KZ lo multiplica por el zoom
# y solo lo usa esta ventana: las demás (diagnóstico, ejecución…) siguen con $script:K.
$script:Z = 1.0
try { $pz = Join-Path $dirDatos 'Ajustes.json'; if (Test-Path -LiteralPath $pz) { $zz = (Get-Content -LiteralPath $pz -Raw -Encoding UTF8 | ConvertFrom-Json).Zoom; if ($zz) { $script:Z = [math]::Max(0.7, [math]::Min(1.3, [double]$zz)) } } } catch { }
$script:KZ = $script:K * $script:Z
[AppDomain]::CurrentDomain.SetData('NitZoom', [single]$script:Z)
$script:CatFiltro = ''; $script:Pagina = 'Comprobar'
if ($Captura -and $env:NIT_PAGINA) { $script:Pagina = $env:NIT_PAGINA }   # solo para capturas de prueba
if ($env:NIT_RETOMAR) {   # reinicio por el zoom: vuelve a la misma página y filtro (Build-Chips descarta el filtro si ya no existe)
    $rp, $rf = $env:NIT_RETOMAR -split '\|', 2; $env:NIT_RETOMAR = $null
    if ($Paginas.Contains($rp)) { $script:Pagina = $rp; if (-not $rf -or $rf -eq '★ Favoritos' -or $Paginas[$rp] -contains $rf) { $script:CatFiltro = [string]$rf } }
}
$script:IconCache = @{}
$script:RutaFavs  = Join-Path $dirDatos 'Favoritos.json'
$script:Favoritos = @('Diagnóstico completo', 'Pantallazos y eventos', 'Licencias y BitLocker', 'Instalar apps básicas', 'Reparar Windows y Tienda')
if (Test-Path -LiteralPath $script:RutaFavs) {
    try { $loadedFavs = Get-Content -LiteralPath $script:RutaFavs -Raw -Encoding UTF8 | ConvertFrom-Json; if ($null -ne $loadedFavs) { $script:Favoritos = @($loadedFavs) } } catch { }
}
function Save-Favoritos {
    try { [IO.File]::WriteAllText($script:RutaFavs, ($script:Favoritos | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($true))) } catch { }
}
function Toggle-Favorito([string]$nombre) {
    if ($script:Favoritos -contains $nombre) {
        $script:Favoritos = @($script:Favoritos | Where-Object { $_ -ne $nombre })
        $lbl.Text = "Quitado de favoritos: $nombre"
    } else {
        $script:Favoritos = @($script:Favoritos) + @($nombre)
        $lbl.Text = "Añadido a favoritos: $nombre"
    }
    Save-Favoritos
    Update-ChipsCount
    Show-Tarjetas
}

$rutaVentanaDx = Join-Path $dirScripts 'Ventana_Diagnostico.ps1'
if (Test-Path -LiteralPath $rutaVentanaDx) { . $rutaVentanaDx }
$rutaVentanaCb = Join-Path $dirScripts 'Ventana_Equilibrio.ps1'
if (Test-Path -LiteralPath $rutaVentanaCb) { . $rutaVentanaCb }
foreach ($mod in 'Historial.ps1', 'Componentes.ps1', 'Actualizador.ps1', 'Ejecutor.ps1') { $pm = Join-Path $dirScripts $mod; if (Test-Path -LiteralPath $pm) { . $pm } }

# Lectura del equipo que se muestra en el panel superior
$script:EqModelo = $env:COMPUTERNAME; $script:EqDetalle = $arq
try {
    $csx = Get-CimInstance Win32_ComputerSystem; $cpx = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name; $osx = Get-CimInstance Win32_OperatingSystem
    $modelo = if ($csx.Model -like "$($csx.Manufacturer)*") { $csx.Model } else { "$($csx.Manufacturer) $($csx.Model)" }
    $script:EqModelo = ($modelo -replace '^(\S+) \1\b', '$1')
    $script:EqDetalle = "{0}  ·  {1:N0} GB RAM  ·  {2}  ·  {3}" -f (($cpx -replace '\(R\)|\(TM\)|CPU|@.*|Intel|Processor', '' -replace '\s+', ' ').Trim()), ($csx.TotalPhysicalMemory / 1GB), ($osx.Caption -replace '^Microsoft\s+', ''), $env:COMPUTERNAME
} catch { }

# Iconos de línea de la fuente «Segoe MDL2 Assets», incluida en Windows 10 y 11 (un solo juego, un solo tamaño)
$Glifos = @{
    'Asistente guiado'=0xEA80; 'Modo taller'=0xEC7A; 'Actualizar herramientas'=0xE895; 'Componentes'=0xEA86
    'SMART detallado'=0xEDA2; 'Historial'=0xE81C; 'Informes'=0xE9F9; 'Cuello de botella'=0xEC4A; 'Dispositivos'=0xE977
    'Visor de eventos'=0xE8FD; 'Monitor recursos'=0xE9D2; 'Info del sistema'=0xE946; 'DxDiag'=0xE7FC
    'Discos (Windows)'=0xEDA2; 'Confiabilidad'=0xE9D9; 'Informe 60 s'=0xE9F9; 'Tareas'=0xE71D; 'Servicios'=0xE713
    'Audio y micrófono'=0xE767; 'Pantalla (colores)'=0xE7F4; 'Ratón y táctil'=0xE962; 'Webcam'=0xE722
    'Teclado y Chattering'=0xE765; 'Informe rápido'=0xE8A5; 'Batería'=0xE83F; 'Energía (60 s)'=0xE945
    'SFC'=0xE90F; 'DISM'=0xE74C; 'Comprobar disco'=0xEDA2; 'Memoria Windows'=0xE964; 'Test de red'=0xE774
}

$GlifosScript = @{
    'Mantenimiento\Cambiar_IP.ps1'=0xE839; 'Mantenimiento\Latencia_DPC.ps1'=0xE9D9; 'Mantenimiento\Uso_VRAM.ps1'=0xE950; 'Mantenimiento\Asesor_BIOS.ps1'=0xE713; 'Mantenimiento\Disco_Destino_Instalacion.ps1'=0xEDA2; 'Mantenimiento\Clonar_Disco.ps1'=0xE8B7; 'Mantenimiento\Ficha_Drivers.ps1'=0xE772; 'Mantenimiento\Limpiar_Almacen_Drivers.ps1'=0xE74D; 'Mantenimiento\Instalar_Driver_Catalogo.ps1'=0xE896; 'Mantenimiento\Quien_Bloquea.ps1'=0xE72E; 'Mantenimiento\Editor_Hosts.ps1'=0xE774; 'Mantenimiento\Quitar_Dispositivos_Fantasma.ps1'=0xE9CE; 'Mantenimiento\Limpiar_Espacio_Windows.ps1'=0xE74D; 'Mantenimiento\Disco_Sucio_y_Reinicios.ps1'=0xE9D9; 'Mantenimiento\Optimizar_Unidades.ps1'=0xEDA2; 'Mantenimiento\Actualizar_Herramientas.ps1'=0xE895; 'Mantenimiento\Componentes_Kit.ps1'=0xEA86; 'Mantenimiento\Perfil_Baja_Latencia.ps1'=0xEC4A
    'Mantenimiento\Instalador_Basico.ps1'=0xE7B8; 'Mantenimiento\Actualizar_Software.ps1'=0xE896
    'Mantenimiento\Actualizar_Windows.ps1'=0xE777; 'Mantenimiento\Salud_Pendrive.ps1'=0xE88E
    'Mantenimiento\Inventario_Equipo.ps1'=0xE8FD; 'Mantenimiento\Punto_Restauracion.ps1'=0xE81C
    'Mantenimiento\Copia_Datos_Usuario.ps1'=0xE74E; 'Mantenimiento\Copia_Drivers.ps1'=0xE8C8
    'Mantenimiento\Restablecer_Windows_Update.ps1'=0xE72C; 'Mantenimiento\LimpiarTemporalesEquipo.ps1'=0xEA99
    'Mantenimiento\Optimizador_Personal.ps1'=0xEC4A; 'Mantenimiento\Optimizar_Rendimiento.ps1'=0xE945
    'Mantenimiento\Control_Energia.ps1'=0xE7E8; 'Mantenimiento\Gestion_Memoria_RAM.ps1'=0xE964
    'Mantenimiento\Diagnostico_Completo.ps1'=0xE9D9; 'Mantenimiento\Red_WiFi_y_Claves.ps1'=0xE701
    'Mantenimiento\Pantalla_Nitidez.ps1'=0xE7F4; 'Mantenimiento\Personalizar_Windows11.ps1'=0xE790
    'Mantenimiento\Desinstalar_Office.ps1'=0xE74D; 'Mantenimiento\Desinstalar_Bloatware_Win11.ps1'=0xEA99; 'Mantenimiento\Quitar_IA_Windows.ps1'=0xE72E
    'Mantenimiento\Analizar_Espacio_Disco.ps1'=0xE9D2; 'Mantenimiento\Reparar_Windows_y_Tienda.ps1'=0xE90F
    'Mantenimiento\Activar_Seguridad_Windows.ps1'=0xEA18; 'Mantenimiento\Actualizar_Version_Windows.ps1'=0xE898
    'Mantenimiento\Reparar_Red.ps1'=0xE774; 'Mantenimiento\Desinstalar_Total.ps1'=0xE74D; 'Mantenimiento\Limpiar_Registro_Huerfano.ps1'=0xE74D; 'Mantenimiento\Limpiar_Navegadores.ps1'=0xE774
    'Mantenimiento\Reparar_Impresoras.ps1'=0xE749; 'Mantenimiento\Programas_Inicio.ps1'=0xE7E8
    'Mantenimiento\Reparar_Inicio_Barra_Explorador.ps1'=0xE80F; 'Mantenimiento\Reparar_Audio_y_Privacidad.ps1'=0xE767; 'Mantenimiento\Hora_y_Sincronizacion.ps1'=0xE121
    'Mantenimiento\Reparar_Arranque_y_WinRE.ps1'=0xE7E8; 'Mantenimiento\Auditoria_Seguridad.ps1'=0xE83D; 'Mantenimiento\Desinfeccion_Guiada.ps1'=0xE7BA; 'Mantenimiento\Limpieza_Total.ps1'=0xE894;'Mantenimiento\Comprobar_WMI_y_Runtimes.ps1'=0xE9F5; 'Mantenimiento\Por_Que_Falla_Windows_Update.ps1'=0xE895
    'Mantenimiento\Que_Esta_Frenando_Ahora.ps1'=0xE9D9; 'Mantenimiento\Reparar_Office_y_Caches.ps1'=0xE8A5; 'Mantenimiento\Red_Avanzada.ps1'=0xE839
    'Mantenimiento\Prueba_Hardware.ps1'=0xE7F8; 'Mantenimiento\Restaurar_Datos_Usuario.ps1'=0xE777
    'Mantenimiento\Preparar_Venta.ps1'=0xE8EC; 'Mantenimiento\Informe_Entrega.ps1'=0xE8A5
    'Mantenimiento\Restaurar_Cuarentena.ps1'=0xE7A7; 'Mantenimiento\Vaciar_Cuarentena.ps1'=0xE74D
    'Mantenimiento\Deshacer_Cambios.ps1'=0xE7A7; 'Mantenimiento\Analizador_BSOD_y_Eventos.ps1'=0xE7BA
    'Mantenimiento\Auditoria_Licencias_BitLocker.ps1'=0xE8D7; 'Mantenimiento\Auditoria_Drivers_Huerfanos.ps1'=0xE950
    'Mantenimiento\Asistente_Guiado_Inteligente.ps1'=0xEA80; 'Mantenimiento\Monitor_Latencia_y_Red.ps1'=0xEC05; 'Mantenimiento\DNS_Mas_Rapido.ps1'=0xE774
    'Mantenimiento\Monitores_y_Garantia.ps1'=0xE7F4; 'Mantenimiento\Reparar_Perfil_Usuario.ps1'=0xE77B
    'Mantenimiento\Reparar_Drivers_OEM.ps1'=0xE950; 'Mantenimiento\Reinstalar_Grafica_Limpia.ps1'=0xE7F4; 'Mantenimiento\Puesta_a_Punto_Rapida.ps1'=0xE9F5; 'Mantenimiento\Reparar_TPM.ps1'=0xE8D7; 'Mantenimiento\Instalar_Impresora_Red.ps1'=0xE749
}

$form = New-Object Windows.Forms.Form
$form.Text = 'Nitrit0 Kit'
$form.Size = New-Object Drawing.Size(1240, 800)
$form.StartPosition = 'Manual'; $form.Location = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Location; $form.WindowState = 'Maximized'
$form.Font = New-Object Drawing.Font($script:Fuentes.UI, (9 * $script:Z))
$form.BackColor = $cFondo
$form.Add_HandleCreated({ [Nit.NativeUx]::SetDarkTitleBar($form.Handle, ($script:TemaActual -eq 'oscuro')) })

$logo = Join-Path $dirScripts 'Recursos\logo-nitrit0.png'
$bmpLogo = $null
if (Test-Path $logo) { try { $bmpLogo = New-Object Drawing.Bitmap($logo); $form.Icon = [Drawing.Icon]::FromHandle($bmpLogo.GetHicon()) } catch { } }

# --- Cabecera Superior Fluent ---
$KK = $script:KZ
$cab = New-Object Windows.Forms.Panel; $cab.Dock = 'Top'; $cab.Height = [int](60 * $KK); $cab.BackColor = $cCab
$x0 = [int](24 * $KK)
if ($bmpLogo) {
    $pb = New-Object Windows.Forms.PictureBox; $pb.Image = $bmpLogo; $pb.SizeMode = 'Zoom'; $pb.Size = New-Object Drawing.Size([int](38 * $KK), [int](38 * $KK)); $pb.Location = New-Object Drawing.Point([int](22 * $KK), [int](16 * $KK))
    $cab.Controls.Add($pb); $x0 = [int](70 * $KK)
}
$tit = New-Object Windows.Forms.Label; $tit.Text = 'Nitrit0 Kit'; $tit.ForeColor = (Get-Tc 'Texto'); $tit.AutoSize = $true
$tit.Font = New-Object Drawing.Font($script:Fuentes.Display, (14.5 * $script:Z)); $tit.Location = New-Object Drawing.Point($x0, [int](5 * $KK))
$sub = New-Object Windows.Forms.Label; $sub.ForeColor = $cTexto; $sub.AutoSize = $true
$sub.Font = New-Object Drawing.Font($script:Fuentes.UI, (9 * $script:Z)); $sub.Location = New-Object Drawing.Point(($x0 + 2), [int](34 * $KK))

# Buscador cápsula redondeado sin bordes cuadrados viejos
$searchWrap = New-Object Windows.Forms.Panel
$searchWrap.Size = New-Object Drawing.Size([int](265 * $KK), [int](36 * $KK))
$searchWrap.BackColor = $cCab
$searchWrap.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($searchWrap, $true, $null)
$busca = New-Object Windows.Forms.TextBox
$busca.BorderStyle = 'None'
$busca.BackColor = Get-Tc 'Tarjeta'
$busca.ForeColor = Get-Tc 'Texto'
$busca.Font = New-Object Drawing.Font($script:Fuentes.UI, (10 * $script:Z))
$busca.Width = [int](156 * $KK)
$busca.Location = New-Object Drawing.Point([int](36 * $KK), [int](9 * $KK))
$busca.Add_HandleCreated({ [void][Nit.NativeUx]::SendMessage($busca.Handle, 0x1501, 1, 'Buscar') })
$searchWrap.Controls.Add($busca)
$searchWrap.Add_Paint({
    param($s, $e)
    $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'ClearTypeGridFit'; $k = $script:KZ
    $r = New-Object Drawing.Rectangle(1, 1, ($s.ClientSize.Width - 3), ($s.ClientSize.Height - 3))
    $p = [UiHelper]::RoundRect($r, [int](16 * $k))
    $b = New-Object Drawing.SolidBrush (Get-Tc 'Tarjeta')
    $pen = New-Object Drawing.Pen((Get-Tc $(if ($busca.Focused) { 'Acento' } else { 'Borde' })), 1.0)
    $g.FillPath($b, $p); $g.DrawPath($pen, $p)
    $f = New-Object Drawing.Font('Segoe MDL2 Assets', (9.5 * $script:Z))
    $bt = New-Object Drawing.SolidBrush (Get-Tc 'Tenue')
    $g.DrawString([string][char]0xE721, $f, $bt, [single](12 * $k), [single](11 * $k))
    # El atajo se muestra como una tecla, no dentro del texto de ayuda
    $rk = New-Object Drawing.Rectangle(($s.ClientSize.Width - [int](60 * $k)), [int](8 * $k), [int](48 * $k), [int](20 * $k))
    $pk = [UiHelper]::RoundRect($rk, [int](8 * $k)); $penk = New-Object Drawing.Pen((Get-Tc 'Borde'), 1.0); $g.DrawPath($penk, $pk)
    $fk = New-Object Drawing.Font($script:Fuentes.Mono, (8.5 * $script:Z)); $sfk = New-Object Drawing.StringFormat; $sfk.Alignment = 'Center'; $sfk.LineAlignment = 'Center'
    $g.DrawString('Ctrl F', $fk, $bt, (New-Object Drawing.RectangleF($rk.X, $rk.Y, $rk.Width, $rk.Height)), $sfk)
    foreach ($o in $p, $b, $pen, $f, $bt, $pk, $penk, $fk, $sfk) { $o.Dispose() }
})
$busca.Add_GotFocus({ $searchWrap.Invalidate() })
$busca.Add_LostFocus({ $searchWrap.Invalidate() })

# Interruptor de modo claro / oscuro
$sw = New-Object Windows.Forms.Panel; $sw.Size = New-Object Drawing.Size([int](165 * $KK), [int](34 * $KK)); $sw.Cursor = 'Hand'; $sw.BackColor = $cCab
$sw.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($sw, $true, $null)
$script:SwPos = $(if ($script:TemaActual -eq 'oscuro') { 1.0 } else { 0.0 }); $script:SwObj = $script:SwPos
$sw.Add_Paint({
    param($s, $e)
    $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'ClearTypeGridFit'; $k = $script:KZ
    $w = [int](46 * $k); $h = [int](24 * $k); $x = $s.ClientSize.Width - $w - 2; $y = [int](($s.ClientSize.Height - $h) / 2); $t = $script:SwPos
    $c1 = Get-Tc 'Borde'; $c2 = Get-Tc 'Acento'
    $col = [Drawing.Color]::FromArgb([int]($c1.R + ($c2.R - $c1.R) * $t), [int]($c1.G + ($c2.G - $c1.G) * $t), [int]($c1.B + ($c2.B - $c1.B) * $t))
    $p = New-Object Drawing.Drawing2D.GraphicsPath; $p.AddArc($x, $y, $h, $h, 90, 180); $p.AddArc($x + $w - $h, $y, $h, $h, 270, 180); $p.CloseFigure()
    $b = New-Object Drawing.SolidBrush $col; $g.FillPath($b, $p); $b.Dispose(); $p.Dispose()
    $kb = New-Object Drawing.SolidBrush ([Drawing.Color]::White); $g.FillEllipse($kb, $x + 3 + ($w - $h) * $t, $y + 3, $h - 6, $h - 6); $kb.Dispose()
    $txt = if ($script:TemaActual -eq 'oscuro') { 'Modo oscuro' } else { 'Modo claro' }
    $f = New-Object Drawing.Font($script:Fuentes.UI, (9.5 * $script:Z)); $tb2 = New-Object Drawing.SolidBrush (Get-Tc 'TextoSuave'); $sf = New-Object Drawing.StringFormat; $sf.Alignment = 'Far'; $sf.LineAlignment = 'Center'
    $sf.FormatFlags = 'NoWrap'; $g.DrawString($txt, $f, $tb2, (New-Object Drawing.RectangleF 0, 0, ($x - 8), $s.ClientSize.Height), $sf); $f.Dispose(); $tb2.Dispose(); $sf.Dispose()
})
$tmSw = New-Object Windows.Forms.Timer; $tmSw.Interval = 15
$tmSw.Add_Tick({ $d = $script:SwObj - $script:SwPos; if ([Math]::Abs($d) -lt 0.05) { $script:SwPos = $script:SwObj; $tmSw.Stop() } else { $script:SwPos += $d * 0.35 }; $sw.Invalidate() })
# Ampliar o reducir la vista: guarda el zoom y vuelve a abrir el lanzador (todo el tamaño se calcula al arrancar)
function Set-Zoom([double]$z) {
    $z = [math]::Round([math]::Max(0.7, [math]::Min(1.3, $z)), 1)
    if ($z -eq [math]::Round($script:Z, 1) -or $Captura) { return }
    try { $a = Get-Ajustes; $a.Zoom = $z; Set-Ajustes $a } catch { return }
    $env:NIT_RETOMAR = "$($script:Pagina)|$($script:CatFiltro)"   # el lanzador nuevo hereda la página y el filtro
    try { Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`"" -ErrorAction Stop; $form.Close() } catch { }
}
$btnZoomMenos = New-Object BotonPro; $btnZoomMas = New-Object BotonPro
foreach ($bz in $btnZoomMenos, $btnZoomMas) { $bz.Size = New-Object Drawing.Size([int](40 * $KK), [int](34 * $KK)); $bz.ColorFondo = Get-Tc 'HeroBtn'; $bz.ColorTexto = Get-Tc 'Texto'; $bz.ColorBorde = Get-Tc 'HeroBorde'; $bz.Radio = 16 }
$btnZoomMenos.Text = 'A-'; $btnZoomMas.Text = 'A+'
$btnZoomMenos.Add_Click({ Set-Zoom ($script:Z - 0.1) }); $btnZoomMas.Add_Click({ Set-Zoom ($script:Z + 0.1) })
$cab.Controls.AddRange(@($tit, $sub, $searchWrap, $sw, $btnZoomMenos, $btnZoomMas))
$PosBusca = {
    $K = $script:KZ
    $sw.Left = $cab.ClientSize.Width - $sw.Width - [int](24 * $K)
    $sw.Top = [int](($cab.ClientSize.Height - $sw.Height) / 2)
    $searchWrap.Left = $sw.Left - $searchWrap.Width - [int](16 * $K)
    $searchWrap.Top = [int](($cab.ClientSize.Height - $searchWrap.Height) / 2)
    $btnZoomMas.Left = $searchWrap.Left - $btnZoomMas.Width - [int](16 * $K); $btnZoomMenos.Left = $btnZoomMas.Left - $btnZoomMenos.Width - [int](6 * $K)
    $btnZoomMas.Top = $btnZoomMenos.Top = [int](($cab.ClientSize.Height - $btnZoomMas.Height) / 2)
}

$st = New-Object Windows.Forms.StatusStrip; $st.BackColor = $cCab; $st.SizingGrip = $false
$lbl = New-Object Windows.Forms.ToolStripStatusLabel; $lbl.ForeColor = $cTexto; $lbl.Text = 'Listo'
[void]$st.Items.Add($lbl)

$tip = New-Object Windows.Forms.ToolTip; $tip.AutoPopDelay = 14000
$flow = New-Object Windows.Forms.FlowLayoutPanel
$flow.Dock = 'Fill'; $flow.AutoScroll = $true; $flow.BackColor = $cFondo; $flow.Padding = New-Object Windows.Forms.Padding(24, 8, 12, 16)
$flow.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($flow, $true, $null)

# --- Banner Hero con Botones Redondeados Modernos (BotonPro) ---
$K = $script:KZ
$heroHost = New-Object Windows.Forms.Panel; $heroHost.Dock = 'Top'; $heroHost.BackColor = $cFondo; $heroHost.Height = [int](108 * $K)
$heroHost.Padding = New-Object Windows.Forms.Padding([int](24 * $K), [int](12 * $K), [int](24 * $K), [int](4 * $K))
$hero = New-Object Windows.Forms.Panel; $hero.Dock = 'Fill'; $hero.BackColor = $cFondo
$hero.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($hero, $true, $null)
$heroHost.Controls.Add($hero)
$hero.Add_Paint({
    param($s, $e)
    $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'ClearTypeGridFit'; $k = $script:KZ
    $r = New-Object Drawing.Rectangle(0, 0, ($s.ClientSize.Width - 1), ($s.ClientSize.Height - 1))
    $p = [UiHelper]::RoundRect($r, [int](32 * $k))
    $bf = New-Object Drawing.SolidBrush (Get-Tc 'Tarjeta'); $pen = New-Object Drawing.Pen((Get-Tc 'Borde'), 1.0)
    $g.FillPath($bf, $p); $g.DrawPath($pen, $p)
    # Una sola línea: el modelo y, a su derecha, la lectura monoespaciada del equipo. Así el banner ocupa poco.
    $f1 = New-Object Drawing.Font($script:Fuentes.Display, (12.5 * $script:Z)); $f2 = New-Object Drawing.Font($script:Fuentes.Mono, (9.5 * $script:Z))
    $b1 = New-Object Drawing.SolidBrush (Get-Tc 'Texto'); $b2 = New-Object Drawing.SolidBrush (Get-Tc 'TextoSuave')
    $x = [single](22 * $k); $y = [single](9 * $k); $w1 = $g.MeasureString($script:EqModelo, $f1).Width
    $g.DrawString($script:EqModelo, $f1, $b1, $x, $y)
    $g.DrawString($script:EqDetalle, $f2, $b2, ($x + $w1 + [single](12 * $k)), ($y + [single](4 * $k)))
    foreach ($o in $p, $bf, $pen, $f1, $f2, $b1, $b2) { $o.Dispose() }
})
function Nuevo-BotonHeroPro([string]$texto, $fondo, $fore, $borde, [int]$ancho=162) {
    $b = New-Object BotonPro
    $b.Text = $texto
    $b.Size = New-Object Drawing.Size([int]($ancho * $script:KZ), [int](36 * $script:KZ))
    $b.ColorFondo = $fondo
    $b.ColorTexto = $fore
    $b.ColorBorde = $borde
    $b.Radio = 16
    $b
}

# Una sola acción principal en el acento; el resto son botones secundarios iguales
$btnHeroRapido     = Nuevo-BotonHeroPro 'Diagnóstico rápido' (Get-Tc 'Acento') (Get-Tc 'TextoAcento') ([Drawing.Color]::Transparent) 164
$btnHeroCompleto   = Nuevo-BotonHeroPro 'Diagnóstico profundo' (Get-Tc 'HeroBtn') (Get-Tc 'Texto') (Get-Tc 'HeroBorde') 172
$btnHeroEquilibrio = Nuevo-BotonHeroPro 'Cuello de botella' (Get-Tc 'HeroBtn') (Get-Tc 'Texto') (Get-Tc 'HeroBorde') 152
$btnHeroTaller     = Nuevo-BotonHeroPro 'Modo taller' (Get-Tc 'HeroBtn') (Get-Tc 'Texto') (Get-Tc 'HeroBorde') 120
$btnHeroAsistente  = Nuevo-BotonHeroPro 'Asistente guiado' (Get-Tc 'HeroBtn') (Get-Tc 'Texto') (Get-Tc 'HeroBorde') 148
$hero.Controls.AddRange(@($btnHeroAsistente, $btnHeroTaller, $btnHeroEquilibrio, $btnHeroCompleto, $btnHeroRapido))
$hero.Add_Resize({
    $k = $script:KZ; $y = $hero.ClientSize.Height - $btnHeroRapido.Height - [int](12 * $k); $sep = [int](8 * $k)
    $btnHeroRapido.Location     = New-Object Drawing.Point([int](24 * $k), $y)
    $btnHeroCompleto.Location   = New-Object Drawing.Point(($btnHeroRapido.Right + $sep), $y)
    $btnHeroEquilibrio.Location = New-Object Drawing.Point(($btnHeroCompleto.Right + $sep), $y)
    $btnHeroTaller.Location     = New-Object Drawing.Point(($btnHeroEquilibrio.Right + $sep), $y)
    $btnHeroAsistente.Location  = New-Object Drawing.Point(($btnHeroTaller.Right + $sep), $y)
    $hero.Invalidate()
})
$tip2 = New-Object Windows.Forms.ToolTip
$tip2.SetToolTip($btnHeroRapido, 'Menos de un minuto: Windows, procesador, memoria, discos, batería, drivers, sucesos y seguridad.')
$tip2.SetToolTip($btnHeroCompleto, 'Unos 10 minutos: añade la comprobación del sistema de archivos (chkdsk) y de los archivos de Windows (SFC).')
$tip2.SetToolTip($btnHeroEquilibrio, 'Analiza si algún componente hace cuello de botella (RAM en Single Channel, gráfica limitada o disco mecánico) y frena al resto del equipo.')
$tip2.SetToolTip($btnHeroTaller, 'Flujo profesional: pide datos del cliente, ejecuta diagnóstico rápido y abre informe HTML de entrega.')
$tip2.SetToolTip($btnHeroAsistente, '¿No sabes qué herramienta elegir? Selecciona el síntoma del ordenador y lo repara paso a paso.')

$btnHeroEquilibrio.Add_Click({ if (Get-Command Show-Equilibrio -ErrorAction SilentlyContinue) { Show-Equilibrio 'Config' } })
$btnHeroTaller.Add_Click({ if (Get-Command Show-Diagnostico -ErrorAction SilentlyContinue) { Show-Diagnostico 'Rapido' $true $true } })
$btnHeroRapido.Add_Click({ if (Get-Command Show-Diagnostico -ErrorAction SilentlyContinue) { Show-Diagnostico 'Rapido' $true } })
$btnHeroCompleto.Add_Click({ if (Get-Command Show-Diagnostico -ErrorAction SilentlyContinue) { Show-Diagnostico 'Completo' $true } })
$btnHeroAsistente.Add_Click({ Start-Herramienta ($Herramientas | Where-Object { $_.N -eq 'Asistente guiado' } | Select-Object -First 1) $null })

# --- Filtro de Categorías con Píldoras Redondeadas (ChipPro) y Contador ---
$chips = New-Object Windows.Forms.FlowLayoutPanel; $chips.Dock = 'Top'; $chips.BackColor = $cFondo; $chips.Height = [int](48 * $K)
$chips.Padding = New-Object Windows.Forms.Padding([int](24 * $K), [int](10 * $K), [int](10 * $K), 0); $chips.WrapContents = $true; $chips.AutoScroll = $false
$chips.Add_Resize({ $h = $chips.GetPreferredSize((New-Object Drawing.Size($chips.ClientSize.Width, 0))).Height + [int](10 * $script:KZ); if ($chips.Height -ne $h) { $chips.Height = $h } })

function Marcar-Chips {
    foreach ($b in $chips.Controls) {
        $b.Seleccionado = ([string]$b.Tag -eq $script:CatFiltro)
        $b.Acento = Get-Tc 'Acento'
        $b.Invalidate()
    }
}

# Tamaño de una píldora según su texto; $extra ensancha las de página
function Set-TamanoChip($b, [int]$alto, [int]$extra) {
    $gTmp = [Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
    $fTmp = New-Object Drawing.Font($script:Fuentes.UI, (9 * $script:Z))
    $w = [int][Math]::Ceiling($gTmp.MeasureString("$($b.Text)  $($b.Cantidad)", $fTmp).Width) + [int]((26 + $extra) * $K)
    $fTmp.Dispose(); $gTmp.Dispose()
    $b.Size = New-Object Drawing.Size($w, [int]($alto * $K))
}

# Selector de página (Comprobar / Preparar equipo / Reparar y mantener / Kit)
$barraPaginas = New-Object Windows.Forms.FlowLayoutPanel; $barraPaginas.Dock = 'Top'; $barraPaginas.BackColor = $cFondo; $barraPaginas.Height = [int](54 * $K)
$barraPaginas.Padding = New-Object Windows.Forms.Padding([int](24 * $K), [int](10 * $K), [int](10 * $K), 0); $barraPaginas.WrapContents = $false; $barraPaginas.AutoScroll = $false
function Marcar-Paginas {
    foreach ($b in $barraPaginas.Controls) { $b.Seleccionado = ([string]$b.Tag -eq $script:Pagina); $b.Acento = Get-Tc 'Acento'; $b.Invalidate() }
}
foreach ($p in $Paginas.Keys) {
    $b = New-Object ChipPro
    $b.Text = $p; $b.Tag = $p
    $b.Cantidad = @(Get-Visibles | Where-Object { $_.P -eq $p }).Count
    Set-TamanoChip $b 36 28
    $b.Margin = New-Object Windows.Forms.Padding(0, 0, [int](10 * $K), 0)
    $b.Add_Click({ param($origen, $ev) $script:Pagina = [string]$origen.Tag; $script:CatFiltro = ''; Marcar-Paginas; Build-Chips; Show-Tarjetas })
    $barraPaginas.Controls.Add($b)
}
Marcar-Paginas

# Filtros de la página actual: Todas, ★ Favoritos (si hay) y sus grupos
function Build-Chips {
    $chips.SuspendLayout()
    while ($chips.Controls.Count -gt 0) { $x = $chips.Controls[0]; $chips.Controls.RemoveAt(0); $x.Dispose() }
    $grupos = @($Paginas[$script:Pagina])
    $enPag = @(Get-Visibles | Where-Object { $_.P -eq $script:Pagina })
    $nFav = @($enPag | Where-Object { $script:Favoritos -contains $_.N }).Count
    if ($script:CatFiltro -eq '★ Favoritos' -and $nFav -eq 0) { $script:CatFiltro = '' }
    foreach ($c in @('', '★ Favoritos') + $grupos) {
        $cnt = if ($c -eq '★ Favoritos') { $nFav } elseif ($c) { @($enPag | Where-Object { $_.G -eq $c }).Count } else { $enPag.Count }
        if ($c -eq '★ Favoritos' -and $cnt -eq 0) { continue }
        $b = New-Object ChipPro
        $b.Text = if ($c) { $c -replace '^★ ', '' } else { 'Todas' }
        $b.Tag = $c; $b.Cantidad = $cnt
        Set-TamanoChip $b 30 0
        $b.Margin = New-Object Windows.Forms.Padding(0, 0, [int](8 * $K), [int](8 * $K))
        $b.Add_Click({ param($origen, $ev) $script:CatFiltro = [string]$origen.Tag; Marcar-Chips; Show-Tarjetas })
        $chips.Controls.Add($b)
    }
    $chips.Visible = ($grupos.Count -gt 1)   # la página Kit tiene un solo grupo: sin filtros
    $chips.ResumeLayout()
    $h = $chips.GetPreferredSize((New-Object Drawing.Size($chips.ClientSize.Width, 0))).Height + [int](10 * $script:KZ); if ($chips.Height -ne $h) { $chips.Height = $h }
    Marcar-Chips
}
function Update-ChipsCount { Build-Chips }
Build-Chips

function Update-ColoresVentana {
    [Nit.NativeUx]::SetDarkTitleBar($form.Handle, ($script:TemaActual -eq 'oscuro'))
    $form.BackColor = Get-Tc 'Fondo'; $cab.BackColor = Get-Tc 'Cab'; $sw.BackColor = Get-Tc 'Cab'; $searchWrap.BackColor = Get-Tc 'Cab'
    $tit.ForeColor = Get-Tc 'Texto'; $sub.ForeColor = Get-Tc 'TextoSuave'
    $busca.BackColor = Get-Tc 'Tarjeta'; $busca.ForeColor = Get-Tc 'Texto'; $st.BackColor = Get-Tc 'Cab'
    if (-not $script:Desconectado) { $lbl.ForeColor = Get-Tc 'TextoSuave' }
    $flow.BackColor = Get-Tc 'Fondo'; $chips.BackColor = Get-Tc 'Fondo'; $barraPaginas.BackColor = Get-Tc 'Fondo'; Marcar-Paginas; $heroHost.BackColor = Get-Tc 'Fondo'; $hero.BackColor = Get-Tc 'Fondo'
    $btnHeroRapido.ColorFondo = Get-Tc 'Acento'; $btnHeroRapido.ColorTexto = Get-Tc 'TextoAcento'
    foreach ($bb in @($btnHeroCompleto, $btnHeroEquilibrio, $btnHeroTaller, $btnHeroAsistente)) { $bb.ColorFondo = Get-Tc 'HeroBtn'; $bb.ColorTexto = Get-Tc 'Texto'; $bb.ColorBorde = Get-Tc 'HeroBorde'; $bb.Invalidate() }
    $btnHeroRapido.Invalidate()

    Marcar-Chips; $hero.Invalidate(); $sw.Invalidate(); $searchWrap.Invalidate()
}

function Set-TemaVivo([string]$modo) {
    Set-Tema $modo
    try { $a = Get-Ajustes; $a.Tema = $modo; Set-Ajustes $a } catch { }
    $script:SwObj = $(if ($modo -eq 'oscuro') { 1.0 } else { 0.0 }); $tmSw.Start()
    $form.SuspendLayout(); Update-ColoresVentana; Show-Tarjetas; $form.ResumeLayout(); $form.Refresh()
}
$sw.Add_Click({ Set-TemaVivo $(if ($script:TemaActual -eq 'oscuro') { 'claro' } else { 'oscuro' }) })
$form.Controls.AddRange(@($flow, $st, $chips, $barraPaginas, $heroHost, $cab))
$script:Cabs = @()

function Show-Tarjetas {
    $q = $busca.Text.Trim()
    $flow.SuspendLayout()
    while ($flow.Controls.Count -gt 0) {
        $ctrl = $flow.Controls[0]
        $flow.Controls.RemoveAt(0)
        $ctrl.Dispose()
    }
    $script:Cabs = @()
    $ok = 0
    # Secciones: con búsqueda, todas las páginas; sin ella, solo la página elegida (sin repetir favoritos debajo)
    $todas = Get-Visibles; $secciones = @()
    if ($q) {
        foreach ($p in $Paginas.Keys) { foreach ($g in $Paginas[$p]) {
            $it = @($todas | Where-Object { $_.P -eq $p -and $_.G -eq $g -and ($_.N -like "*$q*" -or $_.D -like "*$q*") })
            if ($it) { $secciones += , @("$p  ›  $g", $it) }
        } }
    } elseif ($script:CatFiltro -eq '★ Favoritos') {
        $it = @($todas | Where-Object { $_.P -eq $script:Pagina -and ($script:Favoritos -contains $_.N) })
        if ($it) { $secciones += , @('Favoritos', $it) }
    } else {
        foreach ($g in $Paginas[$script:Pagina]) {
            if ($script:CatFiltro -and $g -ne $script:CatFiltro) { continue }
            $it = @($todas | Where-Object { $_.P -eq $script:Pagina -and $_.G -eq $g })
            if ($it) { $secciones += , @($g, $it) }
        }
    }
    foreach ($sec in $secciones) {
        $c = $sec[0]; $grupo = $sec[1]
        $acento = Get-AcentoCat $c
        $h1 = New-Object Windows.Forms.Label
        $h1.Text = "$($c -replace '^★ ', '')  ·  $($grupo.Count)"; $h1.ForeColor = Get-Tc 'TextoSuave'
        $h1.Font = New-Object Drawing.Font($script:Fuentes.Semi, (9.5 * $script:Z)); $h1.Height = [int](24 * $script:KZ); $h1.TextAlign = 'BottomLeft'
        $h1.Width = $flow.ClientSize.Width - 60; $h1.Margin = New-Object Windows.Forms.Padding(0, 6, 0, 4)
        $flow.Controls.Add($h1); $flow.SetFlowBreak($h1, $true); $script:Cabs += $h1
        foreach ($h in $grupo) {
            $e = Get-Exe $h
            $disp = [bool]($h.Uri -or $h.Informe -or $h.Cmd -or $h.Run -or $h.Accion -or $e -or ($h.Html -and (Test-Path -LiteralPath (Join-Path $dirScripts $h.Html))) -or ($h.Script -and (Test-Path -LiteralPath (Join-Path $dirScripts $h.Script))))
            if ($disp) { $ok++ }
            $t = New-Object TarjetaPro
            $t.Titulo = $h.N; $t.Desc = $h.D; $t.Acento = $acento; $t.Activa = $disp; $t.Peligro = [bool]$h.Peligro
            $t.Favorito = ($script:Favoritos -contains $h.N)
            $t.Margin = New-Object Windows.Forms.Padding(0, 0, [int](12 * $script:KZ), [int](12 * $script:KZ)); $t.Tag = $h
            if ($e) {
                if (-not $script:IconCache.ContainsKey($e)) {
                    try {
                        $icoObj = [Drawing.Icon]::ExtractAssociatedIcon($e)
                        if ($icoObj) { $script:IconCache[$e] = $icoObj.ToBitmap(); $icoObj.Dispose() }
                    } catch { }
                }
                if ($script:IconCache.ContainsKey($e)) { $t.Icono = $script:IconCache[$e] }
            }
            if (-not $t.Icono -and $Glifos.ContainsKey($h.N)) { $t.Glifo = [char]::ConvertFromUtf32($Glifos[$h.N]) }
            elseif (-not $t.Icono -and $h.Script) { $t.Glifo = [char]::ConvertFromUtf32($(if ($GlifosScript.ContainsKey($h.Script)) { $GlifosScript[$h.Script] } else { 0xE713 })) }
            $tipText = $h.D + $(if ($h.Ayuda) { "`n`n" + $h.Ayuda.Trim() } else { '' })
            $tip.SetToolTip($t, $tipText)
            $t.Add_MouseUp({
                param($origen, $ev)
                if ($origen.ClickEnEstrella) {
                    Toggle-Favorito $origen.Tag.N
                } elseif ($ev.Button -eq [Windows.Forms.MouseButtons]::Left -and $origen.Activa) {
                    Start-Herramienta $origen.Tag $origen
                }
            })
            $flow.Controls.Add($t)
        }
    }
    $flow.ResumeLayout()
    $sub.Text = "v$VersionKit  ·  $ok herramientas listas en esta vista"
}

$form.KeyPreview = $true
$form.Add_KeyDown({
    param($s, $e)
    if ($e.Control -and $e.KeyCode -eq 'F') {
        $busca.Focus(); $busca.SelectAll(); $e.SuppressKeyPress = $true
    } elseif ($e.Control -and $e.KeyCode -in 'Oemplus', 'Add') { Set-Zoom ($script:Z + 0.1); $e.SuppressKeyPress = $true
    } elseif ($e.Control -and $e.KeyCode -in 'OemMinus', 'Subtract') { Set-Zoom ($script:Z - 0.1); $e.SuppressKeyPress = $true
    } elseif ($e.Control -and $e.KeyCode -in 'D0', 'NumPad0') { Set-Zoom 1.0; $e.SuppressKeyPress = $true
    } elseif ($e.KeyCode -eq 'Escape') {
        if ($busca.Text.Length -gt 0) { $busca.Text = ''; $e.SuppressKeyPress = $true }
        elseif ($script:CatFiltro -ne '') { $script:CatFiltro = ''; Marcar-Chips; Show-Tarjetas; $e.SuppressKeyPress = $true }
    }
})

$tb = New-Object Windows.Forms.Timer; $tb.Interval = 180
$tb.Add_Tick({ $tb.Stop(); Show-Tarjetas })
$busca.Add_TextChanged({ $tb.Stop(); $tb.Start() })
$cab.Add_Resize($PosBusca)
$form.Add_Resize({ foreach ($c in $script:Cabs) { $c.Width = [Math]::Max(200, $flow.ClientSize.Width - 60) } })

$script:Desconectado = $false; $script:TDesc = $null
$tmKit = New-Object Windows.Forms.Timer; $tmKit.Interval = 3000
$tmKit.Add_Tick({
    $ok = Test-KitDisponible
    if (-not $ok) {
        $n = Find-KitReconectado
        if ($n) { $Global:NitKit.Raiz = $n; $Global:NitKit.Datos = Join-Path $n 'Datos'; $env:NIT_RAIZ = $n; Update-RutasKit; $ok = Test-KitDisponible }
    }
    if (-not $ok -and -not $script:Desconectado) {
        $script:Desconectado = $true; $script:TDesc = Get-Date; Write-Log 'Unidad del kit desconectada (detectado por el lanzador)' 'AVISO'
        $lbl.Text = 'Unidad del kit desconectada. Vuelve a conectarla y se retomará sola'; $lbl.ForeColor = Get-Tc 'Aviso'
    }
    elseif ($ok -and $script:Desconectado) {
        $script:Desconectado = $false; $seg = [int]((Get-Date) - $script:TDesc).TotalSeconds; Update-RutasKit
        Write-Log "Unidad del kit reconectada tras $seg s" 'INFO'; Sync-Log
        $lbl.Text = "Unidad reconectada tras $seg s"; $lbl.ForeColor = Get-Tc 'Ok'; Show-Tarjetas
    }
})

$form.Add_Shown({
    [Nit.NativeUx]::SetDarkTitleBar($form.Handle, ($script:TemaActual -eq 'oscuro'))
    & $PosBusca; Show-Tarjetas; $tmKit.Start()
    if ($Captura) {
        $script:tc = New-Object Windows.Forms.Timer; $script:tc.Interval = 1800
        $script:tc.Add_Tick({ $script:tc.Stop(); try { $bm = New-Object Drawing.Bitmap($form.Width, $form.Height); $form.DrawToBitmap($bm, (New-Object Drawing.Rectangle 0, 0, $form.Width, $form.Height)); $bm.Save($Captura, [Drawing.Imaging.ImageFormat]::Png); $bm.Dispose() } catch { Write-Log "Captura falló: $($_.Exception.Message)" 'ERROR' }; $form.Close() })
        $script:tc.Start(); return
    }
    if (Get-Command Invoke-OfertaDriver -ErrorAction SilentlyContinue) { try { Invoke-OfertaDriver } catch { } }
    if ($Auto -and (Get-Command Show-Diagnostico -ErrorAction SilentlyContinue)) { Show-Diagnostico 'Rapido' $true $true }
})
$form.Add_FormClosed({ $tmKit.Stop(); Write-Log 'Lanzador cerrado'; try { if ((Get-Command Get-Ajustes -ErrorAction SilentlyContinue) -and $script:DriverInstaladoEnSesion -and (Get-Ajustes).QuitarDriverAlSalir) { [void](Invoke-Pawnio 'quitar') } } catch { } })

[void]$form.ShowDialog()
