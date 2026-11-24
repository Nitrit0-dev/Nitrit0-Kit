# =====================================================================
#  Catálogo de scripts del Lanzador Nitrit0 (Edición Personal v2.2)
# =====================================================================
@{
    # --- Mantenimiento ---
    'Optimizador_Personal.ps1' = @{ Titulo = 'Optimizador personal'; Simulable = $true; Categoria = 'Mantenimiento'; Peligroso = $true; SinDestino = $true
        Descripcion = 'Analiza el equipo y aplica Fluidez, Juego, Normal, Privacidad, Limpieza, Arranque, Energía, Red o un Perfil (Juego, Trabajo, Tranquilo, Ahorro, Equilibrado). Todo se respalda y se puede Revertir.'
        Ayuda = @'
QUÉ HACE: abre una ventana para elegir el modo. Todo lo que cambia el registro, los servicios o el plan de energía se guarda en Salidas\Optimizador_Respaldo_*.json y se puede deshacer con el modo Revertir.
- Analizar: solo diagnostica y recomienda.
- Fluidez: sin transparencias ni animaciones pesadas, sin apps en segundo plano ni anuncios, Edge sin precarga, y el Explorador no adivina el tipo de carpeta al abrirla.
- Juego: plan de Máximo rendimiento, HAGS, GameDVR fuera y prioridad multimedia.
- Normal: plan equilibrado y reparto multimedia por defecto.
- Privacidad: sin contenido patrocinado, Cortana, publicidad, Copilot/Recall, telemetría al mínimo, ubicación desactivada por directiva (Encontrar mi dispositivo y Mapas no localizarán el equipo) ni sincronización forzada.
- Limpieza: temporales, caché de Windows Update y navegadores, y papelera.
- Arranque: permite desmarcar programas que arrancan con Windows.
- PERFILES (elige cómo quieres el equipo; cada uno junta varios modos y se revierte de una vez): Juego = Fluidez + Juego + Energía + Red; Trabajo = Normal + Energía + Privacidad + comodidad (rutas largas, sin aviso de Teclas especiales, «Finalizar tarea» en la barra); Tranquilo = Normal + Fluidez + Privacidad.
- Red: sin limitación de red multimedia, Wi-Fi a máximo rendimiento (en portátil solo con corriente) y ratón sin aceleración.
- Energía: desactiva el inicio rápido, la suspensión selectiva de USB (en portátil solo con corriente) y el retraso al arrancar apps. No toca la hibernación.
- Revertir: elige un respaldo y deja todo como estaba.
'@ }
    'Optimizar_Rendimiento.ps1' = @{ Titulo = 'Optimizar rendimiento'; Simulable = $true; Categoria = 'Mantenimiento'; Peligroso = $true; SinDestino = $true
        Descripcion = 'Quita límites de CPU en el arranque, ajusta la paginación, TRIM/desfragmentación de C: y limpia componentes de Windows Update.'
        Ayuda = @'
QUÉ HACE: quita el límite de procesadores del arranque, fija el archivo de paginación (con topes y solo si hay espacio), lanza TRIM o desfragmentación de C: según el tipo de disco y limpia componentes antiguos de Windows Update (DISM).
'@ }
    'Reparar_Windows_y_Tienda.ps1' = @{ Titulo = 'Reparar Windows y Tienda'; Timeout = 9000; Simulable = $true; Categoria = 'Mantenimiento'; Peligroso = $false; SinDestino = $true
        Descripcion = 'Verifica el disco (chkdsk /scan), repara la imagen de Windows (DISM + SFC /scannow) y limpia la caché de Microsoft Store.'
        Ayuda = @'
CUÁNDO USARLO: cuando el equipo tiene fallos inexplicables, pantallazos, archivos corruptos de Windows o la tienda Microsoft Store no abre/no descarga.
Ejecuta en orden: chkdsk /scan, DISM /RestoreHealth, sfc /scannow y vaciado de caché de la Store.
'@ }

    # --- Actualizaciones ---
    'Actualizar_Windows.ps1' = @{ Titulo = 'Actualizar Windows'; Categoria = 'Actualizaciones'; Timeout = 10800; Peligroso = $false; SinDestino = $true; Simulable = $true
        Descripcion = 'Instala parches de Windows y drivers oficiales con PSWindowsUpdate. No reinicia solo.'
        Ayuda = @'
QUÉ HACE: instala el módulo PSWindowsUpdate si falta, activa Microsoft Update para incluir drivers, descarga e instala todo con -IgnoreReboot y al final indica si hace falta reiniciar.
'@ }
    'Actualizar_Software.ps1' = @{ Titulo = 'Actualizar programas'; Categoria = 'Actualizaciones'; Timeout = 4200; Peligroso = $false; SinDestino = $true; Simulable = $true
        Descripcion = 'Actualiza con winget todos los programas instalados en el PC, en silencio.'
        Ayuda = @'
QUÉ HACE: ejecuta "winget upgrade --all" aceptando licencias para dejar navegadores, reproductores y utilidades al día.
'@ }

    # --- Memoria y rendimiento ---
    'Gestion_Memoria_RAM.ps1' = @{ Titulo = 'Gestión de memoria RAM'; Simulable = $true; Categoria = 'Memoria y rendimiento'; Peligroso = $false; SinDestino = $true
        Descripcion = 'Ver módulos RAM y ranuras libres, Liberar RAM al instante (Working Set) y Optimizar SysMain + Compresión.'
        Ayuda = @'
Al ejecutarlo puedes elegir una acción o hacer las 3 del tirón:
1) Hacer TODO (Ver RAM + Liberar RAM + Ajustar SysMain).
2) Liberar Memoria RAM al instante: vacía el Working Set de los procesos inactivos para recuperar RAM sin cerrar programas.
3) Ver RAM física y ranuras libres: muestra cada módulo, su velocidad MHz y cuántos zócalos libres quedan en la placa base.
4) Ajustar SysMain y Compresión: desactiva SysMain si tienes un SSD/NVMe (lo respeta si es HDD) y activa la compresión de memoria.
'@ }

    # --- Diagnóstico ---
    'Diagnostico_Completo.ps1' = @{ Titulo = 'Diagnóstico completo'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true
        Descripcion = 'Placa, CPU, GPU, Uptime, disco, RAM, Informe completo de Batería (salud/ciclos/horas), BSOD, S.M.A.R.T. y BIOS.'
        Ayuda = @'
QUÉ HACE: revisa todo el hardware del PC, incluye el informe avanzado de salud, ciclos y autonomía estimada de la batería (si es portátil), apagados bruscos, pantallazos azules y estado S.M.A.R.T. de todos los discos.
Guarda el informe en Salidas\Logs_Diagnostico.
'@ }
    'Red_WiFi_y_Claves.ps1' = @{ Titulo = 'Wi-Fi y claves'; Simulable = $true; Categoria = 'Diagnóstico'; Peligroso = $true; SinDestino = $true
        Descripcion = 'Recupera todas las contraseñas Wi-Fi guardadas en el PC, configura DNS rápidos (Cloudflare/Google) o resetea la red.'
        Ayuda = @'
Al ejecutarlo eliges qué hacer:
1) Ver Contraseñas Wi-Fi: muestra una tabla con todas las redes Wi-Fi guardadas en el ordenador y su contraseña en texto claro.
2) Poner DNS Rápidos Cloudflare (1.1.1.1 / 1.0.0.1): acelera la navegación y evita bloqueos de operadora.
3) Poner DNS de Google (8.8.8.8) o devolver a Automático (DHCP).
4) Reparar y Resetear Red: vacía caché DNS, renueva IP y restablece TCP/IP y Winsock.
'@ }
    'Pantalla_Nitidez.ps1' = @{ Titulo = 'Nitidez de pantalla'; Simulable = $true; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true
        Descripcion = 'Resolución nativa (EDID) frente a la actual, Hz máximos, escalado y ClearType. Puede aplicar lo recomendado y revierte solo.'
        Ayuda = @'
CUÁNDO USARLO: texto borroso o pantalla que no va a sus Hz máximos.
'@ }

    # --- Energía ---
    'Control_Energia.ps1' = @{ Titulo = 'Control de energía'; Simulable = $true; Categoria = 'Energía'; Peligroso = $true; SinDestino = $true
        Descripcion = 'Reiniciar, apagar, reiniciar a BIOS UEFI, reinicio con aviso de 5 min o abortar.'
        Ayuda = @'
Permite reiniciar directamente a la BIOS/UEFI sin tener que pulsar F2/Supr al arrancar, apagar o programar un reinicio.
'@ }

    # --- Personalización ---
    'Personalizar_Windows11.ps1' = @{ Titulo = 'Personalizar Windows 11'; Simulable = $true; Categoria = 'Personalización'; Peligroso = $false; SinDestino = $true
        Descripcion = 'Barra a la izquierda, menú clásico Win10, sin Bing, resolución 1920x1080, cambiar nombre del PC y contraseña de tu usuario.'
        Ayuda = @'
Ajustes visuales de Windows 11 + cambio de nombre del equipo y cambio/restablecimiento seguro de contraseña local.
'@ }

    # --- Software ---
    'Instalador_Basico.ps1' = @{ Titulo = 'Instalar apps básicas'; Categoria = 'Software'; Timeout = 5400; Peligroso = $false; SinDestino = $true; Simulable = $true
        Descripcion = 'Equipo nuevo o recién formateado: instala las apps básicas para empezar a trabajar (navegador, compresor, PDF, vídeo...) con casillas: Chrome, Firefox, Brave, WinRAR, 7-Zip, Foxit, VLC... (AnyDesk, Steam y Discord sin marcar). El pack personal añade Office 2013. Con tiempo máximo, reintentos y caché local si el pendrive se desconecta.'
        Ayuda = @'
QUÉ HACE: abre una ventana donde marcas qué programas instalar. Usa winget (máx. 15 min por programa) y, si falla, descarga el instalador oficial y comprueba su firma digital. WinRAR se instala en modo de prueba, salvo que el pack lleve licencia (solo el pack personal). AnyDesk no se instala con arranque automático. Todo queda en Datos\Logs.
'@ }
    'Desinstalar_Office.ps1' = @{ Titulo = 'Desinstalar Office'; Simulable = $true; Categoria = 'Software'; Timeout = 3600; Peligroso = $true; SinDestino = $true
        Descripcion = 'Quita cualquier versión de Office y limpia carpetas y registro para reinstalar de cero. Con modo simulación y punto de restauración.'
        Ayuda = @'
Deja el PC totalmente limpio de versiones anteriores o preinstaladas de Office/365 sin borrar nunca archivos de correo (.pst/.ost).
'@ }
'Analizar_Espacio_Disco.ps1' = @{ Titulo = 'Analizar espacio en disco'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true
        Descripcion = 'Radiografía de qué llena el disco C: (Descargas, AppData, copias iPhone, Windows.old y Top 20 archivos gigantes).'
        Ayuda = @'
CUÁNDO USARLO: cuando el disco C: sigue lleno después de pasar la limpieza de temporales y no sabes dónde se han ido los GB.
Muestra cuánto pesan las carpetas del usuario, si existe Windows.old o copias de móvil, y lista los 20 archivos más pesados (>200 MB) con su ruta exacta.
'@ }
    'Desinstalar_Bloatware_Win11.ps1' = @{ Titulo = 'Quitar bloatware de Windows 11'; Simulable = $true; Categoria = 'Software'; Peligroso = $true; SinDestino = $true
        Descripcion = 'Detecta y desinstala con casillas el Bloatware de Windows 11 (Clipchamp, Bing, Solitario, Cortana, TikTok, etc.).'
        Ayuda = @'
CUÁNDO USARLO: tras formatear o en PCs recién comprados para quitar todas las aplicaciones basura preinstaladas que consumen recursos en segundo plano.
No toca nunca la Microsoft Store, la Calculadora, Fotos ni Seguridad de Windows.
'@ }
    'Quitar_IA_Windows.ps1' = @{ Titulo = 'Quitar IA de Windows'; Categoria = 'Software'; Peligroso = $true; SinDestino = $true; Timeout = 900; Simulable = $true
        Descripcion = 'Desactiva con casillas Copilot, Recall, Click to Do y las funciones de IA de Windows 11; permite añadir otras apps a quitar.'
        Ayuda = @'
CUÁNDO USARLO: en equipos con Windows 11 donde el cliente no quiere Copilot ni Recall (privacidad, rendimiento o por política de la empresa).
QUÉ TOCA: directivas de equipo (valen para todos los usuarios), la característica Recall y sus tareas, y la app de Copilot. Puedes añadir otras apps por su nombre de paquete.
Incluye las directivas de IA de Edge (ojo: HubsSidebarEnabled apaga toda la barra lateral de Edge, no solo Copilot).
QUÉ NO TOCA: no modifica el almacén de componentes ni fuerza componentes que Windows protege; esos quedan inactivos por las directivas. Las opciones de IA de Notepad y Office se ajustan a mano en cada programa.
CÓMO SE DESHACE: se crea un punto de restauración y los cambios van a Mantenimiento > Deshacer cambios. Puede hacer falta reiniciar.
'@ }
    # --- Nuevos en esta versión ---
    'Salud_Pendrive.ps1' = @{ Titulo = 'Salud del pendrive'; Categoria = 'Mantenimiento'; Peligroso = $false; SinDestino = $true; Timeout = 600
        Descripcion = 'Espacio, velocidad real, desconexiones registradas e integridad de los archivos del pendrive donde está el kit.'
        Ayuda = @'
CUÁNDO USARLO: si el kit se cuelga, va lento o el pendrive se desconecta. Mide la escritura/lectura, cuenta las desconexiones guardadas en Datos\Logs y comprueba que no falten archivos del kit.
'@ }
    'Inventario_Equipo.ps1' = @{ Titulo = 'Inventario del equipo'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true; Timeout = 600
        Descripcion = 'Informe HTML con hardware, Windows, discos, red, antivirus, controladores con problemas y programas instalados. Listo para entregar.'
        Ayuda = @'
Genera Datos\Informes\Inventario_<equipo>_<fecha>.html y lo abre en el navegador.
'@ }
    'Punto_Restauracion.ps1' = @{ Titulo = 'Punto de restauración'; Categoria = 'Mantenimiento'; Peligroso = $false; SinDestino = $true; Timeout = 600
        Descripcion = 'Crea un punto de restauración de Windows antes de tocar nada (activa la protección si estaba apagada).'
        Ayuda = @'
Conviene ejecutarlo antes de optimizar, desinstalar programas o cambiar ajustes. Salta el límite de un punto cada 24 horas.
'@ }
    'Copia_Datos_Usuario.ps1' = @{ Titulo = 'Copia de datos del usuario'; Simulable = $true; Categoria = 'Mantenimiento'; Timeout = 14400; Peligroso = $false; SinDestino = $true
        Descripcion = 'Copia de seguridad de Escritorio, Documentos, Imágenes, Descargas y marcadores en la carpeta que elijas (con reintentos).'
        Ayuda = @'
Te pide la carpeta de destino y comprueba que haya espacio. Usa robocopy con reintentos y deja un registro (robocopy.log) junto a la copia.
'@ }
    'Copia_Drivers.ps1' = @{ Titulo = 'Copia de drivers'; Categoria = 'Mantenimiento'; Peligroso = $false; SinDestino = $true; Timeout = 1500
        Descripcion = 'Exporta los controladores de terceros instalados (antes de formatear) a Datos\Drivers\<equipo>.'
        Ayuda = @'
Usa pnputil /export-driver. Comprueba el espacio libre antes. Para reinstalar: pnputil /add-driver "carpeta\*.inf" /subdirs /install
'@ }
    'Restablecer_Windows_Update.ps1' = @{ Titulo = 'Restablecer Windows Update'; Categoria = 'Actualizaciones'; Peligroso = $true; SinDestino = $true; Timeout = 900; Simulable = $true
        Descripcion = 'Arregla Windows Update atascado: reinicia servicios y renombra SoftwareDistribution y catroot2 (sin borrar nada).'
        Ayuda = @'
CUÁNDO USARLO: errores 0x8024..., actualizaciones que no avanzan o se quedan en 0%. Las carpetas antiguas se conservan como .bak_<fecha>.
'@ }
    'Activar_Seguridad_Windows.ps1' = @{ Titulo = 'Activar seguridad de Windows'; Simulable = $true; Categoria = 'Mantenimiento'; Peligroso = $false; SinDestino = $true; Timeout = 900
        Descripcion = 'Activa Defender (tiempo real y firmas) y el Firewall. Si hay otro antivirus activo, no toca Defender.'
        Ayuda = @'
Quita directivas que dejan Defender apagado, arranca sus servicios, activa la protección en tiempo real, actualiza firmas y enciende el firewall en los tres perfiles. Si Windows lo bloquea (Protección contra alteraciones) lo indica y abre Seguridad de Windows.
'@ }
    'Actualizar_Version_Windows.ps1' = @{ Titulo = 'Actualizar versión de Windows'; Simulable = $true; Categoria = 'Actualizaciones'; Peligroso = $true; SinDestino = $true; Timeout = 5400
        Descripcion = 'Sube Windows 11 a la última versión con el asistente oficial de Microsoft (para versiones que ya no reciben parches).'
        Ayuda = @'
Comprueba espacio (15 GB), batería, Internet y reinicios pendientes, descarga el Asistente de instalación de Windows 11 de microsoft.com, verifica su firma y lo ejecuta. Conserva programas y archivos. Tarda de 30 a 90 minutos y reinicia el equipo.
'@ }
    'Reparar_Red.ps1' = @{ Titulo = 'Reparar red'; Categoria = 'Mantenimiento'; Peligroso = $false; SinDestino = $true; Timeout = 900; Simulable = $true
        Descripcion = 'Repara la red: vacía DNS, renueva IP y restablece Winsock y TCP/IP.'
        Ayuda = @'
Para problemas de conexión sin causa clara (sin Internet con Wi-Fi conectado, páginas que no cargan). Conviene reiniciar al terminar.
'@ }
    'Reparar_Inicio_Barra_Explorador.ps1' = @{ Titulo = 'Reparar Inicio, barra y Explorador'; Categoria = 'Mantenimiento'; Peligroso = $false; SinDestino = $true; Timeout = 900; Simulable = $true
        Descripcion = 'El menú Inicio no abre, la barra de tareas no responde o los iconos salen en blanco: reinicia el Explorador, vuelve a registrar los paquetes de la interfaz y reconstruye la caché de iconos.'
        Ayuda = 'Primero enseña el estado (Explorador, paquetes de Inicio/barra/búsqueda, servicio de búsqueda, tamaño de la caché de iconos) y luego tú marcas qué reparar. No borra documentos ni cambia ajustes. El Explorador se cierra un momento y Windows lo vuelve a abrir solo. Si el fallo sigue, cierra sesión y vuelve a entrar.' }
    'Reparar_Audio_y_Privacidad.ps1' = @{ Titulo = 'Reparar audio y privacidad'; Categoria = 'Mantenimiento'; Peligroso = $false; SinDestino = $true; Timeout = 600; Simulable = $true
        Descripcion = 'No hay sonido, el micrófono no funciona en ninguna aplicación o la cámara sale bloqueada: reinicia los servicios de audio, activa dispositivos desactivados y corrige los permisos de privacidad.'
        Ayuda = 'Comprueba los servicios de audio, las entradas y salidas desactivadas y los permisos de micrófono y cámara (en tu cuenta y en todo el equipo). Tú marcas qué reparar; los cambios de permisos se pueden deshacer desde «Deshacer cambios». Si una directiva de la organización bloquea el micrófono o la cámara, solo se avisa: no se toca.' }
    'Hora_y_Sincronizacion.ps1' = @{ Titulo = 'Hora y sincronización'; Categoria = 'Mantenimiento'; Peligroso = $false; SinDestino = $true; Timeout = 600; Simulable = $true
        Descripcion = 'La hora va mal o da errores de certificado y de inicio de sesión: mide el desfase contra un servidor de hora, comprueba el servicio y sincroniza.'
        Ayuda = 'Mide el desfase con una consulta NTP directa (no depende del idioma de Windows). Puedes poner el servicio de hora en automático, configurar los servidores (time.windows.com y pool.ntp.org; no hace falta en un dominio) y sincronizar. Si la hora se desajusta al apagar el equipo, suele ser la pila de la placa base. La zona horaria no se cambia.' }
    'Entorno_Corporativo.ps1' = @{ Titulo = 'Equipo de empresa'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true; Timeout = 120; Simulable = $false
        Descripcion = 'Vas a tocar un equipo que quizá no es de un particular: comprueba si lo gestiona una empresa (dominio, Entra ID, Intune, directivas de grupo).'
        Ayuda = 'Solo lee el registro y los datos del sistema; no cambia nada. Si hay indicios de gestión, avisa a quien lo administra antes de tocar red, directivas, usuarios o programas. No ve lo que una empresa pueda aplicar más tarde.' }
    'Certificados_Arranque_Seguro.ps1' = @{ Titulo = 'Certificados de arranque seguro'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true; Timeout = 300; Simulable = $true
        Descripcion = 'Los certificados de Microsoft de 2011 caducan en 2026: comprueba si el equipo ya tiene los de 2023 y, si faltan, ofrece lanzar la actualización.'
        Ayuda = 'Mira Secure Boot, las variables UEFI db y KEK y el estado de la actualización de Windows. No cambia nada hasta que lo confirmas. Si faltan certificados y confirmas, crea un punto de restauración, suspende BitLocker durante 2 reinicios y lanza la tarea de Windows que los aplica; después hay que reiniciar. En algún equipo la BIOS pide la clave de BitLocker al reiniciar: ten la clave de recuperación. Necesita administrador.' }
    'Que_Esta_Frenando_Ahora.ps1' = @{ Titulo = 'Qué lo está frenando ahora'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true; Timeout = 600; Simulable = $true
        Descripcion = 'Va lento ahora mismo: mide unos segundos y dice qué proceso satura procesador, disco y memoria, con opción de cerrarlo o parar el servicio.'
        Ayuda = 'Usa los contadores de rendimiento de Windows. Enseña los 5 que más consumen de cada recurso y deja marcar qué cerrar (con educación; a la fuerza solo si no responde, y se dice cuál) o qué servicio prescindible parar hasta el próximo reinicio. Nunca ofrece procesos del sistema ni el antivirus. Lo que no esté guardado en un programa cerrado se pierde.' }
    'Reparar_Office_y_Caches.ps1' = @{ Titulo = 'Reparar Office y cachés'; Categoria = 'Mantenimiento'; Peligroso = $false; SinDestino = $true; Timeout = 2400; Simulable = $true
        Descripcion = 'Word, Excel u Outlook se cuelgan, Teams va lento o OneDrive no sincroniza: reparación rápida de Office y limpieza de las cachés de Teams y OneDrive.'
        Ayuda = 'Detecta Office (Click-to-Run), Teams (clásico y nuevo) y OneDrive y tú marcas qué hacer. Los programas se cierran con educación; si alguno tiene algo sin guardar, esa tarea se salta. Limpiar Teams obliga a iniciar sesión otra vez. Restablecer OneDrive no borra archivos. La caché de autocompletado de Outlook no se toca.' }
    'Red_Avanzada.ps1' = @{ Titulo = 'Red avanzada'; Categoria = 'Mantenimiento'; Peligroso = $false; SinDestino = $true; Timeout = 600; Simulable = $true
        Descripcion = 'El Wi-Fi se corta, no ves equipos ni impresoras o hay Internet pero no cargan páginas: revisa proxy, ahorro de energía, SMB, firewall, DNS y puertos, y repara cada punto por separado.'
        Ayuda = 'Comprueba por separado el proxy (y si responde), el ahorro de energía del adaptador, los servicios de compartir archivos, las reglas del firewall para la red privada, el DNS y el alcance de varios puertos (puedes añadir los tuyos con -Puertos host:puerto). Cada reparación se elige aparte y deja anotado cómo deshacerla. No restablece toda la pila de red: para eso está «Reparar red».' }
    'Auditoria_Seguridad.ps1' = @{ Titulo = 'Auditoría de seguridad'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true; Timeout = 600
        Descripcion = '¿Está protegido este equipo? Revisa antivirus, firewall, UAC, Escritorio remoto, administradores y tareas o servicios que arrancan desde carpetas de usuario.'
        Ayuda = 'Solo lectura: no cambia nada. Marca con un aviso lo que merece una mirada (antivirus apagado o con firmas viejas, firewall desactivado, inicio de sesión automático, tareas o servicios que ejecutan programas desde AppData o Temp). Puede haber falsos positivos con programas legítimos mal instalados. Con administrador las lecturas son más completas.' }
    'Limpieza_Total.ps1' = @{ Titulo = 'Limpieza total del equipo'; Categoria = 'Mantenimiento'; Peligroso = $true; SinDestino = $true; Timeout = 7200; Simulable = $true
        Descripcion = 'Equipo lleno o lento: pasa en un solo paso temporales y cachés, la limpieza profunda de Windows y, si quieres, los navegadores, y dice cuánto espacio se ha liberado.'
        Ayuda = @'
Encadena «Limpiar temporales», «Limpieza profunda de Windows» y «Limpiar navegadores» (este último solo si lo confirmas). Antes crea un punto de restauración y al final compara el espacio libre en C:. No toca documentos ni programas: para quitar programas está «Desinstalador de apps». Cada paso conserva sus propios avisos de lo que no se puede deshacer (Windows.old, registros de eventos, cookies e historial). Con -SoloAnalizar solo calcula lo que liberaría.
'@ }
    'Desinfeccion_Guiada.ps1' = @{ Titulo = 'Desinfección guiada'; Categoria = 'Mantenimiento'; Peligroso = $true; SinDestino = $true; Timeout = 21600; Simulable = $true
        Descripcion = 'Sospecha de virus o adware (va raro, sale publicidad, el navegador cambia solo): revisa el estado, crea un punto de restauración y abre uno tras otro los escáneres del kit.'
        Ayuda = @'
Primero solo mira (antivirus, tareas y servicios sospechosos, procesos en carpetas de usuario). Luego crea un punto de restauración y abre KVRT, AdwCleaner y, si están en Apps\Malware, Sophos y Trellix Stinger, esperando a que cierres cada uno. No borra nada por su cuenta: cada escáner pone en cuarentena lo que aceptes en su ventana y se restaura desde ella. Necesita Internet (firmas) y a un técnico delante; no se ejecuta en modo automático. Al terminar, reinicia y repite «Auditoría de seguridad».
'@ }
    'Comprobar_WMI_y_Runtimes.ps1' = @{ Titulo = 'WMI y runtimes'; Categoria = 'Mantenimiento'; Peligroso = $false; SinDestino = $true; Timeout = 900; Simulable = $true
        Descripcion = 'Un programa dice que WMI falla o faltan DLL de Visual C++ o .NET: comprueba WMI, lista los runtimes instalados y, si WMI no responde, ofrece salvar su repositorio.'
        Ayuda = 'Prueba varias consultas WMI con tiempo máximo y enseña los Visual C++ Redistributable y el .NET Framework instalados (solo informa; instalarlos es cosa del instalador oficial de Microsoft). Si WMI falla, ofrece «salvar el repositorio», el método suave: reconstruye lo legible y conserva lo demás. No restablece WMI de cero.' }
    'Por_Que_Falla_Windows_Update.ps1' = @{ Titulo = 'Por qué falla Windows Update'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true; Timeout = 600
        Descripcion = 'Una actualización no se instala o da error 0x80…: lee los fallos recientes, traduce el código a una causa y recomienda qué hacer.'
        Ayuda = 'Solo lectura. Reúne los últimos fallos del registro de Windows Update con su código de error y su causa habitual, y comprueba servicios, espacio libre y reinicio pendiente. Recomienda la herramienta del kit adecuada (DISM, SFC, Restablecer Windows Update, Red avanzada). Parámetro -Dias para mirar más atrás.' }
    'Reparar_Arranque_y_WinRE.ps1' = @{ Titulo = 'Reparar arranque y WinRE'; Categoria = 'Mantenimiento'; Peligroso = $true; SinDestino = $true; Timeout = 900; Simulable = $true
        Descripcion = 'HERRAMIENTA TÉCNICA: tras clonar o si Windows no arranca, diagnostica UEFI/BIOS, la partición EFI, el BCD y WinRE, y reconstruye los archivos de arranque o habilita la recuperación.'
        Ayuda = 'Primero solo mira (UEFI o BIOS, partición EFI o activa, si el BCD se puede leer, estado real de WinRE por ReAgent.xml y su partición). Luego tú marcas qué hacer: habilitar WinRE (reagentc /enable) y/o reconstruir el arranque (bcdboot). Antes guarda una copia del BCD y exige una confirmación que ningún modo automático acepta. Para volver atrás: -RestaurarBcd con el bcd.bak guardado. Prueba antes en una máquina virtual.' }
    'Desinstalar_Total.ps1' = @{ Titulo = 'Desinstalador de apps'; Categoria = 'Software'; Peligroso = $true; PublicoOk = $true; SinDestino = $true; Timeout = 7200; Simulable = $true
        Descripcion = 'Desinstala uno o varios programas y limpia sus restos (carpetas, registro, servicios, tareas, firewall, inicio). Todo va a una cuarentena reversible.'
        Ayuda = @'
Marca uno o varios programas (lo marcado se conserva al filtrar por texto): se confirma una vez, se crea un solo punto de restauración y se van quitando uno tras otro. Cada programa se desinstala con su desinstalador oficial y luego se buscan los restos. Tú marcas lo que se borra (los dudosos vienen sin marcar). Las carpetas se mueven a una cuarentena y el registro se exporta en .reg, así que se puede deshacer. La casilla «borrar también mis datos» deja el programa como una instalación limpia (cuidado con navegadores y correo: incluye perfiles y marcadores). Avisa si es un componente compartido (runtimes, controladores).
'@ }
    'Limpiar_Navegadores.ps1' = @{ Titulo = 'Limpiar navegadores'; Categoria = 'Mantenimiento'; Peligroso = $false; SinDestino = $true; Timeout = 900; Simulable = $true
        Descripcion = 'El navegador va lento o una web no carga bien: limpia caché, historial, cookies y datos guardados de Edge, Chrome, Brave, Vivaldi, Opera y Firefox, eligiendo qué.'
        Ayuda = @'
Detecta los navegadores instalados y deja marcar, por navegador, qué limpiar. Vienen marcados la caché y el historial; cookies (cierran sesiones), formularios, contraseñas y sesión van sin marcar, y los tres últimos piden una confirmación extra que ningún modo automático salta. Los marcadores nunca se borran y hay una casilla para copiarlos antes. El historial incluye la lista de descargas, pero no los archivos descargados; en Firefox no se ofrece historial. Los navegadores abiertos se cierran con educación (guarda antes lo que tengas en pestañas). El borrado es definitivo: no hay «Deshacer cambios» para esto. Solo limpia el perfil del usuario con el que corre el kit.
'@ }
    'Limpiar_Registro_Huerfano.ps1' = @{ Titulo = 'Limpiar registro huérfano'; Categoria = 'Software'; Peligroso = $true; SinDestino = $true; Timeout = 1800; Simulable = $true
        Descripcion = 'Busca en el registro restos de programas ya borrados (entradas sin programa, inicio, rutas, DLL compartidas, ayuda, fuentes, cortafuegos, servicios y tareas que apuntan a archivos inexistentes) y los limpia.'
        Ayuda = @'
Solo propone entradas que apuntan a un archivo que ya no existe en una unidad fija y conectada: nunca claves de Windows ni de controladores, y una unidad ausente (pendrive) no cuenta como resto. Servicios, tareas, fuentes, reglas del cortafuegos, complementos del navegador y extensiones vienen sin marcar. Antes de borrar cada entrada se crea un punto de restauración y se guarda su copia .reg en la cuarentena de «Desinstalador de apps»: desde ahí se restaura la sesión «..._Registro». No es una limpieza para «acelerar» el equipo: quita basura, no cambia el rendimiento. Para desinstalar un programa y sus carpetas usa «Desinstalador de apps».
'@ }
    'Asistente_Guiado_Inteligente.ps1' = @{ Oculto = $true }   # tiene tarjeta propia en $Herramientas del lanzador
    'Restaurar_Cuarentena.ps1' = @{ Titulo = 'Restaurar cuarentena'; Simulable = $true; Categoria = 'Software'; Peligroso = $false; SinDestino = $true; Timeout = 1800
        Descripcion = 'Deshace una limpieza de Desinstalar Total: devuelve carpetas y registro desde la cuarentena.'; Ayuda = 'Elige la sesión a restaurar. Si el programa se desinstaló, habrá que reinstalarlo.' }
    'Vaciar_Cuarentena.ps1' = @{ Titulo = 'Vaciar cuarentena'; Categoria = 'Software'; Peligroso = $true; SinDestino = $true; Timeout = 1800; Simulable = $true
        Descripcion = 'Borra definitivamente la cuarentena de Desinstalar Total para liberar espacio.'; Ayuda = 'Después ya no se podrá restaurar nada de lo que se quitó.' }
    'Deshacer_Cambios.ps1' = @{ Titulo = 'Deshacer cambios'; Simulable = $true; Categoria = 'Mantenimiento'; Peligroso = $false; SinDestino = $true; Timeout = 1800
        Descripcion = 'Deshace los cambios de otros scripts (registro, servicios, DNS, arranque, paginación, nombre del equipo) a como estaban.'
        Ayuda = 'Cada script que cambia ajustes guarda el estado anterior en Datos\Respaldo\Cambios y crea un punto de restauración. Aquí eliges la sesión y se revierte todo en orden inverso. Algunos cambios (contraseñas, apps quitadas) no se pueden revertir solos: se indican.' }

    # --- Diagnóstico avanzado e informes HTML (en Datos\Informes) ---
    'Analizador_BSOD_y_Eventos.ps1' = @{ Titulo = 'Pantallazos y eventos'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true; Timeout = 900
        Descripcion = 'Forense de pantallazos azules: minidumps y drivers .sys implicados, errores físicos WHEA, cortes Kernel-Power 41 y fallos de GPU (TDR).'
        Ayuda = 'Solo lee: no cambia nada. Los LiveKernelReports (cuelgues recuperados sin pantallazo) se listan aparte y no cuentan como BSOD.' }
    'Monitor_Latencia_y_Red.ps1' = @{ Titulo = 'Latencia de red'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true; Timeout = 600
        Descripcion = 'Distingue si los cortes de Internet son del Wi-Fi/router o de la operadora: latencia, jitter, pérdida de paquetes y velocidad de los DNS.'
        Ayuda = 'Tarda alrededor de un minuto (15 pings al router, a Cloudflare y a Google). Solo mide: no cambia la configuración de red.' }
    'DNS_Mas_Rapido.ps1' = @{ Titulo = 'DNS más rápido'; Simulable = $true; Categoria = 'Mantenimiento'; Peligroso = $false; SinDestino = $true; Timeout = 420
        Descripcion = 'Webs que tardan en empezar a cargar o ping alto en juegos: mide 8 DNS públicos desde este equipo y pone el más rápido.'
        Ayuda = 'Prueba 5 webs x 3 rondas en cada servidor (Cloudflare, Google, Quad9, OpenDNS, AdGuard, CleanBrowsing, Control D y DNS.SB) y tu DNS actual. Solo cambia si la mejora es clara (más de 3 ms y un 15 %). Pregunta antes de cambiar. Solo toca el DNS de los adaptadores físicos activos; no se cambia en equipos de dominio. Si con el nuevo no se resuelve nada, devuelve el anterior. Se deshace en Mantenimiento > Deshacer cambios. Sin ventana: -Aplicar (pone el mejor) o -SinPreguntas (solo mide).' }
    'Cambiar_IP.ps1' = @{ Titulo = 'Cambiar IP'; Simulable = $true; Categoria = 'Mantenimiento'; Peligroso = $false; SinDestino = $true; Timeout = 1800
        Descripcion = 'Pon IP fija o DHCP, cambia el DNS, guarda perfiles de IP rápidos y activa, desactiva o renueva un adaptador de red.'
        Ayuda = @'
QUÉ HACE: abre una ventana con los adaptadores de red y su configuración actual. Permite IP manual (IP, máscara, puerta y DNS), volver a DHCP, aplicar perfiles guardados (Datos\Perfiles_IP.json), activar o desactivar el adaptador y liberar o renovar el DHCP.
SE DESHACE: la IP y el DNS anteriores quedan guardados; Mantenimiento > Deshacer cambios los devuelve.
OJO: si cambias la IP del adaptador por el que llega Internet o una conexión remota, se cortará. Sin ventana: -Dhcp o -IP <ip> -Mascara -Puerta -Dns, y -Adaptador <nombre>.
'@ }
    'Latencia_DPC.ps1' = @{ Titulo = 'Latencia DPC'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true; Timeout = 300
        Descripcion = 'Tirones de audio o vídeo, ratón a saltos: mide cuánto tiempo pierde la CPU atendiendo drivers (DPC) e interrupciones.'
        Ayuda = 'Mide 20 segundos y da un veredicto orientativo (normal, elevado o alto). Solo lee contadores: no cambia nada. No señala qué driver lo causa; para eso hace falta LatencyMon o xperf.' }
    'Asesor_BIOS.ps1' = @{ Titulo = 'Asesor de BIOS'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true; Timeout = 120
        Descripcion = 'Quieres sacarle más al equipo: lee la BIOS y dice qué opciones activar (XMP/EXPO, Resizable BAR, virtualización, Secure Boot, TPM) y dónde están.'
        Ayuda = 'Solo lee lo que Windows ve de la BIOS: no cambia nada en Windows ni en la BIOS. Las rutas de menú son orientativas según la marca de la placa. Si hay BitLocker, avisa de suspenderlo antes de entrar en la BIOS.' }
    'Clonar_Disco.ps1' = @{ Titulo = 'Clonar disco (Windows a otro disco)'; Categoria = 'Mantenimiento'; Peligroso = $true;SinDestino = $true; Timeout = 43200
        Descripcion = 'Cambias de disco (HDD a SSD o a uno más pequeño) y quieres llevarte Windows tal cual: copia el sistema, los datos y deja el arranque listo.'
        Ayuda = 'Elige origen y destino; empieza en modo simulación (enseña el plan y no cambia nada). Al clonar de verdad BORRA ENTERO el disco destino y exige escribir la confirmación. Nunca deja elegir el disco de Windows en marcha ni el del kit. El origen no se modifica. Copia Windows con DISM desde una instantánea (VSS) usando una imagen temporal en otro disco con sitio libre. Solo discos GPT/UEFI, no dinámicos. Si había BitLocker, el destino queda sin cifrar. Después de clonar, desconecta el disco antiguo antes de arrancar con el nuevo.' }
    'Disco_Destino_Instalacion.ps1' = @{ Titulo = 'Disco que borraría el instalador'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true; Timeout = 60
        Descripcion = 'Vas a instalar Windows con Rufus en modo silencioso o con un autounattend: te dice qué disco se borraría (el 0), qué tiene dentro y si es el de Windows.'
        Ayuda = 'Solo lee los discos y sus particiones: no cambia ni borra nada. La instalación silenciosa de Rufus formatea el primer disco entero, con todas sus particiones (también las de datos). Si hay más de un disco, desactiva el puerto de los demás en la BIOS o desconecta su cable antes de arrancar.' }
    'Uso_VRAM.ps1' = @{ Titulo = 'Uso de VRAM'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true; Timeout = 120
        Descripcion = 'Juegos a tirones o memoria de vídeo insuficiente: muestra la VRAM usada por cada gráfica y los procesos que más gastan.'
        Ayuda = 'Solo lee contadores de GPU (Windows 10 1709 o superior con driver oficial). No cierra procesos ni cambia nada.' }
    'Auditoria_Licencias_BitLocker.ps1' = @{ Titulo = 'Licencias y BitLocker'; Categoria = 'Diagnóstico'; Peligroso = $true; SinDestino = $true; Timeout = 600
        Descripcion = 'Resguardo antes de formatear o tocar la BIOS: clave OEM de la placa, activación de Windows, TPM, Secure Boot y claves de BitLocker.'
        Ayuda = 'OJO: el informe HTML contiene las claves de recuperación de BitLocker en texto claro y se abre desde la carpeta temporal del equipo, no del pendrive. Si hay que entregarlo, guárdalo tú donde quieras y bórralo al cerrar el parte.' }
    'Ficha_Drivers.ps1' = @{ Titulo = 'Ficha de drivers'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true; Timeout = 300
        Descripcion = 'Quieres saber qué driver falta o es genérico: lista cada dispositivo con su Hardware ID, chip y driver, y deja un enlace al Catálogo de Microsoft para buscarlo.'
        Ayuda = 'Solo lee: no instala, no descarga y no cambia nada. Genera un informe con los dispositivos con problema, con el driver básico de Windows, con driver de más de 4 años y los correctos. El enlace al Catálogo de Microsoft Update solo se abre si lo pulsas en el informe. En equipos HP y Lenovo, «Drivers del fabricante» hace lo mismo con el catálogo oficial del modelo. Un driver antiguo que funciona no hace falta cambiarlo.' }
    'Limpiar_Almacen_Drivers.ps1' = @{ Titulo = 'Limpiar almacén de drivers'; Categoria = 'Mantenimiento'; Peligroso = $true; SinDestino = $true; Timeout = 3600; Simulable = $true
        Descripcion = 'El disco se llena sin motivo: quita del almacén de drivers las versiones antiguas de gráfica, audio o impresora que ya no usa ningún dispositivo.'
        Ayuda = 'Primero lista los paquetes y marcas lo que quitar; solo se proponen los que ningún dispositivo usa (las versiones antiguas ya sustituidas vienen marcadas; las de un dispositivo que no está conectado, sin marcar). Nunca toca los de Windows, los que están en uso ni los de arranque. Antes crea un punto de restauración y guarda una copia de cada paquete en Datos\Drivers\Almacen_<fecha>; se borra con pnputil sin forzar, así que Windows se niega si algo lo usa. Para recuperar uno: pnputil /add-driver <copia>\oemNN\*.inf /install.' }
    'Instalar_Driver_Catalogo.ps1' = @{ Titulo = 'Driver desde el Catálogo de Microsoft'; Categoria = 'Mantenimiento'; Peligroso = $true; SinDestino = $true; Timeout = 5400; Simulable = $true
        Descripcion = 'Un dispositivo sin driver o con el básico de Windows: elige cuál, busca su driver en el Catálogo de Microsoft Update, lo descarga, comprueba su firma y lo instala.'
        Ayuda = 'Elige el dispositivo y enseña el driver más reciente para tu Windows (versión, fecha y tamaño). No instala nada sin que lo confirmes: descarga de servidores de Microsoft, comprueba que cada catálogo lleva firma válida de Microsoft, crea un punto de restauración y lo instala con pnputil. Si algo falla, no cambia el equipo. Para consultar el catálogo se envía a Microsoft el Hardware ID del dispositivo (un código público del chip, sin datos personales).' }
    'Quien_Bloquea.ps1' = @{ Titulo = 'Quién bloquea un archivo o disco'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true; Timeout = 600; Simulable = $true
        Descripcion = 'Windows dice «el archivo está en uso» o no deja expulsar el disco: te dice qué programa lo tiene abierto.'
        Ayuda = 'Elige un archivo, una carpeta o una unidad y usa el Administrador de reinicio de Windows para saber qué programas la tienen abierta (y qué programas se ejecutan desde ella). Solo mira. Al final, si lo confirmas, puede cerrar los programas de la lista (nunca los de Windows ni el Explorador; lo que no esté guardado se pierde).' }
    'Editor_Hosts.ps1' = @{ Titulo = 'Editor del archivo HOSTS'; Categoria = 'Mantenimiento'; Peligroso = $true; SinDestino = $true; Timeout = 900; Simulable = $true
        Descripcion = 'Una web no abre o va a otro sitio sin motivo: enseña el archivo HOSTS, marca lo sospechoso y deja corregirlo.'
        Ayuda = 'El HOSTS fuerza que un nombre de web vaya a otra dirección; lo usan los bloqueadores de anuncios y también virus y programas viejos. Marca como sospechosas las redirecciones de nombres delicados (Windows Update, antivirus, bancos...). Antes de guardar hace una copia en Datos\Respaldo\Hosts y se puede restaurar el contenido original de Windows. Hace falta administrador para guardar.' }
    'Quitar_Dispositivos_Fantasma.ps1' = @{ Titulo = 'Dispositivos fantasma'; Categoria = 'Mantenimiento'; Peligroso = $true; SinDestino = $true; Timeout = 1800; Simulable = $true
        Descripcion = 'Pendrives, móviles y monitores que ya no están conectados siguen registrados en Windows y a veces dan conflictos: los lista y los quita.'
        Ayuda = 'Lista los dispositivos USB, de almacenamiento, Bluetooth y monitores que ya no están presentes. Los habituales (USB, móviles, discos externos, monitores) vienen marcados; el resto, sin marcar. Quitar la entrada no borra nada del dispositivo: Windows la recrea al enchufarlo. Crea un punto de restauración antes y usa pnputil /remove-device (Windows 10 2004 o superior).' }
    'Limpiar_Espacio_Windows.ps1' = @{ Titulo = 'Limpieza profunda de Windows'; Categoria = 'Mantenimiento'; Peligroso = $true; SinDestino = $true; Timeout = 3600; Simulable = $true
        Descripcion = 'Falta espacio en C: y quieres saber cuánto ocupa cada cosa antes de borrar: miniaturas, registros, cachés de la gráfica y de la Tienda, caché de actualizaciones, volcados y Windows.old.'
        Ayuda = 'Calcula primero cuánto ocupa cada categoría y te deja elegir. Propuestas seguras que se regeneran solas (miniaturas, registros CBS, caché de Delivery Optimization, cachés de shaders de la GPU, caché de certificados, temporales de apps de la Tienda, logs ETL de Windows Update y restos de instaladores) y opcionales sin marcar: informes de errores de Windows (WER), caché de instalación de drivers (INFCACHE.1), volcados de memoria (los técnicos los usan para diagnosticar pantallazos), registros del Visor de eventos (no se pueden recuperar) y Windows.old (al quitarlo no se puede volver a la versión anterior de Windows); estas dos piden una confirmación extra. Complementa a «Limpiar temporales».' }
    'Ajustes_Rapidos_Soporte.ps1' = @{ Titulo = 'Ajustes rápidos de soporte'; Categoria = 'Mantenimiento'; Peligroso = $false; SinDestino = $true; Timeout = 300; Simulable = $true
        Descripcion = 'Antes de entregar el equipo: sin autoejecución en USB, sin reinicios por sorpresa con la sesión abierta y, si quieres, sin drivers por Windows Update ni hibernación.'
        Ayuda = 'Muestra cuáles de estos ajustes ya están puestos y te deja elegir los que faltan: sin autoejecución en USB y unidades, sin reinicio automático por actualizaciones con una sesión abierta, Windows Update sin drivers (sin marcar) apagar la hibernación para liberar hiberfil.sys (sin marcar: también quita el inicio rápido), desactivar el servicio de Registro remoto y, sin marcar, el de telemetría DiagTrack. Cada cambio queda registrado y se deshace desde «Deshacer cambios». No toca Defender, el firewall, UAC ni SmartScreen. Con -SoloAnalizar solo dice cuáles están puestos.' }
    'Prueba_Capacidad_USB.ps1' = @{ Titulo = 'Prueba de capacidad real (USB)'; Categoria = 'Diagnóstico'; Peligroso = $true; SinDestino = $true; Timeout = 21600; Simulable = $true
        Descripcion = 'Un pendrive, tarjeta o disco externo barato que anuncia mucho más de lo que guarda: llena el espacio libre, lo lee y dice cuánto guarda de verdad.'
        Ayuda = 'Escribe archivos de prueba (bloques de 1 MB numerados) en el ESPACIO LIBRE del dispositivo que elijas, los vuelve a leer y compara. Si lo leído no coincide, la capacidad real es menor que la anunciada. Borra los archivos de prueba al terminar y no toca los tuyos, pero en un dispositivo falsificado lo que ya tuviera guardado puede estropearse: haz copia antes. Nunca prueba el disco de Windows ni el del kit. Tarda de 5 a 10 minutos por cada 10 GB en un pendrive básico. Con poco volumen respecto a la RAM pide expulsar y volver a conectar el dispositivo para que la lectura no salga de la caché de Windows. Con -SoloAnalizar solo lista los candidatos.' }
    'Prueba_Puertos_USB.ps1' = @{ Titulo = 'Prueba de puertos USB'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true; Timeout = 3600; Simulable = $true
        Descripcion = 'Un puerto USB que va lento o no reconoce bien: mide la velocidad real de escritura y lectura puerto por puerto y dice si rinde como USB 3 o como USB 2.'
        Ayuda = 'Escribe y lee un archivo temporal de 256 MB en el pendrive o disco USB que elijas (nunca el disco de Windows ni el del kit) y clasifica la velocidad: USB 3, USB 2 o peor. Después te deja cambiar el dispositivo de puerto y repetir, y al final da una tabla de puertos. Mide el conjunto puerto + cable + dispositivo: para saber si un puerto es USB 3 usa un dispositivo USB 3 conocido. Con administrador vacía la caché de Windows antes de leer (si no, la lectura sale inflada y solo se fía la escritura). No toca tus archivos y borra el temporal al terminar. Con -SoloAnalizar solo lista los controladores y dispositivos.' }
    'Bluetooth_Diagnostico.ps1' = @{ Titulo = 'Bluetooth'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true; Timeout = 300; Simulable = $true
        Descripcion = 'El Bluetooth no aparece, no conecta o se ha ido: comprueba el adaptador, su driver y los servicios, y lo reinicia si hace falta.'
        Ayuda = 'Mira si hay adaptador Bluetooth y si tiene driver, el estado de los servicios de Bluetooth y cuántos dispositivos hay emparejados. Si algo está mal y aceptas (o usas -Reparar), pone el servicio en inicio manual y lo arranca y reinicia el adaptador (lo desactiva y lo activa). No borra emparejamientos ni toca drivers. Lo que cambia queda registrado y se deshace desde «Deshacer cambios». Con -SoloAnalizar solo mira.' }
    'Disco_Sucio_y_Reinicios.ps1' = @{ Titulo = 'Disco sucio y reinicios pendientes'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true; Timeout = 120
        Descripcion = 'Antes de instalar drivers o clonar: dice si algún disco está marcado como sucio y si hay un reinicio pendiente.'
        Ayuda = 'Solo mira: usa fsutil dirty query en cada unidad NTFS, busca una comprobación de disco programada para el próximo arranque y los avisos de reinicio pendiente de Windows (actualizaciones, instaladores, cambio de nombre). No repara ni cambia nada.' }
    'Optimizar_Unidades.ps1' = @{ Titulo = 'Optimizar unidades (TRIM)'; Categoria = 'Mantenimiento'; Peligroso = $false; SinDestino = $true; Timeout = 10800; Simulable = $true
        Descripcion = 'El equipo va lento con el disco muy lleno o hace tiempo que no se optimiza: TRIM en SSD y desfragmentar solo los discos duros que lo necesitan.'
        Ayuda = 'Distingue cada unidad: en un SSD lanza TRIM y no desfragmenta nunca; en un disco duro mecánico mide la fragmentación y solo desfragmenta si pasa del 10 %; las de tipo desconocido se saltan. No toca datos. Pide confirmación antes y puede tardar en discos duros llenos.' }
    'Actualizar_Herramientas.ps1' = @{ Titulo = 'Actualizar herramientas'; Categoria = 'Mantenimiento'; Peligroso = $true; SinDestino = $true; Timeout = 3600; Simulable = $true
        Descripcion = 'Las apps de Apps\ se quedan viejas: comprueba cada una en su fuente oficial y actualiza las que elijas, con copia de la versión anterior.'
        Ayuda = 'Consulta GitHub o la web de cada autor, descarga lo que marques, verifica el SHA-256 publicado o la firma digital del autor y guarda la versión anterior en Datos\Respaldo antes de reemplazar. Los programas sin descarga directa estable solo se listan con su web oficial. Si un programa está abierto, hay que cerrarlo antes. Cambia archivos del kit, por eso no sale en el pack público.' }
    'Componentes_Kit.ps1' = @{ Titulo = 'Componentes del kit'; Categoria = 'Mantenimiento'; Peligroso = $false; SinDestino = $true; Timeout = 300; Simulable = $true
        Descripcion = 'La temperatura de la CPU no es fiable: estado del controlador de sensores PawnIO, smartmontools y LibreHardwareMonitor, y instalarlo o quitarlo.'
        Ayuda = 'Muestra si están el controlador de sensores PawnIO (firmado, de código abierto), smartmontools y LibreHardwareMonitor. El controlador permite leer la temperatura real de la CPU, los ventiladores y la potencia; se instala una vez por equipo y solo si lo confirmas, y se puede quitar con la misma herramienta (recomendado en equipos de clientes). Hace falta administrador para instalar o quitar.' }
    'Auditoria_Drivers_Huerfanos.ps1' = @{ Titulo = 'Drivers con fallo'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true; Timeout = 900
        Descripcion = 'Dispositivos con fallo en el Administrador de dispositivos (códigos 43, 28, 10...), su Hardware ID y el tamaño de DriverStore.' }
    'LimpiarTemporalesEquipo.ps1' = @{ Titulo = 'Limpiar temporales'; Categoria = 'Mantenimiento'; Peligroso = $false; SinDestino = $true; Simulable = $true
        Descripcion = 'Limpia temporales de Windows, caché de navegadores, Prefetch y papelera sin tocar documentos del usuario.' }
    'Reparar_Impresoras.ps1' = @{ Titulo = 'Reparar impresoras'; Categoria = 'Mantenimiento'; Peligroso = $false; SinDestino = $true; Timeout = 600; Simulable = $true
        Descripcion = 'Vacía la cola de impresión atascada, reinicia el servicio y quita el modo «sin conexión». Ofrece una página de prueba.'
        Ayuda = 'Se pierden los trabajos que estaban esperando en la cola. No desinstala impresoras ni drivers.' }
    'Instalar_Impresora_Red.ps1' = @{ Titulo = 'Instalar impresora de red'; Simulable = $true; Categoria = 'Mantenimiento'; Peligroso = $false; SinDestino = $true; Timeout = 900
        Descripcion = 'Añade una impresora por su dirección IP: comprueba que responde, crea el puerto y la instala con el mejor controlador que haya en el equipo.'
        Ayuda = 'Pide la IP (está en la pantalla de la impresora o en su hoja de configuración). No descarga controladores: usa el universal del fabricante si está instalado o el genérico IPP de Windows. Ofrece una página de prueba.' }
    'Reparar_TPM.ps1' = @{ Titulo = 'Reparar TPM'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true; Timeout = 900; Simulable = $true
        Descripcion = 'Para «este equipo no cumple los requisitos de Windows 11» o «TPM no detectado»: revisa TPM 2.0, UEFI y Secure Boot y reactiva el chip.'
        Ayuda = 'Arranca el servicio TBS, reactiva el dispositivo en Windows y, en HP y Lenovo, puede pedir a la BIOS que encienda el chip (pregunta antes y se aplica al reiniciar). En otras marcas indica los pasos a mano. Nunca borra el TPM: no se pierden claves de BitLocker ni de Windows Hello.' }
    'Reparar_Drivers_OEM.ps1' = @{ Titulo = 'Drivers del fabricante'; Categoria = 'Mantenimiento'; Peligroso = $true; SinDestino = $true; Timeout = 5400; Simulable = $true
        Descripcion = 'HP y Lenovo: compara vídeo, red, chipset/USB y BIOS con el catálogo oficial e instala lo anticuado. ASUS, MSI, Gigabyte y Dell: usa la herramienta oficial de la marca.'
        Ayuda = 'HP y Lenovo: primero compara y enseña la lista; no instala nada sin confirmarlo. Crea un punto de restauración, comprueba la firma digital de cada descarga e instala en orden: chipset, vídeo, red y BIOS. La BIOS solo en HP, solo si se marca y con el cargador puesto. La casilla «Solo consultar» no cambia nada. ASUS, MSI, Gigabyte y Dell no publican un catálogo por modelo que se pueda leer: el kit instala o abre su herramienta oficial (ASUS DriverHub o MyASUS, MSI Center, la página de soporte de Gigabyte, Dell Command | Update) y siempre pregunta antes. DriverHub y MSI Center dejan software residente en el equipo del cliente.' }
    'Puesta_a_Punto_Rapida.ps1' = @{ Titulo = 'Puesta a punto'; Categoria = 'Mantenimiento'; Peligroso = $false; SinDestino = $true; Timeout = 900; Simulable = $true
        Descripcion = 'Un clic para un equipo lento: enseña RAM, temporales, inicio y disco, y borra temporales de más de un día y libera RAM de procesos inactivos.'
        Ayuda = 'Es el «Boost» sencillo. Enseña el estado y pide una sola confirmación con dos casillas: borrar los temporales con más de un día (usuario y Windows; no se recuperan, son desechables) y liberar la RAM de los procesos inactivos (alivio momentáneo: Windows recarga lo que se use). No cierra programas ni navegadores y no toca el registro, los servicios ni los datos del usuario. Al final muestra el antes y el después. Para más a fondo: «Limpiar temporales», «Optimizador personal» y «Programas de inicio».' }
    'Reinstalar_Grafica_Limpia.ps1' = @{ Titulo = 'Reinstalar gráfica'; Categoria = 'Mantenimiento'; Peligroso = $true; SinDestino = $true; Timeout = 7200
        Descripcion = 'Para pantallazos, parpadeos o un driver de vídeo corrupto: copia el actual, limpia con DDU y deja instalar el nuevo desde cero (NVIDIA, Radeon e Intel).'
        Ayuda = 'Panel en 5 pasos: 1) copia del driver actual y punto de restauración, 2) conseguir el driver nuevo (NVCleanstall o página oficial), 3) elegir un instalador ya guardado, 4) limpiar con DDU (reinicia, mejor en Modo seguro), 5) instalar el nuevo. DDU no se abre sin copia hecha y sin driver nuevo a mano o Internet. La limpieza de DDU no se deshace: para volver atrás usa la copia del paso 1 (pnputil /add-driver) o el punto de restauración. Tras el reinicio, vuelve a abrir esta herramienta y pulsa el paso 5. Con BitLocker, ten la clave de recuperación.' }
    'Monitores_y_Garantia.ps1' = @{ Titulo = 'Monitores y garantía'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true; Timeout = 600
        Descripcion = 'Marca, modelo, número de serie, año, tamaño y conexión de cada pantalla, y número de serie del equipo con acceso a la web de garantía.'
        Ayuda = 'Solo lee. Abre la página de garantía de HP, Lenovo o Dell con el número de serie copiado al portapapeles (se pega con Ctrl+V).' }
    'Reparar_Perfil_Usuario.ps1' = @{ Titulo = 'Reparar perfil de usuario'; Simulable = $true; Categoria = 'Mantenimiento'; Peligroso = $true; SinDestino = $true; Timeout = 900
        Descripcion = 'Para «has iniciado sesión con un perfil temporal» o un escritorio vacío: revisa cuentas, carpetas y errores de perfil y recupera el perfil original.'
        Ayuda = 'El diagnóstico no cambia nada. La reparación corrige solo la lista de perfiles del registro (con copia previa y pregunta por cada cuenta): nunca borra ni mueve archivos. No repara la cuenta que tiene la sesión abierta: entra con otra cuenta de administrador.' }
    'Perfil_Baja_Latencia.ps1' = @{ Titulo = 'Perfil de baja latencia'; Categoria = 'Memoria y rendimiento'; Peligroso = $false; SinDestino = $true; Timeout = 300; Simulable = $true
        Descripcion = 'Windows 11 va con tirones al abrir Inicio, la búsqueda o el clic derecho: activa el perfil de baja latencia de Microsoft (24H2/25H2 con la actualización de junio de 2026).'
        Ayuda = 'Descarga ViVeTool v0.3.4 de su GitHub oficial (se comprueba su huella SHA256), activa 4 funciones ocultas de Windows y hay que reiniciar. Pregunta si activar o desactivar. No instala nada permanente: ViVeTool solo escribe interruptores en el registro y «Desactivar» los quita; además crea un punto de restauración. Si la compilación es anterior a 26100.8655 (24H2) o 26200.8655 (25H2) avisa y no hace nada. Es una función no oficial: en algunos portátiles el ventilador sube un poco.' }
    'Programas_Inicio.ps1' = @{ Titulo = 'Programas de inicio'; Categoria = 'Memoria y rendimiento'; Peligroso = $false; SinDestino = $true; Timeout = 1800; Simulable = $true
        Descripcion = 'Lista lo que se carga al encender el equipo y deja elegir qué desactivar, como en el Administrador de tareas.'
        Ayuda = 'No desinstala nada. Lo desactivado se recupera con «Deshacer cambios». Las entradas de «este usuario» son las de la cuenta con la que se abrió el kit.' }
    'Deshacer_Dano_Optimizadores.ps1' = @{ Titulo = 'Deshacer el daño de otros optimizadores'; Simulable = $true; Categoria = 'Mantenimiento'; Peligroso = $false; SinDestino = $true; Timeout = 900
        Descripcion = 'Devuelve a su valor normal lo que dejan los «optimizadores» y scripts de debloat: servicios de Windows deshabilitados, bloqueos de actualizaciones, Tienda o Defender, y Microsoft bloqueado en hosts.'
        Ayuda = 'Primero solo enseña lo que encuentra; tú marcas qué se corrige. Cada cambio se registra y se deshace con «Deshacer cambios», y el archivo hosts se copia antes de tocarlo. Si tu empresa gestiona esas políticas, no las quites.' }
    'Por_Que_Se_Reinicio.ps1' = @{ Titulo = 'Por qué se reinició el equipo'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true; Timeout = 600
        Descripcion = 'Para cada reinicio o apagado de los últimos 30 días dice qué lo provocó: una actualización, una persona, un programa, una pantalla azul o un corte de corriente.'
        Ayuda = 'No cambia nada. Se apoya en los registros de Windows; si el registro se ha vaciado o es muy reciente, habrá menos eventos que mostrar.' }
    'Sello_Equipo.ps1' = @{ Titulo = 'Sello de recepción y entrega'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true; Timeout = 600
        Descripcion = 'Anota el estado del equipo al recibirlo (series, cuentas, administradores, certificados, programas) y al entregarlo dice qué ha cambiado.'
        Ayuda = 'No cambia nada. Primera vez: crea la recepción. Cuando termines, vuelve a abrirlo y elige entrega: compara con la recepción y señala cuentas, administradores o certificados nuevos. Los sellos se guardan en la carpeta de trabajo del kit (en el pack público, en la carpeta temporal del PC).' }
    'Auditoria_Acceso_Remoto.ps1' = @{ Titulo = 'Auditoría de acceso remoto'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true; Timeout = 600
        Descripcion = 'Revisa si alguien puede entrar o controlar el equipo a distancia: programas de control remoto, Escritorio remoto, cuentas de administrador u ocultas, puertas traseras en la pantalla de bloqueo, proxy forzado y tareas sospechosas.'
        Ayuda = 'Solo lee, no cambia nada. Útil tras una llamada de falso soporte técnico, con un equipo prestado o de segunda mano. «Revisar» no significa infectado: puede ser algo tuyo. Con administrador lee más (procesos de otros usuarios y tareas del sistema).' }
    'Historial_USB.ps1' = @{ Titulo = 'Historial de USB conectados'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true; Timeout = 300
        Descripcion = 'Lista las unidades USB, móviles y cámaras que se han conectado a este equipo: primera conexión, última conexión, última retirada y número de serie.'
        Ayuda = 'Solo lee, no cambia nada. Windows guarda solo la primera conexión, la última y la última retirada de cada dispositivo: no sabe cuántas veces se conectó ni qué se copió. Útil para reconocer un pendrive que no es tuyo.' }
    'Test_Velocidad_Internet.ps1' = @{ Titulo = 'Test de velocidad de Internet'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true; Timeout = 300
        Descripcion = 'Mide latencia, bajada y subida contra el servidor público de pruebas de Cloudflare (unos 40 MB de datos de relleno).'
        Ayuda = 'Solo se conecta cuando lo ejecutas, a speed.cloudflare.com; no envía datos de tu equipo, únicamente datos de relleno para medir. Mide el camino hasta Cloudflare: hacia otros sitios puede variar. Repite la medición en otro momento antes de concluir nada.' }
    'Instalar_Drivers_Faltantes.ps1' = @{ Titulo = 'Instalar los drivers que faltan'; Categoria = 'Mantenimiento'; Peligroso = $true; SinDestino = $true; Timeout = 5400; Simulable = $true
        Descripcion = 'Busca en el Catálogo de Microsoft el driver de todos los dispositivos que salen sin driver, te deja marcar cuáles y los descarga, verifica e instala.'
        Ayuda = 'Necesita Internet y administrador. Crea un punto de restauración antes, solo instala drivers con firma válida de Microsoft y no toca los dispositivos que ya funcionan. Si el Catálogo no tiene un driver (p. ej. controladores propios de Lenovo o ASUS), te lo dice: para esos usa «Drivers del fabricante».' }
    'Prueba_Hardware.ps1' = @{ Titulo = 'Prueba de hardware'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true; Timeout = 3600
        Descripcion = 'Prueba manual de pantalla (píxeles muertos), altavoces, micrófono, cámara, teclado y salud de la batería.'
        Ayuda = 'Pensada para portátiles y equipos de segunda mano. Marca cada prueba como «Bien» o «Falla»; el resultado queda en el registro. No cambia nada.' }
    'Restaurar_Datos_Usuario.ps1' = @{ Titulo = 'Restaurar datos del usuario'; Categoria = 'Mantenimiento'; Timeout = 14400; Peligroso = $false; SinDestino = $true; Simulable = $true
        Descripcion = 'Vuelca en este equipo una copia hecha con «Copia de datos del usuario»: documentos, fotos, escritorio y marcadores.'
        Ayuda = 'Nunca sobrescribe: lo que ya existe en el equipo se deja como está. Las contraseñas del navegador no se pueden pasar con esta copia.' }
    'Preparar_Venta.ps1' = @{ Titulo = 'Preparar para venta'; Categoria = 'Mantenimiento'; Peligroso = $true; SinDestino = $true; Timeout = 1800; Simulable = $true
        Descripcion = 'Repasa datos, cuentas, cifrado y licencia antes de vender o devolver el equipo y abre el restablecimiento de fábrica de Windows.'
        Ayuda = 'El borrado lo hace el asistente de Windows y solo empieza cuando lo confirmas en sus pantallas. Borra TODOS los datos y programas: haz antes la copia.' }
    'Informe_Entrega.ps1' = @{ Titulo = 'Informe de entrega'; Categoria = 'Diagnóstico'; Peligroso = $false; SinDestino = $true; Timeout = 900
        Descripcion = 'Parte de una página para el cliente: trabajos hechos con el kit y estado del equipo al llegar y al entregar.'
        Ayuda = 'Usa el primer y el último diagnóstico guardados de este equipo: pasa el «Diagnóstico rápido» antes y después. Se imprime o se guarda como PDF desde el navegador.' }
}
