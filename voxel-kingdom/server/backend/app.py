import asyncio
from collections import defaultdict, deque
from contextlib import asynccontextmanager
import hashlib
import json
import mimetypes
import secrets
import time
from urllib.parse import urlparse

from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse, FileResponse
from fastapi.staticfiles import StaticFiles
from . import config, ai
from .models import RULES, LIMITS, GameError, fields, require, model_for_ai
from .store import Store, encoded
from .transport import compact, receipt_for_wire, chat_for_wire, event_for_wire

store = Store(config.DATABASE)
store.recover_pending()
locks = defaultdict(asyncio.Lock)
subscribers = defaultdict(set)
chat_locks = defaultdict(asyncio.Lock)
chat_rates = defaultdict(deque)
ai_slots = asyncio.Semaphore(4)
mimetypes.add_type("application/wasm", ".wasm")


class Subscription:
    def __init__(self, queue, assets, version=1):
        self.queue = queue
        self.assets = set(assets)
        self.version = version


@asynccontextmanager
async def lifespan(_):
    yield
    await ai.close()
    store.db.close()


app = FastAPI(title="Voxel Kingdom", lifespan=lifespan)


@app.middleware("http")
async def guard(request, call_next):
    # Mutations from a browser must originate from this application, not a foreign page.
    origin = request.headers.get("origin")
    if origin and urlparse(origin).netloc != request.headers.get("host"):
        return JSONResponse({"error": {"code": "ORIGIN_DENIED", "message": "不允许跨站请求"}}, status_code=403)
    try:
        content_length = int(request.headers.get("content-length", "0"))
        if content_length < 0:
            raise ValueError
    except ValueError:
        return JSONResponse({"error": {"code": "INVALID_SCHEMA", "message": "请求长度无效"}}, status_code=400)
    if content_length > LIMITS["command_bytes"]:
        return JSONResponse({"error": {"code": "MODEL_TOO_LARGE", "message": "请求超过 1 MiB"}}, status_code=413)
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    return response


@app.exception_handler(GameError)
async def game_error(_, exc):
    return JSONResponse({"error": {"code": exc.code, "message": exc.message}}, status_code=401 if exc.code == "UNAUTHENTICATED" else 400)


async def body(request):
    raw = bytearray()
    async for chunk in request.stream():
        require(len(raw) + len(chunk) <= LIMITS["command_bytes"], "MODEL_TOO_LARGE", "请求超过 1 MiB")
        raw.extend(chunk)
    try:
        data = json.loads(raw)
        require(isinstance(data, dict))
        return data
    except ValueError:
        raise GameError("INVALID_SCHEMA", "JSON 格式无效") from None


def identity(request):
    token = request.headers.get("authorization", "").removeprefix("Bearer ")
    return store.session(token)


def publish(room_id, event):
    if not event:
        return
    active_assets = set(store.room(room_id)["assets"])
    for subscriber in list(subscribers[room_id]):
        queue = subscriber.queue
        item = event_for_wire(event, subscriber.assets) if subscriber.version == 2 else event
        if "asset" in event and subscriber.version == 1:
            asset_id = event["asset"]["id"]
            if asset_id in subscriber.assets:
                item = {k: v for k, v in event.items() if k != "asset"}
            subscriber.assets.add(asset_id)
        if "asset" in event:
            subscriber.assets.add(event["asset"]["id"])
        subscriber.assets.intersection_update(active_assets)
        if queue.full():
            # A slow client must reload a snapshot rather than silently losing events.
            while not queue.empty():
                queue.get_nowait()
            queue.put_nowait({"kind": "resync_required"})
        else:
            queue.put_nowait(item)


@app.get("/api/health")
async def health():
    return {"ok": True, "rules_version": RULES["rules_version"], "ai_configured": bool(config.API_KEY), "model": config.MODEL,
            "invite_required": bool(config.JOIN_CODE), "protocol_versions": [1, 2]}


