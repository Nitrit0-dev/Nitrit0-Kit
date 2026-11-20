# =====================================================================
#  Recoger_Resultados_Prueba.ps1 - Recoge de golpe el estado de la VM tras probar el pack público de Nitrit0.
#  SOLO LEE: no cambia nada del kit ni del sistema. Genera un informe de texto para pasárselo a quien corrige.
#  Uso (PowerShell como administrador, para ver los puntos de restauración):
#    powershell.exe -NoProfile -ExecutionPolicy Bypass -File Recoger_Resultados_Prueba.ps1 -Kit C:\Nitrit0_Kit_Publico
#    (opcional) -CopiaDatos "C:\Ruta\Copia_<equipo>_<usuario>_<fecha>"  para revisar la copia de datos del usuario
#  Salida: C:\Resultados\Resultado_Prueba.txt
# =====================================================================
param([string]$Kit = 'C:\Nitrit0_Kit_Publico', [string]$CopiaDatos, [string]$Salida = 'C:\Resultados\Resultado_Prueba.txt')
$ErrorActionPreference = 'Continue'
$out = New-Object Collections.Generic.List[string]
function T([string]$t) { $out.Add(''); $out.Add('=' * 70); $out.Add($t); $out.Add('=' * 70) }
function L([string]$t) { $out.Add($t) }
function Try-Bloque([string]$nombre, [scriptblock]$b) { try { & $b } catch { L "  [ERROR al recoger '$nombre'] $($_.Exception.Message)" } }

$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
T '0. ENTORNO'
L "Fecha: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
L "Equipo: $env:COMPUTERNAME   Usuario: $env:USERNAME   Administrador: $esAdmin"
Try-Bloque 'SO' { $o = Get-CimInstance Win32_OperatingSystem; L "Windows: $($o.Caption) $($o.Version) build $($o.BuildNumber)" }
L "Kit: $Kit  (existe: $(Test-Path -LiteralPath $Kit))"
if (-not (Test-Path -LiteralPath $Kit)) { L 'No se encuentra el kit: indica -Kit con su ruta.' }
if (-not $esAdmin) { L 'AVISO: sin administrador no se pueden leer los puntos de restauración.' }

T '1. EJECUTABLES Y HUELLAS'
Try-Bloque 'huellas' {
    foreach ($f in 'Nitrit0.exe') {
        $p = Join-Path $Kit $f
        if (Test-Path -LiteralPath $p) {
            $h = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
            $ref = Join-Path $Kit 'Herramientas_y_huellas.txt'
            $coincide = if (Test-Path -LiteralPath $ref) { [bool](Select-String -LiteralPath $ref -Pattern $h -SimpleMatch -Quiet) } else { 'sin Herramientas_y_huellas.txt' }
            $firma = (Get-AuthenticodeSignature -LiteralPath $p).Status
            L "$f  SHA-256 $h  | consta en Herramientas_y_huellas.txt: $coincide | firma: $firma"
        } else { L "$f  FALTA" }
    }
}

T '2. CARPETA DATOS DEL KIT (el pack público arranca con solo Ajustes.json, Integridad.json y kit.id)'
Try-Bloque 'Datos' {
    $d = Join-Path $Kit 'Datos'
    Get-ChildItem -LiteralPath $d -Force -ErrorAction Stop | ForEach-Object { L ("  {0,-10} {1}" -f $(if ($_.PSIsContainer) { 'carpeta' } else { "$($_.Length) B" }), $_.Name) }
    $d2 = Join-Path $d 'Informes'
    if (Test-Path -LiteralPath $d2) { L '  Datos\Informes:'; Get-ChildItem -LiteralPath $d2 -Recurse -File | ForEach-Object { L "    $($_.FullName.Substring($d2.Length + 1))" }
        $mal = @(Get-ChildItem -LiteralPath $d2 -Recurse -File | Where-Object { $_.Name -match '^(Bateria|Energia)_' })
        L "  Informes de batería/energía en el pendrive (debe ser 0): $($mal.Count)" }
    L '  Ajustes.json:'; Get-Content -LiteralPath (Join-Path $d 'Ajustes.json') -Raw | ForEach-Object { L "    $($_.Trim())" }
}

