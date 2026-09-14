# QuizRounds2 v3.68-r79 — Deploy Estável Comprovado

A r79 preserva integralmente o runtime e as correções determinísticas da r77, mas corrige a arquitetura de CI que fez o deploy falhar: **GitHub Pages não instala mais Python, Playwright ou Chromium durante a publicação**. O deploy volta a depender apenas dos gates locais do projeto e da geração/validação do `_site`.

## Correção principal do deploy

- O workflow `Deploy QuizRounds2 no GitHub Pages` não contém mais `setup-python`, `pip install` nem `playwright install`.
- O deploy continua bloqueado por `validate-release`, sincronização 16/16, estresse 16/16 + 10.000 cenários, auditoria completa, validação do `_site` e smoke HTTP.
- O E2E real foi movido para `.github/workflows/e2e.yml`.
- A homologação E2E usa a imagem oficial `mcr.microsoft.com/playwright/python:v1.55.0-noble`, que já traz navegador/dependências, evitando download de Chromium durante o deploy.
- O E2E continua cobrindo 4 cenários: autenticação/suíte lógica, evento completo com 100 jogadores simulados, reconexão/resposta do celular e viewport móvel.
- `pageerror` e `console.error` continuam reprovando a homologação E2E.

## Sincronização preservada

- `state_version` à frente é divergente e bloqueante; somente igualdade exata é sincronização.
- ACK é validado por identidade exata; aparelho extra não substitui ausente.
- ACKs duplicados são deduplicados.
- Early-completion e deadline adaptativo de até 8 s permanecem.
- Jogadores/telão no estado correto respondem ao teste sem heartbeat RPC em massa.
- `state_version = 0` aparece como **Inicializando**.
- Cache anti-downgrade, `qr_build`, watchdog, fallback controlado por polling e áudio exclusivo do telão permanecem.

## Backend / Supabase

- Backend base: **schema 042**.
- Backend recomendado: **schema 043**.
- Modos avançados de equipes exigem **schema 043**.
- Se seu Supabase já está em 043, não reaplique migration.
- Nenhuma migration nova nesta release; cadeia permanece `001–043`.

## Publicar no GitHub

1. Preserve somente a pasta `.git` do repositório local.
2. Remova os arquivos do projeto anterior e copie o conteúdo **de dentro desta pasta r79** para a raiz do repositório.
3. Execute `00_VERIFICAR_ANTES_DO_PUSH.bat`.
4. Faça commit e `Push origin` somente com os gates locais aprovados.
5. Aguarde **Deploy QuizRounds2 no GitHub Pages** concluir em verde.
6. Depois, se quiser homologar o navegador, abra **Actions → Homologação E2E QuizRounds2 → Run workflow**. Esse teste é separado e não derruba o deploy do Pages.
7. Abra ADM, jogador e telão e confirme o build **3.68-r79**.

Não coloque `sb_secret_` ou `service_role` no navegador. O deploy usa `SUPABASE_URL` e `SUPABASE_PUBLISHABLE_KEY` configurados no GitHub Actions.

## Validações incluídas

- `scripts/validate-sync-behavior.mjs`: **16/16** cenários.
- `scripts/validate-event-stress.mjs`: **16/16**, **10.000 cenários** e 20 transições com 100 jogadores + 1 telão.
- `scripts/validate-build.mjs`: auditoria estrutural bloqueante.
- `scripts/validate-pages.mjs`: valida o artefato de publicação.
- `scripts/validate-site-smoke.mjs`: smoke HTTP **7/7**.
- `tests/e2e/test_browser_e2e.py`: **4 cenários em Chromium real** no workflow dedicado de homologação.

O E2E usa o simulador integrado e não substitui ensaio físico de Wi‑Fi, Android/iPhone ou carga real do Supabase.

## Arquivos de homologação

- `CHANGELOG_v3.68_r79_Deploy_Estavel_Comprovado.txt`
- `VALIDATION_r79_Deploy_Estavel_Comprovado.txt`
- `FINAL_RELEASE_r79.txt`
- `BUILD_MANIFEST_SHA256.txt`

Histórico das versões anteriores permanece em `docs/history/` e não participa do runtime ativo.


## Pipeline de deploy comprovado

O GitHub Pages usa apenas o gate essencial, build/validação do artefato, upload, deploy e confirmação de propagação. Os testes pesados ficam nos workflows manuais `Homologação Técnica QuizRounds2` e `Homologação E2E QuizRounds2`, evitando que provisionamento ou testes de desenvolvimento derrubem a publicação.
