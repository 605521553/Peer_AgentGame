# 公网 IP 版本完成情况与验收报告

日期：2026-10-15（北京时间）。入口：<https://140.143.163.231>。发布：`20261015-163244`。

## 已实现

- Ubuntu 服务器托管网页及游戏权威服务，玩家浏览器通过 HTTPS/WSS 交互。
- 公网 IP 自签证书，Nginx 同源代理，静态 WebAssembly 压缩传输。
- DeepSeek 密钥仅在服务器私有配置中；每次 AI 请求附带规则，返回命令由服务器验证。
- 可选邀请码、请求大小限制、入口限流、专用系统账号和单进程资源限制。
- systemd 常驻与开机启动、每日 SQLite 在线一致性备份。
- 新增部署与验收脚本、逐批修改记录及操作说明。

## 已完成验证

| 验收项 | 结果与证据 |
|---|---|
| 本地回归 | 42 项 pytest 通过，1 项已有依赖弃用警告 |
| Godot Web 导出 | 成功，Compatibility |
| 公网 HTTPS 主页 / 健康接口 | 200；API 测试使用指定服务器证书验证 |
| WASM 传输 | MIME 正确，gzip 10,114,291 字节 |
| 无邀请访问新身份 | 拒绝；既有会话恢复已回归验证 |
| 私有文件暴露检查 | 配置、源码、数据库、部署脚本探测均 404 |
| 发布凭据检查 | 53 个源码/构建/部署/文档文件及发布压缩包未发现实际 API Key 或邀请码 |
| 两个独立浏览器身份 | 创建、单块改色、形状 JSON 导入、拆除、销毁均同步 |
| 权限验证 | 他人建筑修改/销毁被拒绝 |
| 刷新与拾取 | 刷新恢复、建筑/方块拾取、聊天输入不移动视角通过 |
| 真实网页 AI 操作 | 自然语言创建一个绿色方块成功并同步 |
| 浏览器运行 | 控制台错误 0；截图已检查 |
| 原有 API 网站 | 部署前后均 HTTP 200 |
| 初始备份 | 服务成功，SQLite 完整性检查通过 |

真实 DeepSeek API 三轮（模型 `deepseek-v4-pro`）：

| 操作 | AI 调用耗时 | 结果 |
|---|---:|---|
| 创建城堡 | 10.220 秒 | 已执行，一次生成通过 |
| 修改一个方块颜色 | 3.421 秒 | 仅目标方块改变，其他颜色和几何保持 |
| 销毁建筑 | 2.001 秒 | 已删除，一次生成通过 |

这些耗时为本次样本，不是稳定性能保证。浏览器截图所示四塔堡垒为示例模型，真实 AI 城堡另存于 `ai/deepseek-castle.json`。

## 恢复验证

恢复测试通过，独立验收房间 `recovery-1792053625`：

- 第二个浏览器离线期间，第一个浏览器修改方块；恢复网络后，第二方自动重连并取得一致快照。
- 执行 `systemctl restart voxel-kingdom` 后，两方均建立新的 WSS 连接；本次恢复耗时 2.53 秒。
- 重启前后服务端快照一致，原会话仍有效；再次销毁建筑后两方同步为空。
- 测试后再次完成在线备份；游戏服务 active，MemoryCurrent 37,105,664 字节（约 35.4 MiB），原 API 站点仍 HTTP 200。
- 未重启整台服务器，也未执行人为进程崩溃测试。服务开机启动和失败重启策略已配置。

**结论：公网 IP 邀请测试版本已部署并完成上述功能验收，可以开始使用。**

## 测试范围

两个独立浏览器上下文运行于同一物理 Windows 电脑，连接远端公网服务器，未模拟本机服务器。尚未完成“两台不同网络物理设备”、手机/Safari、长时间压测及大规模并发验收。当前可用于小规模邀请测试，不作公开大规模运营承诺。

## 本地留存

- [逐批修改与结果记录](public-ip-deployment-log.md)
- [玩家使用和服务器维护](public-ip-operation.md)
- [部署日志](../artifacts/public-deployment/deploy-20261015-163244.log)
- [发布文件校验清单](../artifacts/public-deployment/manifest-20261015-163244.json)
- [双浏览器验收数据](../artifacts/public-deployment/browser/browser-smoke.json)
- [浏览器截图](../artifacts/public-deployment/browser/web-ai-chat.png)
- [真实 AI 验收数据](../artifacts/public-deployment/ai/deepseek-live.json)
- [断网与服务重启验收数据](../artifacts/public-deployment/recovery/recovery.json)
- [重启后截图](../artifacts/public-deployment/recovery/after-restart.png)

邀请码保存在项目外 `%LOCALAPPDATA%\VoxelKingdom\公网访问凭据.md`，报告与发布包不包含凭据。
