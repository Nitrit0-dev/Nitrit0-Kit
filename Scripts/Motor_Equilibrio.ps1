# =====================================================================
#  Motor de Equilibrio (qué pieza frena al resto) - Nitrit0
#  Parte 1: análisis de configuración (RAM, canales, gráfica, CPU, disco, energía).
#  Parte 2: monitor en vivo (mide qué componente se satura bajo tu carga real).
#  Todo con herramientas incluidas en Windows. No modifica nada.
#  Las puntuaciones por componente son ESTIMACIONES orientativas (tabla interna por
#  generación y gama), no benchmarks.
# =====================================================================

$script:RaizKitEq = Split-Path -Parent $PSScriptRoot
if (Test-Path (Join-Path $PSScriptRoot 'Sensores.ps1')) { . (Join-Path $PSScriptRoot 'Sensores.ps1') }

function Get-NombreGama([double]$s, [bool]$cpu = $false) {
    if ($cpu) { if ($s -lt 25) { return 'Básica' } elseif ($s -lt 42) { return 'Media-baja' } elseif ($s -lt 58) { return 'Media' } elseif ($s -lt 72) { return 'Media-alta' } else { return 'Alta' } }
    if ($s -lt 15) { return 'Muy básica' } elseif ($s -lt 30) { return 'Básica' } elseif ($s -lt 45) { return 'Media-baja' } elseif ($s -lt 60) { return 'Media' } elseif ($s -lt 75) { return 'Media-alta' } elseif ($s -lt 88) { return 'Alta' } else { return 'Entusiasta' }
}
function Limitar([double]$v, [double]$min = 3, [double]$max = 100) { [math]::Round([math]::Max($min, [math]::Min($max, $v))) }

# ---------------------------------------------------------------- CPU
function Get-InfoCpu {
    $c = Get-CimInstance Win32_Processor | Select-Object -First 1
    $nombre = ($c.Name + '').Trim()
    $corto = ($nombre -replace '\(R\)|\(TM\)|CPU|@.*', '' -replace '\s+', ' ').Trim()
    $r = [ordered]@{ Nombre = $nombre; Corto = $corto; Nucleos = [int]$c.NumberOfCores; Hilos = [int]$c.NumberOfLogicalProcessors; MHz = [int]$c.MaxClockSpeed; Anio = $null; Gen = ''; Clase = ''; BajoConsumo = $false; Score = $null; Gama = '' }
    $ajuste = 0; $anio = $null
    $mesAnio = @{ 2 = 2011; 3 = 2012; 4 = 2013; 5 = 2015; 6 = 2015; 7 = 2017; 8 = 2018; 9 = 2019; 10 = 2019; 11 = 2020; 12 = 2021; 13 = 2022; 14 = 2023 }
    if ($nombre -match 'Core\(TM\)\s*(i[3579])-(\d{3,5})([A-Z]{0,3})') {
        $fam = $matches[1]; $num = $matches[2]; $suf = $matches[3]
        $gen = if ($num.Length -eq 5) { [int]$num.Substring(0, 2) } elseif ($num.Length -eq 4 -and $num.StartsWith('1')) { [int]$num.Substring(0, 2) } elseif ($num.Length -eq 3) { 1 } else { [int]$num.Substring(0, 1) }
        $anio = if ($gen -eq 1) { 2010 } else { $mesAnio[$gen] }
        $r.Gen = "$gen.ª generación Intel ($fam$(if ($suf) { ', sufijo ' + $suf }))"; $r.Clase = $fam
        $ajuste += @{ i3 = -10; i5 = -2; i7 = 5; i9 = 12 }[$fam]
        if ($suf -match '^(U|Y)') { $ajuste -= 12; $r.BajoConsumo = $true } elseif ($suf -match '^P') { $ajuste -= 4 } elseif ($suf -match '^(HX|HK|K|KF|KS)') { $ajuste += 6 } elseif ($suf -match '^T') { $ajuste -= 8 }
    }
    elseif ($nombre -match 'Core\(TM\)\s*Ultra\s*(\d)\s*(\d)(\d{2})([A-Z]*)') {
        $anio = if ($matches[2] -ge 2) { 2025 } else { 2024 }; $r.Gen = "Core Ultra serie $($matches[2])"; $r.Clase = "Ultra $($matches[1])"
        $ajuste += @{ 3 = -8; 5 = -1; 7 = 6; 9 = 12 }[[int]$matches[1]]
        if ($matches[4] -match '^(U|V)') { $ajuste -= 10; $r.BajoConsumo = $true }
    }
    elseif ($nombre -match 'Ryzen\s*(\d)\s*(?:PRO\s*)?(\d)(\d{3})([A-Z0-9]*)') {
        $serie = [int]$matches[2]; $suf = $matches[4]
        $anio = @{ 1 = 2017; 2 = 2018; 3 = 2019; 4 = 2020; 5 = 2021; 6 = 2022; 7 = 2023; 8 = 2024; 9 = 2024 }[$serie]
        $r.Gen = "Ryzen serie $($serie)000"; $r.Clase = "Ryzen $($matches[1])"
        $ajuste += @{ 3 = -10; 5 = -2; 7 = 5; 9 = 12 }[[int]$matches[1]]
        if ($suf -match '^(U|C)') { $ajuste -= 10; $r.BajoConsumo = $true } elseif ($suf -match '^(HX|HS)') { $ajuste += 4 } elseif ($suf -match '^X3D') { $ajuste += 8 } elseif ($suf -match '^G') { $ajuste -= 3 }
    }
    elseif ($nombre -match 'Ryzen\s*AI\s*(\d)\s*(?:HX\s*)?(\d{3})') { $anio = 2024; $r.Gen = 'Ryzen AI serie 300'; $r.Clase = "Ryzen AI $($matches[1])"; $ajuste += 8 }
    elseif ($nombre -match 'Core\(TM\)\s*([3579])\s+(\d{3})([A-Z]*)') {
        $anio = 2024; $r.Gen = 'Core serie 100/200 (sin «i»)'; $r.Clase = "Core $($matches[1])"
        $ajuste += @{ 3 = -8; 5 = -1; 7 = 6; 9 = 12 }[[int]$matches[1]]
        if ($matches[3] -match '^(U|V)') { $ajuste -= 10; $r.BajoConsumo = $true }
    }
    elseif ($nombre -match 'Snapdragon|Apple|Qualcomm') { $anio = 2024; $r.Gen = 'Arquitectura ARM'; $ajuste += 0 }
    elseif ($nombre -match 'Pentium|Celeron|Atom|N\d{3,4}') { $anio = 2018; $r.Gen = 'Gama de entrada'; $ajuste -= 15 }
    $r.Anio = $anio
    if ($anio) { $s = 20 + ($anio - 2012) * 4.5 + $ajuste } else { $s = 25 + $r.MHz / 120 }
    $s += [math]::Max(-8, [math]::Min(10, ($r.Hilos - 8) * 1.2))
    $r.Score = Limitar $s 5 100; $r.Gama = Get-NombreGama $r.Score $true
    [pscustomobject]$r
}

