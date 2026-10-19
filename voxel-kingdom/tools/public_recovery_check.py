"""Public browser reconnect + service restart acceptance. Uses dedicated test room only."""
import json
import os
import sys
import time
from pathlib import Path
from playwright.sync_api import sync_playwright
from deploy_public import connect, run

sys.stdout.reconfigure(encoding='utf-8')
root = Path(__file__).resolve().parents[1]
private = Path(os.environ['LOCALAPPDATA']) / 'VoxelKingdom'
access = json.loads((private / 'public-access.json').read_text(encoding='utf-8'))
output = Path(os.environ.get('VOXEL_TEST_OUTPUT', str(root / 'artifacts/public-deployment/recovery')))
output.mkdir(parents=True, exist_ok=True)
room = 'recovery-' + str(int(time.time()))
ssh = connect()
try:
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, args=['--disable-background-timer-throttling','--disable-renderer-backgrounding','--use-angle=d3d11'])
        contexts = [browser.new_context(ignore_https_errors=True, viewport={'width':1600,'height':1000}) for _ in range(2)]
        pages = []
        for i, context in enumerate(contexts):
            page = context.new_page()
            page.goto(access['url'], wait_until='networkidle', timeout=180000)
            page.wait_for_function('window.voxelReady===true', timeout=120000)
            page.fill('#room', room)
            page.fill('#name', f'恢复验收{i+1}')
            page.fill('#access-code', access['invite_code'])
            page.click('#join')
            page.wait_for_function('window.voxelApp.session!==null')
            pages.append(page)
        a,b = pages
        a.wait_for_function('window.voxelApp.state.players.length===2')
        result = a.evaluate("async()=>await window.voxelApp.command('building.create',{position:[22,1,22],rotation_y_quarter_turns:0,blueprint:window.voxelApp.sampleCastle()})")
        assert result['status']=='applied'
        entity=result['result']['entity']
        b.wait_for_function('Object.keys(window.voxelApp.state.entities).length===1')
        contexts[1].set_offline(True)
        b.wait_for_timeout(2500)
        result=a.evaluate("""async e=>{const asset=window.voxelApp.state.assets[e.blueprint_id];return await window.voxelApp.command('building.paint_voxel',{entity_id:e.id,expected_entity_revision:e.revision,voxel:asset.cells[0].slice(0,3),color:'#FF00CC'});} """, entity)
        assert result['status']=='applied'
        contexts[1].set_offline(False)
        b.wait_for_function('Object.values(window.voxelApp.state.entities)[0].revision===2',timeout=30000)
        before=a.evaluate('JSON.parse(JSON.stringify(window.voxelApp.state))')
        assert before==b.evaluate('JSON.parse(JSON.stringify(window.voxelApp.state))')
        authoritative_before=a.evaluate("async()=>await fetch('/api/snapshot',{headers:{Authorization:'Bearer '+window.voxelApp.session.token}}).then(r=>r.json())")['state']
        # Compare persisted state with the same server representation. The v2
        # client normalizes transport models and may omit optional wire fields.
        print('Offline browser resumed from authoritative snapshot',flush=True)
        events=[]
        for page in pages:
            page.on('websocket',lambda ws: events.append(ws.url))
        restarted_at=time.perf_counter()
        run(ssh,'sudo -n systemctl restart voxel-kingdom.service')
        for page in pages:
            page.wait_for_function("document.getElementById('connection').textContent.includes('已连接')",timeout=30000)
        # Require newly created WSS connections after the restart, not just stale UI text.
        deadline=time.monotonic()+30
        while len(events)<2 and time.monotonic()<deadline:
            a.wait_for_timeout(200)
        assert len(events)>=2, 'Both browser connections must reopen after restart'
        for page in pages:
            page.wait_for_function("Object.values(window.voxelApp.state.entities)[0]?.revision===2")
            snapshot=page.evaluate("async()=>await fetch('/api/snapshot',{headers:{Authorization:'Bearer '+window.voxelApp.session.token}}).then(r=>r.json())")
            assert snapshot['state']==authoritative_before, 'Persisted authoritative state changed on restart'
            assert page.evaluate('JSON.parse(JSON.stringify(window.voxelApp.state))')==before, 'Client world changed on restart'
        recovery_seconds=round(time.perf_counter()-restarted_at,2)
        a.screenshot(path=str(output/'after-restart.png'))
        result=a.evaluate("async e=>await window.voxelApp.command('building.destroy',{entity_id:e.id,expected_entity_revision:2})",entity)
        assert result['status']=='applied'
        b.wait_for_function('Object.keys(window.voxelApp.state.entities).length===0')
        remote=run(ssh,"sudo -n systemctl start voxel-kingdom-backup.service && sudo -n systemctl show voxel-kingdom.service -p ActiveState -p MemoryCurrent -p NRestarts && curl --resolve api.patelender.cn:443:127.0.0.1 -s -o /dev/null -w 'Existing site HTTP %{http_code}\\n' https://api.patelender.cn/")
        (output/'server-health.txt').write_text(remote,encoding='utf-8')
        summary={'room':room,'public_url':access['url'],'browser_offline_recovery':True,'server_restart_persistence':True,'both_websockets_reopened':True,'sessions_survive_restart':True,'post_restart_mutation_synced':True,'recovery_seconds':recovery_seconds,'physical_devices':1,'isolated_browser_contexts':2}
        (output/'recovery.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
        print(json.dumps(summary,ensure_ascii=False),flush=True)
        browser.close()
finally:
    ssh.close()
