class_name SaveStore
extends RefCounted

var path: String
var state := {"version": 1, "runs": 0, "wins": 0, "best_stage": 0, "muted": false, "last_run": {}}

func _init(file_path: String) -> void:
	path = file_path

func load_state() -> void:
	if not FileAccess.file_exists(path): return
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary: return
	var loaded: Dictionary = parser.data
	if loaded.get("version") != state.version: return
	for key in state:
		if not loaded.has(key): continue
		if key == "muted" and loaded[key] is bool: state[key] = loaded[key]
		elif key == "last_run" and loaded[key] is Dictionary: state[key] = loaded[key]
		elif key in ["runs", "wins", "best_stage"] and (loaded[key] is float or loaded[key] is int): state[key] = maxi(0, int(loaded[key]))

func record(model: CombatModel) -> void:
	state.runs += 1
	if model.state == "VICTORY": state.wins += 1
	state.best_stage = maxi(int(state.best_stage), model.level_index + 1)
	state.last_run = {"seed": model.seed_value, "stage": model.level_index + 1, "shots": model.total_shots, "kills": model.kills, "damage": model.total_damage, "victory": model.state == "VICTORY"}
	write()

func write() -> void:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: push_warning("无法写入设置/统计文件"); return
	file.store_string(JSON.stringify(state, "\t"))
	file.close()
	var error := DirAccess.rename_absolute(path + ".tmp", path)
	if error != OK: push_warning("无法完成设置文件保存: " + str(error))
