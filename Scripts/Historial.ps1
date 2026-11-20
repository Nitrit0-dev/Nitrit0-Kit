# =====================================================================
#  Historial de diagnósticos - Nitrit0
#  Guarda cada diagnóstico en Datos\Historial\<equipo>\ y lo compara con el anterior del mismo equipo.
# =====================================================================

function Get-IdEquipo {
    $s = ''; try { $s = (Get-CimInstance Win32_BIOS).SerialNumber } catch { }
    $n = if ($s -and $s -notmatch 'O\.E\.M|Default|None|System Serial') { "$env:COMPUTERNAME-$s" } else { $env:COMPUTERNAME }
    ($n -replace '[^\w\-\.]+', '_')
}

# $resultados: hashtable Id -> @{ Nombre; Estado; Resumen; Metricas }
function Save-Historial($resultados, [string]$modo, $ficha, [double]$seg) {
    try {
        $dir = Join-Path (Get-BaseTrabajo) "Historial\$(Get-IdEquipo)"; New-Item -ItemType Directory -Force $dir | Out-Null
        $pruebas = @(); foreach ($id in $resultados.Keys) { $r = $resultados[$id]; $pruebas += [pscustomobject]@{ Id = $id; Nombre = $r.Nombre; Estado = $r.Estado; Resumen = $r.Resumen; Metricas = $r.Metricas } }
        $reg = [pscustomobject]@{ Fecha = (Get-Date).ToString('s'); Equipo = $env:COMPUTERNAME; Modo = $modo; Segundos = [math]::Round($seg); Ficha = $ficha; Pruebas = $pruebas }
        $ruta = Join-Path $dir ((Get-Date -Format 'yyyyMMdd_HHmmss') + '.json')
        $reg | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ruta -Encoding UTF8
        $ruta
    } catch { $null }
}

# Devuelve el diagnóstico guardado anterior (el más reciente distinto del que acabamos de guardar)
function Get-HistorialAnterior([string]$rutaActual) {
    try {
        $dir = Join-Path (Get-BaseTrabajo) "Historial\$(Get-IdEquipo)"
        $f = Get-ChildItem -LiteralPath $dir -Filter *.json -ErrorAction Stop | Where-Object { $_.FullName -ne $rutaActual } | Sort-Object Name -Descending | Select-Object -First 1
        if ($f) { return (Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json) }
    } catch { }
    $null
}

$script:EtiquetasMetricas = [ordered]@{
    BateriaSaludPct = @{ T = 'Salud de la batería'; U = '%'; Peor = 'baja' }
    BateriaCiclos = @{ T = 'Ciclos de la batería'; U = ''; Peor = 'sube' }
    DesgastePct = @{ T = 'Desgaste del disco'; U = '%'; Peor = 'sube' }
    SmartDesgastePct = @{ T = 'Desgaste SMART'; U = '%'; Peor = 'sube' }
    SmartReasignados = @{ T = 'Sectores reasignados'; U = ''; Peor = 'sube' }
    SmartPendientes = @{ T = 'Sectores pendientes'; U = ''; Peor = 'sube' }
    SmartErroresMedio = @{ T = 'Errores de medio (NVMe)'; U = ''; Peor = 'sube' }
    SmartApagadosInesperados = @{ T = 'Apagados inesperados (disco)'; U = ''; Peor = 'sube' }
    LibreCPct = @{ T = 'Espacio libre en C:'; U = '%'; Peor = 'baja' }
    TempCpuC = @{ T = 'Temperatura CPU en reposo'; U = ' °C'; Peor = 'sube' }
    TempCpuMaxCargaC = @{ T = 'Temperatura CPU bajo carga'; U = ' °C'; Peor = 'sube' }
    TempDiscoMaxC = @{ T = 'Temperatura máx. de disco'; U = ' °C'; Peor = 'sube' }
    Errores7d = @{ T = 'Errores del sistema (7 días)'; U = ''; Peor = 'sube' }
    Pantallazos30d = @{ T = 'Pantallazos azules (30 días)'; U = ''; Peor = 'sube' }
    ErroresDisco30d = @{ T = 'Errores de disco (30 días)'; U = ''; Peor = 'sube' }
    ApagadosInesperados30d = @{ T = 'Apagados inesperados (30 días)'; U = ''; Peor = 'sube' }
    MemUsoPct = @{ T = 'Uso de RAM en reposo'; U = '%'; Peor = 'sube' }
}

