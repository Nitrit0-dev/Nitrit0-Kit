# =====================================================================
#  Optimizador_Personal.ps1
#  Modos:
#   Analizar    Solo diagnostica (arranque, disco, RAM, energía, reinicio pendiente) y recomienda. No cambia nada.
#   Fluidez     Efectos visuales ligeros, sin apps en segundo plano ni anuncios, Edge sin precarga, servicios inútiles a Manual.
#   Juego       Plan de máxima potencia, HAGS, GameDVR fuera, prioridad multimedia (y sin limitación de energía en sobremesa).
#   Normal      Plan equilibrado y reparto multimedia por defecto.
#   Privacidad  Anuncios, telemetría de opinión, Copilot/Recall, historial de actividad, Cortana, OneDrive, Delivery Optimization.
#   Limpieza    Temporales, caché de Windows Update y de navegadores, papelera; informa del espacio liberado.
#   Arranque    Lista los programas que arrancan con Windows y permite desactivarlos o reactivarlos.
#   Perfiles    PerfilJuego (Fluidez+Juego+Energía+Red), PerfilTrabajo (Normal+Energía+Privacidad+comodidad), PerfilTranquilo (Normal+Fluidez+Privacidad).
#              PerfilAhorro (Economizador + Fluidez: poco consumo), PerfilEquilibrado (Normal: lo que trae Windows para el día a día).
#   Red         Sin limitación de red multimedia, Wi-Fi a máximo rendimiento y ratón sin aceleración.
#   Energia     Inicio rápido fuera, suspensión selectiva de USB fuera (en portátil solo con corriente) y sin retraso al arrancar apps.
#   Revertir    Deshace un modo anterior con el respaldo que se guarda en Salidas\.
#  Todo lo que cambia el registro o los servicios se respalda y se puede revertir. No toca SmartScreen ni Defender.
# =====================================================================
[CmdletBinding()]
param(
    [ValidateSet('', 'Analizar', 'Fluidez', 'Juego', 'Normal', 'Privacidad', 'Limpieza', 'Arranque', 'Energia', 'Red', 'PerfilJuego', 'PerfilTrabajo', 'PerfilTranquilo', 'PerfilAhorro', 'PerfilEquilibrado', 'Revertir')]
    [string]$Modo = '',
    [Alias('Simular')][switch]$SoloAnalizar   # equivale a -Modo Analizar: solo diagnostica y recomienda
)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }

if ($Global:E) { $E = $Global:E }
else {
    $E = @{
        OK = [char]::ConvertFromUtf32(0x2705); Error = [char]::ConvertFromUtf32(0x274C); Aviso = [char]::ConvertFromUtf32(0x26A0)
        Info = [char]::ConvertFromUtf32(0x2139); Cohete = [char]::ConvertFromUtf32(0x1F680); Lupa = [char]::ConvertFromUtf32(0x1F50D)
        Disco = [char]::ConvertFromUtf32(0x1F4BE); Reloj = [char]::ConvertFromUtf32(0x23F3); Refresh = [char]::ConvertFromUtf32(0x1F504)
    }
}

$script:Respaldo   = New-Object System.Collections.Generic.List[object]
$script:Aplicados  = 0
$script:Rechazados = 0

# ---------------------------------------------------------------------
#  Utilidades base
# ---------------------------------------------------------------------
function Test-Administrador {
    [CmdletBinding()]
    param()
    return (Test-EsAdmin)
}

function Get-CarpetaRespaldos {
    [CmdletBinding()]
    param()
    $base = Split-Path -Parent (Get-CarpetaSalida)
    if ([string]::IsNullOrWhiteSpace($base)) { $base = $env:TEMP }
    $carpeta = Join-Path -Path $base -ChildPath 'Salidas'
    if (-not (Test-Path -LiteralPath $carpeta)) { New-Item -Path $carpeta -ItemType Directory -Force -ErrorAction Stop | Out-Null }
    return $carpeta
}

function Set-ValorRegistro {
    <# Escribe un valor de registro guardando antes el anterior para poder revertirlo.
       Con -Opcional un fallo (p. ej. clave protegida por Windows) solo cuenta como rechazado y no corta el modo. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Ruta,
        [Parameter(Mandatory = $true)][string]$Nombre,
        [Parameter(Mandatory = $true)][object]$Valor,
        [Parameter(Mandatory = $true)][string]$Tipo,
        [switch]$Opcional
    )

    try {
        $existia = $false; $previo = $null; $tipoPrevio = $null
        if (Test-Path -LiteralPath $Ruta) {
            try {
                $previo = (Get-ItemProperty -LiteralPath $Ruta -Name $Nombre -ErrorAction Stop).$Nombre
                $tipoPrevio = (Get-Item -LiteralPath $Ruta -ErrorAction Stop).GetValueKind($Nombre).ToString()
                $existia = $true
            }
            catch { $existia = $false }
        }
        else { New-Item -Path $Ruta -Force -ErrorAction Stop | Out-Null }

        Set-ItemProperty -LiteralPath $Ruta -Name $Nombre -Value $Valor -Type $Tipo -ErrorAction Stop
        $script:Respaldo.Add([pscustomobject]@{ Tipo = 'Registro'; Ruta = $Ruta; Nombre = $Nombre; Existia = $existia; Valor = $previo; TipoValor = $tipoPrevio }); Sync-Respaldo
        $script:Aplicados++
        return $true
    }
    catch {
        if ($Opcional) { $script:Rechazados++; return $false }
        throw "No se pudo escribir '$Nombre' en '$Ruta': $($_.Exception.Message)"
    }
}

function Set-ServicioInicio {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Nombre,
        [Parameter(Mandatory = $true)][ValidateSet('Automatic', 'Manual', 'Disabled')][string]$Tipo
    )

    $servicio = Get-CimInstance -ClassName Win32_Service -Filter "Name='$Nombre'" -ErrorAction SilentlyContinue
    if (-not $servicio) { return }
    $actual = switch ($servicio.StartMode) { 'Auto' { 'Automatic' } 'Manual' { 'Manual' } 'Disabled' { 'Disabled' } default { $null } }
    if (-not $actual -or $actual -eq $Tipo) { return }
    try {
        Set-Service -Name $Nombre -StartupType $Tipo -ErrorAction Stop
        $script:Respaldo.Add([pscustomobject]@{ Tipo = 'Servicio'; Nombre = $Nombre; Previo = $actual }); Sync-Respaldo
        $script:Aplicados++
        Write-Output "  $($E.OK) Servicio $Nombre -> $Tipo (antes: $actual)."
    }
    catch { $script:Rechazados++; Write-Output "  $($E.Aviso) No se pudo cambiar el servicio ${Nombre}: $($_.Exception.Message)" }
}

function Get-PlanEnergiaActivo {
    [CmdletBinding()]
    param()
    $texto = (& powercfg.exe /getactivescheme 2>&1) | Out-String
    $m = [regex]::Match($texto, '[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}')
    if ($m.Success) { return $m.Value }
    return $null
}

function Set-PlanEnergia {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Guid,
        [Parameter(Mandatory = $true)][string]$Nombre
    )

    # El resultado se deja en $script:PlanOk (la función escribe mensajes y no puede devolver un valor limpio)
    $script:PlanOk = $false
    try {
        $lista = (& powercfg.exe /list 2>&1) | Out-String
        if ($LASTEXITCODE -ne 0) { Write-Output "$($E.Aviso) powercfg /list falló (código $LASTEXITCODE). No se cambia el plan."; return }
        if ($lista -notmatch [regex]::Escape($Guid)) { Write-Output "$($E.Aviso) El plan '$Nombre' no aparece en powercfg /list."; return }
        $anterior = Get-PlanEnergiaActivo
        & powercfg.exe /setactive $Guid 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Output "$($E.Error) No se pudo activar '$Nombre' (código $LASTEXITCODE)."; return }
        if ($anterior -and $anterior -ne $Guid) { $script:Respaldo.Add([pscustomobject]@{ Tipo = 'Energia'; Guid = $anterior }); Sync-Respaldo }
        $script:Aplicados++
        $script:PlanOk = $true
        Write-Output "$($E.OK) Plan de energía '$Nombre' activado."
    }
    catch { Write-Output "$($E.Error) Error con powercfg: $($_.Exception.Message)" }
}

