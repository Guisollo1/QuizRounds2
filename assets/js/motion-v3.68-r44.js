const reduceMotion=window.matchMedia?.('(prefers-reduced-motion: reduce)')?.matches===true;
const q=(s,r=document)=>r.querySelector(s);
const qa=(s,r=document)=>[...r.querySelectorAll(s)];

const restartHandles=new WeakMap();
function restart(el,cls,ms=650){
  if(!el||reduceMotion)return;
  let handles=restartHandles.get(el);if(!handles){handles=new Map();restartHandles.set(el,handles);}
  const previous=handles.get(cls);if(previous?.raf)cancelAnimationFrame(previous.raf);if(previous?.timer)clearTimeout(previous.timer);
  el.classList.remove(cls);
  const state={raf:0,timer:0};
  state.raf=requestAnimationFrame(()=>{
    if(!el.isConnected){handles.delete(cls);return;}
    el.classList.add(cls);
    if(ms>0)state.timer=setTimeout(()=>{el?.classList.remove(cls);handles.delete(cls);},ms);else handles.delete(cls);
  });
  handles.set(cls,state);
}
function pulseText(el,cls='motion-text-pop'){restart(el,cls,520);}
function observeText(el,fn){
  if(!el)return null;let last=el.textContent;
  const obs=new MutationObserver(()=>{const now=el.textContent;if(now===last)return;const prev=last;last=now;fn(now,prev,el);});
  obs.observe(el,{childList:true,subtree:true,characterData:true});return obs;
}
function semanticClassName(el){return [...el.classList].filter(c=>!c.startsWith('motion-')).sort().join(' ');}
function observeClass(el,fn){
  if(!el)return null;let last=semanticClassName(el);
  const obs=new MutationObserver(()=>{const now=semanticClassName(el);if(now===last)return;const prev=last;last=now;fn(now,prev,el);});
  obs.observe(el,{attributes:true,attributeFilter:['class']});return obs;
}
function stagger(container,selector,cls='motion-stagger-item'){
  if(!container||reduceMotion)return;
  qa(selector,container).forEach((el,i)=>{el.style.setProperty('--motion-index',String(i));restart(el,cls,780+i*70);});
}
function microPress(){
  const selector='button,.ghost,[role="button"],.avatar-choice';
  const editable=t=>!!t?.closest?.('input,textarea,select,label,[contenteditable="true"]');
  document.addEventListener('pointerdown',e=>{if(editable(e.target))return;const el=e.target.closest?.(selector);if(!el||el.disabled)return;el.classList.add('motion-pressed');},{passive:true});
  const clear=e=>{if(editable(e.target))return;const el=e.target.closest?.(selector);el?.classList.remove('motion-pressed');};
  document.addEventListener('pointerup',clear,{passive:true});document.addEventListener('pointercancel',clear,{passive:true});
  document.addEventListener('keydown',e=>{if(editable(e.target)||!['Enter',' '].includes(e.key))return;const el=e.target.closest?.(selector);if(el&&!el.disabled)el.classList.add('motion-pressed');});
  document.addEventListener('keyup',e=>{if(editable(e.target)||!['Enter',' '].includes(e.key))return;e.target.closest?.(selector)?.classList.remove('motion-pressed');});
}
function connectionMotion(){
  qa('.connection-pill').forEach(el=>observeClass(el,()=>restart(el,'motion-connection-change',620)));
}
function logoMotion(){
  const logos=qa('.display-event-logo,#logoPreview,.player-brand>span,.brand-mark');
  logos.forEach((el,i)=>{if(reduceMotion)return;el.style.setProperty('--motion-delay',`${Math.min(.45,i*.08)}s`);el.classList.add('motion-logo-load');});
}
function createOverlay(className,text=''){
  const el=document.createElement('div');el.className=className;if(text)el.textContent=text;document.body.append(el);return el;
}
function particleBurst(kind='blue',count=22){
  if(reduceMotion||document.body?.dataset?.fxDensity==='low')return;
  if(document.body?.dataset?.fxDensity==='medium')count=Math.max(6,Math.round(count*.45));
  let layer=q('#motionCelebrationLayer');if(!layer){layer=createOverlay('motion-celebration-layer');layer.id='motionCelebrationLayer';layer.setAttribute('aria-hidden','true');}
  const chars=kind==='champion'?['★','✦','●','◆','▰']:kind==='correct'?['✓','✦','●']:['✦','●','◆'];
  for(let i=0;i<count;i++){
    const p=document.createElement('i');p.className=`motion-particle motion-particle-${kind}`;p.textContent=chars[i%chars.length];
    p.style.setProperty('--mx',`${8+Math.random()*84}%`);p.style.setProperty('--my',`${56+Math.random()*24}%`);p.style.setProperty('--mdx',`${(Math.random()-.5)*38}vw`);p.style.setProperty('--mdy',`${-(18+Math.random()*48)}vh`);p.style.setProperty('--mrot',`${(Math.random()-.5)*620}deg`);p.style.setProperty('--mdelay',`${Math.random()*.18}s`);p.style.setProperty('--mdur',`${1.1+Math.random()*.9}s`);layer.append(p);setTimeout(()=>p.remove(),2300);
  }
}
function setupTimer(el,questionEl){
  if(!el)return;let max=0,lastQuestion=questionEl?.textContent||'';
  const update=()=>{const qtxt=questionEl?.textContent||'';if(qtxt!==lastQuestion){lastQuestion=qtxt;max=0;}const n=Number(String(el.textContent).replace(/\D/g,''));if(Number.isFinite(n)&&n>0){max=Math.max(max,n);const ratio=max?Math.max(0,Math.min(1,n/max)):1;el.style.setProperty('--timer-progress',String(ratio));if(n<=5)restart(el,'motion-timer-kick',420);}};
  observeText(el,update);update();
}

