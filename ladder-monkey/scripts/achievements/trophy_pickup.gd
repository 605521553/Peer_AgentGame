class_name TrophyPickup
extends Area3D
signal collected(trophy: TrophyPickup)
const PLAYER_LAYER: int = 1 << 5
const PICKUP_LAYER: int = 1 << 6
var profile: AchievementProfile
var award_id: int
var award_name: String
var award_height: float
var claimed: bool = false
var visual: Node3D
var phase: float = 0.0
var anchor := Vector3.ZERO

func _ready() -> void:
	collision_layer = PICKUP_LAYER
	collision_mask = PLAYER_LAYER
	monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = profile.pickup_radius
	shape.shape = sphere
	add_child(shape)
	visual = TrophyModel.build(profile.fragment_count)
	add_child(visual)
	anchor = position
	phase = award_id * 1.31
	area_entered.connect(_on_area_entered)

func _process(delta: float) -> void:
	if claimed:
		return
	phase += delta * profile.float_frequency
	position = anchor + Vector3.UP * sin(phase) * profile.float_amplitude
	visual.rotation.y += delta * profile.rotation_speed

func _on_area_entered(area: Area3D) -> void:
	if claimed or not area.is_in_group("monkey_reward_probe"):
		return
	# Latch before emitting: repeated overlaps in the same physics frame are safe.
	claimed = true
	set_process(false)
	set_deferred("monitoring", false)
	collected.emit(self)
	visual.hide()
	# Manager copies the meshes to physics bodies after the query flush, then
	# frees this pickup. Keeping it alive until then preserves exact transforms.
