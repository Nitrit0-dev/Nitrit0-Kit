# Dirección visual de la app Nitrit0

Fuente: el tema que ya usa el lanzador (`Scripts\Tema.ps1`), lo que pidió Juan (app amigable, una sola base visual, filtros y favoritos como en el lanzador, que no parezca hecha por IA) y el uso real: un técnico con el pendrive en el equipo de un cliente, a menudo con luz de taller y prisa.

Lectura: app de taller para un técnico, en lenguaje de banco de trabajo, dial ENERGY 1 / RHYTHM 2 / MOTION 1.

## Decisiones (cada una con su porqué)
- **Oscuro por defecto, claro disponible.** El kit ya era oscuro y se usa en equipos ajenos, a menudo con poca luz. El claro existe y se ha comprobado (R-34).
- **Neutros cálidos casi negros, un solo acento cian (#22D3EE, el del kit).** El acento solo marca lo seleccionado, la acción principal y el foco. Estados: verde, ámbar y rojo, solo para estados reales.
- **IBM Plex Sans y Plex Mono, empaquetadas.** Carácter de manual de servicio e instrumento de medida, humanista y legible con tildes; Plex Mono con números tabulares para datos (rutas, GB, tiempos). No dependen de que el equipo del cliente las tenga.
- **Listas, no mosaicos.** Hay ~100 herramientas: una fila por herramienta con su icono real, nombre, descripción y acción. Se escanea más rápido que una rejilla de tarjetas iguales.
- **Inicio parte de la decisión del técnico:** qué le pasa a este equipo y qué hago ahora. Sin anillos ni tarjetas de métricas.
- **Radios:** 6 px controles, 10 px superficies, sin píldoras. **Sombras:** ninguna salvo diálogos.
- **Movimiento:** un cambio de página corto (160 ms) y estados al pasar el ratón. Respeta «reducir movimiento».
- **Iconos:** los de cada programa (extraídos del .exe) en las herramientas; Lucide solo en la navegación, trazo 1.75 uniforme.

## Reglas de la casa
- Ninguna pantalla trae color, fuente ni espaciado propios: todo sale de `diseno/tokens.css`.
- Sin etiquetas pequeñas en mayúsculas sobre los títulos, sin insignias decorativas, sin franjas de color a un lado.
- Todo control hace algo o no existe; lo que aún no está en la app lo dice con un texto claro.
- Los textos nombran la acción («Analizar espacio en disco»), no «Iniciar» ni «Ejecutar». En las listas densas de herramientas el botón dice «Abrir» o «Ejecutar» y su nombre accesible lleva el de la herramienta («Ejecutar Analizar espacio en disco»).

## Modo sencillo (pensado para una persona mayor o un niño)
Referencia: VoiceStudio (debpalash), cuya portada ofrece pocas tareas grandes en palabras llanas y cada una abre su propio espacio con una acción principal y lo avanzado plegado en «Optional details».
- **Una sola pantalla, sin menú.** El modo sencillo oculta la barra lateral; el técnico entra con «Modo técnico» (abajo a la derecha) y vuelve con «Modo sencillo». Se recuerda en `Datos\Ajustes.json` (`Modo`) y por defecto es el sencillo.
- **Se abre según lo que eliges.** La portada pregunta «¿Qué le pasa a tu ordenador?» con seis opciones en lenguaje de calle; al elegir una se despliega debajo lo que se va a hacer, cuánto tarda y el botón «Empezar». Una sola opción abierta a la vez.
- **Lo avanzado, plegado.** «Más opciones» (nombre del cliente, actualizaciones) y «Detalles técnicos» van en desplegables cerrados. En modo técnico abren solos.
- **Letra grande y poco que leer:** 17 px de base, títulos de 32 px, botones de 44 px como mínimo, frases cortas en primera persona («Estoy revisando tu ordenador», «Esto es lo que he hecho»). Sin siglas ni nombres de pruebas.
- **El resultado se lee de un vistazo:** un icono grande con tono (correcto o aviso), una frase, lo que se hizo y, si hace falta, un botón grande «Reiniciar ahora».
- Iconos: Lucide también en las opciones de la portada (reconocer rápido el tipo de problema), sin fondo ni recuadro.


## Modo técnico: espacios de trabajo con pestañas (inspirado en VoiceStudio)
- El menú lateral pasa de ocho entradas sueltas a cuatro espacios: Arreglar mi equipo, Estado del equipo, Diagnóstico y Herramientas (la crítica de diseño ponía el límite en cinco).
- Dentro de un espacio, lo relacionado va en **pestañas** (control segmentado arriba a la izquierda): Diagnóstico = Diagnóstico | Qué lo frena; Herramientas = Comprobar | Preparar equipo | Reparar y mantener | Kit | Combos, con su cuenta. «Cuello de botella» se llama ahora «Qué lo frena». Son navegación (un grupo de botones con la actual marcada con `aria-current`), no un `tablist`: no hay un panel asociado por pestaña.
- **Combos:** cuatro paquetes (Puesta a punto, Reparar Windows, Internet y protección, Mantenimiento completo) que rellenan una lista de pasos sueltos con casillas; una barra fija abajo dice cuántos pasos y cuánto tiempo y ejecuta. Los pasos se aplican en el orden del script, no en el que se marquen.
- **Modo sencillo ampliado:** arriba, «Cómo está tu ordenador ahora» (recomendaciones a partir de la lectura real del equipo, con «Arreglarlo» que abre la opción que corresponde) y, abajo, «O míralo tú mismo» con siete programas de diagnóstico con nombre de calle (estado de los discos, temperaturas, qué ocupa el espacio, ficha del ordenador, probar pantalla y teclado, recuperar archivos borrados).


## Revisión de diseño (2026-11-13): reglas nuevas
Hecha con la skill impeccable (crítica con dos evaluadores independientes: uno de diseño y otro mecánico con el detector, el medidor de contraste y la lectura del código). Resultado del primero: 26/40 («aceptable, hay que mejorar antes de que lo use una persona sin conocimientos»); detector: limpio; contrastes de texto: todos por encima de 4,5:1.
- **Quien no sabe, decide, y decide de verdad.** Tras la revisión, el modo sencillo enseña lo encontrado y los pasos previstos y la persona quita los que no quiera o pide «Solo quiero la información». El script espera esa respuesta antes de cambiar nada (sin respuesta en 30 minutos no cambia nada). La copia de seguridad previa no se puede quitar. Es agencia real: nada de progreso falso ni de acciones inventadas para dar sensación de que se hace algo.
- **Las opciones con riesgo piden un «¿Empezamos?»** (Internet, avisos y errores, virus); las inocuas, no.
- **Sin cuenta real, barra que se mueve** (indeterminada, sin porcentaje inventado); con cuenta, «Paso 2 de 4: …».
- **El final no asusta.** Un reinicio pendiente no es un problema: «Ya está listo» con un botón de reiniciar. «Solo la información» responde «No he cambiado nada, como pediste». La copia que no se pudo guardar se dice con calma debajo de la lista, no como titular.
- **Una sola pregunta al empezar:** «No sé qué le pasa» va la primera, el panel de recomendaciones solo sale si hay algo que contar y los programas de diagnóstico van plegados («Programas para mirarlo tú mismo»).
- **Accesibilidad:** el foco pasa al título al cambiar de fase aunque la vista no cambie; objetivos de 44 px en el modo sencillo (pie, resúmenes, campos, diálogos); texto de 15 px como mínimo en el modo sencillo; borde de campos con contraste de 3:1 (`--borde-fuerte`); nombres largos se parten en vez de desbordar; tema claro/oscuro a mano en el modo sencillo.



## Portada del modo técnico y panel «Este equipo» (2026-11-14)
Inspirado en Winhance y VoiceStudio (ver `docs\Revision_Winhance_WinUtil.md` y la maqueta en `docs\propuesta-visual`), con las reglas de la casa.
- **«Inicio» es la primera entrada del lateral técnico** (Ctrl+1; el resto se desplaza: Arreglar 2, Estado 3, Diagnóstico 4, Herramientas 5). El modo sencillo no cambia.
- **Tres tarjetas grandes** para lo que se hace a diario (revisar el equipo, va lento, no hay Internet): abren la opción correspondiente de «Arreglar mi equipo», que sigue explicando qué va a hacer y pide el «Empezar». **Seis pequeñas** que llevan a cosas que ya existen. Solo aparece lo que se puede usar (la tarjeta de quitar programas no sale en el pack público porque esa herramienta está oculta). Un solo color de acento: el icono va en acento y nada más lleva color.
- **«Este equipo»** (lateral, abajo): punto + memoria en uso; al pulsar abre un panel con procesador, memoria y discos reales (el disco del sistema primero), batería si hay y tiempo encendido, y «Ver el estado completo». La memoria se lee cada 3 s; procesador y discos salen de la lectura compartida del equipo (`equipo.ts`), que se pide al abrir y se reutiliza en «Estado del equipo». Va en posición fija porque el lateral recorta lo que sobresale. Cierra con Escape o al pulsar fuera.
- **Pendiente de la propuesta:** estado actual y etiqueta «Como recomendamos / Valor distinto» por ajuste, interruptores, detalles técnicos plegables, revisión de perfiles y ajustes de la app. Necesitan que cada herramienta de ajustes sepa leer su estado.
- Gancho de prueba solo en desarrollo: `NITRIT0_CLIC=<selector>` pulsa un elemento antes de la captura.

## Ajustes de Windows con estado (2026-11-14)
Pestaña «Ajustes» dentro de Herramientas (modo técnico), también desde la tarjeta «Ajustes de Windows» de Inicio.
- **Cada ajuste dice cómo está ahora:** una sola etiqueta con icono y texto («Como recomendamos», «Valor de Windows», «Valor distinto», «Elegido por ti»), nunca solo color; «Recomendado: X · Windows: Y» a su lado y un enlace «Poner “X”» si no coincide. Lo que es cuestión de gusto no lleva recomendación ni se pinta como fallo.
- **Control según el ajuste:** interruptor rectangular con el estado escrito cuando hay dos opciones; desplegable de una sola elección (con teclado) cuando hay más.
- **Detalles técnicos plegables** (ruta del registro, valor, el de ahora, el recomendado y el de Windows) y filtros «Solo lo que existe en mi Windows» (por compilación), «Solo lo que no está como recomendamos» y «Detalles técnicos» abiertos.
- **Seguridad:** la interfaz solo manda un id y una clave de opción; qué clave del registro se toca y qué valores valen lo decide `Scripts\Ajustes_Para_App.ps1` (lista blanca, solo HKCU), que la app y el propio script comprueban contra `Integridad.json`. Cada cambio guarda el valor anterior (`Set-ValorSeguro`) y aparece en «Deshacer los últimos cambios».
- **De momento 5 ajustes** (barra de tareas: Vista de tareas, alineación, búsqueda; Explorador: extensiones y archivos ocultos). Para añadir uno basta una entrada en la tabla del script y regenerar la integridad.
- **Tema:** desplegable en el lateral (Oscuro, Claro, Igual que Windows) en vez del botón que alternaba dos; en el modo sencillo, un enlace del pie que va pasando por los tres. `Ajustes.json`: `TemaModo` = lo elegido, `Tema` = el efectivo (para las herramientas antiguas de PowerShell).
- Pendiente: ajustes de la propia app (idioma, cómo se aplican los cambios) y perfiles con revisión.

## Pulido de legibilidad y amabilidad (2026-11-21)
- Texto base de 15 px (antes 14) y controles más cómodos: botones y chips con altura mínima (36 y 32 px), menú lateral de 38 px, filas de herramientas con más aire. El modo sencillo mantiene sus 44 px.
- Cumplidas las reglas de la casa que se habían colado: el veredicto ya no lleva franja de color a un lado (borde entero y fondo muy suave del tono), los sellos ya no son píldoras (radio de 6 px) y el menú de Limpieza ya no marca la página actual con una barra lateral.
- Casillas de Limpieza de 22 px, como las de la app principal; estado pulsado en los botones; botones del menú de Limpieza atenuados mientras hay una operación en marcha.
- Estilos en línea sustituidos por clases (`al-final`, `bloque-ancho`, `sep-arriba`, `sep-abajo`). Quedan unos pocos en Limpieza y el cálculo del medidor.
- Las solapas siguen siendo navegación y no un `tablist`; el comentario del componente decía lo contrario y se ha corregido.
