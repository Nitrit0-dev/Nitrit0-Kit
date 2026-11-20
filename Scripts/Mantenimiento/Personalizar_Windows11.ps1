# =====================================================================
#  Personalizar_Windows11.ps1 (Edición Personal Nitrit0 - v2.5)
#  - Permite poner libremente cualquier nombre al PC y al Usuario.
#  - Corrige el error de cadena vacía en ConvertTo-SecureString cuando
#    el usuario no tiene contraseña previa o marca Restablecer.
# =====================================================================
[CmdletBinding()]
param([Alias('Simular')][switch]$SoloAnalizar)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }

if (-not $Global:E) {
    $Global:E = @{
        OK = [char]::ConvertFromUtf32(0x2705); Error = [char]::ConvertFromUtf32(0x274C); Aviso = [char]::ConvertFromUtf32(0x26A0)
        Info = [char]::ConvertFromUtf32(0x2139); PC = [char]::ConvertFromUtf32(0x1F5A5); Cohete = [char]::ConvertFromUtf32(0x1F680)
        Reloj = [char]::ConvertFromUtf32(0x23F3); Candado = [char]::ConvertFromUtf32(0x1F512)
    }
}
$E = $Global:E

if ($SoloAnalizar) {
    Write-Output "  $($E.Info) Modo análisis: la ventana ofrece alinear la barra de tareas a la izquierda, menú contextual clásico, quitar Bing de Inicio, poner 1920x1080, cambiar el nombre del PC y del usuario, cambiar la contraseña y reiniciar."
    Exit-Kit 'Ok' 'No se ha abierto la ventana ni se ha cambiado nada.'
}
Assert-Admin 'personalizar Windows (nombre del equipo, usuario y contraseña)'

function Test-NombreEquipo {
    param([string]$Nombre)
    if ([string]::IsNullOrWhiteSpace($Nombre)) { return 'Escribe el nuevo nombre para el PC.' }
    if ($Nombre.Length -gt 15) { return "Tiene $($Nombre.Length) caracteres: el máximo en Windows para el nombre de red del PC es 15." }
    if ($Nombre -notmatch '^[A-Za-z0-9-]+$') { return 'El nombre de red del PC solo admite letras (sin tildes ni espacios), números y guiones (ej: PC-Juan).' }
    if ($Nombre.StartsWith('-') -or $Nombre.EndsWith('-')) { return 'No puede empezar ni terminar en guion.' }
    if ($Nombre -match '^\d+$') { return 'No puede ser solo números.' }
    return $null
}

function Test-NombreUsuario {
    param([string]$Nombre)
    if ([string]::IsNullOrWhiteSpace($Nombre)) { return 'Escribe el nuevo nombre para el usuario.' }
    if ($Nombre.Length -gt 48) { return "Es demasiado largo (máximo 48 caracteres)." }
    return $null
}

function ConvertTo-SecureStringSeguro {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
    param([string]$Texto)
    if ([string]::IsNullOrEmpty($Texto)) {
        return (New-Object System.Security.SecureString)
    }
    return (ConvertTo-SecureString -String $Texto -AsPlainText -Force)
}

