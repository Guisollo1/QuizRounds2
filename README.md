# QuizRounds2 v3.68-r54 — Refatorado / Fluxo Estável

## Instalação e compatibilidade do Supabase

A r54 aceita **schema 042** para Partida Padrão e GameShow individual. Isso corrige o bloqueio global visto na r52 quando aparecia “backend incompatível — aplique migration 043”.

Para usar **Equipes com Automático equilibrado, Jogador escolhe ou ADM escolhe**, atualize o Supabase de teste para **schema 043** executando `00_ATUALIZAR_SUPABASE_PARA_SCHEMA_043.sql`. Quem já está no schema 043 não precisa executar novamente.

## Fluxo refatorado

- **Partida Padrão:** Sala → Perguntas → Regras → Ordem → Revisar → Apresentar.
- **Partida GameShow individual:** Criar (Sala + dinâmica) → Perguntas → Regras → Ordem → Revisar → Apresentar.
- **Partida GameShow por equipes:** Criar → Perguntas → Equipes → Regras → Ordem → Revisar → Apresentar.
- Nova sala começa com a fila vazia; reutilizar perguntas da partida anterior é uma opção explícita.
- A Central continua a sala no modo correto, sem jogar GameShow para o fluxo Padrão.
- Modelos GameShow preservam equipes quando o backend está no schema 043.
- O checklist bloqueia o lobby se uma mecânica especial estiver incompleta.
- O teste guiado adapta o número de jogadores virtuais ao tipo de partida.
- O runtime foi enxugado para os assets ativos da r54.

## Segurança do projeto

Use somente no repositório **QuizRounds2** e no Supabase de teste. Não aplique migrations nem estes arquivos no QuizRounds principal de produção sem uma etapa separada de homologação.

---

# QuizRounds2 v3.68-r51 — Fluxo de Perguntas Individual

## O que mudou
- A aba 2 agora é **Criar perguntas**: apenas Editor e Importação.
- O **Banco / Pesquisar e selecionar** saiu da aba 2.
- A aba 3 **Partida Padrão** agora segue: Sala → Escolher perguntas → Regras → Ordem dos rounds → Apresentação.
- A aba 4 **GameShow Pro** usa o mesmo fluxo, com banco próprio no contexto da sala Pro e ferramentas de mídia/mecânicas no passo Perguntas.
- O mesmo componente de banco é montado no contexto certo sem duplicar IDs nem criar bancos separados no Supabase.
- Sem migration nova; backend continua no schema 042.

# QuizRounds2 v3.68-r50 — Apresentação em subabas individuais

## Fluxo do ADM
- Aba 3 **Configuração**: Sala → Regras → Rounds → Apresentação.
- Aba 4 **GameShow Pro**: Sala → Regras → Rounds → Apresentação.
- Não existe mais uma aba principal separada para “Apresentação”.
- O lobby e o controle dos rounds permanecem individuais no contexto em que a sala foi montada.
- Backend: schema 042. Não há migration nova na r50.


A r49 reorganiza o GameShow Pro para repetir o fluxo Sala → Regras → Rounds da Configuração normal. A nova sala é criada já com a dinâmica principal, regras básicas e equipes escolhidas. Backend schema 042, sem migration nova.

# QuizRounds2 v3.68-r48 — ADM organizado e estável

## Estado da r48

- Release visual real: frontend, cache-bust, diagnóstico e assets ativos identificados como `3.68-r48`.
- Backend permanece no **schema 042**; não existe migration nova para esta revisão.
- ADM 100vh/full width reorganizado com zonas claras: Saúde do evento, Controle do evento, Público e classificação, Análise e diagnóstico.
- Sombras padronizadas em três níveis e raios em quatro tokens para evitar o efeito “caixa dentro de caixa”.
- Barra de status compacta sem BUILD duplicado; versão permanece no cabeçalho/diagnóstico.
- Resumo da partida não compete mais com a barra sticky.
- Pré-teste tem uma ação principal e os testes de carga ficam agrupados.
- Estado “somente leitura” do controlador é aviso, não falha crítica.
- Todos os recursos GameShow Pro e Game Modes da r47 foram preservados.

Ambiente de teste independente do QuizRounds principal, preparado para GitHub Pages + Supabase.

