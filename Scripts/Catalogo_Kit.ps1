# =====================================================================
#  Catalogo_Kit.ps1 - Catálogo de herramientas del kit (Nitrit0)
#  Define $Herramientas, $Paginas y a qué página y grupo va cada una. Es la fuente única: lo cargan el lanzador clásico,
#  Exportar_Catalogo.ps1 (que genera App\datos\herramientas.json para la app) y Validar_Kit.ps1.
#  Espera $dirScripts y Write-Log; no abre ventanas ni cambia nada.
# =====================================================================
# --- Catálogo de Herramientas ---
$Herramientas = @(
    @{ N='Asistente guiado'; C='Otros'; D='¿No sabes qué herramienta tocar? Elige qué síntoma tiene el PC y lo diagnostico y reparo paso a paso.'; Script='Mantenimiento\Asistente_Guiado_Inteligente.ps1'; Timeout=21600 }
    @{ N='Modo taller'; C='Otros'; D='Un clic: ficha del cliente, diagnóstico rápido, historial e informe listo para entregar.'; Accion='Taller' }
    @{ N='Cuello de botella'; C='Otros'; D='Analiza si algún componente hace cuello de botella (CPU, gráfica, RAM en Single Channel o disco lento) y frena a tu PC.'; Accion='Equilibrio' }
    @{ N='Informe rápido'; C='Otros'; D='Genera al instante un informe de texto con hardware, discos, batería y errores recientes.'; Informe=$true }
    @{ N='CPU-Z';            C='CPU';     D='Modelo exacto de procesador, frecuencias, caché, placa base y módulos de memoria.'; Exe=@{ x64='CPU\cpu-z_*\cpuz_x64.exe'; x86='CPU\cpu-z_*\cpuz_x32.exe' } }
    @{ N='HWiNFO';           C='CPU';     D='Telemetría completa del hardware y sensores (temperaturas, voltajes, consumo y ventiladores).'; Exe=@{ x64='HW Info\hwi_*\HWiNFO64.exe'; x86='HW Info\hwi_*\HWiNFO32.exe'; arm64='HW Info\hwi_*\HWiNFO_ARM64.exe' } }
    @{ N='HWMonitor';        C='CPU';     D='Temperaturas, voltajes y ventiladores en tiempo real con registro de mínimos y máximos.'; Exe=@{ x64='HW Info\hwmonitor_*\HWMonitor_x64.exe'; x86='HW Info\hwmonitor_*\HWMonitor_x32.exe' } }
    @{ N='LibreHardwareMonitor'; C='CPU'; D='Sensores en vivo: temperaturas, ventiladores, potencia y voltajes con soporte PawnIO.'; Exe=@{ x64='HW Info\LibreHardwareMonitor\LibreHardwareMonitor.exe' } }
    @{ N='Core Temp';        C='CPU';     D='Temperatura individual de cada núcleo de la CPU, carga y frecuencia en tiempo real.'; Exe=@{ x64='HW Info\CoreTemp64\Core Temp.exe' } }
    @{ N='GPU-Z';            C='GPU';     D='Especificaciones de la tarjeta gráfica, sensores de temperatura, carga y memoria VRAM.'; Exe=@{ x64='GPU\GPU-Z.exe' } }
    @{ N='CrystalDiskInfo';  C='Disco';   D='Estado S.M.A.R.T. de discos: salud, temperatura, sectores reasignados y horas de encendido.'; Exe=@{ x64='Disk\CrystalDiskInfo*\DiskInfo64.exe'; x86='Disk\CrystalDiskInfo*\DiskInfo32.exe'; arm64='Disk\CrystalDiskInfo*\DiskInfoA64.exe' } }
    @{ N='CrystalDiskMark';  C='Disco';   D='Mide la velocidad secuencial y aleatoria de lectura y escritura del disco.'; Peligro=$true; Exe=@{ x64='Disk\CrystalDiskMark*\DiskMark64.exe'; x86='Disk\CrystalDiskMark*\DiskMark32.exe'; arm64='Disk\CrystalDiskMark*\DiskMarkA64.exe' } }
    @{ N='SMART detallado';  C='Disco';   D='smartctl: auditoría S.M.A.R.T. profunda (desgaste NVMe, sectores pendientes, registro de errores).'; Accion='SmartDetalle' }
    @{ N='WizTree';          C='Disco';   D='Escáner ultrarrápido MFT que muestra qué archivos y carpetas ocupan más espacio en disco.'; Exe=@{ x64='Disk\wiztree_*\WizTree64.exe'; x86='Disk\wiztree_*\WizTree.exe' } }
    @{ N='WinDirStat';       C='Disco';   D='Mapa visual interactivo del uso del disco clasificado por tipo de archivo.'; Exe=@{ x64='Disk\WinDirStat\x64\WinDirStat.exe'; x86='Disk\WinDirStat\x86\WinDirStat.exe'; arm64='Disk\WinDirStat\arm64\WinDirStat.exe' } }
    @{ N='HDDScan';          C='Disco';   D='Diagnóstico S.M.A.R.T. y escaneo de superficie bloque a bloque para HDD y SSD.'; Exe=@{ x64='Disk\HDDScan\HDDScan.exe' } }
    @{ N='TestMem5';         C='Memoria'; D='Prueba intensiva de estabilidad de memoria RAM. Ciérrala cuando complete el ciclo.'; Peligro=$true; Exe=@{ x64='Memoria\TestMem5\TM5.exe' } }
    @{ N='MemTest64';        C='Memoria'; D='Comprobación rápida de errores de direccionamiento y estabilidad en memoria RAM.'; Peligro=$true; Exe=@{ x64='Memoria\MemTest64.exe' } }
    @{ N='MemTest86 (USB)';  C='Memoria'; D='Crea un pendrive autoarrancable con MemTest86 (borra el USB) para diagnóstico fuera de Windows.'; Peligro=$true; Exe=@{ x64='Memoria\memtest86-usb\imageUSB.exe' } }
    @{ N='FurMark';          C='Estrés';  D='Prueba de estrés térmico extremo para la tarjeta gráfica (GPU). Vigila las temperaturas.'; Peligro=$true; Exe=@{ x64='Stress Test\FurMark_*\FurMark_win64\FurMark_GUI.exe' } }
    @{ N='Prime95';          C='Estrés';  D='Tortura de CPU y controlador de memoria para detectar inestabilidad térmica o de voltaje.'; Peligro=$true; Exe=@{ x64='Stress Test\p95v*\prime95.exe' } }
    @{ N='OCCT';             C='Estrés';  D='Suite profesional de estrés para CPU, GPU, VRAM y fuente de alimentación (PSU).'; Peligro=$true; Exe=@{ x64='Stress Test\OCCT.exe' } }
    @{ N='AdwCleaner';       C='Malware'; D='Elimina adware, secuestradores de navegador, barras de herramientas y PUPs.'; Exe=@{ x64='Malware\adwcleaner.exe' } }
    @{ N='KVRT';             C='Malware'; D='Kaspersky Virus Removal Tool: escáner antimalware profundo sin instalación.'; Exe=@{ x64='Malware\KVRT.exe' } }
    @{ N='Sophos Virus Removal Tool'; C='Malware'; D='Segundo motor antimalware independiente. Se instala en el equipo al abrirlo: desinstálalo al terminar si es de un cliente.'; Exe=@{ x64='Malware\sophos*.exe' } }
    @{ N='Trellix Stinger';  C='Malware'; D='Escáner ligero de amenazas muy extendidas (antes McAfee Stinger), sin instalación.'; Exe=@{ x64='Malware\stinger*.exe' } }
    @{ N='Autoruns';         C='Sistema'; D='Muestra absolutamente todo lo que arranca con Windows (registro, tareas, servicios, DLLs).'; Exe=@{ x64='Sistema\Autoruns\Autoruns64.exe'; x86='Sistema\Autoruns\Autoruns.exe'; arm64='Sistema\Autoruns\Autoruns64a.exe' } }
    @{ N='IP Changer';       C='Sistema'; D='Cambia la IP, máscara, puerta de enlace y DNS del equipo con perfiles guardados: para conectar a routers o impresoras con IP fija.'; Exe=@{ x64='Red\IPC v*\IP Changer.exe' } }
    @{ N='Process Explorer'; C='Sistema'; D='Muestra todos los procesos con su árbol, uso de recursos y a quién pertenecen. Sirve para investigar un proceso sospechoso o saber qué bloquea un archivo.'; Exe=@{ x64='Sistema\ProcessExplorer\procexp64.exe'; x86='Sistema\ProcessExplorer\procexp.exe'; arm64='Sistema\ProcessExplorer\procexp64a.exe' } }
    @{ N='USBDeview';        C='Periféricos'; D='Lista todos los dispositivos USB conectados y los que se conectaron antes. Útil en conflictos de controladores USB o para ver qué pendrives se enchufaron.'; Exe=@{ x64='Perifericos\USBDeview\USBDeview.exe' } }
    @{ N='PhotoRec';         C='Recuperación'; D='Recupera archivos borrados (fotos, documentos, vídeos…) de discos, tarjetas o pendrives, aunque estén dañados. Guarda lo recuperado en OTRA unidad, nunca en la que se quiere recuperar.'; Exe=@{ x64='Recuperacion\testdisk-*\qphotorec_win.exe' } }
    @{ N='TestDisk';         C='Recuperación'; D='Recupera particiones perdidas y repara el arranque de un disco. Se usa en una ventana de texto y puede cambiar la tabla de particiones: solo para quien sabe lo que hace.'; Peligro=$true; Exe=@{ x64='Recuperacion\testdisk-*\testdisk_win.exe' } }
    @{ N='Rufus';            C='Utilidades'; D='Crea pendrives de arranque con Windows, Linux o herramientas de rescate. Borra todo el contenido del pendrive elegido.'; Peligro=$true; Exe=@{ x64='Instaladores\Utilidades\rufus-*.exe' } }
    @{ N='WTools';           C='Sistema'; D='Latencia DPC, overlay de GPU y utilidades de sistema. Evita su limpieza y reparación de registro en equipos de clientes (su copia del registro falla).'; Peligro=$true; Exe=@{ x64='Sistema\WTools v*\WTools.exe' } }
    @{ N='Pantalla (colores)'; C='Pantalla'; D='Prueba interactiva a pantalla completa con patrones sólidos, degradados y píxeles muertos.'; Html='Pruebas\Prueba_Pantalla.html' }
    @{ N='MonTest';          C='Pantalla'; D='Suite PassMark MonitorTest: contraste, uniformidad, convergencia y tiempos de respuesta.'; Exe=@{ x64='Pantalla\montest.exe' } }
    @{ N='Monitor Test';     C='Pantalla'; D='Patrones de prueba ligeros para detectar fugas de luz (bleeding) y píxeles atascados.'; Exe=@{ x64='Pantalla\monitor_test_utility.exe' } }
    @{ N='CRU';              C='Pantalla'; D='Custom Resolution Utility: edita resoluciones EDID y tasas de refresco del monitor.'; Peligro=$true; Exe=@{ x64='Pantalla\cru-*\CRU.exe' } }
    @{ N='Teclado y Chattering'; C='Periféricos'; D='Laboratorio ISO Español: comprueba todas las teclas, NKRO y rebote mecánico (<28 ms).'; Html='Pruebas\Prueba_Teclado.html' }
    @{ N='Test de teclado (App)'; C='Periféricos'; D='Utilidad de escritorio clásica para verificar códigos de pulsación del teclado.'; Exe=@{ x64='Perifericos\keyboardtestutility.exe' } }
    @{ N='Webcam';           C='Periféricos'; D='Prueba de cámara web en vivo: resolución real, FPS y diagnóstico de permisos sin internet.'; Html='Pruebas\Prueba_Webcam.html' }
    @{ N='Audio y micrófono'; C='Periféricos'; D='Test estéreo L/R, barrido de frecuencias y grabadora de micrófono con vúmetro en vivo.'; Html='Pruebas\Prueba_Audio.html' }
    @{ N='Placa de vídeo (GPU)'; C='Estrés'; D='Prueba de la placa de vídeo: llena y relee la memoria con patrones y repite cálculos verificados con carga sostenida. Da Pasa, Falla o No evaluado.'; Html='Pruebas\Prueba_GPU.html' }
    @{ N='Prueba de procesador'; C='Estrés'; D='Carga todos los hilos con cálculos verificados, da Pasa, Falla o No evaluado y una puntuación para comparar antes y después de un cambio.'; Html='Pruebas\Prueba_CPU.html' }
    @{ N='Mando de videojuegos'; C='Periféricos'; D='Prueba de mando (Xbox, PlayStation, Switch Pro o genérico): botones, sticks con medida de deriva, gatillos y vibración.'; Html='Pruebas\Prueba_Mando.html' }
    @{ N='Ratón y táctil';   C='Periféricos'; D='Verifica botones, rueda, doble clic involuntario, panel táctil y gestos multitáctiles.'; Html='Pruebas\Prueba_Raton.html' }
    @{ N='Historial';        C='Utilidades'; D='Abre la carpeta con el historial de diagnósticos guardados por equipo.'; Accion='AbrirHistorial' }
    @{ N='Informes';         C='Utilidades'; D='Abre la carpeta donde se exportan todos los informes HTML y auditorías.'; Accion='AbrirInformes' }
    @{ N='Dispositivos';     C='Utilidades'; D='Administrador de dispositivos de Windows: controladores con conflicto y hardware PnP.'; Run='devmgmt.msc' }
    @{ N='Visor de eventos'; C='Utilidades'; D='Registros del sistema de Windows: fallos de servicios, disco y pantallazos.'; Run='eventvwr.msc' }
    @{ N='Monitor recursos'; C='Utilidades'; D='Monitor en tiempo real de uso de CPU, procesos en disco, red y memoria física.'; Run='resmon.exe' }
    @{ N='Info del sistema'; C='Utilidades'; D='Resumen detallado de hardware, recursos de E/S, DMA y entorno (msinfo32).'; Run='msinfo32.exe' }
    @{ N='DxDiag';           C='Utilidades'; D='Herramienta de diagnóstico de DirectX: aceleración gráfica, controladores y sonido.'; Run='dxdiag.exe' }
    @{ N='Discos (Windows)'; C='Utilidades'; D='Administración de discos de Windows: particiones, formato, letras de unidad y volúmenes.'; Run='diskmgmt.msc' }
    @{ N='Confiabilidad';    C='Utilidades'; D='Monitor de confiabilidad: línea temporal de cierres inesperados y fallos de Windows.'; Run='perfmon.exe'; RunArgs='/rel' }
    @{ N='Informe 60 s';     C='Utilidades'; D='Genera durante 60 segundos el informe oficial de salud del sistema de Windows.'; Run='perfmon.exe'; RunArgs='/report' }
    @{ N='Tareas';           C='Utilidades'; D='Administrador de tareas de Windows: procesos activos, rendimiento y pestaña de inicio.'; Run='taskmgr.exe' }
    @{ N='Servicios';        C='Utilidades'; D='Consola de servicios de Windows (services.msc): estado y tipo de inicio.'; Run='services.msc' }
    @{ N='Batería';          C='Windows'; D='Genera y abre el informe oficial de salud de batería, capacidad real frente a fábrica y ciclos.'; Accion='CmdBateria' }
    @{ N='Energía (60 s)';   C='Windows'; D='Traza durante 60 s problemas de consumo energético y dispositivos que impiden suspender.'; Accion='CmdEnergia' }
    @{ N='SFC';              C='Windows'; D='Comprueba y repara archivos protegidos del sistema operativo (sfc /scannow).'; Peligro=$true; Cmd='sfc /scannow' }
    @{ N='DISM';             C='Windows'; D='Repara el almacén de componentes de la imagen de Windows mediante Windows Update.'; Peligro=$true; Cmd='DISM /Online /Cleanup-Image /RestoreHealth' }
    @{ N='Comprobar disco';  C='Windows'; D='Verifica la integridad del sistema de archivos NTFS de la unidad de Windows en modo lectura.'; Cmd='chkdsk %SystemDrive%' }
    @{ N='Memoria Windows';  C='Windows'; D='Programador de diagnóstico de memoria de Windows (reinicia el PC para testar la RAM).'; Peligro=$true; Cmd='mdsched.exe' }
    @{ N='Test de red';      C='Windows'; D='Prueba de ping y ruta de saltos (tracert) hacia Cloudflare 1.1.1.1.'; Cmd='ping -n 10 1.1.1.1 & tracert -d -h 15 1.1.1.1' }
)

