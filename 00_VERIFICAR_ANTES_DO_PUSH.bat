@echo off
setlocal
cd /d "%~dp0"
echo ==============================================
echo QuizRounds2 - verificacao antes do push
echo ==============================================
where node >nul 2>nul
if errorlevel 1 (
  echo ERRO: Node.js nao encontrado.
  pause
  exit /b 1
)
echo.
echo [1/2] Gate essencial...
node scripts\validate-release.mjs
if errorlevel 1 (
  echo.
  echo BLOQUEADO: corrija os erros do gate essencial antes do push.
  pause
  exit /b 1
)
echo.
echo [2/2] Auditoria profunda...
node scripts\validate-build.mjs
if errorlevel 1 (
  echo.
  echo AVISO: a auditoria profunda encontrou divergencias.
  echo O GitHub ainda executara o gate essencial e validara o artefato publicado.
  echo Revise o resultado acima antes de um evento importante.
) else (
  echo Auditoria profunda aprovada.
)
echo.
echo GATE ESSENCIAL APROVADO - pode enviar para o GitHub.
pause
exit /b 0
