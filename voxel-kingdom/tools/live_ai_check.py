"""Actual paid provider acceptance: create, change exactly one cell, destroy."""
import json
import time
from pathlib import Path
import httpx
import sys
import os
import ssl
sys.stdout.reconfigure(encoding="utf-8")

base=os.environ.get("VOXEL_TEST_BASE_URL","http://127.0.0.1:8765")
room="ai-check-"+str(int(time.time()))
root=Path(__file__).resolve().parents[1]
out=Path(os.environ.get("VOXEL_TEST_OUTPUT", str(root / "artifacts/acceptance")))
out.mkdir(parents=True,exist_ok=True)
access=json.loads(Path(os.environ["VOXEL_TEST_ACCESS_FILE"]).read_text(encoding="utf-8")) if os.environ.get("VOXEL_TEST_ACCESS_FILE") else {}
verify=ssl.create_default_context(cafile=os.environ["VOXEL_TEST_CA"]) if os.environ.get("VOXEL_TEST_CA") else True
with httpx.Client(timeout=260,verify=verify,trust_env=False) as client:
    joined=client.post(base+"/api/join",json={"world_id":room,"name":"AI验收",**({"access_code":access["invite_code"]} if access else {})}).json()
    headers={"Authorization":"Bearer "+joined["token"]}
    def request(text, selection):
        response=client.post(base+"/api/chat",headers=headers,json={"request_id":"live-"+str(time.time_ns()),"text":text,"selection":selection})
        response.raise_for_status()
        result=response.json()
        print(json.dumps({"status":result["status"],"message":result["message"],"metrics":result.get("metrics"),"error":result.get("error")},ensure_ascii=False),flush=True)
        return result
    start=time.perf_counter()
    create=request("在选定地面位置创建一座尺寸不超过12×10×12的四塔城堡。墙体灰色#808080，四座塔顶蓝色#2060FF，有空心庭院和门洞。立即创建。",{"position":[20,1,20]})
    summary={"room":room,"model":create.get("metrics",{}).get("model"),"create_status":create["status"],"create_metrics":create.get("metrics"),"create_error":create.get("error")}
    if create["status"]=="completed":
        entity=create["receipt"]["result"]["entity"]
        snapshot=client.get(base+"/api/snapshot",headers=headers).json()["state"]
        before=snapshot["assets"][entity["blueprint_id"]]
        voxel=before["cells"][0][:3]
        paint=request("仅把选中的这一个方块改成#FF00CC，必须保留所有其他方块形状与颜色。",{"entity_id":entity["id"],"revision":entity["revision"],"position":entity["position"],"voxel":voxel})
        summary["paint_status"]=paint["status"];summary["paint_metrics"]=paint.get("metrics")
        snapshot=client.get(base+"/api/snapshot",headers=headers).json()["state"]
        current=snapshot["entities"][entity["id"]]
        after=snapshot["assets"][current["blueprint_id"]]
        old={tuple(c[:3]):before["palette"][c[3]] for c in before["cells"]}
        new={tuple(c[:3]):after["palette"][c[3]] for c in after["cells"]}
        changed=[list(k) for k in old if old[k]!=new.get(k)]
        summary.update(voxel_count=before["voxel_count"],face_count=before["face_count"],size=before["size"],changed_cells=changed,shape_preserved=set(old)==set(new),single_voxel_change=changed==[voxel] and new.get(tuple(voxel))=="#FF00CC")
        destroy=request("主动销毁这座属于我的选中建筑。",{"entity_id":entity["id"],"revision":current["revision"],"position":entity["position"]})
        summary["destroy_status"]=destroy["status"];summary["destroy_metrics"]=destroy.get("metrics")
        summary["removed"]=not client.get(base+"/api/snapshot",headers=headers).json()["state"]["entities"]
        (out / "deepseek-castle.json").write_text(json.dumps({k:before[k] for k in ("schema_version","name","size","encoding","palette","cells")},ensure_ascii=False),encoding="utf-8")
    summary["elapsed_s"]=round(time.perf_counter()-start,2)
    (out / "deepseek-live.json").write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding="utf-8")
    print(json.dumps(summary,ensure_ascii=False),flush=True)
    assert summary.get("single_voxel_change") and summary.get("removed"),"Actual AI acceptance did not complete"
