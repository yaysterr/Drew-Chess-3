extends Node2D

@export var pieces = []
@export var piece_scene = preload("res://scenes/Piece.tscn")

@export var white_king_pos: Vector2
@export var black_king_pos: Vector2

const CELL_SIZE    = 66
const BOARD_COLS   = 8
const BOARD_ROWS   = 8

# Colors
const COLOR_DARK          = Color(0.196, 0.161, 0.278)
const COLOR_LIGHT         = Color(1.0,   1.0,   1.0  )
const COLOR_BOARD_BACKING = Color(0.122, 0.094, 0.176)
const COLOR_BORDER        = Color(1.0,   0.710, 0.439)
const BORDER_WIDTH        = 2.0
const BORDER_MARGIN       = 14.0

# Highlights
const COLOR_HIGHLIGHT_MOVE    = Color(1.0, 0.92, 0.4,  0.60)
const COLOR_HIGHLIGHT_CAPTURE = Color(1.0, 0.85, 0.2,  0.70)
const COLOR_HIGHLIGHT_SPECIAL = Color(0.4, 0.90, 1.0,  0.65)

# Land Mine card marker colors
const COLOR_MINE      = Color(0.886, 0.345, 0.412, 0.55)
const COLOR_MINE_MARK = Color(0.094, 0.063, 0.137, 0.9)

# Skill-card status marker colors
const COLOR_STATUS_BOUNCE = Color(0.4, 0.85, 1.0, 0.95)
const COLOR_STATUS_DEVOUR = Color(1.0, 0.55, 0.25, 0.95)
const COLOR_STATUS_SPRING = Color(0.55, 0.9, 0.45, 0.95)
const COLOR_STATUS_DUEL   = Color(1.0, 0.85, 0.3, 0.9)
const COLOR_STATUS_EXHAUSTED = Color(0.55, 0.55, 0.62, 0.95)

var highlight_moves    : Array = []
var highlight_captures : Array = []
var highlight_special  : Array = []

# Revive card, Phase 3 — the square currently under the mouse while picking
# the revival destination gets an extra golden pulse ring (on top of the
# normal yellow "valid square" dot every targeted-square card already uses).
var revive_hover_square: Vector2 = Vector2(-1, -1)
var _revive_pulse_t: float = 0.0

# Board flip (black plays from bottom)
var flipped: bool = false

# Turn tracking for en passant
var current_turn: int = 0

# Land Mine state
var mines: Array = []

# Cloak / placement / explosion animation state, keyed by "x,y" square string
# so it survives mine dict rebuilds. Values are floats/bools only — purely
# visual, no gameplay effect.
var _mine_reveal_alpha: Dictionary = {}   # square key -> current fade alpha (0..1)
var _mine_revealed_target: Dictionary = {} # square key -> target bool (enemy nearby?)
var _mine_place_t: Dictionary = {}         # square key -> seconds since placement
const MINE_REVEAL_FADE_SPEED := 2.6   # ~0.4s smooth fade, no hard flash
const MINE_PLACE_ANIM_TIME   := 0.7   # rune + materialize glow duration

var mine_explosions: Array = []   # [{pos, t}], t counts up from 0
const MINE_EXPLOSION_TIME := 0.6

# Human player's own turn counter — used for mine-reveal flicker and duel display
var current_player_turn: int = 0

# ── Coordinate helpers ────────────────────────────────────────────────────────
func col_to_file(col: int) -> String:
	return char(ord('a') + col)

func row_to_rank(row: int) -> String:
	return str(BOARD_ROWS - row)

func cell_name(col: int, row: int) -> String:
	return col_to_file(col) + row_to_rank(row)

# ── Highlight API ─────────────────────────────────────────────────────────────
func show_highlights(move_pos: Array, cap_pos: Array, special_pos: Array = []) -> void:
	highlight_moves    = move_pos
	highlight_captures = cap_pos
	highlight_special  = special_pos
	queue_redraw()

func clear_highlights() -> void:
	highlight_moves    = []
	highlight_captures = []
	highlight_special  = []

func set_revive_hover_square(sq: Vector2) -> void:
	if revive_hover_square == sq:
		return
	revive_hover_square = sq
	queue_redraw()

