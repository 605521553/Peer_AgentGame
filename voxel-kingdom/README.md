# Voxel Kingdom

Godot 4.7.2 Compatibility 体素建造原型。多人共享世界，DeepSeek 每次请求携带完整规则；服务器验证并执行所有建筑操作。第一阶段不包含移动单位与战斗。

## 公网服务器版本（2026-10-15）

已部署到 [公网游戏入口](https://140.143.163.231)。玩家直接使用浏览器，无需启动本地后台。首次访问需接受该 IP 的自签名证书；首次进入需邀请码，房主可查看本机 `%LOCALAPPDATA%\VoxelKingdom\公网访问凭据.md`。不同玩家填写相同房间名称即可联机，每个房间最多四人。有效会话刷新后会自动进入，恢复原房间与视角；已缓存模型无需重新下载。

参见 [公网使用与维护](doc/public-ip-operation.md)、[公网完成与验收报告](doc/public-ip-acceptance-report.md)、[逐批修改记录](doc/public-ip-deployment-log.md)。下方本机启动方式继续保留用于开发。

## 启动

项目目录为 `D:\Godot4.7.2\Projects\voxel-kingdom`。本机依赖、Web 导出和后端私有配置已准备好。

```powershell
cd D:\Godot4.7.2\Projects\voxel-kingdom
.\tools\start-server.ps1
```

打开 [本机游戏](http://localhost:8765)。本次环境的局域网入口为 [192.168.101.243:8766](https://192.168.101.243:8766)，其他设备需在可互通网络中访问，IP 改变时使用新的 WLAN 地址。同一房间内最多四个玩家身份；浏览器会保存自己的会话，刷新后点“进入王国”恢复。不同房间互相隔离。

Godot 编辑器打开 `client/project.godot`，按 F5 可使用桌面客户端；桌面和网页连接同一后端。后端在同一进程中监听 HTTP 8765 与 HTTPS 8766，可通过启动参数 `-Bind 127.0.0.1` 限制为本机。

局域网使用本机自签 HTTPS 证书，首次访问需在浏览器接受这个已知本机地址的证书。证书与私钥仅保存于项目外，不安装系统根证书。当前 Web 模板的音频 Worklet 需要安全上下文，因此局域网游玩使用 HTTPS 8766，localhost 可使用 HTTP 8765。

## 游玩

1. 进入房间，点击己方地面选择位置。
2. 输入自然语言，例如“在这里建一座灰墙蓝顶、有四座塔和门洞的小城堡”。
3. AI 提出命令，服务器校验通过后自动执行，其他玩家实时看到结果。
4. 点击建筑或具体方块，可以通过聊天修改形状、颜色；也可使用颜色选择器精确修改一个方块。
5. 建筑与模型面板提供示例城堡、JSON 导入与导出。拆除 / 销毁只允许操作己方建筑。

WASD 平移，Q/E 旋转，滚轮缩放，中键或右键拖动；聊天获得焦点时不会误触地图移动。“光照”按钮可以切换无光照颜色检查模式。

## 配置与数据

DeepSeek Key 保存在项目外的 `%LOCALAPPDATA%\VoxelKingdom\server.env`，世界数据在同目录 `world.sqlite3`。Key 不进入 Godot 包、网页或验收报告。可用 `VOXEL_ENV_FILE` 和 `VOXEL_DATABASE` 环境变量指定其他路径。配置样例在 `server/backend/server.env.example`。

规则与容量集中于 `protocol/rules.json`。本机选用已验证可用的 `deepseek-v4-pro`，采用 JSON 输出和非思考模式；模型输出仍可能无效，系统最多纠错一次，失败时保持世界不变。每玩家每分钟最多六轮 AI 请求。

## 导出与复验

```powershell
# 使用与引擎版本相同的 Web 模板；本机模板已安装。
.\tools\export-web.ps1

# 自动化检查；开发依赖仅用于验证。
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv\Scripts\python.exe -m pytest -q
& 'D:\Godot4.7.2\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path client --script tests/mesher_check.gd

# 后端运行时进行浏览器验收。首次使用需安装 Chromium。
.\.venv\Scripts\python.exe -m playwright install chromium
.\.venv\Scripts\python.exe tools\browser_smoke.py
.\.venv\Scripts\python.exe tools\performance_check.py
```

`tools/live_ai_check.py` 会实际调用 DeepSeek 并产生账号费用，用于复验自然语言创建、单方块改色和销毁闭环。各脚本使用独立验收房间；正式房间不会被压力测试填满。

Web 文件在 `build/client-web`；FastAPI 只公开该目录和 `client/web` 界面资源。启动时不能使用多 worker：当前房间锁和广播订阅属于单进程。持久状态、事件和幂等记录由 SQLite 事务保存。

本机与局域网版本已交付；2026-10-15 已追加公网 IP HTTPS/WSS 部署和双浏览器验收。独立物理设备验收、正式可信证书和大规模并发仍未完成。

## 文档

- [设计与阶段文档索引](doc/README.md)
- [第一阶段完成情况与验收报告](doc/stage-01-completion-report.md)
- [完整技术文档](doc/technical-overview.md)

## 子项目与独立发布

- [客户端](client/README.md)：打开 `client/project.godot`；包含 Godot、网页 UI 和模型缓存。
- [服务端](server/README.md)：Python 权威服务，可独立安装依赖和运行测试。
- [共享协议](protocol/README.md)：规则唯一源、v2 传输格式及 v1 兼容说明。

```powershell
# 修改客户端场景后导出，再独立发布（不重启后端）
powershell -NoProfile -ExecutionPolicy Bypass -File tools/export-web.ps1
.\.venv\Scripts\python.exe tools/deploy_public.py --component client
# 仅发布服务端（不更换客户端产物）
.\.venv\Scripts\python.exe tools/deploy_public.py --component server
# 两端配套升级
.\.venv\Scripts\python.exe tools/deploy_public.py --component all
```

- [本次逐批实施记录](doc/session-sync-implementation-log.md)
- [自动恢复与同步优化验收报告](doc/session-sync-completion-report.md)
