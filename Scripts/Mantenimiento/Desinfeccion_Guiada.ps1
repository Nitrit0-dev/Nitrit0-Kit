# =====================================================================
#  Desinfeccion_Guiada.ps1 - Desinfección guiada de un equipo con sospecha de malware (Nitrit0)
#  Para «va raro», «sale publicidad», «el navegador cambia solo» o antes de entregar un equipo de origen dudoso.
#  Orden: 1) mira el estado (antivirus, tareas y servicios sospechosos, procesos en carpetas de usuario),
#         2) crea un punto de restauración, 3) abre uno tras otro los escáneres del kit (Apps\Malware) y espera a que
#         los cierres: KVRT, AdwCleaner y, si están en el kit, Sophos y Trellix Stinger.
#  NO borra nada por su cuenta: cada escáner pone en cuarentena lo que tú aceptes dentro de su ventana, y se restaura desde ella.
#  Necesita a un técnico delante (los escáneres son programas con ventana); no se ejecuta en modo automático.
#  Parámetros: -SoloAnalizar (solo mira y dice qué escáneres hay; no abre ninguno)   -SinPreguntas (no pide confirmar cada paso)
#  Salida: 0 bien · 1 error (o ningún escáner en el kit) · 2 cancelado
# =====================================================================
[CmdletBinding()]
param([switch]$SoloAnalizar, [switch]$SinPreguntas)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
if ($env:NIT_AUTO) { Exit-Kit 'Cancelado' 'No se ejecuta en modo automático: los escáneres necesitan a un técnico que los maneje.' }
if (-not $SoloAnalizar) { Assert-Admin 'desinfectar el equipo' }

$escaneres = @(
    @{ N = 'Kaspersky Virus Removal Tool'; Rel = 'Malware\KVRT.exe'; Nota = 'Escáner profundo. Descarga sus firmas al abrirse: necesita Internet.' }
    @{ N = 'Malwarebytes AdwCleaner'; Rel = 'Malware\adwcleaner.exe'; Nota = 'Adware, secuestradores de navegador y programas no deseados.' }
    @{ N = 'Sophos Virus Removal Tool'; Rel = 'Malware\sophos*.exe'; Nota = 'Segundo motor independiente (opcional). Se instala en el equipo al abrirlo: desinstálalo al terminar si es de un cliente.' }
    @{ N = 'Trellix Stinger'; Rel = 'Malware\stinger*.exe'; Nota = 'Escáner ligero de amenazas muy extendidas (opcional).' }
)

# ---------------------------------------------------------------- 1) Estado previo (solo lectura)
Write-Output "  $($E.Lupa) Estado del equipo antes de desinfectar"
$auditoria = Join-Path $PSScriptRoot 'Auditoria_Seguridad.ps1'
if (Test-Path -LiteralPath $auditoria) {
    try { & $auditoria } catch { Write-Output "    $($E.Aviso) No se pudo completar la auditoría de seguridad: $($_.Exception.Message)" }
} else { Write-Output "    $($E.Aviso) Falta Auditoria_Seguridad.ps1: se sigue sin la revisión previa." }

try {
    $raros = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path -match '\\(AppData|Temp|Users\\Public|Downloads)\\' } |
        Sort-Object Path -Unique | Select-Object -First 15)
    if ($raros.Count) {
        Write-Output "  $($E.Info) Procesos en marcha desde carpetas de usuario o temporales (pueden ser legítimos: Teams, Discord, instaladores):"
        foreach ($p in $raros) { Write-Output "    · $($p.ProcessName) — $($p.Path)" }
    } else { Write-Output "  $($E.OK) Ningún proceso en marcha desde carpetas de usuario o temporales." }
} catch { Write-Output "  $($E.Aviso) No se pudieron leer los procesos: $($_.Exception.Message)" }

