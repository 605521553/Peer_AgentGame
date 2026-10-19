/* Browser owns chat/network; Godot owns the camera and voxel renderer. */
const $=id=>document.getElementById(id);
let session=null, state={entities:{},assets:{},players:[],seq:0}, socket=null, busy=false, reconnectTimer=null, pendingChat=null;
let lastCommand=null, rulesVersion='stage-01-v1', synchronized=false, restoreCamera=null, cameraSaveAfter=Infinity, connectionEpoch=0;
const savedRead=(key,fallback=null)=>{try{return JSON.parse(localStorage.getItem(key))??fallback;}catch{return fallback;}};
const savedWrite=(key,value)=>{try{localStorage.setItem(key,JSON.stringify(value));}catch{}};
const savedRemove=key=>{try{localStorage.removeItem(key);}catch{}};
const roomCacheKey=()=>session.world_id+':'+session.player_id;
const cameraKey=room=>'voxel-camera:'+room;
const networkMetrics={snapshots:0,events:0,receivedBytes:0,autoRestored:false};
function connectionStatus(text){$('connection').textContent=text;}
function saveCamera(){const m=window.voxelMetrics;if(session&&synchronized&&Date.now()>cameraSaveAfter&&m?.camera_target)savedWrite(cameraKey(session.world_id),{target:m.camera_target,size:m.camera_size,yaw:m.camera_yaw_deg});}
async function waitForSeq(seq){const deadline=Date.now()+15000;while(state.seq<seq||!synchronized){if(Date.now()>deadline){window.voxelResync();throw new Error('操作已确认，正在恢复同步，请勿重复提交。');}await new Promise(r=>setTimeout(r,80));}}

