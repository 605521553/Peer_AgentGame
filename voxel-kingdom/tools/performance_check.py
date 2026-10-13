"""Actual browser/Godot performance, ordinary scene and exact aggregate quotas."""
import json
import sys
import time
from pathlib import Path
import httpx
from playwright.sync_api import sync_playwright
sys.stdout.reconfigure(encoding="utf-8")
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT / "artifacts/acceptance"
OUT.mkdir(parents=True,exist_ok=True)
BASE="http://127.0.0.1:8765"

def ordinary():
    return {"schema_version":1,"name":"灰墙蓝顶基准城堡","size":[16,16,16],"encoding":"box_ops_v1","palette":["#808080","#2060FF","#D8B978"],"ops":[
        {"op":"fill_box","min":[0,0,0],"max_exclusive":[16,1,16],"color":0},
        {"op":"fill_box","min":[0,1,0],"max_exclusive":[16,14,16],"color":0},
        {"op":"clear_box","min":[2,1,2],"max_exclusive":[14,14,14]},
        *[{"op":"fill_box","min":[x,14,z],"max_exclusive":[x+4,16,z+4],"color":1} for x,z in [(0,0),(12,0),(0,12),(12,12)]],
        {"op":"fill_box","min":[5,1,5],"max_exclusive":[11,11,11],"color":2},
        {"op":"clear_box","min":[7,1,0],"max_exclusive":[9,4,2]}]}

def colorful():
    cells=[[x,y,z,(x*16+y)*8+z] for x in range(16) for y in range(16) for z in range(8)]
    palette=["#%06X" % ((i*105487+0x345678)&0xFFFFFF) for i in range(2048)]
    return {"schema_version":1,"name":"逐方块异色压力建筑","size":[16,16,8],"encoding":"cells_v1","palette":palette,"cells":cells}

def seed(client, room, model, count):
    users=[client.post(BASE+"/api/join",json={"world_id":room,"name":f"压力玩家{i+1}"}).json() for i in range(4)]
    latencies=[]
    for i in range(count):
        slot=i//16;local=i%16;zone=users[slot]["snapshot"]["players"][slot]["zone"]
        data={"schema_version":1,"rules_version":"stage-01-v1","world_id":room,"command_id":"seed-"+str(i),"type":"building.create","payload":{"position":[zone[0]+(local%4)*16,1,zone[1]+(local//4)*16],"rotation_y_quarter_turns":0,"blueprint":model}}
        start=time.perf_counter();result=client.post(BASE+"/api/command",headers={"Authorization":"Bearer "+users[slot]["token"]},json=data).json();latencies.append((time.perf_counter()-start)*1000)
        assert result["status"]=="applied",result
    return users,latencies

results=[]
with httpx.Client(timeout=60) as client, sync_playwright() as p:
    browser=p.chromium.launch(headless=True,args=["--use-angle=d3d11","--disable-background-timer-throttling","--disable-renderer-backgrounding"])
    for label,model,count in [("ordinary",ordinary(),20),("colorful_at_room_limits",colorful(),64)]:
        room="perf-"+label+"-"+str(int(time.time()))
        users,latencies=seed(client,room,model,count)
        context=browser.new_context(viewport={"width":1920,"height":1080})
        page=context.new_page();errors=[];page.on("pageerror",lambda e:errors.append(str(e)))
        page.goto(BASE,wait_until="networkidle",timeout=120000);page.wait_for_function("window.voxelReady===true",timeout=120000)
        page.evaluate("data=>{localStorage.setItem('voxel-kingdom:'+data.world_id,JSON.stringify(data));document.getElementById('room').value=data.world_id;}",users[0] | {"snapshot":None,"rules":None,"event":None})
        start=time.perf_counter();page.click("#join")
        page.wait_for_function("count=>window.voxelMetrics?.rendered===count && window.voxelMetrics.queue===0",arg=count,timeout=180000)
        loaded=time.perf_counter()-start
        page.evaluate("window.voxelUiActions.push('map')");page.wait_for_timeout(6000)
        measurements=[]
        for _ in range(15):
            page.wait_for_timeout(500);measurements.append(page.evaluate("window.voxelMetrics"))
        gpu=page.evaluate("""()=>{const gl=document.getElementById('canvas').getContext('webgl2');const ext=gl.getExtension('WEBGL_debug_renderer_info');return ext?gl.getParameter(ext.UNMASKED_RENDERER_WEBGL):'unknown';}""")
        snapshot=client.get(BASE+"/api/snapshot",headers={"Authorization":"Bearer "+users[0]["token"]}).json()["state"]
        asset=next(iter(snapshot["assets"].values()))
        entry={"case":label,"room":room,"buildings":count,"voxels_each":asset["voxel_count"],"faces_each":asset["face_count"],"total_voxels":asset["voxel_count"]*count,"total_unmerged_faces":asset["face_count"]*count,"viewport":[1920,1080],"canvas":page.evaluate("[document.getElementById('canvas').width,document.getElementById('canvas').height]"),"gpu":gpu,"browser":browser.version,"scene_ready_s":round(loaded,2),"fps_min":min(m["fps"] for m in measurements),"fps_average":round(sum(m["fps"] for m in measurements)/len(measurements),2),"frame_p95_ms_max":max(m["frame_p95_ms"] for m in measurements),"metrics":measurements[-1],"command_ms_p95":round(sorted(latencies)[int(len(latencies)*.95)],2),"console_errors":errors}
        page.screenshot(path=str(OUT/(label+".png")))
        print(json.dumps(entry,ensure_ascii=False),flush=True);results.append(entry)
        context.close()
    browser.close()
(OUT / "performance.json").write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding="utf-8")
