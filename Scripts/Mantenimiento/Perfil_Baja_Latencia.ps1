# =====================================================================
#  Perfil_Baja_Latencia.ps1 - Activa o desactiva el perfil de baja latencia de Windows 11 (Nitrit0)
#  Windows 11 24H2/25H2 con la actualización de junio de 2026 (KB5094126) trae un perfil que sube la CPU a su
#  frecuencia máxima 1-3 s al abrir el menú Inicio, la búsqueda o el clic derecho. Microsoft lo despliega por
#  fases y en muchos equipos está dormido: se enciende con ViVeTool (github.com/thebookisclosed/ViVe, v0.3.4,
#  descargada con huella SHA256 fijada). Se necesita reiniciar para que surta efecto.
#  Parámetros: -Accion Activar|Desactivar (sin él pregunta con una ventana; con -SinPreguntas activa)
#              -SinPreguntas (no pregunta nada)   -Simular (no descarga ni cambia nada)
# =====================================================================
[CmdletBinding()]
param([ValidateSet('Activar', 'Desactivar')][string]$Accion, [switch]$SinPreguntas, [Alias('SoloAnalizar')][switch]$Simular)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E

$urlZip = 'https://github.com/thebookisclosed/ViVe/releases/download/v0.3.4/ViVeTool-v0.3.4-IntelAmd.zip'
$huella = 'CC27F073F3FE5DD2C3D947FAF558FD4B2F8E34454F812689B0D65EE8A52E4147'
# Los 4 identificadores del perfil (confirmados por varias guías). Cambian entre compilaciones: si Microsoft los integra, dejan de hacer falta.
$ids = '58989092,60716524,48433719,61391826'

Write-Output "$($E.Cohete) PERFIL DE BAJA LATENCIA DE WINDOWS 11"
if (-not $Simular) { Assert-Admin 'cambiar el perfil de baja latencia (ViVeTool escribe en HKLM)' }
if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { Write-Output "$($E.Aviso) Este equipo es ARM64 y el script solo lleva fijada la versión Intel/AMD de ViVeTool. No se cambia nada."; exit 2 }

# --- ¿Esta compilación tiene el perfil? (24H2: 26100.8655+, 25H2: 26200.8655+)
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$build = [int]$cv.CurrentBuild; $ubr = [int]$cv.UBR
Write-Output "$($E.Info) Windows $($cv.DisplayVersion), compilación $build.$ubr"
if ($build -lt 26100 -or (($build -eq 26100 -or $build -eq 26200) -and $ubr -lt 8655)) {
    Write-Output "$($E.Aviso) Esta compilación aún no trae el perfil: activarlo no haría nada. Instala las actualizaciones (Actualizar Windows o «Actualizar versión de Windows») hasta 26100.8655 / 26200.8655 o superior y repite."
    Write-Log "Perfil_Baja_Latencia: compilación $build.$ubr demasiado antigua"; exit 2
}
if ($build -gt 26200) { Write-Output "$($E.Info) Compilación posterior a 25H2: Microsoft puede haber integrado ya el perfil y estos IDs no tener efecto." }

# --- Acción
if (-not $Accion) {
    if ($SinPreguntas) { $Accion = 'Activar' }
    else {
        Add-Type -AssemblyName System.Windows.Forms
        $r = [Windows.Forms.MessageBox]::Show("Perfil de baja latencia de Windows 11`n`nSí = ACTIVAR (menú Inicio, búsqueda y clic derecho más rápidos; la CPU sube a tope 1-3 s en ráfagas)`nNo = DESACTIVAR (volver al comportamiento anterior)`nCancelar = no hacer nada`n`nSe necesita reiniciar después.", 'Nitrit0', 'YesNoCancel', 'Question')
        if ($r -eq 'Cancel') { Write-Output "$($E.Info) Cancelado: no se ha cambiado nada."; exit 2 }
        $Accion = if ($r -eq 'Yes') { 'Activar' } else { 'Desactivar' }
    }
}
$verbo = if ($Accion -eq 'Activar') { '/enable' } else { '/disable' }
if ($Simular) { Write-Output "$($E.Info) (simulación) se descargaría ViVeTool v0.3.4, se verificaría su SHA256 y se ejecutaría: ViVeTool.exe $verbo /id:$ids"; exit 0 }
if (-not (Test-Internet)) { Write-Output "$($E.Error) Sin conexión a Internet para descargar ViVeTool."; exit 1 }

# --- Descarga y verificación (el exe no está firmado: lo único que lo respalda es la huella fijada)
$zip = Join-Path $Global:NitKit.Cache 'ViVeTool-v0.3.4-IntelAmd.zip'
$dir = Join-Path $Global:NitKit.Cache 'ViVeTool'
Remove-Item -LiteralPath $zip, $dir -Recurse -Force -ErrorAction SilentlyContinue
Write-Output "$($E.Refresh) Descargando ViVeTool v0.3.4 (≈ 526 KB, de github.com/thebookisclosed/ViVe)…"
if (-not (Get-Descarga $urlZip $zip 120 3 'ViVeTool')) { Write-Output "$($E.Error) No se pudo descargar ViVeTool."; exit 1 }
if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $huella) {
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    Write-Output "$($E.Error) La huella SHA256 de lo descargado no coincide con la esperada. No se ejecuta."; Write-Log 'Perfil_Baja_Latencia: huella SHA256 no válida' 'ERROR'; exit 1
}
Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force
$exe = Join-Path $dir 'ViVeTool.exe'
if (-not (Test-Path -LiteralPath $exe)) { Write-Output "$($E.Error) El zip no contiene ViVeTool.exe."; exit 1 }
Write-Output "$($E.OK) Huella verificada."

# --- Cambio (reversible: ViVeTool guarda los overrides en el registro y /disable los quita)
[void](Start-OperacionSegura 'Perfil de baja latencia')
$res = Invoke-Proceso $exe "$verbo /id:$ids" 60 'ViVeTool' 10 -MostrarSalida
if ($res.Codigo -ne 0) { Write-Output "$($E.Error) ViVeTool terminó con código $($res.Codigo). No se ha completado el cambio."; Write-Log "Perfil_Baja_Latencia: ViVeTool código $($res.Codigo)" 'ERROR'; exit 1 }
Save-Informativo "ViVeTool $verbo /id:$ids" 'Para volver atrás: ejecutar este script y elegir Desactivar, o «ViVeTool.exe /disable /id:58989092,60716524,48433719,61391826» (o /reset) como administrador, y reiniciar.'
Write-Output "$($E.OK) Perfil de baja latencia $(if ($Accion -eq 'Activar') { 'ACTIVADO' } else { 'DESACTIVADO' }). Reinicia el equipo para que surta efecto."
if ($Accion -eq 'Activar') {
    Write-Output "$($E.Info) Se nota en Inicio, búsqueda, notificaciones y clic derecho; en apps de terceros aún es irregular. En el Administrador de tareas > Rendimiento > CPU verás un pico de velocidad al abrir el menú Inicio."
    Write-Output "$($E.Info) Con el modo «Ahorro de energía» de Windows casi no actúa: pon el modo Equilibrado o Máximo rendimiento. En portátiles puede subir algo el ventilador."
}
Write-Log "Perfil_Baja_Latencia: $Accion aplicado (IDs $ids)"
