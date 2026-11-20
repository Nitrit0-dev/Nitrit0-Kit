# =====================================================================
#  Disco_Sucio_y_Reinicios.ps1 - ¿Hay discos marcados como «sucios» o un reinicio pendiente? (Nitrit0)
#  Un disco marcado como sucio (apagado a lo bruto, fallo de disco) obliga a Windows a comprobarlo al arrancar; y un reinicio pendiente
#  (actualizaciones, cambio de nombre, instalaciones) hace fallar instalaciones de drivers, clonados y otras herramientas.
#  SOLO MIRA: no repara ni cambia nada. Dice qué hacer.
# =====================================================================
[CmdletBinding()]
param()
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
$esAdmin = Test-EsAdmin
if (-not $esAdmin) { Write-Output "$($E.Aviso) Hace falta administrador para leer el estado de los discos. Ábrelo desde el kit."; exit 1 }
$problemas = 0

Write-Output "  $($E.Lupa) Discos"
foreach ($v in @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.FileSystem -match 'NTFS|ReFS' } | Sort-Object DriveLetter)) {
    # El dato fiable es la propiedad DirtyBitSet de Windows (no depende del idioma); fsutil queda de respaldo
    $sucio = $false; $conocido = $false; $txt = ''
    try { $w = Get-CimInstance Win32_Volume -Filter ("DriveLetter='{0}:'" -f $v.DriveLetter) -ErrorAction Stop; if ($null -ne $w.DirtyBitSet) { $conocido = $true; $sucio = [bool]$w.DirtyBitSet } } catch { }
    if (-not $conocido) {
        $txt = ((& fsutil.exe dirty query ("{0}:" -f $v.DriveLetter) 2>&1) | Out-String).Trim()
        $limpio = $txt -match '(?i)no contiene errores|no est[aá] sucio|not dirty'
        if ($limpio) { $conocido = $true } elseif ($txt -match '(?i)contiene errores|sucio|dirty') { $conocido = $true; $sucio = $true }
    }
    $limpio = $conocido -and -not $sucio
    if ($sucio) { $problemas++; Write-Output ("    {0} {1}: SUCIO. Windows lo comprobará al reiniciar; si no, ejecuta «chkdsk {1}: /f» (pide reiniciar si es el disco de Windows). Antes copia lo importante." -f $E.Error, "$($v.DriveLetter)") }
    elseif ($limpio) { Write-Output ("    {0} {1}: limpio" -f $E.OK, $v.DriveLetter) }
    else { Write-Output ("    {0} {1}: no se pudo saber ({2})" -f $E.Info, $v.DriveLetter, ($txt -replace '\s+', ' ')) }
}

Write-Output "  $($E.Lupa) Comprobación de disco programada para el próximo arranque"
$be = $null; try { $be = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name BootExecute -ErrorAction Stop).BootExecute } catch { }
$autochk = @($be | Where-Object { $_ -and $_ -match 'autocheck' -and $_ -notmatch 'autocheck autochk \*$' })
if ($autochk.Count) { $problemas++; Write-Output "    $($E.Aviso) Hay una comprobación de disco pendiente: $($autochk -join ' | '). Se hará al reiniciar (puede tardar)." } else { Write-Output "    $($E.OK) Ninguna pendiente" }

Write-Output "  $($E.Lupa) Reinicio pendiente"
$motivos = New-Object Collections.Generic.List[string]
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $motivos.Add('una actualización o componente de Windows') }
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $motivos.Add('Windows Update') }
$pf = $null; try { $pf = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction Stop).PendingFileRenameOperations } catch { }
if ($pf) { $motivos.Add('archivos que se sustituyen al arrancar (instalador o desinstalador)') }
$cn = $null; try { $cn = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -ErrorAction Stop).ComputerName; $pn = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -ErrorAction Stop).ComputerName; if ($cn -ne $pn) { $motivos.Add('un cambio de nombre del equipo') } } catch { }
if ($motivos.Count) { $problemas++; Write-Output "    $($E.Aviso) Pendiente por: $($motivos -join '; '). Reinicia antes de instalar drivers, clonar discos o hacer más cambios." } else { Write-Output "    $($E.OK) No hay reinicio pendiente" }

Write-Output ''
if ($problemas) { Write-Output "$($E.Aviso) $problemas cosa(s) a atender (arriba). No se ha cambiado nada." } else { Write-Output "$($E.OK) Discos limpios y sin reinicios pendientes." }
Write-Log "Disco_Sucio_y_Reinicios: $problemas problema(s)"
