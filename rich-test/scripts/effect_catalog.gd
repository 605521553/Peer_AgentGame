extends RefCounted
## Declarative catalog. Every example is editable BBCode, not a separate renderer.

static func number(key: String, label: String, value: float, low: float, high: float, step: float = 0.1) -> Dictionary:
	return {"key": key, "label": label, "default": value, "min": low, "max": high, "step": step, "kind": "number"}

static func color(key: String, label: String, value: String) -> Dictionary:
	return {"key": key, "label": label, "default": value, "kind": "color"}

static func choice(key: String, label: String, value: String, options: Array) -> Dictionary:
	return {"key": key, "label": label, "default": value, "options": options, "kind": "choice"}

static func entry(id: String, title: String, group: String, description: String, tag: String, params: Array = [], word: String = "不可思议", body: String = "") -> Dictionary:
	return {"id": id, "title": title, "group": group, "description": description, "tag": tag, "params": params, "word": word, "body": body}

static func all() -> Array[Dictionary]:
	var amp: Dictionary = number("amp", "幅度 / 强度", 8, 0, 40)
	var speed: Dictionary = number("speed", "速度 · 周期/秒", 2, 0, 12)
	var spread: Dictionary = number("spread", "字符相位差", 0.55, 0, 3)
	var duration: Dictionary = number("duration", "入场时长 · 秒", 0.65, 0.05, 5)
	var result: Array[Dictionary] = [
		entry("color", "文字颜色", "样式", "给局部词语上色。颜色支持透明度，组合使用可突出剧情关键词。", "[color={color}]{word}[/color]", [color("color", "文字颜色", "#73e6cc")]),
		entry("size", "局部字号", "样式", "静态字号会参与排版；动态缩放只改变绘制，不改变占位。", "[font_size={size}]{word}[/font_size]", [number("size", "字号 · px", 38, 12, 72, 1)]),
		entry("font", "局部字体", "样式", "宋体、楷体、等宽字体使用 SystemFont 资源。实际字体由当前系统提供，缺失时会回退。", "[font={font}]{word}[/font]", [choice("font", "字体资源", "res://fonts/handwriting.tres", ["res://fonts/handwriting.tres", "res://fonts/serif.tres", "res://fonts/mono.tres"])], "山海之间"),
		entry("bold", "加粗", "样式", "使用独立粗体字体，提高关键词的视觉重量。", "[b]{word}[/b]"),
		entry("italic", "斜体", "样式", "用倾斜字体表达旁白、心声或外语。中文字体使用合成倾斜。", "[i]{word}[/i]"),
		entry("bolditalic", "粗斜体", "样式", "样式可正确嵌套；标签必须按相反顺序关闭。", "[b][i]{word}[/i][/b]"),
		entry("underline", "下划线", "样式", "局部下划线，可自定义线条颜色。", "[u color={color}]{word}[/u]", [color("color", "线条颜色", "#f4c576")]),
		entry("strike", "删除线", "样式", "用于删改、反悔或不可靠的叙述。", "[s color={color}]{word}[/s]", [color("color", "线条颜色", "#ff8b95")], "我并不害怕"),
		entry("background", "背景高亮", "样式", "背景填色可以像荧光笔一样突出线索。", "[bgcolor={color}]{word}[/bgcolor]", [color("color", "背景颜色", "#38776588")]),
		entry("foreground", "前景覆盖", "样式", "fgcolor 覆盖文字前景，低透明度可用于遮盖或涂抹。", "[fgcolor={color}]{word}[/fgcolor]", [color("color", "覆盖颜色", "#e6a27855")]),
		entry("outline", "局部描边", "样式", "使用原生字体描边，不需要 Shader。", "[outline_size={size}][outline_color={color}]{word}[/outline_color][/outline_size]", [number("size", "描边宽度", 5, 0, 12, 1), color("color", "描边颜色", "#425083")]),
		entry("mono", "等宽 / 代码", "样式", "code 使用主题配置的等宽字体；中文由字体回退处理。", "[code]{word}[/code]", [], "SIGNAL_042"),
		entry("spacing", "字距与倾斜", "样式", "font 可控制字距、额外行距、合成加粗与倾斜。", "[font glyph_spacing={spacing} slant={slant} embolden={weight}]{word}[/font]", [number("spacing", "额外字距 · px", 5, -2, 20, 1), number("slant", "倾斜", 0.1, -0.5, 0.5, 0.01), number("weight", "合成字重", 0.3, -0.5, 2, 0.05)]),
		entry("wave", "波浪", "内置", "Godot 内置 wave。字符沿垂直方向起伏。", "[wave amp={amp} freq={freq} connected={connected}]{word}[/wave]", [amp, number("freq", "频率", 3, 0, 15), choice("connected", "连字同步", "1", ["1", "0"])], "风吹过山谷"),
		entry("shake", "随机抖动", "内置", "Godot 内置 shake。connected 控制连字，不是整词同步；整词震动请用自定义 tremble。", "[shake rate={rate} level={level} connected={connected}]{word}[/shake]", [number("rate", "刷新频率", 20, 0, 60, 1), number("level", "震动强度", 5, 0, 25, 1), choice("connected", "连字同步", "1", ["1", "0"])], "有东西在靠近"),
		entry("tornado", "环绕 / 龙卷", "内置", "Godot 内置 tornado。负频率可以反向运动。", "[tornado radius={radius} freq={freq} connected={connected}]{word}[/tornado]", [number("radius", "环绕半径", 6, 0, 30), number("freq", "频率", 2, -10, 10), choice("connected", "连字同步", "1", ["1", "0"])], "星辰旋转"),
		entry("rainbow", "流动彩虹", "内置", "Godot 内置 rainbow。覆盖原有文字颜色，可调饱和度、亮度及流动方向。", "[rainbow freq={freq} sat={sat} val={val} speed={speed}]{word}[/rainbow]", [number("freq", "颜色分布", 0.4, 0, 4), number("sat", "饱和度", 0.65, 0, 1, 0.01), number("val", "亮度", 1, 0, 1, 0.01), number("speed", "流动速度", 0.6, -4, 4)], "彩色的梦"),
		entry("pulse", "颜色 / 透明度脉冲", "内置", "Godot 内置 pulse。目标颜色乘以原文字颜色，透明度支持八位 HEX。", "[pulse freq={freq} color={color} ease={ease}]{word}[/pulse]", [number("freq", "脉冲频率", 2, 0.1, 10), color("color", "目标乘色 / 透明度", "#b5a2ff40"), number("ease", "缓动指数", -2, -5, 5)], "微弱的信号"),
		entry("fade", "静态渐隐", "内置", "fade 是按字符分布的静态透明度渐变，并非随时间淡出。", "[fade start={start} length={length}]{word}[/fade]", [number("start", "渐隐开始位置", 2, 0, 30, 1), number("length", "渐隐字符数", 8, 1, 40, 1)], "记忆渐渐消失在远方"),
		entry("tremble", "自定义多模式抖动", "自定义", "确定性噪声保证描边与正文同步。可选水平、垂直、双轴，以及整词同步。", "[tremble amp={amp} speed={speed} axis={axis} sync={sync}]{word}[/tremble]", [amp, speed, choice("axis", "抖动方向", "xy", ["xy", "x", "y"]), choice("sync", "整词同步", "false", ["false", "true"])], "别回头"),
		entry("swing", "水平摇摆", "自定义", "正弦运动与字符相位差；相位差为零时整词一起移动。", "[swing amp={amp} speed={speed} spread={spread}]{word}[/swing]", [amp, speed, spread]),
		entry("float", "轻柔漂浮", "自定义", "同时叠加水平和垂直运动，适合梦境或幽灵对白。", "[float amp={amp} speed={speed} spread={spread}]{word}[/float]", [amp, number("speed", "速度", 0.6, 0, 5), spread], "云上的来信"),
		entry("bounce", "持续弹跳", "自定义", "字符反复弹跳。要只在出现时弹一下，使用弹性入场。", "[bounce amp={amp} speed={speed} spread={spread}]{word}[/bounce]", [amp, speed, spread], "太棒啦"),
		entry("ghost", "若隐若现", "自定义", "通过透明度变化保持排版占位。相位差为零时整词同步隐现。", "[ghost speed={speed} min={min} spread={spread}]{word}[/ghost]", [speed, number("min", "最低透明度", 0.1, 0, 1, 0.01), spread], "你看得见我吗"),
		entry("blink", "规律闪烁", "自定义", "占空比决定每个周期亮起的比例。", "[blink speed={speed} duty={duty} min={min} spread={spread}]{word}[/blink]", [speed, number("duty", "亮起占比", 0.6, 0.05, 0.95, 0.01), number("min", "熄灭透明度", 0.05, 0, 1, 0.01), spread], "警告"),
		entry("flicker", "不规则闪烁", "自定义", "像接触不良的灯一样不规则变化，正文与描边共用随机状态。", "[flicker speed={speed} min={min}]{word}[/flicker]", [speed, number("min", "最低透明度", 0.1, 0, 1, 0.01)], "连接不稳定"),
		entry("breathe", "呼吸缩放", "自定义", "围绕字符基线原点缩放。不会重新排版，大幅度可能与相邻文字重叠。", "[breathe amp={amp} speed={speed} spread={spread}]{word}[/breathe]", [amp, number("speed", "速度", 0.8, 0, 6), spread], "心跳"),
		entry("wobble", "旋转摇晃", "自定义", "绕字符基线原点轻微旋转，适合醉意或俏皮的语气。", "[wobble amp={amp} speed={speed} spread={spread}]{word}[/wobble]", [amp, speed, spread]),
		entry("spin", "持续旋转", "自定义", "字符独立旋转，负速度反向运动。", "[spin speed={speed} spread={spread}]{word}[/spin]", [number("speed", "旋转速度", 0.35, -3, 3), spread], "旋转吧"),
		entry("stretch", "弹性拉伸", "自定义", "横向拉伸同时轻微纵向压缩，形成卡通感。", "[stretch amp={amp} speed={speed} spread={spread}]{word}[/stretch]", [amp, speed, spread], "软绵绵"),
		entry("gradient", "双色流光", "自定义", "两个颜色间平滑插值，透明度保留给其他嵌套效果。", "[gradient from={from} to={to} speed={speed} spread={spread}]{word}[/gradient]", [color("from", "起始颜色", "#73e6cc"), color("to", "终点颜色", "#b5a2ff"), speed, spread], "极光之下"),
		entry("glitch", "故障错位", "自定义", "偶尔出现横向位移和颜色跳变，不使用 Shader。", "[glitch amp={amp} speed={speed}]{word}[/glitch]", [amp, speed], "SYSTEM ERROR"),
		entry("scramble", "乱码还原", "入场", "字符显示后先变成字母，再还原原字形。点击重新播放观察，使用原字体字形接口。", "[scramble duration={duration} speed={speed}]{word}[/scramble]", [duration, speed], "秘密坐标已解密"),
		entry("pop", "弹性入场", "入场", "每个字符拥有独立显示时间；出现时放大后回到原尺寸。", "[pop amp={amp} duration={duration}]{word}[/pop]", [amp, duration], "找到宝藏了"),
		entry("rise", "上浮入场", "入场", "从下方向上浮入并淡入，打字播放时每个字符独立开始。", "[rise amp={amp} duration={duration}]{word}[/rise]", [amp, duration], "晨光缓缓升起"),
		entry("slide", "侧滑入场", "入场", "从左侧滑入并淡入。运动不改变文字占位。", "[slide amp={amp} duration={duration}]{word}[/slide]", [amp, duration]),
		entry("reveal", "逐字淡入", "入场", "渐进透明度和逐字显现结合，减少突然出现的跳跃感。", "[reveal duration={duration}]{word}[/reveal]", [duration], "故事开始了"),
		entry("fall", "落下入场", "入场", "从上方落下，带轻微旋转。重新播放会重置入场时间。", "[fall amp={amp} duration={duration}]{word}[/fall]", [amp, duration], "来自天空的礼物"),
		entry("fear", "恐惧", "情绪", "小幅高频颤抖、冷色与较慢局部语速组合。", "[speed={cps}][color={color}][tremble amp={amp} speed=3]{word}[/tremble][/color][speed=28]", [number("amp", "颤抖幅度", 2, 0, 15), number("cps", "局部字/秒", 12, 1, 100, 1), color("color", "情绪颜色", "#b5a2ff")], "我听见了脚步声"),
		entry("anger", "愤怒", "情绪", "粗体、暖色和整词同步重震。", "[b][color={color}][tremble amp={amp} speed={speed} sync=true]{word}[/tremble][/color][/b]", [amp, speed, color("color", "情绪颜色", "#ff8b95")], "现在就离开"),
		entry("joy", "开心", "情绪", "亮色、弹跳与入场缩放可以自然叠加。", "[color={color}][bounce amp={amp} speed={speed}][pop duration=0.5 amp=8]{word}[/pop][/bounce][/color]", [amp, speed, color("color", "情绪颜色", "#f4c576")], "我们成功啦"),
		entry("mystery", "神秘", "情绪", "慢速漂浮与若隐若现组合。", "[float amp={amp} speed=0.4][ghost speed={speed} min=0.2][color={color}]{word}[/color][/ghost][/float]", [amp, number("speed", "隐现速度", 0.5, 0, 5), color("color", "情绪颜色", "#73e6cc")], "你终于来了"),
		entry("whisper", "低声耳语", "情绪", "较小字体、较低音高与缓慢淡入。", "[voice=0.7][font_size={size}][reveal duration={duration}]{word}[/reveal][/font_size][voice=1]", [number("size", "字号", 22, 12, 48, 1), duration], "别让他们知道"),
		entry("rhythm", "语速 / 等待 / 音高", "节奏", "播放控制标签不参与排版。[speed] 改变后续语速，[wait] 显式等待，[voice] 改变音高倍率。", "{word}", [number("wait", "等待 · 秒", 0.8, 0, 5), number("slow", "慢速 · 字/秒", 10, 1, 100, 1), number("fast", "快速 · 字/秒", 55, 1, 150, 1)], "别动", "[speed={slow}]你听见了吗？[wait={wait}]\n[voice=0.7][b]{tag}[/b][voice=1]……[wait={wait}]\n[speed={fast}][color=#f4c576]快跑，别停下来！[/color]"),
		entry("alignment", "段落对齐", "排版", "left / center / right / fill 控制段落对齐。", "[p align={align}]{word}[/p]", [choice("align", "对齐方式", "center", ["left", "center", "right", "fill"])], "写给远方的你", "{tag}\n山谷里的风，带来了很久以前的回声。\n每一个词，都有自己的位置。"),
		entry("indent", "段落缩进", "排版", "indent 可以嵌套。", "[indent]{word}[/indent]", [], "这是藏在书页里的秘密。", "普通段落\n{tag}\n[indent][indent]第二层缩进[/indent][/indent]"),
		entry("lists", "项目列表", "排版", "ul 支持自定义项目符号，ol 支持数字、字母和罗马数字。", "{word}", [choice("type", "编号形式", "1", ["1", "a", "A", "i", "I"])], "探险清单", "[b]{tag}[/b]\n[ul bullet=•]提灯\n地图\n勇气[/ul]\n[ol type={type}]进入山谷\n找到钥匙\n打开大门[/ol]"),
		entry("table", "表格与单元格", "排版", "table / cell 支持背景、边框、内边距与列宽比例。", "{word}", [color("color", "单元格背景", "#223e43")], "物品档案", "[b]{tag}[/b]\n[table=2][cell bg={color} padding=12,8,12,8 border=#52706e]物品[/cell][cell bg={color} padding=12,8,12,8 border=#52706e]描述[/cell][cell padding=12,8,12,8]金色钥匙[/cell][cell padding=12,8,12,8]打开旧塔的门[/cell][cell padding=12,8,12,8]月光石[/cell][cell padding=12,8,12,8][pulse]仍有余温[/pulse][/cell][/table]"),
		entry("dropcap", "首字下沉", "排版", "dropcap 使开头大字跨越多行。", "[dropcap font_size={size} color={color}]{word}[/dropcap]", [number("size", "首字字号", 64, 30, 100, 1), color("color", "首字颜色", "#f4c576")], "夜", "{tag}幕降临的时候，我们仍在寻找那扇门。山谷里的灯已经熄灭，只剩下远处的钟声。\n这一次，故事会有不同的结局。"),
		entry("separator", "分隔线与换行", "排版", "hr 插入分隔线；br 插入不创建新段落的换行。", "{word}", [number("height", "线条高度", 2, 1, 8, 1), color("color", "线条颜色", "#52706e")], "第一章 · 回声", "[center][b]{tag}[/b][/center]\n[hr color={color} height={height} width=80%]\n门后传来了声音。[br]那是你自己的声音。"),
		entry("image", "行内图片", "交互", "img 将纹理放入文本流。支持大小、着色与对齐，示例使用项目内的 SVG 星星。", "[img width={size} height={size} color={color}]res://assets/star.svg[/img] {word}", [number("size", "图标尺寸", 32, 12, 80, 1), color("color", "图标乘色", "#ffffff")], "稀有物品"),
		entry("hint", "悬停提示", "交互", "将鼠标停在下划线文字上查看提示。提示内容可以直接在 BBCode 编辑器修改。", "[hint=\"一枚能打开旧塔大门的钥匙\"][u]{word}[/u][/hint]", [], "金色钥匙"),
		entry("link", "点击关键词", "交互", "url 标签发送 meta_clicked 信号。实验室点击后显示词条，不会启动外部浏览器。", "[url=clue:key][color=#73e6cc]{word}[/color][/url]", [], "失落的钥匙"),
		entry("escape", "转义与 Unicode", "排版", "lb / rb 显示方括号，char 插入 Unicode 字符。方向与零宽控制符可直接在编辑器中输入。", "{word}", [], "标签也是文字", "{tag}\n[lb]b[rb]这里不会加粗[lb]/b[rb]\n[char=2605] Unicode 星星   [char=2665] 爱心\n[font=res://fonts/mono.tres]abc [lri]123[pdi] xyz[/font]"),
		entry("mixed", "综合演出", "情绪", "混合静态样式、局部动画、等待、局部语速和入场。修改编辑器可自由组合所有标签。", "{word}", [], "别回头", "[font_size=18][color=#96aaa9]守塔人 · 深夜[/color][/font_size]\n[reveal duration=0.4]风停了。[/reveal][wait=0.6]\n你握紧了 [color=#f4c576][b]金色钥匙[/b][/color]。[wait=0.4]\n门后传来[ghost speed=0.7 min=0.2][color=#b5a2ff]熟悉的声音[/color][/ghost]……\n[wait=0.8][speed=14][b][tremble amp=2 speed=3][color=#ff8b95]{tag}。[/color][/tremble][/b][wait=0.5]\n[speed=38][pop amp=8 duration=0.5][color=#73e6cc]故事，才刚刚开始。[/color][/pop]")
	]
	return result

static func render_tag(item: Dictionary, values: Dictionary, word: String) -> String:
	var substitutions: Dictionary = values.duplicate()
	substitutions["word"] = word.replace("[", "[lb]")
	return str(item.tag).format(substitutions)

static func render_example(item: Dictionary, values: Dictionary, word: String) -> String:
	var substitutions: Dictionary = values.duplicate()
	substitutions["tag"] = render_tag(item, values, word)
	if not str(item.body).is_empty():
		return str(item.body).format(substitutions)
	return "门后的声音突然变得 " + str(substitutions.tag) + "。\n\n你停下脚步，仔细听着。\n[color=#96aaa9]每个词，都可以有自己的表情。[/color]"
