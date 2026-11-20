@echo off
rem Alternativa al exe: abre el lanzador desde Scripts\ (pide permisos de administrador y oculta la consola).
cd /d "%TEMP%"
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0Lanzador.ps1"
