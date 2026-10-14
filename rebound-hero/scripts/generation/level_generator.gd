class_name LevelGenerator
extends RefCounted

var db: ContentDB
var rng := RandomNumberGenerator.new()
var diagnostics: Dictionary = {}

func _init(content: ContentDB) -> void:
	db = content

func generate(index: int, seed_value: int, weapons: Array, stats: Dictionary) -> Dictionary:
	rng.seed = seed_value
	var template: Dictionary = db.levels[index]
	for attempt in range(int(db.rules.generation.max_attempts)):
		var layout := _build(template, true)
		if _spacing_valid(layout) and _reachable(layout, weapons, stats):
			diagnostics = {"attempts": attempt + 1, "fallback": false, "seed": seed_value}
			return layout
	var fallback := _build(template, false)
	if _spacing_valid(fallback) and _reachable(fallback, weapons, stats):
		diagnostics = {"attempts": db.rules.generation.max_attempts, "fallback": true, "seed": seed_value}
		return fallback
	diagnostics = {"error": "关卡模板无可用路线: " + str(template.id), "seed": seed_value}
	return {}

func _build(template: Dictionary, randomize: bool) -> Dictionary:
	var obstacles: Array = []
	var targets: Array = []
	for definition in template.obstacles:
		var obstacle: Dictionary = definition.duplicate(true)
		obstacle.pos = ContentDB.vec(obstacle.position)
		if randomize: obstacle.pos += _jitter(float(template.obstacle_jitter))
		if obstacle.shape != "circle": obstacle.points = TrajectorySolver.polygon(obstacle)
		obstacles.append(obstacle)
	for i in range(template.enemies.size()):
		var spawn: Dictionary = template.enemies[i]
		var target: Dictionary = db.enemies[spawn.type].duplicate(true)
		target.uid = i
		target.pos = ContentDB.vec(spawn.position)
		if randomize: target.pos += _jitter(float(template.enemy_jitter))
		target.hp = float(target.hp) * float(template.hp_mult)
		target.max_hp = target.hp
		for behavior in target.behaviors:
			if behavior.type == "attack": behavior.damage *= float(template.attack_mult)
		targets.append(target)
	return {"obstacles": obstacles, "enemies": targets, "witnesses": {}}

func _jitter(amount: float) -> Vector2:
	return Vector2(rng.randf_range(-amount, amount), rng.randf_range(-amount, amount))

func bounds() -> Rect2:
	var value: Array = db.rules.arena.rect
	return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))

func _spacing_valid(layout: Dictionary) -> bool:
	var objects: Array = []
	for obstacle in layout.obstacles:
		var radius: float = float(obstacle.radius) if obstacle.shape == "circle" else ContentDB.vec(obstacle.size).length() * 0.5
		objects.append({"pos": obstacle.pos, "radius": radius})
	for enemy in layout.enemies: objects.append({"pos": enemy.pos, "radius": float(enemy.radius)})
	var player_pos := ContentDB.vec(db.player.position)
	for i in range(objects.size()):
		var object: Dictionary = objects[i]
		if not bounds().grow(-float(object.radius)).has_point(object.pos): return false
		if object.pos.distance_to(player_pos) < object.radius + float(db.rules.generation.safe_radius): return false
		for j in range(i):
			if object.pos.distance_to(objects[j].pos) < object.radius + objects[j].radius + float(db.rules.generation.clearance): return false
	return true

func _reachable(layout: Dictionary, weapons: Array, stats: Dictionary) -> bool:
	var remaining: Array = layout.enemies.duplicate(true)
	var witnesses: Dictionary = {}
	var player := {"pos": ContentDB.vec(db.player.position), "radius": db.player.radius}
	var aim: Array = db.rules.arena.aim_degrees
	var samples := int(db.rules.generation.sample_angles)
	var probe_stats: Dictionary = stats.duplicate(true)
	probe_stats.pierce = 0
	for _pass in range(remaining.size()):
		var hits: Dictionary = {}
		for weapon in weapons:
			var definition: Dictionary = db.weapons[weapon.id]
			var limit := float(definition.speed) * float(definition.lifetime)
			# Splitter's unsplit probe must stop at its first split: do not claim unreachable routes.
			var bounces := int(definition.bounces) + int(stats.extra_bounces)
			if int(definition.split.after_bounces) > 0:
				bounces = mini(bounces, int(definition.split.after_bounces) - 1)
			for sample in range(samples):
				var angle := lerpf(float(aim[0]), float(aim[1]), float(sample) / float(samples - 1))
				var direction := Vector2.RIGHT.rotated(deg_to_rad(angle))
				var origin: Vector2 = player.pos + direction * (float(player.radius) + float(db.rules.simulation.epsilon))
				var result := TrajectorySolver.trace(origin, direction, limit, bounces, bounds(), layout.obstacles, remaining, player, probe_stats, float(db.rules.simulation.epsilon))
				if result.kind != "enemy" or result.target.is_empty(): continue
				if TrajectorySolver.shielded(result.target, result.points[-1]) and float(stats.shield_break) <= 0: continue
				var uid: int = result.target.uid
				hits[uid] = int(hits.get(uid, 0)) + 1
				witnesses[uid] = {"angle": angle, "weapon": weapon.id}
		var removed := false
		for enemy in remaining:
			if enemy.hp > 0 and int(hits.get(enemy.uid, 0)) >= int(db.rules.generation.minimum_angle_hits):
				enemy.hp = 0
				removed = true
		var complete := true
		for enemy in remaining:
			if enemy.hp > 0: complete = false
		if complete:
			layout.witnesses = witnesses
			return true
		if not removed: return false
	return false
