@tool
extends RichTextEffect
## One independently registered resource per tag. The clock and reveal times
## belong to the label, never to a glyph callback (which also runs for outlines).

var bbcode: String = "ghost"
var context: Dictionary = {}

func _init(tag: String = "ghost", shared_context: Dictionary = {}) -> void:
	bbcode = tag
	context = shared_context

func _number(env: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = env.get(key, fallback)
	if value is float or value is int:
		return float(value)
	if str(value).is_valid_float():
		return str(value).to_float()
	return fallback

func _noise(index: float, tick: float) -> float:
	return fposmod(sin(index * 127.1 + tick * 311.7) * 43758.5453, 1.0) * 2.0 - 1.0

func _process_custom_fx(fx: CharFXTransform) -> bool:
	var e: Dictionary = fx.env
	var t: float = float(context.get("clock", fx.elapsed_time))
	var i: float = float(fx.relative_index)
	var speed: float = _number(e, "speed", 3.0)
	var amp: float = _number(e, "amp", 6.0)
	var spread: float = _number(e, "spread", 0.55)
	var phase: float = t * speed * TAU + i * spread
	var age: float = t
	var times: Dictionary = context.get("revealed", {})
	if times.has(fx.range.x):
		age = maxf(0.0, t - float(times[fx.range.x]))
	var duration: float = maxf(0.02, _number(e, "duration", 0.65))
	var p: float = clampf(age / duration, 0.0, 1.0)
	match bbcode:
		"tremble":
			var tick: float = floor(t * maxf(speed, 0.0) * 10.0)
			var seed: float = 0.0 if str(e.get("sync", "false")) == "true" else i
			var v := Vector2(_noise(seed + 7.0, tick), _noise(seed + 19.0, tick)) * amp
			match str(e.get("axis", "xy")):
				"x": v.y = 0.0
				"y": v.x = 0.0
			fx.offset += v
		"swing":
			fx.offset.x += sin(phase) * amp
		"float":
			fx.offset += Vector2(sin(phase * 0.7) * amp * 0.45, sin(phase) * amp)
		"bounce":
			fx.offset.y -= absf(sin(phase)) * amp
		"ghost":
			var minimum: float = clampf(_number(e, "min", 0.12), 0.0, 1.0)
			fx.color.a *= lerpf(minimum, 1.0, sin(phase) * 0.5 + 0.5)
		"blink":
			fx.color.a *= 1.0 if fposmod(t * speed + i * spread, 1.0) < _number(e, "duty", 0.5) else _number(e, "min", 0.08)
		"flicker":
			fx.color.a *= 1.0 if _noise(i, floor(t * speed * 10.0)) > -0.4 else _number(e, "min", 0.12)
		"breathe":
			_scale(fx, 1.0 + sin(phase) * amp * 0.01)
		"wobble":
			_rotate(fx, deg_to_rad(sin(phase) * amp))
		"spin":
			_rotate(fx, phase)
		"stretch":
			fx.transform = fx.transform * Transform2D(0.0, Vector2(1.0 + sin(phase) * amp * 0.01, 1.0 - sin(phase) * amp * 0.005), 0.0, Vector2.ZERO)
		"gradient":
			var a: Color = _color(e.get("from", Color("73e6cc")), Color("73e6cc"))
			var b: Color = _color(e.get("to", Color("b5a2ff")), Color("b5a2ff"))
			var tint: Color = a.lerp(b, sin(phase) * 0.5 + 0.5)
			fx.color = Color(tint.r, tint.g, tint.b, fx.color.a)
		"glitch":
			var tick: float = floor(t * speed * 8.0)
			if _noise(i, tick) > 0.45:
				fx.offset.x += _noise(i + 4, tick) * amp * 2.0
				fx.color = Color(0.6, 1.0, 0.85, fx.color.a)
		"scramble":
			if p < 1.0:
				var codepoint: int = 65 + int(absf(_noise(i, floor(age * maxf(speed, 1.0) * 12.0))) * 25.0)
				fx.glyph_index = TextServerManager.get_primary_interface().font_get_glyph_index(fx.font, 1, codepoint, 0)
		"pop":
			var s: float = 1.0 + sin(p * PI) * (1.0 - p) * amp * 0.04
			_scale(fx, s)
			fx.color.a *= minf(1.0, p * 5.0)
		"rise":
			fx.offset.y += (1.0 - p) * amp * 3.0
			fx.color.a *= p
		"slide":
			fx.offset.x -= pow(1.0 - p, 2.0) * amp * 4.0
			fx.color.a *= p
		"reveal":
			fx.color.a *= p
		"fall":
			fx.offset.y -= pow(1.0 - p, 2.0) * amp * 4.0
			_rotate(fx, (1.0 - p) * 0.3)
			fx.color.a *= p
	return true

func _scale(fx: CharFXTransform, value: float) -> void:
	fx.transform = fx.transform * Transform2D(0.0, Vector2(value, value), 0.0, Vector2.ZERO)

func _rotate(fx: CharFXTransform, angle: float) -> void:
	fx.transform = fx.transform * Transform2D(angle, Vector2.ZERO)

func _color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	return Color.from_string(str(value), fallback)
