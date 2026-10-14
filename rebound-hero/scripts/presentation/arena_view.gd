extends Node2D

var model: CombatModel
var config: Dictionary
var font: Font
var actors: Dictionary = {}
var player_actor: Node2D
var actor_scene: PackedScene
var feedbacks: Array = []
var _layout_stamp := ""

func setup(combat: CombatModel, text_font: Font) -> void:
	model = combat
	config = combat.db.visuals
	font = text_font
	actor_scene = load(str(config.renderer_scene))
	model.feedback.connect(_feedback)
	player_actor = actor_scene.instantiate()
	add_child(player_actor)
	player_actor.configure(config)

func refresh(delta: float) -> void:
	if model == null: return
	var stamp := "%d:%d:%s" % [model.seed_value, model.level_index, str(model.generator.diagnostics)]
	if stamp != _layout_stamp:
		_layout_stamp = stamp
		for actor in actors.values(): actor.queue_free()
		actors.clear(); feedbacks.clear()
		for enemy in model.enemies:
			var actor: Node2D = actor_scene.instantiate()
			add_child(actor)
			actor.configure(config)
			actors[enemy.uid] = actor
	for enemy in model.enemies:
		if actors.has(enemy.uid):
			actors[enemy.uid].present({"position": enemy.pos, "radius": enemy.radius, "visual": enemy.visual, "visible": enemy.hp > 0})
	if not model.player.is_empty():
		player_actor.present({"position": model.player.pos, "radius": model.player.radius, "visual": model.player.visual, "visible": true})
	else:
		player_actor.visible = false
	for entry in feedbacks: entry.age += delta
	feedbacks = feedbacks.filter(func(entry): return float(entry.age) < float(config.feedback_lifetime))
	queue_redraw()

func _feedback(kind: String, point: Vector2, message: String) -> void:
	if feedbacks.size() >= int(config.feedback_limit): feedbacks.pop_front()
	feedbacks.append({"kind": kind, "pos": point, "message": message, "age": 0.0})

func _color(key: String) -> Color:
	return Color(str(config[key]))

func _draw() -> void:
	if model == null: return
	var bounds := model.generator.bounds()
	draw_rect(Rect2(0, 0, 1280, 720), _color("background"))
	var spacing := int(config.grid_spacing)
	for x in range(int(bounds.position.x), int(bounds.end.x), spacing):
		for y in range(int(bounds.position.y), int(bounds.end.y), spacing):
			draw_circle(Vector2(x, y), 0.75, _color("grid"))
	draw_rect(bounds, _color("wall"), false, float(config.wall_width))
	for point in [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]:
		draw_circle(point, 4, _color("accent"))
	for obstacle in model.obstacles:
		if obstacle.shape == "circle":
			draw_circle(obstacle.pos, obstacle.radius, _color("obstacle_fill"))
			draw_arc(obstacle.pos, obstacle.radius, 0, TAU, 64, _color("obstacle_edge"), 2, true)
		else:
			draw_colored_polygon(obstacle.points, _color("obstacle_fill"))
			var outline: PackedVector2Array = obstacle.points.duplicate()
			outline.append(outline[0])
			draw_polyline(outline, _color("obstacle_edge"), 2, true)
	for path in model.preview:
		var points: PackedVector2Array = path.points
		for i in range(points.size() - 1):
			draw_dashed_line(points[i], points[i + 1], Color(_color("preview"), 0.7 if model.preview.size() == 1 else 0.4), float(config.preview_width), 9, true)
			if i > 0: draw_circle(points[i], 4, _color("preview"))
		if points.size() > 1:
			draw_arc(points[-1], 6, 0, TAU, 20, _color("preview"), 1, true)
	if model.state == "ENEMY_WARNING":
		for intent in model.intents:
			var path := TrajectorySolver.trace(intent.pos, intent.dir, float(intent.speed) * float(intent.lifetime), int(intent.bounces), bounds, model.obstacles, model.enemies, model.player, {}, float(model.db.rules.simulation.epsilon), true)
			for i in range(path.points.size() - 1): draw_dashed_line(path.points[i], path.points[i + 1], Color(_color("enemy_preview"), 0.45), 1, 12, true)
	for bullet in model.bullets:
		var color := _color("bullet_enemy" if bullet.hostile else "bullet_player")
		draw_line(bullet.pos - bullet.dir * float(config.trail_length), bullet.pos, Color(color, 0.35), 3, true)
		draw_circle(bullet.pos, float(config.bullet_radius), color)
	for enemy in model.enemies:
		if enemy.hp <= 0: continue
		var radius := float(enemy.radius)
		for behavior in enemy.behaviors:
			if behavior.type == "shield":
				var facing := deg_to_rad(float(behavior.facing_degrees))
				var half := deg_to_rad(float(behavior.arc_degrees) * 0.5)
				draw_arc(enemy.pos, radius + 7, facing - half, facing + half, 30, _color("gold"), 4, true)
			elif behavior.type == "attack":
				_draw_text(enemy.pos + Vector2(-15, -radius - 26), "反击 %d" % int(behavior.damage), _color("danger"), int(config.small_size))
		var bar := Rect2(enemy.pos + Vector2(-radius, radius + 13), Vector2(radius * 2, 4))
		draw_rect(bar, _color("panel_border"))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * enemy.hp / enemy.max_hp, bar.size.y)), _color("text"))
		_draw_text(enemy.pos + Vector2(-radius, radius + 33), "%d / %d" % [ceili(enemy.hp), ceili(enemy.max_hp)], _color("muted"), int(config.small_size))
	if not model.player.is_empty():
		draw_line(model.player.pos, model.player.pos + model.aim * 30, _color("accent"), 5, true)
		draw_arc(model.player.pos, 28, PI, TAU, 32, Color(_color("accent"), 0.23), 1, true)
	for entry in feedbacks:
		var fraction := float(entry.age) / float(config.feedback_lifetime)
		var color := _color("danger" if entry.kind == "hurt" else "gold" if entry.kind == "kill" or entry.kind == "crit" or entry.kind == "loot" else "accent")
		color.a = 1.0 - fraction
		if entry.message.is_empty():
			draw_arc(entry.pos, 3 + fraction * 16, 0, TAU, 16, color, 1, true)
		else:
			_draw_text(entry.pos + Vector2(-15, -fraction * float(config.feedback_rise)), entry.message, color, int(config.font_size))

func _draw_text(point: Vector2, value: String, color: Color, size: int) -> void:
	draw_string(font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
