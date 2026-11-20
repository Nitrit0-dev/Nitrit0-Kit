# =====================================================================
#  Reparar_Perfil_Usuario.ps1 - Perfiles de usuario dañados o temporales (Nitrit0)
#  Para «Hemos iniciado sesión con un perfil temporal», «No se puede cargar el perfil de usuario» o un
#  escritorio que aparece vacío. Lista las cuentas con su carpeta, tamaño y estado, busca los errores de
#  perfil del registro de sucesos y detecta las entradas dañadas (.bak) de la lista de perfiles.
#  La reparación solo corrige esas entradas del registro (con copia previa): NUNCA borra carpetas ni archivos.
#  No se puede reparar el perfil de la cuenta con la sesión abierta: hay que entrar con otra cuenta de
#  administrador o reiniciar después.
#  Parámetro: -SinPreguntas (solo diagnostica)
# =====================================================================
[CmdletBinding()]
param([Alias('SoloAnalizar', 'Simular')][switch]$SinPreguntas)   # -SinPreguntas ya solo diagnostica
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
$lista = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'

Write-Output "========================================================"
Write-Output "  $($E.Lupa) PERFILES DE USUARIO"
Write-Output "========================================================"

function Get-NombreSid([string]$sid) { try { (New-Object Security.Principal.SecurityIdentifier($sid)).Translate([Security.Principal.NTAccount]).Value } catch { '(cuenta eliminada o de otro dominio)' } }
$cargados = @(Get-ChildItem 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue | ForEach-Object { $_.PSChildName })

# 1) Entradas de la lista de perfiles (solo cuentas de persona: S-1-5-21-… y cuentas Microsoft/Entra S-1-12-1-…)
$entradas = @(Get-ChildItem -LiteralPath $lista -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^S-1-(5-21|12-1)-' } | ForEach-Object {
        $p = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
        $sid = $_.PSChildName -replace '\.bak$', ''
        [pscustomobject]@{ Clave = $_.PSChildName; Sid = $sid; EsBak = ($_.PSChildName -match '\.bak$'); Ruta = [Environment]::ExpandEnvironmentVariables([string]$p.ProfileImagePath); Estado = [int]$p.State; Cuenta = (Get-NombreSid $sid) }
    })
Write-Output "`n  [1/3] Cuentas con perfil en este equipo"
if (-not $entradas.Count) { Write-Output "    $($E.Aviso) No se pudo leer la lista de perfiles." }
$danados = New-Object Collections.Generic.List[object]
foreach ($g in ($entradas | Group-Object Sid)) {
    $normal = $g.Group | Where-Object { -not $_.EsBak } | Select-Object -First 1; $bak = $g.Group | Where-Object EsBak | Select-Object -First 1
    $ref = if ($bak) { $bak } else { $normal }
    $existe = $ref.Ruta -and (Test-Path -LiteralPath $ref.Ruta)
    $temporal = ($normal -and (($normal.Estado -band 0x800) -or $normal.Ruta -match '\\TEMP(\.|$)')) -or ($cargados -contains $g.Name -and $bak)
    $sesion = $cargados -contains $g.Name
    $notas = @(); if ($sesion) { $notas += 'sesión abierta' }; if (-not $existe) { $notas += 'LA CARPETA NO EXISTE' }; if ($bak) { $notas += 'entrada .bak (dañada)' }; if ($temporal) { $notas += 'perfil TEMPORAL' }
    $mal = [bool]($bak -or $temporal -or -not $existe)
    Write-Output "    $(if ($mal) { $E.Aviso } else { $E.OK }) $($ref.Cuenta)  ·  $($ref.Ruta)$(if ($notas) { '  ·  ' + ($notas -join ', ') })"
    if ($bak) { $danados.Add([pscustomobject]@{ Sid = $g.Name; Cuenta = $ref.Cuenta; Normal = $normal; Bak = $bak; Sesion = $sesion; Existe = $existe }) }
}

