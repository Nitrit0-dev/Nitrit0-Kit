# =====================================================================
#  Sello_Equipo.ps1 - Sello de recepción y de entrega de un equipo (Nitrit0)
#  Recepción: antes de empezar a trabajar anota el estado del equipo (números de serie, cuentas y administradores, certificados raíz de confianza,
#  programas instalados). Entrega: al terminar vuelve a anotarlo y dice qué ha cambiado desde la recepción, para poder demostrar qué se hizo
#  y que no hay nada más (cuentas nuevas, certificados raros, hardware distinto).
#  No cambia nada del equipo. El sello se guarda en la carpeta de trabajo del kit (en el pack público, en la carpeta temporal del PC).
#  Parámetro: -Modo Auto (por defecto: si hay recepción sin entrega pregunta) | Recepcion | Entrega
#  Salida: 0 bien · 1 error · 2 cancelado
# =====================================================================
[CmdletBinding()]
param([ValidateSet('Auto', 'Recepcion', 'Entrega')][string]$Modo = 'Auto')
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
$carpeta = Join-Path (Get-BaseTrabajo) 'Sellos'
try { New-Item -ItemType Directory -Force $carpeta | Out-Null } catch { Exit-Kit 'Error' "No se pudo crear la carpeta de sellos: $carpeta" }

function Get-Foto {
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue; $placa = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
    $sis = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue; $so = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $discos = @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue | ForEach-Object { "$(([string]$_.Model).Trim()) | serie $(([string]$_.SerialNumber).Trim()) | $([int]($_.Size / 1GB)) GB" })
    $usuarios = @(try { Get-LocalUser -ErrorAction Stop | ForEach-Object { "$($_.Name)$(if (-not $_.Enabled) { ' (desactivada)' })" } } catch { })
    $admins = @(try { Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop | ForEach-Object { $_.Name } } catch { })
    $certs = @(try { Get-ChildItem Cert:\LocalMachine\Root -ErrorAction Stop | ForEach-Object { "$($_.Thumbprint) | $(($_.Subject -replace '\s+', ' ').Trim())" } } catch { })
    $progs = @(foreach ($r in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*') {
        foreach ($i in @(Get-ItemProperty -Path $r -ErrorAction SilentlyContinue)) { if ($i.DisplayName -and $i.SystemComponent -ne 1 -and -not $i.ParentKeyName) { "$($i.DisplayName) $($i.DisplayVersion)".Trim() } }
    }) | Sort-Object -Unique
    [ordered]@{
        Version = 1; Equipo = $env:COMPUTERNAME; Fecha = (Get-Date).ToString('s')
        Serie = ([string]$bios.SerialNumber).Trim(); Placa = ([string]$placa.SerialNumber).Trim(); Modelo = "$($sis.Manufacturer) $($sis.Model)".Trim()
        MemoriaGB = [int]($sis.TotalPhysicalMemory / 1GB); Windows = "$($so.Caption) $($so.Version)"; Instalado = $(if ($so.InstallDate) { $so.InstallDate.ToString('yyyy-MM-dd') } else { '' })
        Discos = $discos; Usuarios = $usuarios; Administradores = $admins; Certificados = $certs; Programas = $progs
    }
}
# Escribe con Write-Host: la función devuelve solo el número de diferencias
function Compare-Lista([string]$Titulo, [string[]]$Antes, [string[]]$Ahora, [string]$VerbosNuevo = 'Nuevo', [string]$VerbosQuitado = 'Quitado') {
    $nuevos = @($Ahora | Where-Object { $_ -notin $Antes }); $quitados = @($Antes | Where-Object { $_ -notin $Ahora })
    if (-not $nuevos.Count -and -not $quitados.Count) { Write-Host "  $($E.OK) $Titulo`: sin cambios ($($Ahora.Count))."; return 0 }
    Write-Host "  $($E.Info) $Titulo`:"
    foreach ($x in $nuevos) { Write-Host "      + $VerbosNuevo`: $x" }
    foreach ($x in $quitados) { Write-Host "      - $VerbosQuitado`: $x" }
    $nuevos.Count + $quitados.Count
}

# ¿Hay una recepción de este equipo sin entrega posterior?
$previos = @(Get-ChildItem -LiteralPath $carpeta -Filter 'Sello_*_recepcion.json' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "Sello_$($env:COMPUTERNAME -replace '[^\w\-]', '_')_*" } | Sort-Object LastWriteTime -Descending)
$ultima = $previos | Select-Object -First 1
$haceEntrega = $false
if ($Modo -eq 'Entrega') { $haceEntrega = $true }
elseif ($Modo -eq 'Auto' -and $ultima) {
    $haceEntrega = Confirm-Accion "Hay un sello de recepción de este equipo del $($ultima.LastWriteTime.ToString('dd/MM/yyyy HH:mm')).`n`nSí: hacer la ENTREGA ahora (compara el equipo con ese sello).`nNo: crear una RECEPCIÓN nueva." 'Sello del equipo' -Siempre
}
Write-Output "========================================================"
Write-Output "  $($E.Cohete) SELLO DE $(if ($haceEntrega) { 'ENTREGA' } else { 'RECEPCIÓN' })"
Write-Output "========================================================"
Write-Output "  $($E.Lupa) Anotando el estado del equipo…"
$ahora = Get-Foto
$nombre = ($env:COMPUTERNAME -replace '[^\w\-]', '_')
$marca = Get-Date -Format 'yyyyMMdd_HHmmss'

