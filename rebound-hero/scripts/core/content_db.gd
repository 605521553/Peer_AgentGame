class_name ContentDB
extends RefCounted

var rules: Dictionary
var player: Dictionary
var visuals: Dictionary
var audio: Dictionary
var weapons: Dictionary = {}
var enemies: Dictionary = {}
var items: Dictionary = {}
var affixes: Dictionary = {}
var levels: Array = []
var errors: PackedStringArray = []

func load_all(manifest_path: String = "res://data/manifest.json") -> bool:
	rules = {}; player = {}; visuals = {}; audio = {}
	weapons.clear(); enemies.clear(); items.clear(); affixes.clear(); levels.clear(); errors.clear()
	var manifest = _read(manifest_path)
	if not manifest is Dictionary or not manifest.has("files"):
		errors.append("manifest: 缺少 files")
		return false
	var files: Dictionary = manifest.files
	if manifest.get("schema_version") != 1:
		errors.append("不支持的 manifest.schema_version")
		return false
	var base := manifest_path.get_base_dir()
	var schema = _read(base.path_join(str(manifest.get("schema", ""))))
	if not schema is Dictionary:
		errors.append("缺少配置结构定义 schema.json")
		return false
	for key in ["rules", "player", "visuals", "audio", "weapons", "enemies", "items", "affixes", "levels"]:
		if not files.has(key):
			errors.append("manifest: 缺少 " + key)
			continue
		var value = _read(base.path_join(str(files[key])))
		var error_count := errors.size()
		_shape(value, schema.get(key, {}), key)
		if errors.size() > error_count: continue
		match key:
			"rules", "player", "visuals", "audio":
				if not value is Dictionary:
					errors.append(key + ": 必须是对象")
				else:
					set(key, value)
			"levels":
				if value is Array:
					levels = value
				else:
					errors.append("levels: 必须是数组")
			_:
				if value is Array:
					_index(value, get(key), key)
				else:
					errors.append(key + ": 必须是数组")
	if not errors.is_empty():
		return false
	_validate()
	return errors.is_empty()

func _shape(value, specification: Dictionary, context: String) -> void:
	var kind := str(specification.get("type", ""))
	var valid := false
	match kind:
		"object": valid = value is Dictionary
		"array": valid = value is Array
		"number": valid = value is float or value is int
		"string": valid = value is String
		"bool": valid = value is bool
	if not valid: errors.append(context + ": 类型应为 " + kind); return
	if specification.has("enum") and not specification.enum.has(value): errors.append(context + ": 不支持的值 " + str(value))
	if kind == "number":
		if specification.has("min") and float(value) < float(specification.min): errors.append(context + ": 小于最小值")
		if specification.get("integer", false) and float(value) != floorf(float(value)): errors.append(context + ": 必须是整数")
	elif kind == "array":
		if specification.has("length") and value.size() != int(specification.length): errors.append(context + ": 数组长度错误")
		if value.size() < int(specification.get("min_length", 0)): errors.append(context + ": 数组条目不足")
		if specification.has("items"):
			for i in range(value.size()): _shape(value[i], specification.items, "%s[%d]" % [context, i])
	elif kind == "object":
		for key in specification.get("fields", {}):
			var child: Dictionary = specification.fields[key]
			if not value.has(key):
				if not child.get("optional", false): errors.append(context + "." + key + ": 缺少字段")
			else: _shape(value[key], child, context + "." + key)
		if specification.has("values"):
			for key in value: _shape(value[key], specification.values, context + "." + str(key))

func _read(path: String):
	if not FileAccess.file_exists(path):
		errors.append("文件不存在: " + path)
		return null
	var parser := JSON.new()
	var code := parser.parse(FileAccess.get_file_as_string(path))
	if code != OK:
		errors.append("%s:%d %s" % [path, parser.get_error_line(), parser.get_error_message()])
		return null
	return parser.data

func _index(entries: Array, destination: Dictionary, kind: String) -> void:
	for entry in entries:
		if not entry is Dictionary or not entry.has("id"):
			errors.append(kind + ": 条目缺少 id")
			continue
		var id := str(entry.id)
		if destination.has(id):
			errors.append(kind + ": 重复 id " + id)
		destination[id] = entry

