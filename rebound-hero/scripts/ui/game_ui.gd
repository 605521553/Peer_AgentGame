extends CanvasLayer

signal start_requested
signal next_requested
signal pause_requested

var model: CombatModel
var shop: ShopService
var config: Dictionary
var font: Font
var root: Control
var hp_label: Label
var hp_bar: ProgressBar
var gold_label: Label
var stage_label: Label
var phase_label: Label
var detail_label: Label
var weapon_row: HBoxContainer
var item_label: Label
var overlay: Control
var modal: Control
var paused := false
var dirty := true
var _display_state := ""
var _shop_dirty := true

func setup(combat: CombatModel, service: ShopService, text_font: Font) -> void:
	model = combat; shop = service; config = model.db.visuals; font = text_font
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = int(config.font_size)
	theme.set_color("font_color", "Label", color("text"))
	theme.set_color("font_color", "Button", color("text"))
	theme.set_color("font_hover_color", "Button", color("accent"))
	theme.set_color("font_disabled_color", "Button", color("muted"))
	theme.set_stylebox("normal", "Button", box("panel", "panel_border", 8))
	theme.set_stylebox("hover", "Button", box("panel_border", "accent", 8))
	theme.set_stylebox("pressed", "Button", box("panel_border", "accent", 8))
	theme.set_stylebox("disabled", "Button", box("background", "panel_border", 8))
	root.theme = theme
	label(root, "REBOUND / HERO", Vector2(48, 19), Vector2(320, 35), 28, "accent")
	stage_label = label(root, "弹射策略 · 随机构筑", Vector2(49, 58), Vector2(530, 27), 15, "muted")
	hp_label = label(root, "生命", Vector2(730, 23), Vector2(240, 27), 16)
	hp_bar = ProgressBar.new()
	hp_bar.position = Vector2(730, 59); hp_bar.size = Vector2(238, 7)
	hp_bar.show_percentage = false
	var bar_background := box("panel_border", "panel_border", 3)
	var bar_fill := box("accent", "accent", 3)
	for style in [bar_background, bar_fill]:
		style.content_margin_top = 0; style.content_margin_bottom = 0
	hp_bar.add_theme_stylebox_override("background", bar_background)
	hp_bar.add_theme_stylebox_override("fill", bar_fill)
	root.add_child(hp_bar)
	gold_label = label(root, "", Vector2(998, 24), Vector2(170, 38), 24, "gold")
	var pause_button := button(root, "Ⅱ", _pause)
	pause_button.position = Vector2(1182, 26); pause_button.size = Vector2(50, 38)
	pause_button.custom_minimum_size = Vector2(50, 38)
	pause_button.size = Vector2(50, 38)
	phase_label = label(root, "", Vector2(49, 87), Vector2(440, 24), 15, "accent")
	detail_label = label(root, "", Vector2(510, 87), Vector2(722, 24), 14, "muted")
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weapon_row = HBoxContainer.new()
	weapon_row.position = Vector2(48, 660); weapon_row.size = Vector2(580, 40)
	weapon_row.add_theme_constant_override("separation", 12)
	root.add_child(weapon_row)
	item_label = label(root, "", Vector2(664, 664), Vector2(568, 36), 14, "muted")
	item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	model.changed.connect(func(): dirty = true)
	model.state_changed.connect(func(_state): _shop_dirty = true)

func color(key: String) -> Color:
	return Color(str(config[key]))

func box(fill: String, edge: String, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color(fill); style.border_color = color(edge)
	style.set_border_width_all(1); style.set_corner_radius_all(radius)
	style.content_margin_left = 16; style.content_margin_right = 16
	style.content_margin_top = 8; style.content_margin_bottom = 8
	return style

func label(parent: Node, text: String, position_value: Vector2, size_value: Vector2, font_size: int, tint: String = "text") -> Label:
	var node := Label.new()
	node.text = text; node.position = position_value; node.size = size_value
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color(tint))
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.clip_text = true
	parent.add_child(node)
	return node

