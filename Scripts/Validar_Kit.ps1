# =====================================================================
#  Validar_Kit.ps1 (utilidad de desarrollo - Nitrit0)
#  Se pasa después de tocar cualquier script y ANTES de Regenerar_Integridad.ps1. No cambia nada del equipo.
#  Comprueba: sintaxis de todos los .ps1, codificación (UTF-8 con BOM si hay tildes: PowerShell 5.1 lo exige),
#  que el catálogo se lee y coincide con los archivos, que las tarjetas del lanzador apuntan a archivos que
#  existen, y lo que rompe un script lanzado desde el kit (Read-Host, pause: no hay teclado) o lo ata a un
#  equipo concreto (rutas C:\ fijas).
#  Parámetros: -Corregir (añade el BOM que falte)   -Analizador (pasa además PSScriptAnalyzer si está instalado)
#  Sale con código 0 si no hay errores y 1 si los hay.
# =====================================================================
[CmdletBinding()]
param([switch]$Corregir, [switch]$Analizador)
$dir = $PSScriptRoot; $mant = Join-Path $dir 'Mantenimiento'
$err = New-Object Collections.Generic.List[string]; $avi = New-Object Collections.Generic.List[string]
$ps1 = @(Get-ChildItem -LiteralPath $dir -Recurse -Filter *.ps1)

foreach ($f in $ps1) {
    $rel = $f.FullName.Substring($dir.Length + 1)
    # 1) Sintaxis
    $t = $null; $e = $null; $ast = [Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$t, [ref]$e)
    foreach ($x in $e) { $err.Add("${rel}:$($x.Extent.StartLineNumber)  sintaxis: $($x.Message)") }
    # 2) Codificación
    $b = [IO.File]::ReadAllBytes($f.FullName)
    $bom = $b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF
    $noAscii = $false; foreach ($x in $b) { if ($x -gt 127) { $noAscii = $true; break } }
    if ($noAscii -and -not $bom) {
        if ($Corregir) { [IO.File]::WriteAllText($f.FullName, [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8), (New-Object Text.UTF8Encoding($true))); $avi.Add("$rel  BOM añadido") }
        else { $err.Add("$rel  tiene tildes o emojis y le falta el BOM de UTF-8 (PowerShell 5.1 los leería mal). Usa -Corregir.") }
    }
    # 3) Lo que no funciona lanzado desde el kit (solo scripts de Mantenimiento: se ejecutan sin teclado)
    if ($f.DirectoryName -eq $mant) {
        # Texto traducido: analizar con -match / Select-String lo que imprime un comando nativo cambia con el idioma de Windows (un aviso por script)
        $n = 0; foreach ($l in [IO.File]::ReadAllLines($f.FullName, [Text.Encoding]::UTF8)) {
            $n++
            if ($l -match '(?i)(fsutil|defrag|netsh|ipconfig|sfc|dism|chkdsk|w32tm|powercfg|bcdedit|driverquery|gpresult|schtasks)(\.exe)?' -and $l -match '(?i)-match|-notmatch|-like|Select-String' -and $l -notmatch 'idioma-ok') { $avi.Add("${rel}:$n  analiza con texto la salida de un comando nativo (cambia con el idioma de Windows): usa objetos, CIM o códigos de salida, o añade «# idioma-ok» si el patrón no depende del idioma."); break }
        }
        foreach ($c in $ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] }, $true)) {
            $n = $c.GetCommandName()
            if ($n -in 'Read-Host', 'pause', 'Out-GridView', 'Get-Credential') { $err.Add("${rel}:$($c.Extent.StartLineNumber)  usa ${n}: el kit lanza los scripts sin teclado. Pregunta con una ventana (MessageBox o formulario).") }
            if ($n -in 'Get-WmiObject', 'gwmi') { $avi.Add("${rel}:$($c.Extent.StartLineNumber)  usa Get-WmiObject: mejor Get-CimInstance.") }
        }
        foreach ($s in $ast.FindAll({ param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst] -or $n -is [Management.Automation.Language.ExpandableStringExpressionAst] }, $true)) {
            if ($s.Value -match '(?i)^C:\\(Windows|Users|Program Files|ProgramData)\b') { $avi.Add("${rel}:$($s.Extent.StartLineNumber)  ruta fija «$($s.Value.Substring(0, [Math]::Min(40, $s.Value.Length)))»: usa `$env:SystemRoot, `$env:ProgramData, `$env:USERPROFILE…") }
        }
        # Regla 11: el administrador se comprueba con Test-EsAdmin / Assert-Admin de Comun.ps1, no con IsInRole a mano
        $lineasAdmin = New-Object Collections.Generic.HashSet[int]
        foreach ($m in $ast.FindAll({ param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Extent.Text -eq 'IsInRole' }, $true)) { [void]$lineasAdmin.Add([int]$m.Extent.StartLineNumber) }
        foreach ($ln in ($lineasAdmin | Sort-Object)) { $avi.Add("${rel}:$ln  comprueba el administrador a mano (IsInRole): usa Test-EsAdmin o Assert-Admin de Comun.ps1 (regla 11).") }
        # Regla 10: cancelar con «return» deja el código 0 y la app lo cuenta como éxito; debe ser Exit-Kit 'Cancelado' (código 2).
        # Solo cuenta el «return» del propio script (no el de funciones ni de scriptblocks de ventana) cuyo bloque habla de cancelar.
        foreach ($x in $ast.FindAll({ param($n) $n -is [Management.Automation.Language.ReturnStatementAst] }, $true)) {
            $enFuncion = $false; $p = $x.Parent
            while ($p) { if ($p -is [Management.Automation.Language.FunctionDefinitionAst] -or $p -is [Management.Automation.Language.ScriptBlockExpressionAst]) { $enFuncion = $true; break }; $p = $p.Parent }
            if ($enFuncion) { continue }
            $blk = $x.Parent; while ($blk -and -not ($blk -is [Management.Automation.Language.StatementBlockAst])) { $blk = $blk.Parent }
            if ($blk -and $blk.Extent.Text -match '(?i)cancel') { $avi.Add("${rel}:$($x.Extent.StartLineNumber)  cancela con «return» (sale con 0, la app lo cuenta como éxito): usa Exit-Kit 'Cancelado' (regla 10).") }
        }
        # Usar funciones del kit sin cargar Comun.ps1 solo funciona dentro del lanzador: suelto, el script revienta
        if ($ast.Extent.Text -notmatch 'Comun\.ps1' -and $ast.Extent.Text -match 'Write-Log|Get-Kit(Raiz|Datos)|Invoke-Proceso|Get-Descarga|Start-OperacionSegura|\$Global:NitKit') { $err.Add("$rel  usa funciones del kit pero no carga Comun.ps1: fallará si se ejecuta fuera del lanzador.") }
    }
}

