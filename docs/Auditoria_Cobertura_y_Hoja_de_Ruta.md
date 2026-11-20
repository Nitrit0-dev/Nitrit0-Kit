# Auditoría de Nitrit0 Kit: cobertura, robustez y hoja de ruta

Fecha: 2026-11-15. Informe para revisar juntos; **no se ha escrito código nuevo para él**. Las cifras de robustez salen de búsquedas de texto sobre los 68 scripts de `Scripts\Mantenimiento` (no de ejecutarlos) y la valoración de brechas es criterio mío, no una medición.

## 1. Inventario de lo que ya resolvemos

Catálogo actual: **127 elementos** (124 visibles). Además, «Arreglar mi equipo» ejecuta un diagnóstico guiado con 22 «soluciones» enlazadas a pruebas.

| Área | Qué resolvemos hoy | Cómo |
|---|---|---|
| **Diagnóstico general** | Informe rápido, inventario del equipo, prueba de hardware, diagnóstico completo, historial de diagnósticos, informes HTML, cuello de botella («Qué lo frena») | PowerShell + CIM/WMI, LibreHardwareMonitor |
| **Disco y memoria** | SMART (CrystalDiskInfo, SMART detallado), espacio (WizTree, WinDirStat, Analizar espacio), TRIM/desfragmentar, disco sucio y reinicios pendientes, quién bloquea un archivo, test de RAM (TestMem5, MemTest64/86, mdsched), gestión de RAM, recuperación (TestDisk, PhotoRec) | Programas portables, `fsutil`, Administrador de reinicio, `Optimize-Volume`, CIM |
| **Pantallazos y eventos** | Forense de BSOD: minidumps, drivers `.sys`, WHEA, Kernel-Power 41, TDR de GPU; Visor de eventos | PowerShell sobre registros de eventos y volcados |
| **Sistema operativo** | SFC, DISM, restablecer Windows Update, reparar Windows y Tienda, reparar TPM, reparar perfil de usuario, actualizar Windows y la versión, deshacer cambios, puntos de restauración | Comandos nativos + PowerShell, `Start-OperacionSegura` |
| **Red** | Reparar red (DNS, Winsock, IP), DNS más rápido, cambiar IP, test de red, latencia de red y DPC, Wi-Fi y claves, IP Changer | `netsh`, `ipconfig`, CIM, `Test-NetConnection` |
| **Drivers** | Drivers con fallo, ficha de drivers (Hardware ID, chip, fecha), driver desde el Catálogo de Microsoft (firma comprobada), drivers del fabricante (HP, Lenovo), limpiar almacén de drivers, dispositivos fantasma, copia de drivers, reinstalar gráfica (DDU) | `pnputil`, Catálogo de Microsoft, `Get-WindowsDriver` |
| **Rendimiento y energía** | Modos Ahorro/Equilibrado/Juego, optimizador personal, optimizar rendimiento, programas de inicio, puesta a punto, control de energía, batería, energía (60 s), perfil de baja latencia, uso de VRAM, liberar RAM | Registro con copia y punto de restauración, `powercfg`, `EmptyWorkingSet` |
| **Software y limpieza** | Limpiar temporales, limpieza profunda con estimación, quitar bloatware y IA de Windows 11, desinstalar a fondo y Office, limpiar registro huérfano, actualizar programas (winget), actualizar herramientas del kit | PowerShell, `winget`, cuarentena reversible |
| **Seguridad y arranque** | Activar seguridad de Windows, Licencias y BitLocker, editor de HOSTS (con aviso de entradas sospechosas), Autoruns, antimalware (AdwCleaner, KVRT) | Registro, Defender, programas portables |
| **Equipos y entrega** | Clonar disco, copia y restauración de datos del usuario, instalar impresora de red, reparar impresoras (cola), preparar para venta, informe de entrega, salud del pendrive | `DISM`, VSS, `robocopy`, `Win32_Printer` |

## 2. Robustez y seguridad de lo existente

Medido sobre los 68 scripts de `Scripts\Mantenimiento` (búsqueda de texto, cota aproximada):

