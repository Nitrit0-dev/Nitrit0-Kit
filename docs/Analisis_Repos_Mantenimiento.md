# Análisis de 23 repositorios de mantenimiento y limpieza de Windows

Fecha: 2026-11-15. Lectura hecha por agentes de solo lectura (README, lista de archivos y, en algún caso, parte del script); **no se descargó ni ejecutó nada**. Lo que cada repositorio dice de sí mismo (licencia, «sin telemetría», etc.) no está verificado leyendo su código completo. Los hallazgos sobre qué tenemos ya en el kit sí están comprobados buscando en nuestros scripts.

## Conclusión corta

**Ninguno es para integrar.** Los que tienen código abierto y licencia compatible son interfaces monolíticas o scripts `.bat` con borrados sin deshacer; lo nuestro ya hace lo mismo con punto de restauración, copia y confirmación. Hay **siete ideas** que sí rellenan huecos reales del kit (sección 2). Y hay **dos repositorios que no hay que abrir nunca** (sección 3).

## 1. Veredicto por repositorio

| Repositorio | Qué es | Licencia | Veredicto |
|---|---|---|---|
| ghosessx/Windows-Maintenance-Tool | Un `.exe` de ~200 KB: temporales, Papelera, miniaturas, red, SFC/DISM | MIT | Idea (miniaturas, logs CBS). 7 commits, 0 estrellas |
| Foulest/RepairKit | «Todo en uno» en Java con JRE empaquetado, tweaks y lanzador de herramientas | GPL-3.0 | Descartar (binarios, promociones, sin deshacer por tarea) |
| Mohabdo21/Windows-Repair-Tool | `.bat` de DISM/SFC/reset de Windows Update | MIT | Idea (patrones de seguridad). Su inicio rápido descarga y ejecuta de `main` sin hash |
| arisvardakas/Fixyfier | Programa comercial de la Microsoft Store (~300 tareas). El repositorio solo tiene README | Propietaria | Solo ideas; no se puede usar su código |
| filonux/Mint-Doctor | Reparación de **Linux Mint** | GPL-3.0 | No aplica (Linux). Una idea de diseño |
| debba/tuxcleaner | Limpiador de **Linux** en Rust | GPL-3.0 | No aplica (Linux). Dos ideas de diseño |
| SagarBiswas-MultiHAT/WinTempCleaner | `.bat` que borra temporales; **Enter equivale a «Sí»**, sin registro | MIT | Descartar |
| R4in84/Primus | `.bat` enorme (~140 KB) con PowerShell: recuperación, limpieza, red, privacidad | MIT | Ideas; **no copiar**: varios borrados sin confirmar |
| LevelSparkRecognize/Ashampoo-WinOptimizer | Crack falso con un cargador remoto | ninguna | **NO TOCAR** |
| tdikelt/Ashampoo-WinOptimizer | Página cebo que empuja a descargar un programa no identificado | ninguna | Descartar |
| hellzerg/optimizer | Optimizer: privacidad, servicios, limpieza, DNS, HOSTS (C#, 18 mil estrellas) | GPL-3.0 | Ideas; no integrar el binario |
| InsertX2k/temp_cleaner_gui | Limpiador de temporales en Python/Tkinter | GPL-2.0 | Descartar (ya lo cubrimos) |
| iandiv/Win11Tweaker | Interruptores de Windows 11 (WinUI 3) | MIT | Nada nuevo; parado desde marzo de 2025 |
| google/glazier | Aprovisionamiento corporativo de Windows (Go/Python) | Apache-2.0 | No encaja con un técnico independiente |
| harshvsingh8/win-tools | ~120 `.exe` de utilidades Unix, sin código ni licencia | ninguna | Descartar |
| Leo-Corporation/PermaTop | Fijar ventanas encima de todas | MIT | Descartar |
| ChristianOellers/Drunken-Mouse-Creative-Tool | Sacude el ratón a propósito | MIT | Descartar |
| HawaiiBeach/Win10Clean | Utilidad C#: apps, Edge, OneDrive, menú contextual | GPL-3.0 | Nada nuevo (ver abajo) |
| 5cover/WinClean | Interfaz WPF que lanza ~40 scripts | MIT | Una idea: catálogo con «nivel de seguridad» |
| warengonzaga/wrn-cleaner | `.bat` de mantenimiento; inactivo desde 2024 | GPL-3.0 | Una idea (TRIM) |
| builtbybel/CleanmgrPlus | Sustituto del Liberador de espacio, código cerrado | Propietaria que prohíbe derivados | Descartar |
| un1cum/CleanerPRO | Limpieza de RAM y disco; instalador binario; **tres direcciones de criptomonedas** | Apache-2.0 | Descartar |
| thomasloupe/CleanSweep | Limpiador con interfaz y línea de órdenes | **Sin licencia** (no reutilizable) | Una idea (estimar espacio) |

## 2. Lo que sí rellena un hueco del kit

Comprobado en nuestros scripts que **no existe** (o no lo encuentro):

| # | Idea | De dónde | Para qué sirve |
|---|---|---|---|
| 1 | **Quién bloquea este archivo o disco** (programa que impide borrar o expulsar) | Optimizer, Fixyfier | Muy típico en soporte. Se puede hacer sin programas externos con el Administrador de reinicio de Windows |
| 2 | **Editor del archivo HOSTS** con copia y vuelta atrás | Optimizer | Redirecciones y bloqueos que dejan malware o antiguos instaladores |
| 3 | **Dispositivos fantasma** (drivers de dispositivos que ya no están) | Windows-Maintenance-Tool, Primus, Fixyfier | Encaja al lado de la ficha de drivers y de la limpieza del almacén |
| 4 | **Estimar el espacio recuperable ANTES de limpiar** | CleanSweep | «Limpiar temporales» ya mide el espacio antes y después, pero no estima antes de pedir confirmación |
| 5 | **Categorías de limpieza que no tenemos**: miniaturas del Explorador, registros CBS, registros del Visor de eventos, caché de Delivery Optimization | CleanSweep, Windows-Maintenance-Tool | Hoy limpiamos temporales, Prefetch, SoftwareDistribution, navegadores y Papelera. **Windows.old** solo se analiza, no se borra: dejarlo como opción marcada con aviso |
| 6 | **Aviso de «disco sucio» de CHKDSK** (`fsutil dirty query`) y de reparaciones pendientes | Primus | Una línea; la comprobación de disco actual no lo dice |
| 7 | **TRIM de SSD** (`Optimize-Volume -ReTrim`) y desfragmentar solo los HDD | wrn-cleaner, Primus | No encuentro TRIM en ninguno de nuestros scripts |

Ideas de **diseño** (no son herramientas):
- **Nivel de seguridad por acción en el catálogo** (WinClean). Hoy tenemos «Peligroso» sí o no; un nivel intermedio ayudaría a decidir qué se ve en el pack público.
- **Modo desatendido** que omite lo que pide confirmación y devuelve un código de salida distinto de 0 si queda algo pendiente (Mint-Doctor).
- **Parar una secuencia de reparación** si DISM falla o pide reinicio, y **guardar con nombre único una copia de la caché de Windows Update** antes de vaciarla (Windows-Repair-Tool). Mirar si nuestro «Restablecer Windows Update» ya lo hace.
- **Historial de operaciones en JSONL con rotación** (tuxcleaner). Ya tenemos historial; la rotación es la novedad.

Lo que **ya tenemos** y no hay que repetir: menú contextual clásico de Windows 11 (en «Personalizar Windows 11»), búsqueda web en Inicio y apps en segundo plano (en el Optimizador), GameDVR, quitar bloatware e IA, copia de drivers, matar el árbol de procesos si se cuelga (glazier lo propone y ya lo hace `Invoke-Proceso`), reset de red, SFC y DISM.

## 3. Cuidado

- **LevelSparkRecognize/Ashampoo-WinOptimizer:** su README es un cebo que manda ejecutar `irm <dirección ajena> | iex` y apagar el antivirus. **No abrir esa dirección ni ejecutar nada.** El otro repositorio de Ashampoo (tdikelt) tampoco tiene el programa: solo empuja a descargar algo no identificado.
- **Patrón a evitar en lo que construyamos:** `Windows-Repair-Tool` baja y ejecuta su `.bat` de la rama `main` sin hash; el lanzador de `Windows-Maintenance-Tool` (otro repositorio, `ios12checker`) se autoactualiza igual. Nosotros verificamos siempre contra `Integridad.json`.
- Primus anuncia que pide confirmación en todo lo destructivo, pero según la lectura **cinco funciones borran sin preguntar** y su `Restore_Registry.bat` renombra los registros activos. No copiar su código.

## 4. Orden que propongo

1. «Quién bloquea esto» (idea 1) y «Editor de HOSTS» (idea 2): son herramientas nuevas, de solo lectura la primera y reversible la segunda.
2. Dispositivos fantasma dentro de la ficha de drivers (idea 3), con una opción de quitarlos después.
3. «Limpiar temporales» con estimación previa y categorías nuevas (ideas 4 y 5; Windows.old solo opcional).
4. TRIM y aviso de disco sucio (ideas 6 y 7): pequeños.

## 5. Lo que no está comprobado
- Todo lo que dicen los README de licencia, telemetría y «sin descargas». Solo en Primus se leyó parte del código (~40 %).
- Fechas de actividad: vienen de las páginas de GitHub en el momento de la lectura.
- No he comprobado si «Restablecer Windows Update» ya conserva una copia de la caché ni si el Optimizador hace algún tipo de TRIM bajo otro nombre (busqué `Optimize-Volume`, `ReTrim` y `defrag`).

## 6. Hecho (2026-11-15)
Las siete ideas están implementadas como herramientas nuevas del kit: **Quién bloquea un archivo o disco**, **Editor del archivo HOSTS**, **Dispositivos fantasma** (y el recuento en la Ficha de drivers), **Limpieza profunda de Windows** (con estimación previa), **Disco sucio y reinicios pendientes** y **Optimizar unidades (TRIM)**. Probadas en solo lectura en este equipo; el HOSTS se probó guardando sobre una copia temporal. **Sin probar:** quitar de verdad dispositivos fantasma, la limpieza real (incluidos Windows.old y registros de eventos), TRIM y desfragmentación reales, y cerrar programas desde «Quién bloquea». Dos errores propios corregidos gracias a las pruebas: el texto de `fsutil` varía con el idioma (se usa ahora la propiedad `DirtyBitSet` de Windows) y las instantáneas de volumen quedaron excluidas de los fantasmas.