function Show-DialogoClave {
    param([string]$Usuario)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $d = New-Object System.Windows.Forms.Form
    $d.Text = 'Contraseña del usuario'; $d.StartPosition = 'CenterScreen'; $d.FormBorderStyle = 'FixedDialog'
    $d.MaximizeBox = $false; $d.MinimizeBox = $false; $d.TopMost = $true; $d.ClientSize = New-Object System.Drawing.Size(420, 290)

    $l0 = New-Object System.Windows.Forms.Label
    $l0.Text = "Usuario: $Usuario"; $l0.AutoSize = $true; $l0.Location = New-Object System.Drawing.Point(16, 14)
    $d.Controls.Add($l0)

    $cajas = @{}; $y = 44
    foreach ($par in @(@('Actual', 'Contraseña ACTUAL (déjala vacía si no tiene):'), @('Nueva', 'Contraseña NUEVA:'), @('Repite', 'Repite la contraseña nueva:'))) {
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $par[1]; $l.AutoSize = $true; $l.Location = New-Object System.Drawing.Point(16, $y)
        $d.Controls.Add($l)
        $c = New-Object System.Windows.Forms.TextBox
        $c.UseSystemPasswordChar = $true; $c.Location = New-Object System.Drawing.Point(16, ($y + 20)); $c.Size = New-Object System.Drawing.Size(388, 23)
        $d.Controls.Add($c); $cajas[$par[0]] = $c
        $y += 56
    }

    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = 'No recuerdo la actual: RESTABLECER (se pierden las contraseñas guardadas y archivos EFS)'
    $chk.Location = New-Object System.Drawing.Point(16, 216); $chk.Size = New-Object System.Drawing.Size(388, 36)
    $chk.ForeColor = [System.Drawing.Color]::DarkRed
    $d.Controls.Add($chk)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Aceptar'; $ok.Location = New-Object System.Drawing.Point(220, 254); $ok.Size = New-Object System.Drawing.Size(90, 28)
    $ok.Add_Click({
        if ([string]::IsNullOrEmpty($cajas['Nueva'].Text)) { [void][System.Windows.Forms.MessageBox]::Show('La contraseña nueva no puede estar vacía.', 'Contraseña', 0, 48); return }
        if ($cajas['Nueva'].Text -cne $cajas['Repite'].Text) { [void][System.Windows.Forms.MessageBox]::Show('Las dos contraseñas nuevas no coinciden.', 'Contraseña', 0, 48); return }
        $d.DialogResult = 'OK'
    })
    $no = New-Object System.Windows.Forms.Button
    $no.Text = 'Cancelar'; $no.Location = New-Object System.Drawing.Point(316, 254); $no.Size = New-Object System.Drawing.Size(90, 28); $no.DialogResult = 'Cancel'
    $d.Controls.AddRange(@($ok, $no)); $d.CancelButton = $no

    $res = $null
    try {
        if ($d.ShowDialog() -eq 'OK') {
            $res = [pscustomobject]@{
                Actual      = ConvertTo-SecureStringSeguro -Texto $cajas['Actual'].Text
                Nueva       = ConvertTo-SecureStringSeguro -Texto $cajas['Nueva'].Text
                Restablecer = [bool]$chk.Checked
            }
        }
    } finally {
        foreach ($c in $cajas.Values) { $c.Text = '' }
        $d.Dispose()
    }
    return $res
}

function Set-NombreUsuarioLocal {
    param([string]$Actual, [string]$Nuevo, [string]$NombrePcObjetivo)

    if ((Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue).PartOfDomain) {
        Write-Output "  $($E.Aviso) El equipo está en un dominio: el usuario no se puede renombrar localmente."
        return $false
    }
    try { $cuenta = Get-LocalUser -Name $Actual -ErrorAction Stop }
    catch { Write-Output "  $($E.Error) No se encontró la cuenta local '$Actual'."; return $false }

    $cambioHecho = $false
    try {
        Set-LocalUser -Name $Actual -FullName $Nuevo -ErrorAction Stop
        $cambioHecho = $true
        Write-Output "  $($E.OK) Nombre visible en Menú Inicio y pantalla de sesión cambiado a: '$Nuevo'."

        $NombreLogin = ($Nuevo -replace '[\\/\[\]:;|=,+*?<>"]', '').Trim()
        if ($NombreLogin.Length -gt 20) { $NombreLogin = $NombreLogin.Substring(0, 20).Trim() }

        $PcComparar = if ($NombrePcObjetivo) { $NombrePcObjetivo } else { $env:COMPUTERNAME }
        if ($NombreLogin -ieq $PcComparar) {
            Write-Output "  $($E.Info) Como el PC también se llama '$PcComparar', Windows usa '$Nuevo' en el Menú Inicio y conserva '$Actual' como identificador interno."
        } elseif ([string]$cuenta.PrincipalSource -eq 'Local' -and $NombreLogin -and $Actual -cne $NombreLogin) {
            Rename-LocalUser -Name $Actual -NewName $NombreLogin -ErrorAction SilentlyContinue
            Write-Output "  $($E.OK) Cuenta local renombrada internamente: '$Actual' -> '$NombreLogin'."
        }
        return $true
    } catch {
        Write-Output "  $($E.Error) Error al cambiar el nombre de usuario: $($_.Exception.Message)"
        return $cambioHecho
    }
}

