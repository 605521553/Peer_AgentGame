class_name MonkeyRig
extends Node3D

const FUR := Color("a95c38")
const DARK_FUR := Color("663929")
const SKIN := Color("efbb81")
const CREAM := Color("ffe0a1")
var skeleton: Skeleton3D
var skin_mesh: MeshInstance3D
var ids: Dictionary = {}
var rest_positions: Dictionary = {}
var profile: ClimbProfile = preload("res://resources/climb_profile.tres")

func _ready() -> void:
	if has_node("Skeleton3D"):
		skeleton = get_node("Skeleton3D")
		skin_mesh = get_node("MonkeySkin")
		for i in skeleton.get_bone_count():
			ids[skeleton.get_bone_name(i)] = i
			rest_positions[skeleton.get_bone_name(i)] = skeleton.get_bone_global_rest(i).origin
	else:
		build()
	get_node("AnimationPlayer").play("breathing")

func bone(label: String, parent: String, at: Vector3) -> int:
	var index := skeleton.get_bone_count()
	skeleton.add_bone(label)
	var parent_index: int = ids.get(parent, -1)
	if parent_index >= 0:
		skeleton.set_bone_parent(index, parent_index)
	var local: Vector3 = at - rest_positions[parent] if parent_index >= 0 else at
	skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, local))
	# Godot bone poses are absolute local transforms, initialised to rest.
	skeleton.set_bone_pose_position(index, local)
	ids[label] = index
	rest_positions[label] = at
	return index

