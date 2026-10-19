extends Node3D

const Mesher = preload("res://scripts/voxel_mesher.gd")
var camera: Camera3D
var target := Vector3(32,1,32)
var yaw := -PI/4.0
var camera_size := 64.0
var state: Dictionary = {"entities":{},"assets":{},"players":[],"seq":0}
var player_id := ""
var rules_version := "stage-01-v1"
var selection: Dictionary = {}
var nodes: Dictionary = {}
var mesh_cache: Dictionary = {}
var cell_cache: Dictionary = {}
var queued: Dictionary = {}
var busy := false
var mesh_builds := 0
var node_rebuilds := 0
var material: StandardMaterial3D
var marker: MeshInstance3D
var zone_nodes: Array[MeshInstance3D] = []
var web := false
var elapsed := 0.0
var poll_time := 0.0
var frame_times: Array[float] = []
var mesh_times: Array[float] = []
var dragging := false
var last_mouse := Vector2.ZERO
var token := ""
var backend := "http://127.0.0.1:8765"
var socket := WebSocketPeer.new()
var reconnect_at := 0.0
var was_connected := false
var http: HTTPRequest
var action_http: HTTPRequest
var status_label: Label
var selection_label: Label
var chat_input: LineEdit
var room_input: LineEdit
var name_input: LineEdit

func _ready() -> void:
	web = OS.has_feature("web")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--server="):
			backend = argument.trim_prefix("--server=")
	material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.95
	_create_world()
	if not web:
		_native_ui()
	_update_camera()
	if web:
		JavaScriptBridge.eval("window.voxelReady=true; window.dispatchEvent(new Event('voxel-ready'));",true)

func _create_world() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#132126")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("#CBDDDF")
	environment.environment.ambient_light_energy = 0.75
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-30,0)
	light.light_energy = 1.0
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 180
	add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 500
	camera.current = true
	add_child(camera)
	for slot in range(4):
		var floor_node := MeshInstance3D.new()
		var floor_mesh := BoxMesh.new()
		floor_mesh.size = Vector3(64,1,64)
		floor_node.mesh = floor_mesh
		floor_node.position = Vector3((slot%2)*64+32,0.5,(slot/2)*64+32)
		var floor_mat := StandardMaterial3D.new()
		floor_mat.albedo_color = Color("#48624F") if slot%2 == 0 else Color("#445C4D")
		floor_mat.roughness = 1.0
		floor_node.material_override = floor_mat
		add_child(floor_node)
		zone_nodes.append(floor_node)
	var grid := ImmediateMesh.new()
	grid.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(0,129,4):
		grid.surface_add_vertex(Vector3(i,1.012,0))
		grid.surface_add_vertex(Vector3(i,1.012,128))
		grid.surface_add_vertex(Vector3(0,1.012,i))
		grid.surface_add_vertex(Vector3(128,1.012,i))
	grid.surface_end()
	var grid_node := MeshInstance3D.new()
	grid_node.mesh = grid
	var grid_material := StandardMaterial3D.new()
	grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_material.albedo_color = Color("#6B8069")
	grid_node.material_override = grid_material
	grid_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grid_node)
	for slot in range(4):
		var label := Label3D.new()
		label.text = "ZONE %02d" % (slot+1)
		label.position = Vector3((slot%2)*64+5,1.15,(slot/2)*64+7)
		label.rotation_degrees.x = -90
		label.pixel_size = 0.025
		label.font_size = 40
		label.modulate = Color("#CFE1C1")
		add_child(label)
	marker = MeshInstance3D.new()
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(1.04,0.04,1.04)
	marker.mesh = marker_mesh
	var marker_material := StandardMaterial3D.new()
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_material.albedo_color = Color("#E8D080")
	marker.material_override = marker_material
	marker.visible = false
	add_child(marker)

