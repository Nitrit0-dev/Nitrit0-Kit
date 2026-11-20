# =====================================================================
# Analizador_BSOD_y_Eventos.ps1 (Módulo Senior Forense - Nitrit0_Kit)
# Analiza Minidumps (Pantallazos Azules), Kernel-Power 41, WHEA-Logger
# y errores críticos de disco/NTFS, generando un informe HTML interactivo.
# =====================================================================

[CmdletBinding()]
param(
    [switch]$Silencioso
)

$ErrorActionPreference = "SilentlyContinue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir   = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$ComunPath = Join-Path (Split-Path -Parent $ScriptDir) "Comun.ps1"
if (Test-Path $ComunPath) { . $ComunPath }

$InformesDir = if (Get-Command Get-CarpetaSalida -ErrorAction SilentlyContinue) { Get-CarpetaSalida Informes } else { Join-Path $RootDir "Datos\Informes" }
if (-not (Test-Path $InformesDir)) { New-Item -ItemType Directory -Path $InformesDir -Force | Out-Null }

function Esc($s) { [System.Net.WebUtility]::HtmlEncode([string]$s) }   # los mensajes de eventos pueden traer < > &
$FechaStr = Get-Date -Format "yyyyMMdd_HHmm"
$Equipo   = $env:COMPUTERNAME
$OutHtml  = Join-Path $InformesDir "Forense_BSOD_${Equipo}_${FechaStr}.html"

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "   ANALIZADOR FORENSE DE BSOD, WHEA Y EVENTOS CRÍTICOS (NITRIT0) " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# 1. Analizar carpeta Minidump y MEMORY.DMP
Write-Host "[1/5] Escaneando volcados de memoria (Minidumps)..." -ForegroundColor Yellow
$MinidumpPaths = @("$env:SystemRoot\Minidump", "$env:SystemRoot\LiveKernelReports")
$DumpsEncontrados = @()

# Comprobar si los Minidumps están habilitados en el registro
$CrashCtrl = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl"
$DumpEnabled = $CrashCtrl.CrashDumpEnabled

foreach ($mp in $MinidumpPaths) {
    if (Test-Path $mp) {
        $files = Get-ChildItem -Path $mp -Filter "*.dmp" -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 15
        foreach ($f in $files) {
            # Intentar extraer strings legibles de drivers (.sys) dentro del minidump
            $SysDrivers = @()
            try {
                if ($f.Length -gt 64MB) { throw 'volcado demasiado grande para leerlo entero en memoria' }
                $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
                $ascii = [System.Text.Encoding]::ASCII.GetString($bytes)
                $uni   = [System.Text.Encoding]::Unicode.GetString($bytes)
                $matchesSys = [regex]::Matches("$ascii $uni", '[a-zA-Z0-9_\-]{3,28}\.sys')
                $SysDrivers = $matchesSys | ForEach-Object { $_.Value.ToLower() } | Where-Object {
                    $_ -notmatch '^(ntoskrnl|hal|win32k|ntfs|fltmgr|ci|clfs|tm|ksecdd|cng|pcw|Fs_Rec)\.sys$'
                } | Select-Object -Unique -First 6
            } catch {}

            $DumpsEncontrados += [PSCustomObject]@{
                Archivo     = $(if ($mp -like '*\Minidump') { $f.Name } else { "LiveKernelReport: $($f.Name)" })
                EsBsod      = ($mp -like '*\Minidump')   # LiveKernelReports = cuelgue recuperado en vivo, no pantallazo azul
                Ruta        = $f.DirectoryName
                Fecha       = $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                TamanoKB    = [math]::Round($f.Length / 1KB, 1)
                Sospechosos = if ($SysDrivers.Count -gt 0) { ($SysDrivers -join ", ") } elseif ($f.Length -gt 64MB) { "Volcado grande: no analizado" } else { "Núcleo de Windows / Hardware" }
            }
        }
    }
}

# 2. Eventos Kernel-Power 41 y BugCheck 1001
Write-Host "[2/5] Consultando apagados bruscos (Kernel-Power 41) y BugChecks (1001)..." -ForegroundColor Yellow
$EventosCriticos = @()
$FiltroSistema = @{
    LogName = 'System'
    Id      = @(41, 1001, 6008, 7, 11, 15, 51, 55, 129, 153, 4101)
    StartTime = (Get-Date).AddDays(-30)
}
# Esos ID los reutilizan otros proveedores (Kerberos, TPM, HAL...): se filtra por proveedor para no dar falsos avisos de disco
$RawSysEvents = Get-WinEvent -FilterHashtable $FiltroSistema -MaxEvents 400 -ErrorAction SilentlyContinue | Where-Object {
    $pv = $_.ProviderName
    ($_.Id -eq 41 -and $pv -eq 'Microsoft-Windows-Kernel-Power') -or ($_.Id -eq 1001 -and $pv -eq 'Microsoft-Windows-WER-SystemErrorReporting') -or
    ($_.Id -eq 6008 -and $pv -eq 'EventLog') -or ($_.Id -eq 4101 -and $pv -eq 'Display') -or
    ($_.Id -in 7, 11, 15, 51, 55, 129, 153 -and $pv -match '^(disk|Ntfs|Microsoft-Windows-Ntfs|volmgr|stor|nvme|iaStor|atapi)')
} | Select-Object -First 60

