import fs from 'node:fs';
import path from 'node:path';

const root=process.cwd();
const errors=[];
const read=(r)=>fs.readFileSync(path.join(root,r),'utf8');
const exists=(r)=>fs.existsSync(path.join(root,r));
const fail=(m)=>errors.push(m);

function parseVersion(){
  const raw=read('VERSION.txt');
  return Object.fromEntries(raw.split(/\r?\n/).map(x=>x.trim()).filter(x=>x.includes('=')).map(line=>{const i=line.indexOf('=');return [line.slice(0,i),line.slice(i+1)];}));
}
const meta=parseVersion();
const marker=JSON.parse(read('version.json'));
const build=String(meta.BUILD_ID||'').trim();
const release=String(meta.RELEASE||'').trim();
const ui=`3.92-${release}`;
if(!/^3\.68-r\d+$/.test(build))fail(`BUILD_ID inválido em VERSION.txt: ${build}`);
if(!/^r\d+$/.test(release))fail(`RELEASE inválida em VERSION.txt: ${release}`);
if(marker.build!==build||marker.release!==release)fail(`version.json diverge de VERSION.txt: ${marker.build}/${marker.release} != ${build}/${release}`);
if(String(meta.BACKEND_SCHEMA_REQUIRED)!=='42')fail('BACKEND_SCHEMA_REQUIRED deve permanecer 42');
if(String(meta.TEAM_FEATURE_SCHEMA_REQUIRED)!=='43')fail('TEAM_FEATURE_SCHEMA_REQUIRED deve permanecer 43');
if(String(meta.RELEASE_STATUS)!=='FINAL_STABLE')fail('RELEASE_STATUS deve ser FINAL_STABLE na release final');
if(marker.status!=='final-stable'||marker.frozen!==true)fail('version.json deve marcar status final-stable e frozen=true');

const pages=['index.html','admin.html','display.html','simulator.html','admin/index.html'];
for(const rel of pages){
  if(!exists(rel)){fail(`página ausente: ${rel}`);continue;}
  const s=read(rel);
  if(!s.includes(build))fail(`${rel}: não contém ${build}`);
}

const required=[
  `assets/js/common-v${build}.js`,
  `assets/js/avatars-v${build}.js`,
  `assets/js/city-v${build}.js`,
  `assets/js/admin-v${build}.js`,
  `assets/js/display-v${build}.js`,
  `assets/js/player-v${build}.js`,
  `assets/js/simulator-v${build}.js`,
  `assets/js/motion-v${build}.js`,
  `assets/js/pro-admin-v${build}.js`,
  `assets/js/pro-runtime-v${build}.js`,
  `assets/css/core-v${build}.css`,
  `assets/css/admin-v${build}.css`,
  `assets/css/display-v${build}.css`,
  `assets/css/simulator-v${build}.css`,
  `assets/css/avatars-runtime-v${build}.css`,
  `assets/css/motion-v${build}.css`,
  `assets/css/pro-v${build}.css`,
  `assets/css/display-ui-v${ui}.css`,
  `assets/css/player-ui-v${ui}.css`,
  `assets/css/avatars-ui-v${ui}.css`,
  `assets/maps/industry-v${build}.webp`,
  'assets/js/config.js',
  'scripts/build-pages.mjs',
  'scripts/validate-pages.mjs',
  'scripts/validate-event-stress.mjs',
  'scripts/validate-capacity-80.mjs',
  'scripts/validate-refactor.mjs',
  'scripts/validate-site-smoke.mjs',
  'tests/e2e/test_browser_e2e.py',
  'tests/e2e/requirements.txt',
  '.github/workflows/pages.yml'
];
for(const rel of required)if(!exists(rel))fail(`arquivo essencial ausente: ${rel}`);

if(exists(`assets/js/common-v${build}.js`)){
  const common=read(`assets/js/common-v${build}.js`);
  if(!common.includes(`BUILD_ID='${build}'`))fail(`common não declara BUILD_ID=${build}`);
  if(!common.includes('BACKEND_SCHEMA_REQUIRED=42'))fail('common não declara schema base 42');
}

const cfg=read('assets/js/config.js');
if(!cfg.includes('COLE_AQUI_A_URL_DO_PROJETO')||!cfg.includes('COLE_AQUI_APENAS_A_CHAVE_SB_PUBLISHABLE'))fail('config.js do repositório deve permanecer neutro; credenciais são injetadas no build');
if(/sb_secret_|service_role/i.test(cfg))fail('config.js contém chave privilegiada proibida');

// Validação de referências locais diretamente usadas pelas páginas principais.
for(const rel of ['index.html','admin.html','display.html','simulator.html']){
  const s=read(rel);
  for(const m of s.matchAll(/\b(?:src|href)=["']([^"']+)["']/gi)){
    const raw=m[1];
    if(!raw||raw.startsWith('#')||/^(?:https?:|data:|mailto:|tel:|javascript:)/i.test(raw))continue;
    const clean=raw.split('?')[0].split('#')[0];
    const target=path.normalize(path.join(path.dirname(rel),clean));
    if(!exists(target))fail(`${rel}: referência local ausente -> ${raw}`);
  }
}


