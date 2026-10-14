class_name CombatModel
extends RefCounted

signal changed
signal state_changed(state: String)
signal feedback(kind: String, position: Vector2, message: String)

var db: ContentDB
var generator: LevelGenerator
var effects := EffectSystem.new()
var actions := EnemyActions.new()
var rng := RandomNumberGenerator.new()
var loot_rng := RandomNumberGenerator.new()
var player: Dictionary = {}
var inventory: Array = []
var collected: Dictionary = {}
var pending_loot: Array = []
var level_index := 0
var active_weapon := 0
var state := "TITLE"
var obstacles: Array = []
var enemies: Array = []
var bullets: Array = []
var intents: Array = []
var preview: Array = []
var aim := Vector2.UP
var seed_value: int
var shots := 0
var total_shots := 0
var kills := 0
var total_damage := 0.0
var highest_bullet := 0.0
var highest_shot := 0.0
var shot_damage := 0.0
var shot_kills := 0
var shot_heal := 0.0
var max_chain_kills := 0
var created := 0
var phase_time := 0.0
var turn_time := 0.0
var level_hurt := false
var summary := ""
var error_message := ""
var _accumulator := 0.0
var _preview_dirty := true

func _init(content: ContentDB) -> void:
	db = content
	generator = LevelGenerator.new(db)

func start(new_seed: int = 0) -> void:
	seed_value = new_seed if new_seed != 0 else int(Time.get_unix_time_from_system())
	rng.seed = seed_value
	loot_rng.seed = seed_value ^ 0x4F1BBCDC
	player = db.player.duplicate(true)
	player.pos = ContentDB.vec(player.position)
	player.max_hp = float(player.hp)
	player.hp = float(player.hp)
	player.gold = int(player.gold)
	inventory.clear(); collected.clear(); pending_loot.clear()
	for id in db.player.starting_weapons: inventory.append(make_weapon(id, 0))
	level_index = 0; active_weapon = 0; total_shots = 0; kills = 0
	total_damage = 0; highest_bullet = 0; highest_shot = 0
	error_message = ""
	load_level()

func make_weapon(id: String, quality: int, random_source: RandomNumberGenerator = null) -> Dictionary:
	var source := random_source if random_source != null else loot_rng
	var candidates: Array = []
	for affix_id in db.affixes:
		var affix: Dictionary = db.affixes[affix_id]
		if affix.weapons.is_empty() or affix.weapons.has(id): candidates.append(affix_id)
	var chosen: Array = []
	for _i in range(mini(int(db.rules.shop.quality_affix_count[quality]), candidates.size())):
		var index := source.randi_range(0, candidates.size() - 1)
		chosen.append(candidates[index]); candidates.remove_at(index)
	return {"id": id, "quality": quality, "upgrade": 0, "affixes": chosen}

func weapon_description(instance: Dictionary) -> String:
	var lines: PackedStringArray = [str(db.weapons[instance.id].description)]
	for id in instance.get("affixes", []): lines.append("「%s」%s" % [db.affixes[id].name, db.affixes[id].description])
	return "\n".join(lines)

func set_state(value: String) -> void:
	state = value
	phase_time = 0
	state_changed.emit(value)
	changed.emit()

func load_level() -> void:
	set_state("GENERATING")
	bullets.clear(); preview.clear(); intents.clear()
	shots = 0; level_hurt = false; turn_time = 0; _accumulator = 0; max_chain_kills = 0
	var layout := generator.generate(level_index, seed_value + level_index, inventory, player.stats)
	if layout.is_empty():
		error_message = str(generator.diagnostics.error)
		set_state("ERROR")
		return
	obstacles = layout.obstacles
	enemies = layout.enemies
	_preview_dirty = true
	set_state("AIMING")

func next_level() -> void:
	if state != "SHOP": return
	level_index += 1
	load_level()

func set_aim(point: Vector2) -> void:
	if state != "AIMING": return
	var offset: Vector2 = point - player.pos
	if offset.length() < float(db.rules.arena.min_aim_distance): return
	var limits: Array = db.rules.arena.aim_degrees
	var angle := clampf(rad_to_deg(offset.angle()), float(limits[0]), float(limits[1]))
	var new_aim := Vector2.RIGHT.rotated(deg_to_rad(angle))
	if not new_aim.is_equal_approx(aim):
		aim = new_aim
		_preview_dirty = true

