# =====================================================================
#  Componentes_Kit.ps1 - Piezas opcionales del kit: controlador de sensores PawnIO, smartmontools y LibreHardwareMonitor (Nitrit0)
#  Es la antigua ventana «Componentes» del lanzador, ahora dentro de la app.
#  El controlador PawnIO (firmado, de código abierto) permite leer la temperatura REAL de la CPU, los ventiladores y la potencia.
#  Sin él todo funciona igual, pero la temperatura de la CPU no es fiable. Se instala UNA vez por equipo y solo si tú lo apruebas.
#  Recomendado: quitarlo al terminar en equipos de clientes (esta misma herramienta lo quita).
#  Parámetro: -SoloEstado (muestra el estado y no pregunta ni cambia nada)
# =====================================================================
[CmdletBinding()]
param([Alias('SoloEstado')][switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
$global:dirApps = Join-Path (Get-KitRaiz) 'Apps'; $global:dirDatos = Get-KitDatos   # los usan las funciones del archivo que se carga a continuación
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Componentes.ps1')   # Get-EstadoComponentes e Invoke-Pawnio
$esAdmin = Test-EsAdmin

$e0 = Get-EstadoComponentes
Write-Output "  $($E.Lupa) Estado de los componentes"
Write-Output ("    {0} Controlador de sensores (PawnIO): {1}" -f $(if ($e0.Driver) { $E.OK } else { $E.Info }), $(if ($e0.Driver) { 'instalado' } elseif ($e0.DriverSetup) { 'no instalado (se puede instalar)' } else { 'no instalado y falta Apps\Componentes\PawnIO_setup.exe' }))
Write-Output ("    {0} smartmontools (SMART detallado): {1}" -f $(if ($e0.Smartctl) { $E.OK } else { $E.Aviso }), $(if ($e0.Smartctl) { 'incluido' } else { 'falta en Apps\Disk\smartmontools' }))
Write-Output ("    {0} LibreHardwareMonitor (lectura de sensores): {1}" -f $(if ($e0.Sensores) { $E.OK } else { $E.Aviso }), $(if ($e0.Sensores) { 'incluida' } else { 'falta en Apps\HW Info\LibreHardwareMonitor' }))
Write-Log "Componentes_Kit: driver=$($e0.Driver) smartctl=$($e0.Smartctl) sensores=$($e0.Sensores)"
if ($SoloAnalizar) { return }
if (-not $e0.DriverSetup) { return }
if (-not $esAdmin) { Exit-Kit 'Error' 'Para instalar o quitar el controlador hace falta administrador. Ábrelo desde el kit.' }

if ($e0.Driver) {
    if (Confirm-Accion "El controlador de sensores PawnIO está instalado en este equipo.`n`n¿Lo quito? (Recomendado en equipos de clientes cuando terminas. La temperatura de la CPU dejará de ser fiable.)") {
        [void](Start-OperacionSegura 'Componentes del kit' -SinPuntoRestauracion)
        $r = Invoke-Pawnio 'quitar'
        Write-Output $(if ($r.Ok) { "  $($E.OK) Controlador quitado." } else { "  $($E.Aviso) No se pudo quitar: $($r.Mensaje)" }); Write-Log "Componentes_Kit: quitar PawnIO -> $($r.Ok)"
        if ($r.Ok) { Save-Informativo 'Controlador PawnIO quitado' 'Para volver a instalarlo, abre esta misma herramienta y acepta instalarlo.' } else { exit 1 }
    } else { Exit-Kit 'Cancelado' 'No se cambia nada.' }
} elseif ($e0.Sensores) {
    if (Confirm-Accion "Para medir la temperatura real de la CPU, los ventiladores y la potencia hace falta instalar el controlador de sensores PawnIO (firmado, de código abierto).`n`nSe instala una vez por equipo y se puede quitar desde esta misma herramienta.`nSin él todo funciona igual, pero la temperatura de la CPU no será fiable.`n`n¿Lo instalo ahora?") {
        [void](Start-OperacionSegura 'Componentes del kit' -SinPuntoRestauracion)
        $r = Invoke-Pawnio 'instalar'
        Write-Output $(if ($r.Ok) { "  $($E.OK) Controlador instalado. Ya se puede leer la temperatura real." } else { "  $($E.Aviso) No se pudo instalar: $($r.Mensaje)" }); Write-Log "Componentes_Kit: instalar PawnIO -> $($r.Ok)"
        if ($r.Ok) { Save-Informativo 'Controlador PawnIO instalado' 'Para quitarlo, abre esta misma herramienta y acepta quitarlo (recomendado en equipos de clientes).' } else { exit 1 }
    } else { Exit-Kit 'Cancelado' 'No se instala.' }
}
