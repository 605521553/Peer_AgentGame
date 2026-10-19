extends RefCounted
## CPU greedy meshing: invisible interior faces removed, colors never quantized.

static func voxel_data(model: Dictionary) -> Dictionary:
	var cells: Dictionary = {}
	for c in model.get("cells", []):
		cells[Vector3i(int(c[0]), int(c[1]), int(c[2]))] = int(c[3])
	return cells

static func build(model: Dictionary, tree: SceneTree) -> Array:
	var started := Time.get_ticks_usec()
	var cells := voxel_data(model)
	var size := Vector3i(int(model.size[0]), int(model.size[1]), int(model.size[2]))
	var colors: Array[Color] = []
	for value in model.palette:
		colors.append(Color(value))
	var meshes: Array = []
	var total_quads := 0
	var slice_started := Time.get_ticks_usec()
	# Each 16^3 region is independent, but face visibility looks outside the region.
	for bx in range(0, size.x, 16):
		for by in range(0, size.y, 16):
			for bz in range(0, size.z, 16):
				var lower := Vector3i(bx, by, bz)
				var upper := Vector3i(mini(bx+16, size.x), mini(by+16, size.y), mini(bz+16, size.z))
				var vertices := PackedVector3Array()
				var normals := PackedVector3Array()
				var vertex_colors := PackedColorArray()
				var indices := PackedInt32Array()
				for axis in range(3):
					var u := (axis + 1) % 3
					var v := (axis + 2) % 3
					for direction in [-1, 1]:
						var normal := Vector3.ZERO
						normal[axis] = float(direction)
						var neighbor := Vector3i.ZERO
						neighbor[axis] = direction
						for plane in range(lower[axis], upper[axis]):
							var mask: Dictionary = {}
							for i in range(lower[u], upper[u]):
								for j in range(lower[v], upper[v]):
									var p := Vector3i.ZERO
									p[axis] = plane
									p[u] = i
									p[v] = j
									if cells.has(p) and not cells.has(p+neighbor):
										mask[Vector2i(i,j)] = cells[p]
							for j in range(lower[v], upper[v]):
								for i in range(lower[u], upper[u]):
									var key := Vector2i(i,j)
									if not mask.has(key):
										continue
									var color_index: int = mask[key]
									var width := 1
									while i+width < upper[u] and mask.get(Vector2i(i+width,j), -1) == color_index:
										width += 1
									var height := 1
									var growing := true
									while j+height < upper[v] and growing:
										for dx in range(width):
											if mask.get(Vector2i(i+dx,j+height), -1) != color_index:
												growing = false
												break
										if growing:
											height += 1
									for dx in range(width):
										for dy in range(height):
											mask.erase(Vector2i(i+dx,j+dy))
									var a := Vector3.ZERO
									a[axis] = float(plane + (1 if direction > 0 else 0))
									a[u] = float(i)
									a[v] = float(j)
									var du := Vector3.ZERO
									var dv := Vector3.ZERO
									du[u] = width
									dv[v] = height
									var base := vertices.size()
									vertices.append_array(PackedVector3Array([a,a+du,a+du+dv,a+dv]))
									for _corner in range(4):
										normals.append(normal)
										vertex_colors.append(colors[color_index])
									var winding: Array = [0,2,1,0,3,2] if direction > 0 else [0,1,2,0,2,3]
									for index in winding:
										indices.append(base+index)
									total_quads += 1
							# Single-thread Web stays responsive with a 3 ms CPU work slice.
							if Time.get_ticks_usec()-slice_started > 3000:
								await tree.process_frame
								slice_started = Time.get_ticks_usec()
					if not vertices.is_empty():
						var arrays: Array = []
						arrays.resize(Mesh.ARRAY_MAX)
						arrays[Mesh.ARRAY_VERTEX] = vertices
						arrays[Mesh.ARRAY_NORMAL] = normals
						arrays[Mesh.ARRAY_COLOR] = vertex_colors
						arrays[Mesh.ARRAY_INDEX] = indices
						var mesh := ArrayMesh.new()
						mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
						meshes.append(mesh)
	return [meshes,total_quads, float(Time.get_ticks_usec()-started)/1000.0]

static func raycast(origin: Vector3, direction: Vector3, model: Dictionary, cells: Dictionary) -> Variant:
	var size := Vector3(float(model.size[0]),float(model.size[1]),float(model.size[2]))
	var start = AABB(Vector3.ZERO,size).intersects_ray(origin,direction)
	if start == null:
		return null
	var point: Vector3 = start + direction*0.0001
	for _step in range(128):
		var cell := Vector3i(floori(point.x),floori(point.y),floori(point.z))
		if cell.x < 0 or cell.y < 0 or cell.z < 0 or cell.x >= size.x or cell.y >= size.y or cell.z >= size.z:
			return null
		if cells.has(cell):
			return {"voxel": [cell.x,cell.y,cell.z], "point": point}
		var distance := INF
		for axis in range(3):
			if absf(direction[axis]) > 0.000001:
				var boundary: float = cell[axis] + (1 if direction[axis] > 0 else 0)
				distance = minf(distance,(boundary-point[axis])/direction[axis])
		point += direction*(distance+0.0001)
	return null
