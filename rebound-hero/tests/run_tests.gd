extends SceneTree

var db := ContentDB.new()
var failures: PackedStringArray = []
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func run() -> void:
	check(db.load_all(), "Content load: " + " / ".join(db.errors))
	if not db.errors.is_empty(): quit(1); return
	geometry_tests()
	validation_tests()
	shop_tests()
	combat_tests()
	persistence_tests()
	var count := 20
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seeds="): count = int(argument.trim_prefix("--seeds="))
	generation_tests(count)
	autoplay_test()
	await ui_tests()
	print("RESULT: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func validation_tests() -> void:
	var invalid := ContentDB.new()
	invalid._shape({"hp": "wrong"}, {"type": "object", "fields": {"hp": {"type": "number"}}}, "player")
	check(not invalid.errors.is_empty(), "schema rejects wrong numeric type")
	invalid.errors.clear()
	invalid._index([{"id": "same"}, {"id": "same"}], {}, "fixture")
	check(not invalid.errors.is_empty(), "duplicate IDs rejected")
	var file := FileAccess.open("user://malformed_fixture.json", FileAccess.WRITE)
	file.store_string("{ broken"); file.close()
	invalid._read("user://malformed_fixture.json")
	check(invalid.errors.size() > 1, "malformed JSON reports parse failure")
	DirAccess.remove_absolute("user://malformed_fixture.json")
	var candidate := ContentDB.new()
	candidate.load_all()
	candidate.levels[0].enemies[0].type = "deleted_enemy"
	candidate._validate()
	check(not candidate.errors.is_empty(), "deleted referenced enemy rejected")

func persistence_tests() -> void:
	var store := SaveStore.new("user://test_profile.json")
	store.state.muted = true
	store.write()
	var other := SaveStore.new("user://test_profile.json")
	other.load_state()
	check(other.state.muted, "settings round trip")
	store.state.muted = false
	store.write()
	other.load_state()
	check(not other.state.muted, "atomic save replaces existing file")
	var file := FileAccess.open("user://test_profile.json", FileAccess.WRITE)
	file.store_string("invalid"); file.close()
	var fallback := SaveStore.new("user://test_profile.json")
	fallback.load_state()
	check(fallback.state.runs == 0, "corrupt save falls back safely")
	DirAccess.remove_absolute("user://test_profile.json")

func ui_tests() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var ui: CanvasLayer = main.ui
	check(main.model.state == "TITLE", "main scene opens title")
	var start_button: Button = _find_button(ui.root, "开始新局   →")
	check(start_button != null, "start button rendered")
	if start_button != null: start_button.pressed.emit()
	await process_frame
	await process_frame
	check(main.model.state == "AIMING" and ui.overlay == null, "start UI signal opens arena")
	main._pause()
	var before: String = main.model.state
	await process_frame
	check(main.paused and ui.overlay != null and main.model.state == before, "pause UI works without advancing combat")
	main._pause()
	main.model.summary = "UI fixture"
	main.model.player.gold = 200
	main.model.set_state("SHOP")
	await process_frame
	await process_frame
	var offer: Dictionary = main.shop.offers[2]
	ui._buy(2)
	await process_frame
	check(offer.sold and main.model.collected.has(offer.id), "shop UI purchase updates inventory")
	ui.next_requested.emit()
	await process_frame
	check(main.model.level_index == 1 and main.model.state == "AIMING", "next-stage button dispatch")
	var event := InputEventAction.new()
	event.action = "fire"; event.pressed = true
	main._unhandled_input(event)
	check(main.model.state == "PLAYER_RESOLVING", "configured input action fires weapon")
	main.queue_free()
	await process_frame
	# Allow the audio mixer to release a playback started by the input test.
	await create_timer(0.1).timeout

func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null: return found
	return null

func geometry_tests() -> void:
	var bounds := Rect2(0, 0, 100, 100)
	var player := {"pos": Vector2(50, 90), "radius": 5}
	var hit := TrajectorySolver.cast(Vector2(50, 50), Vector2.RIGHT, 100, bounds, [], [], player, false)
	check(hit.kind == "wall" and hit.point.is_equal_approx(Vector2(100, 50)), "wall exact hit")
	check(Vector2.RIGHT.bounce(hit.normal).is_equal_approx(Vector2.LEFT), "wall reflection")
	var circle := {"shape": "circle", "pos": Vector2(50, 50), "radius": 10}
	hit = TrajectorySolver.cast(Vector2(20, 50), Vector2.RIGHT, 80, bounds, [circle], [], player, false)
	check(hit.point.is_equal_approx(Vector2(40, 50)), "circle surface")
	var triangle := {"shape": "triangle", "pos": Vector2(50, 50), "size": [20, 20], "rotation": 0}
	triangle.points = TrajectorySolver.polygon(triangle)
	hit = TrajectorySolver.cast(Vector2(25, 50), Vector2.RIGHT, 80, bounds, [triangle], [], player, false)
	check(hit.kind == "wall" and not hit.normal.is_equal_approx(Vector2.LEFT), "triangle slanted normal")
	var guard := {"uid": 1, "pos": Vector2(50, 50), "radius": 10, "hp": 20, "behaviors": [{"type": "shield", "arc_degrees": 120, "facing_degrees": 90}]}
	check(TrajectorySolver.shielded(guard, Vector2(50, 60)), "shield front")
	check(not TrajectorySolver.shielded(guard, Vector2(50, 40)), "shield back")
	var path := TrajectorySolver.trace(Vector2(50, 90), Vector2.UP, 200, 4, bounds, [], [guard], player, {"shield_break": 0}, 0.04)
	check(path.kind == "player", "reflected bullet becomes hostile in preview")
	path = TrajectorySolver.trace(Vector2(50, 90), Vector2.UP, 200, 4, bounds, [], [guard], player, {"shield_break": 1}, 0.04)
	check(path.kind == "enemy", "shield break preview stops at enemy")

func shop_tests() -> void:
	var model := CombatModel.new(db)
	model.start(12)
	check(model.state == "AIMING", "initial level generated")
	model.set_state("SHOP")
	var shop := ShopService.new(model)
	shop.open()
	check(shop.offers.size() == int(db.rules.shop.slots), "shop slot count")
	model.player.gold = 0
	check(not shop.buy(1) and model.player.gold == 0, "unaffordable purchase atomic")
	model.player.gold = 200
	model.player.hp -= 30
	var gold_before := int(model.player.gold)
	check(shop.buy(0), "heal buy")
	check(model.player.hp == model.player.max_hp and model.player.gold == gold_before - int(shop.offers[0].price), "heal transaction exact")
	check(not shop.buy(0), "sold item can't be bought twice")
	check(shop.buy(1), "second weapon")
	shop.offers[1].sold = false
	gold_before = model.player.gold
	check(not shop.buy(1) and model.player.gold == gold_before, "replacement requires valid slot before debit")
	check(shop.buy(1, 0), "replacement transaction")
	shop.offers[1].sold = false
	model.player.gold = int(shop.offers[1].price) - shop.sell_value(0)
	check(shop.buy(1, 0) and model.player.gold == 0, "replacement refund contributes to affordability")
	var other := CombatModel.new(db)
	other.start(12)
	check(other.inventory[0].upgrade == 0, "resource instance isolation")
	model.player.gold = 200
	check(shop.upgrade(0) and model.inventory[0].upgrade == 1, "upgrade")
	check(shop.sell(1), "sell spare weapon")
	check(not shop.sell(0), "cannot sell last weapon")
	var refresh_cost := shop.refresh_price()
	check(shop.refresh() and shop.refresh_price() == refresh_cost + int(db.rules.shop.refresh_increment), "refresh escalation")
	model.start(12)
	check(model.inventory.size() == db.player.starting_weapons.size() and model.collected.is_empty() and model.player.gold == db.player.gold, "restart resets run state")

func combat_tests() -> void:
	var model := CombatModel.new(db)
	model.start(42)
	var hp_before: float = model.player.hp
	for _i in range(120): model.tick(1.0 / 60.0)
	check(model.player.hp == hp_before and model.state == "AIMING", "no attack during aim")
	model.aim = Vector2.UP
	check(model.fire() and not model.fire(), "shot input gate")
	settle(model)
	check(["AIMING", "SHOP", "VICTORY", "DEFEAT"].has(model.state), "turn settles")
	model.start(43)
	model.grant_item("chip")
	model.update_preview()
	check(model.player.stats.preview_reflections == 2, "data-driven preview growth")
	model.player.stats.extra_pellets = 500
	model.player.stats.kill_split = 100
	model.fire()
	check(model.bullets.size() <= int(db.rules.simulation.max_alive), "simultaneous bullet cap")
	settle(model)
	check(model.created <= int(db.rules.simulation.max_created_per_shot), "cumulative generation cap")
	check(model.bullets.is_empty(), "stress turn does not hang")
	model.start(99)
	model.inventory = [model.make_weapon("splitter", 0)]
	model.obstacles.clear(); model.enemies.clear()
	model.aim = Vector2.RIGHT.rotated(deg_to_rad(-40))
	model.fire()
	var split_seen := false
	for _i in range(600):
		model.tick(1.0 / 60.0)
		for bullet in model.bullets:
			if int(bullet.depth) > 0:
				split_seen = true
				check(float(bullet.life) < float(db.weapons.splitter.lifetime), "split children inherit remaining lifespan")
				check(int(bullet.bounces) >= int(db.weapons.splitter.split.after_bounces), "split children inherit reflection count")
		if split_seen or model.state == "SHOP": break
	check(split_seen, "splitter produces actual child projectiles")
	settle(model)
	model.start(100)
	var rare := model.make_weapon("pistol", 3)
	check(rare.affixes.size() == int(db.rules.shop.quality_affix_count[3]), "quality weapon has configured affix count")
	model.inventory = [rare]
	check(model.weapon_description(rare).contains("「"), "affixes visible before purchase")
	# Verify the animated simulation agrees with the preview at actual contact points.
	model.start(101)
	model.obstacles.clear(); model.enemies.clear()
	model.aim = Vector2.RIGHT.rotated(deg_to_rad(-35))
	var weapon := model.weapon_stats()
	var origin: Vector2 = model.player.pos + model.aim * (float(model.player.radius) + float(db.rules.simulation.epsilon))
	var predicted := TrajectorySolver.trace(origin, model.aim, float(weapon.speed) * float(weapon.lifetime), int(weapon.bounces), model.generator.bounds(), [], [], model.player, model.player.stats, float(db.rules.simulation.epsilon))
	var actual: Array[Vector2] = []
	model.feedback.connect(func(kind: String, point: Vector2, _message: String):
		if kind == "bounce": actual.append(point))
	model.fire()
	settle(model)
	check(actual.size() == predicted.points.size() - 2, "preview and runtime reflection counts agree")
	for i in range(actual.size()):
		check(actual[i].distance_to(predicted.points[i + 1]) < 0.1, "preview and runtime contact points agree")
	# Real shield self-damage, isolated from map geometry.
	model.start(44)
	model.obstacles.clear()
	var guard: Dictionary = db.enemies.guard.duplicate(true)
	guard.pos = model.player.pos + Vector2(0, -120); guard.uid = 99; guard.max_hp = guard.hp
	model.enemies = [guard]
	model.aim = Vector2.UP
	model.fire()
	settle(model)
	check(model.player.hp < model.player.max_hp and guard.hp == guard.max_hp, "actual shield reflection damages player without damaging guard")
	# Last enemy removal does not open shop while bullets still exist.
	model.start(45)
	model.fire()
	for enemy in model.enemies: enemy.hp = 0
	model.tick(1.0 / 60.0)
	check(model.state == "PLAYER_RESOLVING", "clear waits for remaining bullets")
	settle(model)
	check(model.state == "SHOP", "clear opens shop after resolution")

func settle(model: CombatModel) -> void:
	for _i in range(1800):
		model.tick(1.0 / 60.0)
		if ["AIMING", "SHOP", "VICTORY", "DEFEAT", "ERROR"].has(model.state): return
	check(false, "settlement timeout: " + model.state)

func generation_tests(count: int) -> void:
	var generator := LevelGenerator.new(db)
	var fallbacks := 0
	for seed_index in range(count):
		for index in range(db.levels.size()):
			var layout := generator.generate(index, seed_index + 1000, [{"id": "pistol", "quality": 0, "upgrade": 0}], db.player.stats)
			check(not layout.is_empty(), "valid map seed %d stage %d: %s" % [seed_index, index, str(generator.diagnostics)])
			if generator.diagnostics.get("fallback", false): fallbacks += 1
	print("GENERATION: %d maps, %d fallback layouts" % [count * db.levels.size(), fallbacks])

func autoplay_test() -> void:
	var model := CombatModel.new(db)
	model.start(20261013)
	var shop := ShopService.new(model)
	var attempts := 0
	while attempts < 100 and model.state != "VICTORY" and model.state != "DEFEAT" and model.state != "ERROR":
		if model.state == "SHOP":
			shop.open()
			if model.player.hp < model.player.max_hp: shop.buy(0)
			shop.buy(2)
			shop.upgrade(0)
			model.next_level()
		elif model.state == "AIMING":
			var selected := best_angle(model)
			check(selected.score > 0, "autoplay finds damaging route at stage " + str(model.level_index))
			if selected.score <= 0: break
			model.aim = selected.direction
			model.fire()
			settle(model)
			attempts += 1
	print("AUTOPLAY: state=%s, stage=%d, shots=%d, hp=%.1f, gold=%d" % [model.state, model.level_index + 1, model.total_shots, model.player.hp, model.player.gold])
	check(model.state == "VICTORY", "five-stage run reaches victory with legal purchases")

func best_angle(model: CombatModel) -> Dictionary:
	var best := {"score": 0.0, "direction": Vector2.UP}
	var weapon := model.weapon_stats()
	for i in range(int(db.rules.generation.sample_angles)):
		var angle := lerpf(float(db.rules.arena.aim_degrees[0]), float(db.rules.arena.aim_degrees[1]), float(i) / float(db.rules.generation.sample_angles - 1))
		var direction := Vector2.RIGHT.rotated(deg_to_rad(angle))
		var origin: Vector2 = model.player.pos + direction * (float(model.player.radius) + float(db.rules.simulation.epsilon))
		var path := TrajectorySolver.trace(origin, direction, float(weapon.speed) * float(weapon.lifetime), int(weapon.bounces), model.generator.bounds(), model.obstacles, model.enemies, model.player, model.player.stats, float(db.rules.simulation.epsilon))
		if path.kind != "enemy" or path.target.is_empty(): continue
		if TrajectorySolver.shielded(path.target, path.points[-1]) and model.player.stats.shield_break <= 0: continue
		var score := minf(float(path.target.hp), float(weapon.damage))
		for behavior in path.target.behaviors:
			if behavior.type == "attack": score += float(behavior.damage) * 3.0
		if float(path.target.hp) <= float(weapon.damage): score += 40
		if score > best.score: best = {"score": score, "direction": direction}
	return best
