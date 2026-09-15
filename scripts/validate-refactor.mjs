import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const root=process.cwd(),errors=[];
const read=r=>fs.readFileSync(path.join(root,r),'utf8');
const fail=m=>errors.push(m);
const must=(rel,tokens)=>{const s=read(rel);for(const t of tokens)if(!s.includes(t))fail(`${rel}: marcador ausente -> ${t}`);return s;};
const forbid=(rel,tokens)=>{const s=read(rel);for(const t of tokens)if(s.includes(t))fail(`${rel}: legado/duplicação encontrado -> ${t}`);};

const common=must('assets/js/common-v3.68-r86.js',['export function storageGet(','export function storageSet(','export function storageRemove(','export function jitterDelay(','export function isOlderRoomState(']);
const admin=must('assets/js/admin-v3.68-r86.js',['jitterDelay,isOlderRoomState','isOlderRoomState(data?.room,roomState?.room)']);
const player=must('assets/js/player-v3.68-r86.js',['storageGet,storageSet,storageRemove,jitterDelay,isOlderRoomState','isOlderRoomState(data?.room,gameState?.room)']);
const display=must('assets/js/display-v3.68-r86.js',['storageGet as displayStorageGet,storageSet as displayStorageSet,jitterDelay,isOlderRoomState','isOlderRoomState(data?.room,state?.room)']);

forbid('assets/js/admin-v3.68-r86.js',['function jitterDelay(','function exactPresenceIdentitySet(','function maybeAutoRecoverLag(','async function stabilizeBeforeStart(','lastAutoRecoveryAt','autoRecoveryInFlight','startStabilityBusy','startStabilityPromise']);
forbid('assets/js/player-v3.68-r86.js',['function storageGet(','function storageSet(','function storageRemove(','function jitterDelay(']);
forbid('assets/js/display-v3.68-r86.js',['function displayStorageGet(','function displayStorageSet(','function displayPollJitter(']);

const css=read('assets/css/display-ui-v3.92-r86.css');
if(!css.includes('.display-answer-line{display:flex!important;flex-flow:row nowrap!important;'))fail('Telão: resposta correta não está em uma única linha flexível.');
if(!css.includes('white-space:nowrap!important')||!css.includes('text-wrap:nowrap!important')||!css.includes('overflow-wrap:normal!important'))fail('Telão: texto da resposta ainda pode quebrar linha.');
if(/\.display-answer-line\{[^}]*flex-wrap\s*:\s*wrap/s.test(css))fail('Telão: resposta ainda permite quebra estrutural entre letra e texto.');
if(!css.includes('.display-result-panel:not(.has-ranking){grid-template-columns:minmax(0,1fr)!important}'))fail('Telão: resultado sem ranking não ocupa a largura completa.');
if((css.match(/\.display-result-text\.display-answer-showcase\{[^}]*width:min\(1000px,96%\)/g)||[]).length!==1)fail('Telão: showcase principal da resposta possui camadas CSS duplicadas.');
if(!display.includes('<span class="display-answer-line"><b class="display-answer-key">')||!display.includes('<strong class="display-answer-value">'))fail('Telão: markup letra/resposta não está agrupado.');
for(const token of ['fitDisplayAnswerLine','scheduleDisplayAnswerFit',"classList.toggle('has-ranking',showRank)"])if(!display.includes(token))fail(`Telão: ajuste dinâmico ausente -> ${token}`);

for(const rel of ['assets/js/admin-v3.68-r86.js','assets/js/player-v3.68-r86.js','assets/js/display-v3.68-r86.js','assets/js/common-v3.68-r86.js']){
  const check=spawnSync(process.execPath,['--check',rel],{cwd:root,encoding:'utf8'});
  if(check.status!==0)fail(`${rel}: node --check falhou: ${check.stderr||check.stdout}`);
}

if(errors.length){console.error(`REFATORAÇÃO r86: REPROVADA (${errors.length})`);errors.forEach((e,i)=>console.error(`ERRO ${i+1}: ${e}`));process.exit(1);}
console.log('REFATORAÇÃO r86: APROVADA — utilitários consolidados, layout de resultado por estado e resposta completa do telão em uma única linha.');
