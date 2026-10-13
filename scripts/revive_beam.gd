extends Node2D

## ReviveBeam — a vertical column of golden light that descends onto a
## target square, with feathers/dust spiraling upward through it. Purely
## visual; used by the Revive card's Resurrection phase (Phase 4).
## Spawn via ReviveBeam.tscn as a child of the board, positioned at the
## target square's center. Self-frees when the sequence finishes.

const HEIGHT       := 210.0   # how tall the beam reaches above the tile
const TOP_WIDTH     := 40.0
const BOTTOM_WIDTH  := 16.0
const DESCEND_TIME := 0.42    # beam shoots down into place
const HOLD_TIME    := 0.30    # stays bright while the piece materializes
const FADE_TIME    := 0.45    # eases away afterwards

const COLOR_CORE  = Color(1.0, 0.93, 0.68, 0.9)
const COLOR_EDGE  = Color(0.95, 0.78, 0.30, 0.35)
const COLOR_GROUND_GLOW = Color(1.0, 0.85, 0.4, 0.5)

var _height_frac: float = 0.0   # 0..1 — how far the beam has descended
var _alpha_mult: float  = 1.0   # 1..0 — overall fade multiplier for the finish

@onready var feathers: CPUParticles2D = $Feathers

func _ready() -> void:
	z_index = 6
	z_as_relative = true
	_setup_particles()
	_play()

func _play() -> void:
	var t := create_tween()
	t.tween_method(_set_height_frac, 0.0, 1.0, DESCEND_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_interval(HOLD_TIME)
	t.tween_method(_set_alpha_mult, 1.0, 0.0, FADE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.finished.connect(func():
		if feathers:
			feathers.emitting = false
		queue_free()
	)

func _set_height_frac(v: float) -> void:
	_height_frac = v
	queue_redraw()

func _set_alpha_mult(v: float) -> void:
	_alpha_mult = v
	queue_redraw()

func _draw() -> void:
	var h = HEIGHT * _height_frac
	if h <= 0.5:
		return
	var top_w = TOP_WIDTH * _alpha_mult + BOTTOM_WIDTH * (1.0 - _alpha_mult) * 0.0
	var pts := PackedVector2Array([
		Vector2(-top_w * 0.5, -h),
		Vector2(top_w * 0.5, -h),
		Vector2(BOTTOM_WIDTH * 0.5, 0),
		Vector2(-BOTTOM_WIDTH * 0.5, 0),
	])
	var edge_col = Color(COLOR_EDGE.r, COLOR_EDGE.g, COLOR_EDGE.b, COLOR_EDGE.a * _alpha_mult)
	draw_colored_polygon(pts, edge_col)

	var core_w_top = top_w * 0.4
	var core_w_bot = BOTTOM_WIDTH * 0.4
	var core_pts := PackedVector2Array([
		Vector2(-core_w_top * 0.5, -h),
		Vector2(core_w_top * 0.5, -h),
		Vector2(core_w_bot * 0.5, 0),
		Vector2(-core_w_bot * 0.5, 0),
	])
	var core_col = Color(COLOR_CORE.r, COLOR_CORE.g, COLOR_CORE.b, COLOR_CORE.a * _alpha_mult)
	draw_colored_polygon(core_pts, core_col)

	# Soft glow pooling at the ground where the beam lands.
	var ground_col = Color(COLOR_GROUND_GLOW.r, COLOR_GROUND_GLOW.g, COLOR_GROUND_GLOW.b,
		COLOR_GROUND_GLOW.a * _alpha_mult * _height_frac)
	draw_circle(Vector2.ZERO, 22.0, ground_col)

func _setup_particles() -> void:
	if not feathers:
		return
	feathers.amount               = 18
	feathers.lifetime             = 1.1
	feathers.explosiveness        = 0.05
	feathers.local_coords         = true
	feathers.emission_shape       = CPUParticles2D.EMISSION_SHAPE_SPHERE
	feathers.emission_sphere_radius = 14.0
	feathers.direction             = Vector2(0, -1)
	feathers.spread                = 25.0
	feathers.gravity               = Vector2(0, -14)
	feathers.initial_velocity_min   = 22.0
	feathers.initial_velocity_max   = 48.0
	feathers.angular_velocity_min   = -90.0
	feathers.angular_velocity_max   = 90.0
	feathers.scale_amount_min       = 2.0
	feathers.scale_amount_max       = 3.6
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	grad.colors  = PackedColorArray([
		Color(1.0, 0.93, 0.6, 0.0),
		Color(1.0, 0.9, 0.55, 0.9),
		Color(1.0, 0.85, 0.4, 0.0),
	])
	feathers.color_ramp = grad
	feathers.emitting   = true
