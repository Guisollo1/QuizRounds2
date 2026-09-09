import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const root=process.cwd();
const errors=[];
const notes=[];
const fail=(msg)=>errors.push(msg);
const ok=(msg)=>notes.push(msg);
const exists=(rel)=>fs.existsSync(path.join(root,rel));
const read=(rel)=>fs.readFileSync(path.join(root,rel),'utf8');

function walk(dir){
  const abs=path.join(root,dir);
  if(!fs.existsSync(abs))return[];
  const out=[];
  for(const ent of fs.readdirSync(abs,{withFileTypes:true})){
    const rel=path.posix.join(dir,ent.name);
    if(ent.isDirectory())out.push(...walk(rel));else out.push(rel);
  }
  return out;
}
function localTarget(baseFile,raw){
  let value=String(raw||'').trim();
  if(!value||value.startsWith('#')||/^(?:https?:|data:|blob:|mailto:|tel:|javascript:)/i.test(value))return null;
  value=value.split('#')[0].split('?')[0];
  if(!value||/[{}$<>]/.test(value))return null;
  return path.posix.normalize(path.posix.join(path.posix.dirname(baseFile),value));
}
function checkReference(owner,raw){
  const target=localTarget(owner,raw);
  if(target&&!exists(target))fail(`${owner}: referência ausente -> ${raw} (${target})`);
}
function stripCssNoise(source){
  let out='',i=0,quote='';
  while(i<source.length){
    const c=source[i],n=source[i+1];
    if(!quote&&c==='/'&&n==='*'){i+=2;while(i<source.length&&!(source[i]==='*'&&source[i+1]==='/'))i++;i+=2;continue;}
    if(quote){if(c==='\\'){out+='  ';i+=2;continue;}if(c===quote)quote='';out+=' ';i++;continue;}
    if(c==='"'||c==="'"){quote=c;out+=' ';i++;continue;}out+=c;i++;
  }
  return out;
}
function checkCssBraces(rel){
  const clean=stripCssNoise(read(rel));let depth=0;
  for(const c of clean){if(c==='{')depth++;else if(c==='}'){depth--;if(depth<0){fail(`${rel}: chave CSS fechada sem abertura.`);return;}}}
  if(depth!==0)fail(`${rel}: chaves CSS desbalanceadas (${depth}).`);
}
function namedExports(source){
  const set=new Set();
  for(const m of source.matchAll(/\bexport\s+(?:async\s+)?(?:function|class|const|let|var)\s+([A-Za-z_$][\w$]*)/g))set.add(m[1]);
  for(const m of source.matchAll(/\bexport\s*\{([^}]+)\}/g))for(const item of m[1].split(',')){
    const left=item.trim().split(/\s+as\s+/i)[0]?.trim();if(left)set.add(left);
  }
  return set;
}

const htmlFiles=['index.html','admin.html','display.html','simulator.html'];
const allJs=walk('assets/js').filter(f=>f.endsWith('.js'));
const allCss=walk('assets/css').filter(f=>f.endsWith('.css'));

// 1) JavaScript syntax.
for(const rel of allJs.concat(walk('scripts').filter(f=>f.endsWith('.mjs')))){
  const proc=spawnSync(process.execPath,['--input-type=module','--check'],{input:read(rel),encoding:'utf8'});
  if(proc.status!==0)fail(`${rel}: erro de sintaxe JS\n${(proc.stderr||proc.stdout||'').trim()}`);
}
ok(`Sintaxe JS verificada em ${allJs.length} arquivos + scripts de validação.`);

