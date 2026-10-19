# 自动登录、同步优化与分项目完成情况及验收报告

日期：2026-10-15。公网入口：<https://140.143.163.231>。

## 实现总结

### 自动进入与恢复

- 浏览器启动时读取原房间 token，自动验证身份并连接服务器；无需重填邀请码或点击进入，不创建新玩家槽位。
- 同房间恢复相机位置、朝向与缩放。鉴权失败才回登录框；启动网络失败自动重试，不删除有效会话。
- 增加主动退出；退出清除本机当前房间 token，不删除服务器建筑、不释放原身份槽位。
- Godot/WebAssembly 刷新后仍需重新初始化图形资源；恢复的是身份、原世界内容与视角，不是保留已销毁的引擎实例。

### 数据结构与传输

- 新网页使用传输 v2；HTTP 加入仅身份信息，WSS 是唯一初始世界同步通道，命令和 AI HTTP 回执不再附带重复 event/模型。
- 初始同步保留小型完整实体清单，只下发客户端缺失的模型资产；不实现复杂的无限事件回放。
- 模型按规范体素内容 ID 复用；比较 cells 与盒子表示长度后选择更小编码。服务端仍验证完整世界，客户端解码、校验、生成渲染网格。
- 单格改色发送坐标、RGB、基础模型/修订及新的实体版本，不发送整模型。基础不匹配则重新同步；整体导入仍允许替换完整模型。
- 浏览器 IndexedDB 最多保留 128 模型和 32 个房间索引；读取时验证 SHA-256。缓存损坏、被清理、被禁用或写入失败时仍可从服务器恢复。
- WASM/PCK 使用独立 CacheStorage 缓存，按资源内容版本区分，保留当前与一个旧版本；不缓存 API 或身份数据，缓存失败回退网络。版本更新后首次仍需下载新资源。
- 重同步比较实体版本及模型 ID，不重建未变化的建筑节点。改变颜色的建筑本身仍会重建网格，尚未实现单建筑内部的局部网格增量更新。
- 旧网页/原生客户端保留 v1 兼容路径；其旧协议仍可能使用全量数据。本次优化主要针对新网页 v2。

### 子项目管理

```text
client/       Godot 项目、场景、脚本、网页、客户端测试与导出工具
server/       Python 后端、requirements、服务端测试与启动工具
protocol/     rules.json 唯一源、协议说明
deploy/       Nginx、systemd、备份与安装配置
tools/        兼容启动入口、跨项目验收与独立发布
build/client-web/   客户端构建产物
doc/          方案、逐批记录、验收和维护说明
```

保持同一仓库组织，未创建两个独立仓库。根项目原本没有 Git 元数据，本次未初始化或推送 Git 仓库。

打开 Godot 时使用 `client/project.godot`。服务端可在 `server/` 独立安装和运行；客户端导出不依赖服务端实现。根 `.venv` 继续用于当前本机工具，不作为生产发布内容。

发布工具支持 `--component all|server|client`；服务器上分别维护 `server-current` 与 `client-current`。客户端单独发布不上传运行密钥、不重启后端；服务端单独发布不携带 WASM、不改客户端链接。首次目录迁移通过 all 协调完成，原数据库、会话和密钥位置保留。

## 已通过的验证

| 项目 | 结果 |
|---|---|
| 服务端回归 | 48 passed；根目录及 server 子目录均可运行；1 项已有依赖弃用警告 |
| 客户端网格测试 | 6 项通过 |
| Godot Web 构建 | 成功；最新资源版本 `4c767dcbffd28b427af6` |
| 本机真实双浏览器 | 自动登录、同身份、视角恢复、缓存命中、改色补丁、同模型复用、离线恢复通过 |
| 缓存故障 | 人为损坏后重取；禁用 IndexedDB 后正常进入 |
| 无效会话 | 回登录框，不创建新玩家 |
| 刷新下载 | 本机验收缓存已有模型时模型下载数 0，初始快照 1 次 |
| 单格改色 | 本机事件 484 字节，不含整模型；此为 JSON 内容字节，不含帧/TLS 头 |
| 服务端独立发布 | `20261015-181900`，客户端链接不变，包小于 1 MiB |
| 客户端独立发布 | 最新 `20261015-183434`，后端 PID 前后均为 411753 |
| 公网静态资源 | 版本化 WASM 200、gzip、一年 immutable 缓存；HTML/UI 及时验证更新 |
| 原有业务 | 各次发布后 api.patelender.cn 均 HTTP 200 |

