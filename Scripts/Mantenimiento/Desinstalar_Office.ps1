# =====================================================================
#  Desinstalar_Office.ps1
#  Quita cualquier versión de Microsoft Office / Microsoft 365 / Visio / Project y deja el equipo
#  limpio para reinstalar desde cero:
#   1. Quita las claves de producto instaladas (ospp.vbs /unpkey).
#   2. Desinstala los productos MSI (2003-2019) y los de Click-to-Run (2013 C2R, 2016, 2019, 2021, 365).
#   3. Cierra procesos y borra servicios, tareas programadas, carpetas y claves de registro sobrantes.
#   4. (Opcional) Borra la configuración de usuario de Office (nunca los .pst/.ost del correo).
#  Solo actúa en el equipo local. Usa -Simular para ver lo que haría sin cambiar nada.
# =====================================================================
[CmdletBinding()]
param(
    [Alias('SoloAnalizar')][switch]$Simular,
    [switch]$IncluirDatosUsuario,
    [switch]$SinMenu,
    [switch]$PuntoRestauracion
)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }

if (-not $Global:E) {
    $Global:E = @{
        OK = [char]::ConvertFromUtf32(0x2705); Error = [char]::ConvertFromUtf32(0x274C); Aviso = [char]::ConvertFromUtf32(0x26A0)
        Info = [char]::ConvertFromUtf32(0x2139); Cohete = [char]::ConvertFromUtf32(0x1F680); Lupa = [char]::ConvertFromUtf32(0x1F50D)
        Disco = [char]::ConvertFromUtf32(0x1F4BE); Reloj = [char]::ConvertFromUtf32(0x23F3); Refresh = [char]::ConvertFromUtf32(0x1F504)
        Basura = [char]::ConvertFromUtf32(0x1F5D1)
    }
}

$script:Eliminados = 0
$script:Fallos     = 0
$script:YaNoEstaba = 0
$script:ClavesSim  = 0
$script:Simulando  = [bool]$Simular

