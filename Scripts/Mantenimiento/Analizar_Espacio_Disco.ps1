# =====================================================================
#  Analizar_Espacio_Disco.ps1 (Lanzador Nitrit0 - 100% Local)
#  Localiza rápidamente qué carpetas y archivos gigantes están llenando
#  el disco C: (Descargas, AppData, Windows.old, Hibernación y Top 20).
# =====================================================================
[CmdletBinding()]
param()
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Comun.ps1'); Initialize-Kit (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }

if (-not $Global:E) {
    $Global:E = @{
        OK = [char]::ConvertFromUtf32(0x2705); Error = [char]::ConvertFromUtf32(0x274C); Aviso = [char]::ConvertFromUtf32(0x26A0)
        Info = [char]::ConvertFromUtf32(0x2139); Cohete = [char]::ConvertFromUtf32(0x1F680); Lupa = [char]::ConvertFromUtf32(0x1F50D)
        Disco = [char]::ConvertFromUtf32(0x1F4BE); Reloj = [char]::ConvertFromUtf32(0x23F3)
    }
}
$E = $Global:E

Write-Output "`n========================================================"
Write-Output "  $($E.Disco) RADIOGRAFÍA DE ESPACIO EN DISCO (C:) - NITRIT0"
Write-Output "========================================================`n"

$DiscoC = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
$TotalGB = [math]::Round($DiscoC.Size / 1GB, 2)
$LibreGB = [math]::Round($DiscoC.FreeSpace / 1GB, 2)
$UsadoGB = [math]::Round(($DiscoC.Size - $DiscoC.FreeSpace) / 1GB, 2)
$PctLibre = [math]::Round(($DiscoC.FreeSpace / $DiscoC.Size) * 100, 1)

Write-Output "  $($E.Info) Capacidad Total: $TotalGB GB  |  Ocupado: $UsadoGB GB  |  Libre: $LibreGB GB ($PctLibre%)"