func button(parent: Node, text: String, action: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size = Vector2(100, 40)
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.pressed.connect(action)
	parent.add_child(node)
	return node

func refresh() -> void:
	if not dirty: return
	dirty = false
	if model.player.is_empty():
		hp_label.text = "生命 %d / %d" % [db_player_hp(), db_player_hp()]; hp_bar.max_value = db_player_hp(); hp_bar.value = db_player_hp(); gold_label.text = "新局准备"
	else:
		hp_label.text = "生命  %d / %d" % [ceili(model.player.hp), ceili(model.player.max_hp)]
		hp_bar.max_value = model.player.max_hp; hp_bar.value = model.player.hp
		gold_label.text = "%d  金币" % int(model.player.gold)
		var level: Dictionary = model.db.levels[model.level_index]
		stage_label.text = "%02d / %02d   ·   %s" % [model.level_index + 1, model.db.levels.size(), level.name]
		phase_label.text = phase_text()
		var reflections := int(model.db.rules.preview.base_reflections) + int(model.player.stats.preview_reflections)
		detail_label.text = "预测 %d 次反弹  ·  敌人 %d  ·  本关 %d 发  ·  按住空格快进" % [reflections, model.living_enemies(), model.shots]
		_rebuild_weapons()
		var names: PackedStringArray = []
		var descriptions: PackedStringArray = []
		for id in model.collected:
			names.append("%s×%d" % [model.db.items[id].name, int(model.collected[id])])
			descriptions.append("%s ×%d\n%s" % [model.db.items[id].name, int(model.collected[id]), model.db.items[id].description])
		item_label.text = "鼠标瞄准 · 左键发射 · 1/2 切枪" if names.is_empty() else "构筑 %d 件 · 悬停查看" % names.size()
		item_label.tooltip_text = "\n\n".join(descriptions)
		item_label.mouse_filter = Control.MOUSE_FILTER_STOP
	if _display_state != model.state or (model.state == "SHOP" and _shop_dirty):
		_display_state = model.state; _shop_dirty = false
		_build_overlay()

func phase_text() -> String:
	match model.state:
		"AIMING": return "选择角度  /  " + str(model.db.levels[model.level_index].subtitle)
		"PLAYER_RESOLVING": return "弹道结算中"
		"ENEMY_WARNING": return "敌人即将反击 · 红线显示攻击路径"
		"ENEMY_RESOLVING": return "敌方弹丸结算中"
		"ROUND_END": return "下一回合准备"
		"SHOP": return "清场完成 · 构筑升级"
		_: return ""

func _rebuild_weapons() -> void:
	for child in weapon_row.get_children(): child.queue_free()
	for i in range(model.inventory.size()):
		var instance: Dictionary = model.inventory[i]
		var definition: Dictionary = model.db.weapons[instance.id]
		var node := button(weapon_row, "%d  %s  +%d" % [i + 1, definition.name, instance.upgrade], func(): model.select_weapon(i))
		node.custom_minimum_size = Vector2(240, 40)
		node.tooltip_text = str(model.db.rules.shop.quality_names[instance.quality]) + "\n" + model.weapon_description(instance)
		if i == model.active_weapon: node.add_theme_color_override("font_color", color("accent"))
		node.disabled = model.state != "AIMING"

func _clear_overlay() -> void:
	if is_instance_valid(overlay):
		overlay.visible = false
		overlay.queue_free()
	if is_instance_valid(modal): modal.queue_free()
	overlay = null; modal = null

func _overlay_panel(position_value: Vector2, size_value: Vector2) -> Panel:
	_clear_overlay()
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.035, 0.06, 0.86)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	var panel := Panel.new()
	panel.position = position_value; panel.size = size_value
	panel.add_theme_stylebox_override("panel", box("panel", "panel_border", 14))
	overlay.add_child(panel)
	return panel

func _build_overlay() -> void:
	_clear_overlay()
	match model.state:
		"TITLE": _title()
		"SHOP": _shop()
		"VICTORY", "DEFEAT": _result()
		"ERROR":
			var panel := _overlay_panel(Vector2(250, 220), Vector2(780, 300))
			label(panel, "配置需要修正", Vector2(34, 28), Vector2(700, 40), 28, "danger")
			var message := label(panel, model.error_message, Vector2(34, 90), Vector2(700, 110), 18)
			message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			message.size = Vector2(700, 110)
	if paused: _pause_overlay()

