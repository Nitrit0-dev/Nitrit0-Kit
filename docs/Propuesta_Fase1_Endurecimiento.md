# Propuesta de la Fase 1: endurecimiento quirúrgico

Fecha: 2026-11-15. **Es una propuesta para revisar: no se ha cambiado ningún script ni regla.** Está hecha leyendo el código real de `Comun.ps1`, `Reparar_Red`, `Restaurar_Datos_Usuario`, `Vaciar/Restaurar_Cuarentena`, `LimpiarTemporalesEquipo` y cómo la app interpreta los códigos de salida.

## 0. Lo que la lectura corrige de mi auditoría

La auditoría contó patrones de texto y **exageró la debilidad de tres de los cuatro scripts**. Lo real:

| Script | Lo que ya tiene | Lo que le falta de verdad |
|---|---|---|
| **LimpiarTemporalesEquipo** | Confirmación inicial, mide el espacio antes y después | Es el **único realmente débil**: sin `try/catch`, sin comprobar administrador, sin simulación ni estimación, cierra los navegadores a la fuerza, borra `Windows\Logs\*` (los registros CBS y DISM que un técnico necesita para diagnosticar) y el Prefetch, silencia todos los errores y mide «C:» fijo |
| **Reparar_Red** | Confirmación, **aviso de sesión remota** (AnyDesk, TeamViewer, RDP), copia de `Get-NetIPConfiguration` en un archivo, un `try/catch` | La copia es solo texto: **no se puede reponer sola**. Falta comprobar administrador, modo simulación, códigos de salida y control por paso |
| **Restaurar_Datos_Usuario** | **Nunca sobrescribe** (`robocopy /XC /XN /XO`), tiene `-Simular`, usa `exit 1` en errores | Solo detalles: unificar el nombre (`-SoloAnalizar`), proteger el diálogo con `try/catch`, devolver 2 si se cancela (hoy devuelve 0) y comprobar permisos si el perfil es de otro usuario |
| **Vaciar_Cuarentena / Restaurar_Cuarentena** | Son envoltorios de 3 líneas de `Desinstalar_Total`, que **sí confirma** (muestra sesiones y MB) | Solo propagar el código de salida, `try/catch` y comprobar administrador |

**Un hallazgo que cambia el plan:** la app hoy trata **cualquier código distinto de 0 como fallo** (`correcto = codigo === 0`; el mensaje es «Terminó con código N»). Si adoptamos «`exit 2` = cancelado», **hay que enseñárselo a la app**, o los cancelados saldrán como errores. Es un cambio pequeño en `main/index.ts`.

## 1. Comun.ps1: administrador, contrato de salida y simulación

### 1.1 Funciones nuevas (en `Comun.ps1`, junto a `Confirm-Accion`)
- `Test-EsAdmin` → `$true` o `$false`. Hoy no existe: 18 scripts la reescriben a su manera, el resto asume que la app ya eleva.
- `Assert-Admin [-Motivo 'texto']` → si no hay administrador, escribe «Hace falta administrador para …» y termina el script con código de error.
- `Exit-Kit -Resultado Ok|Error|Cancelado [-Mensaje 'texto']` → escribe el mensaje, lo registra con `Write-Log` y sale con el código del contrato.
- Constantes del contrato: `$Global:Salida = @{ Ok = 0; Error = 1; Cancelado = 2 }`.

### 1.2 Contrato de salida (que pido que aprobéis)
| Código | Significa | La app muestra |
|---|---|---|
| **0** | Terminó bien (o «no había nada que hacer») | Verde |
| **1** | Error, **incluido «falta administrador»** | Rojo |
| **2** | La persona canceló o el script decidió no actuar | Neutro, «Cancelado» (no rojo) |

> **Decisión que necesito:** hoy ~12 scripts (casi todos los de esta sesión) usan `exit 2` para «sin administrador». Con tu contrato, 2 pasa a ser «cancelado»; propongo que **«sin administrador» sea 1** (es un error de requisito, no una decisión del usuario) y migrarlos a `Assert-Admin`.

### 1.3 Cambio en la app
`main/index.ts` (cierre del script): tratar `codigo === 2` como cancelado (`motivo: 'Cancelado'`, sin marcarlo como fallo en el registro del kit). Un cambio de 2 líneas; la interfaz ya sabe pintar «Cancelado».