func select_weapon(index: int) -> void:
	if state != "AIMING" or index < 0 or index >= inventory.size(): return
	active_weapon = index
	_preview_dirty = true
	changed.emit()

func weapon_stats() -> Dictionary:
	var instance: Dictionary = inventory[active_weapon]
	var weapon: Dictionary = db.weapons[instance.id].duplicate(true)
	for id in instance.get("affixes", []): ModifierSystem.apply(weapon, db.affixes[id].modifiers)
	weapon.damage *= float(db.rules.shop.quality_damage[instance.quality]) * (1.0 + float(instance.upgrade) * float(db.rules.shop.upgrade_damage)) * float(player.stats.damage_mult)
	weapon.bounces += int(player.stats.extra_bounces)
	weapon.pellets += int(player.stats.extra_pellets)
	if int(player.stats.extra_pellets) > 0: weapon.spread_degrees = maxf(float(weapon.spread_degrees), float(weapon.extra_pellet_spread))
	return weapon

func update_preview() -> void:
	preview.clear()
	if inventory.is_empty() or state != "AIMING": return
	var weapon := weapon_stats()
	var reflections := mini(int(db.rules.preview.max_reflections), int(db.rules.preview.base_reflections) + int(player.stats.preview_reflections))
	reflections = mini(reflections, int(weapon.bounces))
	var length := minf(float(db.rules.preview.max_length), float(db.rules.preview.base_length) + float(player.stats.preview_length))
	length = minf(length, float(weapon.speed) * float(weapon.lifetime))
	if int(weapon.split.after_bounces) > 0: reflections = mini(reflections, int(weapon.split.after_bounces) - 1)
	var count := mini(int(weapon.pellets), int(db.rules.preview.spread_rays))
	for i in range(count):
		var offset := 0.0 if count == 1 else lerpf(-0.5, 0.5, float(i) / float(count - 1))
		var direction := aim.rotated(deg_to_rad(float(weapon.spread_degrees) * offset))
		var origin: Vector2 = player.pos + direction * (float(player.radius) + float(db.rules.simulation.epsilon))
		preview.append(TrajectorySolver.trace(origin, direction, length, reflections, generator.bounds(), obstacles, enemies, player, player.stats, float(db.rules.simulation.epsilon)))
	_preview_dirty = false

func fire() -> bool:
	if state != "AIMING": return false
	var weapon := weapon_stats()
	bullets.clear(); preview.clear()
	shot_kills = 0; shot_damage = 0; shot_heal = 0; created = 0; turn_time = 0
	shots += 1; total_shots += 1
	set_state("PLAYER_RESOLVING")
	feedback.emit("fire", player.pos, "")
	for i in range(int(weapon.pellets)):
		var offset := 0.0 if int(weapon.pellets) == 1 else lerpf(-0.5, 0.5, float(i) / float(weapon.pellets - 1))
		var direction := aim.rotated(deg_to_rad(float(weapon.spread_degrees) * offset))
		_spawn({"pos": player.pos + direction * (float(player.radius) + float(db.rules.simulation.epsilon)), "dir": direction, "speed": weapon.speed, "life": weapon.lifetime, "damage": weapon.damage, "limit": weapon.bounces, "split": weapon.split.duplicate(true), "depth": 0, "hostile": false, "bounces": 0, "pierce": int(player.stats.pierce), "ignored": [], "dead": false, "total": 0.0})
	return true

func _spawn(bullet: Dictionary) -> void:
	if bullets.size() >= int(db.rules.simulation.max_alive) or created >= int(db.rules.simulation.max_created_per_shot): return
	bullets.append(bullet)
	created += 1

func tick(delta: float) -> void:
	if state == "TITLE" or state == "SHOP" or state == "VICTORY" or state == "DEFEAT" or state == "ERROR": return
	if state == "AIMING":
		if _preview_dirty: update_preview()
		return
	_accumulator += minf(delta, float(db.rules.simulation.max_frame_delta))
	var step := float(db.rules.simulation.fixed_step)
	while _accumulator >= step:
		_accumulator -= step
		_step(step)
		if state == "AIMING" or state == "SHOP" or state == "VICTORY" or state == "DEFEAT":
			_accumulator = 0
			break

