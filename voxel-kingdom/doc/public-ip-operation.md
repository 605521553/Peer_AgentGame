# 公网 IP 版本使用与维护

更新：2026-10-15（北京时间）。入口：<https://140.143.163.231>。

## 玩家使用

1. 使用支持 WebGL 2 的桌面 Chrome / Edge 浏览器打开入口。
2. 本阶段使用自签 IP 证书；首次访问会出现证书不受信任提示。确认地址是上面的服务器 IP 后，在浏览器“高级”中选择继续访问。无需安装系统根证书，不要全局关闭浏览器证书检查。
3. 邀请码由房主提供。房主本机保存于 `%LOCALAPPDATA%\VoxelKingdom\公网访问凭据.md`，也有机器可读文件 `public-access.json`。这两份文件在项目之外，勿放入 Web 发布目录。
4. 输入名字、房间和邀请码。多人填写同一房间，每个房间最多四个身份。
5. 点击自己的区域，再输入“在这里创建一座灰墙蓝顶的城堡”。也可用建筑面板导入 JSON 或修改一个方块的颜色。
6. WASD 平移、Q/E 旋转、滚轮缩放、右键拖动。刷新后自动恢复原会话、房间和相机，无需点击进入或再次输入邀请码。点击“退出”会清除本机该房间会话，但不会删除服务器存档或释放原玩家槽位。

玩家无需启动本地后端，无需安装 Python/Godot，也不需要获得 DeepSeek API Key。浏览器负责渲染，Ubuntu 服务器负责验证命令、保存世界、广播更新、调用 DeepSeek。

首次加载 WebAssembly 约需下载 10 MB 压缩数据，实际耗时取决于服务器带宽和玩家网络。本阶段未进行手机/Safari及两台不同网络物理设备验收。

若浏览器没有允许继续访问的选项，需要检查设备管理策略或改用允许此测试方式的桌面浏览器；本次不安装根证书或规避企业策略。长期正式开放可另行配置受信任证书。

## 服务器布局

| 项目 | 配置 |
|---|---|
| 公网入口 | Nginx HTTPS 443，IP 虚拟主机；IP HTTP 80 跳转至 HTTPS |
| 后端 | `127.0.0.1:8765`，单 Uvicorn worker |
| WSS | 同源 `/ws`，浏览器每 15 秒发送心跳，代理超时 90 秒 |
| AI 请求超时 | 代理读取超时 300 秒，覆盖模型请求与一次纠错 |
| 发布目录 | `/opt/voxel-kingdom/releases/<时间戳>` |
| 当前版本 | `/opt/voxel-kingdom/server-current` 与 `client-current` 两个符号链接 |
| Python 环境 | `/opt/voxel-kingdom/venv` |
| 服务账号 | `voxel-kingdom`，无登录 shell |
| 运行配置 | `/etc/voxel-kingdom/server.env`，root:voxel-kingdom 640 |
| 数据目录 | `/var/lib/voxel-kingdom`，专用账号 700 |
| 世界数据 | `/var/lib/voxel-kingdom/world.sqlite3`，SQLite WAL |
| 证书与私钥 | `/etc/voxel-kingdom/tls/` |
| 备份 | `/var/lib/voxel-kingdom/backups/`，每日在线一致性备份，保留最近 7 份 |
| 内存限制 | MemoryHigh=384M、MemoryMax=640M |
| CPU 限制 | CPUQuota=150%，约 1.5 个 CPU 核的时间配额 |

现有 `api.patelender.cn` 仍由原 Nginx 站点处理；直接 IP / 无 SNI 默认 HTTPS 站点现在为游戏入口。未占用 8080，未修改 PostgreSQL、Redis、Mihomo 配置。未修改云安全组，443 已经可通过公网访问。

## 常用维护命令

先 `ssh ubuntu@140.143.163.231` 登录，再执行：

```bash
# 状态与日志
sudo systemctl status voxel-kingdom --no-pager
sudo journalctl -u voxel-kingdom -n 100 --no-pager
sudo tail -n 100 /var/log/nginx/voxel-kingdom.error.log

# 后端健康
curl http://127.0.0.1:8765/api/health

# 启停（启动已设置为开机自动运行）
sudo systemctl restart voxel-kingdom
sudo systemctl stop voxel-kingdom
sudo systemctl start voxel-kingdom

# 立即备份和检查计划
sudo systemctl start voxel-kingdom-backup.service
systemctl list-timers voxel-kingdom-backup.timer --no-pager
sudo ls -lh /var/lib/voxel-kingdom/backups/

# Nginx 修改后先验证，再平滑重载
sudo nginx -t && sudo systemctl reload nginx
```

备份按服务器时区每日 03:00 加最多五分钟随机延迟执行。备份使用 SQLite backup API 并执行完整性检查，不直接复制正在使用的数据库文件。当前备份仍在同一服务器，应按需要另存到服务器之外。

修改邀请码或 DeepSeek 配置时使用 `sudoedit /etc/voxel-kingdom/server.env`，之后重启游戏服务。修改邀请码只影响新身份，已有会话仍有效；它不是完整的账号封禁系统。不要把配置内容粘贴到共享日志中。

## 更新与回退

本机项目根目录执行：

```powershell
# 如改动 Godot / HTML 模板，先重新导出。
powershell -NoProfile -ExecutionPolicy Bypass -File tools/export-web.ps1
# 部署工具需要本地 paramiko（当前已安装）。SSH 密码交互输入。
.\.venv\Scripts\python.exe tools/deploy_public.py
```

工具校验已记录的 SSH 主机密钥，按组件白名单打包 `server/backend`、`protocol`、`client/web`、`build/client-web`、`deploy`。上传与安装日志不包含 SSH 密码、DeepSeek 密钥或邀请码。`--component client` 只更新客户端、不重启后端；`--component server` 只更新服务端、不更换客户端；默认 `all` 更新两端。服务端更新期间短暂重启，浏览器会重连；请避开正在执行的 AI 请求。当前脚本保留旧版本目录，但不提供失败后的全自动回退。

出现问题时，可读取 `/opt/voxel-kingdom/previous-server-release` 或 `previous-client-release`，确认其为本项目真实的旧发布目录，再将对应 `server-current` 或 `client-current` 链接切回。服务端回退需重启游戏服务；客户端回退无需重启后端。旧的 `/opt/voxel-kingdom/current` 保留为首次部署历史，不再是活动版本入口。若 Nginx 配置也发生变化，需要恢复旧版本的配置并先执行 `nginx -t`。首次发布没有旧版本可回退。数据库结构变化应另做迁移和恢复验证，不能仅靠切换代码版本恢复。

## 限制与待办

- 邀请码适合熟人测试；尚无完整注册登录、封禁、每日费用预算和开放注册防滥用体系。每个身份每分钟最多 6 次 AI 请求，全局同时最多 4 次。
- 当前锁和广播在进程内，不可增加多个 worker / 多实例。扩容需要先改共享状态与广播机制。
- 公网房间仍最多四个身份，离开页面不释放玩家槽位；请复用原浏览器会话或创建新房间。
- 自签证书截至 2027-10-15，尚无自动续期。到期前需更换；更换后浏览器可能再次要求确认。
- 原有域名证书的 Certbot 续期失败是部署前既有问题，本次未修复；原证书截至 2026-11-11。
- 本次未重启整台服务器；验证的是游戏服务重启与 systemd 开机启用状态。

2026-10-15 自动恢复与同步优化的详细结果见 [新验收报告](session-sync-completion-report.md)。
