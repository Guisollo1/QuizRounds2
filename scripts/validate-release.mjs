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
const adminRuntime=read(`assets/js/admin-v${build}.js`),playerRuntime=read(`assets/js/player-v${build}.js`),displayRuntime=read(`assets/js/display-v${build}.js`);
for(const [name,s] of [['admin',adminRuntime],['player',playerRuntime],['display',displayRuntime]]){
  if(!s.includes('incomingVersion<currentVersion'))fail(`${name}: proteção monotônica de state_version ausente`);
  if(!s.includes('realtimeFallbackUntil'))fail(`${name}: fallback Realtime limitado ausente`);
}
if(!adminRuntime.includes("url.searchParams.set('qr_build',BUILD_ID)"))fail('ADM: link do jogador sem qr_build');
if(!displayRuntime.includes("url.searchParams.set('qr_build',BUILD_ID)"))fail('Telão: QR do jogador sem qr_build');

// r77: observabilidade, watchdog, ACK exato e pré-flight operacional.
if(!playerRuntime.includes('state_version:Number(gameState?.room?.state_version||0)'))fail('Jogador: presença sem state_version');
if(!playerRuntime.includes("kind:'participant',participant_id:me.id,session_id:tabId,reconnect_epoch:connectionEpoch,build:BUILD_ID,state_version"))fail('Jogador: ACK de sincronização sem sessão/estado/build');
if(!displayRuntime.includes("kind:'display',display_id:displayPresenceId"))fail('Telão: presença/ACK enriquecido ausente');
if(!displayRuntime.includes("event:'connection_test'"))fail('Telão: não responde ao teste de conexão');
if(playerRuntime.includes("event:'connection_test'},async({payload})=>{if(epoch!==connectionEpoch)return;try{await heartbeat()"))fail('Jogador: teste de conexão ainda dispara heartbeat RPC em massa');
if(displayRuntime.includes("event:'connection_test'},async({payload})=>{if(epoch!==subscriptionEpoch)return;try{await refresh(false);await trackDisplayPresence()"))fail('Telão: teste de conexão ainda faz refresh/track incondicional');
if(!adminRuntime.includes('function presenceLagSummary()'))fail('ADM: diagnóstico de atraso de estado ausente');
if(!adminRuntime.includes("connectionAcks=new Map()"))fail('ADM: teste de sincronização detalhado ausente');
if(!adminRuntime.includes('syncOk=lag.lagging===0'))fail('ADM: pré-teste não considera convergência dos aparelhos');
if(!adminRuntime.includes('function recoverEventSync('))fail('ADM: recuperação coordenada de sincronização ausente');
if(!adminRuntime.includes('function stabilizeBeforeStart('))fail('ADM: janela de estabilidade antes do início ausente');
if(!adminRuntime.includes('function maybeAutoRecoverLag('))fail('ADM: auto-recuperação controlada ausente');
if(!adminRuntime.includes('Sincronização bloqueou o início'))fail('ADM: bloqueio de início por aparelhos atrasados ausente');
if(!read('admin.html').includes('id="healthSync"')||!read('admin.html').includes('id="startSyncCheck"'))fail('ADM: indicadores visuais de sincronização ausentes');

if(!playerRuntime.includes('session_id:tabId,reconnect_epoch:connectionEpoch'))fail('Jogador: identidade de sessão da presença ausente');
if(!adminRuntime.includes('function startEventWatchdog()')||!adminRuntime.includes('function eventWatchdogTick()'))fail('ADM: watchdog operacional ausente');
if(!adminRuntime.includes('displayStale')||!adminRuntime.includes('playerStale'))fail('ADM: watchdog não classifica heartbeat vencido');
if(!adminRuntime.includes('runPreflight({silent:true,quick:true})'))fail('ADM: pré-flight automático periódico ausente');
if(!adminRuntime.includes("phase()==='lobby'&&Date.now()-lastAutoPreflightAt>20000"))fail('ADM: cadência segura do pré-flight automático ausente');
if(!adminRuntime.includes("displayRequired=eventModeActive"))fail('ADM: telão não vira gate crítico no modo Evento');
if(!adminRuntime.includes('dedup=new Map()'))fail('ADM: deduplicação de presença por aparelho/jogador ausente');
if(!adminRuntime.includes('function summarizePresenceLag(')||!adminRuntime.includes('function evaluateConnectionAcks('))fail('ADM: contrato puro de sincronização r77 ausente');
if(!adminRuntime.includes('Number(d.state_version||0)<=0')||!adminRuntime.includes('Number(d.state_version||0)===target-1')||!adminRuntime.includes('Number(d.state_version||0)>target'))fail('ADM: state_version zero/atrás/à frente não estão classificados de forma estrita');
if(!adminRuntime.includes('Number(a.state_version||0)===Number(targetVersion)'))fail('ADM: ACK não exige state_version exato');
if(!adminRuntime.includes('expectedConnectionTargets')||!adminRuntime.includes('missingIds')||!adminRuntime.includes('extraIds'))fail('ADM: ACK não está preso à identidade esperada');
if(!adminRuntime.includes('matched>=connectionExpectedTargets.length')||!adminRuntime.includes('Math.max(2500,Math.min(8000'))fail('ADM: early-completion/deadline adaptativo ausentes');
if(!adminRuntime.includes('test?.complete&&sameTarget')||!adminRuntime.includes('test.synced||0)===Number(test.responders||0)'))fail('ADM: recuperação pode aprovar ACK incompleto ou alvo obsoleto');
if(!adminRuntime.includes("Modo Evento exige Realtime conectado")||!adminRuntime.includes('fallback:true'))fail('ADM: fallback controlado/Modo Evento estrito ausente');
if(!adminRuntime.includes('transportOk=realtimeOk||(!realtimeRequired&&rpcOk)'))fail('ADM: pré-flight não diferencia fallback normal de Modo Evento');
if(!adminRuntime.includes('const ok=await refreshState(false)'))fail('ADM: pré-flight automático não atualiza o estado antes de classificar');
if(!exists('scripts/validate-sync-behavior.mjs'))fail('Validação comportamental da sincronização ausente');
if(!exists('scripts/validate-event-stress.mjs'))fail('Validação de estresse operacional ausente');
if(!read('.github/workflows/pages.yml').includes('node scripts/validate-event-stress.mjs'))fail('Workflow não executa o estresse operacional bloqueante');
if(!read('.github/workflows/pages.yml').includes('node scripts/validate-site-smoke.mjs _site'))fail('Workflow não executa o smoke HTTP bloqueante do artefato');
if(!read('.github/workflows/pages.yml').includes('python tests/e2e/test_browser_e2e.py _site'))fail('Workflow não executa o E2E Chromium bloqueante');
if(!read('.github/workflows/pages.yml').includes('python -m playwright install --with-deps chromium'))fail('Workflow não instala Chromium do Playwright');

if(errors.length){
  console.error(`GATE RELEASE: REPROVADO (${errors.length})`);
  for(const e of errors)console.error(`ERRO: ${e}`);
  process.exit(1);
}

console.log(`GATE RELEASE: APROVADO — ${build} (${release})`);
