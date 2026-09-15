# QuizRounds2 v3.68-r81 — Início sem reconexão forçada

A r81 corrige o bloqueio observado ao iniciar a partida: jogadores já presentes no mapa não são mais forçados a uma nova sincronização/reconexão antes do primeiro round.

## Correção principal

- **Iniciar Quiz** usa somente uma checagem passiva do estado já publicado.
- O início não envia `state_changed`, não executa `connection_test`, não chama `recoverEventSync()` e não recria canais Realtime.
- A recuperação ativa permanece disponível exclusivamente em **Sincronizar aparelhos** e no watchdog quando existe falha real.
- Builds diferentes continuam bloqueando o início.
- No **Modo Evento**, Realtime e telão continuam obrigatórios.
- Fora do Modo Evento, o fallback controlado por polling permanece disponível.
- Alertas passivos de convergência/heartbeat não impedem o primeiro `admin_start_quiz`; os aparelhos convergem quando ocorre a mudança real de estado da partida.
- `state_version = 0` continua significando aparelho ainda inicializando no diagnóstico.
- Clique repetido em **Começar Quiz** continua coalescido para impedir dois inícios concorrentes.

## Backend

- Nenhuma migration nova.
- `BACKEND_SCHEMA_REQUIRED=42`.
- Schema 043 continua recomendado e necessário para os recursos avançados de equipes.
- Cadeia Supabase preservada em `001–043`.

## Publicação

Execute `00_VERIFICAR_ANTES_DO_PUSH.bat` antes de publicar. Depois do deploy, confirme que ADM, telão e jogadores carregaram `3.68-r81`.

## Histórico

Documentação histórica e helpers antigos permanecem em `docs/history/`, fora do runtime ativo.