func build() -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	add_child(skeleton)
	bone("Root", "", Vector3.ZERO)
	bone("Hips", "Root", Vector3.ZERO)
	bone("Spine", "Hips", Vector3(0, 0.19, -0.025))
	bone("Chest", "Spine", Vector3(0, 0.40, -0.055))
	bone("Neck", "Chest", Vector3(0, 0.58, -0.015))
	bone("Head", "Neck", Vector3(0, 0.73, 0.0))
	var geo := SkinGeometry.new()
	geo.ellipsoid(Vector3(0, 0.10, 0), Vector3(0.255, 0.36, 0.21), FUR, ids.Hips, 12, 8, ids.Chest)
	geo.ellipsoid(Vector3(0, 0.31, -0.035), Vector3(0.30, 0.20, 0.20), FUR, ids.Spine, 12, 6, ids.Chest)
	geo.tube([Vector3(0, 0.43, -0.035), Vector3(0, 0.58, -0.015), Vector3(0, 0.70, 0)], [0.125, 0.11, 0.115], [[[ids.Chest], [1.0]], [[ids.Chest, ids.Neck], [0.25, 0.75]], [[ids.Neck, ids.Head], [0.25, 0.75]]], FUR)
	geo.ellipsoid(Vector3(0, 0.21, -0.17), Vector3(0.185, 0.23, 0.045), SKIN, ids.Spine, 10, 6, ids.Chest)
	var head: Vector3 = rest_positions.Head
	geo.ellipsoid(head + Vector3(0, 0.13, 0), Vector3(0.335, 0.34, 0.285), FUR, ids.Head, 12, 8)
	# A two-lobed face, broad muzzle and ears give an original cartoon silhouette.
	for side in [-1.0, 1.0]:
		geo.ellipsoid(head + Vector3(side * 0.125, 0.15, -0.23), Vector3(0.16, 0.19, 0.087), SKIN, ids.Head)
		geo.ellipsoid(head + Vector3(side * 0.35, 0.15, 0), Vector3(0.115, 0.14, 0.07), DARK_FUR, ids.Head, 8)
		geo.ellipsoid(head + Vector3(side * 0.36, 0.15, -0.04), Vector3(0.075, 0.095, 0.025), SKIN, ids.Head, 8)
	geo.ellipsoid(head + Vector3(0, -0.005, -0.275), Vector3(0.215, 0.13, 0.10), SKIN, ids.Head)
	geo.ellipsoid(head + Vector3(0, 0.05, -0.37), Vector3(0.065, 0.044, 0.034), DARK_FUR, ids.Head, 8, 4)
	# Forehead tuft, bound to the head, visibly faceted.
	geo.ellipsoid(head + Vector3(0.045, 0.44, 0.015), Vector3(0.11, 0.13, 0.11), DARK_FUR, ids.Head, 7, 4)
	for side_label in ["Left", "Right"]:
		var side := -1.0 if side_label == "Left" else 1.0
		var shoulder := Vector3(side * 0.27, 0.40, -0.05)
		var elbow := shoulder + Vector3(side * 0.20, -0.48, 0).normalized() * profile.arm_upper_length
		var wrist := elbow + Vector3(side * 0.10, -0.50, 0).normalized() * profile.arm_lower_length
		bone(side_label + "Arm", "Chest", shoulder)
		bone(side_label + "Forearm", side_label + "Arm", elbow)
		bone(side_label + "Hand", side_label + "Forearm", wrist)
		limb_mesh(geo, shoulder, elbow, wrist, ids[side_label + "Arm"], ids[side_label + "Forearm"], ids[side_label + "Hand"], 0.10, FUR)
		geo.ellipsoid(wrist + Vector3(0, 0.008, 0.069), Vector3(0.078, 0.075, 0.040), SKIN, ids[side_label + "Hand"], 8, 5)
		for f in 4:
			var x := (float(f) - 1.5) * 0.040
			var knuckle := wrist + Vector3(x, 0.064, 0.035)
			var curl := wrist + Vector3(x, 0.028, -0.058)
			var b1 := bone(side_label + "Finger%d" % f, side_label + "Hand", knuckle)
			var b2 := bone(side_label + "Finger%dTip" % f, side_label + "Finger%d" % f, curl)
			geo.tube([knuckle, wrist + Vector3(x, 0.068, -0.014), curl, wrist + Vector3(x, -0.038, -0.054), wrist + Vector3(x, -0.049, 0.001)], [0.018, 0.018, 0.016, 0.014, 0.011], [[[b1], [1.0]], [[b1], [1.0]], [[b1, b2], [0.5, 0.5]], [[b2], [1.0]], [[b2], [1.0]]], SKIN, 6)
		geo.ellipsoid(wrist + Vector3(side * 0.089, -0.011, 0.047), Vector3(0.033, 0.061, 0.033), SKIN, ids[side_label + "Hand"], 6, 4)
		var hip := Vector3(side * 0.17, -0.10, 0)
		var knee := hip + Vector3(side * 0.06, -0.45, 0.07).normalized() * profile.leg_upper_length
		var ankle := knee + Vector3(-side * 0.01, -0.44, -0.12).normalized() * profile.leg_lower_length
		bone(side_label + "Leg", "Hips", hip)
		bone(side_label + "Shin", side_label + "Leg", knee)
		bone(side_label + "Foot", side_label + "Shin", ankle)
		limb_mesh(geo, hip, knee, ankle, ids[side_label + "Leg"], ids[side_label + "Shin"], ids[side_label + "Foot"], 0.125, FUR)
		geo.ellipsoid(ankle + Vector3(0, 0.045, 0.02), Vector3(0.100, 0.045, 0.15), SKIN, ids[side_label + "Foot"], 8, 4)
		for toe in 3:
			geo.ellipsoid(ankle + Vector3((toe - 1) * 0.058, 0.04, -0.11), Vector3(0.033, 0.037, 0.054), SKIN, ids[side_label + "Foot"], 6, 4)
	var tail_path: Array[Vector3] = []
	var tail_radii: Array[float] = []
	var tail_bindings: Array = []
	for i in 7:
		var at := Vector3(0, -0.08 - 0.075 * i + 0.018 * i * i, 0.17 + 0.155 * i)
		var label := "Tail%d" % i
		bone(label, "Hips" if i == 0 else "Tail%d" % (i - 1), at)
		tail_path.append(at)
		tail_radii.append(0.052 - i * 0.005)
		if i == 0:
			tail_bindings.append([[ids[label]], [1.0]])
		else:
			tail_bindings.append([[ids["Tail%d" % (i - 1)], ids[label]], [0.4, 0.6]])
	geo.tube(tail_path, tail_radii, tail_bindings, DARK_FUR, 7)
	for side_label in ["Left", "Right"]:
		var side := -1.0 if side_label == "Left" else 1.0
		var eye := head + Vector3(side * 0.12, 0.18, -0.295)
		bone(side_label + "Eye", "Head", eye)
		geo.ellipsoid(eye, Vector3(0.073, 0.092, 0.032), CREAM, ids[side_label + "Eye"], 8, 5)
		bone(side_label + "Pupil", side_label + "Eye", eye + Vector3(0, -0.006, -0.028))
		geo.ellipsoid(eye + Vector3(0, -0.006, -0.030), Vector3(0.032, 0.050, 0.016), Color("302821"), ids[side_label + "Pupil"], 8, 4)
		geo.ellipsoid(eye + Vector3(-0.009, 0.015, -0.044), Vector3(0.010, 0.015, 0.007), Color.WHITE, ids[side_label + "Pupil"], 6, 4)
		var brow := eye + Vector3(0, 0.10, -0.01)
		bone(side_label + "Brow", "Head", brow)
		geo.ellipsoid(brow, Vector3(0.089, 0.026, 0.035), DARK_FUR, ids[side_label + "Brow"], 8, 4)
	var jaw := head + Vector3(0, -0.038, -0.24)
	bone("Jaw", "Head", jaw)
	geo.ellipsoid(jaw + Vector3(0, -0.045, -0.048), Vector3(0.155, 0.065, 0.082), SKIN, ids.Jaw, 10, 5)
	geo.ellipsoid(jaw + Vector3(0, -0.008, -0.12), Vector3(0.112, 0.035, 0.015), Color("452e2e"), ids.Jaw, 10, 4)
	bone("Tongue", "Jaw", jaw + Vector3(0, -0.018, -0.125))
	geo.ellipsoid(rest_positions.Tongue + Vector3(0, -0.042, -0.035), Vector3(0.063, 0.066, 0.025), Color("ed7080"), ids.Tongue, 8, 5)
	skeleton.reset_bone_poses()
	skin_mesh = MeshInstance3D.new()
	skin_mesh.name = "MonkeySkin"
	skin_mesh.mesh = geo.finish()
	skin_mesh.skeleton = NodePath("../Skeleton3D")
	skin_mesh.skin = skeleton.create_skin_from_rest_transforms()
	skin_mesh.extra_cull_margin = 20.0
	add_child(skin_mesh)
	create_base_animation()

