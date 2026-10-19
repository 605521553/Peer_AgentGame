# 树冠顽猴 / Ladder Monkey

Godot **4.7.2** 原生 3D 小游戏。打开 `project.godot`，按 **F6/F5**（主场景 `scenes/main.tscn`）即可运行；不需要导入模型、安装插件或手动绑定节点。

Windows 64 位发行版为 `dist/LadderMonkey.exe`，游戏资源已经内置，双击即可运行，无须安装 Godot 或另带 PCK 文件。重新导出使用：

```powershell
& 'D:\Godot4.7.2\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'D:\Godot4.7.2\Projects\ladder-monkey' --export-release 'Windows Desktop'
```

使用导出配置 `export_presets.cfg`，需安装同版本 Windows x64 导出模板。发行版支持同样的 `--verify` 自检参数，报告写入 Godot 用户数据目录的 `verification` 子目录。

| 按键 | 行为 |
|---|---|
| W（按住） | 向上交替攀爬 |
| S（按住） | 向下交替攀爬 |
| Space（单次） | 安全收尾，转身、拉眼角、眨眼吐舌，再回到梯子 |

同时按 W/S 保持停止意图。松键、反向和 Space 都会先完成当前换档，保证回到有支撑的姿态。鬼脸过程中重复按 Space 不会叠加；结束后会重新读取 W/S。上下边界自动停止。游戏仅在获得奖杯时显示成就提示，不需要鼠标或额外按键。

## 攀爬成就奖杯

默认第一个金色奖杯位于 **3.1 米**，之后每隔 **2.1 米**一枚，当前梯子共有 6 枚。奖杯在玩家前方一定距离内生成，在梯子中央缓慢旋转和轻微浮动。猴子的身体或头部碰到奖杯后，奖杯立即停止、拆成原有杯壁、把手、杯底和底座等 **24 块**刚体碎片。收集区域跟随最终骨盆及头部骨骼，防止大头模型穿过奖杯后才触发。

碎片带有向外及向上的初速度和随机角速度，会因重力下落，与横档、梯柱、地面及树冠平台发生碰撞和弹跳。默认 5 秒后回收，末尾 0.45 秒逐渐缩小，同时最多保留 96 个碎片。碎片只与专用场景碰撞层交互，不影响猴子的支撑、IK 或攀爬控制，也不会挡住其他奖杯的收集检测。

收集后出现「成就达成！」及奖杯对应名称。提示在 384×288 低分辨率画面内绘制，使用像素奖杯图标和内置中文字体，由 Tween 从屏幕下方滑入，停留 2.4 秒后滑出。连续收集会进入队列，每次只显示一个提示。

每枚奖杯在**本次游戏运行中只能收集一次**；下降或重新经过原高度不会再次生成。重启游戏会开始新一轮收集，没有新增存档或额外操作按键。

参数统一放在 `resources/achievement_profile.tres`：起始高度、间距、提前生成距离、旋转速度、浮动、收集半径、成就名称、碎片数量、爆发速度、角速度、弹性、清理时间、碎片上限及 Toast 进出和停留时长均可在检查器修改。

模块分工：

| 文件 | 职责 |
|---|---|
| `scripts/achievements/achievement_manager.gd` | 高度生成、收集去重、跟随最终骨盆的躯干触发器及碎片专用场景碰撞体 |
| `scripts/achievements/trophy_model.gd` | 中空低多边形金杯及预分片模型，完整奖杯与碎片共用网格 |
| `scripts/achievements/trophy_pickup.gd` | Area3D 触碰、旋转浮动、原子式收集锁定 |
| `scripts/achievements/trophy_debris.gd` | RigidBody3D、凸包形状、随机速度、碰撞弹跳及数量/寿命回收 |
| `scripts/achievements/achievement_toast.gd`、`trophy_icon.gd` | 中文提示、像素图标、Tween 动画、FIFO 队列及重复提示过滤 |

物理层 4 为碎片场景、5 为金色碎片、6 为猴子身体收集区域、7 为奖杯检测区域。奖杯使用 Area3D 的真实重叠信号，不是单纯比较角色高度。骨骼完成求解后更新躯干区域；物理查询结束后再创建碎片，避免在物理回调中修改碰撞形状。

## 角色与动作

- `assets/monkey_rig.tscn` 是实际保存的原创蒙皮模型，可直接在编辑器查看 Skeleton3D、Skin、MeshInstance3D 和 AnimationPlayer。
- 49 根骨骼：骨盆、脊柱、胸腔、颈头、四条双骨肢体、手指、7 节尾巴、眼睛、瞳孔、眉毛、下颌和舌头。
- 3,466 个三角形，10,398 个用于平面法线的顶点；2,540 个顶点使用混合骨骼权重。肘、膝、躯干、颈部和尾巴由蒙皮变形。
- AnimationPlayer 提供呼吸基础动画；身体及面部的 SkeletonModifier3D 接在基础动画之后；四个独立 SkeletonModifier3D 使用解析式双骨 IK。
- 支撑手脚目标锁定在横档世界坐标。只有释放的肢体沿五次平滑曲线与离梯弧线移动，终点速度为零。
- 上行先伸手、随后抬脚、再提升骨盆；下行先探脚、受控下沉、再换手。骨盆位移与相同换档进度绑定。
- 肘部有向外、向后的稳定极向量，膝部朝向梯子；IK 不拉伸骨骼。身体先进行可达范围补偿，再求解四肢。
- 鬼脸时左手和两脚保留横档约束；骨盆、脊柱、胸腔、颈头分配转角，右手目标跟随头部面颊。角色节点没有旋转或上下平移，运动发生在真实骨骼上。

