extends Node2D

## MagicCircle — procedurally-drawn summoning-circle effect used to mark a
## piece as "selected" while resolving the Sacrifice card, then to play a
## final burst when the sacrifice completes.
## Purely visual: spawn with MagicCircle.tscn, call fade_out_and_free() to
## remove quietly, or play_burst_and_free() for a cinematic finish.

const ROTATE_SPEED      := 0.22    # rad/sec — slow, continuous clockwise turn
const PULSE_PERIOD     := 2.8      # seconds per gentle pulse cycle
const WAVE_PERIOD       := 2.0     # seconds for one energy wave to expand+fade
const FADE_DURATION    := 0.5      # smoother, slower fade in/out
const BURST_DURATION   := 0.55     # final-burst shockwave duration

# Crimson/violet fantasy palette (kept soft & elegant — no bloom, no flashing).
# These were originally consts used only by the Sacrifice card; they're now
# plain instance vars (same default values) so other callers (e.g. Revive)
# can call set_palette() right after instantiate() to reskin the circle —
# gold for an anchor-activation circle, purple for an Exhausted aura —
# without touching Sacrifice's look at all.
var RADIUS   := 34.0
var COLOR_RING   = Color(0.70, 0.22, 0.88, 0.92)
var COLOR_GLOW   = Color(0.80, 0.16, 0.28, 0.55)
var COLOR_RUNE   = Color(1.0, 0.83, 0.48, 0.95)
var COLOR_WAVE   = Color(0.84, 0.36, 0.94, 0.5)
var COLOR_BURST  = Color(0.95, 0.55, 0.35, 0.9)   # warm ember accent for the finale

const RUNE_COUNT := 12

## Reskins the circle. Call BEFORE add_child()'ing the instance into the
## tree (i.e. right after MAGIC_CIRCLE_SCENE.instantiate()), since colors and
## radius are read once particle setup runs in _ready(). Any argument left
## null keeps that channel's default (Sacrifice's crimson/violet palette).
func set_palette(ring = null, glow = null, rune = null, wave = null, burst = null, radius = null) -> void:
	if ring   != null: COLOR_RING  = ring
	if glow   != null: COLOR_GLOW  = glow
	if rune   != null: COLOR_RUNE  = rune
	if wave   != null: COLOR_WAVE  = wave
	if burst  != null: COLOR_BURST = burst
	if radius != null: RADIUS      = radius

var _pulse_t: float    = 0.0
var _wave_timer: float = 0.0
var _waves: Array       = []   # ages (seconds) of active expanding waves

var _bursting: bool     = false
var _burst_progress: float = 0.0

@onready var particles: CPUParticles2D = $Particles

func _ready() -> void:
	z_index       = -1     # render beneath the piece sprite
	z_as_relative = true
	modulate.a    = 0.0
	_setup_particles()
	_fade_in()

