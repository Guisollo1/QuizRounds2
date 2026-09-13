import{avatarMarkup}from'./avatars-v3.68-r62.js';
import{SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY}from'./config.js';
export const APP_VERSION='3.68';
export const BUILD_ID='3.68-r62';
export const BACKEND_SCHEMA_REQUIRED=42;
export const TEAM_FEATURE_SCHEMA_REQUIRED=43;

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
const AUTH_STORAGE_KEY=`quizrounds2-${scope}-auth-v1`;
try{
  if(!localStorage.getItem(AUTH_STORAGE_KEY)){
    for(const release of ['v40','v39','v38','v37','v36','v35','v34','v33','v32','v31']){
      const legacyKey=`quizrounds2-${release}-${scope}`,legacyValue=localStorage.getItem(legacyKey);
      if(legacyValue){localStorage.setItem(AUTH_STORAGE_KEY,legacyValue);break;}
    }
  }
}catch{}
export const db=window.supabase.createClient(SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY,{
  auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:false,storageKey:AUTH_STORAGE_KEY}
});
export const $=s=>document.querySelector(s);
export const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export const sleep=ms=>new Promise(r=>setTimeout(r,ms));
export function renderRank(el,rows,opts={}){
  if(!el||!Array.isArray(rows))return false;
  const selfId=opts.selfId?String(opts.selfId):'',movers=Array.isArray(opts.movers)?opts.movers:[],moveMap=new Map(movers.map(x=>[String(x.participant_id??''),Number(x.change)||0]));
  const previousPositions=new Map([...el.querySelectorAll('[data-participant]')].map(node=>[String(node.dataset.participant||''),Number(node.dataset.rank||0)]));
  const signature=JSON.stringify(rows.map((r,i)=>[i+1,String(r.participant_id??''),String(r.display_name??''),String(r.avatar_key??''),Number(r.total_points)||0,selfId&&String(r.participant_id)===selfId?1:0,moveMap.get(String(r.participant_id??''))||0]));
  if(el.dataset.rankSignature===signature)return false;
  const scrollTop=el.scrollTop;
  const html=rows.map((r,i)=>{
    const id=String(r.participant_id??''),pos=i+1,previous=previousPositions.get(id)||0,shift=previous&&previous!==pos?(pos<previous?' rank-shift-up':' rank-shift-down'):'',top=pos<=5?` rank-${pos}`:'',self=selfId&&id===selfId?' is-self':'',change=moveMap.get(id)||0,move=change?`<em class="rank-move ${change>0?'up':'down'}">${change>0?'▲':'▼'}${Math.abs(change)}</em>`:(pos<=5&&movers.length?'<em class="rank-move same">—</em>':'');
    return `<li class="rank-row${top}${self}${shift}" data-rank="${pos}" data-participant="${esc(id)}"><span class="rank-pos">${pos}</span><span class="rank-avatar">${avatarMarkup(r.avatar_key||'scientist_m',{compact:true,animated:false})}</span><strong>${esc(r.display_name)}${move}</strong><b>${Number(r.total_points)||0} pts</b></li>`;
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

const isDisplayAudioScope=()=>document.body?.dataset?.authScope==='display';
let feedbackAudioEnabled=true,feedbackAudioCtx=null,feedbackAudioMaster=null,feedbackAudioUnlocked=false;
const feedbackCueLast=new Map();
function feedbackAudioContext(){
  if(!isDisplayAudioScope()||!feedbackAudioEnabled)return null;
  try{
    const C=window.AudioContext||window.webkitAudioContext;if(!C)return null;
    if(!feedbackAudioCtx){feedbackAudioCtx=new C();feedbackAudioMaster=feedbackAudioCtx.createGain();feedbackAudioMaster.gain.value=.82;feedbackAudioMaster.connect(feedbackAudioCtx.destination);}
    return feedbackAudioCtx;
  }catch{return null;}
}
export function setFeedbackAudioEnabled(value){
  if(!isDisplayAudioScope()){feedbackAudioEnabled=false;return false;}
  feedbackAudioEnabled=value!==false;
  if(!feedbackAudioEnabled&&feedbackAudioCtx?.state==='running')feedbackAudioCtx.suspend?.().catch(()=>{});
  return feedbackAudioEnabled;
}
export async function unlockFeedbackAudio(){
  if(!isDisplayAudioScope())return false;
  feedbackAudioUnlocked=true;const ctx=feedbackAudioContext();if(!ctx)return false;
  try{if(ctx.state==='suspended')await ctx.resume();}catch{}
  return ctx.state==='running';
}
export function isFeedbackAudioReady(){return !!(isDisplayAudioScope()&&feedbackAudioUnlocked&&feedbackAudioCtx?.state==='running');}
function cueTone({f=700,to=null,d=.09,a=.038,delay=0,type='sine'}={}){
  const ctx=feedbackAudioContext();if(!ctx||!feedbackAudioMaster)return;
  const at=ctx.currentTime+Math.max(0,delay),o=ctx.createOscillator(),g=ctx.createGain();o.type=type;o.frequency.setValueAtTime(Math.max(40,f),at);if(Number.isFinite(to))o.frequency.exponentialRampToValueAtTime(Math.max(40,to),at+Math.max(.02,d));g.gain.setValueAtTime(.0001,at);g.gain.exponentialRampToValueAtTime(Math.max(.0002,a),at+.012);g.gain.exponentialRampToValueAtTime(.0001,at+Math.max(.035,d));o.connect(g).connect(feedbackAudioMaster);o.start(at);o.stop(at+d+.025);
}
export function playFeedbackCue(kind='tap',opts={}){
  if(!isDisplayAudioScope()||!feedbackAudioEnabled)return false;
  const now=performance.now(),step=Number(opts.step),key=String(opts.key||`${kind}:${Number.isFinite(step)?step:''}`),minGap=Math.max(0,Number(opts.minGap??({allReady:1600,newLeader:1200,finalRanking:1800,freeze:800,timeEnd:900}[kind]||120)));
  if(!opts.force&&now-(feedbackCueLast.get(key)||-1e9)<minGap)return false;feedbackCueLast.set(key,now);
  const ctx=feedbackAudioContext();if(!ctx||!feedbackAudioUnlocked||ctx.state!=='running')return false;
  const gain=Math.max(.25,Math.min(1.5,Number(opts.volume)||1)),T=(f,d,a,delay=0,type='sine',to=null)=>cueTone({f,d,a:a*gain,delay,type,to});
  switch(kind){
    case'allReady':T(587,.08,.030);T(740,.10,.034,.08);T(988,.16,.042,.17);break;
    case'countdown':{const n=Math.max(1,Math.min(3,Number.isFinite(step)?step:3)),freq={3:523,2:659,1:784}[n];T(freq,.075,.033,0,'triangle');break;}
    case'questionOpen':T(620,.07,.030,0,'sine',760);T(880,.10,.038,.08,'triangle',1080);break;
    case'lastFive':{const n=Math.max(1,Math.min(5,Number.isFinite(step)?step:5)),freq={5:540,4:590,3:660,2:760,1:920}[n];T(freq,n===1?.095:.055,n===1?.036:.022,0,n===1?'triangle':'sine');break;}
    case'timeEnd':T(330,.09,.035,0,'triangle',240);T(180,.16,.032,.09,'sine');break;
    case'newLeader':T(659,.065,.028);T(831,.075,.032,.07);T(1047,.13,.042,.15,'triangle');break;
    case'finalRanking':T(392,.07,.025);T(523,.08,.028,.065);T(659,.095,.032,.135);T(784,.14,.040,.22,'triangle');break;
    case'freeze':T(300,.10,.034,0,'triangle',220);T(170,.18,.040,.10,'sine');break;
    case'reconnect':T(620,.055,.026);T(840,.09,.034,.09);break;
    case'answer':T(720,.055,.027);T(940,.09,.035,.10);break;
    case'ranking':T(520,.05,.025);T(680,.065,.030,.075);T(880,.095,.038,.155);break;
    case'champion':T(620,.06,.030);T(840,.07,.033,.09);T(1080,.09,.038,.18);T(1320,.16,.050,.29,'triangle');break;
    case'tap':default:T(700,.045,.022);break;
  }
  return true;
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
