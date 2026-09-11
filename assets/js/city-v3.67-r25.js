import{avatarMapMarkup,applyAvatarFrameElement,normalizeAvatarKey}from'./avatars-v3.63-r21.js';

const REDUCED=window.matchMedia?.('(prefers-reduced-motion: reduce)')?.matches===true;
const DIRECTIONS=['down','left','right','up'];
const MEDALS=['👑','🥈','🥉'];
const CHAT_LINES=['Oi!','Boa!','Bora!','GG!','Vamos!','Mandou bem!','Tudo certo?','😂','👏','🚀','🎉'];
const PLAY_TOYS=['⚽','🏀','🎈','⭐','🎲'];

/*
  r21 — navegação canônica por grafo e runtime consolidado em sprite-sheets.
  Cada nó foi colocado apenas sobre piso/passarela visível. As arestas seguem
  corredores e contornam mobiliário/máquinas; zonas sem porta permanecem
  desconectadas. POIs são destinos de interação, nunca atalhos de colisão.
*/
const NAV={
  office:{
    nodes:{
      c0:[45,34],c1:[45,40],c2:[45,47],c3:[45,54],c4:[50,58],c5:[56,58],c6:[63,58],c7:[70,58],c8:[78,58],c9:[86,58],
      e0:[58,18],e1:[58,31],e2:[58,46],e3:[58,53],e4:[69,18],e5:[69,31],e6:[69,46],e7:[80,18],e8:[80,31],e9:[80,46],e10:[90,18],e11:[90,31],e12:[90,47],
      k0:[47,68],k1:[50,71],k2:[50,86],k3:[57,88],k4:[65,88],k5:[68,84],k6:[68,70],k7:[62,70],k8:[55,70],
      m0:[75,68],m1:[75,87],m2:[82,89],m3:[90,88],m4:[91,80],m5:[91,69],m6:[85,69],m7:[80,69],
      r0:[12,60],r1:[12,72],r2:[12,84],r3:[18,89],r4:[27,89],r5:[37,88],r6:[39,80],r7:[39,71],r8:[39,61],
      f0:[12,15],f1:[20,14],f2:[31,14],f3:[38,15],f4:[38,29],f5:[32,34],f6:[22,34],f7:[12,31]
    },
    edges:[
      ['c0','c1'],['c1','c2'],['c2','c3'],['c3','c4'],['c4','c5'],['c5','c6'],['c6','c7'],['c7','c8'],['c8','c9'],
      ['c5','e3'],['e0','e1'],['e1','e2'],['e2','e3'],['e0','e4'],['e4','e7'],['e7','e10'],['e1','e5'],['e5','e8'],['e8','e11'],['e2','e6'],['e6','e9'],['e9','e12'],['e10','e11'],['e11','e12'],
      ['k0','k1'],['k1','k2'],['k2','k3'],['k3','k4'],['k4','k5'],['k5','k6'],['k6','k7'],['k7','k8'],['k8','k1'],
      ['m0','m1'],['m1','m2'],['m2','m3'],['m3','m4'],['m4','m5'],['m5','m6'],['m6','m7'],['m7','m0'],
      ['r0','r1'],['r1','r2'],['r2','r3'],['r3','r4'],['r4','r5'],['r5','r6'],['r6','r7'],['r7','r8'],
      ['f0','f1'],['f1','f2'],['f2','f3'],['f3','f4'],['f4','f5'],['f5','f6'],['f6','f7'],['f7','f0']
    ],
    spawn:['c1','c2','c4','c6','c8','e0','e2','e4','e6','e8','e10','e12','k0','k2','k4','k6','m0','m2','m4','m6','r0','r2','r4','r6','r8','f0','f2','f4','f6'],
    pois:[
      {node:'f3',action:'meeting',face:'left',icon:'💬',text:'Reunião'},
      {node:'e1',action:'computer',face:'right',icon:'💻',text:'No computador'},
      {node:'e5',action:'computer',face:'right',icon:'⌨️',text:'Trabalhando'},
      {node:'e11',action:'printer',face:'up',icon:'🖨️',text:'Impressora'},
      {node:'k8',action:'coffee',face:'up',icon:'☕',text:'Cafezinho'},
      {node:'m7',action:'briefing',face:'down',icon:'📋',text:'Planejando'},
      {node:'r8',action:'reception',face:'left',icon:'👋',text:'Recepção'}
    ],
    occluders:[
      {depth:66,clip:'polygon(17% 59%,40% 59%,40% 69%,17% 69%)'},
      {depth:82,clip:'polygon(51% 75%,66% 75%,66% 85%,51% 85%)'},
      {depth:80,clip:'polygon(76% 72%,89% 72%,89% 82%,76% 82%)'}
    ],
    fx:[{x:63,y:22,type:'monitor'},{x:74,y:22,type:'monitor'},{x:85,y:22,type:'monitor'},{x:54,y:69,type:'steam'}]
  },
  laboratory:{
    nodes:{
      c0:[46,31],c1:[46,38],c2:[46,46],c3:[46,54],c4:[46,61],c5:[53,61],c6:[61,61],c7:[69,61],c8:[77,61],c9:[86,61],
      a0:[12,16],a1:[20,16],a2:[30,16],a3:[38,16],a4:[39,27],a5:[38,36],a6:[29,36],a7:[20,36],a8:[12,34],a9:[12,25],
      b0:[58,16],b1:[66,16],b2:[75,16],b3:[85,16],b4:[90,18],b5:[90,31],b6:[90,42],b7:[83,43],b8:[74,43],b9:[65,43],b10:[58,42],b11:[58,30],
      w0:[12,42],w1:[20,42],w2:[28,42],w3:[36,42],w4:[36,49],w5:[28,50],w6:[20,50],w7:[12,50],
      r0:[12,61],r1:[12,72],r2:[12,84],r3:[18,89],r4:[28,89],r5:[38,88],r6:[39,79],r7:[39,70],r8:[39,61],
      l0:[47,68],l1:[50,70],l2:[50,87],l3:[57,89],l4:[65,89],l5:[68,84],l6:[68,70],l7:[62,70],l8:[56,70],
      m0:[75,68],m1:[75,87],m2:[82,89],m3:[90,88],m4:[91,80],m5:[91,69],m6:[85,69],m7:[80,69]
    },
    edges:[
      ['c0','c1'],['c1','c2'],['c2','c3'],['c3','c4'],['c4','c5'],['c5','c6'],['c6','c7'],['c7','c8'],['c8','c9'],
      ['a0','a1'],['a1','a2'],['a2','a3'],['a3','a4'],['a4','a5'],['a5','a6'],['a6','a7'],['a7','a8'],['a8','a9'],['a9','a0'],
      ['b0','b1'],['b1','b2'],['b2','b3'],['b3','b4'],['b4','b5'],['b5','b6'],['b6','b7'],['b7','b8'],['b8','b9'],['b9','b10'],['b10','b11'],['b11','b0'],
      ['w0','w1'],['w1','w2'],['w2','w3'],['w3','w4'],['w4','w5'],['w5','w6'],['w6','w7'],['w7','w0'],
      ['r0','r1'],['r1','r2'],['r2','r3'],['r3','r4'],['r4','r5'],['r5','r6'],['r6','r7'],['r7','r8'],
      ['l0','l1'],['l1','l2'],['l2','l3'],['l3','l4'],['l4','l5'],['l5','l6'],['l6','l7'],['l7','l8'],['l8','l1'],
      ['m0','m1'],['m1','m2'],['m2','m3'],['m3','m4'],['m4','m5'],['m5','m6'],['m6','m7'],['m7','m0']
    ],
    spawn:['c1','c2','c3','c5','c7','a0','a2','a4','a6','a8','b0','b2','b4','b6','b8','b10','w0','w2','w4','w6','r0','r2','r4','r6','r8','l0','l2','l4','l6','m0','m2','m4','m6'],
    pois:[
      {node:'a1',action:'sample',face:'down',icon:'🧪',text:'Amostra'},
      {node:'a5',action:'inspect',face:'left',icon:'🔬',text:'Analisando'},
      {node:'b1',action:'microscope',face:'down',icon:'🔬',text:'Microscópio'},
      {node:'b8',action:'computer',face:'up',icon:'💻',text:'Dados'},
      {node:'w2',action:'wash',face:'up',icon:'🧼',text:'Lavagem'},
      {node:'l8',action:'sample',face:'up',icon:'🧫',text:'Preparando'},
      {node:'m7',action:'briefing',face:'down',icon:'📋',text:'Relatório'},
      {node:'r8',action:'reception',face:'left',icon:'👋',text:'Recepção'}
    ],
    occluders:[
      {depth:67,clip:'polygon(17% 59%,40% 59%,40% 69%,17% 69%)'},
      {depth:83,clip:'polygon(51% 76%,66% 76%,66% 86%,51% 86%)'},
      {depth:80,clip:'polygon(76% 72%,89% 72%,89% 82%,76% 82%)'}
    ],
    fx:[{x:18,y:20,type:'bubble'},{x:30,y:19,type:'bubble'},{x:65,y:18,type:'monitor'},{x:78,y:18,type:'monitor'}]
  },
  industry:{
    nodes:{
      c0:[36,31],c1:[43,31],c2:[51,31],c3:[59,31],c4:[66,31],c5:[66,38],c6:[66,46],c7:[66,55],c8:[66,65],c9:[66,73],
      l0:[12,31],l1:[20,31],l2:[28,31],l3:[35,31],l4:[12,39],l5:[12,49],l6:[12,59],l7:[20,59],l8:[28,59],l9:[35,59],
      v0:[36,38],v1:[36,45],v2:[36,54],v3:[36,63],v4:[36,72],
      h0:[43,38],h1:[51,38],h2:[59,38],h3:[43,72],h4:[51,72],h5:[59,72],
      t0:[11,67],t1:[11,76],t2:[11,88],t3:[20,91],t4:[31,91],t5:[33,83],t6:[33,75],t7:[31,67],
      q0:[55,45],q1:[55,56],q2:[55,66],q3:[62,67],q4:[72,67],q5:[75,59],q6:[75,49],q7:[70,45],q8:[62,45],
      o0:[78,45],o1:[78,55],o2:[78,65],o3:[86,67],o4:[92,64],o5:[92,53],o6:[92,45],o7:[86,45],
      top0:[47,15],top1:[54,15],top2:[61,15],top3:[54,24],
      shop0:[70,15],shop1:[79,15],shop2:[89,15],shop3:[91,25],shop4:[82,28],shop5:[73,28]
    },
    edges:[
      ['c0','c1'],['c1','c2'],['c2','c3'],['c3','c4'],['c4','c5'],['c5','c6'],['c6','c7'],['c7','c8'],['c8','c9'],
      ['l0','l1'],['l1','l2'],['l2','l3'],['l0','l4'],['l4','l5'],['l5','l6'],['l6','l7'],['l7','l8'],['l8','l9'],['l9','l3'],
      ['c0','v0'],['v0','v1'],['v1','v2'],['v2','v3'],['v3','v4'],['v0','h0'],['h0','h1'],['h1','h2'],['h2','c5'],['v4','h3'],['h3','h4'],['h4','h5'],['h5','c9'],
      ['t0','t1'],['t1','t2'],['t2','t3'],['t3','t4'],['t4','t5'],['t5','t6'],['t6','t7'],['t7','t0'],
      ['q0','q1'],['q1','q2'],['q2','q3'],['q3','q4'],['q4','q5'],['q5','q6'],['q6','q7'],['q7','q8'],['q8','q0'],
      ['o0','o1'],['o1','o2'],['o2','o3'],['o3','o4'],['o4','o5'],['o5','o6'],['o6','o7'],['o7','o0'],
      ['top0','top1'],['top1','top2'],['top1','top3'],
      ['shop0','shop1'],['shop1','shop2'],['shop2','shop3'],['shop3','shop4'],['shop4','shop5'],['shop5','shop0']
    ],
    spawn:['c0','c2','c4','c6','c8','l0','l2','l4','l6','l8','v1','v3','h0','h2','h3','h5','t0','t2','t4','t6','q0','q2','q4','q6','q8','o0','o2','o4','o6','top0','top2','shop0','shop2','shop4'],
    pois:[
      {node:'l1',action:'inspect',face:'up',icon:'🔎',text:'Inspeção'},
      {node:'c2',action:'safety',face:'up',icon:'🦺',text:'Segurança'},
      {node:'top1',action:'control',face:'up',icon:'🖥️',text:'Controle'},
      {node:'shop1',action:'maintenance',face:'up',icon:'🛠️',text:'Manutenção'},
      {node:'q1',action:'meeting',face:'right',icon:'💬',text:'Reunião'},
      {node:'o7',action:'briefing',face:'down',icon:'📋',text:'Planejamento'},
      {node:'v3',action:'radio',face:'right',icon:'📻',text:'Rádio'}
    ],
    occluders:[
      {depth:58,clip:'polygon(31% 46%,52% 46%,52% 61%,31% 61%)'},
      {depth:61,clip:'polygon(55% 51%,76% 51%,76% 66%,55% 66%)'},
      {depth:84,clip:'polygon(9% 68%,33% 68%,33% 92%,9% 92%)'}
    ],
    fx:[{x:25,y:14,type:'warning'},{x:55,y:28,type:'warning'},{x:84,y:15,type:'spark'}]
  },
  platform:{
    nodes:{
      h0:[19,18],h1:[27,18],h2:[35,18],h3:[38,23],h4:[35,31],h5:[27,33],h6:[19,31],h7:[17,24],
      n0:[40,29],n1:[47,29],n2:[55,29],n3:[63,29],n4:[72,29],n5:[80,29],
      w0:[35,36],w1:[35,44],w2:[35,53],w3:[35,62],w4:[35,69],
      e0:[58,35],e1:[58,43],e2:[58,52],e3:[58,61],e4:[58,69],
      r0:[67,34],r1:[76,34],r2:[84,34],r3:[86,43],r4:[86,53],r5:[86,63],r6:[84,70],r7:[75,70],r8:[66,70],
      s0:[35,70],s1:[43,70],s2:[51,70],s3:[59,70],s4:[67,70],s5:[75,70],s6:[84,70],
      d0:[43,78],d1:[43,87],d2:[48,92],d3:[54,92],d4:[58,87],d5:[58,78],
      crew0:[13,43],crew1:[22,43],crew2:[31,43],crew3:[31,53],crew4:[31,64],crew5:[22,67],crew6:[13,64],crew7:[13,53],
      ctrl0:[43,15],ctrl1:[50,15],ctrl2:[57,15],ctrl3:[57,22],ctrl4:[50,23],ctrl5:[43,22]
    },
    edges:[
      ['h0','h1'],['h1','h2'],['h2','h3'],['h3','h4'],['h4','h5'],['h5','h6'],['h6','h7'],['h7','h0'],['h4','n0'],
      ['n0','n1'],['n1','n2'],['n2','n3'],['n3','n4'],['n4','n5'],['n0','w0'],['w0','w1'],['w1','w2'],['w2','w3'],['w3','w4'],
      ['n2','e0'],['e0','e1'],['e1','e2'],['e2','e3'],['e3','e4'],['n4','r0'],['r0','r1'],['r1','r2'],['r2','r3'],['r3','r4'],['r4','r5'],['r5','r6'],['r6','r7'],['r7','r8'],
      ['w4','s0'],['s0','s1'],['s1','s2'],['s2','s3'],['s3','s4'],['s4','s5'],['s5','s6'],['s6','r6'],['e4','s3'],['r8','s4'],
      ['s1','d0'],['d0','d1'],['d1','d2'],['d2','d3'],['d3','d4'],['d4','d5'],['d5','s3'],
      ['crew0','crew1'],['crew1','crew2'],['crew2','crew3'],['crew3','crew4'],['crew4','crew5'],['crew5','crew6'],['crew6','crew7'],['crew7','crew0'],
      ['ctrl0','ctrl1'],['ctrl1','ctrl2'],['ctrl2','ctrl3'],['ctrl3','ctrl4'],['ctrl4','ctrl5'],['ctrl5','ctrl0']
    ],
    spawn:['h0','h2','h4','h6','n0','n2','n4','w0','w2','w4','e0','e2','e4','r0','r2','r4','r6','r8','s0','s2','s4','s6','d0','d2','d4','crew0','crew2','crew4','crew6','ctrl0','ctrl2','ctrl4'],
    pois:[
      {node:'h1',action:'helipad',face:'down',icon:'🚁',text:'Heliponto'},
      {node:'ctrl1',action:'control',face:'up',icon:'🖥️',text:'Controle'},
      {node:'n4',action:'crane',face:'right',icon:'🏗️',text:'Guindaste'},
      {node:'r2',action:'inspect',face:'up',icon:'🔎',text:'Inspeção'},
      {node:'s4',action:'safety',face:'up',icon:'🦺',text:'Passarela'},
      {node:'d2',action:'radio',face:'up',icon:'📻',text:'Rádio'},
      {node:'crew1',action:'coffee',face:'down',icon:'☕',text:'Pausa'}
    ],
    occluders:[
      {depth:61,clip:'polygon(39% 34%,56% 34%,56% 62%,39% 62%)'},
      {depth:69,clip:'polygon(65% 51%,84% 51%,84% 70%,65% 70%)'},
      {depth:66,clip:'polygon(12% 39%,34% 39%,34% 68%,12% 68%)'}
    ],
    fx:[{x:69,y:14,type:'beacon'},{x:78,y:25,type:'warning'},{x:50,y:91,type:'wave'}]
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
  let phase='lobby',density='normal',destroyed=false,timer=null,lastFrameAt=0,nextPairAt=0,lastScene='',rosterCount=0,readyCount=0;

  function renderSceneLayers(){
    const scene=sceneKey(city);if(scene===lastScene)return;lastScene=scene;const graph=NAV[scene];
    if(fxLayer){fxLayer.innerHTML=(graph.fx||[]).map((f,i)=>`<i class="city-fx city-fx-${f.type}" style="--fx-x:${f.x}%;--fx-y:${f.y}%;--fx-delay:${(i*.37).toFixed(2)}s" aria-hidden="true"></i>`).join('');}
    if(occlusionLayer){occlusionLayer.innerHTML=(graph.occluders||[]).map((o,i)=>`<i class="city-occluder" data-occluder="${i}" style="clip-path:${o.clip};z-index:${100+Math.round(o.depth*10)}" aria-hidden="true"></i>`).join('');}
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
    const spread=density==='high'?1.05:(density==='medium' ? .72 : .42);
    const ox=((actor.slot%3)-1)*spread,oy=((Math.floor(actor.slot/3)%3)-1)*spread*.52;
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
    const actor={id,el,seed,rosterIndex:index,slot:index%9,node:'',x:50,y:50,nextAt:performance.now()+500,avatarKey:'',connected:true,ready:false,direction:'down',route:[],scene:'',animState:'idle',animStep:0,frameIndex:1,frameImg:null,poiTarget:''};
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
    const next=actor.route.shift(),from=graph.nodes[actor.node],to=graph.nodes[next];if(!from||!to){actor.route=[];actor.poiTarget='';return false;}
    const dir=directionFrom(from,to),d=distance(from,to),duration=Math.max(.9,Math.min(2.6,d*.16));
    clearExtras(actor);actor.el.style.setProperty('--city-move-time',`${duration.toFixed(2)}s`);setActorClass(actor,'walking',dir);setPosition(actor,next);actor.nextAt=now+duration*1000+100;return true;
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
  function pairTick(now){
    if(REDUCED||phase!=='lobby'||density==='high'||now<nextPairAt)return;
    const live=[...actors.values()].filter(a=>a.connected&&a.nextAt<=now&&!a.route.length);if(live.length<2){nextPairAt=now+2500;return;}
    const a=live[Math.floor(Math.random()*live.length)],graph=graphFor(city),same=new Set(reachable(graph,a.node)),others=live.filter(x=>x!==a&&same.has(x.node)&&distance([a.x,a.y],[x.x,x.y])<=16);
    if(others.length){const b=others[Math.floor(Math.random()*others.length)],roll=Math.random();pairInteraction(a,b,now,roll<.48?'chat':roll<.76?'play':'highfive');}
    nextPairAt=now+3500+Math.random()*4500;
  }
  function engineTick(){
    if(destroyed||document.hidden)return;const now=performance.now();animateFrames(now);pairTick(now);for(const actor of actors.values())if(actor.nextAt<=now)act(actor,now);
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
  function destroy(){destroyed=true;if(timer)clearInterval(timer);timer=null;for(const actor of actors.values())actor.el.remove();actors.clear();if(fxLayer)fxLayer.innerHTML='';if(occlusionLayer)occlusionLayer.innerHTML='';}
  document.addEventListener('visibilitychange',()=>{if(destroyed)return;if(document.hidden){if(timer){clearInterval(timer);timer=null;}}else ensureTimer();});
  renderSceneLayers();
  return{setRoster,setPhase,destroy};
}
