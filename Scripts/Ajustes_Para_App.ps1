# =====================================================================
#  Ajustes_Para_App.ps1 - Lee y cambia ajustes sencillos de Windows para la pantalla «Ajustes de Windows» de la app.
#  Lista blanca: solo se puede tocar lo que está en $Ajustes (clave, valor y opciones permitidas); la app solo manda un id y una opción.
#  Todo es del usuario actual (HKCU), nada pide administrador, y cada cambio guarda el valor anterior para «Deshacer cambios».
#  Uso (lo lanza la app):  -Accion Leer   |   -Accion Aplicar -Id <id> -Opcion <clave de la opción>
#  Salida: una línea  ##AJ##<json>  con el resultado.
# =====================================================================
param([Parameter(Mandatory)][ValidateSet('Leer', 'Aplicar')][string]$Accion, [string]$Id, [string]$Opcion)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) } catch { }
function Salir([object]$o) { Write-Output ('##AJ##' + ($o | ConvertTo-Json -Depth 6 -Compress)) }
try {
    . (Join-Path $PSScriptRoot 'Comun.ps1'); Initialize-Kit $env:NIT_RAIZ
    # Se lanza directamente (sin pasar por Ejecutar_Para_App): se comprueba aquí la huella de este mismo script
    $motivo = Test-ScriptAutorizado $PSCommandPath
    if ($motivo) { Salir @{ ok = $false; mensaje = "Este script $motivo." }; exit 1 }
} catch { Salir @{ ok = $false; mensaje = "No se pudo preparar el kit: $($_.Exception.Message)" }; exit 1 }

