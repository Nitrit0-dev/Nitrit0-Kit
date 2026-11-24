# =====================================================================
# Auditoria_Licencias_BitLocker.ps1 (Módulo Senior - Nitrit0_Kit)
# Extrae Clave OEM en BIOS/UEFI, estado de licencia Windows/Office,
# estado de BitLocker y claves de recuperación, TPM 2.0 y Secure Boot.
# =====================================================================

[CmdletBinding()]
param(
    [switch]$Silencioso
)

if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
Assert-Admin 'leer las licencias y las claves de BitLocker'
Write-Log 'Licencias y BitLocker: informe generado en %TEMP% (contiene claves; no se guarda en el pendrive)'
$ErrorActionPreference = "SilentlyContinue"
$InformesDir = Join-Path $env:TEMP "Nitrit0_Cache\Informes"   # claves en claro: nunca en el pendrive
if (-not (Test-Path $InformesDir)) { New-Item -ItemType Directory -Path $InformesDir -Force | Out-Null }

$FechaStr = Get-Date -Format "yyyyMMdd_HHmm"
$Equipo   = $env:COMPUTERNAME
$OutHtml  = Join-Path $InformesDir "Auditoria_Seguridad_y_Claves_${Equipo}_${FechaStr}.html"

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "   AUDITORÍA DE LICENCIAS, BITLOCKER, TPM 2.0 Y BIOS (NITRIT0)   " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# 1. Clave OEM en placa base (MSDM ACPI Table)
$OemKey = (Get-CimInstance -ClassName SoftwareLicensingService).OA3xOriginalProductKey
if ([string]::IsNullOrWhiteSpace($OemKey)) { $OemKey = "No grabada en BIOS/UEFI (Licencia Digital o Retail)" }

# 2. Estado de activación de Windows
$WinLic = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f'" | Select-Object -First 1   # con -Filter tarda segundos en vez de minutos
$EstadoLic = switch ($WinLic.LicenseStatus) {
    1 { "Activado permanentemente / Con licencia" }
    2 { "En periodo de gracia (OOBGrace)" }
    3 { "En periodo de gracia adicional (OOTGrace)" }
    4 { "No original (NonGenuineGrace)" }
    5 { "Notificación (Sin activar)" }
    default { "Desconocido" }
}

# 3. Estado de BitLocker y Recuperación
$BitLockerInfo = @()
$ErrorBL = $null
try { $Volumes = Get-BitLockerVolume -ErrorAction Stop } catch { $Volumes = $null; $ErrorBL = $_.Exception.Message }
if ($Volumes) {
    foreach ($v in $Volumes) {
        $RecKey = ($v.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }).RecoveryPassword
        $BitLockerInfo += [PSCustomObject]@{
            Unidad     = $v.MountPoint
            Estado     = $v.VolumeStatus
            Proteccion = $v.ProtectionStatus
            Porcentaje = "$($v.EncryptionPercentage)%"
            ClaveRecup = if ($RecKey) { $RecKey } else { "Sin clave numérica expuesta / Desactivado" }
        }
    }
}

# 4. TPM y Secure Boot
$Tpm = Get-Tpm -ErrorAction SilentlyContinue
$SecureBoot = try { if (Confirm-SecureBootUEFI) { "Habilitado (UEFI)" } else { "Deshabilitado" } } catch { "No compatible / Modo Legacy BIOS" }

$FilasBitLocker = if ($BitLockerInfo.Count -gt 0) {
    ($BitLockerInfo | ForEach-Object {
        $colorKey = if ($_.Proteccion -eq 'On') { "#f59e0b" } else { "#94a3b8" }
        "<tr><td><b>$($_.Unidad)</b></td><td>$($_.Estado)</td><td>$($_.Proteccion)</td><td>$($_.Porcentaje)</td><td style='font-family:Consolas;color:$colorKey;font-weight:bold;'>$($_.ClaveRecup)</td></tr>"
    }) -join "`n"
} elseif ($ErrorBL) {
    # Una consulta fallida no es "no hay cifrado": se dice tal cual
    "<tr><td colspan='5'>No se pudo consultar BitLocker ($([System.Net.WebUtility]::HtmlEncode($ErrorBL))). No se puede afirmar si hay cifrado: compruébalo a mano.</td></tr>"
} else {
    "<tr><td colspan='5'>BitLocker no está activo o la edición de Windows es Home sin Device Encryption activo.</td></tr>"
}

