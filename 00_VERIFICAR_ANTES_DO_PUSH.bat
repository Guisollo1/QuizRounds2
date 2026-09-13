@echo off
setlocal
cd /d "%~dp0"
echo ===============================================
echo QuizRounds2 - verificacao antes do GitHub Push
echo ===============================================
where node >nul 2>nul
if errorlevel 1 (
  echo [ERRO] Node.js nao foi encontrado neste PC.
  echo Abra VERSION.txt e confirme que todos os arquivos ativos usam a mesma release antes do push.
  pause
  exit /b 1
)
node scripts\validate-build.mjs
if errorlevel 1 (
  echo.
  echo [BLOQUEADO] Nao envie para o GitHub. Corrija os erros acima primeiro.
  pause
  exit /b 1
)
echo.
echo [OK] Release consistente. Pode fazer Commit e Push no GitHub Desktop.
pause
