import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const root=process.cwd(),errors=[],groups=[];
const fail=m=>errors.push(m),ok=m=>groups.push(m),exists=r=>fs.existsSync(path.join(root,r)),read=r=>fs.readFileSync(path.join(root,r),'utf8'),norm=r=>r.replaceAll('\\','/');
function walk(dir){const abs=path.join(root,dir);if(!fs.existsSync(abs))return[];let out=[];for(const e of fs.readdirSync(abs,{withFileTypes:true})){const r=norm(path.join(dir,e.name));out.push(...(e.isDirectory()?walk(r):[r]));}return out;}
function localTarget(owner,raw){let v=String(raw||'').trim();if(!v||v.startsWith('#')||/^(?:https?:|data:|blob:|mailto:|tel:|javascript:)/i.test(v)||v.startsWith('var('))return null;v=v.split('#')[0].split('?')[0];if(!v||/[{}$<>]/.test(v))return null;return norm(path.posix.normalize(path.posix.join(path.posix.dirname(owner),v)));}
function checkRef(owner,raw){const t=localTarget(owner,raw);if(t&&!exists(t))fail(`${owner}: referência ausente -> ${raw} (${t})`);}
function req(rel,tokens,label=rel){const s=read(rel);for(const t of tokens)if(!s.includes(t))fail(`${label}: marcador ausente -> ${t}`);}
function forbid(rel,tokens,label=rel){const s=read(rel);for(const t of tokens)if(s.includes(t))fail(`${label}: padrão proibido -> ${t}`);}
function namedExports(s){const z=new Set();for(const m of s.matchAll(/\bexport\s+(?:async\s+)?(?:function|class|const|let|var)\s+([A-Za-z_$][\w$]*)/g))z.add(m[1]);for(const m of s.matchAll(/\bexport\s*\{([^}]+)\}/g))for(const x of m[1].split(',')){const n=x.trim().split(/\s+as\s+/i)[0]?.trim();if(n)z.add(n);}return z;}
function cssBalanced(rel){let s=read(rel),d=0,q='',comment=false;for(let i=0;i<s.length;i++){const c=s[i],n=s[i+1];if(comment){if(c==='*'&&n==='/'){comment=false;i++;}continue;}if(!q&&c==='/'&&n==='*'){comment=true;i++;continue;}if(q){if(c==='\\'){i++;continue;}if(c===q)q='';continue;}if(c==='"'||c==="'"){q=c;continue;}if(c==='{')d++;if(c==='}')d--;if(d<0){fail(`${rel}: chave CSS fechada sem abertura`);return;}}if(d!==0)fail(`${rel}: chaves CSS desbalanceadas (${d})`);}

const html=['index.html','admin.html','display.html','simulator.html'];
const js=['assets/js/common-v3.68-r55.js','assets/js/avatars-v3.68-r55.js','assets/js/city-v3.68-r55.js','assets/js/admin-v3.68-r55.js','assets/js/display-v3.68-r55.js','assets/js/player-v3.68-r55.js','assets/js/simulator-v3.68-r55.js','assets/js/motion-v3.68-r55.js','assets/js/pro-admin-v3.68-r55.js','assets/js/pro-runtime-v3.68-r55.js'];
const css=['assets/css/core-v3.68-r55.css','assets/css/admin-v3.68-r55.css','assets/css/display-v3.68-r55.css','assets/css/display-ui-v3.92-r55.css','assets/css/player-ui-v3.92-r55.css','assets/css/simulator-v3.68-r55.css','assets/css/avatars-runtime-v3.68-r55.css','assets/css/avatars-ui-v3.92-r55.css','assets/css/motion-v3.68-r55.css','assets/css/pro-v3.68-r55.css'];
const games=['nearest','precision','ordering','matching','classification','true_false_series','hidden_image','zoom_mystery','who_am_i','before_after','case_study','decision_tree','team_mission','bingo','wheel','surprise','crowd_prediction','live_poll','audience_choice','category_choice'];

