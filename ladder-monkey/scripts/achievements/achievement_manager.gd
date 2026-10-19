class_name MonkeyAchievements
extends Node3D
signal achievement_collected(award_id: int, award_name: String)
var profile: AchievementProfile = preload("res://resources/achievement_profile.tres")
var controller: MonkeyClimbController
var body_pose: MonkeyBodyPose
var ladder: MonkeyLadder
var toast: AchievementToast
var debris: TrophyDebris
var body_probe: Area3D
var head_probe_shape: CollisionShape3D
var generated_ids: Dictionary = {}
var collected_ids: Dictionary = {}
var live_trophies: Dictionary = {}
var planned_heights: Array[float] = []

func setup(climb: MonkeyClimbController, pose: MonkeyBodyPose, bars: MonkeyLadder, display: AchievementToast, last_solver: MonkeyLimbIK) -> void:
	controller = climb
	body_pose = pose
	ladder = bars
	toast = display
	debris = TrophyDebris.new()
	debris.name = "TrophyFragments"
	debris.profile = profile
	add_child(debris)
	create_body_probe()
	create_debris_scenery()
	last_solver.modification_processed.connect(update_body_probe)
	var top := ladder.first_rung_height + (ladder.rung_count - 1) * ladder.rung_spacing - 0.30
	var interval := maxf(profile.height_interval, 0.1)
	var height := profile.first_height
	while height <= top:
		planned_heights.append(height)
		height += interval
	spawn_nearby()

func _process(_delta: float) -> void:
	if controller != null:
		spawn_nearby()

func create_body_probe() -> void:
	body_probe = Area3D.new()
	body_probe.name = "MonkeyBodyTrigger"
	body_probe.collision_layer = TrophyPickup.PLAYER_LAYER
	body_probe.collision_mask = 0
	body_probe.monitoring = false
	body_probe.add_to_group("monkey_reward_probe")
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.19
	capsule.height = 0.76
	shape.shape = capsule
	body_probe.add_child(shape)
	# The large cartoon head reaches the cup before the chest. Include it so
	# a trophy cannot pass visibly through the head while awaiting torso contact.
	head_probe_shape = CollisionShape3D.new()
	var head_sphere := SphereShape3D.new()
	head_sphere.radius = 0.30
	head_probe_shape.shape = head_sphere
	head_probe_shape.position = Vector3(0, 0.73, 0)
	body_probe.add_child(head_probe_shape)
	add_child(body_probe)
	body_probe.global_position = controller.pelvis + Vector3(0, 0.13, 0)

func update_body_probe() -> void:
	# Read the final posed pelvis, including reach compensation. The static
	# MonkeyRig node never moves, so a trigger attached to that root is wrong.
	body_probe.global_position = body_pose.final_pelvis + Vector3(0, 0.13, 0)
	var skeleton := controller.rig.skeleton
	var head := skeleton.global_transform * skeleton.get_bone_global_pose(controller.rig.ids.Head)
	head_probe_shape.global_position = head * Vector3(0, 0.13, 0)

func spawn_nearby() -> void:
	for i in planned_heights.size():
		if generated_ids.has(i) or collected_ids.has(i):
			continue
		if planned_heights[i] > controller.pelvis.y - ladder.global_position.y + profile.spawn_ahead_distance:
			continue
		var trophy := TrophyPickup.new()
		trophy.name = "HeightTrophy_%02d" % i
		trophy.profile = profile
		trophy.award_id = i
		trophy.award_height = planned_heights[i]
		trophy.award_name = profile.achievement_names[i % profile.achievement_names.size()] if not profile.achievement_names.is_empty() else "攀登成就"
		trophy.position = ladder.position + Vector3(0, planned_heights[i], profile.distance_from_ladder)
		trophy.collected.connect(on_trophy_collected)
		generated_ids[i] = true
		live_trophies[i] = trophy
		add_child(trophy)

func on_trophy_collected(trophy: TrophyPickup) -> void:
	if collected_ids.has(trophy.award_id):
		return
	collected_ids[trophy.award_id] = true
	live_trophies.erase(trophy.award_id)
	# Physics callbacks cannot add/remove collision shapes during query flush.
	finish_collection.call_deferred(trophy)

func finish_collection(trophy: TrophyPickup) -> void:
	if not is_instance_valid(trophy):
		return
	debris.burst(trophy)
	toast.enqueue(trophy.award_id, trophy.award_name, trophy.award_height)
	achievement_collected.emit(trophy.award_id, trophy.award_name)
	trophy.queue_free()

func create_debris_scenery() -> void:
	var solid := StaticBody3D.new()
	solid.name = "DebrisOnlyScenery"
	solid.collision_layer = TrophyDebris.SCENERY_LAYER
	solid.collision_mask = TrophyDebris.FRAGMENT_LAYER
	add_child(solid)
	var ground := CylinderShape3D.new()
	ground.radius = 4.6
	ground.height = 0.44
	add_solid_shape(solid, ground, Transform3D(Basis.IDENTITY, Vector3(0, -0.25, 0)))
	var height := ladder.first_rung_height + (ladder.rung_count - 1) * ladder.rung_spacing + 0.36
	for side in [-1.0, 1.0]:
		var rail := BoxShape3D.new()
		rail.size = Vector3(0.11, height, 0.13)
		add_solid_shape(solid, rail, ladder.transform * Transform3D(Basis.IDENTITY, Vector3(side * ladder.width * 0.5, height * 0.5, 0)))
	for i in ladder.rung_count:
		var rung := CylinderShape3D.new()
		rung.radius = ladder.rung_radius
		rung.height = ladder.width + 0.045
		add_solid_shape(solid, rung, ladder.transform * Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, ladder.first_rung_height + i * ladder.rung_spacing, 0)))
	var landing := BoxShape3D.new()
	landing.size = Vector3(3.0, 0.16, 1.7)
	add_solid_shape(solid, landing, Transform3D(Basis.IDENTITY, Vector3(0, 14.18, -0.65)))

func add_solid_shape(solid: StaticBody3D, resource: Shape3D, at: Transform3D) -> void:
	var shape := CollisionShape3D.new()
	shape.shape = resource
	shape.transform = at
	solid.add_child(shape)