# ---------------------------------------------------------------------
#  Utilidades de borrado (con modo simulación)
# ---------------------------------------------------------------------
# OJO: el runspace del panel es persistente; si se cambia el código C# hay que cambiar también el nombre de la clase (RegSeguraV3...) o no se recompila.
# Borrado de registro que NO sigue enlaces simbólicos (Office deja alguno; Remove-Item falla y puede borrar su destino; si hay acceso denegado toma posesión de la clave)
if (-not ('RegSeguraV2' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class RegSeguraV2
{
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode)] static extern int RegOpenKeyEx(IntPtr hKey, string sub, int opciones, int sam, out IntPtr resultado);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode)] static extern int RegEnumKeyEx(IntPtr h, int indice, StringBuilder nombre, ref int cch, IntPtr res, IntPtr clase, IntPtr cc, IntPtr ft);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode)] static extern int RegQueryValueEx(IntPtr h, string nombre, IntPtr res, out int tipo, IntPtr datos, ref int cb);
    [DllImport("advapi32.dll")] static extern int RegCloseKey(IntPtr h);
    [DllImport("advapi32.dll")] static extern int RegSetKeySecurity(IntPtr h, int info, IntPtr sd);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, EntryPoint = "ConvertStringSecurityDescriptorToSecurityDescriptorW")] static extern bool ConvSddl(string sddl, uint rev, out IntPtr sd, out uint len);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode)] static extern bool LookupPrivilegeValue(string sistema, string nombre, out LUID luid);
    [DllImport("advapi32.dll")] static extern bool OpenProcessToken(IntPtr proceso, uint acceso, out IntPtr token);
    [DllImport("advapi32.dll")] static extern bool AdjustTokenPrivileges(IntPtr token, bool desactivarTodo, ref TOKEN_PRIVILEGES nuevo, int len, IntPtr anterior, IntPtr retLen);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr p);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("ntdll.dll")] static extern int NtDeleteKey(IntPtr h);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode)] static extern int RegCreateKeyEx(IntPtr hKey, string sub, int res, string clase, int opciones, int sam, IntPtr seg, out IntPtr resultado, out int disp);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode)] static extern int RegSetValueEx(IntPtr h, string nombre, int res, int tipo, byte[] datos, int cb);

    [StructLayout(LayoutKind.Sequential)] struct LUID { public uint Bajo; public int Alto; }
    [StructLayout(LayoutKind.Sequential)] struct LUID_Y_ATRIBUTOS { public LUID Luid; public uint Atributos; }
    [StructLayout(LayoutKind.Sequential)] struct TOKEN_PRIVILEGES { public int Cuenta; public LUID_Y_ATRIBUTOS Privilegio; }

    const int OPEN_LINK = 0x8, BACKUP_RESTORE = 0x4, CREATE_LINK = 0x2;
    const int DELETE = 0x10000, WRITE_DAC = 0x40000, WRITE_OWNER = 0x80000;
    const int ENUM_SUB = 0x8, QUERY = 0x1, WOW64_64 = 0x100, ALL = 0xF003F;
    const int OWNER_SI = 0x1, DACL_SI = 0x4;
    static readonly int PROTECTED_DACL = unchecked((int)0x80000000);
    static bool privilegiosListos;

    static IntPtr Raiz(string hive)
    {
        switch (hive.ToUpperInvariant())
        {
            case "HKLM": return new IntPtr(unchecked((int)0x80000002));
            case "HKCU": return new IntPtr(unchecked((int)0x80000001));
            case "HKU":  return new IntPtr(unchecked((int)0x80000003));
            default: throw new ArgumentException("hive no válido: " + hive);
        }
    }

    static void Habilitar(string nombre)
    {
        IntPtr token;
        if (!OpenProcessToken(GetCurrentProcess(), 0x28, out token)) return;
        try
        {
            LUID luid;
            if (!LookupPrivilegeValue(null, nombre, out luid)) return;
            var tp = new TOKEN_PRIVILEGES { Cuenta = 1, Privilegio = new LUID_Y_ATRIBUTOS { Luid = luid, Atributos = 2 } };
            AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
        }
        finally { CloseHandle(token); }
    }

    static void Privilegios()
    {
        if (privilegiosListos) return;
        foreach (string p in new[] { "SeTakeOwnershipPrivilege", "SeRestorePrivilege", "SeBackupPrivilege" }) Habilitar(p);
        privilegiosListos = true;
    }

    // Toma posesión de la clave (propietario = Administradores) y le concede control total a Administradores y SYSTEM.
    // Devuelve "" si todo fue bien o el paso que falló.
    static string TomarPosesion(IntPtr raiz, string ruta)
    {
        IntPtr h, sd; uint n; int r;
        r = RegOpenKeyEx(raiz, ruta, OPEN_LINK, WRITE_OWNER | WOW64_64, out h);
        if (r != 0) return "WRITE_OWNER (" + r + ")";
        if (!ConvSddl("O:BA", 1, out sd, out n)) { RegCloseKey(h); return "SDDL propietario"; }
        r = RegSetKeySecurity(h, OWNER_SI, sd); LocalFree(sd); RegCloseKey(h);
        if (r != 0) return "cambiar propietario (" + r + ")";

        r = RegOpenKeyEx(raiz, ruta, OPEN_LINK, WRITE_DAC | WOW64_64, out h);
        if (r != 0) return "WRITE_DAC (" + r + ")";
        if (!ConvSddl("D:P(A;OICI;KA;;;BA)(A;OICI;KA;;;SY)", 1, out sd, out n)) { RegCloseKey(h); return "SDDL permisos"; }
        r = RegSetKeySecurity(h, DACL_SI | PROTECTED_DACL, sd); LocalFree(sd); RegCloseKey(h);
        if (r != 0) return "cambiar permisos (" + r + ")";
        return "";
    }

    // Abre sin seguir enlaces. Si se deniega: 1) privilegios de copia/restauración; 2) tomar posesión y reabrir.
    static int Abrir(IntPtr raiz, string ruta, out IntPtr h, out string nota)
    {
        nota = "";
        int sam = DELETE | ENUM_SUB | QUERY | WOW64_64;
        int r = RegOpenKeyEx(raiz, ruta, OPEN_LINK, sam, out h);
        if (r != 5) return r;

        Privilegios();
        r = RegOpenKeyEx(raiz, ruta, OPEN_LINK | BACKUP_RESTORE, sam, out h);
        if (r == 0) { nota = "abierta con privilegios de restauración"; return 0; }

        string fallo = TomarPosesion(raiz, ruta);
        if (fallo.Length > 0) { nota = "no se pudo tomar posesión: " + fallo; return 5; }
        nota = "tras tomar posesión";
        return RegOpenKeyEx(raiz, ruta, OPEN_LINK, sam, out h);
    }

    // Borra una clave y todo lo que cuelga de ella SIN seguir enlaces simbólicos de registro (el enlace se borra, su destino no).
    // Devuelve "" si todo fue bien o el detalle del primer problema.
    public static string Eliminar(string hive, string ruta)
    {
        return Borrar(Raiz(hive), ruta.Trim('\\'), 0);
    }

    static string Borrar(IntPtr raiz, string ruta, int profundidad)
    {
        if (profundidad > 60) return "profundidad excesiva en " + ruta;
        IntPtr h; string nota;
        int r = Abrir(raiz, ruta, out h, out nota);
        if (r == 2) return "";
        if (r != 0) return "no se pudo abrir (" + r + (nota.Length > 0 ? ", " + nota : "") + "): " + ruta;
        string error = "";
        try
        {
            int tipo, cb = 0;
            int q = RegQueryValueEx(h, "SymbolicLinkValue", IntPtr.Zero, out tipo, IntPtr.Zero, ref cb);
            bool esEnlace = (q == 0 || q == 234);
            if (!esEnlace)
            {
                var hijos = new List<string>();
                for (int i = 0; ; i++)
                {
                    var sb = new StringBuilder(512); int cch = 512;
                    if (RegEnumKeyEx(h, i, sb, ref cch, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero) != 0) break;
                    hijos.Add(sb.ToString());
                }
                foreach (string hijo in hijos)
                {
                    string eh = Borrar(raiz, ruta + "\\" + hijo, profundidad + 1);
                    if (eh.Length > 0 && error.Length == 0) error = eh;
                }
            }
            int st = NtDeleteKey(h);
            if (st != 0 && error.Length == 0) error = "NtDeleteKey 0x" + st.ToString("X") + " en " + ruta;
        }
        finally { RegCloseKey(h); }
        return error;
    }
}
'@
}

