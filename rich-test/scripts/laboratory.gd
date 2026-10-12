extends Control

const Catalog = preload("res://scripts/effect_catalog.gd")
const Voice = preload("res://scripts/type_voice.gd")
const STATE_PATH = "user://rich_text_lab.json"
const INK = Color("e7efef")
const MUTED = Color("96aaa9")
const MINT = Color("73e6cc")
const GOLD = Color("f4c576")

var catalog: Array[Dictionary] = Catalog.all()
var filtered: Array[int] = []
var current_index: int = 0
var parameter_values: Dictionary = {}
var drafts: Dictionary = {}
var settings: Dictionary = {"cps": 28.0, "comma": 0.25, "sentence": 0.55, "font_size": 28.0, "line_space": 16.0, "outline": 0.0, "sound": true, "tone": 0, "pitch": 1.0, "variation": 0.08, "volume": -20.0, "every": 2.0, "duration": 0.045, "background": "#111e28", "font": "默认黑体", "shadow_x": 0.0, "shadow_y": 0.0, "shadow_size": 0.0, "shadow_color": "#00000080"}
var building: bool = true
var manual_mode: bool = false
var list: ItemList
var search: LineEdit
var category: OptionButton
var params_box: VBoxContainer
var detail_title: Label
var detail_text: Label
var word_input: LineEdit
var snippet: TextEdit
var editor: TextEdit
var preview: LivingRichText
var stage: PanelContainer
var status: Label
var playback_info: Label
var progress: ProgressBar
var pause_button: Button
var voice: Node
var debounce: Timer
var export_dialog: FileDialog
var import_dialog: FileDialog
var root_box: VBoxContainer
var font_regular: SystemFont
var _active_group: String = "全部"
var _elapsed_status: float = 0.0

func _ready() -> void:
	DisplayServer.window_set_min_size(Vector2i(1120, 760))
	_load_state()
	_create_theme()
	voice = Voice.new()
	add_child(voice)
	_build_ui()
	_configure_preview()
	_sync_settings()
	voice.regenerate()
	_build_dialogs()
	debounce = Timer.new()
	debounce.one_shot = true
	debounce.wait_time = 0.22
	debounce.timeout.connect(_apply_editor)
	add_child(debounce)
	building = false
	_filter_catalog()
	_select_effect(current_index)
	get_tree().auto_accept_quit = false
	if "--capture-lab" in OS.get_cmdline_user_args():
		_capture_later()

