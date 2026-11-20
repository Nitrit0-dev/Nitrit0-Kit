# =====================================================================
#  Copia_Drivers.ps1 - Exporta los controladores de terceros del equipo (Nitrit0)
#  Útil antes de formatear: se guardan en Datos\Drivers\<equipo>\ y se pueden reinstalar con pnputil.
#  Parámetro: -Destino "carpeta" (por defecto, dentro del kit). Comprueba el espacio libre antes de copiar.
# =====================================================================
[CmdletBinding()]
param([string]$Destino)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
Assert-Admin 'exportar los controladores (sin administrador Windows no los lista)'
if (-not $Destino) { $Destino = Join-Path (Get-KitDatos) "Drivers\$($env:COMPUTERNAME)" }
New-Item -ItemType Directory -Force $Destino | Out-Null
Write-Output "  $($E.Lupa) Contando controladores de terceros…"
$drv = @(Get-WindowsDriver -Online -ErrorAction SilentlyContinue)
if (-not $drv.Count) { Exit-Kit 'Error' 'Windows no ha listado ningún controlador de terceros: no se puede exportar (¿modo seguro o servicio de instalación dañado?).' }
$mb = [math]::Round((($drv | ForEach-Object { try { (Get-ChildItem (Split-Path $_.OriginalFileName) -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum } catch { 0 } } | Measure-Object -Sum).Sum) / 1MB)
Write-Output "  $($E.Info) $($drv.Count) controladores (≈ $mb MB). Destino: $Destino"
try { $libre = (New-Object IO.DriveInfo((Split-Path $Destino -Qualifier))).AvailableFreeSpace / 1MB; if ($libre -lt ($mb * 1.2 + 200)) { Write-Output "  $($E.Error) No hay espacio suficiente en el destino ($([int]$libre) MB libres)."; exit 1 } } catch { }
Write-Output "  $($E.Reloj) Exportando (máx. 20 min)…"
$r = Invoke-Proceso 'pnputil.exe' "/export-driver * `"$Destino`"" 1200 'Exportación de controladores' 20
if ($r.Codigo -eq 0) { $n = (Get-ChildItem $Destino -Directory -ErrorAction SilentlyContinue).Count; Write-Output "  $($E.OK) Exportados $n paquetes en $Destino"; Write-Output "  Para reinstalar: pnputil /add-driver `"$Destino\*.inf`" /subdirs /install"; Write-Log "Drivers exportados a $Destino ($n)" }
else { Write-Output "  $($E.Error) pnputil terminó con código $($r.Codigo)$(if ($r.TiempoAgotado) { ' (tiempo agotado)' })."; Write-Log "Exportación de drivers falló ($($r.Codigo))" 'ERROR'; exit 1 }
