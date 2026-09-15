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
if(typeof summarize!=='function'||typeof evaluate!=='function'||typeof expectedTargets!=='function')throw new Error('Contrato de sincronização r86 incompleto.');

let passed=0;
const tests=[];
const test=(name,fn)=>tests.push([name,fn]);
const assert=(v,msg)=>{if(!v)throw new Error(msg);};
const eq=(a,b,msg)=>assert(a===b,`${msg}: esperado ${b}, recebido ${a}`);
const now=1_000_000;
const participant=(id,state=50,generation=7,at=now,bd=build)=>({kind:'participant',id:`p${id}`,state_version:state,generation,at,build:bd});
const display=(state=50,generation=7,at=now,bd=build)=>({kind:'display',id:'display-main',state_version:state,generation,at,build:bd});
const ackParticipant=(id,state=50,generation=7,bd=build,at=now)=>({kind:'participant',participant_id:`p${id}`,state_version:state,generation,build:bd,at});
const ackDisplay=(state=50,generation=7,bd=build,at=now)=>({kind:'display',display_id:'display-main',state_version:state,generation,build:bd,at});
const expected101=()=>[...Array.from({length:100},(_,i)=>`participant:p${i+1}`),'display:display-main'];

// 100 jogadores + telão.
test('100 jogadores + telão exatos ficam sincronizados',()=>{const r=summarize([...Array.from({length:100},(_,i)=>participant(i+1)),display()],50,7,now,build);eq(r.synced,101,'synced');eq(r.lagging,0,'lagging');eq(r.ahead,0,'ahead');});
test('um jogador um estado atrás bloqueia',()=>{const r=summarize([...Array.from({length:100},(_,i)=>participant(i+1,i===36?49:50)),display()],50,7,now,build);eq(r.synced,100,'synced');eq(r.converging,1,'converging');eq(r.lagging,1,'lagging');});
test('um jogador à frente também bloqueia',()=>{const r=summarize([...Array.from({length:100},(_,i)=>participant(i+1,i===36?51:50)),display()],50,7,now,build);eq(r.synced,100,'synced');eq(r.ahead,1,'ahead');eq(r.lagging,1,'lagging');});
test('telão stale é detectado',()=>{const r=summarize([...Array.from({length:100},(_,i)=>participant(i+1)),display(50,7,now-30000)],50,7,now,build);eq(r.displayStale,1,'displayStale');eq(r.stale,1,'stale');eq(r.synced,100,'players synced');});
test('build estrangeiro não entra como sincronizado',()=>{const r=summarize([participant(1),participant(2,50,7,now,'3.68-r1'),display()],50,7,now,build);eq(r.foreignBuild,1,'foreignBuild');eq(r.synced,2,'same-build synced');});
test('presença duplicada usa heartbeat mais recente',()=>{const r=summarize([participant(1,49,7,now-1000),participant(1,50,7,now),display()],50,7,now,build);eq(r.known,2,'known');eq(r.synced,2,'synced');eq(r.lagging,0,'lagging');});
test('generation anterior é inicialização',()=>{const r=summarize([...Array.from({length:100},(_,i)=>participant(i+1,50,6)),display(50,6)],50,7,now,build);eq(r.initializing,101,'initializing');eq(r.synced,0,'synced');eq(r.lagging,101,'lagging');});
test('fronteiras de heartbeat permanecem estritas',()=>{eq(summarize([display(50,7,now-29999)],50,7,now,build).stale,0,'display fresh');eq(summarize([display(50,7,now-30000)],50,7,now,build).stale,1,'display stale');eq(summarize([participant(1,50,7,now-35999)],50,7,now,build).stale,0,'player fresh');eq(summarize([participant(1,50,7,now-36000)],50,7,now,build).stale,1,'player stale');});

test('ACK de 100 jogadores + telão aprova por identidade',()=>{const rows=[...Array.from({length:100},(_,i)=>ackParticipant(i+1)),ackDisplay()],r=evaluate(rows,expected101(),50,7,build);assert(r.complete,'deveria aprovar');eq(r.synced,101,'synced');eq(r.missing,0,'missing');});
test('um ACK ausente entre 101 reprova',()=>{const rows=[...Array.from({length:99},(_,i)=>ackParticipant(i+1)),ackDisplay()],r=evaluate(rows,expected101(),50,7,build);assert(!r.complete,'não pode aprovar');eq(r.missing,1,'missing');});
test('substituir p100 por p101 extra não mascara ausência',()=>{const rows=[...Array.from({length:99},(_,i)=>ackParticipant(i+1)),ackParticipant(101),ackDisplay()],r=evaluate(rows,expected101(),50,7,build);assert(!r.complete,'substituição não pode aprovar');eq(r.missing,1,'missing');eq(r.extra,1,'extra');assert(r.missingIds.includes('participant:p100'),'p100 deveria faltar');});
test('um ACK atrasado reprova',()=>{const rows=[...Array.from({length:100},(_,i)=>ackParticipant(i+1,i===74?49:50)),ackDisplay()],r=evaluate(rows,expected101(),50,7,build);assert(!r.complete,'atrasado não pode aprovar');eq(r.lagging,1,'lagging');});
test('um ACK à frente reprova',()=>{const rows=[...Array.from({length:100},(_,i)=>ackParticipant(i+1,i===74?51:50)),ackDisplay()],r=evaluate(rows,expected101(),50,7,build);assert(!r.complete,'ahead não pode aprovar');eq(r.ahead,1,'ahead');});
test('um ACK de build errado reprova',()=>{const rows=[...Array.from({length:100},(_,i)=>ackParticipant(i+1,50,7,i===11?'3.68-r1':build)),ackDisplay()],r=evaluate(rows,expected101(),50,7,build);assert(!r.complete,'build errado não pode aprovar');eq(r.wrongBuild,1,'wrongBuild');});

