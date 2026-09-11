import{db,$,esc,renderRank,setConnection,serverRemaining,sleep,APP_VERSION,BUILD_ID,BACKEND_SCHEMA_REQUIRED,applyDocumentTheme,normalizeLogoUrl}from'./common-v3.68-r44.js';
import{avatarMarkup}from'./avatars-v3.68-r44.js';

let room=null,roomState=null,queueRows=[],questionBank=[],participants=[],historyRows=[],channel=null,progressChannel=null,poll=null,serverOffset=0,timerTick=null,reconnectTimer=null,reconnectAttempt=0,auditTick=null,actionBusy=false,presenceOnline=null,displayOnline=false,progressRefreshTimer=null,lastAdminQr='',activeAdminTab='central',autoOpening=false,autoClosing=false,lastLatency=0,subscriptionEpoch=0,lastConnectionKey='',refreshSeq=0,refreshAppliedSeq=0,displayWindowRef=null,remoteAuthorized=false,remoteModeActive=false,remoteDeviceLabel='',remotePairLink='',remotePairExpiresAt=0,remoteRoomSyncTimer=null,remoteRoomSyncInFlight=false,eventModeActive=false,controllerGranted=true,controllerConflictLabel='',controllerHeartbeatTimer=null,lastPreflight=null,presenceVersions={players:[],displays:[],admins:[]},versionMismatch=false,eventInsights=null,lastInsightsRounds=-1,lastObservedPhase='',diagnosticEvents=[],lastRemotePhase='',lastRemoteFinalStage='',remoteDeviceCount=0,lastVersionBroadcast='',backendCompatible=false,backendMeta=null;
let parsedImport={questions:[],errors:[],results:[]},parseTimer=null,recentQuestionIds=new Set(),connectionTestNonce='',connectionAcks=new Set();
let editingQuestionId=null,selectedQuestionIds=new Set(),activeBankQuick='all',visibleQuestionRows=[],questionStats=new Map(),questionCollections=[],recentRooms=[],rulesMode='simple',participantFilter='all';
let settingsDraftDirty=false,settingsSaving=false,settingsSaveTimer=null,settingsDraftSerial=0,settingsTrackingReady=false;
const POLL_CONNECTED=4000,POLL_FALLBACK=3000,MAX_IMPORT=500,REMOTE_DEVICE_KEY='quiz2RemoteDeviceToken:v1',REMOTE_ROOM_KEY='quiz2RemoteRoomId:v2',CONTROLLER_DEVICE_KEY='quiz2AdminControllerDevice:v1';
const CHOICE_KEYS=['A','B','C','D','E'],REQUIRED_CHOICE_KEYS=['A','B','C','D'];
// r37: draft-lock impede refreshState de desfazer checkboxes; autosave mantém regras estáveis.
const SETTINGS_DRAFT_IDS=['expectedPlayers','defaultTime','defaultPoints','shuffleAnswersToggle','breakEvery','classificationEnabled','qualifyTop','qualificationSchedule','lateJoinPolicy','lateJoinUntil','autoCloseAll','autoCloseTime','speedBonusEnabled','streakEnabled','streakBonus','avoidRecentGames','themePreset','soundEnabled','allowDuplicateNames','bannedWords','rehearsalMode','lobbyMessage','lobbyStartTime','avatarScene','lobbyMapMode','lobbyReadyThreshold','lobbyMusicEnabled','displayClockMode'];


const $$=s=>[...document.querySelectorAll(s)];
let adminMotionLoaded=false;
function loadAdminMotionAfterAuth(){
  if(adminMotionLoaded)return;
  adminMotionLoaded=true;
  if(!document.getElementById('adminMotionCss')){const link=document.createElement('link');link.id='adminMotionCss';link.rel='stylesheet';link.href='assets/css/motion-v3.68-r44.css?v=3.68-r44';document.head.appendChild(link);}
  import('./motion-v3.68-r44.js?v=3.68-r44').catch(()=>{});
}

let questionHelpReturnFocus=null;
function filterQuestionHelp(){const input=$('#questionHelpSearch'),empty=$('#questionHelpEmpty'),term=String(input?.value||'').trim().toLocaleLowerCase('pt-BR');let shown=0;$$('#questionHelpModal [data-help-section]').forEach(section=>{const hay=section.textContent.toLocaleLowerCase('pt-BR'),visible=!term||hay.includes(term);section.classList.toggle('is-filtered',!visible);if(visible)shown++;});empty?.classList.toggle('hidden',shown>0);}
function openQuestionHelp(focusTarget=''){const modal=$('#questionHelpModal'),dialog=modal?.querySelector('.question-help-dialog');if(!modal||!dialog)return;questionHelpReturnFocus=document.activeElement instanceof HTMLElement?document.activeElement:null;modal.classList.remove('hidden');document.body.classList.add('help-modal-open');if($('#questionHelpSearch'))$('#questionHelpSearch').value='';filterQuestionHelp();requestAnimationFrame(()=>{dialog.focus();if(focusTarget)document.getElementById(focusTarget)?.scrollIntoView({block:'start'});});}
function closeQuestionHelp(){const modal=$('#questionHelpModal');if(!modal||modal.classList.contains('hidden'))return;modal.classList.add('hidden');document.body.classList.remove('help-modal-open');questionHelpReturnFocus?.focus?.();questionHelpReturnFocus=null;}
function trapQuestionHelpFocus(e){if(e.key!=='Tab')return;const modal=$('#questionHelpModal');if(!modal||modal.classList.contains('hidden'))return;const focusable=$$('button:not([disabled]),a[href],input:not([disabled]),select:not([disabled]),textarea:not([disabled]),[tabindex]:not([tabindex="-1"])').filter(el=>modal.contains(el)&&el.offsetParent!==null);if(!focusable.length){e.preventDefault();modal.querySelector('.question-help-dialog')?.focus();return;}const first=focusable[0],last=focusable[focusable.length-1];if(e.shiftKey&&document.activeElement===first){e.preventDefault();last.focus();}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first.focus();}}
function goFromHelp(pane){closeQuestionHelp();switchAdminTab('questions');setQuestionPane(pane,{scroll:true});setTimeout(()=>pane==='edit'?$('#qPrompt')?.focus():$('#bulkQuestionText')?.focus(),180);}

function diag(type,message,details={}){const item={at:new Date().toISOString(),type,message,details};diagnosticEvents.unshift(item);diagnosticEvents=diagnosticEvents.slice(0,160);renderDiagnostics();}
function renderDiagnostics(){
  const el=$('#diagnosticLog');if(el)el.innerHTML=diagnosticEvents.slice(0,80).map(x=>`<div class="diagnostic-row ${esc(x.type)}"><time>${new Date(x.at).toLocaleTimeString('pt-BR')}</time><strong>${esc(x.message)}</strong><span>${esc(Object.keys(x.details||{}).length?JSON.stringify(x.details):'')}</span></div>`).join('')||'<div class="empty">Sem eventos técnicos nesta sessão.</div>';
  const lastError=diagnosticEvents.find(x=>x.type==='error');
  if($('#diagBuild'))$('#diagBuild').textContent=BUILD_ID;
  if($('#diagSchema'))$('#diagSchema').textContent=String(Number(backendMeta?.schema_version||BACKEND_SCHEMA_REQUIRED)).padStart(3,'0');
  if($('#diagRoomState'))$('#diagRoomState').textContent=room?`${statusLabel(phase())} • v${Number(roomState?.room?.state_version||0)}`:'Sem sala';
  if($('#diagController'))$('#diagController').textContent=remoteModeActive?'Controle remoto':controllerGranted?'Este aparelho':'Somente acompanhamento';
  if($('#diagLastError'))$('#diagLastError').textContent=lastError?(lastError.message||'Erro registrado'):'Nenhum';
}
function conn(status,detail=''){const key=`${status}|${detail}`;if(key===lastConnectionKey)return;lastConnectionKey=key;setConnection($('#adminConnection'),status,detail);const banner=$('#adminReconnectBanner');if(banner){const show=['connecting','fallback','offline','error'].includes(status)&&!!room;banner.classList.toggle('hidden',!show);banner.textContent=status==='offline'?'Sem internet. O painel manterá a sala e retomará automaticamente quando a conexão voltar.':status==='fallback'?'Reconectando… reconstruindo o estado oficial pelo modo de segurança.':status==='error'?'Conexão instável. Tentando recuperar o estado oficial da sala…':'Reconectando e reconstruindo o estado oficial da sala…';}diag(status==='connected'?'ok':'net',`Conexão: ${status}`,detail?{detail}:{});}
function haptic(pattern=35){if(!navigator.vibrate)return;try{navigator.vibrate(pattern);}catch{}}
function remoteVibrate(pattern=35){if(!remoteModeActive)return;haptic(pattern);}
let actionToastTimer=null;function actionToast(text,type='ok'){const box=$('#actionToast');if(!box)return;clearTimeout(actionToastTimer);$('#actionToastIcon').textContent=type==='error'?'!':'✓';$('#actionToastText').textContent=text;box.className=`action-toast ${type}`;requestAnimationFrame(()=>box.classList.add('show'));actionToastTimer=setTimeout(()=>{box.classList.remove('show');setTimeout(()=>box.classList.add('hidden'),240);},1800);box.classList.remove('hidden');}
function exportDiagnostics(){const lines=['QuizRounds '+BUILD_ID+' — diagnóstico do evento',`Frontend: ${BUILD_ID}`,`Backend schema: ${Number(backendMeta?.schema_version||BACKEND_SCHEMA_REQUIRED)}`,`Sala: ${room?.code||'sem sala'}`,`Estado: ${phase()} • v${Number(roomState?.room?.state_version||0)}`,`Controlador: ${remoteModeActive?'remoto':controllerGranted?'este aparelho':'acompanhamento'}`,`Gerado: ${new Date().toISOString()}`,'',...diagnosticEvents.slice().reverse().map(x=>`${x.at} | ${x.type.toUpperCase()} | ${x.message}${Object.keys(x.details||{}).length?' | '+JSON.stringify(x.details):''}`)];downloadText(`QuizRounds_diagnostico_${room?.code||'sem_sala'}_${new Date().toISOString().replace(/[:.]/g,'-')}.txt`,lines.join('\n'));}
function switchAdminTab(name){activeAdminTab=name;document.documentElement.classList.toggle('questions-page-scroll',name==='questions');document.body.classList.toggle('questions-page-scroll',name==='questions');$$('.admin-tab').forEach(btn=>{const on=btn.dataset.tab===name;btn.classList.toggle('active',on);btn.setAttribute('aria-selected',String(on));});$$('.tab-panel').forEach(panel=>panel.classList.toggle('active',panel.dataset.panel===name));try{localStorage.setItem('quiz2AdminTab',name);}catch{}if(name==='presentation'){renderAdminQr();refreshState(false);loadParticipants();}if(name==='central'){renderSetupReview();loadRecentRooms();}}
function initAdminTabs(){if($('#adminTabs')?.dataset.ready)return;$('#adminTabs').dataset.ready='1';$$('.admin-tab').forEach(btn=>btn.addEventListener('click',()=>switchAdminTab(btn.dataset.tab)));let saved='central';try{saved=localStorage.getItem('quiz2AdminTab')||'central';}catch{}switchAdminTab(['central','questions','config','presentation'].includes(saved)?saved:'central');}
function setQuestionPane(name,{scroll=false}={}){const panel=$('#adminPanelQuestions');if(!panel)return;const pane=['edit','bank','import'].includes(name)?name:'edit';panel.dataset.questionPane=pane;[...panel.querySelectorAll('.question-subtabs [data-question-pane]')].forEach(btn=>{const on=btn.dataset.questionPane===pane;btn.classList.toggle('active',on);btn.setAttribute('aria-selected',String(on));});try{localStorage.setItem('quiz2QuestionPane',pane);}catch{}if(scroll)panel.querySelector('.question-subtabs')?.scrollIntoView({behavior:'smooth',block:'nearest'});}
function initQuestionSubtabs(){const nav=document.querySelector('.question-subtabs');if(!nav||nav.dataset.ready)return;nav.dataset.ready='1';let pane='edit';try{pane=localStorage.getItem('quiz2QuestionPane')||localStorage.getItem('quiz2MobileQuestionPane')||'edit';}catch{}[...nav.querySelectorAll('[data-question-pane]')].forEach(btn=>btn.addEventListener('click',()=>setQuestionPane(btn.dataset.questionPane,{scroll:true})));setQuestionPane(pane);}
function setConfigPane(name,{scroll=false}={}){const panel=$('#adminPanelConfig');if(!panel)return;const pane=['room','rules','rounds'].includes(name)?name:'room';panel.dataset.configPane=pane;[...panel.querySelectorAll('.config-subtabs [data-config-pane]')].forEach(btn=>{if(!btn.matches('button'))return;const on=btn.dataset.configPane===pane;btn.classList.toggle('active',on);btn.setAttribute('aria-selected',String(on));});try{localStorage.setItem('quiz2ConfigPane',pane);}catch{}if(scroll)panel.querySelector('.config-subtabs')?.scrollIntoView({behavior:'smooth',block:'nearest'});}
function initConfigSubtabs(){const nav=document.querySelector('.config-subtabs');if(!nav||nav.dataset.ready)return;nav.dataset.ready='1';let pane='room';try{pane=localStorage.getItem('quiz2ConfigPane')||'room';}catch{}[...nav.querySelectorAll('[data-config-pane]')].forEach(btn=>btn.addEventListener('click',()=>setConfigPane(btn.dataset.configPane,{scroll:true})));setConfigPane(pane);}
function jumpConfigBlock(name){
  if(name==='questions'){switchAdminTab('questions');setQuestionPane('bank',{scroll:true});return;}
  const pane=['rules','ranking','final'].includes(name)?'rules':'room';switchAdminTab('config');setConfigPane(pane);
  if(['ranking','final'].includes(name))setRulesMode('advanced');
  const target={rules:'configBlockRules',visual:'configBlockVisual',lobby:'configBlockLobby',ranking:'configBlockRanking',final:'configBlockFinal'}[name];
  if(target)setTimeout(()=>document.getElementById(target)?.scrollIntoView({behavior:'smooth',block:'center'}),70);
}
function plannedRounds(){return Math.max(1,Math.min(200,Number($('#plannedRounds').value)||10));}
function phase(){return roomState?.room?.phase||room?.phase||'lobby';}
function roomSettings(){return roomState?.room?.settings||room?.settings||{};}
function renderAdminStatusBar(){
  const realtime=lastConnectionKey.startsWith('connected'),players=Number(presenceOnline??roomState?.active_count??0);
  if($('#statusRoom'))$('#statusRoom').textContent=room?.code||'—';
  if($('#statusPlayers'))$('#statusPlayers').textContent=String(players);
  if($('#statusDisplay')){$('#statusDisplay').textContent=displayOnline?'Conectado':'Não detectado';$('#statusDisplay').dataset.state=displayOnline?'ready':'warn';}
  if($('#statusRealtime')){$('#statusRealtime').textContent=realtime?'Online':navigator.onLine?'Reconectando':'Offline';$('#statusRealtime').dataset.state=realtime?'ready':navigator.onLine?'warn':'fail';}
  if($('#statusController')){$('#statusController').textContent=remoteModeActive?'Remoto':controllerGranted?'Ativo':'Acompanhando';$('#statusController').dataset.state=(remoteModeActive||controllerGranted)?'ready':'warn';}
  if($('#statusBuild'))$('#statusBuild').textContent=BUILD_ID.replace('3.68-','');
}
function applyAdminTheme(theme=null,logo=null){const s=roomSettings(),t=theme||$('#themePreset')?.value||roomState?.room?.theme||s.theme||'violet',l=logo!==null?logo:($('#logoUrl')?.value||roomState?.room?.logo_url||'');applyDocumentTheme(t,l);}

const LOGO_BUCKET='quiz-logos',LOGO_MAX_BYTES=5*1024*1024,LOGO_MIME=new Set(['image/png','image/jpeg','image/webp']);
let pendingLogoObjectUrl='',logoEditorDirty=false,logoDraftValue='',logoLinkSaveTimer=null,logoLinkSaveSeq=0;
function logoShapeLabel(w,h){const r=w/Math.max(1,h);return r>=2.15?'HORIZONTAL':r<=.72?'VERTICAL':r>=1.28?'PAISAGEM':'QUADRADA';}
function setLogoStatus(message='',kind='neutral'){const el=$('#logoUploadStatus');if(!el)return;el.textContent=message;el.dataset.kind=kind;}
function clearPendingLogoObject(){if(pendingLogoObjectUrl){URL.revokeObjectURL(pendingLogoObjectUrl);pendingLogoObjectUrl='';}}
function logoDraftStorageKey(){return`quiz2LogoDraft:v3:${room?.id||'draft'}`;}
function storeLogoDraft(value=''){try{sessionStorage.setItem(logoDraftStorageKey(),JSON.stringify({value:String(value??''),at:Date.now()}));}catch{}}
function restoreLogoDraft(){try{const raw=sessionStorage.getItem(logoDraftStorageKey());if(raw===null)return null;const item=JSON.parse(raw);if(!item||Date.now()-Number(item.at||0)>21600000){sessionStorage.removeItem(logoDraftStorageKey());return null;}return String(item.value??'');}catch{return null;}}
function clearStoredLogoDraft(){try{sessionStorage.removeItem(logoDraftStorageKey());}catch{}}
function markLogoDraft(value=null){const input=$('#logoUrl');logoEditorDirty=true;logoDraftValue=String(value??input?.value??'');storeLogoDraft(logoDraftValue);}
function commitLogoDraft(value=''){logoEditorDirty=false;logoDraftValue=String(value||'');clearStoredLogoDraft();const input=$('#logoUrl');if(input)input.value=logoDraftValue;}
function friendlyLogoError(error){const message=String(error?.message||error||'Falha no upload da logo.');if(/permission denied for function is_admin/i.test(message))return'Permissão do Storage desatualizada. Recarregue o ADM; a correção v3.65 mantém essa dependência removida do upload.';if(/row-level security|unauthorized|forbidden|403/i.test(message))return'Upload bloqueado pela política do Storage. Confirme que você está autenticado como administrador e tente novamente.';return message;}
function managedLogoPath(url=''){
  const raw=String(url||'').trim();if(!raw)return'';
  try{
    const u=new URL(raw),marker=`/storage/v1/object/public/${LOGO_BUCKET}/`,ix=u.pathname.indexOf(marker);
    if(ix<0)return'';
    return decodeURIComponent(u.pathname.slice(ix+marker.length));
  }catch{return'';}
}
async function removeManagedLogo(url,{quiet=true}={}){
  const path=managedLogoPath(url);if(!path)return false;
  try{
    const{data:{user}}=await db.auth.getUser();
    if(!user||!path.startsWith(`${user.id}/`))return false;
    const usage=await db.rpc('admin_managed_logo_usage_count',{p_url:String(url||'').trim()});
    if(usage.error)throw usage.error;
    if(Number(usage.data||0)>0){diag('ok','Logo preservada: ainda usada por outra sala',{path,references:Number(usage.data||0)});return false;}
    const{error}=await db.storage.from(LOGO_BUCKET).remove([path]);
    if(error)throw error;
    diag('ok','Logo antiga removida do Storage',{path});
    return true;
  }catch(e){
    diag('warn','Logo antiga preservada por segurança; não foi possível confirmar referências',{error:e.message||String(e)});
    if(!quiet)setLogoStatus('A nova logo foi aplicada. O arquivo antigo foi preservado por segurança.','warn');
    return false;
  }
}

function renderLogoPreview(source='',message=''){
  const img=$('#logoPreview'),empty=$('#logoPreviewEmpty'),badge=$('#logoFitBadge');if(!img||!empty)return;
  const url=String(source||'').trim();if(!url){img.classList.add('hidden');img.removeAttribute('src');empty.classList.remove('hidden');if(badge)badge.textContent='AUTO FIT';if(message)setLogoStatus(message);return;}
  img.onload=()=>{empty.classList.add('hidden');img.classList.remove('hidden');if(badge)badge.textContent=`${logoShapeLabel(img.naturalWidth,img.naturalHeight)} • ${img.naturalWidth}×${img.naturalHeight}`;if(message)setLogoStatus(message,'ready');};
  img.onerror=()=>{img.classList.add('hidden');empty.classList.remove('hidden');if(badge)badge.textContent='NÃO CARREGOU';setLogoStatus('Não foi possível carregar essa imagem. Verifique o link ou escolha outro arquivo.','error');};
  img.src=url;
}
function logoUrlForSettings(){const raw=$('#logoUrl')?.value.trim()||'';if(!raw)return'';const safe=normalizeLogoUrl(raw);if(!safe)throw new Error('Use um link HTTPS válido. HTTP é aceito somente em localhost para desenvolvimento.');return safe;}
async function persistLogoLinkNow(){
  clearTimeout(logoLinkSaveTimer);logoLinkSaveTimer=null;
  const input=$('#logoUrl'),raw=input?.value.trim()||'';markLogoDraft(raw);if(!room||!raw)return false;
  const safe=normalizeLogoUrl(raw);if(!safe)return false;
  const seq=++logoLinkSaveSeq,oldLogo=roomState?.room?.logo_url||room?.logo_url||'';setLogoStatus('Salvando link da logo…');
  try{
    const{data,error}=await db.rpc('admin_update_room_settings',{p_room_id:room.id,p_patch:{logo_url:safe}});if(error)throw error;if(seq!==logoLinkSaveSeq)return false;
    room=data||room;rememberRoom();commitLogoDraft(safe);await refreshState(true);if(oldLogo&&oldLogo!==safe)await removeManagedLogo(oldLogo);setLogoStatus('Link da logo salvo e sincronizado.','ready');return true;
  }catch(e){if(seq===logoLinkSaveSeq)setLogoStatus(friendlyLogoError(e),'error');return false;}
}
function scheduleLogoLinkSave(){clearTimeout(logoLinkSaveTimer);const raw=$('#logoUrl')?.value.trim()||'',safe=raw?normalizeLogoUrl(raw):'';if(!room||!safe)return;logoLinkSaveTimer=setTimeout(()=>persistLogoLinkNow(),850);}
function previewLogoFromLink(){clearPendingLogoObject();const raw=$('#logoUrl')?.value.trim()||'';markLogoDraft(raw);if(!raw){clearTimeout(logoLinkSaveTimer);applyAdminTheme($('#themePreset')?.value||null,'');renderLogoPreview('','Logo removida da prévia. Use “Remover logo” para confirmar a exclusão.');return;}const safe=normalizeLogoUrl(raw);if(!safe){clearTimeout(logoLinkSaveTimer);renderLogoPreview('');setLogoStatus('Link inválido. Use HTTPS. HTTP é aceito somente em localhost.','error');return;}applyAdminTheme($('#themePreset')?.value||null,safe);renderLogoPreview(safe,'Prévia carregada. O link será salvo automaticamente.');scheduleLogoLinkSave();}
function previewSelectedLogo(){clearTimeout(logoLinkSaveTimer);logoLinkSaveSeq++;const file=$('#logoFile')?.files?.[0];if(!file)return;if(!LOGO_MIME.has(file.type)){setLogoStatus('Formato não aceito. Use PNG, JPG ou WebP.','error');$('#logoFile').value='';return;}if(file.size>LOGO_MAX_BYTES){setLogoStatus('Arquivo acima de 5 MB. Escolha uma imagem menor.','error');$('#logoFile').value='';return;}clearPendingLogoObject();markLogoDraft($('#logoUrl')?.value||'');pendingLogoObjectUrl=URL.createObjectURL(file);renderLogoPreview(pendingLogoObjectUrl,`Prévia local • ${(file.size/1024/1024).toFixed(2)} MB. Clique em “Enviar logo”.`);}
async function uploadLogoFile(){
  const input=$('#logoFile'),btn=$('#uploadLogoBtn'),file=input?.files?.[0];if(!file)return setLogoStatus('Escolha uma imagem antes de enviar.','error');
  if(!LOGO_MIME.has(file.type))return setLogoStatus('Formato não aceito. Use PNG, JPG ou WebP.','error');if(file.size>LOGO_MAX_BYTES)return setLogoStatus('Arquivo acima de 5 MB.','error');
  try{const{data:{session}}=await db.auth.getSession();if(session?.expires_at&&session.expires_at*1000-Date.now()<90000)await db.auth.refreshSession();}catch{}
  const{data:{user},error:userError}=await db.auth.getUser();if(userError||!user)return setLogoStatus('Sessão de administrador indisponível. Entre novamente.','error');
  const oldLogo=roomState?.room?.logo_url||room?.logo_url||'',ext=file.type==='image/png'?'png':file.type==='image/webp'?'webp':'jpg',scope=room?.id||'draft',path=`${user.id}/${scope}/${Date.now()}-${crypto.randomUUID?.()||Math.random().toString(36).slice(2)}.${ext}`;
  btn.disabled=true;setLogoStatus('Enviando logo para o Supabase…');
  try{
    const{error}=await db.storage.from(LOGO_BUCKET).upload(path,file,{cacheControl:'31536000',contentType:file.type,upsert:false});if(error)throw error;
    const{data}=db.storage.from(LOGO_BUCKET).getPublicUrl(path),publicUrl=data?.publicUrl||'';if(!publicUrl)throw new Error('O Supabase não retornou o link público da logo.');
    $('#logoUrl').value=publicUrl;markLogoDraft(publicUrl);clearPendingLogoObject();renderLogoPreview(publicUrl,'Upload concluído.');applyAdminTheme($('#themePreset')?.value||null,publicUrl);
    if(room){
      try{await saveRoomSettings(false);}catch(e){await db.storage.from(LOGO_BUCKET).remove([path]);throw e;}
      setLogoStatus('Logo enviada e aplicada à sala.','ready');
    }else setLogoStatus('Logo enviada. Ela será aplicada quando você criar a sala.','ready');
    input.value='';
  }catch(e){setLogoStatus(friendlyLogoError(e),'error');}
  finally{btn.disabled=false;}
}
async function clearEventLogo(){
  clearTimeout(logoLinkSaveTimer);logoLinkSaveSeq++;const oldLogo=roomState?.room?.logo_url||room?.logo_url||'';
  clearPendingLogoObject();if($('#logoFile'))$('#logoFile').value='';if($('#logoUrl'))$('#logoUrl').value='';markLogoDraft('');applyAdminTheme($('#themePreset')?.value||null,'');renderLogoPreview('');
  try{
    if(room){await saveRoomSettings(false);setLogoStatus('Logo removida da sala e arquivo antigo limpo quando aplicável.','ready');}
    else{commitLogoDraft('');setLogoStatus('Logo removida.');}
  }catch(e){setLogoStatus(friendlyLogoError(e),'error');}
}
function syncLogoEditor(force=false){
  const input=$('#logoUrl'),serverUrl=roomState?.room?.logo_url||room?.logo_url||'';
  if(!force&&!logoEditorDirty){const stored=restoreLogoDraft();if(stored!==null){logoEditorDirty=true;logoDraftValue=stored;if(input)input.value=stored;}}
  if(force||!logoEditorDirty)commitLogoDraft(serverUrl);
  if(pendingLogoObjectUrl){renderLogoPreview(pendingLogoObjectUrl,'Prévia local preservada durante a sincronização. Clique em “Enviar logo”.');return;}
  const raw=String(input?.value??logoDraftValue??'').trim(),safe=raw?normalizeLogoUrl(raw):'';if(raw&&!safe){setLogoStatus('Link em edição preservado, mas ainda inválido. Use HTTPS.','error');return;}applyAdminTheme(null,safe||'');renderLogoPreview(safe||'',safe?(logoEditorDirty?'Prévia local preservada durante a sincronização.':'Logo atual da sala.'):(logoEditorDirty?'Alteração local preservada.':'Nenhuma logo configurada.'));
}

