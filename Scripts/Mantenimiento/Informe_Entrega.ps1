# =====================================================================
#  Informe_Entrega.ps1 - Parte de una página para entregar al cliente (Nitrit0)
#  Reúne lo que el kit ya sabe de este equipo: el primer y el último diagnóstico guardados (cómo llegó y
#  cómo se entrega), los trabajos hechos desde el lanzador (registro del kit) y las notas del técnico.
#  Genera un HTML en Datos\Informes pensado para imprimir o guardar como PDF desde el navegador.
#  Parámetros: -Cliente "nombre"  -Notas "texto"  -Dias 30 (trabajos de los últimos N días)  -Silencioso (no pregunta ni abre)
# =====================================================================
[CmdletBinding()]
param([string]$Cliente, [string]$Notas, [int]$Dias = 30, [switch]$Silencioso)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Historial.ps1')   # Get-IdEquipo
function Esc($t) { [Net.WebUtility]::HtmlEncode([string]$t) }
$datos = Get-BaseTrabajo

# --- Diagnósticos guardados de este equipo: el primero es «al llegar» y el último «al entregar» ---
$diag = @(Get-ChildItem -LiteralPath (Join-Path $datos "Historial\$(Get-IdEquipo)") -Filter *.json -ErrorAction SilentlyContinue | Sort-Object Name)
$leer = { param($f) try { Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null } }
$ini = if ($diag.Count) { & $leer $diag[0] }; $fin = if ($diag.Count -gt 1) { & $leer $diag[-1] }
$ficha = @($diag | ForEach-Object { (& $leer $_).Ficha } | Where-Object { $_ }) | Select-Object -Last 1

# La app (NIT_APP) ya pidió estos datos en su propio formulario y los pasa por entorno: aquí no se abren cuadros de Windows
if ($env:NIT_APP) { if (-not $Cliente) { $Cliente = $env:NIT_CLIENTE }; if (-not $Notas) { $Notas = $env:NIT_NOTAS } }
if (-not $Silencioso -and -not $env:NIT_APP) {
    Add-Type -AssemblyName Microsoft.VisualBasic
    if (-not $Cliente) { $Cliente = [Microsoft.VisualBasic.Interaction]::InputBox('Nombre del cliente (aparece en el informe):', 'Informe de entrega', [string]$ficha.Cliente) }
    if (-not $Notas) { $Notas = [Microsoft.VisualBasic.Interaction]::InputBox('Recomendaciones para el cliente (opcional):', 'Informe de entrega', '') }
}
if (-not $Cliente) { $Cliente = [string]$ficha.Cliente }

# --- Equipo ---
$cs = Get-CimInstance Win32_ComputerSystem; $so = Get-CimInstance Win32_OperatingSystem
$cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name -replace '\s+', ' '
$serie = try { (Get-CimInstance Win32_BIOS).SerialNumber } catch { '' }
$equipo = "$($cs.Manufacturer) $($cs.Model)".Trim()

# --- Trabajos: lo que el lanzador dejó en el registro de este equipo ---
$cat = @{}; try { $cat = Read-DatosPsd1 (Join-Path $PSScriptRoot 'Catalogo.psd1') } catch { Write-Output "  $($E.Aviso) No se pudo leer el catálogo de herramientas: el informe no puede decir qué trabajos se hicieron ($($_.Exception.Message))."; Write-Log "Informe_Entrega: catálogo ilegible: $($_.Exception.Message)" 'AVISO' }
$desde = (Get-Date).AddDays(-$Dias); $trabajos = @()
$patron = (Split-Path (Get-RutaLog) -Leaf) -replace '^Kit_\d+_', 'Kit_*_'
foreach ($log in Get-ChildItem -Path (Join-Path (Split-Path (Get-RutaLog)) $patron) -ErrorAction SilentlyContinue | Sort-Object Name) {
    foreach ($l in Get-Content -LiteralPath $log.FullName -Encoding UTF8 -ErrorAction SilentlyContinue) {
        if ($l -match '^\[(?<f>[\d\- :]+)\] \[\w+\] Script (?<s>[^:]+\.ps1): (?<r>.+) en \d+ s$') {
            $nombre = Split-Path $Matches.s -Leaf; $fecha = [datetime]$Matches.f
            if ($fecha -lt $desde -or $nombre -eq 'Informe_Entrega.ps1' -or -not $cat.ContainsKey($nombre)) { continue }
            $trabajos += [pscustomobject]@{ Fecha = $fecha; Titulo = $cat[$nombre].Titulo; Resultado = $Matches.r; Bien = ($Matches.r -eq 'Terminó correctamente') }
        }
    }
}

