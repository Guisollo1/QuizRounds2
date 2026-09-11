export const AVATARS=[
  {key:'scientist_m',label:'Cientista M',gender:'m',category:'science',assetId:'avatar01',preview:'assets/avatars/hd/scientist_m.png',accent:'#24a7d8'},
  {key:'scientist_f',label:'Cientista F',gender:'f',category:'science',assetId:'avatar06',preview:'assets/avatars/hd/scientist_f.png',accent:'#24a7d8'},
  {key:'chemist_m',label:'Químico M',gender:'m',category:'science',assetId:'avatar02',preview:'assets/avatars/hd/chemist_m.png',accent:'#c43bd9'},
  {key:'chemist_f',label:'Química F',gender:'f',category:'science',assetId:'avatar07',preview:'assets/avatars/hd/chemist_f.png',accent:'#c43bd9'},
  {key:'cleanroom_m',label:'Sala limpa M',gender:'m',category:'lab',assetId:'avatar03',preview:'assets/avatars/hd/cleanroom_m.png',accent:'#4f8ff7'},
  {key:'cleanroom_f',label:'Sala limpa F',gender:'f',category:'lab',assetId:'avatar08',preview:'assets/avatars/hd/cleanroom_f.png',accent:'#4f8ff7'},
  {key:'oil_ops_m',label:'Petroleiro • Operação M',gender:'m',category:'oil',assetId:'avatar04',preview:'assets/avatars/hd/oil_ops_m.png',accent:'#ff8a1f'},
  {key:'oil_ops_f',label:'Petroleira • Operação F',gender:'f',category:'oil',assetId:'avatar09',preview:'assets/avatars/hd/oil_ops_f.png',accent:'#ff8a1f'},
  {key:'oil_maint_m',label:'Petroleiro • Manutenção M',gender:'m',category:'oil',assetId:'avatar05',preview:'assets/avatars/hd/oil_maint_m.png',accent:'#ff9d23'},
  {key:'oil_maint_f',label:'Petroleira • Manutenção F',gender:'f',category:'oil',assetId:'avatar10',preview:'assets/avatars/hd/oil_maint_f.png',accent:'#ff9d23'}
];
const MAP=new Map(AVATARS.map(a=>[a.key,a]));
const DIRECTIONS=['down','left','right','up'];
const DIRECTION_ROW={down:0,left:1,right:2,up:3};
const LEGACY={
  avatar01:'scientist_m',avatar06:'scientist_f',avatar02:'chemist_m',avatar07:'chemist_f',avatar03:'cleanroom_m',avatar08:'cleanroom_f',avatar04:'oil_ops_m',avatar09:'oil_ops_f',avatar05:'oil_maint_m',avatar10:'oil_maint_f',
  frog:'scientist_m',cat:'scientist_f',owl:'chemist_m',unicorn:'chemist_f',robot:'cleanroom_m',alien:'cleanroom_f',fox:'oil_ops_m',panda:'oil_ops_f',ninja:'oil_maint_m',lion:'oil_maint_f',
  astro:'cleanroom_m',shark:'cleanroom_m',wizard:'scientist_m',fairy:'scientist_f',man_classic:'scientist_m',man_beard:'chemist_m',man_curly:'scientist_m',man_blond:'oil_ops_m',man_redhair:'oil_maint_m',man_glasses:'chemist_m',man_cap:'oil_ops_m',boy:'cleanroom_m',
  woman_classic:'scientist_f',woman_curly:'chemist_f',woman_blond:'oil_ops_f',woman_redhair:'oil_maint_f',woman_glasses:'chemist_f',woman_hat:'oil_ops_f',girl:'cleanroom_f',princess:'scientist_f',dog:'oil_ops_m',rabbit:'scientist_f',tiger:'oil_maint_m',bear:'chemist_m',koala:'cleanroom_f',monkey:'scientist_m',penguin:'cleanroom_m',wolf:'oil_ops_m',
  anime_hero:'scientist_m',anime_blue:'cleanroom_m',anime_fire:'oil_ops_m',anime_ninja:'oil_maint_m',anime_magic:'scientist_f',anime_pink:'chemist_f',anime_bluegirl:'cleanroom_f',anime_star:'oil_ops_f',pirate:'oil_ops_m',detective:'chemist_m'
};
const BACKEND_ALIAS={scientist_m:'frog',scientist_f:'cat',chemist_m:'owl',chemist_f:'unicorn',cleanroom_m:'robot',cleanroom_f:'alien',oil_ops_m:'fox',oil_ops_f:'panda',oil_maint_m:'ninja',oil_maint_f:'lion'};
function cleanKey(value){return String(value??'').trim().toLowerCase();}
function clampFrame(frame){return Math.max(0,Math.min(3,Number(frame)||0));}
function frameOffset(frame,row){return{tx:`${-clampFrame(frame)*25}%`,ty:`${-row*25}%`};}
export function isKnownAvatarKey(key){const k=cleanKey(key);return MAP.has(k)||Object.prototype.hasOwnProperty.call(LEGACY,k);}
export function normalizeAvatarKey(key){const k=cleanKey(key);if(MAP.has(k))return k;if(Object.prototype.hasOwnProperty.call(LEGACY,k))return LEGACY[k];return'scientist_m';}
export function avatarInfo(key){return MAP.get(normalizeAvatarKey(key))||AVATARS[0];}
export function backendAvatarKey(key){return BACKEND_ALIAS[normalizeAvatarKey(key)]||BACKEND_ALIAS.scientist_m;}
export function normalizeAvatarDirection(direction){const d=String(direction||'down').toLowerCase();return DIRECTIONS.includes(d)?d:'down';}
export function avatarSheetAsset(key){const a=avatarInfo(key);return`assets/avatars/runtime-r21/${a.key}.png?v=3.63-r21`;}
export function avatarFrameAsset(key){return avatarSheetAsset(key);}
export function applyAvatarFrameElement(el,key,direction='down',frame=1){
  if(!el)return;
  const a=avatarInfo(key),dir=normalizeAvatarDirection(direction),idx=clampFrame(frame),row=DIRECTION_ROW[dir]??0,{tx,ty}=frameOffset(idx,row),src=avatarSheetAsset(a.key),signature=`${a.key}:${dir}:${idx}`;
  if(el.dataset?.signature===signature)return;
  if('src' in el&&el.getAttribute('src')!==src)el.setAttribute('src',src);
  el.style.setProperty('--avatar-frame-tx',tx);el.style.setProperty('--avatar-frame-ty',ty);
  el.dataset.signature=signature;el.dataset.avatarKey=a.key;el.dataset.avatarDirection=dir;el.dataset.avatarFrame=String(idx);
}
function avatarFrameMarkup(a,dir,frame,klass){const idx=clampFrame(frame),row=DIRECTION_ROW[dir]??0,{tx,ty}=frameOffset(idx,row),src=avatarSheetAsset(a.key);return`<span class="qa-frame-viewport"><img class="${klass}" src="${src}" style="--avatar-frame-tx:${tx};--avatar-frame-ty:${ty}" data-signature="${a.key}:${dir}:${idx}" data-avatar-key="${a.key}" data-avatar-direction="${dir}" data-avatar-frame="${idx}" alt="" draggable="false" decoding="async"></span>`;}
function avatarChoicePreviewMarkup(key){const a=avatarInfo(key);return`<span class="avatar-choice-visual"><img class="avatar-choice-image" src="${a.preview}?v=3.63-r21" alt="" decoding="async" loading="lazy"></span>`;}
export function avatarMarkup(key,{animated=false,label=false,compact=false,preview=false,direction='down',frame=1}={}){const a=avatarInfo(key),dir=normalizeAvatarDirection(direction),cls=['quiz-avatar',`avatar-${a.key}`,`avatar-category-${a.category}`,`avatar-gender-${a.gender}`,animated?'avatar-animated':'',compact?'avatar-compact':'',preview?'avatar-picker-preview':''].filter(Boolean).join(' ');return`<span class="${cls}" data-avatar="${a.key}" data-avatar-version="r21" data-direction="${dir}" style="--avatar-accent:${a.accent}" aria-hidden="true"><span class="qa-shadow"></span>${avatarFrameMarkup(a,dir,frame,'qa-sprite-img')}${label?`<span class="qa-label">${a.label}</span>`:''}</span>`;}
export function avatarMapMarkup(key,{direction='down',frame=1}={}){const a=avatarInfo(key),dir=normalizeAvatarDirection(direction);return`<span class="quiz-avatar avatar-map-sprite avatar-${a.key}" data-avatar="${a.key}" data-avatar-version="r21" data-direction="${dir}" style="--avatar-accent:${a.accent}" aria-hidden="true"><span class="qa-shadow"></span>${avatarFrameMarkup(a,dir,frame,'qa-map-frame')}</span>`;}
export function avatarPickerMarkup(selected='scientist_m'){const current=normalizeAvatarKey(selected);return`<div class="avatar-picker-grid avatar-picker-grid-all" role="group" aria-label="Personagens disponíveis">${AVATARS.map((a,index)=>{const isSelected=a.key===current;return`<button type="button" class="avatar-choice ${isSelected?'selected':''}" data-avatar-choice="${a.key}" aria-pressed="${isSelected?'true':'false'}" aria-label="Personagem ${index+1}">${avatarChoicePreviewMarkup(a.key)}</button>`;}).join('')}</div>`;}
