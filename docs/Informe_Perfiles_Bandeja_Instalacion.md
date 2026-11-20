# Informe: perfiles de uso, bandeja, instalación en el equipo, memoria y registro

Fecha: 2026-11-15. Cierra las rondas 7 y 8 de revisión externa (Gemini y Grok).

## Qué se añadió

| Función | Dónde está | Cómo se usa |
|---|---|---|
| Perfiles **Ahorro / Equilibrado / Juego** | `Optimizador_Personal.ps1` (modos `PerfilAhorro`, `PerfilEquilibrado`, `PerfilJuego`); `main/index.ts` (`aplicarPerfil`) | Pregunta inicial, tarjetas en la portada «Modo del equipo» y menú del icono de bandeja |
| Icono en la bandeja | `main/index.ts` (`montarBandeja`) | Cambiar de modo, limpiar temporales, liberar memoria, abrir o salir. Al cerrar la ventana se oculta si el arranque está activado |
| Arranque con Windows | `main/index.ts` (`ponerArranque`) | Tarea programada con privilegios altos y `--bandeja`. **Solo desde la copia instalada** |
| Instalación pequeña | `main/index.ts` (`instalarEnEquipo`, `quitarInstalacion`) | Botón «Instalar en este equipo»: copia a `C:\Program Files\Nitrit0 Kit` (sin `Apps\`), acceso en el menú Inicio y arranque |
| Liberar memoria | `Scripts\Memoria_Para_App.ps1` | A mano, desde la bandeja o sola al pasar del 90 % de RAM (máximo cada 10 min, nunca con script en marcha ni en perfil Juego) |
| Limpiar registro huérfano | `Mantenimiento\Limpiar_Registro_Huerfano.ps1` | Entradas de programas ya borrados, con copia `.reg` reversible en `%ProgramData%\Nitrit0_Cuarentena` |
| Nuevo logo | `App\build\icono*.png/.ico`, `recursos\logo-nitrit0.png` | Recorte del icono elegido |

## Qué cambió tras las dos revisiones

Ronda 7 (arreglado):
- El arranque con Windows ya no se activa desde una carpeta que un usuario normal pueda modificar (la tarea corre con privilegios altos).
- El perfil Juego ya no vacía la papelera.
- Equilibrado restaura los valores de fábrica que tocan Ahorro y Juego.
- Se intenta crear el plan Economizador si Windows lo oculta.
- Memoria: más procesos protegidos y se saltan los de menos de 20 MB; no actúa sola en perfil Juego.
- Registro: no se borra una entrada si no se sabe con certeza qué archivo es; se ignoran rutas con variables de perfil y `WindowsApps`.
- Identificador de aplicación para las notificaciones, limpieza del acceso si la instalación falla y `aria-label` en los interruptores.

Ronda 8 (arreglado):
- Equilibrado **borra** (no pone a 1) las políticas de máquina de GameDVR y Edge, y restaura retardo de menús, búsqueda web, Widgets y Chat.
- El registro hace una sola copia `.reg` por clave antes de borrar sus valores.
- El interruptor de arranque aparece desactivado hasta instalar.

Descartado: el primer hallazgo de la ronda 7 era un falso positivo (el código ya distingue borrar clave y borrar valor). Los servicios que Ahorro pone en Manual no se restauran: casi todos vienen así de fábrica; «Revertir» los devuelve.

## Qué NO está comprobado

- Ejecución real de un perfil (cambia el sistema), el icono de bandeja, la creación de la tarea desde el `.exe` empaquetado y el flujo instalar / quitar.
- El `.exe` empaquetado con el icono nuevo (`signAndEditExecutable: false`).
- Que `PORTABLE_EXECUTABLE_DIR` no pueda ser definida por un usuario sin privilegios para desviar la raíz del kit de la app instalada (punto señalado por el revisor, sin probar).
- El plan Economizador en equipos con Modern Standby.
- Liberar memoria es solo un alivio momentáneo: Windows recarga lo que se vuelve a usar.

## Pendiente

- Pasar la revisión externa (Gemini y Grok) también al clonador, antes de usarlo con discos de clientes.
- Revisar el repositorio externo `openstd`.

## Clonador de discos (`Mantenimiento\Clonar_Disco.ps1`)

Clona un Windows GPT/UEFI a otro disco, incluso menor. Copia con **DISM desde una instantánea VSS** (no archivo a archivo: conserva enlaces físicos y permisos), recrea EFI/MSR/Windows/Recuperación/datos, copia datos con robocopy y deja el arranque con bcdboot. Decisión de diseño según las dos revisiones externas y la propia prueba.

Salvaguardas: por defecto **solo simula**; nunca deja elegir de destino el disco de Windows en marcha ni el del kit; rechaza MBR, discos dinámicos, BitLocker bloqueado y destinos que no caben (lo usado + 15 %); la imagen temporal nunca va al disco destino; confirmación escrita «BORRAR DISCO n»; y justo antes de borrar se comprueba otra vez el destino (número, tamaño, modelo y serie). El origen no se modifica. La partición EFI del destino es de al menos 260 MB. Solo modo técnico (marcado peligroso en el catálogo).

Probado con discos virtuales VHDX (nada real en riesgo): bloqueos y simulación sobre los discos reales; DISM acepta la instantánea de C: como origen y la instantánea se crea y se borra sin dejar restos; creación de la tabla de particiones, captura y aplicación de la imagen (los enlaces físicos se conservan), copia de datos y de recuperación, limpieza de letras temporales y de la imagen, y origen intacto.

**No probado:** el último paso (`bcdboot`) y, por tanto, **arrancar con el disco clonado**. En esta máquina `bcdboot` falla también con el Windows real de C: hacia un disco virtual (error de creación del almacén BCD, código 183), así que no se pudo comprobar. El script verifica el resultado y avisa si el arranque no queda bien. Tampoco se ha probado un clonado real de un Windows grande (horas de copia), ni la ventana de selección y la de confirmación con un humano delante.

Antes de usarlo con un cliente: probarlo con un disco sobrante y comprobar que arranca; desconectar el disco antiguo antes del primer arranque con el nuevo; si el origen tenía BitLocker, el destino queda sin cifrar.
- Revisar el repositorio externo `openstd` (indicado al inicio; no se ha hecho un informe aparte).

## Dónde está cada cosa

- Packs regenerados: `E:\Nitrit0_Packs\Nitrit0_Kit_Publico` y `Nitrit0_Kit_Personal`.
- Material de revisión: `E:\Nitrit0_Packs\Para_Revision\Ronda_7_Gemini_Grok\` y `Ronda_8_Gemini_Grok\`.
- Texto de la revisión: `docs\Revision_Externa_Gemini_Grok.md`.

## Ronda 9 (Gemini): lo aplicado y lo comprobado

Aplicado: texto y alineación de «Modo del equipo» (interruptor a la derecha, mismas pistas en las tres filas y texto según haya o no copia instalada); foco inicial de la pregunta de modo en «Ahora no»; «Estado del equipo» con `C:` primero y aviso de espacio al 15 %; «Clonar disco» movido a «Copias y seguridad»; con `--bandeja` la raíz del kit es siempre la copia de Archivos de programa (no una variable de entorno); «SMART detallado» aparece no disponible si falta `smartctl` (instalación pequeña). Clonador: etiqueta vacía en `Format-Volume`, tamaño máximo por partición, limpieza de `\DosDevices\C:` en el registro del destino y reintento + plan B de `bcdboot`.

Probado con discos virtuales: etiqueta vacía (el clonado termina), plan B (`bcdedit` crea un almacén legible que apunta a Windows) y la interfaz con capturas.

**Hallazgo:** en esta máquina `reg load` falla con cualquier archivo («nombre de archivo demasiado largo»), igual que `bcdboot` al crear su almacén. Es un problema de este Windows (cargar registros nuevos), no del clonador. Por eso: la limpieza de `MountedDevices` solo está probada en su rama de aviso (no pudo cargar el registro y lo dice); su rama correcta, y el arranque real con el disco clonado, siguen **sin probar**. El BCD creado con el plan B es mínimo: hay que comprobar que arranca.

## Ronda 10 (Gemini) y los tres trabajos siguientes

**Correcciones de Gemini aplicadas:** ficha de drivers (fecha del driver blindada, consulta al Catálogo también para ACPI y HID, Bluetooth solo «genérico» si lo dice su nombre) y clonador (`nx OptIn` y `locale` en el BCD manual, borrado también de la letra temporal en `MountedDevices`, descarga final del registro en el `finally`). Dos de sus sugerencias se adaptaron: el patrón ACPI usa fabricantes de letras, no hexadecimal, y «Actualizador»/«Componentes» no se pueden pasar a `script` porque son bibliotecas de funciones con ventana propia.

**1. Catálogo propio.** `Scripts\Catalogo_Kit.ps1` es ahora la fuente única del catálogo (antes estaba dentro de `Lanzador.ps1`). Lo cargan el lanzador, `Exportar_Catalogo.ps1` y `Validar_Kit.ps1`. Comprobado: el JSON exportado es idéntico (119 elementos, 22 soluciones) y el lanzador clásico sigue abriendo. **El lanzador aún no se puede retirar**: «Actualizar herramientas» y «Componentes» solo existen en él y la app los marca como no soportados.

**2. «Limpiar almacén de drivers»** (`Limpiar_Almacen_Drivers.ps1`, peligroso). Solo propone paquetes `oemNN.inf` de terceros que ningún dispositivo usa; las versiones antiguas ya sustituidas vienen marcadas y las «sin dispositivo» no. Excluye los de Windows, los de arranque y las clases Extension, impresora y firmware (comprobado con datos reales que si no se proponían paquetes de audio que sí se usan). Antes de borrar: punto de restauración y copia de cada paquete; se borra con `pnputil /delete-driver` sin `/force`. Probado: análisis real en este equipo (105 paquetes de terceros: 30 en uso, 41 protegidos, 15 versiones antiguas de unos 288 MB y 19 sin dispositivo de unos 59 MB) y la copia de un paquete. **No probado el borrado** (no se ejecutó en este equipo).

**3. Fase 2 de drivers** (`Instalar_Driver_Catalogo.ps1`, peligroso). Busca el driver de un dispositivo en el Catálogo de Microsoft Update por Hardware ID, enseña las opciones para tu Windows, descarga del servidor de Microsoft (solo `windowsupdate.com`, `delivery.mp.microsoft.com` o `download.microsoft.com`), comprueba que cada catálogo `.cat` lleva firma válida de Microsoft, crea un punto de restauración y, con tu confirmación, instala con `pnputil`. Probado de verdad: búsqueda de varios dispositivos y descarga, descompresión y verificación de firma de un driver real de Intel (377 KB) sin instalarlo. **No probado:** la instalación con `pnputil`, ni las ventanas de elegir dispositivo y de confirmar. El Catálogo no tiene API oficial: se lee su web, que puede cambiar, y no se han revisado sus condiciones de uso para consultas automáticas.
