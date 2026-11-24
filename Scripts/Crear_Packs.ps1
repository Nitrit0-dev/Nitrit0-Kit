# =====================================================================
#  Crear_Packs.ps1 - Construye los dos packs del kit en una carpeta APARTE (fuera del kit)
#    Nitrit0_Kit_Publico  = para usuarios y amigos: sin licencias, sin Office, sin datos de nadie,
#                           herramientas peligrosas ocultas y modo sencillo por defecto.
#    Nitrit0_Kit_Personal = lo tuyo: igual, pero con todo visible, la licencia de WinRAR y Office 2013.
#  Las licencias y el instalador de Office NO viven en el kit: se toman de <Destino>\_Extras_Personales
#  (Apps\Licencias, Apps\Instaladores\Office2013). Si falta, el pack personal sale sin ellos y lo avisa.
#  Uso:  powershell.exe -NoProfile -ExecutionPolicy Bypass -File Scripts\Crear_Packs.ps1
#  -Lite: construye SOLO Nitrit0_Kit_Lite (el público sin la carpeta Apps de terceros) para publicarlo, p. ej., en GitHub Releases.
# =====================================================================
[CmdletBinding()]
param([string]$Destino, [string]$Exe, [string]$ExeLimpieza, [string]$ExeAntivirus, [string]$ExeClonador, [switch]$ExeUnico, [switch]$Lite)
$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
if (-not $Destino) { $Destino = Join-Path (Split-Path -Parent $raiz) 'Nitrit0_Packs' }
if (-not $Exe) { $Exe = Join-Path $raiz 'App\bin-unico\Nitrit0.exe' }
if (-not $ExeLimpieza) { $ExeLimpieza = Join-Path $raiz 'App\bin-limpieza\Nitrit0_Limpieza.exe' }   # opcional: si no está compilada, el pack sale sin ella
if (-not $ExeAntivirus) { $ExeAntivirus = Join-Path $raiz 'App\bin-antivirus\Nitrit0_Antivirus.exe' }   # opcional, como la de limpieza
if (-not $ExeClonador) { $ExeClonador = Join-Path $raiz 'App\bin-clonador\Nitrit0_Clonador.exe' }   # opcional, solo pack personal
$extras = Join-Path $Destino '_Extras_Personales'
# Por defecto los packs llevan la app DESCOMPRIMIDA en App\Motor (y App\MotorLimpieza) con un lanzador fino: el .exe único portable descomprime ~360 MB en %TEMP% en cada arranque.
# -ExeUnico fuerza el .exe único de antes. La carpeta es la que deja electron-builder junto al .exe (win-unpacked).
$motorApp = Join-Path (Split-Path -Parent $Exe) 'win-unpacked'
$motorLimp = Join-Path (Split-Path -Parent $ExeLimpieza) 'win-unpacked'
$modoCarpeta = (-not $ExeUnico) -and (Test-Path -LiteralPath (Join-Path $motorApp 'Nitrit0 Kit.exe'))
$modoCarpetaLimp = (-not $ExeUnico) -and (Test-Path -LiteralPath (Join-Path $motorLimp 'Nitrit0 Limpieza.exe'))
$motorAv = Join-Path (Split-Path -Parent $ExeAntivirus) 'win-unpacked'
$modoCarpetaAv = (-not $ExeUnico) -and (Test-Path -LiteralPath (Join-Path $motorAv 'Nitrit0 Antivirus.exe'))
$motorClon = Join-Path (Split-Path -Parent $ExeClonador) 'win-unpacked'
$modoCarpetaClon = (-not $ExeUnico) -and (Test-Path -LiteralPath (Join-Path $motorClon 'Nitrit0 Clonador.exe'))
if (-not (Test-Path -LiteralPath $Exe)) { throw "Falta $Exe. Ejecuta antes: cd App; npm run empaquetar:unico" }
New-Item -ItemType Directory -Force $Destino | Out-Null
$utf8 = New-Object Text.UTF8Encoding($false)