// 2) HTML references, IDs, build/cache and pinned Supabase client.
const pinned='https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.112.4/dist/umd/supabase.min.js';
let idTotal=0;
for(const rel of htmlFiles){
  const source=read(rel);
  for(const m of source.matchAll(/\b(?:src|href)\s*=\s*["']([^"']+)["']/gi))checkReference(rel,m[1]);
  const ids=[...source.matchAll(/\bid\s*=\s*["']([^"']+)["']/gi)].map(m=>m[1]);idTotal+=ids.length;
  const counts=new Map();for(const id of ids)counts.set(id,(counts.get(id)||0)+1);
  for(const [id,count] of counts)if(count>1)fail(`${rel}: ID duplicado ${id} (${count}x).`);
  for(const m of source.matchAll(/\b(?:src|href)\s*=\s*["']([^"']+)["']/gi)){
    const u=m[1];if(/^assets\/(?:css|js)\//.test(u)&&!u.includes('v=3.68-r34'))fail(`${rel}: asset ativo sem cache-bust r34 -> ${u}`);
  }
  if(rel!=='simulator.html'){
    if(!source.includes(pinned))fail(`${rel}: Supabase JS não está fixado exatamente em 2.112.4.`);
    const externalScripts=[...source.matchAll(/<script[^>]+src=["'](https?:[^"']+)["']/gi)].map(m=>m[1]);
    for(const u of externalScripts)if(u!==pinned)fail(`${rel}: script externo inesperado -> ${u}`);
  }
  if(!source.includes('3.68-r34')&&rel!=='display.html')fail(`${rel}: identificação visual/build r34 ausente.`);
}
ok(`${htmlFiles.length} HTML auditados; ${idTotal} IDs sem duplicidade; referências/cache-bust r34 conferidos.`);

// 3) ES module imports and named exports.
for(const rel of allJs){
  const source=read(rel);
  for(const m of source.matchAll(/^\s*import\s*\{([^}]+)\}\s*from\s*["']([^"']+)["']/gm)){
    const raw=m[2];checkReference(rel,raw);const target=localTarget(rel,raw);if(!target||!exists(target))continue;
    const exports=namedExports(read(target));
    for(const item of m[1].split(',')){
      const original=item.trim().split(/\s+as\s+/i)[0]?.trim();
      if(original&&!exports.has(original))fail(`${rel}: importa ${original} de ${target}, mas o export não foi encontrado.`);
    }
  }
  for(const m of source.matchAll(/^\s*import\s*["']([^"']+)["']/gm))checkReference(rel,m[1]);
}
ok('Imports ES Modules locais resolvem e imports nomeados conferem com exports.');

// 4) CSS URLs, braces, logo and avatar picker/map rules.
for(const rel of allCss){
  const source=read(rel);checkCssBraces(rel);
  for(const m of source.matchAll(/url\(\s*["']?([^"')]+)["']?\s*\)/gi)){
    const raw=m[1].trim();if(!raw.startsWith('var('))checkReference(rel,raw);
  }
}
const displayCss=read('assets/css/display-ui-v3.92-r34.css');
for(const shape of ['wide','landscape','square','tall']){
  const token=`.display-body.has-event-logo[data-logo-shape="${shape}"] .display-event-logo`;
  if(displayCss.split(token).length-1!==1)fail(`display-ui r30: regra adaptativa ${shape} ausente/duplicada.`);
}
for(const rel of ['assets/css/admin-v3.68-r34.css','assets/css/display-ui-v3.92-r34.css','assets/css/player-ui-v3.92-r34.css']){
  if(!read(rel).includes('background-color:transparent'))fail(`${rel}: logo transparente não detectada.`);
}
const avatarUi=read('assets/css/avatars-ui-v3.92-r34.css');
if(!avatarUi.includes('grid-template-columns:repeat(4,minmax(0,1fr))'))fail('Avatar picker r30 não usa 4 colunas no desktop.');
if(!avatarUi.includes('repeat(3,minmax(0,1fr))'))fail('Avatar picker r30 não possui grade mobile de 3 colunas.');
if(!avatarUi.includes('city-walkers{overflow:hidden'))fail('Mapa r30 não contém contenção dos atores dentro do viewport.');
ok(`${allCss.length} CSS: referências, balanceamento, logo, picker e contenção do mapa verificados.`);

