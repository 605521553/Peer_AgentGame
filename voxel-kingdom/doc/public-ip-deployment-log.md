# 公网 IP 部署修改与验证记录

日期：2026-10-15（Asia/Shanghai）。目标：浏览器通过服务器 IP 使用 HTTPS/WSS 游玩，同步多人建筑并调用 DeepSeek。每批修改在本文追加，最终结果另见验收报告。本文不保存密码、API Key 或邀请凭据。

## 01 · 开始实施与基线

- 已获得用户授权部署到 140.143.163.231（Ubuntu），暂不配置域名。
- 已有实现：Godot Compatibility Web 客户端、FastAPI 权威命令服务、SQLite、WebSocket、DeepSeek。
- 服务器此前只读检查：2 核、约 1.7 GiB 内存；Nginx 80/443、Sub2API 8080、PostgreSQL 5432、Redis 6379、Mihomo 7890。游戏 8765 空闲。
- 现有业务域名 api.patelender.cn；其 Certbot 续期失败是部署前已存在的问题，证书到期 2026-11-11。
- 计划：独立 systemd 服务、仅本机 HTTP 后端、Nginx IP HTTPS 入口、自签 IP 证书；前端与 API 同源。现有业务保留并核验。
- 公网测试增加邀请入口，以限制陌生访问者创建身份和消耗 AI 额度。
- 本地部署工具依赖增加 Paramiko（只安装在本地 .venv，不属于服务器运行依赖）；SSH 密码只交互输入，不写入源码或日志。
- 尚未部署，尚未进行本轮公网验收。

## 02 · 公网入口、应用保护与部署文件

- `backend/config.py`、`backend/app.py`：增加可选邀请验证；旧会话凭证恢复不要求重复邀请；健康接口只暴露是否启用邀请，不暴露邀请内容。
- 请求体按流累计限制 1 MiB；非法 Content-Length 返回 400，防止未携带长度时无界读取。
- `web/app.js`、`web/shell.html`：新增按配置显示的邀请码输入，API 与 WSS 继续自动使用当前网页地址；HTTPS 提示覆盖公网使用。
- `deploy/`：新增专用用户 systemd 服务（单 worker、127.0.0.1:8765、资源上限、自动重启）、Nginx IP 443 站点（自签 IP 证书、限流、WebSocket 转发、压缩静态文件）、每日 SQLite 在线一致性备份及安装脚本。
- 入口决定：使用已开放的 443，游戏地址为 `https://140.143.163.231`；原 `api.patelender.cn` 的具名虚拟主机继续保留。部署前该原站点返回 HTTP 200。
- `tools/deploy_public.py`：白名单打包、SFTP 传输、SSH 主机密钥校验、交互式密码；只传必要 DeepSeek 配置；上传的临时配置在结束后删除。邀请码仅保存在项目外私有文件。
- 验证：本地 pytest **42 passed**，包含邀请拒绝/恢复、无邀请模式、非法长度、分块超限。仅有已有 Starlette/httpx 弃用提示。
- Web 导出进行中；服务器尚未执行安装。

## 03 · 上传前修正

- Web 导出已成功。
- 首次部署工具在生成版本号时发现 Windows venv 无 IANA tzdata；发生在上传之前，未修改服务器。
- 改为明确的 UTC+08:00 时间戳，避免部署工具依赖额外时区数据库；继续部署。

## 04 · 首次服务器部署完成

