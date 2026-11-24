# =====================================================================
#  Limpieza_Total.ps1 - Limpieza total del equipo en un solo paso (Nitrit0)
#  Encadena las limpiezas del kit y dice cuánto espacio se ha liberado en C:
#    1) Limpiar temporales (temporales de Windows, cachés, Prefetch, papelera).
#    2) Limpieza profunda de Windows (miniaturas, registros, caché de actualizaciones, volcados, Windows.old): tú eliges qué.
#    3) Limpiar navegadores (solo si lo confirmas: borra cachés y, si lo marcas, cookies e historial).
#  No toca documentos ni programas. Cada paso conserva sus propias confirmaciones y sus avisos de lo que no se puede deshacer.
#  Para quitar programas usa «Desinstalador de apps»; para el registro huérfano, «Limpiar registro huérfano».
#  Parámetros: -SoloAnalizar (cada paso solo calcula lo que liberaría)   -SinPreguntas (no pregunta por los navegadores: los salta)
#  Salida: 0 bien · 1 error · 2 cancelado
# =====================================================================
[CmdletBinding()]
param([switch]$SoloAnalizar, [switch]$SinPreguntas)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
if (-not $SoloAnalizar) { Assert-Admin 'hacer la limpieza total' }

function Get-LibreC { try { [int64](Get-Volume -DriveLetter ($env:SystemDrive.TrimEnd(':')) -ErrorAction Stop).SizeRemaining } catch { -1 } }
function Format-Gb([int64]$b) { '{0:N1} GB' -f ($b / 1GB) }

$antes = Get-LibreC
if ($antes -ge 0) { Write-Output "  $($E.Disco) Espacio libre en $($env:SystemDrive) antes: $(Format-Gb $antes)" }

if (-not $SoloAnalizar -and -not $SinPreguntas -and -not (Confirm-Accion "Se van a pasar, una tras otra, las limpiezas del kit:`n`n  1) Temporales y cachés`n  2) Limpieza profunda de Windows (tú eliges qué)`n  3) Navegadores (te lo preguntaré)`n`nNo toca documentos ni programas. Cada paso te avisa de lo que no se puede deshacer. Antes se crea un punto de restauración.`n`n¿Empezar?")) { Exit-Kit 'Cancelado' 'Cancelado: no se ha limpiado nada.' }
if (-not $SoloAnalizar) { [void](Start-OperacionSegura 'Limpieza total del equipo') }

$pasos = @(
    @{ N = 'Temporales y cachés'; S = 'LimpiarTemporalesEquipo.ps1'; Pregunta = $false }
    @{ N = 'Limpieza profunda de Windows'; S = 'Limpiar_Espacio_Windows.ps1'; Pregunta = $false }
    @{ N = 'Navegadores'; S = 'Limpiar_Navegadores.ps1'; Pregunta = $true }
)
$hechos = 0; $fallos = 0; $k = 0
foreach ($p in $pasos) {
    Write-Progreso $k $pasos.Count $p.N; $k++   # barra de la app
    $ruta = Join-Path $PSScriptRoot $p.S
    if (-not (Test-Path -LiteralPath $ruta)) { Write-Output "  $($E.Aviso) Falta $($p.S): se salta «$($p.N)»."; $fallos++; continue }
    if ($p.Pregunta -and -not $SoloAnalizar) {
        if ($SinPreguntas) { Write-Output "  $($E.Info) Se salta «$($p.N)» (con -SinPreguntas no se tocan los navegadores)."; continue }
        if (-not (Confirm-Accion "¿Limpiar también los navegadores?`n`nSe cierran los navegadores abiertos y se borran cachés; en su ventana elegirás si también cookies e historial (eso no se puede recuperar).`n`nNo = se salta este paso." 'Nitrit0 Kit - Limpieza total' -Siempre)) { Write-Output "  $($E.Info) Se salta «$($p.N)»."; continue }
    }
    Write-Output "`n  $($E.Cohete) $($p.N)"
    $global:LASTEXITCODE = 0
    try {
        $m = Test-ScriptAutorizado $ruta; if ($m) { throw "no se ejecuta $([IO.Path]::GetFileName($ruta)): $m" }
        if ($SoloAnalizar) { & $ruta -SoloAnalizar } else { & $ruta }
        $c = $LASTEXITCODE
        if ($c -eq 2) { Write-Output "  $($E.Info) «$($p.N)» cancelado: se continúa con el siguiente paso." }
        elseif ($c) { Write-Output "  $($E.Aviso) «$($p.N)» terminó con error (código $c)."; $fallos++ }
        else { $hechos++ }
    } catch { Write-Output "  $($E.Aviso) «$($p.N)» falló: $($_.Exception.Message)"; $fallos++ }
}

Write-Progreso $pasos.Count $pasos.Count 'Terminado'
Write-Output ''
if ($SoloAnalizar) { Write-Output "  $($E.Info) Solo análisis: no se ha borrado nada."; Exit-Kit 'Ok' }
$despues = Get-LibreC
if ($antes -ge 0 -and $despues -ge 0) { Write-Output "  $($E.OK) Espacio libre en $($env:SystemDrive) ahora: $(Format-Gb $despues) (liberado: $(Format-Gb ([math]::Max(0, $despues - $antes))))" }
Write-Log "Limpieza_Total: $hechos paso(s) bien, $fallos con aviso"
if (-not $hechos) { Exit-Kit 'Error' 'No se completó ningún paso de limpieza.' }
Write-Output "  $($E.Info) Siguiente: «Desinstalador de apps» para quitar programas que ya no uses, y reinicia el equipo."
