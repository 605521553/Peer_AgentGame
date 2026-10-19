import json
import pytest
from starlette.websockets import WebSocketDisconnect
from tests.test_api import client, join, auth
from tests.test_authority import cmd
from backend import app as module
from backend.models import normalize_model
from backend.transport import compact, event_for_wire


def v2(session):
    return {**auth(session), 'X-Voxel-Protocol': '2'}


def test_join_v2_is_identity_only_and_resumes_same_player(client):
    a=client.post('/api/join',json={'world_id':'v2','name':'A','protocol_version':2}).json()
    assert 'snapshot' not in a and 'rules' not in a and a['protocol_version']==2
    b=client.post('/api/join',json={'world_id':'v2','name':'A','protocol_version':2,'token':a['token']}).json()
    assert a['player_id']==b['player_id']
    assert len(module.store.room('v2')['players'])==1


def test_v2_snapshot_known_models_patch_and_light_receipt(client):
    a=join(client)
    first=client.post('/api/command',headers=v2(a),json=cmd(a)).json()
    assert 'event' not in first
    entity=first['result']['entity'];asset_id=entity['blueprint_id']
    with client.websocket_connect('/ws') as ws:
        ws.send_json({'token':a['token'],'protocol_version':2,'known_assets':[asset_id]})
        snapshot=ws.receive_json()
        assert snapshot['state']['assets']=={} and entity['id'] in snapshot['state']['entities']
        update=cmd(a,'building.paint_voxel',{'entity_id':entity['id'],'expected_entity_revision':1,'voxel':[0,0,0],'color':'#123456'},'patch')
        receipt=client.post('/api/command',headers=v2(a),json=update).json()
        patch=ws.receive_json()
        assert 'event' not in receipt and 'asset' not in patch
        assert patch['voxel_patch']['base_blueprint_id']==asset_id
        assert patch['voxel_patch']['base_revision']==1
        assert patch['voxel_patch']['color']=='#123456'
        assert patch['entity']['revision']==2
        assert client.post('/api/command',headers=v2(a),json=update).json()==receipt
    with client.websocket_connect('/ws') as ws:
        ws.send_json({'token':a['token'],'protocol_version':2,'known_assets':[]})
        restored=ws.receive_json()
        assert len(restored['state']['assets'])==1
        wire=next(iter(restored['state']['assets'].values()))
        norm=normalize_model({k:v for k,v in wire.items() if k not in ('id','voxel_count','face_count')})
        assert norm['id']==patch['entity']['blueprint_id']


def test_compact_encoding_is_lossless_and_never_larger():
    model=normalize_model({'schema_version':1,'name':'cube','size':[20,20,20],'palette':['#808080'],'encoding':'box_ops_v1','ops':[{'op':'fill_box','min':[0,0,0],'max_exclusive':[20,20,20],'color':0}]})
    wire=compact(model)
    assert wire['encoding']=='box_ops_v1'
    assert len(json.dumps(wire))<len(json.dumps(model))/100
    assert normalize_model({k:v for k,v in wire.items() if k not in ('id','voxel_count','face_count')})==model


def test_patch_without_base_falls_back_to_model(client):
    a=join(client);e=client.post('/api/command',headers=auth(a),json=cmd(a)).json()['result']['entity']
    change=cmd(a,'building.paint_voxel',{'entity_id':e['id'],'expected_entity_revision':1,'voxel':[0,0,0],'color':'#ABCDEF'},'new')
    event=client.post('/api/command',headers=auth(a),json=change).json()['event']
    wire=event_for_wire(event,set())
    assert 'asset' in wire and 'voxel_patch' not in wire


def test_bad_known_asset_list_closes_connection(client):
    a=join(client)
    with client.websocket_connect('/ws') as ws:
        ws.send_json({'token':a['token'],'protocol_version':2,'known_assets':['fake']*65})
        with pytest.raises(WebSocketDisconnect): ws.receive_json()


def test_chat_v2_does_not_duplicate_event(client,monkeypatch):
    a=join(client)
    async def generate(*args,**kwargs):
        return {'schema_version':1,'rules_version':'stage-01-v1','status':'commands','message':'建造','commands':[{'type':'building.create','payload':cmd(a)['payload']}]},{}
    monkeypatch.setattr(module.ai,'generate',generate)
    data={'request_id':'v2-ai','text':'建造','selection':{}}
    result=client.post('/api/chat',headers=v2(a),json=data).json()
    assert result['status']=='completed' and 'event' not in result['receipt']
    assert client.post('/api/chat',headers=v2(a),json=data).json()==result
    assert client.get('/api/chat/v2-ai',headers=v2(a)).json()==result