func _process(delta: float) -> void:
	elapsed += delta
	frame_times.append(delta*1000.0)
	if frame_times.size() > 240:
		frame_times.pop_front()
	if not _typing():
		var movement := Vector2.ZERO
		if Input.is_physical_key_pressed(KEY_W): movement.y -= 1
		if Input.is_physical_key_pressed(KEY_S): movement.y += 1
		if Input.is_physical_key_pressed(KEY_A): movement.x -= 1
		if Input.is_physical_key_pressed(KEY_D): movement.x += 1
		var forward := Vector3(-sin(yaw),0,-cos(yaw))
		var right := Vector3(cos(yaw),0,-sin(yaw))
		target += (right*movement.x-forward*movement.y)*camera_size*delta*0.55
		if Input.is_physical_key_pressed(KEY_Q): yaw -= delta
		if Input.is_physical_key_pressed(KEY_E): yaw += delta
		target.x = clampf(target.x,0,128)
		target.z = clampf(target.z,0,128)
	_update_camera()
	if web:
		poll_time += delta
		if poll_time > 0.08:
			poll_time = 0
			var messages = JSON.parse_string(str(JavaScriptBridge.eval("JSON.stringify((window.voxelMessageQueue||[]).splice(0))",true)))
			if messages is Array:
				for message in messages:
					_receive(message)
			var actions = JSON.parse_string(str(JavaScriptBridge.eval("JSON.stringify((window.voxelUiActions||[]).splice(0))",true)))
			if actions is Array:
				for action in actions:
					_ui_action(str(action))
	else:
		_poll_socket()
	if not busy and not queued.is_empty():
		_render_next()
	if elapsed >= 0.5:
		elapsed = 0
		var times := frame_times.duplicate()
		times.sort()
		var metrics := {"fps": Engine.get_frames_per_second(), "frame_p95_ms": times[int(times.size()*0.95)] if not times.is_empty() else 0,
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"triangles": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			"memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0 if Performance.get_monitor(Performance.MEMORY_STATIC) > 0 else null,
			"mesh_build_ms": mesh_times.back() if not mesh_times.is_empty() else 0,
			"queue": queued.size(), "rendered": nodes.size(), "seq": state.get("seq",0),
			"camera_target": [target.x,target.y,target.z], "camera_size": camera_size, "camera_yaw_deg": rad_to_deg(yaw),
			"mesh_builds": mesh_builds, "node_rebuilds": node_rebuilds, "renderer": RenderingServer.get_current_rendering_method()}
		if web:
			JavaScriptBridge.eval("window.voxelMetrics=%s;" % JSON.stringify(metrics),true)
		elif status_label and not token.is_empty():
			status_label.text = "在线 · %d 栋 · %d FPS" % [nodes.size(),Engine.get_frames_per_second()]

func _typing() -> bool:
	if web:
		return bool(JavaScriptBridge.eval("['INPUT','TEXTAREA'].includes(document.activeElement?.tagName)",true))
	return get_viewport().gui_get_focus_owner() is LineEdit

func _update_camera() -> void:
	camera.size = camera_size
	camera.position = target + Vector3(sin(yaw)*75,80,cos(yaw)*75)
	camera.look_at(target)

func _unhandled_input(event: InputEvent) -> void:
	if _typing():
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_size = clampf(camera_size*0.9,8,160)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_size = clampf(camera_size/0.9,8,160)
		if event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
			last_mouse = event.position
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_pick(event.position)
	if event is InputEventMouseMotion and dragging:
		var offset: Vector2 = event.position-last_mouse
		last_mouse = event.position
		var scale_factor := camera_size/get_viewport().get_visible_rect().size.y
		var right := Vector3(cos(yaw),0,-sin(yaw))
		var forward := Vector3(-sin(yaw),0,-cos(yaw))
		target -= (right*offset.x-forward*offset.y*1.4)*scale_factor

