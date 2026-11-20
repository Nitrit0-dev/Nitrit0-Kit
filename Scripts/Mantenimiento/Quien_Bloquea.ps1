# =====================================================================
#  Quien_Bloquea.ps1 - Qué programa tiene abierto un archivo, una carpeta o una unidad (Nitrit0)
#  Para «no puedo borrar esto», «el archivo está en uso» o «no puedo expulsar el disco». Usa el Administrador de reinicio de Windows
#  (el mismo que usan los instaladores) para saber qué programas tienen archivos abiertos; en una unidad o carpeta mira además qué
#  programas se están ejecutando desde ella.
#  Solo mira. Al final, si lo confirmas, puede cerrar los programas de la lista (nunca los de Windows ni el Explorador).
#  Parámetros: -Ruta "archivo, carpeta o unidad"   -SoloMirar (no ofrece cerrar nada)
# =====================================================================
[CmdletBinding()]
param([string]$Ruta = '', [Alias('SoloMirar')][switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
Add-Type -AssemblyName System.Windows.Forms
if (-not ('Nit.Rm' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace Nit {
  public static class Rm {
    [StructLayout(LayoutKind.Sequential)] public struct FILETIME { public uint dwLowDateTime; public uint dwHighDateTime; }
    [StructLayout(LayoutKind.Sequential)] public struct RM_UNIQUE_PROCESS { public int dwProcessId; public FILETIME ProcessStartTime; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct RM_PROCESS_INFO {
      public RM_UNIQUE_PROCESS Process;
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string strAppName;
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string strServiceShortName;
      public int ApplicationType; public uint AppStatus; public uint TSSessionId;
      [MarshalAs(UnmanagedType.Bool)] public bool bRestartable; }
    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)] static extern int RmStartSession(out uint h, int f, string key);
    [DllImport("rstrtmgr.dll")] static extern int RmEndSession(uint h);
    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)] static extern int RmRegisterResources(uint h, uint nFiles, string[] files, uint nApps, RM_UNIQUE_PROCESS[] apps, uint nSvc, string[] svcs);
    [DllImport("rstrtmgr.dll")] static extern int RmGetList(uint h, out uint needed, ref uint count, [In, Out] RM_PROCESS_INFO[] info, out uint reason);
    public static List<KeyValuePair<int, string>> Quien(string[] files) {
      var res = new List<KeyValuePair<int, string>>(); uint h;
      if (RmStartSession(out h, 0, Guid.NewGuid().ToString()) != 0) return res;
      try {
        if (RmRegisterResources(h, (uint)files.Length, files, 0, null, 0, null) != 0) return res;
        uint need = 0, cnt = 0, reason;
        int r = RmGetList(h, out need, ref cnt, null, out reason);
        if (r == 234 && need > 0) {
          var info = new RM_PROCESS_INFO[need]; cnt = need;
          r = RmGetList(h, out need, ref cnt, info, out reason);
          if (r == 0) for (int i = 0; i < cnt; i++) res.Add(new KeyValuePair<int, string>(info[i].Process.dwProcessId, info[i].strAppName));
        }
      } finally { RmEndSession(h); }
      return res;
    }
  }
}
'@
}

# ---------------------------------------------------------------- Qué mirar
if (-not $Ruta) {
    $t = [Windows.Forms.MessageBox]::Show("¿Quieres mirar un ARCHIVO (Sí) o una CARPETA o UNIDAD (No)?", 'Quién bloquea', 'YesNoCancel', 'Question')
    if ($t -eq 'Cancel') { Exit-Kit 'Cancelado' 'Cancelado.' }
    if ($t -eq 'Yes') { $d = New-Object Windows.Forms.OpenFileDialog; $d.Title = 'Elige el archivo bloqueado'; if ($d.ShowDialog() -ne 'OK') { Exit-Kit 'Cancelado' 'Cancelado.' }; $Ruta = $d.FileName }
    else { $d = New-Object Windows.Forms.FolderBrowserDialog; $d.Description = 'Elige la carpeta o la unidad (por ejemplo, la del disco que no se deja expulsar)'; if ($d.ShowDialog() -ne 'OK') { Exit-Kit 'Cancelado' 'Cancelado.' }; $Ruta = $d.SelectedPath }
}
if (-not (Test-Path -LiteralPath $Ruta)) { Write-Output "$($E.Error) No encuentro «$Ruta»."; Exit-Kit 'Error' }
$item = Get-Item -LiteralPath $Ruta -Force
Write-Output "  $($E.Lupa) Mirando: $($item.FullName)"

