# Exporta el catálogo FINAL del kit (herramientas + scripts de mantenimiento, con página y grupo) a JSON para la app Electron.
# Solo lee: carga Catalogo_Kit.ps1 (la fuente única del catálogo) sin abrir ninguna ventana.
param([string]$Salida = (Join-Path (Split-Path -Parent $PSScriptRoot) 'App\datos\herramientas.json'))
$ErrorActionPreference = 'Stop'
$ruta = Join-Path $PSScriptRoot 'Catalogo_Kit.ps1'

# Datos que el bloque espera del lanzador
$global:dirScripts = $PSScriptRoot
$archivoSalida = $Salida   # Comun.ps1 también usa una variable $Salida (códigos de salida) y pisaría el parámetro
. (Join-Path $PSScriptRoot 'Comun.ps1')   # Read-DatosPsd1 (el catálogo de Mantenimiento se lee como datos); el Write-Log vacío de abajo lo sustituye porque aquí no hay kit inicializado
$Salida = $archivoSalida
function Write-Log { param($m, $n) }
. $ruta

$elementos = foreach ($h in $Herramientas) {
    $tipo = if ($h.Script) { 'script' } elseif ($h.Accion) { 'accion' } elseif ($h.Informe) { 'informe' } elseif ($h.Html) { 'html' }
            elseif ($h.Cmd) { 'cmd' } elseif ($h.Run) { 'run' } elseif ($h.Uri) { 'uri' } else { 'exe' }
    $id = if ($h.Script) { [IO.Path]::GetFileName($h.Script) } else { $h.N }
    [pscustomobject]@{
        id = $id; titulo = $h.N; descripcion = $h.D; categoria = $h.C; pagina = $h.P; grupo = $h.G; oculta = [bool]$h.Oculta
        peligro = [bool]$h.Peligro; publicoOk = [bool]$h.PublicoOk; tipo = $tipo; exe = $h.Exe; script = $h.Script; accion = $h.Accion; run = $h.Run; runArgs = $h.RunArgs
        cmd = $h.Cmd; html = $h.Html; uri = $h.Uri; timeout = $h.Timeout; ayuda = $h.Ayuda
    }
}
$ids = $elementos | Group-Object id | Where-Object Count -gt 1
if ($ids) { throw "Identificadores repetidos: $($ids.Name -join ', ')" }
# «Solucionar» del diagnóstico: Id de prueba -> títulos de las herramientas del kit que la arreglan (se leen de Ventana_Diagnostico.ps1)
$astDx = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Ventana_Diagnostico.ps1'), [ref]$null, [ref]$null)
$asigDx = $astDx.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$Soluciones' }, $true)
$soluciones = if ($asigDx) { $asigDx.Right.Find({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $true).SafeGetValue() } else { @{} }

New-Item -ItemType Directory -Force (Split-Path $Salida) | Out-Null
[pscustomobject]@{ generado = (Get-Date -Format s); paginas = $Paginas; soluciones = $soluciones; elementos = @($elementos) } | ConvertTo-Json -Depth 6 | Set-Content $Salida -Encoding UTF8
"Exportados $(@($elementos).Count) elementos ($(@($elementos | Where-Object { -not $_.oculta }).Count) visibles) y $($soluciones.Count) soluciones a $Salida"