func limb_mesh(geo: SkinGeometry, a: Vector3, b: Vector3, c: Vector3, upper: int, lower: int, end: int, radius: float, color: Color) -> void:
	geo.tube([a, a.lerp(b, 0.22), a.lerp(b, 0.80), b, b.lerp(c, 0.20), b.lerp(c, 0.80), c], [radius, radius * 0.96, radius * 0.79, radius * 0.76, radius * 0.72, radius * 0.55, radius * 0.49], [[[upper], [1.0]], [[upper], [1.0]], [[upper, lower], [0.85, 0.15]], [[upper, lower], [0.5, 0.5]], [[upper, lower], [0.15, 0.85]], [[lower], [1.0]], [[lower, end], [0.25, 0.75]]], color)

func create_base_animation() -> void:
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.root_node = NodePath("..")
	add_child(player)
	var animation := Animation.new()
	animation.length = 3.6
	animation.loop_mode = Animation.LOOP_LINEAR
	var track := animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(track, NodePath("Skeleton3D:Neck"))
	animation.rotation_track_insert_key(track, 0, Quaternion(Vector3.RIGHT, -0.015))
	animation.rotation_track_insert_key(track, 1.8, Quaternion(Vector3.RIGHT, 0.015))
	animation.rotation_track_insert_key(track, 3.6, Quaternion(Vector3.RIGHT, -0.015))
	var lib := AnimationLibrary.new()
	lib.add_animation("breathing", animation)
	player.add_animation_library("", lib)
