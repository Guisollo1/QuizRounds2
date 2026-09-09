import{avatarMarkup}from'./avatars-v3.68-r38.js';
import{SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY}from'./config.js';
export const APP_VERSION='3.68';
export const BUILD_ID='3.68-r38';
export const BACKEND_SCHEMA_REQUIRED=40;

export const THEME_PALETTES=Object.freeze({
  violet:{primary:'#1565c0',secondary:'#287dda',deep:'#062f66',mid:'#0d57a1',bright:'#3b8fe8',soft:'#e8f2ff'},
  ocean:{primary:'#1474c5',secondary:'#35a7e6',deep:'#073a6a',mid:'#0f6db5',bright:'#35a1dc',soft:'#e8f5ff'},
  emerald:{primary:'#15805c',secondary:'#3eb88b',deep:'#064433',mid:'#0e7656',bright:'#28a97a',soft:'#e8f8f1'},
  sunset:{primary:'#c7475c',secondary:'#ed8e4e',deep:'#6b2036',mid:'#bd4356',bright:'#ee874b',soft:'#fff0ea'},
  midnight:{primary:'#333b82',secondary:'#5665cb',deep:'#0d1228',mid:'#22295c',bright:'#4854a8',soft:'#eef0ff'}
});
const logoShapeCache=new Map();
export function normalizeLogoUrl(value=''){
  const raw=String(value||'').trim();if(!raw)return'';
  try{
    const u=new URL(raw,location.href),host=(u.hostname||'').toLowerCase();
    const localHttp=u.protocol==='http:'&&['localhost','127.0.0.1','::1'].includes(host);
    return u.protocol==='https:'||localHttp?u.href:'';
  }catch{return'';}
}
function logoShapeFromRatio(ratio){return ratio>=2.15?'wide':ratio<=.72?'tall':ratio>=1.28?'landscape':'square';}
function commitLogoShape(body,url,ratio){
  if(!body||body.dataset.eventLogoUrl!==url)return;
  const shape=logoShapeFromRatio(ratio);body.dataset.logoShape=shape;body.style.setProperty('--event-logo-ratio',String(Math.max(.2,Math.min(5,ratio))));body.classList.add('has-event-logo');body.classList.remove('event-logo-error');
}
function loadEventLogo(body,url){
  if(!body)return;
  if(!url){body.classList.remove('has-event-logo','event-logo-error');delete body.dataset.logoShape;delete body.dataset.eventLogoUrl;body.style.removeProperty('--event-logo');body.style.removeProperty('--event-logo-ratio');return;}
  body.dataset.eventLogoUrl=url;body.style.setProperty('--event-logo',`url("${url.replaceAll('"','%22')}")`);
  const cached=logoShapeCache.get(url);if(cached){commitLogoShape(body,url,cached);return;}
  body.classList.remove('event-logo-error');
  const probe=new Image();probe.decoding='async';probe.onload=()=>{const ratio=probe.naturalWidth/Math.max(1,probe.naturalHeight);logoShapeCache.set(url,ratio);commitLogoShape(body,url,ratio);};probe.onerror=()=>{if(body.dataset.eventLogoUrl===url){body.classList.remove('has-event-logo');body.classList.add('event-logo-error');}};probe.src=url;
}
export function applyDocumentTheme(theme='violet',logo=''){
  const key=Object.hasOwn(THEME_PALETTES,String(theme))?String(theme):'violet',pal=THEME_PALETTES[key],body=document.body,root=document.documentElement;
  if(!body)return key;
  body.dataset.theme=key;root.dataset.theme=key;
  for(const [name,value] of Object.entries(pal)){
    body.style.setProperty(`--theme-${name}`,value);
    root.style.setProperty(`--theme-${name}`,value);
  }
  body.style.setProperty('--qr-bg-1',pal.deep);body.style.setProperty('--qr-bg-2',pal.mid);body.style.setProperty('--qr-bg-3',pal.bright);
  root.style.setProperty('--qr-bg-1',pal.deep);root.style.setProperty('--qr-bg-2',pal.mid);root.style.setProperty('--qr-bg-3',pal.bright);
  const safeLogo=normalizeLogoUrl(logo);loadEventLogo(body,safeLogo);
  const meta=document.querySelector('meta[name="theme-color"]');if(meta)meta.setAttribute('content',pal.primary);
  return key;
}

if(!SUPABASE_URL.startsWith('https://'))throw new Error('Configure assets/js/config.js');
if(!SUPABASE_PUBLISHABLE_KEY.startsWith('sb_publishable_')){
  throw new Error('Configuração inválida: use somente a Publishable Key do Supabase (sb_publishable_...). Nunca use sb_secret_ ou service_role no navegador.');
}
const scope=document.body?.dataset?.authScope||'quiz2';
export const db=window.supabase.createClient(SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY,{
  auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:false,storageKey:`quizrounds2-v38-${scope}`}
});
export const $=s=>document.querySelector(s);
export const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export const sleep=ms=>new Promise(r=>setTimeout(r,ms));
export function renderRank(el,rows,opts={}){
  if(!el||!Array.isArray(rows))return false;
  const selfId=opts.selfId?String(opts.selfId):'',movers=Array.isArray(opts.movers)?opts.movers:[],moveMap=new Map(movers.map(x=>[String(x.participant_id??''),Number(x.change)||0]));
  const signature=JSON.stringify(rows.map((r,i)=>[i+1,String(r.participant_id??''),String(r.display_name??''),String(r.avatar_key??''),Number(r.total_points)||0,selfId&&String(r.participant_id)===selfId?1:0,moveMap.get(String(r.participant_id??''))||0]));
  if(el.dataset.rankSignature===signature)return false;
  const scrollTop=el.scrollTop;
  const html=rows.map((r,i)=>{
    const pos=i+1,top=pos<=5?` rank-${pos}`:'',self=selfId&&String(r.participant_id)===selfId?' is-self':'',change=moveMap.get(String(r.participant_id??''))||0,move=change?`<em class="rank-move ${change>0?'up':'down'}">${change>0?'▲':'▼'}${Math.abs(change)}</em>`:(pos<=5&&movers.length?'<em class="rank-move same">—</em>':'');
    return `<li class="rank-row${top}${self}" data-rank="${pos}"><span class="rank-pos">${pos}</span><span class="rank-avatar">${avatarMarkup(r.avatar_key||'scientist_m',{compact:true,animated:pos<=3})}</span><strong>${esc(r.display_name)}${move}</strong><b>${Number(r.total_points)||0} pts</b></li>`;
  }).join('')||'<li class="rank-empty">Sem pontuação ainda</li>';
  el.innerHTML=html;
  el.dataset.rankSignature=signature;
  el.scrollTop=scrollTop;
  return true;
}
export function setConnection(el,status,detail=''){
  if(!el)return;
  const map={idle:['Pronto','connected'],connected:['Conectado','connected'],connecting:['Conectando…','connecting'],fallback:['Modo segurança','fallback'],offline:['Sem internet','offline'],error:['Conexão instável','error']};
  const [label,cls]=map[status]||[String(status),'connecting'];
  el.textContent=detail?`${label} • ${detail}`:label;
  el.className=`connection-pill ${cls}`;
}
export function serverRemaining(closesAt,serverOffset=0){
  if(!closesAt)return 0;
  return Date.parse(closesAt)-(Date.now()+serverOffset);
}
export async function ensureAnonymousSession(){
  const{data:{session}}=await db.auth.getSession();
  if(session)return session;
  const{data,error}=await db.auth.signInAnonymously();
  if(error)throw error;
  return data.session;
}
