# QuizRounds2 v3.68-r89 — Refatorado 80P · Espaço Otimizado

Release baseada na r85, mantendo a arquitetura de estabilidade 80P e a resposta do telão em uma única linha. O foco desta revisão é eliminar áreas ociosas nos cinco HTMLs publicados sem alterar o fluxo do jogo ou o backend.

## Auditoria de aproveitamento de espaço — r89

Foram auditados os cinco HTMLs publicados (`admin.html`, `admin/index.html`, `display.html`, `index.html` e `simulator.html`) e seus layouts ativos. A revisão remove trilhas de grid sem conteúdo, alturas mínimas excessivas, limites de largura que comprimiam o conteúdo útil e breakpoints que empilhavam componentes cedo demais. O telão preserva o mapa/avatares, mas entrega mais largura à pergunta e ao resultado. A regra da resposta correta continua rígida: **letra + texto permanecem na mesma linha**, com ajuste automático da fonte.

## O que foi refatorado

- `common-v3.68-r89.js` concentra utilitários compartilhados de armazenamento local, jitter e validação monotônica de `generation/state_version`.
- ADM, jogador e telão usam a mesma regra para rejeitar estados antigos.
- Foram removidas funções e estados órfãos das estratégias antigas de auto-recuperação que não participavam mais do fluxo da r83.
- A sincronização manual continua disponível, mas **Começar Quiz** não executa ACK obrigatório, não força `state_changed`, não remove canais e não reconecta aparelhos saudáveis.
- O CSS da resposta correta no telão foi consolidado para evitar camadas concorrentes.

## Resposta correta no telão

A letra da alternativa e a resposta completa permanecem **na mesma linha**, sem quebra interna. Quando o ranking ainda não está sendo exibido, o resultado ocupa toda a largura disponível; se a resposta for longa, o telão reduz a tipografia automaticamente até caber sem quebrar.

## Perfil 80P preservado

- Realtime é o caminho principal.
- Polling do jogador conectado permanece em aproximadamente 15 s com jitter.
- Heartbeat do participante permanece em aproximadamente 30 s, com trava contra RPC sobreposta.
- `state_changed` é espalhado em micro-janelas para reduzir rajadas simultâneas.
- Coalescência de `state_version` mantém o maior alvo recebido durante uma sincronização.
- Telão mantém polling de segurança e canal auxiliar isolado do canal principal.
- Presence é diagnóstica e não dispara auto-recuperação agressiva.

O dimensionamento de código ajuda a operar com 80 participantes, mas a capacidade final também depende do Wi‑Fi, dos aparelhos, da latência e do plano/configuração do Supabase. Para evento importante, faça ensaio com o maior número possível de celulares reais.

## Backend

Nenhuma migration nova. `BACKEND_SCHEMA_REQUIRED=42`; schema **043** continua recomendado e necessário para os modos avançados de equipes. Cadeia de migrations preservada em `001–043`.

`state_version = 0` no diagnóstico significa aparelho ainda inicializando. Quando o Realtime degrada, existe **fallback controlado por polling**, sem usar esse fallback para forçar reconexões de clientes saudáveis.

## Validação

Antes do push, execute `00_VERIFICAR_ANTES_DO_PUSH.bat`. Ele executa:

1. gate essencial;
2. contrato de sincronização;
3. estresse operacional;
4. refatoração estrutural;
5. auditoria final bloqueante.

A homologação pesada e o Playwright continuam separados do workflow de publicação do GitHub Pages.

## Publicação

Substitua o conteúdo do repositório pelo conteúdo **desta pasta**, mantendo apenas a pasta `.git` do repositório atual. Não copie a pasta r89 como uma subpasta do projeto.

O histórico de releases e helpers antigos permanece organizado em `docs/history/`.