func clear_revive_hover_square() -> void:
	if revive_hover_square.x < 0:
		return
	revive_hover_square = Vector2(-1, -1)
	queue_redraw()

# Only ticks (and only redraws every frame) while a Revive square-hover pulse
# is actually active — cheap the rest of the time.
func _process(delta: float) -> void:
	if revive_hover_square.x >= 0:
		_revive_pulse_t += delta
		queue_redraw()

	for key in _mine_revealed_target.keys():
		var target = 1.0 if _mine_revealed_target[key] else 0.0
		var current = _mine_reveal_alpha.get(key, 0.0)
		_mine_reveal_alpha[key] = move_toward(current, target, MINE_REVEAL_FADE_SPEED * delta)

	for key in _mine_place_t.keys():
		if _mine_place_t[key] < MINE_PLACE_ANIM_TIME:
			_mine_place_t[key] += delta

	for i in range(mine_explosions.size() - 1, -1, -1):
		mine_explosions[i].t += delta
		if mine_explosions[i].t >= MINE_EXPLOSION_TIME:
			mine_explosions.remove_at(i)

	queue_redraw()

func _mine_key(pos: Vector2) -> String:
	return str(int(pos.x)) + "," + str(int(pos.y))

# Called whenever a mine is placed — starts its cloak hidden with a brief
# materialize glow, rather than snapping instantly invisible.
func register_mine_placed(pos: Vector2) -> void:
	var key = _mine_key(pos)
	_mine_place_t[key] = 0.0
	_mine_revealed_target[key] = false
	_mine_reveal_alpha[key] = 0.0
	GameplaySfx.play_land_mine_place()

func clear_mine_state(pos: Vector2) -> void:
	var key = _mine_key(pos)
	_mine_revealed_target.erase(key)
	_mine_reveal_alpha.erase(key)
	_mine_place_t.erase(key)

# Smoothly reveals (enemy piece within detection radius) or re-cloaks
# (no enemy nearby) a mine. Gameplay is unaffected either way — this only
# drives the fade in _draw().
func set_mine_revealed(pos: Vector2, revealed: bool) -> void:
	_mine_revealed_target[_mine_key(pos)] = revealed

func trigger_mine_explosion(pos: Vector2) -> void:
	mine_explosions.append({"pos": pos, "t": 0.0})
	clear_mine_state(pos)
	GameplaySfx.play_land_mine_explosion()

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready():
	queue_redraw()
	init_pieces()

func apply_flip_to_pieces() -> void:
	for p in pieces:
		p.set_board_flipped(flipped)

