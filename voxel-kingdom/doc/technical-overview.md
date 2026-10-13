# Voxel Kingdom：完整技术文档

> 版本：0.1 · 日期：2026-10-13 · 状态：架构与协议设计  
> 对应：[完整玩法流程](game-design-overview.md) · 当前实施范围：[第一阶段技术计划](stage-01-implementation.md)

## 1. 架构基线

采用 Godot GDScript + Compatibility 客户端、网页聊天、DeepSeek 网关和权威游戏服务。客户端负责显示、选择与预览，服务器负责玩家身份、规则、建筑、占地、命令执行与状态保存。

```text
浏览器：网页聊天 + Godot Web 画面
    │ 用户意图 / 查询              ↑ 回执 / 快照 / 增量
    ↓                            │
后端网关：认证、读取规则与场景、调用 DeepSeek、解析输出
    │ 每次请求包含完整生效规则     ↑ JSON 操作提案
    └─────────────────────── DeepSeek
    │ 绑定身份并提交命令
    ↓
权威游戏服务：规则校验 → 原子提交 → 事件序列 → 持久化
```

DeepSeek 输出经网关传给游戏服务端。模型不直接持有游戏管理权限；玩家即使绕过聊天直接构造命令，也受到相同校验。

第一阶段没有单位、物理战斗与导航，建议 Python 服务同时承担 AI 网关和权威建筑状态，Godot 专注显示；协议 Schema 与样例共用，Python 负责最终验证，GDScript 负责读取规范数据与生成网格。逻辑模块分离，初版同进程部署。未来有持续战斗模拟时，再评估 Godot 无界面服务端，并按负载拆分房间与资产服务。

## 2. DeepSeek：每次调用附带规则

### 2.1 规则包

后端维护版本化的规则数据：当前模式、允许命令、所有生效限制、归属权限、坐标约定、颜色格式、输出 Schema、语义和示例。提示词规则说明与服务端限制尽量从同一配置生成，避免各写一套尺寸上限。

每次实际发往 DeepSeek 的请求，包括纠错重试，都显式带上当前完整生效规则与格式。不能只在第一轮发送，也不能只发送规则版本号或假定模型记得历史。规则包不包含密钥和管理员凭证；不会把未来未开放的功能当作可用命令。

请求组织为：固定规则说明 → 当前玩家、房间、选中目标与相关状态 → 玩家需求。场景快照是有权限过滤的数据，不是全房间存档；规则与世界状态分开更新。

模型输出 `rules_version`；服务端执行时核对当前版本。规则已变化则返回 `RULES_CHANGED`，按最新规则重新生成，不能继续用旧权限或旧上限执行。

### 2.2 结构化输出与失败处理

