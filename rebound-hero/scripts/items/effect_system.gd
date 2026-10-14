class_name EffectSystem
extends RefCounted

var handlers: Dictionary = {}

func _init() -> void:
	handlers = {"add_stat": _add_stat, "heal": _heal, "max_hp": _max_hp}

# New effect operations can be registered without changing shop or inventory code.
func register(operation: String, handler: Callable) -> void:
	handlers[operation] = handler

func apply(item: Dictionary, player: Dictionary) -> void:
	for effect in item.effects:
		handlers[effect.op].call(effect, player)

func _add_stat(effect: Dictionary, player: Dictionary) -> void:
	player.stats[effect.stat] += float(effect.value)

func _heal(effect: Dictionary, player: Dictionary) -> void:
	player.hp = minf(player.max_hp, player.hp + float(effect.value))

func _max_hp(effect: Dictionary, player: Dictionary) -> void:
	player.max_hp += float(effect.value)
