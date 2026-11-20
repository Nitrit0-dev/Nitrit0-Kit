# =====================================================================
#  Tema.ps1 - Colores del kit (oscuro / claro) - Nitrit0 v5.2
#  Una sola rampa de grises grafito y un único color de acento (cian).
#  El color queda para la acción principal, la selección y los estados (ok / aviso / fallo).
#  Conversión hexadecimal propia: no depende de ColorTranslator.
# =====================================================================

Add-Type -AssemblyName System.Drawing, System.Windows.Forms -ErrorAction SilentlyContinue

function ConvertFrom-HexColor([string]$hex) {
    $h = $hex.Trim().TrimStart('#')
    if ($h.Length -eq 6) {
        $r = [Convert]::ToInt32($h.Substring(0, 2), 16)
        $g = [Convert]::ToInt32($h.Substring(2, 2), 16)
        $b = [Convert]::ToInt32($h.Substring(4, 2), 16)
        return [System.Drawing.Color]::FromArgb(255, $r, $g, $b)
    }
    return [System.Drawing.Color]::FromArgb(255, 136, 136, 136)
}

$script:Paletas = @{
    oscuro = @{
        Fondo        = '#141415'
        Cab          = '#0F0F10'
        Tarjeta      = '#19191B'
        TarjetaHov   = '#232325'
        Borde        = '#2C2C2F'
        Texto        = '#EDEDED'
        TextoSuave   = '#A1A1A6'
        Tenue        = '#85858B'
        Acento       = '#22D3EE'
        TextoAcento  = '#04131D'
        Boton        = '#19191B'
        BotonSel     = '#232325'
        Hero1        = '#19191B'
        Hero2        = '#19191B'
        HeroTexto    = '#A1A1A6'
        HeroBtn      = '#232325'
        HeroBorde    = '#343438'
        HeroTaller   = '#232325'
        Ok           = '#4CC38A'
        Aviso        = '#E0A23B'
        Error        = '#E5484D'
        Fallo        = '#E5484D'
        DetalleFondo = '#0F0F10'
        DetalleTexto = '#EDEDED'
    }
    claro = @{
        Fondo        = '#FAFAFA'
        Cab          = '#FFFFFF'
        Tarjeta      = '#FFFFFF'
        TarjetaHov   = '#F4F4F5'
        Borde        = '#E4E4E7'
        Texto        = '#171717'
        TextoSuave   = '#525252'
        Tenue        = '#737373'
        Acento       = '#0E7490'
        TextoAcento  = '#FFFFFF'
        Boton        = '#FFFFFF'
        BotonSel     = '#F4F4F5'
        Hero1        = '#FFFFFF'
        Hero2        = '#FFFFFF'
        HeroTexto    = '#525252'
        HeroBtn      = '#F4F4F5'
        HeroBorde    = '#D4D4D8'
        HeroTaller   = '#F4F4F5'
        Ok           = '#16A34A'
        Aviso        = '#B45309'
        Error        = '#DC2626'
        Fallo        = '#DC2626'
        DetalleFondo = '#FFFFFF'
        DetalleTexto = '#171717'
    }
}

# Tipografía: las fuentes modernas que ya trae Windows 11 (Segoe UI Variable y Cascadia Mono), sin descargar nada.
# En Windows 10 no existen: se usa Segoe UI y Consolas. Hay que comprobarlo, porque si se pide una fuente
# que no está instalada Windows la cambia por «Microsoft Sans Serif».
$famInst = @((New-Object System.Drawing.Text.InstalledFontCollection).Families | ForEach-Object { $_.Name })
function Select-Fuente([string]$moderna, [string]$clasica) { if ($famInst -contains $moderna) { $moderna } else { $clasica } }
$script:Fuentes = @{
    UI      = Select-Fuente 'Segoe UI Variable Text' 'Segoe UI'                        # texto normal
    Semi    = Select-Fuente 'Segoe UI Variable Text Semibold' 'Segoe UI Semibold'      # títulos de tarjeta y botones
    Display = Select-Fuente 'Segoe UI Variable Display Semib' 'Segoe UI Semibold'      # títulos grandes (el nombre viene recortado así en Windows)
    Mono    = Select-Fuente 'Cascadia Mono' 'Consolas'                                 # lecturas y atajos
}
# Orden fijo: lo leen los controles en C# del lanzador con UiHelper.F(i)
[AppDomain]::CurrentDomain.SetData('NitFuentes', [string[]]@($script:Fuentes.UI, $script:Fuentes.Semi, $script:Fuentes.Display, $script:Fuentes.Mono))

$script:TemaActual = 'oscuro'
# Se lee el JSON directamente: Get-Ajustes (Componentes.ps1) todavía no está cargado cuando se carga el tema
try {
    $pAj = Join-Path $Global:NitKit.Datos 'Ajustes.json'
    if (Test-Path -LiteralPath $pAj) { $tAj = (Get-Content -LiteralPath $pAj -Raw -Encoding UTF8 | ConvertFrom-Json).Tema; if ($tAj -in 'claro', 'oscuro') { $script:TemaActual = $tAj } }
} catch { }

function Get-Tc([string]$clave) {
    $p = $script:Paletas[$script:TemaActual]
    $hex = if ($p.ContainsKey($clave)) { $p[$clave] } else { '#888888' }
    ConvertFrom-HexColor $hex
}

# Las categorías ya no tienen color propio: todas usan el acento
function Get-AcentoCat([string]$cat) { Get-Tc 'Acento' }

function Set-Tema([string]$modo) {
    if ($modo -notin 'claro', 'oscuro') { $modo = 'oscuro' }
    $script:TemaActual = $modo
    # Orden fijo: lo leen los controles en C# del lanzador con UiHelper.T(i)
    [System.Drawing.Color[]]$arr = @(
        (Get-Tc 'Fondo'),
        (Get-Tc 'Tarjeta'),
        (Get-Tc 'TarjetaHov'),
        (Get-Tc 'Borde'),
        (Get-Tc 'Texto'),
        (Get-Tc 'TextoSuave'),
        (Get-Tc 'Acento'),
        (Get-Tc 'Aviso')
    )
    [AppDomain]::CurrentDomain.SetData('NitTema', $arr)
}

Set-Tema $script:TemaActual
