# Revisar y arreglar el equipo de forma automática, para la app (Nitrit0).
# 1) Analiza el equipo con el motor de diagnóstico rápido (el mismo de siempre).
# 2) Aplica SOLO las soluciones seguras que corresponden a lo que encontró, una tras otra y sin preguntar.
#    Cada paso tiene su tiempo máximo y se puede saltar: si un programa se queda colgado, se cierra y se sigue con el siguiente.
# 3) Vuelve a comprobar lo que tocó, y escribe un informe de lo detectado y lo cambiado.
# Lo que no se puede arreglar sin riesgo (discos que fallan, drivers, errores graves) NO se toca: se deja en «necesita atención».
# Entradas por entorno: NIT_AUTO_ACTUALIZAR=1 (instalar también las actualizaciones), NIT_AUTO_SALTAR (fichero que pide saltar el paso actual),
# NIT_DX_FICHA (cliente). Emite líneas ##AUTO##{json} que la app pinta; el resto es texto para la consola.
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$inicioTotal = Get-Date
$env:NIT_AUTO = '1'   # los scripts que preguntan algo (Puesta a punto rápida) saben así que deben seguir sin ventanas
$flagSaltar = $env:NIT_AUTO_SALTAR
$instalarActualizaciones = ($env:NIT_AUTO_ACTUALIZAR -eq '1')
$combo = @(); if ($env:NIT_COMBO) { $combo = @($env:NIT_COMBO -split ',' | Where-Object { $_ }) }   # modo «combo»: sin análisis, se aplican justo los pasos elegidos
$buscarVirus = ($env:NIT_AUTO_ANTIVIRUS -eq '1' -or $env:NIT_AUTO_ENFOQUE -eq 'virus')   # análisis rápido con Defender: es la opción «virus» o una casilla de «no sé qué le pasa»
# Qué le pasa al equipo, según la persona (lista cerrada): decide qué pruebas se miran. «todo» las mira todas y guarda el diagnóstico en el historial.
$enfoque = if ($env:NIT_AUTO_ENFOQUE -in 'lento', 'internet', 'avisos', 'virus', 'espacio') { $env:NIT_AUTO_ENFOQUE } else { 'todo' }
$pruebasEnfoque = @{ lento = 'cpu', 'memoria', 'discos', 'arranque'; internet = 'red'; avisos = 'eventos', 'integridad', 'dispositivos', 'smart', 'memoria', 'discos'; virus = 'seguridad', 'arranque'; espacio = 'discos' }
# Nombres que entiende cualquiera, en vez de los del diagnóstico técnico
$amigable = @{ sistema = 'Windows'; win11 = 'Compatibilidad con Windows 11'; cpu = 'Velocidad del procesador'; sensores = 'Temperatura'; memoria = 'Memoria'; discos = 'Discos y espacio'; bateria = 'Batería'; gpu = 'Tarjeta gráfica'
    dispositivos = 'Piezas con problemas'; perifericos = 'Cámara, sonido y Bluetooth'; red = 'Internet'; eventos = 'Errores de Windows'; smart = 'Estado del disco'; integridad = 'Archivos de Windows'; seguridad = 'Protección contra virus'
    actualizaciones = 'Actualizaciones de Windows'; arranque = 'Programas que arrancan con el ordenador' }

# Se escribe directamente en la consola: así una función puede avisar sin que su texto se mezcle con lo que devuelve.
function Send-Auto($o) { [Console]::Out.WriteLine('##AUTO##' + ($o | ConvertTo-Json -Compress -Depth 8)); [Console]::Out.Flush() }
function Say([string]$t) { [Console]::Out.WriteLine($t); [Console]::Out.Flush() }
$Taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
$PowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$carpetaTmp = Join-Path $env:TEMP 'Nitrit0_Cache\Auto'
try { New-Item -ItemType Directory -Force $carpetaTmp | Out-Null; Get-ChildItem $carpetaTmp -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1) } | Remove-Item -Force -ErrorAction SilentlyContinue } catch { }
if ($flagSaltar -and (Test-Path -LiteralPath $flagSaltar)) { Remove-Item -LiteralPath $flagSaltar -Force -ErrorAction SilentlyContinue }
$confirmar = $env:NIT_AUTO_CONFIRMAR   # fichero con la respuesta de la persona al plan (qué pasos hacer); sin él, se aplica todo el plan
if ($confirmar -and (Test-Path -LiteralPath $confirmar)) { Remove-Item -LiteralPath $confirmar -Force -ErrorAction SilentlyContinue }
$soloMirar = $false

# Lo que dice el diagnóstico, en una frase que entiende cualquiera. Si no se reconoce, se deja el texto original.
function Llano([string]$id, [string]$r) {
    switch -Regex ($r) {
        'reinicio pendiente' { return 'Windows tiene cambios pendientes que solo se aplican al reiniciar.' }
        'sin reiniciarse' { return 'Lleva muchos días sin reiniciarse.' }
        'no está activado' { return 'Windows no está activado.' }
        'casi sin espacio|poco espacio' { return 'Queda poco espacio libre en el disco.' }
        'estado de salud|predice un fallo|casi agotado|operativo' { return 'Un disco avisa de que puede fallar: conviene copiar tus datos cuanto antes.' }
        'desgaste|temperatura (alta|crítica)' { return 'Un disco está desgastado o se calienta más de lo normal.' }
        'Memoria casi llena' { return 'La memoria está casi llena.' }
        'Sin acceso a internet' { return 'No hay conexión a Internet.' }
        'resolución de nombres' { return 'Internet va mal: no encuentra las páginas.' }
        'puerta de enlace' { return 'El router no responde.' }
        'Pérdida de paquetes' { return 'La conexión se corta a ratos.' }
        'Latencia alta' { return 'La conexión va lenta.' }
        'Wi-Fi débil' { return 'La señal Wi-Fi es débil.' }
        'Sin conexión de red activa' { return 'El ordenador no está conectado a ninguna red.' }
        'Defender sin protección' { return 'La protección contra virus está apagada.' }
        'Firmas del antivirus' { return 'El antivirus está desactualizado.' }
        'firewall' { return 'Falta activar la protección de red (el cortafuegos).' }
        'última actualización' { return 'Windows lleva meses sin actualizarse.' }
        'Demasiados programas al arrancar' { return 'Arrancan demasiados programas con el ordenador.' }
        'dañada|reparable' { return 'Hay archivos de Windows dañados.' }
    }
    switch ($id) {
        'eventos' { return 'Windows ha registrado errores graves o apagados inesperados.' }
        'dispositivos' { return 'Hay piezas del ordenador con errores.' }
        'sensores' { return 'El ordenador se calienta más de lo normal.' }
        'cpu' { return 'El procesador está muy cargado.' }
        'bateria' { return 'La batería está desgastada.' }
    }
    return $r
}

