import{avatarMapMarkup,applyAvatarFrameElement,normalizeAvatarKey}from'./avatars-v3.68-r43.js';

const REDUCED=window.matchMedia?.('(prefers-reduced-motion: reduce)')?.matches===true;
const DIRECTIONS=['down','left','right','up'];
const MEDALS=['👑','🥈','🥉'];
const CHAT_LINES=['Oi!','Boa!','Bora!','GG!','Vamos!','Mandou bem!','Tudo certo?','😂','👏','🚀','🎉'];
const PLAY_TOYS=['⚽','🏀','🎈','⭐','🎲'];

/*
  r32 — navegação auditada mapa a mapa com rotas de piso, portas e corredores (door-only).
  Os nós e arestas foram redesenhados sobre áreas transitáveis visíveis; conexões
  entre ambientes passam apenas por portas/aberturas mapeadas e não atravessam
  mobiliário (mesas, bancadas, máquinas, camas e armários) nem paredes. POIs permanecem em piso seguro.
*/
const NAV={
  office:{
    nodes:{
      c0:[44,30],c1:[44,36],c2:[44,43],c3:[44,50],c4:[44,56],c5:[50,56],c6:[58,56],c7:[68,56],c8:[78,56],c9:[87,56],
      we0:[56,52],we1:[59,48],e0:[61,47],e1:[70,47],e2:[79,47],e3:[88,47],e4:[89,40],e5:[89,31],e6:[89,22],e7:[89,15],
      e8:[80,15],e9:[70,15],e10:[60,15],kd:[47,59],k0:[48,70],k1:[48,82],k2:[59,82],k3:[61,80],k4:[61,71],k5:[58,70],
      k6:[52,70],md:[72,59],r0:[13,54],r1:[13,66],r2:[18,67],r3:[25,67],r4:[32,67],r5:[36,66],r6:[36,54],r7:[31,82],
      r8:[25,83],r9:[19,82],f0:[12,16],f1:[12,27.5],f2:[18,29.2],f3:[32,29.2],f4:[36,27.5],f5:[36,16],m0:[70,68],
      mL:[70,78],mA:[78,68],mB:[84,68],mR:[88,68],mR2:[88,78]
    },
    edges:[
      ['c0','c1'],['c1','c2'],['c2','c3'],['c3','c4'],['c4','c5'],['c5','c6'],['c6','c7'],['c7','c8'],['c8','c9'],
      ['c6','we0'],['we0','we1'],['we1','e0'],['e0','e1'],['e1','e2'],['e2','e3'],['e3','e4'],['e4','e5'],['e5','e6'],
      ['e6','e7'],['e7','e8'],['e8','e9'],['e9','e10'],['c5','kd'],['kd','k0'],['k0','k1'],['k1','k2'],['k2','k3'],
      ['k3','k4'],['k4','k5'],['k5','k6'],['k6','k0'],['c7','md'],['r0','r1'],['r1','r2'],['r2','r3'],['r3','r4'],
      ['r4','r5'],['r5','r6'],['r7','r8'],['r8','r9'],['m0','mL'],['m0','mA'],['mA','mB'],['mB','mR'],['mR','mR2'],
      ['md','m0'],['f0','f1'],['f1','f2'],['f2','f3'],['f3','f4'],['f4','f5']
    ],
    tight:[
      'we0','we1','kd','md'
    ],
    spawn:[
      'c0','c1','c2','c3','c4','c5','c6','c7','c8','c9','e0','e1','e2','e3','e4','e5','e6','e7','e8','e9','e10','k0',
      'k1','k2','k3','k4','k5','k6','r0','r1','r2','r3','r4','r5','r6','r7','r8','r9','f0','f1','f2','f3','f4','f5',
      'm0','mL','mA','mB','mR','mR2'
    ],
    pois:[
      {node:'f3',action:'meeting',face:'up',icon:'💬',text:'Reunião'},
      {node:'e1',action:'computer',face:'up',icon:'💻',text:'No computador'},
      {node:'e7',action:'printer',face:'left',icon:'🖨️',text:'Impressora'},
      {node:'k6',action:'coffee',face:'up',icon:'☕',text:'Cafezinho'},
      {node:'mA',action:'briefing',face:'down',icon:'📋',text:'Planejando'},
      {node:'r3',action:'reception',face:'up',icon:'👋',text:'Recepção'}
    ],
    occluders:[
      {depth:66,clip:'polygon(17% 59%,40% 59%,40% 69%,17% 69%)'},
      {depth:82,clip:'polygon(51% 75%,66% 75%,66% 85%,51% 85%)'},
      {depth:80,clip:'polygon(76% 72%,89% 72%,89% 82%,76% 82%)'}
    ],
    fx:[
      {x:63,y:22,type:'monitor'},
      {x:74,y:22,type:'monitor'},
      {x:85,y:22,type:'monitor'},
      {x:54,y:69,type:'steam'}
    ]
  },
  laboratory:{
    nodes:{
      c0:[46,31],c1:[46,38],c2:[46,46],c3:[46,54],c4:[46,57],c5:[53,57],c6:[61,57],c7:[69,57],c8:[76,57],a0:[12,17],
      a1:[12,26],a2:[12,34],a3:[20,35],a4:[28,35],a5:[36,34],a6:[36,26],a7:[36,17],am0:[14,26],am1:[22,26],am2:[30,26],
      am3:[35,26],b0:[60,15],b1:[68,15],b2:[77,15],b3:[86,15],b4:[59,23],b5:[59,32],b6:[59,42],b7:[68,43],b8:[77,43],
      b9:[84,43],bd:[65,47],bh:[65,51],w0:[12,48],w1:[18,48],w2:[25,48],w3:[31,48],w4:[36,48],r0:[13,55],r1:[13,67],
      r2:[18,69],r3:[25,69],r4:[32,69],r5:[36,67],r6:[36,55],r7:[31,82],r8:[25,83],r9:[19,82],ld:[46,61],l0:[47,70],
      l1:[47,82],l2:[60,82],l3:[62.5,80],l4:[63,70],l5:[60,70],l6:[53,70],md:[72,60],m0:[70,68],mL:[70,78],mA:[78,68],
      mB:[84,68],mR:[88,68],mR2:[88,78]
    },
    edges:[
      ['c0','c1'],['c1','c2'],['c2','c3'],['c3','c4'],['c4','c5'],['c5','c6'],['c6','c7'],['c7','c8'],['a0','a1'],
      ['a1','a2'],['a2','a3'],['a3','a4'],['a4','a5'],['a5','a6'],['a6','a7'],['a1','am0'],['am0','am1'],['am1','am2'],
      ['am2','am3'],['am3','a6'],['b0','b1'],['b1','b2'],['b2','b3'],['b0','b4'],['b4','b5'],['b5','b6'],['b6','b7'],
      ['b7','b8'],['b8','b9'],['b7','bd'],['bd','bh'],['bh','c6'],['w0','w1'],['w1','w2'],['w2','w3'],['w3','w4'],
      ['r0','r1'],['r1','r2'],['r2','r3'],['r3','r4'],['r4','r5'],['r5','r6'],['r7','r8'],['r8','r9'],['c4','ld'],
      ['ld','l0'],['l0','l1'],['l1','l2'],['l2','l3'],['l3','l4'],['l4','l5'],['l5','l6'],['l6','l0'],['c7','md'],
      ['md','m0'],['m0','mL'],['m0','mA'],['mA','mB'],['mB','mR'],['mR','mR2']
    ],
    tight:[
      'bd','bh','ld','md'
    ],
    spawn:[
      'c0','c1','c2','c3','c4','c5','c6','c7','c8','a0','a1','a2','a3','a4','a5','a6','a7','am0','am1','am2','am3','b0',
      'b1','b2','b3','b4','b5','b6','b7','b8','b9','w0','w1','w2','w3','w4','r0','r1','r2','r3','r4','r5','r6','r7',
      'r8','r9','l0','l1','l2','l3','l4','l5','l6','m0','mL','mA','mB','mR','mR2'
    ],
    pois:[
      {node:'a3',action:'sample',face:'up',icon:'🧪',text:'Amostra'},
      {node:'a6',action:'inspect',face:'left',icon:'🔬',text:'Analisando'},
      {node:'b7',action:'microscope',face:'up',icon:'🔬',text:'Microscópio'},
      {node:'w2',action:'wash',face:'up',icon:'🧼',text:'Lavagem'},
      {node:'l6',action:'sample',face:'up',icon:'🧫',text:'Preparando'},
      {node:'mA',action:'briefing',face:'down',icon:'📋',text:'Relatório'},
      {node:'r3',action:'reception',face:'up',icon:'👋',text:'Recepção'}
    ],
    occluders:[
      {depth:67,clip:'polygon(17% 59%,40% 59%,40% 69%,17% 69%)'},
      {depth:83,clip:'polygon(51% 76%,66% 76%,66% 86%,51% 86%)'},
      {depth:80,clip:'polygon(76% 72%,89% 72%,89% 82%,76% 82%)'}
    ],
    fx:[
      {x:18,y:20,type:'bubble'},
      {x:30,y:19,type:'bubble'},
      {x:65,y:18,type:'monitor'},
      {x:78,y:18,type:'monitor'}
    ]
  },
  industry:{
    nodes:{
      c0:[29,31],c1:[37,31],c2:[45,31],c3:[53,31],c4:[61,31],c5:[66,31],v0:[53,37],v1:[53,45],v2:[53,55],v3:[53,64],
      v4:[53,72],b0:[45,72],b1:[37,72],b2:[61,72],b3:[66,72],l0:[12,32],l1:[12,42],l2:[12,55],l3:[18,57],l4:[24,57],
      l5:[24,47],l6:[24,39],t0:[11,69],t1:[20,69],t2:[29,69],t3:[33,72],t4:[33,81],t5:[33,88],ctrl0:[48,21],
      ctrl1:[55,21],ctrl2:[62,21],ctrld:[55,25],q0:[58,51],q1:[58,60],q2:[66,60],q3:[74,60],q4:[74,51],o0:[77,47],
      o1:[77,59],o2:[84,59],o3:[91,59],o4:[91,48],shop0:[69,20],shopA:[74,20],shop1:[80,20],shop2:[89,20],shopd:[74,25],
      shopout:[74,29],shop6:[70,37]
    },
    edges:[
      ['c0','c1'],['c1','c2'],['c2','c3'],['c3','c4'],['c4','c5'],['c3','v0'],['v0','v1'],['v1','v2'],['v2','v3'],
      ['v3','v4'],['v4','b0'],['b0','b1'],['v4','b2'],['b2','b3'],['l0','l1'],['l1','l2'],['l2','l3'],['l3','l4'],
      ['l4','l5'],['l5','l6'],['t0','t1'],['t1','t2'],['t2','t3'],['t3','t4'],['t4','t5'],['ctrl0','ctrl1'],
      ['ctrl1','ctrl2'],['ctrl1','ctrld'],['ctrld','c3'],['q0','q1'],['q1','q2'],['q2','q3'],['q3','q4'],['o0','o1'],
      ['o1','o2'],['o2','o3'],['o3','o4'],['shop0','shopA'],['shopA','shop1'],['shop1','shop2'],['shopA','shopd'],
      ['shopd','shopout'],['shopout','c5'],['shopd','shop6']
    ],
    tight:[
      'ctrld','shopd','shopout'
    ],
    spawn:[
      'c0','c1','c2','c3','c4','c5','v0','v1','v2','v3','v4','b0','b1','b2','b3','l0','l1','l2','l3','l4','l5','l6',
      't0','t1','t2','t3','t4','t5','ctrl0','ctrl1','ctrl2','q0','q1','q2','q3','q4','o0','o1','o2','o3','o4','shop0',
      'shopA','shop1','shop2','shop6'
    ],
    pois:[
      {node:'l1',action:'inspect',face:'right',icon:'🔎',text:'Inspeção'},
      {node:'c2',action:'safety',face:'up',icon:'🦺',text:'Segurança'},
      {node:'ctrl1',action:'control',face:'up',icon:'🖥️',text:'Controle'},
      {node:'shop1',action:'maintenance',face:'up',icon:'🛠️',text:'Manutenção'},
      {node:'q2',action:'meeting',face:'up',icon:'💬',text:'Reunião'},
      {node:'o0',action:'briefing',face:'right',icon:'📋',text:'Planejamento'},
      {node:'v2',action:'radio',face:'right',icon:'📻',text:'Rádio'}
    ],
    occluders:[
      {depth:58,clip:'polygon(31% 46%,52% 46%,52% 61%,31% 61%)'},
      {depth:61,clip:'polygon(55% 51%,76% 51%,76% 66%,55% 66%)'},
      {depth:84,clip:'polygon(9% 68%,33% 68%,33% 92%,9% 92%)'}
    ],
    fx:[
      {x:25,y:14,type:'warning'},
      {x:55,y:28,type:'warning'},
      {x:84,y:15,type:'spark'}
    ]
  },
  platform:{
    nodes:{
      h0:[19,18],h1:[27,18],h2:[35,18],h3:[38,23],h4:[35,31],h5:[27,33],h6:[19,31],h7:[17,24],n0:[39,30],n1:[47,30],
      n2:[55,30],n3:[63,30],n4:[72,29],n5:[82,29],w0:[37,36],w1:[37,45],w2:[37,54],w3:[37,63],w4:[37,71],e0:[59,35],
      e1:[59,44],e2:[59,53],e3:[59,62],e4:[59,71],r0:[86,34],r1:[86,44],r2:[86,54],r3:[86,64],r4:[85,71],s0:[37,72],
      s1:[45,72],s2:[53,72],s3:[60,72],s4:[68,72],s5:[76,72],s6:[85,72],d0:[50,74],d1:[50,80],d2:[50,87],d3:[54,87],
      d4:[54,80],d5:[54,74],crew0:[14,42],crew1:[22,42],crew2:[31,42],crew3:[32,49],crew4:[32,55],crew5:[32,63],
      crew6:[32,68],ctrl0:[44,21],ctrl1:[50,21],ctrl2:[56,21],ctrld:[50,25]
    },
    edges:[
      ['h0','h1'],['h1','h2'],['h2','h3'],['h3','h4'],['h4','h5'],['h5','h6'],['h6','h7'],['h7','h0'],['h4','n0'],
      ['n0','n1'],['n1','n2'],['n2','n3'],['n3','n4'],['n4','n5'],['n0','w0'],['w0','w1'],['w1','w2'],['w2','w3'],
      ['w3','w4'],['n2','e0'],['e0','e1'],['e1','e2'],['e2','e3'],['e3','e4'],['n5','r0'],['r0','r1'],['r1','r2'],
      ['r2','r3'],['r3','r4'],['w4','s0'],['s0','s1'],['s1','s2'],['s2','s3'],['s3','s4'],['s4','s5'],['s5','s6'],
      ['s6','r4'],['e4','s3'],['s2','d0'],['d0','d1'],['d1','d2'],['d2','d3'],['d3','d4'],['d4','d5'],['d5','s3'],
      ['crew0','crew1'],['crew1','crew2'],['crew2','crew3'],['crew3','crew4'],['crew4','crew5'],['crew5','crew6'],
      ['ctrl0','ctrl1'],['ctrl1','ctrl2'],['ctrl1','ctrld'],['ctrld','n1']
    ],
    tight:[
      'ctrld','d0','d5'
    ],
    spawn:[
      'h0','h1','h2','h3','h4','h5','h6','h7','n0','n1','n2','n3','n4','n5','w0','w1','w2','w3','w4','e0','e1','e2',
      'e3','e4','r0','r1','r2','r3','r4','s0','s1','s2','s3','s4','s5','s6','d1','d2','d3','d4','crew0','crew1','crew2',
      'crew3','crew4','crew5','crew6','ctrl0','ctrl1','ctrl2'
    ],
    pois:[
      {node:'h1',action:'helipad',face:'down',icon:'🚁',text:'Heliponto'},
      {node:'ctrl1',action:'control',face:'up',icon:'🖥️',text:'Controle'},
      {node:'n4',action:'crane',face:'right',icon:'🏗️',text:'Guindaste'},
      {node:'r1',action:'inspect',face:'left',icon:'🔎',text:'Inspeção'},
      {node:'s4',action:'safety',face:'up',icon:'🦺',text:'Passarela'},
      {node:'d1',action:'radio',face:'down',icon:'📻',text:'Rádio'},
      {node:'crew1',action:'coffee',face:'down',icon:'☕',text:'Pausa'}
    ],
    occluders:[
      {depth:61,clip:'polygon(39% 34%,56% 34%,56% 62%,39% 62%)'},
      {depth:69,clip:'polygon(65% 51%,84% 51%,84% 70%,65% 70%)'},
      {depth:66,clip:'polygon(12% 39%,34% 39%,34% 68%,12% 68%)'}
    ],
    fx:[
      {x:69,y:14,type:'beacon'},
      {x:78,y:25,type:'warning'},
      {x:50,y:91,type:'wave'}
    ]
  }
};