# Carpetas de usuario sin cuenta que las use (restos de perfiles antiguos; pueden guardar los documentos que «han desaparecido»)
$raizUsuarios = Split-Path -Parent $env:PUBLIC
$usadas = @($entradas | ForEach-Object { $_.Ruta.TrimEnd('\').ToLower() })
foreach ($d in (Get-ChildItem -LiteralPath $raizUsuarios -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin 'Public', 'Default', 'Default User', 'All Users', 'defaultuser0' -and $usadas -notcontains $_.FullName.ToLower() })) {
    Write-Output "    $($E.Info) Carpeta sin cuenta: $($d.FullName)  (modificada el $($d.LastWriteTime.ToString('dd/MM/yyyy'))). Si faltan documentos, pueden estar aquí."
}

# 2) Errores de perfil en el registro de sucesos
Write-Output "`n  [2/3] Errores de perfil en los últimos 30 días"
$ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Microsoft-Windows-User Profiles Service'; Level = 1, 2, 3; StartTime = (Get-Date).AddDays(-30) } -MaxEvents 40 -ErrorAction SilentlyContinue)
if (-not $ev.Count) { Write-Output "    $($E.OK) Ninguno." }
else {
    $sig = @{ 1511 = 'no se encontró el perfil y se entró con uno temporal'; 1515 = 'se hizo copia del perfil y se entró con uno temporal'; 1508 = 'no se pudo cargar el registro del usuario (NTUSER.DAT dañado o en uso)'; 1502 = 'no se pudo cargar el perfil'; 1500 = 'no se pudo iniciar sesión con el perfil'; 1530 = 'el registro del usuario seguía en uso al cerrar sesión (no es grave)'; 1542 = 'no se pudo cargar el registro de clases' }
    foreach ($g in ($ev | Group-Object Id | Sort-Object Count -Descending)) { Write-Output "    $(if ($g.Name -eq '1530') { $E.Info } else { $E.Aviso }) Suceso $($g.Name) × $($g.Count)  (último: $(($g.Group | Select-Object -First 1).TimeCreated.ToString('dd/MM/yyyy HH:mm'))): $(if ($sig[[int]$g.Name]) { $sig[[int]$g.Name] } else { (($g.Group[0].Message -split "`n")[0]).Trim() })" }
}
$libre = try { (Get-PSDrive -Name $env:SystemDrive[0] -ErrorAction Stop).Free } catch { $null }
if ($null -ne $libre -and $libre -lt 1GB) { Write-Output "    $($E.Error) El disco de Windows tiene menos de 1 GB libre: es una causa habitual de perfiles temporales. Libera espacio antes de nada." }

# 3) Reparación
Write-Output "`n  [3/3] Reparación"
if (-not $danados.Count) {
    Write-Output "    $($E.OK) No hay entradas dañadas en la lista de perfiles."
    if ($ev | Where-Object { $_.Id -in 1508, 1502, 1500 }) { Write-Output "    $($E.Info) Hay errores al cargar el registro del usuario: pasa «Reparar Windows y Tienda» (comprueba el disco) y reinicia. Si persiste, crea una cuenta nueva y copia los datos con «Copia de datos del usuario»." }
    Write-Log "Perfiles: $($entradas.Count) entradas, sin daños"; exit 0
}
foreach ($d in $danados) { Write-Output "    $($E.Aviso) $($d.Cuenta): Windows apartó su perfil (entrada .bak) y $(if ($d.Normal) { 'creó otro vacío o temporal en su lugar' } else { 'no tiene ninguno en uso' }). Carpeta original: $($d.Bak.Ruta)$(if (-not $d.Existe) { '  (NO EXISTE)' })" }
if ($SinPreguntas) { Write-Output "    $($E.Info) Modo sin preguntas: no se cambia nada."; Write-Log "Perfiles: $($danados.Count) entrada(s) dañada(s), solo diagnóstico"; exit 0 }

Add-Type -AssemblyName System.Windows.Forms
$hechos = 0
foreach ($d in $danados) {
    if (-not $d.Existe) { Write-Output "    $($E.Error) $($d.Cuenta): la carpeta original ya no existe, así que no hay perfil que recuperar. Busca sus datos en las «carpetas sin cuenta» de arriba."; continue }
    if ($d.Sesion) { Write-Output "    $($E.Aviso) $($d.Cuenta) tiene la sesión abierta: no se puede reparar ahora. Cierra su sesión, entra con OTRA cuenta de administrador y vuelve a pasar esta herramienta."; continue }
    $msg = "Recuperar el perfil original de $($d.Cuenta)`n`nCarpeta: $($d.Bak.Ruta)`n`nSe corrige la lista de perfiles de Windows para que vuelva a usar esa carpeta. No se borra ni se mueve ningún archivo, y se guarda copia del registro para poder deshacerlo.`n`n¿Continuar?"
    if ([Windows.Forms.MessageBox]::Show($msg, 'Reparar perfil', 'YesNo', 'Question', 'Button2') -ne 'Yes') { Write-Output "    $($E.Info) $($d.Cuenta): no se ha cambiado nada."; continue }
    try {
        if (-not $Global:NitOp) { $dirOp = Start-OperacionSegura 'Reparar perfil de usuario' -SinPuntoRestauracion } else { $dirOp = $Global:NitOp.Dir }
        $copia = Join-Path $dirOp "ProfileList_$($d.Sid).reg"
        & reg.exe export 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' $copia /y 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $copia)) { throw 'no se pudo guardar la copia del registro: no se cambia nada' }
        # La entrada en uso (vacía o temporal) se aparta con otro nombre y la original (.bak) recupera el suyo
        if ($d.Normal) { Rename-Item -LiteralPath (Join-Path $lista $d.Sid) -NewName "$($d.Sid).nitrit0_$(Get-Date -Format 'yyyyMMddHHmmss')" -ErrorAction Stop }
        Rename-Item -LiteralPath (Join-Path $lista "$($d.Sid).bak") -NewName $d.Sid -ErrorAction Stop
        $k = Join-Path $lista $d.Sid
        Set-ItemProperty -LiteralPath $k -Name State -Value 0 -Type DWord -ErrorAction Stop
        if ($null -ne (Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue).RefCount) { Set-ItemProperty -LiteralPath $k -Name RefCount -Value 0 -Type DWord -ErrorAction SilentlyContinue }
        Save-Informativo "Lista de perfiles corregida para $($d.Cuenta)" "Para deshacerlo: doble clic en $copia y reiniciar."
        $hechos++; Write-Output "    $($E.OK) $($d.Cuenta): perfil original recuperado. Copia del registro en $copia"
        Write-Log "Perfiles: recuperada la entrada de $($d.Cuenta) ($($d.Sid))"
    } catch { Write-Output "    $($E.Error) $($d.Cuenta): no se pudo reparar: $($_.Exception.Message)"; Write-Log "Perfiles: fallo al reparar $($d.Sid) - $($_.Exception.Message)" 'ERROR' }
}
if ($hechos) { Write-Output "`n  $($E.Refresh) REINICIA el equipo y entra con la cuenta reparada. Si vuelve a salir el perfil temporal, su registro (NTUSER.DAT) está dañado: crea una cuenta nueva y pasa los datos con «Copia de datos del usuario»." }