## 文件组织与调参

| 文件 | 职责 |
|---|---|
| `scenes/main.tscn`、`scripts/main.gd` | 场景组装、384×288 子视口、像素显示 |
| `scenes/ladder.tscn`、`scripts/world/ladder.gd` | 参数化梯子和世界坐标接触点 |
| `scenes/camera.tscn`、`scripts/world/follow_camera.gd` | 固定方向、平滑垂直跟随 |
| `scenes/forest.tscn`、`scripts/world/forest.gd` | 原创低多边形丛林、地面、水面、树冠平台 |
| `scripts/rig/monkey_rig.gd`、`skin_geometry.gd` | 骨架、蒙皮权重与原创模型生成 |
| `scripts/animation/climb_controller.gd` | 接触所有权、7 状态、换档调度和输入收尾 |
| `scripts/animation/body_pose.gd` | 躯干、可达补偿、尾巴和面部表演 |
| `scripts/animation/two_bone_ik.gd` | 每条肢体的独立 IK、接触方向、手指松握 |
| `resources/climb_profile.tres` | 上下节奏、离梯弧高、重心、肢体长度、IK 权重、鬼脸时长 |
| `shaders/retro.gdshader` | 色阶压缩与轻量 Bayer 抖动 |
| `tools/verification.gd` | 用真实物理键事件驱动的自动验收 |

在 `scenes/ladder.tscn` 的根节点调节横档间距、数量和梯子宽度。默认 34 档、间距 0.42 米、宽 1.24 米。间距和宽度应保留在角色四肢的合理可达范围内。

在检查器打开 `resources/climb_profile.tres` 调整节奏和重心。**修改肢体长度后必须重新生成模型**，使网格、休息姿态与求解长度一致：

```powershell
$godotExe = 'D:\Godot4.7.2\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$monkeyProject = 'D:\Godot4.7.2\Projects\ladder-monkey'
& $godotExe --headless --path $monkeyProject --script res://tools/generate_rig.gd
```

默认 IK 权重 1.0 保持精确接触。减少权重适用于调试混合，不应作为正式攀爬参数。渲染使用 Compatibility/OpenGL，实际 384×288、最近邻放大、有限色阶、低面数和简单光照；顶点不会人为抖动，以保持横档接触清晰。

## 状态规则

| 状态 | 进入、退出与约束 |
|---|---|
| ClimbIdle | 四肢落点固定；W/S 开始换档，Space 进入转身 |
| ClimbUp | 较低的对角肢体先补齐档差；完成半步后重读输入 |
| ClimbDown | 较高的对角肢体先下降；独立落脚和身体下降节奏 |
| ClimbTransition | 松键、反向、Space 请求后完成当前半步，不重定向空中目标 |
| TauntTurn | 完成收尾后转动上半身，右手从横档移向脸，左手/双脚固定 |
| TauntPlay | 固定 3 个支撑点，眼、眉、下颌、舌头与右手表演 |
| TauntReturn | 平滑收回表情与上半身，右手重新准确抓档后允许攀爬 |

方向切换先处理两侧档差，因此不会出现越切换越大的左右落点距离。接触档号在肢体真正落档时更新，身体收尾结束时统一完成该半步。

## 验证与预览

```powershell
& $godotExe --headless --path $monkeyProject --fixed-fps 60 -- --verify
& $godotExe --headless --path $monkeyProject --fixed-fps 30 -- --verify --report-fps=30
& $godotExe --headless --path $monkeyProject --fixed-fps 120 -- --verify --report-fps=120
& $godotExe --path $monkeyProject --fixed-fps 60 -- --capture
& $godotExe --headless --path $monkeyProject --fixed-fps 60 -- --verify-rewards
& $godotExe --path $monkeyProject --fixed-fps 60 -- --capture-rewards
```

`--verify` 注入 W/S/Space 物理键事件，覆盖连续上下爬、松键、途中反向、攀爬中 Space、表演中重复 Space、顶部与底部边界和底部鬼脸。任一关键约束失败时进程以 1 退出，成功以 0 退出。

报告保存到 `artifacts/verification*.json`。自动检查包含：七状态覆盖、接触点与 IK 末端误差、骨段长度不变、至少两个攀爬支撑点、鬼脸三点支撑、左右档差不超过一档、待机高度不漂移、根节点不动及网格权重正常。

完整攀爬验证同时检查六枚真实触碰奖杯全部收集、碎片产生与清理、刚体场景碰撞及六次成就提示完成。`--verify-rewards` 另验证实际飞行/重力/自转、重复经过不重收、同时触碰三枚奖杯时提示排队且不重叠，以及碎片上限生效和全部回收；报告为 `artifacts/reward_verification.json`。`--capture-rewards` 保存 `05_trophy_waiting.png` 至 `08_toast_queue.png`。

`--capture` 生成待机、上爬、下爬和鬼脸的四张实际 3D 渲染图（最近邻放大）。图片位于 `artifacts/01_idle.png` 到 `04_taunt.png`。图片来自 3D 子视口，窗口另施加色阶和抖动后处理。

此实现使用运动学支撑约束与程序化骨骼动画。没有接触力动力学或全身刚体仿真。数值验证证明落点和骨段约束，动作观感则另经实际渲染检查；大幅调整角色比例或梯子间距后应重新运行验证。

所有角色、奖杯和场景几何均在本项目原创生成，没有外部模型或贴图。中文提示字体按 OFL 许可内置，见 `ASSET_LICENSE.md`。游戏运行没有网络依赖。