@app.post("/api/join")
async def join(request: Request):
    data = await body(request)
    fields(data, ("world_id", "name"), ("token", "access_code", "protocol_version"))
    require(type(data.get("protocol_version", 1)) is int and data.get("protocol_version", 1) in (1, 2), "PROTOCOL_MISMATCH", "客户端版本不兼容，请刷新页面")
    if config.JOIN_CODE and not data.get("token"):
        code = data.get("access_code", "")
        require(isinstance(code, str) and secrets.compare_digest(code.encode(), config.JOIN_CODE.encode()),
                "INVITE_REQUIRED", "请输入有效的邀请码")
    require(isinstance(data["world_id"], str))
    async with locks[data["world_id"]]:
        result = store.join(data["world_id"], data["name"], data.get("token"))
        publish(data["world_id"], result.pop("event", None))
        if data.get("protocol_version") == 2:
            result.pop("snapshot", None)
            result.pop("rules", None)
            result["protocol_version"] = 2
        return result


@app.get("/api/snapshot")
async def snapshot(request: Request):
    ident = identity(request)
    async with locks[ident["world_id"]]:
        return {"kind": "snapshot", "state": store.room(ident["world_id"]), "rules": RULES, "player_id": ident["player_id"]}


@app.post("/api/command")
async def command(request: Request):
    ident, data = identity(request), await body(request)
    async with locks[ident["world_id"]]:
        receipt = store.execute(ident, data)
        publish(ident["world_id"], receipt.get("event"))
        return receipt_for_wire(receipt) if request.headers.get("x-voxel-protocol") == "2" else receipt


@app.post("/api/chat")
async def chat(request: Request):
    ident, data = identity(request), await body(request)
    fields(data, ("request_id", "text", "selection"))
    require(isinstance(data["request_id"], str) and 1 <= len(data["request_id"]) <= 100)
    require(isinstance(data["text"], str) and 0 < len(data["text"].strip()) <= LIMITS["chat_chars"])
    fields(data["selection"], (), ("position", "entity_id", "revision", "voxel"))
    key = ident["world_id"] + ":" + ident["player_id"]
    digest = hashlib.sha256(encoded(data).encode()).hexdigest()
    # Concurrent duplicates see the same persisted result; never execute independently.
    async with chat_locks[key]:
        cached = store.chat_begin(ident, data["request_id"], digest)
        if cached is not None:
            return chat_for_wire(cached) if request.headers.get("x-voxel-protocol") == "2" else cached
        try:
            rate = chat_rates[key]
            now = time.monotonic()
            while rate and rate[0] < now - 60:
                rate.popleft()
            require(len(rate) < LIMITS["ai_requests_per_minute"], "RATE_LIMITED", f"每位玩家每分钟最多 {LIMITS['ai_requests_per_minute']} 次 AI 请求，请稍后再试")
            rate.append(now)
            state = store.room(ident["world_id"])
            selection = data["selection"]
            current = state["entities"].get(selection.get("entity_id", ""))
            if current:
                require(selection.get("revision") == current["revision"], "STALE_ENTITY", "选中建筑已更新，请重新选择")
            context = {"player_id": ident["player_id"], "world_id": ident["world_id"], "players": state["players"],
                       "entities": list(state["entities"].values()), "selection": selection,
                       "selected_blueprint": model_for_ai(state["assets"][current["blueprint_id"]]) if current else None}
            require(len(encoded(context).encode()) <= LIMITS["model_context_bytes"], "AI_CONTEXT_TOO_LARGE", "当前建筑模型过大，无法完整上传给 AI；请用模型导入功能修改")
            correction = None
            metrics = {}
            async with ai_slots:
                for attempt in range(2):
                    try:
                        output, metrics = await ai.generate(context, data["text"], correction)
                        if output["commands"]:
                            proposal = output["commands"][0]
                            cmd = {"schema_version": 1, "rules_version": output["rules_version"],
                                   "command_id": data["request_id"] + ":0", "world_id": ident["world_id"], **proposal}
                            async with locks[ident["world_id"]]:
                                store.execute(ident, cmd, dry_run=True)
                        break
                    except GameError as exc:
                        if attempt or exc.code not in ("INVALID_SCHEMA", "INVALID_COLOR", "AI_INVALID_OUTPUT", "MODEL_TOO_LARGE"):
                            raise
                        correction = {"code": exc.code, "message": exc.message}
            receipt = None
            if output["commands"]:
                async with locks[ident["world_id"]]:
                    receipt = store.execute(ident, cmd)
                    publish(ident["world_id"], receipt.get("event"))
            if receipt:
                message = "操作已执行。" if receipt["status"] == "applied" else receipt["error"]["message"]
            else:
                message = output["message"]
            metrics["attempts"] = attempt + 1
            result = {"status": "completed" if receipt and receipt["status"] == "applied" else output["status"],
                      "message": message, "plan": output["message"], "receipt": receipt, "metrics": metrics}
        except GameError as exc:
            result = {"status": "error", "message": exc.message, "error": {"code": exc.code, "message": exc.message}}
        except Exception:
            # Never return transport internals, prompts, credential values or raw provider bodies.
            result = {"status": "error", "message": "服务处理失败，未确认的操作请查询原请求结果。", "error": {"code": "INTERNAL_ERROR"}}
        store.chat_finish(ident, data["request_id"], result)
        return chat_for_wire(result) if request.headers.get("x-voxel-protocol") == "2" else result


