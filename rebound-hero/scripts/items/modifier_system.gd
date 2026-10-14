class_name ModifierSystem
extends RefCounted

# Paths and operands live in content. Adding numeric modifiers needs no combat edits.
static func apply(target: Dictionary, modifiers: Array) -> void:
	for modifier in modifiers:
		var path := str(modifier.path).split(".")
		var owner := target
		for i in range(path.size() - 1): owner = owner[path[i]]
		var key := str(path[-1])
		var value := float(owner[key])
		match modifier.op:
			"add": value += float(modifier.value)
			"multiply": value *= float(modifier.value)
			"minimum": value = maxf(value, float(modifier.value))
		owner[key] = value
