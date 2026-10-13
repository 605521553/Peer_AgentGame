class_name MonkeyLadder
extends Node3D
@export var rung_spacing: float = 0.42
@export var rung_count: int = 34
@export var width: float = 1.24
@export var first_rung_height: float = 0.20
@export var rung_radius: float = 0.045

func _ready() -> void:
	var wood := material(Color("bb8152"))
	var edge := material(Color("724530"))
	var brass := material(Color("d8bb76"))
	var height := first_rung_height + (rung_count - 1) * rung_spacing + 0.36
	for side in [-1.0, 1.0]:
		box("Rail", Vector3(0.11, height, 0.13), Vector3(side * width * 0.5, height * 0.5, 0), wood)
		box("RailEdge", Vector3(0.023, height, 0.018), Vector3(side * width * 0.5 + 0.043, height * 0.5, 0.073), edge)
	for i in rung_count:
		var y := first_rung_height + i * rung_spacing
		var mesh := CylinderMesh.new()
		mesh.top_radius = rung_radius
		mesh.bottom_radius = rung_radius
		mesh.height = width + 0.045
		mesh.radial_segments = 8
		var rung := MeshInstance3D.new()
		rung.name = "Rung_%02d" % i
		rung.mesh = mesh
		rung.material_override = wood
		rung.rotation.z = PI * 0.5
		rung.position.y = y
		add_child(rung)
		for side in [-1.0, 1.0]:
			box("RungBolt", Vector3(0.035, 0.035, 0.015), Vector3(side * width * 0.5, y, 0.077), brass)

func contact(limb: String, rung: int) -> Vector3:
	var hand := limb.ends_with("H")
	var side := -1.0 if limb.begins_with("L") else 1.0
	# Hand origin is the bar centre; curved fingers wrap its circumference.
	# Foot origin is the sole, precisely on the top of the bar.
	return to_global(Vector3(side * (0.39 if hand else 0.25), first_rung_height + rung * rung_spacing + (0.0 if hand else rung_radius), 0.0))

func material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	return mat

func box(label: String, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = mat
	add_child(node)
	return node
