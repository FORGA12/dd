@echo off
setlocal
cd /d "%~dp0"
set "NON_INTERACTIVE=1"
echo Iniciando FreeDeepseekAPI en http://127.0.0.1:9655
echo Pulsa Ctrl+C para detenerlo.
node server.js
if errorlevel 1 (
  echo.
  echo FreeDeepseekAPI termino con un error.
  pause
)