func _pick(point: Vector2) -> void:
	var origin := camera.project_ray_origin(point)
	var direction := camera.project_ray_normal(point)
	var nearest := INF
	var chosen: Dictionary = {}
	for id in nodes:
		if not state.entities.has(id): continue
		var entity: Dictionary = state.entities[id]
		if int(nodes[id].get_meta("revision",0)) != int(entity.revision):
			continue
		var model: Dictionary = state.assets[entity.blueprint_id]
		var inverse: Transform3D = nodes[id].global_transform.affine_inverse()
		var local_origin := inverse*origin
		var local_direction := inverse.basis*direction
		var hit = Mesher.raycast(local_origin,local_direction,model,cell_cache.get(entity.blueprint_id,{}))
		if hit != null:
			var world_hit: Vector3 = nodes[id].global_transform*hit.point
			var distance := origin.distance_to(world_hit)
			if distance < nearest:
				nearest = distance
				chosen = {"entity_id":id,"revision":entity.revision,"position":entity.position,"voxel":hit.voxel}
				marker.position = nodes[id].global_transform*(Vector3(hit.voxel[0],hit.voxel[1],hit.voxel[2])+Vector3(0.5,1.02,0.5))
	if chosen.is_empty() and absf(direction.y) > 0.001:
		var distance := (1.0-origin.y)/direction.y
		if distance > 0:
			var position := origin+direction*distance
			var x := floori(position.x)
			var z := floori(position.z)
			if x >= 0 and x < 128 and z >= 0 and z < 128:
				chosen = {"position":[x,1,z]}
				marker.position = Vector3(x+0.5,1.05,z+0.5)
	selection = chosen
	marker.visible = not selection.is_empty()
	_broadcast_selection()

func _broadcast_selection() -> void:
	if web:
		JavaScriptBridge.eval("window.voxelSelect(%s);" % JSON.stringify(selection),true)
	elif selection_label:
		selection_label.text = "选择：" + JSON.stringify(selection)

func _receive(message: Dictionary) -> void:
	if message.kind == "camera_restore":
		if message.get("target") is Array and message.target.size() == 3:
			target = Vector3(clampf(float(message.target[0]),0,128),1,clampf(float(message.target[2]),0,128))
			camera_size = clampf(float(message.get("size",64)),12,150)
			yaw = deg_to_rad(float(message.get("yaw",-45)))
			_update_camera()
	elif message.kind == "snapshot":
		if message.has("rules"):
			rules_version = str(message.rules.rules_version)
		var old_player := player_id
		player_id = str(message.player_id)
		var old_state := state
		state = message.state
		queued.clear()
		for id in nodes.keys():
			if not state.entities.has(id):
				nodes[id].queue_free()
				nodes.erase(id)
		for id in state.entities:
			if not nodes.has(id) or old_state.get("world_id","") != state.world_id or int(nodes[id].get_meta("revision",0)) != int(state.entities[id].revision) or str(nodes[id].get_meta("blueprint_id","")) != str(state.entities[id].blueprint_id):
				queued[id] = state.entities[id]
		if old_player != player_id:
			_home()
		_update_zones()
		_cleanup_assets()
	elif message.kind == "event":
		var seq := int(message.seq)
		if seq <= int(state.seq): return
		if seq != int(state.seq)+1:
			if web:
				JavaScriptBridge.eval("window.voxelResync();",true)
			else:
				socket.close()
			return
		state.seq = seq
		var kind := str(message.type)
		if kind == "player.joined":
			state.players.append(message.player)
			_update_zones()
		elif kind in ["building.created","building.updated"]:
			if message.has("asset"):
				state.assets[message.asset.id] = message.asset
			state.entities[message.entity.id] = message.entity
			queued[message.entity.id] = message.entity
			if selection.get("entity_id","") == message.entity.id:
				selection.revision = message.entity.revision
				_broadcast_selection()
		elif kind in ["building.removed","building.destroyed"]:
			var id := str(message.entity_id)
			state.entities.erase(id)
			queued.erase(id)
			if nodes.has(id):
				var node: Node3D = nodes[id]
				nodes.erase(id)
				if kind == "building.destroyed":
					var tween := create_tween()
					tween.tween_property(node,"scale",Vector3(0.01,0.01,0.01),0.35)
					tween.tween_callback(node.queue_free)
				else:
					node.queue_free()
			if selection.get("entity_id","") == id:
				selection = {}
				marker.visible = false
				_broadcast_selection()
		_cleanup_assets()

func _cleanup_assets() -> void:
	var active: Dictionary = {}
	for entity in state.entities.values():
		active[entity.blueprint_id] = true
	for id in state.assets.keys():
		if not active.has(id): state.assets.erase(id)
	for id in mesh_cache.keys():
		if not active.has(id): mesh_cache.erase(id)
	for id in cell_cache.keys():
		if not active.has(id): cell_cache.erase(id)

