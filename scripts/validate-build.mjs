import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';

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
const js=['assets/js/common-v3.68-r78.js','assets/js/avatars-v3.68-r78.js','assets/js/city-v3.68-r78.js','assets/js/admin-v3.68-r78.js','assets/js/display-v3.68-r78.js','assets/js/player-v3.68-r78.js','assets/js/simulator-v3.68-r78.js','assets/js/motion-v3.68-r78.js','assets/js/pro-admin-v3.68-r78.js','assets/js/pro-runtime-v3.68-r78.js'];
const css=['assets/css/core-v3.68-r78.css','assets/css/admin-v3.68-r78.css','assets/css/display-v3.68-r78.css','assets/css/display-ui-v3.92-r78.css','assets/css/player-ui-v3.92-r78.css','assets/css/simulator-v3.68-r78.css','assets/css/avatars-runtime-v3.68-r78.css','assets/css/avatars-ui-v3.92-r78.css','assets/css/motion-v3.68-r78.css','assets/css/pro-v3.68-r78.css'];
const games=['nearest','precision','ordering','matching','classification','true_false_series','hidden_image','zoom_mystery','who_am_i','before_after','case_study','decision_tree','team_mission','bingo','wheel','surprise','crowd_prediction','live_poll','audience_choice','category_choice'];

