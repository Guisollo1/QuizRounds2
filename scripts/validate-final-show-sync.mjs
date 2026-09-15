import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const root=process.cwd();
const meta=Object.fromEntries(fs.readFileSync(path.join(root,'VERSION.txt'),'utf8').split(/\r?\n/).filter(x=>x.includes('=')).map(line=>{const i=line.indexOf('=');return[line.slice(0,i),line.slice(i+1)];}));
const build=String(meta.BUILD_ID||'').trim();
const rel=`assets/js/display-v${build}.js`;
const src=fs.readFileSync(path.join(root,rel),'utf8');
const match=src.match(/function applyFinalShowRealtimeHint\(payload\)\{[^\n]+\}/);
if(!match)throw new Error('applyFinalShowRealtimeHint não encontrada no runtime do telão.');

let renders=0,tech=0;
const context={state:{room:{phase:'finished',settings:{final_show_stage:'ranking'}}},renderFinalShowcase:()=>{renders++;},renderDisplayTech:()=>{tech++;},String};
vm.createContext(context);
vm.runInContext(`${match[0]};this.applyHint=applyFinalShowRealtimeHint;`,context,{filename:rel});
const apply=context.applyHint;
let passed=0;
const ok=(cond,msg)=>{if(!cond)throw new Error(msg);passed++;};

let changed=apply({event:'final_show_changed',stage:'stats',state_version:22});
ok(changed===true&&context.state.room.settings.final_show_stage==='stats'&&renders===1&&tech===1,'broadcast final_show_changed não aplicou Estatísticas imediatamente');
changed=apply({event:'final_show_changed',stage:'invalid'});
ok(changed===false&&context.state.room.settings.final_show_stage==='stats'&&renders===1,'etapa inválida não foi ignorada');
context.state.room.phase='result';
changed=apply({event:'final_show_changed',stage:'highlights'});
ok(changed===false&&context.state.room.settings.final_show_stage==='stats','hint final foi aplicado fora da fase finished');
context.state.room.phase='finished';
changed=apply({final_show_stage:'champion'});
ok(changed===true&&context.state.room.settings.final_show_stage==='champion'&&renders===2&&tech===2,'nudge de convergência não aplicou etapa final');

console.log(`VALIDAÇÃO FINAL SHOW: APROVADA (${passed}/4) — ${build}`);
