"""Real Godot browser acceptance: automatic login, model caching, patches and recovery."""
import json
import os
from pathlib import Path
import sys
import time
from playwright.sync_api import sync_playwright

sys.stdout.reconfigure(encoding='utf-8')
root=Path(__file__).resolve().parents[1]
url=os.environ.get('VOXEL_TEST_BASE_URL','http://127.0.0.1:8775')
out=Path(os.environ.get('VOXEL_TEST_OUTPUT',str(root/'artifacts/sync-v2/local')))
out.mkdir(parents=True,exist_ok=True)
access=json.loads(Path(os.environ['VOXEL_TEST_ACCESS_FILE']).read_text(encoding='utf-8')) if os.environ.get('VOXEL_TEST_ACCESS_FILE') else {}
room='sync-'+str(int(time.time()))
frames=[];errors=[]
with sync_playwright() as p:
    browser=p.chromium.launch(headless=True,args=['--disable-background-timer-throttling','--disable-renderer-backgrounding','--use-angle=d3d11'])
    contexts=[browser.new_context(ignore_https_errors=True,viewport={'width':1600,'height':1000}) for _ in range(2)]
    pages=[]
    for i,context in enumerate(contexts):
        page=context.new_page()
        page.on('pageerror',lambda e:errors.append(str(e)))
        page.on('websocket',lambda ws:ws.on('framereceived',lambda data:frames.append(json.loads(data))))
        page.goto(url,wait_until='networkidle',timeout=180000)
        page.wait_for_function('window.voxelReady===true',timeout=120000)
        page.fill('#room',room);page.fill('#name',f'同步验收{i+1}')
        if access:page.fill('#access-code',access['invite_code'])
        page.click('#join');page.wait_for_function('window.voxelApp.synchronized===true')
        pages.append(page)
    a,b=pages
    a.wait_for_function('window.voxelApp.state.players.length===2')
    created=a.evaluate("async()=>await window.voxelApp.command('building.create',{position:[22,1,22],rotation_y_quarter_turns:0,blueprint:window.voxelApp.sampleCastle()})")
    assert created['status']=='applied' and 'event' not in created
    entity=created['result']['entity']
    b.wait_for_function('Object.keys(window.voxelApp.state.entities).length===1')
    a.wait_for_function('window.voxelMetrics?.rendered===1&&window.voxelMetrics.queue===0')
    # Set a distinctive camera pose and let normal persistence save it.
    a.evaluate("window.voxelMessageQueue.push({kind:'camera_restore',target:[40,1,30],size:45,yaw:-20})")
    a.wait_for_function('Math.abs(window.voxelMetrics.camera_yaw_deg+20)<0.01')
    a.wait_for_timeout(2600)
    camera=a.evaluate('({target:window.voxelMetrics.camera_target,size:window.voxelMetrics.camera_size,yaw:window.voxelMetrics.camera_yaw_deg})')
    identity=a.evaluate('window.voxelApp.session.player_id')
    a.evaluate('window.voxelApp.flushCache()')
    a.evaluate('window.voxelRuntimeCache.flush()')
    started=time.perf_counter();a.reload(wait_until='networkidle',timeout=180000)
    a.wait_for_function('window.voxelReady===true&&window.voxelApp.synchronized&&window.voxelMetrics?.rendered===1',timeout=120000)
    a.wait_for_function('Math.abs(window.voxelMetrics.camera_yaw_deg+20)<0.01')
    refresh_ms=round((time.perf_counter()-started)*1000)
    assert not a.locator('#join-dialog').evaluate('(node)=>node.open')
    assert a.evaluate('window.voxelApp.session.player_id')==identity
    assert a.evaluate('window.voxelApp.state.players.length')==2
    assert a.evaluate('window.voxelApp.cacheMetrics.receivedModels')==0
    assert a.evaluate('window.voxelApp.cacheMetrics.cacheHits')==1
    assert a.evaluate('window.voxelApp.networkMetrics.snapshots')==1
    runtime_cache=a.evaluate('window.voxelRuntimeCache.metrics')
    assert runtime_cache['hits']==2 and runtime_cache['misses']==0, runtime_cache
    runtime_network=a.evaluate("performance.getEntriesByType('resource').filter(x=>/\\.(wasm|pck)$/.test(x.name)).reduce((n,x)=>n+x.transferSize,0)")
    assert runtime_network==0,runtime_network
    assert a.evaluate('({target:window.voxelMetrics.camera_target,size:window.voxelMetrics.camera_size,yaw:window.voxelMetrics.camera_yaw_deg})')==camera
    print('Automatic session/camera restoration and cached-model refresh passed',flush=True)
    start=len(frames)
    result=a.evaluate("async e=>await window.voxelApp.command('building.paint_voxel',{entity_id:e.id,expected_entity_revision:1,voxel:[0,0,0],color:'#FF00CC'})",entity)
    b.wait_for_function('Object.values(window.voxelApp.state.entities)[0].revision===2')
    assert a.evaluate('window.voxelApp.state')==b.evaluate('window.voxelApp.state')
    changes=[f for f in frames[start:] if f.get('type')=='building.updated']
    assert len(changes)==2 and all('asset' not in f and 'voxel_patch' in f for f in changes)
    patch_bytes=len(json.dumps(changes[0],ensure_ascii=False,separators=(',',':')).encode())
    assert 'event' not in result
    current=a.evaluate('Object.values(window.voxelApp.state.entities)[0]')
    start=len(frames)
    second=a.evaluate("async e=>await window.voxelApp.command('building.create',{position:[40,1,22],rotation_y_quarter_turns:0,blueprint_id:e.blueprint_id})",current)['result']['entity']
    b.wait_for_function('Object.keys(window.voxelApp.state.entities).length===2')
    assert all('asset' not in f for f in frames[start:] if f.get('type')=='building.created')
    b.wait_for_function('window.voxelMetrics?.rendered===2&&window.voxelMetrics.queue===0')
    rebuilds=b.evaluate('window.voxelMetrics.node_rebuilds')
    contexts[1].set_offline(True);b.wait_for_timeout(2500)
    a.evaluate("async e=>await window.voxelApp.command('building.destroy',{entity_id:e.id,expected_entity_revision:1})",second)
    contexts[1].set_offline(False)
    b.wait_for_function('window.voxelApp.synchronized&&Object.keys(window.voxelApp.state.entities).length===1',timeout=30000)
    assert a.evaluate('window.voxelApp.state')==b.evaluate('window.voxelApp.state')
    b.wait_for_function('window.voxelMetrics?.rendered===1&&window.voxelMetrics.queue===0')
    assert b.evaluate('window.voxelMetrics.node_rebuilds')==rebuilds
    # Corrupt only our browser's model cache: restore must fetch verified server data.
    a.evaluate('window.voxelApp.flushCache()')
    a.evaluate("""async()=>await new Promise((resolve,reject)=>{const r=indexedDB.open('voxel-models-v2',1);r.onsuccess=()=>{const db=r.result,tx=db.transaction('models','readwrite'),s=tx.objectStore('models'),id=Object.values(window.voxelApp.state.entities)[0].blueprint_id,q=s.get(id);q.onsuccess=()=>{const row=q.result;row.model.cells[0][3]=999999;s.put(row);};tx.oncomplete=()=>{db.close();resolve();};tx.onerror=()=>reject(tx.error);};})""")
    a.reload(wait_until='networkidle');a.wait_for_function('window.voxelApp.synchronized&&window.voxelReady===true')
    assert a.evaluate('window.voxelApp.cacheMetrics.receivedModels')==1
    assert a.evaluate('window.voxelApp.cacheMetrics.cacheFailures')>=1
    # Simulate unavailable persistent storage, keeping localStorage session intact.
    contexts[0].add_init_script("Object.defineProperty(window,'indexedDB',{get(){throw new Error('storage disabled for acceptance')}})")
    a.reload(wait_until='networkidle');a.wait_for_function('window.voxelApp.synchronized&&window.voxelReady===true')
    assert a.evaluate('window.voxelApp.session.player_id')==identity
    assert a.evaluate('window.voxelApp.cacheMetrics.receivedModels')==1
    a.wait_for_function('window.voxelMetrics?.rendered===1')
    a.screenshot(path=str(out/'auto-restored.png'))
    # Invalid token should show login, not endlessly retry or create a player.
    b.evaluate("()=>{const room=window.voxelApp.session.world_id;localStorage.setItem('voxel-kingdom:'+room,JSON.stringify({token:'invalid',world_id:room}));}")
    b.reload(wait_until='networkidle');b.wait_for_function("document.getElementById('join-dialog').open")
    assert '失效' in b.locator('#join-error').inner_text()
    assert a.evaluate('window.voxelApp.state.players.length')==2
    a.evaluate("async e=>await window.voxelApp.command('building.destroy',{entity_id:e.id,expected_entity_revision:2})",current)
    a.click('#logout');assert a.evaluate('window.voxelApp.session') is None
    a.reload(wait_until='networkidle');a.wait_for_function("document.getElementById('join-dialog').open")
    assert a.evaluate('window.voxelApp.session') is None
    summary={'runtime_cache_on_refresh':runtime_cache,'runtime_network_bytes_on_refresh':runtime_network,'unchanged_building_not_rebuilt_on_resync':True,'explicit_logout':True,'url':url,'room':room,'automatic_login':True,'same_identity_no_new_slot':True,'camera_restored':True,'refresh_model_downloads':0,'refresh_initial_snapshots':1,'refresh_to_rendered_ms':refresh_ms,'single_voxel_patch_bytes':patch_bytes,'no_full_model_in_patch':True,'same_model_instance_reused':True,'offline_deletion_recovered':True,'corrupt_cache_recovered':True,'unavailable_indexeddb_fallback':True,'invalid_session_shows_login':True,'page_errors':errors,'physical_devices':1,'browser_contexts':2}
    (out/'results.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(summary,ensure_ascii=False),flush=True)
    assert not errors,errors
    browser.close()
