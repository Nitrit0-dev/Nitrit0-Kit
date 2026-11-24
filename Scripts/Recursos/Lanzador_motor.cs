// Lanzador fino de una app Electron ya descomprimida (carpeta junto al .exe). Lo compila Crear_Lanzador.ps1 sustituyendo @DESTINO@ (ruta relativa
// al programa real) y @TITULO@. El .exe único «portable» de electron-builder descomprime ~360 MB en %TEMP% en cada arranque (minutos en un equipo lento
// o con antivirus); este lanzador arranca el programa de verdad al instante, con los mismos argumentos (--bandeja), y se cierra. Si se compila con
// manifiesto de administrador, el programa lanzado hereda esos permisos sin pedirlos otra vez.
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows.Forms;
[assembly: AssemblyTitle("@TITULO@")]
[assembly: AssemblyProduct("Nitrit0 Kit")]
[assembly: AssemblyVersion("1.0.0.0")]
static class Lanzador {
    static string Q(string a) {
        if (a.Length > 0 && a.IndexOfAny(new char[] { ' ', '\t', '"' }) < 0) return a;
        // Convención de CommandLineToArgvW: las barras invertidas que preceden a una comilla (o al cierre) se duplican; si no, «C:\Temp\» se comería la comilla final
        StringBuilder b = new StringBuilder("\"");
        int barras = 0;
        foreach (char ch in a) {
            if (ch == '\\') { barras++; }
            else if (ch == '"') { b.Append('\\', barras * 2 + 1); b.Append('"'); barras = 0; }
            else { b.Append('\\', barras); b.Append(ch); barras = 0; }
        }
        b.Append('\\', barras * 2); b.Append('"');
        return b.ToString();
    }
    [STAThread]
    static int Main(string[] args) {
        // Sin TrimEnd: en la raíz de una unidad («E:\») quedaría «E:» y Path.Combine daría «E:App\...», una ruta relativa a la carpeta actual de esa unidad
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string exe = Path.Combine(dir, "@DESTINO@");
        if (!File.Exists(exe)) {
            MessageBox.Show("Falta el programa en:\n" + exe + "\n\nVuelve a copiar la carpeta completa del kit.", "@TITULO@", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        StringBuilder sb = new StringBuilder("@ARGS@");   // argumentos fijos de este acceso (p. ej. --clonar); vacío en los demás
        foreach (string a in args) { if (sb.Length > 0) sb.Append(' '); sb.Append(Q(a)); }
        ProcessStartInfo si = new ProcessStartInfo(exe, sb.ToString());
        si.UseShellExecute = false;
        si.WorkingDirectory = Path.GetDirectoryName(exe);
        try { Process.Start(si); }
        catch (Exception e) {
            MessageBox.Show("No se pudo abrir el programa:\n" + e.Message, "@TITULO@", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        return 0;
    }
}