@app.get("/api/chat/{request_id}")
async def chat_status(request_id: str, request: Request):
    ident = identity(request)
    row = store.db.execute("SELECT state,result FROM chats WHERE player=? AND room=? AND id=?",
                           (ident["player_id"], ident["world_id"], request_id)).fetchone()
    require(row is not None, "REQUEST_NOT_FOUND", "请求不存在")
    result = json.loads(row[1]) if row[0] == "done" else {"status": "pending", "message": "正在处理"}
    return chat_for_wire(result) if request.headers.get("x-voxel-protocol") == "2" else result


@app.websocket("/ws")
async def websocket(ws: WebSocket):
    origin = ws.headers.get("origin")
    if origin and urlparse(origin).netloc != ws.headers.get("host"):
        await ws.close(code=1008)
        return
    await ws.accept()
    queue, sender = asyncio.Queue(maxsize=128), None
    subscriber = None
    room_id = None
    try:
        auth = await asyncio.wait_for(ws.receive_json(), timeout=10)
        fields(auth, ("token",), ("protocol_version", "known_assets"))
        version = auth.get("protocol_version", 1)
        require(type(version) is int and version in (1, 2), "PROTOCOL_MISMATCH", "请刷新客户端")
        known = auth.get("known_assets", [])
        require(isinstance(known, list) and len(known) <= LIMITS["room_buildings"])
        require(all(isinstance(x, str) and len(x) == 67 and x.startswith('bp-') and all(c in '0123456789abcdef' for c in x[3:]) for x in known))
        require(isinstance(auth["token"], str))
        ident = store.session(auth["token"])
        room_id = ident["world_id"]
        async with locks[room_id]:
            state = store.room(room_id)
            subscriber = Subscription(queue, state["assets"], version)
            subscribers[room_id].add(subscriber)
            if version == 2:
                state = {**state, "assets": {key: compact(model) for key, model in state['assets'].items() if key not in known}}
            queue.put_nowait({"kind": "snapshot", "state": state, "rules": {"rules_version": RULES['rules_version']} if version == 2 else RULES,
                              "player_id": ident["player_id"], "protocol_version": version})

        async def send():
            while True:
                item = await queue.get()
                await ws.send_json(item)
                if item["kind"] == "resync_required":
                    await ws.close(code=1013)
                    return
        sender = asyncio.create_task(send())
        while True:
            data = await ws.receive_json()
            if data == {"kind": "ping"}:
                queue.put_nowait({"kind": "pong"})
    except (WebSocketDisconnect, asyncio.TimeoutError, GameError, ValueError, KeyError):
        try:
            await ws.close(code=1008)
        except RuntimeError:
            pass
    finally:
        if room_id:
            subscribers[room_id].discard(subscriber)
        if sender:
            sender.cancel()
            try:
                await sender
            except (asyncio.CancelledError, RuntimeError):
                pass


@app.get("/")
async def index():
    path = config.CLIENT_ROOT / "build" / "client-web" / "index.html"
    if path.exists():
        return FileResponse(path)
    return JSONResponse({"message": "请先执行 tools/export-web.ps1 生成网页客户端。", "health": "/api/health"}, status_code=503)


# Only the build output and web assets are exposed. Never expose project root or private config.
app.mount("/ui", StaticFiles(directory=config.CLIENT_ROOT / "client/web", check_dir=False), name="ui")
app.mount("/", StaticFiles(directory=config.CLIENT_ROOT / "build/client-web", check_dir=False), name="game")
