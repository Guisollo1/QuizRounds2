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

if(errors.length){
  console.error(`GATE RELEASE: REPROVADO (${errors.length})`);
  for(const e of errors)console.error(`ERRO: ${e}`);
  process.exit(1);
}
console.log(`GATE RELEASE: APROVADO — ${build} (${release})`);