// 5) Active r34 assets + cache compatibility.
const active={
  'admin.html':['assets/css/admin-v3.68-r34.css','assets/css/avatars-runtime-v3.68-r34.css','assets/js/admin-v3.68-r34.js'],
  'display.html':['assets/css/display-ui-v3.92-r34.css','assets/css/avatars-runtime-v3.68-r34.css','assets/css/avatars-ui-v3.92-r34.css','assets/js/display-v3.68-r34.js'],
  'index.html':['assets/css/player-ui-v3.92-r34.css','assets/css/avatars-runtime-v3.68-r34.css','assets/css/avatars-ui-v3.92-r34.css','assets/js/player-v3.68-r34.js'],
  'simulator.html':['assets/css/simulator-v3.68-r34.css','assets/css/avatars-runtime-v3.68-r34.css','assets/css/avatars-ui-v3.92-r34.css','assets/js/simulator-v3.68-r34.js']
};
for(const [rel,required] of Object.entries(active)){
  const source=read(rel);for(const token of required)if(!source.includes(token))fail(`${rel}: não carrega o ativo r34 ${token}.`);
}
for(const rel of ['assets/js/admin-v3.68-r32.js','assets/js/display-v3.68-r32.js','assets/js/player-v3.68-r32.js','assets/js/simulator-v3.68-r32.js','assets/css/display-ui-v3.92-r32.css','assets/js/admin-v3.68-r29.js','assets/js/display-v3.68-r29.js','assets/js/player-v3.68-r29.js','assets/js/simulator-v3.68-r29.js','assets/css/display-ui-v3.92-r29.css','assets/js/admin-v3.68-r28.js','assets/js/common-v3.68.js'])if(!exists(rel))fail(`Asset de compatibilidade anterior ausente: ${rel}`);
ok('Ativos r34 e compatibilidade de cache r29/r28 verificados.');

