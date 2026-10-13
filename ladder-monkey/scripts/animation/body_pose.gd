class_name MonkeyBodyPose
extends SkeletonModifier3D
## Base AnimationPlayer -> body/face pose -> four independent limb modifiers.
var controller: MonkeyClimbController
var rig: MonkeyRig
var final_pelvis := Vector3.ZERO
var maximum_reach_correction: float = 0.0

func _process_modification_with_delta(_delta: float) -> void:
	if controller == null or not controller.initialized:
		return
	var sk := get_skeleton()
	var turn := controller.taunt_blend
	var sway := sin(PI * controller.phase) * sin(PI * controller.phase) if controller.step_running else 0.0
	var side := -1.0 if controller.active_pair == 0 else 1.0
	var hip_basis := Basis(Vector3.UP, -0.10 * turn) * Basis(Vector3.FORWARD, side * 0.028 * sway)
	var spine_basis := hip_basis * Basis(Vector3.UP, -0.43 * turn) * Basis(Vector3.RIGHT, -0.065 + 0.035 * sway * controller.step_direction)
	var chest_basis := spine_basis * Basis(Vector3.UP, -0.90 * turn) * Basis(Vector3.FORWARD, side * 0.055 * sway)
	var neck_base := sk.get_bone_pose_rotation(rig.ids.Neck)
	var neck_basis := chest_basis * Basis(Vector3.UP, -0.48 * turn) * Basis(neck_base)
	var play := controller.expression * sin(controller.clock * 8.0) * 0.028
	var head_basis := neck_basis * Basis(Vector3.UP, -0.72 * turn) * Basis(Vector3.FORWARD, turn * 0.11 + play)
	var hips := rig.to_local(controller.pelvis)
	# Before solving IK, move the torso into the intersection of reachable
	# spheres. This preserves segment lengths and does not move contact points.
	var desired := hips
	for iteration in 6:
		for limb: String in MonkeyClimbController.LIMBS:
			if limb == "RH" and turn > 0.1:
				continue
			var is_hand := limb.ends_with("H")
			var label := ("Left" if limb.begins_with("L") else "Right") + ("Arm" if is_hand else "Leg")
			var origin: Vector3
			if is_hand:
				var chest_at: Vector3 = hips + hip_basis * sk.get_bone_rest(rig.ids.Spine).origin + spine_basis * sk.get_bone_rest(rig.ids.Chest).origin
				origin = chest_at + chest_basis * sk.get_bone_rest(rig.ids[label]).origin
			else:
				origin = hips + hip_basis * sk.get_bone_rest(rig.ids[label]).origin
			var target: Vector3 = sk.to_local(controller.targets[limb].position)
			var reach: float = (controller.profile.arm_upper_length + controller.profile.arm_lower_length if is_hand else controller.profile.leg_upper_length + controller.profile.leg_lower_length) * 0.975
			var distance := origin.distance_to(target)
			if distance > reach:
				hips += (target - origin).normalized() * (distance - reach)
	maximum_reach_correction = maxf(maximum_reach_correction, hips.distance_to(desired))
	final_pelvis = sk.to_global(hips)
	sk.set_bone_global_pose(rig.ids.Root, Transform3D.IDENTITY)
	sk.set_bone_global_pose(rig.ids.Hips, Transform3D(hip_basis, hips))
	set_child(sk, "Spine", spine_basis)
	set_child(sk, "Chest", chest_basis)
	set_child(sk, "Neck", neck_basis)
	set_child(sk, "Head", head_basis)
	for i in 7:
		var label := "Tail%d" % i
		var parent := sk.get_bone_parent(rig.ids[label])
		var previous := sk.get_bone_global_pose(parent)
		var wave := sin(controller.clock * 2.4 - i * 0.62) * (0.035 + sway * 0.035 + turn * 0.06)
		set_child(sk, label, previous.basis * Basis(Vector3.UP, wave) * Basis(Vector3.RIGHT, wave * 0.40))
	apply_face(sk)
	if controller.state >= MonkeyClimbController.State.TauntTurn:
		var head := sk.get_bone_global_pose(rig.ids.Head)
		var cheek := sk.to_global(head * Vector3(0.21, 0.12, -0.32))
		var blend := MonkeyClimbController.smooth5(MonkeyClimbController.window(turn, 0.0, 0.92))
		controller.targets.RH.position = controller.turn_anchor.lerp(cheek, blend) + Vector3(0.12, 0.06, 0.28) * sin(PI * blend) * sin(PI * blend)
		controller.targets.RH.basis = Basis.IDENTITY.slerp(head.basis * Basis(Vector3.RIGHT, -0.25), blend)

func set_child(sk: Skeleton3D, label: String, basis: Basis) -> void:
	var index: int = rig.ids[label]
	var parent := sk.get_bone_global_pose(sk.get_bone_parent(index))
	sk.set_bone_global_pose(index, Transform3D(basis, parent * sk.get_bone_rest(index).origin))

func apply_face(sk: Skeleton3D) -> void:
	var e := controller.expression
	for side_label in ["Left", "Right"]:
		var index: int = rig.ids[side_label + "Eye"]
		var rest := sk.get_bone_rest(index)
		var squint := 1.0 - e * (0.68 if side_label == "Right" else -0.12)
		sk.set_bone_pose_scale(index, Vector3(1.0, squint, 1.0))
		var brow: int = rig.ids[side_label + "Brow"]
		sk.set_bone_pose_rotation(brow, Quaternion(Vector3.FORWARD, e * (0.30 if side_label == "Left" else -0.42)))
		sk.set_bone_pose_position(brow, sk.get_bone_rest(brow).origin + Vector3(0, e * (0.027 if side_label == "Left" else -0.025), 0))
		sk.set_bone_pose_position(rig.ids[side_label + "Pupil"], sk.get_bone_rest(rig.ids[side_label + "Pupil"]).origin + Vector3(e * 0.013, -e * 0.007, 0))
	sk.set_bone_pose_rotation(rig.ids.Jaw, Quaternion(Vector3.RIGHT, e * 0.24))
	sk.set_bone_pose_position(rig.ids.Jaw, sk.get_bone_rest(rig.ids.Jaw).origin + Vector3(0, -e * 0.045, 0))
	sk.set_bone_pose_scale(rig.ids.Tongue, Vector3.ONE * maxf(0.001, e))
	sk.set_bone_pose_rotation(rig.ids.Tongue, Quaternion(Vector3.FORWARD, e * 0.15 * sin(controller.clock * 8.0)))
