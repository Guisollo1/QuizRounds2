import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const root=process.cwd();
const meta=Object.fromEntries(fs.readFileSync(path.join(root,'VERSION.txt'),'utf8').split(/\r?\n/).filter(x=>x.includes('=')).map(line=>{const i=line.indexOf('=');return[line.slice(0,i),line.slice(i+1)];}));
const build=String(meta.BUILD_ID||'').trim();
const adminRel=`assets/js/admin-v${build}.js`;
const src=fs.readFileSync(path.join(root,adminRel),'utf8');
const begin='// SYNC_CONTRACT_BEGIN',end='// SYNC_CONTRACT_END';
const a=src.indexOf(begin),b=src.indexOf(end);
if(a<0||b<a)throw new Error('Bloco SYNC_CONTRACT não encontrado no runtime ADM.');
const context={BUILD_ID:build,Date,Math,Number,String,Array,Map,Set};
vm.createContext(context);
vm.runInContext(src.slice(a+begin.length,b),context,{filename:adminRel});
const summarize=context.summarizePresenceLag;
const evaluate=context.evaluateConnectionAcks;
const expectedTargets=context.expectedConnectionTargets;
if(typeof summarize!=='function'||typeof evaluate!=='function'||typeof expectedTargets!=='function')throw new Error('Funções do contrato r81 não foram carregadas.');

let passed=0;
const tests=[];
const test=(name,fn)=>tests.push([name,fn]);
const eq=(actual,expected,msg)=>{if(actual!==expected)throw new Error(`${msg}: esperado ${expected}, recebido ${actual}`);};
const ok=(v,msg)=>{if(!v)throw new Error(msg);};
const device=({kind='participant',id='p1',build:bd=build,state_version=10,generation=2,at=100000}={})=>({kind,id,build:bd,state_version,generation,at});
const ack=({kind='participant',participant_id='p1',display_id='',build:bd=build,state_version=10,generation=2,at=100000}={})=>({kind,participant_id,display_id,build:bd,state_version,generation,at});
const ids=(...values)=>values;

// Presence: somente igualdade exata é sincronizada.
test('presença no state_version exato é sincronizada',()=>{const r=summarize([device()],10,2,100000,build);eq(r.synced,1,'synced');eq(r.lagging,0,'lagging');eq(r.ahead,0,'ahead');});
test('um state_version atrás é convergindo e bloqueante',()=>{const r=summarize([device({state_version:9})],10,2,100000,build);eq(r.converging,1,'converging');eq(r.lagging,1,'lagging');eq(r.synced,0,'synced');});
test('dois state_versions atrás é atraso forte',()=>{const r=summarize([device({state_version:8})],10,2,100000,build);eq(r.hardLagging,1,'hardLagging');eq(r.lagging,1,'lagging');});
test('state_version à frente é divergente, nunca sincronizado',()=>{const r=summarize([device({state_version:11})],10,2,100000,build);eq(r.ahead,1,'ahead');eq(r.lagging,1,'lagging');eq(r.synced,0,'synced');eq(r.aheadRows[0].aheadBy,1,'aheadBy');});
test('state_version zero é explicitamente inicializando',()=>{const r=summarize([device({state_version:0})],10,2,100000,build);eq(r.initializing,1,'initializing');eq(r.lagging,1,'lagging');});
test('generation antiga é inicializando, nunca sincronizada',()=>{const r=summarize([device({generation:1})],10,2,100000,build);eq(r.initializing,1,'initializing');eq(r.synced,0,'synced');});
test('heartbeat vencido vira stale',()=>{const r=summarize([device({at:50000})],10,2,100000,build);eq(r.stale,1,'stale');eq(r.playerStale,1,'playerStale');});

// Identidades esperadas são congeladas no início do teste.
test('snapshot de identidades deduplica jogador e telão',()=>{const r=expectedTargets([device({id:'p1'}),device({id:'p1',at:99999}),device({kind:'display',id:'d1'})]);eq(r.length,2,'targets');ok(r.includes('participant:p1'),'p1 ausente');ok(r.includes('display:d1'),'display ausente');});

// ACK: nenhuma resposta pode substituir outra identidade.
test('ACK completo e exato aprova',()=>{const expected=ids('participant:p1','participant:p2');const r=evaluate([ack({participant_id:'p1'}),ack({participant_id:'p2'})],expected,10,2,build);eq(r.complete,true,'complete');eq(r.synced,2,'synced');eq(r.missing,0,'missing');});
test('ACK ausente reprova pela identidade faltante',()=>{const expected=ids('participant:p1','participant:p2','participant:p3');const r=evaluate([ack({participant_id:'p1'}),ack({participant_id:'p2'})],expected,10,2,build);eq(r.complete,false,'complete');eq(r.missing,1,'missing');eq(r.missingIds[0],'participant:p3','missing id');});
test('ACK extra não substitui identidade esperada',()=>{const expected=ids('participant:p1','participant:p2','display:d1');const rows=[ack({participant_id:'p1'}),ack({participant_id:'p3'}),ack({kind:'display',participant_id:'',display_id:'d1'})];const r=evaluate(rows,expected,10,2,build);eq(r.complete,false,'complete');eq(r.missing,1,'missing');eq(r.extra,1,'extra');eq(r.missingIds[0],'participant:p2','identidade faltante');});
test('ACK duplicado do mesmo jogador não aumenta respondedores esperados',()=>{const expected=ids('participant:p1','participant:p2');const r=evaluate([ack({participant_id:'p1',at:1}),ack({participant_id:'p1',at:2}),ack({participant_id:'p2',at:3})],expected,10,2,build);eq(r.complete,true,'complete');eq(r.responders,2,'responders deduplicados');eq(r.received,2,'received deduplicado');});
test('ACK um estado atrás reprova',()=>{const r=evaluate([ack({state_version:9})],ids('participant:p1'),10,2,build);eq(r.complete,false,'complete');eq(r.lagging,1,'lagging');});
test('ACK inicializando reprova',()=>{const r=evaluate([ack({state_version:0})],ids('participant:p1'),10,2,build);eq(r.complete,false,'complete');eq(r.initializing,1,'initializing');});
test('ACK em estado à frente reprova',()=>{const r=evaluate([ack({state_version:11})],ids('participant:p1'),10,2,build);eq(r.complete,false,'complete');eq(r.ahead,1,'ahead');});
test('ACK de build diferente reprova',()=>{const r=evaluate([ack({build:'3.68-r1'})],ids('participant:p1'),10,2,build);eq(r.complete,false,'complete');eq(r.wrongBuild,1,'wrongBuild');});

for(const [name,fn] of tests){try{fn();passed++;console.log(`✓ ${name}`);}catch(e){console.error(`✗ ${name}: ${e.message}`);process.exitCode=1;}}
if(process.exitCode)process.exit(1);
console.log(`VALIDAÇÃO COMPORTAMENTAL DA SINCRONIZAÇÃO: APROVADA (${passed}/${tests.length}) — ${build}`);
