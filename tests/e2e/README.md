# E2E de navegador — QuizRounds2 r77

Este gate abre o **simulador real** em Chromium via Playwright e dirige a interface como usuário.
Ele cobre quatro cenários bloqueantes no CI:

1. autenticação e suíte lógica pelo navegador;
2. evento completo com 100 jogadores simulados até ranking final;
3. celular de teste com entrada, desconexão, reconexão, resposta e resultado;
4. viewport móvel de 390×844.

O teste é propositalmente independente de credenciais Supabase e de serviços externos. Assim, uma falha de rede pública não mascara regressões de DOM, JavaScript, timers, ranking ou fluxo de navegação. Os validadores `validate-sync-behavior.mjs` e `validate-event-stress.mjs` continuam cobrindo o contrato Realtime/state_version.

No GitHub Actions, o browser é instalado antes do deploy e este teste é **bloqueante**.
