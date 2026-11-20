# =====================================================================
#  Reparar_Arranque_y_WinRE.ps1 - Diagnostica y repara los archivos de arranque y el entorno de recuperación (Nitrit0)
#  HERRAMIENTA TÉCNICA (oculta en el pack público). Para «tras clonar el disco no arranca», «WinRE desactivado o con error al
#  actualizar» o «faltan los archivos de arranque». Comprueba, sin leer texto traducido:
#    · UEFI/GPT o BIOS/MBR, y la partición EFI (o la activa) del disco donde está Windows.
#    · Si el almacén de arranque (BCD) se puede leer.
#    · El entorno de recuperación (WinRE), por ReAgent.xml y comprobando que su partición existe.
#  Después deja elegir (cada cosa por separado): habilitar WinRE (reagentc /enable) y/o reconstruir los archivos de arranque
#  (bcdboot). Antes de tocar nada guarda una copia del BCD y pide una confirmación que ningún modo automático puede aceptar.
#  Parámetros: -SoloAnalizar (solo diagnostica)  -RestaurarBcd "bcd.bak" (repone una copia guardada antes)
#  Salida: 0 bien · 1 error · 2 cancelado
# =====================================================================
[CmdletBinding()]
param([Alias('Simular')][switch]$SoloAnalizar, [string]$RestaurarBcd = '')
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
if (-not $SoloAnalizar) { Assert-Admin 'reparar el arranque y el entorno de recuperación' }
$sys32 = Join-Path $env:SystemRoot 'System32'
$bcdedit = Join-Path $sys32 'bcdedit.exe'; $bcdboot = Join-Path $sys32 'bcdboot.exe'; $reagentc = Join-Path $sys32 'reagentc.exe'; $mountvol = Join-Path $sys32 'mountvol.exe'
$tipoEfi = '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'

# ---------------------------------------------------------------- Reponer una copia del BCD
if ($RestaurarBcd) {
    if (-not (Test-Path -LiteralPath $RestaurarBcd)) { Exit-Kit 'Error' "No encuentro la copia del BCD: $RestaurarBcd" }
    if (-not (Confirm-Accion "Se va a SUSTITUIR el almacén de arranque actual por:`n$RestaurarBcd`n`nSi la copia no es de este equipo y este disco, Windows podría no arrancar.`n`n¿Continuar?" 'Nitrit0 Kit - Restaurar arranque' -Siempre)) { Exit-Kit 'Cancelado' 'Cancelado: no se ha tocado el arranque.' }
    try { $r = Invoke-Proceso $bcdedit ('/import "{0}"' -f $RestaurarBcd) 60 'Restaurar BCD' 20 } catch { Exit-Kit 'Error' "No se pudo restaurar: $($_.Exception.Message)" }
    Write-Log "Reparar_Arranque_y_WinRE: BCD repuesto desde $RestaurarBcd (código $($r.Codigo))"
    if ($r.Codigo -ne 0) { Exit-Kit 'Error' "bcdedit no pudo importar la copia (código $($r.Codigo))." }
    Exit-Kit 'Ok' 'Almacén de arranque repuesto. Reinicia para comprobar que arranca.'
}

# ---------------------------------------------------------------- Diagnóstico de arranque
Write-Output "  $($E.Lupa) Arranque y discos"
$letraSis = $env:SystemDrive.TrimEnd(':')
$pSis = Get-Partition -DriveLetter $letraSis -ErrorAction SilentlyContinue
if (-not $pSis) { Exit-Kit 'Error' "No se puede identificar el disco donde está Windows ($env:SystemDrive)." }
$disco = Get-Disk -Number $pSis.DiskNumber -ErrorAction SilentlyContinue
$gpt = ($disco.PartitionStyle -eq 'GPT')
$partEfi = @(Get-Partition -DiskNumber $pSis.DiskNumber -ErrorAction SilentlyContinue | Where-Object { $_.GptType -ieq $tipoEfi }) | Select-Object -First 1
$uefi = $gpt -and [bool]$partEfi
Write-Output "    $($E.Info) Windows está en el disco $($pSis.DiskNumber) ($($disco.PartitionStyle)) · arranque: $(if ($uefi) { 'UEFI' } elseif ($gpt) { 'GPT sin partición EFI detectada' } else { 'BIOS (MBR)' })"
if ($uefi) { Write-Output "    $($E.OK) Partición EFI: partición $($partEfi.PartitionNumber), $([math]::Round($partEfi.Size / 1MB)) MB" }
elseif ($gpt) { Write-Output "    $($E.Aviso) El disco es GPT pero no tiene partición EFI: así no puede arrancar." }
else { $activa = Get-Partition -DiskNumber $pSis.DiskNumber -ErrorAction SilentlyContinue | Where-Object { $_.IsActive } | Select-Object -First 1; Write-Output "    $(if ($activa) { $E.OK } else { $E.Aviso }) Partición activa: $(if ($activa) { "partición $($activa.PartitionNumber)" } else { 'ninguna marcada como activa' })" }
$rb = Invoke-Proceso $bcdedit '/enum {current}' 30 'Leer BCD' 15
$bcdOk = ($rb.Codigo -eq 0)
Write-Output "    $(if ($bcdOk) { $E.OK } else { $E.Aviso }) Almacén de arranque (BCD): $(if ($bcdOk) { 'se puede leer' } else { "no se puede leer (código $($rb.Codigo))$(if (-not (Test-EsAdmin)) { ' · hace falta administrador' })" })"