// 6) Frontend/backend build/schema contract.
const common=read('assets/js/common-v3.68-r34.js');
if(!/BUILD_ID=['"]3\.68-r34['"]/.test(common))fail('BUILD_ID r34 ausente no common ativo.');
if(!/BACKEND_SCHEMA_REQUIRED=40/.test(common))fail('BACKEND_SCHEMA_REQUIRED=40 ausente no common ativo.');
for(const rel of ['assets/js/admin-v3.68-r34.js','assets/js/display-v3.68-r34.js','assets/js/player-v3.68-r34.js']){
  const source=read(rel);if(!source.includes('get_quiz_backend_meta'))fail(`${rel}: handshake de backend ausente.`);if(!source.includes('BUILD_ID'))fail(`${rel}: BUILD_ID não é utilizado.`);
}
const admin=read('assets/js/admin-v3.68-r34.js');
if(!admin.includes('version_required'))fail('ADM: broadcast de atualização de build ausente.');
if(!admin.includes('eligible_count'))fail('ADM: elegibilidade por round não é consumida.');
ok('Contrato frontend/backend, BUILD_ID r34 e schema 40 verificados.');

// 7) Migrations 001..040 and hardening + avatar catalog migration.
const migrations=fs.readdirSync(path.join(root,'supabase/migrations')).filter(n=>/^\d{3}_.*\.sql$/.test(n)).sort();
const nums=migrations.map(n=>Number(n.slice(0,3)));
for(let i=1;i<=40;i++)if(nums.filter(n=>n===i).length!==1)fail(`Migration ${String(i).padStart(3,'0')} ausente ou duplicada.`);
if(nums.some(n=>n>40))fail(`Migration futura inesperada encontrada: ${Math.max(...nums)}.`);
const hard=read('supabase/migrations/039_security_runtime_hardening_v368_r29.sql');
for(const token of ['get_quiz_backend_meta','quiz_display_pairings','quiz_display_authorizations','quiz_round_eligibility','require_live_control','admin_managed_logo_usage_count','resume_quiz_display','admin_create_display_pairing','authorize_quiz_display(p_code text,p_pair_token text)'])if(!hard.includes(token))fail(`Migration 039: bloco obrigatório ausente: ${token}.`);
const avatarMig=read('supabase/migrations/040_avatar_catalog_31_v368_r30.sql');
if(!avatarMig.includes("'schema_version',40")||!avatarMig.includes("'min_frontend_build','3.68-r30'"))fail('Migration 040: metadados de schema/build r30 ausentes.');
if(!avatarMig.includes('private.normalize_avatar_key'))fail('Migration 040: normalização de avatar ausente.');
ok('Migrations 001..040 contínuas; hardening 039 e catálogo 040 presentes.');

// 8) Exact 31-avatar catalog, assets and end-to-end selection/map wiring.
const avatarModule=read('assets/js/avatars-v3.68-r34.js');
const avatarKeys=[...avatarModule.matchAll(/\{key:'([^']+)'/g)].map(m=>m[1]);
const uniqueKeys=[...new Set(avatarKeys)];
if(avatarKeys.length!==31||uniqueKeys.length!==31)fail(`Catálogo r30 deveria ter 31 avatares únicos; encontrado ${avatarKeys.length}/${uniqueKeys.length}.`);
const runtimeFiles=fs.readdirSync(path.join(root,'assets/avatars/runtime-r30')).filter(n=>n.endsWith('.webp')).sort();
const previewFiles=fs.readdirSync(path.join(root,'assets/avatars/preview-r30')).filter(n=>n.endsWith('.webp')).sort();
if(runtimeFiles.length!==31)fail(`runtime-r30 deveria conter 31 WEBP; encontrado ${runtimeFiles.length}.`);
if(previewFiles.length!==31)fail(`preview-r30 deveria conter 31 WEBP; encontrado ${previewFiles.length}.`);
for(const key of uniqueKeys){
  if(!exists(`assets/avatars/runtime-r30/${key}.webp`))fail(`Sprite runtime ausente: ${key}.webp`);
  if(!exists(`assets/avatars/preview-r30/${key}.webp`))fail(`Preview ausente: ${key}.webp`);
  if(!avatarMig.includes(`'${key}'`))fail(`Migration 040 não aceita a chave ${key}.`);
}
for(const token of ['runtime-r30','preview-r30','avatarPickerMarkup','backendAvatarKey','avatarMapMarkup','applyAvatarFrameElement'])if(!avatarModule.includes(token))fail(`Módulo de avatar r30 não contém ${token}.`);
const player=read('assets/js/player-v3.68-r34.js'),display=read('assets/js/display-v3.68-r34.js'),city=read('assets/js/city-v3.68-r34.js'),sim=read('assets/js/simulator-v3.68-r34.js');
if(!player.includes('avatarPickerMarkup')||!player.includes('player_set_avatar')||!player.includes('join_quiz_room_v2'))fail('Jogador r30 não está ligado à seleção/persistência dos avatares.');
if(!display.includes('createAvatarCity')||!city.includes('avatarMapMarkup')||!city.includes('row.avatar_key'))fail('Telão/mapa r30 não está ligado ao avatar individual do roster.');
if(!sim.includes('AVATARS')||!sim.includes('avatarPickerMarkup'))fail('Simulador r34 não usa o catálogo de 31 avatares.');
ok('Catálogo end-to-end: 31 avatares, 62 assets, seleção, Supabase e mapa do lobby verificados.');

// 9) Simulator deterministic checks.
if(/\badd\([^;\n]*,\s*true\s*,/.test(sim))fail('Simulador r34 ainda contém verificação aprovada por constante true.');
for(const token of ['Resposta idempotente','Prazo/deadline','Desempate determinístico','Pausa preserva tempo','Anulação recalcula ranking','Reclassificação recalcula pontos','Carga lógica 100 × 20 rounds'])if(!sim.includes(token))fail(`Simulador r34: teste esperado ausente: ${token}.`);
if(!sim.includes('Não substitui teste real contra Supabase'))fail('Simulador r34 não explicita limite da suíte local.');
ok('Suíte local determinística preservada e limites documentados.');

// 10) No privileged credentials; config remains placeholders.
for(const rel of allJs){
  const source=read(rel);for(const m of source.matchAll(/(?:SUPABASE_(?:PUBLISHABLE_)?KEY|apikey|authorization)\s*=\s*["']([^"']+)["']/gi)){
    const value=m[1];if(/^sb_secret_/i.test(value)||/service_role/i.test(value))fail(`${rel}: credencial privilegiada embutida.`);
  }
}
const config=read('assets/js/config.js');
if(!config.includes('COLE_AQUI_A_URL_DO_PROJETO')||!config.includes('COLE_AQUI_APENAS_A_CHAVE_SB_PUBLISHABLE'))fail('config.js não contém placeholders esperados.');
ok('Config neutro e sem credenciais privilegiadas embutidas.');


// 10b) QuizRounds2 browser isolation from production path on the same GitHub Pages origin.
const common2=read('assets/js/common-v3.68-r34.js');
const admin2=read('assets/js/admin-v3.68-r34.js');
const player2=read('assets/js/player-v3.68-r34.js');
const display2=read('assets/js/display-v3.68-r34.js');
if(!common2.includes('quizrounds2-v38-${scope}'))fail('QuizRounds2: auth storageKey não está isolada.');
for(const token of ['quiz2AdminRoomId','quiz2RemoteDeviceToken:v1','quiz2EventMode:v1'])if(!admin2.includes(token))fail(`QuizRounds2: chave ADM não isolada: ${token}.`);
for(const token of ['quiz2Room','quiz2Name','quiz2PlayerId','quiz2ActiveTab'])if(!player2.includes(token))fail(`QuizRounds2: chave jogador não isolada: ${token}.`);
if(!display2.includes('quiz2DisplaySound'))fail('QuizRounds2: preferência do telão não isolada.');
ok('Namespace de navegador QuizRounds2 isolado do QuizRounds principal.');

// 10c) Lobby map collision/nav r34: audited graph, door nodes and tight-node spread.
const city32=read('assets/js/city-v3.68-r34.js');
for(const scene of ['office','laboratory','industry','platform'])if(!city32.includes(`${scene}:{`))fail(`Mapa r34 ausente no grafo: ${scene}.`);
for(const token of ['tightSet','density===\'high\'?.38','door-only','mobiliário'])if(!city32.includes(token))fail(`Colisão r34: marcador obrigatório ausente: ${token}.`);
if(city32.includes("spread=density==='high'?1.05"))fail('Colisão r34: dispersão antiga de 1.05% ainda ativa.');
ok('Quatro mapas r34 auditados com nós de porta/gargalo e dispersão reduzida.');

// 10d) r34 visual layer: wall clock and avatar category filters.
const displayHtml34=read('display.html'),displayJs34=read('assets/js/display-v3.68-r34.js'),playerJs34=read('assets/js/player-v3.68-r34.js'),avatarJs34=read('assets/js/avatars-v3.68-r34.js');
for(const token of ['displayWallClockTime','displayWallClockDate','display-wall-clock'])if(!displayHtml34.includes(token))fail(`r34 telão: relógio ausente: ${token}.`);
for(const token of ['startWallClock','Intl.DateTimeFormat','setInterval(updateWallClock,1000)'])if(!displayJs34.includes(token))fail(`r34 telão: lógica do relógio ausente: ${token}.`);
for(const token of ['data-avatar-filter','data-avatar-group','filters:true'])if(!(avatarJs34+playerJs34).includes(token))fail(`r34 avatares: filtro ausente: ${token}.`);
ok('Relógio do telão e filtros visuais dos avatares r34 verificados.');

// 11) Release metadata and CI gate.
const version=read('VERSION.txt'),readme=read('README.md'),bat=read('01_Abrir_Simulador_QuizRounds2_v3.68-r34.bat'),workflow=read('.github/workflows/pages.yml');
for(const token of ['RELEASE=r34','BUILD_ID=3.68-r34','BACKEND_SCHEMA_REQUIRED=40','SUPABASE_MIGRATIONS=001-040','AVATAR_CATALOG=31'])if(!version.includes(token))fail(`VERSION.txt: metadado ausente ${token}.`);
if(!readme.includes('QuizRounds2')||!readme.includes('31 Avatares')||!readme.includes('segundo projeto Supabase'))fail('README.md não documenta o ambiente de teste QuizRounds2.');
if(!bat.includes('v3.68-r34'))fail('Launcher do simulador não foi atualizado para r34.');
if(!workflow.includes('node scripts/validate-build.mjs'))fail('Workflow do GitHub Pages não executa a validação do build.');
ok('Metadados r34 QuizRounds2, documentação, launcher e CI gate verificados.');

if(errors.length){
  console.error(`\nVALIDAÇÃO QuizRounds2 r34: FALHOU (${errors.length})`);
  for(const e of errors)console.error(`- ${e}`);
  process.exit(1);
}
console.log(`VALIDAÇÃO QuizRounds2 r34: APROVADA (${notes.length} grupos)`);
for(const n of notes)console.log(`- ${n}`);