foreach ($ev in $RawSysEvents) {
    $Categoria = switch ($ev.Id) {
        41   { "Kernel-Power (Apagado brusco / Corte eléctrico / Reinicio por colapso)" }
        1001 { "WER-BugCheck (Pantallazo Azul BSOD registrado)" }
        6008 { "EventLog (El apagado anterior del sistema fue inesperado)" }
        4101 { "Display (El controlador de pantalla dejó de responder - TDR GPU)" }
        129  { "StorAHCI/NVMe (Reinicio del bus de disco - Posible congelación SSD)" }
        153  { "Disk (Operación de E/S reintentada en bloque lógico)" }
        default { "Disco / Almacenamiento / NTFS (ID $($ev.Id))" }
    }
    $EventosCriticos += [PSCustomObject]@{
        Fecha     = $ev.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
        ID        = $ev.Id
        Origen    = $ev.ProviderName
        Categoria = $Categoria
        Mensaje   = ($ev.Message -replace "\r\n", " " -replace "\s+", " ")
    }
}

# 3. Errores de Hardware Físico (WHEA-Logger)
Write-Host "[3/5] Analizando bus de hardware físico (WHEA-Logger: CPU, PCIe, RAM, NVMe)..." -ForegroundColor Yellow
$EventosWHEA = @()
$RawWhea = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = (Get-Date).AddDays(-60) } -MaxEvents 30 -ErrorAction SilentlyContinue
foreach ($w in $RawWhea) {
    $EventosWHEA += [PSCustomObject]@{
        Fecha   = $w.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
        ID      = $w.Id
        Nivel   = $w.LevelDisplayName
        Grave   = ($w.Level -in 1, 2)   # 1 crítico, 2 error; los avisos (3) son errores ya corregidos por el hardware
        Mensaje = ($w.Message -replace "\r\n", " ")
    }
}

# 4. Aplicaciones que más crashean (Application Error 1000 & Application Hang 1002)
Write-Host "[4/5] Recopilando cuelgues de aplicaciones (ID 1000 / 1002)..." -ForegroundColor Yellow
$AppCrashes = @()
$RawApps = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = @(1000, 1002); StartTime = (Get-Date).AddDays(-15) } -MaxEvents 25 -ErrorAction SilentlyContinue
foreach ($a in $RawApps) {
    $AppCrashes += [PSCustomObject]@{
        Fecha   = $a.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
        ID      = $a.Id
        Tipo    = if ($a.Id -eq 1000) { "Crash (1000)" } else { "Cuelgue / Hang (1002)" }
        Detalle = ($a.Message -split "`n")[0..2] -join " | "
    }
}

# 5. Generar Informe HTML
Write-Host "[5/5] Generando informe forense en $OutHtml ..." -ForegroundColor Green

$VeredictoColor = "#10b981"
$VeredictoTexto = "ESTABLE: No se detectan pantallazos azules recientes ni fallos WHEA de hardware."
$nBsod = @($DumpsEncontrados | Where-Object { $_.EsBsod }).Count; $nLive = $DumpsEncontrados.Count - $nBsod
$nWheaGraves = @($EventosWHEA | Where-Object { $_.Grave }).Count
if ($nWheaGraves -gt 0 -or $nBsod -gt 0) {
    $VeredictoColor = "#ef4444"
    $VeredictoTexto = "ATENCIÓN CRÍTICA: Se han detectado $nBsod volcados de pantallazo azul (BSOD) y $nWheaGraves errores físicos WHEA."
} elseif ($EventosCriticos.Count -gt 3 -or $EventosWHEA.Count -gt 0 -or $nLive -gt 0) {
    $VeredictoColor = "#f59e0b"
    $VeredictoTexto = "PRECAUCIÓN: $($EventosCriticos.Count) eventos críticos del sistema en 30 días, $($EventosWHEA.Count) avisos WHEA (errores corregidos) y $nLive informes de cuelgue recuperado (LiveKernelReports). Sin pantallazos azules."
}

$FilasDumps = if ($DumpsEncontrados.Count -gt 0) {
    ($DumpsEncontrados | ForEach-Object {
        "<tr><td><b>$($_.Fecha)</b></td><td>$($_.Archivo)</td><td>$($_.TamanoKB) KB</td><td><span class='badge-warn'>$(Esc $_.Sospechosos)</span></td></tr>"
    }) -join "`n"
} else {
    "<tr><td colspan='4' style='text-align:center;color:#64748b;'>No se encontraron archivos .dmp en $env:SystemRoot\Minidump ni en LiveKernelReports</td></tr>"
}

$FilasWHEA = if ($EventosWHEA.Count -gt 0) {
    ($EventosWHEA | ForEach-Object {
        "<tr><td>$($_.Fecha)</td><td><b>WHEA ID $($_.ID)</b></td><td>$($_.Nivel)</td><td>$(Esc $_.Mensaje)</td></tr>"
    }) -join "`n"
} else {
    "<tr><td colspan='4' style='text-align:center;color:#10b981;'>0 errores de hardware físico (WHEA-Logger limpio en los últimos 60 días)</td></tr>"
}