function Test-EsPortatil {
    [CmdletBinding()]
    param()
    return [bool](Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue)
}

function New-PuntoRestauracion {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Modo)

    Write-Output "$($E.Reloj) Creando punto de restauración antes del modo '$Modo'..."
    # New-PuntoRestauracionSeguro (Comun.ps1) corta a los 3 minutos: Checkpoint-Computer a secas se cuelga si el servicio de instantáneas (VSS) está atascado
    if (New-PuntoRestauracionSeguro "Optimizador Personal - $Modo") { $script:EstadoPunto = 'Creado' }
    else {
        Write-Output "$($E.Aviso) Se continúa sin punto de restauración: los cambios quedan respaldados para el modo Revertir."
        $script:EstadoPunto = 'No se pudo crear'
    }
}

function Save-Respaldo {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Modo)

    if ($script:Respaldo.Count -eq 0) { return $null }
    try {
        # El nombre lleva el equipo: los respaldos viajan en el pendrive de cliente en cliente y Revertir solo debe ofrecer los de este PC
        if (-not $script:RutaRespaldoActual) { $script:RutaRespaldoActual = Join-Path -Path (Get-CarpetaRespaldos) -ChildPath ("Optimizador_Respaldo_{0}_{1}_{2}.json" -f $Modo, (Get-Date -Format 'yyyyMMdd_HHmmss'), $env:COMPUTERNAME) }
        ConvertTo-Json -InputObject @($script:Respaldo.ToArray()) -Depth 4 | Set-Content -LiteralPath $script:RutaRespaldoActual -Encoding UTF8 -ErrorAction Stop
        return $script:RutaRespaldoActual
    }
    catch { Write-Warning "No se pudo guardar el respaldo: $($_.Exception.Message)"; return $null }
}
# El respaldo se guarda tras CADA cambio, no solo al final: si el proceso se corta a la fuerza (cancelar mata el árbol y el «finally» no corre), lo ya cambiado sigue siendo revertible
$script:RutaRespaldoActual = $null
function Sync-Respaldo { [void](Save-Respaldo -Modo $Modo) }

# ---------------------------------------------------------------------
#  Ventanas
# ---------------------------------------------------------------------
function Select-ModoOptimizacion {
    [CmdletBinding()]
    param()

    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop

    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'Optimizador Personal'
    $f.StartPosition = 'CenterScreen'; $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false; $f.TopMost = $true
    $f.ClientSize = New-Object System.Drawing.Size(760, 590)

    $t = New-Object System.Windows.Forms.Label
    $t.Text = 'Elige qué quieres hacer (todo lo que cambia el sistema se respalda y se puede revertir)'
    $t.Font = [System.Drawing.SystemFonts]::DefaultFont
    $t.AutoSize = $true; $t.Location = New-Object System.Drawing.Point(20, 15)
    $f.Controls.Add($t)

    $opciones = @(
        @('Analizar', 'Solo diagnostica y recomienda. No cambia nada (empieza por aquí)')
        @('PerfilJuego', 'PERFIL: todo para jugar (Fluidez + Juego + Energía + Red)')
        @('PerfilTrabajo', 'PERFIL: equilibrado y cómodo (Normal + Energía + Privacidad + comodidad)')
        @('PerfilTranquilo', 'PERFIL: sin anuncios ni ruido (Normal + Fluidez + Privacidad)')
        @('PerfilAhorro', 'PERFIL: poco consumo, para Internet y poco más (Economizador + Fluidez)')
        @('PerfilEquilibrado', 'PERFIL: lo que trae Windows para el día a día (Normal)')
        @('Fluidez', 'Efectos ligeros, sin apps en segundo plano ni anuncios, Edge sin precarga')
        @('Juego', 'Máxima potencia, HAGS, GameDVR fuera y prioridad multimedia')
        @('Normal', 'Plan equilibrado y reparto multimedia por defecto')
        @('Privacidad', 'Anuncios, Copilot/Recall, actividad, telemetría de opinión y OneDrive')
        @('Limpieza', 'Temporales, caché de Windows Update y navegadores; dice lo liberado')
        @('Arranque', 'Elegir qué programas arrancan con Windows')
        @('Energia', 'Sin inicio rápido, USB sin suspensión selectiva y sin retraso al arrancar apps')
        @('Red', 'Sin limitación de red multimedia, Wi-Fi a máximo rendimiento y ratón sin aceleración')
        @('Revertir', 'Deshacer un modo anterior con su respaldo')
    )
    $radios = @(); $y = 50
    foreach ($o in $opciones) {
        $r = New-Object System.Windows.Forms.RadioButton
        $r.Text = "$($o[0])  -  $($o[1])"; $r.Tag = $o[0]; $r.AutoSize = $true
        $r.Location = New-Object System.Drawing.Point(20, $y); $f.Controls.Add($r); $radios += $r; $y += 31
    }
    $radios[0].Checked = $true

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Aceptar'; $ok.Size = New-Object System.Drawing.Size(90, 30); $ok.Location = New-Object System.Drawing.Point(550, 545); $ok.DialogResult = 'OK'
    $no = New-Object System.Windows.Forms.Button
    $no.Text = 'Cancelar'; $no.Size = New-Object System.Drawing.Size(90, 30); $no.Location = New-Object System.Drawing.Point(650, 545); $no.DialogResult = 'Cancel'
    $f.Controls.AddRange(@($ok, $no)); $f.AcceptButton = $ok; $f.CancelButton = $no

    $sel = $null
    try {
        if ($f.ShowDialog() -eq 'OK') { foreach ($r in $radios) { if ($r.Checked) { $sel = [string]$r.Tag; break } } }
    }
    finally { $f.Dispose() }
    return $sel
}

# ---------------------------------------------------------------------
#  Arranque de programas
# ---------------------------------------------------------------------
function Test-EntradaHabilitada {
    [CmdletBinding()]
    param([string]$Aprobacion, [string]$Nombre)
    try {
        $v = (Get-ItemProperty -LiteralPath $Aprobacion -Name $Nombre -ErrorAction Stop).$Nombre
        if ($v -is [byte[]] -and $v.Count -gt 0) { return (($v[0] -band 1) -eq 0) }
    }
    catch { Write-Verbose 'sin registro de aprobación: se considera habilitada' }
    return $true
}

