"""Authoritative voxel validation. No rendering and no model-generated code execution."""
import hashlib
import json
import re
from pathlib import Path

RULES = json.loads(Path(__file__).with_name("rules.json").read_text(encoding="utf-8"))
LIMITS = RULES["limits"]


class GameError(Exception):
    def __init__(self, code, message):
        self.code, self.message = code, message
        super().__init__(message)


def require(condition, code="INVALID_SCHEMA", message="输入字段或格式不合法"):
    if not condition:
        raise GameError(code, message)


def fields(value, required, optional=()):
    require(isinstance(value, dict), message="必须是 JSON 对象")
    keys = set(value)
    missing = sorted(set(required) - keys)
    unknown = sorted(keys - set(required) - set(optional))
    require(not missing and not unknown,
            message=f"字段不合法；缺少字段：{missing}；未允许字段：{unknown}")


def integer(value):
    return type(value) is int


def vector(value, lo, hi):
    require(isinstance(value, list) and len(value) == 3 and
            all(integer(n) and lo <= n <= hi for n in value), message="坐标必须是范围内的三个整数")
    return tuple(value)


def normalize_model(model):
    fields(model, ("schema_version", "name", "size", "encoding", "palette"), ("cells", "ops"))
    require(model["schema_version"] == 1 and integer(model["schema_version"]))
    require(isinstance(model["name"], str) and 1 <= len(model["name"]) <= 80)
    size = vector(model["size"], 1, LIMITS["model_axis"])
    palette = model["palette"]
    require(isinstance(palette, list) and 1 <= len(palette) <= LIMITS["palette"], "INVALID_COLOR", "颜色表数量不合法")
    require(all(isinstance(c, str) and re.fullmatch(r"#[0-9a-fA-F]{6}", c) for c in palette),
            "INVALID_COLOR", "颜色必须为不透明 RGB，例如 #2060FF")
    palette = [c.upper() for c in palette]
    cells = {}

    def point(value):
        p = vector(value, 0, LIMITS["model_axis"] - 1)
        require(all(p[d] < size[d] for d in range(3)), message=f"坐标 {list(p)} 超出模型尺寸 {list(size)}；各坐标必须严格小于对应尺寸")
        return p

    def color(index):
        require(integer(index) and 0 <= index < len(palette), "INVALID_COLOR", f"方块颜色必须是 0..{len(palette)-1} 的整数索引，收到 {index!r}；不是 RGB 字符串")
        return palette[index]

    encoding = model["encoding"]
    if encoding == "cells_v1":
        require("cells" in model and "ops" not in model and isinstance(model["cells"], list))
        require(len(model["cells"]) <= LIMITS["voxels"], "MODEL_TOO_LARGE", "方块数量超过限制")
        for cell in model["cells"]:
            require(isinstance(cell, list) and len(cell) == 4)
            p = point(cell[:3])
            require(p not in cells, message="不允许重复方块坐标")
            cells[p] = color(cell[3])
    elif encoding == "box_ops_v1":
        require("ops" in model and "cells" not in model and isinstance(model["ops"], list))
        require(len(model["ops"]) <= LIMITS["ops"], "MODEL_TOO_LARGE", "操作数量超过限制")
        visits = 0
        for op in model["ops"]:
            require(isinstance(op, dict) and "op" in op)
            kind = op["op"]
            if kind == "set_voxel":
                fields(op, ("op", "position", "color"))
                cells[point(op["position"])] = color(op["color"])
                visits += 1
            else:
                require(kind in ("fill_box", "clear_box"), message="未支持的体素操作")
                fields(op, ("op", "min", "max_exclusive", "color") if kind == "fill_box" else ("op", "min", "max_exclusive"))
                a = point(op["min"])
                b = vector(op["max_exclusive"], 1, LIMITS["model_axis"])
                require(all(a[d] < b[d] <= size[d] for d in range(3)), message=f"盒区间 {list(a)}..{list(b)} 不合法，需每轴 min < max_exclusive <= {list(size)}")
                visits += (b[0] - a[0]) * (b[1] - a[1]) * (b[2] - a[2])
                require(visits <= LIMITS["op_visits"], "MODEL_TOO_LARGE", "体素展开计算量超过限制")
                c = color(op["color"]) if kind == "fill_box" else None
                for x in range(a[0], b[0]):
                    for y in range(a[1], b[1]):
                        for z in range(a[2], b[2]):
                            if c is None:
                                cells.pop((x, y, z), None)
                            else:
                                cells[x, y, z] = c
            require(visits <= LIMITS["op_visits"], "MODEL_TOO_LARGE", "体素展开计算量超过限制")
    else:
        raise GameError("INVALID_SCHEMA", "未支持的体素编码")
    require(0 < len(cells) <= LIMITS["voxels"], "MODEL_TOO_LARGE", "模型为空或实心方块超过 8192")
    require(any(p[1] == 0 for p in cells), message="至少一个底部方块必须接触地面")
    faces = sum((x + dx, y + dy, z + dz) not in cells for x, y, z in cells
                for dx, dy, dz in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)))
    require(faces <= LIMITS["faces"], "MODEL_TOO_LARGE", "外露面数量超过限制，请减少碎片与空隙")
    colors = sorted(set(cells.values()))
    lookup = {c: i for i, c in enumerate(colors)}
    canonical = {"schema_version": 1, "size": list(size), "encoding": "cells_v1", "palette": colors,
                 "cells": [[*p, lookup[c]] for p, c in sorted(cells.items())]}
    digest = hashlib.sha256(json.dumps(canonical, separators=(",", ":")).encode()).hexdigest()
    return {**canonical, "name": model["name"], "id": "bp-" + digest, "voxel_count": len(cells), "face_count": faces}


def rotated_size(model, quarter):
    size = model["size"]
    return [size[2], size[1], size[0]] if quarter % 2 else size


def model_for_ai(model):
    """Lossless cuboid encoding for prompts. Falls back to cells for high-color detail."""
    base = {k: model[k] for k in ("schema_version", "name", "size", "palette")}
    cells = {tuple(c[:3]): c[3] for c in model["cells"]}
    ops = []
    for origin in sorted(cells):
        if origin not in cells:
            continue
        color = cells[origin]
        x, y, z = origin
        end_x = x + 1
        while cells.get((end_x, y, z), -1) == color:
            end_x += 1
        end_z = z + 1
        while all(cells.get((i,y,end_z),-1) == color for i in range(x,end_x)):
            end_z += 1
        end_y = y + 1
        while all(cells.get((i,end_y,j),-1) == color for i in range(x,end_x) for j in range(z,end_z)):
            end_y += 1
        for i in range(x,end_x):
            for j in range(y,end_y):
                for k in range(z,end_z):
                    del cells[i,j,k]
        ops.append({"op":"fill_box","min":[x,y,z],"max_exclusive":[end_x,end_y,end_z],"color":color})
        if len(ops) > LIMITS["ops"]:
            return {**base,"encoding":"cells_v1","cells":model["cells"]}
    return {**base,"encoding":"box_ops_v1","ops":ops}


def rect(entity, assets):
    s = rotated_size(assets[entity["blueprint_id"]], entity["rotation_y_quarter_turns"])
    x, _, z = entity["position"]
    return x, z, x + s[0], z + s[2]


def overlaps(a, b):
    return a[0] < b[2] and a[2] > b[0] and a[1] < b[3] and a[3] > b[1]