# Compara dos diagnósticos. $actual: hashtable Id->@{Nombre;Estado;Metricas}; $anterior: objeto del JSON
function Get-Comparacion($actual, $anterior) {
    $orden = @{ OK = 0; Info = 0; Aviso = 1; Fallo = 2 }
    $empeoran = @(); $mejoran = @(); $metr = @(); $nuevas = @()
    $ant = @{}; foreach ($p in @($anterior.Pruebas)) { $ant[$p.Id] = $p }
    foreach ($id in $actual.Keys) {
        $a = $actual[$id]; $b = $ant[$id]
        if (-not $b) { $nuevas += $a.Nombre; continue }
        if ($orden[$a.Estado] -gt $orden[$b.Estado]) { $empeoran += "$($a.Nombre): $($b.Estado) → $($a.Estado)" }
        elseif ($orden[$a.Estado] -lt $orden[$b.Estado]) { $mejoran += "$($a.Nombre): $($b.Estado) → $($a.Estado)" }
        foreach ($clave in $script:EtiquetasMetricas.Keys) {
            $va = $a.Metricas.$clave; $vb = $b.Metricas.$clave
            if ($null -ne $va -and $null -ne $vb -and "$va" -ne "$vb" -and "$va" -match '^-?[\d\.,]+$' -and "$vb" -match '^-?[\d\.,]+$') {
                $et = $script:EtiquetasMetricas[$clave]; $d = [double]$va - [double]$vb
                $peor = ($et.Peor -eq 'sube' -and $d -gt 0) -or ($et.Peor -eq 'baja' -and $d -lt 0)
                $metr += [pscustomobject]@{ Texto = ("{0}: {1}{3} → {2}{3}" -f $et.T, $vb, $va, $et.U); Peor = $peor; Delta = $d }
            }
        }
    }
    $fecha = try { [datetime]$anterior.Fecha } catch { $null }
    $lin = @()
    if ($empeoran) { $lin += 'EMPEORAN:'; $lin += $empeoran | ForEach-Object { "  · $_" } }
    if ($mejoran) { $lin += 'MEJORAN:'; $lin += $mejoran | ForEach-Object { "  · $_" } }
    $mp = @($metr | Where-Object Peor); $mm = @($metr | Where-Object { -not $_.Peor })
    if ($mp) { $lin += 'VALORES QUE HAN IDO A PEOR:'; $lin += $mp | ForEach-Object { "  · $($_.Texto)" } }
    if ($mm) { $lin += 'VALORES QUE HAN IDO A MEJOR:'; $lin += $mm | ForEach-Object { "  · $($_.Texto)" } }
    if ($nuevas) { $lin += 'PRUEBAS NUEVAS (sin dato anterior): ' + ($nuevas -join ', ') }
    $estado = if ($empeoran.Count -or $mp.Count) { 'Aviso' } else { 'Info' }
    $res = if ($empeoran.Count -or $mp.Count) { "$(if ($empeoran.Count -eq 1) { '1 prueba empeora' } else { "$($empeoran.Count) pruebas empeoran" }) y $(if ($mp.Count -eq 1) { '1 valor ha ido' } else { "$($mp.Count) valores han ido" }) a peor desde el diagnóstico del $(if ($fecha) { $fecha.ToString('dd/MM/yyyy') })" }
           elseif ($mejoran.Count -or $mm.Count) { "Sin empeoramientos desde el diagnóstico del $(if ($fecha) { $fecha.ToString('dd/MM/yyyy') }); algunos valores han mejorado" }
           else { "Sin cambios desde el diagnóstico del $(if ($fecha) { $fecha.ToString('dd/MM/yyyy') })" }
    [pscustomobject]@{ Estado = $estado; Resumen = $res; Detalle = ($lin -join "`n"); Fecha = $fecha }
}