func _create_theme() -> void:
	font_regular = SystemFont.new()
	font_regular.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	var t := Theme.new()
	t.default_font = font_regular
	t.default_font_size = 15
	t.set_color("font_color", "Label", INK)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", MINT)
	t.set_color("font_pressed_color", "Button", MINT)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_color", "TextEdit", INK)
	t.set_color("font_color", "ItemList", INK)
	t.set_color("font_selected_color", "ItemList", MINT)
	t.set_color("selection_color", "TextEdit", Color("315b62"))
	t.set_color("caret_color", "TextEdit", MINT)
	t.set_color("font_color", "CheckButton", INK)
	t.set_color("font_color", "CheckBox", INK)
	t.set_color("font_color", "PopupMenu", INK)
	t.set_stylebox("panel", "PopupMenu", _style(Color("1b2836"), 8))
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, _style(Color("1c2b37"), 7))
		t.set_stylebox("hover", type, _style(Color("29434a"), 7, Color("476960")))
		t.set_stylebox("pressed", type, _style(Color("254a43"), 7, MINT))
		t.set_stylebox("focus", type, _style(Color.TRANSPARENT, 7, MINT))
	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, _style(Color("0e1823"), 7, Color("293c4a")))
		t.set_stylebox("focus", type, _style(Color("111e28"), 7, Color("4d998c")))
	t.set_stylebox("panel", "ItemList", _style(Color("111b26"), 8))
	t.set_stylebox("selected", "ItemList", _style(Color("243f43"), 5))
	t.set_stylebox("selected_focus", "ItemList", _style(Color("243f43"), 5, Color("4d998c")))
	t.set_constant("v_separation", "ItemList", 8)
	t.set_stylebox("background", "ProgressBar", _style(Color("243441"), 3))
	t.set_stylebox("fill", "ProgressBar", _style(MINT, 3))
	t.set_stylebox("slider", "HSlider", _style(Color("2b414d"), 3))
	t.set_stylebox("grabber_area", "HSlider", _style(Color("52796e"), 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", _style(MINT, 3))
	theme = t

func _style(color: Color, radius: int = 10, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	if border.a > 0:
		s.border_color = border
		s.set_border_width_all(1)
	return s

func _label(text_value: String, size: int = 15, color: Color = INK) -> Label:
	var node := Label.new()
	node.text = text_value
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	return node

func _button(parent: Node, text_value: String, action: Callable, tooltip: String = "") -> Button:
	var button := Button.new()
	button.text = text_value
	button.tooltip_text = tooltip
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _column(parent: Node, separation: int = 10) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	parent.add_child(box)
	return box

func _row(parent: Node, separation: int = 8) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	parent.add_child(box)
	return box

func _panel(parent: Node, color: Color = Color("14202d")) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(color, 12, Color("293a47")))
	parent.add_child(panel)
	return panel

func _scroll(parent: Node) -> VBoxContainer:
	var scroller := ScrollContainer.new()
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroller)
	var box := _column(scroller, 12)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return box

func _section(parent: Node, text_value: String) -> void:
	parent.add_child(HSeparator.new())
	parent.add_child(_label(text_value, 16, GOLD))

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("0b111b")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	root_box = _column(margin, 14)
	var header := _row(root_box, 16)
	var title_column := _column(header, 3)
	title_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_column.add_child(_label("TYPE / ALIVE", 13, MINT))
	title_column.add_child(_label("富文本效果实验室", 27))
	header.add_child(_label("%d 种示例  ·  原生 BBCode  ·  无 Shader" % catalog.size(), 14, MUTED))
	_button(header, "保存配置", _save_state)
	_button(header, "导出", func(): export_dialog.popup_centered_ratio(0.7))
	_button(header, "导入", func(): import_dialog.popup_centered_ratio(0.7))
	var workspace := _row(root_box, 14)
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_catalog(workspace)
	_build_center(workspace)
	_build_controls(workspace)
	status = _label("就绪 · 选择效果，调节参数，或直接编辑 BBCode。", 13, MUTED)
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	root_box.add_child(status)

func _build_catalog(parent: Node) -> void:
	var panel := _panel(parent)
	panel.custom_minimum_size.x = 224
	var box := _column(panel, 10)
	box.add_child(_label("01 / 效果目录", 17, MINT))
	search = LineEdit.new()
	search.placeholder_text = "搜索名称、标签或说明…"
	search.text_changed.connect(func(_value): _filter_catalog())
	box.add_child(search)
	category = OptionButton.new()
	for group in ["全部", "样式", "内置", "自定义", "入场", "情绪", "节奏", "排版", "交互"]:
		category.add_item(group)
	category.item_selected.connect(func(index): _active_group = category.get_item_text(index); _filter_catalog())
	box.add_child(category)
	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size = Vector2(200, 180)
	list.auto_height = false
	list.item_selected.connect(func(index): _select_effect(filtered[index]))
	box.add_child(list)
	var tip := _label("提示：先试试「综合演出」。\n入场效果请点「重新播放」。", 12, MUTED)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(tip)

func _build_center(parent: Node) -> void:
	var center := _column(parent, 12)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size.x = 440
	var preview_panel := _panel(center)
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := _column(preview_panel, 10)
	var heading := _row(box)
	heading.add_child(_label("02 / 实时预览", 17, MINT))
	playback_info = _label("", 12, MUTED)
	playback_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	playback_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading.add_child(playback_info)
	stage = _panel(box, Color(settings.background))
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size.y = 210
	var padding := MarginContainer.new()
	for side in ["left", "right"]:
		padding.add_theme_constant_override("margin_" + side, 20)
	for side in ["top", "bottom"]:
		padding.add_theme_constant_override("margin_" + side, 28)
	stage.add_child(padding)
	preview = LivingRichText.new()
	preview.name = "LivingTextPreview"
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.selection_enabled = true
	preview.scroll_active = true
	padding.add_child(preview)
	preview.character_revealed.connect(func(character, position): voice.speak(character, position, preview.voice_pitch))
	preview.meta_clicked.connect(func(meta): _status("词条：%s · 这是一枚可以打开旧塔大门的钥匙。" % str(meta)))
	progress = ProgressBar.new()
	progress.custom_minimum_size.y = 4
	progress.show_percentage = false
	box.add_child(progress)
	var transport := _row(box, 6)
	_button(transport, "▶ 重新播放", _replay, "从头播放打字、局部入场、等待标签和音效")
	pause_button = _button(transport, "Ⅱ 暂停", _pause, "暂停打字与所有文字动画")
	_button(transport, "显示全文", _show_all, "跳过打字，保留动画")
	_button(transport, "复制 BBCode", func(): DisplayServer.clipboard_set(editor.text); _status("BBCode 已复制。"))
	var edit_panel := _panel(center)
	edit_panel.custom_minimum_size.y = 304
	var edit_box := _column(edit_panel, 8)
	edit_box.add_child(_label("03 / BBCode 编辑器", 17, MINT))
	var edit_tools := _row(edit_box, 6)
	_button(edit_tools, "套用到选中文字", _wrap_selection, "先在下方选择一段文字；无选择时插入当前效果片段")
	_button(edit_tools, "载入当前示例", _load_example)
	_button(edit_tools, "撤销", func(): editor.undo())
	_button(edit_tools, "重做", func(): editor.redo())
	editor = TextEdit.new()
	editor.custom_minimum_size.y = 175
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	editor.placeholder_text = "输入 BBCode，或选择一段文字后套用效果…"
	editor.add_theme_font_size_override("font_size", 15)
	editor.text_changed.connect(_editor_changed)
	edit_box.add_child(editor)
	var help := _label("直接编辑会实时预览。手动编辑后，参数只更新片段；点击「载入当前示例」恢复参数联动。", 12, MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	edit_box.add_child(help)

func _build_controls(parent: Node) -> void:
	var panel := _panel(parent)
	panel.custom_minimum_size.x = 330
	var box := _scroll(panel)
	box.add_child(_label("04 / 参数与播放", 17, MINT))
	detail_title = _label("", 22)
	box.add_child(detail_title)
	detail_text = _label("", 13, MUTED)
	detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(detail_text)
	box.add_child(_label("示例词语", 13, MUTED))
	word_input = LineEdit.new()
	word_input.text_changed.connect(func(_value): _parameter_changed())
	box.add_child(word_input)
	params_box = _column(box, 8)
	box.add_child(_label("可复制 / 插入的片段", 13, MUTED))
	snippet = TextEdit.new()
	snippet.editable = false
	snippet.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	snippet.custom_minimum_size.y = 100
	snippet.add_theme_font_size_override("font_size", 13)
	box.add_child(snippet)
	var snippet_tools := _row(box)
	_button(snippet_tools, "复制片段", func(): DisplayServer.clipboard_set(snippet.text); _status("当前效果片段已复制。"))
	_button(snippet_tools, "恢复默认", _reset_effect)
	_section(box, "打字节奏")
	_setting_number(box, "cps", "默认语速 · 字/秒", 1, 150, 1)
	_setting_number(box, "comma", "逗号停顿 · 秒", 0, 2, 0.05)
	_setting_number(box, "sentence", "句末停顿 · 秒", 0, 3, 0.05)
	_section(box, "字体与画布")
	var fonts := OptionButton.new()
	for font_name in ["默认黑体", "宋体", "楷体", "等宽"]:
		fonts.add_item(font_name)
	fonts.select(maxi(0, ["默认黑体", "宋体", "楷体", "等宽"].find(settings.font)))
	fonts.item_selected.connect(func(index): settings.font = fonts.get_item_text(index); _configure_preview())
	box.add_child(fonts)
	_setting_number(box, "font_size", "默认字号 · px", 14, 56, 1)
	_setting_number(box, "line_space", "额外行距 · px", 0, 40, 1)
	_setting_number(box, "outline", "全局描边 · px", 0, 8, 1)
	var background_row := _row(box)
	background_row.add_child(_label("画布颜色", 13, MUTED))
	var background_color := ColorPickerButton.new()
	background_color.color = Color(settings.background)
	background_color.custom_minimum_size = Vector2(100, 28)
	background_color.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	background_color.color_changed.connect(func(value): settings.background = "#" + value.to_html(); stage.add_theme_stylebox_override("panel", _style(value, 10)))
	background_row.add_child(background_color)
	_setting_number(box, "shadow_x", "阴影水平偏移 · px", -12, 12, 1)
	_setting_number(box, "shadow_y", "阴影垂直偏移 · px", -12, 12, 1)
	_setting_number(box, "shadow_size", "阴影轮廓宽度 · px", 0, 8, 1)
	var shadow_row := _row(box)
	shadow_row.add_child(_label("阴影颜色", 13, MUTED))
	var shadow_color := ColorPickerButton.new()
	shadow_color.color = Color(settings.shadow_color)
	shadow_color.custom_minimum_size = Vector2(100, 28)
	shadow_color.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shadow_color.color_changed.connect(func(value): settings.shadow_color = "#" + value.to_html(); _configure_preview())
	shadow_row.add_child(shadow_color)
	_section(box, "逐字音效")
	var sound := CheckButton.new()
	sound.text = "启用合成音效"
	sound.button_pressed = settings.sound
	sound.toggled.connect(func(value): settings.sound = value; _sync_settings(); voice.stop())
	box.add_child(sound)
	var tone := OptionButton.new()
	for tone_name in ["清澈 · 正弦", "温暖 · 谐波", "复古 · 方波", "神秘 · 调频"]:
		tone.add_item(tone_name)
	tone.select(int(settings.tone))
	tone.item_selected.connect(func(index): settings.tone = index; _sync_settings())
	box.add_child(tone)
	_setting_number(box, "pitch", "基础音高倍率", 0.3, 2.5, 0.05)
	_setting_number(box, "variation", "音高随机变化", 0, 0.4, 0.01)
	_setting_number(box, "volume", "音量 · dB", -40, -3, 1)
	_setting_number(box, "every", "每几个字播放一次", 1, 8, 1)
	_setting_number(box, "duration", "单音时长 · 秒", 0.02, 0.15, 0.005)
	_button(box, "试听当前音色", func(): voice.audition())
	_section(box, "编辑提示")
	var tips := _label("效果可以嵌套；先打开的标签最后关闭。\n\n[wait=0.8] 等待 0.8 秒\n[speed=12] 后续语速 12 字/秒\n[voice=0.7] 后续音高 ×0.7\n\nCtrl+Enter：重新播放\nCtrl+S：保存配置\n\n拖动参数实时生成示例。手动编辑时使用片段套用，避免覆盖对白。", 12, MUTED)
	tips.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(tips)

func _number_control(parent: Node, spec: Dictionary, value: float, action: Callable) -> void:
	var box := _column(parent, 3)
	var top := _row(box)
	var title := _label(str(spec.label), 13, MUTED)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var spin := SpinBox.new()
	spin.min_value = spec.min
	spin.max_value = spec.max
	spin.step = spec.step
	spin.value = value
	spin.custom_minimum_size.x = 88
	spin.add_theme_font_size_override("font_size", 13)
	top.add_child(spin)
	var slider := HSlider.new()
	slider.min_value = spec.min
	slider.max_value = spec.max
	slider.step = spec.step
	slider.value = value
	slider.custom_minimum_size.y = 18
	box.add_child(slider)
	slider.value_changed.connect(func(next): spin.set_value_no_signal(next); action.call(next))
	spin.value_changed.connect(func(next): slider.set_value_no_signal(next); action.call(next))

func _setting_number(parent: Node, key: String, title: String, low: float, high: float, step: float) -> void:
	_number_control(parent, Catalog.number(key, title, settings[key], low, high, step), settings[key], func(value):
		settings[key] = value
		_sync_settings()
		if key in ["font_size", "line_space", "outline", "shadow_x", "shadow_y", "shadow_size"]:
			_configure_preview()
		if key == "duration":
			voice.regenerate()
	)

func _filter_catalog() -> void:
	if not is_instance_valid(list):
		return
	list.clear()
	filtered.clear()
	for index in range(catalog.size()):
		var item: Dictionary = catalog[index]
		var haystack: String = str(item.title) + str(item.id) + str(item.description) + str(item.tag)
		if (_active_group == "全部" or item.group == _active_group) and (search.text.is_empty() or haystack.to_lower().contains(search.text.to_lower())):
			filtered.append(index)
			list.add_item("%s  /  %s" % [item.group, item.title])
			list.set_item_tooltip(list.item_count - 1, str(item.description))
			if index == current_index:
				list.select(list.item_count - 1)

func _values(item: Dictionary) -> Dictionary:
	if not parameter_values.has(item.id):
		parameter_values[item.id] = {}
	var values: Dictionary = parameter_values[item.id]
	for spec in item.params:
		if not values.has(spec.key):
			values[spec.key] = spec.default
	return values

func _select_effect(index: int) -> void:
	if not building and is_instance_valid(editor) and not editor.text.is_empty():
		drafts[catalog[current_index].id] = {"source": editor.text, "word": word_input.text, "manual": manual_mode}
	current_index = clampi(index, 0, catalog.size() - 1)
	var item: Dictionary = catalog[current_index]
	building = true
	detail_title.text = str(item.title)
	detail_text.text = str(item.description)
	word_input.text = str(item.word)
	for child in params_box.get_children():
		params_box.remove_child(child)
		child.queue_free()
	var values: Dictionary = _values(item)
	for spec in item.params:
		var key: String = spec.key
		match str(spec.kind):
			"number":
				_number_control(params_box, spec, float(values[key]), func(value): values[key] = value; _parameter_changed())
			"choice":
				params_box.add_child(_label(spec.label, 13, MUTED))
				var option := OptionButton.new()
				for candidate in spec.options:
					option.add_item(str(candidate))
				option.select(maxi(0, spec.options.find(str(values[key]))))
				option.item_selected.connect(func(next): values[key] = spec.options[next]; _parameter_changed())
				params_box.add_child(option)
			"color":
				var row := _row(params_box)
				row.add_child(_label(spec.label, 13, MUTED))
				var picker := ColorPickerButton.new()
				picker.color = Color.from_string(str(values[key]), MINT)
				picker.custom_minimum_size = Vector2(70, 28)
				picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				picker.color_changed.connect(func(next): values[key] = "#" + next.to_html(); _parameter_changed())
				row.add_child(picker)
	manual_mode = false
	if drafts.has(item.id):
		var draft: Dictionary = drafts[item.id]
		word_input.text = str(draft.get("word", item.word))
		manual_mode = bool(draft.get("manual", false))
		_set_editor(str(draft.get("source", Catalog.render_example(item, values, word_input.text))))
	else:
		_set_editor(Catalog.render_example(item, values, word_input.text))
	snippet.text = Catalog.render_tag(item, values, word_input.text)
	building = false
	debounce.stop()
	preview.set_source(editor.text)
	_replay()
	var visible_index: int = filtered.find(current_index)
	if visible_index >= 0:
		list.select(visible_index)
		_reveal_catalog_selection()
	_status("%s · 参数实时联动；选中文字可以组合多个效果。" % str(item.title))

func _reveal_catalog_selection() -> void:
	await get_tree().process_frame
	if is_instance_valid(list):
		list.ensure_current_is_visible()

func _parameter_changed() -> void:
	if building:
		return
	var item: Dictionary = catalog[current_index]
	snippet.text = Catalog.render_tag(item, _values(item), word_input.text)
	if not manual_mode:
		_set_editor(Catalog.render_example(item, _values(item), word_input.text))
		preview.set_source(editor.text)
		if item.group == "入场":
			_replay()
	else:
		_status("片段已更新。选中文字套用，或载入当前示例恢复参数联动。")

func _set_editor(value: String) -> void:
	var was_building: bool = building
	building = true
	editor.text = value
	building = was_building

func _editor_changed() -> void:
	if building:
		return
	manual_mode = true
	debounce.start()

func _apply_editor() -> void:
	voice.stop()
	preview.set_source(editor.text)
	_validate_source()

func _load_example() -> void:
	manual_mode = false
	_parameter_changed()
	_replay()
	_status("示例已载入，参数实时联动已恢复。")

func _wrap_selection() -> void:
	var item: Dictionary = catalog[current_index]
	var selected: String = editor.get_selected_text()
	if selected.is_empty():
		editor.insert_text_at_caret(snippet.text)
	else:
		# Existing BBCode in the selection is intentionally preserved for nesting.
		var substitution: Dictionary = _values(item).duplicate()
		substitution["word"] = selected
		editor.insert_text_at_caret(str(item.tag).format(substitution))
	editor.grab_focus()
	manual_mode = true
	debounce.stop()
	_apply_editor()

func _reset_effect() -> void:
	var id: String = catalog[current_index].id
	parameter_values.erase(id)
	drafts.erase(id)
	# Do not overwrite the cleared draft with the current editor on selection.
	building = true
	_select_effect(current_index)

func _configure_preview() -> void:
	if not is_instance_valid(preview):
		return
	var regular: Font = font_regular
	match str(settings.font):
		"宋体": regular = load("res://fonts/serif.tres")
		"楷体": regular = load("res://fonts/handwriting.tres")
		"等宽": regular = load("res://fonts/mono.tres")
	var bold := FontVariation.new()
	bold.base_font = regular
	bold.variation_embolden = 0.8
	var italic := FontVariation.new()
	italic.base_font = regular
	italic.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.2, 1), Vector2.ZERO)
	var bold_italic := FontVariation.new()
	bold_italic.base_font = regular
	bold_italic.variation_embolden = 0.8
	bold_italic.variation_transform = italic.variation_transform
	preview.add_theme_font_override("normal_font", regular)
	preview.add_theme_font_override("bold_font", bold)
	preview.add_theme_font_override("italics_font", italic)
	preview.add_theme_font_override("bold_italics_font", bold_italic)
	preview.add_theme_font_override("mono_font", load("res://fonts/mono.tres"))
	for key in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
		preview.add_theme_font_size_override(key, int(settings.font_size))
	preview.add_theme_constant_override("line_separation", int(settings.line_space))
	preview.add_theme_constant_override("outline_size", int(settings.outline))
	preview.add_theme_constant_override("shadow_offset_x", int(settings.shadow_x))
	preview.add_theme_constant_override("shadow_offset_y", int(settings.shadow_y))
	preview.add_theme_constant_override("shadow_outline_size", int(settings.shadow_size))
	preview.add_theme_color_override("font_shadow_color", Color(settings.shadow_color))
	preview.add_theme_color_override("font_outline_color", Color("090f19"))
	preview.add_theme_color_override("default_color", INK)

