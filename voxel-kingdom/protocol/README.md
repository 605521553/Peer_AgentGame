# 共享协议

`rules.json` 是游戏命令/模型规则的唯一源文件，服务端读取并在每次 AI 请求中附带。传输版本与游戏规则版本分开：本次新增传输 v2，不改变 `stage-01-v1` 的游戏权限或 SQLite 存档语义。

## v2 初始同步

`POST /api/join` 增加 `protocol_version: 2`，返回 token/player_id/world_id/protocol_version，不包含 snapshot。邀请码仅对新身份验证，已有 token 恢复原身份。

WSS 首帧：`{"token":"…","protocol_version":2,"known_assets":["bp-<sha256>"]}`。已知模型列表最多 64 项，只声明本次房间索引中已从缓存读取并通过内容校验的模型。

服务器在房间锁内注册订阅并取得一致性快照；`snapshot.state.entities/players/seq` 是当前小型全量清单，`snapshot.state.assets` 只包含缺失模型。不存在无限事件回放或客户端上传世界快照。缺失模型仍不能恢复时，客户端清空本次已知声明重连。

模型传输支持 cells_v1、box_ops_v1，按 JSON 长度选择较短表示；模型 ID 基于规范化 cells 的 SHA-256，不随网络表示改变。浏览器校验后再应用/缓存。规范对象字段顺序为 schema_version、size、encoding、palette、cells；palette 去重排序，cells 按 x/y/z 排序，JSON 无空白，UTF-8 编码。

## 回执和事件

HTTP 请求头 `X-Voxel-Protocol: 2` 使命令与 AI 回执省略 event。回执保留 command_id/status/seq/result 或 error；客户端等待 WSS 达到对应 seq，不能把成功回执误当成场景已同步。

单格改色 `building.updated` 事件在接收者已知基础模型时包含 `entity`、`voxel_patch`，不包含 asset。补丁字段：base_blueprint_id、base_revision、voxel、color；entity 带新 revision/blueprint_id。RGB 值避免调色板重排造成歧义。客户端校验旧实体版本、计算新规范模型并验证新 ID；否则重新同步。基础模型未知时发送完整紧凑模型作为回退。

序号断档重同步；删除事件仍明确给出实体 ID。全模型导入允许整体替换。相同模型的新实例省略已知 asset。

## 兼容

未声明 v2 的旧网页/原生客户端仍用 v1 快照和完整事件。服务端先上线兼容实现，再发布新客户端。以后不兼容协议变更需再次协调，不能仅靠独立发布解决兼容性。
