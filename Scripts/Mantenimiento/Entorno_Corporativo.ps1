# =====================================================================
#  Entorno_Corporativo.ps1 - ¿Este equipo lo gestiona una empresa? (Nitrit0)
#  Solo lee: dominio de Windows, Microsoft Entra ID (antes Azure AD), gestión de dispositivos (Intune u otro) y directivas de grupo.
#  No cambia nada. Úsalo antes de tocar red, directivas o programas en un equipo que no es de un particular.
# =====================================================================
[CmdletBinding()]
param()
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$E = $Global:E

Write-Output "========================================================"
Write-Output "  $($E.Lupa) ¿LO GESTIONA UNA EMPRESA?"
Write-Output "========================================================"

$cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
$os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
$indicios = New-Object Collections.Generic.List[string]

# Dominio de Active Directory
if ($cs -and $cs.PartOfDomain) { $indicios.Add("Unido a un dominio de Windows ($($cs.Domain))"); Write-Output "  $($E.Aviso) Unido a un dominio de Windows: $($cs.Domain)." }
else { Write-Output "  $($E.OK) No está unido a un dominio de Windows." }

# Microsoft Entra ID: la unión deja una clave por cada inquilino
$entra = @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo' -ErrorAction SilentlyContinue)
if ($entra.Count) { $indicios.Add('Unido a Microsoft Entra ID'); Write-Output "  $($E.Aviso) Unido a Microsoft Entra ID (cuenta de trabajo o centro educativo)." }
else { Write-Output "  $($E.OK) No está unido a Microsoft Entra ID." }

# Gestión de dispositivos (MDM): cada inscripción real tiene un proveedor; la de gestión local de Windows no cuenta
$mdm = @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue | ForEach-Object { Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue } | Where-Object { $_.DiscoveryServiceFullURL -or ($_.ProviderID -and $_.ProviderID -notin 'Local_Management', 'Local Authority', 'Cloud Authority', 'Deploy Authority') })   # esas tres son entradas internas de Windows, no una empresa
if ($mdm.Count) { $indicios.Add('Dispositivo inscrito en un sistema de gestión (MDM)'); Write-Output "  $($E.Aviso) Inscrito en un sistema de gestión de dispositivos: $((($mdm | ForEach-Object { if ($_.ProviderID) { $_.ProviderID } else { $_.DiscoveryServiceFullURL } }) | Select-Object -Unique) -join ', ')." }
else { Write-Output "  $($E.OK) No está inscrito en ningún sistema de gestión de dispositivos." }

# Directivas de grupo de dominio aplicadas alguna vez
# Con directivas de dominio, el historial guarda qué controlador las entregó (DCName); sin dominio solo hay entradas locales
$gpoDominio = @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\History' -Recurse -ErrorAction SilentlyContinue | Where-Object { try { (Get-ItemProperty -LiteralPath $_.PSPath -Name DCName -ErrorAction Stop).DCName } catch { $null } }).Count
if ($gpoDominio) { $indicios.Add('Recibe directivas de grupo de dominio'); Write-Output "  $($E.Aviso) Recibe directivas de grupo de un dominio." }
else { Write-Output "  $($E.OK) Sin directivas de grupo de dominio." }

# Servidor o controlador de dominio
if ($os -and $os.ProductType -ne 1) { $indicios.Add('Es un servidor o un controlador de dominio'); Write-Output "  $($E.Aviso) Es un servidor o un controlador de dominio, no un equipo de usuario." }

Write-Output ""
if ($indicios.Count) {
    Write-Output "  $($E.Aviso) Parece un equipo gestionado: $($indicios.Count) indicio(s)."
    Write-Output "     Antes de cambiar red, directivas, usuarios o programas, avisa a quien lo administra: puede deshacerte el cambio o bloquearlo."
    Write-Log "Entorno_Corporativo: gestionado ($($indicios -join '; '))"
} else {
    Write-Output "  $($E.OK) Parece un equipo personal: nada indica que lo gestione una empresa."
    Write-Output "     No es una garantía: sin conexión no se ve qué directivas llegarán después."
    Write-Log 'Entorno_Corporativo: personal'
}