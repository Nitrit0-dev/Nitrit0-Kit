// Lanzador de una herramienta suelta del kit (Clonar disco, Desinstalar a fondo). Lo compila Crear_Utilidades_Sueltas.ps1
// sustituyendo @SCRIPT@ y @TITULO@. Pide administrador (manifiesto), comprueba la huella del script con Test-ScriptAutorizado
// y lo ejecuta en esta misma consola. Todo se calcula desde la carpeta del exe: funciona desde cualquier ruta o unidad.
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
[assembly: AssemblyTitle("@TITULO@")]
[assembly: AssemblyProduct("Nitrit0 Kit")]
[assembly: AssemblyVersion("1.0.0.0")]
static class Suelta {
    static string Q(string x) { return "'" + x.Replace("'", "''") + "'"; }
    static int Main() {
        string dir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
        string comun = Path.Combine(dir, "Scripts\\Comun.ps1"), script = Path.Combine(dir, "Scripts\\Mantenimiento\\@SCRIPT@");
        Console.Title = "@TITULO@ - Nitrit0";
        if (!File.Exists(comun) || !File.Exists(script)) { Console.WriteLine("Faltan archivos junto al programa (carpeta Scripts). Vuelve a copiar la carpeta completa."); Console.ReadKey(true); return 1; }
        // La orden va en el propio -Command: no se escribe ningun .ps1 temporal que otro proceso pueda cambiar antes de que corra como administrador
        string orden = "try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) } catch { }; $env:NIT_EJEC='1'; . " + Q(comun) + "; Initialize-Kit " + Q(dir)
            + "; $m = Test-ScriptAutorizado " + Q(script) + "; if ($m) { Write-Host ('No se ejecuta: ' + $m); exit 1 }; $global:LASTEXITCODE = 0; & " + Q(script) + "; exit $LASTEXITCODE";
        string ps = Path.Combine(Environment.SystemDirectory, "WindowsPowerShell\\v1.0\\powershell.exe");
        ProcessStartInfo si = new ProcessStartInfo(ps, "-NoProfile -ExecutionPolicy Bypass -STA -Command \"" + orden.Replace("\"", "\\\"") + "\"");
        si.UseShellExecute = false; si.WorkingDirectory = dir;
        Process p = Process.Start(si); p.WaitForExit();
        Console.WriteLine(); Console.Write("Terminado (codigo " + p.ExitCode + "). Pulsa una tecla para cerrar...");
        Console.ReadKey(true);
        return p.ExitCode;
    }
}