function Remove-RutaOffice {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Ruta)

    if (-not (Test-Path -LiteralPath $Ruta)) { return }
    if ($script:Simulando) { Write-Output "    [simulación] borraría la carpeta: $Ruta"; return }
    try {
        Remove-Item -LiteralPath $Ruta -Recurse -Force -ErrorAction Stop
        Write-Output "    $($Global:E.OK) Carpeta borrada: $Ruta"
        $script:Eliminados++
    }
    catch {
        # Carpetas con permisos de SYSTEM/TrustedInstaller (p. ej. MSOCache): se toma posesión y se reintenta
        try {
            # takeown /d pide la respuesta por defecto en el idioma de Windows («s», «y», «j»…): se usa icacls con el SID de Administradores, que no depende del idioma
            & icacls.exe $Ruta /setowner '*S-1-5-32-544' /t /c /q *> $null
            & icacls.exe $Ruta /grant '*S-1-5-32-544:F' /t /c /q *> $null   # SID del grupo Administradores: el nombre «Administrators» no existe en un Windows en español
            Remove-Item -LiteralPath $Ruta -Recurse -Force -ErrorAction Stop
            Write-Output "    $($Global:E.OK) Carpeta borrada (tomando posesión): $Ruta"
            $script:Eliminados++
        }
        catch {
            Write-Output "    $($Global:E.Aviso) No se pudo borrar del todo: $Ruta (puede quedar algo en uso hasta reiniciar)"
            $script:Fallos++
        }
    }
}