// Sincronização determinística: gate bloqueante.
for(const rel of ['index.html','admin.html','display.html','simulator.html'])if(!read(rel).includes('compare(remote,local)<=0'))fail(`${rel}: proteção contra downgrade de build ausente`);
const commonRuntime=read(`assets/js/common-v${build}.js`),adminRuntime=read(`assets/js/admin-v${build}.js`),playerRuntime=read(`assets/js/player-v${build}.js`),displayRuntime=read(`assets/js/display-v${build}.js`);
if(!commonRuntime.includes('export function isOlderRoomState(')||!commonRuntime.includes('incomingGeneration<currentGeneration')||!commonRuntime.includes('state_version||0)<Number(current.state_version||0)'))fail('Common: proteção monotônica centralizada de state_version ausente');
for(const [name,s] of [['admin',adminRuntime],['player',playerRuntime],['display',displayRuntime]]){
  if(!s.includes('isOlderRoomState(data?.room,'))fail(`${name}: não usa a proteção monotônica compartilhada`);
  if(!s.includes('realtimeFallbackUntil'))fail(`${name}: fallback Realtime limitado ausente`);
}
if(!adminRuntime.includes("url.searchParams.set('qr_build',BUILD_ID)"))fail('ADM: link do jogador sem qr_build');
if(!displayRuntime.includes("url.searchParams.set('qr_build',BUILD_ID)"))fail('Telão: QR do jogador sem qr_build');

// r89: Realtime estável, Presence observacional e início sem churn.
if(!playerRuntime.includes('state_version:Number(gameState?.room?.state_version||0)'))fail('Jogador: presença sem state_version');
if(!displayRuntime.includes("kind:'display',display_id:displayPresenceId"))fail('Telão: presença enriquecida ausente');
if(!adminRuntime.includes('function presenceLagSummary()'))fail('ADM: diagnóstico de presença ausente');
if(!adminRuntime.includes('function startEventWatchdog()')||!adminRuntime.includes('function eventWatchdogTick()'))fail('ADM: watchdog diagnóstico ausente');
if(!adminRuntime.includes('displayStale')||!adminRuntime.includes('playerStale'))fail('ADM: watchdog não classifica heartbeat vencido');
if(!adminRuntime.includes('function summarizePresenceLag(')||!adminRuntime.includes('function evaluateConnectionAcks('))fail('ADM: contrato de diagnóstico/ACK ausente');
if(!adminRuntime.includes('Number(d.state_version||0)===target-1')||!adminRuntime.includes('Number(d.state_version||0)>target'))fail('ADM: diagnóstico de state_version não é estrito');
if(!adminRuntime.includes('Number(a.state_version||0)===Number(targetVersion)'))fail('ADM: ACK manual não exige state_version exato');
if(!adminRuntime.includes('expectedConnectionTargets')||!adminRuntime.includes('missingIds')||!adminRuntime.includes('extraIds'))fail('ADM: ACK manual não está preso à identidade esperada');
if(!adminRuntime.includes('displayRequired=eventModeActive')||!adminRuntime.includes('transportOk=realtimeOk||(!realtimeRequired&&rpcOk)'))fail('ADM: pré-flight diagnóstico/fallback não preservado');
const startBlock=(adminRuntime.match(/async function startQuiz\(\)\{[\s\S]*?\n\}/)||[])[0]||'';
for(const forbidden of ['stabilizeBeforeStart(','recoverEventSync(','runConnectionTest(','broadcastSyncNudge(','subscribe(','removeChannel('])if(startBlock.includes(forbidden))fail(`ADM: Começar Quiz não pode executar ${forbidden}`);
const presenceHandler=(adminRuntime.match(/\.on\('presence',\{event:'sync'\},\(\)=>\{[\s\S]*?\}\);\n  channel=main/)||[])[0]||'';
if(presenceHandler.includes('maybeAutoRecoverLag(')||presenceHandler.includes("broadcastSyncNudge('auto'"))fail('ADM: Presence ainda aciona recuperação automática');
if(adminRuntime.includes("phase()==='lobby'&&Date.now()-lastAutoPreflightAt>20000"))fail('ADM: pré-flight automático periódico voltou a ser executado');
const progressAdmin=(adminRuntime.match(/progress\.subscribe\(status=>\{[\s\S]*?\}\);/)||[])[0]||'';
if(progressAdmin.includes('scheduleReconnect('))fail('ADM: canal auxiliar de progresso ainda reinicia o canal principal');
const progressDisplay=(displayRuntime.match(/progress\.subscribe\(status=>\{[\s\S]*?\}\);/)||[])[0]||'';
if(progressDisplay.includes('scheduleReconnect('))fail('Telão: canal auxiliar de progresso ainda reinicia o canal principal');
if(!playerRuntime.includes('await trackPlayerPresence();')||!displayRuntime.includes('await trackDisplayPresence();'))fail('Presence não é republicada logo após sincronizar estado');
if(displayRuntime.includes("TELÃO RECONECTANDO — renovando presença no controle remoto"))fail('Telão ainda trata falha de Presence como queda do WebSocket');
if(!exists('scripts/validate-sync-behavior.mjs'))fail('Validação comportamental da sincronização ausente');
if(!exists('scripts/validate-event-stress.mjs'))fail('Validação de estresse operacional ausente');
const pagesWorkflow=read('.github/workflows/pages.yml');
if(/setup-python|pip install|playwright install|test_browser_e2e\.py|validate-event-stress\.mjs|validate-sync-behavior\.mjs|validate-site-smoke\.mjs/i.test(pagesWorkflow))fail('Deploy Pages contém homologação pesada; mantenha somente o caminho comprovado de publicação');
for(const token of ['Gate essencial da release','Auditoria profunda de desenvolvimento','continue-on-error: true','node scripts/build-pages.mjs','node scripts/validate-pages.mjs _site','actions/configure-pages@v5','actions/upload-pages-artifact@v4','actions/deploy-pages@v4'])if(!pagesWorkflow.includes(token))fail(`Deploy Pages sem etapa comprovada: ${token}`);
if(!exists('.github/workflows/quality.yml'))fail('Workflow dedicado de homologação técnica ausente');
else{const q=read('.github/workflows/quality.yml');for(const token of ['Homologação Técnica QuizRounds2','workflow_dispatch','node scripts/validate-sync-behavior.mjs','node scripts/validate-event-stress.mjs','node scripts/validate-build.mjs','node scripts/validate-site-smoke.mjs _site'])if(!q.includes(token))fail(`Homologação técnica incompleta: ${token}`);}
if(!exists('.github/workflows/e2e.yml'))fail('Workflow dedicado de homologação E2E ausente');
else{const e2eWorkflow=read('.github/workflows/e2e.yml');if(!e2eWorkflow.includes('mcr.microsoft.com/playwright/python:v1.55.0-noble'))fail('Workflow E2E sem imagem Playwright pré-provisionada');if(!e2eWorkflow.includes('python tests/e2e/test_browser_e2e.py .'))fail('Workflow E2E não executa os cenários de navegador');}


