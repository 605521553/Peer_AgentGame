extends SceneTree

func _initialize() -> void:
	var rig := MonkeyRig.new()
	rig.name = "MonkeyRig"
	rig.build()
	assign_owner(rig, rig)
	var scene := PackedScene.new()
	scene.pack(rig)
	DirAccess.make_dir_recursive_absolute("res://assets")
	var error := ResourceSaver.save(scene, "res://assets/monkey_rig.tscn")
	print("Original skinned monkey saved: ", error, "; bones=", rig.skeleton.get_bone_count(), "; vertices=", rig.skin_mesh.mesh.surface_get_array_len(0))
	rig.free()
	quit(error)

func assign_owner(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		assign_owner(child, owner_node)
