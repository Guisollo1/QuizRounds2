# QuizRounds2 v3.68-r40 — Auditoria Profunda / Base Estável

Ambiente de teste independente do QuizRounds principal, preparado para GitHub Pages + Supabase de teste. Esta revisão prioriza estabilidade de login/entrada e mantém as funções já homologadas nas revisões anteriores.

## Estado da r40

- UI v3.92, tema azul.
- ADM 100vh/100dvh e largura total.
- Login ADM e entrada do jogador com controles explícitos e sem animações pré-autenticação.
- Relógio visível no telão.
- 31 Avatares e quatro mapas de lobby com malha de navegação/colisão por portas e corredores.
- Correções de controlador ativo, pareamento de telão, sala encerrada e persistência das regras preservadas.
- Animações avançadas carregadas somente após autenticação/entrada nas telas críticas.
- Backend mínimo: Supabase schema 040; migrations 001–040. Não existe migration nova na r40.

## Correções estruturais da auditoria

- A sessão Auth do navegador usa chave estável por escopo, evitando criar uma sessão diferente a cada release.
- Há migração automática das chaves de sessão das versões recentes.
- Login e entrada não dependem de submit de formulário; clique e Enter são tratados explicitamente.
- Camadas decorativas do pré-login/pré-entrada não recebem eventos de ponteiro.
- Existe uma proteção crítica inline nos campos de login/entrada para sobreviver a CSS antigo em cache.
- O endereço `/admin` possui alias para o `admin.html` r40 com cache-bust.
- Workflow, build ID, cache-bust e metadados estão alinhados na r40.
- O validador do GitHub Actions bloqueia deploy se houver referência ausente, erro de sintaxe, versão incompatível ou configuração insegura.

## Supabase de teste

Para isolamento total, use um **segundo projeto Supabase** para o QuizRounds2. No repositório `QuizRounds2`, configure `SUPABASE_URL` e `SUPABASE_PUBLISHABLE_KEY` apontando para esse segundo projeto Supabase. A Publishable Key deve começar com `sb_publishable_`.

Em um Supabase novo, aplique as migrations `001` até `040` em ordem e execute `supabase/ADMIN_BOOTSTRAP.sql` para autorizar o administrador. O login anônimo deve permanecer habilitado para jogador/telão conforme a arquitetura atual.

## Publicação

Publique o conteúdo completo desta pasta na raiz do repositório `QuizRounds2` usando GitHub Desktop. Faça commit na branch `main` e `Push origin`. O workflow `.github/workflows/pages.yml` valida e publica o site automaticamente.

Evite substituir somente parte dos arquivos ativos de uma release, pois HTML, CSS e JS usam cache-bust por versão e um commit misto pode carregar runtime incompatível.

## Arquivos de auditoria

- `AUDITORIA_PROFUNDA_v3.68_r40.txt`
- `VALIDATION_r40_Auditoria_Profunda.txt`
- `CHANGELOG_v3.68_r40_Auditoria_Profunda.txt`
- `BUILD_MANIFEST_SHA256.txt`