function playerMotion(){
  const join=q('#joinView');if(join)join.classList.add('motion-r41-entry-safe');
  const picker=q('#avatarPicker');if(picker){
    new MutationObserver(()=>stagger(picker,'[data-avatar-choice]','motion-avatar-in')).observe(picker,{childList:true,subtree:true});
    picker.addEventListener('click',e=>{const item=e.target.closest?.('[data-avatar-choice]');if(item)restart(item,'motion-avatar-select',520);});
  }
  const ready=q('#playerReadyBtn');if(ready)observeClass(ready,(now,prev)=>{if(now.split(' ').includes('ready')&&!prev.split(' ').includes('ready')){restart(ready,'motion-ready-confirm',850);particleBurst('correct',10);}});
  const question=q('#questionText'),answers=q('#answerArea');
  observeText(question,()=>{pulseText(question,'motion-question-in');stagger(answers,'.choice-btn','motion-answer-in');});
  if(answers){new MutationObserver(()=>stagger(answers,'.choice-btn','motion-answer-in')).observe(answers,{childList:true,subtree:true});}
  const status=q('#answerStatus');observeText(status,(now)=>{if(!now.trim())return;restart(status,'motion-status-in',600);});
  const streak=q('#streakStatus');observeText(streak,(now)=>{if(!now.trim()||streak.classList.contains('hidden'))return;restart(streak,'motion-streak-pop',760);});observeClass(streak,()=>{if(!streak.classList.contains('hidden')&&streak.textContent.trim())restart(streak,'motion-streak-pop',760);});
  const roundPoints=q('#roundPointsInfo');observeText(roundPoints,(now)=>{if(!now.trim()||roundPoints.classList.contains('hidden'))return;const pts=Number((now.match(/[-+]?\d+/)||['0'])[0]);const cls=pts>0?'player-fx-correct':'player-fx-wrong';document.body.classList.remove('player-fx-correct','player-fx-wrong');restart(document.body,cls,850);if(pts>0)particleBurst('correct',16);});
  const ranking=q('#ranking');if(ranking)new MutationObserver(()=>stagger(ranking,'.rank-row','motion-rank-row')).observe(ranking,{childList:true});
  setupTimer(q('#timerText'),question);
  observeClass(document.body,(now,prev)=>{if(now.split(' ').includes('player-champion')&&!prev.split(' ').includes('player-champion'))particleBurst('champion',34);});
}