function Convertir-Marca($linea) {
    $tipo = if ($linea.Contains([string][char]0x274C)) { 'error' } elseif ($linea.Contains([string][char]0x26A0)) { 'aviso' } elseif ($linea.Contains([string][char]0x2705)) { 'ok' } else { '' }
    $texto = ($linea -replace '[\uD800-\uDFFF]|[ℹ✅❌⚠⏳✔✖❗⭐♻️]', '').Trim()
    [pscustomobject]@{ Tipo = $tipo; Texto = $texto }
}

# Lee lo nuevo de un fichero que otro proceso sigue escribiendo; solo toma líneas completas (no parte un carácter UTF-8 por la mitad).
function Read-Nuevo([string]$ruta, [ref]$pos) {
    try {
        $fs = [IO.File]::Open($ruta, 'Open', 'Read', 'ReadWrite')
        try {
            if ($fs.Length -le $pos.Value) { return '' }
            [void]$fs.Seek($pos.Value, 'Begin')
            $buf = New-Object byte[] ($fs.Length - $pos.Value)
            $n = $fs.Read($buf, 0, $buf.Length)
            $ult = [Array]::LastIndexOf($buf, [byte]10, $n - 1)
            if ($ult -lt 0) { return '' }
            $pos.Value += ($ult + 1)
            return [Text.Encoding]::UTF8.GetString($buf, 0, $ult + 1)
        } finally { $fs.Dispose() }
    } catch { return '' }
}

# Ejecuta un script del kit en un proceso aparte, con tiempo máximo y posibilidad de saltarlo. Devuelve cómo acabó y las líneas que escribió.
function Invoke-Hijo($a) {
    $ruta = if ([IO.Path]::IsPathRooted($a.Script)) { $a.Script } else { Join-Path $PSScriptRoot $a.Script }
    $salida = Join-Path $carpetaTmp ("{0}_{1}.txt" -f $a.Id, $PID); $errores = $salida + '.err'
    foreach ($f in $salida, $errores) { try { Set-Content -LiteralPath $f -Value '' -Encoding UTF8 } catch { } }
    $arg = '-NoProfile -ExecutionPolicy Bypass -STA -File "{0}" -Script "{1}"' -f (Join-Path $PSScriptRoot 'Ejecutar_Para_App.ps1'), $ruta
    $t0 = Get-Date
    $p = Start-Process -FilePath $PowerShellExe -ArgumentList $arg -WindowStyle Hidden -PassThru -RedirectStandardOutput $salida -RedirectStandardError $errores
    $null = $p.Handle   # sin esto, ExitCode llega vacío en Windows PowerShell 5.1 cuando el proceso termina
    $pos = [long]0; $lineas = New-Object 'Collections.Generic.List[object]'; $ultimoEstado = [datetime]::MinValue
    $final = 'normal'
    $leer = {
        $trozo = Read-Nuevo $salida ([ref]$pos)
        if ($trozo) {
            foreach ($l in ($trozo -split "`r?`n")) {
                $l = $l.Trim(); if (-not $l -or $l -match '^\W{0,3}#< CLIXML' -or $l -match '^\W{0,3}<Objs ' -or $l -match '^=+$') { continue }
                $m = Convertir-Marca $l; if (-not $m.Texto) { continue }
                $lineas.Add($m); $script:ultimaLineaHijo = $m.Texto
                Say ('    ' + $m.Texto)
            }
            $script:ultimaActividad = Get-Date
        }
    }
    $script:ultimaActividad = Get-Date; $script:ultimaLineaHijo = ''
    while (-not $p.HasExited) {
        Start-Sleep -Milliseconds 700
        & $leer
        $seg = ((Get-Date) - $t0).TotalSeconds
        if ($flagSaltar -and (Test-Path -LiteralPath $flagSaltar)) { Remove-Item -LiteralPath $flagSaltar -Force -ErrorAction SilentlyContinue; $final = 'saltado'; break }
        if ($seg -gt $a.Max) { $final = 'tiempo'; break }
        if (((Get-Date) - $ultimoEstado).TotalSeconds -ge 3) {
            $ultimoEstado = Get-Date
            Send-Auto @{ t = 'estado'; id = $a.Id; seg = [int]$seg; silencio = [int]((Get-Date) - $script:ultimaActividad).TotalSeconds; texto = $script:ultimaLineaHijo }
        }
    }
    if ($final -ne 'normal') { try { & $Taskkill /PID $p.Id /T /F 2>&1 | Out-Null } catch { }; [void]$p.WaitForExit(8000) }
    else { [void]$p.WaitForExit(3000) }
    Start-Sleep -Milliseconds 300; & $leer
    $codigo = if ($final -eq 'normal') { $p.ExitCode } else { $null }
    foreach ($f in $salida, $errores) { try { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } catch { } }   # la salida no se deja en el equipo del cliente
    [pscustomobject]@{ Final = $final; Codigo = $codigo; Seg = [int]((Get-Date) - $t0).TotalSeconds; Lineas = $lineas }
}

