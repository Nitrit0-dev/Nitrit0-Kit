# Apps del vídeo de un técnico con 25 años de experiencia (comparación con el kit)

Fuente: vídeo https://youtu.be/Q5aJrqFGnao, en el que un técnico enseña su carpeta de programas de servicio técnico. La transcripción es automática y falla con los nombres de programas; lo que sigue está contrastado por contexto y es una paráfrasis, no una copia. La transcripción se guardó solo en local (no se versiona: es contenido ajeno).

## Ya está en el kit (no hay que añadir nada)
| En el vídeo | En el kit |
|---|---|
| CPU-Z, HWMonitor | Sí, en `Apps\CPU` y `Apps\HW Info` (HWiNFO cubre además lo que hacía Everest/AIDA64) |
| FurMark | Sí (estrés de la gráfica); CPU: Prime95 y OCCT cubren lo que hacía LinX |
| AdwCleaner | Sí (y KVRT) |
| Autoruns | Sí |
| Comprobador de monitores, test de teclado | Sí (MonTest, Monitor Test, Test de teclado) |
| Complete Internet Repair | «Reparar red» (vacía DNS, renueva IP, restablece Winsock y TCP/IP) |
| Vaciar cola de impresión | «Reparar impresoras» |
| Driver Magician (copia de drivers) | «Copia de drivers» |
| DoNotSpy10 (privacidad) | «Optimizador personal» (modo Privacidad) y «Quitar IA de Windows» |
| Victoria, HD Tune | CrystalDiskInfo, CrystalDiskMark y HDDScan |
| BlueScreenView | «Pantallazos y eventos» |
| BatteryInfoView | «Batería» (informe de Windows) |
| Rufus | El programa está en `Apps\Instaladores\Utilidades`, pero **no tiene entrada en el catálogo** |

## Faltan y merecen la pena (gratis o libres, pequeños)
1. **TestDisk y PhotoRec** (GPL): recuperar particiones y archivos borrados. El kit no tiene ninguna herramienta de recuperación. Prioridad alta.
2. **H2testw**: comprueba la capacidad real de un pendrive o tarjeta (los falsos son habituales). Prioridad media; se podría cubrir con un script propio en «Salud del pendrive».
3. **Process Explorer** (Sysinternals): junto a Autoruns, para investigar procesos sospechosos. Prioridad media.
4. **USBDeview** (NirSoft): dispositivos USB conectados y antiguos, útil en conflictos de controladores USB. Baja.
5. **ChipGenius**: chip y fabricante real de un pendrive. Baja (varios antivirus lo marcan como sospechoso).
6. **BleachBit** (GPL): limpiador más profundo que «Limpiar temporales». Baja: ya hay limpieza propia.
7. **Rufus**: dar de alta la entrada en el catálogo (el ejecutable ya está).

## Hay huecos de categoría, no de programa
- **Gestor de particiones** (el vídeo usa AOMEI y MiniTool): el kit solo abre «Discos (Windows)». Las opciones gratuitas son de licencia propietaria con límites; conviene valorarlo aparte.
- **Clonación de discos** (HDClone): sin equivalente. Opciones libres: Clonezilla (se arranca desde un USB aparte).
- **Hiren's BootCD**: es un sistema para arrancar desde USB, no una app portable; el propio vídeo lo trata aparte.

## No se recomienda añadirlos
Herramientas de pendrives de hace 15 años (HP USB Format Tool, JetFlash, formato de bajo nivel, restauración de capacidad), utilidades de Windows XP/7/Vista, Deep Freeze, ElcomSoft (comercial), HD Regenerator (de pago), ZHPCleaner (exige bajar siempre la última versión y ya hay AdwCleaner y KVRT), SPD (voltaje de memorias, muy específico) y la herramienta de inyección de controladores de almacenamiento (DISM hace lo mismo).

## Precauciones
- Bajarlas solo de la web oficial de cada una, nunca de mirrors ni de versiones «portables» de terceros. El propio técnico avisa de falsos positivos y de no usar programas crackeados.
- Descargar es una acción que pide el visto bueno del usuario: ninguna se ha descargado.
- Las de NirSoft, Sysinternals y TestDisk no necesitan instalación; encajan en `Apps\`.

## Actualización: lo que ya se ha añadido
TestDisk y PhotoRec, Process Explorer y USBDeview se descargaron de sus webs oficiales (2026-11-13) y están en el catálogo; Rufus tiene ya entrada. Pendientes: H2testw, ChipGenius, BleachBit y un gestor de particiones.