# ---------------------------------------------------------------- GPU
function Get-InfoGpuUna([string]$nombre, [double]$vramMB) {
    $anio = $null; $score = $null; $tipo = 'Dedicada'; $nota = ''
    $tierN = @{ 10 = 8; 20 = 8; 30 = 15; 40 = 22; 45 = 18; 50 = 28; 55 = 33; 60 = 40; 65 = 46; 70 = 56; 75 = 62; 80 = 74; 90 = 90 }
    $anioN = @{ 6 = 2012; 7 = 2013; 9 = 2015; 10 = 2016; 16 = 2019; 20 = 2018; 30 = 2020; 40 = 2022; 50 = 2025 }
    $moderno = { param($tier, $a) [math]::Round($tier * 0.75 + ($a - 2012) * 2.0) }
    if ($nombre -match 'Intel') {
        $tipo = 'Integrada'
        if ($nombre -match 'Arc.*\b[AB](\d{3})M?\b') { $m = [int]$matches[1]; $tipo = 'Dedicada'; $anio = 2022; $score = switch ($m) { 310 { 10 } 350 { 14 } 370 { 20 } 380 { 22 } 580 { 42 } 750 { 52 } 770 { 60 } default { 30 } }; if ($nombre -match '\bB(\d{3})\b') { $anio = 2024; $score = $(if ($matches[1] -eq '570') { 44 } else { 52 }) } }
        elseif ($nombre -match 'Arc\(TM\) Graphics') { $anio = 2024; $score = 30 }
        elseif ($nombre -match 'Iris.*Xe') { $anio = 2021; $score = 22 }
        elseif ($nombre -match 'Iris') { $anio = 2018; $score = 15 }
        elseif ($nombre -match 'UHD Graphics (\d+)') { $m = [int]$matches[1]; $anio = 2018; $score = if ($m -ge 700) { 18 } elseif ($m -ge 630) { 12 } else { 10 } }
        elseif ($nombre -match 'HD Graphics') { $anio = 2014; $score = 6 }
        else { $anio = 2018; $score = 10 }
    }
    elseif ($nombre -match 'NVIDIA|GeForce|Quadro|RTX|GTX|GT\s*\d') {
        if ($nombre -match '\bMX\s*(\d)(\d{2})\b') {
            $anio = @{ 1 = 2017; 2 = 2019; 3 = 2019; 4 = 2020; 5 = 2022 }[[int]$matches[1]]; $score = @{ 1 = 10; 2 = 13; 3 = 15; 4 = 22; 5 = 26 }[[int]$matches[1]]; $nota = 'serie MX de portátil'
        }
        elseif ($nombre -match '(RTX|GTX|GT)\s*(\d{3,4})') {
            $pref = $matches[1]; $n = [int]$matches[2]; $serie = [math]::Floor($n / 100); $tier = $n % 100
            $a = $anioN[[int]$serie]; $base = $tierN[[int]$tier]; if (-not $base) { $base = 30 }
            if ($a) { $anio = $a; $score = & $moderno $base $a; if ($pref -eq 'RTX') { $score += 6 }; if ($nombre -match '\bTi\b') { $score += 6 }; if ($nombre -match 'SUPER') { $score += 4 } }
            if ($nombre -match 'Laptop|Max-Q|Mobile') { $score -= 8; $nota = 'versión portátil' }
        }
        elseif ($nombre -match 'Quadro|RTX\s*A|\bT\d{3,4}\b') { $anio = 2019; $score = 30; $nota = 'gráfica profesional' }
    }
    elseif ($nombre -match 'Pro\s*W(\d)(\d)\d{2}') {
        $anio = @{ 6 = 2021; 7 = 2022 }[[int]$matches[1]]; if (-not $anio) { $anio = 2021 }
        $tw = @{ 4 = 18; 5 = 28; 6 = 40; 7 = 58; 8 = 74; 9 = 90 }[[int]$matches[2]]; if (-not $tw) { $tw = 30 }
        $score = & $moderno $tw $anio; $nota = 'gráfica profesional AMD'
    }
    elseif ($nombre -match 'WX\s*(\d)(\d{3})') {
        $wx = "WX$($matches[1])$($matches[2])"; $anio = 2017; $score = switch ($wx) { 'WX2100' { 14 } 'WX3100' { 20 } 'WX3200' { $anio = 2019; 24 } 'WX4100' { 24 } 'WX5100' { 40 } 'WX7100' { 55 } 'WX8200' { 62 } 'WX9100' { 66 } default { 28 } }; $nota = 'gráfica profesional AMD'
    }
    elseif ($nombre -match 'Vega\s*(56|64)\b') { $anio = 2017; $score = $(if ($matches[1] -eq '64') { 58 } else { 52 }) }
    elseif ($nombre -match 'Radeon VII') { $anio = 2019; $score = 72 }
    elseif ($nombre -match 'RX\s*(Vega|\d{3,4})\s*(XTX|XT|GRE)?') {
        $t = $matches[1]; $sfx = $matches[2]
        if ($t -match '^\d{3}$') { $tab = @{ '460' = 20; '470' = 30; '480' = 38; '550' = 26; '560' = 30; '570' = 38; '580' = 44; '590' = 50 }; $score = $tab[$t]; $anio = if ($t -match '^4') { 2016 } elseif ($t -eq '590') { 2018 } else { 2017 }; if (-not $score) { $score = 30 } }
        elseif ($t -match '^(\d)(\d)\d{2}$') {
            $serie = [int]$matches[1]; $d = [int]$matches[2]; if ($serie -eq 9) { $d = [int]$t.Substring(2, 1) }
            $a = @{ 5 = 2019; 6 = 2021; 7 = 2023; 9 = 2025 }[$serie]; $tab = @{ 3 = 14; 4 = 20; 5 = 30; 6 = 42; 7 = 58; 8 = 74; 9 = 90 }; $base = $tab[$d]
            if ($a -and $base) { $anio = $a; $score = & $moderno $base $a; if ($sfx -eq 'XT') { $score += 5 } elseif ($sfx -eq 'XTX') { $score += 8 } }
        }
    }
    elseif ($nombre -match 'Radeon.*(Vega \d+|\d{3}M|Graphics)' -and $nombre -notmatch 'Pro W|RX|Radeon VII') {
        $tipo = 'Integrada'; $anio = 2021; $score = 16
        if ($nombre -match '(\d{3})M') { $m = [int]$matches[1]; $anio = 2022; $score = switch ($m) { 610 { 8 } 660 { 20 } 680 { 26 } 740 { 14 } 760 { 24 } 780 { 32 } 880 { 36 } 890 { 40 } default { 20 } } }
        elseif ($nombre -match 'Vega (\d+)') { $anio = 2018; $score = [math]::Min(20, 4 + [int]$matches[1]) }
    }
    elseif ($nombre -match 'Radeon') { $anio = 2016; $score = 25 }
    if ($null -eq $score) { $score = [math]::Min(50, [math]::Max(5, $vramMB / 1024 * 7)); $nota = 'estimada por su memoria de vídeo' }
    [pscustomobject]@{ Nombre = $nombre; Tipo = $tipo; Anio = $anio; Score = (Limitar $score 3 100); Gama = (Get-NombreGama (Limitar $score 3 100)); VRAMMB = [int]$vramMB; Nota = $nota }
}