func _title() -> void:
	var panel := _overlay_panel(Vector2(230, 175), Vector2(820, 390))
	label(panel, "01 / 计算角度，改变战局", Vector2(38, 30), Vector2(750, 30), 16, "accent")
	label(panel, "反弹行者", Vector2(38, 78), Vector2(740, 62), 48)
	label(panel, "每一次反射，都可能成为致命一击。", Vector2(40, 146), Vector2(720, 32), 21, "muted")
	label(panel, "鼠标瞄准 → 左键射击 → 敌人反击 → 商店构筑", Vector2(40, 213), Vector2(735, 30), 18)
	label(panel, "5 关挑战 / 三种武器 / 预测成长 / 镜盾 Boss", Vector2(40, 252), Vector2(730, 30), 16, "muted")
	var start_button := button(panel, "开始新局   →", func(): start_requested.emit())
	start_button.position = Vector2(40, 312); start_button.size = Vector2(230, 48)
	label(panel, "生命跨关保留 · 死亡后重新构筑", Vector2(350, 322), Vector2(425, 28), 15, "muted")

func _shop() -> void:
	var panel := _overlay_panel(Vector2(70, 122), Vector2(1140, 510))
	label(panel, "补给站  /  %02d" % (model.level_index + 1), Vector2(28, 18), Vector2(720, 44), int(config.title_size))
	label(panel, model.summary, Vector2(30, 65), Vector2(1075, 26), 15, "accent")
	var card_width := 256.0
	for i in range(shop.offers.size()):
		var offer: Dictionary = shop.offers[i]
		var card := Panel.new()
		card.position = Vector2(28 + i * 275, 107); card.size = Vector2(card_width, 247)
		card.add_theme_stylebox_override("panel", box("background", "panel_border", 8))
		panel.add_child(card)
		var quality_color := Color(str(config.quality_colors[offer.quality]))
		var quality := label(card, "%s  /  %s" % [model.db.rules.shop.quality_names[offer.quality], "武器" if offer.type == "weapon" else "补给" if offer.type == "heal" else "道具"], Vector2(17, 13), Vector2(222, 26), 14)
		quality.add_theme_color_override("font_color", quality_color)
		var icon := Node2D.new()
		card.add_child(icon)
		var actor: Node2D = load(str(config.renderer_scene)).instantiate()
		icon.add_child(actor); actor.configure(config)
		actor.present({"position": Vector2(34, 70), "radius": 16, "visual": offer.visual, "visible": true})
		label(card, offer.name, Vector2(61, 49), Vector2(189, 40), 20)
		var description := label(card, offer.description, Vector2(17, 100), Vector2(220, 86), 15, "muted")
		card.tooltip_text = offer.description
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.size = Vector2(220, 86)
		var buy_button := button(card, "已售出" if offer.sold else "购买   %d 金币" % int(offer.price), func(): _buy(i))
		buy_button.position = Vector2(16, 194); buy_button.size = Vector2(224, 38)
		var available := int(model.player.gold)
		if offer.type == "weapon" and model.inventory.size() >= int(model.player.max_weapons):
			var refund := 0
			for weapon_index in range(model.inventory.size()): refund = maxi(refund, shop.sell_value(weapon_index))
			available += refund
		buy_button.disabled = offer.sold or available < int(offer.price) or (offer.type == "heal" and model.player.hp >= model.player.max_hp)
	for i in range(model.inventory.size()):
		var weapon: Dictionary = model.inventory[i]
		var offset := i * 540
		label(panel, "%s +%d" % [model.db.weapons[weapon.id].name, weapon.upgrade], Vector2(30 + offset, 371), Vector2(222, 40), 17)
		var upgrade_button := button(panel, "强化 %d" % shop.upgrade_price(i), func(): shop.upgrade(i); _request_shop())
		upgrade_button.position = Vector2(251 + offset, 371); upgrade_button.size = Vector2(130, 40)
		upgrade_button.disabled = int(weapon.upgrade) >= int(model.db.rules.shop.max_upgrade) or model.player.gold < shop.upgrade_price(i)
		var sell_button := button(panel, "出售 +%d" % shop.sell_value(i), func(): shop.sell(i); _request_shop())
		sell_button.position = Vector2(393 + offset, 371); sell_button.size = Vector2(120, 40)
		sell_button.disabled = model.inventory.size() <= 1
	label(panel, shop.message, Vector2(31, 428), Vector2(590, 46), 15, "gold")
	var refresh_button := button(panel, "刷新   %d 金币" % shop.refresh_price(), func(): shop.refresh(); _request_shop())
	refresh_button.position = Vector2(670, 440); refresh_button.size = Vector2(189, 44)
	refresh_button.disabled = model.player.gold < shop.refresh_price()
	var next_button := button(panel, "进入下一关   →", func(): next_requested.emit())
	next_button.position = Vector2(887, 440); next_button.size = Vector2(225, 44)

