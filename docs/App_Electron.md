# App Nitrit0 (Electron): plan

Decisión (2026-11-13): el kit pasa de lanzador WinForms a **app Electron**. Los `.ps1` siguen siendo el motor; la interfaz es nueva. El lanzador actual sigue funcionando hasta que la app lo iguale.

## Principios
1. **Una sola base visual.** Colores, tipografía, espaciado y componentes salen de un único sistema de diseño (`App\src\renderer\diseno\`). Prohibido estilo propio por herramienta.
2. **Datos desde el principio.** La pantalla de inicio enseña salud, CPU, RAM, discos (SMART) y temperaturas reales, con los motores actuales (`Sensores.ps1`, `Motor_Diagnostico.ps1`).
3. **Los scripts no se reescriben.** La app los lanza con `Ejecutor.ps1` (salida en vivo, cancelar, tiempo máximo) y lee su resultado.
4. **Siempre elevada.** El exe lleva `requireAdministrator`, como `Lanzador Nitrit0.exe`; las apps de `Apps\` heredan el permiso.
5. **Interfaz en español**, textos como en el lanzador actual.

## Navegación (inspirada en la estructura de Kudu, no copiada)
Barra lateral con grupos: Inicio · Diagnóstico · Reparar y mantener · Preparar equipo · Discos y memoria · Pantalla y periféricos · Estrés y malware · Windows y red · Kit. Modo **Simple** (preguntas por síntoma, 3 caminos) y **Avanzado** (gráficos y datos).

## Componentes compartidos (primera entrega)
`PageHeader`, `StatCard`, `HealthScore`, `ScanProgress`, `ConfirmDialog`, `EmptyState`, `ToolCard`, `LiveOutput` (consola del Ejecutor).

## Datos
`Scripts\Exportar_Catalogo.ps1` vuelca el catálogo del lanzador y de `Mantenimiento\Catalogo.psd1` a `App\datos\herramientas.json`. Es la única fuente: la app no duplica la lista de herramientas.

## Fases
0. Esqueleto: electron-vite + React (CSS propio con variables, sin Tailwind), sistema de diseño, barra lateral, Inicio con datos reales.
1. Catálogo: todas las herramientas visibles y ejecutables (apps de `Apps\` y scripts con salida en vivo).
2. Diagnóstico, Modo taller, cuello de botella e informes dentro de la app (hecho; faltan Actualizar herramientas, Componentes y el monitor en vivo).
3. Incorporar de Kudu (MIT, conservando su aviso): reglas de limpieza JSON, duplicados y archivos grandes.
4. Retirar el lanzador WinForms cuando haya paridad.

## Empaquetado
`npm run empaquetar` (dentro de `App\`) compila y deja la app en `App\bin\Nitrit0-win32-x64\Nitrit0.exe` con @electron/packager: carpeta portátil, sin instalador y sin descomprimirse en %TEMP%.
- El exe lleva `requireAdministrator`: Windows pide el permiso al abrirlo, igual que el lanzador.
- Encuentra el kit subiendo carpetas hasta `Datos\kit.id` (hasta 4 niveles), así que funciona con cualquier letra de unidad mientras siga dentro del kit.
- `App\bin\` (~360 MB) está en .gitignore. Si se cambia el código hay que volver a empaquetar.
- Probado: abre elevado, ve las 110 herramientas y `admin: true`. Sin permisos de administrador no arranca (error 740): es lo esperado.
- **Archivo único:** `npm run empaquetar:unico` (en `App\`) deja `App\bin-unico\Nitrit0.exe` (106 MB, electron-builder, destino `portable`). Se copia a la raíz del kit (o donde se quiera dentro de él): al abrirse se descomprime en una carpeta temporal (unos 360 MB, 6-7 s) y la borra al cerrar. La raíz del kit se busca desde la carpeta del propio .exe (`PORTABLE_EXECUTABLE_DIR`). Pide administrador y se probó elevado: ve las 110 herramientas y `admin: true`.
  - Sigue necesitando la carpeta del kit (`Scripts\`, `Datos\`, `Apps\`): los scripts quedan fuera a propósito para poder editarlos, comprobar su integridad y actualizarlos sin recompilar.
  - Si el equipo se apaga o el proceso se mata a la fuerza, la carpeta temporal se queda hasta que se limpie `%TEMP%`.
  - Se ha sustituido la firma de código por nada (`signAndEditExecutable: false`: evita descargar herramientas de firma que fallan sin permisos de enlaces simbólicos): el .exe interno lleva el icono por defecto de Electron.
- Pendiente: firmar el exe (SmartScreen avisa en equipos de clientes) y que `Integridad.json` cubra `App\`.

## Cola de ejecución
Con un script normal en marcha (clase `script`), pulsar otro script o informe lo pone en cola en vez de rechazarlo (`lanzarId` en `main/index.ts`; hasta 10, sin repetir). Al terminar uno arranca el siguiente tras 4 s; si se cancela, la cola se vacía; si falla o agota el tiempo, la cola sigue. Diagnóstico, cuello de botella y revisión automática no admiten cola. La cola vive solo en memoria y se ve y se edita en la pantalla «En marcha» (Quitar / Vaciar). Una herramienta con ventana (casillas) abrirá esa ventana sola cuando le toque. Probado con `NITRIT0_LANZAR=<id1>,<id2>,<id3>` (en desarrollo).

## Restricciones
- Electron pesa ~250 MB en el pendrive; aceptado.
- `Apps\` y `Datos\` siguen fuera de git. `node_modules\` y `dist\` también.
- Nada de datos de clientes en logs de la app.

## Revisar y arreglar
La pantalla «Arreglar mi equipo» lanza `Scripts\Arreglo_Automatico_Para_App.ps1` (clase `auto` en el proceso principal; líneas `##AUTO##` con JSON). Detalle de lo que arregla y lo que no, y las pruebas hechas, en `Auditoria_Mejoras.md`.
- Los pasos son una lista cerrada del propio script; la interfaz solo manda «instalar actualizaciones» (sí/no) y el nombre del cliente.
- «Saltar este paso» crea `%TEMP%\Nitrit0_Cache\saltar.flag`; el script lo mira cada segundo y cierra el paso en curso.