function Get-EntradaArranque {
    [CmdletBinding()]
    param()

    $aprobBase = 'Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    $registro = @(
        @{ Origen = 'Usuario (Run)'; Ruta = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Aprob = "HKCU:\Software\$aprobBase\Run" }
        @{ Origen = 'Equipo (Run)'; Ruta = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Aprob = "HKLM:\SOFTWARE\$aprobBase\Run" }
        @{ Origen = 'Equipo 32 bits (Run)'; Ruta = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Aprob = "HKLM:\SOFTWARE\$aprobBase\Run32" }
    )
    foreach ($d in $registro) {
        if (-not (Test-Path -LiteralPath $d.Ruta)) { continue }
        $props = Get-ItemProperty -LiteralPath $d.Ruta
        foreach ($p in $props.PSObject.Properties) {
            if ($p.MemberType -ne 'NoteProperty' -or $p.Name -in 'PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider') { continue }
            [pscustomobject]@{ Nombre = $p.Name; Comando = [string]$p.Value; Origen = $d.Origen; Aprobacion = $d.Aprob; Habilitado = (Test-EntradaHabilitada -Aprobacion $d.Aprob -Nombre $p.Name) }
        }
    }
    $carpetas = @(
        @{ Origen = 'Carpeta Inicio (usuario)'; Ruta = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"; Aprob = "HKCU:\Software\$aprobBase\StartupFolder" }
        @{ Origen = 'Carpeta Inicio (equipo)'; Ruta = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"; Aprob = "HKLM:\SOFTWARE\$aprobBase\StartupFolder" }
    )
    foreach ($d in $carpetas) {
        if (-not (Test-Path -LiteralPath $d.Ruta)) { continue }
        foreach ($a in Get-ChildItem -LiteralPath $d.Ruta -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' }) {
            [pscustomobject]@{ Nombre = $a.Name; Comando = $a.FullName; Origen = $d.Origen; Aprobacion = $d.Aprob; Habilitado = (Test-EntradaHabilitada -Aprobacion $d.Aprob -Nombre $a.Name) }
        }
    }
}

function Show-FormularioArranque {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object[]]$Entradas)

    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'Programas de inicio'; $f.StartPosition = 'CenterScreen'; $f.TopMost = $true; $f.ClientSize = New-Object System.Drawing.Size(900, 540)

    $l = New-Object System.Windows.Forms.Label
    $l.Text = 'Marcado = arranca con Windows. DESMARCA lo que no necesites en el inicio (se puede volver a marcar). No hace falta quitar antivirus, drivers ni software de tu equipo.'
    $l.Location = New-Object System.Drawing.Point(12, 10); $l.Size = New-Object System.Drawing.Size(876, 36)
    $f.Controls.Add($l)

    $lista = New-Object System.Windows.Forms.CheckedListBox
    $lista.CheckOnClick = $true; $lista.HorizontalScrollbar = $true
    $lista.Location = New-Object System.Drawing.Point(12, 52); $lista.Size = New-Object System.Drawing.Size(876, 430)
    foreach ($e in $Entradas) {
        $cmd = if ($e.Comando.Length -gt 90) { $e.Comando.Substring(0, 90) + '...' } else { $e.Comando }
        [void]$lista.Items.Add("$($e.Nombre)   [$($e.Origen)]   $cmd", $e.Habilitado)
    }
    $f.Controls.Add($lista)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Aplicar'; $ok.Location = New-Object System.Drawing.Point(690, 495); $ok.Size = New-Object System.Drawing.Size(90, 30); $ok.DialogResult = 'OK'
    $no = New-Object System.Windows.Forms.Button
    $no.Text = 'Cancelar'; $no.Location = New-Object System.Drawing.Point(798, 495); $no.Size = New-Object System.Drawing.Size(90, 30); $no.DialogResult = 'Cancel'
    $f.Controls.AddRange(@($ok, $no)); $f.CancelButton = $no

    $cambios = @()
    try {
        if ($f.ShowDialog() -eq 'OK') {
            for ($i = 0; $i -lt $Entradas.Count; $i++) {
                $nuevo = $lista.GetItemChecked($i)
                if ($nuevo -ne $Entradas[$i].Habilitado) { $cambios += [pscustomobject]@{ Entrada = $Entradas[$i]; Habilitar = $nuevo } }
            }
        }
        else { return $null }
    }
    finally { $f.Dispose() }
    return , $cambios
}

function Invoke-ModoArranque {
    [CmdletBinding()]
    param()

    Write-Output "`n$($E.Lupa) PROGRAMAS DE INICIO DE WINDOWS..."
    $entradas = @(Get-EntradaArranque)
    if ($entradas.Count -eq 0) { Write-Output "$($E.OK) No hay programas de inicio en el registro ni en las carpetas de inicio."; return }
    Write-Output "$($E.Info) Entradas encontradas: $($entradas.Count) ($(@($entradas | Where-Object { $_.Habilitado }).Count) activas)."

    $cambios = Show-FormularioArranque -Entradas $entradas
    if ($null -eq $cambios) { Write-Output "$($E.Aviso) Cancelado: no se cambió nada."; return }
    if ($cambios.Count -eq 0) { Write-Output "$($E.Info) No marcaste ningún cambio."; return }

    foreach ($c in $cambios) {
        $bytes = [byte[]](@(if ($c.Habilitar) { 2 } else { 3 }) + @(0) * 11)
        if (Set-ValorRegistro -Ruta $c.Entrada.Aprobacion -Nombre $c.Entrada.Nombre -Valor $bytes -Tipo 'Binary' -Opcional) {
            Write-Output "  $($E.OK) $($c.Entrada.Nombre): $(if ($c.Habilitar) { 'activado' } else { 'desactivado' }) en el inicio."
        }
        else { Write-Output "  $($E.Aviso) No se pudo cambiar $($c.Entrada.Nombre) (¿permisos?)." }
    }
    Write-Output "$($E.OK) Los cambios se aplican en el próximo inicio de sesión."
}