func _sync_settings() -> void:
	if is_instance_valid(preview):
		preview.characters_per_second = float(settings.cps)
		preview.punctuation_pause = float(settings.comma)
		preview.sentence_pause = float(settings.sentence)
	if is_instance_valid(voice):
		voice.enabled = bool(settings.sound)
		voice.tone = int(settings.tone)
		voice.pitch = float(settings.pitch)
		voice.variation = float(settings.variation)
		voice.volume_db = float(settings.volume)
		voice.every = int(settings.every)
		voice.duration = float(settings.duration)

func _replay() -> void:
	if is_instance_valid(debounce):
		debounce.stop()
	voice.stop()
	preview.set_source(editor.text, true)
	_validate_source()

func _pause() -> void:
	preview.set_paused(not preview.paused)
	voice.stop()

func _show_all() -> void:
	debounce.stop()
	if preview.source != editor.text:
		preview.set_source(editor.text)
	preview.set_paused(false)
	preview.show_all()
	voice.stop()

func _process(delta: float) -> void:
	if not is_instance_valid(preview) or not is_instance_valid(playback_info):
		return
	_elapsed_status += delta
	if _elapsed_status < 0.08:
		return
	_elapsed_status = 0.0
	var total: int = preview.get_total_character_count()
	var count: int = total if preview.visible_characters < 0 else preview.visible_characters
	progress.max_value = maxi(1, total)
	progress.value = count
	var state: String = "已暂停" if preview.paused else ("打字中" if preview.playing else "全文 / 动画中")
	playback_info.text = "%s  ·  %d / %d" % [state, count, total]
	pause_button.text = "▶ 继续" if preview.paused else "Ⅱ 暂停"

