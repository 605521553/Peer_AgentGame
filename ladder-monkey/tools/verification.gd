extends Node
## Executed only with --verify / --capture, never visible in normal gameplay.
var game: Node
var capture_only: bool = false
var elapsed: float = 0.0
var scenario: int = 0
var scenario_time: float = 0.0
var errors: Array[String] = []
var states_seen: Dictionary = {}
var min_supports: int = 4
var min_taunt_supports: int = 4
var max_rung_stagger: int = 0
var max_joint_speed: float = 0.0
var previous_joints: Dictionary = {}
var report_written: bool = false
var captures: Dictionary = {}
var max_target_slip: float = 0.0
var stable_at: Dictionary = {}
var head_pose := Transform3D.IDENTITY
var foot_pose := Transform3D.IDENTITY
var last_idle_height: float = 0.0
var max_idle_drift: float = 0.0
var max_root_motion: float = 0.0
var report_suffix: String = ""
var output_directory: String = "res://artifacts"
var input_schedule := [
	{"duration": 0.60, "direction": 0, "label": "initial_idle"},
	{"duration": 3.35, "direction": 1, "label": "continuous_up"},
	{"duration": 1.30, "direction": 0, "label": "release_up"},
	{"duration": 2.31, "direction": -1, "label": "continuous_down"},
	{"duration": 1.35, "direction": 0, "label": "release_down"},
	{"duration": 0.37, "direction": 1, "label": "reverse_mid_reach"},
	{"duration": 1.15, "direction": -1, "label": "reverse_to_down"},
	{"duration": 1.37, "direction": 1, "label": "reverse_to_up"},
	{"duration": 1.35, "direction": 0, "label": "settle_reversal"},
	{"duration": 0.29, "direction": 1, "label": "taunt_during_step"},
	{"duration": 5.50, "direction": 0, "label": "queued_taunt", "taunt": true},
	{"duration": 65.0, "direction": 1, "label": "top_boundary"},
	{"duration": 1.3, "direction": 0, "label": "top_idle"},
	{"duration": 78.0, "direction": -1, "label": "bottom_boundary"},
	{"duration": 1.3, "direction": 0, "label": "bottom_idle"},
	{"duration": 4.30, "direction": 0, "label": "taunt_at_bottom", "taunt": true}
]

func _ready() -> void:
	process_priority = -50
	if not OS.has_feature("editor"):
		output_directory = "user://verification"
	for arg in OS.get_cmdline_user_args():
		if arg == "--report-fps=30":
			report_suffix = "_30fps"
		elif arg == "--report-fps=120":
			report_suffix = "_120fps"
	DirAccess.make_dir_recursive_absolute(output_directory)
	game.solvers[-1].modification_processed.connect(cache_final_pose)
	if not capture_only:
		apply_input()

func cache_final_pose() -> void:
	head_pose = game.rig.skeleton.get_bone_global_pose(game.rig.ids.Head)
	foot_pose = game.rig.skeleton.get_bone_global_pose(game.rig.ids.LeftFoot)

func _process(delta: float) -> void:
	if report_written:
		return
	elapsed += delta
	if capture_only:
		capture_sequence()
		return
	scenario_time += delta
	var control: MonkeyClimbController = game.controller
	states_seen[control.state_name()] = true
	var supports := 0
	for limb: String in MonkeyClimbController.LIMBS:
		var data: Dictionary = control.targets[limb]
		if not data.moving:
			supports += 1
			max_target_slip = maxf(max_target_slip, data.position.distance_to(game.ladder.contact(limb, data.rung)))
	min_supports = mini(min_supports, supports)
	if control.state >= MonkeyClimbController.State.TauntTurn:
		min_taunt_supports = mini(min_taunt_supports, supports)
	max_root_motion = maxf(max_root_motion, game.rig.position.length() + game.rig.rotation.length())
	max_rung_stagger = maxi(max_rung_stagger, absi(control.targets.LH.rung - control.targets.RH.rung))
	max_rung_stagger = maxi(max_rung_stagger, absi(control.targets.LF.rung - control.targets.RF.rung))
	for solver: MonkeyLimbIK in game.solvers:
		if solver.solve_count < 2:
			continue
		if previous_joints.has(solver.limb):
			max_joint_speed = maxf(max_joint_speed, solver.actual_joint.distance_to(previous_joints[solver.limb]))
		previous_joints[solver.limb] = solver.actual_joint
	if control.state == MonkeyClimbController.State.ClimbIdle:
		if last_idle_height != 0.0:
			max_idle_drift = maxf(max_idle_drift, absf(control.support_height - last_idle_height))
		last_idle_height = control.support_height
	else:
		last_idle_height = 0.0
	# A second Space press during performance must not restart/stack it.
	if input_schedule[scenario].label == "queued_taunt" and scenario_time > 2.0 and scenario_time < 2.02:
		key_event(KEY_SPACE, true)
	elif scenario_time > 0.04:
		key_event(KEY_SPACE, false)
	if scenario_time >= input_schedule[scenario].duration:
		if input_schedule[scenario].label == "top_idle":
			check(maxi(control.targets.LH.rung, control.targets.RH.rung) == game.ladder.rung_count - 1, "Top boundary was not reached")
		if input_schedule[scenario].label == "bottom_idle":
			check(mini(control.targets.LF.rung, control.targets.RF.rung) == 0, "Bottom boundary was not reached")
		scenario += 1
		scenario_time = 0.0
		if scenario >= input_schedule.size():
			finish_verification()
		else:
			apply_input()

