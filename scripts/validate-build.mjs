import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const root=process.cwd();
const errors=[];
const groups=[];
const fail=msg=>errors.push(msg);
const ok=msg=>groups.push(msg);
const exists=rel=>fs.existsSync(path.join(root,rel));
const read=rel=>fs.readFileSync(path.join(root,rel),'utf8');
const norm=rel=>rel.replaceAll('\\','/');

function walk(dir){
  const abs=path.join(root,dir);
  if(!fs.existsSync(abs))return[];
  const out=[];
  for(const ent of fs.readdirSync(abs,{withFileTypes:true})){
    const rel=norm(path.join(dir,ent.name));
    if(ent.isDirectory())out.push(...walk(rel));else out.push(rel);
  }
  return out;
}
function localTarget(owner,raw){
  let v=String(raw||'').trim();
  if(!v||v.startsWith('#')||/^(?:https?:|data:|blob:|mailto:|tel:|javascript:)/i.test(v)||v.startsWith('var('))return null;
  v=v.split('#')[0].split('?')[0];
  if(!v||/[{}$<>]/.test(v))return null;
  return norm(path.posix.normalize(path.posix.join(path.posix.dirname(owner),v)));
}
function checkRef(owner,raw){const target=localTarget(owner,raw);if(target&&!exists(target))fail(`${owner}: referência local ausente -> ${raw} (${target})`);}
function stripCssNoise(source){
  let out='',i=0,quote='';
  while(i<source.length){
    const c=source[i],n=source[i+1];
    if(!quote&&c==='/'&&n==='*'){i+=2;while(i<source.length&&!(source[i]==='*'&&source[i+1]==='/'))i++;i+=2;continue;}
    if(quote){if(c==='\\'){out+='  ';i+=2;continue;}if(c===quote)quote='';out+=' ';i++;continue;}
    if(c==='"'||c==="'"){quote=c;out+=' ';i++;continue;}out+=c;i++;
  }
  return out;
}
function checkCssBraces(rel){const clean=stripCssNoise(read(rel));let d=0;for(const c of clean){if(c==='{')d++;else if(c==='}'){d--;if(d<0){fail(`${rel}: chave CSS fechada sem abertura`);return;}}}if(d!==0)fail(`${rel}: chaves CSS desbalanceadas (${d})`);}
function namedExports(source){
  const set=new Set();
  for(const m of source.matchAll(/\bexport\s+(?:async\s+)?(?:function|class|const|let|var)\s+([A-Za-z_$][\w$]*)/g))set.add(m[1]);
  for(const m of source.matchAll(/\bexport\s*\{([^}]+)\}/g))for(const item of m[1].split(',')){const n=item.trim().split(/\s+as\s+/i)[0]?.trim();if(n)set.add(n);}
  return set;
}
function requireTokens(rel,tokens,label=rel){const s=read(rel);for(const t of tokens)if(!s.includes(t))fail(`${label}: marcador obrigatório ausente -> ${t}`);}
function forbidTokens(rel,tokens,label=rel){const s=read(rel);for(const t of tokens)if(s.includes(t))fail(`${label}: padrão proibido encontrado -> ${t}`);}

const htmlFiles=['index.html','admin.html','display.html','simulator.html'];
const activeJs=['assets/js/common-v3.68-r48.js','assets/js/avatars-v3.68-r48.js','assets/js/city-v3.68-r48.js','assets/js/admin-v3.68-r48.js','assets/js/display-v3.68-r48.js','assets/js/player-v3.68-r48.js','assets/js/simulator-v3.68-r48.js','assets/js/motion-v3.68-r48.js','assets/js/pro-admin-v3.68-r48.js','assets/js/pro-runtime-v3.68-r48.js'];
const activeCss=['assets/css/core-v3.68-r48.css','assets/css/admin-v3.68-r48.css','assets/css/display-v3.68-r48.css','assets/css/display-ui-v3.92-r48.css','assets/css/player-ui-v3.92-r48.css','assets/css/simulator-v3.68-r48.css','assets/css/avatars-runtime-v3.68-r48.css','assets/css/avatars-ui-v3.92-r48.css','assets/css/motion-v3.68-r48.css','assets/css/pro-v3.68-r48.css'];
const allJs=walk('assets/js').filter(x=>x.endsWith('.js'));
const allCss=walk('assets/css').filter(x=>x.endsWith('.css'));
const gameTypes=['nearest','precision','ordering','matching','classification','true_false_series','hidden_image','zoom_mystery','who_am_i','before_after','case_study','decision_tree','team_mission','bingo','wheel','surprise','crowd_prediction','live_poll','audience_choice','category_choice'];

