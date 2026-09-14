import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';

const site=path.resolve(process.argv[2]||'_site');
if(!fs.existsSync(site))throw new Error(`Diretório do site não encontrado: ${site}`);
const marker=JSON.parse(fs.readFileSync(path.join(site,'version.json'),'utf8'));
const build=String(marker.build||'');
if(!/^3\.68-r\d+$/.test(build))throw new Error(`Build inválido no artefato: ${build}`);

const mime={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.json':'application/json; charset=utf-8','.webp':'image/webp','.png':'image/png','.svg':'image/svg+xml'};
const server=http.createServer((req,res)=>{
  try{
    const url=new URL(req.url||'/', 'http://127.0.0.1');
    let rel=decodeURIComponent(url.pathname).replace(/^\/+/, '');
    if(!rel)rel='index.html';
    let file=path.resolve(site,rel);
    if(!file.startsWith(site+path.sep)&&file!==site){res.writeHead(403);return res.end('forbidden');}
    if(fs.existsSync(file)&&fs.statSync(file).isDirectory())file=path.join(file,'index.html');
    if(!fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404);return res.end('not found');}
    const ext=path.extname(file).toLowerCase();
    res.writeHead(200,{'Content-Type':mime[ext]||'application/octet-stream','Cache-Control':'no-store'});
    fs.createReadStream(file).pipe(res);
  }catch(e){res.writeHead(500);res.end(String(e?.message||e));}
});
await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
const address=server.address();
const base=`http://127.0.0.1:${address.port}`;
const common=`assets/js/common-v${build}.js`;
const checks=[
  ['version.json',`"build": "${build}"`],
  ['index.html',build],
  ['admin.html',build],
  ['display.html',build],
  ['simulator.html',build],
  ['admin/',build],
  [common,`BUILD_ID='${build}'`]
];
let ok=0;
try{
  for(const [rel,needle] of checks){
    const res=await fetch(`${base}/${rel}?qr_smoke=${encodeURIComponent(build)}&ts=${Date.now()}`,{cache:'no-store'});
    const body=await res.text();
    if(!res.ok)throw new Error(`${rel}: HTTP ${res.status}`);
    if(!body.includes(needle))throw new Error(`${rel}: marcador esperado ausente (${needle})`);
    ok++;
    console.log(`✓ ${rel}`);
  }
}finally{
  await new Promise(resolve=>server.close(resolve));
}
console.log(`SMOKE HTTP DO ARTEFATO: APROVADO (${ok}/${checks.length}) — ${build}`);
