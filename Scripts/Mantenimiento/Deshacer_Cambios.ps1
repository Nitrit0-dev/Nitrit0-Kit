# =====================================================================
#  Deshacer_Cambios.ps1 - Devuelve el sistema a como estaba antes de un script de Nitrit0
#  Lee Datos\Respaldo\Cambios\<sesión>\cambios.json (lo escriben los scripts que cambian ajustes) y revierte,
#  en orden inverso: valores de registro, servicios, DNS, arranque (BCD), archivo de paginación y nombre del equipo.
#  Si algún paso falla, la sesión NO se da por deshecha: queda solo con lo que falta (copia del original en cambios.json.bak-*) y se puede reintentar.
#  Un tipo de cambio que esta versión no conoce cuenta como fallo (no se da por bueno en silencio).
#  Parámetros: -Auto (la sesión más reciente) -Id <sesión>
# =====================================================================
[CmdletBinding()]
param([switch]$Auto, [string]$Id, [Alias('Simular')][switch]$SoloAnalizar)
if ($env:NIT_AUTO) { $Auto = $true }   # desde la app no hay ventana para elegir: se deshace la sesión más reciente
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$bases = @((Join-Path (Get-KitDatos) 'Respaldo\Cambios'), (Join-Path $Global:NitKit.Cache 'Cambios'))
$ses = @(); foreach ($b in $bases) { if (Test-Path -LiteralPath $b) { $ses += @(Get-ChildItem -LiteralPath $b -Directory | Where-Object { $_.Name -notlike '*_DESHECHO' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'cambios.json')) }) } }
$ses = @($ses | Sort-Object Name -Descending)
Write-Output "========================================================"
Write-Output "  $($E.Refresh) DESHACER CAMBIOS"
Write-Output "========================================================"
if (-not $ses) { Write-Output "  $($E.Info) No hay cambios registrados que deshacer."; return }
if ($SoloAnalizar) {
    Write-Output "  $($E.Lupa) Sesiones que se podrían deshacer (de la más reciente a la más antigua):"
    foreach ($s in $ses) { Write-Output "    · $($s.Name)" }
    Exit-Kit 'Ok' 'Modo análisis: solo se han listado; no se ha deshecho nada.'
}

