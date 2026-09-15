import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const root=process.cwd(),errors=[];
const read=r=>fs.readFileSync(path.join(root,r),'utf8');
const fail=m=>errors.push(m);
const must=(rel,tokens)=>{const s=read(rel);for(const t of tokens)if(!s.includes(t))fail(`${rel}: marcador ausente -> ${t}`);return s;};
const forbid=(rel,tokens)=>{const s=read(rel);for(const t of tokens)if(s.includes(t))fail(`${rel}: legado/duplicação encontrado -> ${t}`);};

const common=must('assets/js/common-v3.68-r90.js',['export function storageGet(','export function storageSet(','export function storageRemove(','export function jitterDelay(','export function isOlderRoomState(']);
const admin=must('assets/js/admin-v3.68-r90.js',['jitterDelay,isOlderRoomState','isOlderRoomState(data?.room,roomState?.room)']);
const player=must('assets/js/player-v3.68-r90.js',['storageGet,storageSet,storageRemove,jitterDelay,isOlderRoomState','isOlderRoomState(data?.room,gameState?.room)']);
const display=must('assets/js/display-v3.68-r90.js',['storageGet as displayStorageGet,storageSet as displayStorageSet,jitterDelay','if(seq<refreshAppliedSeq)return false;refreshAppliedSeq=seq;',"applyFinalShowRealtimeHint(payload);refresh(true);"]);

forbid('assets/js/admin-v3.68-r90.js',['function jitterDelay(','function exactPresenceIdentitySet(','function maybeAutoRecoverLag(','async function stabilizeBeforeStart(','lastAutoRecoveryAt','autoRecoveryInFlight','startStabilityBusy','startStabilityPromise']);
forbid('assets/js/player-v3.68-r90.js',['function storageGet(','function storageSet(','function storageRemove(','function jitterDelay(']);
forbid('assets/js/display-v3.68-r90.js',['function displayStorageGet(','function displayStorageSet(','function displayPollJitter(','isOlderRoomState(data?.room,state?.room)']);

const css=read('assets/css/display-ui-v3.92-r90.css');
if(!css.includes('.display-answer-line{display:flex!important;flex-flow:row nowrap!important;'))fail('Telão: resposta correta não está em uma única linha flexível.');
if(!css.includes('white-space:nowrap!important')||!css.includes('text-wrap:nowrap!important')||!css.includes('overflow-wrap:normal!important'))fail('Telão: texto da resposta ainda pode quebrar linha.');
if(/\.display-answer-line\{[^}]*flex-wrap\s*:\s*wrap/s.test(css))fail('Telão: resposta ainda permite quebra estrutural entre letra e texto.');
if(!css.includes('.display-result-panel:not(.has-ranking){grid-template-columns:minmax(0,1fr)!important}'))fail('Telão: resultado sem ranking não ocupa a largura completa.');
if((css.match(/\.display-result-text\.display-answer-showcase\{[^}]*width:min\(1000px,96%\)/g)||[]).length!==1)fail('Telão: showcase principal da resposta possui camadas CSS duplicadas.');
if(!display.includes('<span class="display-answer-line"><b class="display-answer-key">')||!display.includes('<strong class="display-answer-value">'))fail('Telão: markup letra/resposta não está agrupado.');
for(const token of ['fitDisplayAnswerLine','scheduleDisplayAnswerFit',"classList.toggle('has-ranking',showRank)"])if(!display.includes(token))fail(`Telão: ajuste dinâmico ausente -> ${token}`);

if(!css.includes('.display-lobby-grid{min-width:0;min-height:0;width:100%;height:100%;display:grid;grid-template-columns:minmax(0,1fr);'))fail('Telão: PIN e QR do lobby não estão empilhados em uma única coluna.');
if(/display-lobby-grid\{[^}]*flex-flow\s*:\s*row/s.test(css))fail('Telão: regra antiga ainda força PIN e QR lado a lado.');
if(!css.includes('.display-lobby-footer{width:100%;display:grid;grid-template-columns:minmax(0,1fr);grid-template-rows:auto auto auto;'))fail('Telão: números e status do lobby não estão empilhados verticalmente.');
for(const token of ['applyFinalShowRealtimeHint(payload)',"event!=='final_show_changed'","finalPresentation=state?.room?.phase==='finished'"])if(!display.includes(token))fail(`Telão: sincronização da apresentação final ausente -> ${token}`);
for(const token of ["broadcastSyncNudge('final-show-stage'","event:'final_show_changed'","finalShowStage()!==stage"])if(!admin.includes(token))fail(`ADM: confirmação/sincronização da apresentação final ausente -> ${token}`);


for(const token of ['async function join({resume=false}={})',"savedPlayerId=storageGet('quiz2PlayerId','')",'canAutoResume=!!(c&&savedName&&savedPlayerId&&sameSavedRoom)','async function recoverPlayerForeground({forceReconnect=false}={})','foregroundRecoveryPromise','backgroundedAt=Date.now()',"window.addEventListener('pageshow'", "window.addEventListener('focus'"])if(!player.includes(token))fail(`Jogador: retomada de foreground ausente -> ${token}`);
if(player.includes("visibilitychange',()=>{if(!document.hidden&&room){acquireTab();refresh(true);heartbeat();}}"))fail('Jogador: handler legado de visibilitychange ainda presente.');

for(const rel of ['assets/js/admin-v3.68-r90.js','assets/js/player-v3.68-r90.js','assets/js/display-v3.68-r90.js','assets/js/common-v3.68-r90.js']){
  const check=spawnSync(process.execPath,['--check',rel],{cwd:root,encoding:'utf8'});
  if(check.status!==0)fail(`${rel}: node --check falhou: ${check.stderr||check.stdout}`);
}

if(errors.length){console.error(`REFATORAÇÃO r90: REPROVADA (${errors.length})`);errors.forEach((e,i)=>console.error(`ERRO ${i+1}: ${e}`));process.exit(1);}
console.log('REFATORAÇÃO r90: APROVADA — telão com transição autoritativa baseada na r67, lobby vertical, apresentação final sincronizada, resposta em uma linha e retomada automática do jogador.');