func _render_next() -> void:
	busy = true
	var id: String = queued.keys()[0]
	var entity: Dictionary = queued[id].duplicate(true)
	queued.erase(id)
	var asset_id := str(entity.blueprint_id)
	if not state.assets.has(asset_id):
		busy = false
		return
	var model: Dictionary = state.assets[asset_id].duplicate(true)
	if not mesh_cache.has(asset_id):
		var output: Array = await Mesher.build(model,get_tree())
		mesh_builds += 1
		mesh_cache[asset_id] = output[0]
		mesh_times.append(output[2])
		if mesh_times.size() > 200: mesh_times.pop_front()
		cell_cache[asset_id] = Mesher.voxel_data(model)
	if not state.entities.has(id) or int(state.entities[id].revision) != int(entity.revision):
		busy = false
		_cleanup_assets()
		return
	if nodes.has(id): nodes[id].queue_free()
	var node := Node3D.new()
	node_rebuilds += 1
	node.set_meta("revision",int(entity.revision))
	node.set_meta("blueprint_id",asset_id)
	var position: Array = entity.position
	var rotation := int(entity.rotation_y_quarter_turns)
	var offset := Vector3.ZERO
	if rotation == 1: offset = Vector3(float(model.size[2]),0,0)
	if rotation == 2: offset = Vector3(float(model.size[0]),0,float(model.size[2]))
	if rotation == 3: offset = Vector3(0,0,float(model.size[0]))
	node.position = Vector3(float(position[0]),float(position[1]),float(position[2]))+offset
	node.rotation.y = -rotation*PI/2.0
	for mesh in mesh_cache[asset_id]:
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = material
		node.add_child(instance)
	add_child(node)
	nodes[id] = node
	busy = false

func _update_zones() -> void:
	var colors := [Color("#587558"),Color("#566B80"),Color("#806855"),Color("#756381")]
	for player in state.players:
		var slot := int(player.slot)
		zone_nodes[slot].material_override.albedo_color = colors[slot]

func _home() -> void:
	for player in state.players:
		if player.id == player_id:
			target = Vector3(float(player.zone[0])+32,1,float(player.zone[1])+32)
			camera_size = 70
			yaw = -PI/4.0

func _ui_action(action: String) -> void:
	if action == "home": _home()
	if action == "map":
		target = Vector3(64,1,64)
		camera_size = 160
	if action == "rotate_left": yaw -= PI/8
	if action == "rotate_right": yaw += PI/8
	if action == "zoom_in": camera_size = maxf(camera_size*0.85,8)
	if action == "zoom_out": camera_size = minf(camera_size/0.85,160)
	if action == "color":
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL else BaseMaterial3D.SHADING_MODE_PER_PIXEL

func _native_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16,16)
	panel.custom_minimum_size = Vector2(330,0)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "VOXEL KINGDOM · 第一阶段"
	box.add_child(title)
	room_input = LineEdit.new()
	room_input.text = "kingdom"
	room_input.placeholder_text = "房间名"
	box.add_child(room_input)
	name_input = LineEdit.new()
	name_input.text = "桌面玩家"
	box.add_child(name_input)
	var join_button := Button.new()
	join_button.text = "进入 / 恢复房间"
	join_button.pressed.connect(_native_join)
	box.add_child(join_button)
	status_label = Label.new()
	status_label.text = "请启动 backend 服务，再进入房间"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_label)
	selection_label = Label.new()
	selection_label.text = "点击地面选择位置，点击方块选择建筑"
	selection_label.custom_minimum_size.x = 310
	selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(selection_label)
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "向 DeepSeek 描述需求"
	chat_input.text_submitted.connect(func(_text): _native_chat())
	box.add_child(chat_input)
	var send := Button.new()
	send.text = "发送给 DeepSeek"
	send.pressed.connect(_native_chat)
	box.add_child(send)
	for action in ["home","color","building.demolish","building.destroy"]:
		var button := Button.new()
		button.text = {"home":"回到我的区域","color":"切换颜色检查","building.demolish":"拆除选中建筑","building.destroy":"销毁选中建筑"}[action]
		button.pressed.connect(func(): _native_action(action))
		box.add_child(button)
	var hint := Label.new()
	hint.text = "WASD 平移 · Q/E 旋转\n滚轮缩放 · 中 / 右键拖动"
	box.add_child(hint)
	http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_joined)
	action_http = HTTPRequest.new()
	add_child(action_http)
	action_http.timeout = 250
	action_http.request_completed.connect(_action_completed)