func _draw():
	var board_px = CELL_SIZE * BOARD_COLS

	# Backing
	draw_rect(
		Rect2(-BORDER_MARGIN, -BORDER_MARGIN,
			  board_px + BORDER_MARGIN * 2,
			  board_px + BORDER_MARGIN * 2),
		COLOR_BOARD_BACKING
	)

	# Checkerboard
	for row in range(BOARD_ROWS):
		for col in range(BOARD_COLS):
			var is_dark = (row + col) % 2 == 1
			var c       = COLOR_DARK if is_dark else COLOR_LIGHT
			draw_rect(Rect2(col * CELL_SIZE, row * CELL_SIZE, CELL_SIZE, CELL_SIZE), c)

	# Border frame
	draw_rect(
		Rect2(
			-BORDER_MARGIN + BORDER_WIDTH * 0.5,
			-BORDER_MARGIN + BORDER_WIDTH * 0.5,
			board_px + BORDER_MARGIN * 2 - BORDER_WIDTH,
			board_px + BORDER_MARGIN * 2 - BORDER_WIDTH
		),
		COLOR_BORDER, false, BORDER_WIDTH
	)

	# Chess notation labels — Files (a‥h) along the bottom
	# NOTE: The board container itself is rotated 180° by game.gd when the
	# player is Black, which already moves every cell (and its label) to the
	# correct flipped screen position. We must NOT also swap which letter/
	# number goes in which column/row here, or labels end up paired with the
	# wrong square. We only need to counter-rotate the glyph itself so the
	# text doesn't render upside-down inside the rotated container.
	for col in range(BOARD_COLS):
		var label_pos = Vector2(col * CELL_SIZE + CELL_SIZE * 0.5 - 5, board_px + 3.0)
		var txt = col_to_file(col)
		if flipped:
			draw_set_transform(label_pos, PI, Vector2.ONE)
			draw_string(
				ThemeDB.fallback_font, Vector2.ZERO, txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_BORDER
			)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_string(
				ThemeDB.fallback_font, label_pos, txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_BORDER
			)

	# Ranks (1‥8) along the left edge
	for row in range(BOARD_ROWS):
		var label_pos = Vector2(-BORDER_MARGIN + 1.0, row * CELL_SIZE + CELL_SIZE * 0.5 + 5)
		var txt = row_to_rank(row)
		if flipped:
			draw_set_transform(label_pos, PI, Vector2.ONE)
			draw_string(
				ThemeDB.fallback_font, Vector2.ZERO, txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_BORDER
			)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_string(
				ThemeDB.fallback_font, label_pos, txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_BORDER
			)

	# ── Move highlights ───────────────────────────────────────────────────────
	var dot_r = CELL_SIZE * 0.18
	for pos in highlight_moves:
		var vp = pos
		draw_circle(
			Vector2(vp.x * CELL_SIZE + CELL_SIZE * 0.5, vp.y * CELL_SIZE + CELL_SIZE * 0.5),
			dot_r, COLOR_HIGHLIGHT_MOVE
		)

	var ring_w = 3.0
	for pos in highlight_captures:
		var vp = pos
		draw_rect(
			Rect2(vp.x * CELL_SIZE + ring_w * 0.5,
				  vp.y * CELL_SIZE + ring_w * 0.5,
				  CELL_SIZE - ring_w,
				  CELL_SIZE - ring_w),
			COLOR_HIGHLIGHT_CAPTURE, false, ring_w
		)

	# Revive card, Phase 3 — golden pulse ring under the hovered valid square
	if revive_hover_square.x >= 0:
		var rvp = revive_hover_square
		var center = Vector2(rvp.x * CELL_SIZE + CELL_SIZE * 0.5, rvp.y * CELL_SIZE + CELL_SIZE * 0.5)
		var pulse = 0.5 + 0.5 * sin(_revive_pulse_t * TAU / 0.9)
		var r = CELL_SIZE * 0.40 * (1.0 + 0.08 * pulse)
		draw_circle(center, r, Color(1.0, 0.85, 0.35, 0.16 + 0.14 * pulse))
		draw_arc(center, r, 0.0, TAU, 40, Color(1.0, 0.92, 0.55, 0.55 + 0.3 * pulse), 2.4, true)

	for pos in highlight_special:
		var vp = pos
		draw_circle(
			Vector2(vp.x * CELL_SIZE + CELL_SIZE * 0.5, vp.y * CELL_SIZE + CELL_SIZE * 0.5),
			dot_r * 1.2, COLOR_HIGHLIGHT_SPECIAL
		)

	# Land Mine markers — hidden by Cloak; fade smoothly into view only while
	# an enemy piece sits within the 3x3 detection radius (see set_mine_revealed).
	for m in mines:
		var pos = m.pos
		var key = _mine_key(pos)
		var alpha = _mine_reveal_alpha.get(key, 0.0)
		var place_t = _mine_place_t.get(key, MINE_PLACE_ANIM_TIME)
		var center = Vector2(pos.x * CELL_SIZE + CELL_SIZE * 0.5,
							 pos.y * CELL_SIZE + CELL_SIZE * 0.5)

		# Brief materialize glow + rune ring right after placement, independent
		# of Cloak fade so the player always sees their own mine land.
		if place_t < MINE_PLACE_ANIM_TIME:
			var pt = place_t / MINE_PLACE_ANIM_TIME
			var glow_alpha = 1.0 - pt
			var ring_r = CELL_SIZE * (0.30 + 0.22 * pt)
			draw_circle(center, ring_r, Color(1.0, 0.85, 0.4, 0.20 * glow_alpha))
			draw_arc(center, ring_r, 0.0, TAU, 28, Color(1.0, 0.92, 0.55, 0.7 * glow_alpha), 2.0, true)
			# small rune tick marks fading outward
			for k in range(4):
				var ang = TAU * float(k) / 4.0 + pt * 1.4
				var rp = center + Vector2(cos(ang), sin(ang)) * ring_r
				draw_circle(rp, 2.2, Color(1.0, 0.92, 0.6, 0.8 * glow_alpha))

		if alpha <= 0.01:
			continue
		var r = CELL_SIZE * 0.22
		var diamond = PackedVector2Array([
			center + Vector2(0, -r), center + Vector2(r, 0),
			center + Vector2(0, r), center + Vector2(-r, 0)
		])
		draw_colored_polygon(diamond, Color(COLOR_MINE.r, COLOR_MINE.g, COLOR_MINE.b, COLOR_MINE.a * alpha))
		draw_line(center + Vector2(-r * 0.6, -r * 0.6), center + Vector2(r * 0.6, r * 0.6),
				  Color(COLOR_MINE_MARK.r, COLOR_MINE_MARK.g, COLOR_MINE_MARK.b, COLOR_MINE_MARK.a * alpha), 2.0)
		draw_line(center + Vector2(r * 0.6, -r * 0.6), center + Vector2(-r * 0.6, r * 0.6),
				  Color(COLOR_MINE_MARK.r, COLOR_MINE_MARK.g, COLOR_MINE_MARK.b, COLOR_MINE_MARK.a * alpha), 2.0)

	# Explosion shockwave — expanding, fading ring + a few scattering embers.
	# No screen shake, no hard flash; alpha ramps down smoothly across MINE_EXPLOSION_TIME.
	for ex in mine_explosions:
		var pos = ex.pos
		var t = ex.t / MINE_EXPLOSION_TIME
		var center = Vector2(pos.x * CELL_SIZE + CELL_SIZE * 0.5,
							 pos.y * CELL_SIZE + CELL_SIZE * 0.5)
		var fade = 1.0 - t
		var ring_r = CELL_SIZE * (0.15 + 0.85 * t)
		draw_circle(center, ring_r * 0.5, Color(1.0, 0.55, 0.25, 0.22 * fade))
		draw_arc(center, ring_r, 0.0, TAU, 32, Color(1.0, 0.75, 0.3, 0.85 * fade), 3.0, true)
		for k in range(8):
			var ang = TAU * float(k) / 8.0
			var ember_r = ring_r * 0.9
			var ember = center + Vector2(cos(ang), sin(ang)) * ember_r
			draw_circle(ember, 2.6 * fade + 0.5, Color(1.0, 0.8, 0.4, 0.9 * fade))

	# Skill-card status markers
	for p in pieces:
		var vp = p.board_position
		var cell_x = vp.x * CELL_SIZE
		var cell_y = vp.y * CELL_SIZE
		var dot_y = cell_y + 9
		if p.status_bounce:
			draw_circle(Vector2(cell_x + 10, dot_y), 4.0, COLOR_STATUS_BOUNCE)
		if p.status_devour:
			draw_circle(Vector2(cell_x + 21, dot_y), 4.0, COLOR_STATUS_DEVOUR)
		if p.status_spring_horse:
			draw_circle(Vector2(cell_x + 32, dot_y), 4.0, COLOR_STATUS_SPRING)
		if p.duel_partner != null and current_player_turn <= p.duel_expires_after_turn:
			draw_rect(Rect2(cell_x + 3, cell_y + 3, CELL_SIZE - 6, CELL_SIZE - 6), COLOR_STATUS_DUEL, false, 2.0)
		if p.is_exhausted():
			_draw_exhausted_icon(Vector2(cell_x + CELL_SIZE - 12, cell_y + 9), p.exhausted_icon_alpha, p.exhausted_turns)

