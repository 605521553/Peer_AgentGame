# 服务端子项目

Python FastAPI / SQLite 权威服务，无 Godot 或 GPU 依赖。协议规则读取 `../protocol/rules.json`，打包时必须随服务端包含。

```powershell
# 在本目录独立安装、运行和测试：
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m backend.run
# 测试需要 pytest（或安装仓库根目录 requirements-dev.txt）。
.\.venv\Scripts\python.exe -m pytest -q
```

仓库已有根目录工具环境时，可用 `../.venv/Scripts/python.exe`，或 `tools/start-server.ps1`；无需重复安装 Godot。网页资源可缺省，API 仍可运行。开发时可设置 `VOXEL_CLIENT_ROOT` 指向含 `client/web` 和 `build/client-web` 的目录；生产 Nginx 独立提供客户端。

配置继续位于项目之外，默认 Windows `%LOCALAPPDATA%/VoxelKingdom/server.env`；Linux systemd 使用 `/etc/voxel-kingdom/server.env`。不要提交密钥。服务必须单 worker，数据库兼容原部署，保留原房间和会话。

独立部署：根目录 `tools/deploy_public.py --component server`。不包含客户端产物，不更换客户端发布链接；更新后端会短暂重启，客户端自动重连。
