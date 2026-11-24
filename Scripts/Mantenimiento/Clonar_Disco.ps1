# =====================================================================
#  Clonar_Disco.ps1 - Clona un disco con Windows (GPT/UEFI) a otro disco, incluso más pequeño (Nitrit0)
#  Qué hace: recrea la tabla de particiones en el disco destino (EFI, MSR, Windows, Recuperación y datos), copia Windows con
#  DISM desde una instantánea VSS (conserva enlaces físicos y permisos: es lo que Microsoft admite, no una copia de archivos),
#  copia las particiones de datos y de recuperación y deja el arranque listo con bcdboot. El disco ORIGEN no se modifica.
#  Qué NO hace: discos MBR/BIOS, discos dinámicos, ni clonar a un disco menor que lo realmente usado (+15 %).
#  Seguridad: por defecto SOLO SIMULA y enseña el plan. Nunca deja elegir de destino el disco de Windows en marcha ni el del kit.
#  Para ejecutar de verdad hay que escribir «BORRAR DISCO <n>» y el destino se vuelve a comprobar (número y serie) antes de tocarlo.
#  El destino se BORRA ENTERO. Necesita sitio libre (≈ lo usado) en otro disco para la imagen temporal.
#  Parámetros: -Origen <n> -Destino <n> -CarpetaImagen <ruta> -Ejecutar -Confirmo "BORRAR DISCO <n>" (sin ventanas)
# =====================================================================
[CmdletBinding()]
param([int]$Origen = -1, [int]$Destino = -1, [string]$CarpetaImagen = '', [switch]$Ejecutar, [string]$Confirmo = '', [switch]$ListarDiscos, [string]$OrigenId = '', [string]$DestinoId = '', [switch]$LimpiarRestos, [ValidateSet('Windows', 'Datos')][string]$Extra = 'Windows')
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$esAdmin = Test-EsAdmin
if (-not $esAdmin) { Write-Output "$($E.Aviso) Hace falta administrador para clonar discos. Ábrelo desde el kit."; exit 1 }

$ESP = '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'; $MSR = '{e3c9e316-0b5c-4db8-817d-f92df00215ae}'
$REC = '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}'; $BAS = '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}'
$LDM = @('{5808c8aa-7e8f-42e0-85d2-e1e90434cfb3}', '{af9b60a0-1431-4f62-bc68-3311714a69ad}')

