extends SceneTree

func _initialize() -> void:
	for cls in ["SkeletonModifier3D", "Skeleton3D", "MeshInstance3D"]:
		print(cls)
		for method in ClassDB.class_get_method_list(cls, true):
			if "modification" in method.name or "bone" in method.name or "skin" in method.name or "advance" in method.name:
				print(method.name)
	quit()
