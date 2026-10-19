class_name TrophyModel
extends RefCounted
## The intact trophy is assembled from the very same meshes that fly apart.
## Bowl walls have thickness and an open top, instead of a solid cone.

static func gold(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.65
	material.metallic = 0.28
	material.emission_enabled = true
	material.emission = color * 0.10
	return material

static func build(fragment_count: int) -> Node3D:
	var root := Node3D.new()
	root.name = "GoldenCup"
	var bright := gold(Color("ffd16b"))
	var shadow := gold(Color("ba772d"))
	var mid := gold(Color("e6a83b"))
	var sectors := clampi(fragment_count, 16, 48) - 9
	for i in sectors:
		var a := TAU * float(i) / sectors
		var b := TAU * float(i + 1) / sectors
		var points: Array[Vector3] = []
		for params in [Vector2(0.085, -0.025), Vector2(0.19, 0.22), Vector2(0.06, -0.015), Vector2(0.165, 0.22)]:
			for angle in [a, b]:
				points.append(Vector3(cos(angle) * params.x, params.y, sin(angle) * params.x))
		var center := Vector3.ZERO
		for point in points:
			center += point / points.size()
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for face in [[0, 2, 3, 1], [4, 5, 7, 6], [2, 6, 7, 3], [0, 1, 5, 4], [0, 4, 6, 2], [1, 3, 7, 5]]:
			for j in [0, 2, 1, 0, 3, 2]:
				surface.add_vertex(points[face[j]] - center)
		surface.generate_normals()
		piece(root, "BowlShard%02d" % i, surface.commit(), center, bright if i % 3 == 0 else mid)
	var stem := CylinderMesh.new()
	stem.top_radius = 0.034
	stem.bottom_radius = 0.045
	stem.height = 0.16
	stem.radial_segments = 6
	piece(root, "Stem", stem, Vector3(0, -0.105, 0), bright)
	var base := BoxMesh.new()
	base.size = Vector3(0.24, 0.055, 0.19)
	piece(root, "Foot", base, Vector3(0, -0.215, 0), shadow)
	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 0.082
	floor_mesh.bottom_radius = 0.075
	floor_mesh.height = 0.025
	floor_mesh.radial_segments = 8
	piece(root, "BowlFloor", floor_mesh, Vector3(0, -0.025, 0), mid)
	for side in [-1.0, 1.0]:
		var path: Array[Vector3] = [Vector3(side * 0.17, 0.16, 0), Vector3(side * 0.30, 0.13, 0), Vector3(side * 0.29, 0.025, 0), Vector3(side * 0.12, -0.015, 0)]
		for j in 3:
			var bar := CylinderMesh.new()
			bar.top_radius = 0.021
			bar.bottom_radius = 0.021
			bar.height = path[j].distance_to(path[j + 1])
			bar.radial_segments = 5
			var node := piece(root, "Handle", bar, (path[j] + path[j + 1]) * 0.5, bright)
			node.quaternion = Quaternion(Vector3.UP, (path[j + 1] - path[j]).normalized())
	return root

static func piece(parent: Node3D, label: String, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = material
	node.position = at
	parent.add_child(node)
	return node