# 4) Catálogo
$cat = @{}
try { . (Join-Path $dir 'Comun.ps1'); $cat = Read-DatosPsd1 (Join-Path $mant 'Catalogo.psd1') } catch { $err.Add("Catalogo.psd1 no se puede leer: $($_.Exception.Message)") }
$enDisco = @(Get-ChildItem -LiteralPath $mant -Filter *.ps1 | Select-Object -ExpandProperty Name)
$categorias = 'Actualizaciones', 'Software', 'Mantenimiento', 'Memoria y rendimiento', 'Energía', 'Personalización', 'Diagnóstico'
foreach ($k in $cat.Keys) {
    $v = $cat[$k]
    if ($v.Oculto) { continue }
    if ($enDisco -notcontains $k) { $avi.Add("Catalogo.psd1: «$k» está en el catálogo pero no existe el archivo.") ; continue }
    if (-not $v.Titulo) { $avi.Add("Catalogo.psd1: «$k» no tiene Titulo.") }
    if (-not $v.Descripcion) { $avi.Add("Catalogo.psd1: «$k» no tiene Descripcion.") }
    if ($v.Simulable -and ([IO.File]::ReadAllText((Join-Path $mant $k), [Text.Encoding]::UTF8) -notmatch 'SoloAnalizar')) { $err.Add("Catalogo.psd1: «$k» declara Simulable pero su script no tiene el parámetro -SoloAnalizar.") }
    if ($v.Categoria -and $categorias -notcontains $v.Categoria) { $err.Add("Catalogo.psd1: «$k» tiene una categoría desconocida («$($v.Categoria)»): saldría en Mantenimiento. Válidas: $($categorias -join ', ').") }
}
$lanz = [IO.File]::ReadAllText((Join-Path $dir 'Lanzador.ps1'), [Text.Encoding]::UTF8) + [IO.File]::ReadAllText((Join-Path $dir 'Catalogo_Kit.ps1'), [Text.Encoding]::UTF8)   # iconos (Lanzador.ps1) y tarjetas (Catalogo_Kit.ps1)
foreach ($n in $enDisco) { if (-not $cat.ContainsKey($n) -and $lanz -notmatch [regex]::Escape("Mantenimiento\$n")) { $avi.Add("$n no está en Catalogo.psd1: saldrá con un título y una descripción genéricos.") } }

# 4b) El catálogo que lee la app (App\datos\herramientas.json) tiene que ser posterior a sus fuentes; si no, la app enseña el catálogo viejo
$jsonApp = Join-Path (Split-Path -Parent $dir) 'App\datos\herramientas.json'
if (Test-Path -LiteralPath $jsonApp) {
    $fechaJson = (Get-Item -LiteralPath $jsonApp).LastWriteTime
    $fuentes = @((Join-Path $dir 'Catalogo_Kit.ps1'), (Join-Path $mant 'Catalogo.psd1'), (Join-Path $dir 'Lanzador.ps1')) | Where-Object { Test-Path -LiteralPath $_ }
    $masNuevas = @($fuentes | Where-Object { (Get-Item -LiteralPath $_).LastWriteTime -gt $fechaJson })
    if ($masNuevas.Count) { $avi.Add("App\datos\herramientas.json es más antiguo que $(($masNuevas | ForEach-Object { Split-Path $_ -Leaf }) -join ', '): ejecuta Exportar_Catalogo.ps1 o la app mostrará el catálogo viejo.") }
} else { $avi.Add('No existe App\datos\herramientas.json (el catálogo de la app): ejecuta Exportar_Catalogo.ps1.') }

