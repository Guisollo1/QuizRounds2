# QuizRounds2 v3.68-r80 — Sincronização Sem Bloqueio Falso

A r80 corrige o bloqueio de início observado na r79 sem relaxar a proteção de sincronização real.

## Correção principal

- Verificações simultâneas de início reutilizam a mesma execução; o ADM não retorna mais “verificação de sincronização já está em andamento” como erro bloqueante.
- Testes de ACK simultâneos também são coalescidos; um teste não cancela outro que já está em andamento.
- Se um ACK de teste não chegar, o aparelho pode ser confirmado pela Presence do Supabase somente quando ela estiver **recente** e mostrar exatamente o mesmo `build`, `generation` e `state_version` do ADM.
- ACK divergente, build diferente, heartbeat vencido, `state_version` atrás/à frente ou aparelho inicializando continuam bloqueando.
- Cliques repetidos em **Começar Quiz** reutilizam a tentativa atual e não disparam dois inícios concorrentes.

## Deploy e homologação

- O workflow de GitHub Pages permanece no pipeline simples e comprovado: gate essencial, build, validação do `_site`, upload, deploy e confirmação de propagação.
- Homologação técnica pesada permanece em `.github/workflows/quality.yml`.
- Playwright/Chromium permanece em `.github/workflows/e2e.yml`.

## Backend

- Nenhuma migration nova.
- `BACKEND_SCHEMA_REQUIRED=42`.
- Schema 043 continua recomendado e necessário para as funções avançadas de equipes.
- Cadeia Supabase preservada em `001–043`.

## Antes do evento

Execute `00_VERIFICAR_ANTES_DO_PUSH.bat` antes de publicar. Depois do deploy, confirme que ADM, telão e jogadores carregaram `3.68-r80`.

## Diagnóstico de sincronização

- `state_version = 0` significa que o aparelho ainda está inicializando e não deve ser considerado sincronizado.
- Fora do Modo Evento, existe fallback controlado por polling quando o Realtime estiver temporariamente indisponível e o Supabase/RPC continuar respondendo.
- Documentação histórica e helpers antigos ficam organizados em `docs/history/` e não fazem parte do runtime ativo.