# Traduce los avisos del motor de diagnóstico a progreso para la app (la pantalla pinta «n de N pruebas»).
$totalPruebas = 0; $hechasPruebas = 0
function Convertir-Dx($linea, [string]$fase) {
    if (-not ($linea -is [string]) -or -not $linea.StartsWith('##DX##')) { return }
    try { $j = $linea.Substring(6) | ConvertFrom-Json } catch { return }
    if ($j.t -eq 'plan') { $script:totalPruebas = @($j.pruebas).Count; $script:hechasPruebas = 0; $script:nombresPlan = @{}; foreach ($q in $j.pruebas) { $script:nombresPlan[[string]$q.id] = [string]$q.nombre } }
    elseif ($j.t -eq 'inicio') { Send-Auto @{ t = 'analisis'; fase = $fase; hechas = $script:hechasPruebas; total = $script:totalPruebas; actual = $(if ($amigable[[string]$j.id]) { $amigable[[string]$j.id] } else { [string]$script:nombresPlan[[string]$j.id] }) } }
    elseif ($j.t -eq 'fin') { $script:hechasPruebas++; Send-Auto @{ t = 'analisis'; fase = $fase; hechas = $script:hechasPruebas; total = $script:totalPruebas; actual = '' } }
}

# ---------------------------------------------------------------------
#  1. Análisis
# ---------------------------------------------------------------------
if ($combo.Count) { $antes = [ordered]@{}; $nombrePrueba = @{}; $clienteFicha = ''; if ($env:NIT_DX_FICHA) { try { $clienteFicha = [string](($env:NIT_DX_FICHA | ConvertFrom-Json).Cliente) } catch { } } }
else {
Say 'Revisando el equipo…'
Send-Auto @{ t = 'fase'; fase = 'analisis'; linea = 'Revisando el equipo' }
$env:NIT_DX_MODO = 'Rapido'
if ($enfoque -eq 'todo') { $env:NIT_DX_IDS = ''; Remove-Item Env:\NIT_DX_SINGUARDAR -ErrorAction SilentlyContinue }
else { $env:NIT_DX_IDS = ($pruebasEnfoque[$enfoque] -join ','); $env:NIT_DX_SINGUARDAR = '1' }   # una revisión parcial no se guarda como si fuera un diagnóstico completo
. (Join-Path $PSScriptRoot 'Diagnostico_Para_App.ps1') | ForEach-Object { Convertir-Dx $_ 'analisis' }
$antes = $res; $clienteFicha = [string]$ficha.Cliente
$nombrePrueba = @{}; foreach ($k in $antes.Keys) { $nombrePrueba[$k] = if ($amigable[$k]) { $amigable[$k] } else { [string]$antes[$k].Nombre } }
if (-not $antes -or $antes.Count -eq 0) {
    Say 'No se pudo analizar el equipo.'
    Send-Auto @{ t = 'error'; texto = 'El análisis no devolvió ningún resultado. Cierra los programas pesados y vuelve a intentarlo.' }
    exit 1
}
}
function Mal([string]$id) { $x = $antes[$id]; return [bool]($x -and ($x.Estado -in 'Aviso', 'Fallo')) }
function Texto([string]$id) { if ($antes[$id]) { return [string]$antes[$id].Resumen } return '' }