// 1
for(const rel of [...walk('assets/js').filter(x=>x.endsWith('.js')),...walk('scripts').filter(x=>x.endsWith('.mjs'))]){const r=spawnSync(process.execPath,['--input-type=module','--check'],{input:read(rel),encoding:'utf8'});if(r.status!==0)fail(`${rel}: JS inválido\n${r.stderr||r.stdout}`);}ok('Sintaxe JavaScript/MJS verificada.');
// 2
let ids=0;const supa='https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.112.4/dist/umd/supabase.min.js';for(const rel of html){const s=read(rel),arr=[...s.matchAll(/\bid=["']([^"']+)["']/gi)].map(x=>x[1]),seen=new Set();ids+=arr.length;for(const id of arr){if(seen.has(id))fail(`${rel}: id duplicado ${id}`);seen.add(id);}for(const m of s.matchAll(/\b(?:src|href)=["']([^"']+)["']/gi)){checkRef(rel,m[1]);if(/^assets\/(?:js|css|vendor)\//.test(m[1])&&!m[1].includes('v=3.68-r78'))fail(`${rel}: cache-bust r78 ausente -> ${m[1]}`);}if(rel!=='simulator.html'&&!s.includes(supa))fail(`${rel}: Supabase JS pin 2.112.4 ausente`);if(!s.includes('3.68-r78'))fail(`${rel}: build r78 ausente`);}ok(`${html.length} HTML / ${ids} IDs / refs principais verificados.`);
// 3
for(const r of [...js,...css])if(!exists(r))fail(`asset r78 ausente: ${r}`);ok('Conjunto ativo r78 existe.');
// 4
for(const rel of js){const s=read(rel);for(const m of s.matchAll(/(?:^|\n)\s*import\s*\{([^}]+)\}\s*from\s*["']([^"']+)["']/g)){checkRef(rel,m[2]);const t=localTarget(rel,m[2]);if(t&&exists(t)){const ex=namedExports(read(t));for(const x of m[1].split(',')){const n=x.trim().split(/\s+as\s+/i)[0]?.trim();if(n&&!ex.has(n))fail(`${rel}: export ${n} ausente em ${t}`);}}}for(const m of s.matchAll(/import\(\s*["']([^"']+)["']\s*\)/g))checkRef(rel,m[1]);}ok('Imports/exportações ES Modules resolvidos.');
// 5
for(const rel of css){cssBalanced(rel);for(const m of read(rel).matchAll(/url\(\s*["']?([^"')]+)["']?\s*\)/gi))checkRef(rel,m[1]);}ok('CSS ativo balanceado e URLs locais resolvidas.');
// 6
req('assets/js/common-v3.68-r78.js',["BUILD_ID='3.68-r78'","BACKEND_SCHEMA_REQUIRED=42","TEAM_FEATURE_SCHEMA_REQUIRED=43"]);req('VERSION.txt',['RELEASE=r78','BUILD_ID=3.68-r78','BACKEND_SCHEMA_REQUIRED=42','BACKEND_SCHEMA_RECOMMENDED=43','TEAM_FEATURE_SCHEMA_REQUIRED=43','SUPABASE_MIGRATIONS=001-043']);ok('Handshake r78: base schema 042, equipes avançadas schema 043.');
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
req('assets/js/admin-v3.68-r78.js',['renderBackendFeatureState','BACKEND_SCHEMA_REQUIRED','TEAM_FEATURE_SCHEMA_REQUIRED','schema>=BACKEND_SCHEMA_REQUIRED','schema>=TEAM_FEATURE_SCHEMA_REQUIRED','00_ATUALIZAR_SUPABASE_PARA_SCHEMA_043.sql']);req('assets/js/pro-admin-v3.68-r78.js',['proBackendSchema','setTeamSchemaAvailability','schema 043','Os demais modos funcionam no schema 042']);ok('Schema 042 não bloqueia aplicação; recurso de equipes é feature-gated no 043.');
// 15
req('assets/js/player-v3.68-r78.js',['BACKEND_SCHEMA_REQUIRED','checkPlayerBackend']);req('assets/js/display-v3.68-r78.js',['BACKEND_SCHEMA_REQUIRED','checkDisplayBackend']);ok('Jogador e telão usam o requisito base schema 042.');
// 16
req('assets/js/admin-v3.68-r78.js',['resetNewRoomQueueIfNeeded','admin_remove_queue_item','reuseQuestionsForNextRoom','newGameReuseQuestions','Nova sala criada com a seleção de perguntas vazia']);req('admin.html',['newGameReuseQuestions','Uma nova sala sempre começa vazia']);ok('Nova sala vazia por padrão + reutilização explícita de perguntas.');
// 17
req('assets/js/admin-v3.68-r78.js',['continueCurrentRoom','reviewCurrentRoom','presentationContextForRoom','centralStepGo','renderCentralJourney']);ok('Central respeita contexto Padrão/GameShow.');
// 18
req('assets/js/admin-v3.68-r78.js',['templateTeamSetup','restoreTemplateTeams','template_team_setup','admin_save_teams','admin_set_team_join_mode']);ok('Modelos/duplicação preservam configuração das equipes.');
// 19
req('admin.html',['id="proQuickCreateCard"','id="proGameModeCard"','data-pro-pane="room"','Nome + dinâmica antes de criar']);forbid('admin.html',['data-pro-pane="dynamics"'],'subaba dinâmica separada');req('assets/js/pro-admin-v3.68-r78.js',["name==='dynamics'?'room'",'createProRoom']);ok('GameShow cria Sala + dinâmica no mesmo passo.');
// 20
req('assets/js/pro-admin-v3.68-r78.js',['updateProStepLabels',"proDraftMode==='teams'",'wizard-step-hidden']);ok('Numeração GameShow é dinâmica com/sem Equipes.');
// 21
req('admin.html',['data-standard-advanced="1"','standardShowAdvancedBtn']);req('assets/css/admin-v3.68-r78.css',['.ui-simple-mode [data-standard-advanced="1"]','standard-show-advanced']);ok('Partida Padrão oculta opções avançadas no modo simples.');
// 22
req('assets/js/admin-v3.68-r78.js',['gameQuestionIssue','validateGameQuestions',"type==='precision'",'correct_order','correct_matches','winning_lines','segments','boxes']);req('assets/js/pro-admin-v3.68-r78.js',['Mecânicas especiais completas','validateGameQuestions']);ok('Checklist valida mecânicas especiais antes do lobby.');
// 23
req('admin.html',['id="proTeamLiveStage"','data-pro-pane="presentation"','DISTRIBUIÇÃO NO LOBBY']);if(/id="proTeamAdminBoard"[\s\S]{0,100}data-pro-pane="teams"/.test(read('admin.html')))fail('board ao vivo ainda parece estar no setup de equipes');ok('Distribuição ao vivo das equipes está na Apresentação/Lobby.');
// 24
req('assets/js/admin-v3.68-r78.js',['launchGuidedTest','admin_list_teams','voteTypes','Math.max(players,8)','openLoadSimulator(Math.min(100,players)']);ok('Teste guiado adapta quantidade de jogadores virtuais.');
// 25
req('admin.html',['id="configQuestionBankMount"','id="proQuestionBankMount"','id="sharedQuestionBankWorkspace"']);req('assets/js/admin-v3.68-r78.js',['mountQuestionBank','questionBankContext']);ok('Banco de perguntas contextual Padrão/GameShow preservado.');
// 26
forbid('admin.html',['id="adminTabPresentation"','id="adminPanelPresentation"']);req('admin.html',['data-config-pane="presentation"','id="configPresentationMount"','data-pro-pane="presentation"','id="proPresentationMount"','id="sharedPresentationWorkspace"']);ok('Apresentação continua como subaba individual dos dois fluxos.');
// 27
const proRun=read('assets/js/pro-runtime-v3.68-r78.js');if(proRun.includes('MutationObserver'))fail('pro-runtime contém MutationObserver');req('assets/js/common-v3.68-r78.js',['rankSignature','el.dataset.rankSignature===signature']);req('assets/js/motion-v3.68-r78.js',['semanticClassName','restartHandles','requestAnimationFrame',"filter(c=>!c.startsWith('motion-'))"]);forbid('assets/js/motion-v3.68-r78.js',['void el.offsetWidth','let last=el.className']);ok('Proteções anti-loop/anti-flicker preservadas.');
// 28
if(read('admin.html').includes('motion-v3.68-r78.js')||read('index.html').includes('motion-v3.68-r78.js'))fail('motion pré-carregado antes de login/join');req('assets/js/admin-v3.68-r78.js',['loadAdminMotionAfterAuth']);req('assets/js/player-v3.68-r78.js',['loadPlayerMotionAfterJoin']);ok('Motion continua deferido após autenticação/entrada.');
// 29
const av=read('assets/js/avatars-v3.68-r78.js'),keys=[...av.matchAll(/\{key:'([^']+)'/g)].map(x=>x[1]);if(new Set(keys).size!==31)fail(`avatares ${new Set(keys).size}/31`);for(const k of new Set(keys))for(const d of ['runtime-r30','preview-r30'])if(!exists(`assets/avatars/${d}/${k}.webp`))fail(`avatar ausente ${d}/${k}`);const city=read('assets/js/city-v3.68-r78.js');for(const sc of ['office','laboratory','industry','platform'])if(!city.includes(`${sc}:{`))fail(`mapa ausente ${sc}`);ok('31 avatares + quatro mapas preservados.');
// 30
const jsTop=walk('assets/js').filter(x=>x.endsWith('.js')),cssTop=walk('assets/css').filter(x=>x.endsWith('.css'));if(jsTop.length!==11)fail(`assets/js deveria ter 11 arquivos ativos/config; tem ${jsTop.length}`);if(cssTop.length!==10)fail(`assets/css deveria ter 10 arquivos ativos; tem ${cssTop.length}`);for(const f of jsTop.filter(x=>x!=='assets/js/config.js'))if(!f.includes('r78'))fail(`JS legado no runtime: ${f}`);for(const f of cssTop)if(!f.includes('r78'))fail(`CSS legado no runtime: ${f}`);if(exists('assets/avatars/runtime-r21')||exists('assets/avatars/hd'))fail('diretórios legados de avatar ainda presentes');ok('Runtime enxugado: assets JS/CSS e avatares legados removidos.');
// 31
for(const r of ['README.md','CHANGELOG_v3.68_r78_Deploy_E2E_Separado.txt','VALIDATION_r78_Deploy_E2E_Separado.txt','FINAL_RELEASE_r78.txt','VERSION.txt','01_Abrir_Simulador_QuizRounds2_v3.68-r78.bat','00_VERIFICAR_ANTES_DO_PUSH.bat','.github/workflows/pages.yml','admin/index.html'])if(!exists(r))fail(`release file ausente ${r}`);req('.github/workflows/pages.yml',['Deploy QuizRounds2 no GitHub Pages','Ler versão da release','node scripts/validate-build.mjs','node scripts/build-pages.mjs','node scripts/validate-pages.mjs _site','BUILD_ID: ${{ steps.release.outputs.build }}']);forbid('.github/workflows/pages.yml',['Deploy QuizRounds2 r78','Validar release r78','Montar site estático r78']);req('scripts/build-pages.mjs',['parseVersionFile','version.json diverge de VERSION.txt','sb_publishable_','SUPABASE_URL','SUPABASE_PUBLISHABLE_KEY']);req('admin/index.html',['../version.json','../admin.html','qr_build','qr_reload']);const cfg=read('assets/js/config.js');if(!cfg.includes('COLE_AQUI_A_URL_DO_PROJETO')||!cfg.includes('COLE_AQUI_APENAS_A_CHAVE_SB_PUBLISHABLE'))fail('config.js não neutro');ok('Release docs/CI auto-versionado/alias/configuração neutra verificados.');
// 32
req('assets/css/avatars-ui-v3.92-r78.css',["industry-v3.68-r78.webp",'--city-ratio:1.333333','r78 — mapas refinados + escala de avatar compatível','--city-avatar-size:47px']);if(exists('assets/maps/industry-v3.50.webp'))fail('mapa antigo da Indústria ainda ativo no pacote');if(!exists('assets/maps/industry-v3.68-r78.webp'))fail('mapa refinado da Indústria ausente');ok('Mapa da Indústria r78 + proporção nativa 4:3 + escala compacta verificados.');
// 33
function parseSceneGraph(src,name){
  const names=['office','laboratory','industry','platform'],start=src.indexOf(`  ${name}:{`);if(start<0)return null;const next=names.map(n=>src.indexOf(`  ${n}:{`,start+1)).filter(x=>x>start);const end=next.length?Math.min(...next):src.indexOf('};\n\nfunction',start)>0?src.indexOf('};\n\nfunction',start):src.length,block=src.slice(start,end);
  const nodePart=(block.match(/nodes:\{([\s\S]*?)\n    \},\n    edges:/)||[])[1]||'',edgePart=(block.match(/edges:\[([\s\S]*?)\n    \],\n    tight:/)||[])[1]||'',spawnPart=(block.match(/spawn:\[([\s\S]*?)\n    \],\n    pois:/)||[])[1]||'',poiPart=(block.match(/pois:\[([\s\S]*?)\n    \],\n    occluders:/)||[])[1]||'';
  const nodes=new Set([...nodePart.matchAll(/([A-Za-z0-9_]+):\[[\d.]+,[\d.]+\]/g)].map(m=>m[1])),edges=[...edgePart.matchAll(/\['([^']+)','([^']+)'\]/g)].map(m=>[m[1],m[2]]),spawn=[...spawnPart.matchAll(/'([^']+)'/g)].map(m=>m[1]),pois=[...poiPart.matchAll(/node:'([^']+)'/g)].map(m=>m[1]);return{nodes,edges,spawn,pois};
}
for(const scene of ['office','laboratory','industry','platform']){const g=parseSceneGraph(city,scene);if(!g){fail(`grafo ausente ${scene}`);continue;}const adj=new Map([...g.nodes].map(n=>[n,new Set()]));for(const[a,b]of g.edges){if(!g.nodes.has(a)||!g.nodes.has(b)){fail(`${scene}: aresta usa nó ausente ${a}/${b}`);continue;}adj.get(a).add(b);adj.get(b).add(a);}for(const n of g.spawn)if(!g.nodes.has(n))fail(`${scene}: spawn ausente ${n}`);if(g.spawn.length){const seen=new Set([g.spawn[0]]),q=[g.spawn[0]];while(q.length){const n=q.pop();for(const x of adj.get(n)||[])if(!seen.has(x)){seen.add(x);q.push(x);}}for(const n of g.spawn)if(!seen.has(n))fail(`${scene}: spawn isolado ${n}`);for(const n of g.pois)if(!seen.has(n))fail(`${scene}: POI fora do grafo transitável ${n}`);}}
req('assets/js/city-v3.68-r78.js',['spawns somente no grafo transitável principal',"['w3','crew5']","city.querySelector('.city-walkers')"]);ok('Spawns/POIs dos quatro mapas pertencem ao mesmo grafo transitável e o mascote fica contido no mapa.');
// 34
req('assets/js/avatars-v3.68-r78.js',["et_skunk',label:'Gambá ET'","gamba:'et_skunk'","gambazinho:'et_skunk'","special_skunk:'et_skunk'"]);req('assets/css/avatars-ui-v3.92-r78.css',['.city-walkers{z-index:2000}','position:relative;z-index:4']);req('assets/css/motion-v3.68-r78.css',['z-index:2060']);ok('Avatar especial e prioridade visual de nomes/personagens protegidos.');
// 35
req('admin.html',['data-avatar-scene-live="office"','data-avatar-scene-live="laboratory"','data-avatar-scene-live="industry"','data-avatar-scene-live="platform"']);req('assets/js/admin-v3.68-r78.js',['setAvatarSceneQuick','avatar_scene:next','overlayReset.error','Não foi possível limpar a sobreposição do telão']);req('assets/js/display-v3.68-r78.js',['applyAvatarScene','settings?.avatar_scene']);ok('Troca de mapa ao vivo e abertura do telão sem overlay residual verificadas.');
// 36
for(const rel of js){const z=read(rel);if(/sb_secret_[A-Za-z0-9_-]+/.test(z)||/service_role\s*[:=]\s*["'][^"']+/i.test(z))fail(`${rel}: segredo privilegiado encontrado`);}req('assets/js/admin-v3.68-r78.js',['ensureControllerForRoomCreation','settingsDraftDirty','admin_close_and_score_round_r47']);req('assets/js/pro-runtime-v3.68-r78.js',['pro_player_team_state','pro_player_choose_team','submit_quiz_game_answer']);ok('Hardening de credenciais, controlador, regras e runtime Pro preservado.');
// 37
req('assets/js/common-v3.68-r78.js',['isDisplayAudioScope','publishDisplayAudioState','quizrounds:display-audio-state','playFeedbackCue','isFeedbackAudioReady','setDisplayAudioVolume','startDisplayAmbience','stopDisplayAmbience','audioTest','cueBoost','allReady','countdown','questionOpen','lastFive','timeEnd','newLeader','finalRanking','freeze']);
req('assets/js/display-v3.68-r78.js',["playCue('allReady'","playCue('countdown'","playCue('questionOpen'","playCue('lastFive'","playCue('timeEnd'","playCue('newLeader'","playCue('finalRanking'","playCue('freeze'",'displayAudioGate','activateDisplayAudio','primeDisplayAudioFromGesture','Som: ativar','displayAudioTestBtn',"const revealed=phase==='result'",'pro_ambient_audio','startDisplayAmbience','stopDisplayAmbience']);
forbid('assets/js/display-v3.68-r78.js',['AudioContext','createOscillator']);
forbid('assets/js/player-v3.68-r78.js',['playFeedbackCue','unlockFeedbackAudio','setFeedbackAudioEnabled','AudioContext','createOscillator','playCue(','soundToggle']);
forbid('assets/js/admin-v3.68-r78.js',['playFeedbackCue','unlockFeedbackAudio','setFeedbackAudioEnabled','AudioContext','createOscillator','adminCue(']);
forbid('assets/js/pro-admin-v3.68-r78.js',['AudioContext','createOscillator','playFeedbackCue']);
forbid('assets/js/pro-runtime-v3.68-r78.js',['AudioContext','createOscillator','playFeedbackCue','setFeedbackAudioEnabled','playProCue','ambientSchedule','ambientCtx','userInteracted','lastPhaseCue']);
const activeRuntimeJs=walk('assets/js').filter(x=>x.endsWith('.js')&&x!=='assets/js/config.js'),webAudioOwners=activeRuntimeJs.filter(rel=>/\b(?:AudioContext|webkitAudioContext)\b/.test(read(rel)));if(webAudioOwners.length!==1||webAudioOwners[0]!=='assets/js/common-v3.68-r78.js')fail(`WebAudio deve existir somente em common-v3.68-r78.js; encontrado em: ${webAudioOwners.join(', ')||'nenhum'}`);
forbid('index.html',['id="soundToggle"']);req('display.html',['id="displayAudioGate"','Ativar som do telão','id="displayAudioTestBtn"','id="displayTechAudio"']);
req('assets/css/display-ui-v3.92-r78.css',['.display-main-area>.display-panel-enter','city-scene-crossfade-old','display-audio-gate','data-audio-state="locked"']);
ok('AudioManager único no telão, master mute e cues sem duplicação Pro verificados.');
// 38
req('assets/js/pro-runtime-v3.68-r78.js',["isPlayer&&(type==='audio'||type==='video')",'pro-media-remote','Mídia no telão','Acompanhe o áudio e o vídeo pela apresentação principal.','syncDisplayMediaAudio','displaySoundEnabled','quizrounds:display-audio-state']);req('assets/css/pro-v3.68-r78.css',['.pro-media-remote']);forbid('assets/js/player-v3.68-r78.js',['<audio','<video','new Audio(']);ok('Mídia sonora/audiovisual no celular é substituída por aviso para acompanhar no telão.');
// 39
req('version.json',['"release": "r78"','"build": "3.68-r78"','"backend_schema_required": 42']);
req('scripts/build-pages.mjs',["const out=path.join(root,'_site')","parseVersionFile","version.json diverge de VERSION.txt","SUPABASE_PUBLISHABLE_KEY","fs.writeFileSync(path.join(out,'.nojekyll')"]);
req('scripts/validate-pages.mjs',["VALIDAÇÃO _site: APROVADA","const commonRel=`assets/js/common-v${build}.js`","version.json diverge de VERSION.txt"]);
req('.github/workflows/pages.yml',["Ler versão da release","BUILD_ID: ${{ steps.release.outputs.build }}","common=\"assets/js/common-v${BUILD_ID}.js\"","node scripts/build-pages.mjs","node scripts/validate-pages.mjs _site","Aguardar propagação e confirmar publicação","max_attempts=60","wait_seconds=10","Cache-Control: no-cache, no-store, max-age=0","admin.html|${BUILD_ID}","display.html|${BUILD_ID}","simulator.html|${BUILD_ID}","admin/|${BUILD_ID}"]);
forbid('.github/workflows/pages.yml',["printf '%s' \"$body\" | grep -Fq","Deploy QuizRounds2 r78 no GitHub Pages"]);req('.github/workflows/pages.yml',["[[ \"$body\" == *\"$needle\"* ]]"]);ok('Pipeline GitHub Pages auto-versionado gera, valida e aguarda propagação sem falso negativo por SIGPIPE.');
// 40
const versionMeta=Object.fromEntries(read('VERSION.txt').split(/\r?\n/).filter(x=>x.includes('=')).map(line=>{const i=line.indexOf('=');return[line.slice(0,i),line.slice(i+1)];}));
const jsonMeta=JSON.parse(read('version.json'));if(versionMeta.RELEASE!=='r78'||versionMeta.BUILD_ID!=='3.68-r78'||jsonMeta.release!==versionMeta.RELEASE||jsonMeta.build!==versionMeta.BUILD_ID)fail('fonte de verdade da release divergente entre VERSION.txt e version.json');
for(const rel of ['.github/workflows/pages.yml','scripts/build-pages.mjs','scripts/validate-pages.mjs'])if(/r(?:[0-5]\d|6[0-7])/.test(read(rel)))fail(`${rel}: referência de release anterior encontrada no CI atual`);ok('Fonte de verdade da release e CI sem mistura de versões anteriores.');
// 41 — cache/version self-heal + Realtime convergence hardening
for(const rel of ['admin.html','display.html','index.html','simulator.html'])req(rel,['id="quizBuildGuard"',"cache:'no-store'",'quiz2:auto-reload:','qr_build','qr_reload']);
req('admin/index.html',['version.json?qr_version_check=',"cache:'no-store'",'qr_build','qr_reload']);
for(const rel of ['assets/js/admin-v3.68-r78.js','assets/js/player-v3.68-r78.js','assets/js/display-v3.68-r78.js'])req(rel,['syncStateToVersion','realtimeTargetVersion','payload?.state_version']);
req('assets/js/admin-v3.68-r78.js',['scheduleRealtimeAuxRefresh',"'CHANNEL_ERROR','TIMED_OUT','CLOSED'"]);
req('assets/js/player-v3.68-r78.js',["status==='CLOSED'&&navigator.onLine",'syncStateToVersion']);
req('assets/js/display-v3.68-r78.js',["'CHANNEL_ERROR','TIMED_OUT','CLOSED'",'syncStateToVersion']);
forbid('assets/js/player-v3.68-r78.js',['banner.onclick=()=>location.reload()']);forbid('assets/js/display-v3.68-r78.js',['banner.onclick=()=>location.reload()']);
ok('Autoatualização de build e convergência Realtime por state_version verificadas.');
// 43 — sincronização determinística r78
for(const rel of ['admin.html','display.html','index.html','simulator.html'])req(rel,['compare(remote,local)<=0','qr_version_check'],'version guard '+rel);
req('admin/index.html',['cmp(v.build,local)>0','qr_build']);
req('assets/js/admin-v3.68-r78.js',['incomingVersion<currentVersion','performance.now()-started<2800',"backendCheckStatus='unavailable'","url.searchParams.set('qr_build',BUILD_ID)"]);
req('assets/js/player-v3.68-r78.js',['incomingVersion<currentVersion','performance.now()-started<2600','realtimeFallbackUntil','Não foi possível verificar o backend agora']);
req('assets/js/display-v3.68-r78.js',['incomingVersion<currentVersion','performance.now()-started<2600','realtimeFallbackUntil',"url.searchParams.set('qr_build',BUILD_ID)",'Backend incompatível confirmado']);
forbid('assets/js/admin-v3.68-r78.js',["includes(status))scheduleReconnect(epoch);if(status==='CLOSED'"]);
forbid('assets/js/display-v3.68-r78.js',["includes(status))scheduleReconnect(epoch);if(status==='CLOSED'"]);
ok('r78: anti-downgrade, estado monotônico, convergência limitada e links versionados verificados.');
// 44 — observabilidade pré-evento r78
req('assets/js/player-v3.68-r78.js',['playerPresencePayload','trackPlayerPresence','state_version:Number(gameState?.room?.state_version||0)',"kind:'participant',participant_id:me.id,session_id:tabId,reconnect_epoch:connectionEpoch,build:BUILD_ID,state_version"]);
req('assets/js/display-v3.68-r78.js',['trackDisplayPresence',"event:'connection_test'","kind:'display',display_id:displayPresenceId"]);
req('assets/js/admin-v3.68-r78.js',['presenceLagSummary','connectionAcks=new Map()','syncOk=lag.lagging===0','Aparelhos com estado atrasado detectados','Teste de sincronização por identidade aprovado']);
ok('r78: presença com estado, detecção de atraso e teste de sincronização telão/jogadores verificados.');
// 45 — operação segura em evento r78
req('admin.html',['id="healthSync"','id="startSyncCheck"','Sincronizar aparelhos','id="diagSync"']);
req('assets/js/admin-v3.68-r78.js',['syncSnapshot','broadcastSyncNudge','maybeAutoRecoverLag','recoverEventSync','stabilizeBeforeStart','Sincronização bloqueou o início','lastAutoRecoveryAt<10000',"runConnectionTest({silent=false,timeoutMs=6000}={})"]);
req('assets/css/admin-v3.68-r78.css',['grid-template-columns:repeat(5,minmax(0,1fr))','grid-template-columns:repeat(9,minmax(0,1fr))']);
ok('r78: recuperação controlada, diagnóstico de sincronização e gate de estabilidade antes do início verificados.');

// 46 — watchdog operacional + pré-flight automático r78
req('assets/js/admin-v3.68-r78.js',['startEventWatchdog','eventWatchdogTick','watchdogSnapshot','displayStale','playerStale','dedup=new Map()','runPreflight({silent:true,quick:true})',"phase()==='lobby'&&Date.now()-lastAutoPreflightAt>20000",'displayRequired=eventModeActive','telão sem heartbeat','builds diferentes']);
req('assets/js/player-v3.68-r78.js',['session_id:tabId','reconnect_epoch:connectionEpoch']);
req('assets/js/display-v3.68-r78.js',['session_id:displayPresenceId','reconnect_epoch:subscriptionEpoch']);
req('admin.html',['Watchdog contínuo','Pré-flight automático']);
ok('r78: watchdog de sessão, presença deduplicada, heartbeat e pré-flight automático verificados.');
// 47 — congelamento da release final r78
req('VERSION.txt',['RELEASE=r78','BUILD_ID=3.68-r78','RELEASE_STATUS=FINAL_STABLE','PACKAGE=QuizRounds2_v3_68_UI_v3_92_GitHub_Supabase_r78_Deploy_E2E_Separado']);
req('version.json',['"release": "r78"','"build": "3.68-r78"','"status": "final-stable"','"frozen": true']);
req('.github/workflows/pages.yml',['Contrato comportamental de sincronização','node scripts/validate-sync-behavior.mjs','Estresse operacional determinístico','node scripts/validate-event-stress.mjs','Auditoria final bloqueante','node scripts/validate-build.mjs','node scripts/validate-pages.mjs _site','Smoke HTTP local do artefato','node scripts/validate-site-smoke.mjs _site']);
forbid('.github/workflows/pages.yml',['continue-on-error: true','Auditoria profunda de desenvolvimento']);
if(!exists('FINAL_RELEASE_r78.txt'))fail('FINAL_RELEASE_r78.txt ausente');
req('00_VERIFICAR_ANTES_DO_PUSH.bat',['[2/4] Contrato comportamental de sincronizacao','[3/4] Estresse operacional 100 jogadores + telao','[4/4] Auditoria final bloqueante','BLOQUEADO: a auditoria final encontrou divergencias','APROVADO - r78 DEPLOY + E2E SEPARADO pronta para enviar ao GitHub.']);
ok('r78: release final congelada, auditoria comportamental/profunda bloqueante e marcadores finais verificados.');
// 48 — contrato estrito de sincronização r78
req('assets/js/admin-v3.68-r78.js',['// SYNC_CONTRACT_BEGIN','summarizePresenceLag','evaluateConnectionAcks','Number(d.state_version||0)===target-1','Number(a.state_version||0)===Number(targetVersion)','test?.complete&&sameTarget','state_version exato','Modo Evento exige Realtime conectado','transportOk=realtimeOk||(!realtimeRequired&&rpcOk)','const ok=await refreshState(false)']);
const syncTest=spawnSync(process.execPath,['scripts/validate-sync-behavior.mjs'],{cwd:root,encoding:'utf8'});if(syncTest.status!==0)fail(`validação comportamental falhou\n${syncTest.stderr||syncTest.stdout}`);else if(!String(syncTest.stdout).includes('APROVADA (16/16)'))fail('validação comportamental não confirmou 16/16 cenários');ok('r78: ACK completo, state_version exato, Inicializando explícito e fallback controlado aprovados em teste comportamental.');
// 49 — pacote operacional higienizado
const rootFiles=fs.readdirSync(root,{withFileTypes:true}).filter(e=>e.isFile()).map(e=>e.name);if(rootFiles.length>20)fail(`raiz da distribuição voltou a ficar poluída: ${rootFiles.length} arquivos`);for(const rel of ['docs/history/release-notes','docs/history/sql-helpers'])if(!exists(rel))fail(`histórico organizado ausente: ${rel}`);for(const stale of ['CHANGELOG_v3.68_r73_Final_Estavel.txt','VALIDATION_r73_Final_Estavel.txt','FINAL_RELEASE_r73.txt','00_APLICAR_MIGRATION_041.sql','00_APLICAR_MIGRATION_042.sql'])if(exists(stale))fail(`arquivo histórico não deveria permanecer na raiz: ${stale}`);req('README.md',['QuizRounds2 v3.68-r78 — Deploy + E2E Separado','state_version = 0','fallback controlado por polling','docs/history/']);forbid('README.md',['Execute `00_APLICAR_MIGRATION_042.sql`','# QuizRounds2 v3.68-r51']);ok(`Distribuição final enxugada (${rootFiles.length} arquivos na raiz) e documentação histórica isolada.`);
// 49 — manifesto final
if(!exists('BUILD_MANIFEST_SHA256.txt'))fail('BUILD_MANIFEST_SHA256.txt ausente');else{const lines=read('BUILD_MANIFEST_SHA256.txt').split(/\r?\n/).filter(Boolean),listed=new Map();for(const line of lines){const m=line.match(/^([0-9a-f]{64})\s+(?:\.\/)?(.+)$/i);if(!m){fail(`manifesto inválido: ${line}`);continue;}listed.set(norm(m[2]),m[1].toLowerCase());}const files=walk('.').filter(f=>!f.startsWith('.git/')&&f!=='BUILD_MANIFEST_SHA256.txt'&&!f.startsWith('_site/')).sort();for(const f of files){if(!listed.has(f)){fail(`manifesto sem arquivo: ${f}`);continue;}const h=createHash('sha256').update(fs.readFileSync(path.join(root,f))).digest('hex');if(h!==listed.get(f))fail(`manifesto divergente: ${f}`);}for(const f of listed.keys())if(!files.includes(f))fail(`manifesto aponta arquivo inexistente/excluído: ${f}`);}ok('Manifesto SHA-256 corresponde integralmente à release.');
// 50 — estresse operacional determinístico r78
if(!exists('scripts/validate-event-stress.mjs'))fail('scripts/validate-event-stress.mjs ausente');
else{const stress=spawnSync(process.execPath,['scripts/validate-event-stress.mjs'],{cwd:root,encoding:'utf8'});if(stress.status!==0)fail(`estresse operacional falhou\n${stress.stderr||stress.stdout}`);else if(!String(stress.stdout).includes('APROVADA (16/16 testes determinísticos + 10000 cenários aleatórios + 20 transições com 101 aparelhos)'))fail('estresse operacional não confirmou a matriz completa r78');}
ok('r78: estresse de 100 jogadores + telão, 10.000 cenários aleatórios e 20 transições sequenciais aprovado.');
// 51 — correções determinísticas da crítica r75
req('assets/js/admin-v3.68-r78.js',['expectedConnectionTargets','missingIds','extraIds','aheadRows','matched>=connectionExpectedTargets.length','Math.max(2500,Math.min(8000']);
req('assets/js/player-v3.68-r78.js',['localVersion<targetVersion','syncStateToVersion(targetVersion,{force:true})']);
forbid('assets/js/player-v3.68-r78.js',["event:'connection_test'},async({payload})=>{if(epoch!==connectionEpoch)return;try{await heartbeat()"]);
forbid('assets/js/display-v3.68-r78.js',["event:'connection_test'},async({payload})=>{if(epoch!==subscriptionEpoch)return;try{await refresh(false);await trackDisplayPresence()"]);
ok('r78: presença à frente bloqueante, ACK por identidade, early-completion e remoção do heartbeat RPC do ACK verificados.');
// 52 — E2E real de navegador r78, isolado do deploy
for(const rel of ['tests/e2e/test_browser_e2e.py','tests/e2e/requirements.txt','tests/e2e/README.md','.github/workflows/e2e.yml'])if(!exists(rel))fail(`infra E2E ausente: ${rel}`);
req('tests/e2e/test_browser_e2e.py',["BUILD = \"3.68-r78\"",'EXPECTED_SCENARIOS = 4','scenario_auth_and_logic','scenario_full_event_100','scenario_player_reconnect','scenario_mobile_layout','E2E BROWSER: APROVADO','pageerror','console.error','PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH','shutil.which("chromium")']);
req('tests/e2e/requirements.txt',['playwright==1.55.0']);
req('.github/workflows/e2e.yml',['Homologação E2E QuizRounds2','workflow_dispatch','mcr.microsoft.com/playwright/python:v1.55.0-noble','options: --ipc=host','python tests/e2e/test_browser_e2e.py --self-check .','python tests/e2e/test_browser_e2e.py .']);
const py=process.platform==='win32'?'python':'python3',e2eSelf=spawnSync(py,['tests/e2e/test_browser_e2e.py','--self-check','.'],{cwd:root,encoding:'utf8'});if(e2eSelf.status!==0)fail(`self-check E2E falhou\n${e2eSelf.stderr||e2eSelf.stdout}`);else if(!String(e2eSelf.stdout).includes('E2E SELF-CHECK: APROVADO'))fail('self-check E2E não confirmou aprovação');
ok('r78: homologação Playwright/Chromium preservada em workflow dedicado com 4 cenários e self-check de seletores.');
// 53 — deploy Pages desacoplado do provisionamento de navegador
forbid('.github/workflows/pages.yml',['actions/setup-python','pip install','playwright install','test_browser_e2e.py']);
req('.github/workflows/pages.yml',['Gate essencial da release','Contrato comportamental de sincronização','Estresse operacional determinístico','Auditoria final bloqueante','Montar site estático','Validar artefato que será publicado','Smoke HTTP local do artefato','Configurar Pages','Enviar artefato','Publicar','Aguardar propagação e confirmar publicação']);
ok('r78: deploy GitHub Pages não depende de Python/Playwright/Chromium e mantém todos os gates do artefato.');

if(errors.length){console.error(`VALIDAÇÃO QuizRounds2 r78 FINAL: REPROVADA (${errors.length} erro(s), ${groups.length} grupos executados)`);errors.forEach((e,i)=>console.error(`ERRO ${i+1}: ${e}`));process.exit(1);}console.log(`VALIDAÇÃO QuizRounds2 r78 FINAL: APROVADA (${groups.length} grupos)`);groups.forEach((g,i)=>console.log(`${String(i+1).padStart(2,'0')}. ${g}`));
