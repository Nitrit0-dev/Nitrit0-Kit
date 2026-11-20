# Prueba del pack público en una instalación limpia

Objetivo: comprobar en un Windows recién instalado lo que desde el equipo de desarrollo no se pudo ver (diálogos, elevación, rollback, firmantes, puntos de restauración). Duración: 1–1,5 h.

## 0. Preparación (una vez)

1. **Máquina:** una VM de Hyper-V (o VMware/VirtualBox) con **Windows 11 recién instalado**, 4 GB de RAM, 60 GB de disco y Internet. No uses Windows Sandbox: no conserva puntos de restauración y se borra al cerrar.
2. En la VM crea un usuario **administrador local** normal (no la cuenta integrada «Administrador»). Actualiza Windows si quieres, pero **no instales nada más**.
3. **Haz un punto de control (snapshot) de la VM** y llámalo «limpia». Vuelve a él entre pruebas largas.
4. Copia **`E:\Nitrit0_Packs\Nitrit0_Kit_Publico`** (2,4 GB) al disco de la VM, por ejemplo a `C:\Nitrit0_Kit_Publico`. Cópialo al disco local, no lo abras desde una carpeta compartida de solo lectura: el kit escribe en `Datos\`. Para probar también el caso del pendrive, repite luego con un disco USB virtual.
5. Antes de empezar, anota la huella del exe y compárala con `Herramientas_y_huellas.txt`:
   ```powershell
   Get-FileHash C:\Nitrit0_Kit_Publico\Nitrit0.exe -Algorithm SHA256
   ```
6. Copia a la VM, **fuera del kit** (por ejemplo a `C:\Resultados`), el script `Recoger_Resultados_Prueba.ps1` (está junto a esta guía). Solo lee: no cambia nada. Ejecútalo como administrador al terminar cada bloque, o al final:
   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Resultados\Recoger_Resultados_Prueba.ps1 -Kit C:\Nitrit0_Kit_Publico
   # tras la prueba 7.3, añade: -CopiaDatos "C:\ruta\de\la\copia"
   ```
   Genera `C:\Resultados\Resultado_Prueba.txt` con: huellas del exe, contenido de `Datos\`, integridad, intrusos, puntos de restauración, variables `NIT_*`, caché temporal, registro del kit, programas instalados, red y copia de datos. Cubre casi todo lo «esperado» de abajo; lo que **no** puede ver (diálogos, mensajes en pantalla) sigue siendo a ojo, con capturas. Si quieres comparar antes y después, guarda cada ejecución con otro nombre: `-Salida C:\Resultados\bloque3.txt`.

Los nombres de herramienta que uso abajo (Reparar red, Actualizar programas...) son aproximados: si no los ves igual, búscalos por el nombre del script (`Reparar_Red.ps1`, `Actualizar_Software.ps1`...). Si una herramienta peligrosa está oculta, para probarla pon `OcultarPeligro` a `false` en `Datos\Ajustes.json` solo en la VM.

Cómo anotar: para cada prueba pon **OK / FALLA / NO PROCEDE** y qué viste realmente. Si falla, copia el final de `Datos\Logs\Kit_*.log` y `Datos\Logs\Ejecuciones\`.

## 1. Arranque y permisos

| # | Qué hacer | Esperado |
|---|---|---|
| 1.1 | Doble clic en `Nitrit0.exe` | Aviso SmartScreen («editor desconocido»): Más información → Ejecutar de todas formas. Después sale el aviso de UAC pidiendo permisos de administrador. |
| 1.2 | Mira la ventana | Arranca en **modo sencillo** y se ve la interfaz sin errores. |
| 1.3 | Menú o lista de herramientas | **No aparecen** las herramientas peligrosas (`OcultarPeligro`): por ejemplo Vaciar cuarentena, SFC o DISM. |
| 1.4 | Cierra y abre `Lanzador Nitrit0.exe` | Abre el lanzador antiguo con permisos; sin errores y también sin las peligrosas. |
| 1.5 | Mira `Datos\` | Tras usar la app **sigue** habiendo solo `Ajustes.json`, `Integridad.json` y `kit.id`: en el pack público nada más se escribe en el pendrive. |

## 2. Lista blanca (integridad)

| # | Qué hacer | Esperado |
|---|---|---|
| 2.1 | Ejecuta una herramienta normal (p. ej. «Informe rápido» o «Diagnóstico rápido») | Funciona. |
| 2.2 | Cierra la app. Copia `Scripts\Mantenimiento\Reparar_Red.ps1` a `Intruso.ps1` en la misma carpeta y abre la app | `Intruso` **no aparece** en el lanzador. |
| 2.3 | Añade una línea `# prueba` al final de `Scripts\Mantenimiento\Reparar_Red.ps1` y lánzalo desde la app | **Error crítico** «su contenido ha cambiado…». No se ejecuta. Quita la línea después. |
| 2.4 | Haz una copia de un `.dll` pequeño de `Apps\`, añádele un byte (`[IO.File]::AppendAllText('<ruta>', 'x')`) y ejecuta «Salud pendrive»; después cambia el nombre de otro archivo de `Apps\` y repite | Marca **MODIFICADO** el primero y **FALTA** el segundo. Restáuralos después con los originales del pack. |
| 2.5 | «Salud pendrive» sin tocar nada | Todo correcto (`1728` archivos aprox.). |

Guarda captura del error crítico de 2.3.

## 3. Confirmaciones y diálogos

| # | Qué hacer | Esperado |
|---|---|---|
| 3.1 | Antes de abrir la app, en una PowerShell de administrador: `[Environment]::SetEnvironmentVariable('NIT_AUTO','1','Machine')`. Cierra sesión, entra de nuevo y abre la app. Lanza **Limpiar temporales** | El cuadro Sí/No **aparece igualmente** (la app quita `NIT_AUTO` del entorno del script). Después borra la variable: `[Environment]::SetEnvironmentVariable('NIT_AUTO',$null,'Machine')` |
| 3.2 | Con la app abierta, lanza **Reparar red** | El cuadro Sí/No sale **delante** de la ventana de la app (no escondido detrás). |
| 3.3 | Responde **No** | Dice «Cancelado: no se ha cambiado nada». Comprueba que no se reinició la red (no pierdes conexión). |
| 3.4 | Repite y responde **Sí** | Muestra la ruta de `Backup_Red_<equipo>.txt` en `%TEMP%\Nitrit0_Cache\Informes`; el archivo existe y contiene la configuración IP. |
| 3.5 | Lanza **Actualizar versión de Windows** (solo si la VM no está ya en la última) y responde **No** | Cancelado sin cambios. (Si respondes Sí tardará mucho: no hace falta.) |

## 4. Cambiar IP y rollback

Necesitas ver el rollback cuando falla, no cuando funciona.

1. Anota tu IP actual: `Get-NetIPConfiguration`.
2. Abre **Cambiar IP**, elige el adaptador, ponle una IP manual en **otra subred** y una **puerta de enlace inválida** (por ejemplo `999.1.1.1` o fuera de la subred) y aplica.
3. Esperado: error al aplicar y **vuelve a DHCP** (o a tu IP anterior). Comprueba con `Get-NetIPConfiguration` que tienes conexión y la IP de antes.
4. Prueba también un cambio **válido** a una IP libre de tu subred y vuelve luego a DHCP con la opción de DHCP.

## 5. Puntos de restauración (necesita administrador)

Activa la protección del sistema si está desactivada (la herramienta intenta hacerlo; comprueba).

| # | Qué hacer | Esperado |
|---|---|---|
| 5.1 | `Get-ComputerRestorePoint` antes de nada | Anota cuántos hay. |
| 5.2 | Lanza **Actualizar programas** | Crea el punto «Nitrit0 - antes de Actualizar programas» (puede tardar hasta 3 min). |
| 5.3 | En menos de 30 min lanza **Reparar Windows y Tienda** | Dice «Ya hay un punto de restauración de Nitrit0 de hace menos de 30 minutos» y **no crea otro**. Puede tardar mucho (DISM y SFC); cancélalo cuando haya salido el mensaje. |
| 5.4 | `Get-ComputerRestorePoint` | Solo +1 punto de Nitrit0. |
| 5.5 | Espera 30+ min (o cambia el reloj) y lanza otra de la lista (p. ej. **Restablecer Windows Update**) | Crea un punto nuevo. |

## 6. Instaladores: firmante esperado (lo más probable que falle)

Abre **Instalar programas** y marca de uno en uno: Chrome, Firefox, Brave, WinRAR, 7-Zip, VLC, AnyDesk. Anota para cada uno el resultado:

| App | Resultado esperado | Si falla |
|---|---|---|
| Chrome (MSI) | Descarga, comprueba firmante «Google LLC» e instala. | Anota el texto exacto de «firmado por … : <subject>». |
| Firefox | Firmante «Mozilla Corporation». | idem |
| Brave | «Brave Software». | idem |
| WinRAR | «win.rar GmbH». Se instala en modo prueba (sin licencia: es el pack público). | idem |
| 7-Zip | Sin firma de editor: se valida la huella SHA-256 fija de la versión 24.08 y el dominio `www.7-zip.org`. | Anota el mensaje exacto. |
| VLC | Lee el nombre actual del listado de `get.videolan.org` (hoy `vlc-3.0.24-win64.exe`) y comprueba el firmante «VideoLAN». | Anota el mensaje exacto. |
| AnyDesk | «AnyDesk» o «philandro». **No** debe arrancar con Windows. | idem |

Si una app se rechaza por firmante, el mensaje muestra el nombre real del certificado: apúntalo (nombre exacto) y se ajusta la lista. Comprueba también que, tras instalar, se haya borrado el instalador de `%TEMP%\Nitrit0_Cache\Descargas`.
Prueba además que **Office 2013 no aparece** en la lista (es del pack personal).

## 7. Informes y privacidad

| # | Qué hacer | Esperado |
|---|---|---|
| 7.1 | **Batería** (en VM sin batería puede no generar nada: anótalo) y **Energía (60 s)** | El informe se muestra en la ventana de la app. `Datos\Informes` **no contiene** `Bateria_*` ni `Energia_*`; sí están en `%TEMP%\Nitrit0_Cache\Informes`. |
| 7.1b | **Inventario del equipo** o **Informe de entrega** (en el pack público) | El HTML se guarda en `%TEMP%\Nitrit0_Cache\Informes`, **no** en `Datos\Informes`. Para ver la diferencia con el pack personal, repite con `OcultarPeligro` = `false` en `Datos\Ajustes.json`: ahora sí va a `Datos\Informes`. |
| 7.2 | **Licencias y BitLocker** (si aparece) | No deja nada con claves en `Datos\`. |
| 7.3 | **Copia de datos del usuario** a una carpeta de prueba | Copia Escritorio/Documentos...; en la carpeta `Chrome_Marcadores` y `Edge_Marcadores` solo hay `Bookmarks` (sin `Login Data`, `Cookies`, `Web Data`, `Local State`). Instala Chrome y abre antes un perfil para que existan. |
| 7.4 | Tras usar varias herramientas, mira `Datos\` del pack público | Sigue con **solo** `Ajustes.json`, `Integridad.json` y `kit.id`: nada de `Logs`, `Historial`, `Respaldo` ni `Historial_Diagnosticos.log`. Los registros están en `%TEMP%\Nitrit0_Cache\Logs` y los respaldos de «Deshacer cambios» en `%TEMP%\Nitrit0_Cache\Cambios`. (En el pack personal, o con `OcultarPeligro` = `false`, sí van a `Datos\`, salvo la salida de «Wi-Fi y claves» y «Licencias y BitLocker», que nunca se copia al pendrive.) |
| 7.5 | Abre la app, **Herramientas**: busca «Wi-Fi y claves» y «Licencias y BitLocker» | En el pack público **no aparecen** (ahora son «peligrosas»). En el personal sí. |
| 7.6 | Lanza **Reparar red** con AnyDesk abierto (o conectado por escritorio remoto) | El cuadro avisa de la herramienta de control remoto antes de pedir confirmación. |

## 8. Asistente y ejecución en cadena

1. Abre el **Asistente guiado** (en `Nitrit0.exe` no está en las listas: es el botón «Asistente guiado» de **Estado del equipo**; también está en `Lanzador Nitrit0.exe`) y elige el síntoma «Problemas con Internet» (pasos: `Reparar_Red` y `Red_WiFi_y_Claves`).
2. Esperado: **una sola** confirmación global; después los pasos corren, cada uno pide su Sí/No si cambia algo; **no se crea ningún** `.ps1` en `%TEMP%\Nitrit0_Cache\Ejecutor` (comprueba la carpeta).
3. Si bloqueas uno (haz lo de 2.3 antes), sale «BLOQUEADO» en el resumen y los demás siguen.

## 9. Lo que NO se puede probar en la VM

- **Drivers de HP y Lenovo** (`Reparar_Drivers_OEM`): no tiene fabricante soportado y avisa «equipo no soportado». Comprueba que ese mensaje sale bien. La ruta de Lenovo con la orden del XML solo se prueba en un Lenovo real.
- **Sensores de temperatura**, batería real y SMART real.

## 9 bis. Portada, «Este equipo», ajustes y tema (cuarta ronda)

| # | Qué hacer | Esperado |
|---|---|---|
| 9b.1 | Abre `Nitrit0.exe` en modo técnico | Primera pantalla «Inicio»: tres tarjetas grandes y varias pequeñas. En el pack público **no** sale «Quitar programas de fábrica» (herramienta oculta). Ctrl+1 vuelve a Inicio. |
| 9b.2 | Pulsa la tarjeta «Va lento» | Abre «Arreglar mi equipo» con esa opción ya desplegada y su botón «Empezar». No empieza nada solo. |
| 9b.3 | Pulsa «Este equipo» (abajo a la izquierda) | Panel con procesador, memoria y discos reales y «Ver el estado completo». Se cierra con Escape o pulsando fuera. |
| 9b.4 | Herramientas → pestaña **Ajustes** | Lee 5 ajustes con su etiqueta de estado. Los de Windows 11 solo aparecen con compilación 22000 o superior (el filtro «Solo lo que existe en mi Windows» lo explica). |
| 9b.5 | Cambia «Mostrar las extensiones de archivo» con su interruptor y abre una ventana nueva del Explorador | Las extensiones se ven u ocultan. Vuelve a dejarlo como estaba. |
| 9b.6 | Cambia **tres** ajustes seguidos y lanza «Deshacer los últimos cambios» (Combos) | Hay **una sola** sesión «Ajustes de Windows» con los tres cambios; al deshacer, vuelven a su valor anterior. |
| 9b.7 | Con una **cuenta estándar**, abre la app y eleva con la contraseña de **otro** administrador | Aviso «La app está abierta con otra cuenta…» y los controles de Ajustes desactivados. **Es la prueba que nunca se ha hecho.** |
| 9b.8 | Desplegable de tema (abajo): Claro, Oscuro, «Igual que Windows»; con la última, cambia el tema de Windows con la app abierta | La app y los botones de la ventana cambian. En el pack público, `Datos\Ajustes.json` solo cambia cuando **tú** eliges el tema, no cuando Windows cambia solo. |
| 9b.9 | En el pack público, busca «Licencias y BitLocker» y «Wi-Fi y claves» en Inicio, Estado del equipo, favoritas y el buscador | No aparecen en ningún sitio. |

## 10. Qué hacer con los resultados

- Vuelve a la instantánea «limpia» entre bloques si algo cambió el sistema.
- Pásame `Resultado_Prueba.txt`, la tabla con OK / FALLA y los logs (`Datos\Logs\*.log`, `Datos\Logs\Ejecuciones\*`) de lo que falle, más los nombres exactos de firmante rechazados. Con eso corrijo y regenero los packs.
- Lo más probable que haya que tocar: nombres de firmante (6), el texto del cuadro tras la ventana (3.2) y los permisos de crear puntos de restauración (5).