# ---------------------------------------------------------------------
#  2. Qué se arregla (solo lo seguro y lo que corresponde a lo detectado)
# ---------------------------------------------------------------------
$mDisco = $null; if ($antes['discos']) { $mDisco = $antes['discos'].Metricas }
$pocoEspacio = [bool]((Mal 'discos') -and $mDisco -and $null -ne $mDisco['LibreCPct'] -and [int]$mDisco['LibreCPct'] -lt 15)
$catalogo = @(
    @{ Id = 'restauracion'; Hecho = 'He guardado una copia de seguridad de la configuración de Windows por si hay que volver atrás.'; Titulo = 'Guardar una copia de seguridad de la configuración'; Que = 'Guarda el estado actual de Windows para poder volver atrás si algo sale mal.'; Script = 'Mantenimiento\Punto_Restauracion.ps1'; Max = 420; Min = 1; Pruebas = @(); Reinicio = $false; Cuando = $null }
    @{ Id = 'limpieza'; Hecho = 'He borrado archivos temporales que sobraban y he liberado memoria.'; Titulo = 'Liberar espacio y memoria'; Que = 'Borra los archivos temporales con más de un día y libera memoria. No toca tus documentos ni cierra programas.'; Script = 'Mantenimiento\Puesta_a_Punto_Rapida.ps1'; Max = 600; Min = 2; Pruebas = @('discos', 'memoria'); Reinicio = $false; Cuando = ($pocoEspacio -or (Mal 'memoria') -or $enfoque -in 'lento', 'espacio') }
    @{ Id = 'limpieza_profunda'; Hecho = 'He hecho una limpieza a fondo de temporales y navegadores.'; Titulo = 'Limpieza a fondo de temporales y navegadores'; Que = 'Borra los temporales del sistema y la caché de los navegadores. Conviene cerrar los navegadores antes.'; Script = 'Mantenimiento\LimpiarTemporalesEquipo.ps1'; Max = 1800; Min = 5; Pruebas = @(); Reinicio = $false; Cambia = $false; Cuando = $false }
    @{ Id = 'red'; Hecho = 'He reparado la configuración de Internet.'; Titulo = 'Reparar la conexión a Internet'; Que = 'Vacía la caché de nombres, renueva la dirección de red y restablece la configuración de red de Windows.'; Script = 'Mantenimiento\Reparar_Red.ps1'; Max = 420; Min = 2; Pruebas = @('red'); Reinicio = $true; Cuando = ((Mal 'red') -and ((Texto 'red') -match 'Sin acceso a internet|resolución de nombres|puerta de enlace')) }
    @{ Id = 'seguridad'; Hecho = 'He encendido y actualizado la protección contra virus.'; Titulo = 'Activar la protección de Windows'; Que = 'Enciende el antivirus de Windows y el firewall y actualiza sus firmas. Si hay otro antivirus, no lo toca.'; Script = 'Mantenimiento\Activar_Seguridad_Windows.ps1'; Max = 600; Min = 3; Pruebas = @('seguridad'); Reinicio = $false; Cuando = (Mal 'seguridad') }
    @{ Id = 'antivirus'; Hecho = 'He analizado el equipo con el antivirus de Windows.'; Titulo = 'Buscar virus con el antivirus de Windows'; Que = 'Hace un análisis rápido con Microsoft Defender y deja que el antivirus trate lo que encuentre.'; Script = 'Antivirus_Para_App.ps1'; Max = 1800; Min = 8; Pruebas = @(); Reinicio = $false; Cambia = $false; Cuando = $buscarVirus }
    @{ Id = 'wu'; Hecho = 'He reparado el sistema de actualizaciones de Windows.'; Titulo = 'Reparar Windows Update'; Que = 'Restablece los componentes de actualización de Windows. No borra nada: las carpetas antiguas se conservan con copia.'; Script = 'Mantenimiento\Restablecer_Windows_Update.ps1'; Max = 600; Min = 3; Pruebas = @('actualizaciones'); Reinicio = $true; Verifica = $false; Cuando = (Mal 'actualizaciones') }
    @{ Id = 'actualizar'; Hecho = 'He instalado las actualizaciones de Windows.'; Titulo = 'Instalar las actualizaciones de Windows'; Que = 'Descarga e instala las actualizaciones pendientes. No reinicia solo.'; Script = 'Mantenimiento\Actualizar_Windows.ps1'; Max = 5400; Min = 45; Pruebas = @('actualizaciones'); Reinicio = $true; Cuando = ($instalarActualizaciones -and (Mal 'actualizaciones')) }
    @{ Id = 'actualizar_programas'; Hecho = 'He actualizado los programas instalados.'; Titulo = 'Actualizar los programas instalados'; Que = 'Actualiza con winget todos los programas que lo permiten, en silencio.'; Script = 'Mantenimiento\Actualizar_Software.ps1'; Max = 4200; Min = 20; Pruebas = @(); Reinicio = $false; Cuando = $false }
    @{ Id = 'integridad'; Hecho = 'He reparado archivos de Windows que estaban dañados.'; Titulo = 'Reparar los archivos de Windows'; Que = 'Comprueba el disco y repara los archivos del sistema dañados (DISM y SFC). Es lo que más tarda.'; Script = 'Mantenimiento\Reparar_Windows_y_Tienda.ps1'; Max = 5400; Min = 25; Pruebas = @('integridad', 'sfc'); Reinicio = $false; Cuando = ((Mal 'integridad') -or (Mal 'sfc')) }
    @{ Id = 'optimizar'; Hecho = 'He optimizado el rendimiento de Windows.'; Titulo = 'Optimizar el rendimiento de Windows'; Que = 'Ajusta el arranque y la memoria virtual, optimiza el disco y limpia restos de actualizaciones. Se puede deshacer con «Deshacer cambios».'; Script = 'Mantenimiento\Optimizar_Rendimiento.ps1'; Max = 3600; Min = 15; Pruebas = @(); Reinicio = $false; Cuando = $false }
    @{ Id = 'deshacer'; Hecho = 'He deshecho los últimos cambios.'; Titulo = 'Deshacer los últimos cambios'; Que = 'Devuelve ajustes, servicios y configuración a como estaban antes de la última revisión. No recupera los archivos temporales que se borraron.'; Script = 'Mantenimiento\Deshacer_Cambios.ps1'; Max = 600; Min = 1; Pruebas = @(); Reinicio = $false; Cambia = $false; Cuando = $false }
)
# Solo para pruebas del kit: NIT_AUTO_FORZAR=limpieza,prueba obliga a incluir esos pasos; «prueba» ejecuta el script de NIT_AUTO_PRUEBA (ruta completa) con el tiempo máximo NIT_AUTO_PRUEBA_MAX.
$forzar = @(); if ($env:NIT_AUTO_FORZAR) { $forzar = @($env:NIT_AUTO_FORZAR -split ',' | Where-Object { $_ }) }
if ($env:NIT_AUTO_PRUEBA) { $catalogo += @{ Id = 'prueba'; Titulo = 'Paso de prueba'; Que = 'Paso de prueba de las herramientas del kit.'; Script = $env:NIT_AUTO_PRUEBA; Max = $(if ($env:NIT_AUTO_PRUEBA_MAX) { [int]$env:NIT_AUTO_PRUEBA_MAX } else { 600 }); Min = 1; Pruebas = @($env:NIT_AUTO_PRUEBA_CUBRE -split ',' | Where-Object { $_ }); Reinicio = $false; Cuando = $false } }
$pasosPlan = @(if ($combo.Count) { @($catalogo | Where-Object { $_.Id -in $combo -and $_.Id -notin 'restauracion', 'prueba' }) } else { @($catalogo | Where-Object { ($_.Cuando -or $_.Id -in $forzar) -and $_.Id -ne 'restauracion' }) })
if (@($pasosPlan | Where-Object { $_.Cambia -ne $false -and $_.Id -ne 'limpieza' }).Count -gt 0) { $pasosPlan = @($catalogo[0]) + $pasosPlan }   # el punto de restauración va primero, solo si se va a cambiar algo del sistema. ($plan lo usa el motor de diagnóstico: otro nombre)

