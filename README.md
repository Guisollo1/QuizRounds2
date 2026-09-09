# QuizRounds2 v3.68 — r31 TESTE · 31 Avatares + Lobby Map

Esta edição foi preparada para ser publicada em um segundo repositório GitHub Pages, recomendado como `QuizRounds2`, sem substituir o `QuizRounds` que já está funcionando.

## Isolamento aplicado nesta edição

- `localStorage`, `sessionStorage` e sessão Auth do Supabase usam namespace próprio `quiz2`, evitando compartilhar estado do navegador com `/QuizRounds/`.
- Janelas de telão e simulador usam nomes exclusivos `quiz2_*`.
- URLs internas continuam relativas, portanto QR, jogador, ADM e telão permanecem dentro de `/QuizRounds2/`.
- O workflow do GitHub Pages usa concorrência própria para o projeto de teste.
- Build ativo: `3.68-r31`; backend mínimo permanece schema `040`.

## Para isolamento total do ambiente de produção

Use um **segundo projeto Supabase** para o QuizRounds2. Configure no repositório QuizRounds2 as mesmas variáveis de Actions (`SUPABASE_URL` e `SUPABASE_PUBLISHABLE_KEY`), porém apontando para o Supabase de teste, e aplique nele as migrations `001` até `040` em ordem. Não aplique migrations experimentais no Supabase do QuizRounds principal.

---

# Base técnica herdada: QuizRounds v3.68 — r30 · 31 Avatares + Lobby Map

Esta versão parte da **r29 Hardening Completo** e incorpora a biblioteca/lógica de avatares do pacote **v3.79/r37d com 31 avatares**, preservando o backend Supabase + GitHub Pages e as correções de segurança da r29.

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
