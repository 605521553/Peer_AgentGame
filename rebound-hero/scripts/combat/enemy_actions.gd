class_name EnemyActions
extends RefCounted

var intent_handlers: Dictionary = {}
var end_handlers: Dictionary = {}

func _init() -> void:
	intent_handlers["attack"] = _attack
	end_handlers["shield"] = _rotate_shield

func intents(enemies: Array, player: Dictionary) -> Array:
	var result: Array = []
	for enemy in enemies:
		if enemy.hp <= 0: continue
		for behavior in enemy.behaviors:
			if intent_handlers.has(behavior.type):
				result.append_array(intent_handlers[behavior.type].call(enemy, behavior, player))
	return result

func end_round(enemies: Array) -> void:
	for enemy in enemies:
		if enemy.hp <= 0: continue
		for behavior in enemy.behaviors:
			if end_handlers.has(behavior.type): end_handlers[behavior.type].call(enemy, behavior)

func _attack(enemy: Dictionary, behavior: Dictionary, player: Dictionary) -> Array:
	var result: Array = []
	var center: Vector2 = (player.pos - enemy.pos).normalized()
	for i in range(int(behavior.pellets)):
		var offset := 0.0 if int(behavior.pellets) == 1 else lerpf(-0.5, 0.5, float(i) / float(behavior.pellets - 1))
		var direction := center.rotated(deg_to_rad(float(behavior.spread_degrees) * offset))
		var intent: Dictionary = behavior.duplicate(true)
		intent.pos = enemy.pos + direction * (float(enemy.radius) + 1.0)
		intent.dir = direction
		intent.source = enemy.uid
		result.append(intent)
	return result

func _rotate_shield(_enemy: Dictionary, behavior: Dictionary) -> void:
	behavior.facing_degrees = fmod(float(behavior.facing_degrees) + float(behavior.rotate_per_round), 360.0)
