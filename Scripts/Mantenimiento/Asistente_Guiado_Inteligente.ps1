# =====================================================================
# Asistente_Guiado_Inteligente.ps1 (Módulo Triaje Guiado - Nitrit0_Kit v3.0)
# Diseñado para cualquier persona (con o sin conocimientos técnicos):
# Pregunta qué síntoma tiene el ordenador en lenguaje claro y ejecuta
# la secuencia exacta de diagnóstico y reparación con respaldo previo.
# =====================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = "SilentlyContinue"
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ScriptsRoot = Split-Path -Parent $ScriptDir
$RootDir = Split-Path -Parent $ScriptsRoot
$ComunPath = Join-Path $ScriptsRoot "Comun.ps1"
if (Test-Path $ComunPath) { . $ComunPath }
if (-not $Global:NitKit) { Initialize-Kit $RootDir }   # Test-ScriptAutorizado y Write-Log necesitan el kit inicializado

$form = New-Object Windows.Forms.Form
$form.Text = "Asistente Inteligente Nitrit0 · ¿Qué le pasa al ordenador?"
$form.Size = New-Object Drawing.Size(760, 704)
$form.StartPosition = "CenterScreen"
$form.BackColor = [Drawing.ColorTranslator]::FromHtml("#0f172a")
$form.ForeColor = [Drawing.ColorTranslator]::FromHtml("#f8fafc")
$form.Font = New-Object Drawing.Font("Segoe UI", 9.5)
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$lblTit = New-Object Windows.Forms.Label
$lblTit.Text = "Asistente Guiado en 1 Clic (Para Todos los Niveles)"
$lblTit.Font = New-Object Drawing.Font("Segoe UI Semibold", 15)
$lblTit.ForeColor = [Drawing.ColorTranslator]::FromHtml("#38bdf8")
$lblTit.AutoSize = $true
$lblTit.Location = New-Object Drawing.Point(24, 18)

$lblSub = New-Object Windows.Forms.Label
$lblSub.Text = "Elige qué síntoma notas en el equipo. El asistente creará un respaldo seguro y ejecutará las herramientas necesarias automáticamente."
$lblSub.ForeColor = [Drawing.ColorTranslator]::FromHtml("#94a3b8")
$lblSub.Size = New-Object Drawing.Size(700, 38)
$lblSub.Location = New-Object Drawing.Point(26, 50)

$form.Controls.AddRange(@($lblTit, $lblSub))