function Set-ClaveUsuarioLocal {
    param([string]$Usuario, $Clave)

    if ((Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue).PartOfDomain) {
        Write-Output "  $($E.Aviso) El equipo está en un dominio: la contraseña la gestiona el dominio."
        return
    }
    try { $cuenta = Get-LocalUser -Name $Usuario -ErrorAction Stop }
    catch { Write-Output "  $($E.Error) '$Usuario' no es una cuenta local de este equipo."; return }
    if ([string]$cuenta.PrincipalSource -ne 'Local') {
        Write-Output "  $($E.Aviso) '$Usuario' está vinculada a una cuenta Microsoft: cámbiala en account.microsoft.com."
        return
    }

    $bNueva = [IntPtr]::Zero; $bActual = [IntPtr]::Zero
    try {
        $bNueva = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Clave.Nueva)
        $nueva  = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bNueva)
        if ($Clave.Restablecer) {
            Set-LocalUser -Name $Usuario -Password $Clave.Nueva -ErrorAction Stop
            Write-Output "  $($E.OK) Contraseña de '$Usuario' RESTABLECIDA correctamente."
        } else {
            $actual = ""
            if ($Clave.Actual -and $Clave.Actual.Length -gt 0) {
                $bActual = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Clave.Actual)
                $actual  = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bActual)
            }
            $objeto = [ADSI]"WinNT://$env:COMPUTERNAME/$Usuario,user"
            $objeto.ChangePassword($actual, $nueva)
            Write-Output "  $($E.OK) Contraseña de '$Usuario' cambiada correctamente."
        }
    } catch {
        Write-Output "  $($E.Error) No se pudo cambiar la contraseña: $($_.Exception.Message)"
        Write-Output "      (Si no tenía contraseña o no recuerdas la anterior, repite marcando la casilla 'RESTABLECER')."
    } finally {
        if ($bNueva -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bNueva) }
        if ($bActual -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bActual) }
    }
}

# Detectar el usuario interactivo real (dueño de explorer.exe)
$UsuarioActual = $env:USERNAME
try {
    $Exp = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($Exp) {
        $Own = Invoke-CimMethod -InputObject $Exp -MethodName GetOwner -ErrorAction SilentlyContinue
        if ($Own -and $Own.User) { $UsuarioActual = $Own.User }
    }
} catch {}

$NombreVisibleActual = $UsuarioActual
try {
    $uObj = Get-LocalUser -Name $UsuarioActual -ErrorAction SilentlyContinue
    if ($uObj -and $uObj.FullName) { $NombreVisibleActual = $uObj.FullName }
} catch {}

Write-Output "`n========================================================"
Write-Output "  $($E.Cohete) PERSONALIZACIÓN WINDOWS 11 Y CUENTA - NITRIT0"
Write-Output "========================================================`n"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "Personalizar Windows 11 - Nitrit0"
$Form.Size = New-Object System.Drawing.Size(485, 465)
$Form.StartPosition = "CenterScreen"
$Form.TopMost = $true
$Form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$Form.FormBorderStyle = "FixedDialog"
$Form.MaximizeBox = $false

$Label = New-Object System.Windows.Forms.Label
$Label.Text = "Selecciona los ajustes a aplicar en este PC:"
$Label.Location = New-Object System.Drawing.Point(20, 15)
$Label.AutoSize = $true
$Label.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$Form.Controls.Add($Label)

$ChkBarra = New-Object System.Windows.Forms.CheckBox
$ChkBarra.Text = "Alinear Barra de Tareas a la Izquierda"; $ChkBarra.Location = New-Object System.Drawing.Point(20, 45); $ChkBarra.Size = New-Object System.Drawing.Size(420, 20); $ChkBarra.Checked = $true
$Form.Controls.Add($ChkBarra)

$ChkMenu = New-Object System.Windows.Forms.CheckBox
$ChkMenu.Text = "Restaurar Menú Contextual Clásico (Clic derecho)"; $ChkMenu.Location = New-Object System.Drawing.Point(20, 75); $ChkMenu.Size = New-Object System.Drawing.Size(420, 20); $ChkMenu.Checked = $true
$Form.Controls.Add($ChkMenu)

$ChkBing = New-Object System.Windows.Forms.CheckBox
$ChkBing.Text = "Desactivar búsquedas web (Bing) en el Menú Inicio"; $ChkBing.Location = New-Object System.Drawing.Point(20, 105); $ChkBing.Size = New-Object System.Drawing.Size(420, 20); $ChkBing.Checked = $true
$Form.Controls.Add($ChkBing)

