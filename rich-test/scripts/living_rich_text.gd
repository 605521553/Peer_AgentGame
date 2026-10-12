extends RichTextLabel
class_name LivingRichText
## Reusable renderer: BBCode + local RichTextEffects + a separate dialogue clock.
## [wait=seconds], [speed=characters_per_second] and [voice=pitch] are stripped
## before rendering and applied at the parsed character position.

signal playback_finished
signal character_revealed(character: String, position: int)
signal playback_changed

const FX = preload("res://scripts/effects/lab_effect.gd")
const TAGS = ["tremble", "swing", "float", "bounce", "ghost", "blink", "flicker", "breathe", "wobble", "spin", "stretch", "gradient", "glitch", "scramble", "pop", "rise", "slide", "reveal", "fall"]

var context: Dictionary = {"clock": 0.0, "revealed": {}}
var characters_per_second: float = 28.0
var punctuation_pause: float = 0.25
var sentence_pause: float = 0.55
var voice_pitch: float = 1.0
var playing: bool = false
var paused: bool = false
var source: String = ""
var events: Dictionary = {}
var plain: String = ""
var remaining: float = 0.0
var current_speed: float = -1.0
var _executed_events: Dictionary = {}
var _probe: RichTextLabel

func _init() -> void:
	bbcode_enabled = true
	for tag in TAGS:
		install_effect(FX.new(tag, context))
	visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	clip_contents = false

func _ready() -> void:
	_probe = RichTextLabel.new()
	_probe.bbcode_enabled = true
	for tag in TAGS:
		_probe.install_effect(FX.new(tag, {}))
	_probe.visible = false
	_probe.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_probe)

func set_source(value: String, animate: bool = false) -> void:
	source = value
	events.clear()
	_executed_events.clear()
	context["clock"] = 0.0
	context["revealed"] = {}
	var pattern := RegEx.new()
	pattern.compile("\\[(wait|speed|voice)=([0-9]+(?:\\.[0-9]+)?)\\]")
	var clean: String = ""
	var last: int = 0
	for token in pattern.search_all(value):
		clean += value.substr(last, token.get_start() - last)
		_probe.text = clean
		var position: int = _probe.get_total_character_count()
		if not events.has(position):
			events[position] = []
		events[position].append({"type": token.get_string(1), "value": token.get_string(2).to_float()})
		last = token.get_end()
	clean += value.substr(last)
	text = ""
	text = clean
	plain = get_parsed_text()
	if animate:
		replay()
	else:
		show_all()

func replay() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	paused = false
	context["clock"] = 0.0
	context["revealed"] = {}
	# Reparse once to restart built-in effect clocks; never reparse on each letter.
	var compiled: String = text
	text = ""
	text = compiled
	visible_characters = 0
	current_speed = -1.0
	_executed_events.clear()
	voice_pitch = 1.0
	remaining = 0.0
	playing = true
	playback_changed.emit()

func show_all() -> void:
	playing = false
	visible_characters = -1
	for index in range(get_total_character_count()):
		if not context["revealed"].has(index):
			context["revealed"][index] = context["clock"]
	playback_changed.emit()

func set_paused(value: bool) -> void:
	paused = value
	process_mode = Node.PROCESS_MODE_DISABLED if paused else Node.PROCESS_MODE_INHERIT
	playback_changed.emit()

func _process(delta: float) -> void:
	context["clock"] = float(context["clock"]) + delta
	if not playing:
		return
	remaining -= delta
	var budget: int = 0
	while remaining <= 0.0 and budget < 64:
		budget += 1
		var index: int = visible_characters
		if events.has(index) and not _executed_events.has(index):
			for event in events[index]:
				match event.type:
					"wait": remaining += clampf(event.value, 0.0, 60.0)
					"speed": current_speed = clampf(event.value, 1.0, 300.0)
					"voice": voice_pitch = clampf(event.value, 0.3, 3.0)
			# A position must execute once, even while waiting at that position.
			_executed_events[index] = true
			if remaining > 0.0:
				break
		if index >= get_total_character_count():
			playing = false
			playback_finished.emit()
			playback_changed.emit()
			break
		context["revealed"][index] = context["clock"]
		visible_characters += 1
		var character: String = plain.substr(index, 1)
		character_revealed.emit(character, index)
		var effective_speed: float = current_speed if current_speed > 0.0 else characters_per_second
		remaining += 1.0 / maxf(effective_speed, 1.0)
		if character in ["，", "、", ",", "：", ":", "；", ";"]:
			remaining += punctuation_pause
		elif character in ["。", "！", "？", ".", "!", "?", "…", "\n"]:
			remaining += sentence_pause
