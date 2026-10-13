class_name MonkeyCamera
extends Camera3D
var controller: MonkeyClimbController
var follow_height: float = 1.675
@export var offset := Vector3(2.65, 1.40, 4.45)
@export var follow_response: float = 5.0

func _ready() -> void:
	fov = 39.0
	near = 0.08
	far = 90.0
	current = true

func _process(delta: float) -> void:
	if controller == null:
		return
	follow_height = lerpf(follow_height, controller.support_height if not controller.step_running else controller.pelvis.y, 1.0 - exp(-follow_response * delta))
	global_position = Vector3(0, follow_height, 0) + offset
	look_at(Vector3(0, follow_height + 0.30, 0.18), Vector3.UP)