function toLocalDateTimeInput(value){if(!value)return'';const d=new Date(value);if(!Number.isFinite(d.getTime()))return'';const pad=n=>String(n).padStart(2,'0');return`${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;}
function lobbyReadiness(){const total=Number(roomState?.participant_count||0),ready=Number(roomState?.ready_count||0),online=Number(roomState?.active_count||0),threshold=Math.max(50,Math.min(100,Number(roomSettings().lobby_ready_threshold||80))),pct=total?Math.round(ready*100/total):0,onlinePct=total?Math.round(online*100/total):0;return{total,ready,online,threshold,pct,onlinePct,highlight:total>0&&pct>=threshold&&onlinePct>=threshold};}
function renderLobbyControls(){const s=roomSettings(),mode=String(s.lobby_map_mode||'auto'),r=lobbyReadiness();$$('[data-lobby-layout]').forEach(b=>b.classList.toggle('active',b.dataset.lobbyLayout===mode));const badge=$('#lobbyReadinessAdmin');if(badge){badge.textContent=r.total?`${r.ready}/${r.total} prontos • ${r.online}/${r.total} online`:'0 prontos';badge.className=`badge ${r.highlight?'ready':'neutral'}`;}if($('#startReadyCheck')){$('#startReadyCheck').textContent=r.total?`${r.ready}/${r.total} prontos • ${r.online}/${r.total} online`:'0 jogadores prontos • opcional';$('#startReadyCheck').className=`start-check ${r.highlight?'ready':'neutral'}`;}}
async function setLobbyLayout(mode){if(!room)return alert('Crie uma sala primeiro.');if(!['auto','standard','map'].includes(mode))return;await withAction('Atualizando lobby do telão…',async()=>{const{error}=await db.rpc('admin_update_room_settings',{p_room_id:room.id,p_patch:{lobby_map_mode:mode}});if(error)throw error;await refreshState(true);});}

function canEditQueue(){return !!(room&&phase()==='lobby');}
function queueAtLimit(){return !room||queueRows.length>=200;}
function statusLabel(p){return({lobby:'LOBBY',preparing:'3…2…1',question_open:'PERGUNTA ABERTA',paused:'PAUSADO',result:'RESULTADO',finished:'ENCERRADO'})[p]||String(p||'SEM SALA').toUpperCase();}
function isControllerAuthorityError(err){return /controlador ativo|modo de acompanhamento|assuma o controle/i.test(String(err?.message||err||''));}
function updateSettingsSaveIndicator(state='idle'){
  const btn=$('#saveRoomSettingsBtn'),hint=$('#settingsSaveState');if(!btn)return;
  btn.classList.toggle('is-saving',state==='saving');btn.classList.toggle('is-dirty',state==='dirty');btn.classList.toggle('is-error',state==='error');
  if(state==='saving'){btn.textContent='Salvando…';btn.disabled=true;if(hint){hint.textContent='Salvando…';hint.dataset.state='saving';}return;}
  btn.disabled=false;
  if(state==='dirty'){btn.textContent='Salvar configurações • alterações';if(hint){hint.textContent='Alterações pendentes';hint.dataset.state='dirty';}return;}
  if(state==='error'){btn.textContent='Salvar configurações • tentar novamente';if(hint){hint.textContent='Falha ao salvar';hint.dataset.state='error';}return;}
  btn.textContent='Salvar configurações';if(hint){hint.textContent='✓ Salvo';hint.dataset.state='saved';setTimeout(()=>{if(!settingsDraftDirty&&!settingsSaving&&hint.dataset.state==='saved'){hint.textContent='Sem alterações';hint.dataset.state='idle';}},1300);}
}
function scheduleSettingsAutosave(){
  clearTimeout(settingsSaveTimer);settingsSaveTimer=null;
  if(!settingsDraftDirty||settingsSaving||!room||phase()!=='lobby')return;
  settingsSaveTimer=setTimeout(async()=>{
    settingsSaveTimer=null;if(!settingsDraftDirty||settingsSaving||!room||phase()!=='lobby')return;
    try{const ok=await saveRoomSettings(false);if(ok)diag('ok','Regras salvas automaticamente');}
    catch(e){diag('error','Falha ao salvar regras automaticamente',{error:e.message||String(e)});updateSettingsSaveIndicator('error');}
  },900);
}
function markSettingsDraftDirty(){
  settingsDraftDirty=true;settingsDraftSerial++;updateSettingsSaveIndicator('dirty');renderSetupReview();scheduleSettingsAutosave();
}
function bindSettingsDraftTracking(){
  if(settingsTrackingReady)return;settingsTrackingReady=true;
  SETTINGS_DRAFT_IDS.forEach(id=>{const el=document.getElementById(id);if(!el)return;const ev=(el.type==='checkbox'||el.tagName==='SELECT'||el.type==='datetime-local')?'change':'input';el.addEventListener(ev,markSettingsDraftDirty);});
}
async function ensureControllerForRoomCreation(){
  const{data,error}=await db.rpc('admin_list_recent_rooms',{p_limit:20});if(error)throw error;
  const active=(data||[]).find(r=>r.status!=='finished'&&r.phase!=='finished');if(!active)return true;
  const same=room&&String(room.id)===String(active.id);
  if(!same){const proceed=confirm(`Existe uma sala ativa (PIN ${active.code})${active.title?` — ${active.title}`:''}. Criar uma nova sala encerrará essa partida e assumirá o controle neste dispositivo.\n\nDeseja continuar?`);if(!proceed)return false;}
  const{data:claim,error:claimError}=await db.rpc('admin_claim_controller',{p_room_id:active.id,p_device_token:controllerDeviceToken(),p_device_label:controllerDeviceLabel(),p_force:true});
  if(claimError)throw claimError;if(!claim?.granted)throw new Error('Não foi possível assumir o controle da sala ativa.');
  diag('ok','Controle da sala ativa assumido para criar nova partida',{room_code:active.code});return true;
}
async function loadPreferredRoom(){
  let savedData=null;const saved=rememberedRoomId();if(saved){const res=await db.rpc('admin_get_room_by_id',{p_room_id:saved});if(!res.error)savedData=res.data;}
  if(savedData&&savedData.status!=='finished'&&savedData.phase!=='finished')return savedData;
  const recent=await db.rpc('admin_list_recent_rooms',{p_limit:20});if(!recent.error){const active=(recent.data||[]).find(r=>r.status!=='finished'&&r.phase!=='finished');if(active){const res=await db.rpc('admin_get_room_by_id',{p_room_id:active.id});if(!res.error&&res.data)return res.data;}}
  if(savedData)return savedData;
  const latest=await db.rpc('admin_get_latest_room');return latest.error?null:latest.data;
}
async function withAction(label,fn,{skipControllerGuard=false}={}){if(actionBusy)return false;if(!backendCompatible){alert(`Backend incompatível. Aplique a migration ${String(BACKEND_SCHEMA_REQUIRED).padStart(3,'0')} antes de comandar a partida.`);return false;}if(remoteModeActive&&!await ensureRemoteRoomBinding())return false;if(room&&!remoteModeActive&&!controllerGranted&&!skipControllerGuard){alert('Este painel está em modo de acompanhamento. Assuma o controle principal antes de enviar comandos.');return false;}actionBusy=true;const busy=$$('#contextPrimaryBtn,#remotePrimaryBtn,#startQuizBtn,#prepareRoundBtn,#openRoundBtn,#closeRoundBtn');busy.forEach(b=>{b.dataset.busyText=b.textContent;b.textContent='PROCESSANDO…';});$$('[data-admin-action],[data-remote-action],[data-final-show],#startQuizBtn,#prepareRoundBtn,#openRoundBtn,#closeRoundBtn,#restartQuizBtn,#shuffleQueueBtn,#createRoomBtn,#pauseQuizBtn,#extend5Btn,#extend10Btn,#annulRoundBtn,#regradeRoundBtn').forEach(b=>b.disabled=true);if($('#adminActionStatus'))$('#adminActionStatus').textContent=label;diag('action',label);let ok=false;try{try{await fn();}catch(e){if(!remoteModeActive&&!skipControllerGuard&&isControllerAuthorityError(e)){const reclaimed=await claimController(false);if(reclaimed){diag('ok','Controle administrativo renovado automaticamente');await fn();}else throw e;}else throw e;}ok=true;diag('ok',`${label} confirmado pelo servidor`);haptic([25,25,45]);actionToast(label.replace(/…$/,'')+' ✓');}catch(e){diag('error',`${label} falhou`,{error:e.message||String(e)});haptic([90,45,90]);actionToast(e.message||'Ação não concluída','error');alert(e.message||String(e));}finally{busy.forEach(b=>{if(b.dataset.busyText){b.textContent=b.dataset.busyText;delete b.dataset.busyText;}});actionBusy=false;if($('#adminActionStatus'))$('#adminActionStatus').textContent='';updateControls();renderRemoteControl();}return ok;}

function rememberRoom(){try{if(room?.id)localStorage.setItem('quiz2AdminRoomId',String(room.id));}catch{}}
function rememberedRoomId(){try{return localStorage.getItem('quiz2AdminRoomId')||'';}catch{return'';}}
function roomRiskSummary(){const joined=Number(roomState?.participant_count||0),queued=queueRows.length;return{joined,queued,hasWork:joined>0||queued>0||Number(roomState?.used_rounds||0)>0};}

let loginBusy=false;
async function authCheck(){try{const{data:{session}}=await db.auth.getSession();if(!session)return;const{data,error}=await db.rpc('is_quiz_admin');if(error)return;if(data)await showAdmin();}catch(e){const box=$('#loginError');if(box)box.textContent='Não foi possível verificar a sessão. Atualize a página e tente novamente.';}}
async function login(){if(loginBusy)return;const box=$('#loginError'),btn=$('#loginBtn'),email=$('#email'),password=$('#password');if(!box||!btn||!email||!password)return;box.textContent='';const loginEmail=email.value.trim();if(!loginEmail||!password.value){box.textContent='Informe e-mail e senha.';(!loginEmail?email:password).focus();return;}loginBusy=true;btn.disabled=true;btn.setAttribute('aria-busy','true');const label=btn.textContent;btn.textContent='Entrando…';try{const{error}=await db.auth.signInWithPassword({email:loginEmail,password:password.value});if(error){box.textContent=error.message;password.focus();return;}const{data,error:adminError}=await db.rpc('is_quiz_admin');if(adminError){box.textContent=adminError.message||'Não foi possível validar a permissão de administrador.';return;}if(!data){box.textContent='Este usuário não está autorizado como administrador.';await db.auth.signOut();return;}await showAdmin();}catch(e){box.textContent=e?.message||'Falha de conexão durante o login.';}finally{loginBusy=false;btn.disabled=false;btn.setAttribute('aria-busy','false');btn.textContent=label;}}
async function logout(){await db.auth.signOut();location.reload();}

function remoteDeviceToken(){
  try{
    let token=localStorage.getItem(REMOTE_DEVICE_KEY)||'';
    if(token.length<20){token=crypto.randomUUID?.()||`${Date.now()}-${Math.random()}-${Math.random()}`;localStorage.setItem(REMOTE_DEVICE_KEY,token);}
    return token;
  }catch{return crypto.randomUUID?.()||`${Date.now()}-${Math.random()}-${Math.random()}`;}
}
function rememberRemoteRoom(id=room?.id){try{if(id)localStorage.setItem(REMOTE_ROOM_KEY,String(id));}catch{}}
function rememberedRemoteRoomId(){try{return localStorage.getItem(REMOTE_ROOM_KEY)||'';}catch{return'';}}
function remoteUrlParams(){return new URLSearchParams(location.search);}
function remotePairCodeFromUrl(){return (remoteUrlParams().get('remote_pair')||'').trim().toUpperCase();}
function wantsRemoteFromUrl(){return remoteUrlParams().get('remote')==='1';}
function setRemoteUrl({pair=null,remote=null}={}){const u=new URL(location.href);if(pair===null)u.searchParams.delete('remote_pair');else u.searchParams.set('remote_pair',pair);if(remote===null)u.searchParams.delete('remote');else u.searchParams.set('remote',remote?'1':'0');history.replaceState(null,'',u);}
function openRemotePairModal(view='create'){const modal=$('#remotePairModal');if(!modal)return;modal.classList.remove('hidden');$('#remotePairCreateView').classList.toggle('hidden',view!=='create');$('#remoteClaimView').classList.toggle('hidden',view!=='claim');}
function closeRemotePairModal(){$('#remotePairModal')?.classList.add('hidden');}
function defaultRemoteDeviceName(){const ua=navigator.userAgent||'';if(/iPhone/i.test(ua))return'iPhone do apresentador';if(/iPad/i.test(ua))return'iPad do apresentador';if(/Android/i.test(ua))return'Celular Android do apresentador';return'Meu celular';}
async function refreshRemoteDeviceCount(){try{const{data,error}=await db.rpc('admin_list_remote_devices');if(error)return remoteDeviceCount;remoteDeviceCount=(Array.isArray(data)?data:[]).filter(x=>x?.active).length;renderEventHealth();return remoteDeviceCount;}catch{return remoteDeviceCount;}}
async function adoptRemoteRoom(nextRoom,{refresh=true,subscribeNow=true}={}){
  if(!nextRoom?.id)return false;
  const oldId=room?.id||'',changed=String(oldId)!==String(nextRoom.id);
  if(changed){
    room={...nextRoom};roomState=null;queueRows=[];participants=[];historyRows=[];presenceOnline=null;displayOnline=false;lastAdminQr='';eventInsights=null;lastInsightsRounds=-1;lastObservedPhase='';
    rememberRemoteRoom(room.id);rememberRoom();
    if($('#plannedRounds'))$('#plannedRounds').value=room.planned_rounds||10;if($('#roomTitle'))$('#roomTitle').value=room.title||'Quiz ao vivo';if($('#roomInfo')){$('#roomInfo').textContent=`Código: ${room.code||'------'}`;$('#roomInfo').classList.add('room-protected');}$('#roomProgress')?.classList.remove('hidden');
    diag('state','Controle remoto vinculado à sala correta',{from:oldId||null,to:room.id,code:room.code||''});
    if(refresh)await Promise.all([refreshState(true),loadQueue(),loadParticipants()]);
    if(subscribeNow)await subscribe();
  }else{
    room={...room,...nextRoom};rememberRemoteRoom(room.id);if(refresh)await refreshState(true);
  }
  return changed;
}
async function checkRemoteAuthorization({adoptRoom=false,refreshRoom=false}={}){
  const token=remoteDeviceToken();
  const{data,error}=await db.rpc('admin_remote_device_status',{p_device_token:token});
  if(error){remoteAuthorized=false;remoteDeviceLabel='';updateRemoteAvailability();return false;}
  remoteAuthorized=!!data?.authorized;remoteDeviceLabel=data?.device_label||'';
  if(!remoteAuthorized){updateRemoteAvailability();if(remoteModeActive)exitRemoteMode();return false;}
  const target=data?.room||null;
  if(target&&(adoptRoom||remoteModeActive||wantsRemoteFromUrl())){
    const changed=!room||String(room.id)!==String(target.id);
    if(changed)await adoptRemoteRoom(target,{refresh:true,subscribeNow:true});
    else if(refreshRoom)await refreshState(true);
  }
  updateRemoteAvailability();return true;
}
function updateRemoteAvailability(){
  const hasRoom=!!room,activeRoom=!!(room&&phase()!=='finished');
  const btn=$('#remoteModeBtn');if(btn){btn.classList.toggle('hidden',!(remoteAuthorized&&hasRoom));btn.textContent=remoteModeActive?'Controle remoto ativo':'Controle remoto';}
  const pair=$('#pairRemoteBtn');if(pair)pair.disabled=!activeRoom||actionBusy;
  const revoke=$('#revokeRemoteBtn');if(revoke)revoke.disabled=actionBusy;
}
async function bindRemotePairCode(code,{deviceLabel='',showStatus=false}={}){
  const clean=String(code||'').trim().toUpperCase();if(!clean)return{ok:false,error:new Error('Código de pareamento ausente.')};
  const status=$('#remoteClaimStatus');if(showStatus&&status){status.textContent='Vinculando este aparelho à sala…';status.className='muted';}
  const{data,error}=await db.rpc('admin_claim_remote_pairing',{p_code:clean,p_device_token:remoteDeviceToken(),p_device_label:deviceLabel||remoteDeviceLabel||defaultRemoteDeviceName()});
  if(error){if(showStatus&&status){status.textContent=error.message;status.className='error';}return{ok:false,error};}
  remoteAuthorized=!!data?.authorized;remoteDeviceLabel=data?.device_label||deviceLabel||defaultRemoteDeviceName();
  if(data?.room)await adoptRemoteRoom(data.room,{refresh:true,subscribeNow:true});
  await refreshRemoteDeviceCount();updateRemoteAvailability();
  if(showStatus&&status){status.textContent=`Celular vinculado à sala ${data?.room?.code||room?.code||'atual'} com sucesso.`;status.className='success';}
  return{ok:true,data};
}
async function initRemoteFeature(){
  const code=remotePairCodeFromUrl(),remoteIntent=wantsRemoteFromUrl()||!!code;
  await checkRemoteAuthorization({adoptRoom:remoteIntent&&!code});
  if(code){
    $('#remoteClaimCode').textContent=code;$('#remoteDeviceName').value=remoteDeviceLabel||defaultRemoteDeviceName();
    if(remoteAuthorized){
      const rebound=await bindRemotePairCode(code,{deviceLabel:remoteDeviceLabel||defaultRemoteDeviceName(),showStatus:false});
      if(rebound.ok){setRemoteUrl({pair:null,remote:true});await enterRemoteMode({skipCheck:true});return;}
      $('#remoteClaimStatus').textContent=rebound.error?.message||'Não foi possível vincular este aparelho à sala.';$('#remoteClaimStatus').className='error';
    }else{$('#remoteClaimStatus').textContent='Entre com a mesma conta ADM usada no computador e confirme este aparelho.';$('#remoteClaimStatus').className='muted';}
    openRemotePairModal('claim');return;
  }
  if(remoteAuthorized&&wantsRemoteFromUrl()&&room)await enterRemoteMode({skipCheck:true});
}
async function createRemotePairing(){
  if(!room)return alert('Abra ou crie uma sala antes de autorizar o celular.');
  const{data,error}=await db.rpc('admin_create_remote_pairing',{p_room_id:room.id});
  if(error)return alert(error.message);
  const u=new URL('admin.html',location.href);u.search='';u.hash='';u.searchParams.set('remote_pair',data.code);u.searchParams.set('remote','1');
  remotePairLink=u.href;remotePairExpiresAt=Date.parse(data.expires_at||0);$('#remotePairCode').textContent=data.code;$('#remotePairQr').innerHTML='';
  try{window.QuizQR?.render($('#remotePairQr'),remotePairLink);}catch{$('#remotePairQr').textContent=data.code;}
  const mins=Math.max(1,Math.ceil((remotePairExpiresAt-Date.now())/60000));$('#remotePairExpires').textContent=`Válido por aproximadamente ${mins} minuto${mins===1?'':'s'} • Sala ${data.room_code}`;openRemotePairModal('create');
}
async function claimRemotePairing(){
  const code=remotePairCodeFromUrl()||$('#remoteClaimCode').textContent.trim();if(!code)return;
  $('#remoteClaimBtn').disabled=true;
  const result=await bindRemotePairCode(code,{deviceLabel:$('#remoteDeviceName').value.trim()||defaultRemoteDeviceName(),showStatus:true});
  $('#remoteClaimBtn').disabled=false;if(!result.ok)return;
  setRemoteUrl({pair:null,remote:true});setTimeout(()=>{closeRemotePairModal();enterRemoteMode({skipCheck:true});},300);
}
async function revokeRemoteDevices(){
  if(!confirm('Revogar todos os celulares autorizados como controle remoto?'))return;
  const{data,error}=await db.rpc('admin_revoke_remote_devices');if(error)return alert(error.message);
  remoteAuthorized=false;remoteDeviceLabel='';remoteDeviceCount=0;if(remoteModeActive)exitRemoteMode();updateRemoteAvailability();renderEventHealth();alert(`${Number(data)||0} dispositivo(s) revogado(s).`);
}
async function copyRemotePairLink(){if(!remotePairLink)return;try{await navigator.clipboard.writeText(remotePairLink);$('#remotePairExpires').textContent='Link copiado. O código continua válido até expirar.';}catch{prompt('Copie o link:',remotePairLink);}}
function stopRemoteRoomSync(){clearInterval(remoteRoomSyncTimer);remoteRoomSyncTimer=null;remoteRoomSyncInFlight=false;}
function startRemoteRoomSync(){stopRemoteRoomSync();remoteRoomSyncTimer=setInterval(async()=>{if(!remoteModeActive||document.hidden||remoteRoomSyncInFlight)return;remoteRoomSyncInFlight=true;try{await checkRemoteAuthorization({adoptRoom:true});}finally{remoteRoomSyncInFlight=false;}},5000);}
async function ensureRemoteRoomBinding(){
  if(!remoteModeActive)return true;
  const ok=await checkRemoteAuthorization({adoptRoom:true});
  if(!ok||!room){actionToast('Controle remoto sem vínculo com uma sala','error');return false;}
  if(!roomState||String(roomState?.room?.id||'')!==String(room.id))await refreshState(true);
  return true;
}
async function syncRemoteNow(){if(!await ensureRemoteRoomBinding())return;await Promise.all([refreshState(true),loadQueue(),loadParticipants()]);}
async function enterRemoteMode({skipCheck=false}={}){
  if(!skipCheck&&!await checkRemoteAuthorization({adoptRoom:true}))return alert('Este aparelho ainda não foi autorizado como controle remoto.');
  if(!remoteAuthorized)return alert('Este aparelho ainda não foi autorizado como controle remoto.');if(!room)return alert('Nenhuma sala ativa encontrada.');
  remoteModeActive=true;document.body.classList.add('remote-control-active');$('#remoteControlView').classList.remove('hidden');setRemoteUrl({pair:null,remote:true});rememberRemoteRoom(room.id);startRemoteRoomSync();renderRemoteControl();renderRemoteTimer();
}
function exitRemoteMode(){stopRemoteRoomSync();remoteModeActive=false;document.body.classList.remove('remote-control-active');$('#remoteControlView').classList.add('hidden');setRemoteUrl({pair:null,remote:null});updateRemoteAvailability();}
function finalShowStage(){const raw=String(roomSettings().final_show_stage||'ranking');return ['ranking','stats','highlights','champion'].includes(raw)?raw:'ranking';}
function quizPresentationComplete(){const used=Number(roomState?.used_rounds||0),target=Number(roomState?.room?.planned_rounds||0),queued=Number(roomState?.queued_count||0);return used>0&&(used>=target||queued===0)&&!roomState?.prepared;}
function nextFinalShowStage(stage=finalShowStage()){return({ranking:'stats',stats:'highlights',highlights:'champion',champion:'ranking'})[stage]||'ranking';}
function finalShowLabel(stage=finalShowStage()){return({ranking:'Ranking final',stats:'Estatísticas da partida',highlights:'Destaques do evento',champion:'Campeão e pódio'})[stage]||'Ranking final';}
async function setFinalShowStage(stage){if(!room||phase()!=='finished')return;const label=finalShowLabel(stage);await withAction(`Mostrando ${label.toLowerCase()}…`,async()=>{const{error}=await db.rpc('admin_set_final_show_stage',{p_room_id:room.id,p_stage:stage});if(error)throw error;await Promise.all([refreshState(true),loadEventInsights()]);remoteVibrate(stage==='champion'?[90,35,130]:[35,25,55]);});}
function renderFinalShowControls(){const stage=finalShowStage();$$('[data-final-show]').forEach(b=>{b.classList.toggle('active',b.dataset.finalShow===stage);b.disabled=actionBusy||phase()!=='finished';});if($('#finalShowStageLabel'))$('#finalShowStageLabel').textContent=finalShowLabel(stage);}
async function remotePrimaryAction(){if(!await ensureRemoteRoomBinding())return;const p=phase(),stage=roomState?.room?.reveal_stage||'hidden',used=Number(roomState?.used_rounds||0),target=Number(roomState?.room?.planned_rounds||0);if(p==='lobby')return startQuiz();if(p==='preparing')return openPreparedRound();if(p==='question_open')return closeRound();if(p==='paused')return pauseQuiz();if(p==='result'&&stage==='hidden')return reveal('answer');if(p==='result'&&stage==='answer')return reveal('distribution');if(p==='result'&&stage==='distribution')return reveal('ranking');if(p==='result'&&stage==='ranking')return quizPresentationComplete()?reveal('final'):maybeScheduledBreakOrPrepare();if(p==='finished')return setFinalShowStage(nextFinalShowStage());}
function renderRemoteTimer(){
  const el=$('#remoteTimer');if(!el||!remoteModeActive)return;const p=phase(),r=roomState?.round;let text='—',danger=false;
  if(p==='lobby')text='LOBBY';else if(p==='paused')text='II';else if(p==='finished')text='FIM';else if(p==='preparing'){const remain=Math.max(0,serverRemaining(roomState?.room?.prepared_until,serverOffset));text=String(Math.max(1,Math.ceil(remain/1000)));danger=remain<=3000;}else if(r?.status==='open'){const remain=serverRemaining(r.closes_at,serverOffset);text=remain<=0?'0':`${Math.ceil(remain/1000)}s`;danger=remain<=5000;}else if(r?.round_no)text=`R${r.round_no}`;
  el.textContent=text;el.classList.toggle('danger',danger);
}
function renderRemoteControl(){
  updateRemoteAvailability();if(!remoteModeActive)return;const rp=phase();if(lastRemotePhase&&lastRemotePhase!==rp)remoteVibrate(rp==='question_open'?[45,35,45]:rp==='result'?[70]:35);lastRemotePhase=rp;const rfs=rp==='finished'?finalShowStage():'';if(rfs&&lastRemoteFinalStage&&lastRemoteFinalStage!==rfs)remoteVibrate(rfs==='champion'?[80,45,120]:[35,25,35]);lastRemoteFinalStage=rfs;
  const p=phase(),r=roomState?.round,total=Number(roomState?.participant_count||0),answers=Number(roomState?.answer_count||0),eligible=Number(roomState?.eligible_count||0),eligibleAnswers=Number(roomState?.eligible_answer_count??answers),answerDenom=p==='question_open'&&eligible>0?eligible:total,answerForRate=p==='question_open'&&eligible>0?eligibleAnswers:answers,rate=p==='question_open'&&answerDenom?Math.min(100,Math.round(answerForRate*100/answerDenom)):0,target=Number(roomState?.room?.planned_rounds||room?.planned_rounds||0),used=Number(roomState?.used_rounds||0),queued=Number(roomState?.queued_count||0);
  $('#remoteRoomTitle').textContent=roomState?.room?.title||room?.title||'Quiz ao vivo';$('#remoteRoomCode').textContent=`Sala ${roomState?.room?.code||room?.code||'------'}`;$('#remotePhaseBadge').textContent=statusLabel(p);$('#remoteRoundLabel').textContent=r?.round_no?`Round ${r.round_no} de ${target}`:`${used} de ${target} rounds`;
  $('#remoteQuestion').textContent=p==='finished'?`Quiz finalizado. Tela atual: ${finalShowLabel()}. Use os botões abaixo para alternar ranking, estatísticas, destaques e campeão.`:p==='lobby'?'Lobby aberto. Os jogadores já podem entrar.':p==='paused'?'Partida pausada.':r?.prompt||roomState?.prepared?.prompt||'Aguardando a próxima pergunta.';
  $('#remoteParticipantCount').textContent=total;$('#remoteAnswerCount').textContent=answers;$('#remoteAnswerTotal').textContent=answerDenom;$('#remoteResponseRate').textContent=`${rate}%`;$('#remoteResponseBar').style.width=`${rate}%`;$('#remoteDeviceLabel').textContent=remoteDeviceLabel||'Celular autorizado';
  const net=$('#remoteConnectionStatus');net.classList.toggle('online',navigator.onLine&&lastLatency<1500);net.classList.toggle('offline',!navigator.onLine);net.querySelector('strong').textContent=!navigator.onLine?'Sem internet':lastLatency<500?`Online • ${lastLatency} ms`:lastLatency<1500?`Online • ${lastLatency} ms`:`Instável • ${lastLatency} ms`;
  const ds=$('#remoteDisplayStatus');ds.classList.toggle('online',displayOnline);ds.classList.toggle('offline',!displayOnline);ds.querySelector('strong').textContent=displayOnline?'Telão conectado':'Telão não detectado';
  const primary=$('#remotePrimaryBtn');const revealStage=roomState?.room?.reveal_stage||'hidden';let label='Aguardando',enabled=false;if(p==='lobby'){label=queued>0?'Começar Quiz':'Adicione perguntas';enabled=queued>0;}else if(p==='preparing'){const remain=Math.max(0,serverRemaining(roomState?.room?.prepared_until,serverOffset));label=remain>0?`Liberar em ${Math.max(1,Math.ceil(remain/1000))} s`:'Liberar pergunta';enabled=remain<=0;}else if(p==='question_open'){label='Encerrar e pontuar';enabled=!!r?.status;}else if(p==='result'&&revealStage==='hidden'){label='Mostrar resposta';enabled=true;}else if(p==='result'&&revealStage==='answer'){label='Mostrar distribuição';enabled=true;}else if(p==='result'&&revealStage==='distribution'){label='Mostrar ranking';enabled=true;}else if(p==='result'&&revealStage==='ranking'){const complete=quizPresentationComplete();label=complete?'Mostrar resultado final':queued>0?'Próximo round':'Sincronizar final';enabled=complete||queued>0;}else if(p==='paused'){label=roomState?.room?.paused_phase==='question_open'?'Retomar pergunta':'Retomar partida';enabled=true;}else if(p==='finished'){const next=nextFinalShowStage();label=next==='stats'?'Mostrar estatísticas':next==='highlights'?'Mostrar destaques':next==='champion'?'Mostrar campeão':'Voltar ao ranking';enabled=true;}
  primary.textContent=label;primary.disabled=actionBusy||!enabled;
  const pause=$('#remotePauseBtn');pause.textContent=p==='paused'?(roomState?.room?.paused_phase==='question_open'?'Retomar pergunta':'Retomar partida'):p==='question_open'?'Congelar pergunta':'Pausar partida';pause.disabled=actionBusy||['lobby','finished'].includes(p);
  const canExtend=!actionBusy&&p==='question_open'&&!!r?.accepting_responses;$('#remoteExtend5Btn').disabled=!canExtend;$('#remoteExtend10Btn').disabled=!canExtend;
  const canReveal=!actionBusy&&p==='result';$('#remoteRevealCard')?.classList.toggle('hidden',p==='finished');$('#remoteRevealAnswerBtn').disabled=!canReveal;$('#remoteRevealDistributionBtn').disabled=!canReveal;$('#remoteRevealRankingBtn').disabled=!canReveal;
  const finalCard=$('#remoteFinalShowCard');finalCard?.classList.toggle('hidden',p!=='finished');if(p==='finished'){const fs=finalShowStage();if($('#remoteFinalStageLabel'))$('#remoteFinalStageLabel').textContent=finalShowLabel(fs);$$('[data-remote-final-show]').forEach(b=>{b.classList.toggle('active',b.dataset.remoteFinalShow===fs);b.disabled=actionBusy;});}
  $('#remoteAnnulBtn').disabled=actionBusy||!(['result','finished'].includes(p)&&r?.status==='closed'&&!r?.annulled);$('#remoteRestartBtn').disabled=actionBusy||used===0;
  renderRemoteTimer();
}
function bindHoldAction(el,fn){let timer=null;const cancel=()=>{clearTimeout(timer);timer=null;el?.classList.remove('is-holding');};el?.addEventListener('pointerdown',e=>{if(el.disabled)return;e.preventDefault();cancel();el.classList.add('is-holding');timer=setTimeout(()=>{cancel();fn();},1000);});['pointerup','pointercancel','pointerleave'].forEach(ev=>el?.addEventListener(ev,cancel));}
async function showAdmin(){$('#loginView').classList.add('hidden');$('#adminView').classList.remove('hidden');$('#logoutBtn').classList.remove('hidden');loadAdminMotionAfterAuth();$('#eventModeBtn')?.classList.remove('hidden');if($('#remoteHapticStatus'))$('#remoteHapticStatus').textContent=navigator.vibrate?'Vibração ativa':'Vibração não disponível';initAdminTabs();initQuestionSubtabs();initConfigSubtabs();initRulesMode();bindSettingsDraftTracking();initEventMode();startTimerLoop();await checkBackendCompatibility({announce:true});await Promise.all([loadQuestions(),loadTemplates(),loadQuestionCollections(),loadRecentRooms()]);const remoteIntent=wantsRemoteFromUrl()||!!remotePairCodeFromUrl();if(!remoteIntent)await resumeLatestRoom();if(room&&!remoteIntent)await claimController(false);await initRemoteFeature();await refreshRemoteDeviceCount();renderEventHealth();}
async function resumeLatestRoom(){const data=await loadPreferredRoom();if(!data){conn(navigator.onLine?'idle':'offline');updateControls();return;}room=data;rememberRoom();settingsDraftDirty=false;settingsDraftSerial=0;updateSettingsSaveIndicator('idle');$('#plannedRounds').value=room.planned_rounds||10;$('#randomizeQueueToggle').checked=!!room.randomize_queue;$('#roomTitle').value=room.title||'Quiz ao vivo';$('#roomInfo').textContent=`Código: ${room.code}`;$('#roomInfo').classList.add('room-protected');$('#roomProgress').classList.remove('hidden');await Promise.all([refreshState(true),loadQueue(),loadAudit(),loadParticipants(),loadHistory()]);await subscribe();}

async function createRoom(){
  if(room){const risk=roomRiskSummary();if(risk.hasWork){const carried=risk.queued>0?` As ${risk.queued} pergunta(s) selecionada(s) serão copiadas para a nova sala.`:'';const msg=`A sala atual ${room.code} será encerrada ao criar a nova sala.${carried} Jogadores permanecem vinculados à sala anterior e podem entrar novamente pelo novo PIN.\n\nDeseja continuar?`;if(!confirm(msg))return;}}
  let authorityReady=false;try{authorityReady=await ensureControllerForRoomCreation();}catch(e){diag('error','Falha ao preparar controlador para nova sala',{error:e.message||String(e)});alert(e.message||String(e));return;}if(!authorityReady)return;
  await withAction('Criando sala…',async()=>{const{data,error}=await db.rpc('admin_create_room_v4',{p_title:$('#roomTitle').value.trim()||'Quiz ao vivo',p_planned_rounds:plannedRounds()});if(error)throw error;const carried=Number(data?.carried_queue_count||0);room=data;rememberRoom();roomState=null;queueRows=[];presenceOnline=null;displayOnline=false;lastAdminQr='';eventInsights=null;lastInsightsRounds=-1;settingsDraftDirty=true;settingsDraftSerial++;$('#eventInsightsCard')?.classList.add('hidden');$('#plannedRounds').value=room.planned_rounds||plannedRounds();$('#roomInfo').textContent=`Código: ${room.code}`;$('#roomInfo').classList.add('room-protected');$('#roomProgress').classList.remove('hidden');await claimController(true);await Promise.all([refreshState(true),loadQueue(),loadAudit(),loadParticipants()]);await saveRoomSettings(false);await subscribe();if(carried>0&&$('#queueWarning')){$('#queueWarning').textContent=`${carried} pergunta(s) mantida(s) da sala anterior. A nova partida está pronta para usar essa seleção.`;$('#queueWarning').className='queue-warning ready';}}, {skipControllerGuard:true});
}
async function updatePlannedRounds(){if(!room||phase()!=='lobby')return;await withAction('Salvando quantidade…',async()=>{const prev=Number(roomState?.room?.planned_rounds||room.planned_rounds||10);const{data,error}=await db.rpc('admin_update_planned_rounds',{p_room_id:room.id,p_planned_rounds:plannedRounds()});if(error){$('#plannedRounds').value=prev;throw error;}room.planned_rounds=data;await Promise.all([refreshState(true),loadQueue()]);});}
async function updateRandomizeQueue(){if(!room||phase()!=='lobby')return;const enabled=$('#randomizeQueueToggle').checked;await withAction('Salvando ordem aleatória…',async()=>{const{data,error}=await db.rpc('admin_set_randomize_queue',{p_room_id:room.id,p_enabled:enabled});if(error){$('#randomizeQueueToggle').checked=!enabled;throw error;}room.randomize_queue=!!data;await refreshState(true);});}
async function shuffleQueue(){if(!room||phase()!=='lobby')return;await withAction('Embaralhando…',async()=>{const{error}=await db.rpc('admin_shuffle_queue',{p_room_id:room.id});if(error)throw error;await Promise.all([loadQueue(),refreshState(true),loadAudit()]);});}

function collectQuestionPayload(){
  const type=$('#qType').value,prompt=$('#qPrompt').value.trim();
  let opts=null,cc=null,cn=null;
  if(!prompt)throw new Error('Digite a pergunta.');
  if(type==='choice'){
    opts=CHOICE_KEYS.map(k=>({key:k,text:$(`#opt${k}`).value.trim()})).filter(o=>o.key!=='E'||o.text);
    if(REQUIRED_CHOICE_KEYS.some(k=>!$(`#opt${k}`).value.trim()))throw new Error('Preencha as alternativas A, B, C e D. A alternativa E é opcional.');
    cc=$('#correctChoice').value;
    if(!opts.some(o=>o.key===cc))throw new Error('A alternativa correta precisa estar preenchida.');
  }else{
    cn=Number($('#correctNumber').value);
    if(!Number.isFinite(cn))throw new Error('Informe o valor correto.');
  }
  return{type,prompt,opts,cc,cn,points:Number($('#points').value)||10,time:Number($('#timeLimit').value)||30,category:$('#qCategory').value.trim()||'Geral',difficulty:$('#qDifficulty').value,scoreEnabled:$('#qScoreEnabled').checked,speedBonus:Number($('#qSpeedBonus').value)||0,tiebreaker:$('#qTiebreaker').checked,presenterNotes:$('#qPresenterNotes').value.trim()};
}
function resetQuestionEditor(clearMessage=true){
  editingQuestionId=null;
  $('#qPrompt').value='';$('#qType').value='choice';CHOICE_KEYS.forEach(k=>$(`#opt${k}`).value='');$('#correctChoice').value='A';$('#correctNumber').value='';
  $('#points').value=Math.max(1,Number(roomSettings().default_points||$('#defaultPoints')?.value||100));$('#timeLimit').value=Math.max(5,Number(roomSettings().default_time||$('#defaultTime')?.value||30));$('#qCategory').value='Geral';$('#qDifficulty').value='medio';$('#qSpeedBonus').value=0;$('#qTiebreaker').checked=false;$('#qScoreEnabled').checked=true;$('#qPresenterNotes').value='';
  $('#choiceFields').classList.remove('hidden');$('#numericFields').classList.add('hidden');
  $('#editorTitle').textContent='Nova pergunta';$('#editorModeBadge').textContent='CRIANDO';$('#editorModeBadge').classList.remove('editing');$('#cancelQuestionEditBtn').classList.add('hidden');$('#saveQuestionBtn').textContent='Salvar pergunta';
  if(clearMessage)$('#questionMsg').textContent='';
  updateQuestionPreview();
}
function startQuestionEdit(id){
  setQuestionPane('edit');
  const q=questionBank.find(x=>String(x.id)===String(id));if(!q)return;
  editingQuestionId=q.id;
  $('#qPrompt').value=q.prompt||'';$('#qType').value=q.question_type||'choice';$('#points').value=q.points||10;$('#timeLimit').value=q.time_limit_seconds||30;$('#qCategory').value=q.category||'Geral';$('#qDifficulty').value=q.difficulty||'medio';$('#qSpeedBonus').value=Number(q.speed_bonus_pct||0);$('#qTiebreaker').checked=!!q.is_tiebreaker;$('#qScoreEnabled').checked=q.score_enabled!==false;$('#qPresenterNotes').value=q.presenter_notes||'';
  if(q.question_type==='choice'){
    const byKey=Object.fromEntries((Array.isArray(q.options)?q.options:[]).map(o=>[String(o.key||'').toUpperCase(),o.text||'']));CHOICE_KEYS.forEach(k=>$(`#opt${k}`).value=byKey[k]||'');$('#correctChoice').value=q.correct_choice||'A';$('#choiceFields').classList.remove('hidden');$('#numericFields').classList.add('hidden');
  }else{$('#correctNumber').value=q.correct_number??'';$('#choiceFields').classList.add('hidden');$('#numericFields').classList.remove('hidden');}
  $('#editorTitle').textContent='Editar pergunta';$('#editorModeBadge').textContent='EDITANDO';$('#editorModeBadge').classList.add('editing');$('#cancelQuestionEditBtn').classList.remove('hidden');$('#saveQuestionBtn').textContent='Salvar alterações';$('#questionMsg').textContent='Edição carregada. Filas de rounds já preparadas mantêm o snapshot anterior.';
  updateQuestionPreview();document.querySelector('.question-editor-scroll')?.scrollTo({top:0,behavior:'smooth'});
}
async function saveQuestion(){
  let payload;try{payload=collectQuestionPayload();}catch(e){alert(e.message);return;}
  $('#saveQuestionBtn').disabled=true;$('#editorSavedState').textContent=editingQuestionId?'Salvando alterações…':'Salvando pergunta…';
  try{
    if(editingQuestionId){
      const{error}=await db.rpc('admin_update_question_v3',{p_question_id:editingQuestionId,p_prompt:payload.prompt,p_type:payload.type,p_options:payload.opts,p_correct_choice:payload.cc,p_correct_number:Number.isFinite(payload.cn)?payload.cn:null,p_points:payload.points,p_time_limit:payload.time,p_category:payload.category,p_difficulty:payload.difficulty,p_score_enabled:payload.scoreEnabled,p_speed_bonus_pct:payload.speedBonus,p_is_tiebreaker:payload.tiebreaker,p_presenter_notes:payload.presenterNotes});
      if(error)throw error;$('#questionMsg').textContent='Alterações salvas no banco.';
    }else{
      const{data:id,error}=await db.rpc('admin_create_question_v2',{p_prompt:payload.prompt,p_type:payload.type,p_options:payload.opts,p_correct_choice:payload.cc,p_correct_number:Number.isFinite(payload.cn)?payload.cn:null,p_points:payload.points,p_time_limit:payload.time});if(error)throw error;
      const meta=await db.rpc('admin_update_question_metadata',{p_question_id:id,p_category:payload.category,p_difficulty:payload.difficulty,p_score_enabled:payload.scoreEnabled,p_speed_bonus_pct:payload.speedBonus,p_is_tiebreaker:payload.tiebreaker,p_presenter_notes:payload.presenterNotes});if(meta.error)throw new Error(`Pergunta criada, mas metadados falharam: ${meta.error.message}`);$('#questionMsg').textContent='Pergunta salva no banco.';
    }
    $('#editorSavedState').textContent='Banco sincronizado no Supabase';
    await loadQuestions();resetQuestionEditor(false);
  }catch(e){$('#questionMsg').textContent=e.message||String(e);$('#editorSavedState').textContent='Falha ao salvar';}
  finally{$('#saveQuestionBtn').disabled=false;}
}
function difficultyLabel(value){return({facil:'Fácil',medio:'Médio',dificil:'Difícil',final:'Final'})[value]||'Médio';}
function updateQuestionPreview(){
  const type=$('#qType')?.value||'choice',prompt=$('#qPrompt')?.value.trim()||'Sua pergunta aparecerá aqui.',points=Math.max(1,Number($('#points')?.value)||10),time=Math.max(5,Number($('#timeLimit')?.value)||30),category=$('#qCategory')?.value.trim()||'Geral',difficulty=$('#qDifficulty')?.value||'medio';
  if($('#qPromptCount'))$('#qPromptCount').textContent=String($('#qPrompt')?.value.length||0);if($('#qPresenterNotesCount'))$('#qPresenterNotesCount').textContent=String($('#qPresenterNotes')?.value.length||0);
  $('#previewQuestionType').textContent=type==='choice'?'MÚLTIPLA ESCOLHA':'NÚMERO / MAIS PRÓXIMO';$('#previewMeta').textContent=`${points} pts • ${time}s`;$('#previewQuestionText').textContent=prompt;$('#previewCategory').textContent=category;$('#previewDifficulty').textContent=difficultyLabel(difficulty);
  if(type==='choice'){
    $('#previewAnswers').className='preview-answer-grid';$('#previewAnswers').innerHTML=CHOICE_KEYS.map(k=>`<div class="preview-answer preview-${k.toLowerCase()}"><span>${k}</span><b>${esc($(`#opt${k}`)?.value.trim()||`Alternativa ${k}${k==='E'?' (opcional)':''}`)}</b></div>`).join('');
  }else{$('#previewAnswers').className='preview-answer-grid numeric-preview';$('#previewAnswers').innerHTML='<div class="preview-numeric">Digite um número no celular. O mais próximo vence.</div>';}
  const len=($('#qPrompt')?.value||'').trim().length,filled=type==='choice'?REQUIRED_CHOICE_KEYS.filter(k=>$(`#opt${k}`)?.value.trim()).length:Number.isFinite(Number($('#correctNumber')?.value))?1:0;
  $('#creatorTip').textContent=!len?'Comece pelo enunciado. Uma frase curta costuma funcionar melhor no telão.':len>180?'O enunciado está longo. Considere reduzir para facilitar a leitura durante o cronômetro.':type==='choice'&&filled<4?'Complete A, B, C e D. A alternativa E é opcional.':'Boa estrutura. Revise o gabarito, a pontuação e o tempo antes de salvar.';
}

function normalizeFieldName(value){
  return String(value||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toUpperCase().trim();
}
function compactValue(value){return String(value??'').replace(/\s+/g,' ').trim();}
function splitTxtBlocks(text){
  const lines=String(text||'').replace(/^\uFEFF/,'').replace(/\r\n?/g,'\n').split('\n');
  const blocks=[];let current=[];
  const meaningful=arr=>arr.some(x=>{const t=x.trim();return t&&!/^#/.test(t);});
  const flush=()=>{if(meaningful(current))blocks.push(current);current=[];};
  for(const line of lines){
    if(/^\s*-{3,}\s*$/.test(line)){flush();continue;}
    if(/^\s*(PERGUNTA|QUEST[AÃ]O|QUESTION)\s*:/i.test(line)&&meaningful(current))flush();
    current.push(line);
  }
  flush();return blocks;
}
function parseTxtBlock(lines,index){
  const fields={},options={};let freePrompt='';
  for(const raw of lines){
    const line=raw.trim();if(!line||/^#/.test(line))continue;
    const opt=line.match(/^([ABCDE])\s*[\)\].:\-]\s*(.+)$/i);
    if(opt){options[opt[1].toUpperCase()]=compactValue(opt[2]);continue;}
    const field=line.match(/^([^:]{2,40})\s*:\s*(.*)$/);
    if(field){fields[normalizeFieldName(field[1])]=compactValue(field[2]);continue;}
    freePrompt+=(freePrompt?' ':'')+compactValue(line);
  }
  const prompt=fields.PERGUNTA||fields.QUESTAO||fields.QUESTION||freePrompt;
  const rawType=normalizeFieldName(fields.TIPO||'');
  const answer=fields.CORRETA||fields.RESPOSTA||fields.GABARITO||'';
  const hasRequired=REQUIRED_CHOICE_KEYS.every(k=>options[k]);
  const optionKeys=options.E?[...REQUIRED_CHOICE_KEYS,'E']:[...REQUIRED_CHOICE_KEYS];
  const type=rawType.includes('NUM')?'numeric':rawType.includes('ESCOL')||rawType.includes('MULTIP')?'choice':hasRequired?'choice':'numeric';
  const points=Number(String(fields.PONTOS||fields.PONTUACAO||'10').replace(',','.'));
  const time=Number(String(fields.TEMPO||fields.SEGUNDOS||'30').replace(',','.'));
  const errors=[];let payload=null;
  if(!prompt)errors.push('Pergunta ausente');
  if(!Number.isInteger(points)||points<1||points>100000)errors.push('Pontos inválidos');
  if(!Number.isInteger(time)||time<5||time>600)errors.push('Tempo inválido');
  if(type==='choice'){
    const correct=String(answer).toUpperCase();
    if(!hasRequired)errors.push('Alternativas A–D incompletas');
    if(!optionKeys.includes(correct))errors.push('Gabarito inválido');
    if(new Set(optionKeys.map(k=>(options[k]||'').toLocaleLowerCase('pt-BR'))).size!==optionKeys.length)errors.push('Alternativas repetidas');
    if(!errors.length)payload={prompt,question_type:'choice',options:optionKeys.map(k=>({key:k,text:options[k]})),correct_choice:correct,correct_number:null,points,time_limit_seconds:time};
  }else{
    const numeric=Number(String(answer).replace(',','.'));
    if(!Number.isFinite(numeric))errors.push('Resposta numérica inválida');
    if(!errors.length)payload={prompt,question_type:'numeric',options:null,correct_choice:null,correct_number:numeric,points,time_limit_seconds:time};
  }
  if(payload){
    const yn=v=>['SIM','S','YES','TRUE','1'].includes(normalizeFieldName(v));
    payload.category=fields.CATEGORIA||'Geral';
    payload.difficulty=({'FACIL':'facil','FÁCIL':'facil','MEDIO':'medio','MÉDIO':'medio','DIFICIL':'dificil','DIFÍCIL':'dificil','FINAL':'final'})[normalizeFieldName(fields.DIFICULDADE||'MEDIO')]||'medio';
    payload.score_enabled=fields.PONTUAR===undefined?true:yn(fields.PONTUAR);
    payload.speed_bonus_pct=Math.max(0,Math.min(100,Number(fields.BONUS_VELOCIDADE||fields.BONUS||0)||0));
    payload.is_tiebreaker=yn(fields.DESEMPATE||'NAO');
    payload.presenter_notes=fields.NOTA||fields.NOTAS||fields.APRESENTADOR||'';
    payload.archived=yn(fields.ARQUIVADA||'NAO');
  }
  return{index:index+1,payload,errors,preview:prompt||'(sem pergunta)'};
}
function currentImportMode(){return document.querySelector('input[name="importMode"]:checked')?.value==='replace'?'replace':'append';}
function syncImportModeUi(){
  const mode=currentImportMode();
  document.querySelectorAll('.import-mode-option').forEach(label=>label.classList.toggle('selected',label.querySelector('input')?.checked));
  $('#replaceImportWarning')?.classList.toggle('hidden',mode!=='replace');
  const button=$('#importQuestionsBtn');
  if(button){button.textContent=mode==='replace'?'Substituir banco pelo lote':'Adicionar lote validado';button.classList.toggle('replace-armed',mode==='replace');}
  renderImportPreview();
}
function analyzeBulkText(){
  const text=$('#bulkQuestionText').value;
  if(!text.trim()){parsedImport={questions:[],errors:[],results:[]};renderImportPreview();return;}
  const blocks=splitTxtBlocks(text).slice(0,MAX_IMPORT+1);
  const results=blocks.map(parseTxtBlock);
  parsedImport={
    questions:results.filter(x=>x.payload).slice(0,MAX_IMPORT).map(x=>x.payload),
    errors:[...results.flatMap(x=>x.errors.map(e=>`Pergunta ${x.index}: ${e}`)),...(blocks.length>MAX_IMPORT?[`Limite: ${MAX_IMPORT}`]:[])],
    results:results.slice(0,MAX_IMPORT)
  };
  renderImportPreview();
}
function renderImportPreview(){
  const total=parsedImport.results?.length||0,valid=parsedImport.questions.length,errors=parsedImport.errors.length,mode=currentImportMode();
  const modeText=mode==='replace'?'SUBSTITUIR BANCO':'ADICIONAR';
  $('#importSummary').textContent=total?`${modeText} • ${total} bloco(s) • ${valid} válido(s) • ${errors} erro(s)`:'Cole um texto ou selecione um TXT. Nada será gravado antes da validação.';
  $('#importSummary').className=`import-summary ${errors?'error':valid?'success':'muted'}`;
  const button=$('#importQuestionsBtn');
  button.disabled=total===0;
  button.textContent=errors?`Revisar ${errors} erro${errors===1?'':'s'}`:(mode==='replace'?'Substituir banco pelo lote':'Adicionar lote validado');
  button.classList.toggle('replace-armed',mode==='replace'&&!button.disabled&&!errors);
  button.classList.toggle('import-has-errors',errors>0);
  $('#importPreview').innerHTML=(parsedImport.results||[]).slice(0,40).map(r=>`<div class="import-preview-row ${r.errors.length?'invalid':'valid'}"><b>${r.index}</b><span>${esc(r.preview)}</span><em>${r.errors.length?esc(r.errors.join(' • ')):'Pronta para importar'}</em></div>`).join('');
}
function txtForQuestion(q){
  const lines=[`PERGUNTA: ${compactValue(q.prompt)}`,`TIPO: ${q.question_type==='choice'?'ESCOLHA':'NUMERO'}`];
  if(q.question_type==='choice'){
    for(const k of CHOICE_KEYS){const text=compactValue((q.options||[]).find(o=>o.key===k)?.text||'');if(k!=='E'||text)lines.push(`${k}: ${text}`);}
    lines.push(`CORRETA: ${q.correct_choice}`);
  }else lines.push(`CORRETA: ${q.correct_number}`);
  lines.push(`PONTOS: ${q.points}`,`TEMPO: ${q.time_limit_seconds}`,`CATEGORIA: ${compactValue(q.category||'Geral')}`,`DIFICULDADE: ${(q.difficulty||'medio').toUpperCase()}`,`PONTUAR: ${q.score_enabled===false?'NAO':'SIM'}`,`BONUS_VELOCIDADE: ${Number(q.speed_bonus_pct||0)}`,`DESEMPATE: ${q.is_tiebreaker?'SIM':'NAO'}`,`ARQUIVADA: ${q.archived?'SIM':'NAO'}`);
  if(q.presenter_notes)lines.push(`NOTA: ${compactValue(q.presenter_notes)}`);
  lines.push('---');return lines.join('\n');
}
function downloadText(filename,text){
  const blob=new Blob([text],{type:'text/plain;charset=utf-8'}),url=URL.createObjectURL(blob),a=document.createElement('a');
  a.href=url;a.download=filename;document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);
}
function downloadTemplate(){
  downloadText('QuizRounds_modelo_v3.68.txt',['# QuizRounds v3.68 — o mesmo formato serve para importar e exportar.','PERGUNTA: Qual é a capital do Brasil?','TIPO: ESCOLHA','A: São Paulo','B: Brasília','C: Salvador','D: Recife','E: Manaus','CORRETA: B','PONTOS: 100','TEMPO: 30','CATEGORIA: Geografia','DIFICULDADE: FACIL','PONTUAR: SIM','BONUS_VELOCIDADE: 20','DESEMPATE: NAO','ARQUIVADA: NAO','NOTA: Comentário opcional do apresentador','---','PERGUNTA: Quantos minutos existem em 2 horas?','TIPO: NUMERO','CORRETA: 120','PONTOS: 50','TEMPO: 20','CATEGORIA: Matemática','DIFICULDADE: FACIL','PONTUAR: SIM','---'].join('\n'));
}
async function getExportableQuestionBank(){
  const{data,error}=await db.rpc('admin_list_question_bank',{p_scope:'all'});
  if(error)throw error;
  return data||[];
}
async function exportQuestionBank(filename){
  const rows=await getExportableQuestionBank();
  const header=['# QuizRounds v3.68 — banco completo de perguntas.','# Inclui respostas corretas, pontuação, tempo e metadados.','# Este arquivo pode ser importado novamente em modo ADICIONAR ou SUBSTITUIR.',''].join('\n');
  downloadText(filename,header+rows.map(txtForQuestion).join('\n'));
  return rows.length;
}
async function exportQuestions(){
  try{const count=await exportQuestionBank(`QuizRounds_banco_perguntas_${new Date().toISOString().slice(0,10)}.txt`);$('#importSummary').textContent=`Backup/exportação concluída: ${count} pergunta(s).`;}catch(e){alert(e.message||String(e));}
}
async function importBulkQuestions(){
  analyzeBulkText();
  const button=$('#importQuestionsBtn');
  if(parsedImport.errors.length){
    const first=parsedImport.errors.slice(0,3).join(' • ');
    $('#importSummary').textContent=`Importação não iniciada: ${parsedImport.errors.length} erro(s). ${first}`;
    $('#importSummary').className='import-summary error';
    $('#importPreview').querySelector('.invalid')?.scrollIntoView({behavior:'smooth',block:'nearest'});
    button.textContent=`Revisar ${parsedImport.errors.length} erro${parsedImport.errors.length===1?'':'s'}`;
    return;
  }
  if(!parsedImport.questions.length){
    $('#importSummary').textContent='Nenhuma pergunta válida encontrada para importar.';
    $('#importSummary').className='import-summary error';
    return;
  }
  const mode=currentImportMode();
  if(mode==='replace'){
    const typed=prompt(`ATENÇÃO: o banco atual será substituído por ${parsedImport.questions.length} pergunta(s).\n\nDigite SUBSTITUIR para confirmar.`,'');
    if(typed!=='SUBSTITUIR'){ $('#importSummary').textContent='Substituição cancelada. Nenhuma alteração foi feita.'; return; }
    if($('#backupBeforeReplace')?.checked){
      try{await exportQuestionBank(`QuizRounds_backup_antes_substituir_${new Date().toISOString().replace(/[:.]/g,'-')}.txt`);}catch(e){alert(`Não foi possível gerar o backup: ${e.message||e}`);return;}
    }
  }
  button.disabled=true;button.textContent=mode==='replace'?'Substituindo…':'Importando…';
  try{
    const{data,error}=await db.rpc('admin_import_questions_v2',{p_questions:parsedImport.questions,p_mode:mode});
    if(error)throw error;
    const imported=Number(data?.imported||parsedImport.questions.length),replaced=Number(data?.replaced||0);
    $('#importSummary').textContent=mode==='replace'?`Banco substituído com segurança: ${replaced} pergunta(s) anterior(es) removida(s) da operação e ${imported} nova(s) importada(s).`:`${imported} pergunta(s) adicionada(s) ao banco.`;
    $('#importSummary').className='import-summary success';
    $('#bulkQuestionText').value='';parsedImport={questions:[],errors:[],results:[]};$('#importPreview').innerHTML='';
    await loadQuestions();
  }catch(e){
    $('#importSummary').textContent=`Importação cancelada sem alterações parciais: ${e.message||String(e)}`;
    $('#importSummary').className='import-summary error';
  }finally{
    const modeNow=currentImportMode();
    button.textContent=parsedImport.errors.length?`Revisar ${parsedImport.errors.length} erro${parsedImport.errors.length===1?'':'s'}`:(modeNow==='replace'?'Substituir banco pelo lote':'Adicionar lote validado');
    button.disabled=(parsedImport.results?.length||0)===0;
    button.classList.toggle('replace-armed',modeNow==='replace'&&!button.disabled&&!parsedImport.errors.length);
    button.classList.toggle('import-has-errors',parsedImport.errors.length>0);
  }
}
async function readTxtFile(file){
  if(!file)return;
  if(file.size>2*1024*1024)return alert('TXT máximo: 2 MB.');
  try{
    $('#bulkQuestionText').value=(await file.text()).replace(/^\uFEFF/,'');
    analyzeBulkText();
    if(!parsedImport.errors.length&&parsedImport.questions.length){
      $('#importSummary').textContent=`${file.name} • ${parsedImport.questions.length} pergunta(s) válidas • pronto para importar.`;
      $('#importSummary').className='import-summary success';
    }
  }catch(e){
    $('#importSummary').textContent=`Não foi possível ler o TXT: ${e.message||String(e)}`;
    $('#importSummary').className='import-summary error';
  }
}

function questionMatches(q){
  const term=($('#questionSearch')?.value||'').trim().toLowerCase(),cat=$('#questionCategoryFilter')?.value||'',dif=$('#questionDifficultyFilter')?.value||'',usage=$('#questionUsageFilter')?.value||'',optCount=$('#questionOptionCountFilter')?.value||'';
  if(term&&!`${q.prompt} ${q.category||''}`.toLowerCase().includes(term))return false;if(cat&&q.category!==cat)return false;if(dif&&q.difficulty!==dif)return false;if(usage==='unused'&&Number(q.use_count||0)>0)return false;if(usage==='recent'&&!q.last_used_at)return false;
  const count=q.question_type==='choice'?(Array.isArray(q.options)?q.options.length:0):0;if(optCount==='numeric'&&q.question_type!=='numeric')return false;if(optCount==='4'&&count!==4)return false;if(optCount==='5'&&count!==5)return false;
  if(activeBankQuick==='choice'&&q.question_type!=='choice')return false;if(activeBankQuick==='numeric'&&q.question_type!=='numeric')return false;if(activeBankQuick==='unused'&&Number(q.use_count||0)>0)return false;if(activeBankQuick==='tiebreaker'&&!q.is_tiebreaker)return false;if(activeBankQuick==='unscored'&&q.score_enabled!==false)return false;if(activeBankQuick==='final'&&q.difficulty!=='final')return false;if(activeBankQuick==='most_correct'&&q.accuracy_pct==null)return false;if(activeBankQuick==='most_wrong'&&q.accuracy_pct==null)return false;
  return true;
}
function sortQuestionRows(rows){
  let mode=$('#questionSort')?.value||'newest';if(activeBankQuick==='most_correct')mode='accuracy_desc';if(activeBankQuick==='most_wrong')mode='accuracy_asc';const difficultyOrder={facil:1,medio:2,dificil:3,final:4};
  return [...rows].sort((a,b)=>{if(mode==='prompt')return String(a.prompt||'').localeCompare(String(b.prompt||''),'pt-BR');if(mode==='category')return String(a.category||'').localeCompare(String(b.category||''),'pt-BR')||String(a.prompt||'').localeCompare(String(b.prompt||''),'pt-BR');if(mode==='difficulty')return (difficultyOrder[a.difficulty]||9)-(difficultyOrder[b.difficulty]||9)||String(a.prompt||'').localeCompare(String(b.prompt||''),'pt-BR');if(mode==='points_desc')return Number(b.points||0)-Number(a.points||0);if(mode==='used_desc')return Number(b.use_count||0)-Number(a.use_count||0);if(mode==='accuracy_desc')return Number(b.accuracy_pct??-1)-Number(a.accuracy_pct??-1);if(mode==='accuracy_asc')return Number(a.accuracy_pct??999)-Number(b.accuracy_pct??999);if(mode==='speed_asc')return Number(a.avg_response_ms??1e15)-Number(b.avg_response_ms??1e15);if(mode==='speed_desc')return Number(b.avg_response_ms??-1)-Number(a.avg_response_ms??-1);return new Date(b.created_at||0)-new Date(a.created_at||0);});
}
function refreshCategoryFilter(){const sel=$('#questionCategoryFilter');if(!sel)return;const current=sel.value,cats=[...new Set(questionBank.map(q=>q.category||'Geral'))].sort((a,b)=>a.localeCompare(b,'pt-BR'));sel.innerHTML='<option value="">Todas categorias</option>'+cats.map(c=>`<option>${esc(c)}</option>`).join('');sel.value=cats.includes(current)?current:'';}
function refreshCategoryQuickFilters(){
  const host=$('#categoryQuickFilters');if(!host)return;const current=$('#questionCategoryFilter')?.value||'',cats=[...new Set(questionBank.map(q=>q.category||'Geral'))].sort((a,b)=>a.localeCompare(b,'pt-BR')).slice(0,18);host.innerHTML=cats.map(c=>`<button type="button" class="category-chip ${current===c?'active':''}" data-category="${esc(c)}">${esc(c)}</button>`).join('')||'<span class="muted compact">Categorias aparecem aqui quando o banco tiver perguntas.</span>';host.querySelectorAll('[data-category]').forEach(btn=>btn.addEventListener('click',()=>{const sel=$('#questionCategoryFilter');sel.value=sel.value===btn.dataset.category?'':btn.dataset.category;renderQuestionBank();}));
}
function updateQuestionBankSummary(rows){
  const choices=rows.filter(q=>q.question_type==='choice').length,numerics=rows.filter(q=>q.question_type==='numeric').length,scored=rows.filter(q=>q.score_enabled!==false),avg=scored.length?Math.round(scored.reduce((sum,q)=>sum+Number(q.points||0),0)/scored.length):0;
  if($('#bankVisibleCount'))$('#bankVisibleCount').textContent=String(rows.length);if($('#bankChoiceCount'))$('#bankChoiceCount').textContent=String(choices);if($('#bankNumericCount'))$('#bankNumericCount').textContent=String(numerics);if($('#bankPointsAverage'))$('#bankPointsAverage').textContent=String(avg);if($('#bankResultBadge'))$('#bankResultBadge').textContent=`${rows.length} ${rows.length===1?'ITEM':'ITENS'}`;
}
function updateSelectionToolbar(){
  const count=selectedQuestionIds.size;if($('#selectedQuestionCount'))$('#selectedQuestionCount').textContent=`${count} ${count===1?'selecionada':'selecionadas'}`;['#clearQuestionSelectionBtn','#queueSelectedQuestionsBtn','#archiveSelectedQuestionsBtn','#restoreSelectedQuestionsBtn'].forEach(id=>{if($(id))$(id).disabled=count===0;});
}
function renderQuestionBank(){
  const canQueue=canEditQueue()&&!queueAtLimit();visibleQuestionRows=sortQuestionRows(questionBank.filter(questionMatches));selectedQuestionIds=new Set([...selectedQuestionIds].filter(id=>questionBank.some(q=>String(q.id)===String(id))));updateQuestionBankSummary(visibleQuestionRows);refreshCategoryQuickFilters();updateSelectionToolbar();
  $('#questionList').innerHTML=visibleQuestionRows.map(q=>{const archived=!!q.archived,queued=queueRows.some(x=>x.question_id===q.id),recentBlocked=recentQuestionIds.has(q.id)&&Number(roomSettings().avoid_recent_games||0)>0,disabled=!canQueue||archived||queued||recentBlocked,selected=selectedQuestionIds.has(String(q.id)),typeLabel=q.question_type==='choice'?'Escolha':'Número';return `<div class="question-item ${archived?'archived':''} ${selected?'selected':''}" data-id="${q.id}"><label class="question-select" title="Selecionar"><input type="checkbox" data-act="select" ${selected?'checked':''}></label><div class="question-card-main"><div class="question-card-top"><strong>${esc(q.prompt)}</strong><div class="question-card-tags"><span class="qtag ${q.question_type}">${typeLabel}</span><span class="qtag ${q.difficulty==='final'?'final':''}">${esc(difficultyLabel(q.difficulty))}</span>${q.is_tiebreaker?'<span class="qtag tiebreaker">DESEMPATE</span>':''}</div></div><div class="question-card-meta"><span>${esc(q.category||'Geral')}</span><span>${q.score_enabled===false?'Sem pontos':`${q.points} pts`}</span><span>${q.time_limit_seconds}s</span>${q.speed_bonus_pct?`<span>+${q.speed_bonus_pct}% velocidade</span>`:''}<span>${q.use_count?`Usada ${q.use_count}x`:'Nunca usada'}</span>${q.accuracy_pct!=null?`<span>${Number(q.accuracy_pct).toFixed(1)}% acerto</span>`:''}${q.avg_response_ms!=null?`<span>${(Number(q.avg_response_ms)/1000).toFixed(1)}s média</span>`:''}${recentBlocked?'<span>Recente</span>':''}</div><div class="question-card-actions"><button class="queue-question" data-act="queue" ${disabled?'disabled':''}>${queued?'Já escolhida':archived?'Arquivada':recentBlocked?'Usada recentemente':'＋ Sala'}</button><button class="edit-question" data-act="edit">Editar</button><button class="ghost" data-act="duplicate">Duplicar</button><button class="ghost archive-question" data-act="archive">${archived?'Restaurar':'Arquivar'}</button></div></div></div>`;}).join('')||'<div class="empty">Nenhuma pergunta corresponde aos filtros atuais.</div>';
  $$('#questionList .question-item').forEach(el=>{const id=el.dataset.id,q=questionBank.find(x=>String(x.id)===String(id));el.querySelector('[data-act="select"]')?.addEventListener('change',e=>{if(e.target.checked)selectedQuestionIds.add(id);else selectedQuestionIds.delete(id);el.classList.toggle('selected',e.target.checked);updateSelectionToolbar();});el.querySelector('[data-act="queue"]')?.addEventListener('click',()=>queueQuestion(id));el.querySelector('[data-act="edit"]')?.addEventListener('click',()=>startQuestionEdit(id));el.querySelector('[data-act="duplicate"]')?.addEventListener('click',()=>duplicateQuestion(id));el.querySelector('[data-act="archive"]')?.addEventListener('click',()=>setArchived(id,!q?.archived));});
}
function clearQuestionFilters(){
  $('#questionSearch').value='';$('#questionCategoryFilter').value='';$('#questionDifficultyFilter').value='';$('#questionUsageFilter').value='';if($('#questionOptionCountFilter'))$('#questionOptionCountFilter').value='';$('#questionSort').value='newest';activeBankQuick='all';$$('[data-bank-quick]').forEach(btn=>btn.classList.toggle('active',btn.dataset.bankQuick==='all'));renderQuestionBank();
}
function setBankQuickFilter(value){activeBankQuick=value||'all';$$('[data-bank-quick]').forEach(btn=>btn.classList.toggle('active',btn.dataset.bankQuick===activeBankQuick));renderQuestionBank();}
async function bulkSetArchived(archived){
  const ids=[...selectedQuestionIds];if(!ids.length)return;if(archived&&!confirm(`Arquivar ${ids.length} pergunta(s) selecionada(s)?`))return;
  for(const id of ids){const{error}=await db.rpc('admin_set_question_archived',{p_question_id:id,p_archived:archived});if(error){alert(error.message);break;}}
  selectedQuestionIds.clear();await loadQuestions();
}
async function bulkQueueSelected(){
  if(!room)return alert('Crie uma sala primeiro.');if(!canEditQueue())return alert('A fila fica bloqueada depois do início.');let available=Math.max(0,200-queueRows.length),added=0;
  for(const id of [...selectedQuestionIds]){if(available<=0)break;const q=questionBank.find(x=>String(x.id)===String(id));if(!q||q.archived||queueRows.some(x=>String(x.question_id)===String(id))||recentQuestionIds.has(q.id)&&Number(roomSettings().avoid_recent_games||0)>0)continue;const{error}=await db.rpc('admin_queue_question',{p_room_id:room.id,p_question_id:id});if(!error){added++;available--;}}
  if(added){const desired=Math.max(Number(roomState?.room?.planned_rounds||room.planned_rounds||1),queueRows.length+added);if(desired<=200)await db.rpc('admin_update_planned_rounds',{p_room_id:room.id,p_planned_rounds:desired});}
  selectedQuestionIds.clear();await Promise.all([loadQueue(),refreshState(true)]);renderQuestionBank();if(!added)alert('Nenhuma pergunta selecionada pôde ser adicionada à sala.');
}

async function loadQuestions(){const [bank,stats]=await Promise.all([db.rpc('admin_list_question_bank',{p_scope:$('#questionScope')?.value||'active'}),db.rpc('admin_question_bank_stats')]);if(bank.error){$('#questionList').textContent=bank.error.message;return;}if(stats.error)diag('warn','Estatísticas históricas do banco indisponíveis',{error:stats.error.message});questionStats=new Map((stats.data||[]).map(x=>[String(x.question_id),x]));questionBank=(bank.data||[]).map(q=>({...q,...(questionStats.get(String(q.id))||{})}));await loadRecentQuestionIds();refreshCategoryFilter();renderQuestionBank();renderBuildSummary();}
async function loadRecentQuestionIds(){recentQuestionIds=new Set();if(!room)return;const n=Math.max(0,Number(roomSettings().avoid_recent_games||$('#avoidRecentGames')?.value||0));if(!n)return;const{data}=await db.rpc('admin_recent_question_ids',{p_room_id:room.id,p_games:n});recentQuestionIds=new Set((data||[]).map(String));}
async function duplicateQuestion(id){const{error}=await db.rpc('admin_duplicate_question',{p_question_id:id});if(error)return alert(error.message);await loadQuestions();}
async function setArchived(id,archived){const{error}=await db.rpc('admin_set_question_archived',{p_question_id:id,p_archived:archived});if(error)return alert(error.message);await loadQuestions();}
async function queueQuestion(id){if(!room)return alert('Crie uma sala primeiro.');if(!canEditQueue())return alert('Fila bloqueada após o início.');if(queueAtLimit())return alert('Limite máximo de 200 perguntas atingido.');const nextCount=queueRows.length+1,currentTarget=Number(roomState?.room?.planned_rounds||room.planned_rounds||plannedRounds());if(nextCount>currentTarget){const grow=await db.rpc('admin_update_planned_rounds',{p_room_id:room.id,p_planned_rounds:nextCount});if(grow.error)return alert(grow.error.message);}const{error}=await db.rpc('admin_queue_question',{p_room_id:room.id,p_question_id:id});if(error)return alert(error.message);await Promise.all([loadQueue(),refreshState(true)]);renderQuestionBank();}
function queueMarkup(locked){return queueRows.map((q,i)=>`<div class="question-item queue-item ${q.status==='used'?'used':''}" draggable="${!locked&&q.status==='queued'}" data-id="${q.id}"><div class="queue-pos">${q.status==='used'?'✓':q.position}</div><div><strong>${esc(q.prompt)}</strong><div class="question-meta">${esc(q.category||'Geral')} • ${esc(q.difficulty||'medio')} • ${q.score_enabled===false?'sem pontos':`${q.points} pts`} • ${q.time_limit_seconds}s${q.is_tiebreaker?' • desempate':''}</div></div><div class="item-actions">${!locked&&q.status==='queued'?`<button class="ghost small" data-act="up" ${i===0?'disabled':''}>↑</button><button class="ghost small" data-act="down" ${i===queueRows.length-1?'disabled':''}>↓</button><button class="warn small" data-act="remove">Remover</button>`:''}</div></div>`).join('')||'<div class="empty">Nenhuma pergunta escolhida.</div>';}
function bindQueueHost(host){if(!host)return;let dragId=null;host.querySelectorAll('.queue-item').forEach(el=>{el.querySelector('[data-act="up"]')?.addEventListener('click',()=>moveQueue(el.dataset.id,-1));el.querySelector('[data-act="down"]')?.addEventListener('click',()=>moveQueue(el.dataset.id,1));el.querySelector('[data-act="remove"]')?.addEventListener('click',()=>removeQueue(el.dataset.id));el.addEventListener('dragstart',()=>{dragId=el.dataset.id;el.classList.add('dragging');});el.addEventListener('dragend',()=>el.classList.remove('dragging'));el.addEventListener('dragover',e=>{if(dragId&&dragId!==el.dataset.id)e.preventDefault();});el.addEventListener('drop',async e=>{e.preventDefault();if(!dragId||dragId===el.dataset.id)return;const from=queueRows.findIndex(x=>x.id===dragId),to=queueRows.findIndex(x=>x.id===el.dataset.id),dir=to>from?1:-1;for(let i=0;i<Math.abs(to-from);i++)await moveQueue(dragId,dir,false);await loadQueue();dragId=null;});});}
async function loadQueue(){const hosts=[$('#roundQueue'),$('#roundQueueMini')].filter(Boolean);if(!room){queueRows=[];hosts.forEach(h=>h.innerHTML='<div class="empty">Crie uma sala para montar os rounds.</div>');renderBuildSummary();renderSetupReview();return;}const{data,error}=await db.rpc('admin_list_room_queue',{p_room_id:room.id});if(error){hosts.forEach(h=>h.textContent=error.message);return;}queueRows=data||[];const target=Number(roomState?.room?.planned_rounds||room.planned_rounds||plannedRounds()),locked=!canEditQueue(),html=queueMarkup(locked);if($('#queueCount'))$('#queueCount').textContent=`${queueRows.length} / ${target}`;if($('#playlistQueueCount'))$('#playlistQueueCount').textContent=`${queueRows.length} / ${target}`;if($('#queueWarning')){$('#queueWarning').textContent=locked?'Fila bloqueada durante a partida.':queueRows.length<1?'Adicione pelo menos 1 pergunta para liberar o início.':queueRows.length<target?`${queueRows.length} de ${target} planejadas • faltam ${target-queueRows.length}, mas você já pode iniciar com a seleção atual.`:'Fila completa. Você pode embaralhar ou iniciar.';$('#queueWarning').className=`queue-warning ${queueRows.length>0?'ready':''}`;}hosts.forEach(h=>{h.innerHTML=html;bindQueueHost(h);});updateControls();renderQuestionBank();renderBuildSummary();renderSetupReview();renderNextQuestionPreview();}
async function moveQueue(id,direction,reload=true){const{error}=await db.rpc('admin_move_queue_item',{p_room_id:room.id,p_queue_id:id,p_direction:direction});if(error)return alert(error.message);if(reload)await loadQueue();}
async function removeQueue(id){const{error}=await db.rpc('admin_remove_queue_item',{p_room_id:room.id,p_queue_id:id});if(error)return alert(error.message);await Promise.all([loadQueue(),refreshState(true)]);}

function parseQualificationSchedule(raw){return String(raw||'').split(',').map(x=>x.trim()).filter(Boolean).map(x=>{const[a,b]=x.split(':').map(Number);return Number.isFinite(a)&&Number.isFinite(b)&&a>0&&b>0?{round:Math.round(a),top:Math.round(b)}:null;}).filter(Boolean).sort((a,b)=>a.round-b.round).slice(0,20);}
function currentQualifyTop(){const s=roomSettings(),base=Math.max(1,Number(s.qualify_top||5)),roundNo=Number(roomState?.round?.round_no||roomState?.used_rounds||0),schedule=Array.isArray(s.qualification_schedule)?s.qualification_schedule:[];let cut=base;for(const x of schedule){if(roundNo>=Number(x.round||0))cut=Math.max(1,Number(x.top||cut));}return cut;}
function getSettingsPatch(){const startRaw=$('#lobbyStartTime')?.value||'',startIso=startRaw&&Number.isFinite(new Date(startRaw).getTime())?new Date(startRaw).toISOString():'';return{expected_players:Math.max(1,Number($('#expectedPlayers')?.value)||50),default_time:Math.max(5,Number($('#defaultTime')?.value)||30),default_points:Math.max(1,Number($('#defaultPoints')?.value)||100),shuffle_answers:!!$('#shuffleAnswersToggle')?.checked,break_every:Math.max(0,Number($('#breakEvery')?.value)||0),classification_enabled:$('#classificationEnabled').checked,qualify_top:Math.max(1,Number($('#qualifyTop').value)||5),qualification_schedule:parseQualificationSchedule($('#qualificationSchedule').value),late_join_policy:$('#lateJoinPolicy').value,late_join_until_round:Math.max(1,Number($('#lateJoinUntil').value)||3),auto_close_all_answered:$('#autoCloseAll').checked,auto_close_time_expired:$('#autoCloseTime')?.checked||false,speed_bonus_enabled:$('#speedBonusEnabled').checked,streak_enabled:$('#streakEnabled').checked,streak_bonus:Math.max(0,Number($('#streakBonus').value)||0),avoid_recent_games:Math.max(0,Number($('#avoidRecentGames').value)||0),theme:$('#themePreset').value,logo_url:logoUrlForSettings(),sound_enabled:$('#soundEnabled').checked,allow_duplicate_names:$('#allowDuplicateNames').checked,banned_words:$('#bannedWords').value.split(',').map(x=>x.trim()).filter(Boolean).slice(0,100),is_rehearsal:$('#rehearsalMode').checked,lobby_message:($('#lobbyMessage')?.value||'').trim().slice(0,120),lobby_start_time:startIso,avatar_scene:$('#avatarScene')?.value||'auto',lobby_map_mode:$('#lobbyMapMode')?.value||'auto',lobby_ready_threshold:Math.max(50,Math.min(100,Number($('#lobbyReadyThreshold')?.value)||80)),lobby_music_enabled:!!$('#lobbyMusicEnabled')?.checked,display_clock_mode:['seconds','minutes','hidden'].includes($('#displayClockMode')?.value)?$('#displayClockMode').value:'seconds'};}
function fillSettings(){const s=roomSettings();if($('#expectedPlayers'))$('#expectedPlayers').value=s.expected_players||50;if($('#defaultTime'))$('#defaultTime').value=s.default_time||30;if($('#defaultPoints'))$('#defaultPoints').value=s.default_points||100;if($('#shuffleAnswersToggle'))$('#shuffleAnswersToggle').checked=!!s.shuffle_answers;if($('#breakEvery'))$('#breakEvery').value=s.break_every||0;$('#classificationEnabled').checked=!!s.classification_enabled;$('#qualifyTop').value=s.qualify_top||5;$('#qualificationSchedule').value=Array.isArray(s.qualification_schedule)?s.qualification_schedule.map(x=>`${x.round}:${x.top}`).join(', '):'';$('#lateJoinPolicy').value=s.late_join_policy||'allow_zero';$('#lateJoinUntil').value=s.late_join_until_round||3;$('#autoCloseAll').checked=!!s.auto_close_all_answered;if($('#autoCloseTime'))$('#autoCloseTime').checked=!!s.auto_close_time_expired;$('#speedBonusEnabled').checked=s.speed_bonus_enabled!==false;$('#streakEnabled').checked=s.streak_enabled!==false;$('#streakBonus').value=s.streak_bonus||0;$('#avoidRecentGames').value=s.avoid_recent_games||0;$('#themePreset').value=roomState?.room?.theme||s.theme||'violet';syncLogoEditor();$('#soundEnabled').checked=s.sound_enabled!==false;$('#allowDuplicateNames').checked=!!s.allow_duplicate_names;$('#bannedWords').value=Array.isArray(s.banned_words)?s.banned_words.join(', '):'';$('#rehearsalMode').checked=!!roomState?.room?.is_rehearsal;if($('#lobbyMessage'))$('#lobbyMessage').value=s.lobby_message||'';if($('#lobbyStartTime'))$('#lobbyStartTime').value=toLocalDateTimeInput(s.lobby_start_time);if($('#avatarScene'))$('#avatarScene').value=['office','laboratory','industry','platform'].includes(s.avatar_scene)?s.avatar_scene:'auto';if($('#lobbyMapMode'))$('#lobbyMapMode').value=['standard','map'].includes(s.lobby_map_mode)?s.lobby_map_mode:'auto';if($('#lobbyReadyThreshold'))$('#lobbyReadyThreshold').value=Math.max(50,Math.min(100,Number(s.lobby_ready_threshold||80)));if($('#lobbyMusicEnabled'))$('#lobbyMusicEnabled').checked=!!s.lobby_music_enabled;if($('#displayClockMode'))$('#displayClockMode').value=['seconds','minutes','hidden'].includes(s.display_clock_mode)?s.display_clock_mode:'seconds';applyAdminTheme();renderLobbyControls();}
async function saveRoomSettings(show=true){clearTimeout(settingsSaveTimer);settingsSaveTimer=null;clearTimeout(logoLinkSaveTimer);logoLinkSaveTimer=null;if(!room){if(show)alert('Crie a sala primeiro.');return false;}if(settingsSaving)return false;let patch;try{patch=getSettingsPatch();}catch(e){if(show)alert(e.message||String(e));else throw e;return false;}const serial=settingsDraftSerial,oldLogo=roomState?.room?.logo_url||room?.logo_url||'',logoWasDirty=logoEditorDirty;let failed=false;settingsSaving=true;updateSettingsSaveIndicator('saving');try{let result=await db.rpc('admin_update_room_settings',{p_room_id:room.id,p_patch:patch});if(result.error&&isControllerAuthorityError(result.error)&&!remoteModeActive){const reclaimed=await claimController(false);if(reclaimed){diag('ok','Controle renovado para salvar configurações');result=await db.rpc('admin_update_room_settings',{p_room_id:room.id,p_patch:patch});}}if(result.error)throw result.error;room=result.data;rememberRoom();commitLogoDraft(patch.logo_url);clearPendingLogoObject();if(settingsDraftSerial===serial)settingsDraftDirty=false;await refreshState(true);if(oldLogo&&oldLogo!==patch.logo_url)await removeManagedLogo(oldLogo);await loadRecentQuestionIds();renderQuestionBank();if(logoWasDirty)setLogoStatus(patch.logo_url?'Logo salva e sincronizada com a sala.':'Logo removida e configuração salva.','ready');if(show)actionToast('Configurações salvas ✓');updateSettingsSaveIndicator('idle');return true;}catch(e){failed=true;settingsDraftDirty=true;updateSettingsSaveIndicator('error');if(show){alert(e.message||String(e));return false;}throw e;}finally{settingsSaving=false;if(settingsDraftDirty){updateSettingsSaveIndicator(failed?'error':'dirty');if(!failed)scheduleSettingsAutosave();}else{updateSettingsSaveIndicator('idle');fillSettings();}}}
async function saveTemplate(){if(!room)return alert('Crie uma sala.');const name=prompt('Nome do modelo de partida:',`${room.title} — modelo`);if(!name)return;const{error}=await db.rpc('admin_save_template',{p_room_id:room.id,p_name:name});if(error)return alert(error.message);await loadTemplates();alert('Modelo salvo.');}
async function loadTemplates(){const sel=$('#templateSelect');if(!sel)return;const{data,error}=await db.rpc('admin_list_templates');if(error)return;const rows=data||[],current=sel.value;sel.innerHTML='<option value="">Selecione um modelo...</option>'+rows.map(t=>`<option value="${t.id}">${esc(t.name)} • ${t.question_count} perguntas</option>`).join('');if(rows.some(t=>t.id===current))sel.value=current;}
async function useTemplate(){const id=$('#templateSelect').value;if(!id)return alert('Selecione um modelo.');let authorityReady=false;try{authorityReady=await ensureControllerForRoomCreation();}catch(e){return alert(e.message||String(e));}if(!authorityReady)return;await withAction('Criando sala do modelo…',async()=>{const{data,error}=await db.rpc('admin_create_from_template',{p_template_id:id,p_title:null});if(error)throw error;room=data;rememberRoom();settingsDraftDirty=false;settingsDraftSerial=0;updateSettingsSaveIndicator('idle');roomState=null;queueRows=[];presenceOnline=null;displayOnline=false;lastAdminQr='';$('#plannedRounds').value=room.planned_rounds||10;await claimController(true);await Promise.all([refreshState(true),loadQueue(),loadAudit(),loadParticipants(),loadQuestions()]);await subscribe();switchAdminTab('config');},{skipControllerGuard:true});}
async function duplicateRoom(){if(!room)return alert('Crie ou abra uma sala.');const title=prompt('Nome da cópia:',`${room.title} — cópia`);if(!title)return;await withAction('Duplicando sala…',async()=>{const{data,error}=await db.rpc('admin_duplicate_room',{p_room_id:room.id,p_title:title});if(error)throw error;room=data;rememberRoom();roomState=null;queueRows=[];presenceOnline=null;displayOnline=false;lastAdminQr='';$('#plannedRounds').value=room.planned_rounds||10;await claimController(true);await Promise.all([refreshState(true),loadQueue(),loadAudit(),loadParticipants(),loadQuestions()]);await subscribe();switchAdminTab('config');});}

async function startQuiz(){if(!room)return alert('Crie ou abra uma sala primeiro.');if(phase()!=='lobby')return alert('O quiz só pode ser iniciado enquanto a sala está no lobby.');await Promise.all([refreshState(true),loadQueue()]);const setup=setupChecks(),blocking=setup.filter(x=>!x.ok);if(blocking.length)return alert('Revisão bloqueou o início: '+blocking.map(x=>x.label).join(', ')+'.');const pf=await runPreflight({silent:true});if(!pf.hard)return alert('Pré-teste bloqueou o início: corrija Supabase, Realtime, perguntas ou controlador principal.');if(!pf.all&&!confirm('O pré-teste ainda tem alerta (por exemplo, telão não detectado). Deseja iniciar mesmo assim?'))return;const queued=queueRows.length;if(queued<1)return alert('Adicione pelo menos 1 pergunta à sala antes de começar.');const saved=await withAction('Validando configurações…',async()=>{await saveRoomSettings(false);});if(!saved)return;await withAction(`Preparando ${queued} pergunta${queued===1?'':'s'}…`,async()=>{const{error}=await db.rpc('admin_start_quiz',{p_room_id:room.id});if(error)throw error;await Promise.all([refreshState(true),loadQueue(),loadAudit()]);$('#plannedRounds').value=Number(roomState?.room?.planned_rounds||queued);});}
async function prepareRound(){if(!room)return;await withAction('Preparando próximo round…',async()=>{const{error}=await db.rpc('admin_prepare_next_round',{p_room_id:room.id});if(error)throw error;await refreshState(true);});}
async function openPreparedRound(){if(!room)return;await withAction('Liberando pergunta…',async()=>{const{error}=await db.rpc('admin_open_prepared_round',{p_room_id:room.id});if(error)throw error;await Promise.all([refreshState(true),loadQueue(),loadAudit()]);});}
async function closeRound(){if(!room)return;await withAction('Encerrando e pontuando…',async()=>{const{data,error}=await db.rpc('admin_close_and_score_round',{p_room_id:room.id});if(error)throw error;await Promise.all([refreshState(true),loadQueue(),loadAudit(),loadParticipants(),loadHistory(),loadEventInsights()]);if(data?.finished)$('#roundHint').textContent='Último round encerrado. Use as etapas de revelação para apresentar o resultado final.';});}
async function pauseQuiz(){if(!room)return;const isPaused=phase()==='paused';await withAction(isPaused?'Retomando…':'Pausando…',async()=>{const{error}=await db.rpc('admin_pause_quiz',{p_room_id:room.id,p_pause:!isPaused});if(error)throw error;await refreshState(true);});}
async function extendRound(sec){if(remoteModeActive&&!await ensureRemoteRoomBinding())return;if(!room)return;const{error}=await db.rpc('admin_extend_round',{p_room_id:room.id,p_seconds:sec});if(error)return alert(error.message);await refreshState(true);}
async function annulRound(){if(!room||!confirm('Anular o último round? Os pontos dele serão removidos do ranking.'))return;const{error}=await db.rpc('admin_annul_round',{p_room_id:room.id});if(error)return alert(error.message);await Promise.all([refreshState(true),loadHistory()]);}
async function regradeRound(){const r=roomState?.round;if(!r)return;if(!confirm('Corrigir o gabarito do último round e recalcular o ranking?'))return;let choice=null,num=null;if(r.question_type==='choice'){choice=prompt('Nova alternativa correta (A, B, C, D ou E):',r.correct_choice||'A');if(!choice)return;choice=choice.trim().toUpperCase();}else{const raw=prompt('Novo valor correto:',r.correct_number??'');if(raw===null)return;num=Number(raw.replace(',','.'));if(!Number.isFinite(num))return alert('Número inválido.');}const{error}=await db.rpc('admin_regrade_round',{p_room_id:room.id,p_correct_choice:choice,p_correct_number:num});if(error)return alert(error.message);await Promise.all([refreshState(true),loadHistory()]);}
async function reveal(stage){if(!room)return;const labels={answer:'Mostrando resposta…',distribution:'Mostrando distribuição…',ranking:'Mostrando ranking…',final:'Abrindo ranking final…'};await withAction(labels[stage]||'Atualizando apresentação…',async()=>{const{error}=await db.rpc('admin_set_reveal_stage',{p_room_id:room.id,p_stage:stage});if(error)throw error;await Promise.all([refreshState(true),stage==='final'?loadEventInsights():Promise.resolve()]);});}
async function restartQuiz(){if(!room||!confirm('Recomeçar do Round 1? Respostas, pontos e ranking serão zerados; jogadores permanecem.'))return;await withAction('Recomeçando…',async()=>{const{error}=await db.rpc('admin_restart_quiz',{p_room_id:room.id});if(error)throw error;await Promise.all([refreshState(true),loadQueue(),loadHistory()]);});}

function renderAdminQr(){const codeEl=$('#adminLobbyCode'),urlEl=$('#adminJoinUrl'),qrEl=$('#adminQr');if(!codeEl||!urlEl||!qrEl)return;if(!room){codeEl.textContent='------';urlEl.textContent='Crie uma sala para gerar o link';qrEl.innerHTML='<div class="qr-placeholder">QR</div>';lastAdminQr='';return;}codeEl.textContent=room.code;const value=joinUrl();try{const u=new URL(value);urlEl.textContent=`${u.host}${u.pathname}?code=${room.code}`;}catch{urlEl.textContent=value;}if(value===lastAdminQr)return;qrEl.innerHTML='';try{window.QuizQR?.render(qrEl,value);lastAdminQr=value;}catch{qrEl.textContent='QR indisponível';}}
function joinUrl(){if(!room)return'';const url=new URL('index.html',location.href);url.search='';url.hash='';url.searchParams.set('code',room.code);return url.href;}
async function copyJoinLink(){if(!room)return;const text=joinUrl();try{await navigator.clipboard.writeText(text);$('#joinLinkStatus').textContent='Link copiado.';}catch{$('#joinLinkStatus').textContent=text;}}
async function openDisplay(mode='reuse'){
  if(!room)return;
  if(phase()==='finished'||room?.status==='finished'){diag('warn','Telão bloqueado: sala encerrada',{room_code:room.code});return alert('Esta sala já foi encerrada. Crie uma nova sala para abrir um novo lobby/telão.');}
  if(!backendCompatible)return alert(`Backend incompatível. Aplique a migration ${String(BACKEND_SCHEMA_REQUIRED).padStart(3,'0')} antes de abrir o telão.`);
  if(!remoteModeActive){const reclaimed=await claimController(false);if(!reclaimed)return alert('Este dispositivo não é o controlador ativo da sala. Use “Assumir controle” antes de abrir o telão.');}
  let target=null,createdBlank=false;
  if(displayWindowRef&&!displayWindowRef.closed){target=displayWindowRef;try{target.focus();}catch{}}
  else if(mode==='window'){
    const width=Math.max(1100,Math.floor((window.screen?.availWidth||1600)*.92)),height=Math.max(720,Math.floor((window.screen?.availHeight||900)*.92)),left=Math.max(0,Math.floor(((window.screen?.availWidth||width)-width)/2)),top=Math.max(0,Math.floor(((window.screen?.availHeight||height)-height)/2));
    target=window.open('about:blank','quiz2_display_popup',`popup=yes,resizable=yes,scrollbars=yes,width=${width},height=${height},left=${left},top=${top}`);createdBlank=!!target;
  }else{target=window.open('about:blank','quiz2_display');createdBlank=!!target;}
  try{
    const{data,error}=await db.rpc('admin_create_display_pairing',{p_room_id:room.id});if(error)throw error;
    const url=`display.html?code=${encodeURIComponent(room.code)}&pair=${encodeURIComponent(data?.pair_token||'')}`;
    if(target&&!target.closed){target.location.href=url;displayWindowRef=target;try{target.focus();}catch{}}
    else{const opened=window.open(url,'_blank');if(opened)displayWindowRef=opened;}
    diag('ok','Telão aberto com pareamento temporário',{expires_at:data?.expires_at||null});
  }catch(e){if(createdBlank&&target&&!target.closed)try{target.close();}catch{}diag('error','Falha ao parear telão',{error:e.message||String(e)});alert(e.message||'Não foi possível autorizar o telão.');}
}

function updatePresentationStage(){const p=room?phase():'lobby',stage=p==='lobby'?'lobby':p==='question_open'||p==='preparing'?'question':'result',badge=$('#presentationStageBadge');if(badge){badge.textContent=statusLabel(p);badge.className=`live-stage-badge stage-${stage}`;}$$('.presentation-stepper [data-stage]').forEach(el=>el.classList.toggle('active',el.dataset.stage===stage));const title=$('#presentationStageTitle'),hint=$('#presentationStageHint');if(!title)return;if(!room){title.textContent='Crie uma sala';hint.textContent='Configure a partida para gerar PIN e QR Code.';}else if(p==='lobby'){const joined=Number(roomState?.participant_count||0),ready=Number(roomState?.ready_count||0),pct=joined?Math.round(ready*100/joined):0;title.textContent='Lobby aberto';hint.textContent=joined<1?'Abra o telão e peça para os jogadores entrarem.':`${ready}/${joined} prontos (${pct}%) • acompanhe conexões e inicie quando desejar.`;}else if(p==='preparing'){title.textContent='Prepare-se';hint.textContent='Contagem regressiva 3…2…1 sincronizada.';}else if(p==='question_open'){title.textContent='Pergunta no ar';hint.textContent='Acompanhe respostas; você pode estender +5/+10 s antes do prazo.';}else if(p==='paused'){title.textContent='Partida pausada';hint.textContent='Os jogadores permanecem conectados.';}else if(p==='result'){title.textContent='Resultado do round';hint.textContent='Revele resposta, distribuição e ranking em etapas.';}else if(p==='finished'){title.textContent=finalShowLabel();hint.textContent='Apresentação final sincronizada: ranking, estatísticas, destaques e campeão.';}else{title.textContent='Final';hint.textContent='Mostre campeão, pódio e relatório.';}}
function updateLiveStats(data){const total=Number(data?.participant_count||0),active=Number(presenceOnline??data?.active_count??0),ready=Number(data?.ready_count||0),answers=Number(data?.answer_count||0),open=data?.room?.phase==='question_open',eligible=Number(data?.eligible_count||0),eligibleAnswers=Number(data?.eligible_answer_count??answers),denom=open&&eligible>0?eligible:total,countForRate=open&&eligible>0?eligibleAnswers:answers,pending=open?Math.max(0,denom-countForRate):0,rate=open&&denom?Math.min(100,Math.round(countForRate*100/denom)):0;$('#participantCount').textContent=total;$('#activeCount').textContent=active;if($('#readyCount'))$('#readyCount').textContent=ready;$('#answerCount').textContent=answers;$('#pendingCount').textContent=pending;$('#responseRate').textContent=`${rate}%`;$('#adminResponseBar').style.width=`${rate}%`;renderLobbyControls();if(open&&roomSettings().auto_close_all_answered&&eligible>0&&eligibleAnswers>=eligible&&!autoClosing){autoClosing=true;closeRound().finally(()=>autoClosing=false);}}
function renderPresenter(){const r=roomState?.round,p=roomState?.prepared,box=$('#presenterPrivate'),preview=$('#nextPreview');if(r&&['question_open','result','finished'].includes(phase())){box.classList.remove('hidden');const answer=r.question_type==='choice'?`${r.correct_choice||'—'}`:`${r.correct_number??'—'}`;$('#presenterAnswer').textContent=`Gabarito: ${answer}`;$('#presenterNotes').textContent=r.presenter_notes||'';}else box.classList.add('hidden');if(p){preview.classList.remove('hidden');$('#nextPreviewPrompt').textContent=p.prompt;$('#nextPreviewMeta').textContent=`${p.category||'Geral'} • ${p.difficulty||'medio'} • ${p.points||0} pts`;if(p.presenter_notes){box.classList.remove('hidden');$('#presenterNotes').textContent=p.presenter_notes;}}else preview.classList.add('hidden');}
function renderRankingMovers(){const rows=(roomState?.round?.movers||[]).filter(x=>x.change).slice(0,6),el=$('#rankingMovers'),signature=JSON.stringify(rows.map(x=>[x.participant_id,x.display_name,x.change]));if(el.dataset.moversSignature!==signature){el.innerHTML=rows.map(x=>`<span class="mover ${x.change>0?'up':'down'}">${x.change>0?'↑':'↓'} ${esc(x.display_name)} ${Math.abs(x.change)} posição(ões)</span>`).join('');el.dataset.moversSignature=signature;}const s=roomSettings();$('#qualificationBadge').textContent=s.classification_enabled?`Classificam Top ${currentQualifyTop()}`:'Sem corte';}
async function refreshState(force=false){if(!room)return false;const seq=++refreshSeq,t=performance.now();const{data,error}=await db.rpc('admin_get_room_state',{p_room_id:room.id});lastLatency=Math.round(performance.now()-t);if($('#latencyBadge')){$('#latencyBadge').textContent=`Latência ${lastLatency} ms`;$('#latencyBadge').className=`badge ${lastLatency<400?'ready':lastLatency<1200?'neutral':'warn'}`;}if(error){if(force&&seq>=refreshAppliedSeq)$('#roundHint').textContent=`Falha ao sincronizar: ${error.message}`;return false;}if(seq<refreshAppliedSeq)return false;refreshAppliedSeq=seq;roomState=data;if(data.room){room={...room,...data.room};rememberRoom();}serverOffset=Date.parse(data.server_now)-Date.now();if(lastObservedPhase&&lastObservedPhase!==data.room?.phase)diag('state',`Estado: ${lastObservedPhase} → ${data.room?.phase}`,{version:data.room?.state_version||0});lastObservedPhase=data.room?.phase||lastObservedPhase;const usedNow=Number(data.used_rounds||0);if(usedNow!==lastInsightsRounds&&usedNow>0){lastInsightsRounds=usedNow;loadEventInsights();}$('#randomizeQueueToggle').checked=!!room.randomize_queue;renderRank($('#adminRanking'),data.ranking||[],{movers:data.round?.movers||[]});updateLiveStats(data);$('#stateVersionAdmin').textContent=`v${data.room?.state_version||0} • g${data.room?.generation||1}`;$('#currentQuestionAdmin').textContent=data.round?.prompt||data.prepared?.prompt||'Nenhuma pergunta em execução.';$('#roomProgress').textContent=`${data.used_rounds||0}/${data.room?.planned_rounds||0} rounds • ${data.queued_count||0} aguardando • ${data.ready_count||0} prontos`;renderAdminQr();if(!settingsDraftDirty&&!settingsSaving)fillSettings();if($('#eventStatusBadge')&&data.room?.is_rehearsal)$('#eventStatusBadge').textContent=`${statusLabel(data.room.phase)} • ENSAIO`;renderPresenter();renderRankingMovers();updatePresentationStage();updateControls();renderTimer();renderRemoteControl();renderEventHealth();await maybeAutoOpen();return true;}
async function maybeAutoOpen(){if(autoOpening||phase()!=='preparing'||!roomState?.room?.prepared_until)return;const remain=serverRemaining(roomState.room.prepared_until,serverOffset);if(remain>0)return;autoOpening=true;try{const{error}=await db.rpc('admin_open_prepared_round',{p_room_id:room.id});if(!error)await Promise.all([refreshState(true),loadQueue()]);}finally{autoOpening=false;}}
function updateStartReadiness(){const target=Number(roomState?.room?.planned_rounds||room?.planned_rounds||plannedRounds()),joined=Number(roomState?.participant_count||0),readyPeople=Number(roomState?.ready_count||0),queued=queueRows.length,lobby=!!room&&phase()==='lobby'&&Number(roomState?.used_rounds||0)===0;const roomCheck=$('#startRoomCheck'),peopleCheck=$('#startPeopleCheck'),readyCheck=$('#startReadyCheck'),queueCheck=$('#startQueueCheck'),guard=$('#startRoomGuard'),btn=$('#startQuizBtn');if(roomCheck){roomCheck.textContent=room?`Sala ${room.code} • lobby`:'Crie uma sala';roomCheck.className=`start-check ${lobby?'ready':'warn'}`;}if(peopleCheck){peopleCheck.textContent=joined>0?`${joined} participante${joined===1?'':'s'} cadastrado${joined===1?'':'s'}`:'0 participantes • podem entrar depois';peopleCheck.className='start-check ready';}if(readyCheck){const pct=joined?Math.round(readyPeople*100/joined):0;readyCheck.textContent=joined?`${readyPeople}/${joined} prontos • ${pct}%`:'0 jogadores prontos • opcional';readyCheck.className=`start-check ${joined>0&&readyPeople===joined?'ready':'neutral'}`;}if(queueCheck){queueCheck.textContent=queued>0?`${queued} pergunta${queued===1?'':'s'} selecionada${queued===1?'':'s'}${queued!==target?` • a partida usará ${queued} round${queued===1?'':'s'}`:''}`:'Nenhuma pergunta selecionada';queueCheck.className=`start-check ${queued>0?'ready':'warn'}`;}const canStart=lobby&&queued>0;if(guard){guard.classList.toggle('hidden',canStart||!room);guard.textContent=!room?'':'Adicione pelo menos 1 pergunta à sala para liberar o início da partida.';}if(btn){btn.disabled=actionBusy||!canStart;btn.classList.toggle('needs-setup',lobby&&!canStart);btn.textContent=canStart?'Começar Quiz':'Adicione perguntas para começar';btn.title=canStart?`${queued} pergunta${queued===1?'':'s'} pronta${queued===1?'':'s'} • ${readyPeople}/${joined||0} jogadores prontos.`:'O quiz só começa quando existe pelo menos 1 pergunta selecionada.';}renderLobbyControls();}
function updateControls(){const has=!!room;if(!has){$$('#displayBtn,#fullscreenDisplayBtn,#pairRemoteBtn,#copyJoinLinkBtn,#startQuizBtn,#contextPrimaryBtn,#emergencyStopBtn,#prepareRoundBtn,#openRoundBtn,#closeRoundBtn,#restartQuizBtn,#shuffleQueueBtn,#pauseQuizBtn,#extend5Btn,#extend10Btn,#annulRoundBtn,#regradeRoundBtn').forEach(b=>b.disabled=true);updateRemoteAvailability();renderRemoteControl();return;}const p=phase(),target=Number(roomState?.room?.planned_rounds||plannedRounds()),used=Number(roomState?.used_rounds||0),queued=Number(roomState?.queued_count||0),r=roomState?.round;$('#eventStatusBadge').textContent=statusLabel(p);$('#roundProgressBadge').textContent=`${used} / ${target}`;$('#displayBtn').disabled=false;$('#fullscreenDisplayBtn').disabled=false;$('#pairRemoteBtn').disabled=actionBusy||p==='finished';$('#copyJoinLinkBtn').disabled=false;const joined=Number(roomState?.participant_count||0);updateStartReadiness();$('#plannedRounds').disabled=p!=='lobby';$('#randomizeQueueToggle').disabled=p!=='lobby'||actionBusy;$('#shuffleQueueBtn').disabled=actionBusy||!(p==='lobby'&&queueRows.length>=2);$('#restartQuizBtn').disabled=actionBusy||used===0;$('#prepareRoundBtn').disabled=actionBusy||!(p==='result'&&used<target&&queued>0);$('#openRoundBtn').disabled=actionBusy||p!=='preparing';$('#closeRoundBtn').disabled=actionBusy||!(p==='question_open'&&r?.status==='open');$('#pauseQuizBtn').disabled=actionBusy||p==='question_open'||p==='finished'||p==='lobby';$('#pauseQuizBtn').textContent=p==='paused'?'Retomar partida':'Pausar entre rounds';const emergency=$('#emergencyStopBtn');if(emergency){const pausedQuestion=p==='paused'&&roomState?.room?.paused_phase==='question_open';emergency.disabled=actionBusy||p==='lobby'||p==='finished'||(!pausedQuestion&&p!=='question_open');emergency.textContent=pausedQuestion?'RETOMAR PERGUNTA':'PARADA / CONGELAR';emergency.classList.toggle('resume',pausedQuestion);}$('#extend5Btn').disabled=actionBusy||!(p==='question_open'&&r?.accepting_responses);$('#extend10Btn').disabled=$('#extend5Btn').disabled;$('#annulRoundBtn').disabled=actionBusy||!(['result','finished'].includes(p)&&r?.status==='closed'&&!r.annulled);$('#regradeRoundBtn').disabled=actionBusy||!(['result','finished'].includes(p)&&r?.status==='closed');const revealStage=roomState?.room?.reveal_stage||'hidden',nextReveal={hidden:'answer',answer:'distribution',distribution:'ranking'}[revealStage]||null;$$('[data-reveal]').forEach(b=>b.disabled=actionBusy||p!=='result'||b.dataset.reveal!==nextReveal);$('#createRoomBtn').disabled=actionBusy;$('#createRoomBtn').textContent=room?'Criar outra sala':'Criar sala';const fin=$('#finishedGameActions');if(fin)fin.classList.toggle('hidden',p!=='finished');const fullRankBtn=$('#toggleFullRankingBtn');if(fullRankBtn)fullRankBtn.textContent=roomSettings().display_full_ranking?'Mostrar somente Top 10':'Mostrar classificação completa';renderFinalShowControls();updateRemoteAvailability();renderRemoteControl();renderContextAction();renderControllerState();}
function renderTimer(){const el=$('#adminTimer'),r=roomState?.round,p=phase();if(!room){el.textContent='Aguardando início';return;}if(p==='lobby'){el.textContent='Lobby aberto';el.className='round-clock';return;}if(p==='preparing'){const remain=Math.max(0,serverRemaining(roomState.room.prepared_until,serverOffset));el.textContent=`Prepare-se • ${Math.max(1,Math.ceil(remain/1000))}`;el.className='round-clock live';maybeAutoOpen();return;}if(p==='paused'){const restore=roomState?.room?.paused_phase,ms=Number(roomState?.room?.paused_remaining_ms||0);el.textContent=restore==='question_open'?`PAUSADO • ${(ms/1000).toFixed(ms<10000?1:0)}s preservados`:restore==='preparing'?`PAUSADO • contagem preservada`:'PAUSADO';el.className='round-clock closed';return;}if(p==='finished'){el.textContent='Quiz encerrado';el.className='round-clock closed';return;}if(!r){el.textContent='Sincronizando';return;}if(r.status!=='open'){el.textContent=`Round ${r.round_no} encerrado`;el.className='round-clock closed';return;}const remain=serverRemaining(r.closes_at,serverOffset);el.textContent=remain<=0?`Round ${r.round_no} • TEMPO ESGOTADO`:`Round ${r.round_no} • ${(remain/1000).toFixed(remain<10000?1:0)}s`;el.className=remain<=5000?'round-clock expired':'round-clock live';if(remain<=0&&roomSettings().auto_close_time_expired&&!autoClosing&&controllerGranted){autoClosing=true;diag('auto','Tempo esgotado: encerramento automático acionado',{round:r.round_no});closeRound().finally(()=>autoClosing=false);}}
function startTimerLoop(){clearInterval(timerTick);timerTick=setInterval(()=>{renderTimer();renderRemoteTimer();renderContextAction();},200);}

function participantIsOnline(p,now=Date.now()){return now-Date.parse(p?.last_seen_at||0)<90000;}
function renderParticipantList(){const host=$('#participantAdminList');if(!host)return;const now=Date.now(),fmtSeen=v=>{const ms=now-Date.parse(v||0);if(!Number.isFinite(ms)||ms<0)return'sem heartbeat';if(ms<60000)return`visto há ${Math.max(1,Math.round(ms/1000))}s`;if(ms<3600000)return`visto há ${Math.round(ms/60000)}min`;return`visto ${new Date(v).toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'})}`;},rows=participants.filter(p=>{const online=participantIsOnline(p,now);if(participantFilter==='online')return online&&!p.kicked;if(participantFilter==='offline')return !online&&!p.kicked;if(participantFilter==='ready')return !!p.ready&&!p.kicked;if(participantFilter==='issues')return !p.kicked&&(!online||(phase()==='lobby'&&!p.ready));return true;});if($('#participantFilterCount'))$('#participantFilterCount').textContent=`${rows.length}/${participants.length}`;host.innerHTML=rows.map(p=>{const online=participantIsOnline(p,now);return`<div class="participant-admin-row ${p.kicked?'kicked':''} ${p.ready?'is-ready':''}" data-id="${p.id}"><span class="presence-dot ${online?'online':'offline'}"></span><span class="participant-avatar">${avatarMarkup(p.avatar_key||'scientist_m',{compact:true,animated:online})}</span><strong>${esc(p.display_name)}</strong><span class="participant-state ${p.ready?'ready':''}">${p.ready?'PRONTO':'AGUARDANDO'}</span><b class="participant-points">${Number(p.total_points)||0} pts</b><small class="participant-diagnostics">${Number(p.answer_count)||0} resp • ${Number(p.missed_count)||0} perd. • ${fmtSeen(p.last_seen_at)} • 🔥 ${Number(p.current_streak)||0}</small><div class="participant-admin-actions participant-desktop-actions"><button class="ghost small" data-detail>Detalhes</button><button class="ghost small" data-kick ${p.kicked?'disabled':''}>Remover</button></div><details class="participant-mobile-actions"><summary aria-label="Ações de ${esc(p.display_name)}">⋯</summary><div><button class="ghost small" data-detail>Detalhes</button><button class="ghost small" data-kick ${p.kicked?'disabled':''}>Remover</button></div></details></div>`;}).join('')||'<div class="empty">Nenhum participante neste filtro.</div>';$$('[data-detail]').forEach(b=>b.addEventListener('click',()=>{const p=participants.find(x=>x.id===b.closest('[data-id]').dataset.id);if(!p)return;alert(`${p.display_name}\n\nPontos: ${Number(p.total_points)||0}\nRespostas: ${Number(p.answer_count)||0}\nRounds perdidos: ${Number(p.missed_count)||0}\nStreak atual: ${Number(p.current_streak)||0}\nMelhor streak: ${Number(p.best_streak)||0}\nPronto: ${p.ready?'SIM':'NÃO'}\nÚltimo heartbeat: ${p.last_seen_at?new Date(p.last_seen_at).toLocaleString('pt-BR'):'sem registro'}\nStatus: ${p.kicked?'REMOVIDO':(participantIsOnline(p)?'CONECTADO':'DESCONECTADO')}`);}));$$('[data-kick]').forEach(b=>b.addEventListener('click',()=>kickParticipant(b.closest('[data-id]').dataset.id)));}
async function loadParticipants(){if(!room)return;const{data,error}=await db.rpc('admin_list_participants',{p_room_id:room.id});if(error)return;participants=data||[];renderParticipantList();}
async function kickParticipant(id){if(!confirm('Remover e bloquear este participante nesta sala?'))return;const{error}=await db.rpc('admin_kick_participant',{p_room_id:room.id,p_participant_id:id,p_block:true});if(error)return alert(error.message);await Promise.all([loadParticipants(),refreshState(true)]);}
async function loadHistory(){if(!room)return;const{data,error}=await db.rpc('admin_get_round_history',{p_room_id:room.id});if(error)return;historyRows=data||[];const answered=historyRows.filter(x=>x.choice_value!==null||x.numeric_value!==null).length,missed=historyRows.length-answered;$('#historySummary').innerHTML=`<span><b>${historyRows.length}</b> registros</span><span><b>${answered}</b> respostas</span><span><b>${missed}</b> rounds sem resposta</span>`;}
function showEvolution(){if(!historyRows.length)return;const rounds=[...new Set(historyRows.map(x=>Number(x.round_no)))].filter(Number.isFinite).sort((a,b)=>a-b),names=[...new Set(historyRows.map(x=>x.display_name))].slice(0,10),maxPos=Math.max(1,...historyRows.map(x=>Number(x.current_position)||0)),w=Math.max(720,rounds.length*84),h=360,padL=54,padR=20,padT=24,padB=44,x=r=>rounds.length<2?padL+(w-padL-padR)/2:padL+(rounds.indexOf(r)/(rounds.length-1))*(w-padL-padR),y=pos=>padT+((Math.max(1,pos)-1)/Math.max(1,maxPos-1))*(h-padT-padB),series=names.map((name,i)=>{const pts=rounds.map(r=>{const row=historyRows.find(v=>Number(v.round_no)===r&&v.display_name===name),pos=Number(row?.current_position);return Number.isFinite(pos)&&pos>0?{r,pos}:null;}).filter(Boolean);return{name,i,pts};}),grid=[1,...Array.from({length:Math.min(4,maxPos-1)},(_,i)=>Math.round(1+(i+1)*(maxPos-1)/Math.min(4,maxPos-1)))].filter((v,i,a)=>a.indexOf(v)===i);$('#evolutionChart').classList.remove('hidden');$('#evolutionChart').innerHTML=`<div class="evolution-legend">${series.map((s,i)=>`<span class="evo-series-${(i%6)+1}"><i></i>${esc(s.name)}</span>`).join('')}</div><div class="evolution-svg-wrap"><svg class="evolution-svg" viewBox="0 0 ${w} ${h}" role="img" aria-label="Evolução de posição por round">${grid.map(v=>`<g><line x1="${padL}" y1="${y(v)}" x2="${w-padR}" y2="${y(v)}" class="evo-grid"/><text x="${padL-10}" y="${y(v)+4}" text-anchor="end">${v}º</text></g>`).join('')}${rounds.map(r=>`<g><line x1="${x(r)}" y1="${padT}" x2="${x(r)}" y2="${h-padB}" class="evo-vgrid"/><text x="${x(r)}" y="${h-15}" text-anchor="middle">R${r}</text></g>`).join('')}${series.map((s,i)=>`<g class="evo-series-${(i%6)+1}"><polyline points="${s.pts.map(p=>`${x(p.r)},${y(p.pos)}`).join(' ')}"/><g>${s.pts.map(p=>`<circle cx="${x(p.r)}" cy="${y(p.pos)}" r="5"><title>${esc(s.name)} • Round ${p.r}: ${p.pos}º</title></circle>`).join('')}</g></g>`).join('')}</svg></div>`;}
async function loadEventInsights(){if(!room)return null;const{data,error}=await db.rpc('admin_get_event_insights',{p_room_id:room.id});if(error){diag('error','Falha ao calcular desempenho das perguntas',{error:error.message});return null;}eventInsights=data||null;renderEventInsights();return eventInsights;}
function eventFunFacts(){const facts=[],mc=eventInsights?.most_correct,mw=eventInsights?.most_wrong,fc=eventInsights?.fastest_correct,climb=eventInsights?.biggest_climb,bal=eventInsights?.most_balanced;if(mw)facts.push(`🧠 A pergunta que derrubou a sala: R${mw.round_no} — ${Number(mw.accuracy_pct||0).toFixed(1)}% acertaram.`);if(mc){const a=Number(mc.accuracy_pct||0);facts.push(`${a>=100?'✨ Todo mundo sabia essa!':a>=90?'✨ Quase todo mundo sabia essa!':'✅ A mais certeira da partida:'} R${mc.round_no} — ${a.toFixed(1)}% de acerto.`);}if(fc)facts.push(`⚡ Resposta relâmpago: ${fc.display_name} em ${(Number(fc.response_ms||0)/1000).toFixed(2)} s no R${fc.round_no}.`);if(climb)facts.push(`🚀 Virada da partida: ${climb.display_name} subiu ${Number(climb.change||0)} posição(ões) no R${climb.round_no}.`);if(bal)facts.push(`⚖️ Pergunta mais equilibrada: R${bal.round_no} — ${Number(bal.balance_pct||0).toFixed(1)}% de equilíbrio.`);return facts.slice(0,5);}
function renderEventInsights(){const card=$('#eventInsightsCard');if(!card)return;const mc=eventInsights?.most_correct,mw=eventInsights?.most_wrong,fast=eventInsights?.fastest,slow=eventInsights?.slowest,ba=eventInsights?.best_accuracy,bs=eventInsights?.best_streak,climb=eventInsights?.biggest_climb,fc=eventInsights?.fastest_correct,bal=eventInsights?.most_balanced,sum=eventInsights?.summary||{},has=!!(mc||mw||fast||slow||ba||bs||climb||fc||bal);card.classList.toggle('hidden',!has);if(mc){$('#mostCorrectQuestion').textContent=`R${mc.round_no} • ${mc.prompt}`;$('#mostCorrectMetric').textContent=`${mc.correct_count}/${mc.answer_count} acertaram • ${Number(mc.accuracy_pct||0).toFixed(1)}%`;$('#mostCorrectDetail').textContent=`${mc.wrong_count} erraram`;}if(mw){$('#mostWrongQuestion').textContent=`R${mw.round_no} • ${mw.prompt}`;$('#mostWrongMetric').textContent=`${mw.wrong_count}/${mw.answer_count} erraram • ${Number(mw.accuracy_pct||0).toFixed(1)}% de acerto`;$('#mostWrongDetail').textContent=`${mw.correct_count} acertaram`;}if(fast){$('#fastestQuestion').textContent=`R${fast.round_no} • ${fast.prompt}`;$('#fastestMetric').textContent=`${(Number(fast.avg_response_ms||0)/1000).toFixed(1)} s em média`;}if(slow){$('#slowestQuestion').textContent=`R${slow.round_no} • ${slow.prompt}`;$('#slowestMetric').textContent=`${(Number(slow.avg_response_ms||0)/1000).toFixed(1)} s em média`;}if($('#insightPlayers'))$('#insightPlayers').textContent=Number(sum.participant_count||0);if($('#insightAnswers'))$('#insightAnswers').textContent=Number(sum.answer_count||0);if($('#insightAccuracy'))$('#insightAccuracy').textContent=`${Number(sum.accuracy_pct||0).toFixed(1)}%`;if($('#insightAvgTime'))$('#insightAvgTime').textContent=sum.avg_response_ms!=null?`${(Number(sum.avg_response_ms)/1000).toFixed(1)} s`:'—';if(ba){$('#bestAccuracyPlayer').textContent=ba.display_name||'—';$('#bestAccuracyMetric').textContent=`${ba.correct_count}/${ba.answer_count} • ${Number(ba.accuracy_pct||0).toFixed(1)}%`;}if(bs){$('#bestStreakPlayer').textContent=bs.display_name||'—';$('#bestStreakMetric').textContent=`${Number(bs.best_streak||0)} acertos seguidos`;}if(climb){$('#biggestClimbPlayer').textContent=climb.display_name||'—';$('#biggestClimbMetric').textContent=`+${Number(climb.change||0)} posições • R${climb.round_no}`;}if(fc){$('#fastestCorrectPlayer').textContent=fc.display_name||'—';$('#fastestCorrectMetric').textContent=`${(Number(fc.response_ms||0)/1000).toFixed(2)} s • R${fc.round_no}`;}if(bal){$('#mostBalancedQuestion').textContent=`R${bal.round_no} • ${bal.prompt}`;$('#mostBalancedMetric').textContent=`${Number(bal.balance_pct||0).toFixed(1)}% de equilíbrio`;}const fun=$('#eventFunFacts');if(fun)fun.innerHTML=eventFunFacts().map(x=>`<div>${esc(x)}</div>`).join('');}
async function exportReport(){if(!room)return alert('Crie/abra uma sala.');await Promise.all([loadHistory(),loadEventInsights()]);const head=['round','pergunta','categoria','dificuldade','jogador','resposta','tempo_ms','pontos','anulada'],lines=[head.join(';')];for(const x of historyRows){const ans=x.choice_value??x.numeric_value??'';lines.push([x.round_no,x.prompt,x.category,x.difficulty,x.display_name,ans,x.response_ms??'',x.awarded_points||0,x.annulled?'SIM':'NAO'].map(v=>`"${String(v??'').replaceAll('"','""')}"`).join(';'));}lines.push('','RESUMO DAS PERGUNTAS');for(const q of eventInsights?.rounds||[])lines.push(['ROUND '+q.round_no,q.prompt,`${q.correct_count} acertos`,`${q.wrong_count} erros`,`${q.answer_count} respostas`,`${Number(q.accuracy_pct||0).toFixed(1)}% acerto`,q.balance_pct!=null?`${Number(q.balance_pct).toFixed(1)}% equilíbrio`:``].map(v=>`"${String(v??'').replaceAll('"','""')}"`).join(';'));const add=(label,obj,extra='')=>{if(!obj)return;lines.push([label,obj.display_name||obj.prompt||'',obj.round_no?`R${obj.round_no}`:'',extra].map(v=>`"${String(v??'').replaceAll('"','""')}"`).join(';'));};lines.push('','DESTAQUES');add('MAIS ACERTADA',eventInsights?.most_correct,`${Number(eventInsights?.most_correct?.accuracy_pct||0).toFixed(1)}%`);add('MAIS ERRADA',eventInsights?.most_wrong,`${Number(eventInsights?.most_wrong?.accuracy_pct||0).toFixed(1)}% acerto`);add('MAIS RÁPIDA',eventInsights?.fastest,`${eventInsights?.fastest?.avg_response_ms||0} ms média`);add('MAIS DEMORADA',eventInsights?.slowest,`${eventInsights?.slowest?.avg_response_ms||0} ms média`);add('MELHOR PRECISÃO',eventInsights?.best_accuracy,`${Number(eventInsights?.best_accuracy?.accuracy_pct||0).toFixed(1)}%`);add('MAIOR SEQUÊNCIA',eventInsights?.best_streak,`${Number(eventInsights?.best_streak?.best_streak||0)} acertos`);add('MAIOR SUBIDA',eventInsights?.biggest_climb,`+${Number(eventInsights?.biggest_climb?.change||0)} posições`);add('RESPOSTA RELÂMPAGO',eventInsights?.fastest_correct,`${eventInsights?.fastest_correct?.response_ms||0} ms`);add('MAIS EQUILIBRADA',eventInsights?.most_balanced,`${Number(eventInsights?.most_balanced?.balance_pct||0).toFixed(1)}%`);lines.push('','RESUMO DIVERTIDO',...eventFunFacts().map(x=>`"${String(x).replaceAll('"','""')}"`));downloadText(`QuizRounds_relatorio_${room.code}.csv`,lines.join('\n'));}
async function loadAudit(){if(!room)return;const{data,error}=await db.rpc('admin_list_audit',{p_room_id:room.id,p_limit:60});if(error)return;$('#auditList').innerHTML=(data||[]).map(x=>`<div class="audit-row"><time>${new Date(x.created_at).toLocaleTimeString('pt-BR')}</time><strong>${esc(x.action)}</strong><span>${esc(JSON.stringify(x.details||{}))}</span></div>`).join('')||'<div class="empty">Sem eventos.</div>';}
function jitterDelay(ms,spread=.22){return Math.max(700,Math.round(ms*(1+((Math.random()*2)-1)*spread)));}
function setPoll(ms){clearTimeout(poll);const tick=async()=>{await refreshState(false);poll=setTimeout(tick,jitterDelay(ms));};poll=setTimeout(tick,jitterDelay(ms));clearInterval(auditTick);auditTick=setInterval(()=>Promise.all([loadAudit(),loadParticipants()]),jitterDelay(Math.max(7000,ms*2),.15));}
function scheduleReconnect(epoch=subscriptionEpoch){
  if(epoch!==subscriptionEpoch)return;
  if(reconnectTimer)return;
  reconnectAttempt=Math.min(reconnectAttempt+1,6);
  conn(navigator.onLine?'fallback':'offline',navigator.onLine?'sincronização por segurança':'aguardando internet');
  setPoll(Math.min(12000,POLL_FALLBACK*(2**Math.max(0,reconnectAttempt-1))));
  reconnectTimer=setTimeout(()=>{reconnectTimer=null;if(epoch===subscriptionEpoch)subscribe();},Math.min(15000,700*(2**(reconnectAttempt-1))));
}
function applyAnswerProgress(payload){if(!roomState?.round||payload?.round_id!==roomState.round.id||progressRefreshTimer)return;progressRefreshTimer=setTimeout(async()=>{progressRefreshTimer=null;await refreshState(false);},500);}
async function runConnectionTest(){if(!room||!channel)return alert('Abra uma sala e aguarde a conexão.');connectionTestNonce=`ct-${Date.now()}-${Math.random().toString(36).slice(2)}`;connectionAcks=new Set();const out=$('#connectionTestResult');out.textContent='Testando…';await channel.send({type:'broadcast',event:'connection_test',payload:{nonce:connectionTestNonce,at:Date.now()}});setTimeout(()=>{const online=Number(roomState?.active_count||presenceOnline||0);out.textContent=`${connectionAcks.size}/${online||roomState?.participant_count||0} responderam`;out.className=`badge ${connectionAcks.size>=Math.max(1,online)?'ready':'neutral'}`;},4000);}
async function subscribe(){
  if(!room)return;
  const epoch=++subscriptionEpoch;
  clearTimeout(reconnectTimer);reconnectTimer=null;
  const oldChannel=channel,oldProgress=progressChannel;
  channel=null;progressChannel=null;
  if(oldChannel)try{await db.removeChannel(oldChannel);}catch{}
  if(oldProgress)try{await db.removeChannel(oldProgress);}catch{}
  if(epoch!==subscriptionEpoch)return;
  conn('connecting');
  const progress=db.channel(`quiz-admin:${room.id}`,{config:{private:true}})
    .on('broadcast',{event:'response_progress'},({payload})=>{if(epoch===subscriptionEpoch)applyAnswerProgress(payload);});
  progressChannel=progress;
  progress.subscribe(status=>{
    if(epoch!==subscriptionEpoch||progress!==progressChannel)return;
    if(['CHANNEL_ERROR','TIMED_OUT'].includes(status))scheduleReconnect(epoch);
  });
  const main=db.channel(`quiz:${room.id}`,{config:{private:true,presence:{key:`admin-${controllerDeviceToken()}`}}})
    .on('broadcast',{event:'state_changed'},async()=>{if(epoch!==subscriptionEpoch)return;await Promise.all([refreshState(true),loadQueue(),loadAudit(),loadParticipants()]);})
    .on('broadcast',{event:'connection_ack'},({payload})=>{if(epoch!==subscriptionEpoch)return;if(connectionTestNonce&&payload?.nonce===connectionTestNonce){connectionAcks.add(payload.participant_id||payload.user_id||Math.random().toString());const el=$('#connectionTestResult');if(el)el.textContent=`${connectionAcks.size} resposta(s) ao teste`;}})
    .on('presence',{event:'sync'},()=>{if(epoch!==subscriptionEpoch||main!==channel)return;const state=main.presenceState()||{},ps=Object.values(state).flat(),playerMap=new Map();for(const [presenceKey,metas] of Object.entries(state)){for(const meta of Array.isArray(metas)?metas:[]){if(meta?.kind==='participant'||meta?.participant_id)playerMap.set(String(meta.participant_id||presenceKey),meta?.build||meta?.version||'antiga');}}presenceOnline=playerMap.size;displayOnline=ps.some(x=>x?.kind==='display'||x?.display_id);presenceVersions={players:[...playerMap.values()],displays:ps.filter(x=>x?.kind==='display'||x?.display_id).map(x=>x?.build||x?.version||'antiga'),admins:ps.filter(x=>x?.kind==='admin').map(x=>x?.build||x?.version||'antiga')};versionMismatch=[...presenceVersions.players,...presenceVersions.displays,...presenceVersions.admins].some(v=>String(v)!==BUILD_ID);if(versionMismatch&&lastVersionBroadcast!==BUILD_ID){lastVersionBroadcast=BUILD_ID;main.send({type:'broadcast',event:'version_required',payload:{version:APP_VERSION,build:BUILD_ID}}).catch(()=>{});}if(!versionMismatch)lastVersionBroadcast='';updateLiveStats(roomState);renderRemoteControl();renderEventHealth();});
  channel=main;
  main.subscribe(async status=>{
    if(epoch!==subscriptionEpoch||main!==channel)return;
    if(status==='SUBSCRIBED'){
      clearTimeout(reconnectTimer);reconnectTimer=null;reconnectAttempt=0;conn('connected');setPoll(POLL_CONNECTED);try{await main.track({kind:'admin',version:BUILD_ID,build:BUILD_ID,device_label:controllerDeviceLabel(),at:Date.now()});}catch{}await refreshState(true);return;
    }
    if(['CHANNEL_ERROR','TIMED_OUT'].includes(status))scheduleReconnect(epoch);
    if(status==='CLOSED'&&navigator.onLine)scheduleReconnect(epoch);
  });
}


function controllerDeviceToken(){
  try{let token=localStorage.getItem(CONTROLLER_DEVICE_KEY)||'';if(token.length<20){token=crypto.randomUUID?.()||`${Date.now()}-${Math.random()}-${Math.random()}`;localStorage.setItem(CONTROLLER_DEVICE_KEY,token);}return token;}catch{return crypto.randomUUID?.()||`${Date.now()}-${Math.random()}`;}
}
function controllerDeviceLabel(){const ua=navigator.userAgent||'';if(/iPhone|Android.+Mobile/i.test(ua))return'Painel ADM no celular';if(/iPad|Android/i.test(ua))return'Painel ADM no tablet';return'Painel ADM principal';}
function renderControllerState(){const banner=$('#controllerConflictBanner');document.body.classList.toggle('controller-observer',!!room&&!remoteModeActive&&!controllerGranted);if(!banner)return;banner.classList.toggle('hidden',!room||controllerGranted||remoteModeActive);if(!controllerGranted&&room){$('#controllerConflictText').textContent=controllerConflictLabel?`${controllerConflictLabel} está comandando esta sala. Este painel continua acompanhando ao vivo.`:'Outro painel está comandando esta sala. Este painel continua acompanhando ao vivo.';}const tile=$('#healthController');if(tile)setHealthTile(tile,controllerGranted||remoteModeActive?'ready':'fail',controllerGranted||remoteModeActive?'Principal':'Somente leitura','Painel de comandos');}
async function claimController(force=false){
  if(!room||wantsRemoteFromUrl()){controllerGranted=true;renderControllerState();return true;}
  clearInterval(controllerHeartbeatTimer);controllerHeartbeatTimer=null;
  const{data,error}=await db.rpc('admin_claim_controller',{p_room_id:room.id,p_device_token:controllerDeviceToken(),p_device_label:controllerDeviceLabel(),p_force:!!force});
  if(error){controllerGranted=false;controllerConflictLabel='Falha ao reservar controle';renderControllerState();return false;}
  controllerGranted=!!data?.granted;controllerConflictLabel=data?.device_label||'';renderControllerState();
  if(controllerGranted)controllerHeartbeatTimer=setInterval(controllerHeartbeat,12000);
  updateControls();renderEventHealth();return controllerGranted;
}
async function controllerHeartbeat(){if(!room||remoteModeActive||!controllerGranted)return;const{data,error}=await db.rpc('admin_controller_heartbeat',{p_room_id:room.id,p_device_token:controllerDeviceToken()});if(error||!data?.granted){controllerGranted=false;controllerConflictLabel='Outro painel assumiu o controle';clearInterval(controllerHeartbeatTimer);controllerHeartbeatTimer=null;renderControllerState();updateControls();}}
async function takeOverController(){if(!room)return;if(!confirm('Assumir o controle principal neste aparelho? O outro painel ficará somente acompanhando após a próxima sincronização.'))return;await claimController(true);}
function initEventMode(){try{eventModeActive=localStorage.getItem('quiz2EventMode:v1')==='1';}catch{}applyEventMode();}
function applyEventMode(){document.body.classList.toggle('event-mode',eventModeActive);const b=$('#eventModeBtn');if(b)b.textContent=eventModeActive?'Sair do modo Evento':'Modo Evento';if(eventModeActive)switchAdminTab('presentation');}
function toggleEventMode(){eventModeActive=!eventModeActive;try{localStorage.setItem('quiz2EventMode:v1',eventModeActive?'1':'0');}catch{}applyEventMode();}
function setHealthTile(el,state,strong,small){if(!el)return;el.className=`health-tile ${state}`;el.querySelector('strong').textContent=strong;el.querySelector('small').textContent=small;}
function renderEventHealth(){
  const supabaseOk=!!roomState&&lastLatency>=0,realtimeOk=lastConnectionKey.startsWith('connected'),players=Number(presenceOnline??roomState?.active_count??0),questions=Number(roomState?.queued_count??queueRows.filter(q=>q.status==='queued').length);
  setHealthTile($('#healthSupabase'),supabaseOk?(lastLatency<1200?'ready':'warn'):'fail',supabaseOk?`${lastLatency} ms`:'Sem resposta','Banco e RPCs');
  setHealthTile($('#healthRealtime'),realtimeOk?'ready':navigator.onLine?'warn':'fail',realtimeOk?'Conectado':navigator.onLine?'Reconectando':'Sem internet','Sincronização ao vivo');
  setHealthTile($('#healthDisplay'),displayOnline?'ready':'warn',displayOnline?'Conectado':'Não detectado','Projetor / telão');
  setHealthTile($('#healthPlayers'),players>0?'ready':'warn',`${players} conectado${players===1?'':'s'}`,`${Number(roomState?.ready_count||0)} pronto(s) • ${Number(roomState?.participant_count||0)} cadastrado(s)`);
  setHealthTile($('#healthQuestions'),questions>0?'ready':'fail',`${questions} pronta${questions===1?'':'s'}`,'Fila da partida');
  setHealthTile($('#healthRemote'),remoteDeviceCount>0?'ready':'warn',remoteDeviceCount>0?`${remoteDeviceCount} autorizado${remoteDeviceCount===1?'':'s'}`:'Opcional',remoteDeviceCount>0?'Controle remoto disponível':'Autorize o celular se quiser');
  const count=(presenceVersions.players.length+presenceVersions.displays.length+presenceVersions.admins.length)||1;setHealthTile($('#healthVersions'),versionMismatch?'fail':'ready',versionMismatch?'Versão diferente detectada':`${BUILD_ID} • ${count} aparelho${count===1?'':'s'}`,versionMismatch?'Recarregue os aparelhos desatualizados':'ADM, telão e jogadores compatíveis');
  const vb=$('#appVersionBadge');if(vb)vb.className=`badge version-badge ${versionMismatch?'warn':'ready'}`;renderControllerState();
  if($('#displayBtn'))$('#displayBtn').textContent=displayOnline?'Abrir telão / projetor':'Reabrir telão / projetor';renderAdminStatusBar();renderDiagnostics();
}
function buildRevision(value=''){const m=String(value||'').match(/-r(\d+)$/i);return m?Number(m[1]):0;}
async function checkBackendCompatibility({announce=false}={}){
  try{
    const{data,error}=await db.rpc('get_quiz_backend_meta');
    const schema=Number(data?.schema_version||0),requiredBuild=String(data?.min_frontend_build||''),sameRelease=!data?.release||String(data.release).startsWith(`${APP_VERSION}-`),buildOk=!requiredBuild||buildRevision(BUILD_ID)>=buildRevision(requiredBuild);
    backendMeta=data||null;backendCompatible=!error&&schema>=BACKEND_SCHEMA_REQUIRED&&sameRelease&&buildOk;
    if(!backendCompatible){const reason=error?.message||`schema ${schema||0}; requerido ${BACKEND_SCHEMA_REQUIRED}; build mínimo ${requiredBuild||'não informado'}`;diag('error','Backend incompatível com esta versão',{reason,build:BUILD_ID});if(announce)alert(`QuizRounds ${BUILD_ID}: backend incompatível. Aplique a migration ${String(BACKEND_SCHEMA_REQUIRED).padStart(3,'0')} antes do evento.`);}
    else diag('ok','Backend compatível',{schema,release:data?.release||'',build:BUILD_ID});
    return{ok:backendCompatible,data,error};
  }catch(error){backendCompatible=false;backendMeta=null;diag('error','Não foi possível verificar a versão do backend',{error:error.message||String(error)});if(announce)alert(`Não foi possível validar o backend. A migration ${String(BACKEND_SCHEMA_REQUIRED).padStart(3,'0')} é obrigatória.`);return{ok:false,error};}
}
async function runPreflight({silent=false}={}){
  if(!room){lastPreflight={all:false,hard:false,issues:['sala']};if(!silent)alert('Crie uma sala antes do pré-teste.');return lastPreflight;}
  const summary=$('#preflightSummary');if(summary){summary.className='preflight-summary neutral';summary.textContent='Executando pré-teste…';}
  const backend=await checkBackendCompatibility();let rpcOk=false,lat=0;try{const t0=performance.now();const{data,error}=await db.rpc('admin_get_room_state',{p_room_id:room.id});lat=Math.round(performance.now()-t0);rpcOk=!error&&!!data;if(rpcOk){roomState=data;lastLatency=lat;}}catch{}
  const backendOk=!!backend.ok,realtimeOk=lastConnectionKey.startsWith('connected'),displayOk=!!displayOnline,questionsOk=Number(roomState?.queued_count??queueRows.filter(q=>q.status==='queued').length)>0,controllerOk=controllerGranted||remoteModeActive,versionsOk=!versionMismatch,issues=[];
  if(!backendOk)issues.push(`backend schema ${BACKEND_SCHEMA_REQUIRED}`);if(!rpcOk)issues.push('Supabase');if(!realtimeOk)issues.push('Realtime');if(!displayOk)issues.push('telão');if(!questionsOk)issues.push('perguntas');if(!controllerOk)issues.push('controlador');if(!versionsOk)issues.push('versões diferentes');
  const hard=backendOk&&rpcOk&&realtimeOk&&questionsOk&&controllerOk&&versionsOk,all=hard&&displayOk;lastPreflight={all,hard,issues,latency:lat,backend:backend.data||null};renderEventHealth();
  if(summary){summary.className=`preflight-summary ${all?'ready':hard?'warn':'fail'}`;summary.textContent=all?'PRONTO PARA INICIAR • todos os sistemas verificados':hard?`PRONTO COM ALERTA • ${issues.join(', ')}`:`NÃO INICIAR • corrija ${issues.join(', ')}`;}
  return lastPreflight;
}
function openLoadSimulator(count,{full=false}={}){const u=new URL('simulator.html',location.href);u.searchParams.set('bots',String(count));u.searchParams.set('autorun','1');u.searchParams.set('from','admin');if(full)u.searchParams.set('fulltest','1');window.open(u.href,full?'quiz2_full_test':'quiz2_load_simulator');diag('test',full?'Teste completo automático aberto':`Simulador de ${count} jogadores aberto`,{players:count});}
function renderContextAction(){
  const b=$('#contextPrimaryBtn'),hint=$('#contextActionHint');if(!b||!hint)return;const p=phase(),r=roomState?.round,stage=roomState?.room?.reveal_stage||'hidden',used=Number(roomState?.used_rounds||0),target=Number(roomState?.room?.planned_rounds||0),queued=Number(roomState?.queued_count||0);let label='Aguardando',text='Sincronizando o estado da partida.',enabled=false;
  if(!room){label='Crie uma sala';text='Configure a partida antes de iniciar.';}
  else if(!controllerGranted&&!remoteModeActive){label='Somente acompanhamento';text='Assuma o controle principal para liberar os comandos.';}
  else if(p==='lobby'){label='INICIAR QUIZ';text='Executa o pré-teste e inicia a contagem do primeiro round.';enabled=queueRows.length>0;}
  else if(p==='preparing'){const remain=Math.max(0,serverRemaining(roomState?.room?.prepared_until,serverOffset));label=remain>0?`LIBERAR EM ${Math.max(1,Math.ceil(remain/1000))} s`:'LIBERAR PERGUNTA';text='A contagem é baseada no horário do servidor.';enabled=remain<=0;}
  else if(p==='question_open'){label='ENCERRAR RESPOSTAS E PONTUAR';text=`${Number((roomState?.eligible_answer_count??roomState?.answer_count)??0)} de ${Number(roomState?.eligible_count||roomState?.participant_count||0)} elegíveis responderam.`;enabled=!!r?.status;}
  else if(p==='paused'){label=roomState?.room?.paused_phase==='question_open'?'RETOMAR PERGUNTA':'RETOMAR PARTIDA';text='O tempo restante foi preservado no servidor.';enabled=true;}
  else if(p==='result'&&stage==='hidden'){label='MOSTRAR RESPOSTA';text='Revela o gabarito somente quando você decidir.';enabled=true;}
  else if(p==='result'&&stage==='answer'){label='MOSTRAR DISTRIBUIÇÃO';text='Mostra como os participantes responderam.';enabled=true;}
  else if(p==='result'&&stage==='distribution'){label='MOSTRAR RANKING';text='Revela o ranking atualizado e as mudanças de posição.';enabled=true;}
  else if(p==='result'&&stage==='ranking'){const complete=quizPresentationComplete();label=complete?'MOSTRAR RESULTADO FINAL':queued>0?'PRÓXIMO ROUND':'SINCRONIZAR FINAL';text=complete?'Mostra campeão e classificação final no telão.':queued>0?'Prepara a próxima pergunta com contagem sincronizada.':'A fila terminou; sincronize para concluir a apresentação.';enabled=complete||queued>0;}
  else if(p==='result'){label='MOSTRAR RESPOSTA';text='Inicia a sequência de revelação do resultado.';enabled=true;}
  else if(p==='finished'){const next=nextFinalShowStage();label=next==='stats'?'MOSTRAR ESTATÍSTICAS':next==='highlights'?'MOSTRAR DESTAQUES':next==='champion'?'MOSTRAR CAMPEÃO':'VOLTAR AO RANKING FINAL';text=`No telão agora: ${finalShowLabel()}.`;enabled=true;}
  b.textContent=label;b.disabled=actionBusy||!enabled;hint.textContent=text;
}
async function contextPrimaryAction(){const p=phase(),stage=roomState?.room?.reveal_stage||'hidden',used=Number(roomState?.used_rounds||0),target=Number(roomState?.room?.planned_rounds||0);if(p==='lobby')return startQuiz();if(p==='preparing')return openPreparedRound();if(p==='question_open')return closeRound();if(p==='paused')return pauseQuiz();if(p==='result'&&stage==='hidden')return reveal('answer');if(p==='result'&&stage==='answer')return reveal('distribution');if(p==='result'&&stage==='distribution')return reveal('ranking');if(p==='result'&&stage==='ranking')return quizPresentationComplete()?reveal('final'):maybeScheduledBreakOrPrepare();if(p==='finished')return setFinalShowStage(nextFinalShowStage());}
async function emergencyStopAction(){if(!room)return;if(phase()==='question_open'&&!confirm('Congelar a pergunta agora? O tempo restante será preservado e nenhuma nova resposta será aceita até retomar.'))return;await pauseQuiz();}
async function toggleFullRanking(){if(!room)return;const enabled=!roomSettings().display_full_ranking;await withAction(enabled?'Mostrando classificação completa…':'Voltando ao Top 10…',async()=>{const{error}=await db.rpc('admin_update_room_settings',{p_room_id:room.id,p_patch:{display_full_ranking:enabled}});if(error)throw error;await refreshState(true);});}
function newRoomAfterGame(){switchAdminTab('config');setConfigPane('room');eventModeActive=false;try{localStorage.setItem('quiz2EventMode:v1','0');}catch{}applyEventMode();$('#roomTitle')?.focus();$('#createRoomBtn')?.scrollIntoView({behavior:'smooth',block:'center'});}


function journeyGo(step){if(step==='room'){switchAdminTab('config');setConfigPane('room',{scroll:true});}else if(step==='questions'){switchAdminTab('questions');setQuestionPane('bank',{scroll:true});}else if(step==='rules'){switchAdminTab('config');setConfigPane('rules',{scroll:true});}else if(step==='review'){switchAdminTab('central');setTimeout(()=>$('#setupReviewCard')?.scrollIntoView({behavior:'smooth',block:'start'}),50);renderSetupReview();}else if(step==='lobby'){switchAdminTab('presentation');setTimeout(()=>$('#adminLobbyCode')?.scrollIntoView({behavior:'smooth',block:'center'}),50);}}
function setupChecks(){const duplicateIds=queueRows.map(x=>x.question_id).filter((v,i,a)=>a.indexOf(v)!==i),invalid=queueRows.filter(q=>!q.prompt||!q.question_type||q.question_type==='choice'&&![4,5].includes(Array.isArray(q.options)?q.options.length:Number(q.options_snapshot?.length||0))),checks=[{ok:!!room,label:'Sala criada',detail:room?`PIN ${room.code}`:'Crie a sala'},{ok:queueRows.length>0,label:'Perguntas selecionadas',detail:`${queueRows.length} na playlist`},{ok:duplicateIds.length===0,label:'Sem duplicações',detail:duplicateIds.length?`${duplicateIds.length} repetida(s)`:'Fila limpa'},{ok:invalid.length===0,label:'Perguntas válidas',detail:invalid.length?`${invalid.length} revisar`:'Gabaritos/alternativas OK'},{ok:!!room&&Number(roomSettings().default_time||30)>=5,label:'Regras configuradas',detail:`${roomSettings().default_time||30}s padrão • ${roomSettings().default_points||100} pts`}];return checks;}
function renderSetupReview(){const list=$('#setupReviewList');if(!list)return;const checks=setupChecks(),done=checks.filter(x=>x.ok).length;list.innerHTML=checks.map(x=>`<div class="setup-review-row ${x.ok?'ok':'warn'}"><span>${x.ok?'✓':'!'}</span><div><strong>${esc(x.label)}</strong><small>${esc(x.detail)}</small></div></div>`).join('');$('#setupReadinessBadge').textContent=`${done}/${checks.length}`;$('#setupReadinessBadge').className=`badge ${done===checks.length?'ready':'neutral'}`;$('#setupReviewSummary').textContent=done===checks.length?'Preparação consistente. Abra o lobby e execute o pré-teste antes de iniciar.':`Faltam ${checks.length-done} verificação(ões) para a preparação ficar completa.`;$('#openLobbyFromReviewBtn').disabled=done!==checks.length;$$('#setupJourney [data-journey-step]').forEach((b,i)=>{const completed=i===0?!!room:i===1?queueRows.length>0:i===2?!!room:i===3?done===checks.length:false;b.classList.toggle('done',completed);});if($('#centralContinueHint'))$('#centralContinueHint').textContent=room?`${room.title} • ${statusLabel(phase())}`:'Nenhuma sala ativa';}
function renderBuildSummary(){const box=$('#eventBuildSummary');if(!box)return;box.classList.toggle('hidden',!room);if(!room)return;const active=queueRows,secs=active.reduce((n,q)=>n+Number(q.time_limit_seconds||q.time_limit_snapshot||30),0)+active.length*12,points=active.reduce((n,q)=>n+(q.score_enabled===false?0:Number(q.points||q.points_snapshot||0)),0),diffs={facil:0,medio:0,dificil:0,final:0};active.forEach(q=>diffs[q.difficulty||q.difficulty_snapshot||'medio']=(diffs[q.difficulty||q.difficulty_snapshot||'medio']||0)+1);$('#buildSummaryTitle').textContent=room.title||'Quiz';$('#buildSummaryQuestions').textContent=active.length;$('#buildSummaryDuration').textContent=`~${Math.max(1,Math.round(secs/60))} min`;$('#buildSummaryPoints').textContent=points.toLocaleString('pt-BR');$('#buildSummaryDifficulty').textContent=`${diffs.facil}F • ${diffs.medio}M • ${diffs.dificil+diffs.final}D`;if($('#playlistSummary'))$('#playlistSummary').innerHTML=`<span>${active.length} perguntas</span><span>~${Math.max(1,Math.round(secs/60))} min</span><span>${points.toLocaleString('pt-BR')} pts</span>`;renderSetupReview();}
async function loadRecentRooms(){const host=$('#recentRoomsList');if(!host)return;const{data,error}=await db.rpc('admin_list_recent_rooms',{p_limit:8});if(error){host.innerHTML=`<div class="empty">${esc(error.message)}</div>`;return;}recentRooms=data||[];host.innerHTML=recentRooms.map(r=>`<button class="recent-room-item" data-room-id="${r.id}" type="button"><div><strong>${esc(r.title)}</strong><span>PIN ${esc(r.code)} • ${statusLabel(r.phase)}</span></div><div><b>${r.used_rounds}/${r.planned_rounds}</b><small>${r.participant_count} jogadores</small></div></button>`).join('')||'<div class="empty">Nenhuma partida anterior.</div>';host.querySelectorAll('[data-room-id]').forEach(b=>b.addEventListener('click',()=>resumeSpecificRoom(b.dataset.roomId)));}
async function resumeSpecificRoom(id){const{data,error}=await db.rpc('admin_get_room_by_id',{p_room_id:id});if(error||!data)return alert(error?.message||'Sala não encontrada.');room=data;rememberRoom();settingsDraftDirty=false;settingsDraftSerial=0;updateSettingsSaveIndicator('idle');roomState=null;queueRows=[];presenceOnline=null;displayOnline=false;lastAdminQr='';$('#plannedRounds').value=room.planned_rounds||10;$('#roomTitle').value=room.title||'Quiz ao vivo';await Promise.all([refreshState(true),loadQueue(),loadAudit(),loadParticipants(),loadHistory(),loadQuestions()]);await subscribe();await claimController(false);switchAdminTab(['question_open','preparing','result','paused','finished'].includes(phase())?'presentation':'central');actionToast('Partida recuperada ✓');}
async function loadQuestionCollections(){const sel=$('#collectionSelect');if(!sel)return;const{data,error}=await db.rpc('admin_list_question_collections');if(error)return;questionCollections=data||[];const current=sel.value;sel.innerHTML='<option value="">Selecione uma coleção...</option>'+questionCollections.map(c=>`<option value="${c.id}">${esc(c.name)} • ${c.question_count}</option>`).join('');if(questionCollections.some(c=>c.id===current))sel.value=current;}
async function saveQuestionCollection(){const ids=[...selectedQuestionIds];if(!ids.length)return alert('Selecione perguntas no banco.');const name=prompt('Nome da coleção:','Minha coleção');if(!name)return;const{error}=await db.rpc('admin_save_question_collection',{p_name:name,p_question_ids:ids});if(error)return alert(error.message);await loadQuestionCollections();actionToast('Coleção salva ✓');}
async function addQuestionIdsToRoom(ids){if(!room)return alert('Crie uma sala primeiro.');if(!canEditQueue())return alert('A fila está bloqueada após o início.');let available=Math.max(0,200-queueRows.length),added=0;const unique=ids.filter(id=>!queueRows.some(x=>String(x.question_id)===String(id))).slice(0,available),desired=Math.min(200,queueRows.length+unique.length),currentTarget=Number(roomState?.room?.planned_rounds||room.planned_rounds||plannedRounds());if(desired>currentTarget){const grow=await db.rpc('admin_update_planned_rounds',{p_room_id:room.id,p_planned_rounds:desired});if(grow.error)return alert(grow.error.message);}for(const id of unique){const{error}=await db.rpc('admin_queue_question',{p_room_id:room.id,p_question_id:id});if(!error)added++;}await Promise.all([loadQueue(),refreshState(true)]);if(added)actionToast(`${added} pergunta(s) adicionada(s) ✓`);return added;}
async function loadCollectionToRoom(){const id=$('#collectionSelect')?.value;if(!id)return alert('Selecione uma coleção.');const{data,error}=await db.rpc('admin_get_question_collection',{p_collection_id:id});if(error)return alert(error.message);await addQuestionIdsToRoom(data?.question_ids||[]);}
async function deleteQuestionCollection(){const id=$('#collectionSelect')?.value;if(!id)return;if(!confirm('Excluir esta coleção? As perguntas do banco não serão apagadas.'))return;const{error}=await db.rpc('admin_delete_question_collection',{p_collection_id:id});if(error)return alert(error.message);await loadQuestionCollections();actionToast('Coleção excluída');}
async function addRandomQuestions(count=10){const pool=visibleQuestionRows.filter(q=>!q.archived&&!queueRows.some(x=>String(x.question_id)===String(q.id)));for(let i=pool.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));[pool[i],pool[j]]=[pool[j],pool[i]];}await addQuestionIdsToRoom(pool.slice(0,count).map(q=>q.id));}
async function addCategoryQuestions(){const cats=[...new Set(questionBank.map(q=>q.category||'Geral'))].sort();const raw=prompt(`Digite a categoria:\n${cats.join(' • ')}`,$('#questionCategoryFilter')?.value||cats[0]||'Geral');if(!raw)return;await addQuestionIdsToRoom(questionBank.filter(q=>(q.category||'Geral').toLowerCase()===raw.trim().toLowerCase()&&!q.archived).map(q=>q.id));}
function setRulesMode(mode){rulesMode=mode==='advanced'?'advanced':'simple';document.body.dataset.rulesMode=rulesMode;$$('[data-rules-mode]').forEach(b=>b.classList.toggle('active',b.dataset.rulesMode===rulesMode));if($('#rulesModeHint'))$('#rulesModeHint').textContent=rulesMode==='simple'?'Somente as regras mais usadas.':'Todas as regras e controles de competição.';try{localStorage.setItem('quiz2RulesMode',rulesMode);}catch{}}
function initRulesMode(){let m='simple';try{m=localStorage.getItem('quiz2RulesMode')||'simple';}catch{}setRulesMode(m);}
function applySpecialPreset(kind){const base=Math.max(1,Number(roomSettings().default_points||$('#defaultPoints')?.value||100));if(kind==='normal'){$('#points').value=base;$('#qTiebreaker').checked=false;if($('#qDifficulty').value==='final')$('#qDifficulty').value='medio';}if(kind==='double'){$('#points').value=Math.max(base*2,Number($('#points').value)||0);$('#qTiebreaker').checked=false;}if(kind==='tiebreaker'){$('#qTiebreaker').checked=true;$('#points').value=Math.max(base,Number($('#points').value)||base);}if(kind==='final'){$('#qDifficulty').value='final';$('#points').value=Math.max(base*2,Number($('#points').value)||0);}updateQuestionPreview();haptic(25);}
function renderNextQuestionPreview(){const card=$('#nextQuestionPreviewCard');if(!card)return;const p=phase(),stage=roomState?.room?.reveal_stage||'hidden',show=p==='result'&&['answer','distribution','ranking'].includes(stage);const next=queueRows.find(q=>q.status==='queued');card.classList.toggle('hidden',!show||!next);if(show&&next){$('#nextQuestionTitle').textContent=next.prompt;$('#nextQuestionMeta').textContent=`${next.category||'Geral'} • ${next.difficulty||'medio'} • ${next.points||0} pts • ${next.time_limit_seconds||30}s`;$('#nextQuestionNote').textContent=next.presenter_notes||'Só o administrador vê esta prévia.';}}
async function maybeScheduledBreakOrPrepare(){const every=Math.max(0,Number(roomSettings().break_every||0)),used=Number(roomState?.used_rounds||0),last=Number(roomSettings().last_break_round||0);if(every>0&&used>0&&used%every===0&&last!==used){await withAction('Iniciando intervalo…',async()=>{const{error}=await db.rpc('admin_update_room_settings',{p_room_id:room.id,p_patch:{last_break_round:used}});if(error)throw error;const paused=await db.rpc('admin_pause_quiz',{p_room_id:room.id,p_pause:true});if(paused.error)throw paused.error;await refreshState(true);});return;}return prepareRound();}
function openNewGameFlow(){switchAdminTab('config');setConfigPane('room');$('#roomTitle')?.focus();}