$ChkResolucion = New-Object System.Windows.Forms.CheckBox
$ChkResolucion.Text = "Forzar Resolución 1920x1080"; $ChkResolucion.Location = New-Object System.Drawing.Point(20, 135); $ChkResolucion.Size = New-Object System.Drawing.Size(420, 20); $ChkResolucion.ForeColor = "DarkBlue"
$Form.Controls.Add($ChkResolucion)

$LblEquipo = New-Object System.Windows.Forms.Label
$LblEquipo.Text = "Equipo y cuenta local (escribe el nombre que quieras):"; $LblEquipo.Location = New-Object System.Drawing.Point(20, 170); $LblEquipo.AutoSize = $true; $LblEquipo.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$Form.Controls.Add($LblEquipo)

$ChkNombre = New-Object System.Windows.Forms.CheckBox
$ChkNombre.Text = "Cambiar nombre del PC ($env:COMPUTERNAME) a:"; $ChkNombre.Location = New-Object System.Drawing.Point(20, 198); $ChkNombre.Size = New-Object System.Drawing.Size(265, 20)
$Form.Controls.Add($ChkNombre)

$TxtNombre = New-Object System.Windows.Forms.TextBox
$TxtNombre.Text = ""; $TxtNombre.MaxLength = 15; $TxtNombre.Location = New-Object System.Drawing.Point(290, 196); $TxtNombre.Size = New-Object System.Drawing.Size(160, 23)
$TxtNombre.Add_TextChanged({ if ($TxtNombre.Text.Trim().Length -gt 0) { $ChkNombre.Checked = $true } })
$Form.Controls.Add($TxtNombre)

$ChkNombreUsr = New-Object System.Windows.Forms.CheckBox
$ChkNombreUsr.Text = "Cambiar usuario ($NombreVisibleActual) a:"; $ChkNombreUsr.Location = New-Object System.Drawing.Point(20, 228); $ChkNombreUsr.Size = New-Object System.Drawing.Size(265, 20)
$Form.Controls.Add($ChkNombreUsr)

$TxtNombreUsr = New-Object System.Windows.Forms.TextBox
$TxtNombreUsr.Text = ""; $TxtNombreUsr.MaxLength = 48; $TxtNombreUsr.Location = New-Object System.Drawing.Point(290, 226); $TxtNombreUsr.Size = New-Object System.Drawing.Size(160, 23)
$TxtNombreUsr.Add_TextChanged({ if ($TxtNombreUsr.Text.Trim().Length -gt 0) { $ChkNombreUsr.Checked = $true } })
$Form.Controls.Add($TxtNombreUsr)

$ChkClave = New-Object System.Windows.Forms.CheckBox
$ChkClave.Text = "Poner o cambiar contraseña de mi usuario ($UsuarioActual)"; $ChkClave.Location = New-Object System.Drawing.Point(20, 258); $ChkClave.Size = New-Object System.Drawing.Size(430, 20)
$Form.Controls.Add($ChkClave)

$ChkReinicio = New-Object System.Windows.Forms.CheckBox
$ChkReinicio.Text = "Reiniciar al terminar (30 s; aplica el nuevo nombre en Menú Inicio)"; $ChkReinicio.Location = New-Object System.Drawing.Point(20, 288); $ChkReinicio.Size = New-Object System.Drawing.Size(430, 20)
$Form.Controls.Add($ChkReinicio)

$script:Opc = @{ Ejecutar = $false; Barra = $false; Menu = $false; Bing = $false; Resolucion = $false; NombreNuevo = $null; UsuarioNuevo = $null; Clave = $null; Reiniciar = $false }