| Criterio | Resultado |
|---|---|
| Con al menos un `try/catch` | **58 de 68** (sin él: Actualizar_Herramientas, Actualizar_Software, Actualizar_Windows, Auditoria_Drivers_Huerfanos, Componentes_Kit, LimpiarTemporalesEquipo, Monitor_Latencia_y_Red, Perfil_Baja_Latencia, Restaurar_Cuarentena, Vaciar_Cuarentena) |
| Registran lo que hacen (`Write-Log`) | **67 de 68** |
| Usan códigos de salida (`exit 1/2`) | 40 |
| Piden confirmación o ventana | 43 |
| Comprueban administrador por sí mismos | **18** (el resto depende de que la app ya vaya elevada) |
| Con **modo simulación** (`-SoloAnalizar`, `-SoloMirar`…) | **solo 9** |
| Clasificación aproximada | 17 solo leen, 40 cambian el sistema, 11 borran datos |
| De los 51 que cambian o borran: con alguna red de seguridad (punto de restauración, copia, cuarentena) | **33 (probablemente menos: la búsqueda es laxa)**; con punto de restauración de verdad, unos 24 |

**Los 18 que cambian o borran sin ninguna red de seguridad detectada:** Actualizar_Herramientas, Asistente_Guiado_Inteligente, Clonar_Disco, Componentes_Kit, Control_Energia, Copia_Drivers, Disco_Sucio_y_Reinicios, Editor_Hosts, Instalar_Impresora_Red, LimpiarTemporalesEquipo, Limpiar_Espacio_Windows, Optimizar_Unidades, Pantalla_Nitidez, Preparar_Venta, Quien_Bloquea, Reparar_Impresoras, Reparar_Red, Restaurar_Datos_Usuario.

Matices que conviene no leer como fallos: varios de esos son inherentemente irreversibles (clonar sobre un disco, borrar temporales) y ya piden confirmación; «Editor_Hosts» y «Actualizar_Herramientas» sí guardan copia, pero con otro mecanismo que la búsqueda no reconoce.

**Los más débiles, por orden:** LimpiarTemporalesEquipo (borra, sin `try/catch`, sin comprobar administrador ni salida), Vaciar_Cuarentena, Restaurar_Cuarentena, Componentes_Kit, Control_Energia, Reparar_Red (restablece Winsock y TCP/IP sin copia), Pantalla_Nitidez (dice que «revierte solo» pero no usa ningún patrón de seguridad), Actualizar_Windows y Actualizar_Software (sin `try/catch` ni comprobación de administrador).

**Una debilidad que he sufrido yo mismo:** dos veces el texto de una herramienta nativa cambió con el idioma de Windows (`fsutil dirty query`, `defrag /A`) y mi lectura falló. Hay que leer propiedades de objetos (CIM, cmdlets), no texto traducido.

## 3. Brechas frente a un mapa exhaustivo de problemas

Leyenda: ✅ cubierto · 🟡 parcial · ❌ falta.

### Red y conectividad
| Problema | Estado |
|---|---|
| DNS, Winsock, TCP/IP, renovar IP | ✅ Reparar red, DNS más rápido |
| Conflicto de IP / IP fija | 🟡 Cambiar IP; no detecta conflictos (ARP) |
| Cortes intermitentes por ahorro de energía del adaptador | ❌ (`Get-NetAdapterPowerManagement`) |
| Proxy colgado (`netsh winhttp`) y configuración de proxy | ❌ |
| VPN: adaptadores virtuales, rutas, MTU | ❌ |
| Puertos bloqueados / quién escucha (`Test-NetConnection`, `netstat -abno`) | ❌ |
| Compartir en red local (SMB, descubrimiento, credenciales de red, NetBIOS) | ❌ |
| Firewall: estado, reglas, restablecer | 🟡 «Activar seguridad» lo activa, no lo audita |
| Adaptadores ocultos o fantasma de red | 🟡 «Dispositivos fantasma» (los de USB/almacenamiento; no los virtuales) |
| Análisis Wi-Fi (canales, señal) | ❌ |