func _validate_source() -> void:
	var checker := RegEx.new()
	checker.compile("\\[(/?)([a-z_]+)([^\\]]*)\\]")
	var standard: Array = ["b", "i", "u", "s", "code", "char", "p", "br", "hr", "center", "left", "right", "fill", "indent", "url", "hint", "img", "font", "font_size", "dropcap", "color", "bgcolor", "fgcolor", "outline_size", "outline_color", "table", "cell", "ul", "ol", "lb", "rb", "wave", "shake", "tornado", "rainbow", "pulse", "fade", "wait", "speed", "voice", "lrm", "rlm", "lre", "rle", "lro", "rlo", "pdf", "alm", "lri", "rli", "fsi", "pdi", "zwj", "zwnj", "wj", "shy"]
	var singles: Array = ["char", "br", "hr", "lb", "rb", "wait", "speed", "voice", "lrm", "rlm", "lre", "rle", "lro", "rlo", "pdf", "alm", "lri", "rli", "fsi", "pdi", "zwj", "zwnj", "wj", "shy"]
	var stack: Array[String] = []
	for token in checker.search_all(editor.text):
		var tag: String = token.get_string(2)
		if tag not in standard and tag not in LivingRichText.TAGS:
			_status("未识别的标签 [%s]：会显示为文字。" % tag)
			return
		if tag in ["wait", "speed", "voice"]:
			var value_text: String = token.get_string(3).trim_prefix("=")
			var control_value := RegEx.new()
			control_value.compile("^[0-9]+(?:\\.[0-9]+)?$")
			if token.get_string(1) == "/" or not token.get_string(3).begins_with("=") or control_value.search(value_text) == null:
				_status("播放指令格式应为 [%s=非负数值]，无需结束标签。" % tag)
				return
		if tag in singles:
			continue
		if token.get_string(1) == "/":
			if stack.is_empty() or stack.back() != tag:
				_status("标签嵌套不匹配：[/%s]。先打开的标签应最后关闭。" % tag)
				return
			stack.pop_back()
		else:
			stack.append(tag)
	if not stack.is_empty():
		_status("未关闭的标签：[%s]。" % stack.back())
	else:
		_status("BBCode 已应用 · %d 个字符 · %s" % [preview.get_total_character_count(), "手动编辑模式" if manual_mode else "参数联动模式"])