$cubiertas = @{}; foreach ($a in $pasosPlan) { foreach ($t in $a.Pruebas) { $cubiertas[$t] = $true } }
$consejos = @{
    discos = 'Si el disco avisa de fallos o desgaste, haz copia de los datos importantes y cámbialo cuanto antes.'
    smart = 'El disco avisa de un posible fallo: haz copia de tus datos cuanto antes.'
    eventos = 'Windows ha registrado errores graves o apagados inesperados. Conviene averiguar la causa (controladores, memoria, disco o temperatura).'
    dispositivos = 'Hay dispositivos con errores, normalmente un controlador que falta o falla.'
    cpu = 'Algo está usando mucho procesador. Mira qué programa es.'
    sensores = 'Temperaturas altas: limpia el polvo y revisa la ventilación.'
    bateria = 'La batería está desgastada. Si el portátil dura poco, habrá que cambiarla.'
    arranque = 'Hay muchos programas que arrancan con Windows. Desactivar los que no hagan falta acelera el inicio.'
    actualizaciones = 'Windows lleva tiempo sin actualizarse. Instala las actualizaciones y reinicia.'
    win11 = 'Este equipo puede no ser compatible con la versión actual de Windows.'
    gpu = 'La tarjeta gráfica tiene un aviso: revisa los controladores.'
    perifericos = 'Un periférico (cámara, audio o Bluetooth) no está bien: revisa sus controladores.'
    memoria = 'La memoria está casi llena. Cierra programas o amplía la RAM.'
    red = 'La red sigue con problemas: revisa el router, el cable o la señal Wi-Fi.'
}

