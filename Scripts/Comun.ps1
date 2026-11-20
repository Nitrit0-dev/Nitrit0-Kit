# =====================================================================
#  Comun.ps1 - Funciones compartidas del kit Nitrit0
#  - Rutas relativas (nada de letras de unidad fijas): la raíz del kit se calcula desde la ubicación del script.
#  - Detección de desconexión del pendrive y espera de reconexión (aunque cambie la letra de unidad).
#  - Reintentos, descargas reanudables, procesos con tiempo máximo y registro de todo en Datos\Logs.
# =====================================================================

if (-not $Global:E) {
    $Global:E = @{
        OK = [char]::ConvertFromUtf32(0x2705); Error = [char]::ConvertFromUtf32(0x274C); Aviso = [char]::ConvertFromUtf32(0x26A0)
        Info = [char]::ConvertFromUtf32(0x2139); Cohete = [char]::ConvertFromUtf32(0x1F680); Lupa = [char]::ConvertFromUtf32(0x1F50D)
        Disco = [char]::ConvertFromUtf32(0x1F4BE); Reloj = [char]::ConvertFromUtf32(0x23F3); Refresh = [char]::ConvertFromUtf32(0x1F504)
    }
}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13 } catch { try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { } }
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest es lentísimo con la barra de progreso de PowerShell 5.1

# ---------------------------------------------------------------------
#  Inicialización
# ---------------------------------------------------------------------
function Initialize-Kit([string]$Raiz) {
    if ([string]::IsNullOrWhiteSpace($Raiz)) { $Raiz = $env:NIT_RAIZ }
    if ([string]::IsNullOrWhiteSpace($Raiz)) { $Raiz = Split-Path -Parent $PSScriptRoot }   # Comun.ps1 está en <kit>\Scripts
    $Raiz = $Raiz.TrimEnd('\')
    $datos = Join-Path $Raiz 'Datos'
    try { New-Item -ItemType Directory -Force $datos | Out-Null } catch { }
    # Identificador del kit: permite reconocerlo si el pendrive vuelve con otra letra
    $idf = Join-Path $datos 'kit.id'; $id = $null
    try { if (Test-Path -LiteralPath $idf) { $id = (Get-Content -LiteralPath $idf -Raw).Trim() } } catch { }
    if (-not $id) { $id = [guid]::NewGuid().ToString(); try { [IO.File]::WriteAllText($idf, $id) } catch { } }
    $cache = Join-Path $env:TEMP 'Nitrit0_Cache'
    try { New-Item -ItemType Directory -Force (Join-Path $cache 'Logs') | Out-Null } catch { }
    # Los informes con claves (BitLocker, licencias) viven solo en %TEMP%: se borran al cabo de una hora
    try { Get-ChildItem -LiteralPath (Join-Path $cache 'Informes') -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddHours(-1) } | Remove-Item -Force -ErrorAction SilentlyContinue } catch { }
    # Logs temporales: los que imprimen claves (Wi-Fi, BitLocker) a la hora; el resto a los 7 días (sin rastro indefinido en el PC con el Pack Público)
    try {
        $dl = Join-Path $cache 'Logs'
        foreach ($dd in @($dl, (Join-Path $dl 'Ejecuciones'))) {
            Get-ChildItem -LiteralPath $dd -Filter '*.log' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'pendiente.log' -and $_.LastWriteTime -lt $(if ($_.Name -match 'Red_WiFi_y_Claves|BitLocker') { (Get-Date).AddHours(-1) } else { (Get-Date).AddDays(-7) }) } | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    } catch { }
    try { Get-Item -LiteralPath (Join-Path $datos 'speedtest.tmp') -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddMinutes(-10) } | Remove-Item -Force -ErrorAction SilentlyContinue } catch { }   # resto de una prueba de velocidad cancelada (la de otro proceso en curso es más reciente)
    $Global:NitKit = @{ Raiz = $Raiz; Datos = $datos; Id = $id; Cache = $cache; Pendiente = (Join-Path $cache 'Logs\pendiente.log'); Desconexiones = 0 }
    $env:NIT_RAIZ = $Raiz
    Sync-Log
}
function Get-KitRaiz { $Global:NitKit.Raiz }
function Get-KitDatos { $Global:NitKit.Datos }

