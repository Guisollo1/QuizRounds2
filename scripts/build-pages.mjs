import fs from 'node:fs';
import path from 'node:path';

const root=process.cwd();
const out=path.join(root,'_site');
const url=String(process.env.SUPABASE_URL||'').trim();
const key=String(process.env.SUPABASE_PUBLISHABLE_KEY||'').trim();

function fail(message){console.error(`BUILD PAGES: ${message}`);process.exit(1);}
function parseVersionFile(){
  const raw=fs.readFileSync(path.join(root,'VERSION.txt'),'utf8');
  return Object.fromEntries(raw.split(/\r?\n/).map(line=>line.trim()).filter(line=>line.includes('=')).map(line=>{const i=line.indexOf('=');return[line.slice(0,i),line.slice(i+1)];}));
}
const meta=parseVersionFile();
const marker=JSON.parse(fs.readFileSync(path.join(root,'version.json'),'utf8'));
const build=String(meta.BUILD_ID||'').trim();
const release=String(meta.RELEASE||'').trim();
if(!/^3\.68-r\d+$/.test(build)||!/^r\d+$/.test(release))fail('VERSION.txt sem BUILD_ID/RELEASE válidos.');
if(marker.build!==build||marker.release!==release)fail(`version.json diverge de VERSION.txt (${marker.build}/${marker.release} != ${build}/${release}).`);
if(!/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/i.test(url))fail('SUPABASE_URL ausente ou inválida.');
if(!/^sb_publishable_[A-Za-z0-9_-]+$/.test(key))fail('SUPABASE_PUBLISHABLE_KEY ausente ou inválida. Use somente sb_publishable_.');
if(/sb_secret_|service_role/i.test(key))fail('Chave privilegiada proibida no frontend.');

fs.rmSync(out,{recursive:true,force:true});
fs.mkdirSync(out,{recursive:true});
for(const file of ['index.html','admin.html','display.html','simulator.html','version.json','VERSION.txt']){
  fs.copyFileSync(path.join(root,file),path.join(out,file));
}
for(const dir of ['admin','assets'])fs.cpSync(path.join(root,dir),path.join(out,dir),{recursive:true});
fs.writeFileSync(path.join(out,'.nojekyll'),'');
fs.writeFileSync(path.join(out,'assets/js/config.js'),
  `export const SUPABASE_URL=${JSON.stringify(url)};\nexport const SUPABASE_PUBLISHABLE_KEY=${JSON.stringify(key)};\n`);
console.log(`BUILD PAGES: _site criado para QuizRounds2 ${build} (${release}).`);
