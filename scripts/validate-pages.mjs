import fs from 'node:fs';
import path from 'node:path';

const root=path.resolve(process.argv[2]||'_site');
const errors=[];
const req=(rel)=>{const p=path.join(root,rel);if(!fs.existsSync(p))errors.push(`ausente: ${rel}`);return p;};
const read=(rel)=>fs.readFileSync(req(rel),'utf8');

for(const rel of ['index.html','admin.html','display.html','simulator.html','admin/index.html','version.json','VERSION.txt','assets/js/config.js'])req(rel);
const marker=JSON.parse(read('version.json'));
const versionRaw=read('VERSION.txt');
const meta=Object.fromEntries(versionRaw.split(/\r?\n/).map(line=>line.trim()).filter(line=>line.includes('=')).map(line=>{const i=line.indexOf('=');return[line.slice(0,i),line.slice(i+1)];}));
const build=String(meta.BUILD_ID||'').trim(),release=String(meta.RELEASE||'').trim();
if(!/^3\.68-r\d+$/.test(build)||!/^r\d+$/.test(release))errors.push('VERSION.txt sem release/build válidos');
if(marker.build!==build||marker.release!==release)errors.push(`version.json diverge de VERSION.txt (${marker.build}/${marker.release} != ${build}/${release})`);
for(const rel of ['index.html','admin.html','display.html','simulator.html','admin/index.html']){
  const s=read(rel);if(!s.includes(build))errors.push(`${rel}: marcador ${build} ausente`);
}
const config=read('assets/js/config.js');
if(!config.includes('sb_publishable_'))errors.push('config.js publicado sem Publishable Key');
if(/sb_secret_|service_role/i.test(config))errors.push('config.js publicado contém chave proibida');
if(config.includes('COLE_AQUI_'))errors.push('config.js publicado ainda contém placeholder');
const commonRel=`assets/js/common-v${build}.js`;req(commonRel);
const common=read(commonRel);
if(!common.includes(`BUILD_ID='${build}'`))errors.push(`${commonRel}: BUILD_ID não corresponde a ${build}`);
if(errors.length){console.error(`VALIDAÇÃO _site: REPROVADA (${errors.length})`);for(const e of errors)console.error(`ERRO: ${e}`);process.exit(1);}
console.log(`VALIDAÇÃO _site: APROVADA — ${build} (${release}) pronta para upload-pages-artifact.`);
