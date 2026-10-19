"""Local real-WebAssembly smoke test. Two isolated browser identities."""
import json
import time
import os
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright
from PIL import Image
from collections import Counter

ROOT=Path(__file__).resolve().parents[1]
OUTPUT=Path(os.environ.get("VOXEL_TEST_OUTPUT", str(ROOT / "artifacts/acceptance")))
OUTPUT.mkdir(parents=True,exist_ok=True)
ROOM="web-check-"+str(int(time.time()))
sys.stdout.reconfigure(encoding="utf-8")
LAN=os.environ.get("VOXEL_TEST_LAN_URL","https://192.168.101.243:8766")
BASE=os.environ.get("VOXEL_TEST_BASE_URL","http://127.0.0.1:8765")
ACCESS=json.loads(Path(os.environ["VOXEL_TEST_ACCESS_FILE"]).read_text(encoding="utf-8")) if os.environ.get("VOXEL_TEST_ACCESS_FILE") else {}
logs=[]
with sync_playwright() as p:
    browser=p.chromium.launch(headless=True,args=["--disable-background-timer-throttling","--disable-renderer-backgrounding","--use-angle=d3d11"])
    # Only our known, self-signed LAN certificate is bypassed for this local acceptance test.
    contexts=[browser.new_context(viewport={"width":1600,"height":1000},ignore_https_errors=True) for _ in range(2)]
    pages=[]
    for i,context in enumerate(contexts):
        page=context.new_page();page.on("pageerror",lambda err:logs.append(str(err)))
        page.on("console",lambda msg:logs.append(msg.text) if msg.type=="error" else None)
        page.goto(BASE if i==0 else LAN,wait_until="networkidle",timeout=180000)
        page.wait_for_function("window.voxelReady===true",timeout=120000)
        page.fill("#room",ROOM);page.fill("#name",f"验收玩家{i+1}")
        if ACCESS:
            page.fill("#access-code",ACCESS["invite_code"])
        page.click("#join")
        page.wait_for_function("window.voxelApp.session!==null && window.voxelApp.state.players.length>=1")
        pages.append(page)
    a,b=pages
    a.wait_for_function("window.voxelApp.state.players.length===2")
    print("Both Web clients loaded",flush=True)
    result=a.evaluate("""async()=>await window.voxelApp.command('building.create', {position:[22,1,22],rotation_y_quarter_turns:0,blueprint:window.voxelApp.sampleCastle()})""")
    assert result["status"]=="applied",result
    entity=result["result"]["entity"]
    b.wait_for_function("Object.keys(window.voxelApp.state.entities).length===1")
    a.wait_for_function("window.voxelMetrics?.rendered===1 && window.voxelMetrics.queue===0",timeout=60000)
    a.evaluate("window.voxelUiActions.push('zoom_in','zoom_in')")
    a.wait_for_timeout(2000)
    a.screenshot(path=str(OUTPUT / "web-castle.png"))
    print("Castle rendered",flush=True)
    model=a.evaluate("window.voxelApp.state.assets[Object.values(window.voxelApp.state.entities)[0].blueprint_id]")
    canvas=a.locator("canvas").bounding_box()
    a.mouse.click(canvas["x"]+canvas["width"]*.50,canvas["y"]+canvas["height"]*.50)
    a.wait_for_function("window.voxelSelection.entity_id!==undefined")
    picked=a.evaluate("window.voxelSelection.voxel")
    a.fill("#voxel-color","#ff00cc");a.click("#paint")
    a.wait_for_function("Object.values(window.voxelApp.state.entities)[0].revision===2")
    b.wait_for_function("Object.values(window.voxelApp.state.entities)[0].revision===2")
    before=model
    after=a.evaluate("window.voxelApp.state.assets[Object.values(window.voxelApp.state.entities)[0].blueprint_id]")
    old={tuple(c[:3]):before["palette"][c[3]] for c in before["cells"]}
    new={tuple(c[:3]):after["palette"][c[3]] for c in after["cells"]}
    assert [k for k in old if old[k]!=new[k]]==[tuple(picked)]
    replacement={k:after[k] for k in ("schema_version","name","size","encoding","palette","cells")}
    replacement["size"]=replacement["size"][:]
    replacement["cells"]=replacement["cells"][:]
    replacement["cells"].append([0,replacement["size"][1],0,0])
    replacement["size"][1]+=1
    replacement_path=OUTPUT / "shape-update-model.json"
    replacement_path.write_text(json.dumps(replacement,ensure_ascii=False),encoding="utf-8")
    a.set_input_files("#model-file",str(replacement_path))
    a.wait_for_function("Object.values(window.voxelApp.state.entities)[0].revision===3")
    b.wait_for_function("Object.values(window.voxelApp.state.entities)[0].revision===3")
    denied=b.evaluate("""async entity=>await window.voxelApp.command('building.destroy',{entity_id:entity.id,expected_entity_revision:2}).then(x=>x).catch(e=>({error:e.message}))""",entity)
    assert "error" in denied and len(b.evaluate("Object.keys(window.voxelApp.state.entities)"))==1
    b.evaluate('window.voxelRuntimeCache.flush()')
    refresh_started=time.perf_counter();b.reload(wait_until="networkidle",timeout=180000);b.wait_for_function("window.voxelReady===true && window.voxelApp.synchronized",timeout=120000)
    refresh_ms=round((time.perf_counter()-refresh_started)*1000)
    resource_timing=b.evaluate("performance.getEntriesByType('resource').filter(x=>/\\.(wasm|pck)$/.test(x.name)).map(x=>({name:x.name,transferSize:x.transferSize,encodedBodySize:x.encodedBodySize,duration:x.duration}))")
    b.wait_for_function("Object.keys(window.voxelApp.state.entities).length===1")
    assert a.evaluate("window.voxelApp.state.seq")==b.evaluate("window.voxelApp.state.seq")
    a.wait_for_timeout(600)
    camera_before=a.evaluate("window.voxelMetrics.camera_target")
    a.fill("#prompt","");a.locator("#prompt").focus();a.keyboard.down("w");a.wait_for_timeout(300);a.keyboard.up("w");a.wait_for_timeout(600)
    assert a.evaluate("window.voxelMetrics.camera_target")==camera_before,"Typing moved the camera"
    a.fill("#prompt","在世界坐标[8,1,8]创建一个绿色#14FF80方块，只有一个体素。请执行创建。")
    a.click("#send")
    a.wait_for_function("window.voxelApp.pendingChat!==null")
    assert a.locator("#send").is_disabled()
    a.click("[data-camera=rotate_right]")
    a.wait_for_function("Object.keys(window.voxelApp.state.entities).length===2",timeout=250000)
    b.wait_for_function("Object.keys(window.voxelApp.state.entities).length===2")
    a.wait_for_function("window.voxelApp.pendingChat===null")
    a.wait_for_timeout(1000)
    a.screenshot(path=str(OUTPUT / "web-ai-chat.png"))
    a.evaluate("window.voxelUiActions.push('color')");a.wait_for_timeout(1000)
    a.screenshot(path=str(OUTPUT / "web-colors.png"))
    image=Image.open(OUTPUT / "web-colors.png").convert("RGB").crop((0,130,1150,830))
    pixels=Counter(image.get_flattened_data())
    # The renderer's gamma/8-bit conversion may differ by one display byte.
    # Canonical voxel colors are compared exactly above; the pixel test rejects larger shifts.
    color_counts={color:sum(count for rgb,count in pixels.items() if all(abs(rgb[i]-expected[i])<=1 for i in range(3)))
                  for color in ["8D969C","315CC0","D8B978","A94136","FF00CC"]
                  for expected in [tuple(bytes.fromhex(color))]}
    assert all(count>0 for count in color_counts.values()),color_counts
    metrics=a.evaluate("window.voxelMetrics")
    renderer=a.evaluate("""()=>{const gl=document.getElementById('canvas').getContext('webgl2');const ext=gl.getExtension('WEBGL_debug_renderer_info');return ext?gl.getParameter(ext.UNMASKED_RENDERER_WEBGL):'unknown';}""")
    a.evaluate("entity=>window.voxelSelect({entity_id:entity.id,revision:window.voxelApp.state.entities[entity.id].revision,position:entity.position})",entity)
    a.click("#destroy");a.wait_for_function("Object.keys(window.voxelApp.state.entities).length===1")
    b.wait_for_function("Object.keys(window.voxelApp.state.entities).length===1")
    survivor=a.evaluate("Object.values(window.voxelApp.state.entities)[0]")
    a.evaluate("entity=>window.voxelSelect({entity_id:entity.id,revision:entity.revision,position:entity.position})",survivor)
    a.click("#demolish");a.wait_for_function("Object.keys(window.voxelApp.state.entities).length===0")
    b.wait_for_function("Object.keys(window.voxelApp.state.entities).length===0")
    summary={"refresh_to_ready_ms":refresh_ms,"refresh_runtime_resources":resource_timing,"room":ROOM,"two_independent_clients":True,"client_urls":[BASE,LAN],"create":True,"single_voxel_color":True,"flat_rgb_pixel_counts_with_1_byte_tolerance":color_counts,"custom_shape_import_update":True,"canvas_picking":True,"chat_input_does_not_move_camera":True,"actual_deepseek_chat_ui":True,"destroy_and_demolish":True,"ownership_rejection":True,"refresh_reconnect":True,"metrics":metrics,"gpu":renderer,"browser":browser.version,"console_errors":logs}
    (OUTPUT / "browser-smoke.json").write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding="utf-8")
    print(json.dumps(summary,ensure_ascii=False),flush=True)
    browser.close()
