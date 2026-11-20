# Análisis: Snappy Driver Installer Origin (SDIO) y Windows-Maintenance-Tool

Fecha: 2026-11-15. Continúa `Analisis_Programas_Diagnostico_Drivers.md`.

## 1. SDIO descargado y examinado

- **Descarga oficial** de la página del autor (www.glenn.delahoy.com), versión 2.0.8.891: `SDIO_2.0.8.891.zip`, 11,5 MB.
  SHA-256: `96F48D84D97EBDA6E60FD67C45EAF388AE7D3B3DB8E171D3C5D7E5381065BA89`.
- Guardado en `Apps\Drivers\SDIO\` (192 archivos, ya extraído) y el zip en `Apps\Drivers\`. **No está en el catálogo ni en los packs**: `Crear_Packs.ps1` excluye `Apps\Drivers` mientras se valora. `Apps\` ya está fuera de git.
- **Comprobado en el propio zip:** los ejecutables (`SDIO_x64_R891.exe`, `SDIO_R891.exe`) llevan **firma digital válida** de Glenn Delahoy; los metadatos dicen «GNU GPL v3»; no hay rutas sospechosas en el zip; no incluye paquetes de drivers (ni índices); trae manual en PDF, scripts de ejemplo y 30 idiomas.
- **El zip no incluye el texto de la licencia GPL.** Si algún día se redistribuye con el kit habría que añadirlo y ofrecer el código fuente (SourceForge: sourceforge.net/projects/snappy-driver-installer-origin).
- **Motor de scripts propio.** Los scripts de ejemplo del zip muestran los comandos: `init`, `writedevicelist <archivo>`, `snapshot`, `checkupdates`, `get ...` (descargas), `restorepoint` (punto de restauración), `select missing newer current better net`, `install`, `reboot ifneeded`, `onerror goto`.
  **Muy importante:** `enableinstall off` viene por defecto, es decir, **modo prueba: no instala nada** hasta que se cambia a `on`.
- **Lo que significa para el kit.** Se puede integrar con poco riesgo: nuestro script genera un script SDIO en modo prueba, SDIO calcula qué drivers faltan o mejoran, el kit enseña la lista, y solo tras confirmar se repite en modo real (con punto de restauración nativo). El técnico ve siempre qué se va a instalar.

**No comprobado:**
- **No se ha ejecutado.** El sistema bloqueó mi intento de ejecutar el programa descargado, así que no he verificado la sintaxis de la línea de órdenes (`-script:` y `-nogui` son suposición mía), ni que funcione sin ventana, ni qué detecta en este equipo.
- La **licencia y las condiciones de los paquetes de drivers** (lo que se descarga aparte, por torrent) siguen sin confirmar, igual que su tamaño. Sin paquetes, SDIO no instala nada.
- El autor advierte de que su selección de drivers no es infalible: nunca instalar sin confirmación humana y con punto de restauración.

**Recomendación:** SDIO como **biblioteca opcional solo para el pack personal**, con los paquetes en otro disco (o un paquete pequeño de drivers de red en el pendrive para equipos sin Internet). Antes de integrarlo: ejecutarlo tú en modo prueba (o autorizar que lo ejecute) para confirmar la línea de órdenes.

## 2. Windows-Maintenance-Tool (WMT, ios12checker)

Datos del repositorio (leídos por un agente en la web): licencia **MIT**, v6.7, 1,5 mil estrellas, 863 commits, último commit el 12-oct-2026, 3 incidencias abiertas. Es una interfaz WPF en PowerShell de **un solo archivo de 3,2 MB (57.056 líneas)** más un lanzador `.bat`, que pide administrador.

**Lo que he comprobado yo, buscando patrones en el script descargado** (sin leerlo entero, sin ejecutarlo):
- No usa `Set-MpPreference`, `Add-MpPreference` ni nada para desactivar Defender.
- `Invoke-Expression` en 4 sitios; uno instala Scoop desde `get.scoop.sh` (descarga y ejecuta un script remoto, solo al elegir esa opción). Los otros tres no los he analizado.
- 30 usos de `Invoke-WebRequest/RestMethod`, 34 de `-ExecutionPolicy Bypass`, 29 de Base64/`EncodedCommand`, 5 de tareas programadas.
- Dominios a los que llama: GitHub, Microsoft, Steam, GOG, Epic, DNS públicos (Cloudflare, Google, Quad9, AdGuard), pypi, chocolatey, scoop, rubygems, crates.io, VirusTotal y el Catálogo de Microsoft Update.
- El README habla de un «ayudante de activación MAS»: **no lo he encontrado** en el código descargado (solo aparece «Activation» en el nombre de un evento de instancia única). Sin verificar.
- **El lanzador `.bat` se autoactualiza en cada arranque** descargando el script desde la rama `main`, **sin comprobar firma ni hash**, y lo ejecuta elevado. Es un patrón que **no hay que copiar**: ejecutarías código de cualquiera que gane acceso a ese repositorio.

**Veredicto:** no integrarlo (monolítico, gigante, con muchas descargas y comandos arbitrarios). Sí aprovechar **ideas**, que con MIT se pueden reimplementar con atribución:

| Idea de WMT | Qué tenemos | Propuesta |
|---|---|---|
| **Almacén de drivers**: clasificar paquetes En uso / Antiguo / Sin asociar / Inactivo, borrar los antiguos (`pnputil`), quitar dispositivos fantasma, exportar y restaurar | `Copia_Drivers`, `Auditoria_Drivers_Huerfanos`, la nueva `Ficha_Drivers` | **Prioridad alta:** «Limpiar almacén de drivers», con copia previa y confirmación. Encaja con la fase de drivers |
| **Compactar el sistema** (Compact OS / NTFS) para ganar espacio en discos pequeños | Nada | Media: script reversible con estimación previa |
| **Accesos directos rotos** (buscar y reparar) | Nada | Media, pequeño y seguro |
| **Limpieza con reglas** Winapp2 / BleachBit (cientos de reglas, con modo de análisis previo) | «Limpiar temporales» propio | Baja: valorar un motor de reglas. **Revisar antes la licencia de Winapp2**, que no he comprobado |
| **TRIM de SSD** | Hay que mirar si el Optimizador ya lo hace | Comprobar; es una línea (`Optimize-Volume -ReTrim`) |
| **Exportar/importar los ajustes** (JSON) | «Ajustes de Windows» con estado | Baja: exportar el perfil de ajustes |
| Gestor de inicio, de restauración, de firewall, de actualizaciones de winget/pip/npm | Autoruns, `Punto_Restauracion`, winget en parte | No hace falta; el firewall es arriesgado |
| Biblioteca de juegos Steam/Epic/GOG | — | No encaja |

**No copiar:** la autoactualización sin verificar, los «comandos personalizados» que ejecutan PowerShell arbitrario y cualquier activador de licencias de terceros.

## 3. Resumen de lo pendiente (para Gemini y para después)

1. Confirmar con una prueba controlada la línea de órdenes de SDIO y definir la integración (modo prueba, confirmación, punto de restauración).
2. Revisar licencias: paquetes de SDIO, `pci.ids`/`usb.ids` y Winapp2.
3. Construir «Limpiar almacén de drivers» (idea más rentable de WMT).
4. Auditar los otros tres `Invoke-Expression` de WMT solo si se decide reutilizar código suyo.