## O que entrou na r47

A r47 amplia o GameShow Pro da r46 com um motor de mecânicas especiais, mantendo o fluxo clássico como fallback. Estão disponíveis: **Mais Próximo Vence, Faixa de Precisão, Ordenação, Relacionar Colunas, Classificação, V/F em Série, Imagem Oculta, Zoom Misterioso, Quem Sou Eu?, Antes e Depois, Caso Técnico, Árvore de Decisão, Missão em Equipe, Bingo de Conhecimento, Roda da Sorte, Caixa Surpresa, Previsão da Sala, Enquete ao Vivo, Escolha do Público e Categoria Escolhida**.

Também foram adicionados **Categoria Aleatória**, **Dificuldade Progressiva**, **Modo Prova** e votação pública para o público escolher a próxima categoria/pergunta. O ADM possui um construtor visual de mecânicas; jogador e telão recebem interfaces específicas para cada tipo de game.

## Supabase — obrigatório

A r47 requer **schema 042**. O projeto precisa já ter a migration 041 da r46.

1. Se seu QuizRounds2 já está funcionando na r46/schema 041, abra o SQL Editor do Supabase de teste.
2. Execute `00_APLICAR_MIGRATION_042.sql`.
3. Confirme que o backend informa schema 042 / build mínimo 3.68-r47.
4. Depois publique os arquivos da r47 no GitHub.

Não execute a migration no projeto do QuizRounds original de produção.

## Comportamento das mecânicas

- Games estruturados usam respostas JSON protegidas por RPC e mantêm um espelho em `quiz_answers`, preservando contagem de respostas, ranking, histórico e dashboard.
- O gabarito das mecânicas estruturadas só é liberado após a etapa de revelação.
- A fila guarda snapshot de `game_type` e `game_spec`; editar uma pergunta depois de enfileirar não altera silenciosamente o round já preparado.
- Participantes que não estavam elegíveis no início do round não conseguem responder o game avançado.
- O Modo Prova oculta resultado/ranking na experiência de jogador e telão durante a execução.
- Roda da Sorte e Caixa Surpresa usam resultado determinístico por round e só revelam o bônus no momento correto.

## Publicação

Substitua o conteúdo da pasta local do repositório `QuizRounds2` por esta release completa, faça **Commit to main** e depois **Push origin** pelo GitHub Desktop. Aguarde o workflow do GitHub Pages ficar verde.

## Arquivos principais desta revisão

- `00_APLICAR_MIGRATION_042.sql`
- `supabase/migrations/042_game_modes_pack_v368_r47.sql`
- `CHANGELOG_v3.68_r47_GameModes_Expandido.txt`
- `VALIDATION_r47_GameModes_Expandido.txt`
- `VERSION.txt`

## Base preservada

A r47 mantém os recursos consolidados da r46: GameShow Pro, equipes, mídia por pergunta, banco profissional, importação CSV/JSON, dashboard pós-evento, áudio, modo ensaio, permissões administrativas, branding, lobby vivo e controle de apresentação. Também preserva 31 avatares, mapas com colisão/portas, tema azul, ADM 100vh, login estável, controlador autoritativo, persistência das regras e ranking sem piscadas.

## r52 — Formação de equipes em 3 modos
No GameShow Pro > Sala > Equipes, escolha: Automático equilibrado, Jogador escolhe ou ADM escolhe. No modo ADM, o painel permite selecionar ou arrastar jogadores entre os times. No modo Jogador, a escolha aparece no celular antes da prontidão. Requer migration 043.

## r53 — Fluxo simples / assistente
A r53 reorganiza a criação da partida para reduzir cliques e decisões técnicas. **Nova partida** pergunta primeiro se o evento será Padrão ou GameShow. O modo simples fica ativo por padrão e mostra apenas o que é necessário.

- **Partida Padrão:** Sala → Perguntas → Regras → Ordem → Revisar → Apresentação.
- **Partida GameShow:** Sala → Dinâmica → Perguntas → Equipes (quando necessário) → Regras → Ordem → Revisar → Apresentação.
- **Sem migration nova:** mantém o backend no schema 043. Quem já aplicou a migration 043 não precisa executar SQL novamente.

