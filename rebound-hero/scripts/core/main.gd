extends Node

var db := ContentDB.new()
var model: CombatModel
var shop: ShopService
var arena: Node2D
var ui: CanvasLayer
var sound: Node
var saves: SaveStore
var paused := false
var capture_frames := 0
var capture_path := ""
var capture_level := 0

func _ready() -> void:
	if not db.load_all():
		push_error("\n".join(db.errors))
		var error := Label.new()
		error.text = "配置加载失败\n" + "\n".join(db.errors)
		add_child(error)
		return
	var font := SystemFont.new()
	_configure_inputs()
	font.font_names = PackedStringArray(db.visuals.font_names)
	font.allow_system_fallback = true
	model = CombatModel.new(db)
	saves = SaveStore.new(str(db.rules.save_path))
	saves.load_state()
	shop = ShopService.new(model)
	sound = load(str(db.visuals.sound_scene)).instantiate()
	add_child(sound)
	sound.setup(model, db.audio)
	sound.muted = bool(saves.state.muted)
	arena = load(str(db.visuals.arena_scene)).instantiate()
	add_child(arena)
	arena.setup(model, font)
	ui = load(str(db.visuals.ui_scene)).instantiate()
	add_child(ui)
	ui.setup(model, shop, font)
	ui.start_requested.connect(_start)
	ui.next_requested.connect(func(): model.next_level())
	ui.pause_requested.connect(_pause)
	model.state_changed.connect(_state_changed)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="): capture_path = argument.trim_prefix("--capture=")
		if argument.begins_with("--seed="): db.rules.seed = int(argument.trim_prefix("--seed="))
		if argument.begins_with("--capture-level="): capture_level = clampi(int(argument.trim_prefix("--capture-level=")) - 1, 0, db.levels.size() - 1)
	if not capture_path.is_empty():
		_start()
		if capture_level > 0:
			model.level_index = capture_level
			model.load_level()
		if OS.get_cmdline_user_args().has("--capture-shop"):
			model.summary = "清场奖励 +33 金币 · 精准 +10 / 无伤 +8"
			model.player.gold = int(db.visuals.capture_gold)
			model.set_state("SHOP")
		if OS.get_cmdline_user_args().has("--capture-title"): model.set_state("TITLE")

func _start() -> void:
	paused = false
	ui.paused = false
	model.start(int(db.rules.seed))

func _state_changed(value: String) -> void:
	if value == "SHOP": shop.open()
	if value == "VICTORY" or value == "DEFEAT": saves.record(model)

func _pause() -> void:
	if model == null: return
	paused = not paused
	ui.set_paused(paused)

func _process(delta: float) -> void:
	if model == null: return
	if not paused:
		var multiplier := float(db.rules.simulation.speed_multiplier) if Input.is_action_pressed("fast_forward") else 1.0
		# Tick separately so clamping large frame deltas does not cancel fast-forward.
		var whole := floori(multiplier)
		for _i in range(whole): model.tick(delta)
		if multiplier > whole: model.tick(delta * (multiplier - whole))
		arena.refresh(delta)
	ui.refresh()
	if not capture_path.is_empty():
		capture_frames += 1
		if capture_frames == 8:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(capture_path)
			get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if model == null: return
	if event is InputEventKey and event.echo: return
	if event.is_action_pressed("pause"): _pause(); return
	if event.is_action_pressed("mute"):
		sound.muted = not sound.muted
		saves.state.muted = sound.muted
		saves.write()
		return
	if paused: return
	for binding in db.rules.weapon_actions:
		if event.is_action_pressed(str(binding.action)): model.select_weapon(int(binding.slot))
	if event is InputEventMouseMotion:
		model.set_aim(get_viewport().get_mouse_position())
	if model.inventory.is_empty(): return
	if event.is_action_pressed("fire"):
		model.set_aim(get_viewport().get_mouse_position())
		model.fire()
	if event.is_action_pressed("cycle_previous"): model.select_weapon(posmod(model.active_weapon - 1, model.inventory.size()))
	if event.is_action_pressed("cycle_next"): model.select_weapon(posmod(model.active_weapon + 1, model.inventory.size()))

func _configure_inputs() -> void:
	for action in db.rules.inputs:
		if not InputMap.has_action(action): InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var binding: Dictionary = db.rules.inputs[action]
		if binding.has("key"):
			var event := InputEventKey.new()
			event.physical_keycode = OS.find_keycode_from_string(str(binding.key))
			InputMap.action_add_event(action, event)
		if binding.has("mouse"):
			var event := InputEventMouseButton.new()
			event.button_index = int(binding.mouse)
			InputMap.action_add_event(action, event)
