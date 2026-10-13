extends Node2D

## Animated backdrop for the main menu:
## - faint checkerboard wash
## - drifting/rotating real chess piece sprites (parallax depth)
## - rising glowing ember particles
## - pulsing peach border frame around the whole screen

const VIEWPORT_SIZE = Vector2(1280, 800)

# ---- Checkerboard wash ----
const CELL_SIZE = 80
const COLOR_DARK  = Color(0.196, 0.161, 0.278, 0.45)
const COLOR_LIGHT = Color(1.0, 1.0, 1.0, 0.035)

# ---- Border frame ----
const COLOR_BORDER = Color(1.0, 0.710, 0.439)
const BORDER_MARGIN = 18.0

# ---- Floating pieces ----
var piece_paths = [
	"res://pieces_new/W-King64x64.png",
	"res://pieces_new/B-Queen64x64.png",
	"res://pieces_new/W-Knight.png",
	"res://pieces_new/B-bishop64x64.png",
	"res://pieces_new/W-Rook.png",
	"res://pieces_new/B-Pawn.png",
	"res://pieces_new/W-Bishop.png",
	"res://pieces_new/B-knight.png",
]

class FloatingPiece:
	var texture: Texture2D
	var pos: Vector2
	var speed: float
	var scale_amt: float
	var alpha: float
	var rot: float
	var rot_speed: float
	var drift_x: float
	var drift_phase: float

var floating_pieces: Array = []

# ---- Embers ----
class Ember:
	var pos: Vector2
	var speed: float
	var radius: float
	var alpha: float
	var phase: float

var embers: Array = []

var time_elapsed: float = 0.0
var rng = RandomNumberGenerator.new()

func _ready():
	rng.randomize()
	_spawn_floating_pieces(7)
	_spawn_embers(28)
	queue_redraw()

func _process(delta):
	time_elapsed += delta

	for p in floating_pieces:
		p.pos.y -= p.speed * delta
		p.rot += p.rot_speed * delta
		if p.pos.y < -120:
			p.pos.y = VIEWPORT_SIZE.y + 120
			p.pos.x = rng.randf_range(40, VIEWPORT_SIZE.x - 40)

	for e in embers:
		e.pos.y -= e.speed * delta
		if e.pos.y < -20:
			e.pos.y = VIEWPORT_SIZE.y + 20
			e.pos.x = rng.randf_range(0, VIEWPORT_SIZE.x)

	queue_redraw()

func _spawn_floating_pieces(count: int) -> void:
	for i in range(count):
		var fp = FloatingPiece.new()
		fp.texture = load(piece_paths[i % piece_paths.size()])
		fp.pos = Vector2(
			rng.randf_range(60, VIEWPORT_SIZE.x - 60),
			rng.randf_range(0, VIEWPORT_SIZE.y)
		)
		fp.speed = rng.randf_range(8.0, 22.0)
		fp.scale_amt = rng.randf_range(0.9, 2.0)
		fp.alpha = rng.randf_range(0.08, 0.18)
		fp.rot = rng.randf_range(0, TAU)
		fp.rot_speed = rng.randf_range(-0.15, 0.15)
		fp.drift_x = rng.randf_range(8.0, 20.0)
		fp.drift_phase = rng.randf_range(0, TAU)
		floating_pieces.append(fp)

func _spawn_embers(count: int) -> void:
	for i in range(count):
		var e = Ember.new()
		e.pos = Vector2(
			rng.randf_range(0, VIEWPORT_SIZE.x),
			rng.randf_range(0, VIEWPORT_SIZE.y)
		)
		e.speed = rng.randf_range(10.0, 36.0)
		e.radius = rng.randf_range(1.2, 3.0)
		e.alpha = rng.randf_range(0.25, 0.65)
		e.phase = rng.randf_range(0, TAU)
		embers.append(e)

func _draw():
	# --- checkerboard wash ---
	var cols = int(ceil(VIEWPORT_SIZE.x / CELL_SIZE)) + 1
	var rows = int(ceil(VIEWPORT_SIZE.y / CELL_SIZE)) + 1
	for row in range(rows):
		for col in range(cols):
			var is_dark = (row + col) % 2 == 1
			var color = COLOR_DARK if is_dark else COLOR_LIGHT
			draw_rect(Rect2(col * CELL_SIZE, row * CELL_SIZE, CELL_SIZE, CELL_SIZE), color)

	# --- floating chess pieces (drawn behind embers, in front of checker wash) ---
	for p in floating_pieces:
		var wobble = sin(time_elapsed * 0.6 + p.drift_phase) * p.drift_x
		var draw_pos = Vector2(p.pos.x + wobble, p.pos.y)
		var tex_size = p.texture.get_size()
		var draw_scale = p.scale_amt
		draw_set_transform(draw_pos, p.rot, Vector2(draw_scale, draw_scale))
		draw_texture(p.texture, -tex_size * 0.5, Color(1, 1, 1, p.alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# --- rising embers ---
	for e in embers:
		var flicker = 0.6 + 0.4 * sin(time_elapsed * 3.0 + e.phase)
		draw_circle(e.pos, e.radius, Color(1.0, 0.710, 0.439, e.alpha * flicker))

	# --- soft glow band behind the title area ---
	var glow_pulse = 0.6 + 0.4 * sin(time_elapsed * 1.4)
	var glow_center_y = 330.0
	for i in range(6):
		var band_h = 90.0 - i * 12.0
		var band_alpha = 0.05 * glow_pulse * (1.0 - i / 6.0)
		draw_rect(
			Rect2(0, glow_center_y - band_h * 0.5, VIEWPORT_SIZE.x, band_h),
			Color(1.0, 0.710, 0.439, band_alpha)
		)

	# --- vignette darkening top/bottom edges for contrast ---
	draw_rect(Rect2(0, 0, VIEWPORT_SIZE.x, 60), Color(0, 0, 0, 0.18))
	draw_rect(Rect2(0, VIEWPORT_SIZE.y - 60, VIEWPORT_SIZE.x, 60), Color(0, 0, 0, 0.18))

	# --- pulsing border frame ---
	var pulse = 0.7 + 0.3 * sin(time_elapsed * 1.8)
	var border_width = 2.0 + pulse * 1.5
	draw_rect(
		Rect2(
			BORDER_MARGIN, BORDER_MARGIN,
			VIEWPORT_SIZE.x - BORDER_MARGIN * 2,
			VIEWPORT_SIZE.y - BORDER_MARGIN * 2
		),
		Color(COLOR_BORDER.r, COLOR_BORDER.g, COLOR_BORDER.b, 0.55 + 0.35 * pulse),
		false, border_width
	)
	# faint outer glow ring
	draw_rect(
		Rect2(
			BORDER_MARGIN - 4, BORDER_MARGIN - 4,
			VIEWPORT_SIZE.x - (BORDER_MARGIN - 4) * 2,
			VIEWPORT_SIZE.y - (BORDER_MARGIN - 4) * 2
		),
		Color(COLOR_BORDER.r, COLOR_BORDER.g, COLOR_BORDER.b, 0.12 * pulse),
		false, 6.0
	)
