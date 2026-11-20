# Seguridad

## Qué comprueba el kit por sí mismo
- Antes de ejecutar un script o una herramienta del kit se comprueba su huella **SHA-256** contra `Datos\Integridad.json`. Si no coincide, no se ejecuta.
- Las descargas de terceros se verifican con la firma Authenticode del fabricante o con la huella que publica el servidor.
- Lo que cambia el sistema (registro, servicios, DNS, IP, arranque) queda anotado y se puede deshacer desde «Deshacer cambios»; los scripts que modifican algo aceptan `-SoloAnalizar`.
- La interfaz de la app solo manda identificadores de un catálogo cerrado; el proceso principal resuelve y comprueba cada ruta, y no ejecuta nada que no figure en él.

## Límites que debes conocer
- `Integridad.json` protege contra cambios **accidentales**. Quien pueda escribir en la carpeta y regenerar ese manifiesto puede cambiar el kit: compara siempre el SHA-256 de lo que descargas con el que se publica junto a la versión.
- `Nitrit0.exe` y `Nitrit0_Limpieza.exe` **no están firmados** (SmartScreen puede avisar de «editor desconocido») y piden permisos de administrador porque las reparaciones los necesitan. Descárgalos solo desde las Releases de este repositorio.
- Es un kit de soporte técnico: úsalo en equipos tuyos o con permiso de su dueño y haz copia de tus datos antes de reparar.

## Cómo avisar de una vulnerabilidad
Abre un aviso privado desde la pestaña **Security → Report a vulnerability** de este repositorio (o un *issue* sin datos sensibles si no hay riesgo). Responderé en cuanto pueda.