func _step(delta: float) -> void:
	phase_time += delta
	match state:
		"PLAYER_RESOLVING", "ENEMY_RESOLVING":
			turn_time += delta
			var snapshot: Array = bullets.duplicate()
			for bullet in snapshot:
				if not bullet.dead: _move_bullet(bullet, delta)
				if player.hp <= 0:
					highest_shot = maxf(highest_shot, shot_damage)
					bullets.clear()
					pending_loot.clear()
					set_state("DEFEAT")
					return
			bullets = bullets.filter(func(b): return not b.dead)
			if turn_time >= float(db.rules.simulation.max_turn_seconds): bullets.clear()
			if bullets.is_empty():
				if state == "PLAYER_RESOLVING":
					highest_shot = maxf(highest_shot, shot_damage)
					max_chain_kills = maxi(max_chain_kills, shot_kills)
					for id in pending_loot:
						grant_item(id)
						feedback.emit("loot", player.pos, "获得 " + str(db.items[id].name))
					pending_loot.clear()
					if living_enemies() == 0:
						_complete_level()
					else:
						intents = actions.intents(enemies, player)
						set_state("ENEMY_WARNING")
				else:
					set_state("ROUND_END")
		"ENEMY_WARNING":
			if phase_time >= float(db.rules.combat.warning_seconds):
				created = 0; turn_time = 0
				for intent in intents:
					_spawn({"pos": intent.pos, "dir": intent.dir, "speed": intent.speed, "life": intent.lifetime, "damage": intent.damage, "limit": intent.bounces, "split": {}, "depth": 0, "hostile": true, "bounces": 0, "pierce": 0, "ignored": [], "dead": false, "total": 0.0})
				set_state("ENEMY_RESOLVING")
		"ROUND_END":
			if phase_time >= float(db.rules.combat.round_end_seconds):
				actions.end_round(enemies)
				_preview_dirty = true
				set_state("AIMING")

func _move_bullet(bullet: Dictionary, delta: float) -> void:
	bullet.life -= delta
	if bullet.life <= 0: bullet.dead = true; return
	var remaining: float = float(bullet.speed) * delta + float(bullet.get("remainder", 0.0))
	bullet.remainder = 0.0
	for _collision in range(int(db.rules.simulation.max_collisions_per_step)):
		if remaining <= 0 or bullet.dead: return
		var hit := TrajectorySolver.cast(bullet.pos, bullet.dir, remaining, generator.bounds(), obstacles, enemies, player, bullet.hostile, bullet.ignored)
		bullet.pos = hit.point
		remaining -= float(hit.distance)
		if hit.kind == "none": return
		if hit.kind == "player":
			_hurt_player(float(bullet.damage))
			bullet.dead = true
			return
		if hit.kind == "enemy":
			if TrajectorySolver.shielded(hit.target, hit.point) and float(player.stats.shield_break) <= 0:
				bullet.hostile = true
				feedback.emit("shield", hit.point, "反射")
			else:
				_damage_enemy(hit.target, bullet)
				if int(bullet.pierce) <= 0:
					bullet.dead = true
					return
				bullet.pierce -= 1
				bullet.ignored.append(hit.target.uid)
				bullet.pos += bullet.dir * float(db.rules.simulation.epsilon)
				continue
		if int(bullet.bounces) >= int(bullet.limit): bullet.dead = true; return
		bullet.dir = bullet.dir.bounce(hit.normal).normalized()
		bullet.bounces += 1
		feedback.emit("bounce", hit.point, "")
		bullet.pos += bullet.dir * float(db.rules.simulation.epsilon)
		remaining = maxf(0, remaining - float(db.rules.simulation.epsilon))
		if not bullet.hostile and not bullet.split.is_empty() and int(bullet.split.after_bounces) > 0 and int(bullet.bounces) >= int(bullet.split.after_bounces):
			_split(bullet, int(bullet.split.count) + int(player.stats.split_extra), float(bullet.split.spread_degrees), float(bullet.split.damage_mult))
			bullet.dead = true
			return
	bullet.remainder = remaining