function Get-InfoGpu {
    $vc = @(Get-CimInstance Win32_VideoController | Where-Object { $_.Name -and $_.Name -notmatch 'Basic Display|Remote|Virtual|Mirror|Parsec|Citrix|Meta|DisplayLink|Hyper-V' })
    $lista = @(foreach ($v in $vc) {
        $ram = [double]$v.AdapterRAM; if ($ram -lt 0 -or $ram -ge 4294967295) { $ram = 4096MB }
        $g = Get-InfoGpuUna ($v.Name.Trim()) ($ram / 1MB)
        $g | Add-Member -NotePropertyName Driver -NotePropertyValue ("{0} ({1:dd/MM/yyyy})" -f $v.DriverVersion, $v.DriverDate) -PassThru
    })
    $ded = @($lista | Where-Object { $_.Tipo -eq 'Dedicada' } | Sort-Object Score -Descending)
    $int = @($lista | Where-Object { $_.Tipo -eq 'Integrada' } | Sort-Object Score -Descending)
    $principal = if ($ded) { $ded[0] } elseif ($int) { $int[0] } else { $null }
    [pscustomobject]@{ Todas = $lista; Principal = $principal; Dedicada = ($ded | Select-Object -First 1); Integrada = ($int | Select-Object -First 1) }
}

# Ancho y versión del enlace PCIe de una gráfica (lectura de propiedades del dispositivo)
function Get-EnlacePcie([string]$nombre) {
    try {
        $dev = Get-PnpDevice -PresentOnly -Class Display -ErrorAction Stop | Where-Object { $_.FriendlyName -eq $nombre } | Select-Object -First 1
        if (-not $dev) { return $null }
        $base = '{3AB22E31-8264-4B4E-9AF5-A8D2D8E33E62}'
        $v = @{}; foreach ($k in 9..12) { $v[$k] = (Get-PnpDeviceProperty -InstanceId $dev.InstanceId -KeyName "$base $k" -ErrorAction SilentlyContinue).Data }
        if ($null -eq $v[10] -or $null -eq $v[12] -or "$($v[10])" -eq '') { return $null }
        [pscustomobject]@{ VelActual = [int]$v[9]; AnchoActual = [int]$v[10]; VelMax = [int]$v[11]; AnchoMax = [int]$v[12] }
    } catch { $null }
}

# ---------------------------------------------------------------- RAM
function Get-InfoRam {
    $mods = @(Get-CimInstance Win32_PhysicalMemory)
    $ranuras = 0; try { $ranuras = [int](Get-CimInstance Win32_PhysicalMemoryArray | Measure-Object MemoryDevices -Sum).Sum } catch { }
    $tipos = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 27 = 'LPDDR'; 28 = 'LPDDR2'; 29 = 'LPDDR3'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5' }
    $total = ($mods | Measure-Object Capacity -Sum).Sum / 1GB
    $tipo = if ($mods) { $t = $tipos[[int]$mods[0].SMBIOSMemoryType]; if ($t) { $t } else { 'desconocido' } } else { 'desconocido' }
    $canales = @(); $conocido = $true
    foreach ($m in $mods) {
        $txt = "$($m.BankLabel) $($m.DeviceLocator)"
        if ($txt -match 'Channel\s*-?\s*([A-D])' -or $txt -match 'DIMM[_ -]?([A-D])\d?\b' -or $txt -match 'CHAN(?:NEL)?\s*([0-3])') { $canales += $matches[1].ToUpper() } else { $conocido = $false }
    }
    $distintos = @($canales | Select-Object -Unique).Count
    $velo = @($mods | ForEach-Object { [int]$_.Speed } | Where-Object { $_ })
    $conf = @($mods | ForEach-Object { [int]$_.ConfiguredClockSpeed } | Where-Object { $_ })
    $caps = @($mods | ForEach-Object { [math]::Round($_.Capacity / 1GB) })
    $soldada = ($tipo -like 'LP*') -or ($mods.Count -gt 0 -and $ranuras -gt 0 -and $mods.Count -eq $ranuras -and ($mods | Where-Object { $_.FormFactor -eq 0 -or $_.FormFactor -eq 13 }).Count -gt 0)
    $r = [ordered]@{
        Modulos = $mods.Count; Ranuras = $ranuras; TotalGB = [math]::Round($total, 1); Tipo = $tipo
        VelNominal = if ($velo) { ($velo | Measure-Object -Minimum).Minimum } else { 0 }
        VelConfig = if ($conf) { ($conf | Measure-Object -Minimum).Minimum } else { 0 }
        Capacidades = $caps; VelocidadesIguales = (@($velo | Select-Object -Unique).Count -le 1); CapacidadesIguales = (@($caps | Select-Object -Unique).Count -le 1)
        CanalesConocidos = $conocido; CanalesDistintos = $distintos; Soldada = $soldada
        Fabricantes = @($mods | ForEach-Object { ($_.Manufacturer + '').Trim() } | Select-Object -Unique)
        Piezas = @($mods | ForEach-Object { ($_.PartNumber + '').Trim() } | Select-Object -Unique)
        Detalle = @($mods | ForEach-Object { "{0}: {1} GB · {2} MHz (configurada {3}) · {4} {5}" -f $_.DeviceLocator, [math]::Round($_.Capacity / 1GB), $_.Speed, $_.ConfiguredClockSpeed, ($_.Manufacturer + '').Trim(), ($_.PartNumber + '').Trim() })
    }
    $doble = $false
    if ($mods.Count -ge 2) { if ($conocido) { $doble = ($distintos -ge 2) } else { $doble = $true } }
    $r.DobleCanal = $doble
    # puntuación estimada
    $base = switch -Regex ($tipo) { '^DDR5' { 75 } '^LPDDR5' { 70 } '^LPDDR4' { 48 } '^DDR4' { 50 } '^LPDDR3' { 32 } '^DDR3' { 25 } default { 40 } }
    $cap = if ($total -ge 32) { 15 } elseif ($total -ge 16) { 10 } elseif ($total -ge 8) { 0 } elseif ($total -ge 4) { -15 } else { -30 }
    $ref = switch -Regex ($tipo) { '^DDR5|LPDDR5' { 5600 } '^DDR4|LPDDR4' { 3200 } '^DDR3|LPDDR3' { 1600 } default { 2400 } }
    $vel = if ($r.VelConfig) { [math]::Max(-10, [math]::Min(8, 10 * ($r.VelConfig / $ref - 0.75))) } else { 0 }
    $can = if ($soldada) { 0 } elseif ($doble) { 8 } elseif ($mods.Count -eq 1) { -12 } else { 0 }
    $r.Score = Limitar ($base + $cap + $vel + $can) 5 100; $r.Gama = Get-NombreGama $r.Score
    [pscustomobject]$r
}