const storageKey=room=>'voxel-kingdom:'+room;
const newId=()=>crypto.randomUUID?.()||Date.now().toString(36)+'-'+Math.random().toString(36).slice(2);
const clone=value=>JSON.parse(JSON.stringify(value));
window.voxelSelect=selection=>{window.voxelSelection=selection;renderSelection();};
window.voxelResync=()=>{if(session)connect(true);};
function toast(text){$('toast').textContent=text;$('toast').classList.add('visible');clearTimeout(toast.timer);toast.timer=setTimeout(()=>$('toast').classList.remove('visible'),4500);}
function message(text,user=false,detail=''){const node=document.createElement('div');node.className=user?'user-message':'assistant-message';if(user){node.textContent=text;}else{const body=document.createElement('div');const title=document.createElement('b');title.textContent='王国建造助手';const p=document.createElement('p');p.textContent=text;body.append(title,p);if(detail){const small=document.createElement('small');small.textContent=detail;body.append(small);}node.append(body);}$('chat-log').append(node);$('chat-log').scrollTop=$('chat-log').scrollHeight;}
async function api(path,data){const response=await fetch(path,{method:data?'POST':'GET',headers:{'Content-Type':'application/json','X-Voxel-Protocol':'2',...(session?{Authorization:'Bearer '+session.token}:{})},body:data?JSON.stringify(data):undefined});const result=await response.json();if(!response.ok){const error=new Error(result.error?.message||'服务请求失败');error.code=result.error?.code;throw error;}return result;}
function push(message){window.voxelMessageQueue.push(clone(message));}
function receive(message){if(message.kind==='snapshot'){state=message.state;networkMetrics.snapshots++;synchronized=true;if(message.rules)rulesVersion=message.rules.rules_version;push(message);const player=state.players.find(p=>p.id===session.player_id);$('room-label').textContent=session.world_id+' · '+player.name;$('player-zone').textContent='我的区域 '+(player.slot+1);connectionStatus('已连接 · '+session.world_id);$('join-dialog').close();$('resume-status').hidden=true;if(restoreCamera){push({kind:'camera_restore',...restoreCamera});restoreCamera=null;}cameraSaveAfter=Date.now()+1500;}else if(message.kind==='event'){if(message.seq<=state.seq)return;if(message.seq!==state.seq+1){window.voxelResync();return;}state.seq=message.seq;networkMetrics.events++;if(message.type==='player.joined'){state.players.push(message.player);}else if(message.entity){state.entities[message.entity.id]=message.entity;if(message.asset)state.assets[message.asset.id]=message.asset;if(window.voxelSelection.entity_id===message.entity.id){window.voxelSelection.revision=message.entity.revision;}}else if(message.entity_id){delete state.entities[message.entity_id];if(window.voxelSelection.entity_id===message.entity_id)window.voxelSelection={};}const used=new Set(Object.values(state.entities).map(e=>e.blueprint_id));for(const id of Object.keys(state.assets))if(!used.has(id))delete state.assets[id];push(message);}else if(message.kind==='resync_required'){socket.close();return;}renderBuildings();renderSelection();if(session)window.VoxelAssets.persist(roomCacheKey(),state.assets);}
async function connect(force=false){
  clearTimeout(reconnectTimer);const epoch=++connectionEpoch;const old=socket;socket=null;old?.close();synchronized=false;connectionStatus('正在同步…');
  const known=await window.VoxelAssets.prepare(roomCacheKey(),force);if(epoch!==connectionEpoch||!session)return;
  const ws=new WebSocket((location.protocol==='https:'?'wss://':'ws://')+location.host+'/ws');socket=ws;let incoming=Promise.resolve();
  ws.onopen=()=>ws.send(JSON.stringify({token:session.token,protocol_version:2,known_assets:known}));
  ws.onmessage=event=>{networkMetrics.receivedBytes+=new TextEncoder().encode(event.data).length;incoming=incoming.then(async()=>{
    if(socket!==ws)return;const message=JSON.parse(event.data);let decoded=message;
    if(message.kind==='snapshot')decoded=await window.VoxelAssets.snapshot(message);
    else if(message.kind==='event'){if(message.seq<=state.seq)return;if(message.seq!==state.seq+1){connect(true);return;}decoded=await window.VoxelAssets.event(message,state);}
    if(socket===ws)receive(decoded);
  }).catch(()=>{if(socket===ws){connectionStatus('正在重新获取场景…');connect(true);}});};
  ws.onclose=()=>{if(socket!==ws)return;synchronized=false;connectionStatus('连接恢复中…');reconnectTimer=setTimeout(()=>connect(),2000);};
  ws.onerror=()=>ws.close();
}
function escapeHtml(text){const node=document.createElement('span');node.textContent=text;return node.innerHTML;}
function renderBuildings(){const list=$('building-list');list.replaceChildren();const entities=Object.values(state.entities);$('building-count').textContent=entities.length;for(const entity of entities){const owner=state.players.find(p=>p.id===entity.owner_id);const button=document.createElement('button');button.className='building-item';const name=document.createElement('b');name.textContent=entity.name;const info=document.createElement('span');info.textContent=`${owner?.name||'玩家'} · (${entity.position[0]}, ${entity.position[2]}) · ${state.assets[entity.blueprint_id]?.voxel_count||0} 方块`;button.append(name,info);button.onclick=()=>window.voxelSelect({entity_id:entity.id,revision:entity.revision,position:entity.position});list.append(button);}if(!entities.length){const p=document.createElement('p');p.textContent='世界还很安静。选择位置，建造第一座建筑。';p.style.color='#92a7aa';p.style.fontSize='12px';p.style.lineHeight='1.8';list.append(p);}}
function renderSelection(){const selection=window.voxelSelection;const entity=state.entities[selection.entity_id];$('entity-actions').hidden=!entity;$('paint').disabled=!selection.voxel;const own=entity?.owner_id===session?.player_id;for(const id of ['demolish','destroy'])$(id).disabled=!own;$('paint').disabled=!own||!selection.voxel;if(entity){$('selected-name').textContent=entity.name+(!own?' · 其他玩家':'');$('selected-detail').textContent=`位置 ${entity.position.join(', ')} · 修订 ${entity.revision}`+(selection.voxel?` · 方块 (${selection.voxel.join(', ')})`:'');if(selection.voxel){const cell=state.assets[entity.blueprint_id].cells.find(c=>c.slice(0,3).every((v,i)=>v===selection.voxel[i]));if(cell)$('voxel-color').value=state.assets[entity.blueprint_id].palette[cell[3]];}}else if(selection.position){$('selected-name').textContent=`建造位置 (${selection.position.join(', ')})`;$('selected-detail').textContent='可以描述建筑，或导入自定义体素模型。';}else{$('selected-name').textContent='点击地面选择建造位置';$('selected-detail').textContent='每一块颜色，都由你决定。';}}
async function join(room,name,fresh=false){
  saveCamera();const saved=fresh?null:savedRead(storageKey(room));
  const result=await api('/api/join',{world_id:room,name,protocol_version:2,...(saved?{token:saved.token}:{access_code:$('access-code').value})});
  session={token:result.token,player_id:result.player_id,world_id:result.world_id,name};
  savedWrite(storageKey(room),session);try{localStorage.setItem('voxel-last-room',room);}catch{}
  const pose=savedRead(cameraKey(room));restoreCamera=pose&&Array.isArray(pose.target)&&pose.target.length===3&&pose.target.every(Number.isFinite)&&Number.isFinite(pose.size)&&Number.isFinite(pose.yaw)?pose:null;cameraSaveAfter=Infinity;state={entities:{},assets:{},players:[],seq:0};window.voxelSelection={};
  await connect();
}
async function command(type,payload){if(!session)throw new Error('请先进入房间');if(!synchronized)throw new Error('场景正在同步，请稍后操作');const request={schema_version:1,rules_version:rulesVersion,command_id:newId(),world_id:session.world_id,type,payload};lastCommand=request;const result=await api('/api/command',request);$('command-log').textContent=JSON.stringify(result,null,2);if(result.status==='rejected')throw new Error(result.error.message);if(result.status==='applied')await waitForSeq(result.seq);toast('操作已执行');return result;}
function selectedEntity(){const entity=state.entities[window.voxelSelection.entity_id];if(!entity)throw new Error('请先点击选择建筑');if(entity.owner_id!==session?.player_id)throw new Error('只能操作自己的建筑');return entity;}
function modelCopy(entity){const m=state.assets[entity.blueprint_id];return {schema_version:1,name:entity.name,size:clone(m.size),encoding:'cells_v1',palette:clone(m.palette),cells:clone(m.cells)};}
async function place(model){const point=window.voxelSelection.position;if(!point||window.voxelSelection.entity_id)throw new Error('请先点击地面选择新建筑的位置');return command('building.create',{position:point,rotation_y_quarter_turns:0,blueprint:model});}
function sampleCastle(){const palette=['#8D969C','#315CC0','#D8B978','#A94136'];const ops=[{op:'fill_box',min:[0,0,0],max_exclusive:[14,1,14],color:0},{op:'fill_box',min:[0,1,0],max_exclusive:[14,6,14],color:0},{op:'clear_box',min:[1,1,1],max_exclusive:[13,6,13]},{op:'clear_box',min:[6,1,0],max_exclusive:[8,4,1]}];for(const [x,z] of [[0,0],[11,0],[0,11],[11,11]]){ops.push({op:'fill_box',min:[x,1,z],max_exclusive:[x+3,9,z+3],color:0},{op:'fill_box',min:[x,9,z],max_exclusive:[x+3,10,z+3],color:1});}ops.push({op:'fill_box',min:[5,1,7],max_exclusive:[9,6,11],color:2},{op:'fill_box',min:[4,6,6],max_exclusive:[10,7,12],color:3});return{schema_version:1,name:'四塔城堡',size:[14,10,14],encoding:'box_ops_v1',palette,ops};}
async function paint(){const entity=selectedEntity();const voxel=window.voxelSelection.voxel;if(!voxel)throw new Error('请在场景中点击具体方块');await command('building.paint_voxel',{entity_id:entity.id,expected_entity_revision:entity.revision,voxel,color:$('voxel-color').value.toUpperCase()});}
async function destructive(type){const entity=selectedEntity();await command(type,{entity_id:entity.id,expected_entity_revision:entity.revision});}
async function submitChat(event){event.preventDefault();if(busy)return;if(!session){$('join-dialog').showModal();return;}if(!synchronized){toast('场景正在同步，请稍后发送');return;}const text=$('prompt').value.trim();if(!text)return;busy=true;$('send').disabled=true;$('ai-status').textContent='DeepSeek 正在理解与生成…';message(text,true);$('prompt').value='';const id=newId();pendingChat=id;const start=performance.now();try{let result;try{result=await api('/api/chat',{request_id:id,text,selection:clone(window.voxelSelection)});}catch(error){message('连接中断，正在查询原请求结果。');for(let i=0;i<120;i++){await new Promise(resolve=>setTimeout(resolve,2000));try{const r=await api('/api/chat/'+id);if(r.status!=='pending'){result=r;break;}}catch{}}if(!result)throw error;}if(result.receipt?.status==='applied')await waitForSeq(result.receipt.seq);message(result.message,result.status==='error'?false:false,result.metrics?`耗时 ${(performance.now()-start)/1000|0}s · ${result.metrics.model}`:'');$('command-log').textContent=JSON.stringify(result,null,2);if(result.receipt?.status==='applied')toast('建筑操作已同步');}catch(error){message(error.message);}finally{busy=false;pendingChat=null;$('send').disabled=false;$('ai-status').textContent='准备好聆听你的想法';}}
$('chat-form').onsubmit=submitChat;
$('prompt').addEventListener('keydown',event=>{if(event.key==='Enter'&&!event.shiftKey){event.preventDefault();$('chat-form').requestSubmit();}});
for(const button of document.querySelectorAll('[data-prompt]'))button.onclick=()=>{$('prompt').value=button.dataset.prompt;$('prompt').focus();};
for(const button of document.querySelectorAll('[data-camera]'))button.onclick=()=>window.voxelUiActions.push(button.dataset.camera);
for(const button of document.querySelectorAll('[data-tab]'))button.onclick=()=>{document.querySelectorAll('[data-tab]').forEach(b=>b.classList.toggle('active',b===button));$('chat-tab').classList.toggle('active',button.dataset.tab==='chat');$('buildings-tab').classList.toggle('active',button.dataset.tab==='buildings');};
function safeAction(action){return async()=>{try{await action();}catch(error){toast(error.message);}};}
$('sample').onclick=safeAction(()=>place(sampleCastle()));$('paint').onclick=safeAction(paint);$('demolish').onclick=safeAction(()=>destructive('building.demolish'));$('destroy').onclick=safeAction(()=>destructive('building.destroy'));
$('import').onclick=()=>{$('model-file').value='';$('model-file').click();};$('model-file').onchange=safeAction(async()=>{const file=$('model-file').files[0];if(!file)return;if(file.size>1048576)throw new Error('模型文件超过 1 MiB');const model=JSON.parse(await file.text());if(window.voxelSelection.entity_id){const entity=selectedEntity();await command('building.update_model',{entity_id:entity.id,expected_entity_revision:entity.revision,blueprint:model});}else await place(model);});
$('export').onclick=safeAction(async()=>{const entity=selectedEntity();const url=URL.createObjectURL(new Blob([JSON.stringify(modelCopy(entity),null,2)],{type:'application/json'}));const link=document.createElement('a');link.href=url;link.download=entity.name+'.json';link.click();setTimeout(()=>URL.revokeObjectURL(url),5000);});
$('join-form').onsubmit=async event=>{event.preventDefault();$('join').disabled=true;$('join-error').textContent='';try{await join($('room').value,$('name').value);}catch(error){$('join-error').textContent=error.message;}finally{$('join').disabled=false;}};
$('logout').onclick=()=>{saveCamera();if(session)savedRemove(storageKey(session.world_id));++connectionEpoch;clearTimeout(reconnectTimer);const old=socket;socket=null;old?.close();session=null;synchronized=false;state={world_id:'',entities:{},assets:{},players:[],seq:0};window.voxelSelection={};push({kind:'snapshot',state,player_id:''});renderBuildings();renderSelection();connectionStatus('已退出');$('join-dialog').showModal();};
$('switch-room').onclick=()=>{$('join-dialog').showModal();};
try{$('room').value=localStorage.getItem('voxel-last-room')||'kingdom';}catch{$('room').value='kingdom';}
async function boot(){
 const room=$('room').value, saved=savedRead(storageKey(room));
 if(!saved?.token){$('resume-status').hidden=true;$('join-dialog').showModal();return;}
 $('resume-status').hidden=false;connectionStatus('正在恢复上次游戏…');
 try{await join(room,saved.name||'建造者');networkMetrics.autoRestored=true;}
 catch(error){if(['UNAUTHENTICATED','PERMISSION_DENIED'].includes(error.code)){savedRemove(storageKey(room));$('resume-status').hidden=true;$('join-error').textContent='原会话已失效，请重新进入。';$('join-dialog').showModal();}else{connectionStatus('网络暂不可用，正在重试…');setTimeout(boot,4000);}}
}
window.addEventListener('pagehide',saveCamera);
setInterval(saveCamera,1000);
boot();
api('/api/health').then(info=>{$('invite-field').hidden=!info.invite_required;}).catch(()=>{});
setInterval(()=>{const m=window.voxelMetrics;if(m){$('fps').textContent=Math.round(m.fps)+' FPS · '+m.rendered+' 栋';$('metrics').textContent=JSON.stringify(m,null,2);document.querySelector('.compass b').style.transform='rotate('+m.camera_yaw_deg+'deg)';}},1000);
setInterval(()=>{if(socket?.readyState===WebSocket.OPEN)socket.send(JSON.stringify({kind:'ping'}));},15000);
document.addEventListener('visibilitychange',()=>{if(!document.hidden&&session&&socket?.readyState!==WebSocket.OPEN)connect();});
// Deliberate development interface: commands still use authenticated server validation.
window.voxelApp={get session(){return session;},get state(){return state;},command,sampleCastle,join,get pendingChat(){return pendingChat;},get synchronized(){return synchronized;},networkMetrics,cacheMetrics:window.VoxelAssets.metrics,flushCache:window.VoxelAssets.flush};
