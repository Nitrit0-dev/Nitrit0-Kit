# =====================================================================
#  Optimizar_Unidades.ps1 - TRIM en los SSD y desfragmentar solo los discos duros mecánicos (Nitrit0)
#  Distingue cada unidad: en un SSD lanza TRIM (avisa al disco de qué bloques están libres; no se desfragmenta nunca);
#  en un disco duro mecánico mide la fragmentación y solo desfragmenta si pasa del 10 %. Las unidades de tipo desconocido
#  (virtuales, USB, tarjetas) se saltan. No toca datos: es el mantenimiento que Windows hace solo, adelantado.
#  Parámetro: -SoloAnalizar (dice qué haría con cada unidad y no hace nada)
# =====================================================================
[CmdletBinding()]
param([switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
$esAdmin = Test-EsAdmin
if (-not $esAdmin) { Write-Output "$($E.Aviso) Hace falta administrador para optimizar unidades. Ábrelo desde el kit."; exit 1 }

$plan = New-Object Collections.Generic.List[object]
foreach ($v in @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.FileSystem -eq 'NTFS' } | Sort-Object DriveLetter)) {
    $tipo = 'Desconocido'; $bus = ''
    try { $disco = (Get-Partition -DriveLetter $v.DriveLetter -ErrorAction Stop).DiskNumber; $pd = Get-PhysicalDisk -ErrorAction Stop | Where-Object { [int]$_.DeviceId -eq $disco } | Select-Object -First 1; if ($pd) { $tipo = [string]$pd.MediaType; $bus = [string]$pd.BusType } } catch { }
    $plan.Add([pscustomobject]@{ Letra = [string]$v.DriveLetter; Tipo = $tipo; Bus = $bus; Etiqueta = [string]$v.FileSystemLabel; Tam = [int64]$v.Size })
}
if (-not $plan.Count) { Write-Output "$($E.Info) No hay unidades NTFS fijas que optimizar."; return }
Write-Output "  $($E.Lupa) Unidades:"
foreach ($u in $plan) {
    $acc = switch ($u.Tipo) { 'SSD' { 'TRIM (SSD)' } 'HDD' { 'medir fragmentación y desfragmentar si pasa del 10 %' } default { 'se salta (tipo desconocido)' } }
    Write-Output ("    {0}: {1} {2} · {3:N0} GB · {4}" -f $u.Letra, $u.Tipo, $u.Bus, ($u.Tam / 1GB), $acc)
}
if ($SoloAnalizar) { Write-Output "`n  $($E.Info) Solo análisis: no se ha hecho nada."; return }
$hacer = @($plan | Where-Object { $_.Tipo -in 'SSD', 'HDD' })
if (-not $hacer.Count) { Write-Output "$($E.Aviso) Ninguna unidad es SSD ni HDD reconocidos: no se hace nada."; return }
if (-not (Confirm-Accion ("Se va a optimizar:`n`n" + (($hacer | ForEach-Object { "  · $($_.Letra): ($($_.Tipo))" }) -join "`n") + "`n`nNo toca tus datos. En un disco duro lleno puede tardar un rato. ¿Continuar?"))) { Exit-Kit 'Cancelado' 'Cancelado.' }
foreach ($u in $hacer) {
    if ($u.Tipo -eq 'SSD') {
        Write-Output "  $($E.Reloj) $($u.Letra): TRIM…"
        try { Optimize-Volume -DriveLetter $u.Letra -ReTrim -ErrorAction Stop; Write-Output "  $($E.OK) $($u.Letra): TRIM hecho."; Write-Log "Optimizar_Unidades: TRIM $($u.Letra)" } catch { Write-Output "  $($E.Aviso) $($u.Letra): $($_.Exception.Message)" }
    } else {
        Write-Output "  $($E.Reloj) $($u.Letra): midiendo la fragmentación…"
        $txt = ((Invoke-Proceso (Join-Path $env:SystemRoot 'System32\defrag.exe') ("{0}: /A" -f $u.Letra) 900 "Analizar $($u.Letra)" 60).Salida)
        # idioma-ok: el último «N %» del informe de defrag es el total fragmentado en cualquier idioma; si no lo entiende, no desfragmenta (ver abajo)
        $m = [regex]::Matches([string]$txt, '(\d{1,3})\s*%'); $frag = if ($m.Count) { [int]$m[$m.Count - 1].Groups[1].Value } else { -1 }
        if ($frag -lt 0) { Write-Output "  $($E.Aviso) $($u.Letra): no pude leer la fragmentación; no se desfragmenta."; continue }
        if ($frag -le 10) { Write-Output "  $($E.OK) $($u.Letra): fragmentación $frag %: no hace falta." ; continue }
        Write-Output "  $($E.Reloj) $($u.Letra): fragmentación $frag %: desfragmentando (puede tardar)…"
        $r = Invoke-Proceso (Join-Path $env:SystemRoot 'System32\defrag.exe') ("{0}: /O" -f $u.Letra) 7200 "Desfragmentar $($u.Letra)" 60
        if ($r.Codigo -eq 0) { Write-Output "  $($E.OK) $($u.Letra): desfragmentado."; Write-Log "Optimizar_Unidades: desfragmentado $($u.Letra) ($frag %)" } else { Write-Output "  $($E.Aviso) $($u.Letra): terminó con código $($r.Codigo)." }
    }
}
Write-Output "`n$($E.OK) Optimización terminada."