### Rendimiento, hardware y energía
| Problema | Estado |
|---|---|
| Cuello de botella, planes de energía, juego/ahorro | ✅ |
| Disco al 100 %: **qué proceso lo causa ahora** | ❌ (hoy se mide el disco, no el culpable) |
| Fugas de memoria (qué proceso crece con el tiempo) | 🟡 «Qué lo frena» mide un instante |
| Salud de discos SMART/NVMe | ✅ |
| Desgaste de batería | ✅ Batería (informe de Windows) |
| Fallos tras suspensión o hibernación, qué lo despertó | 🟡 «Energía (60 s)»; no `powercfg /lastwake` ni `/devicequery wake_armed` |
| USB que se desconectan solos (suspensión selectiva, hubs, controladores) | ❌ |
| Térmico real | ✅ (con el controlador PawnIO) |

### Sistema operativo, registro y arranque
| Problema | Estado |
|---|---|
| Corrupción de imagen (SFC/DISM), Windows Update | ✅ (con lectura de registros: ❌) |
| **Reparar arranque (BCD) y estado de WinRE** | ❌ — el clonador lo toca pero no hay herramienta de reparación |
| **Menú Inicio, barra de tareas, Explorador que fallan** (reinscribir paquetes de la shell, reiniciar `explorer`, cachés) | ❌ |
| Asociaciones de archivos y navegador predeterminado rotos | ❌ |
| Permisos NTFS y propietario de carpetas (`takeown`/`icacls`) | ❌ |
| Almacén de credenciales | ❌ |
| **Hora y sincronización** (`w32tm`, zona horaria) | ❌ — muy frecuente y pequeño |
| WMI dañado (`winmgmt /verifyrepository`) | ❌ |
| Índice de búsqueda de Windows y caché de iconos | ❌ |
| BSOD: análisis de minidumps | ✅ resumen forense; ❌ análisis profundo con WinDbg |

### Drivers y multimedia
| Problema | Estado |
|---|---|
| Dispositivos con error, driver genérico, driver antiguo | ✅ |
| Buscar e instalar el driver concreto, limpiar el almacén | ✅ |
| **Audio que desaparece** (servicios de audio, dispositivo predeterminado, HDMI) | 🟡 solo página de prueba; falta reparar |
| Micrófono o cámara bloqueados por privacidad | ❌ (claves de permisos de privacidad) |
| Reiniciar el driver gráfico (equivalente a Win+Ctrl+Mayús+B), aceleración por hardware | 🟡 «Reinstalar gráfica» (DDU, drástico); falta lo ligero |
| Impresoras: cola atascada | ✅; **driver corrupto que impide borrar** ❌; Bluetooth ❌ |

### Software, navegadores y bloatware
| Problema | Estado |
|---|---|
| Bloatware, telemetría, IA, desinstalación a fondo | ✅ |
| Actualización masiva (`winget`) | ✅; reparar el origen de winget ❌ |
| Reparar Microsoft Store y apps UWP | ✅ |
| Cachés de Teams, OneDrive, Outlook | ❌ (navegadores sí) |
| Reparar Office (Click-to-Run) | ❌ (solo desinstalar) |
| .NET y runtimes de Visual C++ rotos | 🟡 hay instaladores en `Apps\Instaladores`, no reparación guiada |

### Seguridad, privacidad y mantenimiento
| Problema | Estado |
|---|---|
| Restablecer o revisar el HOSTS | ✅ |
| Tareas programadas y procesos de arranque sospechosos | 🟡 Autoruns (manual); sin lista propia con avisos |
| **Defender y firewall: integridad** (`Get-MpComputerStatus`, firmas, protección activa) | 🟡 «Activar seguridad» actúa, no audita |
| Directivas de grupo corruptas (`gpupdate`, restablecer) | ❌ |
| Certificados caducados o de raíz sospechosos | ❌ |

## 4. Propuesta de hoja de ruta (para decidir juntos)