if (-not $haceEntrega) {
    $ruta = Join-Path $carpeta "Sello_${nombre}_${marca}_recepcion.json"
    try { [IO.File]::WriteAllText($ruta, ($ahora | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($true))) } catch { Exit-Kit 'Error' "No se pudo guardar el sello: $($_.Exception.Message)" }
    Write-Output "  $($E.OK) Sello de recepción guardado."
    Write-Output "      Equipo: $($ahora.Modelo)  ·  Serie: $($ahora.Serie)  ·  Windows $($ahora.Windows)"
    Write-Output "      $($ahora.Discos.Count) disco(s), $($ahora.Usuarios.Count) cuenta(s), $($ahora.Administradores.Count) administrador(es), $($ahora.Certificados.Count) certificados raíz, $($ahora.Programas.Count) programas."
    Write-Output "      Archivo: $ruta"
    Write-Output "`n  $($E.Info) Cuando termines el trabajo, vuelve a abrir «Sello de recepción y entrega» y elige ENTREGA: te dirá qué ha cambiado."
    Write-Log "Sello_Equipo: recepción $ruta"
    Exit-Kit 'Ok'
}

if (-not $ultima) { Write-Output "  $($E.Aviso) No hay ningún sello de recepción de este equipo en $carpeta. Haz primero una recepción."; Exit-Kit 'Error' 'Falta el sello de recepción.' }
try { $antes = Get-Content -LiteralPath $ultima.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Exit-Kit 'Error' "No se pudo leer el sello de recepción: $($_.Exception.Message)" }
Write-Output "  $($E.Info) Comparando con la recepción del $(([datetime]$antes.Fecha).ToString('dd/MM/yyyy HH:mm'))…`n"
$cambios = 0
$hw = @()
if ([string]$antes.Serie -ne [string]$ahora.Serie) { $hw += "número de serie de la BIOS: $($antes.Serie) -> $($ahora.Serie)" }
if ([string]$antes.Placa -ne [string]$ahora.Placa) { $hw += "serie de la placa: $($antes.Placa) -> $($ahora.Placa)" }
if ([int]$antes.MemoriaGB -ne [int]$ahora.MemoriaGB) { $hw += "memoria: $($antes.MemoriaGB) GB -> $($ahora.MemoriaGB) GB" }
if ($hw) { Write-Output "  $($E.Aviso) Hardware distinto:"; $hw | ForEach-Object { Write-Output "      · $_" }; $cambios += $hw.Count } else { Write-Output "  $($E.OK) Hardware: mismo número de serie y misma memoria." }
if ([string]$antes.Windows -ne [string]$ahora.Windows) { Write-Output "  $($E.Info) Windows: $($antes.Windows) -> $($ahora.Windows)"; $cambios++ } else { Write-Output "  $($E.OK) Windows: misma versión ($($ahora.Windows))." }
$cambios += Compare-Lista 'Discos' @($antes.Discos) @($ahora.Discos) 'Disco nuevo' 'Disco que ya no está'
$cambios += Compare-Lista 'Cuentas de usuario' @($antes.Usuarios) @($ahora.Usuarios) 'Cuenta nueva' 'Cuenta que ya no existe'
$cambios += Compare-Lista 'Administradores' @($antes.Administradores) @($ahora.Administradores) 'Administrador nuevo' 'Ya no es administrador'
$cambios += Compare-Lista 'Certificados raíz de confianza' @($antes.Certificados) @($ahora.Certificados) 'Certificado nuevo' 'Certificado quitado'
$cambios += Compare-Lista 'Programas instalados' @($antes.Programas) @($ahora.Programas) 'Instalado' 'Desinstalado'
$entrega = Join-Path $carpeta "Sello_${nombre}_${marca}_entrega.json"
try { [IO.File]::WriteAllText($entrega, ($ahora | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($true))) } catch { Write-Output "  $($E.Error) No se pudo guardar el sello de entrega: $($_.Exception.Message)"; Write-Log "Sello_Equipo: no se guardó la entrega: $($_.Exception.Message)" 'ERROR'; Exit-Kit 'Error' 'El sello de entrega no se ha guardado.' }
Write-Output ""
if ($cambios) { Write-Output "  $($E.Info) $cambios diferencia(s) con la recepción. Lo de programas es lo normal si has instalado o quitado algo; revisa especialmente cuentas, administradores y certificados." }
else { Write-Output "  $($E.OK) Nada ha cambiado desde la recepción." }
Write-Output "      Sello de entrega guardado: $entrega"
Write-Log "Sello_Equipo: entrega, $cambios diferencias con $($ultima.Name)"
Exit-Kit 'Ok'
