# Análisis: programas de diagnóstico del artículo de ProfesionalReview y plan de drivers

Fecha: 2026-11-15. Fuente: https://www.profesionalreview.com/guias/mejores-programas-de-diagnostico-pc/ (los datos de la página dicen que se publicó en 2022, así que parte puede estar anticuada).

## 1. Los 14 programas del artículo frente al kit

| Programa del artículo | Qué es | ¿Está en el kit? | Veredicto |
|---|---|---|---|
| **Speccy** (Piriform) | Ficha de hardware y software del equipo | No tal cual; lo cubren `Inventario_Equipo.ps1`, HWiNFO, CPU-Z, GPU-Z y los sensores de LibreHardwareMonitor | **Replicar con lo nuestro** (ver sección 2). Es software propietario de Piriform: no se puede redistribuir en el kit |
| AIDA64 / Hardinfo | Información y sensores muy detallados | HWiNFO + LibreHardwareMonitor | Nada que añadir (AIDA64 es de pago) |
| SysInspector (ESET) | Instantánea del sistema para análisis | Autoruns + Process Explorer cubren lo útil | No añadir |
| CPU-Z / CPU-X | Datos de CPU y memoria | CPU-Z | Ya está |
| Intel Processor Diagnostic Tool | Prueba de estrés y verificación de CPU Intel | OCCT y Prime95 | Opcional: ofrecerlo como descarga oficial en `Instaladores\Fabricantes`. Baja prioridad |
| WiFi Analyzer | Canales y señal de redes Wi-Fi | Hay «Wi-Fi y claves», pero no análisis de canales | **Replicar**: script propio con `netsh wlan show networks mode=bssid` (canales, señal, seguridad). Pequeño |
| Angry IP Scanner | Escáner de IP, latencia y puertos de la red local | No | **Replicar en pequeño**: barrido de ping + tabla ARP + nombre + puertos habituales con PowerShell. La alternativa (integrarlo) exige Java |
| CrystalDiskInfo | Estado SMART de discos | Sí | Ya está |
| CCleaner | Limpieza y registro | «Limpiar temporales», «Limpiar registro huérfano» | No integrar (propietario). Ya tenemos lo útil |
| WinDirStat | Qué ocupa el disco | Sí (más WizTree) | Ya está |
| JScreenFix | Intenta reparar píxeles atascados (web) | MonTest y Monitor Test Utility | Opcional: ventana propia con ruido de color. Baja prioridad |
| Malwarebytes | Antimalware | KVRT y AdwCleaner | No añadir (comercial) |
| Memtest86+ | Prueba de RAM | memtest86-usb, TestMem5, MemTest64 | Ya está |
| FurMark | Estrés de GPU | Sí | Ya está |

**Conclusión:** el kit ya cubre 9 de los 14. El artículo aporta poco aparte de la idea de Speccy y dos herramientas de red pequeñas (análisis Wi-Fi y escáner de la red local). La parte valiosa es la de drivers.

## 2. «Ficha del equipo» propia (lo que aporta Speccy)

Lo que hace Speccy se puede replicar con CIM/WMI y con la LibreHardwareMonitorLib que ya llevamos:
- Placa, BIOS, CPU, memoria (módulos), discos, gráfica, audio, red, pantalla y batería, con temperaturas si hay sensores.
- **Lo que importa para drivers:** para cada dispositivo, su Hardware ID (`PCI\VEN_xxxx&DEV_xxxx`, `USB\VID_xxxx&PID_xxxx`), el driver instalado (proveedor, versión, fecha) y si hay error. `Auditoria_Drivers_Huerfanos.ps1` ya lee los dispositivos con fallo y su Hardware ID; habría que ampliarlo a todos los dispositivos.
- Para traducir los números a nombres legibles (fabricante y chip) existen las bases abiertas `pci.ids` y `usb.ids` (texto, pequeñas). Falta verificar su licencia antes de incluirlas.

## 3. Cómo encontrar el driver concreto de cada dispositivo

Fuentes, de más a menos fiable:

1. **Windows Update / Catálogo de Microsoft Update** (oficial, firmado por Microsoft). El kit ya instala drivers con PSWindowsUpdate. Mejora posible: buscar por Hardware ID en el Catálogo de Microsoft Update y descargar el `.cab` de ese dispositivo (no hay API oficial; se haría leyendo la web, que puede cambiar; hay que revisar sus condiciones de uso).
2. **Catálogos de los fabricantes** (HP, Lenovo, Dell, ASUS): ya cubiertos en `Reparar_Drivers_OEM.ps1` para HP y Lenovo; el resto abre la herramienta oficial.
3. **Fabricantes de chips** (NVIDIA, AMD, Intel, Realtek, Qualcomm, MediaTek): sitios oficiales. NVCleanstall y DDU ya están en el kit para gráficas.
4. **Biblioteca comunitaria: Snappy Driver Installer Origin (SDIO).** Lo comprobado en su web oficial y en SourceForge:
   - Licencia **GPLv3** (según SourceForge); gratuito y de código abierto. La redistribución junto a otro programa implica las obligaciones habituales del copyleft: habría que revisarlas antes de incluirlo.
   - **Portable**, funciona **sin conexión**, con los paquetes de drivers por separado (torrent o descarga). El autor habla de más de 70 GB de drivers.
   - Se puede automatizar con su motor de scripts propio.
   - El propio autor avisa de que su algoritmo de selección **no es infalible** y de que no se cambie un driver que ya funciona.
   - **Sin confirmar:** licencia y condiciones de redistribución de los *paquetes* de drivers, tamaño del programa, parámetros de línea de órdenes y modo «lite» solo con índices. Hay que descargar el zip oficial y leer su documentación (la descarga necesita tu visto bueno).
5. **Evitar:** DriverPack Solution, Driver Booster, Driver Easy y similares (empaquetan programas no deseados o son de pago, y los drivers no están garantizados). Es una valoración mía, sin haber leído su licencia aquí.

**Caso donde más aporta una biblioteca offline:** el equipo del cliente sin red (falta el driver de Ethernet o Wi-Fi). Un paquete pequeño de drivers de red en el pendrive permite arrancar la descarga del resto.

## 4. Propuesta por fases (de menos a más riesgo)

- **Fase 1 (sin dependencias, 1 script):** ampliar la auditoría a una **ficha de drivers** de todos los dispositivos (nombre, Hardware ID, proveedor, versión, fecha, error) y generar un informe con un **enlace al Catálogo de Microsoft Update por cada Hardware ID** sin driver o anticuado. El técnico decide y descarga. No instala nada.
  - **HECHA (2026-11-15):** `Mantenimiento\Ficha_Drivers.ps1` («Ficha de drivers», categoría Diagnóstico, solo lee). Probada en este equipo: 100 dispositivos, 0 con problema, 0 genéricos, 1 antiguo. **No probada** con dispositivos con problema o sin driver (aquí no hay ninguno), así que la rama de «Problema» y el enlace al Catálogo de Microsoft solo están comprobados leyendo el código.
- **Fase 2:** descargar del Catálogo de Microsoft el driver de un dispositivo concreto, **comprobar la firma digital**, crear un punto de restauración y pedir confirmación antes de instalar (reutilizando las funciones de `Reparar_Drivers_OEM.ps1`).
- **Fase 3 (opcional):** integrar SDIO como biblioteca **sin conexión**, instalada a parte (nunca dentro del pack público por tamaño y licencias), con los paquetes en otro disco; el kit solo aportaría la detección y la guía.
- **Fase 4 (opcional):** análisis Wi-Fi y escáner de red local.

## 5. Qué no está comprobado

- Todo lo del artículo se ha leído una vez (parafraseado por un agente de lectura); su fecha de 2022 hace que algunas descripciones estén anticuadas.
- Licencia y redistribución de los paquetes de SDIO, su línea de órdenes y su tamaño real: sin confirmar.
- Condiciones de uso de la web del Catálogo de Microsoft Update para consultas automáticas: sin revisar.
- Licencias de `pci.ids` y `usb.ids`: sin revisar.
- No se ha descargado nada.