T '3. INTEGRIDAD: lo que hay frente a Datos\Integridad.json'
Try-Bloque 'integridad' {
    $jf = Join-Path $Kit 'Datos\Integridad.json'; $ref = Get-Content -LiteralPath $jf -Raw -Encoding UTF8 | ConvertFrom-Json
    $falta = @(); $dif = @(); $conHuella = 0
    foreach ($x in $ref) {
        $p = Join-Path $Kit $x.R
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { $falta += $x.R; continue }
        if ((Get-Item -LiteralPath $p).Length -ne $x.L) { $dif += "$($x.R) (tamaño)"; continue }
        if ($x.H) { $conHuella++; if ((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne $x.H) { $dif += "$($x.R) (huella)" } }
    }
    L "Entradas: $($ref.Count)  con huella: $conHuella  faltan: $($falta.Count)  modificados: $($dif.Count)"
    $falta | Select-Object -First 15 | ForEach-Object { L "  FALTA: $_" }; $dif | Select-Object -First 15 | ForEach-Object { L "  MODIFICADO: $_" }
    $conocidos = @{}; foreach ($x in $ref) { $conocidos[$x.R.ToLower()] = 1 }
    $sobran = @(Get-ChildItem -LiteralPath (Join-Path $Kit 'Scripts') -Recurse -File -Include *.ps1 | Where-Object { -not $conocidos.ContainsKey($_.FullName.Substring($Kit.TrimEnd('\').Length + 1).ToLower()) })
    L "Scripts .ps1 que NO constan en Integridad.json (intrusos o añadidos): $($sobran.Count)"; $sobran | ForEach-Object { L "  $($_.FullName)" }
    $cat = Get-Content -LiteralPath (Join-Path $Kit 'Scripts\Mantenimiento\Catalogo.psd1') -Raw -Encoding UTF8
    $sinFicha = @(Get-ChildItem -LiteralPath (Join-Path $Kit 'Scripts\Mantenimiento') -Filter *.ps1 | Where-Object { $cat -notmatch [regex]::Escape("'$($_.Name)'") })
    L "Scripts de Mantenimiento sin ficha en Catalogo.psd1: $($sinFicha.Count)"; $sinFicha | ForEach-Object { L "  $($_.Name)" }
}

T '4. PUNTOS DE RESTAURACIÓN'
Try-Bloque 'restauración' {
    $pr = @(Get-ComputerRestorePoint -ErrorAction Stop)
    L "Total de puntos: $($pr.Count)"
    $pr | Sort-Object SequenceNumber | ForEach-Object { L ("  #{0}  {1}  {2}" -f $_.SequenceNumber, [Management.ManagementDateTimeConverter]::ToDateTime($_.CreationTime).ToString('yyyy-MM-dd HH:mm:ss'), $_.Description) }
}

T '5. VARIABLES NIT_* (NIT_AUTO / NIT_SIN_PREGUNTAS deben estar vacías salvo en la prueba 3.1)'
foreach ($n in 'NIT_AUTO', 'NIT_SIN_PREGUNTAS') { foreach ($ambito in 'Process', 'User', 'Machine') { L ("  {0,-18} {1,-8} = [{2}]" -f $n, $ambito, [Environment]::GetEnvironmentVariable($n, $ambito)) } }

T '6. CACHÉ TEMPORAL DEL KIT (%TEMP%\Nitrit0_Cache)'
Try-Bloque 'caché' {
    $c = Join-Path $env:TEMP 'Nitrit0_Cache'; L "Ruta: $c"
    foreach ($s in 'Informes', 'Descargas', 'Ejecutor', 'Cambios') {
        $p = Join-Path $c $s
        if (Test-Path -LiteralPath $p) { L "  $s :"; Get-ChildItem -LiteralPath $p -Recurse -File | Select-Object -First 25 | ForEach-Object { L "    $($_.Name)  ($($_.Length) B, $($_.LastWriteTime.ToString('HH:mm:ss')))" } } else { L "  $s : (no existe)" }
    }
    $run = @(Get-ChildItem -LiteralPath (Join-Path $c 'Ejecutor') -Filter 'paso_*.ps1' -ErrorAction SilentlyContinue)
    L "Scripts paso_*.ps1 del antiguo Asistente (debe ser 0): $($run.Count)"
    L "Backup de red:"; Get-ChildItem -LiteralPath (Join-Path $c 'Informes') -Filter 'Backup_Red_*' -ErrorAction SilentlyContinue | ForEach-Object { L "    $($_.Name)  $($_.Length) B" }
}

T '7. REGISTRO DEL KIT (Datos\Logs)'
Try-Bloque 'logs' {
    $dl = Join-Path $Kit 'Datos\Logs'; $dlTemp = Join-Path $env:TEMP 'Nitrit0_Cache\Logs'
    L "  Datos\Logs en el kit existe: $(Test-Path -LiteralPath $dl)   (en el pack PÚBLICO debe ser False: sus registros van a %TEMP%)"
    L "  Registros en %TEMP%\Nitrit0_Cache\Logs: $(@(Get-ChildItem -LiteralPath $dlTemp -File -ErrorAction SilentlyContinue).Count) ficheros"
    foreach ($f in 'Datos\Historial_Diagnosticos.log', 'Datos\Historial', 'Datos\Respaldo') { L "  $f en el kit existe: $(Test-Path -LiteralPath (Join-Path $Kit $f))   (en el pack público debe ser False)" }
    if (-not (Test-Path -LiteralPath $dl)) { $dl = $dlTemp }
    if (-not (Test-Path -LiteralPath $dl)) { L 'No hay registros todavía.' } else {
        $ult = Get-ChildItem -LiteralPath $dl -Filter 'Kit_*.log' | Sort-Object LastWriteTime | Select-Object -Last 1
        if ($ult) {
            L "Último registro: $($ult.Name)"
            L '  Líneas relevantes (bloqueos, firmas, errores, avisos, puntos de restauración):'
            Select-String -LiteralPath $ult.FullName -Pattern 'bloquead|BLOQUEAD|Firmante|Firma no v|\[ERROR\]|\[AVISO\]|restauraci|Operación iniciada' | Select-Object -Last 60 | ForEach-Object { L "    $($_.Line)" }
            L '  Últimas 25 líneas:'; Get-Content -LiteralPath $ult.FullName -Tail 25 | ForEach-Object { L "    $_" }
        }
        $ej = Join-Path $dl 'Ejecuciones'
        if (Test-Path -LiteralPath $ej) { L '  Ejecuciones (últimas 15):'; Get-ChildItem -LiteralPath $ej -File | Sort-Object LastWriteTime | Select-Object -Last 15 | ForEach-Object { L "    $($_.Name)  ($($_.Length) B)" } }
    }
}

T '8. PROGRAMAS INSTALADOS POR EL INSTALADOR (y si AnyDesk arranca con Windows)'
Try-Bloque 'programas' {
    $reg = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    Get-ItemProperty $reg -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'Chrome|Firefox|Brave|WinRAR|7-Zip|VLC|AnyDesk|Office' } | Sort-Object DisplayName | ForEach-Object { L "  $($_.DisplayName)  $($_.DisplayVersion)  [$($_.Publisher)]" }
    $run = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue
    $ad = @($run.PSObject.Properties | Where-Object { $_.Value -match 'AnyDesk' }); L "  AnyDesk en el arranque de Windows (debe ser 0): $($ad.Count)"
    $ad2 = @(Get-Service -Name 'AnyDesk*' -ErrorAction SilentlyContinue); L "  Servicio AnyDesk: $(if ($ad2) { ($ad2 | ForEach-Object { "$($_.Name)=$($_.StartType)" }) -join ', ' } else { 'no instalado' })"
    L "  WinRAR rarreg.key presente (debe ser False en el pack público): $((Test-Path 'C:\Program Files\WinRAR\rarreg.key') -or (Test-Path 'C:\Program Files (x86)\WinRAR\rarreg.key'))"
}

T '9. RED (para la prueba de Cambiar IP)'
Try-Bloque 'red' {
    Get-NetIPInterface -AddressFamily IPv4 | Where-Object { $_.ConnectionState -eq 'Connected' } | ForEach-Object {
        $ip = (Get-NetIPAddress -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object { "$($_.IPAddress)/$($_.PrefixLength)" }) -join ', '
        $gw = (Get-NetRoute -InterfaceIndex $_.InterfaceIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | ForEach-Object { $_.NextHop }) -join ', '
        $dns = (Get-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses -join ', '
        L "  $($_.InterfaceAlias): DHCP=$($_.Dhcp) IP=$ip puerta=$gw DNS=$dns"
    }
    L "  Hay Internet (ping 1.1.1.1): $(Test-Connection 1.1.1.1 -Count 1 -Quiet)"
}

T '10. COPIA DE DATOS DEL USUARIO (solo si indicas -CopiaDatos)'
if ($CopiaDatos) {
    Try-Bloque 'copia' {
        foreach ($s in 'Chrome_Marcadores', 'Edge_Marcadores') {
            $p = Join-Path $CopiaDatos $s
            if (Test-Path -LiteralPath $p) { $f = @(Get-ChildItem -LiteralPath $p -Recurse -File -Force); L "  $s : $(($f | ForEach-Object { $_.Name }) -join ', ')"
                $prohibidos = @($f | Where-Object { $_.Name -match '^(Login Data|Cookies|Cookies-journal|Web Data|Local State|Extension Cookies|Preferences)' }); L "    archivos prohibidos (debe ser 0): $($prohibidos.Count)" }
            else { L "  $s : no existe (¿no tenías ese navegador con perfil?)" }
        }
        $kdbx = @(Get-ChildItem -LiteralPath $CopiaDatos -Recurse -File -Include *.kdbx, *.pst -ErrorAction SilentlyContinue); L "  .kdbx/.pst copiados (informativo): $($kdbx.Count)"
    }
} else { L '  (no indicada)' }

T 'FIN'
New-Item -ItemType Directory -Force (Split-Path $Salida) | Out-Null
[IO.File]::WriteAllText($Salida, ($out -join "`r`n"), (New-Object Text.UTF8Encoding($true)))
Write-Host "Informe guardado en: $Salida ($($out.Count) líneas). Pásalo junto con las capturas." -ForegroundColor Green