# ---------------------------------------------------------------- Disco
function Get-InfoDisco([bool]$ConPrueba = $true) {
    $r = [ordered]@{ Nombre = '(desconocido)'; Medio = 'Unspecified'; Bus = ''; TamanoGB = 0; LibrePct = $null; Score = 40; Gama = ''; Escritura = $null; Lectura = $null }
    try {
        $disco = Get-Partition -DriveLetter $env:SystemDrive[0] -ErrorAction Stop | Get-Disk -ErrorAction Stop
        $pd = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq "$($disco.Number)" } | Select-Object -First 1
        if (-not $pd) { $pd = Get-PhysicalDisk | Select-Object -First 1 }
        $r.Nombre = $pd.FriendlyName; $r.Medio = "$($pd.MediaType)"; $r.Bus = "$($pd.BusType)"; $r.TamanoGB = [math]::Round($pd.Size / 1GB)
        $v = Get-Volume -DriveLetter $env:SystemDrive[0] -ErrorAction SilentlyContinue
        if ($v -and $v.Size -gt 0) { $r.LibrePct = [math]::Round($v.SizeRemaining / $v.Size * 100) }
    } catch { }
    if ($r.Medio -eq 'Unspecified' -and $r.Bus -eq 'NVMe') { $r.Medio = 'SSD' }
    if ($ConPrueba) {
        try {
            $ruta = Join-Path $env:TEMP 'nit_cuello_disco.bin'; $buf = New-Object byte[] 1048576; (New-Object Random).NextBytes($buf)
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $fs = New-Object IO.FileStream($ruta, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None, 1048576, [IO.FileOptions]::WriteThrough)
            for ($i = 0; $i -lt 128; $i++) { $fs.Write($buf, 0, $buf.Length) }; $fs.Flush(); $fs.Close(); $sw.Stop(); $r.Escritura = [math]::Round(128 / $sw.Elapsed.TotalSeconds)
            $sw.Restart(); $fs = New-Object IO.FileStream($ruta, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None, 1048576, [IO.FileOptions]::SequentialScan)
            while ($fs.Read($buf, 0, $buf.Length) -gt 0) { }; $fs.Close(); $sw.Stop(); $r.Lectura = [math]::Round(128 / $sw.Elapsed.TotalSeconds)
        } catch { } finally { Remove-Item (Join-Path $env:TEMP 'nit_cuello_disco.bin') -Force -ErrorAction SilentlyContinue }
    }
    $s = if ($r.Medio -eq 'HDD') { 12 } elseif ($r.Bus -eq 'NVMe') { 72 } elseif ($r.Bus -eq 'USB') { 20 } elseif ($r.Medio -eq 'SSD') { 50 } else { 35 }
    if ($null -ne $r.Escritura -and $r.Escritura -lt 100 -and $r.Medio -ne 'HDD') { $s -= 10 }
    if ($null -ne $r.LibrePct -and $r.LibrePct -lt 10) { $s -= 5 }
    $r.Score = Limitar $s 5 100; $r.Gama = Get-NombreGama $r.Score
    [pscustomobject]$r
}

