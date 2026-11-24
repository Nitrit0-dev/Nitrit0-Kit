# Pregunta abierta: propuestas sobre Nitrit0 Kit

Eres un ingeniero senior que conoce el soporte técnico a equipos de clientes. Lee en este orden, solo lectura (no modifiques ni crees archivos en el proyecto):

1. `CLAUDE.md` (mapa del proyecto y reglas).
2. `docs/App_Electron.md` y `docs/Propuesta_Menu_Nuevo.md` y `docs/Propuesta_Ordenadormon.md`.
3. `App/datos/herramientas.json` (catálogo de lo que hace el kit) y, si te hace falta, los scripts de `Scripts/Mantenimiento/` y el código de `App/src/`.

Contexto: el kit es de un técnico, Juan, que lo lleva en un pendrive y lo usa en equipos de clientes sin conexión asegurada. Windows PowerShell 5.1, sin instalar nada si se puede evitar, todo en español.

Responde en español, directo y sin relleno:

1. **Lo que ya existe y mejorarías.** Cinco cambios por orden de valor. Para cada uno: qué falla o se queda corto (con archivo y línea si lo ves), qué harías y cuánto costaría (pequeño, mediano o grande).
2. **Lo que falta.** Funciones que un técnico de soporte echaría de menos y que encajen con lo que hay. Para cada una: qué problema real resuelve, cómo la implementarías (qué archivos tocarías, qué herramientas del propio Windows usarías, qué riesgos tiene para el equipo del cliente) y cómo se comprobaría que funciona.
3. **Lo que NO harías**, aunque suene bien, y por qué.
4. **Una apuesta.** La única cosa que cambiarías si solo pudieras hacer una.

Distingue lo que has visto en el código de lo que supones. No inventes archivos ni funciones que no existan. Nada de emojis ni frases de relleno.