# --- HTML ---
$chip = { param($e) $c = switch ($e) { 'OK' { 'ok' } 'Aviso' { 'av' } 'Fallo' { 'fa' } default { 'in' } }; $t = switch ($e) { 'OK' { 'Bien' } 'Aviso' { 'Aviso' } 'Fallo' { 'Fallo' } default { [string]$e } }; "<span class='c $c'>$(Esc $t)</span>" }
$filasDiag = ''
if ($ini) {
    $post = @{}; if ($fin) { foreach ($p in @($fin.Pruebas)) { $post[$p.Id] = $p } }
    $lista = if ($fin) { @($fin.Pruebas) } else { @($ini.Pruebas) }
    $prev = @{}; foreach ($p in @($ini.Pruebas)) { $prev[$p.Id] = $p }
    foreach ($p in $lista) {
        $a = $prev[$p.Id]
        $filasDiag += "<tr><td>$(Esc $p.Nombre)</td><td>$(if ($a) { & $chip $a.Estado } else { '—' })</td>$(if ($fin) { "<td>$(& $chip $p.Estado)</td>" })<td class='s'>$(Esc $p.Resumen)</td></tr>"
    }
}
# Si un trabajo se repitió, cuenta la última vez
$trabajos = @($trabajos | Group-Object Titulo | ForEach-Object { $_.Group[-1] } | Sort-Object Fecha)
$filasTrab = ($trabajos | ForEach-Object { "<tr><td>$($_.Fecha.ToString('dd/MM/yyyy HH:mm'))</td><td>$(Esc $_.Titulo)</td><td>$(if ($_.Bien) { "<span class='c ok'>Hecho</span>" } else { "<span class='c av'>$(Esc $_.Resultado)</span>" })</td></tr>" }) -join ''
# --- Puntaje: de 0 a 100 con las mismas comprobaciones al llegar y al entregar (Bien = 1, Aviso = medio, Fallo = 0) ---
$puntaje = { param($lista) $v = @($lista | Where-Object { $_.Estado -in 'OK', 'Aviso', 'Fallo' }); if ($v.Count) { [math]::Round(100 * (@($v | Where-Object Estado -eq 'OK').Count + 0.5 * @($v | Where-Object Estado -eq 'Aviso').Count) / $v.Count) } }
$bloquePuntaje = ''
if ($ini) {
    $comunes = if ($fin) { $ids = @($fin.Pruebas | ForEach-Object { $_.Id }); @($ini.Pruebas | Where-Object { $_.Id -in $ids }) } else { @($ini.Pruebas) }
    $pIni = & $puntaje $comunes
    $pFin = if ($fin) { $idc = @($comunes | ForEach-Object { $_.Id }); & $puntaje @($fin.Pruebas | Where-Object { $_.Id -in $idc }) }
    if ($null -ne $pIni) {
        $n = @($comunes | Where-Object { $_.Estado -in 'OK', 'Aviso', 'Fallo' }).Count
        $dif = if ($null -ne $pFin) { $pFin - $pIni } else { 0 }
        $colorDif = if ($dif -gt 0) { 'ok' } elseif ($dif -lt 0) { 'fa' } else { 'in' }
        $signo = if ($dif -gt 0) { '+' } else { '' }
        $bloquePuntaje = "<div class='punt'><div><span class='s'>Al llegar</span><b>$pIni</b></div>" + $(if ($null -ne $pFin) { "<div class='flecha'>→</div><div><span class='s'>Al entregar</span><b class='$colorDif'>$pFin</b></div><div class='dif $colorDif'>$signo$dif puntos</div>" } else { "<div class='s'>Falta un segundo diagnóstico al entregar para ver la mejora.</div>" }) + "</div><p class='s'>Puntaje de 0 a 100 calculado con $n comprobaciones del diagnóstico: cada «Bien» suma 1, cada «Aviso» medio punto y cada «Fallo» nada.</p>"
    }
}
$fechaIni = if ($ini) { ([datetime]$ini.Fecha).ToString('dd/MM/yyyy HH:mm') }; $fechaFin = if ($fin) { ([datetime]$fin.Fecha).ToString('dd/MM/yyyy HH:mm') }

