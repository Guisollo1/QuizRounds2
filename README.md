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
