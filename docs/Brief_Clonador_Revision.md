# Revisión del clonador de discos de Nitrit0 (brief para otra IA)

## Contexto
Nitrit0 Kit es el kit portátil (pendrive) de un técnico de soporte informático que trabaja en equipos de clientes. Todo está en español y se ejecuta con **Windows PowerShell 5.1** (nunca pwsh) y Electron. El clonador es una herramienta **solo del pack personal** del técnico (el pack público no la lleva, porque borra un disco entero).

Hay una app Electron independiente, `Nitrit0_Clonador.exe` (pide administrador), con la interfaz integrada en una sola pantalla (selector de origen/destino, carpeta de la imagen temporal, «Simular», «Clonar de verdad…» con confirmación escrita, registro en vivo, cancelar). La app **no tiene lógica de borrado propia**: valida los parámetros y llama a `Clonar_Disco.ps1`, comprobando antes su huella SHA-256 en un manifiesto de integridad. El script hace todo el trabajo.

## Qué hace hoy el script (resumen fiel del código incluido abajo)
- Solo clona discos **GPT/UEFI** con un Windows en una partición con letra. Rechaza MBR/BIOS y discos dinámicos.
- Por defecto **solo simula** y enseña el plan. Para ejecutar hay que escribir `BORRAR DISCO <n>` y el destino se vuelve a comprobar (número, tamaño, nombre y serie) justo antes de tocarlo.
- Bloquea como destino el disco del Windows en marcha y el disco del kit. Avisa si el origen es el Windows en marcha (copia desde instantánea VSS).
- Recrea la tabla de particiones en el destino (EFI mínimo 260 MB, MSR, Windows, Recuperación, datos NTFS). La partición de Windows ocupa lo que quede; se exige que quepa lo usado + 15 %. Permite destino **más pequeño** que el origen.
- Copia Windows con **DISM** (`Capture-Image` a un .wim temporal en OTRO disco con sitio libre y `Apply-Image /Verify`), no copia de archivos. Los datos y la recuperación van con **robocopy** `/MIR /COPYALL /B`.
- Limpia del registro del destino las letras de unidad antiguas (`MountedDevices`), deja el arranque con **bcdboot** (con reintento y plan B manual con bcdedit) y **verifica** que existen `ntoskrnl.exe`, `bootmgfw.efi` y un BCD que apunta a `winload`.
- Avisa de BitLocker (el destino queda sin cifrar), de particiones no NTFS o desconocidas que NO se copian, y de que la prueba definitiva es arrancar con el disco nuevo.
- Contrato de salida: 0 bien, 1 error, 2 cancelado.

## Qué NO hace (a propósito o por no haberlo hecho)
MBR/BIOS, discos dinámicos, destino menor que lo usado + 15 %, particiones no NTFS (FAT32/exFAT/ReFS de datos), recuperación de un clonado interrumpido, clonar a un archivo/VHDX, porcentaje real de avance, comprobar la salud (SMART) del origen o el destino, evitar que el equipo se suspenda, ajustar el tamaño de las particiones cuando el destino es MAYOR.

## Lo que te pido
Eres un revisor con experiencia en soporte técnico y en clonado de discos (Macrium, Clonezilla, AOMEI, DISM, VSS). Léelo todo y contesta **en español, de forma concreta y sin relleno**:

1. **Bugs o riesgos de pérdida de datos** que veas en el script o en la app (condiciones de carrera, discos que cambian de número, destino equivocado, instantáneas VSS que no se borran, letras de unidad temporales que se quedan, fallos de robocopy con códigos ≥ 8, etc.). Cita la línea o la función.
2. **Qué falta que un técnico en equipos de clientes echaría de menos.** Lista, ordenada por **valor para el técnico / riesgo de añadirlo**, y para cada punto di si es pequeño, mediano o grande de hacer. Piensa en: salud del disco (SMART) antes de clonar, evitar suspensión, progreso real en %, informe final guardable, soporte MBR/BIOS, partición de datos FAT32/exFAT, crecer la partición de Windows si el destino es mayor, clonar a imagen (.wim/.vhdx) y restaurar, BitLocker (suspender/volver a cifrar), reagentc/WinRE, discos de sector 4Kn, NVMe frente a SATA, arranque tras clonar (drivers de almacenamiento), verificación posterior más profunda, y lo que se te ocurra.
3. **Qué NO añadirías** aunque parezca buena idea, y por qué (complejidad, riesgo, poco uso).
4. **Mejoras de la interfaz** de la app (una sola pantalla; el selector ya es propio, sin ventanas de PowerShell), sobre todo para evitar elegir el disco equivocado.
5. Un **top 5** final de lo que harías primero, con el motivo.

Sé crítico. Si algo del código no lo entiendes o falta contexto, dilo en vez de inventarlo. No des instrucciones para tocar nada fuera del clonador.

---

# Código

Va a continuación: el script completo, el proceso principal de la app y la interfaz.