function Copy-Carpeta([string]$Origen, [string]$Dest, [string[]]$Excluir = @()) {
    $a = @($Origen, $Dest, '/E', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
    if ($Excluir.Count) { $a += '/XD'; $a += $Excluir }
    $a += '/XF'; $a += '*.log', '*.bak', '*.tmp'   # restos de ejecuciones (registros, copias, temporales) de herramientas usadas en este equipo: no viajan en ningún pack
    & robocopy.exe @a | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy falló copiando $Origen (código $LASTEXITCODE)" }
}

function New-Pack([string]$Nombre, [bool]$Personal, [bool]$Lite = $false) {
    $dest = Join-Path $Destino $Nombre
    # Solo se borra una carpeta de pack que cuelgue de $Destino
    if ((Test-Path -LiteralPath $dest)) {
        $r = (Resolve-Path -LiteralPath $dest).Path
        if (-not $r.StartsWith($Destino.TrimEnd('\') + '\') -or ($Nombre -notin 'Nitrit0_Kit_Publico', 'Nitrit0_Kit_Personal', 'Nitrit0_Kit_Lite')) { throw "No borro $r" }
        Remove-Item -LiteralPath $r -Recurse -Force
    }
    New-Item -ItemType Directory -Force $dest | Out-Null
    Write-Host "== $Nombre" -ForegroundColor Cyan

    # Código y herramientas. Nunca viajan: licencias, Office, la carpeta «pendiente» ni nada de Datos
    Copy-Carpeta (Join-Path $raiz 'Scripts') (Join-Path $dest 'Scripts')
    # «Desactivar Smart App Control» apaga una protección de Windows y es irreversible: solo en la raíz del pack PERSONAL, nunca dentro de Scripts ni en el público
    $batSac = 'Desactivar_SmartAppControl.bat'
    Remove-Item -LiteralPath (Join-Path $dest "Scripts\Recursos\$batSac") -Force -ErrorAction SilentlyContinue
    if ($Personal) { Copy-Item -LiteralPath (Join-Path $raiz "Scripts\Recursos\$batSac") -Destination $dest }
    if ($Lite) {   # sin herramientas de terceros: cada una tiene su licencia y se descarga de su web oficial
        New-Item -ItemType Directory -Force (Join-Path $dest 'Apps') | Out-Null
        [IO.File]::WriteAllText((Join-Path $dest 'Apps\LEEME.txt'), $script:LeemeApps, (New-Object Text.UTF8Encoding($true)))
    } else {
        Copy-Carpeta (Join-Path $raiz 'Apps') (Join-Path $dest 'Apps') @('Licencias', 'Office2013', 'Pendiente - Instaladores', (Join-Path $raiz 'Apps\Drivers'))   # Apps\Drivers (SDIO, GPLv3) está en valoración: no viaja en ningún pack
    }
    # Pack público: fuera lo destructivo (KillDisk), lo de acceso remoto (TeamViewer QS) y lo que da falso positivo o firma inválida (Windows-ISO-Downloader): ~165 MB menos
    if (-not $Personal) { foreach ($f in 'KillDisk-Freeware-Setup.exe', 'TeamViewerQS_x64.exe', 'Windows-ISO-Downloader.exe') { Remove-Item -LiteralPath (Join-Path $dest "Apps\Instaladores\Utilidades\$f") -Force -ErrorAction SilentlyContinue } }
    # Pack público: «Clonar disco» es solo del personal (borra un disco entero), así que ni su script viaja. La app ya lo oculta (Peligroso sin PublicoOk)
    if (-not $Personal) { Remove-Item -LiteralPath (Join-Path $dest 'Scripts\Mantenimiento\Clonar_Disco.ps1') -Force -ErrorAction SilentlyContinue }
    # Catálogo de la app (lista de herramientas): sin él Nitrit0.exe no arranca; va con huella en Integridad.json
    New-Item -ItemType Directory -Force (Join-Path $dest 'App\datos') | Out-Null
    Copy-Item -LiteralPath (Join-Path $raiz 'App\datos\herramientas.json') -Destination (Join-Path $dest 'App\datos')
    if ($modoCarpeta) {
        Copy-Carpeta $motorApp (Join-Path $dest 'App\Motor')
        & (Join-Path $PSScriptRoot 'Crear_Lanzador.ps1') -Salida (Join-Path $dest 'Nitrit0.exe') -Destino 'App\Motor\Nitrit0 Kit.exe' -Titulo 'Nitrit0 Kit' | Out-Null
        if (-not (Test-Path -LiteralPath (Join-Path $dest 'Nitrit0.exe'))) { throw 'No se pudo crear el lanzador Nitrit0.exe' }
    } else { Copy-Item -LiteralPath $Exe -Destination (Join-Path $dest 'Nitrit0.exe') }
    if ($modoCarpetaLimp) {
        Copy-Carpeta $motorLimp (Join-Path $dest 'App\MotorLimpieza')
        & (Join-Path $PSScriptRoot 'Crear_Lanzador.ps1') -Salida (Join-Path $dest 'Nitrit0_Limpieza.exe') -Destino 'App\MotorLimpieza\Nitrit0 Limpieza.exe' -Titulo 'Nitrit0 Limpieza' | Out-Null
    } elseif (Test-Path -LiteralPath $ExeLimpieza) { Copy-Item -LiteralPath $ExeLimpieza -Destination (Join-Path $dest 'Nitrit0_Limpieza.exe') } else { Write-Host '  AVISO: falta Nitrit0_Limpieza.exe (npm run limpieza); el pack sale sin ella.' -ForegroundColor Yellow }
    if ($Personal) {   # el antivirus (app aparte) es solo del pack personal
    if ($modoCarpetaAv) {
        Copy-Carpeta $motorAv (Join-Path $dest 'App\MotorAntivirus')
        & (Join-Path $PSScriptRoot 'Crear_Lanzador.ps1') -Salida (Join-Path $dest 'Nitrit0_Antivirus.exe') -Destino 'App\MotorAntivirus\Nitrit0 Antivirus.exe' -Titulo 'Nitrit0 Antivirus' -SinAdmin | Out-Null
    } elseif (Test-Path -LiteralPath $ExeAntivirus) { Copy-Item -LiteralPath $ExeAntivirus -Destination (Join-Path $dest 'Nitrit0_Antivirus.exe') } else { Write-Host '  AVISO: falta Nitrit0_Antivirus.exe (npm run antivirus); el pack sale sin ella.' -ForegroundColor Yellow }
    # El clonador (app aparte, pide administrador) también es solo del pack personal; llama a Clonar_Disco.ps1 con su integridad, simulación y confirmación escrita
    if ($modoCarpetaClon) {
        Copy-Carpeta $motorClon (Join-Path $dest 'App\MotorClonador')
        & (Join-Path $PSScriptRoot 'Crear_Lanzador.ps1') -Salida (Join-Path $dest 'Nitrit0_Clonador.exe') -Destino 'App\MotorClonador\Nitrit0 Clonador.exe' -Titulo 'Nitrit0 Clonador' | Out-Null
    } elseif (Test-Path -LiteralPath $ExeClonador) { Copy-Item -LiteralPath $ExeClonador -Destination (Join-Path $dest 'Nitrit0_Clonador.exe') } else { Write-Host '  AVISO: falta Nitrit0_Clonador.exe (npm run clonador); el pack sale sin ella.' -ForegroundColor Yellow }
    }

    # Datos: NUNCA se copia la carpeta Datos del repositorio. Se crea vacía y solo lleva un kit.id nuevo, Ajustes.json limpio e Integridad.json recién calculado.
    # (El pack público no lleva ni siquiera subcarpetas ni Favoritos/Versiones: el kit las crea al usarse.)
    $dat = Join-Path $dest 'Datos'
    New-Item -ItemType Directory -Force $dat | Out-Null
    [IO.File]::WriteAllText((Join-Path $dat 'kit.id'), [guid]::NewGuid().ToString(), $utf8)
    if ($Personal) {
        foreach ($d in 'Historial', 'Informes', 'Logs', 'Salidas', 'Respaldo') { New-Item -ItemType Directory -Force (Join-Path $dat $d) | Out-Null }
        foreach ($f in 'Favoritos.json', 'Versiones.json') { $o = Join-Path $raiz "Datos\$f"; if (Test-Path -LiteralPath $o) { Copy-Item -LiteralPath $o -Destination $dat } }
    }
    $aj = [ordered]@{ Tema = 'oscuro'; Tecnico = ''; QuitarDriverAlSalir = $false; SensoresDriver = 'no'; Modo = $(if ($Personal) { 'tecnico' } else { 'sencillo' }); OcultarPeligro = (-not $Personal) }
    [IO.File]::WriteAllText((Join-Path $dat 'Ajustes.json'), ($aj | ConvertTo-Json), (New-Object Text.UTF8Encoding($true)))

    # Solo el pack personal: licencia de WinRAR y Office 2013
    if ($Personal) {
        $ea = Join-Path $extras 'Apps'
        if ((Test-Path -LiteralPath (Join-Path $ea 'Licencias')) -or (Test-Path -LiteralPath (Join-Path $ea 'Instaladores\Office2013'))) {
            Copy-Carpeta $ea (Join-Path $dest 'Apps') @('Pendiente - Instaladores')
        } else { Write-Host "  AVISO: no hay $ea; el pack personal sale sin Office ni licencia de WinRAR." -ForegroundColor Yellow }
    }

    # LEEME y huellas
    $leeme = if ($Personal) { $script:LeemePersonal } elseif ($Lite) { $script:LeemeLite } else { $script:LeemePublico }
    [IO.File]::WriteAllText((Join-Path $dest 'LEEME.txt'), $leeme, (New-Object Text.UTF8Encoding($true)))
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dest 'Scripts\Regenerar_Integridad.ps1') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Regenerar_Integridad.ps1 falló en $Nombre (código $LASTEXITCODE): el pack no se da por bueno" }
    $l = New-Object Collections.Generic.List[string]
    $l.Add('HERRAMIENTAS DEL PACK Y SUS HUELLAS (SHA-256)'); $l.Add('Generado: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm'))
    $l.Add('Compara la huella con la que publica el autor de cada programa. «Sin firma» es habitual en herramientas pequeñas y no prueba nada por sí solo.'); $l.Add('')
    $l.Add('Nitrit0.exe (app de este kit, sin firmar): ' + (Get-FileHash -LiteralPath (Join-Path $dest 'Nitrit0.exe') -Algorithm SHA256).Hash)
    foreach ($r in 'App\Motor\Nitrit0 Kit.exe', 'App\Motor\resources\app.asar') { $p = Join-Path $dest $r; if (Test-Path -LiteralPath $p) { $l.Add("$r : " + (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash) } }
    if (Test-Path -LiteralPath (Join-Path $dest 'Nitrit0_Antivirus.exe')) { $l.Add('Nitrit0_Antivirus.exe (revisa archivos con Defender, VirusTotal, la firma digital y, en el personal, ClamAV; sin firmar): ' + (Get-FileHash -LiteralPath (Join-Path $dest 'Nitrit0_Antivirus.exe') -Algorithm SHA256).Hash) }
    if (Test-Path -LiteralPath (Join-Path $dest 'Nitrit0_Clonador.exe')) { $l.Add('Nitrit0_Clonador.exe (clona un disco con Windows a otro; solo pack personal, sin firmar): ' + (Get-FileHash -LiteralPath (Join-Path $dest 'Nitrit0_Clonador.exe') -Algorithm SHA256).Hash) }
    if (Test-Path -LiteralPath (Join-Path $dest 'Nitrit0_Limpieza.exe')) { $l.Add('Nitrit0_Limpieza.exe (limpiador y programas de inicio, sin firmar): ' + (Get-FileHash -LiteralPath (Join-Path $dest 'Nitrit0_Limpieza.exe') -Algorithm SHA256).Hash) }
    $l.Add('')
    $l.Add('Ruta | MB | Firma | Firmante | SHA-256')
    foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $dest 'Apps') -Recurse -File -Filter *.exe | Sort-Object FullName)) {
        $s = Get-AuthenticodeSignature -LiteralPath $f.FullName
        $firmante = if ($s.SignerCertificate) { ($s.SignerCertificate.Subject -replace '^.*?CN=([^,]+).*$', '$1') } else { '' }
        $l.Add(('{0} | {1:N1} | {2} | {3} | {4}' -f $f.FullName.Substring($dest.Length + 1), ($f.Length / 1MB), $s.Status, $firmante, (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash))
    }
    [IO.File]::WriteAllText((Join-Path $dest 'Herramientas_y_huellas.txt'), ($l -join "`r`n"), (New-Object Text.UTF8Encoding($true)))

    # Comprobación común: todo lo que el catálogo de la app referencia existe en el pack y consta con huella en Integridad.json
    $cat = Get-Content -LiteralPath (Join-Path $dest 'App\datos\herramientas.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $manif = @{}; foreach ($x in (Get-Content -LiteralPath (Join-Path $dat 'Integridad.json') -Raw -Encoding UTF8 | ConvertFrom-Json)) { $manif[$x.R.ToLower()] = $x.H }
    $roto = New-Object Collections.Generic.List[string]
    foreach ($e in $cat.elementos) { if ($e.script -and ($Personal -or $e.script -notmatch 'Clonar_Disco\.ps1$')) { $rel = Join-Path 'Scripts' $e.script; if (-not (Test-Path -LiteralPath (Join-Path $dest $rel))) { $roto.Add("falta $rel") } elseif (-not $manif[$rel.ToLower()]) { $roto.Add("sin huella $rel") } } }
    foreach ($rel in 'App\datos\herramientas.json', 'Scripts\Ejecutar_Para_App.ps1', 'Scripts\Comun.ps1', 'Scripts\Ajustes_Para_App.ps1', 'Scripts\Resumen_Sistema.ps1', 'Scripts\SMART_Detalle.ps1', 'Scripts\Informe_Rapido.ps1', 'Scripts\Memoria_Para_App.ps1') { if (-not $manif[$rel.ToLower()]) { $roto.Add("sin huella $rel") } }
    if ($roto.Count) { throw "El catálogo de la app referencia cosas que no están en el pack: $(($roto | Select-Object -First 10) -join '; ')" }
    Write-Host "  Comprobado: el catálogo de la app ($($cat.elementos.Count) elementos) encaja con los scripts y las huellas del pack." -ForegroundColor Green

    # Comprobación por LISTA BLANCA del pack público: si aparece algo no previsto, el build falla
    if (-not $Personal) {
        $permitidoDatos = 'Ajustes.json', 'Integridad.json', 'kit.id'   # kit.id: identifica el kit si el pendrive vuelve con otra letra (es un GUID nuevo, sin datos)
        $sobra = @(Get-ChildItem -LiteralPath $dat -Force | Where-Object { $_.Name -notin $permitidoDatos })
        $faltan = @($permitidoDatos | Where-Object { -not (Test-Path -LiteralPath (Join-Path $dat $_) -PathType Leaf) })
        $prohibido = @(Get-ChildItem -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue | Where-Object {
            ($_.PSIsContainer -and $_.Name -in '_Extras_Personales', '.git', 'Office2013') -or (-not $_.PSIsContainer -and ($_.Extension -in '.key', '.lic', '.log', '.bak', '.tmp', '.rar', '.pst', '.kdbx' -or $_.Name -match '^rarreg|^office.*\.txt$')) })
        # Además de nombres: busca por CONTENIDO claves de WinRAR, claves de producto (25 caracteres) y claves de recuperación de BitLocker en ficheros de texto de Apps\
        $extTexto = '.txt', '.xml', '.ini', '.cfg', '.json', '.csv', '.md', '.html', '.htm', '.reg', '.bat', '.cmd', '.conf', '.lic', '.key'
        $conClave = @(Get-ChildItem -LiteralPath (Join-Path $dest 'Apps') -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in $extTexto -and $_.Length -lt 5MB } |
            Select-String -Pattern 'RAR registration data', '\b[A-Z0-9]{5}(-[A-Z0-9]{5}){4}\b', '\b\d{6}(-\d{6}){7}\b' -List -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Path.Substring($dest.Length + 1)) -> $($_.Pattern)" })
        if (Get-ChildItem -LiteralPath $dest -Recurse -Force -Filter 'Desactivar_SmartAppControl.bat' -ErrorAction SilentlyContinue) { throw 'El pack público lleva Desactivar_SmartAppControl.bat: es solo del pack personal.' }
        if ((Test-Path -LiteralPath (Join-Path $dest 'Nitrit0_Antivirus.exe')) -or (Test-Path -LiteralPath (Join-Path $dest 'App\MotorAntivirus')) -or (Test-Path -LiteralPath (Join-Path $dest 'Apps\Antivirus'))) { throw 'Este pack lleva el antivirus (y ClamAV): es solo del pack personal.' }
        if ((Test-Path -LiteralPath (Join-Path $dest 'Nitrit0_Clonador.exe')) -or (Test-Path -LiteralPath (Join-Path $dest 'App\MotorClonador'))) { throw 'El pack público lleva Nitrit0_Clonador.exe: es solo del pack personal.' }
        if (Test-Path -LiteralPath (Join-Path $dest 'Scripts\Mantenimiento\Clonar_Disco.ps1')) { throw 'El pack público lleva Clonar_Disco.ps1: es solo del pack personal.' }
        if ($conClave) { throw "El pack público lleva ficheros con aspecto de clave/licencia: $($conClave -join '; ')" }
        if ($sobra -or $faltan -or $prohibido) { throw "El pack público no pasa la lista blanca. Sobra en Datos: [$(($sobra | ForEach-Object { $_.Name }) -join ', ')]. Falta en Datos: [$($faltan -join ', ')]. Prohibido: [$(($prohibido | ForEach-Object { $_.FullName }) -join '; ')]" }
        $aj2 = Get-Content -LiteralPath (Join-Path $dat 'Ajustes.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($aj2.Modo -ne 'sencillo' -or $aj2.OcultarPeligro -ne $true) { throw 'Ajustes.json del pack público debe llevar Modo = sencillo y OcultarPeligro = true.' }
        Write-Host '  Comprobado (lista blanca): Datos solo con Ajustes.json, Integridad.json y kit.id; sin licencias, claves, logs ni copias de seguridad.' -ForegroundColor Green
    }
    $mb = [math]::Round((Get-ChildItem -LiteralPath $dest -Recurse -File -Force | Measure-Object Length -Sum).Sum / 1MB)
    Write-Host "  Listo: $dest ($mb MB)" -ForegroundColor Green
}

$script:LeemePublico = @'
KIT NITRIT0 - LÉEME (versión para usuarios y amigos)
=====================================================

Qué es
  Un kit de herramientas para revisar y mantener un PC con Windows: diagnóstico, limpieza,
  red, discos, memoria, pantalla... con explicaciones en castellano.

Cómo se usa
  1. Copia esta carpeta entera a tu PC o déjala en el pendrive.
  2. Abre "Nitrit0.exe" (pide permisos de administrador). Empieza en modo sencillo: te pregunta qué le pasa al equipo.
  3. Windows puede mostrar un aviso de «editor desconocido» porque el programa no está firmado. Antes de continuar, comprueba que te lo ha dado
     directamente quien lo hizo y que la huella de "Nitrit0.exe" coincide con la de "Herramientas_y_huellas.txt". Si tienes dudas, no sigas.

Extra: "Nitrit0_Limpieza.exe" (también como administrador) limpia temporales, cachés y restos eligiendo qué borrar, y gestiona lo que arranca con Windows.

Qué NO hace
  - No envía datos de tu equipo a ningún sitio: los informes y registros se guardan en la carpeta temporal de tu PC y no quedan en este pendrive.
    Sí usa Internet para lo que tú le pidas: descargar programas de las webs oficiales de sus fabricantes, actualizar Windows y consultar
    las actualizaciones de HP o Lenovo.
  - No lleva licencias ni claves de nadie. Programas como WinRAR se instalan en modo de prueba.
  - Las herramientas más delicadas (borrar programas a fondo, claves guardadas, actualizar Windows...) están ocultas.

Antes de arreglar nada
  - Haz copia de tus archivos importantes. Las herramientas de reparación cambian cosas del sistema;
    casi todas se pueden deshacer desde «Deshacer cambios», pero ningún programa es infalible.
  - Si algo te sale raro, no sigas pulsando: pide ayuda a quien te lo pasó.

Herramientas de terceros
  Cada programa de la carpeta Apps es de su autor y se usa con su propia licencia (la mayoría, gratuita para uso personal).
  "Herramientas_y_huellas.txt" lista cada uno con su firma y su huella para que puedas comprobarlos en la web del autor.

Responsabilidad
  Este kit se entrega tal cual, sin garantía. Úsalo bajo tu responsabilidad y en equipos tuyos o con permiso de su dueño.
'@

$script:LeemeApps = @'
Esta versión NO incluye las herramientas portables de terceros (CPU-Z, HWiNFO, CrystalDiskInfo, OCCT, antivirus portables...).
Cada una tiene su propia licencia y su autor la distribuye desde su web oficial: descárgala de allí, comprueba su firma y su huella
y copia su carpeta aquí dentro (por ejemplo Apps\Disk\CrystalDiskInfo...). Las herramientas que falten aparecen en el kit como
«No está en la carpeta Apps»; todo lo demás (los scripts propios y las pruebas del equipo) funciona sin ellas.
'@

$script:LeemeLite = @'
KIT NITRIT0 - LÉEME (versión Lite)
=====================================================

Qué es
  Un kit de herramientas para revisar y mantener un PC con Windows: diagnóstico, revisión total, pruebas de pantalla, teclado, ratón,
  webcam, audio, mando, procesador y placa de vídeo, limpieza, red, discos... con explicaciones en castellano.
  Esta versión Lite lleva la app y los scripts del kit, pero NO las herramientas portables de terceros (carpeta Apps, ver Apps\LEEME.txt).

Cómo se usa
  1. Descomprime esta carpeta entera en tu PC o en un pendrive.
  2. Abre "Nitrit0.exe" (pide permisos de administrador). Empieza en modo sencillo: te pregunta qué le pasa al equipo.
  3. Windows puede mostrar un aviso de «editor desconocido» (SmartScreen) porque el programa no está firmado. Comprueba que la huella
     SHA-256 de "Nitrit0.exe" coincide con la de "Herramientas_y_huellas.txt" y con la publicada junto a la descarga. Si tienes dudas, no sigas.

Qué NO hace
  - No envía datos de tu equipo a ningún sitio: los informes y registros se guardan en la carpeta temporal de tu PC.
    Sí usa Internet para lo que tú le pidas (descargar programas de sus webs oficiales, actualizar Windows).
  - Las herramientas más delicadas están ocultas en este paquete.

Antes de arreglar nada
  - Haz copia de tus archivos importantes. Casi todos los cambios se pueden deshacer desde «Deshacer cambios», pero ningún programa es infalible.

Responsabilidad
  Este kit se entrega tal cual, sin garantía y bajo licencia MIT. Úsalo bajo tu responsabilidad y en equipos tuyos o con permiso de su dueño.
'@

$script:LeemePersonal = @'
KIT NITRIT0 - PACK PERSONAL
===========================
NO LO COMPARTAS: lleva la licencia de WinRAR (Apps\Licencias\rarreg.key) y el instalador de Office 2013 con su clave.
Todo está visible (modo técnico, sin ocultar herramientas peligrosas). Abre "Nitrit0.exe" como administrador.
Para el pack de usuarios y amigos usa Nitrit0_Kit_Publico.
Huellas de las herramientas: Herramientas_y_huellas.txt

Si Windows 11 bloquea Nitrit0.exe con «Control Inteligente de Aplicaciones» (los .exe de este kit no están firmados):
  Desactivar_SmartAppControl.bat (clic derecho > Ejecutar como administrador). Es IRREVERSIBLE y solo para TU equipo: apaga esa
  protección de Windows y no se puede volver a encender sin reinstalar. Con /simular solo muestra el estado.

Extra: "Nitrit0_Clonador.exe" es una app aparte para clonar un disco con Windows a otro (pide administrador; solo simula hasta que escribes la confirmación «BORRAR DISCO n»).
Extra: "Nitrit0_Antivirus.exe" revisa un archivo antes de abrirlo: con el Defender del equipo, con la firma digital y con VirusTotal (y con ClamAV, que se actualiza con Apps\Antivirus\ClamAV\Actualizar_base_de_firmas.bat; de VirusTotal solo envía la huella del archivo, nunca el archivo; hace falta tu propia clave gratuita de VirusTotal). Solo informa: no borra nada.
'@

if ($Lite) { New-Pack 'Nitrit0_Kit_Lite' $false $true }
else {
    New-Pack 'Nitrit0_Kit_Publico' $false
    New-Pack 'Nitrit0_Kit_Personal' $true
}
Write-Host "`nPacks en: $Destino" -ForegroundColor Cyan
