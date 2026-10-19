"""SQLite transactions persist state, event ordering, and idempotency together."""
import copy
import hashlib
import json
import secrets
import sqlite3
import time
from pathlib import Path

from .models import RULES, LIMITS, GameError, fields, integer, normalize_model, overlaps, rect, require, vector


def encoded(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


class Store:
    def __init__(self, path):
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.executescript("""
          CREATE TABLE IF NOT EXISTS rooms(id TEXT PRIMARY KEY, state TEXT NOT NULL);
          CREATE TABLE IF NOT EXISTS sessions(token_hash TEXT PRIMARY KEY, player TEXT NOT NULL, room TEXT NOT NULL);
          CREATE TABLE IF NOT EXISTS commands(player TEXT, room TEXT, id TEXT, hash TEXT, result TEXT,
            PRIMARY KEY(player,room,id));
          CREATE TABLE IF NOT EXISTS chats(player TEXT, room TEXT, id TEXT, hash TEXT, state TEXT, result TEXT,
            PRIMARY KEY(player,room,id));
          CREATE TABLE IF NOT EXISTS events(room TEXT, seq INTEGER, data TEXT, PRIMARY KEY(room,seq));
        """)

    def room(self, room_id):
        row = self.db.execute("SELECT state FROM rooms WHERE id=?", (room_id,)).fetchone()
        return json.loads(row[0]) if row else {"world_id": room_id, "seq": 0, "players": [], "entities": {}, "assets": {}}

    def save(self, state):
        self.db.execute("INSERT INTO rooms VALUES(?,?) ON CONFLICT(id) DO UPDATE SET state=excluded.state",
                        (state["world_id"], encoded(state)))

    def session(self, token):
        require(isinstance(token, str) and 1 <= len(token) <= 200, "UNAUTHENTICATED", "会话格式不合法")
        row = self.db.execute("SELECT player,room FROM sessions WHERE token_hash=?",
                              (hashlib.sha256(token.encode()).hexdigest(),)).fetchone()
        require(row is not None, "UNAUTHENTICATED", "会话失效，请重新进入房间")
        return {"player_id": row[0], "world_id": row[1]}

    def join(self, room_id, name, token=None):
        require(isinstance(room_id, str) and 1 <= len(room_id) <= 40 and all(c.isalnum() or c in "-_" for c in room_id), message="房间名仅允许字母、数字、横线与下划线")
        require(isinstance(name, str) and 1 <= len(name.strip()) <= 24, message="玩家名称长度为 1–24")
        if token:
            identity = self.session(token)
            require(identity["world_id"] == room_id, "PERMISSION_DENIED", "会话不属于该房间")
            return {**identity, "token": token, "snapshot": self.room(room_id), "rules": RULES}
        with self.db:
            state = self.room(room_id)
            require(len(state["players"]) < LIMITS["players"], "ROOM_FULL", "房间最多四位玩家，请进入新房间")
            slot = len(state["players"])
            x, z = (slot % 2) * 64, (slot // 2) * 64
            player = {"id": "player-" + secrets.token_hex(6), "name": name.strip(), "slot": slot, "zone": [x, z, x + 64, z + 64]}
            token = secrets.token_urlsafe(32)
            state["players"].append(player)
            event = self.event(state, "player.joined", {"player": player})
            self.save(state)
            self.db.execute("INSERT INTO sessions VALUES(?,?,?)", (hashlib.sha256(token.encode()).hexdigest(), player["id"], room_id))
        return {"player_id": player["id"], "world_id": room_id, "token": token, "snapshot": state, "rules": RULES, "event": event}

    def event(self, state, kind, data):
        state["seq"] += 1
        event = {"kind": "event", "world_id": state["world_id"], "seq": state["seq"], "type": kind, **data}
        self.db.execute("INSERT INTO events VALUES(?,?,?)", (state["world_id"], state["seq"], encoded(event)))
        return event

    def execute(self, identity, command, dry_run=False):
        require(len(encoded(command).encode()) <= LIMITS["command_bytes"], "MODEL_TOO_LARGE", "命令文件超过 1 MiB")
        fields(command, ("schema_version", "rules_version", "command_id", "world_id", "type", "payload"))
        require(command["schema_version"] == 1 and integer(command["schema_version"]))
        require(command["world_id"] == identity["world_id"], "PERMISSION_DENIED", "无权操作此房间")
        require(isinstance(command["command_id"], str) and 1 <= len(command["command_id"]) <= 128)
        require(isinstance(command["type"], str) and command["type"] in RULES["commands"], message="当前阶段不支持此命令")
        require(isinstance(command["payload"], dict))
        player, room_id, cmd_id = identity["player_id"], identity["world_id"], command["command_id"]
        digest = hashlib.sha256(encoded(command).encode()).hexdigest()
        row = self.db.execute("SELECT hash,result FROM commands WHERE player=? AND room=? AND id=?", (player, room_id, cmd_id)).fetchone()
        if row:
            require(row[0] == digest, "COMMAND_ID_CONFLICT", "同一命令 ID 不能发送不同内容")
            return json.loads(row[1])
        state = self.room(room_id)
        require(any(p["id"] == player for p in state["players"]), "PERMISSION_DENIED", "尚未加入房间")
        try:
            require(command["rules_version"] == RULES["rules_version"], "RULES_CHANGED", "规则已经更新，请重新生成命令")
            result, change = self.apply(state, player, command)
            if dry_run:
                return {"status": "valid", "result": result}
        except GameError as exc:
            if dry_run:
                raise
            receipt = {"command_id": cmd_id, "status": "rejected", "error": {"code": exc.code, "message": exc.message}, "seq": state["seq"]}
            with self.db:
                self.db.execute("INSERT INTO commands VALUES(?,?,?,?,?)", (player, room_id, cmd_id, digest, encoded(receipt)))
            return receipt
        with self.db:
            event = self.event(state, change[0], change[1]) if change else None
            if change:
                used = {e["blueprint_id"] for e in state["entities"].values()}
                state["assets"] = {k: v for k, v in state["assets"].items() if k in used}
                self.save(state)
            receipt = {"command_id": cmd_id, "status": "applied", "seq": state["seq"], "result": result}
            if event:
                receipt["event"] = event
            self.db.execute("INSERT INTO commands VALUES(?,?,?,?,?)", (player, room_id, cmd_id, digest, encoded(receipt)))
        return receipt

    def apply(self, state, player_id, command):
        kind, payload = command["type"], command["payload"]
        if kind in ("world.query", "rules.query"):
            fields(payload, ())
            return (copy.deepcopy(state) if kind == "world.query" else RULES), None
        if kind == "entity.query":
            fields(payload, ("entity_id",))
            require(isinstance(payload["entity_id"], str))
            require(payload["entity_id"] in state["entities"], "ENTITY_NOT_FOUND", "建筑已不存在")
            e = state["entities"][payload["entity_id"]]
            return {"entity": e, "blueprint": state["assets"][e["blueprint_id"]]}, None
        existing = None
        if kind != "building.create":
            optional = ("blueprint", "blueprint_id") if kind == "building.update_model" else ("voxel", "color") if kind == "building.paint_voxel" else ()
            fields(payload, ("entity_id", "expected_entity_revision"), optional)
            require(isinstance(payload["entity_id"], str))
            existing = state["entities"].get(payload["entity_id"])
            require(existing is not None, "ENTITY_NOT_FOUND", "建筑已不存在")
            require(existing["owner_id"] == player_id, "PERMISSION_DENIED", "只能修改或拆毁自己的建筑")
            require(integer(payload["expected_entity_revision"]) and payload["expected_entity_revision"] == existing["revision"], "STALE_ENTITY", "建筑已经更新，请重新选择")
        if kind == "building.paint_voxel":
            fields(payload, ("entity_id", "expected_entity_revision", "voxel", "color"))
            point = vector(payload["voxel"], 0, LIMITS["model_axis"] - 1)
            previous = state["assets"][existing["blueprint_id"]]
            model = {k: copy.deepcopy(previous[k]) for k in ("schema_version", "name", "size", "encoding", "palette", "cells")}
            cell = next((c for c in model["cells"] if tuple(c[:3]) == point), None)
            require(cell is not None, "ENTITY_NOT_FOUND", "选中坐标没有实心方块")
            require(isinstance(payload["color"], str), "INVALID_COLOR", "颜色必须是 #RRGGBB")
            if payload["color"].upper() not in model["palette"]:
                model["palette"].append(payload["color"].upper())
            cell[3] = model["palette"].index(payload["color"].upper())
            used_colors = sorted({model["palette"][c[3]] for c in model["cells"]})
            indices = {color: i for i, color in enumerate(used_colors)}
            for c in model["cells"]:
                c[3] = indices[model["palette"][c[3]]]
            model["palette"] = used_colors
            base_id, base_revision = existing["blueprint_id"], existing["revision"]
            result, change = self.apply(state, player_id, {**command,"type":"building.update_model","payload":{"entity_id":existing["id"],"expected_entity_revision":existing["revision"],"blueprint":model}})
            change[1]["voxel_patch"] = {"base_blueprint_id": base_id, "base_revision": base_revision,
                                      "voxel": list(point), "color": payload["color"].upper()}
            return result, change
        if kind in ("building.demolish", "building.destroy"):
            del state["entities"][existing["id"]]
            return {"entity_id": existing["id"]}, ("building.destroyed" if kind == "building.destroy" else "building.removed", {"entity_id": existing["id"], "revision": existing["revision"] + 1})
        if kind == "building.create":
            fields(payload, ("position", "rotation_y_quarter_turns"), ("blueprint", "blueprint_id"))
            vector(payload["position"], 0, LIMITS["map_size"])
            require(payload["position"][1] == 1, message="建筑锚点高度必须为地面 Y=1")
            require(integer(payload["rotation_y_quarter_turns"]) and 0 <= payload["rotation_y_quarter_turns"] <= 3)
        require(("blueprint" in payload) != ("blueprint_id" in payload), message="蓝图内容与蓝图 ID 必须二选一")
        if "blueprint" in payload:
            model = normalize_model(payload["blueprint"])
        else:
            require(isinstance(payload["blueprint_id"], str))
            model = state["assets"].get(payload["blueprint_id"])
            require(model is not None and any(e["owner_id"] == player_id and e["blueprint_id"] == model["id"] for e in state["entities"].values()), "PERMISSION_DENIED", "蓝图不存在或不属于当前玩家")
        entity = dict(existing) if existing else {"id": "building-" + secrets.token_hex(8), "owner_id": player_id, "name": model["name"], "position": payload["position"], "rotation_y_quarter_turns": payload["rotation_y_quarter_turns"], "revision": 0}
        entity["blueprint_id"], entity["revision"] = model["id"], entity["revision"] + 1
        state["assets"][model["id"]] = model
        area = rect(entity, state["assets"])
        zone = next(p["zone"] for p in state["players"] if p["id"] == player_id)
        require(area[0] >= zone[0] and area[1] >= zone[1] and area[2] <= zone[2] and area[3] <= zone[3], "OUTSIDE_BUILD_ZONE", "建筑必须完全位于自己的区域内")
        others = [e for e in state["entities"].values() if e["id"] != entity["id"]]
        require(not any(overlaps(area, rect(e, state["assets"])) for e in others), "POSITION_OCCUPIED", "建筑占地与已有建筑冲突")
        require(len(others) + 1 <= LIMITS["room_buildings"] and sum(e["owner_id"] == player_id for e in others) + 1 <= LIMITS["player_buildings"], "ROOM_LIMIT_REACHED", "建筑数量达到上限")
        for key, limit in (("voxel_count", "room_voxels"), ("face_count", "room_faces")):
            require(sum(state["assets"][e["blueprint_id"]][key] for e in others) + model[key] <= LIMITS[limit], "ROOM_LIMIT_REACHED", "房间体素或外露面预算不足")
        state["entities"][entity["id"]] = entity
        return {"entity": entity}, ("building.created" if existing is None else "building.updated", {"entity": entity, "asset": model})

    def chat_begin(self, identity, request_id, digest):
        args = (identity["player_id"], identity["world_id"], request_id)
        row = self.db.execute("SELECT hash,state,result FROM chats WHERE player=? AND room=? AND id=?", args).fetchone()
        if row:
            require(row[0] == digest, "COMMAND_ID_CONFLICT", "相同聊天请求 ID 不能更改内容")
            if row[1] == "done":
                return json.loads(row[2])
            raise GameError("REQUEST_PENDING", "本次请求正在处理，稍后用同一 ID 查询")
        with self.db:
            self.db.execute("INSERT INTO chats VALUES(?,?,?,?,?,?)", (*args, digest, "pending", None))
        return None

    def chat_finish(self, identity, request_id, result):
        with self.db:
            self.db.execute("UPDATE chats SET state='done',result=? WHERE player=? AND room=? AND id=?",
                            (encoded(result), identity["player_id"], identity["world_id"], request_id))

    def recover_pending(self):
        # Never re-run a model automatically after a server crash. Recover an already committed command.
        for player, room, rid in self.db.execute("SELECT player,room,id FROM chats WHERE state='pending'").fetchall():
            row = self.db.execute("SELECT result FROM commands WHERE player=? AND room=? AND id=?", (player, room, rid + ":0")).fetchone()
            receipt = json.loads(row[0]) if row else None
            result = {"status": "completed" if receipt else "error", "receipt": receipt,
                      "message": "已恢复原命令结果" if receipt else "服务重启中断了生成，本请求未再次执行，请重新发送需求。"}
            self.chat_finish({"player_id": player, "world_id": room}, rid, result)