# ---------------------------------------------------------------- 2) Escáneres disponibles en el kit
Write-Output "`n  $($E.Lupa) Escáneres en el kit (Apps\Malware)"
$hay = @()
foreach ($s in $escaneres) {
    $ruta = Resolve-ExeKit $s.Rel
    if (Test-Path -LiteralPath $ruta) { $hay += @{ N = $s.N; Ruta = $ruta }; Write-Output "    $($E.OK) $($s.N) — $($s.Nota)" }
    else { Write-Output "    $($E.Info) $($s.N): no está en el kit." }
}
if (-not $hay.Count) { Exit-Kit 'Error' 'No hay ningún escáner en Apps\Malware: copia al menos KVRT o AdwCleaner.' }
if ($SoloAnalizar) { Write-Output "`n  $($E.Info) Solo análisis: no se ha abierto ningún escáner ni se ha cambiado nada."; Exit-Kit 'Ok' }

# ---------------------------------------------------------------- 3) Confirmación y punto de restauración
$lista = ($hay | ForEach-Object { "  · $($_.N)" }) -join "`n"
if (-not $SinPreguntas -and -not (Confirm-Accion "Se van a abrir, uno tras otro, estos escáneres:`n`n$lista`n`nCada uno pone en cuarentena solo lo que tú aceptes en su ventana (se puede restaurar desde ella). Antes se crea un punto de restauración.`nLos análisis completos pueden tardar horas y necesitan Internet para bajar firmas.`n`n¿Empezar?")) { Exit-Kit 'Cancelado' 'Cancelado: no se ha abierto ningún escáner.' }
[void](Start-OperacionSegura 'Desinfección guiada')

# ---------------------------------------------------------------- 4) Escáneres, uno tras otro
$abiertos = 0; $k = 0
foreach ($h in $hay) {
    Write-Progreso $k $hay.Count $h.N; $k++   # barra de la app
    if ($abiertos -gt 0 -and -not $SinPreguntas -and -not (Confirm-Accion "Siguiente escáner: $($h.N).`n`n¿Lo abro ahora? (No = se salta este y se termina.)" 'Nitrit0 Kit - Desinfección')) { Write-Output "  $($E.Info) Se omite $($h.N) y los siguientes."; break }
    try {
        $local = Copy-AlCache $h.Ruta   # se ejecuta desde el PC, no desde el pendrive: más rápido y no lo bloquea
        Write-Output "  $($E.Cohete) Abriendo $($h.N): haz el análisis y CIERRA su ventana al terminar para continuar."
        $p = Start-Process -FilePath $local -PassThru -ErrorAction Stop
        $abiertos++; Write-Log "Desinfeccion_Guiada: abierto $($h.N)"
        if ($p.WaitForExit(3 * 3600 * 1000)) { Write-Output "  $($E.OK) $($h.N) cerrado." }
        else { Write-Output "  $($E.Aviso) $($h.N) lleva más de 3 horas abierto: se deja abierto y se continúa."; Write-Log "Desinfeccion_Guiada: $($h.N) sigue abierto tras 3 h" 'AVISO' }
    } catch { Write-Output "  $($E.Aviso) No se pudo abrir $($h.N): $($_.Exception.Message)"; Write-Log "Desinfeccion_Guiada: fallo al abrir $($h.N): $($_.Exception.Message)" 'AVISO' }
}
Write-Progreso $hay.Count $hay.Count 'Terminado'
if (-not $abiertos) { Exit-Kit 'Error' 'No se pudo abrir ningún escáner.' }

# ---------------------------------------------------------------- 5) Cierre
Save-Informativo 'Desinfección guiada: los escáneres pusieron en cuarentena lo que se aceptó en cada ventana' 'Para recuperar algo: ábrelo en la pestaña de cuarentena del propio escáner (KVRT, AdwCleaner…) y restáuralo. Con Deshacer cambios se vuelve al punto de restauración.'
Write-Output "`n  $($E.OK) Hecho: $abiertos escáner(es) usados."
Write-Output "  $($E.Info) Ahora: reinicia el equipo, vuelve a pasar «Auditoría de seguridad» y comprueba que Windows Defender queda activo."
Write-Log "Desinfeccion_Guiada: terminada, $abiertos escáner(es)"