$Sintomas = @(
    @{
        Titulo = "1. El ordenador va lento, tarda en arrancar o se atasca"
        Desc   = "Crea punto de restauración, limpia temporales y basura acumulada, libera memoria RAM y analiza qué está llenando el disco."
        Scripts = @("Punto_Restauracion.ps1", "LimpiarTemporalesEquipo.ps1", "Gestion_Memoria_RAM.ps1", "Programas_Inicio.ps1", "Analizar_Espacio_Disco.ps1")
        Color  = "#10b981"
    }
    @{
        Titulo = "2. Da pantallazos azules, se apaga solo o se congela"
        Desc   = "Ejecuta el Analizador Forense de BSOD/Minidumps y WHEA, verifica la salud de los archivos de Windows (DISM + SFC) y comprueba drivers con fallos."
        Scripts = @("Analizador_BSOD_y_Eventos.ps1", "Auditoria_Drivers_Huerfanos.ps1", "Reparar_Windows_y_Tienda.ps1")
        Color  = "#ef4444"
    }
    @{
        Titulo = "3. Problemas con Internet, Wi-Fi lento o páginas que no cargan"
        Desc   = "Muestra tus claves Wi-Fi guardadas, limpia la caché DNS, renueva la IP y repara la pila de red TCP/IP y Winsock."
        DescPublico = "Limpia la caché DNS, renueva la IP, repara la pila de red TCP/IP y Winsock y aplica el DNS más rápido."
        Scripts = @("Reparar_Red.ps1", "DNS_Mas_Rapido.ps1", "Red_WiFi_y_Claves.ps1")
        Color  = "#38bdf8"
    }
    @{
        Titulo = "4. Preparar PC antes de formatear o actualizar BIOS (Resguardo Total)"
        Desc   = "Extrae y guarda la clave OEM de placa, las claves de 48 dígitos de BitLocker, exporta los drivers actuales y genera el inventario completo del equipo."
        DescPublico = "Exporta los drivers actuales y genera el inventario completo del equipo."
        Scripts = @("Auditoria_Licencias_BitLocker.ps1", "Inventario_Equipo.ps1", "Copia_Drivers.ps1")
        Color  = "#f59e0b"
    }
    @{
        Titulo = "5. Puesta a punto de PC recién comprado o recién formateado"
        Desc   = "Crea un punto de restauración, quita aplicaciones basura preinstaladas (Bloatware), abre el instalador básico de programas y actualiza todo con Winget."
        DescPublico = "Crea un punto de restauración, abre el instalador básico de programas y actualiza todo con Winget."
        Scripts = @("Punto_Restauracion.ps1", "Desinstalar_Bloatware_Win11.ps1", "Instalador_Basico.ps1", "Actualizar_Software.ps1")
        Color  = "#a855f7"
    }
    @{
        Titulo = "6. La impresora no imprime o los trabajos se quedan atascados"
        Desc   = "Vacía la cola de impresión, reinicia el servicio, quita el modo «sin conexión» y ofrece imprimir una página de prueba."
        Scripts = @("Reparar_Impresoras.ps1")
        Color  = "#22d3ee"
    }
    @{
        Titulo = "7. Revisar un portátil de segunda mano o antes de entregarlo"
        Desc   = "Prueba pantalla, altavoces, micrófono, cámara, teclado y batería, pasa el diagnóstico completo y genera el informe para el cliente."
        Scripts = @("Prueba_Hardware.ps1", "Diagnostico_Completo.ps1", "Informe_Entrega.ps1")
        Color  = "#84cc16"
    }
)

# Pack público: el asistente no lanza lo que el catálogo marca como peligroso (claves Wi-Fi, BitLocker, quitar programas); un síntoma sin pasos se oculta.
$publico = Test-ModoPublico
if ($publico) {
    $peligrosos = @()
    try { $cat = Read-DatosPsd1 (Join-Path $ScriptDir 'Catalogo.psd1'); $peligrosos = @($cat.Keys | Where-Object { $cat[$_].Peligroso }) } catch { $Sintomas = @() }   # sin catálogo legible no se ofrece nada
    $Sintomas = @($Sintomas | ForEach-Object { $_.Scripts = @($_.Scripts | Where-Object { $peligrosos -notcontains $_ }); if ($_.DescPublico) { $_.Desc = $_.DescPublico }; $_ } | Where-Object { $_.Scripts.Count -gt 0 })
}
$num = 0
$Sintomas = @($Sintomas | ForEach-Object { $num++; $_.Titulo = "$num. " + ($_.Titulo -replace '^\d+\.\s*', ''); $_ })