# ---------------------------------------------------------------- Análisis conjunto
function Get-AnalisisConfig {
    param([ValidateSet('General', 'Juegos', 'Creacion', 'Oficina')][string]$Perfil = 'General', [bool]$ConPruebaDisco = $true)
    $anioActual = (Get-Date).Year
    $cpu = Get-InfoCpu; $gpu = Get-InfoGpu; $ram = Get-InfoRam; $disco = Get-InfoDisco $ConPruebaDisco
    $chasis = @((Get-CimInstance Win32_SystemEnclosure).ChassisTypes)
    $portatil = [bool]($chasis | Where-Object { $_ -in 8, 9, 10, 11, 12, 14, 30, 31, 32 }) -or [bool](Get-CimInstance Win32_Battery)
    $ramMin = @{ Oficina = 8; General = 16; Juegos = 16; Creacion = 32 }[$Perfil]
    $pesoGpu = @{ Oficina = 0.2; General = 0.5; Juegos = 1.0; Creacion = 0.8 }[$Perfil]
    $h = New-Object System.Collections.Generic.List[object]
    function Add-H($comp, $est, $tit, $res, $det = '', $sig = '') { $h.Add([pscustomobject]@{ Id = ($comp + $h.Count); Componente = $comp; Estado = $est; Titulo = $tit; Resumen = $res; Detalle = $det; Siguiente = $sig }) }

    # --- Disco
    $dDisco = @("Disco del sistema: $($disco.Nombre) · $($disco.Medio) $($disco.Bus) · $($disco.TamanoGB) GB")
    if ($null -ne $disco.Escritura) { $dDisco += "Velocidad medida (128 MB): escritura $($disco.Escritura) MB/s · lectura $($disco.Lectura) MB/s (la lectura puede estar ayudada por la caché)" }
    if ($null -ne $disco.LibrePct) { $dDisco += "Espacio libre: $($disco.LibrePct) %" }
    if ($disco.Medio -eq 'HDD') { Add-H 'Disco' 'Fallo' 'Disco de arranque mecánico (HDD)' 'Es el mayor cuello de botella posible: Windows y los programas cargan de 5 a 10 veces más lento que en un SSD.' ($dDisco -join "`n") 'Sustituye el disco del sistema por un SSD (SATA o NVMe) y clona o reinstala Windows. Es la mejora que más se nota.' }
    elseif ($disco.Bus -eq 'USB') { Add-H 'Disco' 'Aviso' 'Windows arranca desde un disco USB' 'Los discos externos limitan mucho el arranque y la carga de programas.' ($dDisco -join "`n") 'Instala Windows en un SSD interno.' }
    elseif ($null -ne $disco.Escritura -and $disco.Escritura -lt 100) { Add-H 'Disco' 'Aviso' 'El disco es lento' "El SSD escribe a $($disco.Escritura) MB/s, por debajo de lo normal." ($dDisco -join "`n") 'Comprueba el estado con CrystalDiskInfo, que tenga espacio libre y que el controlador esté actualizado.' }
    else { Add-H 'Disco' 'OK' "Disco de arranque $($disco.Medio) $($disco.Bus)" "$($disco.Nombre): $($disco.Gama.ToLower()) en velocidad. No limita al resto del equipo." ($dDisco -join "`n") }
    if ($null -ne $disco.LibrePct -and $disco.LibrePct -lt 10) { Add-H 'Disco' 'Aviso' 'Poco espacio libre en el disco del sistema' "Solo queda un $($disco.LibrePct) %: Windows pierde rendimiento y el SSD se desgasta más." '' 'Libera espacio con WizTree o WinDirStat.' }

    # --- RAM
    $dRam = @("Total: $($ram.TotalGB) GB $($ram.Tipo) en $($ram.Modulos) módulo(s) de $($ram.Ranuras) ranura(s)") + $ram.Detalle
    if ($ram.Soldada) { Add-H 'RAM' 'Info' 'Memoria soldada a la placa' "Memoria $($ram.Tipo) integrada: el número de canales lo decide el fabricante y no se puede ampliar ni cambiar." ($dRam -join "`n") }
    elseif ($ram.Modulos -eq 1 -and $ram.Ranuras -ge 2) { Add-H 'RAM' 'Aviso' 'Memoria en canal simple' "Hay 1 solo módulo de $($ram.TotalGB) GB para $($ram.Ranuras) ranuras: el ancho de banda de la RAM se reduce a la mitad." ($dRam -join "`n") 'Añade un segundo módulo IGUAL (misma capacidad, velocidad y a ser posible el mismo modelo) en la ranura del otro canal. Mejora hasta un 30-50 % los gráficos integrados.' }
    elseif ($ram.Modulos -ge 2 -and $ram.CanalesConocidos -and $ram.CanalesDistintos -lt 2) { Add-H 'RAM' 'Aviso' 'Módulos de RAM en el mismo canal' "Los $($ram.Modulos) módulos están en un único canal: no se aprovecha el doble canal." ($dRam -join "`n") 'Mueve los módulos a las ranuras de canales distintos (consulta el manual de la placa: normalmente 1.ª y 3.ª, o 2.ª y 4.ª).' }
    elseif ($ram.Modulos -ge 2 -and $ram.DobleCanal) { Add-H 'RAM' 'OK' 'RAM en doble canal' "$($ram.Modulos) módulos repartidos en canales distintos: ancho de banda completo." ($dRam -join "`n") }
    elseif ($ram.Modulos -ge 2) { Add-H 'RAM' 'Info' 'Doble canal probable pero no confirmable' "Hay $($ram.Modulos) módulos; Windows no indica en qué canal está cada uno." ($dRam -join "`n") 'Comprueba el canal con CPU-Z, pestaña Memory.' }
    if ($ram.Modulos -ge 2 -and -not $ram.CapacidadesIguales) { Add-H 'RAM' 'Aviso' 'Módulos de distinta capacidad' "Capacidades: $($ram.Capacidades -join ' + ') GB. La parte desigual no trabaja en doble canal (modo flex)." ($dRam -join "`n") 'Usa módulos iguales para ganar rendimiento.' }
    if ($ram.Modulos -ge 2 -and -not $ram.VelocidadesIguales) { Add-H 'RAM' 'Aviso' 'Módulos con velocidad nominal distinta' 'Todos van a la velocidad del más lento.' ($dRam -join "`n") 'Combina módulos de la misma velocidad.' }
    elseif ($ram.Modulos -ge 2 -and ($ram.Fabricantes.Count -gt 1 -or $ram.Piezas.Count -gt 1)) { Add-H 'RAM' 'Info' 'Módulos de distinto fabricante o modelo' "$($ram.Fabricantes -join ' + '): funcionan, pero pueden obligar a bajar frecuencia o tiempos y causar inestabilidad." ($dRam -join "`n") 'Si ves cuelgues o pantallazos azules, prueba cada módulo por separado con MemTest86.' }
    if ($ram.VelConfig -gt 0 -and $ram.VelNominal -gt 0 -and $ram.VelConfig -lt $ram.VelNominal * 0.95) {
        $txt = "Trabaja a $($ram.VelConfig) MHz y los módulos admiten $($ram.VelNominal) MHz."
        if ($portatil) { Add-H 'RAM' 'Info' 'RAM por debajo de su velocidad nominal' "$txt En portátiles lo normal es que el límite lo ponga el procesador." ($dRam -join "`n") }
        else { Add-H 'RAM' 'Aviso' 'RAM por debajo de su velocidad nominal' "$txt Perfil XMP / DOCP / EXPO probablemente desactivado." ($dRam -join "`n") 'Entra en la BIOS y activa XMP (Intel) o DOCP/EXPO (AMD) para usarla a su velocidad.' }
    }
    elseif ($ram.VelConfig -gt 0 -and $ram.Modulos -ge 1) { Add-H 'RAM' 'OK' "RAM a $($ram.VelConfig) MHz" "$($ram.Tipo) a su velocidad configurada nominal." }
    if ($ram.TotalGB -lt 8) { Add-H 'RAM' 'Fallo' "Poca memoria ($($ram.TotalGB) GB)" 'Con menos de 8 GB Windows paginará a disco continuamente: el equipo irá lento.' ($dRam -join "`n") 'Amplía la RAM como mínimo a 8 GB (16 GB recomendado).' }
    elseif ($ram.TotalGB -lt $ramMin * 0.9) { Add-H 'RAM' 'Aviso' "Memoria justa para el perfil «$Perfil»" "Tienes $($ram.TotalGB) GB y para este uso se recomiendan $ramMin GB." ($dRam -join "`n") "Amplía a $ramMin GB." }
    else { Add-H 'RAM' 'OK' "Capacidad suficiente ($($ram.TotalGB) GB)" "Cubre los $ramMin GB recomendados para el perfil «$Perfil»." }

    # --- CPU
    $dCpu = @("Modelo: $($cpu.Nombre)", "Núcleos / hilos: $($cpu.Nucleos) / $($cpu.Hilos) · Frecuencia base: $($cpu.MHz) MHz", "Generación: $($cpu.Gen) $(if ($cpu.Anio) { '(≈ ' + $cpu.Anio + ')' })")
    if ($cpu.Hilos -lt 4 -and $Perfil -ne 'Oficina') { Add-H 'CPU' 'Aviso' 'Procesador con pocos hilos' "Solo $($cpu.Hilos) hilos: limitará juegos, multitarea y edición." ($dCpu -join "`n") 'Considera un procesador de 6 núcleos o más.' }
    if ($cpu.BajoConsumo -and $Perfil -in 'Juegos', 'Creacion') { Add-H 'CPU' 'Info' 'CPU de bajo consumo (serie U/Y)' 'Estos procesadores limitan la potencia sostenida (≈ 15 W): rinden bien en ráfagas y pierden rendimiento en cargas largas.' ($dCpu -join "`n") 'Para juegos o edición continuados conviene un procesador serie H/HX o de sobremesa.' }
    if ($cpu.Anio -and $cpu.Anio -le $anioActual - 8) { Add-H 'CPU' 'Aviso' "Procesador antiguo (≈ $($cpu.Anio))" "Tiene ≈ $($anioActual - $cpu.Anio) años: le faltan instrucciones, eficiencia y rendimiento por hilo actuales." ($dCpu -join "`n") 'Planifica una actualización de plataforma (CPU + placa + RAM).' }
    elseif (-not ($cpu.Hilos -lt 4 -and $Perfil -ne 'Oficina')) { Add-H 'CPU' 'OK' "CPU de gama $($cpu.Gama.ToLower())" "$($cpu.Corto): $($cpu.Nucleos) núcleos, $($cpu.Hilos) hilos$(if ($cpu.Anio) { ', ≈ ' + $cpu.Anio })." ($dCpu -join "`n") }

    # --- GPU
    $gp = $gpu.Principal; $dGpu = @($gpu.Todas | ForEach-Object { "$($_.Nombre) · $($_.Tipo) · $($_.VRAMMB) MB · $($_.Gama)$(if ($_.Anio) { ' (≈ ' + $_.Anio + ')' }) · Controlador $($_.Driver)" })
    $enlace = $null
    if ($gpu.Dedicada) {
        $enlace = Get-EnlacePcie $gpu.Dedicada.Nombre
        if ($enlace) {
            $gen = @{ 1 = 'Gen1'; 2 = 'Gen2'; 3 = 'Gen3'; 4 = 'Gen4'; 5 = 'Gen5' }; $dGpu += "Enlace PCIe actual: $($gen[$enlace.VelActual]) x$($enlace.AnchoActual) · máximo del dispositivo: $($gen[$enlace.VelMax]) x$($enlace.AnchoMax)"
            if ($enlace.AnchoActual -lt $enlace.AnchoMax) {
                if ($portatil) { Add-H 'GPU' 'Info' "Gráfica dedicada con enlace PCIe x$($enlace.AnchoActual)" "El dispositivo admite x$($enlace.AnchoMax), pero el portátil le da x$($enlace.AnchoActual). Es una limitación de diseño habitual y el impacto suele ser pequeño." ($dGpu -join "`n") }
                else { Add-H 'GPU' 'Aviso' "Gráfica en ranura PCIe x$($enlace.AnchoActual) (admite x$($enlace.AnchoMax))" 'La gráfica no recibe todo el ancho de banda: está en una ranura reducida o mal asentada.' ($dGpu -join "`n") 'Cámbiala a la ranura PCIe x16 principal (la más cercana a la CPU) y comprueba que esté bien insertada.' }
            }
        }
    }
    if (-not $gp) { Add-H 'GPU' 'Info' 'No se detectó la gráfica' 'Windows no devuelve información de la tarjeta gráfica.' '' }
    else {
        if ($gp.Tipo -eq 'Integrada' -and $Perfil -in 'Juegos', 'Creacion') { Add-H 'GPU' 'Aviso' 'Solo hay gráfica integrada' "$($gp.Nombre) comparte la RAM con el sistema: limitará juegos, 3D y edición de vídeo." ($dGpu -join "`n") 'Añade una gráfica dedicada (sobremesa) o usa un equipo con GPU dedicada.' }
        if ($gpu.Dedicada -and $gpu.Integrada) { Add-H 'GPU' 'Info' 'Equipo con dos gráficas (integrada + dedicada)' 'Windows decide qué gráfica usa cada programa; a veces un juego se ejecuta en la integrada.' ($dGpu -join "`n") 'Ajustes > Sistema > Pantalla > Gráficos: asigna la gráfica dedicada a tus juegos y programas pesados. El monitor en vivo te dice cuál usas.' }
        if ($gpu.Dedicada) {
            $g = $gpu.Dedicada
            if ($g.Anio -and $cpu.Anio -and $g.Anio -le $cpu.Anio - 4) { Add-H 'GPU' 'Aviso' "La gráfica es ≈ $($cpu.Anio - $g.Anio) años más antigua que la CPU" "$($g.Nombre) (≈ $($g.Anio), gama $($g.Gama.ToLower())) frente a $($cpu.Corto) (≈ $($cpu.Anio)). Es la pieza que se ha quedado atrás." ($dGpu -join "`n") 'Una gráfica más moderna es la mejora más rentable para juegos y 3D.' }
            elseif ($g.Anio -and $g.Anio -le $anioActual - 7 -and $Perfil -eq 'Juegos') { Add-H 'GPU' 'Aviso' "Gráfica antigua (≈ $($g.Anio))" 'Sin trazado de rayos por hardware ni reescalado por IA, y con soporte de controladores decreciente.' ($dGpu -join "`n") 'Planifica una gráfica más reciente.' }
            if (($cpu.Score - $g.Score) -ge 28 -and $pesoGpu -ge 0.8) { Add-H 'GPU' 'Aviso' 'La gráfica es la pieza débil del equipo' "CPU $($cpu.Gama.ToLower()) ($($cpu.Score)) frente a gráfica $($g.Gama.ToLower()) ($($g.Score))." ($dGpu -join "`n") 'Para juegos o 3D, la gráfica limitará antes que el procesador.' }
            elseif (($g.Score - $cpu.Score) -ge 22 -and $pesoGpu -ge 0.5) { Add-H 'CPU' 'Aviso' 'La CPU puede limitar a la gráfica' "Gráfica $($g.Gama.ToLower()) ($($g.Score)) frente a CPU $($cpu.Gama.ToLower()) ($($cpu.Score)): en juegos la CPU no alimentará bien a la GPU." (($dCpu + $dGpu) -join "`n") 'Un procesador más potente (más rendimiento por hilo) liberaría la gráfica. Confírmalo con el monitor en vivo.' }
            elseif (-not ($g.Anio -and $cpu.Anio -and $g.Anio -le $cpu.Anio - 4)) { Add-H 'GPU' 'OK' "CPU y gráfica equilibradas" "CPU $($cpu.Gama.ToLower()) ($($cpu.Score)) y gráfica $($g.Gama.ToLower()) ($($g.Score)): sin un desequilibrio importante." ($dGpu -join "`n") }
        }
        elseif ($gp.Tipo -eq 'Integrada' -and $Perfil -in 'Oficina', 'General') { Add-H 'GPU' 'OK' 'Gráfica integrada suficiente para este uso' "$($gp.Nombre): válida para ofimática, vídeo y navegación." ($dGpu -join "`n") }
    }

    # --- Energía
    $plan = (powercfg /getactivescheme 2>$null) -join ' '
    $enBateria = $false; try { $bat = Get-CimInstance Win32_Battery; if ($bat -and $bat.BatteryStatus -eq 1) { $enBateria = $true } } catch { }
    if ($plan -match '381b4222') { Add-H 'Sistema' 'Aviso' 'Plan de energía en «Economizador»' 'Limita la frecuencia de la CPU y baja el rendimiento.' $plan 'Cambia a «Equilibrado» o «Alto rendimiento» en Configuración > Sistema > Energía.' }
    elseif ($enBateria) { Add-H 'Sistema' 'Info' 'Portátil funcionando con batería' 'Con batería Windows y el fabricante reducen la potencia de CPU y GPU.' $plan 'Conecta el cargador para medir el rendimiento real.' }
    else { Add-H 'Sistema' 'OK' 'Plan de energía sin límites' 'El plan activo no recorta el rendimiento.' $plan }

    # --- Equilibrio global
    $comp = @(
        [pscustomobject]@{ Clave = 'CPU'; Nombre = $cpu.Corto; Detalle = "$($cpu.Nucleos)N/$($cpu.Hilos)H · $($cpu.MHz / 1000) GHz"; Score = $cpu.Score; Gama = $cpu.Gama; Anio = $cpu.Anio }
        [pscustomobject]@{ Clave = 'GPU'; Nombre = $(if ($gp) { $gp.Nombre } else { 'No detectada' }); Detalle = $(if ($gp) { "$($gp.Tipo) · $($gp.VRAMMB) MB" } else { '' }); Score = $(if ($gp) { $gp.Score } else { 0 }); Gama = $(if ($gp) { $gp.Gama } else { '-' }); Anio = $(if ($gp) { $gp.Anio } else { $null }) }
        [pscustomobject]@{ Clave = 'RAM'; Nombre = "$($ram.TotalGB) GB $($ram.Tipo)"; Detalle = "$(if ($ram.DobleCanal) { 'Doble canal' } elseif ($ram.Soldada) { 'Soldada' } else { 'Canal simple' }) · $($ram.VelConfig) MHz"; Score = $ram.Score; Gama = $ram.Gama; Anio = $null }
        [pscustomobject]@{ Clave = 'Disco'; Nombre = $disco.Nombre; Detalle = "$($disco.Medio) $($disco.Bus)$(if ($null -ne $disco.Lectura) { ' · ' + $disco.Lectura + ' MB/s' })"; Score = $disco.Score; Gama = $disco.Gama; Anio = $null }
    )
    $graves = @($h | Where-Object Estado -eq 'Fallo'); $moderados = @($h | Where-Object Estado -eq 'Aviso')
    $relevantes = @($comp | Where-Object { $_.Clave -ne 'GPU' -or $pesoGpu -ge 0.5 -or ($gp -and $gp.Tipo -eq 'Dedicada') })
    $debil = $relevantes | Sort-Object Score | Select-Object -First 1
    $veredicto = if ($graves.Count) { "Una pieza frena gravemente al resto: $((($graves | ForEach-Object { $_.Componente }) | Select-Object -Unique) -join ', ')" }
                 elseif ($moderados.Count) { "Desequilibrios moderados: $((($moderados | ForEach-Object { $_.Componente }) | Select-Object -Unique) -join ', ')" }
                 else { 'Equipo equilibrado: ninguna pieza frena al resto' }
    $clase = if ($graves.Count) { 'Fallo' } elseif ($moderados.Count) { 'Aviso' } else { 'OK' }
    [pscustomobject]@{ Perfil = $Perfil; Portatil = $portatil; Componentes = $comp; Hallazgos = $h.ToArray(); Veredicto = $veredicto; Clase = $clase; PiezaDebil = $debil; Cpu = $cpu; Gpu = $gpu; Ram = $ram; Disco = $disco }
}

