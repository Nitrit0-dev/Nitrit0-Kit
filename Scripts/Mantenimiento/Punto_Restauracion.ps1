# =====================================================================
#  Punto_Restauracion.ps1 - Crea un punto de restauración de Windows antes de tocar nada (Nitrit0)
#  Activa la protección del sistema en C: si estaba desactivada y salta el límite de 1 punto cada 24 h.
#  Parámetro: -Nombre "texto del punto"
# =====================================================================
[CmdletBinding()]
param([string]$Nombre = "Nitrit0 - antes de mantenimiento")
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
Write-Output "  $($E.Lupa) Comprobando la protección del sistema en $env:SystemDrive …"
try {
    Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
    $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $ant = (Get-ItemProperty $k -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
    Set-ItemProperty -Path $k -Name SystemRestorePointCreationFrequency -Value 0 -Type DWord -Force
    Write-Output "  $($E.Reloj) Creando el punto de restauración (puede tardar un minuto)…"
    try { Checkpoint-Computer -Description $Nombre -RestorePointType MODIFY_SETTINGS -ErrorAction Stop } finally {
        if ($null -ne $ant) { Set-ItemProperty -Path $k -Name SystemRestorePointCreationFrequency -Value $ant -Type DWord -Force } else { Remove-ItemProperty -Path $k -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue }
    }
    $p = Get-ComputerRestorePoint | Sort-Object CreationTime -Descending | Select-Object -First 1
    Write-Output "  $($E.OK) Punto creado: «$($p.Description)» ($([Management.ManagementDateTimeConverter]::ToDateTime($p.CreationTime).ToString('dd/MM/yyyy HH:mm')))"
    Write-Log "Punto de restauración creado: $Nombre"
} catch {
    Write-Output "  $($E.Error) No se pudo crear el punto de restauración: $($_.Exception.Message)"
    Write-Output "  $($E.Info) Si la protección del sistema está bloqueada por directiva o el disco es solo de lectura, no es posible."
    Write-Log "Punto de restauración falló: $($_.Exception.Message)" 'ERROR'; exit 1
}
