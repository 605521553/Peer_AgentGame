class_name TrophyDebris
extends Node3D
## Shards collide with scenery only. No forces can reach the monkey or IK.
const SCENERY_LAYER: int = 1 << 3
const FRAGMENT_LAYER: int = 1 << 4
var profile: AchievementProfile
var rng := RandomNumberGenerator.new()
var active: Array[Dictionary] = []
var spawned_count: int = 0
var cleaned_count: int = 0
var collision_count: int = 0
var peak_active: int = 0

func _ready() -> void:
	rng.randomize()

func burst(trophy: TrophyPickup) -> void:
	var origin := trophy.global_position
	for part: MeshInstance3D in trophy.visual.get_children():
		while active.size() >= profile.max_active_fragments:
			remove_fragment(0)
		var body := RigidBody3D.new()
		body.name = "GoldFragment"
		body.collision_layer = FRAGMENT_LAYER
		body.collision_mask = SCENERY_LAYER
		body.mass = 0.035
		body.linear_damp = 0.08
		body.angular_damp = 0.18
		body.continuous_cd = true
		body.contact_monitor = true
		body.max_contacts_reported = 4
		var physics := PhysicsMaterial.new()
		physics.bounce = profile.bounce
		physics.friction = 0.65
		body.physics_material_override = physics
		var mesh := MeshInstance3D.new()
		mesh.mesh = part.mesh
		mesh.material_override = part.material_override
		body.add_child(mesh)
		var shape := CollisionShape3D.new()
		shape.shape = part.mesh.create_convex_shape()
		shape.shape.margin = 0.002
		body.add_child(shape)
		add_child(body)
		body.global_transform = part.global_transform
		var direction := body.global_position - origin
		direction.y = 0.0
		if direction.length_squared() < 0.0001:
			direction = Vector3(cos(rng.randf() * TAU), 0, sin(rng.randf() * TAU))
		direction = direction.normalized()
		body.linear_velocity = direction * profile.burst_speed * rng.randf_range(0.65, 1.15) + Vector3.UP * profile.upward_speed * rng.randf_range(0.5, 1.2)
		body.angular_velocity = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * profile.angular_speed
		body.body_entered.connect(_on_fragment_collision)
		active.append({"body": body, "mesh": mesh, "age": 0.0})
		spawned_count += 1
	peak_active = maxi(peak_active, active.size())

func _on_fragment_collision(_other: Node) -> void:
	collision_count += 1

func _physics_process(delta: float) -> void:
	for i in range(active.size() - 1, -1, -1):
		active[i].age += delta
		if active[i].age >= profile.fragment_lifetime:
			remove_fragment(i)
		else:
			var fade := minf(profile.fragment_fade_duration, profile.fragment_lifetime)
			var remaining: float = profile.fragment_lifetime - active[i].age
			if fade > 0.0 and remaining < fade:
				active[i].mesh.scale = Vector3.ONE * maxf(0.01, remaining / fade)

func remove_fragment(index: int) -> void:
	var body: RigidBody3D = active[index].body
	if is_instance_valid(body):
		body.queue_free()
	active.remove_at(index)
	cleaned_count += 1