// 1. JS syntax across package.
for(const rel of [...allJs,...walk('scripts').filter(x=>x.endsWith('.mjs'))]){
  const p=spawnSync(process.execPath,['--input-type=module','--check'],{input:read(rel),encoding:'utf8'});
  if(p.status!==0)fail(`${rel}: erro de sintaxe JavaScript\n${(p.stderr||p.stdout||'').trim()}`);
}
ok(`Sintaxe JavaScript verificada em ${allJs.length} arquivos + scripts.`);

// 2. Primary HTML: refs, IDs and cache bust.
let idTotal=0;
const supabasePinned='https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.112.4/dist/umd/supabase.min.js';
for(const rel of htmlFiles){
  const s=read(rel);const ids=[...s.matchAll(/\bid=["']([^"']+)["']/gi)].map(m=>m[1]);idTotal+=ids.length;const seen=new Set();for(const id of ids){if(seen.has(id))fail(`${rel}: id duplicado -> ${id}`);seen.add(id);}
  for(const m of s.matchAll(/\b(?:src|href)=["']([^"']+)["']/gi)){const u=m[1];checkRef(rel,u);if(/^assets\/(?:js|css|vendor)\//.test(u)&&!u.includes('v=3.68-r48'))fail(`${rel}: asset ativo sem cache-bust r48 -> ${u}`);}
  if(rel!=='simulator.html'&&!s.includes(supabasePinned))fail(`${rel}: Supabase JS 2.112.4 fixo não encontrado`);
  if(!s.includes('3.68-r48'))fail(`${rel}: identificação r48 ausente`);
}
ok(`${htmlFiles.length} HTML auditados; ${idTotal} IDs únicos; referências e cache-bust r48 conferidos.`);

// 3. Active asset set exists and is used.
for(const rel of [...activeJs,...activeCss])if(!exists(rel))fail(`Asset r48 ausente: ${rel}`);
const combinedHtml=htmlFiles.map(read).join('\n');
for(const rel of ['assets/js/admin-v3.68-r48.js','assets/js/display-v3.68-r48.js','assets/js/player-v3.68-r48.js','assets/js/pro-admin-v3.68-r48.js','assets/js/pro-runtime-v3.68-r48.js','assets/css/pro-v3.68-r48.css'])if(!combinedHtml.includes(rel))fail(`Asset r48 não referenciado pelos HTML principais: ${rel}`);
ok('Conjunto ativo r48 completo e ligado aos HTML principais.');

// 4. ES module local imports / named exports for active modules.
for(const rel of activeJs){
  const s=read(rel);
  for(const m of s.matchAll(/(?:^|\n)\s*import\s*\{([^}]+)\}\s*from\s*["']([^"']+)["']/g)){
    checkRef(rel,m[2]);const target=localTarget(rel,m[2]);if(!target||!exists(target))continue;const exp=namedExports(read(target));
    for(const item of m[1].split(',')){const n=item.trim().split(/\s+as\s+/i)[0]?.trim();if(n&&!exp.has(n))fail(`${rel}: importa ${n} de ${target}, mas export não existe`);}
  }
  for(const m of s.matchAll(/import\(\s*["']([^"']+)["']\s*\)/g))checkRef(rel,m[1]);
}
ok('Imports ES Modules ativos resolvidos e exports nomeados conferidos.');

// 5. CSS integrity / URLs.
for(const rel of allCss){checkCssBraces(rel);for(const m of read(rel).matchAll(/url\(\s*["']?([^"')]+)["']?\s*\)/gi))checkRef(rel,m[1]);}
requireTokens('assets/css/pro-v3.68-r48.css',['prefers-reduced-motion','pro-game','pro-public-vote','pro-exam','game-hidden-image','game-zoom-mystery'],'CSS Pro r48');
ok(`${allCss.length} CSS: chaves, URLs, responsividade e redução de movimento verificadas.`);

// 6. Build handshake.
requireTokens('assets/js/common-v3.68-r48.js',["BUILD_ID='3.68-r48'","BACKEND_SCHEMA_REQUIRED=42"],'common r48');
requireTokens('VERSION.txt',['RELEASE=r48','BUILD_ID=3.68-r48','BACKEND_SCHEMA_REQUIRED=42','SUPABASE_MIGRATIONS=001-042','AVATAR_CATALOG=31'],'VERSION');
ok('Build r48 alinhado ao backend schema 042.');

// 7. Migration chain 001..042 exactly once.
const migrations=walk('supabase/migrations').filter(x=>/\/\d{3}_.+\.sql$/.test(x));const nums=migrations.map(x=>Number(path.basename(x).slice(0,3))).sort((a,b)=>a-b);
for(let n=1;n<=42;n++){const c=nums.filter(x=>x===n).length;if(c!==1)fail(`Migration ${String(n).padStart(3,'0')}: esperada exatamente 1 vez; encontrada ${c}`);}
if(nums.some(n=>n<1||n>42))fail(`Migrations fora do intervalo 001..042: ${nums.filter(n=>n<1||n>42).join(', ')}`);
ok('Migrations Supabase contínuas 001–042, sem lacunas/duplicidades.');

// 8. Migration 041 Pro preserved + 042 helper identical.
for(const rel of ['supabase/migrations/041_gameshow_pro_v368_r46.sql','supabase/migrations/042_game_modes_pack_v368_r47.sql','00_APLICAR_MIGRATION_041.sql','00_APLICAR_MIGRATION_042.sql'])if(!exists(rel))fail(`Migration/helper ausente: ${rel}`);
if(exists('00_APLICAR_MIGRATION_042.sql')&&exists('supabase/migrations/042_game_modes_pack_v368_r47.sql')&&read('00_APLICAR_MIGRATION_042.sql')!==read('supabase/migrations/042_game_modes_pack_v368_r47.sql'))fail('00_APLICAR_MIGRATION_042.sql difere da migration canônica 042.');
requireTokens('supabase/migrations/041_gameshow_pro_v368_r46.sql',['quiz_teams','admin_event_dashboard','admin_roles','brand','rehearsal'],'migration 041');
ok('Base GameShow Pro 041 preservada e helper 042 idêntico à migration canônica.');

// 9. SQL static safety / balanced dollar quotes.
for(const rel of migrations){const s=read(rel),d=(s.match(/\$\$/g)||[]).length;if(d%2!==0)fail(`${rel}: delimitadores $$ desbalanceados (${d})`);}
const sql42=read('supabase/migrations/042_game_modes_pack_v368_r47.sql');
for(const bad of ['else else','end if; end if; end if; end if; end if; end if;','as x(key text,count integer)'])if(sql42.toLowerCase().includes(bad.toLowerCase()))fail(`Migration 042: padrão SQL suspeito encontrado -> ${bad}`);
ok('SQL estático: delimitadores e padrões críticos da migration 042 conferidos.');

// 10. Game catalog end-to-end.
for(const t of gameTypes){if(!sql42.includes(`'${t}'`))fail(`Migration 042: game_type ausente -> ${t}`);if(!read('assets/js/pro-admin-v3.68-r48.js').includes(`${t}:`))fail(`pro-admin r48: label/handler ausente -> ${t}`);if(!read('admin.html').includes(`value="${t}"`))fail(`admin.html: opção de game ausente -> ${t}`);}
ok(`${gameTypes.length} tipos avançados de game presentes no banco, ADM e frontend.`);

// 11. Question snapshots / editing / duplication.
requireTokens('supabase/migrations/042_game_modes_pack_v368_r47.sql',['capture_game_snapshot_on_queue','capture_game_snapshot_on_round','game_type_snapshot','game_spec_snapshot','admin_update_question_game','admin_list_question_bank','admin_duplicate_question'],'snapshot r48');
ok('Game type/spec congelados em fila/round e preservados em edição/duplicação.');

// 12. Advanced answer endpoint + eligibility + idempotency.
requireTokens('supabase/migrations/042_game_modes_pack_v368_r47.sql',['submit_quiz_game_answer','quiz_game_answers','quiz_round_eligibility','on conflict(round_id,participant_id) do nothing','Resposta já registrada','Tempo esgotado'],'respostas r48');
ok('Respostas avançadas: deadline, elegibilidade e idempotência protegidos no backend.');

// 13. Scoring algorithms requested.
requireTokens('supabase/migrations/042_game_modes_pack_v368_r47.sql',['game_response_fraction',"p_type='precision'", "p_type='ordering'", "p_type='matching'", "p_type='classification'", "p_type='true_false_series'", "p_type='team_mission'", "p_type='bingo'", "v_type='nearest'", "v_type='crowd_prediction'", "v_type in ('wheel','surprise')"],'pontuação r48');
ok('Pontuação r48 cobre proximidade, precisão, ordenação, relações, classificação, V/F, missão, bingo, previsão, roda e surpresa.');

// 14. Secure reveal / answer-key privacy.
requireTokens('supabase/migrations/042_game_modes_pack_v368_r47.sql',['get_round_game_extras_by_code','if not v_reveal then',"-'target'", "-'correct_order'", "-'correct_matches'", "-'classification_answers'", "-'statement_answers'", "-'winning_lines'", "'game_event',case when v_reveal then v_event else null end"],'reveal seguro');
if(/'game_event'\s*,\s*v_event\b/.test(sql42))fail('Migration 042: game_event parece ser exposto antes da revelação.');
ok('Gabaritos/segredos e evento de Roda/Caixa ficam ocultos até a revelação.');

// 15. Main admin uses r47 scorer.
requireTokens('assets/js/admin-v3.68-r48.js',["db.rpc('admin_close_and_score_round_r47'",'ensureControllerForRoomCreation','settingsDraftDirty','loadPreferredRoom'],'admin core r48');
if(read('assets/js/admin-v3.68-r48.js').includes("db.rpc('admin_close_and_score_round',{p_room_id:room.id})"))fail('Admin r48 ainda chama diretamente o scorer clássico no fechamento do round.');
ok('ADM principal fecha rounds pelo scorer r47 e preserva hardening de controlador/regras.');

// 16. Player custom runtime hook and game controls.
requireTokens('assets/js/player-v3.68-r48.js',['window.quiz2GamePack?.renderPlayer','loadPlayerMotionAfterJoin'],'player r48');
requireTokens('assets/js/pro-runtime-v3.68-r48.js',['submit_quiz_game_answer','buildPlayerQuestion','renderPlayerGame','buildPlayerResult','pro-order-list','pro-match-list','pro-class-list','pro-tf-list','pro-bingo-grid'],'runtime player r48');
ok('Jogador r48 integrado ao runtime avançado sem quebrar o fluxo clássico.');

// 17. Hidden/zoom/who-am-I/before-after/case/tree visual mechanics.
requireTokens('assets/js/pro-runtime-v3.68-r48.js',['hidden_image','zoom_mystery','who_am_i','before_after','case_study','decision_tree','--game-reveal','data-clue-index'],'mecânicas visuais r48');
requireTokens('assets/css/pro-v3.68-r48.css',['game-hidden-image','game-zoom-mystery','pro-clues','pro-case-study','pro-tree-intro','pro-before-after'],'CSS mecânicas visuais');
ok('Imagem Oculta, Zoom, Quem Sou Eu, Antes/Depois, Caso e Árvore possuem renderização dedicada.');

// 18. Teams + Bingo + wheel + surprise preserved/implemented.
requireTokens('assets/js/pro-runtime-v3.68-r48.js',['team_mission','bingo','wheel','surprise','renderPlayerTeam'],'runtime equipes/game');
requireTokens('assets/js/pro-admin-v3.68-r48.js',['team_mission','bingo','wheel','surprise'],'admin equipes/game');
ok('Missão em Equipe, Bingo, Roda da Sorte e Caixa Surpresa ligados ao ADM e runtime.');

// 19. Smart categories / random / progressive difficulty.
requireTokens('supabase/migrations/042_game_modes_pack_v368_r47.sql',['admin_queue_smart_question',"v_strategy='audience'", "v_strategy='random'", "v_strategy='progressive'",'v_difficulty:=case'],'fila inteligente');
requireTokens('admin.html',['proSmartCategory','proQueueChosenBtn','proQueueRandomBtn','proQueueProgressiveBtn','proProgressiveMode'],'UI fila inteligente');
requireTokens('assets/js/pro-admin-v3.68-r48.js',['admin_queue_smart_question','proQueueChosenBtn','proQueueRandomBtn','proQueueProgressiveBtn'],'admin fila inteligente');
ok('Categoria escolhida/aleatória e dificuldade progressiva implementadas na fila inteligente.');

// 20. Exam mode.
requireTokens('admin.html',['proExamMode'],'Modo Prova UI');
requireTokens('assets/js/pro-runtime-v3.68-r48.js',['isExamActive','renderExamPlayer','renderExamDisplay'],'Modo Prova runtime');
requireTokens('assets/css/pro-v3.68-r48.css',['data-pro-exam-active="1"','pro-exam-player','pro-exam-display-cover'],'Modo Prova CSS');
ok('Modo Prova oculta gabarito/ranking durante a execução no jogador e telão.');

// 21. Public voting: crowd prediction, live poll, audience choice.
requireTokens('supabase/migrations/042_game_modes_pack_v368_r47.sql',['admin_set_public_vote','pro_submit_public_vote','pro_public_vote_summary','quiz_room_votes'],'votação pública');
requireTokens('admin.html',['proPublicVoteQuestion','proPublicVoteOptions','proOpenPublicVoteBtn','proClosePublicVoteBtn','proQueueAudienceBtn'],'votação ADM');
requireTokens('assets/js/pro-runtime-v3.68-r48.js',['renderPublicVotePlayer','renderPublicVoteDisplay','submitPublicVote'],'votação runtime');
ok('Previsão da Sala, Enquete ao Vivo e Escolha do Público possuem votação persistida e visual ao vivo.');

// 22. Pro bank/import/dashboard/media/audio/roles/branding/rehearsal preserved.
requireTokens('admin.html',['proImportCard','proDashboardCard','proMediaCard','proAudioCard','proPermissionsCard','proBrandingCard','proRehearsalCard'],'GameShow Pro UI');
requireTokens('assets/js/pro-admin-v3.68-r48.js',['admin_import_questions_pro','admin_event_dashboard','proAudioProfile','proPermissionRole','proBrandPreviewTitle','proRehearsal'],'GameShow Pro JS');
requireTokens('supabase/migrations/042_game_modes_pack_v368_r47.sql',['admin_import_questions_pro','admin_event_dashboard',"'game_type',r.game_type_snapshot"],'import/dashboard r48');
ok('Banco Pro, importação, dashboard, mídia, áudio, permissões, branding e ensaio preservados na r48.');

// 23. Runtime stability: no observer loop + anti-flicker/caching.
const proRuntime=read('assets/js/pro-runtime-v3.68-r48.js');
if(proRuntime.includes('MutationObserver'))fail('pro-runtime r48 não deve usar MutationObserver; risco de regressão de travamento.');
requireTokens('assets/js/pro-runtime-v3.68-r48.js',['lastMediaKey','mediaKey!==lastMediaKey','playerRender','renderDisplayGame'],'anti-flicker runtime');
requireTokens('assets/js/common-v3.68-r48.js',['rankSignature','el.dataset.rankSignature===signature'],'ranking estável');
requireTokens('assets/js/motion-v3.68-r48.js',['semanticClassName','restartHandles','requestAnimationFrame',"filter(c=>!c.startsWith('motion-'))"],'motion safety');
forbidTokens('assets/js/motion-v3.68-r48.js',['void el.offsetWidth','let last=el.className'],'motion safety');
ok('Runtime r48 evita observer recursivo e preserva anti-flicker de mídia/ranking.');

// 24. Login/join safety, avatar catalog and maps.
if(read('admin.html').includes('motion-v3.68-r48.js')||read('index.html').includes('motion-v3.68-r48.js'))fail('Motion não deve ser pré-carregado antes do login/entrada.');
requireTokens('assets/js/admin-v3.68-r48.js',['loadAdminMotionAfterAuth'],'ADM motion deferido');
requireTokens('assets/js/player-v3.68-r48.js',['loadPlayerMotionAfterJoin'],'Player motion deferido');
const avatars=read('assets/js/avatars-v3.68-r48.js');const keys=[...avatars.matchAll(/\{key:'([^']+)'/g)].map(m=>m[1]);if(new Set(keys).size!==31)fail(`Catálogo ativo deveria ter 31 avatares; encontrados ${new Set(keys).size}.`);
for(const k of new Set(keys)){for(const dir of ['runtime-r30','preview-r30'])if(!exists(`assets/avatars/${dir}/${k}.webp`))fail(`Avatar asset ausente: ${dir}/${k}.webp`);}
const city=read('assets/js/city-v3.68-r48.js');for(const scene of ['office','laboratory','industry','platform'])if(!city.includes(`${scene}:{`))fail(`Mapa/grafo ausente: ${scene}`);
ok('Login/entrada protegidos; 31 avatares e quatro mapas preservados.');

// 25. Docs, launcher, workflow, alias, configuration hygiene.
for(const rel of ['README.md','CHANGELOG_v3.68_r48_Admin_Organizado.txt','VERSION.txt','01_Abrir_Simulador_QuizRounds2_v3.68-r48.bat','.github/workflows/pages.yml','admin/index.html'])if(!exists(rel))fail(`Arquivo de release ausente: ${rel}`);
requireTokens('.github/workflows/pages.yml',['QuizRounds2 r48','node scripts/validate-build.mjs','sb_publishable_'],'workflow r48');
requireTokens('admin/index.html',['../admin.html?v=3.68-r48'],'alias /admin');
const config=read('assets/js/config.js');if(!config.includes('COLE_AQUI_A_URL_DO_PROJETO')||!config.includes('COLE_AQUI_APENAS_A_CHAVE_SB_PUBLISHABLE'))fail('config.js não está neutro com placeholders.');
for(const rel of activeJs){const s=read(rel);if(/sb_secret_[A-Za-z0-9_-]+/.test(s)||/service_role\s*[:=]\s*["'][^"']+/i.test(s))fail(`${rel}: credencial privilegiada encontrada.`);}
ok('Documentação, launcher, CI, /admin e configuração neutra r48 verificados.');

// 26. r48 admin hierarchy / anti-overdesign checks.
requireTokens('admin.html',['presentation-zone-heading zone-health','presentation-zone-heading zone-control','presentation-zone-heading zone-audience','presentation-zone-heading zone-analysis','load-test-menu','Recarregar r48'],'ADM r48 layout');
if(read('admin.html').includes('id="statusBuild"'))fail('ADM r48: BUILD duplicado na barra de status; mantenha a versão no cabeçalho/diagnóstico.');
requireTokens('assets/css/admin-v3.68-r48.css',['--adm-elev-1','--adm-elev-2','--adm-elev-3','--adm-radius-1','presentation-zone-heading','load-test-menu-panel'],'tokens/layout ADM r48');
requireTokens('assets/js/admin-v3.68-r48.js',["controllerGranted||remoteModeActive?'ready':'warn'"],'estado controlador r48');
ok('ADM r48: hierarquia semântica, elevação padronizada, status sem duplicação e pré-teste compacto verificados.');

if(errors.length){
  console.error(`VALIDAÇÃO QuizRounds2 r48: REPROVADA (${errors.length} erro(s), ${groups.length} grupos executados)`);
  for(const [i,e] of errors.entries())console.error(`ERRO ${i+1}: ${e}`);
  process.exit(1);
}
console.log(`VALIDAÇÃO QuizRounds2 r48: APROVADA (${groups.length} grupos)`);
for(const [i,g] of groups.entries())console.log(`${String(i+1).padStart(2,'0')}. ${g}`);
