import copy
import json
import asyncio
import httpx
import pytest
from backend.models import normalize_model, model_for_ai, GameError, RULES
from backend.store import Store
from backend import ai


def model(color="#FF4040", size=None):
    return {"schema_version":1,"name":"测试模型","size":size or [1,1,1],"encoding":"cells_v1","palette":[color],"cells":[[0,0,0,0]]}


@pytest.fixture
def game(tmp_path):
    db=Store(tmp_path / "world.db")
    a=db.join("test", "甲")
    b=db.join("test", "乙")
    yield db,a,b
    db.db.close()


def cmd(identity, kind="building.create", payload=None, cid="c1"):
    return {"schema_version":1,"rules_version":RULES["rules_version"],"command_id":cid,"world_id":identity["world_id"],"type":kind,
            "payload":payload or {"position":[2,1,2],"rotation_y_quarter_turns":0,"blueprint":model()}}


def create(game):
    db,a,_=game
    return db.execute(a,cmd(a))["result"]["entity"]


def test_command_retries_and_persistent_idempotency(game):
    db,a,_=game
    request=cmd(a)
    result=db.execute(a,request)
    assert db.execute(a,request)==result
    assert len(db.room("test")["entities"])==1
    request["payload"]["position"][0]=8
    with pytest.raises(GameError,match="同一命令"):
        db.execute(a,request)
    assert len(db.room("test")["entities"])==1


@pytest.mark.parametrize("kind",["building.demolish","building.destroy","building.update_model","building.paint_voxel"])
def test_only_owner_can_modify(game,kind):
    db,a,b=game
    entity=create(game)
    payload={"entity_id":entity["id"],"expected_entity_revision":1}
    if kind.endswith("update_model"):payload["blueprint"]=model()
    if kind.endswith("paint_voxel"):payload.update(voxel=[0,0,0],color="#00FF00")
    before=db.room("test")
    result=db.execute(b,cmd(b,kind,payload))
    assert result["error"]["code"]=="PERMISSION_DENIED"
    assert db.room("test")==before


def test_conflict_update_and_stale_are_atomic(game):
    db,a,_=game
    entity=create(game)
    db.execute(a,cmd(a,payload={"position":[4,1,2],"rotation_y_quarter_turns":0,"blueprint":model()},cid="second"))
    before=db.room("test")
    larger=model(size=[3,1,1])
    result=db.execute(a,cmd(a,"building.update_model",{"entity_id":entity["id"],"expected_entity_revision":1,"blueprint":larger},"update"))
    assert result["error"]["code"]=="POSITION_OCCUPIED"
    assert db.room("test")==before
    result=db.execute(a,cmd(a,"building.demolish",{"entity_id":entity["id"],"expected_entity_revision":0},"stale"))
    assert result["error"]["code"]=="STALE_ENTITY"


def test_single_voxel_color_update_preserves_instance(game):
    db,a,_=game
    initial=model(size=[2,1,1]);initial["cells"].append([1,0,0,0])
    entity=db.execute(a,cmd(a,payload={"position":[2,1,2],"rotation_y_quarter_turns":0,"blueprint":initial}))["result"]["entity"]
    changed=copy.deepcopy(initial);changed["palette"].append("#2060FF");changed["cells"][1][3]=1
    result=db.execute(a,cmd(a,"building.update_model",{"entity_id":entity["id"],"expected_entity_revision":1,"blueprint":changed},"paint"))
    new=result["result"]["entity"]
    for key in ("id","owner_id","position","name","rotation_y_quarter_turns"):assert new[key]==entity[key]
    assert new["revision"]==2
    asset=db.room("test")["assets"][new["blueprint_id"]]
    colors=[asset["palette"][c[3]] for c in asset["cells"]]
    assert colors==["#FF4040","#2060FF"]


