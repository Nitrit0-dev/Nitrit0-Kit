# Temperatura de la CPU para el panel «En vivo» de la app. Solo lee; no cambia nada ni escribe en el pendrive.
# Usa LibreHardwareMonitor del kit (Sensores.ps1). Sin administrador o sin el controlador PawnIO no hay temperatura de CPU y se dice por qué.
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
. (Join-Path $PSScriptRoot 'Comun.ps1')
. (Join-Path $PSScriptRoot 'Sensores.ps1')
$raiz = (Split-Path -Parent $PSScriptRoot).TrimEnd('\')
$Global:NitKit = @{ Raiz = $raiz; Datos = (Join-Path $raiz 'Datos') }   # lo mínimo que necesita Test-ScriptAutorizado; sin Initialize-Kit para no tocar el pendrive
$s = Open-Sensores $raiz
$l = Read-Sensores $s
Close-Sensores $s
[pscustomobject]@{
    cpu = $(if ($null -ne $l.CpuTemp) { [int]$l.CpuTemp } else { $null })
    cpuW = $(if ($l.CpuPotenciaW -gt 0) { [double]$l.CpuPotenciaW } else { $null })
    motivo = [string]$l.Motivo
} | ConvertTo-Json -Compress