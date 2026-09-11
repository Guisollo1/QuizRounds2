# QuizRounds2 v3.68-r43 — Estabilidade Visual Completa

Ambiente de teste independente do QuizRounds principal, preparado para GitHub Pages + segundo projeto Supabase.

## Estado da r43

- UI v3.92, tema azul, 31 Avatares e quatro mapas.
- ADM 100vh/100dvh e largura total.
- Jogador com resultado game-show, progresso da partida, pontos animados e feedback de ranking pessoal.
- Telão com tela cheia, relógio configurável, pódio 3º → 2º → 1º e diagnóstico técnico discreto.
- Lobby com guias opcionais de portas/passagens, sombra e caminhada mais natural dos avatares.
- ADM com barra de saúde/status fixa, atalhos de configuração, salvamento inline e diagnóstico resumido.
- Efeitos visuais reduzem automaticamente em alta densidade e `prefers-reduced-motion` é respeitado.
- Correções críticas de login, controlador, regras e travamento por MutationObserver permanecem preservadas.
- Backend mínimo: Supabase schema 040; migrations 001–040. Não existe migration nova na r43.

## Publicação

Substitua o conteúdo da pasta local do repositório `QuizRounds2` por esta release completa, faça `Commit to main` e `Push origin` pelo GitHub Desktop. Não é necessário alterar o Supabase.

## Supabase de teste

Mantenha o QuizRounds2 apontando para o segundo projeto Supabase já configurado. A Publishable Key deve começar com `sb_publishable_` e Anonymous Sign-Ins deve permanecer habilitado para jogador/telão.

## Arquivos da revisão

- `CHANGELOG_v3.68_r43_Estabilidade_Visual_Completa.txt`
- `VALIDATION_r43_Estabilidade_Visual_Completa.txt`
- `VERSION.txt`

---

# QuizRounds2 v3.68-r42 — Jogador com resposta revelada mais bonita

Ambiente de teste independente do QuizRounds principal, preparado para GitHub Pages + segundo projeto Supabase.

## Estado da r42

- UI v3.92, tema azul.
- ADM 100vh/100dvh e largura total.
- Correção crítica do travamento ao abrir **Configuração / Montar a partida**.
- A camada de animações não entra mais em ciclo de `MutationObserver` ao alterar classes.
- Animações preservadas com reinício assíncrono sem reflow forçado.
- Login ADM e entrada do jogador permanecem protegidos.
- Relógio visível no telão.
- 31 Avatares e quatro mapas de lobby com navegação/colisão por portas, paredes e mobiliário.
- Correções de controlador ativo, pareamento de telão, sala encerrada e persistência das regras preservadas.

- Tela do jogador com resposta revelada redesenhada: gabarito em destaque, sua resposta, pontos, posição, tempo e distribuição com visual mais animado.
- Backend mínimo: Supabase schema 040; migrations 001–040. Não existe migration nova na r41.

## Publicação

Substitua o conteúdo da pasta local do repositório `QuizRounds2` por esta release completa, faça `Commit to main` e `Push origin` pelo GitHub Desktop. Não é necessário alterar o Supabase. Para publicar a melhoria do jogador, substitua também os novos arquivos da pasta `assets/js` e `assets/css`.

## Supabase de teste

Mantenha o QuizRounds2 apontando para o segundo projeto Supabase já configurado. A Publishable Key deve começar com `sb_publishable_` e Anonymous Sign-Ins deve permanecer habilitado para jogador/telão.

## Arquivos da revisão

- `CHANGELOG_v3.68_r41_Travamento_Config.txt`
- `VALIDATION_r41_Travamento_Config.txt`
- `VERSION.txt`
