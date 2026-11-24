# =====================================================================
# Script: Optimizar_Rendimiento.ps1 (Ejecución Local - Nitrit0)
# Basado en MemoriayCPUEquipoal100_.ps1 (Arranque Multinúcleo + Paginación Dinámica + Top Procesos)
# =====================================================================

[CmdletBinding()]
param([Alias('Simular')][switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
Write-Output ""
Write-Output "========================================================"
Write-Output "  $($Global:E.Cohete) OPTIMIZADOR DE ARRANQUE, PAGINACIÓN Y CPU (NITRIT0)"
Write-Output "========================================================"
Write-Output ""

if (-not $SoloAnalizar) { Assert-Admin 'cambiar el arranque y la paginación'; [void](Start-OperacionSegura 'Optimizar rendimiento') }
Write-Output ""
# 1. Auditoría rápida de Top 5 Procesos antes de optimizar
Write-Output "--- [1/3] Top 5 Procesos que más RAM consumen actualmente ---"
try {
    $TopProcs = Get-Process -ErrorAction SilentlyContinue | Sort-Object WorkingSet64 -Descending | Select-Object -First 5
    foreach ($p in $TopProcs) {
        $mb = [math]::Round($p.WorkingSet64 / 1MB, 1)
        Write-Output ("  • {0,-25} (PID: {1,-6}) : {2,8} MB" -f $p.ProcessName, $p.Id, $mb)
    }
} catch {}

# 2. Quitar el límite de procesadores (numproc) del arranque si lo hubiera
# Fijar numproc ataba el BCD al número de hilos de hoy (si se activa HyperThreading o se cambia de CPU, quedaba recortado): Windows ya usa todos por defecto.
Write-Output ""
Write-Output "--- [2/3] Procesadores de arranque (BCDEDIT) ---"
try {
    $bcd = @(& bcdedit.exe /enum '{current}' 2>$null)
    if ($LASTEXITCODE -ne 0) { Write-Output "  $($Global:E.Aviso) No se pudo leer la configuración de arranque (hace falta administrador): no se puede decir si hay límite de procesadores." }
    else {
        $hayLimite = [bool]($bcd -match '^\s*numproc\s')   # el nombre del elemento no se traduce # idioma-ok
        if (-not $hayLimite) { Write-Output "  $($Global:E.OK) El arranque no tiene límite de procesadores: ya usa todos los disponibles ($env:NUMBER_OF_PROCESSORS)." }
        elseif ($SoloAnalizar) { Write-Output "  $($Global:E.Info) Modo análisis: el arranque tiene un límite de procesadores (numproc); se quitaría." }
        elseif (Save-Bcd) {
            & (Join-Path $env:SystemRoot 'System32\bcdedit.exe') /deletevalue '{current}' numproc | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Output "  $($Global:E.OK) Quitado el límite de procesadores del arranque (copia guardada: se puede deshacer)." }
            else { Write-Output "  $($Global:E.Aviso) No se pudo quitar el límite de procesadores (código $LASTEXITCODE)." }
        }
    }
} catch {
    Exit-Kit 'Error' "Error al modificar bcdedit: $($_.Exception.Message)"
}

# 3. Configurar Memoria Virtual (Archivo de Paginación Dinámico 1.5x - 3x RAM)
Write-Output ""
Write-Output "--- [3/3] Ajustando Memoria Virtual Dinámica (Pagefile) ---"
try {
    if (-not $SoloAnalizar -and -not (Save-PageFile)) { throw 'no se pudo guardar el estado anterior de la paginación' }
    $computerSystemInfo = Get-CimInstance -ClassName Win32_ComputerSystem
    $totalRamBytes = $computerSystemInfo.TotalPhysicalMemory
    $totalRamGB = [Math]::Round($totalRamBytes / 1GB)
    $totalRamMB = [int]($totalRamBytes / 1MB)

    $initialSizeMB = [int](1.5 * $totalRamMB)
    $maximumSizeMB = [int](3 * $totalRamMB)

    # Tope de seguridad: el archivo de paginación máximo no puede ocupar más del 25 % del espacio libre del disco
    $libreMB = [int]((Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))).Free / 1MB); $tope = [int]($libreMB * 0.25)
    if ($maximumSizeMB -gt $tope) { $maximumSizeMB = [Math]::Max($tope, $totalRamMB); Write-Output "  $($Global:E.Aviso) Máximo limitado a $maximumSizeMB MB para no ocupar más del 25 % del espacio libre." }
    if ($initialSizeMB -gt $maximumSizeMB) { $initialSizeMB = $maximumSizeMB }
    Write-Output "  $($Global:E.Info) RAM física: $totalRamGB GB -> Inicial: $initialSizeMB MB | Máximo: $maximumSizeMB MB"

    if ($SoloAnalizar) { Write-Output "  $($Global:E.Info) Modo análisis: se pondría la paginación de $env:SystemDrive\pagefile.sys en $initialSizeMB-$maximumSizeMB MB (administración automática: $($computerSystemInfo.AutomaticManagedPagefile))." }
    else {
    if ($computerSystemInfo.AutomaticManagedPagefile) {
        $computerSystemInfo.AutomaticManagedPagefile = $false
        Set-CimInstance -InputObject $computerSystemInfo | Out-Null
        Write-Output "  $($Global:E.OK) Administración automática de paginación desactivada."
    }

    $pageFileSetting = Get-CimInstance -ClassName Win32_PageFileSetting | Where-Object { $_.Name -eq "$env:SystemDrive\pagefile.sys" }
    if ($pageFileSetting) {
        $pageFileSetting.InitialSize = $initialSizeMB
        $pageFileSetting.MaximumSize = $maximumSizeMB
        Set-CimInstance -InputObject $pageFileSetting | Out-Null
        Write-Output "  $($Global:E.OK) Archivo $env:SystemDrive\pagefile.sys actualizado correctamente."
    } else {
        New-CimInstance -ClassName Win32_PageFileSetting -Property @{Name="$env:SystemDrive\pagefile.sys"; InitialSize=$initialSizeMB; MaximumSize=$maximumSizeMB} -ErrorAction Stop | Out-Null
        Write-Output "  $($Global:E.OK) Archivo $env:SystemDrive\pagefile.sys creado y dimensionado."
    }
    }
} catch {
    Exit-Kit 'Error' "Error al configurar la memoria virtual: $($_.Exception.Message)"
}

if ($SoloAnalizar) { Exit-Kit 'Ok' 'Modo análisis: no se ha cambiado nada.' }
Write-Output ""
Write-Output "========================================================"
Write-Output "  $($Global:E.OK) OPTIMIZACIÓN COMPLETADA (Requiere reinicio)"
Write-Output "  $($Global:E.Info) Para deshacerlo: Mantenimiento > Deshacer cambios."
Write-Output "========================================================"