- 发布版本：`20261015-163244`；白名单压缩包约 19 MiB，部署日志和 SHA-256 文件清单位于 `artifacts/public-deployment/`。
- 安装 `python3-venv` 时，APT 同时更新了所需 Python 3.12/标准库/setuptools 软件包；未升级整个系统，未重启服务器。
- `/opt/voxel-kingdom/current` 指向该发布；后端由专用无登录用户运行，开机启动已启用。
- Nginx 语法检查成功、平滑重载完成；原站 `api.patelender.cn` 部署前后均为 HTTP 200。
- 服务内部 HTTPS 健康检查通过：AI 已配置、邀请码已开启；初始 systemd MemoryCurrent 36,524,032 字节（约 34.8 MiB）。这只是初始空载值，不代表峰值容量。
- 每日备份计时器已启用，首次 SQLite 一致性备份成功。
- IP 证书有效期：2026-10-15 至 2027-10-15；SHA-256 指纹 `A3:C0:0F:EF:0B:03:87:ED:27:8D:26:4C:68:C5:49:1E:65:3B:36:D9:D0:16:FF:96:82:03:7D:0D:09:86:CF:C5`。
- 邀请码仅存项目外 `%LOCALAPPDATA%/VoxelKingdom/public-access.json`；服务端密钥与邀请存 `/etc/voxel-kingdom/server.env`，未打包公开。
- 新增验收脚本参数：`tools/browser_smoke.py` 和 `tools/live_ai_check.py` 支持公网 URL、独立证据目录、私有邀请文件及 API 测试专用 CA。尚待公网浏览器实测。

## 05 · 公网访问与真实 AI / 浏览器验收

- 本机通过公网 IP 请求 HTTPS：主页、健康接口、WASM 均 200；测试 HTTP 客户端使用从 SSH 获取的指定服务器证书校验，非全局忽略 TLS。
- WASM 正确 MIME `application/wasm`；预压缩传输大小 10,114,291 字节，原文件约 39.5 MB。
- 无邀请码的新身份被拒绝；`/backend/config.py`、`/server.env`、`/world.sqlite3`、`/deploy/install.sh` 均 404。
- `tools/browser_smoke.py` 公网双独立浏览器上下文测试成功：WebAssembly 场景、拾取、创建、单体素改色、JSON 模型形状修改、所有权拒绝、刷新恢复、聊天输入不移动视角、真实 AI 聊天、销毁和拆除、颜色像素检查。
- 浏览器控制台错误为 0；截图已人工查看，3D 城堡和聊天结果显示正常。证据：`artifacts/public-deployment/browser/`。
- `tools/live_ai_check.py` 实际 DeepSeek 三轮成功且均一次生成通过：创建 10,220 ms、单体素改色 3,421 ms、销毁 2,001 ms；其他方块形状与颜色保持，销毁后为空。证据：`artifacts/public-deployment/ai/deepseek-live.json`。
- 测试房间分别为 `web-check-1792053300`、`ai-check-1792053311`，建筑已由测试正常删除；未操作正式玩家房间。
- 新增 `tools/public_recovery_check.py`：将验证浏览器离线重连、后端重启持久性、两方 WSS 恢复及重启后的命令同步。
- 范围说明：本轮两个浏览器身份在同一物理电脑，经公网访问远程服务器；不是两台不同网络设备的实测。

## 06 · 恢复测试与交付文档

- `tools/public_recovery_check.py` 已通过：离线浏览器恢复至最新快照、systemd 服务重启后持久状态与会话一致、双方建立新 WSS 连接、重启后销毁继续同步。恢复样本 2.53 秒。
- 测试后游戏服务 active、约 35.4 MiB 内存，已有 API 站点 HTTP 200；备份再执行成功。测试建筑已清理。
- 添加 `doc/public-ip-operation.md`：玩家访问、配置布局、启停、备份、更新、回退和限制说明。
- 添加 `doc/public-ip-acceptance-report.md`：完成情况、实测数据、证据链接和验收边界。
- 邀请码另写入项目外 `%LOCALAPPDATA%/VoxelKingdom/公网访问凭据.md`，方便房主查阅和向测试玩家分享。
- 更新 README 与文档索引，保留第一阶段原本机/局域网报告作为历史，本次公网报告作为补充。
- 当前服务保留运行，可通过公网 IP 开始测试；尚未完成两台不同网络物理设备、手机和长期负载验收。
- 交付前凭据检查通过：扫描 53 个本地源码/构建/部署/文档文件及发布压缩包各成员，未发现实际 DeepSeek Key 或邀请码；私有访问指南存在于项目外。