@pytest.mark.parametrize("kind",["building.demolish","building.destroy"])
def test_remove_releases_occupancy_and_assets(game,kind):
    db,a,_=game
    e=create(game)
    result=db.execute(a,cmd(a,kind,{"entity_id":e["id"],"expected_entity_revision":1},"remove"))
    assert result["status"]=="applied"
    assert not db.room("test")["assets"]
    assert db.execute(a,cmd(a,cid="rebuild"))["status"]=="applied"


def test_rotation_and_zone(game):
    db,a,_=game
    request=cmd(a,payload={"position":[62,1,2],"rotation_y_quarter_turns":1,"blueprint":model(size=[1,1,3])})
    result=db.execute(a,request)
    assert result["error"]["code"]=="OUTSIDE_BUILD_ZONE"
    assert not db.room("test")["entities"]


def test_spoofed_identity_fields_rejected(game):
    db,a,b=game
    request=cmd(a);request["actor_player_id"]=b["player_id"]
    with pytest.raises(GameError):db.execute(a,request)
    request=cmd(a);request["payload"]["owner_id"]=b["player_id"]
    assert db.execute(a,request)["status"]=="rejected"


@pytest.mark.parametrize("change",[
    lambda m:m.update(size=[33,1,1]),
    lambda m:m.update(palette=["#FF00FF00"]),
    lambda m:m.update(palette=["red"]),
    lambda m:m["cells"].append([0,0,0,0]),
    lambda m:m.update(cells=[[-1,0,0,0]]),
    lambda m:m.update(cells=[[0,0,0,9]]),
    lambda m:m.update(cells=[[False,0,0,0]]),
    lambda m:m.update(cells=[]),
    lambda m:m.update(size=[1,2,1],cells=[[0,1,0,0]]),
    lambda m:m.update(extra="code"),
])
def test_invalid_models(change):
    m=model();change(m)
    with pytest.raises(GameError):normalize_model(m)


def test_surface_budget_and_box_expansion_budget():
    m=model(size=[32,32,32]);m["cells"]=[[x,y,z,0] for x in range(16) for y in range(16) for z in range(16) if (x+y+z)%2==0]
    assert normalize_model(m)["face_count"]==12288
    m["cells"]=[[x,y,z,0] for x in range(20) for y in range(20) for z in range(20) if (x+y+z)%2==0]
    with pytest.raises(GameError):normalize_model(m)
    m={"schema_version":1,"name":"计算量限制","size":[32,32,32],"encoding":"box_ops_v1","palette":["#123456"],"ops":[{"op":"fill_box","min":[0,0,0],"max_exclusive":[32,32,32],"color":0}]*33}
    with pytest.raises(GameError,match="计算量"):normalize_model(m)


def test_box_and_cells_share_same_content_hash():
    a=model(size=[2,1,1]);a["cells"].append([1,0,0,0])
    b={"schema_version":1,"name":"不同名字","size":[2,1,1],"encoding":"box_ops_v1","palette":["#ff4040"],"ops":[{"op":"fill_box","min":[0,0,0],"max_exclusive":[2,1,1],"color":0}]}
    assert normalize_model(a)["id"]==normalize_model(b)["id"]
    assert normalize_model(a)["face_count"]==10


def test_room_restart_preserves_state_and_command(tmp_path):
    path=tmp_path / "world.db"
    db=Store(path);a=db.join("persist","甲");request=cmd(a);result=db.execute(a,request);state=db.room("persist");db.db.close()
    reopened=Store(path)
    assert reopened.session(a["token"])["player_id"]==a["player_id"]
    assert reopened.room("persist")==state
    assert reopened.execute(a,request)==result
    reopened.db.close()


def test_room_and_model_reuse_access(game):
    db,a,b=game
    entity=create(game)
    request=cmd(b,payload={"position":[66,1,2],"rotation_y_quarter_turns":0,"blueprint_id":entity["blueprint_id"]})
    assert db.execute(b,request)["error"]["code"]=="PERMISSION_DENIED"
    request=cmd(a);request["world_id"]="other"
    with pytest.raises(GameError):db.execute(a,request)


