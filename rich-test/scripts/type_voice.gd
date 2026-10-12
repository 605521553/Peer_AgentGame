extends Node
## Short synthesized phonemes. No external audio assets or audio-thread work.

var enabled: bool = true
var tone: int = 0
var pitch: float = 1.0
var variation: float = 0.08
var volume_db: float = -20.0
var every: int = 2
var duration: float = 0.045
var _players: Array[AudioStreamPlayer] = []
var _samples: Array[AudioStreamWAV] = []
var _cursor: int = 0
var _letters: int = 0
var _last_sound: int = 0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	for index in range(4):
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	regenerate()

func regenerate() -> void:
	_samples.clear()
	for kind in range(4):
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = 22050
		var count: int = int(22050 * duration)
		var bytes := PackedByteArray()
		bytes.resize(count * 2)
		for index in range(count):
			var t: float = float(index) / 22050.0
			var frequency: float = [410.0, 240.0, 650.0, 330.0][kind]
			var phase: float = TAU * frequency * t
			var sample: float = sin(phase)
			match kind:
				1: sample = sin(phase) * 0.65 + sin(phase * 2.0) * 0.25
				2: sample = (1.0 if sin(phase) > 0 else -1.0) * 0.4
				3: sample = sin(phase + sin(phase * 0.5) * 2.0) * 0.7
			var envelope: float = minf(t / 0.006, 1.0) * pow(1.0 - float(index) / count, 2.0)
			bytes.encode_s16(index * 2, int(sample * envelope * 22000.0))
		stream.data = bytes
		_samples.append(stream)

func speak(character: String, _position: int, local_pitch: float = 1.0) -> void:
	if not enabled or character.strip_edges().is_empty() or character in ["，", "。", "！", "？", "、", "…", ",", ".", "!", "?", ":", "：", "；", ";"]:
		return
	_letters += 1
	if _letters % maxi(every, 1) != 0 or Time.get_ticks_msec() - _last_sound < 25:
		return
	_last_sound = Time.get_ticks_msec()
	var player: AudioStreamPlayer = _players[_cursor % _players.size()]
	_cursor += 1
	player.stream = _samples[clampi(tone, 0, 3)]
	player.pitch_scale = clampf(pitch * local_pitch * (1.0 + _rng.randf_range(-variation, variation)), 0.2, 4.0)
	player.volume_db = volume_db
	player.play()

func stop() -> void:
	for player in _players:
		player.stop()
	_letters = 0

func audition() -> void:
	var player: AudioStreamPlayer = _players[0]
	player.stream = _samples[clampi(tone, 0, 3)]
	player.pitch_scale = pitch
	player.volume_db = volume_db
	player.play()

func _exit_tree() -> void:
	stop()
