# Diagnóstico del equipo para la app: usa el MISMO motor que la ventana del lanzador (Motor_Diagnostico.ps1) y el mismo historial.
# Ninguna prueba cambia el equipo. Emite una línea por suceso con el prefijo ##DX## y JSON; la app las pinta en vivo.
# Entradas por entorno: NIT_DX_MODO (Rapido | Completo) y NIT_DX_FICHA (JSON con Cliente, Telefono, Motivo, Notas).
# Opcionales: NIT_DX_IDS (pruebas concretas, separadas por comas) y NIT_DX_SINGUARDAR=1 (no escribe en el historial: se usa para volver a comprobar tras un arreglo).
$modo = if ($env:NIT_DX_MODO -eq 'Completo') { 'Completo' } else { 'Rapido' }
$ids = @(); if ($env:NIT_DX_IDS) { $ids = @($env:NIT_DX_IDS -split ',' | Where-Object { $_ }) }
$ficha = @{ Cliente = ''; Telefono = ''; Motivo = ''; Notas = '' }
if ($env:NIT_DX_FICHA) {
    try { $j = $env:NIT_DX_FICHA | ConvertFrom-Json; foreach ($k in 'Cliente', 'Telefono', 'Motivo', 'Notas') { if ($j.$k) { $ficha[$k] = ([string]$j.$k).Trim() } } } catch { }
}
$global:dirDatos = $Global:NitKit.Datos                       # lo espera Historial.ps1
$rutaMotor = Join-Path $PSScriptRoot 'Motor_Diagnostico.ps1'
. $rutaMotor
. (Join-Path $PSScriptRoot 'Historial.ps1')

function Emitir($o) { Write-Output ('##DX##' + ($o | ConvertTo-Json -Compress -Depth 6)) }

$plan = @($script:Pruebas | Where-Object { ($modo -eq 'Completo' -or $_.Modo -eq 'Rapido') -and (-not $ids -or $_.Id -in $ids) })
$nombres = @{}; foreach ($p in $plan) { $nombres[$p.Id] = $p.Nombre }
Emitir @{ t = 'plan'; modo = $modo; pruebas = @($plan | ForEach-Object { @{ id = $_.Id; grupo = $_.Grupo; nombre = $_.Nombre; seg = $_.Seg } }) }

# Las pruebas corren en un hilo aparte, igual que en la ventana, y dejan sus resultados en una cola
$cola = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
$ctl = [hashtable]::Synchronized(@{ Cancelar = $false })
$rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'STA'; $rs.Open()
$ps = [powershell]::Create(); $ps.Runspace = $rs
[void]$ps.AddScript('param($motor,$modo,$cola,$ctl,$ids) Set-Location $env:TEMP; . $motor; Start-Diagnostico -Modo $modo -Cola $cola -Ctl $ctl -Ids $ids').AddArgument($rutaMotor).AddArgument($modo).AddArgument($cola).AddArgument($ctl).AddArgument($ids)
$hilo = $ps.BeginInvoke()

$res = [ordered]@{}; $t0 = Get-Date; $m = $null; $fin = $false; $completado = $false
while (-not $fin) {
    while ($cola.TryDequeue([ref]$m)) {
        if ($m.Tipo -eq 'Inicio') { Emitir @{ t = 'inicio'; id = $m.Id } }
        elseif ($m.Tipo -eq 'Fin') {
            $res[$m.Id] = @{ Id = [string]$m.Id; Nombre = $nombres[$m.Id]; Estado = [string]$m.Estado; Resumen = [string]$m.Resumen; Detalle = [string]$m.Detalle; Metricas = $m.Metricas }
            Emitir @{ t = 'fin'; id = $m.Id; estado = [string]$m.Estado; resumen = [string]$m.Resumen; detalle = [string]$m.Detalle; metricas = $m.Metricas; seg = $m.Seg }
        }
        elseif ($m.Tipo -eq 'Terminado') { $fin = $true; $completado = $true }
        elseif ($m.Tipo -eq 'Cancelado') { $fin = $true }
    }
    if (-not $fin -and $hilo.IsCompleted -and $cola.IsEmpty) { $fin = $true }   # el hilo murió sin avisar
    if (-not $fin) { Start-Sleep -Milliseconds 150 }
}
try { $ps.Dispose(); $rs.Dispose() } catch { }

$seg = [int]((Get-Date) - $t0).TotalSeconds
$ruta = $null; $cmp = $null
# Si el pendrive parpadeó durante las pruebas, se espera a que vuelva antes de guardar: perder 16 min de diagnóstico es lo peor que puede pasar
if (-not $env:NIT_DX_SINGUARDAR -and -not (Test-KitDisponible)) { Emitir @{ t = 'aviso'; texto = 'Esperando al pendrive para guardar el diagnóstico…' }; [void](Wait-Kit 60) }
$dirDatos = $Global:NitKit.Datos
try {
    if ($completado -and -not $env:NIT_DX_SINGUARDAR) { $ruta = Save-Historial $res $modo $ficha $seg }   # un diagnóstico a medias (el hilo murió) no se guarda como si fuera válido
    if ($ruta) { $ant = Get-HistorialAnterior $ruta; if ($ant) { $c = Get-Comparacion $res $ant; $cmp = @{ estado = $c.Estado; resumen = $c.Resumen; detalle = $c.Detalle } } }
} catch { }
Emitir @{ t = 'terminado'; seg = $seg; historial = $ruta; comparacion = $cmp; interrumpido = (-not $completado)
          fallos = @($res.Values | Where-Object { $_.Estado -eq 'Fallo' }).Count; avisos = @($res.Values | Where-Object { $_.Estado -eq 'Aviso' }).Count }
