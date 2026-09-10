# QuizRounds2 v3.68-r41 — Hotfix crítico da aba Configuração

Ambiente de teste independente do QuizRounds principal, preparado para GitHub Pages + segundo projeto Supabase.

## Estado da r41

- UI v3.92, tema azul.
- ADM 100vh/100dvh e largura total.
- Correção crítica do travamento ao abrir **Configuração / Montar a partida**.
- A camada de animações não entra mais em ciclo de `MutationObserver` ao alterar classes.
- Animações preservadas com reinício assíncrono sem reflow forçado.
- Login ADM e entrada do jogador permanecem protegidos.
- Relógio visível no telão.
- 31 Avatares e quatro mapas de lobby com navegação/colisão por portas, paredes e mobiliário.
- Correções de controlador ativo, pareamento de telão, sala encerrada e persistência das regras preservadas.
- Backend mínimo: Supabase schema 040; migrations 001–040. Não existe migration nova na r41.

## Publicação

Substitua o conteúdo da pasta local do repositório `QuizRounds2` por esta release completa, faça `Commit to main` e `Push origin` pelo GitHub Desktop. Não é necessário alterar o Supabase.

## Supabase de teste

Mantenha o QuizRounds2 apontando para o segundo projeto Supabase já configurado. A Publishable Key deve começar com `sb_publishable_` e Anonymous Sign-Ins deve permanecer habilitado para jogador/telão.

## Arquivos da revisão

- `CHANGELOG_v3.68_r41_Travamento_Config.txt`
- `VALIDATION_r41_Travamento_Config.txt`
- `VERSION.txt`
