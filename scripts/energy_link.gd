extends Node2D

## EnergyLink — a temporary glowing tether drawn between two points in the
## parent's local coordinate space. Used to visually connect a Sacrifice
## piece to its target for a beat before the final burst. Purely decorative.

const COLOR_LINK := Color(0.84, 0.32, 0.92, 0.9)
const COLOR_GLOW := Color(0.76, 0.20, 0.30, 0.5)
const FADE_DURATION := 0.4
const TRAVEL_SPEED  := 1.1   # traversals/sec of the traveling energy pulse

var point_a: Vector2 = Vector2.ZERO
var point_b: Vector2 = Vector2.ZERO

var _t: float          = 0.0
var _intensity: float  = 0.0   # 0..1, ramps up smoothly after spawning

func _ready() -> void:
	modulate.a = 0.0
	var t := create_tween()
	t.tween_property(self, "modulate:a", 1.0, FADE_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	_t += delta
	_intensity = min(_intensity + delta / FADE_DURATION, 1.0)
	queue_redraw()

## Fades the link out smoothly and frees it.
func fade_out_and_free() -> void:
	set_process(false)
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, FADE_DURATION * 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.finished.connect(func():
		if is_inside_tree():
			queue_free()
	)

func _draw() -> void:
	var pulse  = 0.6 + 0.4 * sin(_t * TAU * 0.55)
	var glow_a = 0.26 * _intensity * pulse

	# Soft wide glow strokes (translucent, layered — no hard bright edge)
	for i in range(3):
		var w = 7.0 - i * 1.8
		var a = glow_a * (0.55 - i * 0.14)
		if a > 0.0:
			draw_line(point_a, point_b, Color(COLOR_GLOW.r, COLOR_GLOW.g, COLOR_GLOW.b, a), w, true)

	# Core thread
	draw_line(point_a, point_b, Color(COLOR_LINK.r, COLOR_LINK.g, COLOR_LINK.b, 0.55 * _intensity), 1.6, true)

	# Traveling energy pulse flowing from the sacrificed piece toward the target
	var travel_t = fmod(_t * TRAVEL_SPEED, 1.0)
	var pulse_pos = point_a.lerp(point_b, travel_t)
	draw_circle(pulse_pos, 4.5, Color(COLOR_LINK.r, COLOR_LINK.g, COLOR_LINK.b, 0.9 * _intensity))
	draw_circle(pulse_pos, 9.0, Color(COLOR_LINK.r, COLOR_LINK.g, COLOR_LINK.b, 0.22 * _intensity))