$sel = $null
if ($Id) { $sel = $ses | Where-Object { $_.Name -eq $Id } | Select-Object -First 1 }
elseif ($Auto) { $sel = $ses[0] }
else {
    $oscuro = $true; try { $aj = Join-Path (Get-KitDatos) 'Ajustes.json'; if (Test-Path -LiteralPath $aj) { $oscuro = ((Get-Content -LiteralPath $aj -Raw -Encoding UTF8 | ConvertFrom-Json).Tema -ne 'claro') } } catch { }
    $cF = if ($oscuro) { '#12151C' } else { '#F3F5F9' }; $cP = if ($oscuro) { '#1E2330' } else { '#FFFFFF' }; $cT = if ($oscuro) { '#F0F3FA' } else { '#1B2230' }; $cA = if ($oscuro) { '#2BC4D8' } else { '#087F91' }; $cAT = if ($oscuro) { '#06222A' } else { '#FFFFFF' }
    $c = { param($h) [Drawing.ColorTranslator]::FromHtml($h) }
    $f = New-Object Windows.Forms.Form; $f.Text = 'Deshacer cambios'; $f.Size = New-Object Drawing.Size(760, 460); $f.StartPosition = 'CenterScreen'; $f.BackColor = & $c $cF; $f.TopMost = $true; $f.Font = New-Object Drawing.Font('Segoe UI', 10)
    $l = New-Object Windows.Forms.Label; $l.Text = 'Elige qué cambios deshacer (se revierte todo lo que hizo ese script):'; $l.ForeColor = & $c $cT; $l.AutoSize = $true; $l.Location = New-Object Drawing.Point(20, 16)
    $lb = New-Object Windows.Forms.ListBox; $lb.Location = New-Object Drawing.Point(20, 48); $lb.Size = New-Object Drawing.Size(704, 300); $lb.BackColor = & $c $cP; $lb.ForeColor = & $c $cT; $lb.BorderStyle = 'None'; $lb.Font = New-Object Drawing.Font('Segoe UI', 10.5)
    $items = @(); foreach ($s in $ses) { try { $j = Get-Content -LiteralPath (Join-Path $s.FullName 'cambios.json') -Raw -Encoding UTF8 | ConvertFrom-Json; $items += ("{0}   ·   {1}   ·   {2} cambio(s)   ·   {3}" -f ([datetime]$j.Fecha).ToString('dd/MM/yyyy HH:mm'), $j.Nombre, @($j.Cambios).Count, $j.Equipo) } catch { $items += "$($s.Name)   ·   (no se puede leer: no se toca)" } }
    foreach ($i in $items) { [void]$lb.Items.Add($i) }; $lb.SelectedIndex = 0
    $ok = New-Object Windows.Forms.Button; $ok.Text = 'Deshacer lo seleccionado'; $ok.Size = New-Object Drawing.Size(220, 38); $ok.Location = New-Object Drawing.Point(504, 366); $ok.FlatStyle = 'Flat'; $ok.BackColor = & $c $cA; $ok.ForeColor = & $c $cAT; $ok.DialogResult = 'OK'
    $f.Controls.AddRange(@($l, $lb, $ok)); $f.AcceptButton = $ok
    if ($f.ShowDialog() -ne 'OK' -or $lb.SelectedIndex -lt 0) { Exit-Kit 'Cancelado' 'Cancelado: no se ha deshecho nada.' }
    $sel = $ses[$lb.SelectedIndex]
}
if (-not $sel) { Write-Output "  $($E.Error) No se encontró esa sesión."; exit 1 }
$ficheroCambios = Join-Path $sel.FullName 'cambios.json'
try { $j = Get-Content -LiteralPath $ficheroCambios -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
catch { Write-Output "  $($E.Error) No se puede leer $ficheroCambios ($($_.Exception.Message)). No se ha tocado nada: el fichero sigue donde estaba."; exit 1 }
if (-not $j -or $null -eq $j.PSObject.Properties['Cambios'] -or -not $j.Nombre) { Write-Output "  $($E.Error) El registro de cambios de esta sesión está incompleto o dañado ($ficheroCambios). No se ha tocado nada."; exit 1 }
$cambios = @($j.Cambios); [array]::Reverse($cambios)
Write-Output "  Sesión: $($j.Nombre) ($($j.Fecha)) · $($cambios.Count) cambio(s) a deshacer"
[void](New-PuntoRestauracionSeguro "Nitrit0 - antes de deshacer $($j.Nombre)")
$ok = 0; $fallos = 0; $reinicio = $false; $fallidos = New-Object Collections.Generic.List[object]
function Convertir-Valor($v, [string]$tipo) {
    switch ($tipo) { 'DWord' { [int]$v } 'QWord' { [long]$v } 'Binary' { [byte[]]@($v) } 'MultiString' { [string[]]@($v) } default { [string]$v } }
}
foreach ($c in $cambios) {
    try {
        switch ($c.Tipo) {
            'Registro' {
                $nombre = if ($c.Nombre -eq '(default)') { '' } else { $c.Nombre }
                if ($c.ValorExistia) { New-Item -Path $c.Ruta -Force -ErrorAction SilentlyContinue | Out-Null; Set-ItemProperty -LiteralPath $c.Ruta -Name $c.Nombre -Value (Convertir-Valor $c.Previo $c.TipoPrevio) -Type $(if ($c.TipoPrevio -eq 'ExpandString') { 'ExpandString' } else { $c.TipoPrevio }) -Force -ErrorAction Stop }
                else {
                    if (Test-Path -LiteralPath $c.Ruta) { if ($nombre -eq '') { Set-ItemProperty -LiteralPath $c.Ruta -Name '(default)' -Value '' -ErrorAction SilentlyContinue } else { Remove-ItemProperty -LiteralPath $c.Ruta -Name $c.Nombre -ErrorAction Stop } }
                    if (-not $c.ClaveExistia -and (Test-Path -LiteralPath $c.Ruta)) { $it = Get-Item -LiteralPath $c.Ruta; if (-not $it.SubKeyCount -and -not ($it.GetValueNames() | Where-Object { $_ })) { Remove-Item -LiteralPath $c.Ruta -Force -ErrorAction SilentlyContinue } }
                    if ($c.PadreExistia -eq $false) { $pd = Split-Path $c.Ruta -Parent; if (Test-Path -LiteralPath $pd) { $ip = Get-Item -LiteralPath $pd; if (-not $ip.SubKeyCount -and -not ($ip.GetValueNames() | Where-Object { $_ })) { Remove-Item -LiteralPath $pd -Force -ErrorAction SilentlyContinue } } }
                }
                Write-Output "    $($E.OK) Registro: $($c.Ruta)\$($c.Nombre)"
            }
            'Servicio' {
                $mapa = @{ Auto = 'Automatic'; Manual = 'Manual'; Disabled = 'Disabled'; Boot = 'Automatic'; System = 'Automatic' }
                Set-Service -Name $c.Servicio -StartupType $mapa[[string]$c.InicioPrevio] -ErrorAction Stop
                if ($c.EstadoPrevio -eq 'Running') { Start-Service -Name $c.Servicio -ErrorAction SilentlyContinue }
                Write-Output "    $($E.OK) Servicio $($c.Servicio): inicio $($c.InicioPrevio)$(if ($c.EstadoPrevio -eq 'Running') { ', en ejecución' })"
            }
            'Dns' {
                if ($c.Automatico) { Set-DnsClientServerAddress -InterfaceIndex $c.Interfaz -ResetServerAddresses -ErrorAction Stop } else { Set-DnsClientServerAddress -InterfaceIndex $c.Interfaz -ServerAddresses @($c.Previo) -ErrorAction Stop }
                Write-Output "    $($E.OK) DNS del adaptador $($c.Interfaz): $(if ($c.Automatico) { 'automático (DHCP)' } else { @($c.Previo) -join ', ' })"
            }
            'Ip' {
                $i = [int]$c.Interfaz
                Get-NetIPAddress -InterfaceIndex $i -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '169.254.*' } | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
                Remove-NetRoute -InterfaceIndex $i -DestinationPrefix '0.0.0.0/0' -Confirm:$false -ErrorAction SilentlyContinue
                if ($c.Dhcp -or -not $c.Ip) { Set-NetIPInterface -InterfaceIndex $i -AddressFamily IPv4 -Dhcp Enabled -ErrorAction Stop }
                else {
                    Set-NetIPInterface -InterfaceIndex $i -AddressFamily IPv4 -Dhcp Disabled -ErrorAction Stop
                    $p = @{ InterfaceIndex = $i; IPAddress = [string]$c.Ip; PrefixLength = [int]$c.Prefijo; ErrorAction = 'Stop' }; if ($c.Puerta) { $p.DefaultGateway = [string]$c.Puerta }
                    [void](New-NetIPAddress @p)
                }
                Write-Output "    $($E.OK) IP del adaptador ${i}: $(if ($c.Dhcp -or -not $c.Ip) { 'automática (DHCP)' } else { "$($c.Ip)/$($c.Prefijo)" })"
            }
            'Bcd' { & bcdedit.exe /import $c.Archivo 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw "bcdedit /import código $LASTEXITCODE" }; $reinicio = $true; Write-Output "    $($E.OK) Configuración de arranque restaurada (hace falta reiniciar)." }
            'PageFile' {
                $cs = Get-CimInstance Win32_ComputerSystem
                if ($c.Automatico) { $cs.AutomaticManagedPagefile = $true; Set-CimInstance -InputObject $cs | Out-Null }
                else { foreach ($p in @($c.Configuracion)) { $s = Get-CimInstance Win32_PageFileSetting | Where-Object { $_.Name -eq $p.Nombre }; if ($s) { $s.InitialSize = [int]$p.Inicial; $s.MaximumSize = [int]$p.Maximo; Set-CimInstance -InputObject $s | Out-Null } else { New-CimInstance -ClassName Win32_PageFileSetting -Property @{ Name = $p.Nombre; InitialSize = [int]$p.Inicial; MaximumSize = [int]$p.Maximo } | Out-Null } } }
                $reinicio = $true; Write-Output "    $($E.OK) Archivo de paginación restaurado$(if ($c.Automatico) { ' (administración automática)' }) (hace falta reiniciar)."
            }
            'NombrePC' { Rename-Computer -NewName $c.Previo -Force -ErrorAction Stop; $reinicio = $true; Write-Output "    $($E.OK) Nombre del equipo: $($c.Previo) (hace falta reiniciar)." }
            'Info' { Write-Output "    $($E.Info) Sin reversión automática: $($c.Ruta) $($c.Nombre)" }
            default { throw "Tipo de cambio desconocido «$($c.Tipo)»: esta versión del kit no sabe deshacerlo (¿lo registró una versión más nueva?). Queda anotado para reintentarlo." }
        }
        $ok++
    } catch { $fallos++; [void]$fallidos.Add($c); Write-Output "    $($E.Error) $($c.Tipo): $($_.Exception.Message)" }
}
Write-Log "Deshacer cambios '$($j.Nombre)': $ok revertidos, $fallos con error"
Write-Output "`n  $(if ($fallos) { $E.Aviso } else { $E.OK }) $ok revertidos, $fallos con error.$(if ($reinicio) { ' Reinicia el equipo para completar la restauración.' })"
if (-not $fallos) {
    try { Rename-Item -LiteralPath $sel.FullName -NewName ($sel.Name + '_DESHECHO') -ErrorAction Stop } catch { }
    return
}
# Con fallos la sesión sigue pendiente, solo con lo que falta: así se puede reintentar sin repetir lo ya revertido
try {
    $pendientes = @($fallidos.ToArray()); [array]::Reverse($pendientes)   # de vuelta al orden original
    Copy-Item -LiteralPath $ficheroCambios -Destination "$ficheroCambios.bak-$(Get-Date -Format 'yyyyMMdd_HHmmss')" -Force -ErrorAction Stop
    Write-JsonAtomico $ficheroCambios ([pscustomobject]@{ Esquema = 1; Id = $j.Id; Nombre = $j.Nombre; Equipo = $j.Equipo; Fecha = $j.Fecha; Parcial = $true; Cambios = $pendientes })
    Write-Output "  $($E.Aviso) Quedan $($pendientes.Count) cambio(s) sin deshacer. La sesión sigue en la lista: vuelve a ejecutar «Deshacer cambios» para reintentar solo esos."
} catch { Write-Output "  $($E.Aviso) No se pudo actualizar el registro de la sesión ($($_.Exception.Message)); se reintentará todo al volver a deshacer." }
exit 1
