# Nitrit0 Kit: informe de auditoría y correcciones (para revisión independiente)

Fecha: 2026-11-14. Idioma del proyecto: español. Este documento resume qué se auditó, qué se encontró, qué se corrigió y **qué no se ha podido comprobar**, para que otra persona (o IA) lo vuelva a revisar sin fiarse de lo dicho aquí.

## 1. Qué es el kit

Kit portátil de soporte técnico para Windows (pendrive o carpeta): una app Electron (`Nitrit0.exe`, interfaz) y un lanzador WinForms antiguo (`Lanzador Nitrit0.exe` → `Scripts\Lanzador.ps1`) que ejecutan ~55 scripts de PowerShell 5.1 (`Scripts\Mantenimiento\`, con ficha en `Catalogo.psd1`) y abren ~90 herramientas portables de terceros (`Apps\`). Todo corre como administrador.

Objetivo de la revisión: poder dárselo a **particulares y amigos** con garantías de que (a) no lleva nada malicioso, (b) no filtra datos ni licencias, (c) un usuario sin conocimientos no se hace daño con él, y (d) ayuda de verdad.

## 2. Qué se ha entregado: dos packs

Carpeta: `E:\Nitrit0_Packs\` (fuera del repositorio; los crea `Scripts\Crear_Packs.ps1`).

| Pack | Para quién | Contenido distinto |
|---|---|---|
| `Nitrit0_Kit_Publico` (2,4 GB) | usuarios y amigos | Sin licencias ni Office. `Datos\` vacío (kit.id nuevo). `Ajustes.json`: modo `sencillo` y `OcultarPeligro: true` (esconde las herramientas marcadas como peligrosas). |
| `Nitrit0_Kit_Personal` (3,1 GB) | uso propio | Igual código, todo visible (modo técnico) + licencia de WinRAR + instalador de Office 2013. **No se comparte.** |

Cada pack trae `LEEME.txt`, `Herramientas_y_huellas.txt` (SHA-256 y estado de firma de cada `.exe` de `Apps\`, más la huella de `Nitrit0.exe` y del lanzador) y `Datos\Integridad.json`. Ese manifiesto lleva el SHA-256 de **92 ficheros de `Scripts\`**, de **390 binarios y código de `Apps\`** (.exe, .dll, .sys, .msi, .ps1, .bat, .cmd, .vbs, .js), del catálogo de la app (`App\datos\herramientas.json`) y de los dos ejecutables de la raíz (`Nitrit0.exe`, `Lanzador Nitrit0.exe`); el resto de recursos pesados, solo por tamaño (1728 entradas en el pack público).

Huella de `Nitrit0.exe` (sin firmar, compilado el 15-nov-2026 tras la quinta ronda): `1F855F7697E83DE1722578C8F927669B8AE1E662C1833B37D4DDDC3BA242D553`.

Para revisar sin mover 2,4 GB basta el paquete pequeño `E:\Nitrit0_Packs\Para_Revision\Nitrit0_Codigo_Para_Revision.zip` (scripts, código fuente de la app, este informe y las huellas; sin binarios ni datos).

## 3. Cómo se auditó

1. **Barrido de patrones** en todos los `.ps1/.psd1/.bat` (descargas, `Invoke-Expression`, Base64, `-EncodedCommand`, tareas programadas, claves `Run`, desactivación de Defender/UAC/firewall, subidas con POST, correo): sin subida de datos, sin ofuscación, sin persistencia añadida, sin desactivar seguridad. Todas las URLs a las que descargan son de los propios fabricantes (Microsoft, Google, Mozilla, Brave, 7-Zip, VideoLAN, AnyDesk, RARLab, Sysinternals, Kaspersky, Malwarebytes, GitHub para ViVeTool, HP y Lenovo para drivers…); la lista completa sale con `Select-String -Path Scripts\*.ps1,Scripts\Mantenimiento\*.ps1 -Pattern 'https?://'`.
2. **Revisión por script** de los 55 scripts de mantenimiento hecha por un modelo (opencode, DeepSeek) y **verificada a mano en los puntos relevantes** (no se leyeron los 55 por una segunda persona).
3. **Inventario de firmas Authenticode y SHA-256** de 835 ejecutables y bibliotecas: 601 con firma válida, 214 sin firma, 20 con error de lectura.
4. **App Electron** (`App\src`): `contextIsolation: true`, `sandbox: true`, CSP restrictiva, informes dentro de `iframe sandbox=""`, `setWindowOpenHandler` en deny, IPC por identificador del catálogo (no ejecuta órdenes arbitrarias del renderer).

## 4. Hallazgos y qué se hizo

### Bloqueantes (corregidos)
| Hallazgo | Corrección |
|---|---|
| Claves de producto de Office en texto claro (`.txt`, 2 copias), `rarreg.key` de WinRAR y 720 MB de Office 2013 dentro del kit | Sacados del kit. Viven solo en `_Extras_Personales\` y se copian únicamente al pack personal. El pack público se comprueba al construirse (el script falla si encuentra `rarreg*`, `office*.txt`, `Office2013`, `*.key` o datos en `Datos\`). |
| Un paquete antiguo (`App\bin-unico\Nitrit0App` + `.rar` de 1,7 GB) conservaba todo lo anterior | Borrado y regenerado el exe. |
| Historial, informes y logs de clientes (`Datos\`, 5,4 GB de respaldos) | Borrados. El pack se construye con `Datos\` vacío. |
| AnyDesk marcado por defecto y con `--start-with-win` | Ya no viene marcado y se instala sin arranque automático. |
| «Desinstalar todo» traía marcado «borrar también mis datos»; «Quitar bloatware» traía todo marcado | Ambos sin marcar por defecto. |
| Informe de BitLocker (claves de 48 dígitos) y salida de «Wi-Fi y claves» se guardaban en el pendrive | El informe se genera en `%TEMP%\Nitrit0_Cache\Informes` y se borra solo a la hora (`Initialize-Kit`); `Ejecutor.ps1` no copia al kit la salida de esos dos scripts. |
| `Copia_Datos_Usuario` copiaba `Login Data` (base de contraseñas del navegador) | Ya no se copia. |
| `LimpiarTemporalesEquipo`, `Reparar_Red`, `Actualizar_Version_Windows` actuaban sin preguntar | Nueva `Confirm-Accion` (Comun.ps1): Sí/No con «No» por defecto; se salta solo con `NIT_AUTO`/`NIT_SIN_PREGUNTAS` (revisión automática ya confirmada). |
| Acciones destructivas a un clic para un particular | `OcultarPeligro` en `Ajustes.json` oculta las herramientas marcadas `Peligro` tanto en la app (`App.tsx`) como en el lanzador antiguo (`Get-Visibles`). El pack público arranca así. |

### A corregir (hechas)
| Hallazgo | Corrección |
|---|---|
| `Salud_Pendrive` anunciaba SHA-256 pero comparaba solo el tamaño | `Regenerar_Integridad.ps1` guarda SHA-256 de `Scripts\` y de los ejecutables/código de `Apps\`; `Salud_Pendrive` verifica todo lo que lleve huella (`-Rapido` salta las de Apps). Ver sección 4 bis. |
| `Reparar_Drivers_OEM` ejecuta por `cmd.exe` órdenes del XML de Lenovo (sin firma) | Sustituido por análisis de la orden y ejecución directa (sección 4 bis, punto 4). |
| `Actualizar_Windows` instalaba PSWindowsUpdate sin versión | Fijada a 2.2.1.5 (la actual en PSGallery a 2026-11-14). |
| `Cambiar_IP` borraba la IP antes de crear la nueva | Si falla, restaura DHCP o la IP/puerta anteriores y relanza el error. |
| Diagnóstico daba OK a una CPU a 0 °C (sensor mentiroso) | Temperaturas < 15 °C se tratan como «sin sensor» (diagnóstico, sensores, prueba de carga). |
| El informe decía «1 dispositivo con error» sin nombrarlo; RAM al 84 % salía en verde | Ahora nombra hasta 3 dispositivos con su código; aviso de RAM desde 85 %. |
| La revisión automática podía quedarse 30 min esperando confirmación | Espera máxima 5 min; sin respuesta no cambia nada. |
| `Instalador_Basico` ofrecía Office siempre | La opción de Office 2013 solo aparece si existe `Apps\Instaladores\Office2013` (solo pack personal). WinRAR se instala en modo prueba salvo que el pack lleve `rarreg.key`. |
| LEEME decía una cosa y el exe se llama otra; carpeta `Pendiente - Instaladores` | Corregido; carpeta movida a `_Extras_Personales` (no va en ningún pack). |

## 4 bis. Segunda auditoría externa: 9 puntos aplicados (14-nov-2026)

| # | Hallazgo | Corrección |
|---|---|---|
| 1 | Informes de `Powercfg_Para_App.ps1` (nombre del equipo, serie de placa y batería) y otros informes entregables en `Datos\Informes` del pendrive | Powercfg guarda siempre en `%TEMP%\Nitrit0_Cache\Informes`. El resto de informes (`Inventario_Equipo`, `Informe_Entrega`, `Diagnostico_Completo`, `Arreglo_Automatico`, `Informe_Rapido`, `Analizador_BSOD`, `Monitor_Latencia`, informes del lanzador) pasan por `Get-CarpetaSalida` (`Comun.ps1`): con `OcultarPeligro: true` (pack público) van a `%TEMP%\Nitrit0_Cache\Informes`; en el pack personal siguen en `Datos\Informes`. Se decide por `OcultarPeligro` y no por `Modo` (sencillo/técnico), porque la persona cambia `Modo` desde la app. La app (`index.ts`) hace lo mismo al abrir «Informes» y admite ver informes de ambas carpetas. En el público, los informes se borran de `%TEMP%` a la hora (si hacen falta, hay que guardarlos antes). |
| 2 | `Apps\` solo se validaba por tamaño | SHA-256 también para los .exe/.dll/.sys/.msi/.ps1/.bat/.cmd/.vbs/.js de `Apps\` (390 ficheros) además de `Scripts\`; recursos pesados, por tamaño. Regla única `Test-HuellaRequerida` en `Comun.ps1`. Comprobación completa ≈ 6 s; `-Rapido` ≈ 3 s. |
| 3 | Un `.ps1` plantado en `Scripts\Mantenimiento\` se listaba y corría como administrador | Lista blanca: el lanzador solo lista scripts con ficha en `Catalogo.psd1`. Antes de ejecutar, `Ejecutar_Para_App.ps1`, `Ejecutor.ps1` y la app (`index.ts`: el script, `Ejecutar_Para_App.ps1`, `Comun.ps1`, `Resumen_Sistema.ps1` y `SMART_Detalle.ps1`) comprueban su SHA-256 contra `Datos\Integridad.json`; si no consta o no coincide, error crítico y no se ejecuta. Probado: consta, intruso, modificado y fuera del kit. |
| 4 | `cmd.exe /c` con filtro `& \| < > ^` sobre órdenes del XML de Lenovo | `Resolve-OrdenLenovo`: se separan ejecutable y argumentos; el .exe debe quedar dentro de la carpeta del paquete (sin `..`, UNC ni `%VAR%`), ser `.exe` y tener firma Authenticode `Valid`; se lanza directamente con `Invoke-Proceso`. Los .bat/.cmd/.msi y los encadenados `&&` ya no se ejecutan (se remite a Lenovo Vantage). Probado con 8 casos. |
| 5 | `Asistente_Guiado_Inteligente` escribía un .ps1 en `%TEMP%` y lo lanzaba elevado (TOCTOU) | Ya no se escribe ningún .ps1: cada paso se lanza con `-Command` desde el kit, tras una única confirmación global y la comprobación de integridad del script. |
| 6 | Copia de datos: evitar cookies, `Web Data` y `Local State`; `Instalador_Basico` no comprobaba el firmante | De los navegadores solo se copia `Bookmarks` (se quita también `Preferences`); nunca `Login Data`, `Cookies`, `Web Data` ni `Local State`. `Instalador_Basico` exige, además de firma válida, el firmante esperado y que la dirección de descarga sea HTTPS del dominio oficial. **Verificado con descargas reales (14-nov-2026):** Chrome (Google LLC), Firefox (Mozilla Corporation), Brave («Brave Software, Inc.»), WinRAR (win.rar GmbH) y AnyDesk («AnyDesk Software GmbH») coinciden. **7-Zip no firma sus instaladores (NotSigned):** se fija el SHA-256 de la versión concreta (`7z2408-x64.exe`), que coincide con el del release oficial de su GitHub. **VLC daba 404** (la versión fijada ya no estaba en `last/`): el nombre se lee ahora del listado oficial. Solo se comprueba el dominio de la URL inicial, no el final tras redirecciones. |
| 7 | `NIT_AUTO`/`NIT_SIN_PREGUNTAS` heredables; diálogos tras la ventana de Electron; red sin copia previa | La app (`index.ts`) y `Ejecutor.ps1` las quitan del entorno al lanzar una herramienta suelta: solo las pasa la revisión automática. `Confirm-Accion` abre el cuadro con un dueño invisible `TopMost`. `Vaciar_Cuarentena` (rama `-VaciarCuarentena` de `Desinstalar_Total`) usa `Confirm-Accion` y ya estaba marcado `Peligroso`. `Reparar_Red` guarda `Get-NetIPConfiguration` en `%TEMP%\Nitrit0_Cache\Informes\Backup_Red_<equipo>.txt` antes de resetear (se borra a la hora; avisa de la ruta). |
| 8 | `Crear_Packs` validaba con lista negra | No se copia `Datos\` del repositorio: se crea con `kit.id` nuevo, `Ajustes.json` limpio (sencillo, `OcultarPeligro` true) e `Integridad.json` recién calculado. El build falla si en `Datos\` hay algo más (se permite `kit.id` además de lo pedido porque el kit lo necesita para reconocerse) o si en el pack hay `.key .lic .log .bak .tmp .rar .pst .kdbx`, `_Extras_Personales`, `.git` u `Office2013`. La primera ejecución detectó 4 restos de uso dentro de `Apps\` (2 `.cfg.bak` de DDU, 1 `.log` de TestDisk y 1 de WTools); ahora la copia excluye `*.log *.bak *.tmp`. `LEEME.txt` lleva un bloque de aviso legal (AS IS, copia previa, licencias de terceros) y ya no dice que los scripts «aparecen solos». |
| 9 | Verificación | `Validar_Kit -Analizador`: 0 errores y 0 avisos (se corrigieron 14 avisos de estilo previos: variables `$sender` y variables sin usar). `npm run tipos` limpio. Exe reconstruido. Integridad regenerada y packs reconstruidos; pack público: `Datos` = `Ajustes.json`, `Integridad.json`, `kit.id`; 0 licencias y 0 Office. |
| 10 | Punto de restauración antes de cambiar el sistema (sugerido en la revisión con Gemini) | `Start-OperacionSegura` ya creaba uno; ahora lo hacen también `Actualizar_Windows`, `Actualizar_Version_Windows`, `Actualizar_Software`, `Instalador_Basico`, `Reparar_Windows_y_Tienda`, `Restablecer_Windows_Update` y `Activar_Seguridad_Windows`. Para no crear uno por herramienta en el Asistente o la revisión automática, se reutiliza el de Nitrit0 de los últimos 30 minutos. Quedan sin él a propósito los que solo leen o copian archivos, `Reparar_Red` (un punto de restauración no revierte Winsock/TCP-IP; para eso guarda la configuración IP), `Reparar_Impresoras` e `Instalar_Impresora_Red`, y los que ya registran cada cambio para «Deshacer cambios» con `-SinPuntoRestauracion` (`Cambiar_IP`, `Puesta_a_Punto_Rapida`, `Reparar_TPM`). **No probado:** la creación y la detección del punto exigen administrador y esta sesión no lo era; si falla la consulta, cae al comportamiento anterior (crea uno). |
| 11 | Detectado por el usuario al probar el pack: `Nitrit0.exe` mostraba «No se pudo cargar el catálogo» (ENOENT `App\datos\herramientas.json`) en el público y en el personal | Error mío: `Crear_Packs` copiaba `Scripts\` y `Apps\` pero no el catálogo de la app. Ahora lo copia, y el build comprueba que cada script que el catálogo referencia existe en el pack y consta con huella. |
| 12 | El catálogo de la app (`herramientas.json`) decide qué órdenes se ejecutan y no estaba protegido | Entra en `Integridad.json` con SHA-256 y la app (`index.ts`, `leerCatalogo`) se niega a cargarlo si no coincide. |
| 13 | Tercera y cuarta revisión (Gemini y Grok): en el pack público, `index.ts` y `Comun.ps1` seguían guardando en `Datos\` del pendrive el nombre de usuario (`Historial_Diagnosticos.log`), el nombre del equipo (`Logs\Kit_*.log`), la salida de cada script (`Logs\Ejecuciones`), el historial de diagnósticos por equipo (`Historial\<equipo>`) y los respaldos de cambios (`Respaldo\Cambios`, con nombre del equipo y valores previos del registro) | Nueva `Get-BaseTrabajo` (PowerShell) y `baseTrabajo()` (app): con `OcultarPeligro` true todo eso va a `%TEMP%\Nitrit0_Cache` (`Logs`, `Historial`, `Cambios`); en el personal sigue en `Datos\`. `Write-Log`, `Sync-Log`, `Start-OperacionSegura`, `Save-Historial`, `Ejecutor.ps1`, el lanzador, `Salud_Pendrive`, `Informe_Entrega` y la app usan la misma regla. `Test-ModoPublico` se lee una vez por sesión y, si `Ajustes.json` falta o no se puede leer, asume público. **Probado:** con el pack público, `Write-Log` y `Start-OperacionSegura` escriben en `%TEMP%` y `Datos` queda con `Ajustes.json`, `Integridad.json` y `kit.id`. |
| 14 | La app copiaba al pendrive (pack personal) la salida de `Red_WiFi_y_Claves` y `Auditoria_Licencias_BitLocker` (contraseñas y claves de BitLocker en claro); solo el lanzador antiguo lo evitaba | Misma exclusión en `index.ts`; además esas dos herramientas pasan a `Peligroso` (ocultas en el pack público). `herramientas.json` regenerado (también incorpora `DNS_Mas_Rapido`, que faltaba). |
| 15 | `lanzarApp` (.exe portables de `Apps\`) y los `.html` se abrían sin comprobar su huella; `motivoBloqueo` usaba `ruta.slice(raiz.length + 1)` (fallaba con el kit en la raíz de una unidad) | Ambos comprueban `Integridad.json` antes de abrirse (probado en Node contra el pack real: scripts, catálogo, html y los 88 `.exe` de `Apps\` pasan; lo desconocido se bloquea) y `motivoBloqueo` usa `path.relative`. Un `.exe` intruso con número de versión mayor que el real ya no se ejecuta. |
| 16 | Los ganchos de pruebas `NIT_AUTO_PRUEBA*` y `NIT_AUTO_FORZAR` de la revisión automática podían activarse desde el entorno | La app los quita del entorno al lanzar scripts (el gancho sigue en `Arreglo_Automatico_Para_App.ps1`, solo para banco de pruebas, y no ejecuta nada que no conste en `Integridad.json`). |
| 17 | El LEEME del pack público decía «no envía nada a Internet», explicaba cómo saltar SmartScreen y cómo desactivar `OcultarPeligro` | Reescrito: dice qué usa Internet (descarga de programas oficiales, Windows Update, HP/Lenovo), que no envía datos del equipo, que los informes y registros no quedan en el pendrive, y ya no enseña a saltar SmartScreen ni a mostrar las herramientas ocultas (sigue siendo posible editando `Datos\Ajustes.json` o con el botón de modo técnico). |
| 18 | `Reparar_Red` no avisaba si había una sesión remota abierta | El cuadro de confirmación avisa si hay escritorio remoto, AnyDesk, TeamViewer, RustDesk o ScreenConnect. |
| 19 | La lista negra de `Crear_Packs` no miraba el contenido | Además de nombres, el build busca por contenido (en ficheros de texto de `Apps\`) claves de WinRAR, claves de producto de 25 caracteres y claves de recuperación de BitLocker; probado con una clave plantada. `Nitrit0.exe` y el lanzador de la raíz entran en `Integridad.json`. |

## 4 ter. Cuarta ronda: interfaz nueva y ajustes de Windows con estado (14-nov-2026)

Esta ronda **no corrige hallazgos de las auditorías anteriores**: añade funciones nuevas y, con ellas, superficie nueva que conviene revisar. Todo es del **modo técnico** de la app; el modo sencillo no cambia. Diseño y justificación: `App\DESIGN.md` (secciones «Portada del modo técnico…» y «Ajustes de Windows con estado»), `docs\Revision_Winhance_WinUtil.md` (de dónde salen las ideas y qué no se copia: Winhance usa licencia PolyForm Shield, no se ha copiado ni código ni catálogo) y la maqueta `docs\propuesta-visual\index.html`.

### Qué se ha añadido

| Pieza | Qué hace |
|---|---|
| `App\src\renderer\src\paginas\Tareas.tsx` («Inicio», Ctrl+1) | Portada con tarjetas. Las tres grandes abren una opción ya existente de «Arreglar mi equipo» (que pide su «Empezar»); las pequeñas llevan a herramientas y pantallas que ya existen, solo si están disponibles. Sin IPC nuevo. |
| `componentes\PanelEquipo.tsx` + `equipo.ts` | Panel «Este equipo» en el lateral: lee `vivo()` cada 3 s y `resumen()` al abrir (IPC que ya existían, con comprobación de integridad). Sin IPC nuevo. |
| `Scripts\Ajustes_Para_App.ps1` | **Nuevo, toca el registro.** Lee y cambia 5 ajustes de usuario (HKCU): Vista de tareas, alineación y búsqueda de la barra de tareas; extensiones y archivos ocultos del Explorador. Tabla `$Ajustes` = lista blanca (clave, valor, opciones válidas, versión mínima de Windows). |
| `main\index.ts`: `ajustesPs` y el manejador `ajustes` | **Nuevo IPC.** Acepta `{accion:'leer'}` o `{accion:'aplicar', id, opcion}`. Valida `id` con `^[a-z_]{1,30}$` y `opcion` con `^[a-z]{1,30}$`; comprueba la huella de `Ajustes_Para_App.ps1` y `Comun.ps1` contra `Integridad.json` antes de lanzar; entorno sin `NIT_AUTO`/`NIT_SIN_PREGUNTAS`; ejecuta los cambios de uno en uno (cola). |
| `paginas\Ajustes.tsx` + `componentes\Desplegable.tsx` | Pestaña «Ajustes» de Herramientas: estado actual, etiqueta («Como recomendamos», «Valor de Windows», «Valor distinto», «Elegido por ti»), interruptor o desplegable, detalles técnicos. Solo manda id y clave de opción. |
| Tema de tres valores (`main\index.ts`, `App.tsx`, `Desplegable.tsx`) | Desplegable de tema en el lateral: «Oscuro», «Claro» e «Igual que Windows». `Ajustes.json` guarda el modo elegido en `TemaModo` y, en `Tema`, el tema efectivo en ese momento (lo leen las herramientas antiguas de PowerShell, que solo conocen oscuro y claro). El manejador `tema` valida el valor (cualquier cosa que no sea `claro` o `sistema` se trata como `oscuro`); con «Igual que Windows», `nativeTheme.on('updated')` actualiza los botones de la ventana y `Tema`. Sin IPC nuevo. |
| Gancho `NITRIT0_CLIC` (`main\index.ts`) | Solo con `dev` (app sin empaquetar): pulsa elementos antes de una captura para pruebas. |

### Cómo se limita lo nuevo (lo que se afirma; a verificar contra el código)

1. **La interfaz no decide qué se escribe.** Nunca manda una ruta, un nombre de valor ni un valor numérico: solo el id del ajuste y la clave de la opción. El script busca ambos con comparación exacta (`-ceq`) en su tabla y rechaza lo demás («Ese ajuste no existe», «Esa opción no es válida»).
2. **Doble comprobación de integridad:** la app (`motivoBloqueo`) y el propio script (`Test-ScriptAutorizado $PSCommandPath`) verifican la huella antes de actuar.
3. **Solo HKCU, sin elevación propia, sin comandos externos:** el script usa `Set-ValorSeguro` (`Comun.ps1`), que guarda el valor anterior para «Deshacer cambios»; no ejecuta nada del sistema salvo lecturas y escrituras de registro.
4. **Versión de Windows:** cada ajuste lleva `MinBuild`; el script se niega a aplicar uno que no existe en la compilación actual.
5. **Pack público:** `Start-OperacionSegura` guarda el registro de cambios en `%TEMP%\Nitrit0_Cache\Cambios` y los registros van a `%TEMP%`; el pack público no gana nada en `Datos\`.

### Comprobado (con qué)

- `Ajustes_Para_App.ps1 -Accion Leer` devuelve el estado real de este equipo (5 ajustes, compilación 26300).
- Casos malos rechazados: opción inventada, id inexistente, id con inyección (`extensiones; calc`).
- **Cambio real de extremo a extremo desde la app:** pulsar el interruptor de «Mostrar las extensiones de archivo» cambió `HideFileExt` de 0 a 1 y el resumen pasó a «0 de 1»; al volver a pulsar quedó en 0; el registro de cambios guardó los dos valores previos. El equipo del desarrollo ha quedado como estaba.
- Leer desde una copia del pack público no escribe nada en su `Datos`.
- **Tema, en la app real:** el desplegable se abre hacia arriba con sus tres opciones; «Claro» aplica el tema claro entero (también la barra de título) y guarda `Tema: claro, TemaModo: claro`; «Igual que Windows» guarda `TemaModo: sistema` y `Tema` = el efectivo (oscuro, porque este Windows usa tema de apps oscuro). El `Ajustes.json` del desarrollador se restauró después de la prueba.
- `Validar_Kit -Analizador`: 0 errores y 0 avisos; `tsc --noEmit` limpio; capturas de la app real (portada, panel, ajustes, desplegable abierto).

### No comprobado o con límites conocidos (se piden ojos externos)

- **Sin administrador:** todo se probó con la app sin elevar. El caso de la app elevada con **otra cuenta** (HKCU del administrador) ahora se detecta y se bloquea (ver 4 quater), pero **solo se ha probado el caso «misma cuenta»**: no se ha probado con una cuenta distinta real.
- **Valores «de fábrica» (`Def`):** salen de memoria y de la documentación pública, no de una instalación limpia. Dudoso: el cuadro de búsqueda (el valor de fábrica varía por versión y fabricante; el script lo avisa en una nota) y `Hidden`.
- **Efecto sobre el Explorador:** `HideFileExt` y `Hidden` se ven al abrir una ventana nueva; no se difunde `WM_SETTINGCHANGE`. La interfaz lo dice en los detalles técnicos («Efecto»).
- **Sesiones de «Deshacer cambios»:** resuelto (ver 4 quater): una sola sesión por tanda de ajustes (30 min).
- **«Igual que Windows» con el sistema cambiando en vivo** no se ha probado (solo la lectura inicial): el evento `nativeTheme 'updated'` está escrito pero no se ha provocado un cambio de tema de Windows con la app abierta.
- **Herramientas antiguas de PowerShell** con `Tema: claro` (diálogos de «Desinstalar Total», «Instalador básico», etc.): no se han abierto con el tema claro elegido desde la app nueva.
- **Exe empaquetado** y **Windows 10** no se han probado.
- Los ajustes nuevos se añaden con una entrada en la tabla; no hay todavía un test que compruebe que toda entrada tiene su valor de fábrica y su versión mínima.

### Qué se pide a la revisión de esta ronda

1. **`Ajustes_Para_App.ps1` y el manejador `ajustes` de `index.ts`:** ¿hay forma de que algo que no sea una entrada de la tabla llegue a `Set-ValorSeguro`, o de que `id`/`opcion` lleguen sin validar a la línea de órdenes de PowerShell? Revisar el paso de argumentos con `execFile` y la comparación `-ceq`.
2. **El caso de HKCU con otra cuenta elevada:** ¿es realista en equipos de clientes y cómo se detectaría (comparar el SID del proceso con el del usuario de la sesión)?
3. **La cola de cambios y los tiempos:** ¿puede un renderer comprometido encolar cambios en bucle? (Está aislado con `contextIsolation` y `sandbox`, pero no hay límite de frecuencia.)
4. **Coherencia informe-código:** verificar cada afirmación de «Cómo se limita lo nuevo» contra el código, sin fiarse de este texto.
5. **`Tareas.tsx`:** confirmar que ninguna tarjeta llama a algo fuera del catálogo verificado (solo `lanzar`, `abrirOpcion` y cambios de vista).
6. **Tema:** ¿puede un valor inesperado de `TemaModo` en `Ajustes.json` (el fichero es editable por quien tenga el pendrive) romper algo en `modoTema()`, `temaEfectivo()` o en las herramientas de PowerShell que leen `Tema`? Revisar también el manejador `tema` y el evento `nativeTheme 'updated'`.


## 4 quater. Quinta ronda: hallazgos de la revisión de la cuarta (15-nov-2026)

La revisión de Gemini/Grok de la cuarta ronda (con los `.txt` de `Archivos_clave`) encontró fallos reales; cada uno se comprobó contra el código antes de corregirlo.

| # | Hallazgo | Corrección |
|---|---|---|
| 20 | **Alta.** `App.tsx` pasaba `elementos` (sin filtrar) a «Estado del equipo» (`Inicio.tsx`): con `OcultarPeligro` seguían a mano en favoritas y en los botones de «Revisión rápida» herramientas marcadas como peligrosas (por ejemplo «Licencias y BitLocker», que arranca entre las favoritas por defecto). Era un fallo anterior a esta ronda. | Ahora recibe `visibles`, como `Tareas` y `Pagina`. |
| 21 | `Crear_Packs.ps1` comprobaba que `herramientas.json`, `Ejecutar_Para_App.ps1` y `Comun.ps1` constaran con huella, pero no los scripts que `index.ts` lanza fuera del catálogo. | Se añaden `Ajustes_Para_App.ps1`, `Resumen_Sistema.ps1`, `SMART_Detalle.ps1` e `Informe_Rapido.ps1`: si faltan o no tienen huella, el build falla. |
| 22 | `ajustesPs` y `resumen` no quitaban del entorno `NIT_AUTO_PRUEBA*` ni `NIT_AUTO_FORZAR` (sí `ejecutarScript`). | Un solo `entornoLimpio()` en `index.ts`, usado por los tres. |
| 23 | `nativeTheme 'updated'` escribía `Ajustes.json` (el pendrive en el pack público) sin que la persona hiciera nada. | Ya no se escribe: solo se actualizan los botones de la ventana. Consecuencia: las herramientas antiguas de PowerShell leen el último tema elegido desde la app, no el cambio automático del sistema. |
| 24 | Cola de ajustes sin límite. | Máximo 5 cambios en espera; el sexto se rechaza con un mensaje. |
| 25 | Cada interruptor creaba su carpeta de «Deshacer cambios». | `Start-SesionAjustes`: se sigue la sesión `*_Ajustes_de_Windows` de los últimos 30 minutos (si no hay, se crea una). Probado: dos cambios seguidos = una carpeta con dos entradas. |
| 26 | App elevada con **otra cuenta**: HKCU sería el del administrador, no el de la persona del escritorio. | `Get-OtraCuenta` compara el usuario con la sesión interactiva (`Win32_ComputerSystem.UserName`) con la identidad del proceso; si difieren, `Leer` lo avisa, la pantalla muestra el aviso y desactiva los controles, y `Aplicar` se niega. No se comprueba en sesiones de escritorio remoto (el usuario de la consola puede ser otro). **Sin probar con una cuenta distinta real.** |
| 27 | Sección 7 y Anexo del informe obsoletos (preguntas de la primera ronda; el Anexo decía que `index.ts` solo verifica dos scripts). | Reescritos abajo. |
| 28 | **Media (backend).** `lanzarId` no comprobaba `peligro` con `esPublico()`: ocultar lo peligroso en el pack público era solo visual. | `lanzarId` rechaza cualquier herramienta peligrosa en el pack público (queda «BLOQUEADO» en el historial), venga el id de favoritas, de «Estado del equipo» o del IPC. |
| 29 | La corrección 20 tenía un efecto secundario que se vio al verificarla: «Estado del equipo» usa a propósito un elemento marcado como oculto (el botón «Asistente guiado»), y filtrar por `visibles` lo habría quitado para todos. | Esa pantalla recibe `permitidos` (solo se quita lo peligroso en el pack público). |
| 30 | Guía de prueba desactualizada: 1725 archivos en vez de 1728; el Asistente guiado no está en las listas de `Nitrit0.exe`; no había pruebas para la portada, el panel, los ajustes ni el tema. | Corregida y añadida la sección 9 bis de `docs\Prueba_Instalacion_Limpia.md`. |
| 31 | `Quitar_IA_Windows.ps1` citaba a Winhance (licencia PolyForm Shield) como fuente de las directivas de Edge. | El comentario remite a la documentación de Microsoft Edge (`Microsoft Edge Browser Policy Documentation`); son nombres de directivas documentados por Microsoft. |
| 32 | **Media.** `Asistente_Guiado_Inteligente.ps1` (no peligroso, abierto desde «Estado del equipo») lanzaba por su cuenta `Red_WiFi_y_Claves.ps1`, `Auditoria_Licencias_BitLocker.ps1` y `Desinstalar_Bloatware_Win11.ps1` en el pack público: era otro camino al margen de `OcultarPeligro`. | En el pack público el asistente lee `Catalogo.psd1`, quita los pasos marcados `Peligroso` y oculta los síntomas que se quedan sin pasos (si no puede leer el catálogo no ofrece ninguno). Las descripciones de los síntomas 3, 4 y 5 dejan de mencionar lo que ya no hace. Probado con el modo público forzado: los 7 síntomas quedan con pasos seguros. |
| 33 | El aviso final del asistente decía siempre que los informes están en `Datos` del kit; en el pack público van a `%TEMP%\Nitrit0_Cache`. | El texto depende del modo. |
| 34 | `Salud_Pendrive.ps1`: si se cancela la prueba de velocidad (`taskkill`), el `finally` no corre y `Datos\speedtest.tmp` (64 MB) quedaba en el pendrive. | `Initialize-Kit` borra `speedtest.tmp` si tiene más de 10 minutos (una prueba en curso en otro proceso es más reciente). |
| 35 | **Visual.** En la portada, el pie y la barra de título se salían por la derecha (el contenido ancho del pie ensanchaba la rejilla), y la columna derecha quedaba mucho más larga que la izquierda. | La rejilla usa `minmax(0, 1fr)` y «Tus favoritas» pasa a la columna izquierda, bajo «Unidades». |
| 36 | Las huellas de `Nitrit0.exe` del informe, de `Herramientas_y_huellas.txt` y del zip no coincidían (dos compilaciones el mismo día). | Cada vez que se recompila: `Crear_Packs.ps1`, y después se copian a `Para_Revision` el informe, `Herramientas_y_huellas.txt` y un zip nuevo. |
| — | **No cambiado, a propósito:** «Actualizar herramientas» y «Componentes» (página «Kit») salen deshabilitadas con «Solo en el lanzador clásico». | Es lo previsto en `App\DESIGN.md` («lo que aún no está en la app lo dice con un texto claro»): son ventanas de WinForms del lanzador clásico, no se han conectado a la app. |

## 5. Lo que NO se ha hecho o NO se ha podido comprobar (importante)

- **No se ha pasado antivirus ni VirusTotal** a ningún binario. Tampoco se han comparado las huellas de las herramientas de terceros con las publicadas por sus autores (el pack las lista para que se haga).
- **`Nitrit0.exe` y `Lanzador Nitrit0.exe` no están firmados** → SmartScreen/antivirus pueden avisar. El exe se ha compilado pero no se ha probado elevado en un equipo limpio (ver `docs\Prueba_Instalacion_Limpia.md`). Comprobado: `Validar_Kit.ps1 -Analizador` (0 errores, 0 avisos), `tsc --noEmit`, integridad por hash dentro de los packs y la lista blanca con casos reales.
- **No ejercitado en pantalla:** los diálogos Sí/No (incl. `TopMost`), el rollback de `Cambiar_IP`, la creación y reutilización de puntos de restauración (exigen administrador), la instalación real de los programas y la ruta de Lenovo de `Reparar_Drivers_OEM` (la lógica de `Resolve-OrdenLenovo` sí se probó con 8 casos).
- **Licencias de redistribución** de las herramientas incluidas (FurMark, OCCT, HWiNFO, WizTree, CrystalDisk*, etc.) **no verificadas**: alguna puede limitar el uso comercial o la redistribución. No publicar el pack en un enlace abierto.
- `Windows-ISO-Downloader.exe` da error al leer la firma (firmante «HeiDoc V.O.F.»; posible certificado caducado o cadena no confiable).
- Riesgos residuales conocidos, no tocados: `Get-Descarga` usa `curl` y la integridad de lo descargado se apoya en firma/huella del instalador, no en la cadena de redirecciones; `Desinstalar_Office.ps1` incluye ~145 líneas de C# con P/Invoke (toma posesión y borra claves; sin cuarentena); `Activar_Seguridad_Windows` no guarda los valores previos de las directivas de Defender (a propósito: solo refuerza).
- Los informes de diagnóstico siguen sin avisar de «apagados inseguros» del SMART y no hay checklist específico de portátil (batería, cargador, huella, Thunderbolt).
- **Pendiente de decidir (no tocado):** el modo técnico (botón de la app o `OcultarPeligro: false`) muestra herramientas que cambian el equipo y no están marcadas `Peligroso`: reparar red, limpiar temporales (cierra navegadores y vacía la papelera de todas las cuentas), el instalador de programas, cambiar IP y el asistente. En el modo combo, `Confirm-Accion` no vuelve a preguntar (la única confirmación es la pantalla que lanza el combo).
- **No tocado:** el resumen del diagnóstico puede decir «correcto» con muchos apagados inesperados del SMART (solo van al detalle) y el aviso de RAM empieza en el 85 %; `Desinstalar_Office.ps1` crea una tarea SYSTEM de una sola vez y la borra al final (si el script muere entre medias queda); `Reparar_Drivers_OEM.ps1` deja `ProgramData\Nitrit0\DriversOEM.json` en el PC; la firma interior de los paquetes de Lenovo vale con cualquier firmante `Valid` (el paquete descargado sí se comprueba contra HP/Lenovo).
- **Aclaración sobre Lenovo:** `Resolve-OrdenLenovo` se probó con 8 casos de rutas y órdenes (lógica), pero no contra un XML real de Lenovo ni en un equipo Lenovo; los paquetes `.bat`, `.cmd`, `.msi` o con `&&` ya no se instalan.
- **Licencias:** el aviso «tal cual» del LEEME no da derecho a redistribuir herramientas de terceros que sean freeware personal; no se han leído las licencias una a una. El pack personal sigue llevando Office 2013 y `rarreg.key` (que ya estuvieron en claro en versiones anteriores del kit).
- La lista blanca impide ejecutar lo que no consta en `Integridad.json` o ha cambiado, pero quien pueda escribir en el pendrive y regenerar ese manifiesto sigue pudiendo cambiarlo todo: no sustituye a una firma digital.

## 6. Cambios en el repositorio (desde el commit `d164dae`, todas las rondas)

Commits: `b5cd6c5` (endurecimiento y packs), `b66fdcc` (DNS_Mas_Rapido), `47bd015` y `e466008` (catálogo en los packs, informes por modo, registros fuera del pendrive), `a65cfeb` (portada y panel) y la cuarta ronda (ajustes con estado). Ficheros tocados o nuevos (la maqueta `docs/propuesta-visual/` no se lista):

- `.claude/launch.json`
- `App/datos/herramientas.json`
- `App/DESIGN.md`
- `App/src/main/index.ts`
- `App/src/preload/index.ts`
- `App/src/renderer/src/App.tsx`
- `App/src/renderer/src/componentes/Basicos.tsx`
- `App/src/renderer/src/componentes/Desplegable.tsx`
- `App/src/renderer/src/componentes/PanelEquipo.tsx`
- `App/src/renderer/src/diseno/componentes.css`
- `App/src/renderer/src/equipo.ts`
- `App/src/renderer/src/paginas/Ajustes.tsx`
- `App/src/renderer/src/paginas/Arreglar.tsx`
- `App/src/renderer/src/paginas/Inicio.tsx`
- `App/src/renderer/src/paginas/Tareas.tsx`
- `App/src/renderer/src/tipos.ts`
- `docs/Informe_Auditoria_y_Correcciones.md`
- `docs/Prueba_Instalacion_Limpia.md`
- `docs/Recoger_Resultados_Prueba.ps1`
- `docs/Revision_Winhance_WinUtil.md`
- `docs/Video_Winhance_Resumen.md`
- `Scripts/Actualizador.ps1`
- `Scripts/Ajustes_Para_App.ps1`
- `Scripts/Comun.ps1`
- `Scripts/Crear_Packs.ps1`
- `Scripts/Diagnostico_Para_App.ps1`
- `Scripts/Ejecutar_Para_App.ps1`
- `Scripts/Ejecutor.ps1`
- `Scripts/Exportar_Catalogo.ps1`
- `Scripts/Historial.ps1`
- `Scripts/Informe_Rapido.ps1`
- `Scripts/Lanzador.ps1`
- `Scripts/LEEME.txt`
- `Scripts/Mantenimiento/Activar_Seguridad_Windows.ps1`
- `Scripts/Mantenimiento/Actualizar_Software.ps1`
- `Scripts/Mantenimiento/Actualizar_Version_Windows.ps1`
- `Scripts/Mantenimiento/Actualizar_Windows.ps1`
- `Scripts/Mantenimiento/Analizador_BSOD_y_Eventos.ps1`
- `Scripts/Mantenimiento/Asistente_Guiado_Inteligente.ps1`
- `Scripts/Mantenimiento/Auditoria_Licencias_BitLocker.ps1`
- `Scripts/Mantenimiento/Cambiar_IP.ps1`
- `Scripts/Mantenimiento/Catalogo.psd1`
- `Scripts/Mantenimiento/Copia_Datos_Usuario.ps1`
- `Scripts/Mantenimiento/Desinstalar_Bloatware_Win11.ps1`
- `Scripts/Mantenimiento/Desinstalar_Total.ps1`
- `Scripts/Mantenimiento/DNS_Mas_Rapido.ps1`
- `Scripts/Mantenimiento/Informe_Entrega.ps1`
- `Scripts/Mantenimiento/Instalador_Basico.ps1`
- `Scripts/Mantenimiento/LimpiarTemporalesEquipo.ps1`
- `Scripts/Mantenimiento/Monitor_Latencia_y_Red.ps1`
- `Scripts/Mantenimiento/Punto_Restauracion.ps1`
- `Scripts/Mantenimiento/Reparar_Drivers_OEM.ps1`
- `Scripts/Mantenimiento/Reparar_Red.ps1`
- `Scripts/Mantenimiento/Reparar_Windows_y_Tienda.ps1`
- `Scripts/Mantenimiento/Restablecer_Windows_Update.ps1`
- `Scripts/Mantenimiento/Salud_Pendrive.ps1`
- `Scripts/Motor_Diagnostico.ps1`
- `Scripts/Powercfg_Para_App.ps1`
- `Scripts/Regenerar_Integridad.ps1`
- `Scripts/Ventana_Diagnostico.ps1`

## 7. Qué se pide a la revisión (vigente)

1. Verificar cada fila de las secciones 4 bis y 4 quater contra el código (no contra este texto): «Confirmado», «No coincide» (archivo y línea) o «No pude comprobarlo».
2. Responder las seis preguntas del final de la sección 4 ter (`Ajustes_Para_App.ps1` y el manejador `ajustes`, HKCU con otra cuenta, cola de cambios, `Tareas.tsx`, tema). Las tres primeras tienen ya una corrección en 4 quater: ¿es suficiente?
3. ¿Se puede saltar `OcultarPeligro` o `Confirm-Accion` desde la app (IPC, `NIT_AUTO*`, `Ajustes.json` editable)? Comprobar en concreto que **toda** pantalla que muestra herramientas usa la lista filtrada (el fallo 20 estaba en una).
4. ¿Qué falta para que un particular sin conocimientos lo use sin hacerse daño (textos, copias previas, avisos)?
5. Riesgos legales: licencias de las herramientas de `Apps\` y aviso de responsabilidad del `LEEME.txt` del pack público.
6. `Scripts\Crear_Packs.ps1`: ¿la comprobación del pack público garantiza que no viajan licencias ni datos?
7. Contradicciones entre secciones de este informe, o entre el informe y el código.

## Anexo: límites conocidos (actualizado en la quinta ronda)

- La app (`index.ts`, `motivoBloqueo`) verifica contra `Integridad.json`: el script y `Ejecutar_Para_App.ps1` y `Comun.ps1` antes de ejecutar una herramienta, `herramientas.json` al cargar el catálogo, `Resumen_Sistema.ps1`, `SMART_Detalle.ps1`, `Ajustes_Para_App.ps1`, los `.html` de `Scripts\Pruebas` y cada `.exe` de `Apps\` antes de abrirlo. Lo que un script carga con `.` desde otro script no se comprueba por separado. Quien pueda escribir en el pendrive y regenerar `Integridad.json` sigue pudiendo cambiarlo todo: no sustituye a una firma digital (`Nitrit0.exe` y el lanzador siguen sin firmar).
- El `.exe` y el lanzador se reconstruyeron pero no se han ejecutado elevados en un equipo limpio; el diálogo `TopMost` y el aviso de bloqueo no se han visto en pantalla.
- Sin pasar antivirus ni VirusTotal.
