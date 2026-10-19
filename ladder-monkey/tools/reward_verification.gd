extends Node
## Integration test: natural body overlap, physical shards, retracing a
## collected height, then simultaneous Area3D pickups to exercise the queue.
var game: Node
var capture_images: bool = false
var elapsed: float = 0.0
var stage: int = 0
var stage_time: float = 0.0
var errors: Array[String] = []
var event_ids: Array[int] = []
var active_toasts: int = 0
var peak_toasts: int = 0
var peak_pending: int = 0
var sample: RigidBody3D
var initial_sample_position := Vector3.ZERO
var initial_vertical_velocity: float = 0.0
var observed_gravity: bool = false
var observed_spin: bool = false
var observed_motion: bool = false
var sample_collection_time: float = -1.0
var captured: Dictionary = {}
var output_directory: String = "res://artifacts"
var done: bool = false

func _ready() -> void:
	process_priority = 50
	if not OS.has_feature("editor"):
		output_directory = "user://verification"
	DirAccess.make_dir_recursive_absolute(output_directory)
	game.achievements.debris.rng.seed = 48153
	game.achievements.achievement_collected.connect(on_collected)
	game.achievement_toast.toast_started.connect(on_toast_started)
	game.achievement_toast.toast_finished.connect(on_toast_finished)
	if not capture_images:
		set_key(KEY_W, true)

func on_toast_started(_id: int) -> void:
	active_toasts += 1
	peak_toasts = maxi(peak_toasts, active_toasts)

func on_toast_finished(_id: int) -> void:
	active_toasts -= 1

func on_collected(id: int, _label: String) -> void:
	event_ids.append(id)
	if id == 0:
		sample_collection_time = elapsed
		set_key(KEY_W, false)
		sample = game.achievements.debris.active[0].body
		initial_sample_position = sample.global_position
		initial_vertical_velocity = sample.linear_velocity.y

func _process(delta: float) -> void:
	if done:
		return
	elapsed += delta
	stage_time += delta
	var awards: MonkeyAchievements = game.achievements
	peak_pending = maxi(peak_pending, game.achievement_toast.pending.size())
	if is_instance_valid(sample):
		observed_motion = observed_motion or sample.global_position.distance_to(initial_sample_position) > 0.03
		observed_spin = observed_spin or sample.angular_velocity.length() > 0.1
		observed_gravity = observed_gravity or sample.linear_velocity.y < initial_vertical_velocity - 0.1
		check(sample.collision_mask == TrophyDebris.SCENERY_LAYER, "Shard collision mask can reach the monkey")
	if capture_images:
		update_captures()
	match stage:
		0:
			if not event_ids.is_empty():
				check(event_ids == [0], "First reward ID/order incorrect")
				check(awards.debris.spawned_count == awards.profile.fragment_count, "Burst does not use configured shard count")
				check(awards.body_probe.global_position.distance_to(game.body.final_pelvis + Vector3(0, 0.13, 0)) < 0.001, "Collection trigger does not follow posed torso")
				check(awards.head_probe_shape.shape is SphereShape3D, "Cartoon head has no collection shape")
				stage = 1
				stage_time = 0.0
		1:
			if stage_time > 6.1:
				check(awards.debris.active.is_empty(), "Natural collection fragments exceeded lifetime")
				check(awards.debris.collision_count > 0, "Natural burst did not collide/bounce on scenery")
				check(game.achievement_toast.finished_ids == [0], "Natural achievement toast failed")
				set_key(KEY_S, true)
				stage = 2
				stage_time = 0.0
		2:
			if stage_time > 1.3:
				set_key(KEY_S, false)
				set_key(KEY_W, true)
				stage = 3
				stage_time = 0.0
		3:
			if stage_time > 2.1:
				set_key(KEY_W, false)
				stage = 4
				stage_time = 0.0
		4:
			if stage_time > 1.2:
				check(event_ids == [0], "Revisiting an award height collected it twice")
				check(not awards.live_trophies.has(0), "Collected trophy respawned")
				game.achievement_toast.enqueue(0, "初攀新星", awards.profile.first_height)
				check(not game.achievement_toast.active and game.achievement_toast.pending.is_empty(), "Toast accepted a duplicate ID")
				# Test fixtures use the real overlap path, not direct collection calls.
				var limited: AchievementProfile = awards.profile.duplicate()
				limited.max_active_fragments = 32
				awards.debris.profile = limited
				for i in 3:
					var trophy := TrophyPickup.new()
					trophy.profile = awards.profile
					trophy.award_id = 100 + i
					trophy.award_name = awards.profile.achievement_names[i + 1]
					trophy.award_height = awards.body_probe.global_position.y
					trophy.position = awards.to_local(awards.body_probe.global_position)
					trophy.collected.connect(awards.on_trophy_collected)
					awards.add_child(trophy)
				stage = 5
				stage_time = 0.0
		5:
			if stage_time > 10.4:
				check(event_ids.size() == 4, "Simultaneous overlaps were lost or duplicated")
				check(game.achievement_toast.displayed_ids == event_ids, "Toasts did not preserve collection order")
				check(game.achievement_toast.finished_ids == event_ids, "Queued toasts did not complete")
				check(peak_pending >= 2, "Multiple rewards never queued")
				check(peak_toasts == 1 and active_toasts == 0, "Achievement panels overlapped")
				check(awards.debris.active.is_empty(), "Burst stress test leaked rigid bodies")
				check(awards.debris.peak_active <= 32, "Configured debris limit was exceeded")
				check(awards.debris.spawned_count == awards.debris.cleaned_count, "Capped/expired shards were not all cleaned")
				check(observed_motion and observed_spin and observed_gravity, "Shards did not show physical flight/spin/gravity")
				finish()
	if elapsed > 40.0:
		check(false, "Reward integration timed out at stage %d" % stage)
		finish()

