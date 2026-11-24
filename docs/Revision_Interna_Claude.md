# Revisión interna de Nitrit0 Kit (Claude, 23-nov-2026)

Misma estructura que pedí a los demás modelos. Lo marcado «visto» lo comprobé en el código o ejecutándolo; lo marcado «sin probar» no he podido ejecutarlo en este equipo (sin administrador, sin cliente delante).

## 1. Bugs y riesgos

1. **Los packs que hay en `E:\Nitrit0_Packs` están desfasados (visto).** Se hicieron antes de añadir `Certificados_Arranque_Seguro.ps1`, la limpieza de OneDrive y de perfiles sin uso y el arreglo del optimizador (plan de ahorro por GUID, avisos de batería y reinicio pendiente en la gráfica y en Office). `Datos\Integridad.json` también está viejo: `Validar_Kit` avisa de que el catálogo exportado es anterior. Hay que regenerar integridad y rehacer packs.
2. **Diecisiete archivos sin comitear (visto):** Bichobit con etapas y guardado en el pendrive, PDF del informe, temperatura de CPU, `Sensores.ps1`, `Comun.ps1` (avisos previos), tres scripts de mantenimiento y el catálogo.
3. **Temperatura de CPU (riesgo alto, corregido en parte).** Cada lectura abre y cierra LibreHardwareMonitor, que carga y descarga un controlador de kernel. Cada 20 s era demasiado: un antivirus o un EDR lo marcaría. Lo he subido a 60 s. Lo correcto sería un lector que se quede abierto mientras el panel «En vivo» esté a la vista (sin hacer, mediano).
4. **Bichobit (bajo, corregido).** La clave del almacenamiento distinguía mayúsculas: si el hostname y el nombre del equipo difieren solo en eso, la criatura «desaparecía». Ahora va en minúsculas. Sigue pendiente que `anotarHito` restaure primero desde el pendrive: si el almacenamiento local se vació y no se pasó por Inicio, la marca de «arreglado» o «entregado» se pierde.
5. **Sin probar:** `Certificados_Arranque_Seguro` como administrador (en este equipo solo salió el aviso de que falta administrador); las categorías nuevas de limpieza (OneDrive y perfiles) con datos reales, porque este PC no tiene perfiles inactivos ni archivos locales de OneDrive; el botón «Guardar como PDF» dentro de la app (la técnica sí está probada con un informe real); la temperatura en pantalla.
6. **Heredados y conocidos, sin tocar:** la inferencia de «doble canal» en la RAM da por bueno el doble canal cuando Windows no etiqueta los canales; los guardas contra doble clic en Combos e Historial; comprobaciones de desmontaje en `PanelEquipo` y `Discos`; la reversión de `ChangeDisplaySettings`; validación de entrada en `Restaurar_Datos_Usuario` y `Quien_Bloquea`; codificación HTML en `Auditoria_Licencias_BitLocker`.

## 2. Qué falta en el catálogo (propuestas, por valor)

- **Vigilar la temperatura durante las pruebas de estrés y parar al umbral** (propuesta de DeepSeek, sin verificar que no exista): FurMark o Prime95 en un equipo con refrigeración rota pueden apagarlo o dañarlo. Aprovecha `Sensores.ps1`. Mediano.
- **Exportar y restaurar impresoras** (propuesta de DeepSeek): ahorra reconfigurar las de red del cliente. Pequeño-mediano.
- **Claves de producto de Office y de terceros antes de formatear.** Hoy se rescata la de Windows (OEM) pero no la del software. Mediano; ojo con mostrar una clave genérica como si fuera la buena.
- **Que «Revisión total» recomiende por sí sola** la herramienta del catálogo que arregla cada fallo (hoy lo hace el diagnóstico detallado, la revisión total solo enseña el resultado). Pequeño.
- **Tarjeta de Bichobit para compartir** y las especies por opción de entrada: decisión de diseño tuya.

## 3. Qué cambiaría de lo que hay

- **Una sola puerta por herramienta.** Quedan repetidas entre el menú de recorrido y las pantallas de herramientas (limpieza, desinstalar, clonar). La revisión de DeepSeek lo detectó sobre documentos antiguos; compruébalo con la app abierta.
- **SFC, DISM y chkdsk** abren una consola sin tiempo máximo ni registro en el historial. Lo dejé a propósito (se ve el progreso); si algún día quieres historial, la vía es `Reparar_Windows_y_Tienda.ps1`.
- **Firmar el ejecutable** quitaría el aviso de SmartScreen delante del cliente. Requiere un certificado de pago: es decisión tuya.
- **Probar y comitear por tandas** de aquí en adelante: se han acumulado cuatro cambios grandes sin commit.

## 4. Top 5 de lo que haría primero

1. Regenerar integridad, rehacer los packs y comprobar que el público no lleva Clonador, Antivirus ni `Clonar_Disco.ps1`.
2. Comitear por tandas (Bichobit, PDF, sensores, limpieza, arranque seguro).
3. Probar con la app abierta como administrador: temperatura, PDF y Bichobit tras limpiar temporales.
4. Convertir el lector de temperatura en uno persistente.
5. Vigilancia de temperatura en las pruebas de estrés.