func _required(value: Dictionary, keys: Array, context: String) -> bool:
	var valid := true
	for key in keys:
		if not value.has(key):
			errors.append(context + ": 缺少 " + str(key))
			valid = false
	return valid

func _positive(value: Dictionary, keys: Array, context: String) -> void:
	for key in keys:
		if not value.get(key) is float and not value.get(key) is int:
			errors.append(context + ": " + str(key) + " 必须为数值")
		elif float(value[key]) <= 0:
			errors.append(context + ": " + str(key) + " 必须大于零")

func _validate() -> void:
	if not _required(rules, ["arena", "simulation", "preview", "generation", "shop", "rewards", "combat"], "rules"):
		return
	if not _required(player, ["position", "radius", "hp", "gold", "max_weapons", "starting_weapons", "stats", "visual"], "player"):
		return
	var quality_count: int = rules.shop.quality_names.size()
	for key in ["quality_affix_count", "quality_price", "quality_damage"]:
		if rules.shop[key].size() != quality_count: errors.append("shop." + key + ": 长度必须与品质数量一致")
	if visuals.quality_colors.size() != quality_count: errors.append("visuals.quality_colors: 长度必须与品质数量一致")
	if float(player.stats.damage_mult) <= 0: errors.append("player.stats.damage_mult 必须大于零")
	if player.starting_weapons.size() > int(player.max_weapons): errors.append("初始武器超过携带上限")
	var rect: Array = rules.arena.rect
	if float(rect[2]) <= 0 or float(rect[3]) <= 0: errors.append("arena.rect: 战场尺寸必须大于零")
	if float(rules.arena.aim_degrees[0]) >= float(rules.arena.aim_degrees[1]): errors.append("aim_degrees: 最小角度必须小于最大角度")
	for key in ["armor_cap", "dodge_cap", "crit_cap"]:
		if float(rules.combat[key]) > 1: errors.append("combat." + key + ": 必须不大于 1")
	if float(rules.rewards.drop_chance) > 1: errors.append("drop_chance 必须不大于 1")
	for id in [player.visual, rules.shop.heal.visual]:
		if not visuals.styles.has(id): errors.append("未定义 visual: " + str(id))
	for key in ["renderer_scene", "arena_scene", "ui_scene", "sound_scene"]:
		if not ResourceLoader.exists(str(visuals[key])): errors.append("visuals." + key + ": 场景不存在")
	_required(rules.arena, ["rect", "aim_degrees", "min_aim_distance"], "arena")
	_required(rules.preview, ["base_reflections", "base_length", "max_reflections", "max_length", "spread_rays"], "preview")
	_positive(rules.simulation, ["fixed_step", "max_frame_delta", "speed_multiplier", "epsilon", "max_collisions_per_step", "max_alive", "max_created_per_shot", "max_split_depth", "max_turn_seconds"], "simulation")
	_positive(rules.generation, ["max_attempts", "sample_angles", "minimum_angle_hits", "clearance", "safe_radius"], "generation")
	_positive(player, ["hp", "radius", "max_weapons"], "player")
	for id in player.starting_weapons:
		if not weapons.has(id): errors.append("player: 未知初始武器 " + str(id))
	for id in weapons:
		var w: Dictionary = weapons[id]
		if not _required(w, ["name", "description", "price", "damage", "speed", "lifetime", "bounces", "pellets", "spread_degrees", "extra_pellet_spread", "split", "visual"], "weapon " + id): continue
		_positive(w, ["damage", "speed", "lifetime", "pellets"], "weapon " + id)
		if not visuals.styles.has(w.visual): errors.append("weapon " + id + ": 未定义 visual")
		_required(w.split, ["after_bounces", "count", "damage_mult", "spread_degrees"], "split " + id)
	for id in affixes:
		var affix: Dictionary = affixes[id]
		if not _required(affix, ["name", "description", "weapons", "modifiers"], "affix " + id): continue
		for weapon_id in affix.weapons:
			if not weapons.has(weapon_id): errors.append("affix " + id + ": 未知武器 " + str(weapon_id))
		for modifier in affix.modifiers:
			if not _required(modifier, ["path", "op", "value"], "modifier " + id): continue
			if not ["add", "multiply", "minimum"].has(modifier.op): errors.append("affix " + id + ": 未知 modifier.op")
			for weapon_id in weapons:
				if not affix.weapons.is_empty() and not affix.weapons.has(weapon_id): continue
				var owner: Dictionary = weapons[weapon_id]
				var path := str(modifier.path).split(".")
				for i in range(path.size()):
					if not owner.has(path[i]): errors.append("affix " + id + ": 无效属性路径 " + str(modifier.path)); break
					if i < path.size() - 1:
						if not owner[path[i]] is Dictionary: errors.append("affix: 路径非对象"); break
						owner = owner[path[i]]
	for id in enemies:
		var e: Dictionary = enemies[id]
		if not _required(e, ["name", "hp", "radius", "reward", "visual", "behaviors"], "enemy " + id): continue
		_positive(e, ["hp", "radius"], "enemy " + id)
		if not visuals.styles.has(e.visual): errors.append("enemy " + id + ": 未定义 visual")
		for behavior in e.behaviors:
			match behavior.get("type", ""):
				"shield": _required(behavior, ["arc_degrees", "facing_degrees", "rotate_per_round"], "shield " + id)
				"attack": _required(behavior, ["damage", "pellets", "spread_degrees", "speed", "lifetime", "bounces"], "attack " + id)
				_: errors.append("enemy " + id + ": 未注册行为 " + str(behavior.get("type")))
	for id in items:
		var item: Dictionary = items[id]
		if not _required(item, ["name", "description", "price", "quality", "max_stacks", "effects", "visual"], "item " + id): continue
		if int(item.quality) >= quality_count: errors.append("item " + id + ": 品质索引超出范围")
		if not visuals.styles.has(item.visual): errors.append("item " + id + ": 未定义 visual")
		for effect in item.effects:
			if not effect.has("value"): errors.append("item " + id + ": 缺少 effect.value")
			match effect.get("op", ""):
				"add_stat":
					if not player.stats.has(effect.get("stat", "")): errors.append("item " + id + ": 未知 stat")
				"heal", "max_hp": pass
				_: errors.append("item " + id + ": 未注册 effect.op")
	var seen: Dictionary = {}
	if levels.is_empty(): errors.append("至少需要一个关卡")
	for level in levels:
		if not level is Dictionary or not _required(level, ["id", "name", "subtitle", "target_shots", "hp_mult", "attack_mult", "enemy_jitter", "obstacle_jitter", "obstacles", "enemies"], "level"): continue
		if seen.has(level.id): errors.append("重复关卡 id: " + str(level.id))
		seen[level.id] = true
		for spawn in level.enemies:
			if not enemies.has(spawn.get("type", "")): errors.append("level: 未知敌人 " + str(spawn.get("type")))
		for obstacle in level.obstacles:
			if not ["rect", "circle", "triangle"].has(obstacle.get("shape", "")): errors.append("level: 未知几何形状")
			elif obstacle.shape == "circle": _required(obstacle, ["radius"], "circle " + level.id)
			else:
				if _required(obstacle, ["size", "rotation"], "polygon " + level.id):
					if float(obstacle.size[0]) <= 0 or float(obstacle.size[1]) <= 0: errors.append("polygon " + level.id + ": 尺寸必须大于零")
		for feature in level.get("shop_featured", []):
			var catalog: Dictionary = weapons if feature.type == "weapon" else items
			if not catalog.has(feature.id): errors.append("level " + level.id + ": 推荐商品不存在 " + feature.id)
	for weights in rules.shop.quality_weights:
		if weights.size() != quality_count: errors.append("品质权重长度不匹配")
		var total := 0.0
		for weight in weights: total += float(weight)
		if not is_equal_approx(total, 100.0): errors.append("商店品质概率必须合计 100")

static func vec(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))
