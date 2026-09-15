@echo off
setlocal
cd /d "%~dp0"
echo ==============================================
echo QuizRounds2 r81 SINCRONIZACAO SEM BLOQUEIO FALSO - pre-push
echo ==============================================
where node >nul 2>nul
if errorlevel 1 (
  echo ERRO: Node.js nao encontrado.
  pause
  exit /b 1
)
echo.
echo [1/4] Gate essencial...
node scripts\validate-release.mjs
if errorlevel 1 (
  echo.
  echo BLOQUEADO: corrija os erros do gate essencial antes do push.
  pause
  exit /b 1
)
echo.
echo [2/4] Contrato comportamental de sincronizacao...
node scripts\validate-sync-behavior.mjs
if errorlevel 1 (
  echo.
  echo BLOQUEADO: a sincronizacao deterministica nao passou nos testes comportamentais.
  pause
  exit /b 1
)
echo.
echo [3/4] Estresse operacional 100 jogadores + telao...
node scripts\validate-event-stress.mjs
if errorlevel 1 (
  echo.
  echo BLOQUEADO: o estresse operacional encontrou um falso positivo de sincronizacao.
  pause
  exit /b 1
)
echo.
echo [4/4] Auditoria final bloqueante...
node scripts\validate-build.mjs
if errorlevel 1 (
  echo.
  echo BLOQUEADO: a auditoria final encontrou divergencias.
  echo Nao envie esta release para o evento ate corrigir os erros acima.
  pause
  exit /b 1
)
echo.
echo ==============================================
echo APROVADO - r81 INICIO SEM RECONNECT pronta para enviar ao GitHub.
echo ==============================================
pause
exit /b 0