# Small padlock glyph (arc "shackle" + filled "body") marking an Exhausted
# piece — reads clearly as "restrained" at a glance, distinct from the plain
# status dots used by the other skill-card effects above. `alpha` lets the
# Revive card fade this in smoothly rather than popping in instantly; the
# remaining-turns counter is drawn just beside it.
func _draw_exhausted_icon(center: Vector2, alpha: float = 1.0, turns: int = 0) -> void:
	if alpha <= 0.01:
		return
	var col = Color(COLOR_STATUS_EXHAUSTED.r, COLOR_STATUS_EXHAUSTED.g, COLOR_STATUS_EXHAUSTED.b, COLOR_STATUS_EXHAUSTED.a * alpha)
	var body = Rect2(center + Vector2(-4, -1), Vector2(8, 6))
	draw_rect(body, col, true)
	draw_arc(center + Vector2(0, -2), 3.2, PI, TAU, 12, col, 1.6, true)
	if turns > 0:
		draw_string(ThemeDB.fallback_font, center + Vector2(6, 3), str(turns),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(col.r, col.g, col.b, col.a))

# ── Piece initialisation ──────────────────────────────────────────────────────
func init_pieces():
	for pt in Globals.INITIAL_PIECE_SET_SINGLE:
		var piece_type = pt[0]
		var black_pos = Vector2(pt[1], pt[2])
		var white_pos = Vector2(pt[1], BOARD_ROWS - 1 - pt[2])

		var bp = piece_scene.instantiate()
		add_child(bp)
		bp.init_piece(piece_type, Globals.COLORS.BLACK, black_pos, self)
		pieces.append(bp)

		var wp = piece_scene.instantiate()
		add_child(wp)
		wp.init_piece(piece_type, Globals.COLORS.WHITE, white_pos, self)
		pieces.append(wp)

		if piece_type == Globals.PIECE_TYPES.KING:
			register_king(white_pos, Globals.COLORS.WHITE)
			register_king(black_pos, Globals.COLORS.BLACK)

