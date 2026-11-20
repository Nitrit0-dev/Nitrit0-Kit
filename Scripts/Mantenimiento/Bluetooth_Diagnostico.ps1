# =====================================================================
#  Bluetooth_Diagnostico.ps1 - Comprueba y repara el Bluetooth del equipo (Nitrit0)
#  Mira si hay adaptador y si tiene driver, el estado de los servicios de Bluetooth y cuántos dispositivos hay emparejados.
#  Si algo está mal y aceptas (o usas -Reparar): pone el servicio en inicio manual y lo arranca, y reinicia el adaptador (desactivarlo y activarlo).
#  No borra emparejamientos ni toca drivers. Lo que se cambia queda registrado y se deshace desde «Deshacer cambios».
#  Parámetros: -SoloAnalizar (solo mira) · -Reparar (aplica las reparaciones sin preguntar) · -SinPreguntas (no abre ventanas; sin -Reparar no cambia nada)
# =====================================================================
[CmdletBinding()]
param([Alias('Simular', 'SoloMirar')][switch]$SoloAnalizar, [switch]$Reparar, [switch]$SinPreguntas)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
$problemas = New-Object Collections.Generic.List[string]
$arreglos = New-Object Collections.Generic.List[scriptblock]

# --- Adaptador: dispositivos de la clase Bluetooth que cuelgan de USB, PCI o ACPI (el resto son enumeradores y dispositivos emparejados) ---
$todos = @(Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue)
$adaptadores = @($todos | Where-Object { $_.Present -and $_.InstanceId -match '^(USB|PCI|ACPI|SERIAL)\\' })
$emparejados = @($todos | Where-Object { $_.InstanceId -match '^BTH(ENUM|LE)\\DEV_' })
Write-Output "  $($E.Lupa) Adaptador Bluetooth:"
if (-not $adaptadores.Count) {
    Write-Output "    $($E.Aviso) No se detecta ningún adaptador Bluetooth."
    $problemas.Add('No hay adaptador Bluetooth (o está desactivado en la BIOS, o falta su driver, o el equipo no lo lleva).')
} else {
    foreach ($a in $adaptadores) {
        $ok = ($a.Status -eq 'OK')
        Write-Output ("    {0} {1} · {2}" -f $(if ($ok) { $E.OK } else { $E.Aviso }), $a.FriendlyName, $(if ($ok) { 'funciona' } else { "con problema (estado $($a.Status))" }))
        if (-not $ok) {
            $problemas.Add("El adaptador «$($a.FriendlyName)» no está bien (estado $($a.Status)): puede faltar el driver o estar desactivado.")
            $id = $a.InstanceId; $arreglos.Add({ Disable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction Stop; Start-Sleep -Seconds 2; Enable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction Stop; Write-Output "    $($E.OK) Adaptador reiniciado (desactivado y activado)." }.GetNewClosure())
        }
    }
}

# --- Servicios (StartMode y State son valores fijos, no texto traducido) ---
Write-Output "  $($E.Lupa) Servicios de Bluetooth:"
foreach ($s in @(@('bthserv', 'Servicio de compatibilidad con Bluetooth'), @('BthAvctpSvc', 'Servicio de audio y vídeo de Bluetooth'))) {
    $sv = Get-CimInstance Win32_Service -Filter "Name='$($s[0])'" -ErrorAction SilentlyContinue
    if (-not $sv) { Write-Output "    $($E.Info) $($s[1]): no existe en este Windows."; continue }
    Write-Output ("    {0} {1} · inicio {2} · {3}" -f $(if ($sv.StartMode -eq 'Disabled') { $E.Aviso } else { $E.OK }), $s[1], $sv.StartMode, $(if ($sv.State -eq 'Running') { 'en marcha' } else { 'parado (Windows lo arranca cuando se usa)' }))
    if ($sv.StartMode -eq 'Disabled') {
        $problemas.Add("El servicio «$($s[1])» está desactivado: sin él el Bluetooth no funciona.")
        $nombre = $s[0]; $arreglos.Add({ if (-not (Set-ServicioSeguro $nombre 'Manual')) { throw "no se pudo cambiar el servicio $nombre" }; Start-Service -Name $nombre -ErrorAction SilentlyContinue; Write-Output "    $($E.OK) Servicio ${nombre}: inicio manual y arrancado." }.GetNewClosure())
    }
}

# --- Dispositivos emparejados (los que no están conectados ahora salen como «Unknown»: es normal) ---
Write-Output "  $($E.Lupa) Dispositivos emparejados: $($emparejados.Count)"
foreach ($d in ($emparejados | Where-Object { $_.FriendlyName } | Select-Object -First 8)) { Write-Output ("    · {0} ({1})" -f $d.FriendlyName, $(if ($d.Status -eq 'OK') { 'conectado' } else { 'no conectado ahora' })) }

if (-not $problemas.Count) { Write-Output "`n$($E.OK) El Bluetooth de este equipo está bien."; Write-Output "  $($E.Info) Si un dispositivo no conecta: apágalo y enciéndelo, quítalo de Configuración > Bluetooth y vuelve a emparejarlo, y comprueba que el Bluetooth no está apagado (modo avión o tecla de función)."; Write-Log 'Bluetooth_Diagnostico: sin problemas'; return }

Write-Output "`n$($E.Aviso) Problemas encontrados:"
foreach ($p in $problemas) { Write-Output "    · $p" }
if ($SoloAnalizar) { Write-Output "`n  $($E.Info) Solo análisis: no se ha cambiado nada."; Exit-Kit 'Error' "$($problemas.Count) problema(s) de Bluetooth." }
if (-not $arreglos.Count) { Exit-Kit 'Error' 'Sin adaptador no hay nada que reparar desde aquí: revisa la BIOS y los drivers del fabricante (Drivers del fabricante en el kit).' }

$aplicar = [bool]$Reparar
if (-not $aplicar -and -not $SinPreguntas) { $aplicar = [bool](Confirm-Accion "Se pueden aplicar $($arreglos.Count) reparación(es) de Bluetooth (servicio en inicio manual y arrancado, adaptador reiniciado).`n`nNo se borra ningún emparejamiento.`n`n¿Aplicarlas ahora?" 'Nitrit0 Kit' -Siempre) }
if (-not $aplicar) { Exit-Kit 'Error' "$($problemas.Count) problema(s) de Bluetooth sin reparar." }

Assert-Admin 'reparar el Bluetooth'
[void](Start-OperacionSegura 'Reparar Bluetooth' -SinPuntoRestauracion)
$fallos = 0
foreach ($a in $arreglos) { try { & $a } catch { $fallos++; Write-Output "    $($E.Aviso) $($_.Exception.Message)" } }
Save-Informativo 'Adaptador Bluetooth reiniciado' 'Si hace falta, se puede volver a desactivar/activar desde el Administrador de dispositivos.'
Write-Log "Bluetooth_Diagnostico: $($arreglos.Count) reparaciones, $fallos con error"
if ($fallos) { Exit-Kit 'Error' "$fallos reparación(es) de Bluetooth no se pudieron aplicar." }
Write-Output "`n$($E.OK) Hecho. Vuelve a probar el Bluetooth; si sigue sin ir, actualiza el driver del adaptador (Drivers del fabricante)."