# Si la app está elevada con OTRA cuenta de administrador (el usuario estándar al que un familiar le escribe la contraseña en el aviso de permisos), HKCU es el de esa
# cuenta y no el de la persona que tiene el escritorio: se avisa y no se cambia nada. En una sesión de escritorio remoto no se comprueba (el usuario de la consola puede ser otro).
function Get-OtraCuenta {
    try {
        if ($env:SESSIONNAME -like 'RDP*') { return @{ otra = $false } }
        $sesion = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName   # quien tiene la sesión interactiva (DOMINIO\usuario); vacío si nadie
        $yo = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        if ($sesion -and ($sesion -ine $yo)) { return @{ otra = $true; proceso = $yo; sesion = $sesion } }
    } catch { }
    @{ otra = $false }
}
# Una sola sesión de «Deshacer cambios» por tanda de ajustes: se sigue la de los últimos 30 minutos en vez de crear una carpeta por cada interruptor
function Start-SesionAjustes {
    $base = if ((Test-ModoPublico) -or -not (Test-KitDisponible)) { Join-Path $Global:NitKit.Cache 'Cambios' } else { Join-Path (Join-Path $Global:NitKit.Datos 'Respaldo') 'Cambios' }
    $previa = Get-ChildItem -LiteralPath $base -Directory -Filter '*_Ajustes_de_Windows' -ErrorAction SilentlyContinue |
        Where-Object { (Test-Path -LiteralPath (Join-Path $_.FullName 'cambios.json')) -and (Get-Item -LiteralPath (Join-Path $_.FullName 'cambios.json')).LastWriteTime -gt (Get-Date).AddMinutes(-30) } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($previa) {
        try {
            $j = Get-Content -LiteralPath (Join-Path $previa.FullName 'cambios.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([string]$j.Equipo -ne $env:COMPUTERNAME) { throw 'sesión de otro equipo' }
            $cam = New-Object Collections.Generic.List[object]; foreach ($c in @($j.Cambios)) { $cam.Add($c) }
            $Global:NitOp = @{ Id = $j.Id; Nombre = $j.Nombre; Dir = $previa.FullName; Equipo = $j.Equipo; Fecha = $j.Fecha; Cambios = $cam }
            return
        } catch { }
    }
    [void](Start-OperacionSegura 'Ajustes de Windows' -SinPuntoRestauracion)   # solo anota el valor anterior para «Deshacer cambios»
}
$otraCuenta = Get-OtraCuenta
$Adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
# Def = lo que trae Windows (y lo que vale si el valor no existe). Rec = lo que recomendamos; $null = es cuestión de gusto, sin recomendación.
$Ajustes = @(
    @{ Id = 'vista_tareas'; Grupo = 'Barra de tareas'; Titulo = 'Botón de Vista de tareas'; Descripcion = 'El botón de la barra para ver todas las ventanas abiertas.'; Efecto = 'Se ve al momento.'
       Ruta = $Adv; Nombre = 'ShowTaskViewButton'; MinBuild = 0; Activado = 'mostrar'; Def = 'mostrar'; Rec = $null
       Opciones = @(@{ K = 'mostrar'; T = 'Mostrar'; V = 1 }, @{ K = 'ocultar'; T = 'Ocultar'; V = 0 }) }
    @{ Id = 'alineacion'; Grupo = 'Barra de tareas'; Titulo = 'Alineación de los iconos'; Descripcion = 'Dónde empiezan los iconos de la barra de tareas.'; Efecto = 'Se ve al momento.'
       Ruta = $Adv; Nombre = 'TaskbarAl'; MinBuild = 22000; Def = 'centro'; Rec = $null
       Opciones = @(@{ K = 'izquierda'; T = 'A la izquierda'; V = 0 }, @{ K = 'centro'; T = 'Centrados'; V = 1 }) }
    @{ Id = 'busqueda'; Grupo = 'Barra de tareas'; Titulo = 'Cuadro de búsqueda'; Descripcion = 'Cómo se muestra la búsqueda en la barra de tareas.'; Efecto = 'Se ve al momento.'
       Ruta = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; Nombre = 'SearchboxTaskbarMode'; MinBuild = 22000; Def = 'cuadro'; Rec = $null
       Nota = 'El valor de fábrica puede variar según la versión de Windows y el fabricante del equipo.'
       Opciones = @(@{ K = 'oculto'; T = 'Oculto'; V = 0 }, @{ K = 'icono'; T = 'Solo icono'; V = 1 }, @{ K = 'iconotexto'; T = 'Icono y texto'; V = 3 }, @{ K = 'cuadro'; T = 'Cuadro completo'; V = 2 }) }
    @{ Id = 'extensiones'; Grupo = 'Explorador de archivos'; Titulo = 'Mostrar las extensiones de archivo'; Descripcion = 'Ver «.exe», «.pdf», «.jpg»… al final del nombre. Ayuda a no abrir un programa disfrazado de documento.'; Efecto = 'Se ve al abrir una ventana nueva del Explorador.'
       Ruta = $Adv; Nombre = 'HideFileExt'; MinBuild = 0; Activado = 'mostrar'; Def = 'ocultar'; Rec = 'mostrar'
       Opciones = @(@{ K = 'mostrar'; T = 'Mostrar'; V = 0 }, @{ K = 'ocultar'; T = 'Ocultar'; V = 1 }) }
    @{ Id = 'ocultos'; Grupo = 'Explorador de archivos'; Titulo = 'Mostrar archivos y carpetas ocultos'; Descripcion = 'Enseña lo que Windows esconde por defecto (carpetas de programas, de configuración…).'; Efecto = 'Se ve al abrir una ventana nueva del Explorador.'
       Ruta = $Adv; Nombre = 'Hidden'; MinBuild = 0; Activado = 'mostrar'; Def = 'ocultar'; Rec = $null
       Opciones = @(@{ K = 'mostrar'; T = 'Mostrar'; V = 1 }, @{ K = 'ocultar'; T = 'Ocultar'; V = 2 }) }
)
$build = [Environment]::OSVersion.Version.Build

function Get-Actual($s) {
    $item = Get-ItemProperty -LiteralPath $s.Ruta -Name $s.Nombre -ErrorAction SilentlyContinue
    if ($null -eq $item) { return @{ K = $s.Def; Raw = $null } }   # sin valor: vale el de fábrica
    $raw = $item.($s.Nombre)
    $op = $s.Opciones | Where-Object { [string]$_.V -eq [string]$raw } | Select-Object -First 1
    @{ K = $(if ($op) { $op.K } else { 'otro' }); Raw = $raw }
}
function ConvertTo-Info($s) {
    $a = Get-Actual $s
    @{ id = $s.Id; grupo = $s.Grupo; titulo = $s.Titulo; descripcion = $s.Descripcion; efecto = $s.Efecto; nota = [string]$s.Nota
       tipo = $(if ($s.Opciones.Count -eq 2 -and $s.Activado) { 'interruptor' } else { 'lista' }); activado = [string]$s.Activado
       opciones = @($s.Opciones | ForEach-Object { @{ k = $_.K; t = $_.T; v = $_.V } }); def = $s.Def; rec = $s.Rec; actual = $a.K; raw = $a.Raw
       ruta = ($s.Ruta -replace '^HKCU:\\', 'HKCU\'); nombre = $s.Nombre; tipoReg = 'REG_DWORD'; aplicable = ($build -ge $s.MinBuild); minBuild = $s.MinBuild }
}

try {
    if ($Accion -eq 'Leer') { Salir @{ ok = $true; build = $build; otraCuenta = $otraCuenta; ajustes =@($Ajustes | ForEach-Object { ConvertTo-Info $_ }) }; exit 0 }
    $s = $Ajustes | Where-Object { $_.Id -ceq $Id } | Select-Object -First 1
    if (-not $s) { Salir @{ ok = $false; mensaje = 'Ese ajuste no existe.' }; exit 1 }
    $op = $s.Opciones | Where-Object { $_.K -ceq $Opcion } | Select-Object -First 1
    if (-not $op) { Salir @{ ok = $false; mensaje = 'Esa opción no es válida para este ajuste.' }; exit 1 }
    if ($build -lt $s.MinBuild) { Salir @{ ok = $false; mensaje = 'Este ajuste no existe en esta versión de Windows.' }; exit 1 }
    if ($otraCuenta.otra) { Salir @{ ok = $false; mensaje = "La app está abierta con otra cuenta ($($otraCuenta.proceso)) y el escritorio es de $($otraCuenta.sesion): estos ajustes cambiarían el perfil equivocado. Ábrela con tu propia cuenta de administrador." }; exit 1 }
    Start-SesionAjustes
    Set-ValorSeguro $s.Ruta $s.Nombre ([int]$op.V) 'DWord'
    Write-Log "Ajuste de Windows «$($s.Titulo)»: $($op.T)"
    Salir @{ ok = $true; ajuste = (ConvertTo-Info $s) }
} catch { Salir @{ ok = $false; mensaje = $_.Exception.Message }; exit 1 }
