extends SceneTree
const Mesher = preload("res://scripts/voxel_mesher.gd")
var failures: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)

func _run() -> void:
	var model := {"size":[2,1,1],"palette":["#FF0000","#0000FF"],"cells":[[0,0,0,0],[1,0,0,0]]}
	var output: Array = await Mesher.build(model,self)
	check(output[1] == 6,"Same-color adjacent cubes merge to six quads")
	model.cells[1][3] = 1
	output = await Mesher.build(model,self)
	check(output[1] == 10,"Two colors preserve boundary: ten external quads")
	var colors: Dictionary = {}
	for mesh in output[0]:
		var arrays: Array = mesh.surface_get_arrays(0)
		for color in arrays[Mesh.ARRAY_COLOR]: colors[color.to_html(false)] = true
	check(colors.size() == 2,"Vertex colors preserve both source colors")
	model = {"size":[20,1,1],"palette":["#00FF00"],"cells":[]}
	for x in range(20): model.cells.append([x,0,0,0])
	output = await Mesher.build(model,self)
	check(output[1] == 10,"Chunk border removes interior faces")
	var sparse := {"size":[3,3,1],"palette":["#888888"],"cells":[[0,0,0,0],[2,0,0,0],[0,1,0,0],[2,1,0,0],[0,2,0,0],[1,2,0,0],[2,2,0,0]]}
	var voxels := Mesher.voxel_data(sparse)
	check(Mesher.raycast(Vector3(1.5,1.5,5),Vector3(0,0,-1),sparse,voxels)==null,"Door opening is not selected as a solid block")
	var hit = Mesher.raycast(Vector3(0.5,1.5,5),Vector3(0,0,-1),sparse,voxels)
	check(hit != null and hit.voxel == [0,1,0],"Solid block selected with local voxel coordinate")
	print(JSON.stringify({"suite":"mesher","checks":6,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