### Imprescindibles (frecuentes, hoy sin cubrir, riesgo controlable)
1. **Reparar arranque y WinRE**: estado (`reagentc /info`, `bcdedit /enum`), reconstruir BCD con `bcdboot` y copia previa. Encaja con el clonador y se puede probar con discos virtuales.
2. **Reparar Inicio, barra de tareas y Explorador**: reiniciar la shell, reinscribir sus paquetes, reconstruir cachés de iconos y miniaturas.
3. **Reparar audio**: servicios de audio, dispositivo predeterminado, permisos de micrófono y cámara, HDMI.
4. **Hora y sincronización**: comprobar y corregir con `w32tm`, zona horaria. Pequeño y muy pedido.
5. **Red avanzada en una herramienta**: proxy, ahorro de energía del adaptador, firewall (estado), SMB y uso compartido, probador de puertos con `Test-NetConnection`.
6. **«Qué lo está frenando AHORA»**: qué proceso causa el disco al 100 %, la RAM o la CPU (contadores y muestreo), con el servicio concreto (`SysMain`, `Search`, Defender).

### Muy recomendables
7. Reparar Office y limpiar cachés de Teams, OneDrive y Outlook.
8. **Auditoría de seguridad** de solo lectura: Defender (protección y firmas), firewall, tareas programadas y servicios de arranque sospechosos, certificados caducados, directivas de grupo.
9. Permisos NTFS: tomar propiedad y restaurar herencia con vista previa y copia de las ACL.
10. Reconstruir el índice de búsqueda; asociaciones de archivos y navegador predeterminado.
11. Comprobar y reparar WMI y los runtimes (.NET, VC++).
12. Bluetooth y impresoras: diagnóstico y quitar un driver de impresora corrupto.
13. Leer los registros de Windows Update (`Get-WindowsUpdateLog`) para decir *por qué* falla, no solo reiniciar componentes.

### Avanzados / Pro
14. Captura de red sin programas externos (`netsh trace`) y `pathping`; grabación de rendimiento con el Windows Performance Recorder.
15. Análisis profundo de un volcado con WinDbg (`cdb`) y símbolos de Microsoft.
16. Comprobador de drivers (`verifier`) guiado, con aviso fuerte.
17. Informe de directivas y unión a dominio/Entra ID (`gpresult`, `dsregcmd /status`) para equipos de empresa.
18. Borrado seguro del espacio libre (`cipher /w`) en «Preparar para venta».

## 5. Herramientas nativas de Windows poco conocidas que añadirían valor sin reinventar la rueda