function Remove-ClaveOffice {
    param([string]$Clave)
    if (-not (Test-Path -LiteralPath $Clave)) { return }
    if ($script:Simulando) { $script:ClavesSim++; return }

    # Ruta nativa (hive + subruta) para el borrado que no sigue enlaces
    $nativa = $Clave -replace '^Microsoft\.PowerShell\.Core\\Registry::', ''
    $nativa = $nativa -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\' -replace '^HKCU:\\', 'HKEY_CURRENT_USER\'
    $hive = $null; $sub = $null
    if ($nativa -match '^(HKEY_LOCAL_MACHINE|HKLM)\\(.+)$') { $hive = 'HKLM'; $sub = $Matches[2] }
    elseif ($nativa -match '^(HKEY_USERS|HKU)\\(.+)$') { $hive = 'HKU'; $sub = $Matches[2] }
    elseif ($nativa -match '^(HKEY_CURRENT_USER|HKCU)\\(.+)$') { $hive = 'HKCU'; $sub = $Matches[2] }

    $detalle = ''
    if ($hive) { $detalle = [RegSeguraV2]::Eliminar($hive, $sub) }
    else { try { Remove-Item -LiteralPath $Clave -Recurse -Force -ErrorAction Stop } catch { $detalle = $_.Exception.Message } }

    # Si algo quedó (permisos solo de SYSTEM), se reintenta con una tarea puntual que corre como SYSTEM
    # $nativa va dentro de una línea de cmd.exe que corre como SYSTEM: solo se usa si no lleva caracteres de shell
    if ((Test-Path -LiteralPath $Clave) -and $hive -eq 'HKLM' -and $nativa -notmatch '^[\w\\ .\-{}(),@]+$') { Write-Output "    $($Global:E.Info) Sin reintento como SYSTEM: la clave lleva caracteres que no se pasan a una línea de shell." }
    if ((Test-Path -LiteralPath $Clave) -and $hive -eq 'HKLM' -and $nativa -match '^[\w\\ .\-{}(),@]+$') {
        $tarea = 'OfficeLimpiezaReg_' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        try {
            & schtasks.exe /Create /TN $tarea /TR "cmd.exe /c reg delete `"$nativa`" /f" /SC ONCE /ST 00:00 /RU SYSTEM /RL HIGHEST /F *> $null
            & schtasks.exe /Run /TN $tarea *> $null
            for ($i = 0; $i -lt 20 -and (Test-Path -LiteralPath $Clave); $i++) { Start-Sleep -Seconds 1 }
        }
        finally { & schtasks.exe /Delete /TN $tarea /F *> $null }
    }

    if (Test-Path -LiteralPath $Clave) {
        Write-Output "    $($Global:E.Aviso) No se pudo borrar la clave (probar tras reiniciar y repetir): $($nativa) $(if ($detalle) { '- ' + $detalle })"
        $script:Fallos++
    }
    else { $script:Eliminados++ }
}

# ---------------------------------------------------------------------
#  Detección
# ---------------------------------------------------------------------
function Get-ProductoOffice {
    [CmdletBinding()]
    param()

    $raices = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $incluir = '^(Microsoft Office|Microsoft 365|Office 365|Office \d\d|Microsoft Visio|Microsoft Project|Microsoft (Access|Outlook|Word|Excel|PowerPoint|Publisher|OneNote|InfoPath|SharePoint Designer)|Skype for Business|Microsoft Lync)'
    $excluir = 'Visual Studio|Teams|OneDrive|Update for|Security Update|Hotfix|KB\d{6,}'

    foreach ($raiz in $raices) {
        if (-not (Test-Path -LiteralPath $raiz)) { continue }
        foreach ($clave in Get-ChildItem -LiteralPath $raiz -ErrorAction SilentlyContinue) {
            $p = Get-ItemProperty -LiteralPath $clave.PSPath -ErrorAction SilentlyContinue
            $nombre = [string]$p.DisplayName
            if (-not $nombre) { continue }
            $porCodigo = $clave.PSChildName -match '0000000FF1CE\}$'   # todos los productos MSI de Office terminan así
            if (-not ($nombre -match $incluir -or $porCodigo)) { continue }
            if ($nombre -match $excluir) { continue }

            $desinstalar = [string]$p.UninstallString
            $tipo = 'Otro'
            if ($desinstalar -match 'OfficeClickToRun') { $tipo = 'ClickToRun' }
            elseif ($desinstalar -match 'Office Setup Controller.*setup\.exe') { $tipo = 'OSetup' }
            elseif ($desinstalar -match '\{[0-9A-Fa-f-]{36}\}') { $tipo = 'MSI' }
            $guid = [regex]::Match($desinstalar, '\{[0-9A-Fa-f-]{36}\}').Value
            if (-not $guid -and $clave.PSChildName -match '^\{') { $guid = $clave.PSChildName }

            [pscustomobject]@{
                Nombre  = $nombre
                Version = [string]$p.DisplayVersion
                Tipo    = $tipo
                Guid    = $guid
                Clave   = $clave.PSPath
                Cadena  = $desinstalar
            }
        }
    }
}

function Get-RutaOfficeSobrante {
    [CmdletBinding()]
    param()

    $pf = $env:ProgramFiles; $pf86 = ${env:ProgramFiles(x86)}
    $cpf = $env:CommonProgramFiles; $cpf86 = ${env:CommonProgramFiles(x86)}
    $pd = $env:ProgramData
    $rutas = New-Object System.Collections.Generic.List[string]

    foreach ($base in @($pf, $pf86)) {
        if ($base) { foreach ($d in Get-ChildItem -LiteralPath $base -Directory -Filter 'Microsoft Office*' -ErrorAction SilentlyContinue) { $rutas.Add($d.FullName) } }
    }
    foreach ($base in @($cpf, $cpf86)) {
        if (-not $base) { continue }
        $shared = Join-Path -Path $base -ChildPath 'Microsoft Shared'
        if (-not (Test-Path -LiteralPath $shared)) { continue }
        foreach ($patron in 'OFFICE1*', 'ClickToRun', 'Source Engine') {
            foreach ($d in Get-ChildItem -LiteralPath $shared -Directory -Filter $patron -ErrorAction SilentlyContinue) { $rutas.Add($d.FullName) }
        }
    }
    foreach ($r in @("$pd\Microsoft\ClickToRun", "$pd\Microsoft\Office", "$env:SystemDrive\MSOCache")) { if (Test-Path -LiteralPath $r) { $rutas.Add($r) } }
    $menu = "$pd\Microsoft\Windows\Start Menu\Programs"
    if (Test-Path -LiteralPath $menu) {
        foreach ($d in Get-ChildItem -LiteralPath $menu -Directory -Filter 'Microsoft Office*' -ErrorAction SilentlyContinue) { $rutas.Add($d.FullName) }
    }
    $rutas | Select-Object -Unique
}

function Get-ClaveRegistroOffice {
    [CmdletBinding()]
    param()

    $claves = New-Object System.Collections.Generic.List[string]
    foreach ($c in 'HKLM:\SOFTWARE\Microsoft\Office', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office', 'HKLM:\SOFTWARE\Microsoft\AppVISV') {
        if (Test-Path -LiteralPath $c) { $claves.Add($c) }
    }
    # Registros de instalador huérfanos de productos Office (los códigos MSI de Office acaban en 0000000FF1CE)
    foreach ($raiz in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall') {
        if (Test-Path -LiteralPath $raiz) {
            foreach ($k in Get-ChildItem -LiteralPath $raiz -ErrorAction SilentlyContinue) {
                if ($k.PSChildName -match '0000000FF1CE\}$|^Office1[0-9]\.|^(O365|ProPlus|Standard|HomeBusiness|HomeStudent|ProfessionalRetail|VisioPro|ProjectPro)\w* - ') { $claves.Add($k.PSPath) }
            }
        }
    }
    $productos = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products'
    if (Test-Path -LiteralPath $productos) {
        foreach ($k in Get-ChildItem -LiteralPath $productos -ErrorAction SilentlyContinue) { if ($k.PSChildName -match 'F01FEC$') { $claves.Add($k.PSPath) } }
    }
    $claves | Select-Object -Unique
}

# ---------------------------------------------------------------------
#  Ventana de opciones
# ---------------------------------------------------------------------
function Show-OpcionesDesinstalacion {
    [CmdletBinding()]
    param([string]$Resumen, [bool]$Simulacion, [bool]$DatosUsuario, [bool]$PuntoRestauracion)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'Desinstalar Office'; $f.StartPosition = 'CenterScreen'; $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false; $f.MinimizeBox = $false; $f.TopMost = $true; $f.ClientSize = New-Object System.Drawing.Size(560, 460)

    $l = New-Object System.Windows.Forms.Label
    $l.Text = 'Se va a desinstalar Office y limpiar el equipo. Esto es lo detectado:'
    $l.Location = New-Object System.Drawing.Point(12, 10); $l.Size = New-Object System.Drawing.Size(536, 20)
    $f.Controls.Add($l)

    $t = New-Object System.Windows.Forms.TextBox
    $t.Multiline = $true; $t.ReadOnly = $true; $t.ScrollBars = 'Vertical'; $t.Text = $Resumen
    $t.Location = New-Object System.Drawing.Point(12, 34); $t.Size = New-Object System.Drawing.Size(536, 190)
    $f.Controls.Add($t)

    $c1 = New-Object System.Windows.Forms.CheckBox
    $c1.Text = 'Limpiar también carpetas y registro del equipo (recomendado para reinstalar de cero)'
    $c1.Checked = $true; $c1.Location = New-Object System.Drawing.Point(12, 235); $c1.Size = New-Object System.Drawing.Size(536, 22)
    $f.Controls.Add($c1)

    $c2 = New-Object System.Windows.Forms.CheckBox
    $c2.Text = 'Borrar la configuración de usuario de Office (perfiles de Outlook, personalización). NO borra .pst/.ost'
    $c2.Checked = $DatosUsuario; $c2.Location = New-Object System.Drawing.Point(12, 262); $c2.Size = New-Object System.Drawing.Size(536, 36)
    $f.Controls.Add($c2)

    $c3 = New-Object System.Windows.Forms.CheckBox
    $c3.Text = 'SIMULAR: solo mostrar lo que se haría, sin cambiar nada'
    $c3.Checked = $Simulacion; $c3.Location = New-Object System.Drawing.Point(12, 302); $c3.Size = New-Object System.Drawing.Size(536, 22)
    $f.Controls.Add($c3)

    $c4 = New-Object System.Windows.Forms.CheckBox
    $c4.Text = 'Crear un punto de restauración antes (no disponible en todos los equipos)'
    $c4.Checked = $PuntoRestauracion; $c4.Location = New-Object System.Drawing.Point(12, 328); $c4.Size = New-Object System.Drawing.Size(536, 22)
    $f.Controls.Add($c4)

    $aviso = New-Object System.Windows.Forms.Label
    $aviso.Text = 'Cierra antes Word, Excel, Outlook, etc. Después hay que REINICIAR antes de reinstalar.'
    $aviso.ForeColor = [System.Drawing.Color]::DarkRed
    $aviso.Location = New-Object System.Drawing.Point(12, 362); $aviso.Size = New-Object System.Drawing.Size(536, 36)
    $f.Controls.Add($aviso)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Continuar'; $ok.Location = New-Object System.Drawing.Point(300, 415); $ok.Size = New-Object System.Drawing.Size(120, 30); $ok.DialogResult = 'OK'
    $no = New-Object System.Windows.Forms.Button
    $no.Text = 'Cancelar'; $no.Location = New-Object System.Drawing.Point(428, 415); $no.Size = New-Object System.Drawing.Size(120, 30); $no.DialogResult = 'Cancel'
    $f.Controls.AddRange(@($ok, $no)); $f.CancelButton = $no

    $r = $f.ShowDialog()
    $res = [pscustomobject]@{ Aceptado = ($r -eq 'OK'); LimpiarEquipo = $c1.Checked; DatosUsuario = $c2.Checked; Simular = $c3.Checked; PuntoRestauracion = $c4.Checked }
    $f.Dispose()
    $res
}

# ---------------------------------------------------------------------
#  Pasos
# ---------------------------------------------------------------------
function Stop-ProcesoServicioOffice {
    [CmdletBinding()]
    param()

    Write-Output "$($Global:E.Reloj) Cerrando procesos y servicios de Office..."
    $procesos = 'WINWORD', 'EXCEL', 'POWERPNT', 'OUTLOOK', 'MSACCESS', 'MSPUB', 'ONENOTE', 'ONENOTEM', 'VISIO', 'WINPROJ',
                'lync', 'UcMapi', 'OfficeClickToRun', 'OfficeC2RClient', 'AppVShNotify', 'MSOSYNC', 'OIS', 'GROOVE', 'INFOPATH', 'SDXHelper', 'msoia'
    foreach ($n in $procesos) {
        foreach ($p in Get-Process -Name $n -ErrorAction SilentlyContinue) {
            if ($script:Simulando) { Write-Output "    [simulación] cerraría el proceso $($p.ProcessName)"; continue }
            try { Stop-Process -Id $p.Id -Force -ErrorAction Stop; Write-Output "    $($Global:E.OK) Proceso cerrado: $($p.ProcessName)" }
            catch { Write-Output "    $($Global:E.Aviso) No se pudo cerrar $($p.ProcessName)" }
        }
    }
    foreach ($s in 'ClickToRunSvc', 'ose', 'ose64') {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if (-not $svc) { continue }
        if ($script:Simulando) { Write-Output "    [simulación] pararía y eliminaría el servicio $s"; continue }
        try { if ($svc.Status -ne 'Stopped') { Stop-Service -Name $s -Force -ErrorAction Stop } } catch { Write-Verbose "No se pudo parar $s" }
        & sc.exe delete $s *> $null
        Write-Output "    $($Global:E.OK) Servicio eliminado: $s"
    }
}

function Remove-ClaveProductoOffice {
    [CmdletBinding()]
    param()

    # Quita la clave instalada de Office 2010-2019 MSI para que no quede licencia asociada al reinstalar
    $scripts = New-Object System.Collections.Generic.List[string]
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $base) { continue }
        foreach ($d in Get-ChildItem -LiteralPath $base -Directory -Filter 'Microsoft Office*' -ErrorAction SilentlyContinue) {
            foreach ($o in Get-ChildItem -LiteralPath $d.FullName -Filter 'ospp.vbs' -File -Recurse -Depth 2 -ErrorAction SilentlyContinue) { $scripts.Add($o.FullName) }
        }
    }
    $yaQuitadas = New-Object System.Collections.Generic.HashSet[string]
    foreach ($vbs in ($scripts | Select-Object -Unique)) {
        try {
            $estado = & cscript.exe //nologo $vbs /dstatus 2>&1 | Out-String
            $claves = [regex]::Matches($estado, '(?im)^.*(?:characters|caracteres).*:\s*([A-Z0-9]{5})\s*$') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
            foreach ($c in $claves) {
                if (-not $yaQuitadas.Add($c)) { continue }
                if ($script:Simulando) { Write-Output "    [simulación] quitaría la clave que termina en $c"; continue }
                & cscript.exe //nologo $vbs "/unpkey:$c" *> $null
                Write-Output "    $($Global:E.OK) Clave de producto quitada (termina en $c)."
            }
        }
        catch { Write-Output "    $($Global:E.Aviso) No se pudo consultar la licencia con $vbs" }
    }
}

function Uninstall-ProductoOffice {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object[]]$Producto)

    foreach ($p in $Producto) {
        if ($script:Simulando -or $p.Tipo -ne 'MSI') { Write-Output "  $($Global:E.Refresh) $($p.Nombre) $($p.Version) [$($p.Tipo)]" }
        if ($script:Simulando) { Write-Output "    [simulación] se desinstalaría"; continue }
        try {
            if ($p.Tipo -eq 'MSI' -and $p.Guid) {
                $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList "/x $($p.Guid) /qn /norestart REBOOT=ReallySuppress" -Wait -PassThru -ErrorAction Stop
                if ($proc.ExitCode -in 1605, 1614) { $script:YaNoEstaba++ }
                else {
                    Write-Output "  $($Global:E.Refresh) $($p.Nombre) $($p.Version) [MSI]"
                    if ($proc.ExitCode -in 0, 3010, 1641) { Write-Output "    $($Global:E.OK) Desinstalado (código $($proc.ExitCode))."; $script:Eliminados++ }
                    else { Write-Output "    $($Global:E.Aviso) msiexec devolvió $($proc.ExitCode); se limpiará a mano después."; $script:Fallos++ }
                }
            }
            elseif ($p.Tipo -eq 'ClickToRun') {
                $c2r = Join-Path -Path $env:CommonProgramFiles -ChildPath 'Microsoft Shared\ClickToRun\OfficeClickToRun.exe'
                if (-not (Test-Path -LiteralPath $c2r)) { $c2r = ([regex]::Match($p.Cadena, '"?([^"]*OfficeClickToRun\.exe)"?')).Groups[1].Value }
                if (-not $c2r -or -not (Test-Path -LiteralPath $c2r)) { Write-Output "    $($Global:E.Aviso) No se encontró OfficeClickToRun.exe; se limpiará a mano después."; continue }
                $id = ([regex]::Match($p.Cadena, 'productstoremove=([^ ]+)')).Groups[1].Value
                if (-not $id) { $id = ([regex]::Match($p.Clave, '\\([A-Za-z0-9]+) - ')).Groups[1].Value }
                $argumentos = "scenario=install scenariosubtype=ARP sourcetype=None productstoremove=$id DisplayLevel=False forceappshutdown=True"
                $proc = Start-Process -FilePath $c2r -ArgumentList $argumentos -PassThru -ErrorAction Stop
                if (-not $proc.WaitForExit(1200000)) { try { $proc.Kill() } catch { Write-Verbose 'sin permiso para cerrar' }; Write-Output "    $($Global:E.Aviso) Tiempo agotado; se limpiará a mano después."; $script:Fallos++ }
                else {
                    # OfficeClickToRun.exe devuelve el control antes de acabar: se espera hasta 15 min a que desaparezca su entrada
                    $esperado = 0
                    while ((Test-Path -LiteralPath $p.Clave) -and $esperado -lt 900) { Start-Sleep -Seconds 10; $esperado += 10 }
                    if (Test-Path -LiteralPath $p.Clave) { Write-Output "    $($Global:E.Aviso) Click-to-Run no terminó de quitarlo (código $($proc.ExitCode)); se limpiará a mano después."; $script:Fallos++ }
                    else { Write-Output "    $($Global:E.OK) Desinstalado (código $($proc.ExitCode))."; $script:Eliminados++ }
                }
            }
            elseif ($p.Tipo -eq 'OSetup') {
                $exe  = ([regex]::Match($p.Cadena, '"([^"]+setup\.exe)"')).Groups[1].Value
                $prod = ([regex]::Match($p.Cadena, '/uninstall\s+(\S+)')).Groups[1].Value
                if (-not $exe -or -not $prod -or -not (Test-Path -LiteralPath $exe)) { Write-Output "    $($Global:E.Aviso) No se pudo leer su desinstalador; se limpiará a mano después."; continue }
                $cfg = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("office_un_" + [guid]::NewGuid().ToString('N') + ".xml")
                try {
                    Set-Content -LiteralPath $cfg -Value @("<Configuration Product=`"$prod`">", '  <Display Level="none" CompletionNotice="no" SuppressModal="yes" AcceptEULA="yes" />', '  <Setting Id="SETUP_REBOOT" Value="Never" />', '</Configuration>') -Encoding UTF8 -ErrorAction Stop
                    $proc = Start-Process -FilePath $exe -ArgumentList "/uninstall $prod /config `"$cfg`"" -PassThru -ErrorAction Stop
                    if (-not $proc.WaitForExit(1200000)) { try { $proc.Kill() } catch { Write-Verbose 'sin permiso para cerrar' }; Write-Output "    $($Global:E.Aviso) Tiempo agotado; se limpiará a mano después."; $script:Fallos++ }
                    elseif ($proc.ExitCode -in 0, 3010, 1641) { Write-Output "    $($Global:E.OK) Desinstalado (código $($proc.ExitCode))."; $script:Eliminados++ }
                    else { Write-Output "    $($Global:E.Aviso) Su desinstalador devolvió $($proc.ExitCode); se limpiará a mano después."; $script:Fallos++ }
                }
                finally { Remove-Item -LiteralPath $cfg -Force -ErrorAction SilentlyContinue }
            }
            else { Write-Output "    $($Global:E.Info) Sin desinstalador conocido; se limpiará a mano después." }        }
        catch { Write-Output "    $($Global:E.Error) Error: $($_.Exception.Message)"; $script:Fallos++ }
    }
}

function Clear-DatosUsuarioOffice {
    [CmdletBinding()]
    param()

    Write-Output "`n$($Global:E.Basura) Configuración de usuario de Office (no se tocan .pst ni .ost)..."
    Remove-ClaveOffice -Clave 'HKCU:\Software\Microsoft\Office'
    foreach ($perfil in Get-ChildItem -LiteralPath "$env:SystemDrive\Users" -Directory -ErrorAction SilentlyContinue) {
        foreach ($sub in 'AppData\Local\Microsoft\Office', 'AppData\Roaming\Microsoft\Office') {
            Remove-RutaOffice -Ruta (Join-Path -Path $perfil.FullName -ChildPath $sub)
        }
    }
}

# =====================================================================
#  PRINCIPAL
# =====================================================================
Write-Output ""
Write-Output "========================================================"
Write-Output "  $($Global:E.Basura) DESINSTALADOR COMPLETO DE OFFICE"
Write-Output "========================================================"

Assert-Admin 'desinstalar Office'
Confirm-EquipoListo 'desinstalar Office'

try {
    $productos = @(Get-ProductoOffice)
    $rutas     = @(Get-RutaOfficeSobrante)
    $claves    = @(Get-ClaveRegistroOffice)

    if ($productos.Count -eq 0 -and $rutas.Count -eq 0 -and $claves.Count -eq 0) {
        Write-Output "$($Global:E.OK) No hay rastro de Office en este equipo: ya está limpio."
        return
    }

    $resumen = "PRODUCTOS INSTALADOS ($($productos.Count)):`r`n"
    foreach ($p in $productos) { $resumen += "  - $($p.Nombre) $($p.Version) [$($p.Tipo)]`r`n" }
    $resumen += "`r`nCARPETAS SOBRANTES: $($rutas.Count)`r`n"
    foreach ($r in $rutas) { $resumen += "  - $r`r`n" }
    $resumen += "`r`nCLAVES DE REGISTRO SOBRANTES: $($claves.Count)"

    $limpiarEquipo = $true; $datosUsuario = [bool]$IncluirDatosUsuario; $crearPunto = [bool]$PuntoRestauracion
    if ($SinMenu) {
        Write-Output $resumen
        # Sin ventana de opciones tampoco había confirmación: -SinMenu desinstalaba Office y borraba carpetas y claves directamente. Solo se salta si es una simulación.
        if (-not $Simular -and -not (Confirm-Accion "Se va a DESINSTALAR Microsoft Office y limpiar sus restos (carpetas y claves de registro).`n`n¿Continuar?" 'Nitrit0 Kit - Desinstalar Office' -Siempre)) { Exit-Kit 'Cancelado' 'Cancelado: no se ha cambiado nada.' }
    }
    else {
        $op = Show-OpcionesDesinstalacion -Resumen $resumen -Simulacion ([bool]$Simular) -DatosUsuario ([bool]$IncluirDatosUsuario) -PuntoRestauracion $true
        if (-not $op.Aceptado) { Exit-Kit 'Cancelado' 'Cancelado: no se ha cambiado nada.' }
        $limpiarEquipo = $op.LimpiarEquipo; $datosUsuario = $op.DatosUsuario; $script:Simulando = $op.Simular; $crearPunto = $op.PuntoRestauracion
    }

    if ($script:Simulando) { Write-Output "`n$($Global:E.Info) MODO SIMULACIÓN: no se cambia nada." }
    elseif ($crearPunto) {
        [void](New-PuntoRestauracionSeguro 'Antes de desinstalar Office')   # con tiempo máximo (3 min) y avisos propios; Checkpoint-Computer a secas se cuelga si VSS está atascado
    }
    else { Write-Output "$($Global:E.Info) Sin punto de restauración (desmarcado)." }
    if (-not $script:Simulando) {
        [void](Start-OperacionSegura 'Desinstalar Office' -SinPuntoRestauracion)
        Save-Informativo 'Office desinstalado, con sus carpetas y claves de registro' 'No se deshace solo: reinstala Office con su instalador y la licencia del cliente; si se creó el punto «Antes de desinstalar Office», puede usarse.'
    }

    Write-Output "`n$($Global:E.Lupa) 1/4 Procesos y licencias"
    Stop-ProcesoServicioOffice
    Remove-ClaveProductoOffice

    Write-Output "`n$($Global:E.Lupa) 2/4 Desinstalando productos"
    if ($productos.Count -gt 0) {
        # Primero las suites (más grandes), luego componentes sueltos
        Uninstall-ProductoOffice -Producto ($productos | Sort-Object { $_.Nombre -match 'Professional|Profesional|Standard|Estándar|365|Home|Hogar|Visio|Project' } -Descending)
        if ($script:YaNoEstaba -gt 0) { Write-Output "  $($Global:E.Info) $($script:YaNoEstaba) componente(s) ya se habían quitado junto al producto principal." }
    } else { Write-Output "  $($Global:E.Info) No hay productos registrados." }

    if ($limpiarEquipo) {
        Write-Output "`n$($Global:E.Lupa) 3/4 Limpiando carpetas, tareas y registro"
        Stop-ProcesoServicioOffice
        if (-not $script:Simulando) {
            foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -like '\Microsoft\Office\*' })) {
                try { Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false -ErrorAction Stop; Write-Output "    $($Global:E.OK) Tarea programada eliminada: $($t.TaskName)" } catch { Write-Verbose "No se pudo quitar la tarea" }
            }
        }
        foreach ($r in @(Get-RutaOfficeSobrante)) { Remove-RutaOffice -Ruta $r }
        $clavesRegistro = @(Get-ClaveRegistroOffice)
        foreach ($k in $clavesRegistro) { Remove-ClaveOffice -Clave $k }
        if ($script:Simulando) { Write-Output "    [simulación] borraría $($clavesRegistro.Count) claves de registro de Office" }
        elseif ($clavesRegistro.Count -gt 0) {
            $quedan = @($clavesRegistro | Where-Object { Test-Path -LiteralPath $_ }).Count
            Write-Output "    $($Global:E.Info) Claves de registro: $($clavesRegistro.Count - $quedan) borradas, $quedan pendientes."
        }
    }
    else { Write-Output "`n$($Global:E.Info) 3/4 Limpieza de carpetas y registro omitida por elección." }

    Write-Output "`n$($Global:E.Lupa) 4/4 Datos de usuario"
    if ($datosUsuario) { Clear-DatosUsuarioOffice } else { Write-Output "  $($Global:E.Info) Se conservan los datos de usuario." }

    Write-Output ""
    Write-Output "========================================================"
    if ($script:Simulando) { Write-Output "  $($Global:E.Info) SIMULACIÓN TERMINADA. No se ha cambiado nada." }
    else {
        $restos = @(Get-ProductoOffice).Count
        Write-Output "  $($Global:E.OK) Elementos eliminados: $($script:Eliminados)   |   Avisos: $($script:Fallos)"
        if ($restos -gt 0) { Write-Output "  $($Global:E.Aviso) Aún figuran $restos producto(s) en el registro: reinicia y vuelve a ejecutar este script." }
        else { Write-Output "  $($Global:E.OK) Office ya no figura instalado." }
        Write-Output "  $($Global:E.Aviso) REINICIA el equipo antes de reinstalar Office."
    }
    Write-Output "========================================================"
}
catch {
    Exit-Kit 'Error' "Error inesperado: $($_.Exception.Message)"
}
