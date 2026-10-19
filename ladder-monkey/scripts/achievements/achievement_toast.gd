class_name AchievementToast
extends Control
signal toast_started(award_id: int)
signal toast_finished(award_id: int)
var profile: AchievementProfile
var pending: Array[Dictionary] = []
var known_ids: Dictionary = {}
var displayed_ids: Array[int] = []
var finished_ids: Array[int] = []
var active: bool = false
var active_id: int = -1
var panel: PanelContainer
var title_label: Label
var name_label: Label
var tween: Tween
var panel_size := Vector2(254, 56)
var shown_position := Vector2.ZERO
var hidden_position := Vector2.ZERO

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	panel.name = "AchievementToast"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = panel_size
	panel.size = panel_size
	var style := StyleBoxFlat.new()
	style.bg_color = Color("282d2b")
	style.border_color = Color("d6ae63")
	style.set_border_width_all(2)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	style.shadow_color = Color(0.06, 0.08, 0.07, 0.8)
	style.shadow_size = 3
	style.shadow_offset = Vector2(2, 3)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var icon := TrophyPixelIcon.new()
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	row.add_child(text)
	var font: FontFile = preload("res://assets/fonts/ZCOOLQingKeHuangYou-Regular.ttf").duplicate()
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.hinting = TextServer.HINTING_NORMAL
	title_label = Label.new()
	title_label.text = "成就达成！"
	title_label.add_theme_font_override("font", font)
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", Color("ffe4a1"))
	text.add_child(title_label)
	name_label = Label.new()
	name_label.add_theme_font_override("font", font)
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color("d9dfcd"))
	text.add_child(name_label)
	resized.connect(update_layout)
	update_layout()
	panel.hide()

func update_layout() -> void:
	var view_size := get_viewport_rect().size
	shown_position = Vector2(roundf((view_size.x - panel_size.x) * 0.5), view_size.y - panel_size.y - profile.toast_bottom_margin)
	hidden_position = Vector2(shown_position.x, view_size.y + 8)
	if not active:
		panel.position = hidden_position
	panel.pivot_offset = panel_size * 0.5

func enqueue(award_id: int, award_name: String, height: float) -> void:
	if known_ids.has(award_id):
		return
	known_ids[award_id] = true
	pending.append({"id": award_id, "name": award_name, "height": height})
	if not active:
		show_next()

func show_next() -> void:
	if active or pending.is_empty():
		return
	var award: Dictionary = pending.pop_front()
	active = true
	active_id = award.id
	displayed_ids.append(active_id)
	name_label.text = "%s  /  %.1f m" % [award.name, award.height]
	panel.position = hidden_position
	panel.scale = Vector2.ONE * 0.94
	panel.modulate.a = 0.0
	panel.show()
	toast_started.emit(active_id)
	tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "position", shown_position, profile.toast_enter_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "scale", Vector2.ONE, profile.toast_enter_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "modulate:a", 1.0, profile.toast_enter_duration)
	tween.chain().tween_interval(profile.toast_hold_duration)
	tween.chain().tween_property(panel, "position", hidden_position, profile.toast_exit_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(panel, "modulate:a", 0.0, profile.toast_exit_duration)
	tween.parallel().tween_property(panel, "scale", Vector2.ONE * 0.97, profile.toast_exit_duration)
	tween.chain().tween_callback(finish_current)

func finish_current() -> void:
	var previous := active_id
	finished_ids.append(previous)
	active = false
	active_id = -1
	panel.hide()
	toast_finished.emit(previous)
	show_next.call_deferred()