$y = 96
foreach ($s in $Sintomas) {
    $pan = New-Object Windows.Forms.Panel
    $pan.Size = New-Object Drawing.Size(700, 74)
    $pan.Location = New-Object Drawing.Point(24, $y)
    $pan.BackColor = [Drawing.ColorTranslator]::FromHtml("#1e293b")
    $pan.Cursor = "Hand"

    $bar = New-Object Windows.Forms.Panel
    $bar.Size = New-Object Drawing.Size(6, 74)
    $bar.Dock = "Left"
    $bar.BackColor = [Drawing.ColorTranslator]::FromHtml($s.Color)

    $lt = New-Object Windows.Forms.Label
    $lt.Text = $s.Titulo
    $lt.Font = New-Object Drawing.Font("Segoe UI Semibold", 11)
    $lt.ForeColor = [Drawing.Color]::White
    $lt.AutoSize = $true
    $lt.Location = New-Object Drawing.Point(18, 10)

    $ld = New-Object Windows.Forms.Label
    $ld.Text = $s.Desc
    $ld.Font = New-Object Drawing.Font("Segoe UI", 8.8)
    $ld.ForeColor = [Drawing.ColorTranslator]::FromHtml("#cbd5e1")
    $ld.Size = New-Object Drawing.Size(540, 38)
    $ld.Location = New-Object Drawing.Point(18, 34)

    $btn = New-Object Windows.Forms.Button
    $btn.Text = "Solucionar"
    $btn.Size = New-Object Drawing.Size(110, 36)
    $btn.Location = New-Object Drawing.Point(574, 19)
    $btn.FlatStyle = "Flat"
    $btn.BackColor = [Drawing.ColorTranslator]::FromHtml($s.Color)
    $btn.ForeColor = [Drawing.ColorTranslator]::FromHtml("#020617")
    $btn.Font = New-Object Drawing.Font("Segoe UI Semibold", 9.5)
    $btn.Tag = $s

    $accionClick = {
        param($origen, $e)
        $item = $origen.Tag
        # Una única confirmación global antes de lanzar nada; cada paso se comprueba además contra Datos\Integridad.json
        if (Confirm-Accion ("Se van a ejecutar en orden los siguientes módulos:`n`n• " + ($item.Scripts -join "`n• ") + "`n`nCada uno puede pedirte después sus propias confirmaciones si va a cambiar algo.`n`n¿Empezar ahora?") 'Asistente Inteligente Nitrit0') {
            $form.Hide()
            $resumen = @(); $fallos = 0; $n = 0
            $q = { param($x) "'" + ($x -replace "'", "''") + "'" }
            foreach ($sc in $item.Scripts) {
                $n++; $rutaSc = Join-Path $ScriptDir $sc
                if (-not (Test-Path -LiteralPath $rutaSc)) { $resumen += "FALTA   $sc"; $fallos++; continue }
                $motivo = Test-ScriptAutorizado $rutaSc
                if ($motivo) { Write-Host "`n>>> Paso $n de $($item.Scripts.Count): $sc BLOQUEADO: $motivo" -ForegroundColor Red; Write-Log "Asistente: $sc bloqueado: $motivo" 'ERROR'; $resumen += "BLOQUEADO $sc ($motivo)"; $fallos++; continue }
                Write-Host "`n>>> Paso $n de $($item.Scripts.Count): $sc" -ForegroundColor Cyan
                # Cada paso va en un proceso aparte (los scripts usan exit) y en esta misma consola, con Comun.ps1 cargado.
                # La orden va en el propio -Command: no se escribe ningún .ps1 en %TEMP% que otro proceso pudiera cambiar antes de que corra como administrador.
                $orden = "try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding(`$false) } catch { }; `$env:NIT_EJEC='1'; . $(& $q $ComunPath); Initialize-Kit $(& $q $RootDir); & $(& $q $rutaSc); exit `$LASTEXITCODE"
                $cod = -1
                try { $p = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-Command', ('"' + ($orden -replace '"', '\"') + '"')) -NoNewWindow -Wait -PassThru -ErrorAction Stop; $cod = $p.ExitCode } catch { Write-Host "    No se pudo iniciar: $($_.Exception.Message)" }
                if ($cod -eq 0) { $resumen += "OK      $sc" } else { $resumen += "AVISO   $sc (código $cod)"; $fallos++ }
            }
            Write-Host "`n=== Resumen del asistente ==="; $resumen | ForEach-Object { Write-Host "  $_" }
            $txtFin = if ($fallos) { "Terminado, pero $fallos paso(s) no acabaron bien:" } else { "Todos los pasos terminaron correctamente:" }
            [Windows.Forms.MessageBox]::Show("$txtFin`n`n" + ($resumen -join "`n") + "`n`n" + $(if ($publico) { "Los informes están en la carpeta temporal del equipo (%TEMP%\Nitrit0_Cache) y se borran al cabo de una hora." } else { "Los informes y respaldos están en la carpeta Datos del kit." }), "Asistente Nitrit0", "OK", $(if ($fallos) { "Warning" } else { "Information" })) | Out-Null
            $form.Close()
            if ($fallos) { $script:CodigoSalida = 1 }
        }
    }

    $btn.Add_Click($accionClick)
    $pan.Controls.AddRange(@($btn, $lt, $ld, $bar))
    $form.Controls.Add($pan)
    $y += 80
}

[void]$form.ShowDialog()
exit ([int]$script:CodigoSalida)   # distinto de 0 si algún paso falló: el lanzador lo muestra como aviso