func check(condition: bool, message: String) -> void:
	if not condition and not errors.has(message):
		errors.append(message)

func set_key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func finish() -> void:
	done = true
	var rewards: MonkeyAchievements = game.achievements
	var result := {"passed": errors.is_empty(), "errors": errors, "real_collection_ids": event_ids, "toast_order": game.achievement_toast.displayed_ids, "peak_simultaneous_toasts": peak_toasts, "peak_pending_toasts": peak_pending, "spawned_shards": rewards.debris.spawned_count, "cleaned_shards": rewards.debris.cleaned_count, "peak_active_shards_with_limit_32": rewards.debris.peak_active, "physical_collisions": rewards.debris.collision_count, "gravity_observed": observed_gravity, "spin_observed": observed_spin, "flight_observed": observed_motion, "simulation_seconds": elapsed}
	var report := FileAccess.open(output_directory + "/reward_verification.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(result, "\t"))
	print("REWARD_VERIFICATION ", JSON.stringify(result))
	get_tree().quit(0 if errors.is_empty() else 1)

func update_captures() -> void:
	if elapsed > 0.40 and not captured.has("waiting"):
		captured.waiting = true
		capture("05_trophy_waiting")
	if elapsed > 0.90 and not captured.has("start_climbing"):
		captured.start_climbing = true
		set_key(KEY_W, true)
	if sample_collection_time >= 0.0:
		var since := elapsed - sample_collection_time
		if since > 0.07 and not captured.has("burst"):
			captured.burst = true
			capture("06_trophy_burst")
		if since > 0.55 and not captured.has("toast"):
			captured.toast = true
			capture("07_achievement_toast")
	if stage == 5 and stage_time > 3.6 and not captured.has("queue"):
		captured.queue = true
		capture("08_toast_queue")

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = game.viewport.get_texture().get_image()
	image.resize(1152, 864, Image.INTERPOLATE_NEAREST)
	image.save_png(output_directory + "/" + label + ".png")
	print("CAPTURE ", label)
