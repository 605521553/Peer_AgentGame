class_name SkinGeometry
extends RefCounted
## Original flat-shaded geometry with four skin weights per vertex.
## Tubes blend joint rings so elbows, knees, spine and tail deform.
var vertices := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var bones := PackedInt32Array()
var weights := PackedFloat32Array()

func triangle(a: Vector3, b: Vector3, c: Vector3, color: Color, binding: Array) -> void:
	var normal := (b - a).cross(c - a).normalized()
	if normal.length_squared() < 0.01:
		return
	# Godot uses clockwise front faces. Retain the outward geometric normal
	# while reversing storage order (otherwise double-sided lighting flips it).
	for i in [0, 2, 1]:
		vertices.append([a, b, c][i])
		normals.append(normal)
		colors.append(color)
		var ids: Array = binding[i][0]
		var amounts: Array = binding[i][1]
		for j in 4:
			bones.append(ids[j] if j < ids.size() else 0)
			weights.append(amounts[j] if j < amounts.size() else 0.0)

func ellipsoid(center: Vector3, radius: Vector3, color: Color, bone: int, sides: int = 10, rings: int = 6, blend_bone: int = -1) -> void:
	for r in rings:
		for s in sides:
			var points: Array[Vector3] = []
			var binds: Array = []
			for pair in [Vector2i(r, s), Vector2i(r + 1, s), Vector2i(r + 1, s + 1), Vector2i(r, s + 1)]:
				var phi := PI * float(pair.x) / rings
				var theta := TAU * float(pair.y) / sides
				points.append(center + Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta)) * radius)
				var t := clampf((cos(phi) + 1.0) * 0.5, 0.0, 1.0)
				binds.append([[bone, blend_bone], [1.0 - t, t]] if blend_bone >= 0 else [[bone], [1.0]])
			var shade := color * (0.95 + 0.05 * sin(float(s * 7 + r * 13)))
			shade.a = 1.0
			triangle(points[0], points[2], points[1], shade, [binds[0], binds[2], binds[1]])
			triangle(points[0], points[3], points[2], shade, [binds[0], binds[3], binds[2]])

func tube(path: Array[Vector3], radii: Array[float], bindings: Array, color: Color, sides: int = 8) -> void:
	var loops: Array = []
	for i in path.size():
		var tangent: Vector3
		if i == 0:
			tangent = path[1] - path[0]
		elif i == path.size() - 1:
			tangent = path[i] - path[i - 1]
		else:
			tangent = path[i + 1] - path[i - 1]
		tangent = tangent.normalized()
		var axis := Vector3.FORWARD if absf(tangent.dot(Vector3.FORWARD)) < 0.92 else Vector3.RIGHT
		var u := tangent.cross(axis).normalized()
		var v := tangent.cross(u).normalized()
		var loop: Array[Vector3] = []
		for j in sides:
			var angle := TAU * float(j) / sides
			loop.append(path[i] + radii[i] * (u * cos(angle) + v * sin(angle)))
		loops.append(loop)
	for i in path.size() - 1:
		for j in sides:
			var k := (j + 1) % sides
			triangle(loops[i][j], loops[i + 1][k], loops[i + 1][j], color, [bindings[i], bindings[i + 1], bindings[i + 1]])
			triangle(loops[i][j], loops[i][k], loops[i + 1][k], color, [bindings[i], bindings[i], bindings[i + 1]])
	for j in sides:
		var k := (j + 1) % sides
		triangle(path[0], loops[0][k], loops[0][j], color, [bindings[0], bindings[0], bindings[0]])
		triangle(path[-1], loops[-1][j], loops[-1][k], color, [bindings[-1], bindings[-1], bindings[-1]])

func finish() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mesh.surface_set_material(0, mat)
	return mesh
