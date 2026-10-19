/* Bounded, optional model cache. The server remains authoritative. */
window.VoxelAssets = (() => {
  const memory = new Map();
  let database, unavailable = false, pending = Promise.resolve();
  const metrics = {receivedModels:0, cacheHits:0, patches:0, cacheFailures:0};
  function open() {
    if (unavailable) return Promise.resolve(null);
    if (!database) database = new Promise(resolve => {
      try {
        const request = indexedDB.open('voxel-models-v2', 1);
        const timeout = setTimeout(() => { unavailable=true; resolve(null); }, 1500);
        request.onupgradeneeded = () => {
          request.result.createObjectStore('models', {keyPath:'id'});
          request.result.createObjectStore('rooms', {keyPath:'key'});
        };
        request.onsuccess = () => { clearTimeout(timeout); if(unavailable){request.result.close();return;} request.result.onversionchange=()=>{request.result.close();unavailable=true;}; resolve(request.result); };
        request.onerror = request.onblocked = () => { clearTimeout(timeout); unavailable=true; resolve(null); };
      } catch { unavailable=true; resolve(null); }
    });
    return database;
  }
  async function read(store, key) {
    const db = await open(); if (!db) return null;
    return new Promise(resolve => {
      try { const request=db.transaction(store).objectStore(store).get(key);request.onsuccess=()=>resolve(request.result);request.onerror=()=>resolve(null); }
      catch {resolve(null);}
    });
  }
  async function normalize(input) {
    const size=input.size, palette=input.palette;
    if(!Array.isArray(size)||size.length!==3||!size.every(x=>Number.isInteger(x)&&x>=1&&x<=32)||!Array.isArray(palette)||palette.length>8192||!palette.every(x=>/^#[0-9a-fA-F]{6}$/.test(x)))throw Error('模型格式无效');
    const cells=new Map();let visits=0;
    const point=p=>Array.isArray(p)&&p.length===3&&p.every((x,i)=>Number.isInteger(x)&&x>=0&&x<size[i]);
    function set(p,c){if(!point(p)||!Number.isInteger(c)||c<0||c>=palette.length)throw Error('模型坐标或颜色无效');cells.set(p.join(','),[...p,palette[c].toUpperCase()]);}
    if(input.encoding==='cells_v1'){
      if(!Array.isArray(input.cells)||input.cells.length>8192)throw Error('模型过大');
      for(const c of input.cells){if(!Array.isArray(c)||c.length!==4)throw Error('体素格式无效');set(c.slice(0,3),c[3]);}
      if(cells.size!==input.cells.length)throw Error('重复体素');
    }else if(input.encoding==='box_ops_v1'){
      if(!Array.isArray(input.ops)||input.ops.length>1024)throw Error('模型操作过多');
      for(const op of input.ops){
        if(op.op==='set_voxel'){set(op.position,op.color);visits++;continue;}
        if(!['fill_box','clear_box'].includes(op.op)||!point(op.min)||!Array.isArray(op.max_exclusive)||op.max_exclusive.length!==3||!op.max_exclusive.every((x,i)=>Number.isInteger(x)&&x>op.min[i]&&x<=size[i]))throw Error('模型范围无效');
        visits+=op.max_exclusive.reduce((n,x,i)=>n*(x-op.min[i]),1);if(visits>1048576)throw Error('模型展开超限');
        for(let x=op.min[0];x<op.max_exclusive[0];x++)for(let y=op.min[1];y<op.max_exclusive[1];y++)for(let z=op.min[2];z<op.max_exclusive[2];z++){
          if(op.op==='clear_box')cells.delete([x,y,z].join(','));else set([x,y,z],op.color);
        }
      }
    }else throw Error('未知模型编码');
    if(!cells.size||cells.size>8192)throw Error('模型体素数无效');
    const values=[...cells.values()].sort((a,b)=>a[0]-b[0]||a[1]-b[1]||a[2]-b[2]);
    const colors=[...new Set(values.map(x=>x[3]))].sort(), indices=new Map(colors.map((c,i)=>[c,i]));
    const canonical={schema_version:1,size:[...size],encoding:'cells_v1',palette:colors,cells:values.map(c=>[...c.slice(0,3),indices.get(c[3])])};
    const hash=[...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(JSON.stringify(canonical))))].map(x=>x.toString(16).padStart(2,'0')).join('');
    if(input.id!=='bp-'+hash)throw Error('模型校验失败');
    return {...input,...canonical,ops:undefined,voxel_count:cells.size};
  }
  async function accept(model){const value=await normalize(model);memory.set(value.id,value);metrics.receivedModels++;return value;}
  async function prepare(room, force=false){
    if(force){memory.clear();return [];}
    const row=await read('rooms',room), ids=Array.isArray(row?.ids)?row.ids.slice(0,64):[];
    const valid=[];
    for(const id of ids){try{if(!memory.has(id)){const row=await read('models',id);if(!row)continue;memory.set(id,await normalize(row.model));}valid.push(id);}catch{memory.delete(id);metrics.cacheFailures++;}}
    return valid;
  }
  async function snapshot(message){
    for(const model of Object.values(message.state.assets))await accept(model);
    const assets={};
    for(const entity of Object.values(message.state.entities)){
      const id=entity.blueprint_id;if(!memory.has(id))throw Error('模型缓存缺失');
      assets[id]=memory.get(id);if(!message.state.assets[id])metrics.cacheHits++;
    }
    return {...message,state:{...message.state,assets}};
  }
  async function event(message,state){
    if(message.voxel_patch){
      const p=message.voxel_patch, prior=state.entities[message.entity.id];
      if(!prior||prior.revision!==p.base_revision||prior.blueprint_id!==p.base_blueprint_id)throw Error('补丁版本不一致');
      const base=state.assets[p.base_blueprint_id];if(!base)throw Error('补丁缺少基础模型');
      const model=structuredClone(base);model.id=message.entity.blueprint_id;
      let index=model.palette.indexOf(p.color);if(index<0){index=model.palette.length;model.palette.push(p.color);}
      const cell=model.cells.find(c=>c.slice(0,3).every((v,i)=>v===p.voxel[i]));if(!cell)throw Error('补丁目标缺失');cell[3]=index;
      const updated=await normalize(model);memory.set(updated.id,updated);metrics.patches++;
      return {...message,asset:updated};
    }
    if(message.asset)return {...message,asset:await accept(message.asset)};
    if(message.entity){const model=memory.get(message.entity.blueprint_id);if(!model)throw Error('模型缺失');return {...message,asset:model};}
    return message;
  }
  function persist(room,assets){
    // Serialize transactions so an older snapshot cannot overwrite a newer room manifest.
    const models=Object.values(assets), ids=models.map(m=>m.id);
    pending=pending.then(async()=>{
      const db=await open();if(!db)return;
      await new Promise(resolve=>{
        try{
          const tx=db.transaction(['models','rooms'],'readwrite');const store=tx.objectStore('models');
          for(const model of models)store.put({id:model.id,model,used:Date.now()});
          tx.objectStore('rooms').put({key:room,ids,used:Date.now()});
          const all=store.getAll();all.onsuccess=()=>{const sorted=all.result.sort((a,b)=>b.used-a.used);for(const old of sorted.slice(128))store.delete(old.id);};
          const rooms=tx.objectStore('rooms'), rows=rooms.getAll();rows.onsuccess=()=>{for(const old of rows.result.sort((a,b)=>b.used-a.used).slice(32))rooms.delete(old.key);};
          tx.oncomplete=()=>resolve();tx.onerror=tx.onabort=()=>{metrics.cacheFailures++;resolve();};
        }catch{metrics.cacheFailures++;resolve();}
      });
      for(const id of memory.keys()){if(memory.size<=128)break;if(!ids.includes(id))memory.delete(id);}
    }).catch(()=>{metrics.cacheFailures++;});
    return pending;
  }
  return {prepare,snapshot,event,persist,metrics,flush:()=>pending};
})();