# ---------------------------------------------------------------- Diagnóstico de WinRE (ReAgent.xml + partición real; el código de salida de reagentc no distingue habilitado de deshabilitado)
Write-Output "  $($E.Lupa) Entorno de recuperación (WinRE)"
$winre = $false; $detalleRe = 'sin información'
$xmlRe = Join-Path $sys32 'Recovery\ReAgent.xml'
try {
    [xml]$x = Get-Content -LiteralPath $xmlRe -Raw -ErrorAction Stop
    $estado = [string]$x.WindowsRE.InstallState.state; $ruta = [string]$x.WindowsRE.WinreLocation.path
    # El GUID del XML no coincide con el de Get-Partition; el desplazamiento en el disco sí
    $off = 0L; [void][int64]::TryParse([string]$x.WindowsRE.WinreLocation.offset, [ref]$off)
    $particion = $null; if ($off -gt 0) { $particion = Get-Partition -DiskNumber $pSis.DiskNumber -ErrorAction SilentlyContinue | Where-Object { $_.Offset -eq $off } | Select-Object -First 1 }
    $local = Test-Path -LiteralPath (Join-Path $sys32 'Recovery\Winre.wim')
    $winre = ($estado -eq '1') -and $ruta -and ($particion -or $local)
    $detalleRe = if ($estado -ne '1') { 'deshabilitado' } elseif (-not $ruta) { 'habilitado pero sin ubicación registrada' } elseif ($particion) { "habilitado · partición $($particion.PartitionNumber) del disco $($particion.DiskNumber)" } elseif ($local) { 'habilitado · imagen en el propio Windows' } else { 'habilitado en el registro, pero su partición no existe (roto)' }
} catch { $detalleRe = 'no se pudo leer ReAgent.xml' }
Write-Output "    $(if ($winre) { $E.OK } else { $E.Aviso }) WinRE: $detalleRe"
Write-Log "Reparar_Arranque_y_WinRE: análisis (UEFI=$uefi, GPT=$gpt, BCD=$bcdOk, WinRE=$winre)"
if ($SoloAnalizar) { Write-Output "`n  $($E.Info) Solo análisis: no se ha tocado el arranque ni WinRE."; Exit-Kit 'Ok' }

# ---------------------------------------------------------------- Elegir qué hacer
$items = @(
    [pscustomobject]@{ Id = 'winre'; Texto = 'Habilitar el entorno de recuperación (WinRE)'; Detalle = $(if ($winre) { 'Ya está habilitado: solo marcarlo si Windows Update se queja de WinRE.' } else { 'Ejecuta reagentc /enable. Necesita la imagen Winre.wim o su partición de recuperación.' }); Marcado = (-not $winre) }
    [pscustomobject]@{ Id = 'bcdboot'; Texto = 'Reconstruir los archivos de arranque (bcdboot)'; Detalle = 'Vuelve a crear los archivos de arranque desde C:\Windows. Útil tras clonar o si el BCD está roto. Se guarda antes una copia del BCD.'; Marcado = (-not $bcdOk) }
)
$elegidos = Show-Marcables 'Reparar arranque y WinRE' 'HERRAMIENTA TÉCNICA. Marca solo lo necesario; se guarda una copia del arranque antes de actuar.' $items 'Reparar lo marcado'
if ($null -eq $elegidos -or -not $elegidos.Count) { Exit-Kit 'Cancelado' 'No se ha tocado el arranque.' }
$ids = @($elegidos | ForEach-Object { $_.Id })
$lista = (@(if ('bcdboot' -in $ids) { '• reconstruir los archivos de arranque' }; if ('winre' -in $ids) { '• habilitar WinRE' }) -join "`n")
if (-not (Confirm-Accion "VAS A MODIFICAR EL ARRANQUE DE WINDOWS:`n$lista`n`nSe guarda antes una copia del BCD. Un corte de luz durante el proceso puede dejar el equipo sin arrancar.`n`n¿Continuar?" 'Nitrit0 Kit - Confirmación crítica' -Siempre)) { Exit-Kit 'Cancelado' 'Cancelado: no se ha tocado el arranque.' }

