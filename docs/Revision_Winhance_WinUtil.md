# Winhance y WinUtil frente a Nitrit0 Kit: qué nos sirve, sobre todo de interfaz

Fecha: 2026-11-14. Fuentes: repositorios públicos (API de GitHub), el vídeo de Tutos PC (ver `Video_Winhance_Resumen.md`) y lectura mecánica de ficheros de Winhance hecha con opencode (modelo gratis) y **verificada por muestreo**: de 15 nombres de clases que citaba, 14 existen en el código; uno (`ReviewModeFilter`) no, aunque el filtro «mostrar solo cambios» sí existe con otro nombre. No he ejecutado ninguna de las dos herramientas.

## 1. Qué son

| | Winhance | WinUtil (Chris Titus) |
|---|---|---|
| Repositorio | memstechtips/Winhance | ChristitusTech/winutil |
| Tamaño y actividad | 14,9 mil estrellas, push del 14-nov-2026, versión 26.06.12 | 66 mil estrellas, push del 14-nov-2026 |
| Tecnología | App C# (WinUI 3) con instalador y versión portable | Script PowerShell con interfaz WPF, se lanza con `irm … \| iex` |
| Licencia | **PolyForm Shield 1.0.0**: se puede usar y modificar, **no** redistribuir como producto que compita con él | MIT |
| Secciones | Software y apps, Optimizar, Personalizar, Herramientas avanzadas (ISO y autounattend), Ajustes | Instalar apps (239), Tweaks (69), Características (33), Arreglos, Actualizaciones; DNS |
| Windows 10 | Sí | Según comentarios del vídeo, ya no (sin comprobar) |

**Licencia de Winhance:** conviene no copiar su código, ni sus ficheros de definiciones, ni sus textos. Las claves de registro y directivas de Microsoft son hechos públicos y se pueden usar documentándolas desde Microsoft; las ideas de interfaz no están protegidas. Un detalle a revisar: `Scripts\Mantenimiento\Quitar_IA_Windows.ps1` dice en un comentario que sus directivas de Edge están «tomadas de Winhance». Son nombres de directivas de Edge documentados por Microsoft, riesgo bajo, pero lo prudente es contrastarlas con la documentación de Microsoft y cambiar ese comentario. **Hecho el 15-nov-2026:** el comentario remite a la documentación de Microsoft Edge.

