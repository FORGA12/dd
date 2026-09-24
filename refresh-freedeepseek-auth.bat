@echo off
setlocal
cd /d "%~dp0"
echo Renovacion de token y cookies de DeepSeek Web
echo Se abrira una ventana Chrome separada.
echo.
node scripts/auth.js --login
if errorlevel 1 (
  echo.
  echo No se pudo renovar la autenticacion.
  pause
  exit /b 1
)
echo.
echo Autenticacion renovada. Ahora puedes ejecutar launch-freedeepseekapi.bat.
pause
