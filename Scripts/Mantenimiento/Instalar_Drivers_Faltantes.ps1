# =====================================================================
#  Instalar_Drivers_Faltantes.ps1 - Instala de una vez los drivers que faltan (Nitrit0)
#  Busca en el Catálogo de Microsoft Update el driver de TODOS los dispositivos que salen sin driver (código 28 o sin configurar), te los enseña para
#  que marques cuáles instalar y, tras un punto de restauración, descarga cada uno, comprueba que viene de Microsoft con firma válida y lo instala.
#  Es el modo -Faltantes de «Driver desde el Catálogo de Microsoft» con su propia ficha, para lanzarlo desde la «Ficha de drivers».
#  Parámetro: -SoloAnalizar (busca y lista, no descarga ni instala nada)
#  Salida: 0 bien · 1 error · 2 cancelado
# =====================================================================
[CmdletBinding()]
param([switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
$destino = Join-Path $PSScriptRoot 'Instalar_Driver_Catalogo.ps1'
$motivo = Test-ScriptAutorizado $destino
if ($motivo) { Write-Output "$($E.Error) No se ejecuta Instalar_Driver_Catalogo.ps1: $motivo. Ejecuta Regenerar_Integridad.ps1 si lo has cambiado tú."; exit 1 }
$global:LASTEXITCODE = 0
& $destino -Faltantes -SoloAnalizar:$SoloAnalizar
exit $LASTEXITCODE
