extends Node

# Procedural prototype audio is a replaceable presentation subscriber.
var config: Dictionary
var streams: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var cursor := 0
var last_times: Dictionary = {}
var muted := false

func setup(model: CombatModel, settings: Dictionary) -> void:
	config = settings
	for id in config.sounds:
		streams[id] = _synthesize(config.sounds[id])
	for _i in range(int(config.voices)):
		var voice := AudioStreamPlayer.new()
		voice.volume_db = float(config.volume_db)
		add_child(voice)
		voices.append(voice)
	model.feedback.connect(_feedback)

func _synthesize(sound: Dictionary) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = int(config.sample_rate)
	var count := int(float(sound.duration) * stream.mix_rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var phase := 0.0
	for i in range(count):
		var fraction := float(i) / float(count)
		var frequency := lerpf(float(sound.frequency), float(sound.end_frequency), fraction)
		phase += TAU * frequency / float(stream.mix_rate)
		var envelope := sin(PI * fraction) * (1.0 - fraction)
		bytes.encode_s16(i * 2, int(sin(phase) * envelope * float(sound.gain) * 32767))
	stream.data = bytes
	return stream

func _feedback(kind: String, _position: Vector2, _message: String) -> void:
	if muted or not config.enabled or not streams.has(kind) or voices.is_empty(): return
	var time := Time.get_ticks_msec() * 0.001
	if time - float(last_times.get(kind, -1.0)) < float(config.minimum_gap): return
	last_times[kind] = time
	var voice := voices[cursor]
	voice.stream = streams[kind]
	voice.play()
	cursor = (cursor + 1) % voices.size()

func _exit_tree() -> void:
	for voice in voices:
		voice.stop()
		voice.stream = null
	streams.clear()