$$('[data-config-jump]').forEach(b=>b.addEventListener('click',()=>jumpConfigBlock(b.dataset.configJump)));$('#reloadCurrentBuildBtn')?.addEventListener('click',()=>{const u=new URL(location.href);u.searchParams.set('build',BUILD_ID);u.searchParams.set('reload',String(Date.now()));location.replace(u.href);});$('#eventModeBtn').addEventListener('click',toggleEventMode);$('#takeOverControllerBtn').addEventListener('click',takeOverController);$('#runPreflightBtn').addEventListener('click',()=>runPreflight());$('#loadTest20Btn').addEventListener('click',()=>openLoadSimulator(20));$('#loadTest50Btn').addEventListener('click',()=>openLoadSimulator(50));$('#loadTest100Btn').addEventListener('click',()=>openLoadSimulator(100));$('#fullAutoTestBtn').addEventListener('click',()=>openLoadSimulator(100,{full:true}));$('#refreshInsightsBtn').addEventListener('click',loadEventInsights);$('#exportDiagnosticsBtn').addEventListener('click',exportDiagnostics);$('#contextPrimaryBtn').addEventListener('click',contextPrimaryAction);$('#emergencyStopBtn').addEventListener('click',emergencyStopAction);$('#toggleFullRankingBtn').addEventListener('click',toggleFullRanking);$('#samePlayersNewGameBtn').addEventListener('click',restartQuiz);$('#newRoomAfterGameBtn').addEventListener('click',newRoomAfterGame);
['#roomTitle','#plannedRounds','#expectedPlayers','#defaultTime','#defaultPoints','#breakEvery'].forEach(id=>$(id)?.addEventListener('input',()=>{renderBuildSummary();renderSetupReview();}));
$('#loginBtn')?.addEventListener('click',login);$('#email')?.addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();$('#password')?.focus();}});$('#password')?.addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();login();}});$('#logoutBtn').addEventListener('click',logout);$('#createRoomBtn').addEventListener('click',createRoom);$('#plannedRounds').addEventListener('change',updatePlannedRounds);$('#randomizeQueueToggle').addEventListener('change',updateRandomizeQueue);$('#shuffleQueueBtn').addEventListener('click',shuffleQueue);$('#saveRoomSettingsBtn').addEventListener('click',()=>saveRoomSettings(true));$('#themePreset').addEventListener('change',()=>applyAdminTheme($('#themePreset').value,normalizeLogoUrl($('#logoUrl').value.trim())));$('#logoUrl').addEventListener('input',previewLogoFromLink);$('#logoUrl').addEventListener('change',previewLogoFromLink);$('#logoFile')?.addEventListener('change',previewSelectedLogo);$('#uploadLogoBtn')?.addEventListener('click',uploadLogoFile);$('#clearLogoBtn')?.addEventListener('click',clearEventLogo);$('#saveTemplateBtn').addEventListener('click',saveTemplate);$('#loadTemplateBtn').addEventListener('click',useTemplate);$('#duplicateRoomBtn').addEventListener('click',duplicateRoom);$('#exportReportBtn').addEventListener('click',exportReport);
$('#saveQuestionBtn').addEventListener('click',saveQuestion);$('#newQuestionBtn').addEventListener('click',()=>{resetQuestionEditor();document.querySelector('.question-editor-scroll')?.scrollTo({top:0,behavior:'smooth'});});$('#resetQuestionBtn').addEventListener('click',()=>{if(editingQuestionId&&!confirm('Descartar a edição atual?'))return;resetQuestionEditor();});$('#cancelQuestionEditBtn').addEventListener('click',()=>resetQuestionEditor());
$('#refreshQuestionsBtn').addEventListener('click',loadQuestions);$('#questionScope').addEventListener('change',loadQuestions);['#questionSearch','#questionCategoryFilter','#questionDifficultyFilter','#questionUsageFilter','#questionOptionCountFilter','#questionSort'].forEach(id=>$(id)?.addEventListener(id==='#questionSearch'?'input':'change',renderQuestionBank));$('#clearQuestionFiltersBtn').addEventListener('click',clearQuestionFilters);$$('[data-bank-quick]').forEach(btn=>btn.addEventListener('click',()=>setBankQuickFilter(btn.dataset.bankQuick)));$('#selectVisibleQuestionsBtn').addEventListener('click',()=>{visibleQuestionRows.forEach(q=>selectedQuestionIds.add(String(q.id)));renderQuestionBank();});$('#clearQuestionSelectionBtn').addEventListener('click',()=>{selectedQuestionIds.clear();renderQuestionBank();});$('#queueSelectedQuestionsBtn').addEventListener('click',bulkQueueSelected);$('#archiveSelectedQuestionsBtn').addEventListener('click',()=>bulkSetArchived(true));$('#restoreSelectedQuestionsBtn').addEventListener('click',()=>bulkSetArchived(false));
$('#qType').addEventListener('change',()=>{const n=$('#qType').value==='numeric';$('#choiceFields').classList.toggle('hidden',n);$('#numericFields').classList.toggle('hidden',!n);updateQuestionPreview();});['#qPrompt','#optA','#optB','#optC','#optD','#optE','#correctChoice','#correctNumber','#points','#timeLimit','#qCategory','#qDifficulty','#qSpeedBonus','#qTiebreaker','#qScoreEnabled','#qPresenterNotes'].forEach(id=>$(id)?.addEventListener(['#qPrompt','#optA','#optB','#optC','#optD','#optE','#correctNumber','#points','#timeLimit','#qCategory','#qSpeedBonus','#qPresenterNotes'].includes(id)?'input':'change',updateQuestionPreview));$$('[data-points-preset]').forEach(btn=>btn.addEventListener('click',()=>{$('#points').value=btn.dataset.pointsPreset;updateQuestionPreview();}));$$('[data-time-preset]').forEach(btn=>btn.addEventListener('click',()=>{$('#timeLimit').value=btn.dataset.timePreset;updateQuestionPreview();}));document.querySelector('.question-editor-card')?.addEventListener('keydown',e=>{if((e.ctrlKey||e.metaKey)&&e.key==='Enter'){e.preventDefault();saveQuestion();}});updateQuestionPreview();updateSelectionToolbar();
$('#txtImportFile').addEventListener('change',e=>{readTxtFile(e.target.files?.[0]);e.target.value='';});$('#bulkQuestionText').addEventListener('input',()=>{clearTimeout(parseTimer);parseTimer=setTimeout(analyzeBulkText,250);});$('#analyzeImportBtn').addEventListener('click',analyzeBulkText);$('#importQuestionsBtn').addEventListener('click',importBulkQuestions);$('#clearImportBtn').addEventListener('click',()=>{$('#bulkQuestionText').value='';parsedImport={questions:[],errors:[],results:[]};renderImportPreview();});document.querySelectorAll('input[name="importMode"]').forEach(r=>r.addEventListener('change',syncImportModeUi));$('#downloadTemplateBtn').addEventListener('click',downloadTemplate);$('#exportQuestionsBtn').addEventListener('click',exportQuestions);syncImportModeUi();
$('#goQuestionsBtn').addEventListener('click',()=>{switchAdminTab('questions');setQuestionPane('bank',{scroll:true});});$('#startQuizBtn').addEventListener('click',startQuiz);$('#prepareRoundBtn').addEventListener('click',prepareRound);$('#openRoundBtn').addEventListener('click',openPreparedRound);$('#closeRoundBtn').addEventListener('click',closeRound);$('#pauseQuizBtn').addEventListener('click',pauseQuiz);$('#extend5Btn').addEventListener('click',()=>extendRound(5));$('#extend10Btn').addEventListener('click',()=>extendRound(10));$('#annulRoundBtn').addEventListener('click',annulRound);$('#regradeRoundBtn').addEventListener('click',regradeRound);$$('[data-reveal]').forEach(b=>b.addEventListener('click',()=>reveal(b.dataset.reveal)));$$('[data-final-show]').forEach(b=>b.addEventListener('click',()=>setFinalShowStage(b.dataset.finalShow)));$('#restartQuizBtn').addEventListener('click',restartQuiz);$('#displayBtn').addEventListener('click',()=>openDisplay('reuse'));$('#fullscreenDisplayBtn').addEventListener('click',()=>openDisplay('window'));$('#copyJoinLinkBtn').addEventListener('click',copyJoinLink);$('#forceSyncBtn').addEventListener('click',()=>Promise.all([refreshState(true),loadQueue(),loadAudit(),loadParticipants()]));$('#connectionTestBtn').addEventListener('click',runConnectionTest);$('#refreshParticipantsBtn').addEventListener('click',loadParticipants);$('#loadHistoryBtn').addEventListener('click',loadHistory);$('#showEvolutionBtn').addEventListener('click',showEvolution);
$('#pairRemoteBtn').addEventListener('click',createRemotePairing);$('#revokeRemoteBtn').addEventListener('click',revokeRemoteDevices);$('#remoteModeBtn').addEventListener('click',enterRemoteMode);$('#remoteExitBtn').addEventListener('click',exitRemoteMode);$('#remotePairCloseBtn').addEventListener('click',closeRemotePairModal);$('#remotePairCopyBtn').addEventListener('click',copyRemotePairLink);$('#remotePairRegenerateBtn').addEventListener('click',createRemotePairing);$('#remoteClaimBtn').addEventListener('click',claimRemotePairing);$('#remotePrimaryBtn').addEventListener('click',remotePrimaryAction);$('#remotePauseBtn').addEventListener('click',emergencyStopAction);$('#remoteExtend5Btn').addEventListener('click',()=>extendRound(5));$('#remoteExtend10Btn').addEventListener('click',()=>extendRound(10));$('#remoteRevealAnswerBtn').addEventListener('click',()=>reveal('answer'));$('#remoteRevealDistributionBtn').addEventListener('click',()=>reveal('distribution'));$('#remoteRevealRankingBtn').addEventListener('click',()=>reveal('ranking'));$$('[data-remote-final-show]').forEach(b=>b.addEventListener('click',()=>setFinalShowStage(b.dataset.remoteFinalShow)));$('#remoteRefreshBtn').addEventListener('click',syncRemoteNow);bindHoldAction($('#remoteAnnulBtn'),annulRound);bindHoldAction($('#remoteRestartBtn'),restartQuiz);$('#remotePairModal').addEventListener('click',e=>{if(e.target===$('#remotePairModal'))closeRemotePairModal();});document.addEventListener('keydown',e=>{if(e.key==='Escape'&&!$('#remotePairModal').classList.contains('hidden'))closeRemotePairModal();});