$BtnAplicar = New-Object System.Windows.Forms.Button
$BtnAplicar.Text = "Aplicar Seleccionados"; $BtnAplicar.Location = New-Object System.Drawing.Point(20, 345); $BtnAplicar.Size = New-Object System.Drawing.Size(200, 42); $BtnAplicar.BackColor = "LightGreen"; $BtnAplicar.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$BtnAplicar.Add_Click({
    $script:Opc.Barra = $ChkBarra.Checked; $script:Opc.Menu = $ChkMenu.Checked; $script:Opc.Bing = $ChkBing.Checked; $script:Opc.Resolucion = $ChkResolucion.Checked
    if ($ChkNombre.Checked) {
        $motivo = Test-NombreEquipo -Nombre $TxtNombre.Text.Trim()
        if ($motivo) { [void][System.Windows.Forms.MessageBox]::Show("Nombre de PC no válido:`n$motivo", "Nombre del equipo", 0, 48); return }
        $script:Opc.NombreNuevo = $TxtNombre.Text.Trim()
    }
    if ($ChkNombreUsr.Checked) {
        $motivoU = Test-NombreUsuario -Nombre $TxtNombreUsr.Text.Trim()
        if ($motivoU) { [void][System.Windows.Forms.MessageBox]::Show("Nombre de usuario no válido:`n$motivoU", "Nombre de usuario", 0, 48); return }
        $script:Opc.UsuarioNuevo = $TxtNombreUsr.Text.Trim()
    }
    if ($ChkClave.Checked) {
        $dlg = Show-DialogoClave -Usuario $UsuarioActual
        if (-not $dlg) { return }
        $script:Opc.Clave = $dlg
    }
    $script:Opc.Reiniciar = $ChkReinicio.Checked
    $script:Opc.Ejecutar  = $true
    $Form.Close()
})
$Form.Controls.Add($BtnAplicar)

$BtnCancelar = New-Object System.Windows.Forms.Button
$BtnCancelar.Text = "Cancelar"; $BtnCancelar.Location = New-Object System.Drawing.Point(250, 345); $BtnCancelar.Size = New-Object System.Drawing.Size(200, 42); $BtnCancelar.BackColor = "LightCoral"
$BtnCancelar.Add_Click({ $Form.Close() })
$Form.Controls.Add($BtnCancelar)

[void]$Form.ShowDialog()
if (-not $script:Opc.Ejecutar) { Exit-Kit 'Cancelado' 'Operación cancelada.' }
# Lo que no se puede deshacer se confirma aparte diciendo la consecuencia (-Siempre: ningún modo automático acepta por la persona)
$irreversible = @()
if ($script:Opc.Clave) { $irreversible += 'Cambiar la contraseña del usuario como administrador: se pierden los archivos cifrados con EFS y las credenciales guardadas de esa cuenta.' }
if ($script:Opc.UsuarioNuevo) { $irreversible += "Renombrar el usuario a «$($script:Opc.UsuarioNuevo)»." }
if ($script:Opc.NombreNuevo -and $script:Opc.NombreNuevo -ine $env:COMPUTERNAME) { $irreversible += "Renombrar el PC a «$($script:Opc.NombreNuevo)»." }
if ($script:Opc.Reiniciar -and ($script:Opc.UsuarioNuevo -or ($script:Opc.NombreNuevo -and $script:Opc.NombreNuevo -ine $env:COMPUTERNAME))) { $irreversible += 'Reiniciar el equipo a los 30 segundos: guarda antes tu trabajo.' }
if ($irreversible.Count -and -not (Confirm-Accion ("«Deshacer cambios» no puede revertir esto:`n`n• " + ($irreversible -join "`n• ") + "`n`n¿Continuar?") 'Personalizar Windows 11' -Siempre)) { Exit-Kit 'Cancelado' 'Cancelado: no se ha cambiado nada.' }
[void](Start-OperacionSegura 'Personalizar Windows 11')

$ReinicioExplorer = $false
$RaizUsuario = "HKCU:"
try {
    $Explorer = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($Explorer) {
        $SidUsuario = (Invoke-CimMethod -InputObject $Explorer -MethodName GetOwnerSid -ErrorAction SilentlyContinue).Sid
        if ($SidUsuario -and (Test-Path "Registry::HKEY_USERS\$SidUsuario")) { $RaizUsuario = "Registry::HKEY_USERS\$SidUsuario" }
    }
} catch {}