$Html = @"
<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<title>Resguardo de Claves y BitLocker - $Equipo</title>
<style>
  body { font-family: 'Segoe UI', sans-serif; margin: 0; background: #0f172a; color: #f8fafc; }
  header { background: #020617; padding: 22px 32px; border-bottom: 2px solid #1e293b; }
  header h1 { margin: 0; font-size: 21px; color: #38bdf8; }
  .container { max-width: 1000px; margin: 24px auto; padding: 0 24px; }
  .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 18px; margin-bottom: 24px; }
  .card { background: #1e293b; border-radius: 10px; padding: 20px; border: 1px solid #334155; }
  .card h2 { margin-top: 0; font-size: 16px; color: #38bdf8; border-bottom: 1px solid #334155; padding-bottom: 8px; }
  .kv { margin: 10px 0; font-size: 14px; }
  .kv span { color: #94a3b8; display: inline-block; width: 170px; }
  .key-box { background: #020617; border: 1px dashed #38bdf8; padding: 10px 14px; font-family: Consolas, monospace; font-size: 16px; color: #38bdf8; border-radius: 6px; margin-top: 8px; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; margin-top: 10px; }
  th, td { text-align: left; padding: 10px; border-bottom: 1px solid #334155; }
  th { background: #0f172a; color: #94a3b8; }
</style>
</head>
<body>
<header>
  <h1>KIT NITRIT0 · Resguardo Pre-Intervención (Licencias, OEM, BitLocker y TPM)</h1>
</header>
<div class="container">
  <div class="grid">
    <div class="card">
      <h2>Licencia Windows y Clave OEM en BIOS</h2>
      <div class="kv"><span>Producto:</span> <b>$($WinLic.Name)</b></div>
      <div class="kv"><span>Estado Activación:</span> <b>$EstadoLic</b></div>
      <div class="kv"><span>Final de Clave Activa:</span> <b>XXXXX-XXXXX-XXXXX-XXXXX-$($WinLic.PartialProductKey)</b></div>
      <div class="kv"><span>Clave OEM en Placa (BIOS):</span></div>
      <div class="key-box">$OemKey</div>
    </div>
    <div class="card">
      <h2>Seguridad de Plataforma (TPM / UEFI)</h2>
      <div class="kv"><span>TPM Presente:</span> <b>$($Tpm.TpmPresent)</b></div>
      <div class="kv"><span>TPM Listo (Ready):</span> <b>$($Tpm.TpmReady)</b></div>
      <div class="kv"><span>Arranque Seguro (Secure Boot):</span> <b>$SecureBoot</b></div>
      <div class="kv"><span>Recomendación Taller:</span> <b style="color:#f59e0b;">Suspender BitLocker antes de actualizar BIOS</b></div>
    </div>
  </div>

  <div class="card">
    <h2>Estado de Cifrado BitLocker y Claves de Recuperación de 48 Dígitos</h2>
    <table>
      <thead><tr><th>Unidad</th><th>Estado Volumen</th><th>Protección</th><th>Cifrado</th><th>Clave de Recuperación (Guardar antes de tocar BIOS/Placa)</th></tr></thead>
      <tbody>$FilasBitLocker</tbody>
    </table>
  </div>
</div>
</body>
</html>
"@

[System.IO.File]::WriteAllText($OutHtml, $Html, (New-Object System.Text.UTF8Encoding($true)))
if (-not $Silencioso) { Open-Informe $OutHtml }
Write-Host "Informe generado en la carpeta temporal del equipo (no en el pendrive); se borra solo en una hora. Si lo entregas, guárdalo tú donde quieras." -ForegroundColor Yellow