$('#centralNewGameBtn')?.addEventListener('click',openNewGameFlow);$('#centralContinueBtn')?.addEventListener('click',()=>room?journeyGo(['question_open','preparing','result','paused','finished'].includes(phase())?'lobby':'review'):openNewGameFlow());$('#centralBankBtn')?.addEventListener('click',()=>journeyGo('questions'));$('#refreshRecentRoomsBtn')?.addEventListener('click',loadRecentRooms);$$('#setupJourney [data-journey-step]').forEach(b=>b.addEventListener('click',()=>journeyGo(b.dataset.journeyStep)));$('#reviewBackRulesBtn')?.addEventListener('click',()=>journeyGo('rules'));$('#openLobbyFromReviewBtn')?.addEventListener('click',()=>journeyGo('lobby'));$('#buildSummaryReviewBtn')?.addEventListener('click',()=>journeyGo('review'));$('#roomNextQuestionsBtn')?.addEventListener('click',()=>journeyGo('questions'));$('#rulesBackQuestionsBtn')?.addEventListener('click',()=>journeyGo('questions'));$('#rulesNextReviewBtn')?.addEventListener('click',async()=>{if(room)await saveRoomSettings(false);journeyGo('review');});$('#backToPreparationBtn')?.addEventListener('click',()=>{if(phase()!=='lobby'&&!confirm('A partida já começou. Voltar ao painel de preparação apenas para consulta?'))return;journeyGo('review');});$$('[data-rules-mode]').forEach(b=>b.addEventListener('click',()=>setRulesMode(b.dataset.rulesMode)));$$('[data-special-preset]').forEach(b=>b.addEventListener('click',()=>applySpecialPreset(b.dataset.specialPreset)));$('#questionOptionCountFilter')?.addEventListener('change',renderQuestionBank);$('#addRandom10Btn')?.addEventListener('click',()=>addRandomQuestions(10));$('#addCategoryBtn')?.addEventListener('click',addCategoryQuestions);$('#saveCollectionBtn')?.addEventListener('click',saveQuestionCollection);$('#loadCollectionBtn')?.addEventListener('click',loadCollectionToRoom);$('#deleteCollectionBtn')?.addEventListener('click',deleteQuestionCollection);$('#duplicateFinishedGameBtn')?.addEventListener('click',duplicateRoom);$('#differentQuestionsGameBtn')?.addEventListener('click',newRoomAfterGame);$$('[data-lobby-layout]').forEach(b=>b.addEventListener('click',()=>setLobbyLayout(b.dataset.lobbyLayout)));$$('[data-participant-filter]').forEach(b=>b.addEventListener('click',()=>{participantFilter=b.dataset.participantFilter||'all';$$('[data-participant-filter]').forEach(x=>x.classList.toggle('active',x===b));renderParticipantList();}));
$('#adminHelpBtn')?.addEventListener('click',()=>openQuestionHelp('helpQuick'));$('#questionHelpBtn')?.addEventListener('click',()=>openQuestionHelp('helpQuick'));$('#questionHelpCloseBtn')?.addEventListener('click',closeQuestionHelp);$('#questionHelpSearch')?.addEventListener('input',filterQuestionHelp);$$('#questionHelpModal [data-help-target]').forEach(btn=>btn.addEventListener('click',()=>document.getElementById(btn.dataset.helpTarget)?.scrollIntoView({behavior:'smooth',block:'start'})));$('#questionHelpOpenEditorBtn')?.addEventListener('click',()=>goFromHelp('edit'));$('#questionHelpOpenImportBtn')?.addEventListener('click',()=>goFromHelp('import'));$('#questionHelpModal')?.addEventListener('click',e=>{if(e.target===$('#questionHelpModal'))closeQuestionHelp();});document.addEventListener('keydown',e=>{if(e.key==='Escape'&&!$('#questionHelpModal')?.classList.contains('hidden')){e.preventDefault();closeQuestionHelp();return;}trapQuestionHelpFocus(e);});
window.addEventListener('online',()=>{renderEventHealth();room&&subscribe();});window.addEventListener('offline',()=>{conn('offline');setPoll(POLL_FALLBACK);renderEventHealth();});document.addEventListener('visibilitychange',()=>{if(document.hidden)return;if(remoteModeActive){syncRemoteNow();return;}if(room)Promise.all([refreshState(true),loadQueue(),loadAudit(),loadParticipants()]);});window.addEventListener('load',authCheck);
