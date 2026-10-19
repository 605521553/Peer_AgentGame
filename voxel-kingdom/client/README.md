# 客户端子项目

Godot 4.7.2 Compatibility。打开本目录 `project.godot`，F5 运行原生客户端；网页客户端由 `web/` 与 Godot 场景共同构成。

```powershell
# 从仓库根目录导出：
powershell -NoProfile -ExecutionPolicy Bypass -File client/tools/export-web.ps1
# 网格验证：
& 'D:\Godot4.7.2\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path client --script tests/mesher_check.gd
```

产物：`../build/client-web/`。导出后用 Python 标准库生成引擎资源内容版本路径，Nginx 对版本资源长期缓存，HTML/网页脚本及时验证更新。工具优先使用已有根 venv，否则使用 PATH 中的 Python，不需要安装服务端依赖。

新网页使用传输 v2，自动恢复同源浏览器会话与相机；IndexedDB 缓存已验证模型。缓存可清理，服务器持有真实世界。当前原生客户端保留 v1 兼容路径，其桌面 UI 不提供网页自动会话与邀请码流程。

`web/runtime-cache.js` 通过 CacheStorage 缓存同源版本化 WASM/PCK，保留当前及一个旧版本；首次下载流式交给引擎并异步缓存，刷新直接读取缓存。缓存不可用则回退网络。API、身份令牌和世界状态不进入此资源缓存；没有引入 Service Worker。

不依赖服务器 Python 实现进行构建。协议见 `../protocol/README.md`。独立发布使用根目录 `tools/deploy_public.py --component client`，不上传 API 密钥、不重启后端。
