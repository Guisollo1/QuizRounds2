# QuizRounds2 v3.68 — r39 TESTE · Animações Completas

A r39 mantém o backend/schema **040**, a recuperação de controlador da r35 e o ADM 100VH/full width da r36. Esta versão adiciona uma camada de movimento e feedback visual sem alterar migrations, contratos Supabase ou regras do quiz.

## Animações e refinamentos r39

- Lobby: entrada `pop/fade`, prontidão com check e brilho, nomes/avatares com transições e mapa vivo entre rodadas.
- Mapas: caminhada suavizada, pequena pausa ao virar, desaceleração em gargalos, passagem visual por portas e preservação das colisões com paredes/mobiliário.
- Easter egg: mascote gambá aparece ocasionalmente em pontos seguros do lobby, sem participar da colisão ou do estado da sala.
- Perguntas: entrada com `fade/slide`, alternativas escalonadas, feedback tátil/visual ao selecionar e suspense curto na revelação.
- Cronômetro: progresso contínuo com pulso discreto nos segundos finais.
- Respostas: correto/errado com feedback visual próprio e partículas leves somente em eventos positivos.
- Ranking: reordenação mais suave, Top 3 escalonado, aviso de novo líder e pódio final com celebração.
- Telão: transições entre estados, PIN/QR animados e relógio com atualização visual suave.
- ADM: troca de abas mais suave, confirmação de salvamento, status de conexão refinado e feedback imediato nos comandos do controle remoto.
- Acessibilidade/desempenho: todas as animações respeitam `prefers-reduced-motion`; efeitos são decorativos e não bloqueiam comandos, Realtime ou navegação.
- Sem migration nova: Supabase permanece em `001–040`, schema mínimo `040`.

---

# QuizRounds2 v3.68 — r36 TESTE · ADM 100VH + Full Width

A r35 corrige três falhas operacionais observadas no ambiente de teste sem alterar o schema do Supabase. O backend mínimo continua **040**, portanto esta atualização pode ser publicada somente pelo GitHub quando o Supabase do QuizRounds2 já está nas migrations `001–040`.

## Correções r35

- **Nova sala:** o ADM identifica a sala ativa real e recupera/assume o controle antes de criar a próxima partida, evitando o erro “Este dispositivo não é o controlador ativo da sala”.
- **Sala lembrada:** ao iniciar o ADM, uma sala ativa tem prioridade sobre uma sala encerrada apenas lembrada no navegador.
- **Telão:** uma sala finalizada é bloqueada antes de abrir a janela; o ADM orienta criar uma nova sala em vez de gerar o erro “A sala já foi encerrada”.
- **Pareamento do telão:** o lease do controlador é renovado antes de gerar a autorização temporária.
- **Regras:** checkboxes e campos em edição não são mais reescritos pelo polling/Realtime.
- **Autosave:** alterações nas regras são salvas automaticamente no lobby, com proteção contra mudanças feitas durante um salvamento em andamento.
- **Lease expirado:** ações normais tentam renovar o controle automaticamente; um controlador realmente ativo em outro painel continua protegido.
- **Sem migration nova:** Supabase continua `001–040`, schema mínimo `040`.
- Mantidos **tema azul**, **relógio no telão**, **31 avatares** e **colisões auditadas dos quatro mapas**.

---

# QuizRounds2 v3.68 — r34 TESTE · Relógio no Telão + Refinamento Visual

A r34 mantém o backend/schema 040 e toda a lógica funcional da r33, adicionando uma camada visual segura. O telão agora exibe um relógio grande e permanente no cabeçalho durante a apresentação.

## Alterações visuais r34

- Relógio digital `HH:MM:SS` no telão, com dia/data e adaptação para resoluções menores.
- Lobby com PIN/QR mais destacados, superfícies com maior contraste e melhor leitura a distância.
- Transições mais suaves entre lobby, pergunta, resultado e ranking.
- Ranking e pódio final com maior profundidade visual e hierarquia do Top 3.
- Seletor de 31 avatares com filtros: Todos, Ciência, Jalecos, Macacões, Proteção, Social e Especiais.
- Preview do avatar selecionado ampliado sem aumentar os arquivos de sprite.
- Jogador mobile com botão de prontidão mais acessível e fixado na área inferior do lobby.
- ADM harmonizado com cards, abas, estados e botões em azul consistente.
- Simulador alinhado ao mesmo sistema visual do telão.
- Mapa do lobby preserva colisões/portas da r33 e recebe somente acabamento de profundidade/sombra.
- Nenhuma migration nova: Supabase permanece `001–040`, schema mínimo `040`.

---

# QuizRounds2 v3.68 — r33 TESTE · Tema Azul + 31 Avatares + Lobby Map

Esta edição mantém integralmente as colisões auditadas da r32 e troca o tema visual principal roxo por **azul** no jogador, ADM, telão e simulador. O identificador interno `violet` foi preservado apenas por compatibilidade com salas/configurações já gravadas, mas agora renderiza a paleta azul.

## Alteração r33 — tema azul

- Fundo principal do jogador e do telão alterado de roxo para azul.
- Cabeçalhos, botões, badges, foco e superfícies temáticas principais foram harmonizados com a paleta azul.
- ADM e simulador receberam a mesma identidade azul.
- A opção antiga `Violeta` passa a aparecer como `Azul`, preservando o valor interno para não quebrar dados já salvos.
- Os quatro mapas e o motor de colisões/portas da r32 foram mantidos sem regressão.
- Build ativo: `3.68-r33`; backend mínimo continua schema `040`.

