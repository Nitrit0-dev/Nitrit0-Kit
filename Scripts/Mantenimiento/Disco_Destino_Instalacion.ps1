# =====================================================================
#  Disco_Destino_Instalacion.ps1 - Qué disco borraría una instalación silenciosa de Windows (Nitrit0)
#  Rufus (modo silencioso) y los autounattend con disco fijo instalan en el primer disco (el 0) y lo borran
#  ENTERO, con todas sus particiones. Este script lista los discos del equipo, marca cuál sería el 0 y avisa
#  si tiene datos o no es el disco de Windows. SOLO LEE: no cambia ni borra nada.
#  Parámetro: -SinPreguntas (no pregunta nada; este script nunca pide teclado, se admite por coherencia)
# =====================================================================
[CmdletBinding()]
param([switch]$SinPreguntas)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E

$discos = @(Get-Disk -ErrorAction SilentlyContinue | Sort-Object Number)
if (-not $discos) { Write-Output "$($E.Error) No se pudo leer ningún disco (¿falta administrador?)."; Write-Log 'Disco_Destino_Instalacion: sin discos'; exit 1 }

$discoWin = $null; try { $discoWin = (Get-Partition -DriveLetter $env:SystemDrive.TrimEnd(':') -ErrorAction Stop).DiskNumber } catch { }
$primero = $discos[0]
$avisos = 0

foreach ($d in $discos) {
    $parts = @(Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue)
    $conLetra = @($parts | Where-Object { $_.DriveLetter } | ForEach-Object {
        $v = Get-Volume -DriveLetter $_.DriveLetter -ErrorAction SilentlyContinue
        $nombre = if ($v -and $v.FileSystemLabel) { " «$($v.FileSystemLabel)»" } else { '' }
        $usado = if ($v -and $v.Size) { ', ' + [math]::Round(($v.Size - $v.SizeRemaining) / 1GB, 1) + ' GB usados' } else { '' }
        "$($_.DriveLetter):$nombre$usado"
    })
    $etiq = @()
    if ($d.Number -eq $discoWin) { $etiq += 'tiene el Windows actual' }
    if ($d.BusType -eq 'USB') { $etiq += 'USB / extraíble' }
    $tam = [math]::Round($d.Size / 1GB)
    Write-Output "$($E.Disco) Disco $($d.Number): $($d.FriendlyName) · $tam GB · $($d.BusType) · $($d.PartitionStyle) · $($parts.Count) partición(es)$(if ($etiq) { ' · ' + ($etiq -join ', ') })"
    foreach ($c in $conLetra) { Write-Output "      $c" }
}

Write-Output ''
Write-Output "$($E.Aviso) Una instalación silenciosa borraría el DISCO $($primero.Number) ($($primero.FriendlyName), $([math]::Round($primero.Size / 1GB)) GB) entero, con todas sus particiones."
if ($null -eq $discoWin) { $avisos++; Write-Output "$($E.Aviso) No se pudo saber cuál es el disco del Windows actual: no se puede decir si el primero es el del sistema." }
elseif ($primero.Number -ne $discoWin) { $avisos++; Write-Output "$($E.Aviso) Ese disco NO es el del Windows actual (disco $discoWin): probablemente sea un disco de datos." }
if ($primero.BusType -eq 'USB') { $avisos++; Write-Output "$($E.Aviso) El disco $($primero.Number) es USB: puede ser el propio pendrive de arranque." }
if ($discos.Count -gt 1) {
    $avisos++
    Write-Output "$($E.Info) Hay $($discos.Count) discos. Antes de arrancar el instalador silencioso desactiva en la BIOS el puerto SATA/M.2 de los demás o desconecta su cable, y vuelve a activarlos al terminar."
    Write-Output "$($E.Info) En Ventoy, la plantilla autounattend.xml no formatea nada por sí sola: el instalador te deja elegir el disco."
}
else { Write-Output "$($E.OK) Solo hay un disco: no hay riesgo de borrar otro por error (pero sí se pierden todas sus particiones, también las de datos)." }
Write-Output "$($E.OK) Lectura hecha. No se ha cambiado nada."
Write-Log "Disco_Destino_Instalacion: $($discos.Count) disco(s), primero=$($primero.Number), avisos=$avisos"
