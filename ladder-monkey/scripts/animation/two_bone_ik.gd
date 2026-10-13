class_name MonkeyLimbIK
extends SkeletonModifier3D
## Analytic two-bone solve with a stable anatomical pole and exact end basis.
## Implemented via the supported 4.7.2 SkeletonModifier3D callback, without
## deprecated SkeletonIK3D or global pose override APIs.
var controller: MonkeyClimbController
var rig: MonkeyRig
var limb: String
var upper: int
var lower: int
var end: int
var length_a: float
var length_b: float
var rest_a := Vector3.ZERO
var rest_b := Vector3.ZERO
var maximum_error: float = 0.0
var contact_error: float = 0.0
var maximum_length_error: float = 0.0
var solve_count: int = 0
var clamped_count: int = 0
var actual_end := Vector3.ZERO
var actual_joint := Vector3.ZERO
var joint_angle: float = 0.0

func setup(monkey: MonkeyRig, climb: MonkeyClimbController, key: String) -> void:
	rig = monkey
	controller = climb
	limb = key
	var side := "Left" if limb.begins_with("L") else "Right"
	var hand := limb.ends_with("H")
	upper = rig.ids[side + ("Arm" if hand else "Leg")]
	lower = rig.ids[side + ("Forearm" if hand else "Shin")]
	end = rig.ids[side + ("Hand" if hand else "Foot")]
	rest_a = rig.skeleton.get_bone_rest(lower).origin
	rest_b = rig.skeleton.get_bone_rest(end).origin
	length_a = rest_a.length()
	length_b = rest_b.length()
	influence = controller.profile.ik_weight

func _process_modification_with_delta(_delta: float) -> void:
	if controller == null or not controller.initialized:
		return
	var sk := get_skeleton()
	var root_pose := sk.get_bone_global_pose(upper)
	var start := root_pose.origin
	var target: Vector3 = sk.to_local(controller.targets[limb].position)
	var vector := target - start
	var raw_distance := vector.length()
	var distance := clampf(raw_distance, absf(length_a - length_b) + 0.005, length_a + length_b - 0.001)
	var forward := vector.normalized()
	# Pole remains in skeleton/world space even when the torso twists. Elbows
	# bend out and back; knees point toward the front of the monkey / ladder.
	var side := -1.0 if limb.begins_with("L") else 1.0
	var pole := Vector3(side * 0.70, -0.22, 0.85) if limb.ends_with("H") else Vector3(side * 0.22, 0.08, -1.0)
	var projected := pole - forward * pole.dot(forward)
	if projected.length_squared() < 0.0001:
		projected = Vector3.RIGHT - forward * forward.x
	var bend := projected.normalized()
	var along := (length_a * length_a - length_b * length_b + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(0.0, length_a * length_a - along * along))
	var joint := start + forward * along + bend * height
	var solved_end := start + forward * distance
	var upper_basis := Basis(Quaternion(rest_a.normalized(), (joint - start).normalized()))
	var lower_basis := Basis(Quaternion(rest_b.normalized(), (solved_end - joint).normalized()))
	sk.set_bone_global_pose(upper, Transform3D(upper_basis, start))
	sk.set_bone_global_pose(lower, Transform3D(lower_basis, joint))
	var world_basis: Basis = controller.targets[limb].basis
	sk.set_bone_global_pose(end, Transform3D(sk.global_basis.inverse() * world_basis, solved_end))
	if limb.ends_with("H"):
		var side_label := "Left" if limb.begins_with("L") else "Right"
		var release: float = 1.0 - controller.targets[limb].grip
		for i in 4:
			sk.set_bone_pose_rotation(rig.ids[side_label + "Finger%d" % i], Quaternion(Vector3.RIGHT, release * -0.52))
			sk.set_bone_pose_rotation(rig.ids[side_label + "Finger%dTip" % i], Quaternion(Vector3.RIGHT, release * -0.42))
	actual_end = sk.to_global(solved_end)
	actual_joint = sk.to_global(joint)
	joint_angle = acos(clampf((start - joint).normalized().dot((solved_end - joint).normalized()), -1.0, 1.0))
	var error := actual_end.distance_to(controller.targets[limb].position)
	maximum_error = maxf(maximum_error, error)
	if not controller.targets[limb].moving:
		contact_error = maxf(contact_error, error)
	maximum_length_error = maxf(maximum_length_error, maxf(absf(start.distance_to(joint) - length_a), absf(joint.distance_to(solved_end) - length_b)))
	if absf(raw_distance - distance) > 0.002:
		clamped_count += 1
	solve_count += 1