test('20 transições com 101 aparelhos não aceitam atrás nem à frente',()=>{for(let version=51;version<=70;version++){const exact=[...Array.from({length:100},(_,i)=>participant(i+1,version)),display(version)],sr=summarize(exact,version,7,now,build);eq(sr.synced,101,`v${version} synced`);eq(sr.lagging,0,`v${version} lagging`);const behind=[...exact];behind[version%100]={...behind[version%100],state_version:version-1};eq(summarize(behind,version,7,now,build).lagging,1,`v${version} behind`);const ahead=[...exact];ahead[(version+17)%100]={...ahead[(version+17)%100],state_version:version+1};eq(summarize(ahead,version,7,now,build).ahead,1,`v${version} ahead`);const acks=[...Array.from({length:100},(_,i)=>ackParticipant(i+1,version)),ackDisplay(version)];assert(evaluate(acks,expected101(),version,7,build).complete,`v${version} exact ACK`);acks[version%100]={...acks[version%100],state_version:version-1};assert(!evaluate(acks,expected101(),version,7,build).complete,`v${version} behind ACK`);}});

test('runtime usa snapshot de identidade, early-completion e deadline adaptativo',()=>{assert(src.includes('connectionExpectedTargets=expectedConnectionTargets'),'snapshot de identidades ausente');assert(src.includes('matched>=connectionExpectedTargets.length'),'early completion ausente');assert(src.includes('Math.max(2500,Math.min(8000'),'deadline adaptativo ausente');assert(src.includes('result.extra'),'respostas extras não são reportadas');});

for(const [name,fn] of tests){try{fn();passed++;console.log(`✓ ${name}`);}catch(e){console.error(`✗ ${name}: ${e.message}`);process.exitCode=1;}}
if(process.exitCode)process.exit(1);

// Fuzz por propriedade, com identidade esperada explícita.
let seed=0x76c0ffee;
const rnd=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/0x100000000;};
let ackFuzz=0,presenceFuzz=0;
for(let n=0;n<6000;n++){
  const expectedCount=Math.floor(rnd()*102),target=1+Math.floor(rnd()*500),gen=1+Math.floor(rnd()*10),expected=Array.from({length:expectedCount},(_,i)=>`participant:p${i}`),rows=[];
  const produced=Math.floor(rnd()*105);
  for(let i=0;i<produced;i++){
    const expectedId=i<expectedCount&&rnd()<.8?i:expectedCount+Math.floor(rnd()*5),mode=Math.floor(rnd()*7);
    rows.push({kind:'participant',participant_id:`p${expectedId}`,build:mode===5?'3.68-r1':build,state_version:mode===0?target:mode===1?target-1:mode===2?target+1:mode===3?0:target,generation:mode===4?gen-1:gen,at:i});
  }
  const r=evaluate(rows,expected,target,gen,build),latest=new Map();
  for(const row of rows)latest.set(`participant:${row.participant_id}`,row);
  let independent=true;
  for(const id of expected){const row=latest.get(id);if(!row||row.build!==build||Number(row.generation)!==gen||Number(row.state_version)!==target){independent=false;break;}}
  if(r.complete!==independent)throw new Error(`Fuzz ACK divergente no cenário ${n}: complete=${r.complete}, esperado=${independent}`);
  ackFuzz++;
}
for(let n=0;n<4000;n++){
  const target=1+Math.floor(rnd()*500),gen=1+Math.floor(rnd()*10),count=1+Math.floor(rnd()*101),devices=[];
  for(let i=0;i<count;i++){
    const kind=i===count-1&&rnd()<.2?'display':'participant',ttl=kind==='display'?30000:36000,mode=Math.floor(rnd()*8);
    devices.push({kind,id:`${kind}-${i}`,build:mode===7?'3.68-r1':build,state_version:mode===0?0:mode===1?target-1:mode===2?Math.max(1,target-2):mode===3?target+1:target,generation:mode===4?gen-1:gen,at:now-(mode===5?ttl:Math.floor(rnd()*(ttl-1)))});
  }
  const r=summarize(devices,target,gen,now,build);
  assert(r.synced+r.lagging+r.stale+r.foreignBuild<=count,'classificação excedeu total');
  assert(r.synced>=0&&r.lagging>=0&&r.ahead>=0&&r.stale>=0&&r.foreignBuild>=0,'contagem negativa');
  if(r.lagging===0&&r.stale===0&&r.foreignBuild===0)eq(r.synced,count,'todos elegíveis deveriam estar exatos');
  presenceFuzz++;
}

console.log(`VALIDAÇÃO DE ESTRESSE OPERACIONAL: APROVADA (${passed}/${tests.length} testes determinísticos + ${ackFuzz+presenceFuzz} cenários aleatórios + 20 transições com 101 aparelhos) — ${build}`);