func register_king(pos, col):
	if col == Globals.COLORS.WHITE:
		white_king_pos = pos
	else:
		black_king_pos = pos

# ── Piece queries ─────────────────────────────────────────────────────────────
func get_piece(pos: Vector2):
	for piece in pieces:
		if piece.board_position == pos:
			return piece
	return null

# Instantiates and places a brand-new piece at an empty square — the same
# instantiate/add_child/init_piece pattern used by init_pieces(), just
# reusable at any time. Used by the Revive card. Caller must ensure `pos`
# is actually empty.
func spawn_piece(piece_type, color, pos: Vector2):
	var p = piece_scene.instantiate()
	add_child(p)
	p.init_piece(piece_type, color, pos, self)
	p.set_board_flipped(flipped)
	pieces.append(p)
	queue_redraw()
	return p

# Revive card, Phase 4 — spawns the descending beam-of-light effect on the
# target square, just before the revived piece appears there. Purely visual.
const REVIVE_BEAM_SCENE = preload("res://scenes/ReviveBeam.tscn")
func spawn_revive_beam(pos: Vector2) -> Node:
	var beam = REVIVE_BEAM_SCENE.instantiate()
	add_child(beam)
	beam.position = Vector2(pos.x * CELL_SIZE + CELL_SIZE * 0.5, pos.y * CELL_SIZE + CELL_SIZE * 0.5)
	return beam

func delete_piece(piece, animate: bool = true):
	for i in range(pieces.size()):
		if pieces[i] == piece:
			pieces.pop_at(i)
			if animate and is_instance_valid(piece) and piece.is_inside_tree():
				piece.play_death_animation()
			else:
				piece.queue_free()
			return

# ── Threat search ─────────────────────────────────────────────────────────────
func beam_search_threat(own_color, cur_x, cur_y, inc_x, inc_y) -> Array:
	var threat = []
	cur_x += inc_x
	cur_y += inc_y
	while cur_x >= 0 and cur_x < 8 and cur_y >= 0 and cur_y < 8:
		var p = get_piece(Vector2(cur_x, cur_y))
		if p != null:
			if p.color != own_color:
				threat.append(Vector2(cur_x, cur_y))
			break
		threat.append(Vector2(cur_x, cur_y))
		cur_x += inc_x
		cur_y += inc_y
	return threat

func spot_search_threat(own_color, cur_x, cur_y, inc_x, inc_y,
						 threat_only = false, free_only = false):
	cur_x += inc_x
	cur_y += inc_y
	if cur_x < 0 or cur_x >= 8 or cur_y < 0 or cur_y >= 8:
		return null
	var pos = Vector2(cur_x, cur_y)
	var p   = get_piece(pos)
	if p != null:
		if free_only:
			return null
		return pos if p.color != own_color else null
	return pos if not threat_only else null

# ── Clone for move validation ─────────────────────────────────────────────────
func clone():
	var b = self.duplicate()
	b.current_turn = current_turn
	b.mines = mines.duplicate()
	b.current_player_turn = current_player_turn
	for i in range(pieces.size()):
		b.pieces[i] = pieces[i].clone(b)
	return b
