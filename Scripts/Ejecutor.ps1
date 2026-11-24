# =====================================================================
#  Ejecutor.ps1 - Ejecuta los scripts de Mantenimiento en un proceso aparte, sin bloquear la ventana.
#  - Salida en vivo, botón Cancelar, tiempo máximo y registro en Datos\Logs\Ejecuciones.
#  - Vigila la unidad del kit: avisa si se desconecta y registra cuánto tardó en volver.
#  Se carga desde Lanzador.ps1 (usa Get-Tc, $form y $script:K del lanzador) y Comun.ps1.
# =====================================================================

# Primero la DLL precompilada (Compilar_Recursos.ps1): cargarla es instantáneo. Compilar el C# con csc.exe en cada arranque tardaba minutos en un equipo recién instalado.
# La DLL solo se carga si figura en Integridad.json con su huella; si falta o no es de confianza, se compila como antes.
if (-not ('Nit.Ventanas' -as [type])) {
    $dllNit = Join-Path $PSScriptRoot 'Recursos\Nit.Ejecutor.dll'
    if ((Test-Path -LiteralPath $dllNit) -and -not (Test-ScriptAutorizado $dllNit)) { try { Add-Type -LiteralPath $dllNit -ErrorAction Stop } catch { } }
}
if (-not ('Nit.Ventanas' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace Nit {
    public static class Ventanas {
        delegate bool EnumCb(IntPtr h, IntPtr l);
        [DllImport("user32.dll")] static extern bool EnumWindows(EnumCb cb, IntPtr l);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
        [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
        [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int n);
        [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
        [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
        [DllImport("user32.dll")] static extern int GetWindowTextLength(IntPtr h);
        [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
        [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int i);
        [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out Rc r);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
        [StructLayout(LayoutKind.Sequential)] struct Rc { public int L, T, R, B; }
        // La app lanza PowerShell con windowsHide (Node): Windows esconde la primera ventana que abre el script (casillas, avisos) y el usuario no la ve.
        // Una ventana de verdad (título, borde y tamaño, de WinForms o un MessageBox) que siga oculta se muestra a la fuerza.
        static bool EsVentanaDeUsuario(IntPtr h) {
            if (GetWindowTextLength(h) == 0) return false;
            if ((((uint)GetWindowLong(h, -16)) & 0xC00000u) != 0xC00000u) return false;
            Rc r; if (!GetWindowRect(h, out r) || r.R - r.L < 100 || r.B - r.T < 50) return false;
            StringBuilder s = new StringBuilder(64); GetClassName(h, s, 64); string c = s.ToString();
            return c.StartsWith("WindowsForms10.Window") || c == "#32770";
        }
        // Trae al frente las ventanas visibles nuevas de los procesos indicados (los scripts que piden marcar opciones)
        public static int TraerAlFrente(int[] pids, HashSet<long> vistas) {
            HashSet<uint> ps = new HashSet<uint>(); foreach (int p in pids) ps.Add((uint)p);
            List<IntPtr> nuevas = new List<IntPtr>();
            EnumWindows(delegate(IntPtr h, IntPtr l) {
                uint pid; GetWindowThreadProcessId(h, out pid);
                if (ps.Contains(pid) && !IsWindowVisible(h) && EsVentanaDeUsuario(h)) ShowWindow(h, 5);
                if (ps.Contains(pid) && IsWindowVisible(h) && GetWindowTextLength(h) > 0 && !vistas.Contains(h.ToInt64())) { vistas.Add(h.ToInt64()); nuevas.Add(h); }
                return true;
            }, IntPtr.Zero);
            foreach (IntPtr h in nuevas) Frente(h);
            return nuevas.Count;
        }
        public static void Frente(IntPtr h) {
            if (IsIconic(h)) ShowWindow(h, 9);
            keybd_event(0x12, 0, 0, UIntPtr.Zero); keybd_event(0x12, 0, 2, UIntPtr.Zero);
            SetWindowPos(h, new IntPtr(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0040);
            SetWindowPos(h, new IntPtr(-2), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0040);
            SetForegroundWindow(h);
        }
    }
    public class Lanzado {
        public Process P;
        public ConcurrentQueue<string> Cola = new ConcurrentQueue<string>();
        public static Lanzado Iniciar(string exe, string args, string cwd, string raiz) {
            ProcessStartInfo si = new ProcessStartInfo(exe, args);
            si.UseShellExecute = false; si.CreateNoWindow = true; si.WorkingDirectory = cwd;
            si.RedirectStandardOutput = true; si.RedirectStandardError = true; si.RedirectStandardInput = true;
            si.StandardOutputEncoding = new UTF8Encoding(false); si.StandardErrorEncoding = new UTF8Encoding(false);
            si.EnvironmentVariables["NIT_RAIZ"] = raiz;
            si.EnvironmentVariables.Remove("NIT_AUTO"); si.EnvironmentVariables.Remove("NIT_SIN_PREGUNTAS");   // solo la revisión automática salta las confirmaciones
            Lanzado l = new Lanzado(); l.P = new Process(); l.P.StartInfo = si;
            l.P.OutputDataReceived += delegate(object s, DataReceivedEventArgs e) { if (e.Data != null) l.Cola.Enqueue(e.Data); };
            l.P.ErrorDataReceived += delegate(object s, DataReceivedEventArgs e) { if (e.Data != null) l.Cola.Enqueue(e.Data); };
            l.P.Start(); l.P.StandardInput.Close(); l.P.BeginOutputReadLine(); l.P.BeginErrorReadLine();
            return l;
        }
        public void Matar() { try { string tk = System.IO.Path.Combine(Environment.SystemDirectory, "taskkill.exe"); Process k = Process.Start(new ProcessStartInfo(tk, "/PID " + P.Id + " /T /F") { CreateNoWindow = true, UseShellExecute = false }); k.WaitForExit(5000); } catch { } }   // ruta completa: con «taskkill.exe» a secas, un ejecutable de ese nombre en la carpeta de trabajo (%TEMP%) correría como administrador
    }
}
'@
}

# PIDs del proceso lanzado y de todos sus descendientes (los scripts abren ventanas desde procesos hijos)
function Get-PidsArbol([int]$raiz) {
    $set = @{ $raiz = 1 }
    try {
        $todos = @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId -ErrorAction Stop); $cambio = $true
        while ($cambio) { $cambio = $false; foreach ($p in $todos) { if (-not $set.ContainsKey([int]$p.ProcessId) -and $set.ContainsKey([int]$p.ParentProcessId)) { $set[[int]$p.ProcessId] = 1; $cambio = $true } } }
    } catch { }
    [int[]]@($set.Keys)
}

function New-OrdenScript([string]$rutaScript) {
    $comun = Join-Path $dirScripts 'Comun.ps1'
    $q = { param($s) "'" + ($s -replace "'", "''") + "'" }
    $cmd = "`$ErrorActionPreference='Continue'; `$ProgressPreference='SilentlyContinue'; try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding(`$false) } catch { }; `$env:NIT_EJEC='1'; " +
           ". $(& $q $comun); Initialize-Kit `$env:NIT_RAIZ; `$global:LASTEXITCODE = 0; " +
           # Si el script revienta con un error no controlado, se muestra, se anota y la ventana dice «Terminó con código 1» (antes salía como correcto)
           "try { & $(& $q $rutaScript) } catch { Write-Host (`"`$(`$Global:E.Error) Error no controlado: `" + `$_.Exception.Message + `"  (`" + `$_.InvocationInfo.ScriptName + `":`" + `$_.InvocationInfo.ScriptLineNumber + `")`"); try { Write-Log (`"Error no controlado en $([IO.Path]::GetFileName($rutaScript)): `" + `$_.Exception.Message) 'ERROR' } catch { }; exit 1 }; `$c = `$LASTEXITCODE; if (`$c -eq 0 -and (Test-ReinicioPendiente)) { Write-Host (`$Global:E.Aviso + ' Windows tiene un reinicio pendiente: reinicia el equipo para completar los cambios.') }; exit `$c"
    # La orden va en el propio -Command: no se escribe ningún .ps1 en %TEMP% que otro proceso pudiera cambiar antes de que corra elevado (TOCTOU)
    '-NoProfile -ExecutionPolicy Bypass -STA -Command "' + ($cmd -replace '"', '\"') + '"'
}

function Show-Ejecucion($h, $propietario) {
    $K = $script:K; $cF = Get-Tc 'Fondo'; $cCab = Get-Tc 'Cab'; $cT = Get-Tc 'Texto'; $cS = Get-Tc 'TextoSuave'; $cA = Get-Tc 'Acento'
    $ruta = Join-Path $dirScripts $h.Script
    if (-not (Test-Path -LiteralPath $ruta)) { [void][Windows.Forms.MessageBox]::Show("No se encuentra el script:`n$ruta", 'Ejecutor', 0, 16); return }
    $motivo = Test-ScriptAutorizado $ruta
    if ($motivo) { Write-Log "Ejecución bloqueada de $($h.Script): $motivo" 'ERROR'; [void][Windows.Forms.MessageBox]::Show("No se ejecuta $($h.Script): $motivo.`n`nSi lo has actualizado tú, ejecuta Regenerar_Integridad.ps1. Si no, no lo ejecutes: alguien ha cambiado el kit.", 'Ejecutor: bloqueado', 0, 16); return }
    $limite = if ($h.Timeout) { [int]$h.Timeout } else { 1800 }
    $nombreLog = ("{0}_{1}" -f (Get-Date -Format 'yyyyMMdd_HHmmss'), ([IO.Path]::GetFileNameWithoutExtension($h.Script) -replace '[^\w\-]', '_'))
    $dirEj = Join-Path (Get-BaseTrabajo) 'Logs\Ejecuciones'   # pack público: %TEMP%, no el pendrive
    $logLocal = Join-Path $env:TEMP "Nitrit0_Cache\Logs\$nombreLog.log"; New-Item -ItemType Directory -Force (Split-Path $logLocal) | Out-Null

    $dlg = New-Object Windows.Forms.Form; $dlg.Text = $h.N; $dlg.Size = New-Object Drawing.Size([int](900 * $K), [int](640 * $K)); $dlg.MinimumSize = New-Object Drawing.Size(640, 420)
    $dlg.StartPosition = 'CenterParent'; $dlg.BackColor = $cF; $dlg.Font = New-Object Drawing.Font($script:Fuentes.UI, 9.5); if ($form.Icon) { $dlg.Icon = $form.Icon }
    $cab = New-Object Windows.Forms.Panel; $cab.Dock = 'Top'; $cab.Height = [int](70 * $K); $cab.BackColor = $cCab
    $tit = New-Object Windows.Forms.Label; $tit.Text = $h.N; $tit.ForeColor = $cT; $tit.Font = New-Object Drawing.Font($script:Fuentes.Display, 14); $tit.AutoSize = $true; $tit.Location = New-Object Drawing.Point([int](20 * $K), [int](8 * $K))
    $est = New-Object Windows.Forms.Label; $est.ForeColor = $cS; $est.AutoSize = $false; $est.Size = New-Object Drawing.Size([int](840 * $K), [int](24 * $K)); $est.Location = New-Object Drawing.Point([int](22 * $K), [int](38 * $K)); $est.Anchor = 'Top,Left,Right'
    $cab.Controls.AddRange(@($tit, $est))
    $barra = New-Object Windows.Forms.ProgressBar; $barra.Dock = 'Top'; $barra.Style = 'Marquee'; $barra.MarqueeAnimationSpeed = 30; $barra.Height = 4
    $pie = New-Object Windows.Forms.Panel; $pie.Dock = 'Bottom'; $pie.Height = [int](56 * $K); $pie.BackColor = $cCab
    $btnCancel = New-Object Windows.Forms.Button; $btnCancel.Text = 'Cancelar ejecución'; $btnCancel.Size = New-Object Drawing.Size([int](170 * $K), [int](34 * $K)); $btnCancel.FlatStyle = 'Flat'; $btnCancel.BackColor = Get-Tc 'Boton'; $btnCancel.ForeColor = $cT; $btnCancel.FlatAppearance.BorderColor = Get-Tc 'Borde'; $btnCancel.Anchor = 'Top,Right'; $btnCancel.Cursor = 'Hand'
    $btnCerrar = New-Object Windows.Forms.Button; $btnCerrar.Text = 'Cerrar'; $btnCerrar.Size = New-Object Drawing.Size([int](110 * $K), [int](34 * $K)); $btnCerrar.FlatStyle = 'Flat'; $btnCerrar.BackColor = $cA; $btnCerrar.ForeColor = Get-Tc 'TextoAcento'; $btnCerrar.FlatAppearance.BorderColor = Get-Tc 'Borde'; $btnCerrar.Anchor = 'Top,Right'; $btnCerrar.Enabled = $false; $btnCerrar.Cursor = 'Hand'
    $btnLog = New-Object Windows.Forms.Button; $btnLog.Text = 'Abrir registro'; $btnLog.Size = New-Object Drawing.Size([int](130 * $K), [int](34 * $K)); $btnLog.FlatStyle = 'Flat'; $btnLog.BackColor = Get-Tc 'Boton'; $btnLog.ForeColor = $cT; $btnLog.FlatAppearance.BorderColor = Get-Tc 'Borde'; $btnLog.Anchor = 'Top,Right'; $btnLog.Cursor = 'Hand'
    $pie.Controls.AddRange(@($btnLog, $btnCancel, $btnCerrar))
    $posPie = { $y = [int](11 * $K); $btnCerrar.Location = New-Object Drawing.Point(($pie.ClientSize.Width - $btnCerrar.Width - 20), $y); $btnCancel.Location = New-Object Drawing.Point(($btnCerrar.Left - $btnCancel.Width - 10), $y); $btnLog.Location = New-Object Drawing.Point(($btnCancel.Left - $btnLog.Width - 10), $y) }
    $pie.Add_Resize($posPie)
    $txt = New-Object Windows.Forms.TextBox; $txt.Multiline = $true; $txt.ReadOnly = $true; $txt.ScrollBars = 'Both'; $txt.WordWrap = $false; $txt.Dock = 'Fill'; $txt.BorderStyle = 'None'
    $txt.BackColor = Get-Tc 'DetalleFondo'; $txt.ForeColor = Get-Tc 'DetalleTexto'; $txt.Font = New-Object Drawing.Font($script:Fuentes.Mono, 10)
    $dlg.Controls.AddRange(@($txt, $barra, $pie, $cab)); $dlg.Add_Shown($posPie)

    $S = @{ Vistas = (New-Object 'Collections.Generic.HashSet[long]'); Tick = 0; T0 = Get-Date; Fin = $false; Motivo = ''; Cancelado = $false; Agotado = $false; SinUnidad = $false; Desc = $null; Lineas = New-Object Collections.Generic.List[string] }
    $orden = New-OrdenScript $ruta
    Write-Historial "Ejecutó script $($h.Script)"; Write-Log "Script $($h.Script) iniciado desde el lanzador (máx. $limite s)"
    $S.L = [Nit.Lanzado]::Iniciar((Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'), $orden, $env:TEMP, $Global:NitKit.Raiz)
    $txt.AppendText("Iniciando $($h.N)…`r`n")

    $tm = New-Object Windows.Forms.Timer; $tm.Interval = 200
    $tm.Add_Tick({
        $n = 0; $sb = $null; $l = $null
        while ($n -lt 400 -and $S.L.Cola.TryDequeue([ref]$l)) { if ($l -match '^\W{0,3}#< CLIXML' -or $l -match '^\W{0,3}<Objs ') { continue }; if (-not $sb) { $sb = New-Object Text.StringBuilder }; [void]$sb.Append($l).Append("`r`n"); $S.Lineas.Add($l); $n++ }
        if ($sb) { $txt.AppendText($sb.ToString()); if ($txt.TextLength -gt 400000) { $txt.Text = $txt.Text.Substring($txt.TextLength - 200000) ; $txt.SelectionStart = $txt.TextLength; $txt.ScrollToCaret() } }
        $seg = [int]((Get-Date) - $S.T0).TotalSeconds
        if (-not $S.Fin) {
            # Ventanas que abra el script (casillas, avisos...): se traen al frente para que se vean siempre
            $S.Tick++
            if ($S.Tick % 5 -eq 0 -and -not $S.L.P.HasExited) { try { [void][Nit.Ventanas]::TraerAlFrente((Get-PidsArbol $S.L.P.Id), $S.Vistas) } catch { } }
            # Vigilancia de la unidad (cada ~3 s)
            if ($seg % 3 -eq 0) {
                $ok = Test-KitDisponible
                if (-not $ok -and -not $S.SinUnidad) { $S.SinUnidad = $true; $S.TDesc = Get-Date; Write-Log "Unidad del kit desconectada durante $($h.Script)" 'AVISO'; $txt.AppendText("`r`n$($Global:E.Aviso) UNIDAD DEL KIT DESCONECTADA. El script continúa en segundo plano; se espera su reconexión…`r`n") }
                elseif ($ok -and $S.SinUnidad) { $S.SinUnidad = $false; $d = [int]((Get-Date) - $S.TDesc).TotalSeconds; Write-Log "Unidad del kit reconectada tras $d s durante $($h.Script)"; $txt.AppendText("$($Global:E.OK) Unidad reconectada tras $d s.`r`n"); Sync-Log }
            }
            $est.Text = "En ejecución · $([timespan]::FromSeconds($seg).ToString('mm\:ss')) de máx. $([int]($limite / 60)) min$(if ($S.SinUnidad) { ' · ' + $Global:E.Aviso + ' unidad desconectada' } else { '' })"
            $est.ForeColor = if ($S.SinUnidad) { Get-Tc 'Aviso' } else { Get-Tc 'TextoSuave' }
            # El aviso se escribe una vez; si el proceso sigue vivo se reintenta el corte cada 10 ticks (antes se repetía taskkill y el aviso en cada tick hasta que muriera)
            if ($seg -ge $limite -and -not $S.L.P.HasExited -and (-not $S.Agotado -or $S.Tick % 10 -eq 0)) { if (-not $S.Agotado) { $txt.AppendText("`r`n$($Global:E.Aviso) Tiempo máximo ($([int]($limite / 60)) min) agotado: se canceló el script.`r`n") }; $S.Agotado = $true; $S.L.Matar() }
            if ($S.L.P.HasExited -and $S.L.Cola.IsEmpty) {
                $S.Fin = $true; $barra.Style = 'Continuous'; $barra.Value = 100
                $cod = $S.L.P.ExitCode
                $S.Motivo = if ($S.Cancelado) { 'Cancelado por el usuario' } elseif ($S.Agotado) { 'Tiempo máximo agotado' } elseif ($cod -eq 0) { 'Terminó correctamente' } elseif ($cod -eq 2) { 'Cancelado' } else { "Terminó con código $cod" }   # contrato: 2 = cancelado por la persona (neutro, como en la app)
                $est.Text = "$($S.Motivo) · $([timespan]::FromSeconds($seg).ToString('mm\:ss'))"; $est.ForeColor = if ($cod -eq 0 -and -not $S.Cancelado -and -not $S.Agotado) { Get-Tc 'Ok' } elseif ($cod -eq 2 -and -not $S.Cancelado -and -not $S.Agotado) { Get-Tc 'TextoSuave' } else { Get-Tc 'Fallo' }
                $txt.AppendText("`r`n── $($S.Motivo) ($([timespan]::FromSeconds($seg).ToString('mm\:ss'))) ──`r`n")
                $btnCancel.Enabled = $false; $btnCerrar.Enabled = $true
                Write-Log "Script $($h.Script): $($S.Motivo) en $seg s"
                try { [IO.File]::WriteAllText($logLocal, ($S.Lineas -join "`r`n"), (New-Object Text.UTF8Encoding($true))) } catch { }
                # Estos scripts imprimen claves: su salida no se copia al pendrive (queda solo en %TEMP%)
                try { if ($h.Script -notmatch 'Red_WiFi_y_Claves|Auditoria_Licencias_BitLocker' -and ((Test-ModoPublico) -or (Wait-Kit 20))) { New-Item -ItemType Directory -Force $dirEj | Out-Null; Copy-Item -LiteralPath $logLocal -Destination (Join-Path $dirEj "$nombreLog.log") -Force } } catch { }
                $tm.Stop()
            }
        }
    })
    $btnCancel.Add_Click({ if (-not $S.Fin) { $r = [Windows.Forms.MessageBox]::Show('¿Cancelar la ejecución? Se cerrará el script y los procesos que haya lanzado.', 'Cancelar', 'YesNo', 'Question'); if ($r -eq 'Yes') { $S.Cancelado = $true; $S.L.Matar(); $txt.AppendText("`r`n$($Global:E.Aviso) Cancelando…`r`n") } } })
    $btnCerrar.Add_Click({ $dlg.Close() })
    $btnLog.Add_Click({ $f = Join-Path $dirEj "$nombreLog.log"; if (-not (Test-Path -LiteralPath $f)) { $f = $logLocal }; if (Test-Path -LiteralPath $f) { Start-Process notepad.exe -ArgumentList "`"$f`"" } else { [void][Windows.Forms.MessageBox]::Show('El registro se guarda al terminar la ejecución.', 'Registro', 0, 64) } })
    $dlg.Add_FormClosing({ param($snd, $cev) if (-not $S.Fin) { $r = [Windows.Forms.MessageBox]::Show('El script sigue en ejecución. ¿Cerrar la ventana y cancelarlo?', 'Ejecución en curso', 'YesNo', 'Warning'); if ($r -ne 'Yes') { $cev.Cancel = $true } else { $S.L.Matar(); $S.Cancelado = $true } } })
    $dlg.Add_FormClosed({ $tm.Stop(); $tm.Dispose() })
    $tm.Start()
    $dueno = if ($propietario) { $propietario } else { $form }
    [void]$dlg.ShowDialog($dueno)
}

# Ventana de espera de reconexión de la unidad. Devuelve $true si el kit vuelve a estar disponible.
function Show-EsperaUnidad([int]$TimeoutSeg = 120) {
    if (Test-KitDisponible) { return $true }
    $K = $script:K
    $dlg = New-Object Windows.Forms.Form; $dlg.Text = 'Unidad desconectada'; $dlg.Size = New-Object Drawing.Size([int](520 * $K), [int](220 * $K)); $dlg.StartPosition = 'CenterParent'; $dlg.FormBorderStyle = 'FixedDialog'; $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor = Get-Tc 'Fondo'; $dlg.Font = New-Object Drawing.Font($script:Fuentes.UI, 10)
    $l1 = New-Object Windows.Forms.Label; $l1.Text = $Global:E.Aviso + '  No se encuentra la unidad del kit'; $l1.Font = New-Object Drawing.Font($script:Fuentes.Semi, 13); $l1.ForeColor = Get-Tc 'Aviso'; $l1.AutoSize = $true; $l1.Location = New-Object Drawing.Point([int](20 * $K), [int](16 * $K))
    $l2 = New-Object Windows.Forms.Label; $l2.ForeColor = Get-Tc 'Texto'; $l2.Size = New-Object Drawing.Size([int](470 * $K), [int](70 * $K)); $l2.Location = New-Object Drawing.Point([int](22 * $K), [int](56 * $K))
    $b = New-Object Windows.Forms.Button; $b.Text = 'Cancelar'; $b.Size = New-Object Drawing.Size([int](120 * $K), [int](34 * $K)); $b.Location = New-Object Drawing.Point([int](376 * $K), [int](136 * $K)); $b.FlatStyle = 'Flat'; $b.BackColor = Get-Tc 'Boton'; $b.ForeColor = Get-Tc 'Texto'; $b.FlatAppearance.BorderColor = Get-Tc 'Borde'; $b.DialogResult = 'Cancel'
    $dlg.Controls.AddRange(@($l1, $l2, $b)); $dlg.CancelButton = $b
    $t0 = Get-Date; $W = @{ Ok = $false }; Write-Log 'Esperando reconexión de la unidad del kit (ventana)' 'AVISO'
    $tm = New-Object Windows.Forms.Timer; $tm.Interval = 700
    $tm.Add_Tick({
        $seg = [int]((Get-Date) - $t0).TotalSeconds
        $nueva = $null; if (-not (Test-KitDisponible)) { $nueva = Find-KitReconectado }
        if ($nueva) { $Global:NitKit.Raiz = $nueva; $Global:NitKit.Datos = Join-Path $nueva 'Datos'; $env:NIT_RAIZ = $nueva; Write-Log "Unidad reconectada en $nueva" 'AVISO' }
        if (Test-KitDisponible) { $W.Ok = $true; $tm.Stop(); $dlg.Close(); return }
        if ($seg -ge $TimeoutSeg) { $tm.Stop(); $dlg.Close(); return }
        $l2.Text = "Reconecta el pendrive. Se continuará automáticamente al detectarlo (aunque cambie de letra).`r`nEsperando… $seg s de $TimeoutSeg s"
    })
    $tm.Start(); [void]$dlg.ShowDialog($form); $tm.Dispose()
    if ($W.Ok) { Write-Log "Unidad recuperada tras $([int]((Get-Date) - $t0).TotalSeconds) s"; Sync-Log }
    $W.Ok
}