# ---------------------------------------------------------------- Monitor en vivo
# Se ejecuta en un runspace: va dejando muestras en $Cola (ConcurrentQueue) cada ~2 s.
function Start-Monitor {
    param([int]$Segundos = 60, $Cola, $Ctl)
    # Con la CPU saturada la medición debe seguir respondiendo: se le da prioridad sobre el resto
    try { [Threading.Thread]::CurrentThread.Priority = [Threading.ThreadPriority]::AboveNormal } catch { }
    $sens = $null; try { $sens = Open-Sensores $script:RaizKitEq } catch { }
    $inicio = Get-Date; $n = 0
    while (((Get-Date) - $inicio).TotalSeconds -lt $Segundos) {
        if ($Ctl.Cancelar) { $Cola.Enqueue(@{ Tipo = 'Cancelado' }); return }
        $t0 = Get-Date
        $m = @{ Tipo = 'Muestra'; T = [math]::Round(($t0 - $inicio).TotalSeconds); Cpu = $null; Nucleo = $null; Perf = $null; Ram = $null; Paginas = 0; Disco = $null; Cola = 0; Gpu = $null; GpuOtro = $null; GpuMB = $null; TempCpu = $null }
        try {
            $p = @(Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor)
            $m.Cpu = [double](($p | Where-Object Name -eq '_Total').PercentProcessorTime)
            $m.Nucleo = [double](($p | Where-Object Name -ne '_Total' | Measure-Object PercentProcessorTime -Maximum).Maximum)
        } catch { }
        try { $pi = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'"; if ($pi.PercentProcessorPerformance) { $m.Perf = [double]$pi.PercentProcessorPerformance } } catch { }
        try { $os = Get-CimInstance Win32_OperatingSystem; $m.Ram = [math]::Round((1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize) * 100, 1) } catch { }
        try { $mem = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory; $m.Paginas = [double]$mem.PagesInputPersec } catch { }
        try { $d = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'"; $m.Disco = [double]$d.PercentDiskTime; $m.Cola = [double]$d.CurrentDiskQueueLength } catch { }
        try {
            $ge = @(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction Stop)
            $suma3d = @{}; $sumaOtro = @{}
            foreach ($e in $ge) {
                if ($e.Name -match 'luid_(0x[0-9A-Fa-f]+_0x[0-9A-Fa-f]+)_.*engtype_(\w+)') {
                    $l = $matches[1]; $tp = $matches[2]; $u = [double]$e.UtilizationPercentage
                    if ($tp -eq '3D') { $suma3d[$l] = [double]$suma3d[$l] + $u } else { $sumaOtro[$l] = [math]::Max([double]$sumaOtro[$l], $u) }
                }
            }
            $m.Gpu = [math]::Min(100, [double](($suma3d.Values | Measure-Object -Maximum).Maximum))
            $m.GpuOtro = [math]::Min(100, [double](($sumaOtro.Values | Measure-Object -Maximum).Maximum))
        } catch { }
        try { $gm = @(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory -ErrorAction Stop); $m.GpuMB = [math]::Round((($gm | Measure-Object DedicatedUsage -Maximum).Maximum) / 1MB) } catch { }
        try { if ($sens -and $sens.Ok) { $lec = Read-Sensores $sens; if ($null -ne $lec.CpuTemp) { $m.TempCpu = [double]$lec.CpuTemp } } } catch { }
        $n++
        if ($n -gt 1) { $Cola.Enqueue($m) }    # la primera lectura de los contadores no es válida
        $esp = 2000 - ((Get-Date) - $t0).TotalMilliseconds
        if ($esp -gt 50) { Start-Sleep -Milliseconds ([int]$esp) }
    }
    try { Close-Sensores $sens } catch { }
    $Cola.Enqueue(@{ Tipo = 'Terminado' })
}

function Get-Estadistica($valores) {
    $v = @($valores | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
    if (-not $v.Count) { return [pscustomobject]@{ N = 0; Media = 0; P95 = 0; Max = 0; Sat = 0 } }
    $s = $v | Sort-Object
    [pscustomobject]@{ N = $v.Count; Media = [math]::Round(($v | Measure-Object -Average).Average, 1); P95 = $s[[math]::Min($s.Count - 1, [int][math]::Floor($s.Count * 0.95))]; Max = ($v | Measure-Object -Maximum).Maximum; Sat = 0 }
}

# Interpreta las muestras del monitor y devuelve hallazgos y estadísticas
function Get-VeredictoMonitor {
    param($Muestras, $Analisis)
    $m = @($Muestras)
    $porc = { param($vals, $umbral) $v = @($vals | Where-Object { $null -ne $_ }); if (-not $v.Count) { 0 } else { [math]::Round((@($v | Where-Object { $_ -ge $umbral }).Count / $v.Count) * 100) } }
    $cpu = Get-Estadistica ($m | ForEach-Object { $_.Cpu }); $nuc = Get-Estadistica ($m | ForEach-Object { $_.Nucleo })
    $gpu = Get-Estadistica ($m | ForEach-Object { $_.Gpu }); $ram = Get-Estadistica ($m | ForEach-Object { $_.Ram })
    $dsk = Get-Estadistica ($m | ForEach-Object { $_.Disco }); $prf = Get-Estadistica ($m | ForEach-Object { $_.Perf })
    $pag = Get-Estadistica ($m | ForEach-Object { $_.Paginas }); $cola = Get-Estadistica ($m | ForEach-Object { $_.Cola })
    $gmb = Get-Estadistica ($m | ForEach-Object { $_.GpuMB })
    $tcp = Get-Estadistica ($m | ForEach-Object { $_.TempCpu })
    $cpu.Sat = & $porc ($m | ForEach-Object { $_.Cpu }) 90; $nuc.Sat = & $porc ($m | ForEach-Object { $_.Nucleo }) 95
    $gpu.Sat = & $porc ($m | ForEach-Object { $_.Gpu }) 90; $ram.Sat = & $porc ($m | ForEach-Object { $_.Ram }) 90; $dsk.Sat = & $porc ($m | ForEach-Object { $_.Disco }) 90
    $h = New-Object System.Collections.Generic.List[object]
    function AddM($comp, $est, $tit, $res, $det = '', $sig = '') { $h.Add([pscustomobject]@{ Id = "m$($h.Count)"; Componente = $comp; Estado = $est; Titulo = $tit; Resumen = $res; Detalle = $det; Siguiente = $sig }) }
    $dTodo = @(
        ("CPU total: media {0} % · p95 {1} % · máx. {2} % · ≥90 % el {3} % del tiempo" -f $cpu.Media, $cpu.P95, $cpu.Max, $cpu.Sat),
        ("Núcleo más cargado: media {0} % · ≥95 % el {1} % del tiempo" -f $nuc.Media, $nuc.Sat),
        ("GPU 3D: media {0} % · p95 {1} % · máx. {2} % · ≥90 % el {3} % del tiempo" -f $gpu.Media, $gpu.P95, $gpu.Max, $gpu.Sat),
        ("RAM en uso: media {0} % · máx. {1} %" -f $ram.Media, $ram.Max),
        ("Disco ocupado: media {0} % · máx. {1} % · cola media {2}" -f $dsk.Media, $dsk.Max, $cola.Media),
        ("Frecuencia CPU: media {0} % de la base" -f $prf.Media),
        ("Memoria de vídeo usada: máx. {0} MB" -f $gmb.Max),
        $(if ($tcp.N) { "Temperatura CPU: media {0} °C · máx. {1} °C" -f $tcp.Media, $tcp.Max } else { "Temperatura CPU: sin sensor (instala el controlador desde «Componentes»)" }),
        ("Muestras: {0} (cada ≈ 2 s)" -f $m.Count)
    ) -join "`n"
    if ($m.Count -lt 5) { AddM 'Medición' 'Info' 'Muestras insuficientes' 'Se obtuvieron muy pocas muestras. Repite la medición durante al menos 30 s.' $dTodo; return [pscustomobject]@{ Hallazgos = $h.ToArray(); Cpu = $cpu; Nucleo = $nuc; Gpu = $gpu; Ram = $ram; Disco = $dsk; Limitante = 'Sin datos'; Detalle = $dTodo } }
    $bajaCarga = ($cpu.Media -lt 30 -and $gpu.Media -lt 30 -and $dsk.Media -lt 30 -and $ram.Media -lt 85)
    if ($bajaCarga) { $h.Clear(); AddM 'Medición' 'Info' 'La carga durante la medición fue baja' ("CPU {0} %, GPU {1} %, disco {2} % de media: no hay carga suficiente para ver un cuello de botella." -f $cpu.Media, $gpu.Media, $dsk.Media) $dTodo 'Inicia la medición y, a la vez, abre el juego o programa que quieres evaluar (o la tarea que va lenta). Debe haber carga real durante los 60 s.' }
    $limitante = 'Ninguno'
    # RAM
    if ($ram.Media -ge 90 -or $pag.Media -gt 200) { AddM 'RAM' 'Aviso' 'La memoria RAM está al límite' ("Uso medio {0} %, máximo {1} % y {2} lecturas de paginación/s: Windows está usando el disco como memoria." -f $ram.Media, $ram.Max, [math]::Round($pag.Media)) $dTodo 'Cierra programas, o amplía la RAM. Es un cuello de botella muy notable.'; $limitante = 'RAM' }
    # Disco
    if ($dsk.Media -ge 85 -or $cola.Media -gt 2) { AddM 'Disco' 'Aviso' 'El disco está saturado' ("Ocupado de media un {0} % y cola media de {1}: los programas esperan al disco." -f $dsk.Media, $cola.Media) $dTodo 'Si es un HDD, cámbialo por un SSD. Si es un SSD, mira si hay una copia de seguridad, antivirus o indexación trabajando en segundo plano.'; if ($limitante -eq 'Ninguno') { $limitante = 'Disco' } }
    # CPU
    $gpuLibre = ($gpu.Media -lt 85)
    if ($nuc.Sat -ge 40 -and $cpu.Media -lt 75 -and $gpuLibre -and -not $bajaCarga) {
        AddM 'CPU' 'Aviso' 'Un hilo de la CPU limita el rendimiento (cuello de botella de CPU)' ("Un núcleo estuvo al ≥95 % el {0} % del tiempo con la CPU total en {1} % y la GPU solo en {2} %: la gráfica espera a que la CPU le mande trabajo." -f $nuc.Sat, $cpu.Media, $gpu.Media) $dTodo 'Lo que limita es el rendimiento por hilo del procesador. Ayudan: un procesador más rápido por núcleo, reducir opciones dependientes de la CPU (población, física, distancia de dibujado) o subir resolución/calidad gráfica para equilibrar.'; $limitante = 'CPU (un hilo)'
    }
    elseif ($cpu.Media -ge 85 -or $cpu.Sat -ge 40) { AddM 'CPU' 'Aviso' 'La CPU está saturada' ("Media {0} %, ≥90 % el {1} % del tiempo.{2}" -f $cpu.Media, $cpu.Sat, $(if ($gpu.Media -lt 60) { ' La GPU queda libre mientras tanto.' } else { '' })) $dTodo 'La CPU no da más de sí para esta tarea. Cierra procesos en segundo plano o valora un procesador con más núcleos/hilos.'; $limitante = 'CPU' }
    # Temperatura
    if ($tcp.N -and $tcp.Max -ge 100) { AddM 'CPU' 'Fallo' 'La CPU llega a temperatura crítica bajo carga' ("Máximo de {0} °C (media {1} °C): el procesador reduce su frecuencia para protegerse." -f $tcp.Max, $tcp.Media) $dTodo 'Limpia ventilador y disipador, renueva la pasta térmica y comprueba que el aire circula bien. Con estas temperaturas el rendimiento cae.'; if ($limitante -eq 'Ninguno') { $limitante = 'CPU (temperatura)' } }
    elseif ($tcp.N -and $tcp.Max -ge 90) { AddM 'CPU' 'Aviso' 'La CPU se calienta mucho bajo carga' ("Máximo de {0} °C (media {1} °C): cerca del límite térmico, puede estar reduciendo frecuencia." -f $tcp.Max, $tcp.Media) $dTodo 'Revisa la limpieza del ventilador, el plan de energía y la ventilación del equipo.' }
    # Throttling
    if ($prf.N -gt 0 -and $prf.Media -lt 70 -and $cpu.Media -gt 60) { AddM 'CPU' 'Aviso' 'La CPU baja de frecuencia bajo carga' ("Trabajó de media al {0} % de su frecuencia base con una carga alta: posible límite térmico o de energía." -f $prf.Media) $dTodo 'Limpia ventilador y disipador, comprueba la temperatura con HWiNFO y que el plan de energía no esté en «Economizador».' }
    # GPU
    if ($gpu.Media -ge 90 -or $gpu.Sat -ge 50) {
        $g = $Analisis.Gpu.Principal
        if ($limitante -eq 'Ninguno') { $limitante = 'GPU' }
        if ($g -and $g.Score -lt 45) { AddM 'GPU' 'Aviso' 'La gráfica está al límite y es de gama baja' ("GPU 3D al {0} % de media ({1}). Es el componente que limita." -f $gpu.Media, $g.Gama.ToLower()) $dTodo 'Baja la calidad gráfica o la resolución, o plantéate una gráfica más potente.' }
        else { AddM 'GPU' 'Info' 'La gráfica trabaja al límite (lo normal en juegos)' ("GPU 3D al {0} % de media: es el factor limitante y significa que la CPU la alimenta bien." -f $gpu.Media) $dTodo 'Si quieres más fotogramas por segundo, reduce resolución o calidad, o sube de gráfica.' }
    }
    # Gráfica dedicada sin uso
    $ded = $Analisis.Gpu.Dedicada
    if ($ded -and $Analisis.Gpu.Integrada -and $cpu.Media -ge 50 -and $gpu.Media -lt 10 -and $gmb.Max -lt 300) { AddM 'GPU' 'Info' 'Parece que la gráfica dedicada no se está usando' ("Mientras la CPU trabajaba al {0} %, la GPU 3D apenas llegó al {1} %. Puede que el programa use la gráfica integrada." -f $cpu.Media, $gpu.Max) $dTodo 'Ajustes > Sistema > Pantalla > Gráficos: elige «Alto rendimiento» para ese programa o juego.' }
    if (-not ($h | Where-Object { $_.Estado -in 'Aviso', 'Fallo' }) -and -not $bajaCarga) { AddM 'Sistema' 'OK' 'Sin cuello de botella apreciable' ("Ningún componente estuvo saturado de forma sostenida (CPU {0} %, GPU {1} %, RAM {2} %, disco {3} % de media)." -f $cpu.Media, $gpu.Media, $ram.Media, $dsk.Media) $dTodo; $limitante = 'Ninguno' }
    [pscustomobject]@{ Hallazgos = $h.ToArray(); Cpu = $cpu; Nucleo = $nuc; Gpu = $gpu; Ram = $ram; Disco = $dsk; Perf = $prf; Limitante = $limitante; Detalle = $dTodo; BajaCarga = $bajaCarga }
}
