# 第一阶段：运行与接口说明

> 日期：2026-10-13 · 当前范围：本机与局域网。

## 1. 入口

启动项目中的 `tools/start-server.ps1`，打开 `http://localhost:8765`。本次本机 WLAN 地址为 `192.168.101.243`，局域网入口为 `https://192.168.101.243:8766`。

局域网使用项目外的自签证书，首次浏览器访问需要接受本机站点证书，不会安装系统根证书。当前模板的音频 Worklet 需要安全上下文，普通局域网 HTTP 无法启动场景，启动页提供明确提示；localhost HTTP 可正常运行。

Godot 编辑器 F5 可运行桌面客户端。网页和桌面默认使用同一服务；桌面可传 `--server=http://地址:端口` 覆盖后端地址。房间名相同才共享世界。

私有配置与 SQLite 保存在 `%LOCALAPPDATA%\VoxelKingdom`。迁移时复制 SQLite 与会话数据；不要在项目的公开资源目录放入密钥。服务重启会恢复房间。

## 2. HTTP 与 WebSocket

| 入口 | 作用 |
| --- | --- |
| `GET /api/health` | 运行状态与当前模型，不返回密钥 |
| `POST /api/join` | `{world_id,name,token?}`，创建 / 恢复身份，返回会话和快照 |
| `GET /api/snapshot` | 查询已认证玩家的当前房间 |
| `POST /api/command` | 提交版本化游戏命令 |
| `POST /api/chat` | `{request_id,text,selection}`，调用 DeepSeek 并执行合法提案 |
| `GET /api/chat/{request_id}` | 网络断开时查询原请求，避免重复执行 |
| `WS /ws` | 连接后首条发送 `{token}`；收到快照后消费有序事件 |

加入后 HTTP 请求使用 `Authorization: Bearer <session-token>`。会话 token 与 DeepSeek Key 不同，前者属于玩家登录凭证。WebSocket 不在 URL 中携带 token，避免进入 URL 日志。

## 3. 命令

命令信封采用完整技术文档中的 `schema_version`、`rules_version`、`command_id`、`world_id`、`type` 和 `payload`。当前版本为 `stage-01-v1`，创建归属由会话绑定，禁止客户端指定另一位玩家作为 owner。

- `building.create`：位置、四分之一圈旋转、内联模型或己方可复用蓝图 ID。
- `building.update_model`：实体 ID、预期修订号、新模型；原位置、朝向、名字与归属保留。
- `building.paint_voxel`：实体 ID、预期修订号、局部整数 `voxel` 坐标与 RGB `color`，仅改变这一个实心方块。
- `building.demolish` / `building.destroy`：实体 ID 与预期修订号，立即释放占地，销毁另外产生客户端短暂表现。
- `world.query` / `entity.query` / `rules.query`：结构化只读查询。

模型支持 `cells_v1` 与 `box_ops_v1`，格式见完整技术文档。API 的 `paint_voxel.color` 是 `#RRGGBB`；蓝图操作中的 `color` 是调色板整数索引，二者含义不同。

## 4. AI 与故障处理

每次请求都附带完整当前规则、操作格式、玩家区域、相关实体和选择。模型修改所需蓝图使用无损长方体压缩，无法压缩的多彩模型保留完整 cells。这个压缩不改变世界数据或颜色。

DeepSeek 返回完整合法 JSON 后才进入预检与执行。字段错误最多自动纠错一次；归属、过期实体、规则变化或网络失败不会自动换目标执行。已执行的结果通过真实回执展示。

聊天请求与命令 ID 都有持久幂等记录。同一请求 ID 的重试查询原结果；服务崩溃后不会重新调用模型来猜测是否执行过，而是恢复已提交命令或标记本请求中断。

## 5. 已知边界

当前由一个进程在同一事件循环中提供 HTTP 与 HTTPS，共享房间锁、广播与数据库，四个玩家身份的区域会持续保留；新玩家身份填满时使用另一个房间。没有账号管理、退出并释放区域或房间清理界面。

浏览器刷新保留当前房间身份，但重新进入需要点击一次进入按钮。页面后台暂停时，恢复后重连获取最新快照。当前界面不持久保存聊天显示历史，权威命令与世界状态会保存。

当前模型修改重新生成该建筑的网格块，并用共享资产网格缓存复用其他实例；尚未实现逐块损坏 / 差分重建。没有地形编辑、透明材质、移动单位或战斗。