$html = @"
<!doctype html>
<html lang="es"><head><meta charset="utf-8"><title>Informe de entrega - $(Esc $Cliente)</title>
<style>
  body { font-family: 'Segoe UI', sans-serif; color: #171717; margin: 0; background: #fafafa; }
  .hoja { max-width: 820px; margin: 24px auto; background: #fff; border: 1px solid #e4e4e7; border-radius: 12px; padding: 32px 40px; }
  h1 { font-size: 22px; font-weight: 600; margin: 0 0 4px; }
  h2 { font-size: 14px; font-weight: 600; margin: 28px 0 8px; }
  p, td, th { font-size: 13px; line-height: 20px; }
  .sub, .s { color: #525252; }
  .dos { display: grid; grid-template-columns: 1fr 1fr; gap: 4px 32px; margin-top: 16px; }
  table { width: 100%; border-collapse: collapse; }
  th { text-align: left; font-weight: 600; color: #525252; }
  th, td { padding: 6px 8px 6px 0; border-bottom: 1px solid #e4e4e7; vertical-align: top; }
  .c { font-weight: 600; } .ok { color: #16a34a; } .av { color: #b45309; } .fa { color: #dc2626; } .in { color: #525252; }
  .punt { display: flex; align-items: center; gap: 24px; margin: 4px 0 8px; }
  .punt div { display: flex; flex-direction: column; } .punt b { font-size: 40px; line-height: 44px; font-weight: 600; }
  .punt .flecha { font-size: 28px; color: #525252; } .punt .dif { font-size: 15px; font-weight: 600; }
  .firmas { display: grid; grid-template-columns: 1fr 1fr; gap: 48px; margin-top: 56px; }
  .firmas div { border-top: 1px solid #171717; padding-top: 6px; font-size: 12px; color: #525252; }
  @media print { body { background: #fff; } .hoja { border: 0; margin: 0; padding: 0; max-width: none; } }
</style></head><body><div class="hoja">
<h1>Informe de entrega</h1>
<p class="sub">$(Get-Date -Format 'dd/MM/yyyy')</p>
<div class="dos">
  <p><b>Cliente:</b> $(Esc $Cliente)$(if ($ficha.Telefono) { " · $(Esc $ficha.Telefono)" })</p>
  <p><b>Equipo:</b> $(Esc $equipo)</p>
  <p><b>Motivo de la visita:</b> $(if ($ficha.Motivo) { Esc $ficha.Motivo } else { '—' })</p>
  <p><b>N.º de serie:</b> $(Esc $serie)</p>
  <p><b>Procesador:</b> $(Esc $cpu)</p>
  <p><b>Memoria y sistema:</b> $([math]::Round($cs.TotalPhysicalMemory / 1GB)) GB · $(Esc $so.Caption)</p>
</div>
<h2>Trabajos realizados</h2>
$(if ($filasTrab) { "<table><tr><th>Fecha</th><th>Trabajo</th><th>Resultado</th></tr>$filasTrab</table>" } else { "<p class='sub'>No hay trabajos del kit registrados en este equipo en los últimos $Dias días.</p>" })
<h2>Estado del equipo</h2>
$bloquePuntaje
$(if ($filasDiag) { "<table><tr><th>Comprobación</th><th>Al llegar$(if ($fechaIni) { "<br><span class='s'>$fechaIni</span>" })</th>$(if ($fin) { "<th>Al entregar<br><span class='s'>$fechaFin</span></th>" })<th>Detalle</th></tr>$filasDiag</table>" } else { "<p class='sub'>No hay diagnósticos guardados de este equipo. Pasa el «Diagnóstico rápido» antes y después del trabajo para que salgan aquí.</p>" })
$(if ($Notas) { "<h2>Recomendaciones</h2><p>$(Esc $Notas)</p>" })
<div class="firmas"><div>Técnico</div><div>Cliente (recibí el equipo conforme)</div></div>
</div></body></html>
"@

$dir = Get-CarpetaSalida 'Informes'
$ruta = Join-Path $dir ("Entrega_{0}_{1}.html" -f ($env:COMPUTERNAME -replace '[^\w\-]', '_'), (Get-Date -Format 'yyyyMMdd_HHmm'))
[IO.File]::WriteAllText($ruta, $html, (New-Object Text.UTF8Encoding($true)))
Write-Output "  $($E.OK) Informe creado: $ruta"
Write-Output "  $($E.Info) $($trabajos.Count) trabajo(s) y $($diag.Count) diagnóstico(s) de este equipo. Para PDF: Ctrl+P en el navegador > Guardar como PDF."
if ($diag.Count -lt 2) { Write-Output "  $($E.Aviso) Solo hay $($diag.Count) diagnóstico(s): para comparar «al llegar» y «al entregar» hacen falta dos." }
Write-Log "Informe de entrega creado: $ruta"
if (-not $Silencioso) { Open-Informe $ruta }
