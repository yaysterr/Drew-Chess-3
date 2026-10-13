extends Control

var value: int = 0
var max_value: int = 4

const FILLED = Color(1.0, 0.710, 0.439, 1.0)
const EMPTY  = Color(1.0, 0.710, 0.439, 0.22)
const RADIUS = 7.0
const SPACING = 20.0

func _draw() -> void:
	for i in range(max_value):
		var c = Vector2(RADIUS + i * SPACING, RADIUS)
		draw_circle(c, RADIUS, FILLED if i < value else EMPTY)
		draw_arc(c, RADIUS, 0, TAU, 24, FILLED, 1.5)

func set_value(v: int) -> void:
	value = clamp(v, 0, max_value)
	queue_redraw()
