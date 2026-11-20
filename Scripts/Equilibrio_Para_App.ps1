# Cuello de botella para la app: usa el motor del lanzador (Motor_Equilibrio.ps1, Get-AnalisisConfig). Solo lee y mide; no cambia nada.
# Entrada por entorno: NIT_EQ_PERFIL (General | Juegos | Creacion | Oficina). Emite una línea ##EQ## con el análisis en JSON.
$perfil = if ($env:NIT_EQ_PERFIL -in 'General', 'Juegos', 'Creacion', 'Oficina') { $env:NIT_EQ_PERFIL } else { 'General' }
. (Join-Path $PSScriptRoot 'Motor_Equilibrio.ps1')
Write-Output "  $($Global:E.Lupa) Analizando CPU, gráfica, memoria y disco (perfil $perfil)…"
$a = Get-AnalisisConfig -Perfil $perfil
Write-Output ('##EQ##' + ([pscustomobject]@{
    perfil = $a.Perfil; portatil = $a.Portatil; veredicto = $a.Veredicto; clase = $a.Clase
    pieza = $(if ($a.PiezaDebil) { $a.PiezaDebil.Clave } else { $null })
    componentes = @($a.Componentes | ForEach-Object { @{ clave = $_.Clave; nombre = $_.Nombre; detalle = $_.Detalle; score = $_.Score; gama = $_.Gama; anio = $_.Anio } })
    hallazgos = @($a.Hallazgos | ForEach-Object { @{ id = $_.Id; componente = $_.Componente; estado = $_.Estado; titulo = $_.Titulo; resumen = $_.Resumen; detalle = $_.Detalle; siguiente = $_.Siguiente } })
} | ConvertTo-Json -Compress -Depth 6))