**¿Ya lo habíamos revisado?** Solo Winhance y de forma puntual (esas directivas de Edge). No hay ninguna revisión de WinUtil en `docs\` ni en la memoria del proyecto; esta es la primera, y la de WinUtil es superficial (estructura y tipos de ajuste, sin leer su código).

## 2. Cómo se compara con lo que ya tenemos

Nitrit0 Kit es un kit de soporte: diagnóstico, reparación, herramientas portables y combos de mantenimiento, con deshacer, plan con confirmación y lista blanca de ejecución. Winhance y WinUtil son más de «ajustar Windows a tu gusto». Se solapan en:

| Tema | Nosotros | Winhance / WinUtil |
|---|---|---|
| Quitar bloatware / IA | `Desinstalar_Bloatware_Win11`, `Quitar_IA_Windows` | Lista de apps con estado real y aviso de dependencias; scripts que lo vuelven a quitar en cada inicio (**no recomendable**, ver 4) |
| Optimización | `Optimizar_Rendimiento`, `Perfil_Baja_Latencia`, `Personalizar_Windows11`, `Control_Energia`, `Gestion_Memoria_RAM` | Cientos de ajustes con valor recomendado/predeterminado, leyendo el estado actual |
| Deshacer | `Start-OperacionSegura` + `Deshacer_Cambios` (por sesión, solo los scripts que usan `Set-ValorSeguro`: 4 de 55) | Copia de la configuración al primer inicio, restaurar, volver a valores de fábrica, punto de restauración |
| Instalar programas | `Instalador_Basico` (12 apps, con firma/huella) | 239 apps con winget |
| DNS | `DNS_Mas_Rapido` (mide 8 DNS) | Lista fija de perfiles DNS |
| Características de Windows | Casi nada (solo algo en `Quitar_IA_Windows`) | .NET, WSL, Hyper-V, Sandbox, etc. |
| ISO a medida | Solo descargador de ISO y Ventoy | Crear ISO con autounattend |

## 3. Ideas de interfaz que valen la pena (de más a menos útil para nosotros)

Todas adaptadas a nuestra app (tarjetas, plan de revisión y combos), sin copiar nada de su código.

1. **Estado actual en cada ajuste, con etiqueta «Recomendado / Predeterminado / Personalizado».** Hoy nuestros scripts aplican un cambio fijo; la persona no ve cómo está el equipo antes. Un modo «solo leer» por herramienta que devuelva el valor actual permitiría pintar la tarjeta y decir «ya está aplicado» o «tu valor es otro». Empezaría por `Personalizar_Windows11`, `Quitar_IA_Windows`, `Optimizar_Rendimiento` y `Control_Energia`. Winhance tiene además un estado «Personalizado» cuando el valor no coincide con ninguna opción: evita afirmar un estado falso.
2. **Detalles técnicos plegables** (ruta del registro, valor actual y valor previo). Ya guardamos `Ruta`, `Nombre` y `Previo` en `cambios.json` con `Set-ValorSeguro`; falta mostrarlo. Encaja con el «Modo técnico».
3. **Perfiles exportables e importables con revisión.** Para el técnico que prepara varios equipos: guardar un perfil (qué combos y herramientas aplicar) y, al importarlo, revisarlo paso a paso (aceptar o rechazar cada uno, contador «X de Y revisados», opción de saltar la revisión si es de confianza). Nuestra pantalla de plan de la revisión automática ya es la mitad. **Condición de seguridad:** el perfil solo puede contener identificadores del catálogo y parámetros validados, nunca órdenes ni rutas; si no, rompe la lista blanca.
4. **Aviso en portátiles.** Un comentario del vídeo (sin comprobar) dice que Winhance desactiva la suspensión al cerrar la tapa y el inicio con huella o reconocimiento facial. Sea cierto o no, es una advertencia razonable: antes de ajustes de energía o privacidad, detectar portátil (batería) y avisar. `Perfil_Baja_Latencia` y `Personalizar_Windows11` ya mencionan portátil; habría que revisar si el aviso llega a la interfaz.
5. **Filtro por versión de Windows.** Marcar en el catálogo desde qué build vale cada ajuste y ocultar lo que no aplica. Winhance además ignora al importar lo que no corresponde al Windows de destino.
6. **Avisos con jerarquía.** Un aviso concreto («esto desactiva X») no debe quedar tapado por el genérico («requiere reinicio»).
7. **Botones «Poner recomendado» / «Poner predeterminado» por ajuste** y un filtro «mostrar solo lo que cambia» en el plan. Necesitan los valores predeterminados de cada ajuste, que hoy no tenemos recogidos.
8. **Menú «Ver»** (detalles técnicos, solo cambios) y un contador de resumen en el diagnóstico («N recomendados, N personalizados»). Es retoque visual.

## 4. Lo que no recomiendo copiar

- **Scripts que se ejecutan en cada inicio para volver a quitar apps.** Es persistencia en el equipo del cliente, justo lo que las revisiones de Grok y Gemini nos han hecho eliminar. Si algún día se quiere, solo como opción explícita y con aviso, nunca en el pack público.
- **Ajustes que bajan la seguridad como «recomendados».** Según el análisis, Winhance marca como recomendados el UAC en «No notificar», desactivar Smart App Control, la integridad de memoria (HVCI) y VBS, o el modo desarrollador. Para un pack que va a amigos no debemos replicarlo.
- **ISO desatendida que omite requisitos de hardware y la cuenta Microsoft.** Es una herramienta grande, de uso muy distinto al soporte diario, con consecuencias para el equipo y un tramo de zona gris con las licencias. No ahora.
- **Su catálogo de 239 apps.** Más superficie de ataque y más licencias que revisar; mejor ampliar `Instalador_Basico` con pocas apps y verificadas.

## 5. Contenido (no interfaz) que podría inspirar nuevos ajustes

Siempre reversibles con `Set-ValorSeguro`, de bajo riesgo y documentados por Microsoft, y con valores recomendados por nosotros:

- **Rendimiento y juegos:** Game Mode, Xbox Game DVR/Game Bar, aceleración de pointer (precisión del puntero), GPU scheduling por hardware, optimizaciones en ventana.
- **Windows Update:** descarga por conexión medida, drivers por Windows Update, optimización de entrega (P2P), el valor de «solo actualizaciones de seguridad» que recomienda el vídeo. Necesitan aviso de que no es lo mismo en un equipo ajeno.
- **Barra de tareas:** Copilot, Widgets, Meet Now, alineación; es lo más demandado por los clientes (poco riesgo).
- **Características de Windows** (de WinUtil): activar .NET 3.5 y Windows Sandbox son tareas de soporte muy frecuentes y hoy no tenemos herramienta.
- **DNS:** nuestra herramienta ya mide 8; WinUtil tiene perfiles con filtro de malware que podríamos ofrecer tras la medición.

## 6. Por dónde empezaría

1. Estado actual y etiqueta «Predeterminado / Personalizado» en 3 herramientas de ajustes (la idea 1).
2. Detalles técnicos plegables (idea 2), que aprovecha lo que ya guardamos.
3. Aviso de portátil en la interfaz (idea 4).
4. Herramienta «Características de Windows» (.NET 3.5, Sandbox, WSL), con deshacer.
5. Perfiles con revisión (idea 3), solo después de lo anterior y con la validación contra el catálogo.

Todo esto toca la interfaz, que según `CLAUDE.md` está «cerrada con el usuario»: no se hace sin que lo pidas.