最新本机专项刷新到场景渲染 **1869 ms**，公网专项 **1949 ms**。两者均自动恢复身份/相机，模型下载数 **0**，初始快照 **1** 次，WASM/PCK 缓存命中 **2**、未命中 **0**、网络重复下载 **0 字节**。这是指定电脑及测试场景的测量样本，不是性能承诺；首次下载仍有约 10 MB 压缩 WASM。

公网专项同时通过：同模型实例复用、离线期间删除恢复、缓存损坏/禁用回退、无效会话回登录、主动退出、未变建筑重同步不重建；页面错误为 0。改单格事件 484 字节，不包含完整模型。

修正前单独公网玩法回归虽然功能通过，但刷新耗时 22,677 ms，资源计时证明 WASM 被重新下载约 10 MB；仅设置 immutable 缓存头不足以证明缓存命中。补充显式资源缓存后上述专项验证通过。此前并行运行的玩法验收曾超过旧 30 秒导航超时，不计为通过，完整经过保留在逐批记录中。

最终发布的完整公网玩法回归通过：真实 DeepSeek 聊天创建、双身份同步、自定义模型导入、逐方块改色及像素验证、场景拾取、销毁/拆除、越权拒绝、输入时相机不移动。控制台错误 0；该轮刷新到可操作样本为 **4205 ms**，未出现 WASM/PCK 网络资源请求。专项与玩法测试计时终点略有差别，不能当作严格同条件基准对比。

服务重启专项通过：离线客户端恢复、双方 WSS 自动重连、会话及建筑持久化、重启后命令继续同步；本轮恢复约 **3.36 秒**。严格比较服务器前后存档及客户端前后世界均一致。测试后服务 active、约 35.1 MiB 内存，备份执行成功，原 API 站点仍 HTTP 200。首次使用旧测试脚本发生不同对象表示直接比较失败，修正验收比较方式后重跑通过，未因此修改运行代码。

## 使用与维护

原游戏地址、邀请码和原有效会话继续可用。更新后普通刷新可加载新网页；首次进入仍填写邀请码，之后同源同浏览器刷新自动进入。换浏览器/地址或清除站点存储后，需要重新进入。

仓库根目录常用命令：

```powershell
# 本机启动（兼容入口）
powershell -NoProfile -ExecutionPolicy Bypass -File tools/start-server.ps1
# 导出客户端
powershell -NoProfile -ExecutionPolicy Bypass -File tools/export-web.ps1
# 服务端测试
.\.venv\Scripts\python.exe -m pytest -q
# 部署工具依赖（本机已安装）
.\.venv\Scripts\python.exe -m pip install -r tools/requirements-deploy.txt
# 按需独立发布
.\.venv\Scripts\python.exe tools/deploy_public.py --component client
.\.venv\Scripts\python.exe tools/deploy_public.py --component server
```

旧 `/opt/voxel-kingdom/current` 为历史入口；维护与回退应使用 `server-current` / `client-current` 及相应 previous 文件。生产数据仍在 `/var/lib/voxel-kingdom`，备份计时器保留。

## 验收边界

- 浏览器为同一物理 Windows 电脑上的两个独立身份，通过公网访问 Ubuntu；尚未验收两台不同网络物理设备、手机/Safari及长期压力负载。
- 未实现离线编辑、完整账号系统、二进制协议、任意模型差分、持久化 GPU 网格或多实例服务端。
- 自签 IP 证书仍需首次接受；原域名 Certbot 续期问题仍属于既有运维问题。
- 服务端和客户端分开发布仍须保持协议兼容；缓存并非权威存档，不能代替数据库备份。
- 旧发布与版本化静态资源保留方便回退/加载，长期部署需要定期管理历史目录的磁盘占用。

## 留存证据

- [逐批修改记录](session-sync-implementation-log.md)
- [原实施方案](session-sync-project-plan.md)
- [客户端说明](../client/README.md)、[服务端说明](../server/README.md)、[协议说明](../protocol/README.md)
- [本机验证](../artifacts/sync-v2/local/results.json)、[迁移后验证](../artifacts/sync-v2/local-migrated/results.json)
- [服务端独立发布证据](../artifacts/public-deployment/release-20261015-181900.json)
- [客户端独立发布证据](../artifacts/public-deployment/release-20261015-182050.json)
- [最终客户端发布证据](../artifacts/public-deployment/release-20261015-183434.json)
- [最终本机缓存验证](../artifacts/sync-v2/local-runtime-cache/results.json)
- [最终公网缓存与同步验证](../artifacts/sync-v2/public-runtime-cache/results.json)
- [最终公网完整玩法与真实 AI 验证](../artifacts/sync-v2/public-gameplay-final/browser-smoke.json)
- [私有配置原值检查结果](../artifacts/sync-v2/credential-scan.json)
- [服务重启与持久性验证](../artifacts/sync-v2/public-recovery/recovery.json)