function displayMotion(){
  const clock=q('#displayWallClockTime');let lastMinute='';observeText(clock,(now)=>{const minute=now.slice(0,5);restart(clock,'motion-clock-tick',430);if(minute!==lastMinute){lastMinute=minute;restart(clock.parentElement,'motion-clock-minute',700);}});
  const pin=q('#displayLobbyCode');observeText(pin,()=>restart(pin,'motion-pin-reveal',850));
  const qr=q('#displayQr');if(qr)new MutationObserver(()=>restart(qr,'motion-qr-pop',720)).observe(qr,{childList:true,subtree:true});
  const question=q('#displayQuestionText'),options=q('#displayOptions');
  observeText(question,()=>pulseText(question,'motion-question-in'));
  if(options)new MutationObserver(()=>stagger(options,'.display-option','motion-option-in')).observe(options,{childList:true});
  setupTimer(q('#displayTimer'),question);
  const result=q('#displayResultText'),reveal=q('#displayRevealStep');observeText(result,()=>restart(result,'motion-result-reveal',700));observeText(reveal,()=>restart(reveal,'motion-reveal-kicker',520));
  let leader='';
  const rankLists=qa('#displayRanking,#displayFinalRanking');
  rankLists.forEach(list=>{if(!list)return;new MutationObserver(()=>{stagger(list,'li','motion-rank-row');const name=q('li:first-child strong',list)?.textContent?.replace(/[▲▼]\d+.*/,'').trim()||'';if(leader&&name&&name!==leader&&document.body.dataset.displayPhase!=='lobby'){const toast=q('#motionLeaderToast')||createOverlay('motion-leader-toast');toast.id='motionLeaderToast';toast.textContent=`★ Novo líder: ${name}`;restart(toast,'show',1800);particleBurst('blue',12);}if(name)leader=name;}).observe(list,{childList:true,subtree:true});});
  const podium=q('#displayPodium');if(podium)new MutationObserver(()=>{stagger(podium,'.podium-place','motion-podium-in');setTimeout(()=>particleBurst('champion',26),900);}).observe(podium,{childList:true});
  const finished=q('#displayFinished');if(finished){let lastStage='';new MutationObserver(()=>{const stage=finished.dataset.finalStage||'';if(stage&&stage!==lastStage){lastStage=stage;restart(finished,'motion-final-stage',760);if(stage==='champion')particleBurst('champion',42);}}).observe(finished,{attributes:true,attributeFilter:['data-final-stage']});}
  const stage=q('#displayStage');if(stage)observeClass(stage,()=>restart(stage,'motion-stage-sync',500));
}

function adminMotion(){
  q('#loginView')?.classList.add('motion-r41-entry-safe');
  qa('.admin-tab,[data-config-pane],[data-rules-mode]').forEach(btn=>btn.addEventListener('click',()=>restart(btn,'motion-tab-confirm',420)));
  const workspace=q('.admin-workspace');if(workspace){let lastPanel=q('.tab-panel.active',workspace)?.dataset.panel||'';new MutationObserver(records=>{if(!records.some(m=>m.target?.matches?.('.tab-panel')))return;const active=q('.tab-panel.active',workspace),key=active?.dataset.panel||'';if(!active||key===lastPanel)return;lastPanel=key;restart(active,'motion-panel-in',560);}).observe(workspace,{subtree:true,attributes:true,attributeFilter:['class']});}
  const toast=q('#actionToast');if(toast)observeClass(toast,()=>{if(toast.classList.contains('show'))restart(toast,'motion-toast-pop',620);});
  const saved=q('#editorSavedState');observeText(saved,(now)=>{if(/sincronizado|salv/i.test(now)&&!/salvando|falha/i.test(now))restart(saved,'motion-save-ok',700);});
  const remotePhase=q('#remotePhaseBadge');observeText(remotePhase,()=>restart(q('.remote-round-card'),'motion-remote-state',650));
  qa('[data-remote-action],[data-remote-final-show]').forEach(btn=>btn.addEventListener('click',()=>restart(btn,'motion-remote-command',520)));
  const remoteDisplay=q('#remoteDisplayStatus');if(remoteDisplay)new MutationObserver(()=>restart(remoteDisplay,'motion-status-card',520)).observe(remoteDisplay,{childList:true,subtree:true});
  const settingsBtn=q('#saveRoomSettingsBtn');settingsBtn?.addEventListener('click',()=>restart(settingsBtn,'motion-save-request',760));
}

function simulatorMotion(){
  const shell=q('.sim-shell,.simulator-shell,.admin-app');if(shell&&!reduceMotion)shell.classList.add('motion-page-enter');
  qa('.sim-tab').forEach(btn=>btn.addEventListener('click',()=>restart(btn,'motion-tab-confirm',420)));
  const log=q('#simLog');if(log)new MutationObserver(()=>{const last=log.lastElementChild;if(last)restart(last,'motion-log-entry',560);}).observe(log,{childList:true});
}

microPress();connectionMotion();logoMotion();
if(document.body.classList.contains('player-body'))playerMotion();
if(document.body.classList.contains('display-body'))displayMotion();
if(document.body.classList.contains('admin-body'))adminMotion();
if(document.body.classList.contains('sim-body')||q('#simLoginForm'))simulatorMotion();

document.documentElement.classList.add('motion-r41-ready');