# ---------------------------------------------------------------- 1) Archivos abiertos (Administrador de reinicio)
$archivos = @()
if ($item.PSIsContainer) { $archivos = @(Get-ChildItem -LiteralPath $item.FullName -File -Recurse -Force -ErrorAction SilentlyContinue | Select-Object -First 3000 -ExpandProperty FullName) } else { $archivos = @($item.FullName) }
$hallados = @{}
if ($archivos.Count) { foreach ($x in [Nit.Rm]::Quien([string[]]$archivos)) { $hallados[[int]$x.Key] = [pscustomobject]@{ Pid = [int]$x.Key; Programa = [string]$x.Value; Motivo = 'tiene archivos abiertos aquí' } } }
# ---------------------------------------------------------------- 2) Programas que se ejecutan desde ahí
$base = $item.FullName.TrimEnd('\') + $(if ($item.PSIsContainer) { '\' } else { '' })
foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
    $ruta = $null; try { $ruta = $p.Path } catch { }
    if ($ruta -and ($ruta -like "$base*" -or $ruta -ieq $item.FullName)) { $hallados[[int]$p.Id] = [pscustomobject]@{ Pid = [int]$p.Id; Programa = $p.ProcessName; Motivo = "se ejecuta desde $ruta" } }
}
$lista = @($hallados.Values | Sort-Object Programa)
if ($item.PSIsContainer -and $archivos.Count -ge 3000) { Write-Output "  $($E.Aviso) La carpeta es muy grande: se revisaron los primeros 3000 archivos." }
if (-not $lista.Count) {
    Write-Output "  $($E.OK) Ningún programa tiene abierto nada de esto ahora mismo."
    Write-Output "  $($E.Info) Si Windows sigue diciendo que está en uso, puede ser el propio Windows (indexador, antivirus, vista previa del Explorador) o un servicio: prueba a cerrar las ventanas del Explorador que lo muestren, o reinicia."
    Write-Log "Quien_Bloquea: nada abierto en $($item.FullName)"; Exit-Kit 'Ok'
}
Write-Output "  $($E.Aviso) Esto es lo que lo tiene en uso:"
foreach ($x in $lista) { Write-Output ("    · {0} (PID {1}) · {2}" -f $x.Programa, $x.Pid, $x.Motivo) }
Write-Log "Quien_Bloquea: $($lista.Count) programas en $($item.FullName): $(($lista | ForEach-Object { $_.Programa }) -join ', ')"
if ($SoloAnalizar) { Exit-Kit 'Ok' }

# ---------------------------------------------------------------- 3) Cerrar (con confirmación)
$protegidos = 'explorer', 'System', 'Idle', 'csrss', 'wininit', 'winlogon', 'services', 'lsass', 'svchost', 'dwm', 'smss', 'MsMpEng', 'fontdrvhost', 'Nitrit0', 'Nitrit0 Kit', 'powershell', 'conhost'
$cerrables = @($lista | Where-Object { $_.Programa -notin $protegidos -and $_.Pid -ne $PID -and $_.Pid -gt 4 })
$aparte = @($lista | Where-Object { $_.Programa -in $protegidos })
if ($aparte.Count) { Write-Output "  $($E.Info) De la lista, $(($aparte | ForEach-Object { $_.Programa }) -join ', ') son de Windows o de esta herramienta y no se cierran desde aquí (el Explorador: cierra sus ventanas)." }
if (-not $cerrables.Count) { Exit-Kit 'Ok' }
if (Confirm-Accion ("Programas que tienen esto en uso:`n`n" + (($cerrables | ForEach-Object { "  · $($_.Programa)" }) -join "`n") + "`n`n¿Los cierro? Si tienen algo sin guardar, se perderá.") 'Nitrit0 Kit' -Siempre) {
    foreach ($x in $cerrables) { try { Stop-Process -Id $x.Pid -Force -ErrorAction Stop; Write-Output "  $($E.OK) Cerrado: $($x.Programa)"; Write-Log "Quien_Bloquea: cerrado $($x.Programa) ($($x.Pid))" } catch { Write-Output "  $($E.Aviso) No se pudo cerrar $($x.Programa): $($_.Exception.Message)" } }
    Write-Output "  $($E.Info) Ya puedes borrar o expulsar. Si sigue en uso, ejecuta esta herramienta otra vez."
} else { Write-Output "  $($E.Info) No se ha cerrado nada." }