初版采用 DeepSeek Chat API 的 JSON Output：设置 `response_format` 为 `json_object`，提示中明确要求 JSON 并给出格式样例，控制输出长度；处理空内容、截断与格式不符。JSON 格式正确不等于字段合法或操作有权限，仍须独立验证。[DeepSeek JSON Output](https://api-docs.deepseek.com/guides/json_mode/)

接口地址、模型名称、超时与 token 预算通过部署配置指定，实施时核对账号可用模型，不将某个模型名称写死。API 密钥仅在网关环境中保存。[DeepSeek API 接入文档](https://api-docs.deepseek.com/guides/function_calling/)

第一阶段一轮最多生成一项世界修改；查询可以只生成回答。无法确定对象时输出澄清结果。输出不合法时最多自动纠错一次，纠错仍附带完整规则。只在完整输出校验通过后提交命令，不执行流式输出的半段 JSON。

聊天请求 ID 与执行命令 ID 分开。网络重试重复同一请求不能再次调用并执行出一栋新建筑；执行状态不明时先查询原命令，不盲目生成新 ID 重试。

模型标准输出对象包含 `schema_version`、`rules_version`、`status`（`commands` / `clarification` / `answer`）、`message`、`commands`。网关为命令补充可信身份、房间和请求 ID；模型不得决定自己的权限。

例如，玩家要求在选定位置放一块红色方块，模型提出的结果为：

```json
{
  "schema_version": 1,
  "rules_version": "stage-01-v1",
  "status": "commands",
  "message": "计划在选定位置创建红色方块。",
  "commands": [{
    "type": "building.create",
    "payload": {
      "position": [8, 1, 8],
      "rotation_y_quarter_turns": 0,
      "blueprint": {
        "schema_version": 1,
        "name": "红色方块",
        "size": [1, 1, 1],
        "encoding": "cells_v1",
        "palette": ["#FF4040"],
        "cells": [[0, 0, 0, 0]]
      }
    }
  }]
}
```

这段 `message` 是待执行说明。网关加上命令信封后提交；“已创建”只能来自成功回执。`clarification` 与 `answer` 的 `commands` 必须为空数组，`commands` 状态在第一阶段必须恰有一条修改命令。

## 3. 数据与体素格式

### 3.1 数据分层

| 对象 | 权威内容 |
| --- | --- |
| 规则包 | 模式、版本、命令集合、容量、权限与行为规则 |
| 体素蓝图 | 尺寸、RGB 调色板、实心方块坐标和颜色索引 |
| 建筑实例 | ID、房间、归属、蓝图引用、位置、朝向、状态、修订号 |
| 命令 | ID、类型、规则版本、目标、参数、身份上下文 |
| 回执 / 事件 | 是否执行、错误原因、实体变化、权威事件序号 |
| 世界快照 | 规则版本、玩家区域、资产引用、实体与同步起点 |

所有改变共享世界的行为走命令入口。相机和选择只保留在客户端；结构化查询不修改世界，也不必加入世界变更日志。

### 3.2 坐标与逐方块颜色

初版 1 体素 = 1 世界单位，X 正向为东、Z 正向为南、Y 为高度。蓝图锚点是局部包围盒最小角 `[0,0,0]`。位置表示这个锚点的世界坐标；旋转为绕 Y 轴的 0 / 90 / 180 / 270 度，旋转后重新归一到新包围盒最小角，再加位置。

方块颜色是 sRGB `#RRGGBB`，不透明。空坐标代表空气，空气不以颜色表示。调色板只是去重编码，每个方块引用独立索引；不能限制为固定几种材料色，也不能把建筑统一颜色当作逐方块颜色实现。

蓝图示例：

```json
{
  "schema_version": 1,
  "name": "四色底座",
  "size": [2, 1, 2],
  "encoding": "cells_v1",
  "palette": ["#808080", "#2060FF", "#FF4040", "#E8D080"],
  "cells": [[0, 0, 0, 0], [1, 0, 0, 1], [0, 0, 1, 2], [1, 0, 1, 3]]
}
```

`cells` 每项为 `[x,y,z,palette_index]`。坐标必须是范围内整数，重复坐标拒绝，索引必须有效，空模型拒绝。名称不作为资产唯一 ID。

大模型生成整座城堡时可以使用 `box_ops_v1`：`fill_box`、`clear_box`、`set_voxel` 按数组顺序覆盖。盒区间是 `[min,max_exclusive)`；所有操作只允许在声明尺寸内执行。`cells_v1` 与 `box_ops_v1` 二选一，服务端展开成同一种规范数据后校验与存储。

```json
{
  "schema_version": 1,
  "name": "蓝顶灰色小屋",
  "size": [4, 4, 4],
  "encoding": "box_ops_v1",
  "palette": ["#808080", "#2060FF", "#FF4040"],
  "ops": [
    {"op": "fill_box", "min": [0, 0, 0], "max_exclusive": [4, 3, 4], "color": 0},
    {"op": "clear_box", "min": [1, 1, 1], "max_exclusive": [3, 3, 3]},
    {"op": "clear_box", "min": [1, 0, 0], "max_exclusive": [2, 2, 1]},
    {"op": "fill_box", "min": [0, 3, 0], "max_exclusive": [4, 4, 4], "color": 1},
    {"op": "set_voxel", "position": [0, 3, 0], "color": 2}
  ]
}
```

规范化统一颜色大小写、去掉未使用颜色、按坐标与实际色值确定内容，再计算内容哈希。展示名称、作者与访问权限另存。多个实例复用资产；替换一个实例的模型创建或复用新资产，不修改其他实例。

体素数据为事实来源，网格与选择辅助数据可重建。后续可增加材料属性、损坏增量与压缩二进制编码；RGB 外观不能替代材料和战斗规则。

## 4. 命令执行契约

首阶段命令为查询、`building.create`、`building.update_model`、`building.paint_voxel`、`building.demolish`、`building.destroy`。创建可以附带蓝图或引用已有授权资产；更新使用完整替换模型，保证失败时保留原模型。后续添加施工、维修、部队、攻击与地形命令，统一沿用验证入口。

```json
{
  "schema_version": 1,
  "rules_version": "stage-01-v1",
  "command_id": "request-a-0042:0",
  "world_id": "room-001",
  "type": "building.create",
  "payload": {
    "position": [8, 1, 8],
    "rotation_y_quarter_turns": 0,
    "blueprint_id": "bp-0001"
  }
}
```

身份来自认证会话，创建归属由服务器绑定。`building.update_model`、拆除和销毁必须包含目标 ID 与 `expected_entity_revision`，防止迟到的 AI 输出误改已更新的目标。

创建示例中的 `blueprint_id` 假定此前已注册且当前身份可访问。内联 `blueprint` 与资产 `blueprint_id` 必须二选一；`building.update_model` 同样使用这一约定，并保留实例 ID、名称、位置、朝向与归属。名称修改后续通过独立字段规则开放。

验证顺序建议为：身份与房间 → 请求大小与 Schema → 规则版本与命令白名单 → 对象权限与修订号 → 模型展开和复杂度 → 位置、占地与房间额度 → 原子提交。

资源扣除（后续阶段）、占地预留、实体和额度更新必须整体成功或整体失败。先预览后执行也要复查；模型请求期间世界可能已变化。命令日志标记 `applied` / `rejected`，单项即时操作完成后返回权威实体与序号；未来持续任务另发进度事件。

同一身份与房间内重复命令 ID、相同内容返回原结果；相同 ID 不同内容返回冲突。幂等结果随状态提交保存，不能仅放进短期内存缓存。每房间按稳定顺序执行，避免占地和删除更新竞争。

建议错误码包括 `INVALID_SCHEMA`、`RULES_CHANGED`、`MODEL_TOO_LARGE`、`INVALID_COLOR`、`POSITION_OCCUPIED`、`OUTSIDE_BUILD_ZONE`、`PERMISSION_DENIED`、`STALE_ENTITY`、`ROOM_LIMIT_REACHED`、`COMMAND_ID_CONFLICT`。失败不改变已存在实体与占地。

拆除立即删除活跃实例；销毁产生不同事件与短暂客户端表现，然后移除活跃实例。第一阶段二者均立即释放占地，客户端表现不阻止新建；日志保留对象 ID 与销毁信息用于同步和恢复。

## 5. 联机、存储与部署

浏览器使用 HTTPS 请求和 WSS 同步；不能以原生 ENet / UDP 作为 Web 客户端唯一通道。首阶段 Python 服务统一提供认证、DeepSeek 调用与 WebSocket 命令 / 状态协议；DeepSeek 网关提交命令时仍经过相同权限检查。后续拆分独立游戏服务时使用受认证内部连接，玩家不能伪装成网关。[Godot Web 网络限制](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html#networking)

首次加入传快照、事件序号与缺少的资产；后续传增量，资产按哈希缓存。先注册订阅并确定快照序号，再衔接后续事件，避免加入期间丢失变化。客户端缺序号则补发或重取快照，收到重复事件应忽略。

断线重连恢复身份与玩家区域，拉取最新状态，不以浏览器残留画面作为权威数据。浏览器后台暂停时也按重连处理。第一阶段全图公开，后续战争迷雾须在查询和事件下发层过滤。

首阶段建议以事务存储保存资产、活跃建筑、事件序号、房间区域和幂等回执，采用 SQLite 即可。服务重启能恢复房间；浏览器缓存仅用于加速。未来增加定期快照、日志压缩、规则迁移和房间分片。

完整战斗回放还需要固定模拟版本、随机种子和输入顺序并验证确定性，不能仅凭聊天记录重现。第一阶段目标是权威状态恢复，不要求确定性战斗回放。

生产部署使用静态托管 / 反向代理、HTTPS、WSS 和后端服务。不将 DeepSeek Key 放入 HTML、Godot 包或客户端请求。单线程导出优先；多线程导出时再验证安全上下文、跨源隔离及网页资源集成。[Godot Web 导出与线程](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html#thread-and-extension-support)

## 6. Compatibility 与体素渲染

可以从 Forward+ 切换为 Compatibility；Godot 官方将其作为 Web 渲染选择。当前项目尚无游戏场景，适合在首阶段开始时切换，再核验实际 Godot 4.7 安装与导出模板。切换不是性能保证，仍需浏览器实测。[Godot 渲染器选择与切换](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html#switching-between-renderers)

首版使用基础光照或无光照颜色检查模式，不依赖 Forward+ 专用 GI、计算着色器和后处理。CPU 展开体素，使用 ArrayMesh；同类方块共用材质，通过顶点颜色显示逐方块色值，避免每一种 RGB 新建一个材质。

网格先剔除相邻实心体素间的面，即使颜色不同也剔除不可见内部面。再按方向、颜色和相容渲染属性做 Greedy Meshing。不同颜色的相邻可见面保持边界，不跨色合并造成插值渐变。顶点颜色赋给面的全部顶点，在颜色不连续处拆分顶点。[体素网格合并算法原文](https://0fps.net/2012/06/30/meshing-in-a-minecraft-game/)

独立颜色越多，面合并收益通常越低，但共享材质仍控制 Draw Calls。不能为了面数偷偷量化颜色；可选低质量档位若简化远景，必须保留权威模型和近景颜色数据。

渲染建议组合：

- 地形分 Chunk，建筑按局部块生成网格；不为每体素创建独立节点或物理刚体。
- 蓝图网格缓存，变化只更新受影响块，边界变化同时重建相邻块。
- 无线程 Web 模式分帧生成和上传网格；有线程时后台只处理安全数据，主线程提交显示资源。
- 相机视锥剔除、少量共享材质、远距简化与动态加载；评估分块对更新成本与绘制调用的影响。
- 第一阶段地面用简化碰撞，建筑选择用包围盒候选加体素射线查询；门洞不能被整盒误判为实心。
- 后续导航使用局部障碍更新，战斗使用空间索引，破坏采用批量增量，限制物理碎片和网格更新频率。

性能验证同时测三角形、Draw Calls、CPU / GPU 帧时间、网格耗时、峰值内存、加载体积和同步量。均色建筑、相邻异色、每方块不同色、稀疏碎片和连续修改分别测试；不能只用均色实心立方体证明所有模型都快。

## 7. 阶段技术对应关系

| 阶段 | 技术能力 |
| --- | --- |
| 第一阶段 | Compatibility、相机与选择、RGB 体素网格、规则包、DeepSeek JSON、权限与原子建筑命令、WSS、存储与重连、Web 验证 |
| 第二阶段方向 | 建筑类型与资源规则、施工进度、固定建筑能力；攻击形式另行设计 |
| 第三阶段方向 | 固定步长模拟、小队、导航、攻击与伤害、胜负与对局同步 |
| 后续方向 | 迷雾过滤、外交、多房间扩展、局部破坏、资产分发与性能分级 |

每阶段开始前将对应玩法拆成实施模块与验收项。当前只详细编写第一阶段，后续方向不构成已承诺接口与容量。

## 8. 第一阶段实际实现补充

`building.paint_voxel` 包含实体 ID、预期修订号、局部方块坐标与 RGB 字符串，服务端保持其他方块不变。完整模型修改继续使用 `building.update_model`。AI 模型上下文采用无损长方体压缩，正常运行复用 DeepSeek HTTP 连接。

一个 Python 进程在同一事件循环中提供 HTTP 8765 与 HTTPS 8766。当前模板在 LAN 普通 HTTP 下无法初始化音频 Worklet；局域网使用项目外的自签证书，首次浏览器访问接受本机站点证书，系统信任设置保持原样。[AudioWorklet 安全上下文说明](https://developer.mozilla.org/en-US/docs/Web/API/AudioWorklet)

实测与边界见[完成报告](stage-01-completion-report.md)，运行与参数见[运行说明](stage-01-operation.md)。
