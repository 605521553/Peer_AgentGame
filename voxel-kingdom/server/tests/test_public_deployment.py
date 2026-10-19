from tests.test_api import client, join
from backend import config


def test_invitation_blocks_new_identities_but_allows_session_resume(client, monkeypatch):
    monkeypatch.setattr(config, "JOIN_CODE", "test-invitation")
    assert client.get('/api/health').json()['invite_required'] is True
    for code in (None, "wrong", {"unexpected": "object"}, "邀请"):
        response = client.post('/api/join', json={"world_id": "invite", "name": "A", "access_code": code})
        assert response.json()['error']['code'] == 'INVITE_REQUIRED'
    payload = {"world_id": "invite", "name": "A", "access_code": "test-invitation"}
    accepted = client.post('/api/join', json=payload).json()
    assert 'token' in accepted
    resumed = client.post('/api/join', json={"world_id": "invite", "name": "A", "token": accepted['token']})
    assert resumed.json()['player_id'] == accepted['player_id']
    invalid = client.post('/api/join', json={"world_id": "invite", "name": "A", "token": "fake"})
    assert invalid.status_code == 401


def test_invitation_disabled_for_local_default(client, monkeypatch):
    monkeypatch.setattr(config, "JOIN_CODE", "")
    assert 'token' in join(client)


def test_malformed_content_length_is_rejected(client):
    assert client.post('/api/join', content='{}', headers={'content-length': 'broken'}).status_code == 400


def test_chunked_request_size_is_limited(client):
    response = client.post('/api/join', content=iter([b'x' * 600000, b'y' * 600000]))
    assert response.json()['error']['code'] == 'MODEL_TOO_LARGE'
