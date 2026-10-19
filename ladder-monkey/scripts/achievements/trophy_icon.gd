class_name TrophyPixelIcon
extends Control
## Native pixel geometry, matching the cup's silhouette; no raster asset.
func _ready() -> void:
	custom_minimum_size = Vector2(34, 34)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var dark := Color("95622e")
	var gold := Color("e6ac4d")
	var light := Color("ffe6a1")
	draw_rect(Rect2(2, 2, 30, 30), Color("423c35"))
	draw_rect(Rect2(8, 7, 18, 4), gold)
	draw_rect(Rect2(10, 11, 14, 8), gold)
	draw_rect(Rect2(12, 19, 10, 3), dark)
	draw_rect(Rect2(15, 22, 4, 5), gold)
	draw_rect(Rect2(10, 27, 14, 3), gold)
	draw_rect(Rect2(11, 9, 3, 8), light)
	draw_rect(Rect2(4, 9, 4, 8), gold)
	draw_rect(Rect2(26, 9, 4, 8), gold)
	draw_rect(Rect2(7, 16, 4, 3), gold)
	draw_rect(Rect2(23, 16, 4, 3), gold)
	draw_rect(Rect2(9, 7, 16, 2), light)
	draw_rect(Rect2(11, 27, 11, 1), light)