$FilasSys = if ($EventosCriticos.Count -gt 0) {
    ($EventosCriticos | Select-Object -First 25 | ForEach-Object {
        "<tr><td>$($_.Fecha)</td><td><b>ID $($_.ID)</b></td><td>$($_.Categoria)</td><td style='font-size:12px;'>$(Esc $_.Mensaje)</td></tr>"
    }) -join "`n"
} else {
    "<tr><td colspan='4' style='text-align:center;color:#10b981;'>Sin eventos críticos de apagado, disco o GPU en los últimos 30 días.</td></tr>"
}

$FilasApps = if ($AppCrashes.Count -gt 0) {
    ($AppCrashes | Select-Object -First 15 | ForEach-Object {
        "<tr><td>$($_.Fecha)</td><td><b>$($_.Tipo)</b></td><td style='font-size:12px;'>$(Esc $_.Detalle)</td></tr>"
    }) -join "`n"
} else {
    "<tr><td colspan='3' style='text-align:center;color:#64748b;'>Sin cierres inesperados de programas recientes.</td></tr>"
}

$HtmlContent = @"
<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<title>Informe Forense BSOD y Eventos - $Equipo</title>
<style>
  body { font-family: 'Segoe UI', system-ui, sans-serif; margin: 0; background: #0f172a; color: #e2e8f0; }
  header { background: #020617; padding: 24px 32px; border-bottom: 2px solid #1e293b; display:flex; justify-content:space-between; align-items:center; }
  header h1 { margin: 0; font-size: 22px; color: #38bdf8; }
  header p { margin: 4px 0 0; color: #94a3b8; font-size: 13px; }
  .container { max-width: 1200px; margin: 24px auto; padding: 0 24px; }
  .veredicto { padding: 16px 20px; border-radius: 10px; background: #1e293b; border-left: 6px solid $VeredictoColor; margin-bottom: 24px; font-weight: 600; font-size: 15px; }
  .card { background: #1e293b; border-radius: 10px; padding: 20px; margin-bottom: 24px; box-shadow: 0 4px 12px rgba(0,0,0,0.25); }
  .card h2 { margin-top: 0; font-size: 17px; color: #f8fafc; border-bottom: 1px solid #334155; padding-bottom: 10px; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; }
  th, td { text-align: left; padding: 10px 12px; border-bottom: 1px solid #334155; vertical-align: top; }
  th { background: #0f172a; color: #94a3b8; font-weight: 600; }
  tr:hover { background: #26334d; }
  .badge-warn { background: #7c2d12; color: #fed7aa; padding: 3px 8px; border-radius: 6px; font-family: Consolas, monospace; font-size: 12px; }
</style>
</head>
<body>
<header>
  <div>
    <h1>KIT NITRIT0 · Auditoría Forense de BSOD y Eventos Críticos</h1>
    <p>Equipo: <b>$Equipo</b> | Fecha: $(Get-Date -Format "dd/MM/yyyy HH:mm") | Estado Minidump Registro: $DumpEnabled</p>
  </div>
</header>
<div class="container">
  <div class="veredicto">$VeredictoTexto</div>

  <div class="card">
    <h2>1. Volcados de Memoria (Pantallazos Azules / Minidumps) y Drivers Causantes</h2>
    <table>
      <thead><tr><th>Fecha</th><th>Archivo Dump</th><th>Tamaño</th><th>Drivers de 3ºs en Pila (.sys sospechosos)</th></tr></thead>
      <tbody>$FilasDumps</tbody>
    </table>
  </div>

  <div class="card">
    <h2>2. Errores Físicos de Hardware (WHEA-Logger: CPU, PCIe, RAM, NVMe)</h2>
    <table>
      <thead><tr><th>Fecha</th><th>Evento</th><th>Nivel</th><th>Descripción Técnica</th></tr></thead>
      <tbody>$FilasWHEA</tbody>
    </table>
  </div>

  <div class="card">
    <h2>3. Eventos Críticos de Sistema (Kernel-Power 41, GPU TDR 4101, Cuelgues de Disco 129/153)</h2>
    <table>
      <thead><tr><th>Fecha</th><th>ID</th><th>Categoría Técnica</th><th>Detalle del Evento</th></tr></thead>
      <tbody>$FilasSys</tbody>
    </table>
  </div>

  <div class="card">
    <h2>4. Últimos Cierres Inesperados de Aplicaciones (ID 1000 / 1002)</h2>
    <table>
      <thead><tr><th>Fecha</th><th>Tipo</th><th>Aplicación y Módulo con Fallo</th></tr></thead>
      <tbody>$FilasApps</tbody>
    </table>
  </div>
</div>
</body>
</html>
"@

[System.IO.File]::WriteAllText($OutHtml, $HtmlContent, (New-Object System.Text.UTF8Encoding($true)))
if (-not $Silencioso) { Open-Informe $OutHtml }
Write-Host "Informe Forense generado con éxito: $OutHtml" -ForegroundColor Green
