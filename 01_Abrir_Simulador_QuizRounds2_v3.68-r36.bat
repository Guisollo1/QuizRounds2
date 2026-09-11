@echo off
setlocal
cd /d "%~dp0"
title Quiz Rounds v3.68-r36 - Simulador Local
echo ============================================================
echo   QUIZ ROUNDS v3.68-r36 - SIMULADOR DE USO REAL
echo ============================================================
echo.
echo Login ADM de teste: admin
echo Senha de teste:     quiz123
echo.
echo Abrindo simulador no navegador...
start "" "%~dp0simulator.html"
exit /b 0
