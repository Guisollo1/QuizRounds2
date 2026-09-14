# QuizRounds2 v3.68-r77 — Final E2E Real

A r77 preserva integralmente as correções determinísticas da r76 e corrige a única área que ainda estava abaixo de 9/10: **E2E automatizado**. Ela não adiciona modos de jogo nem altera regras de pontuação. O deploy agora executa um **Chromium real via Playwright** antes de publicar.

## Correções principais

- Novo gate **E2E real de navegador** no GitHub Actions, executado antes do upload para Pages.
- O Chromium percorre autenticação, suíte lógica, fluxo completo com 100 jogadores simulados, entrada/reconexão/resposta do celular e viewport móvel.
- Erros JavaScript de página e `console.error` tornam o E2E reprovado.

- `state_version` **à frente** do ADM agora é classificado como **divergente** e bloqueia o pré-flight. Somente igualdade exata é sincronização.
- O teste de ACK congela as **identidades esperadas** no início. Um aparelho extra nunca substitui outro que não respondeu.
- ACKs duplicados da mesma identidade são deduplicados.
- O teste termina imediatamente quando todas as identidades esperadas responderem; se faltar alguém, usa deadline adaptativo de até 8 s.
- Jogadores e telão que já estão no estado correto respondem ao ACK sem heartbeat RPC e sem refresh obrigatório.
- Apenas aparelhos realmente atrasados/inicializando tentam convergir antes de responder.
- `state_version = 0` continua aparecendo como **Inicializando**.
- Cache anti-downgrade, `qr_build`, watchdog, fallback controlado por polling, áudio exclusivo do telão e o pré-flight da r75 permanecem preservados.

## Backend / Supabase

- Backend base exigido: **schema 042**.
- Backend recomendado: **schema 043**.
- Modos avançados de formação de equipes exigem **schema 043**.
- Se o Supabase já está no schema 043, **não execute migration novamente**.
- A r77 não cria migration nova; a cadeia permanece `001–043`.

## Publicar no GitHub

1. Preserve a pasta `.git` do repositório local.
2. Remova os arquivos do projeto anterior e copie o conteúdo **de dentro desta pasta da r77** para a raiz do repositório.
3. Execute `00_VERIFICAR_ANTES_DO_PUSH.bat`.
4. Só faça commit/push quando os gates locais estiverem aprovados; o GitHub executará também o E2E Chromium bloqueante.
5. Aguarde `Deploy QuizRounds2 no GitHub Pages` concluir em verde.
6. Abra ADM, jogador e telão e confirme o build **3.68-r77**.

Não coloque `sb_secret_` ou `service_role` no navegador. O deploy usa `SUPABASE_URL` e `SUPABASE_PUBLISHABLE_KEY` configurados no GitHub Actions.

## Validações incluídas

- `scripts/validate-sync-behavior.mjs`: **16/16** cenários comportamentais, incluindo presença à frente e substituição indevida de identidade.
- `scripts/validate-event-stress.mjs`: **16/16** testes determinísticos, **10.000** cenários pseudoaleatórios por propriedade e 20 transições com 100 jogadores + 1 telão.
- `scripts/validate-site-smoke.mjs`: smoke HTTP do `_site` publicado localmente.
- `scripts/validate-build.mjs`: auditoria estrutural bloqueante da release.
- `tests/e2e/test_browser_e2e.py`: **4/4 cenários em Chromium real**, bloqueantes antes do deploy.

O E2E da r77 é um teste real de navegador sobre o simulador integrado, portanto cobre DOM, timers, navegação, ranking e reconexão simulada. Ele ainda **não substitui um ensaio físico** com Supabase real, ADM, telão e celulares na rede do evento.

## Teste antes do evento

Abra uma sala de teste, o telão e pelo menos dois celulares. Ative o som no próprio telão. No Modo Evento, execute **Sincronizar aparelhos** e confirme que todos os dispositivos esperados responderam pela própria identidade e ficaram exatamente no mesmo `state_version` e `generation`. Depois faça uma rodada completa até o ranking/pódio.

## Arquivos de homologação

- `CHANGELOG_v3.68_r77_Final_E2E_Real.txt`
- `VALIDATION_r77_Final_E2E_Real.txt`
- `FINAL_RELEASE_r77.txt`
- `BUILD_MANIFEST_SHA256.txt`

Histórico de versões anteriores permanece em `docs/history/` e não participa do runtime ativo.
