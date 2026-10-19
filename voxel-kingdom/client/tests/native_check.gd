extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var room_input: LineEdit = scene.get("room_input")
	room_input.text = "native-check-"+str(Time.get_unix_time_from_system()).replace(".","-")
	scene.call("_native_join")
	for _i in range(300):
		await process_frame
		if not str(scene.get("token")).is_empty(): break
	if str(scene.get("token")).is_empty():
		print("Native test failed: server join")
		quit(1)
		return
	var body: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/acceptance/deepseek-castle.json"))
	var command := {"schema_version":1,"rules_version":"stage-01-v1","command_id":"native-create","world_id":room_input.text,"type":"building.create","payload":{"position":[8,1,8],"rotation_y_quarter_turns":0,"blueprint":body}}
	var http: HTTPRequest = scene.get("action_http")
	http.request("http://127.0.0.1:8765/api/command",["Content-Type: application/json","Authorization: Bearer "+str(scene.get("token"))],HTTPClient.METHOD_POST,JSON.stringify(scene.call("wire_data",command)))
	scene.set("target",Vector3(14,1,14))
	scene.set("camera_size",30.0)
	await create_timer(3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/acceptance/native-client.png")
	var state: Dictionary = scene.get("state")
	var nodes: Dictionary = scene.get("nodes")
	print(JSON.stringify({"suite":"native","renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"entities":state.entities.size(),"rendered":nodes.size()}))
	quit(0 if state.entities.size()==1 and nodes.size()==1 else 1)
