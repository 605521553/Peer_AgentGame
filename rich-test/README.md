# 富文本效果实验室

Godot 4.7.2 项目。打开 `project.godot`，按 **F6** 运行 `scenes/laboratory.tscn`，或按 **F5** 运行已配置的主场景。

## 使用

- 左侧有 55 个示例，支持类别筛选和搜索。首次运行默认选择「综合演出」。
- 右侧参数可用滑条或数字精确输入。颜色支持透明度。默认字体、字号、行距、描边、阴影与画布色可以全局调整。
- 中间编辑器直接输入 BBCode，220 毫秒后实时预览。选中文字，再按「套用到选中文字」可叠加当前效果；无选择时插入片段。
- 手动编辑后，参数变化只更新右侧片段，保留对白。按「载入当前示例」恢复参数与示例的实时联动。
- 每个示例保留自己的参数与编辑草稿。「恢复默认」仅重置当前示例。
- 「重新播放」重置所有打字与动画；「暂停」同时暂停打字、内置动画与自定义动画；「显示全文」跳过打字。
- 音效由四种波形实时合成，可调音色、音高、变化、音量、字符间隔和单音长度。「试听当前音色」直接播放一声。
- `Ctrl+Enter` 重新播放，`Ctrl+S` 保存。退出会自动保存到 `user://rich_text_lab.json`。导入 / 导出 JSON 可交换整个实验室配置。
- 提示标签悬停显示说明；点击词条会在底部显示线索。实验室不会自动打开外部 URL。

## 包含的效果

| 类别 | 内容 |
|---|---|
| 样式 | 颜色、字号、字体、粗体、斜体、粗斜体、下划线、删除线、背景高亮、前景覆盖、局部描边、代码字体、字距/倾斜/字重 |
| Godot 内置 | wave、shake、tornado、rainbow、pulse、fade（静态渐隐） |
| 自定义循环 | tremble 多轴/整词抖动、swing 水平摇摆、float 漂浮、bounce 弹跳、ghost 隐现、blink 规律闪烁、flicker 不规则闪烁、breathe 呼吸缩放、wobble 摇晃、spin 旋转、stretch 拉伸、gradient 双色流光、glitch 故障错位 |
| 逐字入场 | scramble 乱码还原、pop 弹性入场、rise 上浮、slide 侧滑、reveal 淡入、fall 落下 |
| 情绪与节奏 | 恐惧、愤怒、开心、神秘、耳语、综合演出，局部语速、显式等待、局部音高 |
| 排版与交互 | 对齐、缩进、列表、表格、首字下沉、分隔线/换行、行内图片、悬停提示、点击关键词、标签转义与 Unicode |

高级原生 BBCode 参数也可直接在编辑器修改，例如 `font` 的 OpenType 功能与可变字体坐标、`p` 的语言/书写方向/制表位，以及 `img` 的区域/对齐。它们依赖所选字体或图片本身的能力，不保证系统回退字体拥有相应功能。

## 在其他场景复用

`scripts/living_rich_text.gd` 提供 `LivingRichText`，继承 `RichTextLabel`，自动注册所有自定义效果。组件与实验室 UI、音效相互独立。也可以直接实例化 `scenes/living_rich_text.tscn`。

```gdscript
var dialogue := LivingRichText.new()
dialogue.custom_minimum_size = Vector2(700, 260)
add_child(dialogue)
dialogue.characters_per_second = 28
dialogue.punctuation_pause = 0.25
dialogue.sentence_pause = 0.55
dialogue.set_source(
    "你握紧了[color=#f4c576][b]钥匙[/b][/color]。[wait=0.5]" +
    "[tremble amp=2 speed=3 axis=xy sync=false]别回头。[/tremble]",
    true
)
# dialogue.replay() / dialogue.show_all() / dialogue.set_paused(true)
# dialogue.character_revealed.connect(...) / dialogue.playback_finished.connect(...)
```

调用 `set_source()` 前必须将组件加入场景树。播放控制标签：

```text
[wait=0.8]    # 当前位置等待 0.8 秒；只在打字播放时生效
[speed=12]    # 后续每秒 12 字，直到下一个 speed 标签
[voice=0.7]   # 后续音高乘以 0.7，直到下一个 voice 标签
```

这三种标签不需要闭合，是播放指令，不能单独放进普通 `RichTextLabel` 使用。原生与自定义标签可以嵌套；先打开的最后关闭。局部语速示例用 `[speed=28]` 显式恢复到 28 字/秒，可按需编辑。

自定义循环标签常用 `amp`（幅度）、`speed`（每秒周期）、`spread`（字符相位差）；`spread=0` 让字符同步。入场标签使用 `duration`。`tremble` 还支持 `axis=x/y/xy` 和 `sync=true/false`。

`lab_effect.gd` 为每种标签注册独立 `RichTextEffect` 资源，通过共享时钟和逐字出现时间计算效果。回调不修改时钟，不依赖回调次数，因此正文与描边保持一致。

## 字体与限制

- 字体使用 `SystemFont`，默认优先微软雅黑，宋体 / 楷体 / Consolas 通过资源切换；未复制或分发 Windows 字体。其他系统会回退到可用字体。正式发布时建议使用许可合适的项目内字体，并替换这些资源。
- 中文粗体使用合成字重；斜体使用合成倾斜。可替换为真实字重字体。
- 旋转/缩放以字符基线原点为中心；动画不重新布局，大幅度可能重叠。预览留有边距并允许滚动，仍需为实际对白控制幅度。
- 打字以 Godot 排版后的字符位置控制，中文和常规拉丁文本已覆盖。复杂 Emoji、组合字符、双向文字及混合图片的精确节奏，应针对目标语言补充测试。
- 无 Shader / 粒子效果；故障错位与乱码均在字符效果中实现。
- UI 提供结构性 BBCode 提示，不是完整语法检查器；不支持的字体属性或资源路径仍由 Godot 处理。

## 验证

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/test_lab.gd
```

测试遍历全部示例与数值边界，并检查播放控制位置、重复播放、暂停、逐字入场时间、选词套用、手动草稿保护和配置导入。

渲染截图：`godot --path . -- --capture-lab`，结果写入 `artifacts/laboratory.png`。普通运行不会执行截图或自动退出。