# ---------------------------------------------------------------------
#  Análisis (solo lectura)
# ---------------------------------------------------------------------
function Invoke-Analisis {
    [CmdletBinding()]
    param()

    Write-Output "`n$($E.Lupa) DIAGNÓSTICO RÁPIDO (no cambia nada)..."
    $recomendaciones = New-Object System.Collections.Generic.List[string]

    $so = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($so) {
        $dias = [math]::Round(((Get-Date) - $so.LastBootUpTime).TotalDays, 1)
        Write-Output "  $($E.Info) Tiempo encendido sin reiniciar: $dias días."
        if ($dias -ge 7) { $recomendaciones.Add("Reinicia el equipo: lleva $dias días encendido (Inicio rápido acumula estado y fugas de memoria).") }
        $totalGB = [math]::Round($so.TotalVisibleMemorySize / 1MB, 1); $libreGB = [math]::Round($so.FreePhysicalMemory / 1MB, 1)
        $uso = [math]::Round((1 - $so.FreePhysicalMemory / $so.TotalVisibleMemorySize) * 100)
        Write-Output "  $($E.Info) RAM: $totalGB GB, en uso $uso % (libres $libreGB GB)."
        if ($uso -ge 85) { $recomendaciones.Add("La RAM está al $uso %: revisa los procesos que más consumen y los programas de inicio.") }
        if ($totalGB -le 8) { $recomendaciones.Add("Solo $totalGB GB de RAM: ampliar memoria sería la mejora de fluidez más notable.") }
    }

    try {
        $unidad = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':')) -ErrorAction Stop
        $total = $unidad.Used + $unidad.Free; $pct = [math]::Round($unidad.Free / $total * 100)
        Write-Output "  $($E.Info) Disco $($env:SystemDrive) libre: $([math]::Round($unidad.Free / 1GB, 1)) GB ($pct %)."
        if ($pct -lt 15) { $recomendaciones.Add("Queda solo el $pct % libre en $($env:SystemDrive): ejecuta el modo Limpieza.") }
    }
    catch { Write-Output "  $($E.Aviso) No se pudo leer el espacio del disco." }

    try {
        $numDisco = (Get-Partition -DriveLetter $env:SystemDrive.TrimEnd(':') -ErrorAction Stop).DiskNumber
        $fisico = Get-PhysicalDisk -DeviceNumber $numDisco -ErrorAction Stop
        Write-Output "  $($E.Info) Disco del sistema: $($fisico.FriendlyName) ($($fisico.MediaType), $($fisico.BusType), salud $($fisico.HealthStatus))."
        if ($fisico.MediaType -eq 'HDD') { $recomendaciones.Add('El sistema está en un disco duro mecánico (HDD): pasar a SSD es la mayor mejora posible de fluidez.') }
        if ($fisico.HealthStatus -ne 'Healthy') { $recomendaciones.Add("El disco reporta salud '$($fisico.HealthStatus)': haz copia de seguridad ya.") }
    }
    catch { Write-Output "  $($E.Info) No se pudo identificar el tipo de disco." }

    $plan = ((& powercfg.exe /getactivescheme 2>&1) | Out-String).Trim()
    Write-Output "  $($E.Info) $plan"
    if ($plan -match 'a1841308-3541-4fab-bc81-f71556f20b4a' -and -not (Test-EsPortatil)) { $recomendaciones.Add('Plan de ahorro de energía en un sobremesa: usa el modo Normal o Juego.') }

    $arranque = @(Get-EntradaArranque | Where-Object { $_.Habilitado })
    Write-Output "  $($E.Info) Programas que arrancan con Windows: $($arranque.Count)."
    if ($arranque.Count -ge 8) { $recomendaciones.Add("Hay $($arranque.Count) programas en el inicio: usa el modo Arranque para quitar los que no necesites.") }

    $pendiente = (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
        (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
    if ($pendiente) { $recomendaciones.Add('Hay un reinicio pendiente (actualizaciones): reinicia antes de medir la fluidez.') }

    Write-Output "`n  Procesos que más memoria usan:"
    foreach ($p in Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5) {
        Write-Output ("    - {0,-28} {1,7} MB" -f $p.ProcessName, [math]::Round($p.WorkingSet64 / 1MB))
    }

    Write-Output "`n$($E.Cohete) RECOMENDACIONES:"
    if ($recomendaciones.Count -eq 0) { Write-Output "  $($E.OK) No se detecta nada llamativo. Modo Fluidez para un ajuste fino." }
    else { foreach ($r in $recomendaciones) { Write-Output "  $($E.Aviso) $r" } }
}

# ---------------------------------------------------------------------
#  Limpieza
# ---------------------------------------------------------------------
function Clear-CarpetaContenido {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Ruta)

    $eliminados = 0; $errores = 0
    if (-not (Test-Path -LiteralPath $Ruta)) { return [pscustomobject]@{ Eliminados = 0; Errores = 0 } }
    try { $elementos = @(Get-ChildItem -LiteralPath $Ruta -Force -ErrorAction Stop) }
    catch { return [pscustomobject]@{ Eliminados = 0; Errores = 1 } }
    foreach ($el in $elementos) {
        try {
            # No se siguen enlaces simbólicos ni uniones
            if (([int]$el.Attributes -band [int][System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            Remove-Item -LiteralPath $el.FullName -Recurse -Force -Confirm:$false -ErrorAction Stop
            $eliminados++
        }
        catch { $errores++ }
    }
    return [pscustomobject]@{ Eliminados = $eliminados; Errores = $errores }
}

function Invoke-LimpiezaTemporales {
    [CmdletBinding()]
    param()

    Write-Output "`n$($E.Disco) LIMPIEZA DE TEMPORALES, CACHÉS Y PAPELERA..."
    $unidad = $env:SystemDrive.TrimEnd(':')
    $libreAntes = (Get-PSDrive -Name $unidad -ErrorAction SilentlyContinue).Free

    $rutas = New-Object System.Collections.Generic.List[string]
    foreach ($r in @($env:TEMP, "$env:LOCALAPPDATA\Microsoft\Windows\INetCache", "$env:SystemRoot\Temp",   # C:\Temp no se toca: no es de Windows y en oficinas la crean a mano para trabajo temporal
            "$env:LOCALAPPDATA\CrashDumps", "$env:ProgramData\Microsoft\Windows\WER\ReportQueue", "$env:ProgramData\Microsoft\Windows\WER\Temp")) { $rutas.Add($r) }

    # Cachés de navegadores (solo caché: no se tocan cookies, contraseñas ni historial). Se omite el que esté abierto.
    $navegadores = @(
        @{ Nombre = 'Chrome'; Proceso = 'chrome'; Base = "$env:LOCALAPPDATA\Google\Chrome\User Data" }
        @{ Nombre = 'Edge'; Proceso = 'msedge'; Base = "$env:LOCALAPPDATA\Microsoft\Edge\User Data" }
        @{ Nombre = 'Brave'; Proceso = 'brave'; Base = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data" }
    )
    foreach ($n in $navegadores) {
        if (-not (Test-Path -LiteralPath $n.Base)) { continue }
        if (Get-Process -Name $n.Proceso -ErrorAction SilentlyContinue) { Write-Output "  $($E.Aviso) $($n.Nombre) está abierto: se omite su caché."; continue }
        foreach ($perfil in Get-ChildItem -LiteralPath $n.Base -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' }) {
            foreach ($sub in 'Cache', 'Code Cache', 'GPUCache', 'Service Worker\CacheStorage') { $rutas.Add((Join-Path -Path $perfil.FullName -ChildPath $sub)) }
        }
    }
    $firefox = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
    if ((Test-Path -LiteralPath $firefox) -and -not (Get-Process -Name 'firefox' -ErrorAction SilentlyContinue)) {
        foreach ($p in Get-ChildItem -LiteralPath $firefox -Directory -ErrorAction SilentlyContinue) { $rutas.Add((Join-Path -Path $p.FullName -ChildPath 'cache2')) }
    }

    $total = 0; $fallos = 0
    foreach ($ruta in $rutas) {
        if ([string]::IsNullOrWhiteSpace($ruta) -or -not (Test-Path -LiteralPath $ruta)) { continue }
        $r = Clear-CarpetaContenido -Ruta $ruta
        $total += $r.Eliminados; $fallos += $r.Errores
    }

    # Caché de Windows Update: se paran sus servicios para poder borrar los ficheros y se vuelven a arrancar
    $parados = @()
    foreach ($s in 'wuauserv', 'bits') {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') { try { Stop-Service -Name $s -Force -ErrorAction Stop; $parados += $s } catch { Write-Verbose "No se pudo parar $s" } }
    }
    try {
        $r = Clear-CarpetaContenido -Ruta "$env:SystemRoot\SoftwareDistribution\Download"
        $total += $r.Eliminados; $fallos += $r.Errores
    }
    finally { foreach ($s in $parados) { try { Start-Service -Name $s -ErrorAction Stop } catch { Write-Verbose "No se pudo arrancar $s" } } }

    if (Get-Command -Name 'Delete-DeliveryOptimizationCache' -ErrorAction SilentlyContinue) {
        try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop; Write-Output "  $($E.OK) Caché de Optimización de distribución vaciada." }
        catch { Write-Verbose 'sin caché de Delivery Optimization que vaciar' }
    }

    # Borrado definitivo de todas las cuentas: se pregunta siempre que haya ventana (Confirm-Accion acepta solo en revisión automática)
    if (Confirm-Accion "Se vaciará la Papelera de la unidad del sistema (todas las cuentas). Los archivos que contiene no se podrán recuperar.`n`n¿Vaciarla?" 'Vaciar Papelera') {
        try { Clear-RecycleBin -DriveLetter $env:SystemDrive.TrimEnd(':') -Force -ErrorAction Stop; Write-Output "  $($E.OK) Papelera vaciada." }
        catch { Write-Output "  $($E.Info) Papelera: nada que vaciar o no accesible." }
    } else { Write-Output "  $($E.Info) Papelera: se deja como está." }

    $libreDespues = (Get-PSDrive -Name $unidad -ErrorAction SilentlyContinue).Free
    if ($libreAntes -and $libreDespues) {
        $gb = [math]::Round(($libreDespues - $libreAntes) / 1GB, 2)
        if ($gb -lt 0) { $gb = 0 }
        Write-Output "  $($E.OK) Elementos eliminados: $total. Espacio liberado en ${unidad}: ~$gb GB (libres ahora: $([math]::Round($libreDespues / 1GB, 1)) GB)."
    }
    else { Write-Output "  $($E.OK) Elementos eliminados: $total." }
    if ($fallos -gt 0) { Write-Output "  $($E.Info) $fallos elemento(s) estaban en uso y se omitieron (normal)." }
    Write-Output "  $($E.OK) No se eliminan Prefetch ni ETLLogs."
}

# ---------------------------------------------------------------------
#  Modos que cambian la configuración
# ---------------------------------------------------------------------
function Invoke-ModoFluidez {
    [CmdletBinding()]
    param()

    Write-Output "`n$($E.Cohete) APLICANDO MODO FLUIDEZ..."
    $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'

    # Efectos visuales ligeros (se mantiene el suavizado de fuentes)
    [void](Set-ValorRegistro -Ruta 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Nombre 'EnableTransparency' -Valor 0 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta 'HKCU:\Control Panel\Desktop\WindowMetrics' -Nombre 'MinAnimate' -Valor '0' -Tipo 'String' -Opcional)
    [void](Set-ValorRegistro -Ruta $adv -Nombre 'TaskbarAnimations' -Valor 0 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta 'HKCU:\Control Panel\Desktop' -Nombre 'MenuShowDelay' -Valor '50' -Tipo 'String' -Opcional)
    Write-Output "  $($E.OK) Transparencias y animaciones de ventanas/barra desactivadas; menús más rápidos."

    # Explorador: no adivinar el tipo de carpeta (Música/Imágenes) al abrirla; evita que carpetas grandes tarden en pintarse
    [void](Set-ValorRegistro -Ruta 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell' -Nombre 'FolderType' -Valor 'NotSpecified' -Tipo 'String' -Opcional)

    # Los programas de inicio arrancan sin espera artificial
    [void](Set-ValorRegistro -Ruta 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' -Nombre 'StartupDelayInMSec' -Valor 0 -Tipo 'DWord' -Opcional)

    # Aplicaciones de Microsoft Store en segundo plano
    [void](Set-ValorRegistro -Ruta 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' -Nombre 'GlobalUserDisabled' -Valor 1 -Tipo 'DWord' -Opcional)
    Write-Output "  $($E.OK) Apps de la Store sin ejecutarse en segundo plano."

    # Sugerencias, anuncios y apps promocionadas (Inicio, bloqueo, notificaciones)
    foreach ($n in 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled', 'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled',
        'SubscribedContent-338393Enabled', 'SubscribedContent-310093Enabled', 'SilentInstalledAppsEnabled', 'SystemPaneSuggestionsEnabled',
        'SoftLandingEnabled', 'RotatingLockScreenEnabled', 'OemPreInstalledAppsEnabled', 'PreInstalledAppsEnabled') {
        [void](Set-ValorRegistro -Ruta $cdm -Nombre $n -Valor 0 -Tipo 'DWord' -Opcional)
    }
    [void](Set-ValorRegistro -Ruta 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' -Nombre 'Enabled' -Valor 0 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Nombre 'BingSearchEnabled' -Valor 0 -Tipo 'DWord' -Opcional)
    Write-Output "  $($E.OK) Sugerencias, anuncios y búsqueda web en Inicio desactivados."

    # Widgets y Chat de la barra (Windows 11 puede proteger estas claves: es normal que alguna se rechace)
    [void](Set-ValorRegistro -Ruta $adv -Nombre 'TaskbarDa' -Valor 0 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta $adv -Nombre 'TaskbarMn' -Valor 0 -Tipo 'DWord' -Opcional)

    # Edge: sin precarga al iniciar ni procesos en segundo plano (ahorra RAM y arranque)
    [void](Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Nombre 'StartupBoostEnabled' -Valor 0 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Nombre 'BackgroundModeEnabled' -Valor 0 -Tipo 'DWord' -Opcional)
    Write-Output "  $($E.OK) Edge sin precarga ni procesos en segundo plano."

    # Servicios que casi nadie usa: a Manual (siguen funcionando si algo los pide)
    Write-Output "  $($E.Info) Servicios innecesarios a Manual:"
    foreach ($s in 'MapsBroker', 'RetailDemo', 'WMPNetworkSvc', 'Fax', 'wisvc') { Set-ServicioInicio -Nombre $s -Tipo Manual }

    Write-Output "`n  $($E.Info) Cierra sesión o reinicia para ver todos los cambios. Para quitar programas del inicio usa el modo Arranque."
    Write-Output "$($E.OK) MODO FLUIDEZ APLICADO ($($script:Aplicados) ajustes, $($script:Rechazados) rechazados por Windows)."
}

function Invoke-ModoJuego {
    [CmdletBinding()]
    param()

    Write-Output "`n$($E.Cohete) APLICANDO MODO JUEGO..."
    $portatil = Test-EsPortatil

    # Plan: Máximo rendimiento si Windows lo permite; si no, Alto rendimiento
    $ultimate = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
    $existe = ((& powercfg.exe /list 2>&1) | Out-String) -match $ultimate
    if (-not $existe -and -not $portatil) { & powercfg.exe /duplicatescheme $ultimate 2>&1 | Out-Null }
    $script:PlanOk = $false
    if (-not $portatil) { Set-PlanEnergia -Guid $ultimate -Nombre 'Máximo rendimiento' }
    if (-not $script:PlanOk) { Set-PlanEnergia -Guid '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' -Nombre 'Alto rendimiento' }
    if ($portatil) { Write-Output "  $($E.Aviso) Es un portátil: la batería durará menos con este plan. Usa el modo Normal al desenchufar." }

    # HAGS y modo Juego; grabación en segundo plano fuera
    [void](Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Nombre 'HwSchMode' -Valor 2 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta 'HKCU:\Software\Microsoft\GameBar' -Nombre 'AllowAutoGameMode' -Valor 1 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta 'HKCU:\Software\Microsoft\GameBar' -Nombre 'AutoGameModeEnabled' -Valor 1 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta 'HKCU:\System\GameConfigStore' -Nombre 'GameDVR_Enabled' -Valor 0 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -Nombre 'AppCaptureEnabled' -Valor 0 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' -Nombre 'AllowGameDVR' -Valor 0 -Tipo 'DWord' -Opcional)

    # Programador multimedia: prioridad para juegos
    $mm = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
    [void](Set-ValorRegistro -Ruta $mm -Nombre 'SystemResponsiveness' -Valor 0 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta "$mm\Tasks\Games" -Nombre 'Scheduling Category' -Valor 'High' -Tipo 'String' -Opcional)
    [void](Set-ValorRegistro -Ruta "$mm\Tasks\Games" -Nombre 'GPU Priority' -Valor 8 -Tipo 'DWord' -Opcional)

    # En sobremesa se evita que Windows limite la CPU de procesos en segundo plano (en portátil gasta batería)
    if (-not $portatil) {
        [void](Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' -Nombre 'PowerThrottlingOff' -Valor 1 -Tipo 'DWord' -Opcional)
    }

    Write-Output "$($E.OK) HAGS, Modo Juego, GameDVR y prioridad multimedia ajustados ($($script:Aplicados) cambios, $($script:Rechazados) rechazados)."
    Write-Output "$($E.OK) SmartScreen y Defender se mantienen sin cambios."
    Write-Output "$($E.Aviso) Reinicia el equipo para aplicar HAGS y los cambios de gráficos."
    Write-Output "`n$($E.OK) MODO JUEGO APLICADO."
}

function Invoke-ModoNormal {
    [CmdletBinding()]
    param()

    Write-Output "`n$($E.Refresh) APLICANDO MODO NORMAL / USO DIARIO..."
    Set-PlanEnergia -Guid '381b4222-f694-41f0-9685-ff5bb260df2e' -Nombre 'Equilibrado'
    $mm = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
    [void](Set-ValorRegistro -Ruta $mm -Nombre 'SystemResponsiveness' -Valor 20 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta "$mm\Tasks\Games" -Nombre 'Scheduling Category' -Valor 'Medium' -Tipo 'String' -Opcional)
    [void](Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' -Nombre 'PowerThrottlingOff' -Valor 0 -Tipo 'DWord' -Opcional)
    Write-Output "$($E.OK) Plan equilibrado y reparto multimedia por defecto."
    Write-Output "$($E.Info) Para deshacer del todo un modo anterior (HAGS, GameDVR...) usa el modo Revertir."
    Write-Output "`n$($E.OK) MODO NORMAL APLICADO."
}

function Invoke-ModoPrivacidad {
    [CmdletBinding()]
    param()

    Write-Output "`n$($E.Lupa) APLICANDO MODO PRIVACIDAD..."
    [void](Set-ValorRegistro -Ruta 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Nombre 'HideFileExt' -Valor 0 -Tipo 'DWord' -Opcional)

    # Descargas P2P y contenido patrocinado
    [void](Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' -Nombre 'DODownloadMode' -Valor 0 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config' -Nombre 'DODownloadMode' -Valor 0 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Nombre 'DisableWindowsConsumerFeatures' -Valor 1 -Tipo 'DWord' -Opcional)

    # Cortana, búsqueda web, publicidad personalizada
    [void](Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -Nombre 'AllowCortana' -Valor 0 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Nombre 'AllowCloudSearch' -Valor 0 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' -Nombre 'Enabled' -Valor 0 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' -Nombre 'TailoredExperiencesWithDiagnosticDataEnabled' -Valor 0 -Tipo 'DWord' -Opcional)

    # Historial de actividad, Copilot y análisis de IA (Recall)
    $sys = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
    [void](Set-ValorRegistro -Ruta $sys -Nombre 'EnableActivityFeed' -Valor 0 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta $sys -Nombre 'PublishUserActivities' -Valor 0 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta $sys -Nombre 'UploadUserActivities' -Valor 0 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' -Nombre 'TurnOffWindowsCopilot' -Valor 1 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' -Nombre 'DisableAIDataAnalysis' -Valor 1 -Tipo 'DWord' -Opcional)

    # Telemetría y avisos de opinión
    [void](Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Nombre 'DoNotShowFeedbackNotifications' -Valor 1 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack' -Nombre 'DiagnosticDataViewing' -Valor 0 -Tipo 'DWord' -Opcional)
    # Datos de diagnóstico al mínimo (en Home/Pro Windows lo trata como «Necesarios») y sin acceso a la ubicación por directiva
    [void](Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Nombre 'AllowTelemetry' -Valor 0 -Tipo 'DWord' -Opcional)
    if (Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' -Nombre 'DisableLocation' -Valor 1 -Tipo 'DWord' -Opcional) {
        Write-Output "  $($E.Info) Ubicación desactivada por directiva: «Encontrar mi dispositivo» y Mapas no podrán localizar el equipo (Revertir quita el valor; la clave vacía puede quedar)."
    }

    # OneDrive: ya no se desactiva su sincronización (DisableFileSyncNGSC): en equipos de clientes que guardan Escritorio y Documentos en OneDrive dejaba de hacer copias en la nube sin avisar

    Write-Output "$($E.OK) Privacidad ajustada: $($script:Aplicados) cambios, $($script:Rechazados) rechazados por Windows."
    Write-Output "$($E.Info) No se eliminan Prefetch ni ETLLogs. Reinicia Explorer o el equipo para ver las extensiones."
    Write-Output "`n$($E.OK) MODO PRIVACIDAD APLICADO."
}

function Set-ValorPlanEnergia {
    <# Cambia un valor del plan activo con powercfg guardando el anterior (CA y CC) para Revertir.
       $Dc = $null deja la batería como está (portátiles). #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Subgrupo,
        [Parameter(Mandatory = $true)][string]$Ajuste,
        [Parameter(Mandatory = $true)][int]$Ac,
        $Dc = $null
    )

    $plan = Get-PlanEnergiaActivo
    if (-not $plan) { Write-Output "  $($E.Aviso) No se pudo leer el plan activo; se omite este ajuste."; return }
    # Los dos índices actuales salen en el orden CA, CC (se leen por su formato 0x..., así vale en cualquier idioma)
    $q = ((& powercfg.exe /query $plan $Subgrupo $Ajuste 2>&1) | Out-String)
    $v = @([regex]::Matches($q, '0x[0-9a-fA-F]{8}') | ForEach-Object { [Convert]::ToInt32($_.Value.Substring(2), 16) })
    if ($v.Count -lt 2) { Write-Output "  $($E.Info) Este plan no tiene el ajuste (${Ajuste}); se omite."; return }
    $acPrevio = $v[$v.Count - 2]; $dcPrevio = $v[$v.Count - 1]
    & powercfg.exe /setacvalueindex $plan $Subgrupo $Ajuste $Ac 2>&1 | Out-Null
    $ok = ($LASTEXITCODE -eq 0)
    if ($ok -and $null -ne $Dc) { & powercfg.exe /setdcvalueindex $plan $Subgrupo $Ajuste $Dc 2>&1 | Out-Null; $ok = ($LASTEXITCODE -eq 0) }
    if (-not $ok) { $script:Rechazados++; Write-Output "  $($E.Aviso) powercfg no pudo cambiar el ajuste ${Ajuste}."; return }
    & powercfg.exe /setactive $plan 2>&1 | Out-Null
    $script:Respaldo.Add([pscustomobject]@{ Tipo = 'PowerCfg'; Plan = $plan; Subgrupo = $Subgrupo; Ajuste = $Ajuste; Ac = $acPrevio; Dc = $dcPrevio; TocoDc = ($null -ne $Dc) }); Sync-Respaldo
    $script:Aplicados++
}

function Invoke-ModoEnergia {
    [CmdletBinding()]
    param()

    Write-Output "`n$($E.Refresh) APLICANDO MODO ENERGÍA Y ARRANQUE..."
    $portatil = Test-EsPortatil

    # Inicio rápido: apaga de verdad (aplica actualizaciones, libera USB y discos, evita fallos tras "apagar")
    [void](Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Nombre 'HiberbootEnabled' -Valor 0 -Tipo 'DWord' -Opcional)
    Write-Output "  $($E.OK) Inicio rápido desactivado: «Apagar» apaga de verdad. El arranque tarda algo más, pero se corrigen muchos fallos raros."

    # Suspensión selectiva de USB: evita que ratones, teclados y discos USB se "duerman" o se desconecten
    $usb = '2a737441-1930-4402-8d77-b2bebba308a3'; $susp = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
    if ($portatil) { Set-ValorPlanEnergia -Subgrupo $usb -Ajuste $susp -Ac 0 }
    else { Set-ValorPlanEnergia -Subgrupo $usb -Ajuste $susp -Ac 0 -Dc 0 }
    Write-Output "  $($E.OK) Suspensión selectiva de USB desactivada en el plan activo$(if ($portatil) { ' (solo con corriente; con batería se deja ahorrar)' })."

    # Las apps de inicio arrancan sin el retraso artificial que mete Windows
    [void](Set-ValorRegistro -Ruta 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' -Nombre 'StartupDelayInMSec' -Valor 0 -Tipo 'DWord' -Opcional)
    Write-Output "  $($E.OK) Retraso de arranque de aplicaciones eliminado."

    Write-Output "$($E.Info) No se toca la hibernación (en portátiles es la red de seguridad si se agota la batería). Para elegir qué programas arrancan usa el modo Arranque."
    Write-Output "$($E.OK) Energía y arranque ajustados ($($script:Aplicados) cambios, $($script:Rechazados) rechazados). Reinicia para notarlo."
    Write-Output "`n$($E.OK) MODO ENERGÍA APLICADO."
}

function Invoke-ModoRed {
    [CmdletBinding()]
    param()

    Write-Output "`n$($E.Refresh) APLICANDO MODO RED Y JUEGOS..."
    $portatil = Test-EsPortatil

    # Windows limita el tráfico de red de fondo mientras suena audio/vídeo/juego; -1 (0xFFFFFFFF) lo quita
    [void](Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Nombre 'NetworkThrottlingIndex' -Valor ([int]-1) -Tipo 'DWord' -Opcional)
    Write-Output "  $($E.OK) Limitación de red multimedia desactivada (menos picos de latencia con juegos y llamadas)."

    # Adaptador Wi-Fi a máximo rendimiento en el plan activo (en portátil solo con corriente)
    $wifi = '19cbb8fa-5279-450e-9fac-8a3d5fedd0c1'; $modo = '12bbebe6-58d6-4636-95bb-3217ef867c1a'
    if ($portatil) { Set-ValorPlanEnergia -Subgrupo $wifi -Ajuste $modo -Ac 0 }
    else { Set-ValorPlanEnergia -Subgrupo $wifi -Ajuste $modo -Ac 0 -Dc 0 }
    Write-Output "  $($E.OK) Wi-Fi sin ahorro de energía en el plan activo$(if ($portatil) { ' (solo con corriente)' })."

    # Puntero sin aceleración: el ratón responde igual a la misma distancia, mejor para apuntar
    $mouse = 'HKCU:\Control Panel\Mouse'
    foreach ($n in 'MouseSpeed', 'MouseThreshold1', 'MouseThreshold2') { [void](Set-ValorRegistro -Ruta $mouse -Nombre $n -Valor '0' -Tipo 'String' -Opcional) }
    Write-Output "  $($E.OK) Aceleración del ratón desactivada (se nota al cerrar sesión)."

    Write-Output "$($E.Info) No se toca el algoritmo de Nagle ni IPv6/Teredo: el beneficio es discutible y varía según la red. Para fijar DNS o IP usa «Cambiar IP»."
    Write-Output "`n$($E.OK) MODO RED APLICADO ($($script:Aplicados) cambios, $($script:Rechazados) rechazados)."
}

function Invoke-AjustesTrabajo {
    [CmdletBinding()]
    param()

    Write-Output "`n$($E.Refresh) AJUSTES DE COMODIDAD PARA TRABAJAR..."
    # Rutas largas (>260 caracteres) en Explorador y aplicaciones modernas
    [void](Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Nombre 'LongPathsEnabled' -Valor 1 -Tipo 'DWord' -Opcional)
    # Pulsar Mayús 5 veces ya no abre el aviso de Teclas especiales
    [void](Set-ValorRegistro -Ruta 'HKCU:\Control Panel\Accessibility\StickyKeys' -Nombre 'Flags' -Valor '506' -Tipo 'String' -Opcional)
    # «Finalizar tarea» con clic derecho en la barra de tareas
    [void](Set-ValorRegistro -Ruta 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings' -Nombre 'TaskbarEndTask' -Valor 1 -Tipo 'DWord' -Opcional)
    # Pantalla azul con el código de error a la vista (útil para diagnosticar)
    [void](Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -Nombre 'DisplayParameters' -Valor 1 -Tipo 'DWord' -Opcional)
    Write-Output "  $($E.OK) Rutas largas, Teclas especiales sin aviso, «Finalizar tarea» en la barra y detalle en pantallas azules."
}

function Invoke-RestaurarEstandar {
    # Devuelve a los valores de fábrica de Windows lo que tocan los modos Ahorro y Juego (con respaldo, así que «Revertir» también lo deshace)
    [CmdletBinding()]
    param()

    Write-Output "$($E.Refresh) Restaurando valores estándar de Windows (efectos, segundo plano, grabación de juegos, red, ratón)..."
    [void](Set-ValorRegistro -Ruta 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Nombre 'EnableTransparency' -Valor 1 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta 'HKCU:\Control Panel\Desktop\WindowMetrics' -Nombre 'MinAnimate' -Valor '1' -Tipo 'String' -Opcional)
    [void](Set-ValorRegistro -Ruta 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Nombre 'TaskbarAnimations' -Valor 1 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' -Nombre 'GlobalUserDisabled' -Valor 0 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta 'HKCU:\System\GameConfigStore' -Nombre 'GameDVR_Enabled' -Valor 1 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -Nombre 'AppCaptureEnabled' -Valor 1 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta 'HKCU:\Control Panel\Desktop' -Nombre 'MenuShowDelay' -Valor '400' -Tipo 'String' -Opcional)
    [void](Set-ValorRegistro -Ruta 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Nombre 'BingSearchEnabled' -Valor 1 -Tipo 'DWord' -Opcional)
    foreach ($n in 'TaskbarDa', 'TaskbarMn') { [void](Set-ValorRegistro -Ruta 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Nombre $n -Valor 1 -Tipo 'DWord' -Opcional) }
    # Las políticas de máquina se QUITAN (aunque valgan 1, Windows y Edge muestran «administrado por tu organización»). Las pone Ahorro/Juego; «Revertir» las deja como estaban antes.
    foreach ($p in @(@('HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR', 'AllowGameDVR'), @('HKLM:\SOFTWARE\Policies\Microsoft\Edge', 'StartupBoostEnabled'), @('HKLM:\SOFTWARE\Policies\Microsoft\Edge', 'BackgroundModeEnabled'))) { Remove-ItemProperty -LiteralPath $p[0] -Name $p[1] -ErrorAction SilentlyContinue }
    [void](Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Nombre 'HiberbootEnabled' -Valor 1 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Nombre 'NetworkThrottlingIndex' -Valor 10 -Tipo 'DWord' -Opcional)
    $mouse = 'HKCU:\Control Panel\Mouse'
    [void](Set-ValorRegistro -Ruta $mouse -Nombre 'MouseSpeed' -Valor '1' -Tipo 'String' -Opcional)
    [void](Set-ValorRegistro -Ruta $mouse -Nombre 'MouseThreshold1' -Valor '6' -Tipo 'String' -Opcional)
    [void](Set-ValorRegistro -Ruta $mouse -Nombre 'MouseThreshold2' -Valor '10' -Tipo 'String' -Opcional)
    Write-Output "$($E.OK) Valores estándar restaurados (los servicios puestos a Manual por Ahorro se dejan como están; «Revertir» los devuelve)."
}

function Invoke-ModoAhorro {
    [CmdletBinding()]
    param()

    Write-Output "`n$($E.Refresh) APLICANDO MODO AHORRO (internet y poco más)..."
    # Plan Economizador (a1841308...): si Windows no lo trae a la vista se avisa y se sigue con lo demás
    if (((& powercfg.exe /list 2>&1) | Out-String) -notmatch 'a1841308-3541-4fab-bc81-f71556f20b4a') { & powercfg.exe /duplicatescheme a1841308-3541-4fab-bc81-f71556f20b4a 2>&1 | Out-Null }   # en equipos que lo ocultan
    Set-PlanEnergia -Guid 'a1841308-3541-4fab-bc81-f71556f20b4a' -Nombre 'Economizador'
    $mm = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
    [void](Set-ValorRegistro -Ruta $mm -Nombre 'SystemResponsiveness' -Valor 20 -Tipo 'DWord' -Opcional)
    [void](Set-ValorRegistro -Ruta "$mm\Tasks\Games" -Nombre 'Scheduling Category' -Valor 'Medium' -Tipo 'String' -Opcional)
    [void](Set-ValorRegistro -Ruta 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' -Nombre 'PowerThrottlingOff' -Valor 0 -Tipo 'DWord' -Opcional)
    Write-Output "$($E.OK) Plan de bajo consumo y reparto multimedia por defecto."
}

function Invoke-Perfil {
    <# Un perfil es una combinación de modos que ya existen; se ejecuta con un solo punto de restauración y un solo respaldo. #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][ValidateSet('Juego', 'Trabajo', 'Tranquilo', 'Ahorro', 'Equilibrado')][string]$Nombre)

    Write-Output "`n$($E.Cohete) PERFIL $($Nombre.ToUpperInvariant())"
    switch ($Nombre) {
        'Juego'     { Invoke-ModoFluidez; Invoke-ModoJuego; Invoke-ModoEnergia; Invoke-ModoRed }   # sin limpieza: cambiar de perfil no debe vaciar la papelera
        'Trabajo'   { Invoke-ModoNormal; Invoke-ModoEnergia; Invoke-ModoPrivacidad; Invoke-AjustesTrabajo }
        'Tranquilo' { Invoke-ModoNormal; Invoke-ModoFluidez; Invoke-ModoPrivacidad }
        'Ahorro'      { Invoke-ModoAhorro; Invoke-ModoFluidez }
        'Equilibrado' { Invoke-ModoNormal; Invoke-RestaurarEstandar }
    }
    Write-Output "`n$($E.OK) PERFIL $($Nombre.ToUpperInvariant()) APLICADO. Para volver atrás usa el modo Revertir."
}

# ---------------------------------------------------------------------
#  Revertir
# ---------------------------------------------------------------------
function Invoke-Revertir {
    [CmdletBinding()]
    param()

    Write-Output "`n$($E.Refresh) REVERTIR UN MODO ANTERIOR..."
    $carpeta = $null
    try { $carpeta = Get-CarpetaRespaldos } catch { Write-Output "$($E.Error) No se pudo abrir la carpeta de respaldos: $($_.Exception.Message)"; return }
    # Solo los respaldos de ESTE equipo (el nombre termina en _EQUIPO.json): aplicar el de otro PC cambiaría servicios, energía y registro por valores que no son los suyos
    $todos = @(Get-ChildItem -LiteralPath $carpeta -Filter 'Optimizador_Respaldo_*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    $archivos = @($todos | Where-Object { $_.Name -like "*_$($env:COMPUTERNAME).json" })
    if ($todos.Count -gt $archivos.Count) { Write-Output "$($E.Info) $($todos.Count - $archivos.Count) respaldo(s) de otros equipos o de versiones antiguas (sin equipo en el nombre) no se ofrecen aquí." }
    if ($archivos.Count -eq 0) { Write-Output "$($E.Aviso) No hay respaldos de este equipo en $carpeta. Solo se pueden revertir modos aplicados con esta versión en este PC."; return }

    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'Revertir'; $f.StartPosition = 'CenterScreen'; $f.TopMost = $true; $f.ClientSize = New-Object System.Drawing.Size(560, 330)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = 'Elige el respaldo que quieres deshacer (el más reciente está arriba):'
    $l.Location = New-Object System.Drawing.Point(12, 10); $l.Size = New-Object System.Drawing.Size(536, 20); $f.Controls.Add($l)
    $caja = New-Object System.Windows.Forms.ListBox
    $caja.Location = New-Object System.Drawing.Point(12, 36); $caja.Size = New-Object System.Drawing.Size(536, 240)
    foreach ($a in $archivos) { [void]$caja.Items.Add($a.Name) }
    $caja.SelectedIndex = 0; $f.Controls.Add($caja)
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Revertir'; $ok.Location = New-Object System.Drawing.Point(350, 288); $ok.Size = New-Object System.Drawing.Size(90, 30); $ok.DialogResult = 'OK'
    $no = New-Object System.Windows.Forms.Button
    $no.Text = 'Cancelar'; $no.Location = New-Object System.Drawing.Point(458, 288); $no.Size = New-Object System.Drawing.Size(90, 30); $no.DialogResult = 'Cancel'
    $f.Controls.AddRange(@($ok, $no)); $f.CancelButton = $no

    $elegido = $null
    try { if ($f.ShowDialog() -eq 'OK' -and $caja.SelectedItem) { $elegido = Join-Path -Path $carpeta -ChildPath ([string]$caja.SelectedItem) } }
    finally { $f.Dispose() }
    if (-not $elegido) { Write-Output "$($E.Aviso) Cancelado: no se cambió nada."; return }

    try { $cambios = @(Get-Content -LiteralPath $elegido -Raw -ErrorAction Stop | ConvertFrom-Json) }
    catch { Write-Output "$($E.Error) No se pudo leer el respaldo: $($_.Exception.Message)"; return }

    $ok1 = 0; $mal = 0
    [array]::Reverse($cambios)
    foreach ($c in $cambios) {
        try {
            switch ($c.Tipo) {
                'Registro' {
                    if ($c.Existia) {
                        $v = $c.Valor
                        switch ($c.TipoValor) {
                            'Binary'      { $v = [byte[]]@($c.Valor) }
                            'DWord'       { $n = [int64]$c.Valor; $v = if ($n -gt [int]::MaxValue) { [uint32]$n } else { [int]$n } }
                            'QWord'       { $v = [int64]$c.Valor }
                            'MultiString' { $v = [string[]]@($c.Valor) }
                        }
                        Set-ItemProperty -LiteralPath $c.Ruta -Name $c.Nombre -Value $v -Type $c.TipoValor -ErrorAction Stop
                    }
                    elseif (Test-Path -LiteralPath $c.Ruta) { Remove-ItemProperty -LiteralPath $c.Ruta -Name $c.Nombre -ErrorAction Stop }
                }
                'Servicio' { Set-Service -Name $c.Nombre -StartupType $c.Previo -ErrorAction Stop }
                'Energia'  { & powercfg.exe /setactive $c.Guid 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw "powercfg devolvió $LASTEXITCODE" } }
                'PowerCfg' {
                    & powercfg.exe /setacvalueindex $c.Plan $c.Subgrupo $c.Ajuste ([int]$c.Ac) 2>&1 | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw "powercfg devolvió $LASTEXITCODE" }
                    if ($c.TocoDc) { & powercfg.exe /setdcvalueindex $c.Plan $c.Subgrupo $c.Ajuste ([int]$c.Dc) 2>&1 | Out-Null }
                    & powercfg.exe /setactive $c.Plan 2>&1 | Out-Null
                }
            }
            $ok1++
        }
        catch { $mal++; Write-Output "  $($E.Aviso) No se pudo restaurar $($c.Tipo) '$($c.Nombre)$($c.Guid)': $($_.Exception.Message)" }
    }
    Write-Output "$($E.OK) Restaurados $ok1 ajuste(s); $mal con incidencias."
    if ($mal -eq 0) {
        try { Rename-Item -LiteralPath $elegido -NewName ([IO.Path]::GetFileName($elegido) + '.revertido') -ErrorAction Stop; Write-Output "$($E.Info) Respaldo marcado como revertido." } catch { Write-Verbose 'no se pudo renombrar' }
    }
    Write-Output "$($E.Info) Cierra sesión o reinicia para que todos los cambios surtan efecto."
}

# =====================================================================
#  PRINCIPAL
# =====================================================================
Assert-Admin 'optimizar el equipo'
if ($SoloAnalizar) { $Modo = 'Analizar' }

if ([string]::IsNullOrWhiteSpace($Modo) -and $env:NIT_OPT_MODO -in @('PerfilAhorro', 'PerfilEquilibrado', 'PerfilJuego')) { $Modo = $env:NIT_OPT_MODO }   # la app elige el perfil sin formulario
if ([string]::IsNullOrWhiteSpace($Modo)) {
    try { $Modo = Select-ModoOptimizacion }
    catch { Exit-Kit 'Error' "No se pudo mostrar el formulario de selección: $($_.Exception.Message)" }
    if ([string]::IsNullOrWhiteSpace($Modo)) { Exit-Kit 'Cancelado' 'Operación cancelada: no se seleccionó ningún modo.' }
}

Write-Output "`n========================================================"
Write-Output "    $($E.Cohete) OPTIMIZADOR PERSONAL - MODO $($Modo.ToUpperInvariant())"
Write-Output "========================================================"
Write-Output "$($E.Info) SmartScreen y Defender no se modifican en ningún modo."

$puntoRestauracion = 'No aplica para este modo'
$errorPrincipal = $null
try {
    if ($Modo -in @('Fluidez', 'Juego', 'Normal', 'Privacidad', 'Energia', 'Red', 'PerfilJuego', 'PerfilTrabajo', 'PerfilTranquilo', 'PerfilAhorro', 'PerfilEquilibrado')) { New-PuntoRestauracion -Modo $Modo; $puntoRestauracion = $script:EstadoPunto }

    switch ($Modo) {
        'Analizar'   { Invoke-Analisis }
        'Fluidez'    { Invoke-ModoFluidez }
        'Juego'      { Invoke-LimpiezaTemporales; Invoke-ModoJuego }
        'Normal'     { Invoke-ModoNormal }
        'Privacidad' { Invoke-ModoPrivacidad }
        'Limpieza'   { Invoke-LimpiezaTemporales }
        'Arranque'   { Invoke-ModoArranque }
        'Energia'    { Invoke-ModoEnergia }
        'Red'        { Invoke-ModoRed }
        'PerfilJuego'     { Invoke-Perfil -Nombre 'Juego' }
        'PerfilTrabajo'   { Invoke-Perfil -Nombre 'Trabajo' }
        'PerfilTranquilo' { Invoke-Perfil -Nombre 'Tranquilo' }
        'PerfilAhorro'      { Invoke-Perfil -Nombre 'Ahorro' }
        'PerfilEquilibrado' { Invoke-Perfil -Nombre 'Equilibrado' }
        'Revertir'   { Invoke-Revertir }
        default      { throw "Modo no válido: $Modo" }
    }
}
catch {
    $errorPrincipal = $_.Exception.Message
    Write-Output "$($E.Error) Error durante el modo '$Modo': $errorPrincipal"
}
finally {
    $archivoRespaldo = Save-Respaldo -Modo $Modo
    Write-Output "`n========================================================"
    Write-Output "    $($E.Info) RESUMEN FINAL"
    Write-Output "========================================================"
    Write-Output " $($E.Info) Modo: $Modo"
    Write-Output " $($E.Reloj) Punto de restauración: $puntoRestauracion"
    if ($archivoRespaldo) { Write-Output " $($E.Disco) Respaldo guardado: $archivoRespaldo  (usa el modo Revertir para deshacerlo)" }
    if ($errorPrincipal) { Write-Output " $($E.Error) El proceso terminó con incidencias. Revisa los mensajes anteriores." }
    else { Write-Output " $($E.OK) Proceso finalizado. Revisa los avisos anteriores, si los hubo." }
    Write-Output "========================================================"
}
if ($errorPrincipal) { exit 1 }