# ---------------------------------------------------------------------
#  Contrato de salida de los scripts y comprobación de administrador
#  exit 0 = bien · exit 1 = error (incluida la falta de administrador) · exit 2 = cancelado por la persona (la app lo muestra en neutro)
# ---------------------------------------------------------------------
$Global:Salida = @{ Ok = 0; Error = 1; Cancelado = 2 }
function Test-EsAdmin { try { ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { $false } }
# Escribe el mensaje (si lo hay), lo anota en el registro y termina el script con el código del contrato
function Exit-Kit([ValidateSet('Ok', 'Error', 'Cancelado')][string]$Resultado = 'Ok', [string]$Mensaje = '') {
    if ($Mensaje) {
        $ic = switch ($Resultado) { 'Ok' { $Global:E.OK } 'Error' { $Global:E.Error } default { $Global:E.Info } }
        Write-Output "  $ic $Mensaje"; Write-Log "Salida $Resultado`: $Mensaje" $(if ($Resultado -eq 'Error') { 'ERROR' } else { 'INFO' })
    }
    exit $Global:Salida[$Resultado]
}
# Avance para la barra de la app: «paso Actual de Total» y un texto corto. Solo se escribe dentro de la app (NIT_APP); en consola o en el lanzador clásico no hace nada.
function Write-Progreso([int]$Actual, [int]$Total, [string]$Texto = '') {
    if ($env:NIT_APP) { Write-Host ('##PROGRESO##' + (@{ a = $Actual; t = $Total; x = $Texto } | ConvertTo-Json -Compress)) }
}
# Windows tiene cambios que solo se completan al reiniciar (servicing, actualizaciones). No cuenta PendingFileRenameOperations: lo ponen hasta instaladores corrientes
function Test-ReinicioPendiente {
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
}
function Assert-Admin([string]$Motivo = 'continuar') { if (-not (Test-EsAdmin)) { Exit-Kit 'Error' "Hace falta administrador para $Motivo. Ábrelo desde el kit." } }

# Lee un .psd1 como DATOS: solo acepta literales (texto, números, $true/$false/$null, listas y tablas). Si el archivo lleva código falla, en vez de ejecutarlo.
function Read-DatosPsd1([string]$Ruta) {
    $err = $null; $ast = [Management.Automation.Language.Parser]::ParseFile($Ruta, [ref]$null, [ref]$err)
    if ($err -and @($err).Count) { throw "Sintaxis no válida en ${Ruta}: $(@($err)[0].Message)" }
    $h = $ast.Find({ param($n) $n -is [Management.Automation.Language.HashtableAst] }, $false)
    if (-not $h) { throw "No hay una tabla de datos en $Ruta" }
    $h.SafeGetValue()
}

# Ventana con casillas para elegir qué hacer (reparaciones por separado). Cada elemento: Id, Texto, Detalle, Marcado.
# Devuelve los elegidos (puede ser un array vacío) o $null si la persona cancela.
function Show-Marcables([string]$Titulo, [string]$Subtitulo, [object[]]$Items, [string]$TextoBoton = 'Hacer lo marcado') {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $f = New-Object Windows.Forms.Form; $f.Text = $Titulo; $f.Size = New-Object Drawing.Size(940, 560); $f.StartPosition = 'CenterScreen'; $f.TopMost = $true; $f.Font = New-Object Drawing.Font('Segoe UI', 9.5)
    $t = New-Object Windows.Forms.Label; $t.Text = $Titulo; $t.Font = New-Object Drawing.Font('Segoe UI Semibold', 14); $t.AutoSize = $true; $t.Location = New-Object Drawing.Point(20, 14)
    $s = New-Object Windows.Forms.Label; $s.Text = $Subtitulo; $s.AutoSize = $false; $s.Size = New-Object Drawing.Size(880, 40); $s.Location = New-Object Drawing.Point(20, 46)
    $lv = New-Object Windows.Forms.ListView; $lv.View = 'Details'; $lv.CheckBoxes = $true; $lv.FullRowSelect = $true; $lv.Location = New-Object Drawing.Point(20, 92); $lv.Size = New-Object Drawing.Size(884, 360); $lv.Anchor = 'Top,Bottom,Left,Right'
    foreach ($c in @(@('Qué hacer', 380), @('Detalle', 480))) { [void]$lv.Columns.Add($c[0], $c[1]) }
    foreach ($x in $Items) { $i = New-Object Windows.Forms.ListViewItem([string]$x.Texto); [void]$i.SubItems.Add([string]$x.Detalle); $i.Tag = $x; $i.Checked = [bool]$x.Marcado; [void]$lv.Items.Add($i) }
    $ok = New-Object Windows.Forms.Button; $ok.Text = $TextoBoton; $ok.Size = New-Object Drawing.Size(220, 36); $ok.Location = New-Object Drawing.Point(684, 474); $ok.Anchor = 'Bottom,Right'; $ok.DialogResult = 'OK'
    $no = New-Object Windows.Forms.Button; $no.Text = 'No hacer nada'; $no.Size = New-Object Drawing.Size(140, 36); $no.Location = New-Object Drawing.Point(534, 474); $no.Anchor = 'Bottom,Right'; $no.DialogResult = 'Cancel'
    $f.Controls.AddRange(@($t, $s, $lv, $ok, $no)); $f.AcceptButton = $ok; $f.CancelButton = $no
    $ok.Enabled = ($lv.CheckedItems.Count -gt 0); $lv.Add_ItemChecked({ $ok.Enabled = ($lv.CheckedItems.Count -gt 0) }.GetNewClosure())   # sin nada marcado no hay nada que hacer
    if ($f.ShowDialog() -ne 'OK') { return $null }
    , @($lv.CheckedItems | ForEach-Object { $_.Tag })
}
# Pregunta Sí/No antes de una acción que borra o reinicia cosas. Sin ventana (revisión automática, -SinPreguntas) sigue adelante porque ya se confirmó antes.
function Confirm-Accion([string]$Texto, [string]$Titulo = 'Nitrit0 Kit', [switch]$Siempre) {
    # NIT_AUTO / NIT_SIN_PREGUNTAS solo los pone la revisión automática (la app y Ejecutor las quitan al lanzar una herramienta suelta).
    # -Siempre: para lo IRREVERSIBLE (vaciar la cuarentena, quitar Windows.old…): ningún modo automático ni de pruebas puede aceptarlo por la persona.
    if (-not $Siempre -and ($env:NIT_AUTO -or $env:NIT_SIN_PREGUNTAS)) { return $true }
    if ($Siempre -and $env:NIT_AUTO) { return $false }   # irreversible en modo automático: no se acepta ni se abre un cuadro que nadie va a ver (colgaría hasta el tiempo máximo)
    $dueno = $null
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dueno = New-Object Windows.Forms.Form; $dueno.TopMost = $true   # dueño invisible y siempre delante: el diálogo no se queda tras la ventana de la app
        return ([Windows.Forms.MessageBox]::Show($dueno, $Texto, $Titulo, 'YesNo', 'Warning', 'Button2') -eq 'Yes')
    } catch { return $false } finally { if ($dueno) { $dueno.Dispose() } }
}

