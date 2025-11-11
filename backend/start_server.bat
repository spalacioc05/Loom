@echo off
echo ====================================
echo   Iniciando Backend - Servicio TTS
echo ====================================
echo.

cd /d "%~dp0"

:loop
echo [%date% %time%] Iniciando servidor...
node index.js

echo.
echo ====================================
echo   El servidor se detuvo
echo ====================================
echo.
echo Presiona Ctrl+C para salir o cualquier tecla para reiniciar...
pause > nul

goto loop
