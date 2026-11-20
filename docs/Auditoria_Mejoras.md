# Auditoría de mejoras: app Nitrit0 (fase 1)

Fecha: 2026-11-13. Estado auditado: `App\` tras la fase 1 (catálogo final, lanzado de apps y scripts, salida en vivo, favoritos, filtros, búsqueda).

## Qué se comprobó de verdad
- Compila y pasa `tsc` sin errores. El detector de diseño de Impeccable queda en 0 avisos (había uno: animación de `width`, ya corregido).
- Los 26 programas de `Apps\` se resuelven y se les extrae el icono real.
- Un script real (`Inventario_Equipo.ps1`) se ejecutó desde la app: salida en vivo, código de salida, registro en `Datos\Logs\Ejecuciones` y línea en `Historial_Diagnosticos.log`.
- Recorrido con clics reales (Playwright sobre la app): filtro por grupo, marcar y quitar favorita, pestaña Favoritas, búsqueda global con Ctrl+F, estado vacío, diálogo de confirmación (foco en «Cancelar», se cierra con Escape) y las 4 páginas (61, 13, 28 y 5 herramientas).
- Una revisión de código con opencode (modelo gratuito) sobre el proceso principal: de 12 puntos, 8 eran reales y se corrigieron (ver abajo).

## Corregido en esta pasada
- Los informes HTML (inventario, entrega, BSOD, licencias y BitLocker, latencia) ya no abren el navegador: se ven en la misma ventana, pestaña «Informe», con «Abrir en el navegador» si se quiere. El aviso va por una línea marcada que genera `Open-Informe` (Comun.ps1) solo cuando corre la app; el lanzador clásico sigue abriendo el navegador como siempre.
- Un fallo al arrancar PowerShell dejaba la app en «Ya hay algo en marcha» para siempre.
- Procesos lanzados sin escuchar el error: un `powershell` o `taskkill` que no arrancara podía tumbar la app.
- `JSON.parse` fuera de un `try`: cualquier texto de más en la salida de `Resumen_Sistema.ps1` cerraba la app.
- `abrirRegistro` aceptaba cualquier `.log`; ahora solo los de las carpetas de registros del kit.
- Sin bloqueo de navegación: una página externa habría heredado `window.kit`.
- El reintento con permisos de administrador salía también cuando el .exe no existía.
- «Abierto» se decía aunque Windows no pudiera abrir la carpeta o el HTML.
- Los ajustes y favoritos se escribían sin atomicidad: soltar el pendrive a medias podía dejarlos truncados.
- Una sola ventana de la app a la vez.

## Fase 2 (añadida después)
Hecho y probado con la app real:
- **Diagnóstico rápido** con el mismo motor y el mismo historial que el lanzador (`Diagnostico_Para_App.ps1`): 17 pruebas en vivo, progreso, detalle por prueba, «Siguiente paso» con las herramientas del kit, comparación con el diagnóstico anterior y copia del resumen. Se probó entero (14 correctas, 2 avisos, 1 información).
- **Cuello de botella** (`Equilibrio_Para_App.ps1`): perfiles General, Juegos, Creación y Oficina; veredicto, puntuación por pieza y hallazgos.
- **Informe rápido**: ahora vive en `Informe_Rapido.ps1`, compartido por el lanzador y la app (sin duplicar código).
- **Informe de entrega**: la app pide cliente y recomendaciones con su propio formulario. Antes el script abría cuadros de Windows y se quedaba esperando (se vio en la prueba).
- **Ficha del cliente y Modo taller** (ficha y diagnóstico rápido de un clic).

Sin probar con clics: el formulario del informe de entrega, el flujo completo de Modo taller y el diagnóstico profundo (carga el equipo y tarda unos 16 min).

Aún solo en el lanzador clásico: **Actualizar herramientas** y **Componentes** (instalan y descargan; piden más cuidado), y el **monitor en vivo** del cuello de botella.

Cosas vistas al probar:
- La gráfica sale con 4095 MB de VRAM (límite de 32 bits de WMI; la GTX 1080 tiene 8 GB). El script `Uso_VRAM` ya lo mide mejor; conviene reutilizarlo.
- Sin administrador, «Integridad de la imagen de Windows» no puede completarse y sale como información.
- Los textos del motor traen «prueba(s)» y «valor(es)»; se pueden pulir en `Historial.ps1` sin tocar nada más.

## Pendiente, por prioridad

### Alta (impide usarla como sustituta del lanzador)
1. **Empaquetado y permisos.** Hoy se arranca con `npx electron .` y no pide administrador. Hace falta un build portable con manifiesto `requireAdministrator`, una carpeta de unos 250 MB en el pendrive y que `Lanzador Nitrit0.exe` (o uno nuevo) la abra. Sin esto, las herramientas piden UAC una a una.
2. **Acciones que solo existen en el lanzador clásico:** Modo taller, Cuello de botella, Diagnóstico rápido y profundo, Actualizar herramientas, Componentes, Informe rápido. Son ventanas WinForms; en la app salen marcadas como «Solo en el lanzador clásico». Es la fase 2.
3. **Letra de unidad cambiante.** `raíz` se fija al arrancar. Si el pendrive vuelve con otra letra, el aviso de «ha vuelto» no salta y el historial y los registros dejan de escribirse sin avisar. El lanzador ya resuelve esto con `Find-KitReconectado`; hay que portarlo.
4. **Una app que no es administrador falla en silencio** en varias herramientas de Windows (`sfc`, `DISM`). Mostrar el aviso en la propia fila, no solo en la barra lateral.

### Media
5. **Inicio tarda 5 a 8 s** en pintar por `Get-CimInstance`. Guardar la última lectura y refrescar detrás, con aviso de «datos de hace N min».
6. **Más revisiones en Inicio** con datos que el kit ya sabe sacar: SMART real (smartctl), temperaturas (LibreHardwareMonitor/PawnIO), actualizaciones pendientes, antivirus, TPM y Secure Boot, BitLocker, drivers con fallo, eventos críticos recientes. Hoy la salud de disco es solo el `HealthStatus` de Windows, que casi siempre dice «Healthy».
7. **Guardar el informe como PDF** desde la propia app (hoy: «Abrir en el navegador» y Ctrl+P). Y salida en vivo más útil: botón de copiar, búsqueda dentro de la salida, abrir el informe que generó el script, y entrada por teclado para los scripts que preguntan algo (hoy el teclado está cerrado, igual que en el lanzador).
8. **Pantalla de Ajustes:** técnico, zoom y tamaño de texto (el lanzador tiene A- y A+), abrir carpetas del kit.
9. **Recientes y historial** dentro de la app, con lo que ya está en `Datos\Logs\Ejecuciones`.
10. **Un solo script a la vez.** Razonable por seguridad, pero hay herramientas largas (OCCT, Prime95) que no deberían bloquear un diagnóstico rápido.

### Baja
11. **Resolver la versión de cada app.** El lanzador elige por versión interna del .exe; la app, por orden natural de la ruta. Coinciden hoy; unificar.
12. **`runArgs` con espacios.** Se parten por espacios y pasan por `cmd /c start`. Solo vienen del catálogo propio, así que no es explotable, pero se rompería con una ruta con espacios. Guardarlos como lista.
13. **`cancelar` no espera al cierre real.** Marca «Cancelado» y lanza `taskkill`; si el cierre falla, el estado miente hasta que llegue el `close`.
14. **Catálogo generado a mano.** `Exportar_Catalogo.ps1` hay que lanzarlo tras tocar `Lanzador.ps1` o `Catalogo.psd1`. Debería ir dentro de `Validar_Kit.ps1` o regenerarse al arrancar.
15. **Sin pruebas automáticas** de la app. El gancho `NITRIT0_LANZAR` y `NITRIT0_CAPTURA` sirve de base para una prueba de humo; falta el resolver de rutas y el parseo del catálogo.

## Diseño (antislop e Impeccable)
Resuelto: sin tarjetas de métricas ni anillos, sin etiquetas pequeñas sobre títulos, sin insignias decorativas ni franjas laterales, un solo acento, IBM Plex empaquetada, iconos reales de cada programa, radios de 6 y 10 px, tema claro y oscuro con las mismas variables.

Para revisar con ojos de diseñador:
- **Tema claro:** solo comprobado en la pantalla de carga de Inicio. Falta recorrerlo entero (lista, diálogo, consola) y medir contraste real.
- **Ventana a 960 px y con zoom 130 %:** no se ha mirado.
- **Estados no vistos:** error al cargar el catálogo, aviso de unidad desconectada durante un script, cancelación desde la interfaz.
- **Lucide en la navegación** (declarado en DESIGN.md): si se quiere identidad propia, dibujar cuatro iconos a medida.
- **Foco al cambiar de vista:** el foco se queda en el botón del menú; un lector de pantalla no anuncia el título de la página nueva.
- **Texto «Pide confirmación antes de abrirse»** en ámbar sobre fondo oscuro: contraste correcto, pero repetido en 12 filas; valorar un único aviso por grupo.

## Siguiente paso recomendado
1. Empaquetado con administrador (punto 1) y letra de unidad (punto 3): sin ellos la app no puede sustituir al lanzador.
2. Fase 2: Modo taller, Diagnóstico e Informe rápido dentro de la app.
3. Revisión con Fable cuando esté la fase 2, con este documento como lista de partida.

## Revisión externa: Fable, opencode y Gemini (2026-11-13)
Tres revisores independientes sobre el mismo código; cada hallazgo se comprobó contra el código antes de aceptarlo.

**Corregido** (confirmado por uno o más revisores):
- Los trabajos hechos desde la app no salían en el «Informe de entrega»: la app solo escribía en `Historial_Diagnosticos.log` y el informe lee `Logs\Kit_*.log`. Ahora la app escribe con el formato de `Write-Log` (lo vieron los tres).
- Cerrar la ventana con un script en marcha lo mataba sin preguntar. Ahora pide confirmación, como el lanzador (los tres).
- Menú de Electron activo (Ctrl+R recargaba y dejaba un script huérfano; Ctrl+Mayús+I abría las herramientas de desarrollo). Sin menú en producción, con zoom propio (Ctrl y +, -, 0) y recuperación de la ejecución si la interfaz se remonta.
- Ganchos de prueba (`NITRIT0_*`, `ELECTRON_RENDERER_URL`) solo en desarrollo; `will-navigate` limitado a la interfaz propia; programas del sistema (PowerShell, cmd, taskkill) por ruta absoluta de System32.
- stdout y stderr compartían búfer (una línea `##DX##` partida se perdía); fin de ejecución también por `exit` si `close` no llega; un segundo `close` tras un fallo al arrancar repetía el aviso.
- Informe de batería y de energía sin pasar por `cmd`: script `Powercfg_Para_App.ps1`, y el informe se ve en la ventana.
- Resumen del equipo con WMI dañado (campos vacíos, volumen de tamaño 0, BIOS en lista): la pantalla de Inicio ya no se queda en blanco, y hay un aviso de error por pantalla en vez de una ventana vacía.
- El diagnóstico no se guarda en el historial si el motor no terminó; espera hasta 60 s al pendrive antes de guardar y avisa en una banda visible en cualquier pantalla.
- La app ya no crea `Datos\` en una unidad ausente, ni deja el registro de ejecución en `%TEMP%` del cliente cuando lo copia al pendrive.
- Carrera al lanzar el cuello de botella (borraba el análisis anterior si el proceso lo rechazaba); fallo silencioso del botón de Modo taller; foco que no pasaba al título al cambiar de pantalla; reloj de la ejecución que arrancaba en 00:00 al volver.
- Accesibilidad: el reloj ya no se anuncia cada segundo, pestañas sin ARIA contradictoria, progreso como `progressbar`, indicador de fila desplegable, chip deshabilitado visible.
- Contraste en tema claro (ámbar, verde y acento medidos: ahora todos por encima de 4,5:1) y color de error en oscuro; el ámbar deja de ser también el color de «favorita».
- Textos: «Abierto: X», decimales con coma, plurales (1 disco, 1 aviso), estados de disco en español, «No se pudo…», «Ctrl+F», «se desgasta más», plurales del motor de comparación, «Sin avisos en la revisión rápida» en lugar de «Todo en orden».
- Favoritas por defecto como el lanzador; tema guardado aplicado ya a los botones de la ventana; caché de Chromium fuera de `%APPDATA%` del cliente; botones de cancelar con «Seguir ejecutando».
- `Inventario_Equipo.ps1` ya no revienta si la fecha de la BIOS o de instalación viene vacía.

**Descartado tras comprobarlo:**
- Gemini: que las versiones de `package.json` no existen (están instaladas: Electron 45.3.1, Vite 8.3.8, TypeScript 7.0.2); que las filas `<details>` se cierran solas (React solo toca `open` cuando cambia su valor); el fallo de cultura numérica en `Historial.ps1` (las métricas son números, no texto); la fuga del vigía (el proceso termina con él).
- Gemini: que el relleno de los medidores no se distingue (mide 4:1, por encima del 3:1 exigido).

**Pendiente** (verificado, aún sin hacer):
1. Empaquetado portable con `requestedExecutionLevel=requireAdministrator` (la raíz ya se resuelve subiendo hasta `Datos\kit.id`).
2. Pendrive con otra letra al reconectar y copia local de `Save-Historial` (la app solo espera 60 s a la misma letra).
3. Informe HTML del diagnóstico (el clásico lo generaba; en la app queda el informe de entrega) y limpieza de temporales al detener (`nit_cuello_disco.bin` de 128 MB).
4. `smartctl` sin tiempo máximo por disco en `Motor_Diagnostico.ps1`.
5. Catálogo extraído de `Lanzador.ps1` por posición: moverlo a un `.psd1` antes de retirar el lanzador.
6. `Datos\Integridad.json` no cubre `App\` y nadie la comprueba al arrancar.
7. «Volver al kit» recuerda la pantalla pero no el filtro; «Modo taller» y «Cuello de botella» no se pueden marcar como favoritas.
8. Estilos con valores sueltos que quedan en `componentes.css` (tamaños de letra y espaciados sin tokens).

## Modo automático «Revisar y arreglar» (2026-11-13)
Petición: la app resultaba demasiado técnica; tenía que servir a alguien sin experiencia, analizar los fallos, aplicar las soluciones sin ir de una en una, dar un informe de lo detectado y lo cambiado, agilizar lo lento y comprobar que nada se queda colgado.

**Hecho**
- Pantalla nueva «Arreglar mi equipo», la primera y la que se abre por defecto: un botón, sin jerga. «Estado del equipo» (antes Inicio) y el resto quedan debajo para el técnico.
- `Scripts\Arreglo_Automatico_Para_App.ps1`: analiza con el motor de diagnóstico rápido, decide los arreglos según lo que salga mal, los aplica uno tras otro, vuelve a medir lo que tocó y escribe el informe (`Datos\Informes\Revision_<equipo>_<fecha>.html`, que se ve dentro de la app).
- Solo arregla lo seguro: punto de restauración, liberar espacio y memoria, reparar la red, activar la protección de Windows, reparar Windows Update y los archivos de Windows (DISM/SFC). Actualizar Windows solo si se marca la casilla. Discos que fallan, drivers, errores graves y temperaturas se dejan en «necesita atención» con un consejo y la herramienta que toca.
- Nada se queda colgado: cada paso tiene su tiempo máximo (el proceso y sus hijos se cierran), botón «Saltar este paso», aviso a los 2 minutos sin señales y «Detener todo». Cada prueba del diagnóstico corre ahora en su propio hilo con tiempo máximo (60 s o el triple de lo previsto), también en el lanzador clásico: una consulta WMI o un smartctl colgados ya no paran el resto.
- El diagnóstico rápido tarda unos 45 s en este equipo (no los 2 minutos que decía la pantalla).
- Cada comprobación posterior se hace solo sobre lo que se tocó (`NIT_DX_IDS`) y sin ensuciar el historial (`NIT_DX_SINGUARDAR`).
- Probado con la app real: análisis, paso que termina bien, paso saltado a mano, paso cerrado por tiempo máximo (sin procesos huérfanos), verificación posterior e informe en la ventana, en oscuro y claro.

**Sin probar con el equipo de un cliente roto** (aquí no hay nada que arreglar): reparar red, activar seguridad, reparar Windows Update y DISM/SFC son los scripts de siempre del kit, pero no se han ejecutado dentro de este flujo ni en esta sesión. Antes de fiarse de ellos conviene una prueba en un equipo con ese fallo y con permisos de administrador (la «Revisar y arreglar» sin administrador ni siquiera puede crear el punto de restauración). Las pruebas del flujo usaron pasos simulados (`NIT_AUTO_FORZAR`, `NIT_AUTO_PRUEBA`: solo para pruebas).

**Pendiente**
- Botón «Reiniciar ahora» al terminar cuando hace falta reiniciar.
- Ejecutar las pruebas del diagnóstico en paralelo (bajaría de ~45 s a ~25 s) sin falsear las que miden carga (CPU, sensores, red).
- DISM tarda lo que tarda: el aviso de «sin señales» y el tiempo máximo (90 min) son la red de seguridad, no una aceleración.


### Modo sencillo para personas sin experiencia (2026-11-13)
Petición: plantearlo para alguien que no es técnico, una persona mayor o un niño, con un interfaz que va abriendo opciones según lo que se elige (referencia: VoiceStudio).
- La app arranca en **modo sencillo**: sin menú, una portada con seis problemas en palabras normales (va lento, no tengo Internet, salen avisos o errores, me preocupa la seguridad, se queda sin espacio, no sé qué le pasa). Al elegir uno se despliega qué hará y el botón «Empezar».
- Cada opción **mira solo lo que toca** (`NIT_AUTO_ENFOQUE`): por ejemplo «No tengo Internet» solo comprueba la red, así que acaba en segundos en vez de revisar 17 cosas. «Va lento» y «Se queda sin espacio» hacen siempre la limpieza suave. Las revisiones parciales no se guardan en el historial de diagnósticos.
- Progreso con una frase y una barra, sin listas; el listado de pasos y el botón de saltar quedan en «Ver qué está pasando». Si un paso pasa de 2 minutos sin avances aparece un «Pasar al siguiente» bien visible.
- Resultado en lenguaje llano («Tu ordenador está bien», «Ya está arreglado», «He arreglado lo que podía», «Hay algo que no puedo arreglar yo solo»), con lo hecho y lo que necesita ayuda de una persona. El reinicio pendiente ya no cuenta como problema: sale un botón «Reiniciar ahora» (pide confirmación, deja 30 s y se puede cancelar).
- Los detalles técnicos y el informe completo siguen ahí, plegados.
- Análisis de virus: la opción «Creo que tiene un virus» lanza un análisis rápido con el antivirus de Windows (Microsoft Defender, `Scripts\Antivirus_Para_App.ps1`), con avisos de progreso, tiempo máximo de 30 min y el resultado en la pantalla (cuántas amenazas y cuáles). Defender trata lo que encuentra según su configuración; la app solo lo lanza y lo cuenta. Si el equipo usa otro antivirus no lo toca y lo dice; si no hay permisos de administrador o falla, la pantalla dice «No he podido buscar virus» en vez de dar el equipo por bueno. En «No sé qué le pasa» hay una casilla opcional para sumarlo. Probado de verdad con permisos de administrador: 2 min 15 s, 0 amenazas. No es un análisis completo del disco ni sustituye a un antivirus de terceros o a un técnico si el problema es grave. Los portátiles de terceros del kit (KVRT, AdwCleaner) siguen en el modo técnico.
- Probado con la app real en oscuro y claro (portada, opción desplegada, progreso, resultado con reinicio, paso al modo técnico y vuelta). **No** se probó el botón «Reiniciar ahora» hasta el final (reiniciaría el equipo de pruebas) ni a una persona real usándolo: conviene que lo pruebe alguien mayor de verdad.


### Pestañas, combos y más diagnóstico en el modo sencillo (2026-11-13)
- **Apps nuevas** (descargadas de sus webs oficiales, comprobadas): TestDisk y PhotoRec 7.2 (firma digital válida del autor), Process Explorer 17.21 (firmado por Microsoft) y USBDeview 3.10 (NirSoft, sin firma digital como es habitual). Están en `Apps\Recuperacion`, `Apps\Sistema\ProcessExplorer` y `Apps\Perifericos\USBDeview`; además se dio de alta Rufus, que ya estaba en el kit sin entrada. Las cuatro nuevas arrancan (probado sin elevar). No se descargó H2testw (la web oficial no ofrece enlace directo) ni ChipGenius.
- **Modo técnico con pestañas**, como VoiceStudio: cinco espacios en el menú y, dentro, pestañas (Diagnóstico | Cuello de botella; Comprobar | Preparar equipo | Reparar y mantener | Kit).
- **Combos:** pasos de mantenimiento que se pueden aplicar juntos o de uno en uno, en paquetes o a medida. Usan el mismo motor que «Revisar y arreglar» (modo `NIT_COMBO` del script): tiempo máximo por paso, saltar, informe y sin análisis previo. Hay tres pasos nuevos solo para combos (limpieza a fondo, actualizar programas y optimizar rendimiento) que nunca se aplican solos. La lista de pasos está duplicada en `Combos.tsx` y en el script; si se añade uno hay que añadirlo en ambos y en la lista blanca del proceso principal.
- **Modo sencillo:** recomendaciones según cómo esté el equipo y siete programas de diagnóstico a un clic.
- Probado con la app real: portada sencilla, pestañas de Herramientas y de Diagnóstico, página de Combos con un paquete, y un combo real de un paso (Liberar espacio y memoria) de principio a fin. **No** se probaron combos con pasos de reparación (red, Windows Update, DISM, optimizar) ni los programas nuevos dentro de la app (solo arrancándolos aparte).


### Revisión de diseño con las skills (2026-11-13)
- **Skills usadas:** impeccable (crítica: Nielsen, carga cognitiva, personas; con dos evaluadores independientes), el medidor de contraste de antislop-human y el detector. Otras skills del catálogo que encajan para próximas pasadas: `onboard` y `clarify` de impeccable (primer uso y textos), `break-ui` (datos extremos), `animate`/`improve-animations` (movimiento) y `emil-design-eng` (pulido). No se usaron skills de marketing (landing, CRO…) porque no aplican.
- **Puntuación de partida:** 26/40. Problemas principales: portada del modo sencillo con hasta 16 acciones, barra de progreso vacía, final alarmante por un reinicio, «Empezar» sin confirmar nada, textos de 12,5 px y objetivos pequeños, foco que no se movía entre fases, Combos duplicando Herramientas.
- **Aplicado:** decisión real sobre el plan antes de cambiar nada, confirmaciones solo donde hay riesgo, barra indeterminada o «Paso N de M», final tranquilo, «No sé qué le pasa» primero y lo demás plegado, menú de cuatro entradas con Combos como pestaña de Herramientas, «Qué lo frena», foco y tamaños, bordes de campos y desbordes. Probado con la app real: plan → «Hacerlo», plan → «Solo la información», menú y pestañas del modo técnico.
- **Sobre la «sensación de que lo hace el usuario»:** se resolvió con participación verdadera (elige el problema, aprueba o recorta el plan, puede saltar o parar, decide cuándo reiniciar). No se simulan acciones ni progreso: si el usuario cree que ha arreglado algo, es porque ha decidido de verdad qué se hacía.
- **Pendiente de la crítica:** «antes → después» con números reales (solo donde el script lo mida), guardar el informe en el Escritorio como acción propia, acceso fijo a la última ejecución y atajos entre espacios. Sin probar con una persona real; lo de foco y lectores de pantalla es por lectura de código.

