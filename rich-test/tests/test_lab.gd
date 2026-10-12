extends SceneTree
## Run: godot --headless --path . --script res://tests/test_lab.gd
## Exercises the real UI, parser, renderer and playback rather than mock copies.

var failures: Array[String] = []
var assertions: int = 0
var lab: Control

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	lab = load("res://scenes/laboratory.tscn").instantiate()
	root.add_child(lab)
	await process_frame
	lab.voice.enabled = false
	var initial_state: Dictionary = lab._state().duplicate(true)
	check(lab.catalog.size() >= 55, "Catalog should cover at least 55 examples")
	var ids: Dictionary = {}
	for index in range(lab.catalog.size()):
		var item: Dictionary = lab.catalog[index]
		check(not ids.has(item.id), "Duplicate catalog ID: " + str(item.id))
		ids[item.id] = true
		lab._select_effect(index)
		lab.voice.enabled = false
		lab._show_all()
		await process_frame
		lab._validate_source()
		check(not lab.editor.text.contains("{word}") and not lab.editor.text.contains("{tag}"), "Unexpanded template: " + str(item.id))
		check(not lab.preview.get_parsed_text().is_empty(), "Empty output: " + str(item.id))
		check(not lab.preview.get_parsed_text().contains("[wait=") and not lab.preview.get_parsed_text().contains("[speed="), "Control tags leaked: " + str(item.id))
		check(not lab.status.text.contains("不匹配") and not lab.status.text.contains("未关闭") and not lab.status.text.contains("未识别"), "Invalid sample: " + str(item.id) + " " + lab.status.text)
		# Render both extremes of each numeric control, including zero speed,
		# zero amplitude and shortest entry duration.
		var values: Dictionary = lab._values(item)
		var original: Dictionary = values.duplicate()
		for edge in ["min", "max"]:
			for spec in item.params:
				if spec.kind == "number":
					values[spec.key] = spec[edge]
			lab.manual_mode = false
			lab._parameter_changed()
			lab._show_all()
			await process_frame
		for key in original:
			values[key] = original[key]
	# Rich BBCode before the controls must not shift control positions.
	var text: LivingRichText = lab.preview
	text.set_source("[b]甲[/b][wait=0.2][speed=80][color=#ffffff]乙[/color][voice=0.6]丙", true)
	check(text.get_parsed_text() == "甲乙丙", "Parsed dialogue should exclude controls")
	check(text.events.has(1) and text.events.has(2), "Control positions should use parsed characters")
	text._process(0.001)
	check(text.visible_characters == 1, "First character should reveal immediately")
	text._process(0.04)
	check(text.visible_characters == 1, "Explicit wait must hold at the second character")
	text._process(0.3)
	check(text.visible_characters == 3 and not text.playing, "Playback should finish after wait")
	check(is_equal_approx(text.voice_pitch, 0.6), "Local voice pitch should apply")
	# Replay must execute the wait again, rather than consume the event map.
	text.replay()
	text._process(0.001)
	text._process(0.04)
	check(text.visible_characters == 1, "Replay should retain waits")
	# Pause should halt the clock, animation and reveal advancement.
	text.set_paused(true)
	var before: float = text.context.clock
	await create_timer(0.04).timeout
	check(is_equal_approx(text.context.clock, before), "Pause should stop the effect clock")
	text.set_paused(false)
	text.show_all()
	check(text.visible_characters == -1 and not text.playing, "Show all should cancel typing")
	# Each character's entrance age begins when revealed, not at scene start.
	text.set_source("[rise duration=0.5]甲乙[/rise]", true)
	text._process(0.001)
	var first_time: float = text.context.revealed[0]
	text._process(0.04)
	check(text.context.revealed.has(1) and float(text.context.revealed[1]) > first_time, "Entry times should differ per revealed character")
	# Wrapped selections support nesting and remain editable/undoable.
	lab._select_effect(ids.keys().find("color"))
	lab._set_editor("甲乙丙")
	lab.editor.select(0, 1, 0, 2)
	lab._wrap_selection()
	check(lab.editor.text == "甲[color=#73e6cc]乙[/color]丙", "Selected phrase should be wrapped")
	check(lab.preview.get_parsed_text() == "甲乙丙", "Wrapping should preserve visible content")
	var edited: String = lab.editor.text
	lab._values(lab.catalog[lab.current_index])["color"] = "#ff0000"
	lab._parameter_changed()
	check(lab.editor.text == edited, "Parameter change must preserve manually edited source")
	# Real UI signal wiring must update the correct individual parameter.
	lab.building = true
	lab._select_effect(ids.keys().find("wave"))
	var wave_values: Dictionary = lab._values(lab.catalog[lab.current_index])
	var amp_spin: SpinBox = lab.params_box.get_child(0).get_child(0).get_child(1)
	var freq_spin: SpinBox = lab.params_box.get_child(1).get_child(0).get_child(1)
	amp_spin.value = 13
	freq_spin.value = 4
	check(float(wave_values.amp) == 13 and float(wave_values.freq) == 4, "Numeric UI callbacks should bind distinct parameter keys")
	check(lab.editor.text.contains("amp=13") and lab.editor.text.contains("freq=4"), "Parameter UI should regenerate BBCode")
	# Filter selection and reset must preserve catalog identity.
	lab.search.text = "tremble"
	lab._filter_catalog()
	check(lab.filtered.size() >= 1, "Searching by BBCode should find effects")
	lab.search.text = ""
	lab._filter_catalog()
	lab._reset_effect()
	check(float(lab._values(lab.catalog[lab.current_index]).amp) == 8, "Reset should restore current effect defaults")
	# Escaped brackets are visible text and must not become a custom tag.
	text.set_source("[lb]wave[rb] [b]甲[/b][wait=0.1]乙", true)
	check(text.events.has(8), "Control position should include escaped visible brackets")
	# Serialization round-trip and untrusted config type checks.
	var state: Dictionary = JSON.parse_string(JSON.stringify(lab._state()))
	check(lab._accept_state(state), "Exported configuration should import")
	check(lab._accept_state({"version": 1, "settings": {"cps": 9999}, "parameters": {"color": []}, "drafts": {}}), "Malformed individual fields should be safely ignored")
	check(float(lab.settings.cps) <= 150, "Imported speed should be clamped")
	check(not lab._accept_state({"version": 99}), "Unknown format version should be rejected")
	# Import through the actual application path, including rebuilding controls.
	var temporary_path: String = "user://lab_test_import.json"
	var temporary := FileAccess.open(temporary_path, FileAccess.WRITE)
	temporary.store_string(JSON.stringify(state))
	temporary.close()
	lab._import_file(temporary_path)
	await process_frame
	check(lab.editor.text == str(state.drafts[state.selected].source), "Import should restore the selected draft")
	check(lab.word_input.text == str(state.drafts[state.selected].word), "Import should restore the edited example word")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
	# Restore the user's in-memory defaults; the test never writes user:// state.
	lab._accept_state(initial_state)
	print("LAB_TEST_RESULT: %d assertions, %d failures, %d examples" % [assertions, failures.size(), lab.catalog.size()])
	lab.voice.stop()
	await create_timer(0.12).timeout
	lab.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