# ---------------------------------------------------------------- Hacerlo
$errores = 0
try {
    $dir = Start-OperacionSegura 'Reparar arranque y WinRE'
    $copia = Save-Bcd
    if (-not $copia -and 'bcdboot' -in $ids) { Exit-Kit 'Error' 'Abortado: no se pudo guardar la copia del BCD y sin ella no se reconstruye el arranque.' }
    if ($copia) { Write-Output "  $($E.Info) Para volver atrás:  Reparar_Arranque_y_WinRE.ps1 -RestaurarBcd `"$(Join-Path $dir 'bcd.bak')`"" }

    if ('bcdboot' -in $ids) {
        Write-Output "  $($E.Reloj) Reconstruyendo los archivos de arranque…"
        $montada = $null
        try {
            $parametros = "`"$env:SystemRoot`""
            if ($uefi) {
                $destino = $partEfi.DriveLetter
                if (-not $destino) {   # la partición EFI no tiene letra: se monta con mountvol /S (la del disco de Windows) y se suelta al terminar
                    $usadas = @(Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Name })
                    $libre = @('S', 'T', 'U', 'V', 'W', 'Y', 'Z') | Where-Object { $_ -notin $usadas } | Select-Object -First 1
                    if (-not $libre) { throw 'no hay letra libre para montar la partición EFI' }
                    $rm = Invoke-Proceso $mountvol "${libre}: /S" 30 'Montar partición EFI' 15
                    if ($rm.Codigo -ne 0) { throw "mountvol no pudo montar la partición EFI (código $($rm.Codigo))" }
                    $montada = $libre; $destino = $libre
                }
                $parametros += " /s ${destino}: /f UEFI"
            } elseif (-not $gpt) {
                # BIOS: el BCD va en la partición ACTIVA (a menudo «Reservada del sistema», sin letra), no necesariamente en C:. Sin letra se omite /s y bcdboot usa la del firmware.
                $act = Get-Partition -DiskNumber $pSis.DiskNumber -ErrorAction SilentlyContinue | Where-Object { $_.IsActive } | Select-Object -First 1
                if (-not $act) { $parametros += " /s ${letraSis}: /f BIOS" }
                elseif ($act.DriveLetter) { $parametros += " /s $($act.DriveLetter): /f BIOS" }
                else { $parametros += ' /f BIOS' }
            }
            $r = Invoke-Proceso $bcdboot $parametros 120 'Reconstruir arranque (bcdboot)' 20
            if ($r.Codigo -eq 0) { Write-Output "    $($E.OK) Archivos de arranque reconstruidos."; Write-Log "Reparar_Arranque_y_WinRE: bcdboot $parametros correcto" }
            else { $errores++; Write-Output "    $($E.Error) bcdboot falló (código $($r.Codigo))."; Write-Log "Reparar_Arranque_y_WinRE: bcdboot falló ($($r.Codigo))" }
        } catch { $errores++; Write-Output "    $($E.Error) $($_.Exception.Message)" }
        finally { if ($montada) { [void](Invoke-Proceso $mountvol "${montada}: /D" 30 'Soltar partición EFI' 15) } }
    }
    if ('winre' -in $ids) {
        Write-Output "  $($E.Reloj) Habilitando WinRE…"
        $r = Invoke-Proceso $reagentc '/enable' 90 'Habilitar WinRE' 20
        if ($r.Codigo -eq 0) { Write-Output "    $($E.OK) WinRE habilitado."; Write-Log 'Reparar_Arranque_y_WinRE: reagentc /enable correcto' }
        else { $errores++; Write-Output "    $($E.Error) No se pudo habilitar WinRE (código $($r.Codigo)): comprueba que existe Winre.wim o su partición."; Write-Log "Reparar_Arranque_y_WinRE: reagentc /enable falló ($($r.Codigo))" }
    }
} catch { Exit-Kit 'Error' "La reparación se interrumpió: $($_.Exception.Message)" }
if ($errores) { Exit-Kit 'Error' "Terminado con $errores error(es). Revisa el registro antes de reiniciar." }
Exit-Kit 'Ok' 'Hecho. Reinicia para comprobar que Windows arranca.'