function Get-ScriptsMantenimiento {
    $dir = Join-Path $dirScripts 'Mantenimiento'; $res = @()
    if (-not (Test-Path -LiteralPath $dir)) { return $res }
    $cat = @{}; try { $cat = Read-DatosPsd1 (Join-Path $dir 'Catalogo.psd1') } catch { Write-Log "Catalogo.psd1 no se pudo leer: $($_.Exception.Message)" 'AVISO' }
    $yaDeclarados = @($Herramientas | Where-Object { $_.Script } | ForEach-Object { $_.Script })
    $mapa = @{ 'Actualizaciones' = 'Software'; 'Software' = 'Software'; 'Mantenimiento' = 'Mantenimiento'; 'Memoria y rendimiento' = 'Mantenimiento'; 'Energía' = 'Mantenimiento'; 'Personalización' = 'Mantenimiento'; 'Diagnóstico' = 'Diagnóstico' }
    foreach ($f in (Get-ChildItem -LiteralPath $dir -Filter *.ps1 | Sort-Object Name)) {
        $e = $cat[$f.Name]
        if (-not $e) { Write-Log "Script $($f.Name) ignorado: no está declarado en Catalogo.psd1" 'AVISO'; continue }   # lista blanca: un .ps1 suelto en Mantenimiento no se lista ni se ejecuta
        if ($e.Oculto) { continue }
        if ($yaDeclarados -contains "Mantenimiento\$($f.Name)") { continue }   # ya tiene tarjeta propia en $Herramientas
        $c = if ($e -and $e.Categoria -and $mapa.ContainsKey($e.Categoria)) { $mapa[$e.Categoria] } else { 'Mantenimiento' }
        $d = if ($e -and $e.Descripcion) { ($e.Descripcion -replace '^NUEVO:\s*', '' -replace '^UNIFICADO:\s*', '') } else { 'Utilidad automatizada de mantenimiento y diagnóstico del sistema.' }
        # Formatear título limpio y legible
        $tituloLimpio = ($f.BaseName -replace '_', ' ' -replace 'LimpiarTemporalesEquipo', 'Limpiar Temporales' -replace 'Win11', 'Win 11' -replace 'Windows11', 'Windows 11')
        $res += @{ N = $(if ($e -and $e.Titulo) { $e.Titulo } else { $tituloLimpio }); C = $c; D = $d; Script = "Mantenimiento\$($f.Name)"; Peligro = [bool]($e -and $e.Peligroso); PublicoOk = [bool]($e -and $e.PublicoOk); Timeout = $(if ($e -and $e.Timeout) { $e.Timeout } else { 1800 }); Ayuda = $(if ($e) { $e.Ayuda } else { $null }) }
    }
    $res
}
$Herramientas = @($Herramientas) + @(Get-ScriptsMantenimiento)
# --- Páginas del lanzador: qué quiero hacer (Comprobar / Preparar equipo / Reparar y mantener) y sus grupos ---
$Paginas = [ordered]@{
    'Comprobar'          = @('Resumen y salud', 'CPU y GPU', 'Discos y memoria', 'Pantalla y periféricos', 'Pruebas de estrés', 'Antimalware', 'Windows y red')
    'Preparar equipo'    = @('Configurar', 'Actualizar', 'Entrega')
    'Reparar y mantener' = @('Reparar', 'Limpiar y optimizar', 'Copias y seguridad', 'Desinstalar')
    'Kit'                = @('Kit')
    'Nuestras herramientas' = @('Discos y copias', 'Drivers', 'Sistema y limpieza')   # lo que hemos creado nosotros: tiene entrada propia en el lateral de la app (no sale en las pestañas de Herramientas)
}
# Destino por categoría (apps y scripts nuevos caen aquí solos) y excepciones por nombre. Formato: 'Página|Grupo'
$DestinoCat = @{
    'CPU' = 'Comprobar|CPU y GPU'; 'GPU' = 'Comprobar|CPU y GPU'; 'Disco' = 'Comprobar|Discos y memoria'; 'Memoria' = 'Comprobar|Discos y memoria'
    'Pantalla' = 'Comprobar|Pantalla y periféricos'; 'Periféricos' = 'Comprobar|Pantalla y periféricos'
    'Estrés' = 'Comprobar|Pruebas de estrés'; 'Malware' = 'Comprobar|Antimalware'
    'Recuperación' = 'Reparar y mantener|Copias y seguridad'; 'Sistema' = 'Comprobar|Windows y red'; 'Utilidades' = 'Comprobar|Windows y red'; 'Windows' = 'Comprobar|Windows y red'
    'Diagnóstico' = 'Comprobar|Resumen y salud'; 'Software' = 'Preparar equipo|Configurar'; 'Mantenimiento' = 'Reparar y mantener|Reparar'; 'Otros' = 'Kit|Kit'
}
$DestinoNombre = @{
    'Rufus' = 'Preparar equipo|Configurar'
    'Ficha de drivers' = 'Nuestras herramientas|Drivers'; 'Driver desde el Catálogo de Microsoft' = 'Nuestras herramientas|Drivers'; 'Limpiar almacén de drivers' = 'Nuestras herramientas|Drivers'; 'Limpiar registro huérfano' = 'Nuestras herramientas|Sistema y limpieza'; 'Limpiar navegadores' = 'Nuestras herramientas|Sistema y limpieza'
    'Reparar Inicio, barra y Explorador' = 'Nuestras herramientas|Sistema y limpieza'; 'Reparar audio y privacidad' = 'Nuestras herramientas|Sistema y limpieza'; 'Hora y sincronización' = 'Nuestras herramientas|Sistema y limpieza'
    'Qué lo está frenando ahora' = 'Nuestras herramientas|Sistema y limpieza'; 'Reparar Office y cachés' = 'Nuestras herramientas|Sistema y limpieza'; 'Red avanzada' = 'Nuestras herramientas|Sistema y limpieza'
    'Auditoría de seguridad' = 'Nuestras herramientas|Sistema y limpieza'; 'Desinfección guiada' = 'Nuestras herramientas|Sistema y limpieza'; 'Limpieza total del equipo' = 'Reparar y mantener|Limpiar y optimizar';'WMI y runtimes' = 'Nuestras herramientas|Sistema y limpieza'; 'Por qué falla Windows Update' = 'Nuestras herramientas|Sistema y limpieza'
    'Reparar arranque y WinRE' = 'Nuestras herramientas|Discos y copias'
    'Actualizar herramientas' = 'Kit|Kit'; 'Componentes del kit' = 'Kit|Kit'
    'Quién bloquea un archivo o disco' = 'Nuestras herramientas|Discos y copias'; 'Disco sucio y reinicios pendientes' = 'Nuestras herramientas|Discos y copias'
    'Editor del archivo HOSTS' = 'Nuestras herramientas|Sistema y limpieza'; 'Dispositivos fantasma' = 'Nuestras herramientas|Drivers'; 'Limpieza profunda de Windows' = 'Nuestras herramientas|Discos y copias'; 'Optimizar unidades (TRIM)' = 'Nuestras herramientas|Discos y copias'
    'Informe rápido' = 'Comprobar|Resumen y salud'; 'Batería' = 'Comprobar|Resumen y salud'; 'Energía (60 s)' = 'Comprobar|Resumen y salud'
    'Analizar espacio en disco' = 'Comprobar|Discos y memoria'; 'Memoria Windows' = 'Comprobar|Discos y memoria'; 'Nitidez de pantalla' = 'Comprobar|Pantalla y periféricos'
    'Latencia de red' = 'Comprobar|Windows y red'; 'Wi-Fi y claves' = 'Comprobar|Windows y red'
    'SFC' = 'Reparar y mantener|Reparar'; 'DISM' = 'Reparar y mantener|Reparar'; 'Comprobar disco' = 'Reparar y mantener|Reparar'; 'Reparar TPM' = 'Reparar y mantener|Reparar'
    'Activar seguridad de Windows' = 'Preparar equipo|Configurar'; 'Personalizar Windows 11' = 'Preparar equipo|Configurar'; 'Control de energía' = 'Preparar equipo|Configurar'
    'Instalar impresora de red' = 'Preparar equipo|Configurar'; 'Quitar bloatware de Windows 11' = 'Preparar equipo|Configurar'; 'Instalar apps básicas' = 'Preparar equipo|Configurar'
    'Actualizar Windows' = 'Preparar equipo|Actualizar'; 'Actualizar programas' = 'Preparar equipo|Actualizar'; 'Actualizar versión de Windows' = 'Preparar equipo|Actualizar'; 'Drivers del fabricante' = 'Preparar equipo|Actualizar'
    'Preparar para venta' = 'Preparar equipo|Entrega'; 'Informe de entrega' = 'Preparar equipo|Entrega'
    'Restablecer Windows Update' = 'Reparar y mantener|Reparar'; 'Reinstalar gráfica' = 'Reparar y mantener|Reparar'; 'Puesta a punto' = 'Reparar y mantener|Limpiar y optimizar'
    'Limpiar temporales' = 'Reparar y mantener|Limpiar y optimizar'; 'Optimizador personal' = 'Reparar y mantener|Limpiar y optimizar'; 'Optimizar rendimiento' = 'Reparar y mantener|Limpiar y optimizar'
    'Gestión de memoria RAM' = 'Reparar y mantener|Limpiar y optimizar'; 'Programas de inicio' = 'Reparar y mantener|Limpiar y optimizar'
    'Copia de datos del usuario' = 'Reparar y mantener|Copias y seguridad'; 'Restaurar datos del usuario' = 'Reparar y mantener|Copias y seguridad'; 'Copia de drivers' = 'Reparar y mantener|Copias y seguridad'; 'Clonar disco (Windows a otro disco)' = 'Nuestras herramientas|Discos y copias'
    'Punto de restauración' = 'Reparar y mantener|Copias y seguridad'; 'Deshacer cambios' = 'Reparar y mantener|Copias y seguridad'; 'Licencias y BitLocker' = 'Reparar y mantener|Copias y seguridad'
    'Desinstalar Office' = 'Reparar y mantener|Desinstalar'; 'Desinstalador de apps' = 'Reparar y mantener|Desinstalar'; 'Restaurar cuarentena' = 'Reparar y mantener|Desinstalar'; 'Vaciar cuarentena' = 'Reparar y mantener|Desinstalar'
    'Historial' = 'Kit|Kit'; 'Informes' = 'Kit|Kit'; 'Salud del pendrive' = 'Kit|Kit'
}
# Ya están en la cabecera: se mantienen para los botones y los favoritos, pero no salen como tarjeta
$Ocultas = @('Asistente guiado', 'Modo taller', 'Cuello de botella')
foreach ($h in $Herramientas) {
    $d = if ($DestinoNombre.ContainsKey($h.N)) { $DestinoNombre[$h.N] } elseif ($DestinoCat.ContainsKey($h.C)) { $DestinoCat[$h.C] } else { 'Reparar y mantener|Reparar' }
    $h.P, $h.G = $d -split '\|'
    $h.Oculta = ($Ocultas -contains $h.N)
}

$null = $Paginas   # lo usan quienes cargan este archivo (el lanzador y Exportar_Catalogo.ps1)
