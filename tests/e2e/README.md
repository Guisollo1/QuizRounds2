# E2E de navegador — QuizRounds2 r86

A homologação E2E é propositalmente separada do deploy do GitHub Pages. Isso evita que falhas de provisionamento/download de navegador impeçam uma publicação válida.

Workflow: `.github/workflows/e2e.yml` → **Homologação E2E QuizRounds2**.

Ele usa `mcr.microsoft.com/playwright/python:v1.55.0-noble` e executa quatro cenários:
1. autenticação e suíte lógica pela interface;
2. evento completo com 100 jogadores simulados;
3. entrada, desconexão, reconexão, resposta e resultado do celular;
4. viewport móvel 390×844.

O script também tenta usar Chromium/Chrome do sistema quando executado localmente. `pageerror` e `console.error` reprovam o cenário.