def test_rules_change_and_player_count_limit(game):
    db,a,_=game
    request=cmd(a);request["rules_version"]="old"
    assert db.execute(a,request)["error"]["code"]=="RULES_CHANGED"
    for _ in range(2):db.join("test","访客")
    with pytest.raises(GameError):db.join("test","第五人")


def test_ai_all_calls_include_full_rules_and_no_secret(monkeypatch):
    monkeypatch.setattr(ai.config,"API_KEY","test-key-that-must-never-be-in-prompt")
    calls=[]
    async def handler(request):
        payload=json.loads(request.content);calls.append(payload)
        assert json.JSONDecoder().raw_decode(payload["messages"][0]["content"].split("完整规则 JSON：\n")[1])[0]==RULES
        assert "test-key-that-must-never-be-in-prompt" not in json.dumps(payload)
        content=json.dumps({"schema_version":1,"rules_version":RULES["rules_version"],"status":"answer","message":"状态正常","commands":[]})
        return httpx.Response(200,json={"choices":[{"finish_reason":"stop","message":{"content":content}}],"usage":{}})
    async def run():
        for correction in (None,{"code":"INVALID_SCHEMA"}):
            result,_=await ai.generate({},"查询",correction,transport=httpx.MockTransport(handler))
            assert result["status"]=="answer"
    asyncio.run(run());assert len(calls)==2


@pytest.mark.parametrize("response",[
    {"choices":[{"finish_reason":"length","message":{"content":"{}"}}]},
    {"choices":[{"finish_reason":"stop","message":{"content":""}}]},
    {"choices":[{"finish_reason":"stop","message":{"content":"{broken"}}]},
])
def test_ai_empty_truncated_malformed(response,monkeypatch):
    monkeypatch.setattr(ai.config,"API_KEY","test")
    async def run():
        with pytest.raises(GameError):
            await ai.generate({},"test",transport=httpx.MockTransport(lambda _:httpx.Response(200,json=response)))
    asyncio.run(run())


def test_crash_recovers_committed_chat_without_reexecuting(game):
    db,a,_=game
    db.chat_begin(a,"chat1","digest")
    result=db.execute(a,cmd(a,cid="chat1:0"))
    db.recover_pending()
    cached=db.chat_begin(a,"chat1","digest")
    assert cached["receipt"]==result
    assert len(db.room("test")["entities"])==1


def test_prompt_compression_is_lossless():
    blueprint={"schema_version":1,"name":"空心异色小屋","size":[8,5,8],"encoding":"box_ops_v1","palette":["#123456","#ABCDEF"],"ops":[{"op":"fill_box","min":[0,0,0],"max_exclusive":[8,5,8],"color":0},{"op":"clear_box","min":[1,1,1],"max_exclusive":[7,5,7]},{"op":"set_voxel","position":[0,4,0],"color":1}]}
    canonical=normalize_model(blueprint)
    compressed=model_for_ai(canonical)
    assert normalize_model(compressed)["id"]==canonical["id"]
    assert len(json.dumps(compressed))<len(json.dumps(canonical))


def test_paint_command_preserves_other_cells(game):
    db,a,_=game
    m=model(size=[2,1,1]);m["cells"].append([1,0,0,0])
    entity=db.execute(a,cmd(a,payload={"position":[2,1,2],"rotation_y_quarter_turns":0,"blueprint":m}))["result"]["entity"]
    result=db.execute(a,cmd(a,"building.paint_voxel",{"entity_id":entity["id"],"expected_entity_revision":1,"voxel":[1,0,0],"color":"#00FF00"},"paint-one"))
    asset=result["event"]["asset"]
    assert [asset["palette"][c[3]] for c in asset["cells"]]==["#FF4040","#00FF00"]
