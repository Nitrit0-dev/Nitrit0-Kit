using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;
[assembly: AssemblyTitle("Lanzador Nitrit0")]
[assembly: AssemblyProduct("Nitrit0 Kit")]
[assembly: AssemblyVersion("3.0.0.0")]
static class Lanzador {
    [STAThread]
    static int Main(string[] args) {
        // Todo se calcula desde la carpeta del exe: funciona desde cualquier ruta o unidad.
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(dir, "Scripts", "Lanzador.ps1");
        if (!File.Exists(script)) {
            MessageBox.Show("No se encuentra Scripts\\Lanzador.ps1 junto al lanzador:\n" + dir + "\n\nComprueba que no has movido el exe fuera de la carpeta del kit.", "Lanzador Nitrit0", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 2;
        }
        string extra = args.Length > 0 ? " " + string.Join(" ", args) : "";
        ProcessStartInfo si = new ProcessStartInfo("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"" + script + "\"" + extra);
        si.UseShellExecute = false; si.CreateNoWindow = true;
        si.WorkingDirectory = Environment.GetEnvironmentVariable("TEMP");   // no bloquear la unidad (se puede expulsar)
        try {
            Process p = Process.Start(si);
            if (p.WaitForExit(5000) && p.ExitCode != 0)
                MessageBox.Show("El lanzador se cerró al arrancar (código " + p.ExitCode + ").\nRevisa Datos\\Error_Lanzador.log y Datos\\Logs.", "Lanzador Nitrit0", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        } catch (Exception e) {
            MessageBox.Show("No se pudo abrir PowerShell:\n" + e.Message, "Lanzador Nitrit0", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        return 0;
    }
}