### 1.4 `-SoloAnalizar` estándar
- Nombre canónico **`-SoloAnalizar`**. Los 9 scripts que ya tienen modo simulación lo mantienen y los que usan otro nombre (`-Simular`, `-SoloMirar`, `-SoloLeer`, `-SoloConsulta`) lo conservan como **alias** (no se rompe nada).
- Nuevo campo opcional en la ficha del catálogo: **`Simulable = $true`**. `Validar_Kit` comprobará que un script marcado así tiene de verdad ese parámetro. Más adelante la app podrá ofrecer «Ver qué haría» antes de ejecutar (no entra en esta fase).

### 1.5 Migración
Solo se cambian a `Assert-Admin`/`Exit-Kit` los **cuatro scripts críticos** y los **diez que escribí en esta sesión**. Los demás 50 no se tocan en la Fase 1 (cambiarlos todos sin probarlos sería más riesgo que beneficio).

## 2. Los cuatro scripts críticos

### 2.1 LimpiarTemporalesEquipo (el que más cambia)
1. `Assert-Admin`.
2. **`-SoloAnalizar`**: calcula cuánto ocupa cada categoría y no borra nada. La confirmación inicial pasa a decir cuánto se va a liberar.
3. **`try/catch` por categoría** (temporales del sistema, navegadores, Papelera) con recuento de lo que no se pudo borrar por estar en uso, en vez de silenciarlo todo.
4. **Navegadores: cierre amable primero** (`CloseMainWindow`, esperar unos segundos) y solo forzar los que no cierren, diciendo cuáles se forzaron.
5. **Qué deja de borrar** (decisión vuestra, ver abajo): `Windows\Logs\*` (se pierden los registros CBS y DISM) y **Prefetch** (Windows lo recrea; borrarlo no aporta y ralentiza el siguiente arranque).
6. `SoftwareDistribution\Download`: parar y volver a arrancar `wuauserv` y `bits` con `try/finally` (hoy falla en silencio si están activos).
7. Medir **`$env:SystemDrive`**, no «C:» fijo. Códigos: 0 bien, 1 si algo crítico falla, 2 si se cancela.

### 2.2 Reparar_Red
1. `Assert-Admin`.
2. **`-SoloAnalizar`**: enseña adaptadores, IP, DNS, puerta de enlace, proxy y estado de conectividad sin cambiar nada.
3. **Copia que se puede restaurar:** `netsh -c interface dump` guarda la configuración de red como un script (independiente del idioma) en la carpeta de respaldo; se repone con `netsh -f <archivo>`. Se añade **`-RestaurarRed <archivo>`** al propio script. Además se guarda la lista de DNS por adaptador (`Get-DnsClientServerAddress`). Se mantiene el aviso de sesión remota.
4. **`try/catch` y resultado por paso** (flushdns, release/renew, registerdns, winsock, ip reset) y un resumen «n de 6 pasos bien».
5. Tras reparar: si sigue sin haber Internet, **código 1** con consejo; si se repuso, 0. Cancelar → 2.

### 2.3 Restaurar_Datos_Usuario
`-Simular` pasa a `-SoloAnalizar` (con `-Simular` como alias); el diálogo de carpeta y las copias van dentro de `try/catch`; se comprueba espacio libre y, si el perfil destino es de **otro** usuario, `Assert-Admin`; cancelar devuelve 2. Se conserva lo bueno: nunca sobrescribe. Para decir qué se copió se usan los **códigos de salida de robocopy** (independientes del idioma), no su texto.

### 2.4 Vaciar_Cuarentena y Restaurar_Cuarentena
Siguen siendo envoltorios (la confirmación vive en `Desinstalar_Total`, que muestra sesiones y MB). Se añade `try/catch`, `Assert-Admin` (la cuarentena está en `ProgramData`) y **propagar el código de salida** de `Desinstalar_Total` (hoy se pierde).

## 3. Reglas de desarrollo (`.claude/skills/nitrit0-script/SKILL.md` y `CLAUDE.md`)

Texto propuesto para añadir:

> **9. Nunca parsear texto traducido.** La salida de `fsutil`, `defrag`, `netsh`, `ipconfig`, `sfc`, `dism`, `chkdsk` o `robocopy` cambia con el idioma de Windows. Usa, por este orden: (1) cmdlets y objetos (`Get-NetIPConfiguration`, `Get-Volume`…); (2) propiedades CIM (`Win32_Volume.DirtyBitSet`); (3) **códigos de salida** (`$LASTEXITCODE`, los de `robocopy`); (4) archivos de configuración en formato no traducido (`netsh dump`, `reg export`, `/xml`). Solo si no hay otra salida, el texto se lee con patrones que cubran español e inglés y el script **tiene que fallar con un aviso claro** (no asumir «limpio» si no entiende la salida). *Caso real:* `fsutil dirty query` dice «no contiene errores» en este equipo; un `-match 'dirty'` habría dado un falso «sucio».
>
> **10. Contrato de salida.** `exit 0` correcto, `exit 1` error (incluida la falta de administrador), `exit 2` cancelado. Se usa `Exit-Kit`.
>
> **11. Administrador.** Siempre con `Test-EsAdmin` / `Assert-Admin` de `Comun.ps1`; nunca `IsInRole` a mano.
>
> **12. Simulación.** Todo script que cambie o borre algo acepta `-SoloAnalizar` y lo declara con `Simulable = $true` en su ficha.

Además, `Validar_Kit.ps1` ganará un **aviso (no error)** cuando un script analice con `-match` o `Select-String` la salida de esos comandos, para que quede a la vista. Un aviso porque no se puede distinguir con exactitud un uso legítimo de uno frágil.

## 4. Cómo lo probaría

| Cambio | Prueba |
|---|---|
| `Test-EsAdmin`, `Assert-Admin`, `Exit-Kit` | Ejecutar con y sin administrador y comprobar códigos de salida |
| Código 2 en la app | Lanzar un script de prueba que termine con 0, 1 y 2 y ver cómo lo pinta la app |
| LimpiarTemporalesEquipo | `-SoloAnalizar` real; después **un borrado real aquí** (solo temporales; si no queréis, solo con datos de prueba) |
| Reparar_Red | `-SoloAnalizar`, la copia con `netsh dump` y comprobar que el archivo se puede leer; **la reparación real corta la red unos segundos**: solo si lo autorizáis |
| Restaurar_Datos_Usuario | Con una copia de prueba en una carpeta temporal y `-SoloAnalizar`, y una restauración real sobre un perfil de prueba |
| Cuarentenas | Un ciclo de desinstalar un programa de prueba, restaurar y vaciar |
| Todo | `Validar_Kit -Analizador`, regenerar integridad y packs |

## 5. Decisiones que necesito antes de empezar

1. **Contrato:** «sin administrador» = **1** (mi propuesta) o 2.
2. **LimpiarTemporalesEquipo:** ¿dejo de borrar **Prefetch** (mi recomendación: sí) y limito `Windows\Logs` a los archivos de **más de 30 días** (mi recomendación) o dejo de tocarlo del todo?
3. **Navegadores:** cierre amable y forzar solo los que no cierren (recomendado).
4. **Pruebas reales:** ¿autorizas borrar de verdad temporales en este equipo y cortar la red unos segundos para probar `Reparar_Red`? Si no, las pruebas serán solo de análisis y con datos de prueba, y lo destructivo quedará sin comprobar.
5. **Alcance de la migración:** ¿bien solo con los cuatro críticos y los diez de esta sesión?

## 6. Archivos que se tocarían

`Scripts\Comun.ps1`, `App\src\main\index.ts`, `Scripts\Validar_Kit.ps1`, los 4 scripts críticos, la ficha de `Catalogo.psd1` (campo `Simulable`), `.claude\skills\nitrit0-script\SKILL.md`, `CLAUDE.md`, y la migración a `Assert-Admin`/`Exit-Kit` de: Clonar_Disco, Disco_Sucio_y_Reinicios, Editor_Hosts, Instalar_Driver_Catalogo, Limpiar_Almacen_Drivers, Limpiar_Espacio_Windows, Optimizar_Unidades, Quien_Bloquea, Quitar_Dispositivos_Fantasma, Componentes_Kit y Actualizar_Herramientas.