func _fade_in() -> void:
	var t := create_tween()
	t.tween_property(self, "modulate:a", 1.0, FADE_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

## Removes the circle quietly — smooth fade out, then frees itself.
## Used when a selection is simply deselected/cancelled (no destruction).
## Safe to call more than once (idempotent).
func fade_out_and_free() -> void:
	if not is_inside_tree():
		return
	set_process(false)
	if particles:
		particles.emitting = false
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, FADE_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.finished.connect(func():
		if is_inside_tree():
			queue_free()
	)

## Plays a satisfying — but still smooth, non-flashy — final burst of
## magical energy (an expanding shockwave, a brief warm glow swell, and a
## one-shot particle burst), then fades out and frees itself. Used exactly
## when the marked piece is actually destroyed.
func play_burst_and_free() -> void:
	if not is_inside_tree():
		return
	set_process(true)
	if particles:
		particles.emitting = false
	_bursting        = true
	_burst_progress  = 0.0

	var burst_particles := CPUParticles2D.new()
	add_child(burst_particles)
	burst_particles.one_shot                = true
	burst_particles.amount                  = 24
	burst_particles.lifetime                = BURST_DURATION + 0.25
	burst_particles.explosiveness           = 1.0
	burst_particles.local_coords            = true
	burst_particles.emission_shape          = CPUParticles2D.EMISSION_SHAPE_SPHERE
	burst_particles.emission_sphere_radius  = RADIUS * 0.25
	burst_particles.direction               = Vector2(0, -1)
	burst_particles.spread                  = 180.0
	burst_particles.gravity                 = Vector2.ZERO
	burst_particles.initial_velocity_min    = 55.0
	burst_particles.initial_velocity_max    = 100.0
	burst_particles.scale_amount_min        = 2.5
	burst_particles.scale_amount_max        = 5.0
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	grad.colors  = PackedColorArray([
		Color(COLOR_BURST.r, COLOR_BURST.g, COLOR_BURST.b, 0.95),
		Color(COLOR_BURST.r, COLOR_BURST.g, COLOR_BURST.b, 0.85),
		Color(COLOR_BURST.r, COLOR_BURST.g, COLOR_BURST.b, 0.0),
	])
	burst_particles.color_ramp = grad
	burst_particles.emitting   = true

	var t := create_tween()
	t.tween_method(_set_burst_progress, 0.0, 1.0, BURST_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.finished.connect(func():
		var t2 := create_tween()
		t2.tween_property(self, "modulate:a", 0.0, FADE_DURATION * 0.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		t2.finished.connect(func():
			if is_inside_tree():
				queue_free()
		)
	)

func _set_burst_progress(v: float) -> void:
	_burst_progress = v

func _process(delta: float) -> void:
	rotation += ROTATE_SPEED * delta

	_pulse_t += delta

	_wave_timer += delta
	if _wave_timer >= WAVE_PERIOD:
		_wave_timer = 0.0
		_waves.append(0.0)
	for i in range(_waves.size() - 1, -1, -1):
		_waves[i] += delta
		if _waves[i] > WAVE_PERIOD:
			_waves.remove_at(i)

	queue_redraw()

func _draw() -> void:
	var pulse       = 0.5 + 0.5 * sin(_pulse_t * TAU / PULSE_PERIOD)  # 0..1, gentle
	# A smooth, bounded brightening during the burst — never a hard flash.
	var burst_swell = 0.0
	if _bursting:
		burst_swell = sin(_burst_progress * PI) * 0.5   # rises then eases back down
	var glow_alpha  = 0.30 + 0.22 * pulse + burst_swell * 0.35
	var ring_scale  = 1.0 + 0.05 * pulse + burst_swell * 0.10

	# Soft layered glow — several translucent concentric fills stand in for
	# bloom without an actual bloom pass (kept elegant, not overpowering).
	for i in range(4):
		var r = RADIUS * ring_scale * (1.0 + i * 0.14)
		var a = glow_alpha * (0.30 - i * 0.06)
		if a > 0.0:
			draw_circle(Vector2.ZERO, r, Color(COLOR_GLOW.r, COLOR_GLOW.g, COLOR_GLOW.b, a))

	# Outer + middle + inner rings
	draw_arc(Vector2.ZERO, RADIUS * ring_scale, 0.0, TAU, 56, COLOR_RING, 2.2, true)
	draw_arc(Vector2.ZERO, RADIUS * ring_scale * 0.82, 0.0, TAU, 48,
		Color(COLOR_RING.r, COLOR_RING.g, COLOR_RING.b, COLOR_RING.a * 0.6), 1.2, true)
	draw_arc(Vector2.ZERO, RADIUS * ring_scale * 0.55, 0.0, TAU, 40,
		Color(COLOR_RING.r, COLOR_RING.g, COLOR_RING.b, COLOR_RING.a * 0.7), 1.5, true)

	# Runic tick marks + tiny glyph tips around the ring
	for i in range(RUNE_COUNT):
		var ang  = (TAU / RUNE_COUNT) * i
		var dir  = Vector2(cos(ang), sin(ang))
		var perp = Vector2(-dir.y, dir.x) * 3.2
		var p1   = dir * (RADIUS * 0.80)
		var p2   = dir * (RADIUS * 0.94)
		draw_line(p1, p2, COLOR_RUNE, 2.0, true)
		var tip = dir * (RADIUS * 1.0)
		draw_polygon(PackedVector2Array([tip - perp, tip + dir * 5.0, tip + perp]),
			PackedColorArray([COLOR_RUNE]))
		# small dot at the inner base of each rune tick for extra detail
		draw_circle(dir * (RADIUS * 0.68), 1.6, Color(COLOR_RUNE.r, COLOR_RUNE.g, COLOR_RUNE.b, 0.6))

	# Inner geometric glyph connecting every other rune point
	var star_pts := PackedVector2Array()
	for i in range(RUNE_COUNT):
		if i % 2 == 0:
			var ang = (TAU / RUNE_COUNT) * i
			star_pts.append(Vector2(cos(ang), sin(ang)) * RADIUS * 0.5)
	for i in range(star_pts.size()):
		draw_line(star_pts[i], star_pts[(i + 1) % star_pts.size()], COLOR_RING, 1.2, true)

	# Subtle energy waves expanding outward from the center
	for age in _waves:
		var t = age / WAVE_PERIOD
		var r = RADIUS * (0.9 + t * 0.9)
		var a = (1.0 - t) * 0.4
		if a > 0.01:
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 44,
				Color(COLOR_WAVE.r, COLOR_WAVE.g, COLOR_WAVE.b, a), 1.5, true)

	# Final-burst shockwave ring — one smooth outward sweep, no flashing
	if _bursting:
		var br = RADIUS * (1.0 + _burst_progress * 2.0)
		var ba = (1.0 - _burst_progress) * 0.7
		if ba > 0.01:
			draw_arc(Vector2.ZERO, br, 0.0, TAU, 56,
				Color(COLOR_BURST.r, COLOR_BURST.g, COLOR_BURST.b, ba), 2.2, true)

func _setup_particles() -> void:
	if not particles:
		return
	particles.amount                 = 14         # still lightweight
	particles.lifetime               = 2.6
	particles.preprocess             = 1.3
	particles.speed_scale            = 1.0
	particles.explosiveness          = 0.0
	particles.randomness             = 0.6
	particles.local_coords           = true
	particles.emission_shape         = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = RADIUS * 0.8
	particles.direction               = Vector2(0, -1)
	particles.spread                  = 180.0
	particles.gravity                 = Vector2(0, -4)
	particles.initial_velocity_min    = 2.0
	particles.initial_velocity_max    = 7.0
	particles.scale_amount_min        = 2.0
	particles.scale_amount_max        = 4.2
	var base = Color(COLOR_RUNE.r, COLOR_RUNE.g, COLOR_RUNE.b)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	grad.colors  = PackedColorArray([
		Color(base.r, base.g, base.b, 0.0),
		Color(base.r, base.g, base.b, 0.8),
		Color(base.r, base.g, base.b, 0.0),
	])
	particles.color_ramp = grad
	particles.emitting   = true