`powercfg /lastwake /requests /devicequery wake_armed /sleepstudy /energy` (despertares, suspensión, batería) · `w32tm` (hora) · `winmgmt /verifyrepository` · `reagentc` y `bcdboot` (recuperación) · `netsh trace` y `pathping` (red) · `Get-NetAdapterPowerManagement` · `Get-MpComputerStatus` y `MpCmdRun` (Defender) · `Get-WindowsUpdateLog` · `driverquery /si` y `sigverif` (drivers sin firmar) · `dism /Cleanup-Image /AnalyzeComponentStore` · `cipher /w` · `takeown` e `icacls` · `gpresult` y `dsregcmd` · `mrt.exe` (herramienta de eliminación de software malicioso de Microsoft) · `wpr` y `tracerpt` (trazas de rendimiento) · `schtasks /query /v` y `Get-ScheduledTask` (tareas sospechosas) · `certutil` y `Cert:\` (certificados) · `Test-NetConnection` (puertos y rutas).

## 6. Mejoras técnicas antes de seguir añadiendo módulos

1. **Red de seguridad uniforme.** Hoy 18 scripts que modifican el sistema no tienen copia previa ni punto de restauración. Regla propuesta: todo script que cambie algo usa `Start-OperacionSegura` (o declara en la ficha del catálogo por qué no puede).
2. **Modo simulación en todo lo que cambia algo.** Solo 9 de 51 lo tienen. Hacerlo estándar (`-SoloAnalizar`) y que la ficha del catálogo diga si el script es simulable, para que la app ofrezca «ver qué haría» antes de ejecutar.
3. **`try/catch` y códigos de salida en los 10 scripts sin ellos**, empezando por `LimpiarTemporalesEquipo` y los de cuarentena. Contrato único de salida: código 0 bien, 1 error, 2 cancelado, y líneas marcadas para la app.
4. **Una función única «¿soy administrador?»** en `Comun.ps1`, usada por todos; hoy 18 lo comprueban cada uno a su manera y el resto asume que la app ya eleva.
5. **No leer texto traducido.** Prohibir en la guía de scripts el análisis de la salida de herramientas nativas cuando exista cmdlet o propiedad CIM equivalente.
6. **Pruebas automáticas sobre discos virtuales y datos simulados**, como las que hemos improvisado esta sesión, guardadas en `Scripts\Pruebas`, para poder repetirlas tras cada cambio.
7. **Niveles de riesgo en el catálogo** (leer, cambia, borra, irreversible) en lugar de «peligroso» sí o no: permitiría decidir qué sale en el pack público con más finura.
8. **Resolver las dos funciones aún pendientes del lanzador clásico** (ya pasadas a la app) y decidir cuándo borrar `Lanzador.ps1`.

## 7. Qué decidir ahora

- ¿Empezamos por los **seis imprescindibles** en ese orden, o prefieres otro?
- ¿Endurecemos primero los 18 scripts sin red de seguridad (mejora técnica 1 a 3) antes de añadir módulos nuevos? Mi recomendación: sí, pero solo los que más pueden dañar (`LimpiarTemporalesEquipo`, `Reparar_Red`, `Restaurar_Datos_Usuario`, `Vaciar_Cuarentena`) y el resto sobre la marcha.
- Los puntos de «Avanzados» solo en el pack personal.

## 8. Lo que no he comprobado
- Las cifras de robustez son búsquedas de texto sobre los scripts: dicen que un patrón existe, no que esté bien usado.
- No he ejecutado todos los scripts ni leído a fondo los 28 de `Scripts\` fuera de `Mantenimiento` (solo conté sus bloques `try`).
- La columna «Estado» de la sección 3 es mi valoración a partir del catálogo y de lo que sé de los scripts; puede haber funciones parciales que no recuerdo.

## 9. Estado a 20-nov-2026 (revisión de cobertura)

Desde esta auditoría (15-nov) se han cubierto casi todos los «imprescindibles» y «muy recomendables»: reparar arranque y WinRE, Inicio/barra/Explorador, audio y privacidad (incluidos los permisos de cámara y micrófono), hora y sincronización, red avanzada, «qué lo está frenando ahora», Office y cachés, auditoría de seguridad, WMI y runtimes, y los registros de Windows Update.

Pruebas de hardware dentro de la app («Pruebas del equipo», sin navegador): pantalla, teclado y chattering, ratón y táctil, webcam, audio y micrófono, **placa de vídeo** (WebGPU: memoria de vídeo con patrones, cálculo verificado y carga sostenida), **procesador** (hilos con cálculo verificado y puntuación para comparar) y **mando** (botones, deriva, gatillos y vibración).
Scripts nuevos: prueba de capacidad real de USB, prueba de puertos USB (velocidad por puerto) y diagnóstico de Bluetooth.
El «Siguiente paso» del diagnóstico apunta ya a las pruebas nuevas (GPU, procesador, Bluetooth).

Huecos que siguen abiertos:
- **Wi-Fi: análisis de señal y canales.** No hay un adaptador Wi-Fi con el que probarlo y `netsh wlan` devuelve texto traducido (regla 9); haría falta la API WinRT o `WlanApi`.
- **Benchmark comparable de GPU** (la de procesador ya guarda puntuaciones en la propia página) y de memoria.
- Del documento original: permisos NTFS y propiedad de carpetas, driver de impresora corrupto, análisis profundo de volcados (WinDbg), `verifier`, `gpresult`/`dsregcmd` y borrado seguro del espacio libre.

No verificado con hardware real: el reinicio del adaptador Bluetooth y el vaciado de caché antes de leer en la prueba de puertos USB (ambos necesitan administrador y, el primero, un adaptador); el mando solo se probó con un mando simulado.