# 5) Tarjetas del lanzador que apuntan a archivos de Scripts\
foreach ($m in [regex]::Matches($lanz, "(?:Script|Html)='([^']+)'")) { if (-not (Test-Path -LiteralPath (Join-Path $dir $m.Groups[1].Value))) { $err.Add("Lanzador.ps1: la tarjeta apunta a «$($m.Groups[1].Value)», que no existe.") } }
foreach ($m in [regex]::Matches($lanz, "'(Mantenimiento\\[^']+\.ps1)'\s*=\s*0x")) { if (-not (Test-Path -LiteralPath (Join-Path $dir $m.Groups[1].Value))) { $avi.Add("Lanzador.ps1: hay un icono para «$($m.Groups[1].Value)», que ya no existe.") } }

# 5b) El respaldo fijo de 7-Zip (7zAAMM-x64.exe) no debe envejecer más de 12 meses (comprobación sin red)
$inst = Join-Path $dir 'Mantenimiento\Instalador_Basico.ps1'
if (Test-Path -LiteralPath $inst) {
    $m7 = [regex]::Match((Get-Content -LiteralPath $inst -Raw -Encoding UTF8), '7z(\d{2})(\d{2})-x64\.exe')
    if ($m7.Success) { try { $f7 = New-Object DateTime (2000 + [int]$m7.Groups[1].Value), ([int]$m7.Groups[2].Value), 1; if (((Get-Date) - $f7).TotalDays -gt 365) { $avi.Add("Instalador_Basico.ps1: el respaldo fijo de 7-Zip ($($m7.Value)) tiene más de 12 meses; actualiza la URL y su SHA-256.") } } catch { } }
}

# 5c) La DLL precompilada del Ejecutor debe corresponder al C# actual de Ejecutor.ps1 (si no, la app cargaría código viejo)
$ejps = Join-Path $dir 'Ejecutor.ps1'; $dllEj = Join-Path $dir 'Recursos\Nit.Ejecutor.dll'; $shaEj = Join-Path $dir 'Recursos\Nit.Ejecutor.src.sha256'
if (Test-Path -LiteralPath $ejps) {
    $mej = [regex]::Match((Get-Content -LiteralPath $ejps -Raw -Encoding UTF8), "(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@")
    if ($mej.Success) {
        $hej = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes(($mej.Groups[1].Value -replace "`r`n", "`n")))).Replace('-', '')
        if (-not (Test-Path -LiteralPath $dllEj) -or -not (Test-Path -LiteralPath $shaEj)) { $err.Add('Falta Recursos\Nit.Ejecutor.dll: ejecuta Compilar_Recursos.ps1 (sin ella cada script compila C# al arrancar y tarda minutos en un equipo lento).') }
        elseif ((Get-Content -LiteralPath $shaEj -Raw).Trim() -ne $hej) { $err.Add('Recursos\Nit.Ejecutor.dll no corresponde al C# actual de Ejecutor.ps1: ejecuta Compilar_Recursos.ps1.') }
    }
}

# 6) PSScriptAnalyzer (opcional)
if ($Analizador) {
    if (Get-Module -ListAvailable PSScriptAnalyzer) {
        $reglas = 'PSPossibleIncorrectComparisonWithNull', 'PSPossibleIncorrectUsageOfAssignmentOperator', 'PSPossibleIncorrectUsageOfRedirectionOperator', 'PSUseDeclaredVarsMoreThanAssignments', 'PSAvoidAssignmentToAutomaticVariable', 'PSMisleadingBacktick', 'PSAvoidDefaultValueSwitchParameter'
        foreach ($r in (Invoke-ScriptAnalyzer -Path $dir -Recurse -IncludeRule $reglas)) { $avi.Add("$($r.ScriptName):$($r.Line)  [$($r.RuleName -replace '^PS', '')] $(($r.Message -replace '\s+', ' '))") }
    } else { $avi.Add('PSScriptAnalyzer no está instalado (Install-Module PSScriptAnalyzer -Scope CurrentUser).') }
}

Write-Host "Validación del kit: $($ps1.Count) scripts, $($enDisco.Count) de mantenimiento, $($cat.Count) entradas de catálogo."
foreach ($x in $avi) { Write-Host "  AVISO  $x" -ForegroundColor Yellow }
foreach ($x in $err) { Write-Host "  ERROR  $x" -ForegroundColor Red }
if ($err.Count) { Write-Host "$($err.Count) error(es), $($avi.Count) aviso(s). Corrígelos antes de regenerar la integridad." -ForegroundColor Red; exit 1 }
Write-Host "Sin errores ($($avi.Count) aviso(s)). Si el cambio era intencionado, ejecuta ahora Regenerar_Integridad.ps1." -ForegroundColor Green
exit 0
