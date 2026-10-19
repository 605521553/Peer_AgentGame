import copy
from collections import defaultdict
import asyncio
import pytest
from fastapi.testclient import TestClient
from backend import app as module
from backend.models import GameError, RULES
from backend.store import Store
from tests.test_authority import model, cmd


@pytest.fixture
def client(tmp_path,monkeypatch):
    monkeypatch.setattr(module,"store",Store(tmp_path / "api.db"))
    monkeypatch.setattr(module,"locks",defaultdict(asyncio.Lock))
    monkeypatch.setattr(module,"chat_locks",defaultdict(asyncio.Lock))
    monkeypatch.setattr(module,"subscribers",defaultdict(set))
    monkeypatch.setattr(module,"chat_rates",defaultdict(lambda:__import__('collections').deque()))
    with TestClient(module.app) as client:
        yield client


def join(client,name="甲",room="api-test"):
    return client.post("/api/join",json={"world_id":room,"name":name}).json()


def auth(session):
    return {"Authorization":"Bearer "+session["token"]}


def test_websocket_snapshot_order_and_asset_cache(client):
    a,b=join(client),join(client,"乙")
    with client.websocket_connect("/ws") as ws:
        ws.send_json({"token":b["token"]})
        snapshot=ws.receive_json();assert snapshot["kind"]=="snapshot"
        first=client.post("/api/command",headers=auth(a),json=cmd(a)).json()
        event=ws.receive_json();assert event["seq"]==snapshot["state"]["seq"]+1 and "asset" in event
        request=cmd(a,cid="second");request["payload"]["position"]=[4,1,2]
        assert client.post("/api/command",headers=auth(a),json=request).json()["status"]=="applied"
        event=ws.receive_json();assert event["seq"]==first["seq"]+1 and "asset" not in event
        ws.send_json({"kind":"ping"});assert ws.receive_json()=={"kind":"pong"}


def test_http_origin_auth_and_payload_limit(client):
    assert client.get("/api/snapshot").status_code==401
    assert client.post("/api/join",headers={"Origin":"https://foreign.example"},json={"world_id":"a","name":"a"}).status_code==403
    assert client.post("/api/join",content=b"x"*1048577).status_code==413
    assert client.post("/api/join",json={"world_id":"a","name":"a","token":{"fake":True}}).status_code==401
    a=join(client)
    response=client.get("/api/snapshot",headers=auth(a))
    assert response.status_code==200
    assert "token" not in response.json()["state"]


def test_chat_idempotent_and_authoritative_receipt(client,monkeypatch):
    a=join(client)
    calls=[]
    async def generate(context,text,correction=None):
        calls.append(context)
        return {"schema_version":1,"rules_version":RULES["rules_version"],"status":"commands","message":"计划创建","commands":[{"type":"building.create","payload":cmd(a)["payload"]}]},{"model":"fake"}
    monkeypatch.setattr(module.ai,"generate",generate)
    request={"request_id":"chat1","text":"建造","selection":{"position":[2,1,2]}}
    result=client.post("/api/chat",headers=auth(a),json=request).json()
    assert result["receipt"]["status"]=="applied" and result["message"]=="操作已执行。"
    assert client.post("/api/chat",headers=auth(a),json=request).json()==result
    assert len(calls)==1
    assert client.get("/api/chat/chat1",headers=auth(a)).json()==result
    request["text"]="其他请求"
    assert client.post("/api/chat",headers=auth(a),json=request).status_code==400


def test_failed_ai_request_is_safe_and_cached(client,monkeypatch):
    a=join(client);calls=[]
    async def generate(*args,**kwargs):
        calls.append(1);raise GameError("AI_TIMEOUT","超时")
    monkeypatch.setattr(module.ai,"generate",generate)
    request={"request_id":"fail1","text":"建造","selection":{}}
    result=client.post("/api/chat",headers=auth(a),json=request).json()
    assert result["error"]["code"]=="AI_TIMEOUT"
    assert client.post("/api/chat",headers=auth(a),json=request).json()==result
    assert len(calls)==1
    assert not client.get("/api/snapshot",headers=auth(a)).json()["state"]["entities"]


def test_late_ai_output_cannot_overwrite_new_revision(client,monkeypatch):
    a=join(client)
    e=client.post("/api/command",headers=auth(a),json=cmd(a)).json()["result"]["entity"]
    async def generate(context,text,correction=None):
        update=cmd(a,"building.paint_voxel",{"entity_id":e["id"],"expected_entity_revision":1,"voxel":[0,0,0],"color":"#00FF00"},"external")
        module.store.execute(a,update)
        return {"schema_version":1,"rules_version":RULES["rules_version"],"status":"commands","message":"计划销毁","commands":[{"type":"building.destroy","payload":{"entity_id":e["id"],"expected_entity_revision":1}}]},{}
    monkeypatch.setattr(module.ai,"generate",generate)
    result=client.post("/api/chat",headers=auth(a),json={"request_id":"late","text":"销毁","selection":{"entity_id":e["id"],"revision":1}}).json()
    assert result["error"]["code"]=="STALE_ENTITY"
    assert module.store.room(a["world_id"])["entities"][e["id"]]["revision"]==2
