import fs from 'node:fs';
import path from 'node:path';

const root=path.resolve(process.argv[2]||'_site');
const errors=[];
const req=(rel)=>{const p=path.join(root,rel);if(!fs.existsSync(p))errors.push(`ausente: ${rel}`);return p;};
const read=(rel)=>fs.readFileSync(req(rel),'utf8');

for(const rel of ['index.html','admin.html','display.html','simulator.html','admin/index.html','version.json','VERSION.txt','assets/js/config.js','assets/js/common-v3.68-r64.js'])req(rel);
for(const rel of ['index.html','admin.html','display.html','simulator.html','admin/index.html']){
  const s=read(rel);if(!s.includes('3.68-r64'))errors.push(`${rel}: marcador 3.68-r64 ausente`);
}
const marker=JSON.parse(read('version.json'));
if(marker.build!=='3.68-r64'||marker.release!=='r64')errors.push('version.json não identifica r64/3.68-r64');
const config=read('assets/js/config.js');
if(!config.includes('sb_publishable_'))errors.push('config.js publicado sem Publishable Key');
if(/sb_secret_|service_role/i.test(config))errors.push('config.js publicado contém chave proibida');
if(config.includes('COLE_AQUI_'))errors.push('config.js publicado ainda contém placeholder');
const common=read('assets/js/common-v3.68-r64.js');
if(!common.includes("BUILD_ID='3.68-r64'"))errors.push('common.js publicado não é r64');
if(errors.length){console.error(`VALIDAÇÃO _site: REPROVADA (${errors.length})`);for(const e of errors)console.error(`ERRO: ${e}`);process.exit(1);}
console.log('VALIDAÇÃO _site: APROVADA — r64 pronta para upload-pages-artifact.');