function Get-TamanoCarpetaGB([string]$Ruta) {
    if (-not (Test-Path -LiteralPath $Ruta)) { return 0 }
    try {
        $suma = (Get-ChildItem -LiteralPath $Ruta -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        return [math]::Round($suma / 1GB, 2)
    } catch { return 0 }
}

# 1. Elementos especiales del sistema (Windows.old, Hibernación, Paginación)
Write-Output "`n--- $($E.Lupa) 1. ARCHIVOS DE SISTEMA Y RESPALDOS ANTIGUOS ---"
foreach ($f in @("$env:SystemDrive\pagefile.sys", "$env:SystemDrive\hiberfil.sys", "$env:SystemDrive\swapfile.sys")) {
    $it = Get-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
    if ($it) {
        Write-Output ("  • {0,-22} : {1,6} GB" -f $it.Name, [math]::Round($it.Length / 1GB, 2))
    }
}
if (Test-Path "$env:SystemDrive\Windows.old") {
    $tamOld = Get-TamanoCarpetaGB "$env:SystemDrive\Windows.old"
    Write-Output "  $($E.Aviso) $env:SystemDrive\Windows.old         : $tamOld GB  (Instalación anterior de Windows: puedes borrarla con Liberador de espacio)"
} else {
    Write-Output "  $($E.OK) No existe carpeta $env:SystemDrive\Windows.old."
}

# 2. Desglose de carpetas del usuario actual y ocultas típicas (Backups de iPhone, instaladores...)
Write-Output "`n--- $($E.Lupa) 2. DESGLOSE DE CARPETAS DE TU USUARIO ($env:USERNAME) ---"
$RutasUsuario = [ordered]@{
    "Descargas (Downloads)"         = "$env:USERPROFILE\Downloads"
    "Escritorio (Desktop)"          = "$env:USERPROFILE\Desktop"
    "Documentos (Documents)"        = "$env:USERPROFILE\Documents"
    "Vídeos (Videos)"               = "$env:USERPROFILE\Videos"
    "Imágenes (Pictures)"           = "$env:USERPROFILE\Pictures"
    "OneDrive (Sincronizado local)" = "$env:USERPROFILE\OneDrive"
    "AppData\Local (Cachés/Apps)"   = "$env:LOCALAPPDATA"
    "AppData\Roaming (Datos Apps)"  = "$env:APPDATA"
    "Copias iPhone/iPad (Apple)"    = "$env:APPDATA\Apple Computer\MobileSync\Backup"
    "Copias iPhone (Microsoft Store)"= "$env:USERPROFILE\Apple\MobileSync\Backup"
}

foreach ($par in $RutasUsuario.GetEnumerator()) {
    if (Test-Path -LiteralPath $par.Value) {
        $gb = Get-TamanoCarpetaGB $par.Value
        if ($gb -ge 0.1) {
            $icono = if ($gb -ge 15) { $E.Aviso } else { " •" }
            Write-Output ("  {0} {1,-32} : {2,6} GB   ({3})" -f $icono, $par.Key, $gb, $par.Value)
        }
    }
}

# 3. Top 20 archivos más grandes en las carpetas de usuario (películas, ISOs, instaladores, ZIPs...)
Write-Output "`n--- $($E.Reloj) 3. BUSCANDO LOS 20 ARCHIVOS MÁS PESADOS EN LAS CARPETAS DE USUARIO (>200 MB)... ---"
# Recorrido propio y rápido: no entra en carpetas con cientos de miles de archivos pequeños (node_modules, .git, paquetes de Store, temporales) ni en enlaces simbólicos
if (-not ('Nit.BuscaGrandes' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
namespace Nit {
    public static class BuscaGrandes {
        static readonly string[] Saltar = { "\\node_modules", "\\.git", "\\AppData\\Local\\Packages", "\\AppData\\Local\\Temp" };
        public static List<KeyValuePair<long, string>> Buscar(string raiz, long minimo) {
            List<KeyValuePair<long, string>> res = new List<KeyValuePair<long, string>>();
            Stack<string> pila = new Stack<string>(); pila.Push(raiz);
            while (pila.Count > 0) {
                string d = pila.Pop();
                try {
                    DirectoryInfo di = new DirectoryInfo(d);
                    foreach (FileInfo f in di.EnumerateFiles()) { try { if (f.Length >= minimo) res.Add(new KeyValuePair<long, string>(f.Length, f.FullName)); } catch { } }
                    foreach (DirectoryInfo sub in di.EnumerateDirectories()) {
                        try {
                            if ((sub.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                            bool saltar = false; string fn = sub.FullName;
                            foreach (string x in Saltar) { if (fn.EndsWith(x, StringComparison.OrdinalIgnoreCase)) { saltar = true; break; } }
                            if (!saltar) pila.Push(fn);
                        } catch { }
                    }
                } catch { }
            }
            res.Sort(delegate(KeyValuePair<long, string> a, KeyValuePair<long, string> b) { return b.Key.CompareTo(a.Key); });
            return res;
        }
    }
}
'@
}
$Grandes = @([Nit.BuscaGrandes]::Buscar((Split-Path -Parent $env:PUBLIC), 200MB) | Select-Object -First 20 | ForEach-Object { [pscustomobject]@{ Length = $_.Key; FullName = $_.Value } })

if ($Grandes.Count -gt 0) {
    foreach ($arch in $Grandes) {
        $tam = [math]::Round($arch.Length / 1GB, 2)
        Write-Output ("  [{0,5} GB]  {1}" -f $tam, $arch.FullName)
    }
} else {
    Write-Output "  $($E.OK) No se encontraron archivos individuales de más de 200 MB en las carpetas de usuario."
}

Write-Output "`n========================================================"
Write-Output "  $($E.OK) ANÁLISIS DE ESPACIO COMPLETADO"
Write-Output "========================================================"