# Tiempos medidos en equipos anteriores (solo id del paso y segundos): sustituyen a la estimación fija cuando existen
$archivoTiempos = $null; $tiempos = @{}
try { $archivoTiempos = Join-Path (Get-KitDatos) 'Tiempos_Pasos.json' } catch { }
if ($archivoTiempos -and (Test-Path -LiteralPath $archivoTiempos)) {
    try { foreach ($q in (Get-Content -LiteralPath $archivoTiempos -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties) { $tiempos[$q.Name] = @{ n = [int]$q.Value.n; seg = [double]$q.Value.seg } } } catch { }
}
foreach ($a in $catalogo) { $tm = $tiempos[$a.Id]; if ($tm -and $tm.n -ge 1) { $a.Min = [math]::Max(1, [int][math]::Round($tm.seg / 60)) } }
Send-Auto @{ t = 'plan'
    detectados = @($antes.Keys | Where-Object { $antes[$_].Estado -in 'Aviso', 'Fallo' } | ForEach-Object { @{ id = $_; nombre = $nombrePrueba[$_]; estado = [string]$antes[$_].Estado; resumen = [string]$antes[$_].Resumen; llano = (Llano $_ ([string]$antes[$_].Resumen)) } })
    revisadas = $antes.Count
    pasos = @($pasosPlan | ForEach-Object { @{ id = $_.Id; titulo = $_.Titulo; que = $_.Que; hecho = $_.Hecho; min = $_.Min } }); espera = [bool]($confirmar -and -not $combo.Count -and $pasosPlan.Count -gt 0) }
Say ("Se han revisado {0} puntos. Pasos a aplicar: {1}." -f $antes.Count, $(if ($pasosPlan.Count) { ($pasosPlan | ForEach-Object { $_.Titulo }) -join ', ' } else { 'ninguno' }))

# La persona decide: la app enseña lo encontrado y los pasos previstos, y ella quita los que no quiera (o pide solo la información).
# Sin respuesta en 5 minutos no se cambia nada.
if ($confirmar -and -not $combo.Count -and $pasosPlan.Count -gt 0) {
    $limiteEspera = (Get-Date).AddMinutes(5)
    while (-not (Test-Path -LiteralPath $confirmar) -and (Get-Date) -lt $limiteEspera) { Start-Sleep -Milliseconds 500 }
    $elegidos = @()
    if (Test-Path -LiteralPath $confirmar) {
        try { $elegidos = @((Get-Content -LiteralPath $confirmar -Raw -Encoding UTF8 | ConvertFrom-Json).ids) } catch { $elegidos = @() }
        Remove-Item -LiteralPath $confirmar -Force -ErrorAction SilentlyContinue
    } else { Say 'No hubo respuesta: no se ha cambiado nada.' }
    $pasosPlan = @($pasosPlan | Where-Object { $_.Id -in $elegidos })
    $cambian = @($pasosPlan | Where-Object { $_.Cambia -ne $false -and $_.Id -ne 'limpieza' -and $_.Id -ne 'restauracion' })
    if ($cambian.Count -gt 0 -and -not ($pasosPlan | Where-Object { $_.Id -eq 'restauracion' })) { $pasosPlan = @($catalogo[0]) + $pasosPlan }   # el punto de restauración no es opcional si algo cambia el sistema
    if (@($pasosPlan | Where-Object { $_.Id -ne 'restauracion' }).Count -eq 0) { $pasosPlan = @(); $soloMirar = $true }
    $cubiertas = @{}; foreach ($a in $pasosPlan) { foreach ($t in $a.Pruebas) { $cubiertas[$t] = $true } }
    Say ("Elegido: {0}" -f $(if ($pasosPlan.Count) { ($pasosPlan | ForEach-Object { $_.Titulo }) -join ', ' } else { 'solo la información, sin cambiar nada' }))
}

# ---------------------------------------------------------------------
#  3. Aplicar, paso a paso
# ---------------------------------------------------------------------
$hechos = New-Object 'Collections.Generic.List[object]'
$antivirus = $null
$i = 0
foreach ($a in $pasosPlan) {
    $i++
    Say ''
    Say ("Paso {0} de {1}: {2}" -f $i, $pasosPlan.Count, $a.Titulo)
    Send-Auto @{ t = 'paso'; id = $a.Id; estado = 'inicio'; n = $i; de = $pasosPlan.Count; linea = ("Paso {0} de {1}: {2}" -f $i, $pasosPlan.Count, $a.Titulo) }
    $r = Invoke-Hijo $a
    if ($a.Id -eq 'antivirus') {
        $otroAv = @($r.Lineas | Where-Object { $_.Texto -like 'Otro antivirus:*' } | ForEach-Object { ($_.Texto -replace '^Otro antivirus:\s*', '').Trim() })[0]
        $cuenta = @($r.Lineas | Where-Object { $_.Texto -match '^Amenazas encontradas: \d+$' } | ForEach-Object { [int]($_.Texto -replace '\D', '') })
        $antivirus = @{ analizado = [bool]($r.Final -eq 'normal' -and $cuenta.Count -gt 0); amenazas = $(if ($cuenta.Count) { $cuenta[0] } else { 0 }); otro = $otroAv; lista = @($r.Lineas | Where-Object { $_.Texto -like 'Amenaza: *' } | ForEach-Object { ($_.Texto -replace '^Amenaza:\s*', '') }) }
    }
    $est = switch ($r.Final) {
        'saltado' { 'saltado' }
        'tiempo' { 'tiempo' }
        # El código de salida lo deja el último comando del script y no siempre significa fallo: solo cuenta si además escribió un error.
        default { if ($r.Codigo -eq 0) { 'ok' } elseif ($r.Codigo -eq 2) { 'nohecho' } elseif (@($r.Lineas | Where-Object { $_.Tipo -eq 'error' }).Count) { 'aviso' } else { 'ok' } }
    }
    $marcadas = @($r.Lineas | Where-Object { $_.Tipo })
    $clave = if ($marcadas.Count) { @($marcadas | Select-Object -Last 8) } else { @($r.Lineas | Select-Object -Last 3) }
    $h = @{ Id = $a.Id; Titulo = $a.Titulo; Que = $a.Que; Hecho = $a.Hecho; Estado = $est; Seg = $r.Seg; Codigo = $r.Codigo; Pruebas = $a.Pruebas; Reinicio = $a.Reinicio; Verifica = ($a.Verifica -ne $false -and $a.Pruebas.Count -gt 0)
            Lineas = @($clave | ForEach-Object { @{ tipo = $_.Tipo; texto = $_.Texto } }) }
    $hechos.Add($h)
    if ($est -in 'ok', 'aviso' -and $r.Seg -gt 0) { $tm = $tiempos[$a.Id]; if (-not $tm) { $tm = @{ n = 0; seg = 0.0 } }; $n = [math]::Min($tm.n, 9); $tiempos[$a.Id] = @{ n = $n + 1; seg = (($tm.seg * $n) + $r.Seg) / ($n + 1) } }
    $textoFin = switch ($est) { 'ok' { 'Hecho' } 'aviso' { 'Terminó con avisos' } 'saltado' { 'Saltado' } 'tiempo' { "Se cerró: tardaba más de $(if ($a.Max -ge 120) { "$([int]($a.Max / 60)) min" } else { "$($a.Max) s" })" } 'nohecho' { 'No se pudo aplicar ahora' } }
    Say ("  -> {0} ({1} s)" -f $textoFin, $r.Seg)
    Send-Auto @{ t = 'paso'; id = $a.Id; estado = 'fin'; resultado = $est; seg = $r.Seg; texto = $textoFin; lineas = $h.Lineas; n = $i; de = $pasosPlan.Count }
    Write-Log ("Revisión automática: {0}: {1} en {2} s" -f $a.Titulo, $textoFin.ToLower(), $r.Seg) $(if ($est -eq 'ok') { 'INFO' } else { 'AVISO' })
}

if ($archivoTiempos -and $tiempos.Count) { try { [IO.File]::WriteAllText($archivoTiempos, ($tiempos | ConvertTo-Json), (New-Object Text.UTF8Encoding($true))) } catch { } }

# ---------------------------------------------------------------------
#  4. Volver a comprobar lo que se ha tocado
# ---------------------------------------------------------------------
$despues = @{}
$verificar = @($hechos | Where-Object { $_.Verifica -and $_.Estado -in 'ok', 'aviso' } | ForEach-Object { $_.Pruebas } | Where-Object { Mal $_ } | Select-Object -Unique)
if ($verificar.Count) {
    Say ''; Say 'Comprobando que los arreglos han funcionado…'
    Send-Auto @{ t = 'fase'; fase = 'verificando'; linea = 'Comprobando que los arreglos han funcionado' }
    $env:NIT_DX_IDS = ($verificar -join ','); $env:NIT_DX_SINGUARDAR = '1'
    . (Join-Path $PSScriptRoot 'Diagnostico_Para_App.ps1') | ForEach-Object { Convertir-Dx $_ 'verificando' }
    Remove-Item Env:\NIT_DX_SINGUARDAR -ErrorAction SilentlyContinue; $env:NIT_DX_IDS = ''
    foreach ($k in $res.Keys) { $despues[$k] = $res[$k] }
}

# Resultado de cada paso y de cada problema
$arreglados = @{}
foreach ($h in $hechos) {
    $cubre = @($h.Pruebas | Where-Object { Mal $_ })
    $res1 = 'hecho'
    if ($h.Estado -in 'saltado', 'tiempo', 'nohecho') { $res1 = $h.Estado }
    elseif ($h.Pruebas.Count -eq 0 -or $cubre.Count -eq 0) { $res1 = if ($h.Estado -eq 'ok') { 'hecho' } else { 'avisos' } }   # sin nada concreto que comprobar después
    elseif (-not $h.Verifica) { $res1 = 'preparado' }
    else {
        $buenas = @($cubre | Where-Object { $despues[$_] -and $despues[$_].Estado -in 'OK', 'Info' })
        foreach ($b in $buenas) { $arreglados[$b] = $true }
        if ($cubre.Count -and $buenas.Count -eq $cubre.Count) { $res1 = 'resuelto' }
        elseif ($buenas.Count) { $res1 = 'parcial' }
        elseif ($h.Reinicio -and $h.Estado -eq 'ok') { $res1 = 'reinicio' }
        else { $res1 = 'pendiente' }
    }
    $h.Resultado = $res1
    $h.Despues = @($h.Pruebas | Where-Object { $despues[$_] } | ForEach-Object { @{ id = $_; nombre = $nombrePrueba[$_]; estado = [string]$despues[$_].Estado; resumen = [string]$despues[$_].Resumen } })
}
$reiniciar = [bool](($hechos | Where-Object { $_.Reinicio -and $_.Estado -eq 'ok' }) -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'))

$detectados = @($antes.Keys | Where-Object { $antes[$_].Estado -in 'Aviso', 'Fallo' })
$atencion = @($detectados | Where-Object { -not $arreglados[$_] } | ForEach-Object {
    $resumenAhora = if ($despues[$_]) { [string]$despues[$_].Resumen } else { [string]$antes[$_].Resumen }
    $estadoAhora = if ($despues[$_]) { [string]$despues[$_].Estado } else { [string]$antes[$_].Estado }
    $cons = if ($_ -eq 'sistema' -and $resumenAhora -match 'reinicio|reiniciarse') { 'Reinicia el equipo para terminar de aplicar lo que tiene pendiente.' }
            elseif ($_ -eq 'sistema' -and $resumenAhora -match 'activado') { 'Windows no está activado: hace falta una licencia válida.' }
            elseif ($consejos[$_]) { $consejos[$_] } else { 'Revisa este punto con las herramientas del kit.' }
    @{ id = $_; nombre = $nombrePrueba[$_]; estado = $estadoAhora; resumen = $resumenAhora; llano = (Llano $_ $resumenAhora); consejo = $cons; intentado = [bool]$cubiertas[$_] } })

# ---------------------------------------------------------------------
#  5. Informe
# ---------------------------------------------------------------------
$seg = [int]((Get-Date) - $inicioTotal).TotalSeconds
$nArreglados = @($detectados | Where-Object { $arreglados[$_] }).Count
$nProblemas = if ($detectados.Count -eq 1) { 'un problema' } else { "$($detectados.Count) problemas" }
$necesitan = if ($atencion.Count -eq 1) { 'necesita' } else { 'necesitan' }
$titular = if ($detectados.Count -eq 0) { 'No se ha encontrado ningún problema.' }
    elseif ($atencion.Count -eq 0) { if ($detectados.Count -eq 1) { 'Se encontró un problema y se ha arreglado.' } else { "Se encontraron $nProblemas y se han arreglado todos." } }
    elseif ($nArreglados -eq 0) { if ($detectados.Count -eq 1) { 'Se encontró un problema y necesita tu atención.' } else { "Se encontraron $nProblemas y $necesitan tu atención." } }
    else { "Se encontraron ${nProblemas}: $nArreglados arreglado$(if ($nArreglados -ne 1) { 's' }) y $($atencion.Count) que $necesitan tu atención." }

if ($combo.Count) {
    $nOk = @($hechos | Where-Object { $_.Estado -eq 'ok' }).Count
    $titular = if ($hechos.Count -eq 0) { 'No se ha aplicado ningún paso.' } elseif ($nOk -eq $hechos.Count) { "Se $(if ($hechos.Count -eq 1) { 'ha aplicado un paso' } else { "han aplicado $($hechos.Count) pasos" })." } else { "Se han aplicado $nOk de $($hechos.Count) pasos." }
}

if ($combo -contains 'deshacer') { $titular = 'Se han deshecho los últimos cambios.' }

function Esc($t) { [Net.WebUtility]::HtmlEncode([string]$t) }
$etiqueta = @{ OK = 'Correcto'; Info = 'Informativo'; Aviso = 'Aviso'; Fallo = 'Problema' }
$resTxt = @{ resuelto = 'Arreglado y comprobado'; parcial = 'Arreglado en parte'; reinicio = 'Aplicado: falta reiniciar'; preparado = 'Preparado: falta instalar las actualizaciones'; hecho = 'Hecho'; avisos = 'Terminó con avisos'; pendiente = 'Aplicado, pero el problema sigue'; saltado = 'Saltado'; tiempo = 'Se cerró porque tardaba demasiado'; nohecho = 'No se pudo aplicar ahora' }
$sb = New-Object Text.StringBuilder
[void]$sb.Append("<h2>Resumen</h2><p class=g>$(Esc $titular)</p>")
if ($reiniciar) { [void]$sb.Append('<p class=n>Conviene reiniciar el equipo para terminar de aplicar los cambios.</p>') }
if ($antivirus) {
    [void]$sb.Append('<h2>Análisis de virus</h2>')
    if ($antivirus.otro) { [void]$sb.Append("<p class=m>Este equipo usa otro antivirus ($(Esc $antivirus.otro)). Hay que analizarlo desde su propia ventana.</p>") }
    elseif (-not $antivirus.analizado) { [void]$sb.Append('<p class=m>El análisis no se pudo completar.</p>') }
    elseif ($antivirus.amenazas -eq 0) { [void]$sb.Append('<p class=m>Análisis rápido con el antivirus de Windows: no se ha encontrado ninguna amenaza.</p>') }
    else { [void]$sb.Append("<p class=g>Se han encontrado $($antivirus.amenazas) amenaza(s).</p><ul>"); foreach ($l in $antivirus.lista) { [void]$sb.Append("<li>$(Esc $l)</li>") }; [void]$sb.Append('</ul>') }
}
if (-not $combo.Count) {
[void]$sb.Append('<h2>Lo que se ha encontrado</h2>')
if ($detectados.Count) {
    [void]$sb.Append('<table><tr><th>Qué</th><th>Estado</th><th>Detalle</th><th>Después</th></tr>')
    foreach ($d in $detectados) {
        $post = if ($arreglados[$d]) { 'Arreglado' } elseif ($cubiertas[$d]) { 'Sigue pendiente' } else { 'Necesita atención' }
        [void]$sb.Append("<tr><td>$(Esc $nombrePrueba[$d])</td><td>$(Esc $etiqueta[[string]$antes[$d].Estado])</td><td>$(Esc $antes[$d].Resumen)</td><td>$post</td></tr>")
    }
    [void]$sb.Append('</table>')
} else { [void]$sb.Append("<p class=m>Las $($antes.Count) comprobaciones han salido bien.</p>") }
}
[void]$sb.Append('<h2>Lo que se ha hecho</h2>')
if ($hechos.Count) {
    foreach ($h in $hechos) {
        [void]$sb.Append("<div class=p><b>$(Esc $h.Titulo)</b> · $(Esc $resTxt[$h.Resultado]) <span class=m>($($h.Seg) s)</span><br><span class=m>$(Esc $h.Que)</span>")
        if ($h.Lineas.Count) { [void]$sb.Append('<ul>'); foreach ($l in $h.Lineas) { [void]$sb.Append("<li>$(Esc $l.texto)</li>") }; [void]$sb.Append('</ul>') }
        [void]$sb.Append('</div>')
    }
} else { [void]$sb.Append('<p class=m>No hizo falta cambiar nada en el equipo.</p>') }
if ($atencion.Count) {
    [void]$sb.Append('<h2>Necesita atención</h2><table><tr><th>Qué</th><th>Detalle</th><th>Qué hacer</th></tr>')
    foreach ($t in $atencion) { [void]$sb.Append("<tr><td>$(Esc $t.nombre)</td><td>$(Esc $t.resumen)</td><td>$(Esc $t.consejo)</td></tr>") }
    [void]$sb.Append('</table>')
}
if ($antes.Count) {
[void]$sb.Append("<h2>Todo lo que se ha revisado ($($antes.Count))</h2><table><tr><th>Comprobación</th><th>Estado</th><th>Resultado</th></tr>")
foreach ($k in $antes.Keys) { [void]$sb.Append("<tr><td>$(Esc $nombrePrueba[$k])</td><td>$(Esc $etiqueta[[string]$antes[$k].Estado])</td><td>$(Esc $antes[$k].Resumen)</td></tr>") }
[void]$sb.Append('</table>')
}
$css = 'body{font:14px Segoe UI,sans-serif;margin:0;background:#f3f5f9;color:#1b2230}header{background:#0d1016;color:#fff;padding:22px 32px}header h1{margin:0;font-size:22px}header p{margin:4px 0 0;color:#9aa3b8}main{padding:8px 32px 40px;max-width:1100px}h2{margin:28px 0 8px;color:#087f91;font-size:16px}table{border-collapse:collapse;width:100%;background:#fff;border-radius:8px;overflow:hidden;margin-bottom:8px}th,td{text-align:left;padding:7px 12px;border-bottom:1px solid #e1e6ef;vertical-align:top}th{background:#e8eef6;font-weight:600}.m{color:#4f5a70}.g{font-size:16px;font-weight:600}.n{background:#fff4dc;border:1px solid #e0b252;border-radius:6px;padding:8px 12px}.p{background:#fff;border:1px solid #e1e6ef;border-radius:8px;padding:10px 14px;margin-bottom:8px}.p ul{margin:6px 0 0;padding-left:20px}@media(prefers-color-scheme:dark){body{background:#12151c;color:#f0f3fa}table,.p{background:#1e2330;border-color:#2e3548}th{background:#272d3f}td,th{border-color:#2e3548}h2{color:#2bc4d8}.m{color:#9aa3b8}.n{background:#3a2f12;border-color:#8a6a1f}}'
$cabecera = "Revisión del equipo $(Esc $env:COMPUTERNAME)"
$subtitulo = "Generado el $(Get-Date -Format 'dd/MM/yyyy HH:mm')$(if ($clienteFicha) { ' · Cliente: ' + (Esc $clienteFicha) }) · Nitrit0"
$html = "<!doctype html><html lang=es><head><meta charset=utf-8><title>$cabecera</title><style>$css</style></head><body><header><h1>$cabecera</h1><p>$subtitulo</p></header><main>$($sb.ToString())</main></body></html>"
$rutaInforme = $null
try {
    if (-not (Test-KitDisponible)) { [void](Wait-Kit 30) }
    $dir = Get-CarpetaSalida 'Informes'
    $rutaInforme = Join-Path $dir ("Revision_{0}_{1}.html" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmm'))
    [IO.File]::WriteAllText($rutaInforme, $html, (New-Object Text.UTF8Encoding($true)))
} catch { $rutaInforme = $null; Say "No se pudo guardar el informe: $($_.Exception.Message)" }

Write-Log ("Revisión automática: {0} Pasos aplicados: {1}. Duración {2} s." -f $titular, $hechos.Count, $seg)
Say ''; Say $titular
$pasosFin = @($hechos | ForEach-Object { @{ id = $_.Id; titulo = $_.Titulo; que = $_.Que; hecho = $_.Hecho; estado = $_.Estado; resultado = $_.Resultado; seg = $_.Seg; lineas = $_.Lineas; despues = $_.Despues } })
Send-Auto @{ t = 'fin'; resultado = @{
    equipo = $env:COMPUTERNAME; modo = $(if ($combo.Count) { 'combo' } else { 'auto' }); soloMirar = $soloMirar; enfoque = $enfoque; seg = $seg; revisadas = $antes.Count; titular = $titular; reiniciar = $reiniciar; informe = $rutaInforme
    antivirus = $antivirus
    detectados = @($detectados | ForEach-Object { @{ id = $_; nombre = $nombrePrueba[$_]; estado = [string]$antes[$_].Estado; resumen = [string]$antes[$_].Resumen; llano = (Llano $_ ([string]$antes[$_].Resumen)); arreglado = [bool]$arreglados[$_] } })
    pasos = $pasosFin; atencion = $atencion } }
if ($rutaInforme) { Open-Informe $rutaInforme }
exit 0
