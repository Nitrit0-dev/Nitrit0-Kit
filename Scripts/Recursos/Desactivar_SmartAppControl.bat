@echo off
setlocal EnableExtensions
chcp 65001 >nul
title Nitrit0 - Desactivar el Control Inteligente de Aplicaciones
rem =====================================================================
rem  Desactivar_SmartAppControl.bat - Apaga Smart App Control (Control Inteligente de Aplicaciones) de ESTE equipo.
rem  Solo para tu equipo personal: viene en el pack personal, nunca en el público ni se usa en equipos de clientes.
rem  Windows lo bloquea con programas sin firmar (como Nitrit0.exe). Una vez apagado NO se puede volver a encender sin reinstalar Windows.
rem  Uso: clic derecho > Ejecutar como administrador.   Con /simular solo mira el estado y no cambia nada.
rem  Salida: 0 bien (o ya estaba apagado) - 1 error - 2 cancelado
rem =====================================================================
set "CLAVE=HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy"
set "VALOR=VerifiedAndReputablePolicyState"
set "SIMULAR="
if /i "%~1"=="/simular" set "SIMULAR=1"

echo ========================================================
echo   Desactivar Smart App Control (Control Inteligente de Aplicaciones)
echo ========================================================
echo.

rem Estado actual: 0x0 apagado, 0x1 activado, 0x2 modo evaluación (REG_DWORD no se traduce: vale en cualquier idioma)
set "ESTADO="
for /f "tokens=3" %%v in ('reg query "%CLAVE%" /v %VALOR% 2^>nul ^| find "REG_DWORD"') do set "ESTADO=%%v"
if not defined ESTADO (
  echo No encuentro el valor de Smart App Control: este Windows no lo tiene ^(es anterior a Windows 11 22H2^) o no se puede leer.
  set "SALIDA=1" & goto :fin
)
if "%ESTADO%"=="0x0" (
  echo Smart App Control ya está desactivado en este equipo. No hay nada que hacer.
  set "SALIDA=0" & goto :fin
)
if "%ESTADO%"=="0x1" echo Estado actual: ACTIVADO.
if "%ESTADO%"=="0x2" echo Estado actual: modo EVALUACIÓN ^(Windows decide solo si lo activa o lo apaga^).
echo.

if defined SIMULAR (
  echo Simulación: se pondría %VALOR% = 0 en %CLAVE%. No se ha cambiado nada.
  set "SALIDA=0" & goto :fin
)

fltmc >nul 2>&1
if errorlevel 1 (
  echo Hace falta administrador. Cierra esta ventana y ejecútalo con clic derecho ^> Ejecutar como administrador.
  set "SALIDA=1" & goto :fin
)

echo ATENCIÓN - LEE ESTO ANTES DE CONTINUAR
echo   - Es IRREVERSIBLE: una vez apagado, Windows no deja volver a encenderlo sin reinstalar el sistema.
echo   - Este equipo quedará sin esa protección frente a programas desconocidos o sin firmar.
echo   - Úsalo solo en TU equipo. No lo hagas en el equipo de un cliente ni de otra persona.
echo   - Hace falta reiniciar para que surta efecto.
echo.
set "RESP="
set /p "RESP=Para continuar escribe DESACTIVAR (en mayúsculas) y pulsa Intro. Cualquier otra cosa cancela: "
if not "%RESP%"=="DESACTIVAR" (
  echo.
  echo Cancelado: no se ha cambiado nada.
  set "SALIDA=2" & goto :fin
)

reg add "%CLAVE%" /v %VALOR% /t REG_DWORD /d 0 /f >nul 2>&1
if errorlevel 1 (
  echo.
  echo No se pudo escribir el valor ^(Windows lo ha rechazado^). Hazlo a mano: Seguridad de Windows ^> Control de aplicaciones y navegador ^> Control Inteligente de Aplicaciones ^> Desactivado.
  set "SALIDA=1" & goto :fin
)

rem Se vuelve a leer para comprobar que Windows lo ha aceptado
set "NUEVO="
for /f "tokens=3" %%v in ('reg query "%CLAVE%" /v %VALOR% 2^>nul ^| find "REG_DWORD"') do set "NUEVO=%%v"
if not "%NUEVO%"=="0x0" (
  echo.
  echo Windows no ha aceptado el cambio. Hazlo a mano: Seguridad de Windows ^> Control de aplicaciones y navegador ^> Control Inteligente de Aplicaciones ^> Desactivado.
  set "SALIDA=1" & goto :fin
)
echo.
echo Hecho: Smart App Control queda desactivado. REINICIA el equipo para que surta efecto.
set "SALIDA=0"

:fin
echo.
if not defined SIMULAR pause
exit /b %SALIDA%