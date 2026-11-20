# Revisión externa (Gemini y Grok): ronda de perfiles, bandeja, instalación y registro

## Qué subirles

Los archivos `.txt` que hay en esta misma carpeta (son el código tal cual, con extensión `.txt` para que los lean completos):

| Archivo | Qué contiene |
|---|---|
| `main_index.ts.txt` | Proceso principal de la app: perfiles, bandeja, arranque con Windows, instalación en el equipo, liberar memoria |
| `preload_index.ts.txt` | Puente entre la interfaz y el proceso principal (lista de órdenes permitidas) |
| `PerfilUso.tsx.txt`, `Tareas.tsx.txt`, `App.tsx.txt` | Interfaz: pregunta inicial, tarjetas de modo, instalación, memoria |
| `Optimizador_Personal.ps1.txt` | Modos nuevos `PerfilAhorro` y `PerfilEquilibrado` |
| `Limpiar_Registro_Huerfano.ps1.txt` | Script nuevo: restos de programas borrados en el registro |
| `Memoria_Para_App.ps1.txt` | Script nuevo: liberar RAM de procesos inactivos |

No les subas los packs ni `Nitrit0.exe`.

## Texto para pegar

Eres revisor de código senior. Revisa estos cambios de «Nitrit0 Kit», una app Electron (TypeScript + React) para Windows 10/11 que ejecuta scripts de Windows PowerShell 5.1 (no pwsh) como administrador, en equipos de clientes y en el del propio técnico. No puedes ejecutar nada: revisa leyendo. Responde en español, ordenado de más a menos grave, con archivo y línea. Distingue lo que has **comprobado leyendo** de lo que **supones**, y dime qué no has podido revisar.

Cambios:
1. **Perfiles de uso** Ahorro / Equilibrado / Juego, elegibles en una pregunta inicial, en la portada y en el icono de bandeja. Reutilizan modos del Optimizador (plan de energía y registro, con punto de restauración y respaldo para revertir). La interfaz solo manda un id de una lista cerrada.
2. **Bandeja y arranque con Windows**: icono junto al reloj con menú; arranque mediante tarea programada `schtasks /sc onlogon /rl highest` con `--bandeja`; al cerrar la ventana se oculta si el arranque está activado. Se permite también en el pack público (lo activa la persona) pero se rechaza si el `.exe` está en una unidad extraíble o de red.
3. **Instalación pequeña en el equipo**: copia el `.exe`, `Scripts\`, `App\datos\herramientas.json` y `Datos\{kit.id,Integridad.json,Ajustes.json}` a `C:\Program Files\Nitrit0 Kit`, crea un acceso en el menú Inicio y activa el arranque. «Quitar instalación» lo deshace (si se ejecuta desde la copia instalada, se borra a sí misma al cerrarse).
4. **Liberar memoria**: `Memoria_Para_App.ps1` llama a `EmptyWorkingSet` de `psapi.dll` sobre los procesos (salvo el de primer plano y una lista de procesos de Windows/seguridad). Se lanza a mano, desde la bandeja, o sola si la RAM pasa del 90 % (como mucho cada 10 minutos y nunca con un script en marcha).
5. **`Limpiar_Registro_Huerfano.ps1`**: detecta entradas de registro, servicios y tareas que apuntan a archivos inexistentes y las borra tras exportar un `.reg` a una cuarentena reversible.

Pregúntate sobre todo:
- **Seguridad de la instalación y la tarea con privilegios altos**: el `.exe` y los scripts quedan en Archivos de programa (solo escribe un administrador), pero `Datos\Ajustes.json` y `Integridad.json` también. ¿Puede un usuario sin privilegios aprovecharse (la tarea se ejecuta elevada al iniciar sesión)? ¿Cuándo la tarea apunta a una ruta escribible por usuarios (por ejemplo, el pack público en una carpeta cualquiera)? ¿Inyección en los argumentos de `schtasks` o en el `cmd /c` de `quitarInstalacion` si la ruta tiene espacios o comillas?
- **`quitarInstalacion` y `instalarEnEquipo`**: ¿pueden borrar algo que no deben (ruta derivada de variables de entorno)? ¿Qué pasa si falla a medias? ¿Se deja la tarea o el acceso colgando?
- **Memoria**: ¿puede `EmptyWorkingSet` perjudicar (juegos, antivirus, rendimiento posterior por fallos de página)? ¿La lista de procesos excluidos es suficiente? ¿Es honesto decir que es solo un alivio momentáneo?
- **`Limpiar_Registro_Huerfano.ps1`**: ¿qué falsos positivos pueden borrar algo que sí se usa (unidades extraíbles o de red, rutas con variables, App Paths sin extensión, servicios de arranque retardado, rutas 8.3, WOW6432Node)? ¿La restauración desde el `.reg` deja el registro como estaba (binarios, `REG_EXPAND_SZ`, permisos)?
- **Optimizador**: ¿el plan Economizador (`a1841308-3541-4fab-bc81-f71556f20b4a`) falla en equipos con Modern Standby y el perfil queda a medias? ¿`PerfilEquilibrado` deshace de verdad lo que dejó `PerfilJuego` (HwSchMode, GameDVR, PowerThrottling)? ¿Sale con código 1 solo cuando debe?
- **Electron**: ocultar en `close` con scripts en marcha, instancia única al arrancar oculto, clic en la bandeja antes de que exista la ventana, `Notification` sin permisos, ejecución elevada y `userData` en `%TEMP%`.
- **Accesibilidad** de `PerfilUso.tsx` y de la sección «Modo del equipo» (diálogo modal, foco, `aria-pressed`, `role="switch"`).

Después, propón mejoras concretas y pequeñas, sin reescribir lo que ya funciona.

## Segunda ronda (solo diseño, sin código): clonado de discos

Queremos una herramienta propia de clonado de disco a disco para el kit (sin redistribuir Hasleo, cuya licencia gratuita es solo para uso doméstico). Idea: instantánea VSS + `Get-Disk`/`New-Partition` + copia por volumen, clonar a un disco menor reduciendo la partición, verificar y reparar el arranque con `bcdboot`. Dime los peligros (elegir mal el disco destino, BitLocker, discos dinámicos, EFI/MSR, arranque tras clonar), las salvaguardas obligatorias y si recomiendas esto, o usar Rescuezilla/Clonezilla en un WinPE del pendrive.
