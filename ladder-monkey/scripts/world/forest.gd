class_name MonkeyForest
extends Node3D
## Deterministic, original low-poly scenery; no downloaded dependencies.
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed = 32781
	var earth := mat(Color("a19a65"))
	var stone := mat(Color("687d72"))
	var bark := mat(Color("675541"))
	var leaves := mat(Color("49785e"))
	var dark_leaves := mat(Color("315c50"))
	var sand := mat(Color("cab387"))
	var water := mat(Color("427b79"))
	var ground := CylinderMesh.new()
	ground.top_radius = 4.6
	ground.bottom_radius = 5.0
	ground.height = 0.44
	ground.radial_segments = 16
	add_mesh("ForestIsland", ground, Vector3(0, -0.25, 0), earth)
	var pond := CylinderMesh.new()
	pond.top_radius = 65.0
	pond.bottom_radius = 65.0
	pond.height = 0.05
	pond.radial_segments = 32
	add_mesh("QuietWater", pond, Vector3(0, -0.50, 0), water)
	for i in 14:
		var angle := TAU * i / 14.0
		var at := Vector3(cos(angle) * 4.5, -0.15, sin(angle) * 4.5)
		rock(at, Vector3(0.55, 0.31, 0.47), stone)
	# A narrow clearing keeps all contact points visible from the fixed camera.
	for i in 9:
		var z := -2.3 - float(i % 3) * 2.7
		var x := (-1.0 if i % 2 == 0 else 1.0) * (2.8 + float(i % 4) * 1.2)
		tree(Vector3(x, -0.35, z), rng.randf_range(8.0, 14.0), bark, leaves if i % 2 == 0 else dark_leaves)
	for i in 28:
		var angle := rng.randf_range(0, TAU)
		var radius := rng.randf_range(1.8, 4.2)
		var at := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		if at.z > 1.0 and at.x > 0.0:
			continue
		fern(at, leaves if i % 2 == 0 else dark_leaves)
	for i in 13:
		rock(Vector3(rng.randf_range(-3.8, 3.8), 0.03, rng.randf_range(-3.8, -0.8)), Vector3(0.20, 0.12, 0.17) * rng.randf_range(0.7, 2.0), stone)
	var path := BoxMesh.new()
	path.size = Vector3(1.45, 0.022, 1.5)
	add_mesh("LadderClearing", path, Vector3(0, -0.01, 0.40), sand)
	# A distant canopy landing explains the long vertical ladder.
	var platform := BoxMesh.new()
	platform.size = Vector3(3.0, 0.16, 1.7)
	add_mesh("CanopyLanding", platform, Vector3(0, 14.18, -0.65), bark)
	for x in [-1.4, 1.4]:
		var post := BoxMesh.new()
		post.size = Vector3(0.10, 1.0, 0.10)
		add_mesh("LandingPost", post, Vector3(x, 14.75, -1.35), bark)
	var beam := BoxMesh.new()
	beam.size = Vector3(3.0, 0.08, 0.08)
	add_mesh("LandingRailing", beam, Vector3(0, 15.15, -1.35), bark)
	var light := DirectionalLight3D.new()
	light.name = "WarmSun"
	light.rotation_degrees = Vector3(-48, -35, 0)
	light.light_color = Color("ffe0b0")
	light.light_energy = 1.05
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 24.0
	add_child(light)
	var env_node := WorldEnvironment.new()
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("527a77")
	sky_mat.sky_horizon_color = Color("c6c9a7")
	sky_mat.ground_bottom_color = Color("4a675b")
	sky_mat.ground_horizon_color = Color("c6c9a7")
	sky_mat.sun_angle_max = 5.0
	sky.sky_material = sky_mat
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("a1b5b7")
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.fog_enabled = true
	environment.fog_light_color = Color("90aba0")
	environment.fog_density = 0.009
	env_node.environment = environment
	add_child(env_node)

func mat(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 1.0
	return result

func add_mesh(label: String, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	add_child(instance)
	return instance

func rock(at: Vector3, scale_vec: Vector3, material: Material) -> void:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 7
	sphere.rings = 3
	var instance := add_mesh("RiverStone", sphere, at, material)
	instance.scale = scale_vec * 2.0
	instance.rotation.y = rng.randf_range(0, TAU)

func tree(at: Vector3, height: float, bark: Material, leaves: Material) -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.23
	trunk.bottom_radius = 0.44
	trunk.height = height
	trunk.radial_segments = 7
	add_mesh("JungleTrunk", trunk, at + Vector3(0, height * 0.5, 0), bark)
	for i in 3:
		var canopy := SphereMesh.new()
		canopy.radial_segments = 8
		canopy.rings = 4
		var instance := add_mesh("Canopy", canopy, at + Vector3((i - 1) * 1.3, height - 0.3 + i * 0.5, 0), leaves)
		instance.scale = Vector3(4.2, 2.6, 3.9)

func fern(at: Vector3, material: Material) -> void:
	for i in 5:
		var blade := PrismMesh.new()
		blade.size = Vector3(0.15, rng.randf_range(0.30, 0.65), 0.38)
		var instance := add_mesh("Fern", blade, at + Vector3(0, 0.14, 0), material)
		instance.rotation = Vector3(0.4, TAU * i / 5.0, 0.35)