for(const graph of Object.values(NAV)){
  graph.adj={};
  for(const key of Object.keys(graph.nodes))graph.adj[key]=[];
  for(const[a,b]of graph.edges){
    if(!graph.nodes[a]||!graph.nodes[b])continue;
    graph.adj[a].push(b);graph.adj[b].push(a);
  }
  graph.poiByNode=new Map((graph.pois||[]).map(p=>[p.node,p]));
  graph.tightSet=new Set(graph.tight||[]);
}

const FRAME_SEQUENCES={
  idle:[1],walking:[0,1,2,3],chatting:[1,2,3,2],playing:[1,2,1,0],waving:[1,2,3,2],
  jumping:[1],dancing:[0,1,2,3],cheering:[1,2,3,2],interacting:[1,2,1,3]
};

function hashString(value){let h=2166136261;for(const ch of String(value||'')){h^=ch.charCodeAt(0);h=Math.imul(h,16777619);}return h>>>0;}
function nextRand(actor){actor.seed=(Math.imul(actor.seed,1664525)+1013904223)>>>0;return actor.seed/4294967296;}
function between(actor,min,max){return min+nextRand(actor)*(max-min);}
function sceneKey(city){const scene=String(city?.dataset?.scene||'office').toLowerCase();return NAV[scene]?scene:'office';}
function graphFor(city){return NAV[sceneKey(city)];}
function distance(a,b){return Math.hypot((a?.[0]||0)-(b?.[0]||0),(a?.[1]||0)-(b?.[1]||0));}
function directionFrom(a,b){const dx=(b?.[0]||0)-(a?.[0]||0),dy=(b?.[1]||0)-(a?.[1]||0);return Math.abs(dx)>Math.abs(dy)?(dx<0?'left':'right'):(dy<0?'up':'down');}
function shortest(graph,start,end){
  if(!graph?.nodes?.[start]||!graph?.nodes?.[end])return[start];
  if(start===end)return[start];
  const queue=[start],prev=new Map([[start,null]]);
  for(const node of queue){
    for(const next of graph.adj[node]||[]){
      if(prev.has(next))continue;prev.set(next,node);
      if(next===end){const path=[next];let cur=node;while(cur){path.push(cur);cur=prev.get(cur);}return path.reverse();}
      queue.push(next);
    }
  }
  return[start];
}
function reachable(graph,start){
  if(!graph?.nodes?.[start])return[];
  const out=[],seen=new Set([start]),queue=[start];
  for(const node of queue){out.push(node);for(const next of graph.adj[node]||[]){if(!seen.has(next)){seen.add(next);queue.push(next);}}}
  return out;
}

