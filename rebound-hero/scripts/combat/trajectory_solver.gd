class_name TrajectorySolver
extends RefCounted

# Shared analytic center-ray solver. No rendering or damage side effects.
static func polygon(obstacle: Dictionary) -> PackedVector2Array:
	var size := ContentDB.vec(obstacle.size)
	var local := PackedVector2Array()
	match obstacle.shape:
		"rect": local = PackedVector2Array([Vector2(-size.x, -size.y), Vector2(size.x, -size.y), size, Vector2(-size.x, size.y)])
		"triangle": local = PackedVector2Array([Vector2(0, -size.y), size, Vector2(-size.x, size.y)])
	var points := PackedVector2Array()
	for point in local:
		points.append(obstacle.pos + (point * 0.5).rotated(deg_to_rad(float(obstacle.rotation))))
	return points

static func cast(origin: Vector2, direction: Vector2, distance: float, bounds: Rect2, obstacles: Array, enemies: Array, player: Dictionary, hostile: bool, ignored: Array = []) -> Dictionary:
	var result := {"distance": distance, "kind": "none", "point": origin + direction * distance, "normal": Vector2.ZERO, "target": {}}
	var corners := PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)])
	for i in range(corners.size()):
		_consider(result, _segment(origin, direction, corners[i], corners[(i + 1) % corners.size()]), "wall", {})
	for obstacle in obstacles:
		if obstacle.shape == "circle":
			_consider(result, _circle(origin, direction, obstacle.pos, float(obstacle.radius)), "wall", obstacle)
		else:
			var points: PackedVector2Array = obstacle.points
			for i in range(points.size()):
				_consider(result, _segment(origin, direction, points[i], points[(i + 1) % points.size()]), "wall", obstacle)
	if hostile:
		_consider(result, _circle(origin, direction, player.pos, float(player.radius)), "player", player)
	else:
		for enemy in enemies:
			if enemy.hp <= 0 or ignored.has(enemy.uid): continue
			_consider(result, _circle(origin, direction, enemy.pos, float(enemy.radius)), "enemy", enemy)
	return result

static func _consider(result: Dictionary, hit: Dictionary, kind: String, target: Dictionary) -> void:
	if hit.is_empty() or hit.distance > result.distance: return
	result.merge(hit, true)
	result.kind = kind
	result.target = target

static func _segment(origin: Vector2, direction: Vector2, a: Vector2, b: Vector2) -> Dictionary:
	var edge := b - a
	var denominator := direction.cross(edge)
	if absf(denominator) < 0.000001: return {}
	var offset := a - origin
	var t := offset.cross(edge) / denominator
	var u := offset.cross(direction) / denominator
	if t < 0.00001 or u < 0 or u > 1: return {}
	var normal := Vector2(-edge.y, edge.x).normalized()
	if normal.dot(direction) > 0: normal = -normal
	return {"distance": t, "point": origin + direction * t, "normal": normal}

static func _circle(origin: Vector2, direction: Vector2, center: Vector2, radius: float) -> Dictionary:
	var offset := origin - center
	var b := offset.dot(direction)
	var discriminant := b * b - (offset.length_squared() - radius * radius)
	if discriminant < 0: return {}
	var t := -b - sqrt(discriminant)
	if t < 0.00001: t = -b + sqrt(discriminant)
	if t < 0.00001: return {}
	var point := origin + direction * t
	return {"distance": t, "point": point, "normal": (point - center).normalized()}

static func shielded(enemy: Dictionary, point: Vector2) -> bool:
	for behavior in enemy.behaviors:
		if behavior.type == "shield":
			var facing := Vector2.RIGHT.rotated(deg_to_rad(float(behavior.facing_degrees)))
			return facing.dot((point - enemy.pos).normalized()) >= cos(deg_to_rad(float(behavior.arc_degrees) * 0.5))
	return false

static func trace(origin: Vector2, direction: Vector2, length: float, reflections: int, bounds: Rect2, obstacles: Array, enemies: Array, player: Dictionary, stats: Dictionary, epsilon: float, hostile: bool = false) -> Dictionary:
	var points := PackedVector2Array([origin])
	var ignored: Array = []
	var pierces := int(stats.get("pierce", 0))
	var end_kind := "range"
	var target: Dictionary = {}
	# Extra hits account for finite penetration; reflection count is not segment count.
	for _i in range(reflections + enemies.size() + 2):
		var hit := cast(origin, direction, length, bounds, obstacles, enemies, player, hostile, ignored)
		points.append(hit.point)
		length -= float(hit.distance)
		end_kind = hit.kind
		target = hit.target
		if hit.kind == "none" or length <= 0: break
		if hit.kind == "player": break
		if hit.kind == "enemy":
			if not shielded(hit.target, hit.point) or stats.get("shield_break", 0) > 0:
				if pierces <= 0: break
				pierces -= 1
				ignored.append(hit.target.uid)
				origin = hit.point + direction * epsilon
				length -= epsilon
				continue
			hostile = true
		if reflections <= 0: break
		reflections -= 1
		direction = direction.bounce(hit.normal).normalized()
		origin = hit.point + direction * epsilon
		length -= epsilon
	return {"points": points, "kind": end_kind, "target": target}