# Comprueba que un script del kit figura en Datos\Integridad.json con huella SHA-256 y que su contenido no ha cambiado.
# Devuelve $null si es correcto, o el motivo por el que no debe ejecutarse (lista blanca: lo que no está en el manifiesto no corre).
function Test-ScriptAutorizado([string]$Ruta) {
    try {
        $raiz = $Global:NitKit.Raiz.TrimEnd('\'); $full = [IO.Path]::GetFullPath($Ruta)
        if (-not $full.StartsWith($raiz + '\', [StringComparison]::OrdinalIgnoreCase)) { return 'está fuera del kit' }
        $rel = $full.Substring($raiz.Length + 1)
        $jf = Join-Path $Global:NitKit.Datos 'Integridad.json'
        if (-not (Test-Path -LiteralPath $jf)) { return 'falta Datos\Integridad.json (ejecuta Regenerar_Integridad.ps1)' }
        $lista = Get-Content -LiteralPath $jf -Raw -Encoding UTF8 | ConvertFrom-Json   # en variable: PowerShell 5.1 entrega el array de golpe y @() lo envolvería
        $e = $lista | Where-Object { $_.R -ieq $rel } | Select-Object -First 1
        if (-not $e -or -not $e.H) { return 'no figura en Datos\Integridad.json' }
        if ((Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash -ne $e.H) { return 'su contenido ha cambiado desde que se generó la integridad' }
        $null
    } catch { "no se pudo comprobar su integridad ($($_.Exception.Message))" }
}
# Extensiones de Apps\ que llevan huella SHA-256 (el resto de recursos pesados solo se comprueba por tamaño).
function Test-HuellaRequerida([string]$Rel) {
    ($Rel -like 'Scripts\*') -or ($Rel -like 'App\datos\*') -or ($Rel -eq 'Nitrit0.exe') -or ($Rel -eq 'Nitrit0_Limpieza.exe') -or (($Rel -like 'Apps\*') -and ([IO.Path]::GetExtension($Rel) -in '.exe', '.dll', '.sys', '.msi', '.ps1', '.bat', '.cmd', '.vbs', '.js'))
}

# ---------------------------------------------------------------------
#  Registro (siempre se escribe; si el pendrive no está, se guarda en local y se vuelca al volver)
# ---------------------------------------------------------------------
# Dónde guardan sus datos de trabajo (registros, historial, respaldos): en el pack personal, Datos del pendrive; en el público (OcultarPeligro), %TEMP%\Nitrit0_Cache,
# para que un pendrive prestado no acumule nombres de equipos ni salidas de los PC por los que pasa.
function Get-BaseTrabajo { if (Test-ModoPublico) { $Global:NitKit.Cache } else { $Global:NitKit.Datos } }
function Get-RutaLog { Join-Path (Join-Path (Get-BaseTrabajo) 'Logs') ("Kit_{0}_{1}.log" -f (Get-Date -Format 'yyyyMMdd'), ($env:COMPUTERNAME -replace '[^\w\-]', '_')) }
function Write-Log([string]$Mensaje, [string]$Nivel = 'INFO') {
    $l = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Nivel, $Mensaje
    if (-not $Global:NitKit) { return }
    # En el pack personal solo se escribe en el kit si se reconoce (kit.id presente): nunca se crean carpetas en una unidad ausente u otra unidad con la misma letra
    try {
        if (-not ((Test-ModoPublico) -or (Test-KitDisponible))) { throw 'kit no disponible' }
        New-Item -ItemType Directory -Force (Split-Path (Get-RutaLog)) -ErrorAction Stop | Out-Null; [IO.File]::AppendAllText((Get-RutaLog), $l + "`r`n", [Text.Encoding]::UTF8)
    }
    catch { try { [IO.File]::AppendAllText($Global:NitKit.Pendiente, $l + "`r`n", [Text.Encoding]::UTF8) } catch { } }
}
function Sync-Log {
    try {
        $p = $Global:NitKit.Pendiente
        if ((Test-Path -LiteralPath $p) -and ((Test-ModoPublico) -or (Test-KitDisponible))) {
            New-Item -ItemType Directory -Force (Split-Path (Get-RutaLog)) | Out-Null
            [IO.File]::AppendAllText((Get-RutaLog), (Get-Content -LiteralPath $p -Raw), [Text.Encoding]::UTF8)
            Remove-Item -LiteralPath $p -Force
        }
    } catch { }
}

# ---------------------------------------------------------------------
#  Unidad del kit: detección y espera de reconexión
# ---------------------------------------------------------------------
function Test-KitDisponible { try { [IO.File]::Exists((Join-Path $Global:NitKit.Datos 'kit.id')) } catch { $false } }

# Si el pendrive vuelve con otra letra, lo localiza por el identificador guardado en Datos\kit.id
function Find-KitReconectado {
    $raiz = $Global:NitKit.Raiz
    $rel = if ($raiz.Length -gt 3 -and $raiz[1] -eq ':') { $raiz.Substring(3) } else { $null }
    if (-not $rel) { return $null }
    # Extraíbles primero: si el kit también está copiado en el disco duro con el mismo kit.id, manda el pendrive
    foreach ($d in ([IO.DriveInfo]::GetDrives() | Sort-Object { if ($_.DriveType -eq 'Removable') { 0 } else { 1 } })) {
        try {
            if (-not $d.IsReady) { continue }
            $c = Join-Path $d.RootDirectory.FullName $rel; $f = Join-Path $c 'Datos\kit.id'
            if ([IO.File]::Exists($f) -and ([IO.File]::ReadAllText($f).Trim() -eq $Global:NitKit.Id)) { return $c }
        } catch { }
    }
    $null
}

# Espera a que el kit vuelva a estar accesible. Devuelve $true si está disponible, $false si se agotó el tiempo.
function Wait-Kit([int]$TimeoutSeg = 180, [scriptblock]$Progreso) {
    if (Test-KitDisponible) { return $true }
    $t0 = Get-Date; $Global:NitKit.Desconexiones++
    Write-Log "Unidad del kit NO accesible ($($Global:NitKit.Raiz)). Esperando reconexión hasta $TimeoutSeg s." 'AVISO'
    $ult = -1
    while (((Get-Date) - $t0).TotalSeconds -lt $TimeoutSeg) {
        $seg = [int]((Get-Date) - $t0).TotalSeconds
        if (Test-KitDisponible) { break }
        $nueva = Find-KitReconectado
        if ($nueva) {
            Write-Log "Unidad reconectada con otra ruta: $nueva (antes $($Global:NitKit.Raiz))" 'AVISO'
            $Global:NitKit.Raiz = $nueva; $Global:NitKit.Datos = Join-Path $nueva 'Datos'; $env:NIT_RAIZ = $nueva
            break
        }
        if ($seg -ne $ult -and $seg % 5 -eq 0) {
            $m = "$($Global:E.Reloj) Unidad del kit desconectada. Esperando reconexión… ($seg s de $TimeoutSeg s)"
            if ($Progreso) { & $Progreso $m } else { Write-Host $m }
            $ult = $seg
        }
        Start-Sleep -Milliseconds 700
    }
    $ok = Test-KitDisponible
    $dur = [int]((Get-Date) - $t0).TotalSeconds
    if ($ok) { Write-Log "Unidad del kit recuperada tras $dur s." 'INFO'; Sync-Log; $m2 = "$($Global:E.OK) Unidad del kit reconectada tras $dur s."; if ($Progreso) { & $Progreso $m2 } else { Write-Host $m2 } }
    else { Write-Log "La unidad del kit no volvió en $dur s." 'ERROR' }
    $ok
}

# ---------------------------------------------------------------------
#  Reintentos
# ---------------------------------------------------------------------
function Invoke-Reintento([scriptblock]$Accion, [int]$Intentos = 3, [int]$EsperaSeg = 3, [string]$Nombre = 'operación', [switch]$EsperarKit) {
    for ($i = 1; $i -le $Intentos; $i++) {
        try { return (& $Accion) }
        catch {
            Write-Log "$Nombre falló (intento $i/$Intentos): $($_.Exception.Message)" 'AVISO'
            if ($i -ge $Intentos) { throw }
            Write-Host "  $($Global:E.Aviso) $Nombre falló (intento $i/$Intentos). Reintentando en $($EsperaSeg * $i) s…"
            if ($EsperarKit) { [void](Wait-Kit 120) }
            Start-Sleep -Seconds ($EsperaSeg * $i)
        }
    }
}

# ---------------------------------------------------------------------
#  Copias robustas (reanudan si el origen desaparece y vuelve)
# ---------------------------------------------------------------------
function Copy-ConReintento([string]$Origen, [string]$Destino, [int]$Intentos = 4) {
    New-Item -ItemType Directory -Force (Split-Path $Destino) | Out-Null
    $ultimaEx = $null
    for ($i = 1; $i -le $Intentos; $i++) {
        $fi = $null; $fo = $null
        try {
            if (-not (Test-Path -LiteralPath $Origen)) { [void](Wait-Kit 120); if (-not (Test-Path -LiteralPath $Origen)) { throw "No existe $Origen" } }
            $tam = (Get-Item -LiteralPath $Origen).Length
            if ((Test-Path -LiteralPath $Destino) -and (Get-Item -LiteralPath $Destino).Length -eq $tam) { return $Destino }
            $ini = 0L
            if ((Test-Path -LiteralPath $Destino) -and $i -gt 1) { $ini = [Math]::Max(0L, (Get-Item -LiteralPath $Destino).Length - 4MB) }   # reanudar con margen de seguridad
            $fi = [IO.File]::Open($Origen, 'Open', 'Read', 'ReadWrite')
            $fo = [IO.File]::Open($Destino, 'OpenOrCreate', 'Write', 'None'); $fo.SetLength($ini); [void]$fo.Seek($ini, 'Begin'); [void]$fi.Seek($ini, 'Begin')
            $buf = New-Object byte[] (1MB); $ult = Get-Date
            while (($n = $fi.Read($buf, 0, $buf.Length)) -gt 0) {
                $fo.Write($buf, 0, $n)
                if (((Get-Date) - $ult).TotalSeconds -ge 5) { $ult = Get-Date; Write-Host ("      {0} Copiando {1}: {2:N0} de {3:N0} MB" -f $Global:E.Reloj, (Split-Path $Origen -Leaf), ($fo.Position / 1MB), ($tam / 1MB)) }
            }
            $fo.Flush(); $fo.Dispose(); $fi.Dispose(); $fo = $null; $fi = $null
            if ((Get-Item -LiteralPath $Destino).Length -ne $tam) { throw 'El tamaño copiado no coincide.' }
            return $Destino
        } catch {
            $ultimaEx = $_
            Write-Log "Copia de $Origen falló (intento $i/$Intentos): $($_.Exception.Message)" 'AVISO'
        } finally { if ($fo) { $fo.Dispose() }; if ($fi) { $fi.Dispose() } }
        Write-Host "  $($Global:E.Aviso) La copia se interrumpió (intento $i/$Intentos). Comprobando la unidad…"
        [void](Wait-Kit 120); Start-Sleep -Seconds 2
    }
    throw $ultimaEx
}

# Copia un archivo del kit a la caché local (%TEMP%) y devuelve la ruta local. Así el instalador no depende del pendrive.
function Copy-AlCache([string]$Ruta) {
    $rel = $Ruta; $r = $Global:NitKit.Raiz
    if ($Ruta.StartsWith($r, [StringComparison]::OrdinalIgnoreCase)) { $rel = $Ruta.Substring($r.Length).TrimStart('\') }
    $dest = Join-Path (Join-Path $Global:NitKit.Cache 'Apps') $rel
    Copy-ConReintento $Ruta $dest
}

# ---------------------------------------------------------------------
#  Procesos con tiempo máximo (matan el árbol de procesos si se cuelgan)
# ---------------------------------------------------------------------
function Stop-Arbol([int]$ProcId) { try { & (Join-Path $env:SystemRoot 'System32\taskkill.exe') /PID $ProcId /T /F 2>&1 | Out-Null } catch { } }

# Devuelve @{ Codigo; TiempoAgotado; Salida }. Muestra un latido cada $LatidoSeg s con la última línea útil de la salida.
function Invoke-Proceso([string]$Ruta, [string]$Argumentos = '', [int]$TimeoutSeg = 600, [string]$Etiqueta = 'Proceso', [int]$LatidoSeg = 20, [switch]$MostrarSalida) {
    $so = Join-Path $env:TEMP ("nit_so_{0}.txt" -f [guid]::NewGuid().ToString('N')); $se = $so + '.err'
    $res = [pscustomobject]@{ Codigo = -9998; TiempoAgotado = $false; Salida = '' }
    try {
        $sp = @{ FilePath = $Ruta; PassThru = $true; WindowStyle = 'Hidden'; RedirectStandardOutput = $so; RedirectStandardError = $se }
        if ($Argumentos) { $sp.ArgumentList = $Argumentos }
        $p = Start-Process @sp
        $t0 = Get-Date; $ult = 0
        Write-Log "$Etiqueta iniciado (PID $($p.Id), máx. $TimeoutSeg s): $Ruta $Argumentos"
        while (-not $p.HasExited) {
            $seg = [int]((Get-Date) - $t0).TotalSeconds
            if ($seg -ge $TimeoutSeg) { Stop-Arbol $p.Id; $res.TiempoAgotado = $true; $res.Codigo = -9999; Write-Host "  $($Global:E.Aviso) $Etiqueta superó el tiempo máximo ($TimeoutSeg s) y se canceló."; Write-Log "$Etiqueta cancelado por tiempo máximo ($TimeoutSeg s)" 'ERROR'; break }
            if ($seg - $ult -ge $LatidoSeg) {
                $ult = $seg; $lin = ''
                try {
                    # sfc escribe en UTF-16 (deja caracteres nulos entre letras) y DISM solo pinta una barra «[====  42.0%  ====]»:
                    # se quitan los nulos y, si no hay ninguna línea de texto útil, se muestra al menos el porcentaje.
                    $cola = @(Get-Content -LiteralPath $so -Tail 6 -ErrorAction SilentlyContinue | ForEach-Object { $_ -replace "`0", '' })
                    $lin = ($cola | Where-Object { $_ -match '[\p{L}\p{N}]{3}' -and $_ -notmatch '^\s*[\-\\|/█▒░ ]+\s*$' -and $_ -notmatch '^\s*\[[=\s\d\.,%]+\]\s*$' } | Select-Object -Last 1)
                    if (-not $lin) { $pct = [regex]::Matches(($cola -join ' '), '(\d{1,3}(?:[\.,]\d)?)\s*%'); if ($pct.Count) { $lin = $pct[$pct.Count - 1].Groups[1].Value + ' %' } }
                } catch { }
                Write-Host ("      {0} {1} en curso… {2} s{3}" -f $Global:E.Reloj, $Etiqueta, $seg, $(if ($lin) { " | " + $lin.Trim() } else { '' }))
            }
            Start-Sleep -Milliseconds 500
        }
        if (-not $res.TiempoAgotado) { $p.WaitForExit(); $res.Codigo = [int]$p.ExitCode }
        try { $res.Salida = (((Get-Content -LiteralPath $so -ErrorAction SilentlyContinue) -join "`n") -replace "`0", '') } catch { }
        if ($MostrarSalida -and $res.Salida) { ($res.Salida -split "`n" | Where-Object { $_ -match '[\p{L}\p{N}]{3}' -and $_ -notmatch '^\s*[\-\\|/█▒░ ]+\s*$' } | Select-Object -Last 8) | ForEach-Object { Write-Host "        $_" } }
        Write-Log "$Etiqueta terminó con código $($res.Codigo)"
    } catch { Write-Log "$Etiqueta no pudo ejecutarse: $($_.Exception.Message)" 'ERROR'; Write-Host "  $($Global:E.Error) No se pudo ejecutar ${Etiqueta}: $($_.Exception.Message)" }
    finally { Remove-Item -LiteralPath $so, $se -Force -ErrorAction SilentlyContinue }
    $res
}

# ---------------------------------------------------------------------
#  Red y descargas
# ---------------------------------------------------------------------
function Test-Internet {
    try { $c = New-Object Net.Sockets.TcpClient; $r = $c.BeginConnect('1.1.1.1', 443, $null, $null); $ok = $r.AsyncWaitHandle.WaitOne(3000) -and $c.Connected; $c.Close(); $ok } catch { $false }
}

# Descarga con reintentos y reanudación (curl.exe si existe; si no, Invoke-WebRequest). Devuelve $true/$false.
function Get-Descarga([string]$Url, [string]$Destino, [int]$TimeoutSeg = 300, [int]$Intentos = 3, [string]$Etiqueta = 'Descarga') {
    # Las comillas van a mano en la línea de curl: una URL o ruta con « " » inyectaría opciones (p. ej. otro -o que pise un archivo)
    if ($Url -notmatch '^https?://[^\s"]+$' -or $Destino -match '["<>|]') { Write-Log "$Etiqueta rechazada: URL o destino no válidos" 'ERROR'; Write-Host "    $($Global:E.Error) $Etiqueta rechazada: URL o destino no válidos."; return $false }
    New-Item -ItemType Directory -Force (Split-Path $Destino) | Out-Null
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    for ($i = 1; $i -le $Intentos; $i++) {
        try {
            if (Test-Path -LiteralPath $curl) {
                $r = Invoke-Proceso $curl "-L -s -S --fail --connect-timeout 15 --max-time $TimeoutSeg -C - -o `"$Destino`" `"$Url`"" ($TimeoutSeg + 20) "$Etiqueta" 10
                if ($r.Codigo -ne 0) { throw "curl terminó con código $($r.Codigo)" }
            } else { Invoke-WebRequest -Uri $Url -OutFile $Destino -UseBasicParsing -TimeoutSec $TimeoutSeg -Headers @{ 'User-Agent' = 'Mozilla/5.0 Nitrit0' } -ErrorAction Stop }
            if ((Test-Path -LiteralPath $Destino) -and (Get-Item -LiteralPath $Destino).Length -gt 10KB) { return $true }
            throw 'Archivo descargado vacío o demasiado pequeño.'
        } catch {
            Write-Log "$Etiqueta falló (intento $i/$Intentos): $($_.Exception.Message)" 'AVISO'
            Write-Host "    $($Global:E.Aviso) $Etiqueta falló (intento $i/$Intentos): $($_.Exception.Message)"
            if ($i -lt $Intentos) { Start-Sleep -Seconds (3 * $i) }
        }
    }
    $false
}

# Carpeta de salida de informes/registros de los scripts (dentro de Datos, nunca junto al script)
# Abre un informe HTML recién creado. En la app (NIT_APP) no abre el navegador: avisa con una línea marcada y la app lo muestra en su propia ventana.
function Open-Informe([string]$Ruta) {
    if ($env:NIT_APP) { Write-Output "##INFORME##$Ruta"; return }
    try { Start-Process $Ruta } catch { }
}
# Pack público = Ajustes.json con OcultarPeligro true. No se mira «Modo» (sencillo/técnico): lo cambia la persona desde la app y no debe mover dónde se guardan los datos.
function Test-ModoPublico {
    # Se lee una vez por sesión (Write-Log se llama muchas veces) y solo se recuerda si la lectura fue buena.
    # Si Ajustes.json falta o no se puede leer, se asume pack público: ante la duda, nada se guarda en el pendrive.
    if ($Global:NitKit.ContainsKey('Publico')) { return $Global:NitKit.Publico }
    try { $aj = Join-Path $Global:NitKit.Datos 'Ajustes.json'; if (Test-Path -LiteralPath $aj) { $Global:NitKit.Publico = [bool]((Get-Content -LiteralPath $aj -Raw -Encoding UTF8 | ConvertFrom-Json).OcultarPeligro -eq $true); return $Global:NitKit.Publico } } catch { }
    $true
}
# Carpeta de salida dentro de Datos; los informes ('Informes' y sus subcarpetas) van a %TEMP%\Nitrit0_Cache\Informes en el pack público,
# para que un pendrive que pasa por varios equipos no acumule datos de todos (en el pack personal, el técnico los conserva en Datos\Informes).
function Get-CarpetaSalida([string]$Sub = 'Salidas') {
    $base = if ($Sub -match '^Informes(\\|$)' -and (Test-ModoPublico)) { $Global:NitKit.Cache } else { $Global:NitKit.Datos }
    $d = Join-Path $base $Sub; try { New-Item -ItemType Directory -Force $d | Out-Null } catch { }; $d
}

# ---------------------------------------------------------------------
#  Red de seguridad para los scripts que CAMBIAN el sistema
#  Start-OperacionSegura: punto de restauración + carpeta de respaldo (Datos\Respaldo\Cambios\<fecha>_<nombre>).
#  Set-ValorSeguro / Set-ServicioSeguro / Set-DnsSeguro / Save-Bcd / Save-PageFile: guardan el estado anterior ANTES de cambiar.
#  Mantenimiento > «Deshacer cambios» devuelve todo a como estaba.
# ---------------------------------------------------------------------
function New-PuntoRestauracionSeguro([string]$Descripcion) {
    try {
        $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        $ant = (Get-ItemProperty $k -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
        Set-ItemProperty -Path $k -Name SystemRestorePointCreationFrequency -Value 0 -Type DWord -Force
        Write-Host "  $($Global:E.Reloj) Creando el punto de restauración (puede tardar unos minutos; si Windows no responde en 3 min se continúa sin él)..."
        # Checkpoint-Computer no tiene tiempo máximo y se cuelga si el servicio de instantáneas (VSS) está atascado: va en un proceso aparte que se corta a los 180 s
        $orden = "try { Enable-ComputerRestore -Drive '$($env:SystemDrive)\' -ErrorAction Stop; Checkpoint-Computer -Description '$($Descripcion -replace "'", "''")' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop; Write-Output 'PUNTO_OK' } catch { Write-Output `$_.Exception.Message }"
        $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($orden))
        try { $r = Invoke-Proceso (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $enc" 180 'Punto de restauración' 30 } finally {
            if ($null -ne $ant) { Set-ItemProperty -Path $k -Name SystemRestorePointCreationFrequency -Value $ant -Type DWord -Force } else { Remove-ItemProperty -Path $k -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue }
        }
        if ($r.TiempoAgotado) { throw 'Windows tardó más de 3 minutos (el servicio de instantáneas VSS está ocupado o atascado; reinicia el equipo si se repite)' }
        # El código de salida del hijo no es fiable: el éxito se reconoce por la marca que imprime al final
        if ([string]$r.Salida -notmatch 'PUNTO_OK') { throw $(if ($r.Salida) { ([string]$r.Salida).Trim() } else { 'sin respuesta de Windows' }) }
        Write-Host "  $($Global:E.OK) Punto de restauración creado: $Descripcion"; Write-Log "Punto de restauración: $Descripcion"; return $true
    } catch { Write-Host "  $($Global:E.Aviso) No se pudo crear el punto de restauración ($($_.Exception.Message -replace '\r?\n', ' ')). Los cambios se registran igualmente."; Write-Log "Punto de restauración falló: $($_.Exception.Message)" 'AVISO'; return $false }
}
function Start-OperacionSegura([string]$Nombre, [switch]$SinPuntoRestauracion) {
    $id = "{0}_{1}" -f (Get-Date -Format 'yyyyMMdd_HHmmss'), (($Nombre -replace '[^\w\-]', '_') -replace '_+', '_')
    $dir = Join-Path (Join-Path $Global:NitKit.Datos 'Respaldo') "Cambios\$id"
    # Pack público o kit ausente: el registro de cambios (nombre del equipo, valores previos del registro) se queda en el PC, no en el pendrive («Deshacer cambios» lo busca ahí también)
    if ((Test-ModoPublico) -or -not (Test-KitDisponible)) { $dir = Join-Path $Global:NitKit.Cache "Cambios\$id" }
    try { New-Item -ItemType Directory -Force $dir | Out-Null } catch { }
    $Global:NitOp = @{ Id = $id; Nombre = $Nombre; Dir = $dir; Equipo = $env:COMPUTERNAME; Fecha = (Get-Date).ToString('s'); Cambios = (New-Object Collections.Generic.List[object]) }
    Write-Log "Operación iniciada: $Nombre (registro de cambios en $dir)"
    if (-not $SinPuntoRestauracion) {
        # Varias herramientas seguidas (asistente, revisión automática) no crean un punto cada una: vale el de Nitrit0 de los últimos 30 minutos
        $reciente = $null
        try { $reciente = Get-ComputerRestorePoint -ErrorAction Stop | Where-Object { $_.Description -like 'Nitrit0 - antes de*' } | Where-Object { [Management.ManagementDateTimeConverter]::ToDateTime($_.CreationTime) -gt (Get-Date).AddMinutes(-30) } | Select-Object -First 1 } catch { }
        if ($reciente) { Write-Host "  $($Global:E.Info) Ya hay un punto de restauración de Nitrit0 de hace menos de 30 minutos: «$($reciente.Description)»." }
        else { [void](New-PuntoRestauracionSeguro "Nitrit0 - antes de $Nombre") }
    }
    Write-Host "  $($Global:E.Info) Cada cambio queda registrado y se puede deshacer (Mantenimiento > Deshacer cambios)."
    $dir
}
# Escribe un JSON sin dejarlo a medias: primero a un .tmp y luego se sustituye el definitivo (un corte o un pendrive desconectado no estropea la copia anterior).
function Write-JsonAtomico([string]$Ruta, $Objeto, [int]$Profundidad = 6) {
    $tmp = "$Ruta.tmp"
    ($Objeto | ConvertTo-Json -Depth $Profundidad) | Set-Content -LiteralPath $tmp -Encoding UTF8
    if (Test-Path -LiteralPath $Ruta) {
        try { [IO.File]::Replace($tmp, $Ruta, $null) }
        catch { Move-Item -LiteralPath $tmp -Destination $Ruta -Force }   # exFAT/FAT32 (pendrives) no admiten Replace
    } else { Move-Item -LiteralPath $tmp -Destination $Ruta -Force }
}
function Save-Cambio([hashtable]$c) {
    if (-not $Global:NitOp) { return }
    $Global:NitOp.Cambios.Add([pscustomobject]$c)
    try { Write-JsonAtomico (Join-Path $Global:NitOp.Dir 'cambios.json') ([pscustomobject]@{ Esquema = 1; Id = $Global:NitOp.Id; Nombre = $Global:NitOp.Nombre; Equipo = $Global:NitOp.Equipo; Fecha = $Global:NitOp.Fecha; Cambios = $Global:NitOp.Cambios.ToArray() }) }
    catch {
        # Sin este registro no se podría deshacer: se avisa (una sola vez por operación) en vez de seguir en silencio
        Write-Log "No se pudo guardar el registro de cambios: $($_.Exception.Message)"
        if (-not $Global:NitOp.AvisoRegistro) { $Global:NitOp.AvisoRegistro = $true; Write-Host "  $($Global:E.Aviso) No se pudo guardar el registro de cambios (¿pendrive lleno o desconectado?): lo que se cambie ahora puede no poder deshacerse desde «Deshacer cambios»." }
    }
    Write-Log "Cambio registrado: $($c.Tipo) $($c.Ruta)$($c.Nombre)$($c.Servicio)$($c.Interfaz)"
}
function Set-ValorSeguro([string]$Ruta, [string]$Nombre, $Valor, [string]$Tipo = 'DWord') {
    $claveExistia = Test-Path -LiteralPath $Ruta; $existia = $false; $prev = $null; $tipoPrev = $null
    $nombreReal = if ($Nombre -eq '(default)') { '' } else { $Nombre }
    if ($claveExistia) { try { $it = Get-Item -LiteralPath $Ruta; if ($it.GetValueNames() -contains $nombreReal) { $existia = $true; $prev = $it.GetValue($nombreReal, $null, 'DoNotExpandEnvironmentNames'); $tipoPrev = $it.GetValueKind($nombreReal).ToString() } } catch { } }
    $padreExistia = $true; try { $padreExistia = Test-Path -LiteralPath (Split-Path $Ruta -Parent) } catch { }
    Save-Cambio @{ Tipo = 'Registro'; Ruta = $Ruta; Nombre = $Nombre; ClaveExistia = $claveExistia; PadreExistia = $padreExistia; ValorExistia = $existia; Previo = $prev; TipoPrevio = $tipoPrev }
    if (-not $claveExistia) { New-Item -Path $Ruta -Force | Out-Null }
    Set-ItemProperty -LiteralPath $Ruta -Name $Nombre -Value $Valor -Type $Tipo -Force
    # Se relee: si otro programa o una directiva lo ha vuelto a cambiar, se anota en el registro en vez de dar el cambio por hecho
    if ($Valor -isnot [array] -and $Tipo -in 'DWord', 'QWord', 'String', 'ExpandString') {
        try { $ahora = (Get-ItemProperty -LiteralPath $Ruta -Name $Nombre -ErrorAction Stop).$Nombre; if ("$ahora" -ne "$Valor") { Write-Log "Verificación: $Ruta\$Nombre vale '$ahora' y se esperaba '$Valor'"; Write-Host "  $($Global:E.Aviso) $Nombre no ha quedado en '$Valor' (vale '$ahora'): puede haberlo cambiado de nuevo una directiva o un programa." } } catch { }
    }
}
function Set-ServicioSeguro([string]$Nombre, [string]$Inicio = 'Disabled', [switch]$Detener) {
    $s = Get-CimInstance Win32_Service -Filter "Name='$Nombre'" -ErrorAction SilentlyContinue
    if (-not $s) { return $false }
    Save-Cambio @{ Tipo = 'Servicio'; Servicio = $Nombre; InicioPrevio = $s.StartMode; EstadoPrevio = $s.State }
    if ($Detener -and $s.State -eq 'Running') { Stop-Service -Name $Nombre -Force -ErrorAction SilentlyContinue }
    Set-Service -Name $Nombre -StartupType $Inicio -ErrorAction SilentlyContinue
    $true
}
function Set-DnsSeguro([int]$Interfaz, [string[]]$Servidores, [switch]$Automatico) {
    $prev = @(); $auto = $true
    try { $prev = @((Get-DnsClientServerAddress -InterfaceIndex $Interfaz -AddressFamily IPv4 -ErrorAction Stop).ServerAddresses) } catch { }
    try { $g = (Get-NetAdapter -InterfaceIndex $Interfaz -ErrorAction Stop).InterfaceGuid; $auto = [string]::IsNullOrWhiteSpace((Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$g" -ErrorAction Stop).NameServer) } catch { }
    Save-Cambio @{ Tipo = 'Dns'; Interfaz = $Interfaz; Previo = $prev; Automatico = $auto }
    if ($Automatico) { Set-DnsClientServerAddress -InterfaceIndex $Interfaz -ResetServerAddresses -ErrorAction Stop } else { Set-DnsClientServerAddress -InterfaceIndex $Interfaz -ServerAddresses $Servidores -ErrorAction Stop }
}
function Save-Bcd {
    $f = Join-Path $Global:NitOp.Dir 'bcd.bak'
    & (Join-Path $env:SystemRoot 'System32\bcdedit.exe') /export $f 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $f)) { Save-Cambio @{ Tipo = 'Bcd'; Archivo = $f }; Write-Host "  $($Global:E.OK) Copia de seguridad de la configuración de arranque guardada."; $true }
    else { Write-Host "  $($Global:E.Aviso) No se pudo copiar la configuración de arranque (BCD): no se modificará."; $false }
}
function Save-PageFile {
    try {
        $cs = Get-CimInstance Win32_ComputerSystem
        $cfg = @(Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue | ForEach-Object { @{ Nombre = $_.Name; Inicial = [int]$_.InitialSize; Maximo = [int]$_.MaximumSize } })
        Save-Cambio @{ Tipo = 'PageFile'; Automatico = [bool]$cs.AutomaticManagedPagefile; Configuracion = $cfg }
        $true
    } catch { Write-Host "  $($Global:E.Aviso) No se pudo guardar la configuración actual de paginación: no se modificará."; $false }
}
function Save-Informativo([string]$Texto, [string]$Detalle = '') { Save-Cambio @{ Tipo = 'Info'; Ruta = $Texto; Nombre = $Detalle } }

# Resuelve la ruta de un programa del kit. Admite comodines en la carpeta (p. ej. 'CPU\cpu-z_*\cpuz_x64.exe'):
# si hay varias versiones, elige la más nueva (por versión del archivo; si empatan, por fecha). Así, al copiar una versión nueva no hay que tocar nada.
function Resolve-ExeKit([string]$Rel) {
    $ruta = Join-Path (Join-Path $Global:NitKit.Raiz 'Apps') $Rel
    if ($Rel -notmatch '[\*\?]') { return $ruta }
    $c = @(Get-ChildItem -Path $ruta -File -ErrorAction SilentlyContinue)
    if (-not $c.Count) { return $ruta }
    $ver = { param($x) try { $v = (([string]$x.VersionInfo.FileVersion) -replace ',\s*', '.') -replace '[^\d\.].*$', ''; if ($v -match '^\d+(\.\d+){0,3}$') { if ($v -notmatch '\.') { $v += '.0' }; [version]$v } else { [version]'0.0' } } catch { [version]'0.0' } }
    ($c | Sort-Object @{ Expression = { & $ver $_ }; Descending = $true }, @{ Expression = { $_.LastWriteTime }; Descending = $true } | Select-Object -First 1).FullName
}