if ($script:Opc.Barra) {
    $Path = "$RaizUsuario\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Set-ValorSeguro $Path "TaskbarAl" 0 'DWord'
    Write-Output "  $($E.OK) Barra de tareas alineada a la izquierda."
    $ReinicioExplorer = $true
}
if ($script:Opc.Menu) {
    $Path = "$RaizUsuario\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
    Set-ValorSeguro $Path "(default)" "" 'String'
    Write-Output "  $($E.OK) Menú contextual clásico de Windows 10 activado."
    $ReinicioExplorer = $true
}
if ($script:Opc.Bing) {
    $Path = "$RaizUsuario\Software\Policies\Microsoft\Windows\Explorer"
    Set-ValorSeguro $Path "DisableSearchBoxSuggestions" 1 'DWord'
    Write-Output "  $($E.OK) Búsquedas web de Bing desactivadas en Inicio."
    $ReinicioExplorer = $true
}
if ($script:Opc.Resolucion) {
    Write-Output "  $($E.Info) Aplicando resolución 1920x1080..."
    try {
        if (-not ('DisplayResNitri' -as [type])) {
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class DisplayResNitri {
    [StructLayout(LayoutKind.Sequential)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
        public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
        public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
        public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
    }
    [DllImport("user32.dll")] public static extern int EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);
    [DllImport("user32.dll")] public static extern int ChangeDisplaySettings(ref DEVMODE devMode, int flags);
    public static string SetResolution(int width, int height) {
        DEVMODE dm = new DEVMODE();
        dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        if (EnumDisplaySettings(null, -1, ref dm) != 0) {
            dm.dmPelsWidth = width; dm.dmPelsHeight = height;
            int ret = ChangeDisplaySettings(ref dm, 0);
            return ret == 0 ? "OK" : "ERROR: " + ret;
        }
        return "ERROR: EnumDisplaySettings falló";
    }
}
"@ -ErrorAction Stop
        }
        $Res = [DisplayResNitri]::SetResolution(1920, 1080)
        if ($Res -eq "OK") { Write-Output "  $($E.OK) Resolución cambiada a 1920x1080." }
        else { Write-Output "  $($E.Aviso) La pantalla no admitió 1920x1080 ($Res)." }
    } catch {
        Write-Output "  $($E.Error) Error cambiando resolución: $($_.Exception.Message)"
    }
}

if ($ReinicioExplorer) {
    Write-Output "  $($E.Info) Reiniciando el Explorador de Windows..."
    # Solo el Explorador de esta sesión: con -Name se cerraba también el de otros usuarios conectados (RDP)
    $miSesion = (Get-Process -Id $PID).SessionId
    Get-Process -Name explorer -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $miSesion } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

$RequiereReinicio = $false

# 1. Cambiar primero la contraseña usando el nombre de cuenta actual (antes de renombrarla)
if ($script:Opc.Clave) {
    Save-Informativo 'Se cambió la contraseña del usuario (no se puede deshacer automáticamente)' $UsuarioActual
    Set-ClaveUsuarioLocal -Usuario $UsuarioActual -Clave $script:Opc.Clave
    $script:Opc.Clave = $null
}

# 2. Renombrar el usuario si se solicitó
if ($script:Opc.UsuarioNuevo) {
    Save-Informativo 'Se renombró el usuario local (no se puede deshacer automáticamente)' "$UsuarioActual -> $($script:Opc.UsuarioNuevo)"
    if (Set-NombreUsuarioLocal -Actual $UsuarioActual -Nuevo $script:Opc.UsuarioNuevo -NombrePcObjetivo $script:Opc.NombreNuevo) {
        $RequiereReinicio = $true
    }
}

# 3. Renombrar el PC si se solicitó
if ($script:Opc.NombreNuevo -and $script:Opc.NombreNuevo -ine $env:COMPUTERNAME) {
    try {
        Save-Cambio @{ Tipo = 'NombrePC'; Previo = $env:COMPUTERNAME }
        Rename-Computer -NewName $script:Opc.NombreNuevo -Force -ErrorAction Stop
        Write-Output "  $($E.OK) Nombre del PC cambiado a '$($script:Opc.NombreNuevo)' (se aplica al reiniciar)."
        $RequiereReinicio = $true
    } catch { Write-Output "  $($E.Error) No se pudo cambiar el nombre del PC: $($_.Exception.Message)" }
}

if ($RequiereReinicio -and $script:Opc.Reiniciar) {
    & shutdown.exe /r /t 30 /c "Aplicando nuevo nombre de equipo/usuario en 30 segundos"
    Write-Output "  $($E.Reloj) Reinicio programado en 30 segundos."
} elseif ($RequiereReinicio) {
    Write-Output "  $($E.Aviso) Cierra sesión o reinicia el equipo para ver el nuevo nombre en el Menú Inicio."
}

Write-Output "`n  $($E.OK) Proceso de personalización finalizado."
Write-Output "  $($E.Info) Para deshacer los ajustes: Mantenimiento > Deshacer cambios."