export function createAvatarCity(host,badge,{maxActors=100}={}){
  const actors=new Map();
  const city=host?.closest('.avatar-city');
  const fxLayer=city?.querySelector('#avatarCityFx');
  const occlusionLayer=city?.querySelector('#avatarCityOcclusion');
  const doorLayer=city?.querySelector('#avatarCityDoorGuides,.city-door-guides');
  let phase='lobby',density='normal',destroyed=false,timer=null,lastFrameAt=0,nextPairAt=0,lastScene='',rosterCount=0,readyCount=0,mascotEl=null,nextMascotAt=performance.now()+12000;

  function renderSceneLayers(){
    const scene=sceneKey(city);if(scene===lastScene)return;lastScene=scene;const graph=NAV[scene];
    if(fxLayer){fxLayer.innerHTML=(graph.fx||[]).map((f,i)=>`<i class="city-fx city-fx-${f.type}" style="--fx-x:${f.x}%;--fx-y:${f.y}%;--fx-delay:${(i*.37).toFixed(2)}s" aria-hidden="true"></i>`).join('');}
    if(occlusionLayer){occlusionLayer.innerHTML=(graph.occluders||[]).map((o,i)=>`<i class="city-occluder" data-occluder="${i}" style="clip-path:${o.clip};z-index:${100+Math.round(o.depth*10)}" aria-hidden="true"></i>`).join('');}
    if(doorLayer){doorLayer.innerHTML=(graph.tight||[]).map((node,i)=>{const pt=graph.nodes[node];return pt?`<i class="city-door-guide" data-door-node="${node}" style="--door-x:${pt[0]}%;--door-y:${pt[1]}%;--door-delay:${(i*.11).toFixed(2)}s" aria-hidden="true"></i>`:'';}).join('');}
  }
  function applyFrame(actor,index=1){
    const img=actor?.frameImg;if(!img?.isConnected||!actor?.avatarKey)return;
    const frame=Math.max(0,Math.min(3,Number(index)||0)),dir=DIRECTIONS.includes(actor.direction)?actor.direction:'down',signature=`${actor.avatarKey}:${dir}:${frame}`;
    if(img.dataset.signature===signature)return;
    applyAvatarFrameElement(img,actor.avatarKey,dir,frame);
    const wrap=img.closest('.quiz-avatar');if(wrap){wrap.dataset.direction=dir;wrap.dataset.avatar=actor.avatarKey;}
    actor.frameIndex=frame;
  }
  function setActorClass(actor,action,direction=actor.direction||'down'){
    const facing=DIRECTIONS.includes(direction)?direction:'down';
    actor.el.classList.remove('is-walking','is-idle','is-jumping','is-chatting','is-playing','is-waving','is-dancing','is-cheering','is-interacting','face-down','face-left','face-right','face-up');
    actor.el.classList.add(`is-${action}`,`face-${facing}`);actor.el.dataset.direction=facing;actor.direction=facing;
    if(actor.animState!==action){actor.animState=action;actor.animStep=0;}
    const seq=FRAME_SEQUENCES[action]||FRAME_SEQUENCES.idle;applyFrame(actor,seq[actor.animStep%seq.length]??1);
  }
  function animateFrames(now){
    const cadence=REDUCED?900:density==='high'?360:density==='medium'?260:210;if(now-lastFrameAt<cadence)return;lastFrameAt=now;
    for(const actor of actors.values()){
      const seq=REDUCED?[1]:(FRAME_SEQUENCES[actor.animState]||FRAME_SEQUENCES.idle);
      if(seq.length<=1){if(actor.frameIndex!==(seq[0]??1))applyFrame(actor,seq[0]??1);continue;}
      actor.animStep=(actor.animStep+1)%seq.length;applyFrame(actor,seq[actor.animStep]);
    }
  }
  function clearExtras(actor){const speech=actor.el.querySelector('.city-speech'),toy=actor.el.querySelector('.city-toy'),action=actor.el.querySelector('.city-action');if(speech)speech.textContent='';if(toy)toy.textContent='';if(action){action.textContent='';action.removeAttribute('data-label');}}
  function pointForActor(actor,nodeKey){
    const graph=graphFor(city),base=graph.nodes[nodeKey];if(!base)return null;
    const tight=graph.tightSet?.has(nodeKey)===true;
    const spread=tight?0:(density==='high'?.38:(density==='medium'?.30:.22));
    const ox=((actor.slot%3)-1)*spread,oy=((Math.floor(actor.slot/3)%3)-1)*spread*.46;
    return[Math.max(2,Math.min(98,base[0]+ox)),Math.max(2,Math.min(98,base[1]+oy))];
  }
  function setPosition(actor,nodeKey,{instant=false}={}){
    const point=pointForActor(actor,nodeKey);if(!point)return;
    actor.node=nodeKey;actor.x=point[0];actor.y=point[1];
    if(instant)actor.el.classList.add('city-teleport');
    actor.el.style.setProperty('--city-x',`${actor.x.toFixed(2)}%`);actor.el.style.setProperty('--city-y',`${actor.y.toFixed(2)}%`);actor.el.style.zIndex=String(100+Math.round(actor.y*10));
    if(instant)requestAnimationFrame(()=>requestAnimationFrame(()=>actor.el.classList.remove('city-teleport')));
  }
  function ensureScene(actor){
    renderSceneLayers();const scene=sceneKey(city);if(actor.scene===scene&&NAV[scene]?.nodes?.[actor.node])return;
    const graph=NAV[scene],spawns=graph.spawn?.length?graph.spawn:Object.keys(graph.nodes),index=(hashString(`${actor.id}:${scene}`)+actor.rosterIndex)%Math.max(1,spawns.length);
    actor.scene=scene;actor.route=[];actor.poiTarget='';actor.slot=(actor.rosterIndex+((actor.seed>>>7)%9))%9;setPosition(actor,spawns[index]||Object.keys(graph.nodes)[0],{instant:true});setActorClass(actor,'idle','down');actor.nextAt=performance.now()+500+((actor.seed>>>10)%1300);
  }
  function makeActor(row,index){
    const id=String(row.participant_id||`actor-${index}`),seed=hashString(id||row.display_name||index)||1,el=document.createElement('div');
    el.className='city-actor is-idle city-entering';el.dataset.participant=id;
    el.innerHTML='<span class="city-rank-crown" aria-hidden="true"></span><span class="city-speech" aria-hidden="true"></span><span class="city-name"></span><span class="city-avatar-shell"></span><span class="city-toy" aria-hidden="true"></span><span class="city-action" aria-hidden="true"></span>';
    const actor={id,el,seed,rosterIndex:index,slot:index%9,node:'',x:50,y:50,nextAt:performance.now()+500,avatarKey:'',connected:true,ready:false,direction:'down',route:[],scene:'',animState:'idle',animStep:0,frameIndex:1,frameImg:null,poiTarget:'',turnReady:false};
    host.append(el);actors.set(id,actor);ensureScene(actor);setTimeout(()=>el.classList.remove('city-entering'),700);return actor;
  }
  function setAvatar(actor,key){
    const normalized=normalizeAvatarKey(key);if(actor.avatarKey===normalized&&actor.frameImg?.isConnected)return;
    actor.avatarKey=normalized;actor.el.querySelector('.city-avatar-shell').innerHTML=avatarMapMarkup(normalized,{direction:actor.direction,frame:actor.frameIndex??1});actor.frameImg=actor.el.querySelector('.qa-map-frame');applyFrame(actor,actor.frameIndex??1);
  }
  function randomDirection(actor){return DIRECTIONS[Math.floor(nextRand(actor)*DIRECTIONS.length)]||'down';}
  function idle(actor,now,duration=between(actor,2.6,5.8),direction=actor.direction){clearExtras(actor);setActorClass(actor,'idle',direction||randomDirection(actor));actor.nextAt=now+duration*1000;}
  function moveNext(actor,now){
    ensureScene(actor);const graph=graphFor(city);if(!actor.route.length)return false;
    const next=actor.route[0],from=graph.nodes[actor.node],to=graph.nodes[next];if(!from||!to){actor.route=[];actor.poiTarget='';return false;}
    const dir=directionFrom(from,to),d=distance(from,to),narrow=graph.tightSet?.has(actor.node)||graph.tightSet?.has(next);
    if(actor.direction!==dir&&actor.animState==='walking'&&!actor.turnReady){
      actor.turnReady=true;clearExtras(actor);actor.el.classList.add('city-turning');setActorClass(actor,'idle',dir);actor.nextAt=now+(REDUCED?0:170);setTimeout(()=>actor.el?.classList.remove('city-turning'),220);return true;
    }
    actor.turnReady=false;actor.route.shift();
    const duration=Math.max(narrow?1.15:.95,Math.min(narrow?3.0:2.65,d*(narrow?.19:.165)));
    clearExtras(actor);actor.el.classList.remove('city-tight-move','city-door-pass');if(narrow)actor.el.classList.add('city-tight-move','city-door-pass');
    actor.el.style.setProperty('--city-move-time',`${duration.toFixed(2)}s`);actor.el.style.setProperty('--city-ease',narrow?'cubic-bezier(.38,.08,.22,.98)':'cubic-bezier(.35,.08,.25,1)');
    setActorClass(actor,'walking',dir);setPosition(actor,next);actor.nextAt=now+duration*1000+(narrow?150:90);
    if(narrow)setTimeout(()=>actor.el?.classList.remove('city-door-pass'),Math.round(duration*1000)+180);
    return true;
  }
  function chooseReachablePoi(actor){
    const graph=graphFor(city),reachableSet=new Set(reachable(graph,actor.node)),pois=(graph.pois||[]).filter(p=>reachableSet.has(p.node)&&p.node!==actor.node);
    if(!pois.length)return null;
    return pois[Math.floor(nextRand(actor)*pois.length)]||null;
  }
  function sendTo(actor,target){
    const graph=graphFor(city),path=shortest(graph,actor.node,target);if(path.length<2)return false;actor.route=path.slice(1);return true;
  }
  function wander(actor,now){
    ensureScene(actor);const graph=graphFor(city),pool=reachable(graph,actor.node).filter(k=>k!==actor.node);if(!pool.length){idle(actor,now);return;}
    const preferred=pool.filter(k=>distance(graph.nodes[actor.node],graph.nodes[k])>=10),source=preferred.length?preferred:pool,choice=source[Math.floor(nextRand(actor)*source.length)];actor.poiTarget='';
    if(sendTo(actor,choice))moveNext(actor,now);else idle(actor,now);
  }
  function visitPoi(actor,now){
    const poi=chooseReachablePoi(actor);if(!poi){wander(actor,now);return;}actor.poiTarget=poi.node;if(sendTo(actor,poi.node))moveNext(actor,now);else performPoi(actor,poi,now);
  }
  function performPoi(actor,poi,now){
    clearExtras(actor);actor.poiTarget='';const action=actor.el.querySelector('.city-action');if(action){action.textContent=poi.icon||'•';action.dataset.label=poi.text||'';}
    setActorClass(actor,'interacting',poi.face||actor.direction);actor.nextAt=now+between(actor,2.4,4.3)*1000;
  }
  function jump(actor,now){clearExtras(actor);setActorClass(actor,'jumping',actor.direction||'down');actor.nextAt=now+950;}
  function wave(actor,now){clearExtras(actor);actor.el.querySelector('.city-speech').textContent=CHAT_LINES[Math.floor(nextRand(actor)*CHAT_LINES.length)];setActorClass(actor,'waving',randomDirection(actor));actor.nextAt=now+2100;}
  function play(actor,now){clearExtras(actor);actor.el.querySelector('.city-toy').textContent=PLAY_TOYS[Math.floor(nextRand(actor)*PLAY_TOYS.length)];setActorClass(actor,'playing',randomDirection(actor));actor.nextAt=now+2300;}
  function dance(actor,now){clearExtras(actor);actor.el.querySelector('.city-speech').textContent='🎵';setActorClass(actor,'dancing',actor.direction);actor.nextAt=now+2100;}
  function cheer(actor,now){clearExtras(actor);actor.el.querySelector('.city-speech').textContent=nextRand(actor)>.45?'🎉':'👏';setActorClass(actor,'cheering',actor.direction);actor.nextAt=now+1700;}
  function faceEachOther(a,b){const pa=[a.x,a.y],pb=[b.x,b.y];setActorClass(a,a.animState,directionFrom(pa,pb));setActorClass(b,b.animState,directionFrom(pb,pa));}
  function pairInteraction(a,b,now,type){
    if(!a||!b||a===b||density==='high')return;clearExtras(a);clearExtras(b);a.route=[];b.route=[];a.poiTarget='';b.poiTarget='';
    if(type==='chat'){a.el.querySelector('.city-speech').textContent=CHAT_LINES[Math.floor(nextRand(a)*CHAT_LINES.length)];b.el.querySelector('.city-speech').textContent=CHAT_LINES[Math.floor(nextRand(b)*CHAT_LINES.length)];setActorClass(a,'chatting',a.direction);setActorClass(b,'chatting',b.direction);}
    else if(type==='highfive'){a.el.querySelector('.city-speech').textContent='🙌';b.el.querySelector('.city-speech').textContent='🙌';setActorClass(a,'cheering',a.direction);setActorClass(b,'cheering',b.direction);}
    else{const toy=PLAY_TOYS[Math.floor(nextRand(a)*PLAY_TOYS.length)];a.el.querySelector('.city-toy').textContent=toy;b.el.querySelector('.city-toy').textContent=toy;setActorClass(a,'playing',a.direction);setActorClass(b,'playing',b.direction);}
    faceEachOther(a,b);a.nextAt=b.nextAt=now+2300;
  }
  function act(actor,now){
    ensureScene(actor);
    if(actor.route.length){moveNext(actor,now);return;}
    const graph=graphFor(city),poi=actor.poiTarget?graph.poiByNode.get(actor.node):null;if(poi){performPoi(actor,poi,now);return;}
    if(REDUCED||!actor.connected){idle(actor,now,REDUCED?12:7);return;}
    if(phase==='question_open'){idle(actor,now,between(actor,7,12),nextRand(actor)>.75?randomDirection(actor):actor.direction);return;}
    if(phase==='preparing'){if(nextRand(actor)<.18)wave(actor,now);else idle(actor,now,between(actor,4,7));return;}
    if(phase==='paused'){if(nextRand(actor)<.22)visitPoi(actor,now);else idle(actor,now,between(actor,4,8));return;}
    if(phase==='result'||phase==='finished'){
      const leader=actor.el.classList.contains('city-leader'),r=nextRand(actor);
      if(phase==='finished'&&leader){if(r<.52)cheer(actor,now);else if(r<.78)dance(actor,now);else if(r<.92)jump(actor,now);else wave(actor,now);return;}
      if(r<.42)cheer(actor,now);else if(r<.58)jump(actor,now);else if(r<.74)dance(actor,now);else if(r<.88)wave(actor,now);else idle(actor,now,between(actor,1.8,3.3));return;
    }
    if(density==='high'&&actor.rosterIndex>=30){idle(actor,now,between(actor,7,13));return;}
    if(density==='medium'&&actor.rosterIndex>=38&&nextRand(actor)<.72){idle(actor,now,between(actor,5,10));return;}
    const r=nextRand(actor);
    if(r<.25)visitPoi(actor,now);else if(r<.47)wander(actor,now);else if(r<.60)idle(actor,now);else if(r<.73)wave(actor,now);else if(r<.86)play(actor,now);else dance(actor,now);
  }
  function mascotAnchor(scene){
    const anchors={office:[[4,76,'right'],[96,67,'left'],[50,96,'up']],laboratory:[[4,73,'right'],[96,70,'left'],[53,96,'up']],industry:[[4,70,'right'],[96,61,'left'],[52,96,'up']],platform:[[4,73,'right'],[96,72,'left'],[52,96,'up']]};
    const list=anchors[scene]||anchors.office;return list[Math.floor(Math.random()*list.length)]||list[0];
  }
  function mascotTick(now){
    if(REDUCED||phase!=='lobby'||density==='high'||!rosterCount||mascotEl||now<nextMascotAt||!city)return;
    const [x,y,dir]=mascotAnchor(sceneKey(city));mascotEl=document.createElement('div');mascotEl.className=`city-mascot-peek face-${dir}`;mascotEl.style.setProperty('--mascot-x',`${x}%`);mascotEl.style.setProperty('--mascot-y',`${y}%`);mascotEl.innerHTML=`<span class="city-mascot-bubble">👀</span><span class="city-avatar-shell">${avatarMapMarkup('et_skunk',{direction:dir,frame:1})}</span>`;
    (city.querySelector('.city-map-viewport')||city).append(mascotEl);requestAnimationFrame(()=>mascotEl?.classList.add('show'));
    setTimeout(()=>mascotEl?.classList.add('leaving'),2500);setTimeout(()=>{mascotEl?.remove();mascotEl=null;},3300);nextMascotAt=now+18000+Math.random()*22000;
  }

  function pairTick(now){
    if(REDUCED||phase!=='lobby'||density==='high'||now<nextPairAt)return;
    const live=[...actors.values()].filter(a=>a.connected&&a.nextAt<=now&&!a.route.length);if(live.length<2){nextPairAt=now+2500;return;}
    const a=live[Math.floor(Math.random()*live.length)],graph=graphFor(city),same=new Set(reachable(graph,a.node)),others=live.filter(x=>x!==a&&same.has(x.node)&&distance([a.x,a.y],[x.x,x.y])<=16);
    if(others.length){const b=others[Math.floor(Math.random()*others.length)],roll=Math.random();pairInteraction(a,b,now,roll<.48?'chat':roll<.76?'play':'highfive');}
    nextPairAt=now+3500+Math.random()*4500;
  }
  function engineTick(){
    if(destroyed||document.hidden)return;const now=performance.now();animateFrames(now);pairTick(now);mascotTick(now);for(const actor of actors.values())if(actor.nextAt<=now)act(actor,now);
  }
  function resetTimer(){if(timer)clearInterval(timer);timer=null;if(!actors.size||destroyed)return;const cadence=REDUCED?650:density==='high'?300:density==='medium'?230:190;timer=setInterval(engineTick,cadence);}
  function ensureTimer(){if(!timer&&actors.size&&!destroyed)resetTimer();}
  function stopTimerIfEmpty(){if(actors.size)return;if(timer)clearInterval(timer);timer=null;}

  function updatePopulationBadge(){
    if(!badge)return;
    if(!rosterCount){badge.textContent='0 jogadores';return;}
    if(phase==='lobby'||phase==='preparing'||phase==='paused')badge.textContent=`${readyCount}/${rosterCount} prontos`;
    else badge.textContent=`${rosterCount} jogador${rosterCount===1?'':'es'}`;
  }
  function setRoster(rows=[]){
    const raw=Array.isArray(rows)?rows:[],nextDensity=raw.length>=60?'high':raw.length>=30?'medium':'normal';if(nextDensity!==density){density=nextDensity;if(city)city.dataset.density=density;resetTimer();}
    const list=raw.slice(0,Math.min(maxActors,100)),wanted=new Set(list.map((r,i)=>String(r.participant_id||`actor-${i}`)));
    for(const[id,actor]of actors)if(!wanted.has(id)){actor.el.remove();actors.delete(id);}
    const ranked=[...list].sort((a,b)=>(Number(b.total_points)||0)-(Number(a.total_points)||0)||String(a.joined_at||'').localeCompare(String(b.joined_at||''))),hasScore=ranked.some(r=>Number(r.total_points)>0),medals=new Map(hasScore?ranked.slice(0,3).map((r,i)=>[String(r.participant_id),MEDALS[i]]):[]);
    list.forEach((row,index)=>{
      const id=String(row.participant_id||`actor-${index}`),actor=actors.get(id)||makeActor(row,index),connected=row.connected!==false,medal=medals.get(id)||'';actor.rosterIndex=index;actor.slot=(index+((actor.seed>>>7)%9))%9;ensureScene(actor);
      actor.connected=connected;actor.ready=!!row.ready;actor.el.classList.toggle('offline',!connected);actor.el.classList.toggle('is-ready',actor.ready);actor.el.classList.toggle('city-leader',!!medal);actor.el.querySelector('.city-rank-crown').textContent=medal;actor.el.querySelector('.city-name').textContent=String(row.display_name||'Jogador');setAvatar(actor,row.avatar_key||'scientist_m');
      if(!connected&&actor.nextAt<performance.now()+1000)actor.nextAt=performance.now()+1000;
    });
    readyCount=list.filter(x=>x.ready).length;rosterCount=list.length;updatePopulationBadge();if(list.length)ensureTimer();else stopTimerIfEmpty();
  }
  function setPhase(nextPhase){
    phase=nextPhase||'lobby';city?.setAttribute('data-city-phase',phase);renderSceneLayers();updatePopulationBadge();const now=performance.now();
    for(const actor of actors.values()){
      ensureScene(actor);
      if(phase==='question_open'){actor.route=[];actor.poiTarget='';clearExtras(actor);setActorClass(actor,'idle',actor.direction);actor.nextAt=now+between(actor,6,10)*1000;}
      else if(phase==='result'||phase==='finished'){actor.route=[];actor.poiTarget='';actor.nextAt=now+Math.random()*700;}
      else actor.nextAt=Math.min(actor.nextAt,now+1100);
    }
  }
  function destroy(){destroyed=true;if(timer)clearInterval(timer);timer=null;for(const actor of actors.values())actor.el.remove();actors.clear();if(fxLayer)fxLayer.innerHTML='';if(occlusionLayer)occlusionLayer.innerHTML='';if(doorLayer)doorLayer.innerHTML='';mascotEl?.remove();mascotEl=null;}
  document.addEventListener('visibilitychange',()=>{if(destroyed)return;if(document.hidden){if(timer){clearInterval(timer);timer=null;}}else ensureTimer();});
  renderSceneLayers();
  return{setRoster,setPhase,destroy};
}
