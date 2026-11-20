# =====================================================================
#  Por_Que_Se_Reinicio.ps1 - Por qué se reinició o se apagó el equipo (Nitrit0)
#  Repasa los últimos 30 días en los registros de Windows y dice, para cada reinicio o apagado, qué lo provocó:
#  una actualización, una persona o un programa que lo pidió, una pantalla azul con su código, un corte de corriente o un bloqueo.
#  No cambia nada. Se apoya en números de evento y en sus campos, no en el texto traducido de los mensajes.
#  Salida: 0 bien · 1 error
# =====================================================================
[CmdletBinding()]
param([int]$Dias = 30)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
if ($Dias -lt 1 -or $Dias -gt 365) { $Dias = 30 }
$desde = (Get-Date).AddDays(-$Dias)
Write-Output "  $($E.Lupa) Leyendo los registros de Windows de los últimos $Dias días…"
$ev = @()
try {
    $ev += @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 41; ProviderName = 'Microsoft-Windows-Kernel-Power'; StartTime = $desde } -ErrorAction SilentlyContinue)
    $ev += @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1074; ProviderName = 'User32'; StartTime = $desde } -ErrorAction SilentlyContinue)
    $ev += @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 6008; ProviderName = 'EventLog'; StartTime = $desde } -ErrorAction SilentlyContinue)
    $ev += @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1001; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; StartTime = $desde } -ErrorAction SilentlyContinue)
    $ev += @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 6005, 6006; ProviderName = 'EventLog'; StartTime = $desde } -ErrorAction SilentlyContinue)
} catch { Write-Output "  $($E.Aviso) No se pudieron leer todos los registros: $($_.Exception.Message)" }
if (-not $ev.Count) { Write-Output "  $($E.Info) No hay eventos de reinicio o apagado en ese periodo (o el registro de Windows se ha vaciado)."; Write-Log 'Por_Que_Se_Reinicio: sin eventos'; exit 0 }

function Get-Datos($e) { $d = @{}; try { foreach ($x in ([xml]$e.ToXml()).Event.EventData.Data) { $d[[string]$x.Name] = [string]$x.'#text' } } catch { }; $d }
$filas = New-Object Collections.Generic.List[object]
foreach ($e in ($ev | Sort-Object TimeCreated)) {
    $f = $e.TimeCreated.ToString('dd/MM/yyyy HH:mm')
    switch ($e.Id) {
        41 {
            $d = Get-Datos $e; $bc = 0; try { $bc = [int64]$d['BugcheckCode'] } catch { }
            if ($bc -ne 0) { $filas.Add([pscustomobject]@{ F = $f; Nivel = 'mal'; T = ("Pantalla azul (código de parada 0x{0:X}). Windows se reinició sola." -f $bc); Q = 'Mira «Pantallazos y eventos» para ver qué controlador la provoca.' }) }
            else { $filas.Add([pscustomobject]@{ F = $f; Nivel = 'mal'; T = 'Apagado inesperado: el equipo se quedó sin corriente, se bloqueó o se mantuvo pulsado el botón de encendido.'; Q = 'Si se repite sin motivo: revisa la fuente de alimentación, el cargador, las temperaturas y la memoria.' }) }
        }
        1074 {
            # Campos del evento 1074: proceso, equipo, motivo (texto de Windows), código, tipo (restart/shutdown/power off), comentario, usuario
            $p = $e.Properties; $proc = if ($p.Count -gt 0) { [string]$p[0].Value } else { '' }; $tipo = if ($p.Count -gt 4) { [string]$p[4].Value } else { '' }; $usu = if ($p.Count -gt 6) { [string]$p[6].Value } else { '' }
            $exe = ($proc -replace '\s*\(.*$', '' -replace '^.*[\\/]', '').Trim()   # solo el nombre del programa, sin ruta ni equipo
            $quien = if ($proc -match '(?i)TrustedInstaller|MoUsoCoreWorker|usoclient|wuauclt|musNotification|SetupHost|TiWorker') { 'una actualización de Windows' } elseif ($proc -match '(?i)winlogon|explorer|shutdown|StartMenuExperienceHost') { "una persona ($usu)" } else { "el programa «$exe» ($usu)" }
            $filas.Add([pscustomobject]@{ F = $f; Nivel = 'ok'; T = "Pedido por ${quien}: $tipo."; Q = '' })
        }
        6008 { $filas.Add([pscustomobject]@{ F = $f; Nivel = 'aviso'; T = 'Windows anota que el apagado anterior no fue limpio.'; Q = '' }) }
        1001 { $d = Get-Datos $e; $filas.Add([pscustomobject]@{ F = $f; Nivel = 'mal'; T = 'Informe de pantalla azul guardado por Windows tras reiniciar.'; Q = 'Los detalles están en «Pantallazos y eventos».' }) }
        6006 { $filas.Add([pscustomobject]@{ F = $f; Nivel = 'ok'; T = 'Apagado limpio de Windows.'; Q = '' }) }
        6005 { }
    }
}
$malos = @($filas | Where-Object Nivel -eq 'mal').Count
Write-Output ""
foreach ($r in $filas) { Write-Output ("  {0} {1}  {2}" -f $(switch ($r.Nivel) { 'ok' { $E.OK } 'aviso' { $E.Aviso } default { $E.Error } }), $r.F, $r.T); if ($r.Q) { Write-Output "       $($r.Q)" } }
Write-Output ""
if ($malos) { Write-Output "  $($E.Aviso) $malos reinicio(s) o apagado(s) inesperados en $Dias días. Los demás los pidió Windows o una persona." }
else { Write-Output "  $($E.OK) Ningún reinicio inesperado en $Dias días: todos fueron pedidos por Windows o por una persona." }
Write-Log "Por_Que_Se_Reinicio: $($filas.Count) eventos, $malos inesperados"
exit 0
