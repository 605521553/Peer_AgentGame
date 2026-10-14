extends Node2D

# Disposable visual adapter. Receives a presentation descriptor, never combat objects.
var descriptor: Dictionary = {}
var styles: Dictionary = {}
var textures: Dictionary = {}

func configure(configuration: Dictionary) -> void:
	styles = configuration.styles
	for id in styles:
		var path := str(styles[id].texture)
		if not path.is_empty() and ResourceLoader.exists(path): textures[id] = load(path)

func present(value: Dictionary) -> void:
	descriptor = value
	position = value.position
	visible = value.visible
	queue_redraw()

func _draw() -> void:
	if descriptor.is_empty() or not visible: return
	var id := str(descriptor.visual)
	if not styles.has(id): return
	var style: Dictionary = styles[id]
	var radius := float(descriptor.radius)
	var color := Color(str(style.color))
	if textures.has(id):
		draw_texture_rect(textures[id], Rect2(Vector2.ONE * -radius, Vector2.ONE * radius * 2), false)
		return
	var sides := 4
	match style.shape:
		"triangle": sides = 3
		"hex": sides = 6
		"octagon": sides = 8
	var points := PackedVector2Array()
	for i in range(sides): points.append(Vector2.UP.rotated(TAU * float(i) / float(sides)) * radius)
	draw_circle(Vector2.ZERO, radius + 7, Color(color, 0.07))
	draw_colored_polygon(points, Color(color, 0.19))
	points.append(points[0])
	draw_polyline(points, color, 2, true)
	draw_circle(Vector2.ZERO, radius * 0.22, color)