// 1
for(const rel of [...walk('assets/js').filter(x=>x.endsWith('.js')),...walk('scripts').filter(x=>x.endsWith('.mjs'))]){const r=spawnSync(process.execPath,['--input-type=module','--check'],{input:read(rel),encoding:'utf8'});if(r.status!==0)fail(`${rel}: JS inválido\n${r.stderr||r.stdout}`);}ok('Sintaxe JavaScript/MJS verificada.');
// 2
let ids=0;const supa='https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.112.4/dist/umd/supabase.min.js';for(const rel of html){const s=read(rel),arr=[...s.matchAll(/\bid=["']([^"']+)["']/gi)].map(x=>x[1]),seen=new Set();ids+=arr.length;for(const id of arr){if(seen.has(id))fail(`${rel}: id duplicado ${id}`);seen.add(id);}for(const m of s.matchAll(/\b(?:src|href)=["']([^"']+)["']/gi)){checkRef(rel,m[1]);if(/^assets\/(?:js|css|vendor)\//.test(m[1])&&!m[1].includes('v=3.68-r55'))fail(`${rel}: cache-bust r55 ausente -> ${m[1]}`);}if(rel!=='simulator.html'&&!s.includes(supa))fail(`${rel}: Supabase JS pin 2.112.4 ausente`);if(!s.includes('3.68-r55'))fail(`${rel}: build r55 ausente`);}ok(`${html.length} HTML / ${ids} IDs / refs principais verificados.`);
// 3
for(const r of [...js,...css])if(!exists(r))fail(`asset r55 ausente: ${r}`);ok('Conjunto ativo r55 existe.');
// 4
for(const rel of js){const s=read(rel);for(const m of s.matchAll(/(?:^|\n)\s*import\s*\{([^}]+)\}\s*from\s*["']([^"']+)["']/g)){checkRef(rel,m[2]);const t=localTarget(rel,m[2]);if(t&&exists(t)){const ex=namedExports(read(t));for(const x of m[1].split(',')){const n=x.trim().split(/\s+as\s+/i)[0]?.trim();if(n&&!ex.has(n))fail(`${rel}: export ${n} ausente em ${t}`);}}}for(const m of s.matchAll(/import\(\s*["']([^"']+)["']\s*\)/g))checkRef(rel,m[1]);}ok('Imports/exportações ES Modules resolvidos.');
// 5
for(const rel of css){cssBalanced(rel);for(const m of read(rel).matchAll(/url\(\s*["']?([^"')]+)["']?\s*\)/gi))checkRef(rel,m[1]);}ok('CSS ativo balanceado e URLs locais resolvidas.');
// 6
req('assets/js/common-v3.68-r55.js',["BUILD_ID='3.68-r55'","BACKEND_SCHEMA_REQUIRED=42","TEAM_FEATURE_SCHEMA_REQUIRED=43"]);req('VERSION.txt',['RELEASE=r55','BUILD_ID=3.68-r55','BACKEND_SCHEMA_REQUIRED=42','BACKEND_SCHEMA_RECOMMENDED=43','TEAM_FEATURE_SCHEMA_REQUIRED=43','SUPABASE_MIGRATIONS=001-043']);ok('Handshake r55: base schema 042, equipes avançadas schema 043.');
// 7
const mig=walk('supabase/migrations').filter(x=>/\/\d{3}_.+\.sql$/.test(x)),nums=mig.map(x=>+path.basename(x).slice(0,3)).sort((a,b)=>a-b);for(let n=1;n<=43;n++)if(nums.filter(x=>x===n).length!==1)fail(`migration ${String(n).padStart(3,'0')} ausente/duplicada`);if(nums.some(x=>x<1||x>43))fail('migration fora de 001-043');ok('Cadeia Supabase 001–043 contínua.');
// 8
for(const r of ['00_APLICAR_MIGRATION_043.sql','00_ATUALIZAR_SUPABASE_PARA_SCHEMA_043.sql','supabase/migrations/043_team_formation_modes_v368_r52.sql'])if(!exists(r))fail(`helper/migration ausente: ${r}`);if(read('00_APLICAR_MIGRATION_043.sql')!==read('supabase/migrations/043_team_formation_modes_v368_r52.sql'))fail('helper APLICAR 043 diverge');if(read('00_ATUALIZAR_SUPABASE_PARA_SCHEMA_043.sql')!==read('supabase/migrations/043_team_formation_modes_v368_r52.sql'))fail('helper ATUALIZAR 043 diverge');ok('Migration 043 e helpers idênticos.');
// 9
for(const rel of mig){const n=(read(rel).match(/\$\$/g)||[]).length;if(n%2)fail(`${rel}: $$ desbalanceado`);}ok('SQL estático: delimitadores $$ balanceados.');
// 10
const sql42=read('supabase/migrations/042_game_modes_pack_v368_r47.sql');for(const t of games){if(!sql42.includes(`'${t}'`))fail(`game ${t} ausente na migration 042`);if(!read('admin.html').includes(`value="${t}"`))fail(`game ${t} ausente no ADM`);}ok(`${games.length} mecânicas especiais preservadas.`);
// 11
req('supabase/migrations/042_game_modes_pack_v368_r47.sql',['capture_game_snapshot_on_queue','capture_game_snapshot_on_round','game_type_snapshot','game_spec_snapshot','submit_quiz_game_answer','quiz_round_eligibility','Resposta já registrada','Tempo esgotado']);ok('Snapshots, respostas estruturadas, elegibilidade e idempotência preservados.');
// 12
req('supabase/migrations/042_game_modes_pack_v368_r47.sql',['get_round_game_extras_by_code','if not v_reveal then',"-'target'","-'correct_order'","-'correct_matches'"]);ok('Segredos/gabaritos continuam protegidos até revelação.');
// 13
req('supabase/migrations/043_team_formation_modes_v368_r52.sql',['admin_set_team_join_mode','pro_player_team_state','pro_player_choose_team','admin_team_lobby_state','admin_assign_participant_team',"v_mode not in ('auto','player','admin')","'schema_version',43"]);ok('Três modos de formação de equipes preservados no schema 043.');
// 14
req('assets/js/admin-v3.68-r55.js',['renderBackendFeatureState','BACKEND_SCHEMA_REQUIRED','TEAM_FEATURE_SCHEMA_REQUIRED','schema>=BACKEND_SCHEMA_REQUIRED','schema>=TEAM_FEATURE_SCHEMA_REQUIRED','00_ATUALIZAR_SUPABASE_PARA_SCHEMA_043.sql']);req('assets/js/pro-admin-v3.68-r55.js',['proBackendSchema','setTeamSchemaAvailability','schema 043','Os demais modos funcionam no schema 042']);ok('Schema 042 não bloqueia aplicação; recurso de equipes é feature-gated no 043.');
// 15
req('assets/js/player-v3.68-r55.js',['BACKEND_SCHEMA_REQUIRED','checkPlayerBackend']);req('assets/js/display-v3.68-r55.js',['BACKEND_SCHEMA_REQUIRED','checkDisplayBackend']);ok('Jogador e telão usam o requisito base schema 042.');
// 16
req('assets/js/admin-v3.68-r55.js',['resetNewRoomQueueIfNeeded','admin_remove_queue_item','reuseQuestionsForNextRoom','newGameReuseQuestions','Nova sala criada com a seleção de perguntas vazia']);req('admin.html',['newGameReuseQuestions','Uma nova sala sempre começa vazia']);ok('Nova sala vazia por padrão + reutilização explícita de perguntas.');
// 17
req('assets/js/admin-v3.68-r55.js',['continueCurrentRoom','reviewCurrentRoom','presentationContextForRoom','centralStepGo','renderCentralJourney']);ok('Central respeita contexto Padrão/GameShow.');
// 18
req('assets/js/admin-v3.68-r55.js',['templateTeamSetup','restoreTemplateTeams','template_team_setup','admin_save_teams','admin_set_team_join_mode']);ok('Modelos/duplicação preservam configuração das equipes.');
// 19
req('admin.html',['id="proQuickCreateCard"','id="proGameModeCard"','data-pro-pane="room"','Nome + dinâmica antes de criar']);forbid('admin.html',['data-pro-pane="dynamics"'],'subaba dinâmica separada');req('assets/js/pro-admin-v3.68-r55.js',["name==='dynamics'?'room'",'createProRoom']);ok('GameShow cria Sala + dinâmica no mesmo passo.');
// 20
req('assets/js/pro-admin-v3.68-r55.js',['updateProStepLabels',"proDraftMode==='teams'",'wizard-step-hidden']);ok('Numeração GameShow é dinâmica com/sem Equipes.');
// 21
req('admin.html',['data-standard-advanced="1"','standardShowAdvancedBtn']);req('assets/css/admin-v3.68-r55.css',['.ui-simple-mode [data-standard-advanced="1"]','standard-show-advanced']);ok('Partida Padrão oculta opções avançadas no modo simples.');
// 22
req('assets/js/admin-v3.68-r55.js',['gameQuestionIssue','validateGameQuestions',"type==='precision'",'correct_order','correct_matches','winning_lines','segments','boxes']);req('assets/js/pro-admin-v3.68-r55.js',['Mecânicas especiais completas','validateGameQuestions']);ok('Checklist valida mecânicas especiais antes do lobby.');
// 23
req('admin.html',['id="proTeamLiveStage"','data-pro-pane="presentation"','DISTRIBUIÇÃO NO LOBBY']);if(/id="proTeamAdminBoard"[\s\S]{0,100}data-pro-pane="teams"/.test(read('admin.html')))fail('board ao vivo ainda parece estar no setup de equipes');ok('Distribuição ao vivo das equipes está na Apresentação/Lobby.');
// 24
req('assets/js/admin-v3.68-r55.js',['launchGuidedTest','admin_list_teams','voteTypes','Math.max(players,8)','openLoadSimulator(Math.min(100,players)']);ok('Teste guiado adapta quantidade de jogadores virtuais.');
// 25
req('admin.html',['id="configQuestionBankMount"','id="proQuestionBankMount"','id="sharedQuestionBankWorkspace"']);req('assets/js/admin-v3.68-r55.js',['mountQuestionBank','questionBankContext']);ok('Banco de perguntas contextual Padrão/GameShow preservado.');
// 26
forbid('admin.html',['id="adminTabPresentation"','id="adminPanelPresentation"']);req('admin.html',['data-config-pane="presentation"','id="configPresentationMount"','data-pro-pane="presentation"','id="proPresentationMount"','id="sharedPresentationWorkspace"']);ok('Apresentação continua como subaba individual dos dois fluxos.');
// 27
const proRun=read('assets/js/pro-runtime-v3.68-r55.js');if(proRun.includes('MutationObserver'))fail('pro-runtime contém MutationObserver');req('assets/js/common-v3.68-r55.js',['rankSignature','el.dataset.rankSignature===signature']);req('assets/js/motion-v3.68-r55.js',['semanticClassName','restartHandles','requestAnimationFrame',"filter(c=>!c.startsWith('motion-'))"]);forbid('assets/js/motion-v3.68-r55.js',['void el.offsetWidth','let last=el.className']);ok('Proteções anti-loop/anti-flicker preservadas.');
// 28
if(read('admin.html').includes('motion-v3.68-r55.js')||read('index.html').includes('motion-v3.68-r55.js'))fail('motion pré-carregado antes de login/join');req('assets/js/admin-v3.68-r55.js',['loadAdminMotionAfterAuth']);req('assets/js/player-v3.68-r55.js',['loadPlayerMotionAfterJoin']);ok('Motion continua deferido após autenticação/entrada.');
// 29
const av=read('assets/js/avatars-v3.68-r55.js'),keys=[...av.matchAll(/\{key:'([^']+)'/g)].map(x=>x[1]);if(new Set(keys).size!==31)fail(`avatares ${new Set(keys).size}/31`);for(const k of new Set(keys))for(const d of ['runtime-r30','preview-r30'])if(!exists(`assets/avatars/${d}/${k}.webp`))fail(`avatar ausente ${d}/${k}`);const city=read('assets/js/city-v3.68-r55.js');for(const sc of ['office','laboratory','industry','platform'])if(!city.includes(`${sc}:{`))fail(`mapa ausente ${sc}`);ok('31 avatares + quatro mapas preservados.');
// 30
const jsTop=walk('assets/js').filter(x=>x.endsWith('.js')),cssTop=walk('assets/css').filter(x=>x.endsWith('.css'));if(jsTop.length!==11)fail(`assets/js deveria ter 11 arquivos ativos/config; tem ${jsTop.length}`);if(cssTop.length!==10)fail(`assets/css deveria ter 10 arquivos ativos; tem ${cssTop.length}`);for(const f of jsTop.filter(x=>x!=='assets/js/config.js'))if(!f.includes('r55'))fail(`JS legado no runtime: ${f}`);for(const f of cssTop)if(!f.includes('r55'))fail(`CSS legado no runtime: ${f}`);ok('Runtime enxugado: assets JS/CSS legados removidos.');
// 31
for(const r of ['README.md','CHANGELOG_v3.68_r55_Mapas_Refinados.txt','VERSION.txt','01_Abrir_Simulador_QuizRounds2_v3.68-r55.bat','.github/workflows/pages.yml','admin/index.html'])if(!exists(r))fail(`release file ausente ${r}`);req('.github/workflows/pages.yml',['QuizRounds2 r55','node scripts/validate-build.mjs','sb_publishable_']);req('admin/index.html',['../admin.html?v=3.68-r55']);const cfg=read('assets/js/config.js');if(!cfg.includes('COLE_AQUI_A_URL_DO_PROJETO')||!cfg.includes('COLE_AQUI_APENAS_A_CHAVE_SB_PUBLISHABLE'))fail('config.js não neutro');ok('Release docs/CI/alias/configuração neutra verificados.');
// 32
req('assets/css/avatars-ui-v3.92-r55.css',["industry-v3.68-r55.webp",'--city-ratio:1.333333','r55 — mapas refinados + escala de avatar compatível','--city-avatar-size:47px']);if(exists('assets/maps/industry-v3.50.webp'))fail('mapa antigo da Indústria ainda ativo no pacote');if(!exists('assets/maps/industry-v3.68-r55.webp'))fail('mapa refinado da Indústria ausente');ok('Mapa da Indústria r55 + proporção nativa 4:3 + escala compacta verificados.');
// 33
req('assets/js/city-v3.68-r55.js',['r55 — navegação refinada mapa a mapa','const spread=tight?0',"q5:[68,47],q6:[62,47]","e0:[63,35]","r7:[20,74],r8:[20,86]"]);forbid('assets/js/city-v3.68-r55.js',["am0:[14,26]"]);ok('Rotas refinadas: recepção, laboratório, indústria e plataforma verificadas.');
// 34
for(const rel of js){const z=read(rel);if(/sb_secret_[A-Za-z0-9_-]+/.test(z)||/service_role\s*[:=]\s*["'][^"']+/i.test(z))fail(`${rel}: segredo privilegiado encontrado`);}req('assets/js/admin-v3.68-r55.js',['ensureControllerForRoomCreation','settingsDraftDirty','admin_close_and_score_round_r47']);req('assets/js/pro-runtime-v3.68-r55.js',['pro_player_team_state','pro_player_choose_team','submit_quiz_game_answer']);ok('Hardening de credenciais, controlador, regras e runtime Pro preservado.');

if(errors.length){console.error(`VALIDAÇÃO QuizRounds2 r55: REPROVADA (${errors.length} erro(s), ${groups.length} grupos executados)`);errors.forEach((e,i)=>console.error(`ERRO ${i+1}: ${e}`));process.exit(1);}console.log(`VALIDAÇÃO QuizRounds2 r55: APROVADA (${groups.length} grupos)`);groups.forEach((g,i)=>console.log(`${String(i+1).padStart(2,'0')}. ${g}`));