func _native_join() -> void:
	var saved := ConfigFile.new()
	if saved.load("user://session.cfg") == OK:
		token = str(saved.get_value("sessions",backend+":"+room_input.text,""))
	var payload := {"world_id":room_input.text,"name":name_input.text}
	if not token.is_empty(): payload.token = token
	http.request(backend+"/api/join",["Content-Type: application/json"],HTTPClient.METHOD_POST,JSON.stringify(payload))

func _joined(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var data = JSON.parse_string(body.get_string_from_utf8())
	if code != 200 or not data is Dictionary:
		status_label.text = "连接失败：检查服务端 " + backend
		return
	token = str(data.token)
	player_id = ""
	_receive({"kind":"snapshot","state":data.snapshot,"player_id":data.player_id})
	var saved := ConfigFile.new()
	saved.load("user://session.cfg")
	saved.set_value("sessions",backend+":"+room_input.text,token)
	saved.save("user://session.cfg")
	_connect_socket()

func _connect_socket() -> void:
	socket = WebSocketPeer.new()
	socket.connect_to_url(backend.replace("https://","wss://").replace("http://","ws://")+"/ws")
	was_connected = false
	reconnect_at = Time.get_ticks_msec()/1000.0+3

func _poll_socket() -> void:
	if token.is_empty(): return
	socket.poll()
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		if not was_connected:
			was_connected = true
			socket.send_text(JSON.stringify({"token":token}))
		while socket.get_available_packet_count():
			var data = JSON.parse_string(socket.get_packet().get_string_from_utf8())
			if data is Dictionary:
				if data.get("kind","") == "resync_required": socket.close()
				elif data.get("kind","") != "pong": _receive(data)
	elif socket.get_ready_state() == WebSocketPeer.STATE_CLOSED and Time.get_ticks_msec()/1000.0 > reconnect_at:
		_connect_socket()

func _native_chat() -> void:
	if token.is_empty() or chat_input.text.is_empty(): return
	var payload := {"request_id":"desktop-"+str(Time.get_ticks_usec()),"text":chat_input.text,"selection":selection}
	var error := action_http.request(backend+"/api/chat",["Content-Type: application/json","Authorization: Bearer "+token],HTTPClient.METHOD_POST,JSON.stringify(wire_data(payload)))
	if error == OK:
		status_label.text = "DeepSeek 正在生成…"
		chat_input.text = ""

func _native_action(action: String) -> void:
	if action in ["home","color"]:
		_ui_action(action)
		return
	if not selection.has("entity_id") or token.is_empty(): return
	var payload := {"schema_version":1,"rules_version":rules_version,"command_id":"desktop-"+str(Time.get_ticks_usec()),"world_id":state.world_id,"type":action,"payload":{"entity_id":selection.entity_id,"expected_entity_revision":selection.revision}}
	action_http.request(backend+"/api/command",["Content-Type: application/json","Authorization: Bearer "+token],HTTPClient.METHOD_POST,JSON.stringify(wire_data(payload)))

static func wire_data(value: Variant) -> Variant:
	# Godot JSON parses integers as floats; the protocol intentionally requires integer fields.
	if value is float:
		return int(value) if value == floor(value) else value
	if value is Array:
		var array: Array = []
		for item in value: array.append(wire_data(item))
		return array
	if value is Dictionary:
		var dictionary: Dictionary = {}
		for key in value: dictionary[key] = wire_data(value[key])
		return dictionary
	return value

func _action_completed(_result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var data = JSON.parse_string(body.get_string_from_utf8())
	if data is Dictionary:
		selection_label.text = str(data.get("message",data.get("status",data.get("error",{}))))