func _status(message: String) -> void:
	if is_instance_valid(status):
		status.text = message

func _state() -> Dictionary:
	drafts[catalog[current_index].id] = {"source": editor.text, "word": word_input.text, "manual": manual_mode}
	return {"version": 1, "selected": catalog[current_index].id, "settings": settings, "parameters": parameter_values, "drafts": drafts}

func _save_state() -> void:
	var file := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_state(), "\t"))
		_status("配置已保存，下次打开会自动恢复。")
	else:
		_status("保存失败：%s" % error_string(FileAccess.get_open_error()))

func _load_state() -> void:
	if not FileAccess.file_exists(STATE_PATH):
		current_index = catalog.size() - 1
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(STATE_PATH))
	if data is Dictionary:
		_accept_state(data)

func _accept_state(data: Dictionary) -> bool:
	if data.get("version", 0) != 1 or not data.get("settings", {}) is Dictionary or not data.get("parameters", {}) is Dictionary or not data.get("drafts", {}) is Dictionary:
		return false
	# Import is data only. Keep known settings, constrain numbers, and ignore
	# malformed parameter/draft fields instead of letting UI creation crash.
	var bounds: Dictionary = {"cps": [1, 150], "comma": [0, 2], "sentence": [0, 3], "font_size": [14, 56], "line_space": [0, 40], "outline": [0, 8], "tone": [0, 3], "pitch": [0.3, 2.5], "variation": [0, 0.4], "volume": [-40, -3], "every": [1, 8], "duration": [0.02, 0.15], "shadow_x": [-12, 12], "shadow_y": [-12, 12], "shadow_size": [0, 8]}
	for key in settings:
		var value: Variant = data.settings.get(key, settings[key])
		if bounds.has(key) and (value is float or value is int):
			settings[key] = clampf(float(value), bounds[key][0], bounds[key][1])
		elif key in ["background", "shadow_color"] and value is String and Color.html_is_valid(value):
			settings[key] = value
		elif key == "sound" and value is bool:
			settings[key] = value
		elif key == "font" and value in ["默认黑体", "宋体", "楷体", "等宽"]:
			settings[key] = value
	parameter_values.clear()
	drafts.clear()
	for item in catalog:
		var candidate: Variant = data.parameters.get(item.id, {})
		var values: Dictionary = _values(item)
		if candidate is Dictionary:
			for spec in item.params:
				var value: Variant = candidate.get(spec.key, spec.default)
				if spec.kind == "number" and (value is float or value is int):
					values[spec.key] = clampf(float(value), spec.min, spec.max)
				elif spec.kind == "choice" and str(value) in spec.options:
					values[spec.key] = str(value)
				elif spec.kind == "color" and value is String and Color.html_is_valid(value):
					values[spec.key] = value
		var draft: Variant = data.drafts.get(item.id, {})
		if draft is Dictionary and draft.get("source", null) is String:
			drafts[item.id] = {"source": str(draft.source).left(50000), "word": str(draft.get("word", item.word)).left(2000), "manual": bool(draft.get("manual", false))}
		if item.id == data.get("selected", "mixed"):
			current_index = catalog.find(item)
	return true