func apply_input() -> void:
	key_event(KEY_W, false)
	key_event(KEY_S, false)
	key_event(KEY_SPACE, false)
	var item: Dictionary = input_schedule[scenario]
	if item.direction > 0:
		key_event(KEY_W, true)
	elif item.direction < 0:
		key_event(KEY_S, true)
	if item.get("taunt", false):
		key_event(KEY_SPACE, true)
	print("VERIFY ", item.label)

func key_event(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)

func finish_verification() -> void:
	report_written = true
	var control: MonkeyClimbController = game.controller
	check(min_supports >= 2, "Fewer than two support contacts")
	check(min_taunt_supports >= 3, "Taunt lost its three support contacts")
	check(max_root_motion < 0.00001, "Character root was moved or rotated instead of bones")
	check(max_target_slip < 0.0001, "World-space contact target slipped")
	check(max_rung_stagger <= 1, "Reversal created a rung stagger greater than one")
	check(max_idle_drift < 0.00001, "Idle height drifted")
	check(control.completed_taunts == 2, "Space did not produce exactly two complete performances")
	check(states_seen.size() == 7, "Not all seven animation states were exercised")
	var chains: Dictionary = {}
	for solver: MonkeyLimbIK in game.solvers:
		chains[solver.limb] = {"max_endpoint_error_m": solver.maximum_error, "max_planted_error_m": solver.contact_error, "max_segment_length_error_m": solver.maximum_length_error, "reach_clamps": solver.clamped_count, "solves": solver.solve_count}
		check(solver.maximum_error < 0.002, solver.limb + " unreachable end target")
		check(solver.contact_error < 0.0002, solver.limb + " planted contact slipped")
		check(solver.maximum_length_error < 0.00001, solver.limb + " bones stretched")
		check(solver.solve_count > 100, solver.limb + " modifier was not processed")
	var mesh: ArrayMesh = game.rig.skin_mesh.mesh
	var arrays := mesh.surface_get_arrays(0)
	var multi_weight := 0
	var w: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	for i in range(0, w.size(), 4):
		check(absf(w[i] + w[i + 1] + w[i + 2] + w[i + 3] - 1.0) < 0.002, "Non-normalized vertex weights")
		if w[i + 1] > 0.01:
			multi_weight += 1
	check(multi_weight > 500, "Insufficient blended skin vertices")
	var result := {"engine": Engine.get_version_info().string, "passed": errors.is_empty(), "physical_key_events": true, "simulation_seconds": elapsed, "states": states_seen.keys(), "half_steps": control.completed_steps, "taunts": control.completed_taunts, "minimum_supports": min_supports, "minimum_taunt_supports": min_taunt_supports, "max_root_motion": max_root_motion, "max_target_slip_m": max_target_slip, "max_idle_drift_m": max_idle_drift, "max_rung_stagger": max_rung_stagger, "max_joint_displacement_per_frame_m": max_joint_speed, "max_torso_reach_correction_m": game.body.maximum_reach_correction, "bones": game.rig.skeleton.get_bone_count(), "vertices": arrays[Mesh.ARRAY_VERTEX].size(), "blended_vertices": multi_weight, "ik": chains, "errors": errors}
	var file := FileAccess.open(output_directory + "/verification" + report_suffix + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	print("VERIFICATION_RESULT ", JSON.stringify(result))
	get_tree().quit(0 if errors.is_empty() else 1)

func capture_sequence() -> void:
	var control: MonkeyClimbController = game.controller
	if elapsed > 0.60 and not captures.has("idle"):
		captures.idle = true
		capture("01_idle")
		Input.action_press("climb_up")
	if elapsed > 1.00 and not captures.has("reach"):
		captures.reach = true
		capture("02_up_reach")
	if elapsed > 2.00 and not captures.has("down"):
		captures.down = true
		Input.action_release("climb_up")
		Input.action_press("climb_down")
	if elapsed > 3.00 and not captures.has("descending"):
		captures.descending = true
		capture("03_down_reach")
	if elapsed > 4.00 and not captures.has("space"):
		captures.space = true
		Input.action_release("climb_down")
		Input.action_press("taunt")
	if elapsed > 4.05:
		Input.action_release("taunt")
	if control.state == MonkeyClimbController.State.TauntPlay and control.taunt_clock > 0.55 and not captures.has("face"):
		captures.face = true
		capture("04_taunt")
	if elapsed > 9.00:
		report_written = true
		print("CAPTURES complete")
		get_tree().quit()

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = game.viewport.get_texture().get_image()
	image.resize(1152, 864, Image.INTERPOLATE_NEAREST)
	image.save_png(output_directory + "/" + label + ".png")
	print("CAPTURE ", label)