func _split(parent: Dictionary, count: int, spread: float, damage_mult: float) -> void:
	if int(parent.depth) >= int(db.rules.simulation.max_split_depth): return
	for i in range(count):
		var offset := 0.0 if count == 1 else lerpf(-0.5, 0.5, float(i) / float(count - 1))
		var child: Dictionary = parent.duplicate(true)
		child.dir = parent.dir.rotated(deg_to_rad(spread * offset))
		child.pos = parent.pos + child.dir * float(db.rules.simulation.epsilon)
		child.damage *= damage_mult
		child.depth += 1
		child.total = 0.0
		child.split = {}
		child.dead = false
		child.remainder = 0.0
		_spawn(child)
	feedback.emit("split", parent.pos, "分裂")

func _damage_enemy(enemy: Dictionary, bullet: Dictionary) -> void:
	var bounce_mult := 1.0 + minf(float(db.rules.combat.bounce_bonus_cap), float(player.stats.bounce_bonus) * int(bullet.bounces))
	var critical := rng.randf() < minf(float(db.rules.combat.crit_cap), float(player.stats.crit_chance))
	var damage := float(bullet.damage) * bounce_mult * (float(player.stats.crit_mult) if critical else 1.0)
	var dealt := minf(float(enemy.hp), damage)
	enemy.hp = maxf(0, float(enemy.hp) - damage)
	shot_damage += dealt; total_damage += dealt; bullet.total += dealt
	highest_bullet = maxf(highest_bullet, float(bullet.total))
	var healing := minf(float(db.rules.combat.heal_cap_per_shot) - shot_heal, dealt * float(player.stats.lifesteal))
	shot_heal += healing
	player.hp = minf(player.max_hp, player.hp + healing)
	feedback.emit("crit" if critical else "damage", enemy.pos, str(roundi(damage)))
	if enemy.hp <= 0:
		kills += 1; shot_kills += 1
		player.gold += int(enemy.reward)
		feedback.emit("kill", enemy.pos, "+%d 金币" % int(enemy.reward))
		if int(player.stats.kill_split) > 0:
			_split(bullet, int(player.stats.kill_split), float(db.rules.combat.kill_split_spread), float(db.rules.combat.kill_split_damage_mult))
		if loot_rng.randf() < float(db.rules.rewards.drop_chance):
			var choices: Array = []
			for id in db.items:
				if int(db.items[id].quality) <= level_index and int(collected.get(id, 0)) < int(db.items[id].max_stacks): choices.append(id)
			if not choices.is_empty():
				var id: String = choices[loot_rng.randi_range(0, choices.size() - 1)]
				pending_loot.append(id)
	changed.emit()

func _hurt_player(damage: float) -> void:
	if rng.randf() < minf(float(db.rules.combat.dodge_cap), float(player.stats.dodge)):
		feedback.emit("dodge", player.pos, "闪避")
		return
	var actual := damage * (1.0 - minf(float(db.rules.combat.armor_cap), float(player.stats.armor)))
	player.hp = maxf(0, float(player.hp) - actual)
	level_hurt = true
	feedback.emit("hurt", player.pos, "-%d" % ceili(actual))
	changed.emit()

func grant_item(id: String) -> void:
	if not db.items.has(id): return
	if int(collected.get(id, 0)) >= int(db.items[id].max_stacks): return
	collected[id] = int(collected.get(id, 0)) + 1
	effects.apply(db.items[id], player)
	_preview_dirty = true
	changed.emit()

func living_enemies() -> int:
	var count := 0
	for enemy in enemies:
		if enemy.hp > 0: count += 1
	return count

func _complete_level() -> void:
	var reward := int(db.rules.rewards.clear)
	var bonuses: PackedStringArray = []
	if shots <= int(db.levels[level_index].target_shots):
		reward += int(db.rules.rewards.precision)
		bonuses.append("精准 +%d" % int(db.rules.rewards.precision))
	if not level_hurt:
		reward += int(db.rules.rewards.no_damage)
		bonuses.append("无伤 +%d" % int(db.rules.rewards.no_damage))
	var chain := mini(int(db.rules.rewards.chain_cap), maxi(0, max_chain_kills - 1) * int(db.rules.rewards.chain_per_kill))
	reward += chain
	if chain > 0: bonuses.append("连杀 +%d" % chain)
	player.gold += reward
	summary = "清场奖励 +%d 金币" % reward
	if not bonuses.is_empty(): summary += "  ·  " + " / ".join(bonuses)
	set_state("VICTORY" if level_index == db.levels.size() - 1 else "SHOP")