// r89: retomada automática da sessão do jogador após suspensão/reload móvel.
for(const token of [
  'async function join({resume=false}={})',
  "savedPlayerId=storageGet('quiz2PlayerId','')",
  'sameSavedRoom=!queryCode||queryCode===savedCode',
  'canAutoResume=!!(c&&savedName&&savedPlayerId&&sameSavedRoom)',
  'setTimeout(()=>join({resume:true}),0)',
  'async function recoverPlayerForeground({forceReconnect=false}={})',
  'foregroundRecoveryPromise',
  'backgroundedAt=Date.now()',
  "window.addEventListener('pageshow'",
  "window.addEventListener('focus'"
]) if(!playerRuntime.includes(token)) fail(`Jogador: retomada de sessão ausente -> ${token}`);
if(!marker.player_auto_resume||!marker.foreground_recovery||!marker.background_session_persistence)fail('version.json não declara persistência/retomada do jogador');

// r89: lobby do telão sem disputa horizontal e apresentação final resiliente.
const displayCss=read(`assets/css/display-ui-v${ui}.css`);
if(!displayCss.includes('display:grid;grid-template-columns:minmax(0,1fr);grid-template-rows:minmax(120px,.62fr)'))fail('Telão: lobby PIN/QR vertical não está ativo');
if(!displayCss.includes('.display-lobby-footer{width:100%;display:grid;grid-template-columns:minmax(0,1fr);grid-template-rows:auto auto auto;'))fail('Telão: números/estado do lobby ainda disputam largura horizontal');
for(const token of ['applyFinalShowRealtimeHint(payload)',"event!=='final_show_changed'","finalPresentation=state?.room?.phase==='finished'"])if(!displayRuntime.includes(token))fail(`Telão: sync final ausente -> ${token}`);
for(const token of ["broadcastSyncNudge('final-show-stage'","event:'final_show_changed'","finalShowStage()!==stage"])if(!adminRuntime.includes(token))fail(`ADM: sync final ausente -> ${token}`);
if(!marker.display_lobby_vertical_stack||!marker.display_lobby_vertical_numbers||!marker.final_show_realtime_hardening)fail('version.json não declara as correções r89 de lobby/final');

if(errors.length){
  console.error(`GATE RELEASE: REPROVADO (${errors.length})`);
  for(const e of errors)console.error(`ERRO: ${e}`);
  process.exit(1);
}

console.log(`GATE RELEASE: APROVADO — ${build} (${release})`);