func _request_shop() -> void:
	dirty = true; _shop_dirty = true

func db_player_hp() -> int:
	return int(model.db.player.hp)

func _buy(index: int) -> void:
	var offer: Dictionary = shop.offers[index]
	if offer.type == "weapon" and model.inventory.size() >= int(model.player.max_weapons):
		_replacement(index)
		return
	shop.buy(index)
	_request_shop()

func _replacement(index: int) -> void:
	if is_instance_valid(modal): modal.queue_free()
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(modal)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.65)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); modal.add_child(shade)
	var panel := Panel.new()
	panel.position = Vector2(340, 232); panel.size = Vector2(600, 256)
	panel.add_theme_stylebox_override("panel", box("panel", "accent", 12)); modal.add_child(panel)
	label(panel, "选择要替换的武器", Vector2(25, 20), Vector2(550, 40), 26)
	label(panel, "旧武器自动折价返还；取消不会消耗金币。", Vector2(25, 70), Vector2(550, 28), 15, "muted")
	for i in range(model.inventory.size()):
		var instance: Dictionary = model.inventory[i]
		var choose := button(panel, "%s  返还 %d" % [model.db.weapons[instance.id].name, shop.sell_value(i)], func(): shop.buy(index, i); _request_shop())
		choose.position = Vector2(25 + 282 * i, 117); choose.size = Vector2(269, 44)
		choose.disabled = int(model.player.gold) + shop.sell_value(i) < int(shop.offers[index].price)
	var cancel := button(panel, "取消", func(): modal.queue_free(); modal = null)
	cancel.position = Vector2(25, 187); cancel.size = Vector2(550, 42)

func _result() -> void:
	var victory := model.state == "VICTORY"
	var panel := _overlay_panel(Vector2(280, 162), Vector2(720, 406))
	label(panel, "挑战完成" if victory else "信号中断", Vector2(36, 26), Vector2(650, 56), 38, "accent" if victory else "danger")
	label(panel, "你击碎了折光核心。" if victory else "保留这次经验，重新选择你的路线。", Vector2(38, 90), Vector2(640, 32), 18, "muted")
	label(panel, "到达关卡    %d / %d\n射击次数    %d\n消灭敌人    %d" % [model.level_index + 1, model.db.levels.size(), model.total_shots, model.kills], Vector2(38, 150), Vector2(300, 120), 19)
	label(panel, "总伤害        %d\n单弹最高      %d\n单次发射      %d" % [roundi(model.total_damage), roundi(model.highest_bullet), roundi(model.highest_shot)], Vector2(368, 150), Vector2(320, 120), 19)
	label(panel, "复现种子  %d" % model.seed_value, Vector2(38, 280), Vector2(580, 28), 14, "muted")
	var restart := button(panel, "再来一局   →", func(): start_requested.emit())
	restart.position = Vector2(38, 332); restart.size = Vector2(644, 46)

func _pause() -> void:
	if model.state == "TITLE" or model.state == "VICTORY" or model.state == "DEFEAT": return
	pause_requested.emit()

func set_paused(value: bool) -> void:
	paused = value
	_build_overlay()

func _pause_overlay() -> void:
	var panel := _overlay_panel(Vector2(380, 250), Vector2(520, 218))
	label(panel, "暂停", Vector2(30, 28), Vector2(460, 54), 34)
	label(panel, "Esc 继续 · 空格加速弹道结算", Vector2(30, 88), Vector2(460, 28), 17, "muted")
	var resume := button(panel, "继续战斗", func(): pause_requested.emit())
	resume.position = Vector2(30, 144); resume.size = Vector2(460, 44)
