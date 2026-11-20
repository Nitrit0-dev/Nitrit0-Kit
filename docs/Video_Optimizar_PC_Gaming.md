# Vídeo «Optimizar un PC gaming con Windows»: tiempos, apps y qué replicar

Fecha: 2026-11-13. Vídeo de ~38 min (créditos y enlace del vídeo no constan en lo pegado). La transcripción es automática y falla con nombres propios; lo que sigue es una **paráfrasis con el minuto de cada tema**, no una copia. El texto íntegro no se versiona (contenido ajeno).

Enlaces revisados: Win11Debloat (Raphire), Win-Debloat-Tools (LeDragoX), PresentMon (Intel), dnsspeedtest.online, MSI Afterburner, guía de XMP/EXPO de G.SKILL y guía de overclock de CPU de Tom's Hardware. **SCSKiller** no sale en el vídeo: se añadió aparte.
Limitaciones de la revisión: la página de MSI devolvió «Access Denied» y la de Intel solo trajo código; de PresentMon y Afterburner hablo por lo que ya se sabe de ellos, a comprobar al implementar.

## Línea de tiempo

| Min | Tema | Qué dice |
|---|---|---|
| 0:00 | Objetivo | Optimizar un PC gaming para más FPS, menos frame times y menos latencia. |
| 0:39 | Avisos | Vídeo largo; cada cambio es responsabilidad de quien lo hace; hay que ser realista: el hardware se vende por algo. |
| 1:27 | Limpieza | Vaciar `%temp%` y `temp` desde Ejecutar. |
| 2:18 | Privacidad | Revisar Configuración > Privacidad y seguridad (voz, diagnóstico, etc.) y accesibilidad (narrador). |
| 2:46 | Punto de restauración | Crear uno antes de tocar nada y cómo restaurarlo (3:37). |
| 4:03 | **Win11Debloat** | Quitar apps incrustadas, telemetría, Copilot, consejos. Modo por defecto o personalizado (5:37); preguntas sí/no; no cerrar la ventana; reiniciar (7:42). |
| 7:48 | **DNS** | `dnsspeedtest.online` mide servidores DNS desde tu ubicación; se mira la columna «average» (8:26). |
| 9:13 | Red | Jugar por cable; poner ese DNS en IPv4 del adaptador (10:03); comprobar con `ping` antes y después (10:31). |
| 11:36 | **DPI y polling rate** | DPI entre 400 y 1600 (no al máximo, por saltos de píxel). Polling 1000–2000 Hz: 125 Hz se nota lento y 8000 Hz carga la CPU (13:13). |
| 14:42 | **Win-Debloat-Tools** | Descargar el zip, abrir PowerShell como administrador, lanzar la versión GUI y pulsar «Apply Tweaks» (18:14), o la versión CLI sin preguntas (18:38). Recomienda abrir el menú y elegir. |
| 20:19 | **Cuello de botella (PresentMon)** | Medir CPU, GPU, frame times y FPS al 1 % dentro del juego (21:03). GPU ~80 % y CPU ~50 % = sin cuello (23:13). CPU al 95–100 % en un juego que depende de CPU = cuello (23:52). Un tope de CPU al 75 % con GPU baja también es cuello (26:39). Explica juegos «CPU-bound» y «GPU-bound» (24:53). |
| 27:10 | Overclock de CPU | No lo guía: depende del modelo; deja un enlace (Tom's Hardware). |
| 27:56 | **MSI Afterburner** | Solo toca límite de potencia (al máximo), reloj del núcleo en pasos de +100/+200 y ventilador; memoria a 0; nunca voltaje. Si el juego se ve con cuadros verdes, bajar. Guardar perfil (30:24). |
| 31:35 | **XMP / EXPO** | Activar el perfil de la RAM en la BIOS (F2/Supr), elegir el de más MHz; si no arranca, borrar CMOS (33:57). |
| 34:49 | Windows 11 LTSC | Recomienda el Windows oficial sin apps (de pago), nunca ISO modificadas por terceros. |
| 36:33 | Actualizar | Pasar Windows Update tras debloat por si se quitó algo básico. |
| 37:05 | Cierre | Bajar ajustes del juego; las ganancias reales suelen ser de 10–60 FPS y sobre todo estabilidad. |

## Ya lo tenemos

| En el vídeo | En el kit |
|---|---|
| Vaciar temporales | «Limpiar temporales» y «Puesta a punto rápida» |
| Privacidad, telemetría, tips, Bing en la búsqueda | «Optimizador personal» (modo Privacidad) |
| Copilot, Recall, IA | «Quitar IA de Windows» |
| Apps incrustadas de Windows | «Quitar bloatware de Windows 11» (con casillas) |
| Xbox Game Bar y grabación | Modo Juego del Optimizador (GameDVR fuera) |
| Punto de restauración y volver atrás | «Punto de restauración» y «Deshacer cambios» (respaldo de cada cambio) |
| Juego: plan de energía, HAGS, prioridad multimedia | Modo Juego y perfil Juego (Fluidez + Juego + Energía + Red) |
| Ratón sin aceleración, red multimedia sin límite | Modo Red del Optimizador |
| Menú clásico de clic derecho, retraso de apps de inicio | «Personalizar Windows 11» y Optimizador |
| XMP/EXPO | «Asesor de BIOS» y aviso en «Cuello de botella» («RAM por debajo de su velocidad») |
| Cuello de botella CPU/GPU | «Cuello de botella» con perfil Juegos y monitor en vivo |
| Ver CPU, GPU, RAM, VRAM | CPU-Z, GPU-Z, HWiNFO y «Uso de VRAM» |
| Ping, jitter y DNS | «Latencia de red» (compara Cloudflare, Google y Quad9) |
| Actualizar Windows | «Actualizar Windows» |

## Qué replicar (ordenado por valor)

1. **«DNS más rápido»** (alta, barato). Hoy el kit compara solo 3 DNS y fija Cloudflare o Google a mano. Replicar la idea del vídeo: medir 8–12 servidores con consultas reales (`Resolve-DnsName -Server`, varias muestras y varios dominios, mediana), proponer el mejor, aplicarlo con el respaldo que ya existe (`Set-DnsSeguro`) y enseñar el antes y el después. No se copia nada de dnsspeedtest.online: es una web de terceros que además mide DNS-sobre-HTTPS desde el navegador.
2. **Medidor de fotogramas** (alta). El monitor en vivo da CPU y GPU, pero no frame times ni el 1 % bajo, que es lo que el vídeo usa para decidir. Opción: añadir PresentMon (herramienta de consola, portable, de Intel) a `Apps\` y un script que mide 60 s de un juego y devuelve FPS medios, 1 % bajo, el peor frame time y quién limita. Antes de escribirlo, comprobar su licencia y sus parámetros actuales en el repositorio oficial.
3. **SCSKiller** (media). Precompila los shaders del juego en la caché del driver (NVIDIA/AMD, DX12 y DX11 en NVIDIA) para evitar tirones. Es GPL-3.0, instalable o portable. Cautelas: las versiones aún no van firmadas (SmartScreen avisa y Smart App Control las bloquea), y con juegos con anticheat solo debe leer, no inyectar. Encaja en `Apps\GPU` como herramienta para clientes gamers; se descargaría solo con tu visto bueno.
4. **Windows Update más manso** (media). De Win11Debloat no tenemos: no recibir drivers por Windows Update, no reiniciar solo con sesión abierta, desactivar la optimización de entrega. Sería un modo nuevo del Optimizador, con respaldo.
5. **Retoques pequeños** (baja): red apagada durante el modo de espera moderno (Modern Standby) en portátiles, Storage Sense, optimizaciones de pantalla completa; y texto de ayuda en «Asesor de BIOS» con «si no arranca tras activar XMP, borra el CMOS» y en el modo Red con «ratón a 1000 Hz, DPI 400–1600».
6. **Receta «Equipo gaming»** (baja, solo orquestación): combinar lo que ya existe en el orden del vídeo (punto de restauración, privacidad y bloatware, DNS, red, comprobar XMP, medir cuello, shaders). Es un combo, no código nuevo.

## Lo que no replicamos

- **MSI Afterburner**: software propietario sin redistribución libre; se queda como recomendación. Subir reloj y límite de potencia también puede dar inestabilidad en el equipo de un cliente: solo con su permiso y sin tocar voltajes.
- **Overclock de CPU**: depende de placa y modelo, y el propio vídeo lo descarta.
- **Windows LTSC**: licencia de pago, y el vídeo mismo evita decir dónde conseguirlo.
- **Polling rate y DPI**: Windows no los lee; los cambia el software del fabricante del ratón.
- **Win-Debloat-Tools**: el repositorio está archivado y su modo CLI aplica todo sin preguntar (servicios, características, tareas). Para equipos de clientes es más arriesgado que nuestros scripts, que respaldan cada cambio; solo se toman ideas.