# ---------------------------------------------------------------- Lectura de discos
$discoSis = -1; try { $discoSis = (Get-Partition -DriveLetter $env:SystemDrive.TrimEnd(':') -ErrorAction Stop).DiskNumber } catch { }
$discoKit = -1; try { $discoKit = (Get-Partition -DriveLetter ((Get-KitRaiz).Substring(0, 1)) -ErrorAction Stop).DiskNumber } catch { }
# Discos que nunca pueden ser destino: el de la letra del sistema y, además, los que Windows marca como sistema o arranque (la letra puede fallar en discos dinámicos o arranque desde VHD)
$protegidos = @($discoSis, $discoKit) + @(Get-Disk -ErrorAction SilentlyContinue | Where-Object { $_.IsSystem -or $_.IsBoot } | ForEach-Object { $_.Number })
function Get-TextoDisco($d) {
    $t = @(); if ($d.Number -eq $discoSis) { $t += 'Windows en marcha' }; if ($d.Number -eq $discoKit) { $t += 'este kit' }; if ($d.BusType -eq 'USB') { $t += 'USB' }
    '{0} · {1} · {2} GB · {3}{4}' -f $d.Number, $d.FriendlyName, [math]::Round($d.Size / 1GB), $d.PartitionStyle, $(if ($t) { ' · ' + ($t -join ', ') } else { '' })
}
function Get-VolumenWindows([int]$n) {
    foreach ($p in @(Get-Partition -DiskNumber $n -ErrorAction SilentlyContinue)) {
        if ($p.DriveLetter -and (Test-Path -LiteralPath ('{0}:\Windows\System32\config\SYSTEM' -f $p.DriveLetter))) { return $p }
    }
    $null
}
$discos = @(Get-Disk | Sort-Object Number)
if ($ListarDiscos) {   # lo usa Nitrit0_Clonador.exe para pintar su selector: solo lee, una línea JSON marcada
    $lista = foreach ($d in $discos) {
        $letras = @(Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue | Where-Object DriveLetter | ForEach-Object { [string]$_.DriveLetter })
        [pscustomobject]@{ Numero = [int]$d.Number; Nombre = [string]$d.FriendlyName; GB = [int][math]::Round($d.Size / 1GB); Estilo = [string]$d.PartitionStyle; Sistema = ($d.Number -eq $discoSis -or ($protegidos -contains $d.Number -and $d.Number -ne $discoKit)); Kit = ($d.Number -eq $discoKit); Serie = ([string]$d.SerialNumber).Trim(); Id = [string]$d.UniqueId; Bus = [string]$d.BusType; USB = ($d.BusType -eq 'USB'); TieneWindows = [bool](Get-VolumenWindows $d.Number); Letras = ($letras -join ' ') }
    }
    Write-Output ('##DISCOS##' + (ConvertTo-Json -InputObject @($lista) -Compress)); exit 0
}
# Instantáneas creadas por este script: se anotan en HKLM\SOFTWARE\Nitrit0\ClonadoSnap, que por defecto solo escriben los administradores.
# La limpieza borra solo lo anotado ahí; nunca fía de lo que haya en %TEMP% ni en carpetas que un usuario pudiera haber creado antes.
$script:regSnap = 'HKLM:\SOFTWARE\Nitrit0\ClonadoSnap'
function Add-RegistroSnap([string]$id, [string]$link) { if (-not (Test-Path -LiteralPath $script:regSnap)) { New-Item -Path $script:regSnap -Force | Out-Null }; New-ItemProperty -LiteralPath $script:regSnap -Name $id -Value $link -PropertyType String -Force | Out-Null }
function Get-RegistroSnap {
    if (-not (Test-Path -LiteralPath $script:regSnap)) { return @() }
    $k = Get-Item -LiteralPath $script:regSnap
    @($k.GetValueNames() | Where-Object { $_ -match '^\{?[0-9A-Fa-f\-]{36}\}?$' } | ForEach-Object { [pscustomobject]@{ Id = $_; Link = [string]$k.GetValue($_) } })
}
function Remove-RegistroSnap([string]$id) { if (Test-Path -LiteralPath $script:regSnap) { Remove-ItemProperty -LiteralPath $script:regSnap -Name $id -ErrorAction SilentlyContinue } }
if ($LimpiarRestos) {   # tras cancelar o cortar un clonado: el proceso muerto no llega a su «finally», así que se deshace lo que deja
    $hecho = 0
    & reg.exe unload 'HKLM\NIT_CLON_SYS' 2>&1 | Out-Null; if ($LASTEXITCODE -eq 0) { $hecho++; Write-Output "  $($E.OK) Descargado el registro del destino (NIT_CLON_SYS)." }
    $svc = Get-Service ShellHWDetection -ErrorAction SilentlyContinue; if ($svc -and $svc.Status -ne 'Running') { Start-Service ShellHWDetection -ErrorAction SilentlyContinue; $hecho++; Write-Output "  $($E.OK) Servicio ShellHWDetection puesto en marcha otra vez." }
    foreach ($s in @(Get-RegistroSnap)) {   # solo las instantáneas anotadas al crearlas
        if ($s.Link -and $s.Link -notmatch '\.\.' -and (Split-Path -Parent $s.Link) -ieq $env:TEMP.TrimEnd('\') -and (Split-Path -Leaf $s.Link) -like 'nit_snap_*' -and (Test-Path -LiteralPath $s.Link)) { & cmd.exe /c rmdir "$($s.Link)" 2>&1 | Out-Null }
        Get-CimInstance Win32_ShadowCopy -ErrorAction SilentlyContinue | Where-Object { $_.ID -eq $s.Id } | Remove-CimInstance -ErrorAction SilentlyContinue
        Remove-RegistroSnap $s.Id
        $hecho++; Write-Output "  $($E.OK) Quitada la instantánea $($s.Id)."
    }
    foreach ($v in @(Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' })) {
        $carp = '{0}:\Nitrit0_Clon' -f $v.DriveLetter
        foreach ($w in @(Get-ChildItem -LiteralPath $carp -Filter 'windows_clon*.wim' -File -Force -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $w.FullName -Force -ErrorAction SilentlyContinue; $hecho++; Write-Output "  $($E.OK) Borrada la imagen temporal $($w.FullName)." }
    }
    if (-not $hecho) { Write-Output "$($E.Info) No quedaba nada por limpiar." } else { Write-Output "$($E.OK) Limpieza terminada ($hecho cosa(s))." }
    exit 0
}
if ($discoSis -lt 0 -or $discoKit -lt 0) { Write-Output "$($E.Error) No he podido identificar el disco de Windows en marcha o el del kit: por seguridad no se clona."; exit 1 }   # sin saberlo, las protecciones del destino no valdrían
if ($discos.Count -lt 2) { Write-Output "$($E.Error) Hace falta al menos otro disco conectado para clonar."; exit 1 }

# ---------------------------------------------------------------- Ventanas (solo si no se pasaron los discos por parámetro)
function Show-Seleccion {
    $f = New-Object Windows.Forms.Form; $f.Text = 'Clonar disco · Nitrit0'; $f.StartPosition = 'CenterScreen'; $f.Size = New-Object Drawing.Size(640, 330); $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false
    $l1 = New-Object Windows.Forms.Label; $l1.Text = 'Disco ORIGEN (se copia; no se modifica):'; $l1.Location = '12,12'; $l1.AutoSize = $true
    $c1 = New-Object Windows.Forms.ComboBox; $c1.DropDownStyle = 'DropDownList'; $c1.Location = '12,32'; $c1.Width = 600
    $l2 = New-Object Windows.Forms.Label; $l2.Text = 'Disco DESTINO (se BORRA ENTERO):'; $l2.Location = '12,66'; $l2.AutoSize = $true
    $c2 = New-Object Windows.Forms.ComboBox; $c2.DropDownStyle = 'DropDownList'; $c2.Location = '12,86'; $c2.Width = 600
    foreach ($d in $discos) { [void]$c1.Items.Add((Get-TextoDisco $d)); [void]$c2.Items.Add((Get-TextoDisco $d)) }
    $l3 = New-Object Windows.Forms.Label; $l3.Text = 'Carpeta para la imagen temporal (otro disco con sitio libre; vacío = elegir sola):'; $l3.Location = '12,120'; $l3.AutoSize = $true
    $t3 = New-Object Windows.Forms.TextBox; $t3.Location = '12,140'; $t3.Width = 520
    $b3 = New-Object Windows.Forms.Button; $b3.Text = 'Examinar…'; $b3.Location = '540,138'; $b3.Width = 72
    $b3.Add_Click({ $fb = New-Object Windows.Forms.FolderBrowserDialog; if ($fb.ShowDialog() -eq 'OK') { $t3.Text = $fb.SelectedPath } })
    $ck = New-Object Windows.Forms.CheckBox; $ck.Text = 'Solo simular (enseña el plan y no cambia nada)'; $ck.Checked = $true; $ck.Location = '12,180'; $ck.AutoSize = $true
    $nota = New-Object Windows.Forms.Label; $nota.Text = 'Con «Solo simular» desmarcado se pedirá una confirmación escrita antes de borrar el destino.'; $nota.Location = '12,205'; $nota.AutoSize = $true
    $ok = New-Object Windows.Forms.Button; $ok.Text = 'Continuar'; $ok.Location = '430,250'; $ok.Width = 90; $ok.DialogResult = 'OK'
    $ca = New-Object Windows.Forms.Button; $ca.Text = 'Cancelar'; $ca.Location = '525,250'; $ca.Width = 90; $ca.DialogResult = 'Cancel'
    $f.AcceptButton = $ok; $f.CancelButton = $ca; $f.Controls.AddRange(@($l1, $c1, $l2, $c2, $l3, $t3, $b3, $ck, $nota, $ok, $ca)); $f.TopMost = $true
    if ($f.ShowDialog() -ne 'OK' -or $c1.SelectedIndex -lt 0 -or $c2.SelectedIndex -lt 0) { return $null }
    [pscustomobject]@{ Origen = $discos[$c1.SelectedIndex].Number; Destino = $discos[$c2.SelectedIndex].Number; Carpeta = $t3.Text.Trim(); Simular = $ck.Checked }
}
function Read-Frase([string]$frase, [string]$detalle) {
    $f = New-Object Windows.Forms.Form; $f.Text = 'Confirmar borrado del disco destino'; $f.StartPosition = 'CenterScreen'; $f.Size = New-Object Drawing.Size(560, 330); $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.TopMost = $true
    $l = New-Object Windows.Forms.Label; $l.Text = $detalle; $l.Location = '12,10'; $l.Size = New-Object Drawing.Size(520, 180)
    $l2 = New-Object Windows.Forms.Label; $l2.Text = "Para continuar escribe exactamente:  $frase"; $l2.Location = '12,196'; $l2.AutoSize = $true; $l2.Font = New-Object Drawing.Font($l2.Font, [Drawing.FontStyle]::Bold)
    $t = New-Object Windows.Forms.TextBox; $t.Location = '12,222'; $t.Width = 520
    $ok = New-Object Windows.Forms.Button; $ok.Text = 'Borrar y clonar'; $ok.Location = '330,256'; $ok.Width = 110; $ok.DialogResult = 'OK'; $ok.Enabled = $false
    $ca = New-Object Windows.Forms.Button; $ca.Text = 'Cancelar'; $ca.Location = '445,256'; $ca.Width = 90; $ca.DialogResult = 'Cancel'
    $t.Add_TextChanged({ $ok.Enabled = ($t.Text -ceq $frase) })
    $f.CancelButton = $ca; $f.Controls.AddRange(@($l, $l2, $t, $ok, $ca))
    if ($f.ShowDialog() -eq 'OK') { return $t.Text }
    ''
}

$simular = -not $Ejecutar
if ($Origen -lt 0 -or $Destino -lt 0) {
    $s = Show-Seleccion
    if (-not $s) { Write-Output "$($E.Info) Cancelado: no se ha cambiado nada."; exit 2 }
    $Origen = $s.Origen; $Destino = $s.Destino; if ($s.Carpeta) { $CarpetaImagen = $s.Carpeta }; $simular = $s.Simular
}

# ---------------------------------------------------------------- Plan y bloqueos
function Get-Plan([int]$o, [int]$d, [string]$carpeta) {
    $bloq = New-Object Collections.Generic.List[string]; $avis = New-Object Collections.Generic.List[string]
    $plan = [pscustomobject]@{ Bloqueos = $bloq; Avisos = $avis; Items = @(); Usado = 0; Win = $null; Carpeta = $carpeta; Caliente = ($o -eq $discoSis); DiscoO = $null; DiscoD = $null }
    $dO = Get-Disk -Number $o -ErrorAction SilentlyContinue; $dD = Get-Disk -Number $d -ErrorAction SilentlyContinue
    if (-not $dO -or -not $dD) { $bloq.Add('Alguno de los discos elegidos ya no existe.'); return $plan }
    $plan.DiscoO = $dO; $plan.DiscoD = $dD
    # Salud del origen y del destino (solo aviso): clonar desde un disco que falla o hacia uno que se muere es perder horas. Los puentes USB suelen no dar SMART: entonces no se dice nada.
    foreach ($par in @(@('origen', $o), @('destino', $d))) {
        try {
            $pd = Get-PhysicalDisk -ErrorAction Stop | Where-Object { $_.DeviceId -eq [string]$par[1] } | Select-Object -First 1
            if (-not $pd) { continue }
            if ($pd.HealthStatus -and [string]$pd.HealthStatus -ne 'Healthy') { $avis.Add("El disco $($par[0]) indica salud «$($pd.HealthStatus)»: no es buena idea clonar con él.") }
            $rel = $pd | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
            if ($rel -and ($rel.ReadErrorsUncorrected -gt 0 -or $rel.Wear -ge 85)) { $avis.Add("SMART del disco $($par[0]): errores de lectura sin corregir = $($rel.ReadErrorsUncorrected), desgaste = $($rel.Wear) %.") }
        } catch { }
    }
    if ($o -eq $d) { $bloq.Add('El origen y el destino son el mismo disco.') }
    if ($d -eq $discoSis) { $bloq.Add('El destino es el disco del Windows en marcha: borrarlo destruiría este equipo.') }
    if ($d -eq $discoKit) { $bloq.Add('El destino es el disco donde está este kit.') }
    if ($d -ne $discoSis -and $d -ne $discoKit -and $protegidos -contains $d) { $bloq.Add('El destino contiene el sistema o el arranque de este equipo.') }
    # Identidad: si la app mandó el identificador único de lo que el técnico vio en pantalla, el disco con ese número debe ser el mismo (los números cambian si se conecta o quita un USB)
    if ($OrigenId -and [string]$dO.UniqueId -ne $OrigenId) { $bloq.Add('El disco origen ya no es el que se eligió (cambió su identificador). Vuelve a leer los discos y elige de nuevo.') }
    if ($DestinoId -and [string]$dD.UniqueId -ne $DestinoId) { $bloq.Add('El disco destino ya no es el que se eligió (cambió su identificador). Vuelve a leer los discos y elige de nuevo.') }
    if ($dD.IsOffline -or $dD.IsReadOnly) { $bloq.Add('El destino está sin conexión o es de solo lectura: ponlo en línea en Administración de discos.') }
    if ($dO.PartitionStyle -ne 'GPT') { $bloq.Add("El origen es $($dO.PartitionStyle): solo se clonan discos GPT con arranque UEFI.") }
    $partes = @(Get-Partition -DiskNumber $o -ErrorAction SilentlyContinue | Sort-Object Offset)
    if (@($partes | Where-Object { $LDM -contains ([string]$_.GptType).ToLower() }).Count) { $bloq.Add('El origen es un disco dinámico: no se admite.') }
    $win = Get-VolumenWindows $o; $plan.Win = $win
    if (-not $win) { $bloq.Add('No encuentro un Windows en el disco origen (necesita una partición con letra que tenga \Windows).') }
    if ($bloq.Count -and -not $win) { return $plan }
    $vw = Get-Volume -DriveLetter $win.DriveLetter -ErrorAction SilentlyContinue
    if (-not $vw -or $vw.Size -le 0) { $bloq.Add('No se pudo leer el tamaño del volumen de Windows del origen: sin eso no se puede comprobar que el destino sea suficiente.'); return $plan }
    $plan.Usado = [int64]($vw.Size - $vw.SizeRemaining)
    if (Test-Path -LiteralPath ('{0}:\hiberfil.sys' -f $win.DriveLetter) -ErrorAction SilentlyContinue) { $avis.Add('El origen tiene hibernación o arranque rápido (hiberfil.sys): apaga Windows del todo («shutdown /s /full») o ejecuta «powercfg /h off» antes de clonar; si no, el clon puede fallar en el primer arranque.') }
    if ($plan.Caliente) { $avis.Add('El origen es el Windows en marcha: se copia desde una instantánea (VSS). Cierra programas y no uses el equipo durante la copia.') }
    try {
        $bl = Get-BitLockerVolume -MountPoint ('{0}:' -f $win.DriveLetter) -ErrorAction Stop
        if ($bl.LockStatus -eq 'Locked') { $bloq.Add('El volumen de Windows está bloqueado por BitLocker: desbloquéalo primero.') }
        elseif ($bl.VolumeStatus -ne 'FullyDecrypted') { $avis.Add('BitLocker o el cifrado de dispositivo está activo en el origen: la copia se hace con los datos descifrados y el DESTINO QUEDARÁ SIN CIFRAR (se puede volver a activar). Guarda antes la clave de recuperación.') }
    } catch { }
    $items = New-Object Collections.Generic.List[object]; $fijo = [int64]0
    foreach ($p in $partes) {
        $g = ([string]$p.GptType).ToLower()
        if ($p.PartitionNumber -eq $win.PartitionNumber) { $items.Add([pscustomobject]@{ Tipo = 'Windows'; Size = [int64]0; Origen = $p; Etiqueta = (Get-Volume -DriveLetter $p.DriveLetter).FileSystemLabel }); continue }
        if ($g -eq $ESP) { $tam = [int64][math]::Max($p.Size, 260MB); $items.Add([pscustomobject]@{ Tipo = 'ESP'; Size = $tam; Origen = $p; Etiqueta = 'SYSTEM' }); $fijo += $tam }   # bcdboot copia todos los idiomas: una EFI de 100 MB se llena (mínimo 260 MB, lo que recomienda Microsoft)
        elseif ($g -eq $MSR) { if (@($items | Where-Object Tipo -eq 'MSR').Count) { continue }; $items.Add([pscustomobject]@{ Tipo = 'MSR'; Size = [int64]$p.Size; Origen = $p; Etiqueta = '' }); $fijo += $p.Size }
        elseif ($g -eq $REC) { $items.Add([pscustomobject]@{ Tipo = 'Recovery'; Size = [int64]$p.Size; Origen = $p; Etiqueta = 'Recovery' }); $fijo += $p.Size }
        elseif ($g -eq $BAS -and $p.DriveLetter) {
            $v = Get-Volume -DriveLetter $p.DriveLetter -ErrorAction SilentlyContinue
            if ($v -and $v.FileSystem -eq 'NTFS') { $items.Add([pscustomobject]@{ Tipo = 'Datos'; Size = [int64]$p.Size; Origen = $p; Etiqueta = $v.FileSystemLabel }); $fijo += $p.Size }
            else { $avis.Add("La partición $($p.DriveLetter): no es NTFS y NO se copia (se perderá su contenido en el clon).") }
        }
        elseif ($g -eq $BAS) { $avis.Add("La partición $($p.PartitionNumber) ($([math]::Round($p.Size / 1GB, 1)) GB) es de datos pero no tiene letra de unidad y NO se copia: asígnale una letra en Administración de discos y repite si hay que llevársela.") }
        else { $avis.Add("La partición $($p.PartitionNumber) ($([math]::Round($p.Size / 1MB)) MB, tipo $g) no se reconoce y NO se copia.") }
    }
    if (-not (@($items | Where-Object Tipo -eq 'ESP').Count)) { $bloq.Add('El origen no tiene partición de arranque EFI.') }
    $winSize = [int64]([math]::Floor(($dD.Size - 32MB - $fijo) / 1MB) * 1MB)   # 32 MB de margen: cabeceras GPT y alineación de cada partición
    # Si el destino es mayor, el espacio sobrante va a Windows (por defecto) o a la última partición de datos (-Extra Datos); Windows conserva al menos lo que tenía el origen y lo necesario (usado + 15 %)
    if ($Extra -eq 'Datos') {
        $ultimoDatos = @($items | Where-Object Tipo -eq 'Datos') | Select-Object -Last 1
        if (-not $ultimoDatos) { $avis.Add('No hay partición de datos en el origen: el espacio sobrante del destino va a Windows.') }
        else {
            $minWin = [int64]([math]::Ceiling([math]::Max([double]$win.Size, [double]($plan.Usado * 1.15)) / 1MB) * 1MB)
            if ($winSize -gt $minWin) { $ultimoDatos.Size = [int64]$ultimoDatos.Size + ($winSize - $minWin); $winSize = $minWin }
        }
    }
    foreach ($it in $items) { if ($it.Tipo -eq 'Windows') { $it.Size = $winSize } }
    $plan.Items = $items.ToArray()
    $necesario = [int64]($plan.Usado * 1.15)
    if ($winSize -lt $necesario) { $bloq.Add(("En el destino la partición de Windows quedaría de {0} GB y se necesitan al menos {1} GB (lo usado + 15 %). Elige un disco mayor o reduce antes las particiones de datos." -f [math]::Round($winSize / 1GB, 1), [math]::Round($necesario / 1GB, 1))) }
    # Sitio para la imagen temporal: nunca en el disco destino (se borra), ni en el origen (se está capturando), ni en el del kit; con margen y en un volumen que admita archivos grandes
    $minimo = [int64]($plan.Usado * 1.1)
    if ($carpeta) {
        try {
            $lc = (Get-Item -LiteralPath $carpeta -ErrorAction Stop).PSDrive.Name; $dc = (Get-Partition -DriveLetter $lc -ErrorAction Stop).DiskNumber; $vc = Get-Volume -DriveLetter $lc -ErrorAction Stop
            if ($dc -eq $d) { $bloq.Add('La carpeta de la imagen está en el disco destino, que se va a borrar.') }
            elseif ($dc -eq $o) { $bloq.Add('La carpeta de la imagen está en el disco origen: elige otro disco.') }
            elseif ($dc -eq $discoKit) { $bloq.Add('La carpeta de la imagen está en el disco del kit: elige otro disco.') }
            elseif ($vc.FileSystem -eq 'FAT32') { $bloq.Add('La carpeta de la imagen está en un volumen FAT32, que no admite archivos de más de 4 GB.') }
            elseif ($vc.SizeRemaining -lt $minimo) { $bloq.Add(("La carpeta de la imagen tiene {0} GB libres y hacen falta unos {1} GB." -f [math]::Round($vc.SizeRemaining / 1GB, 1), [math]::Round($minimo / 1GB, 1))) }
            else { $plan.Carpeta = $carpeta }
        } catch { $bloq.Add("La carpeta de la imagen no es válida: $carpeta") }
    }
    else {
        $mejor = $null
        foreach ($v in @(Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.FileSystem -ne 'FAT32' -and $_.SizeRemaining -gt $minimo } | Sort-Object SizeRemaining -Descending)) {
            try { $dv = (Get-Partition -DriveLetter $v.DriveLetter -ErrorAction Stop).DiskNumber } catch { continue }
            if ($dv -ne $d -and $dv -ne $o -and $dv -ne $discoKit) { $mejor = $v; break }
        }
        if ($mejor) { $plan.Carpeta = ('{0}:\Nitrit0_Clon' -f $mejor.DriveLetter) } else { $bloq.Add(("No hay otro disco con {0} GB libres para la imagen temporal. Conecta uno o indica la carpeta." -f [math]::Round($plan.Usado / 1GB, 1))) }
    }
    $plan
}

$plan = Get-Plan $Origen $Destino $CarpetaImagen
Write-Output ''
Write-Output "$($E.Disco) PLAN DE CLONADO"
if ($plan.DiscoO) { Write-Output ("  Origen : " + (Get-TextoDisco $plan.DiscoO)); Write-Output ("  Destino: " + (Get-TextoDisco $plan.DiscoD) + '  <- SE BORRARÁ ENTERO') }
foreach ($it in $plan.Items) { Write-Output ('    {0,-9} {1,8} GB  {2}' -f $it.Tipo, [math]::Round($it.Size / 1GB, 2), $(if ($it.Origen.DriveLetter) { "(origen $($it.Origen.DriveLetter):)" } else { '' })) }
if ($plan.Win) { Write-Output ("  Windows usa {0} GB; imagen temporal en: {1}" -f [math]::Round($plan.Usado / 1GB, 1), $plan.Carpeta) }
foreach ($a in $plan.Avisos) { Write-Output "  $($E.Aviso) $a" }
if ($plan.Bloqueos.Count) {
    foreach ($b in $plan.Bloqueos) { Write-Output "  $($E.Error) $b" }
    Write-Output "$($E.Error) No se puede clonar así. No se ha cambiado nada."; Write-Log "Clonar_Disco: bloqueado ($($plan.Bloqueos -join ' | '))" 'AVISO'; exit 1
}
if ($simular) {
    Write-Output "$($E.OK) SIMULACIÓN terminada: todo encaja y no se ha cambiado nada. Para clonar de verdad, vuelve a ejecutarlo y desmarca «Solo simular»."
    Write-Log "Clonar_Disco: simulación origen=$Origen destino=$Destino"; exit 0
}

# ---------------------------------------------------------------- Confirmación escrita y recomprobación del destino
$frase = "BORRAR DISCO $Destino"
if ($Confirmo -cne $frase) {
    $det = "Se va a BORRAR ENTERO este disco:`r`n`r`n  " + (Get-TextoDisco $plan.DiscoD) + "`r`n`r`nContenido actual:`r`n" + ((@(Get-Partition -DiskNumber $Destino -ErrorAction SilentlyContinue | ForEach-Object { '  · {0} MB {1}' -f [math]::Round($_.Size / 1MB), $(if ($_.DriveLetter) { "($($_.DriveLetter):)" } else { '' }) }) -join "`r`n"))
    if ((Read-Frase $frase $det) -cne $frase) { Write-Output "$($E.Info) Cancelado: no se ha cambiado nada."; Write-Log 'Clonar_Disco: cancelado en la confirmación'; exit 2 }
}
$dd = Get-Disk -Number $Destino -ErrorAction SilentlyContinue; $do = Get-Disk -Number $Origen -ErrorAction SilentlyContinue
if (-not $dd -or $dd.Size -ne $plan.DiscoD.Size -or $dd.FriendlyName -ne $plan.DiscoD.FriendlyName -or $dd.SerialNumber -ne $plan.DiscoD.SerialNumber -or $dd.UniqueId -ne $plan.DiscoD.UniqueId -or $protegidos -contains $dd.Number) {
    Write-Output "$($E.Error) El disco destino ya no es el mismo que se eligió (cambió el número, tamaño, serie o identificador). No se ha tocado nada."; Write-Log 'Clonar_Disco: el destino cambió antes de borrar' 'ERROR'; exit 1
}
if (-not $do -or $do.Size -ne $plan.DiscoO.Size -or $do.UniqueId -ne $plan.DiscoO.UniqueId) {
    Write-Output "$($E.Error) El disco origen ya no es el mismo que se eligió. No se ha tocado nada."; Write-Log 'Clonar_Disco: el origen cambió antes de borrar' 'ERROR'; exit 1
}

# ---------------------------------------------------------------- Ejecución
function Format-Particion($p, [string]$fs, [string]$etiqueta) {   # Format-Volume rechaza una etiqueta vacía (C: suele no tener)
    if ($etiqueta) { [void](Format-Volume -Partition $p -FileSystem $fs -NewFileSystemLabel $etiqueta -Confirm:$false) } else { [void](Format-Volume -Partition $p -FileSystem $fs -Confirm:$false) }
}
function Add-Letra([int]$disco, [int]$num) {
    $p = Get-Partition -DiskNumber $disco -PartitionNumber $num
    if (-not $p.DriveLetter) { Add-PartitionAccessPath -DiskNumber $disco -PartitionNumber $num -AssignDriveLetter; $p = Get-Partition -DiskNumber $disco -PartitionNumber $num }
    [string]$p.DriveLetter
}
function New-Instantanea([string]$letra) {
    $r = ([wmiclass]'Win32_ShadowCopy').Create(('{0}:\' -f $letra), 'ClientAccessible')
    if ($r.ReturnValue -ne 0) { throw "No se pudo crear la instantánea de ${letra}: (código $($r.ReturnValue))" }
    $sc = Get-CimInstance Win32_ShadowCopy | Where-Object { $_.ID -eq $r.ShadowID }
    $link = Join-Path $env:TEMP ('nit_snap_{0}_{1}' -f $letra, [guid]::NewGuid().ToString('N').Substring(0, 6))
    & cmd.exe /c mklink /d "$link" ($sc.DeviceObject + '\') | Out-Null
    if (-not (Test-Path -LiteralPath "$link\")) { $sc | Remove-CimInstance -ErrorAction SilentlyContinue; throw "No se pudo abrir la instantánea de ${letra}:" }
    Add-RegistroSnap $r.ShadowID $link
    [pscustomobject]@{ Id = $r.ShadowID; Link = $link }
}
function Remove-Instantanea($s) { if ($s) { try { & cmd.exe /c rmdir "$($s.Link)" | Out-Null } catch { }; try { Get-CimInstance Win32_ShadowCopy | Where-Object { $_.ID -eq $s.Id } | Remove-CimInstance -ErrorAction SilentlyContinue } catch { }; Remove-RegistroSnap $s.Id } }
function Copy-Datos([string]$desde, [string]$hasta, [string]$etq) {
    $r = Invoke-Proceso 'robocopy.exe' ('"{0}" "{1}" /MIR /COPYALL /DCOPY:DAT /B /XJ /R:1 /W:1 /NFL /NDL /NP /XD "System Volume Information" "$RECYCLE.BIN"' -f $desde.TrimEnd('\'), $hasta.TrimEnd('\')) 21600 $etq 30
    if ($r.Codigo -ge 8 -or $r.Codigo -lt 0) { throw "La copia de $etq falló (robocopy código $($r.Codigo))" }
    if (($r.Codigo -band 4) -eq 4) { Write-Output "  $($E.Aviso) $etq : robocopy avisa de discrepancias (código $($r.Codigo)): puede haber archivos que no coinciden. Revisa el registro." }
}

$snaps = New-Object Collections.Generic.List[object]; $wim = $null; $letrasTemp = New-Object Collections.Generic.List[object]
$errorFinal = $null; $detenido = $false; $destinoTocado = $false
try {
    Write-Log "Clonar_Disco: EJECUCIÓN origen=$Origen destino=$Destino imagen=$($plan.Carpeta)"
    $svc = Get-Service ShellHWDetection -ErrorAction SilentlyContinue; if ($svc -and $svc.Status -eq 'Running') { Stop-Service ShellHWDetection -Force -ErrorAction SilentlyContinue; $detenido = $true }
    # Primero se captura Windows a la imagen temporal: el destino no se toca hasta que la imagen existe (si VSS, DISM o el espacio fallan, no se ha borrado nada)
    $wim = Join-Path $plan.Carpeta ('windows_clon_{0}.wim' -f [guid]::NewGuid().ToString('N').Substring(0, 8)); New-Item -ItemType Directory -Force -Path $plan.Carpeta | Out-Null
    $raizWin = '{0}:\' -f $plan.Win.DriveLetter
    if ($plan.Caliente) { Write-Output "$($E.Refresh) 1/6 Creando la instantánea (VSS) de Windows…"; $sn = New-Instantanea ([string]$plan.Win.DriveLetter); $snaps.Add($sn); $raizWin = "$($sn.Link)\" } else { Write-Output "$($E.Info) 1/6 El origen no está en marcha: se copia directamente." }
    Write-Output "$($E.Disco) 2/6 Capturando Windows con DISM (tarda; verás el avance)…"
    $c = Invoke-Proceso 'dism.exe' ('/Capture-Image /ImageFile:"{0}" /CaptureDir:"{1}" /Name:Windows /Compress:fast /CheckIntegrity' -f $wim, $raizWin.TrimEnd('\')) 21600 'Captura de Windows' 30
    if ($c.Codigo -ne 0 -or -not (Test-Path -LiteralPath $wim)) { throw "DISM no pudo capturar Windows (código $($c.Codigo)). El disco destino NO se ha tocado. $($c.Salida -split "`n" | Select-Object -Last 3)" }
    Write-Output "  $($E.OK) Imagen de Windows capturada. El disco destino aún no se ha tocado."
    # La captura puede haber durado horas: se vuelve a comprobar la identidad del destino justo antes de borrarlo
    $dd2 = Get-Disk -Number $Destino -ErrorAction SilentlyContinue
    if (-not $dd2 -or $dd2.UniqueId -ne $plan.DiscoD.UniqueId -or $dd2.Size -ne $plan.DiscoD.Size -or $protegidos -contains $dd2.Number) { throw 'El disco destino ya no es el que se eligió (cambió durante la captura). No se ha borrado nada.' }
    Write-Output "$($E.Cohete) 3/6 Preparando el disco destino (tabla GPT nueva)…"; $destinoTocado = $true
    if ((Get-Disk -Number $Destino).PartitionStyle -ne 'RAW') { Clear-Disk -Number $Destino -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop }   # un disco virgen (RAW) no admite Clear-Disk
    if ((Get-Disk -Number $Destino).PartitionStyle -eq 'RAW') { Initialize-Disk -Number $Destino -PartitionStyle GPT -ErrorAction Stop }
    # Windows crea solo una MSR al inicializar un disco GPT: se quita para que la tabla sea exactamente la del plan
    Get-Partition -DiskNumber $Destino -ErrorAction SilentlyContinue | Remove-Partition -Confirm:$false -ErrorAction SilentlyContinue
    $mapa = @{}; $datos = New-Object Collections.Generic.List[object]; $recups = New-Object Collections.Generic.List[object]
    foreach ($it in $plan.Items) {
        # Si no cabe, se para: recortar en silencio una partición dejaría el plan impreso distinto del disco real (solo Windows admite un recorte mínimo por alineación)
        $libre = [int64](Get-Disk -Number $Destino).LargestFreeExtent
        if ($libre -ge [int64]$it.Size) { $tam = [int64]$it.Size } elseif ($it.Tipo -eq 'Windows' -and ([int64]$it.Size - $libre) -le 64MB) { $tam = $libre } else { throw "No cabe la partición $($it.Tipo) en el destino (necesita $([math]::Round($it.Size / 1MB)) MB y quedan $([math]::Round($libre / 1MB)) MB libres)." }
        switch ($it.Tipo) {
            'ESP' { $p = New-Partition -DiskNumber $Destino -Size $tam -GptType $ESP -AssignDriveLetter; Format-Particion $p 'FAT32' 'SYSTEM' ; $mapa.ESP = Add-Letra $Destino $p.PartitionNumber; $letrasTemp.Add(@($Destino, $p.PartitionNumber)) }
            'MSR' { [void](New-Partition -DiskNumber $Destino -Size $tam -GptType $MSR) }
            'Windows' { $p = New-Partition -DiskNumber $Destino -Size $tam -GptType $BAS -AssignDriveLetter; Format-Particion $p 'NTFS' $it.Etiqueta; $mapa.Windows = Add-Letra $Destino $p.PartitionNumber; $letrasTemp.Add(@($Destino, $p.PartitionNumber)) }
            'Recovery' {
                $p = New-Partition -DiskNumber $Destino -Size $tam -GptType $REC -AssignDriveLetter; Format-Particion $p 'NTFS' 'Recovery' 
                $recups.Add(@{ Num = $p.PartitionNumber; Letra = (Add-Letra $Destino $p.PartitionNumber); Origen = $it.Origen }); $letrasTemp.Add(@($Destino, $p.PartitionNumber))
                $ds = Join-Path $env:TEMP 'nit_dp_rec.txt'; Set-Content -LiteralPath $ds -Value ("select disk $Destino", "select partition $($p.PartitionNumber)", 'gpt attributes=0x8000000000000001') -Encoding ASCII
                $dpr = Invoke-Proceso 'diskpart.exe' "/s `"$ds`"" 120 'Atributos de recuperación'; Remove-Item -LiteralPath $ds -Force -ErrorAction SilentlyContinue
                if ($dpr.Codigo -ne 0) { Write-Output "  $($E.Aviso) No se pudieron marcar los atributos de recuperación (diskpart código $($dpr.Codigo)): comprueba «reagentc /info» tras arrancar." }
            }
            'Datos' { $p = New-Partition -DiskNumber $Destino -Size $tam -GptType $BAS -AssignDriveLetter; Format-Particion $p 'NTFS' $it.Etiqueta; $datos.Add(@{ Letra = (Add-Letra $Destino $p.PartitionNumber); Origen = $it.Origen }); $letrasTemp.Add(@($Destino, $p.PartitionNumber)) }
        }
    }
    Write-Output "  $($E.OK) Particiones creadas y formateadas."

    Write-Output "$($E.Disco) 4/6 Aplicando la imagen en el destino…"
    $a = Invoke-Proceso 'dism.exe' ('/Apply-Image /ImageFile:"{0}" /Index:1 /ApplyDir:{1}:\ /Verify' -f $wim, $mapa.Windows) 21600 'Aplicar Windows' 30
    if ($a.Codigo -ne 0) { throw "DISM no pudo aplicar la imagen (código $($a.Codigo)). $($a.Salida -split "`n" | Select-Object -Last 3)" }
    Remove-Item -LiteralPath $wim -Force -ErrorAction SilentlyContinue; $wim = $null
    # El Windows copiado trae las letras de unidad del disco viejo (MountedDevices): se quita la de C: para que el nuevo se asigne la suya al arrancar
    $hive = '{0}:\Windows\System32\config\SYSTEM' -f $mapa.Windows
    & reg.exe unload 'HKLM\NIT_CLON_SYS' 2>&1 | Out-Null   # por si una ejecución anterior cortada lo dejó cargado (si no lo está, no hace nada)
    & reg.exe load 'HKLM\NIT_CLON_SYS' $hive 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        # Se quitan TODAS las letras (\DosDevices\X:), no solo C:: las del disco viejo (D:, E:…) apuntarían a sus volúmenes. Windows reasigna las suyas al arrancar.
        try { $kmd = Get-Item -LiteralPath 'HKLM:\NIT_CLON_SYS\MountedDevices' -ErrorAction Stop; foreach ($vn in @($kmd.GetValueNames())) { if ($vn -match '^\\DosDevices\\[A-Za-z]:$') { Remove-ItemProperty -LiteralPath $kmd.PSPath -Name $vn -ErrorAction SilentlyContinue } }; $kmd.Close() } catch { Write-Output "  $($E.Aviso) No se pudieron limpiar las letras antiguas del registro del destino: $($_.Exception.Message)" }
        [gc]::Collect(); Start-Sleep -Milliseconds 500
        $descargado = $false; for ($i = 0; $i -lt 6 -and -not $descargado; $i++) { & reg.exe unload 'HKLM\NIT_CLON_SYS' 2>&1 | Out-Null; $descargado = ($LASTEXITCODE -eq 0); if (-not $descargado) { Start-Sleep 1 } }
        if (-not $descargado) { Write-Output "  $($E.Aviso) No se pudo descargar el registro del destino (HKLM\NIT_CLON_SYS): se descargará al reiniciar." }
    } else { Write-Output "  $($E.Aviso) No se pudo abrir el registro del destino para limpiar las letras de unidad antiguas." }

    if ($datos.Count -or $recups.Count) { Write-Output "$($E.Disco) 5/6 Copiando particiones de datos y de recuperación…" } else { Write-Output "$($E.Info) 5/6 No hay más particiones que copiar." }
    foreach ($dt in $datos) {
        $desde = '{0}:\' -f $dt.Origen.DriveLetter
        if ($plan.Caliente) { $s2 = New-Instantanea ([string]$dt.Origen.DriveLetter); $snaps.Add($s2); $desde = "$($s2.Link)\" }
        Copy-Datos $desde ('{0}:\' -f $dt.Letra) "Datos $($dt.Origen.DriveLetter):"
    }
    foreach ($recup in $recups) {   # puede haber más de una (la del fabricante y la de Windows)
        try {
            $teniaLetra = [bool]$recup.Origen.DriveLetter
            $lr = Add-Letra $Origen $recup.Origen.PartitionNumber; if (-not $teniaLetra) { $letrasTemp.Add(@($Origen, $recup.Origen.PartitionNumber)) }   # solo se quita al final la letra que se puso aquí
            Copy-Datos ('{0}:\' -f $lr) ('{0}:\' -f $recup.Letra) "Recuperación $($recup.Origen.PartitionNumber)"
        } catch { Write-Output "  $($E.Aviso) No se pudo copiar la partición de recuperación $($recup.Origen.PartitionNumber): $($_.Exception.Message)" }
    }

    Write-Output "$($E.Cohete) 6/6 Dejando el arranque listo (bcdboot)…"
    $bcdRuta = '{0}:\EFI\Microsoft\Boot\BCD' -f $mapa.ESP
    $b = Invoke-Proceso 'bcdboot.exe' ('{0}:\Windows /s {1}: /f UEFI' -f $mapa.Windows, $mapa.ESP) 300 'bcdboot' 10 -MostrarSalida
    $bcdBueno = { & bcdedit.exe /store $bcdRuta /enum 2>&1 | Out-Null; $LASTEXITCODE -eq 0 }
    if ($b.Codigo -ne 0 -or -not (& $bcdBueno)) {
        Write-Output "  $($E.Aviso) bcdboot no dejó un almacén de arranque válido (código $($b.Codigo)). Reintento…"
        Remove-Item -LiteralPath $bcdRuta, "$bcdRuta.LOG", "$bcdRuta.LOG1", "$bcdRuta.LOG2" -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2
        $b = Invoke-Proceso 'bcdboot.exe' ('{0}:\Windows /s {1}: /f UEFI' -f $mapa.Windows, $mapa.ESP) 300 'bcdboot (reintento)' 10 -MostrarSalida
    }
    if ($b.Codigo -ne 0 -or -not (& $bcdBueno)) {
        # Plan B: el almacén se construye en la carpeta temporal (NTFS) con bcdedit y se copia a la EFI. Los archivos de arranque ya los dejó bcdboot.
        Write-Output "  $($E.Aviso) Método alternativo: creo el almacén de arranque con bcdedit."
        $tmpBcd = Join-Path $env:TEMP ('nit_bcd_' + [guid]::NewGuid().ToString('N')); $dw = '{0}:' -f $mapa.Windows; $de = '{0}:' -f $mapa.ESP
        & bcdedit.exe /createstore $tmpBcd | Out-Null
        & bcdedit.exe /store $tmpBcd /create '{bootmgr}' /d 'Windows Boot Manager' | Out-Null
        & bcdedit.exe /store $tmpBcd /set '{bootmgr}' device "partition=$de" | Out-Null
        & bcdedit.exe /store $tmpBcd /set '{bootmgr}' path '\EFI\Microsoft\Boot\bootmgfw.efi' | Out-Null
        $salidaOs = (& bcdedit.exe /store $tmpBcd /create /d 'Windows' /application osloader) | Out-String
        if ($salidaOs -notmatch '(\{[0-9a-fA-F\-]{36}\})') { Remove-Item -LiteralPath $tmpBcd -Force -ErrorAction SilentlyContinue; throw "bcdboot no pudo crear el arranque (código $($b.Codigo)) y bcdedit tampoco." }
        $idOs = $Matches[1]
        & bcdedit.exe /store $tmpBcd /set $idOs device "partition=$dw" | Out-Null
        & bcdedit.exe /store $tmpBcd /set $idOs osdevice "partition=$dw" | Out-Null
        & bcdedit.exe /store $tmpBcd /set $idOs path '\Windows\system32\winload.efi' | Out-Null
        & bcdedit.exe /store $tmpBcd /set $idOs systemroot '\Windows' | Out-Null
        & bcdedit.exe /store $tmpBcd /set $idOs nx OptIn | Out-Null
        & bcdedit.exe /store $tmpBcd /set $idOs locale (Get-Culture).Name | Out-Null
        & bcdedit.exe /store $tmpBcd /set '{bootmgr}' locale (Get-Culture).Name | Out-Null
        & bcdedit.exe /store $tmpBcd /displayorder $idOs /addlast | Out-Null
        & bcdedit.exe /store $tmpBcd /default $idOs | Out-Null
        & bcdedit.exe /store $tmpBcd /set '{bootmgr}' timeout 3 | Out-Null
        New-Item -ItemType Directory -Force -Path (Split-Path $bcdRuta) | Out-Null
        Copy-Item -LiteralPath $tmpBcd -Destination $bcdRuta -Force; Remove-Item -LiteralPath $tmpBcd, "$tmpBcd.LOG", "$tmpBcd.LOG1", "$tmpBcd.LOG2" -Force -ErrorAction SilentlyContinue
        Write-Output "  $($E.Aviso) El almacén de arranque se creó a mano: comprueba que el equipo arranca con el disco nuevo."
    }

    # Verificación
    $fallos = @()
    if (-not (Test-Path -LiteralPath ('{0}:\Windows\System32\ntoskrnl.exe' -f $mapa.Windows))) { $fallos += 'falta ntoskrnl.exe en el destino' }
    if (-not (Test-Path -LiteralPath ('{0}:\Windows\System32\winload.efi' -f $mapa.Windows))) { $fallos += 'falta winload.efi en el destino' }
    if (-not (Test-Path -LiteralPath ('{0}:\Windows\System32\config\SOFTWARE' -f $mapa.Windows))) { $fallos += 'falta la colmena SOFTWARE del registro en el destino' }
    if (-not (Test-Path -LiteralPath ('{0}:\EFI\Microsoft\Boot\bootmgfw.efi' -f $mapa.ESP))) { $fallos += 'falta bootmgfw.efi en la partición EFI' }
    $bcd = & bcdedit.exe /store ('{0}:\EFI\Microsoft\Boot\BCD' -f $mapa.ESP) /enum 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $bcd -notmatch '(?i)winload') { $fallos += ('el almacén de arranque (BCD) no apunta a Windows: ' + (($bcd -split "`n" | Select-Object -First 4) -join ' ')) }
    if ($fallos.Count) { throw ('Verificación fallida: ' + ($fallos -join '; ')) }
    Write-Output ''
    Write-Output "$($E.OK) CLONADO TERMINADO (archivos del sistema y arranque presentes; el contenido de las particiones de datos no se compara archivo a archivo)."
    Write-Output "$($E.Info) Antes de arrancar con el disco nuevo: apaga, desconecta el disco ANTIGUO (o elige el nuevo en el menú de arranque de la BIOS)."
    Write-Output "$($E.Info) Si el origen tenía BitLocker, el destino está sin cifrar: vuelve a activarlo. Si «reagentc /info» dice Deshabilitado, ejecuta «reagentc /enable»."
    Write-Output "$($E.Aviso) La prueba definitiva es arrancar el equipo con el disco clonado: este script no puede hacerlo por ti."
    Write-Log "Clonar_Disco: terminado y verificado origen=$Origen destino=$Destino"
}
catch { $errorFinal = $_.Exception.Message; Write-Output "$($E.Error) El clonado falló: $errorFinal"; Write-Output "$($E.Info) El disco ORIGEN no se ha modificado. $(if ($destinoTocado) { 'El destino puede haber quedado a medias: repite el clonado.' } else { 'El destino NO se ha tocado.' })"; Write-Log "Clonar_Disco: error $errorFinal" 'ERROR' }
finally {
    & reg.exe unload 'HKLM\NIT_CLON_SYS' 2>&1 | Out-Null   # por si el registro del destino se quedó cargado (si no lo está, no hace nada)
    foreach ($s in $snaps) { Remove-Instantanea $s }
    if ($wim) { Remove-Item -LiteralPath $wim -Force -ErrorAction SilentlyContinue }
    foreach ($lt in $letrasTemp) { try { $pp = Get-Partition -DiskNumber $lt[0] -PartitionNumber $lt[1] -ErrorAction Stop; if ($pp.DriveLetter) { Remove-PartitionAccessPath -DiskNumber $lt[0] -PartitionNumber $lt[1] -AccessPath ('{0}:\' -f $pp.DriveLetter) -ErrorAction SilentlyContinue } } catch { } }
    if ($detenido) { Start-Service ShellHWDetection -ErrorAction SilentlyContinue }
}
if ($errorFinal) { exit 1 }