---

# QuizRounds2 v3.68 — r32 TESTE · 31 Avatares + Lobby Map · Colisão Auditada

Esta edição foi preparada para ser publicada em um segundo repositório GitHub Pages, recomendado como `QuizRounds2`, sem substituir o `QuizRounds` que já está funcionando.

## Isolamento aplicado nesta edição

- `localStorage`, `sessionStorage` e sessão Auth do Supabase usam namespace próprio `quiz2`, evitando compartilhar estado do navegador com `/QuizRounds/`.
- Janelas de telão e simulador usam nomes exclusivos `quiz2_*`.
- URLs internas continuam relativas, portanto QR, jogador, ADM e telão permanecem dentro de `/QuizRounds2/`.
- O workflow do GitHub Pages usa concorrência própria para o projeto de teste.
- Build ativo: `3.68-r32`; backend mínimo permanece schema `040`.


## Correção r32 — colisão e navegação dos mapas do lobby

- Os quatro mapas (`Escritório`, `Laboratório`, `Indústria` e `Plataforma`) foram auditados individualmente.
- A malha de navegação foi redesenhada sobre piso, corredores e passarelas visíveis.
- Transições entre ambientes usam somente portas ou aberturas mapeadas.
- Foram removidas rotas que atravessavam mesas, bancadas, cubículos, máquinas, camas, armários, caixas e paredes.
- Pontos de porta e gargalos não recebem dispersão lateral de avatar.
- A dispersão dos demais nós foi reduzida para impedir que o corpo do personagem invada mobiliário em corredores estreitos.
- O telão e o simulador usam o mesmo motor `city-v3.68-r32.js`, evitando comportamento diferente entre teste local e GitHub Pages.

## Para isolamento total do ambiente de produção

Use um **segundo projeto Supabase** para o QuizRounds2. Configure no repositório QuizRounds2 as mesmas variáveis de Actions (`SUPABASE_URL` e `SUPABASE_PUBLISHABLE_KEY`), porém apontando para o Supabase de teste, e aplique nele as migrations `001` até `040` em ordem. Não aplique migrations experimentais no Supabase do QuizRounds principal.

---

# Base técnica herdada: QuizRounds v3.68 — r30 · 31 Avatares + Lobby Map

Esta versão parte da **r29 Hardening Completo** e incorpora a biblioteca/lógica de avatares do pacote **v3.79/r39d com 31 avatares**, preservando o backend Supabase + GitHub Pages e as correções de segurança da r29.

## O que mudou na r30

- O jogador pode escolher entre **31 avatares** antes de entrar na sala.
- Todos os 31 possuem preview próprio e sprite-sheet 4×4 para animação em **baixo, esquerda, direita e cima**.
- O avatar escolhido é persistido no Supabase e usado no **mapa do lobby**, ranking, identidade do jogador e lista do ADM.
- O mapa do lobby continua usando a lógica estável de navegação/colisão da base r29; apenas o runtime/catálogo de personagens foi expandido.
- Chaves antigas continuam compatíveis e são normalizadas para os personagens correspondentes.
- O seletor usa 4 colunas no desktop, 3 no mobile e 2 em telas muito estreitas, sem exibir nomes de profissão nos cards.
- O hardening da r29 permanece: pareamento seguro do telão, privacidade de estado/placar, lease do ADM, elegibilidade por round, backoff/jitter e proteção da logo.

## Atualização do Supabase

Se seu backend já está na r29/schema 39, aplique apenas:

`040_avatar_catalog_31_v368_r30.sql`

Se ainda estiver na r28 ou anterior, aplique primeiro a migration 039 e depois a 040, em ordem. O frontend r30 exige **schema 40** para garantir que todos os 31 avatares sejam realmente gravados e reapareçam no mapa.

## Publicação no GitHub Pages

Depois de atualizar o Supabase, publique os arquivos da r30 no GitHub. O workflow continua executando `scripts/validate-build.mjs` antes do deploy.

## Estabilidade

A **r26 continua sendo o rollback homologado**. A r30 mantém as correções da r29 e adiciona somente a camada de catálogo/runtime/persistência necessária para os 31 avatares.


## r36 — ADM 100vh / largura total
O painel `admin.html` passa a ocupar toda a largura disponível e no mínimo 100% da altura do viewport (100dvh com fallback 100vh). Abas, workspace, grids e cabeçalho não possuem max-width centralizador. Conteúdo extenso preserva rolagem natural. Backend e migrations permanecem no schema 040.


## r39 — Hotfix de login e campos de entrada
- Inputs do ADM e do jogador ficam acima de todas as camadas decorativas.
- Overlays, pseudo-elementos e animações não participam do hit-testing.
- Controles editáveis foram excluídos do micro-feedback global de pressão.
- Mantidas as animações r37 após a entrada, o ADM 100dvh/full-width, o tema azul e o schema 040.


## r39 — Hotfix de interação
O login ADM e a entrada do jogador não carregam a camada de animação antes da autenticação/entrada. As animações são ativadas somente depois que a área interativa crítica deixa de estar em uso. Isso restaura foco, digitação, clique/toque e submissão nativa dos formulários sem alterar o schema Supabase 040.
