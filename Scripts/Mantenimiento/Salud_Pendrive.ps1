# =====================================================================
#  Salud_Pendrive.ps1 - Comprueba la unidad donde está el kit (Nitrit0)
#  Espacio libre, sistema de archivos, velocidad real de lectura/escritura, desconexiones registradas
#  en los logs e integridad de los archivos del kit (si existe Datos\Integridad.json).
#  Parámetros: -GenerarIntegridad (calcula y guarda las huellas SHA-256 de Scripts y de los ejecutables de Apps)
#              -Rapido (la comprobación no calcula las huellas de Apps, solo las de Scripts)
#              -Completa (calcula también la huella de los ejecutables pesados de Apps, >20 MB: por USB puede tardar varios minutos)
# =====================================================================
[CmdletBinding()]
param([switch]$GenerarIntegridad, [switch]$Rapido, [switch]$Completa)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
$raiz = Get-KitRaiz; $datos = Get-KitDatos
Write-Output "========================================================"
Write-Output "  $($E.Disco) SALUD DE LA UNIDAD DEL KIT"
Write-Output "========================================================"
Write-Output "  Kit en: $raiz"

# 1) Datos de la unidad
$letra = $raiz.Substring(0, 2)
try {
    $di = New-Object IO.DriveInfo($letra)
    Write-Output ("  Etiqueta: {0}   Sistema de archivos: {1}   Tipo: {2}" -f $di.VolumeLabel, $di.DriveFormat, $di.DriveType)
    Write-Output ("  Espacio: {0:N1} GB libres de {1:N1} GB" -f ($di.AvailableFreeSpace / 1GB), ($di.TotalSize / 1GB))
    if ($di.AvailableFreeSpace -lt 2GB) { Write-Output "  $($E.Aviso) Queda poco espacio libre (menos de 2 GB): las copias y los informes pueden fallar." }
} catch { Write-Output "  $($E.Aviso) No se pudo leer la unidad: $($_.Exception.Message)" }
try {
    $v = Get-Volume -DriveLetter $letra[0] -ErrorAction Stop; $dk = Get-Partition -DriveLetter $letra[0] | Get-Disk
    Write-Output ("  Disco: {0} ({1}), bus {2}, estado {3}/{4}" -f $dk.FriendlyName, $dk.PartitionStyle, $dk.BusType, $v.HealthStatus, $v.OperationalStatus)
} catch { }

# 2) Prueba de velocidad (archivo temporal de 64 MB en Datos)
Write-Output "`n  $($E.Reloj) Prueba de velocidad (64 MB)…"
$tmp = Join-Path $datos 'speedtest.tmp'
try {
    $buf = New-Object byte[] (1MB); (New-Object Random).NextBytes($buf)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $fs = [IO.File]::Open($tmp, 'Create', 'Write', 'None'); for ($i = 0; $i -lt 64; $i++) { $fs.Write($buf, 0, $buf.Length) }; $fs.Flush($true); $fs.Dispose(); $sw.Stop()
    $esc = 64 / [Math]::Max(0.001, $sw.Elapsed.TotalSeconds)
    $sw.Restart(); $fs = [IO.File]::Open($tmp, 'Open', 'Read', 'None'); while ($fs.Read($buf, 0, $buf.Length) -gt 0) { }; $fs.Dispose(); $sw.Stop()
    $lec = 64 / [Math]::Max(0.001, $sw.Elapsed.TotalSeconds)
    Write-Output ("  Escritura: {0:N1} MB/s   Lectura (puede venir de caché): {1:N1} MB/s" -f $esc, $lec)
    if ($esc -lt 8) { Write-Output "  $($E.Aviso) Escritura muy lenta (menos de 8 MB/s): pendrive viejo o puerto USB 2.0. Prueba otro puerto." }
    Write-Log "Salud pendrive: escritura $([math]::Round($esc,1)) MB/s"
} catch { Write-Output "  $($E.Error) Fallo en la prueba de escritura: $($_.Exception.Message)  (¿protegido contra escritura o desconectado?)"; Write-Log "Salud pendrive: fallo de escritura $($_.Exception.Message)" 'ERROR' }
finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }

# 3) Desconexiones registradas
Write-Output "`n  $($E.Lupa) Desconexiones registradas en los logs del kit:"
$logs = Get-ChildItem -LiteralPath (Split-Path (Get-RutaLog)) -Filter 'Kit_*.log' -ErrorAction SilentlyContinue
$ev = @(); foreach ($l in $logs) { $ev += Select-String -LiteralPath $l.FullName -Pattern 'NO accesible|desconectada|no volvió|recuperada|reconectada' -ErrorAction SilentlyContinue }
if ($ev) { $ev | Select-Object -Last 15 | ForEach-Object { Write-Output ("    " + $_.Line) }; Write-Output "  $($E.Aviso) Total de eventos: $($ev.Count). Si se repiten, cambia de puerto/cable o de pendrive." }
else { Write-Output "    $($E.OK) Ninguna." }

# 4) Integridad
$jf = Join-Path $datos 'Integridad.json'
function Get-Huellas { Get-ChildItem -LiteralPath (Join-Path $raiz 'Scripts'), (Join-Path $raiz 'Apps'), (Join-Path $raiz 'App\datos') -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $r = $_.FullName.Substring($raiz.Length + 1); [pscustomobject]@{ R = $r; L = $_.Length; H = $(if (Test-HuellaRequerida $r) { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash } else { '' }) } } }   # SHA-256 de Scripts y de los ejecutables de Apps; el resto, por tamaño
if ($GenerarIntegridad) {
    Write-Output "`n  $($E.Reloj) Calculando huellas (SHA-256 de Scripts y de los ejecutables de Apps)…"
    # Un solo generador de la lista de integridad: el de Get-Huellas no incluía los .exe de las apps ni App\Motor*, y los dejaba sin huella
    $regen = Join-Path $raiz 'Scripts\Regenerar_Integridad.ps1'
    if (Test-Path -LiteralPath $regen) { & $regen | Out-Null }
    else { Get-Huellas | ConvertTo-Json -Compress | Set-Content -LiteralPath $jf -Encoding UTF8 }
    Write-Output "  $($E.OK) Guardado en Datos\Integridad.json"
}
elseif (Test-Path -LiteralPath $jf) {
    Write-Output "`n  $($E.Lupa) Comprobando integridad del kit$(if ($Rapido) { ' (modo rápido: sin huellas de Apps)' } elseif (-not $Completa) { ' (huella de Scripts, App y Nitrit0.exe; los ejecutables de Apps de más de 20 MB, por tamaño: usa -Completa para todo)' })…"
    $ref = Get-Content -LiteralPath $jf -Raw -Encoding UTF8 | ConvertFrom-Json
    $falta = @(); $dif = @()
    foreach ($x in $ref) {
        $p = Join-Path $raiz $x.R
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { $falta += $x; continue }
        if ((Get-Item -LiteralPath $p).Length -ne $x.L) { $dif += $x; continue }
        if ($x.H -and -not ($x.R -like 'Apps\*' -and ($Rapido -or (-not $Completa -and $x.L -gt 20MB))) -and (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne $x.H) { $dif += $x }   # con huella: se comprueba el contenido, no solo el tamaño
    }
    if (-not $falta -and -not $dif) { Write-Output "  $($E.OK) Todos los archivos del kit están, con el tamaño esperado y los scripts y ejecutables con su huella SHA-256 ($($ref.Count))." }
    else { $falta | Select-Object -First 10 | ForEach-Object { Write-Output "    FALTA: $($_.R)" }; $dif | Select-Object -First 10 | ForEach-Object { Write-Output "    MODIFICADO: $($_.R)" }; Write-Output "  $($E.Aviso) $($falta.Count) archivo(s) faltan y $($dif.Count) han cambiado (si actualizaste herramientas es normal: vuelve a generar con -GenerarIntegridad)." }
}
else { Write-Output "`n  $($E.Info) Sin referencia de integridad. Ejecuta el script con -GenerarIntegridad para crearla." }
Write-Output "`n  Listo."