func _build_dialogs() -> void:
	export_dialog = FileDialog.new()
	export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.filters = PackedStringArray(["*.json ; 富文本实验室配置"])
	export_dialog.current_file = "rich-text-lab.json"
	export_dialog.file_selected.connect(func(path):
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(_state(), "\t"))
			_status("已导出：" + path)
		else:
			_status("导出失败：" + error_string(FileAccess.get_open_error()))
	)
	add_child(export_dialog)
	import_dialog = FileDialog.new()
	import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_dialog.filters = export_dialog.filters
	import_dialog.file_selected.connect(_import_file)
	add_child(import_dialog)

func _import_file(path: String) -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or not _accept_state(data):
		_status("导入失败：请选择实验室导出的版本 1 JSON 配置。")
		return
	# Rebuild the controls so all restored sliders/colors match the imported data.
	building = true
	debounce.stop()
	voice.stop()
	for child in get_children():
		if child != voice and child != debounce and child != export_dialog and child != import_dialog:
			remove_child(child)
			child.queue_free()
	_build_ui()
	_configure_preview()
	_sync_settings()
	voice.regenerate()
	building = false
	_filter_catalog()
	_select_effect(current_index)
	_status("配置已导入：" + path)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and event.keycode == KEY_ENTER:
			_replay()
			get_viewport().set_input_as_handled()
		elif event.ctrl_pressed and event.keycode == KEY_S:
			_save_state()
			get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_state()
		voice.stop()
		_close_later()

func _close_later() -> void:
	await get_tree().create_timer(0.08).timeout
	get_tree().quit()

func _capture_later() -> void:
	await get_tree().create_timer(2.0).timeout
	_show_all()
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/laboratory.png")
	print("LAB_CAPTURE_SAVED")
	get_tree().quit()
