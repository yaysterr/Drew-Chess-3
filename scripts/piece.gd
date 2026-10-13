extends Node2D

@onready var spirte = $Sprite2D

const SPRITE_SIZE = 16
const CELL_SIZE = 66

const X_OFFSET = 33
const Y_OFFSET = 33

@export var piece_type: Globals.PIECE_TYPES
@export var color: Globals.COLORS
@export var board_position: Vector2

var board_handle;

@export var moved: bool;

# En Passant: store the turn this pawn moved two squares
var en_passant_turn: int = -1

# Tracks how many times this piece has moved (used by various effects)
var move_count: int = 0

# ===== Skill Card status flags =====
var status_bounce: bool = false
var status_devour: bool = false
var status_spring_horse: bool = false

# Spell - You and Me
var duel_partner = null
var duel_expires_after_turn: int = -1

# Spell - Revive: remaining turns this piece is Exhausted for. Stacks
# additively (see game.gd's _apply_exhausted). 0 = not exhausted.
var exhausted_turns: int = 0

# Purely visual: opacity of the on-board Exhausted padlock icon. Defaults to
# fully visible so any piece that becomes Exhausted without an explicit
# fade-in (or is cloned mid-simulation) still renders normally. Revive's
# Phase 5 briefly sets this to 0 and tweens it back up to 1.
var exhausted_icon_alpha: float = 1.0

func init_piece(
	type: Globals.PIECE_TYPES,
	col: Globals.COLORS,
	board_pos: Vector2,
	board
):
	piece_type = type
	color = col
	board_position = board_pos
	board_handle = board
	moved = false
	en_passant_turn = -1
	move_count = 0
	status_bounce = false
	status_devour = false
	status_spring_horse = false
	duel_partner = null
	duel_expires_after_turn = -1
	exhausted_turns = 0
	exhausted_icon_alpha = 1.0
	
	update_sprite()
	
	position = Vector2(
		X_OFFSET + board_position[0] * CELL_SIZE,
		Y_OFFSET + board_position[1] * CELL_SIZE,
	)

## True while this piece is Exhausted: cannot move, cannot be targeted by
## friendly card effects, cannot activate abilities, and (if a Bishop)
## cannot be chosen as a Revive anchor.
func is_exhausted() -> bool:
	return exhausted_turns > 0
	
func update_sprite():
	if spirte:
		var texture_path = Globals.SPRITE_MAPPING[color][piece_type]
		spirte.texture = load(texture_path)
		spirte.region_enabled = false
		spirte.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var scale_factor = (CELL_SIZE * 0.85) / 64.0
		spirte.scale = Vector2(scale_factor, scale_factor)

func move_position(to_move: Vector2, animate: bool = true):
	moved = true
	move_count += 1
	board_position = to_move
	var target_pos = Vector2(
		X_OFFSET + board_position[0] * CELL_SIZE,
		Y_OFFSET + board_position[1] * CELL_SIZE,
	)
	if animate:
		var tw = create_tween()
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(self, "position", target_pos, 0.32)
	else:
		position = target_pos
	if piece_type == Globals.PIECE_TYPES.KING:
		board_handle.register_king(board_position, color)
	if piece_type == Globals.PIECE_TYPES.PAWN:
		en_passant_turn = -1  # reset by default

func promote_to(new_type) -> void:
	piece_type = new_type
	update_sprite()

func play_death_animation() -> void:
	# Stop being clickable/targetable immediately so it can't be re-selected mid-animation
	set_process(false)
	set_process_input(false)
	z_index = 100  # render above other pieces while it dies

	var tw = create_tween()
	# Quick punch up, then shrink + fade + tip-over happen together
	tw.tween_property(self, "scale", Vector2(1.3, 1.3), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var fall = create_tween()
	fall.set_parallel(true)
	fall.tween_property(self, "scale", Vector2.ZERO, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_property(self, "rotation_degrees", 40.0 if randf() > 0.5 else -40.0, 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if spirte:
		fall.tween_property(spirte, "modulate:a", 0.0, 0.26).set_trans(Tween.TRANS_QUAD)

	tw.finished.connect(func():
		fall.play()
		fall.finished.connect(queue_free)
	)


func set_board_flipped(flipped: bool) -> void:
	if spirte:
		spirte.rotation_degrees = 180.0 if flipped else 0.0

# ── Magic Circle selection marker (visual only — used by the Sacrifice card
# to show which pieces are currently chosen) ────────────────────────────────
const MAGIC_CIRCLE_SCENE = preload("res://scenes/MagicCircle.tscn")
var _magic_circle_instance = null

func show_magic_selection() -> void:
	if _magic_circle_instance != null:
		return
	var mc = MAGIC_CIRCLE_SCENE.instantiate()
	add_child(mc)
	move_child(mc, 0)  # keep it behind the sprite in draw order too
	_magic_circle_instance = mc

func hide_magic_selection() -> void:
	if _magic_circle_instance != null:
		_magic_circle_instance.fade_out_and_free()
		_magic_circle_instance = null

## Plays a cinematic final-burst effect on this piece's magic circle (instead
## of a plain fade) — used the moment the piece is actually destroyed.
func burst_magic_selection() -> void:
	if _magic_circle_instance != null:
		_magic_circle_instance.play_burst_and_free()
		_magic_circle_instance = null

# ── Revive card VFX (purely visual — no gameplay effect) ──────────────────────
# Gold/purple palettes reused from the shared MagicCircle effect, kept subtle
# and consistent with the rest of the game's soft-glow, no-flash style.
const REVIVE_GOLD_RING  = Color(0.95, 0.80, 0.35, 0.92)
const REVIVE_GOLD_GLOW  = Color(0.95, 0.75, 0.30, 0.45)
const REVIVE_GOLD_RUNE  = Color(1.0, 0.90, 0.55, 0.95)
const REVIVE_GOLD_WAVE  = Color(1.0, 0.85, 0.45, 0.5)
const REVIVE_GOLD_BURST = Color(1.0, 0.88, 0.55, 0.9)

const REVIVE_PURPLE_RING  = Color(0.62, 0.32, 0.85, 0.9)
const REVIVE_PURPLE_GLOW  = Color(0.55, 0.22, 0.75, 0.5)
const REVIVE_PURPLE_RUNE  = Color(0.85, 0.68, 1.0, 0.9)
const REVIVE_PURPLE_WAVE  = Color(0.7, 0.4, 0.9, 0.5)
const REVIVE_PURPLE_BURST = Color(0.78, 0.5, 1.0, 0.85)

const REVIVE_CHARGE_SFX     := preload("res://audio/revive_charge.wav")
const REVIVE_RESURRECT_SFX  := preload("res://audio/revive_resurrect.wav")

var _revive_glow_tween: Tween = null

# Phase 1 — Target Selection. state is one of "valid", "hover", "dim", "none".
func set_revive_glow_state(state: String) -> void:
	if spirte == null:
		return
	var target_mod  := Color(1, 1, 1, 1)
	var target_scale := Vector2.ONE
	match state:
		"valid":
			target_mod = Color(1.16, 1.07, 0.72, 1.0)
		"hover":
			target_mod   = Color(1.4, 1.22, 0.68, 1.0)
			target_scale = Vector2(1.07, 1.07)
		"dim":
			target_mod = Color(0.5, 0.5, 0.56, 1.0)
		_:
			target_mod = Color(1, 1, 1, 1)
	if _revive_glow_tween != null and _revive_glow_tween.is_valid():
		_revive_glow_tween.kill()
	_revive_glow_tween = create_tween()
	_revive_glow_tween.set_parallel(true)
	_revive_glow_tween.tween_property(spirte, "modulate", target_mod, 0.18).set_trans(Tween.TRANS_SINE)
	_revive_glow_tween.tween_property(self, "scale", target_scale, 0.18).set_trans(Tween.TRANS_SINE)

# Phase 2 — Anchor Activation. A large slowly-rotating gold circle appears
# beneath the chosen Bishop, golden particles rise, the Bishop floats gently
# upward, then settles back down. ~1 second total.
func play_revive_anchor_charge() -> void:
	set_process(false)
	var mc = MAGIC_CIRCLE_SCENE.instantiate()
	mc.set_palette(REVIVE_GOLD_RING, REVIVE_GOLD_GLOW, REVIVE_GOLD_RUNE, REVIVE_GOLD_WAVE, REVIVE_GOLD_BURST, 46.0)
	add_child(mc)
	move_child(mc, 0)

	var sfx := AudioStreamPlayer.new()
	sfx.stream     = REVIVE_CHARGE_SFX
	sfx.volume_db  = -12.0
	add_child(sfx)
	sfx.play()
	sfx.finished.connect(sfx.queue_free)

	var base_y = position.y
	var t := create_tween()
	t.tween_property(self, "position:y", base_y - 7.0, 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "position:y", base_y - 3.0, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "position:y", base_y, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await t.finished

	mc.fade_out_and_free()
	set_process(true)

# Phase 4 — Resurrection. The freshly-spawned piece rises up from below and
# fades in, then settles into place with a small landing shockwave.
func play_revive_materialize() -> void:
	set_process(false)
	set_process_input(false)
	var final_pos = position
	position = final_pos + Vector2(0, -34)
	scale    = Vector2(0.86, 0.86)
	if spirte:
		spirte.modulate.a = 0.0

	var sfx := AudioStreamPlayer.new()
	sfx.stream    = REVIVE_RESURRECT_SFX
	sfx.volume_db = -8.0
	add_child(sfx)
	sfx.play()
	sfx.finished.connect(sfx.queue_free)

	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "position", final_pos, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(self, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if spirte:
		t.tween_property(spirte, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await t.finished

	set_process(true)
	set_process_input(true)
	_play_revive_landing_shockwave()

func _play_revive_landing_shockwave() -> void:
	var mc = MAGIC_CIRCLE_SCENE.instantiate()
	mc.set_palette(REVIVE_GOLD_RING, REVIVE_GOLD_GLOW, REVIVE_GOLD_RUNE, REVIVE_GOLD_WAVE, REVIVE_GOLD_BURST, 30.0)
	add_child(mc)
	move_child(mc, 0)
	mc.play_burst_and_free()

# Phase 5 — Exhausted status. A soft purple aura wraps the piece and eases
# into the persistent (already-existing) padlock icon that board.gd draws
# every frame for as long as the piece remains Exhausted. `strong` gives the
# revived piece itself the fuller aura; the anchor Bishop gets a smaller one.
func play_revive_purple_aura(strong: bool = true) -> void:
	var mc = MAGIC_CIRCLE_SCENE.instantiate()
	var radius = 32.0 if strong else 22.0
	mc.set_palette(REVIVE_PURPLE_RING, REVIVE_PURPLE_GLOW, REVIVE_PURPLE_RUNE, REVIVE_PURPLE_WAVE, REVIVE_PURPLE_BURST, radius)
	add_child(mc)
	move_child(mc, 0)
	var hold := create_tween()
	hold.tween_interval(0.5 if strong else 0.35)
	hold.finished.connect(func():
		if is_instance_valid(mc):
			mc.fade_out_and_free()
	)
	fade_in_exhausted_icon()

# Fades the on-board Exhausted padlock icon in smoothly instead of popping it
# in instantly. Purely visual — exhausted_turns (the actual gameplay state)
# is unaffected.
func fade_in_exhausted_icon() -> void:
	exhausted_icon_alpha = 0.0
	var t := create_tween()
	t.tween_method(_set_exhausted_icon_alpha, 0.0, 1.0, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _set_exhausted_icon_alpha(v: float) -> void:
	exhausted_icon_alpha = v
	if board_handle:
		board_handle.queue_redraw()

# Clears any lingering Revive target-glow tint/scale — used on cancel or once
# targeting moves past the Bishop-selection stage.
func clear_revive_glow() -> void:
	if _revive_glow_tween != null and _revive_glow_tween.is_valid():
		_revive_glow_tween.kill()
	if spirte:
		spirte.modulate = Color(1, 1, 1, 1)
	scale = Vector2.ONE

# ── Active Effects (for UI display, e.g. Card Info hover panel) ────────────────
# Any future skill-card effect that follows the existing "status_<name>: bool"
# convention (see "Skill Card status flags" above) is picked up here
# automatically via reflection — no per-effect name needs to be hardcoded.
# Effects that don't fit the simple boolean convention (e.g. the You and Me
# duel, which stores a partner reference rather than a flag) are appended
# as one extra special case below.
func get_active_effects() -> Array:
	var effects: Array = []
	for prop in get_property_list():
		var pname: String = prop.name
		if pname.begins_with("status_") and typeof(get(pname)) == TYPE_BOOL:
			if get(pname):
				effects.append(_effect_label_from_property(pname))
	if duel_partner != null:
		effects.append("You and Me (Duel)")
	if exhausted_turns > 0:
		effects.append("Exhausted (" + str(exhausted_turns) + ")")
	return effects

# Converts a "status_spring_horse" style property name into a readable
# "Spring Horse" label — purely a string transform, not a name lookup table,
# so it needs no updates when new status_* flags are added elsewhere.
func _effect_label_from_property(pname: String) -> String:
	var raw = pname.substr(len("status_"))
	var words = raw.split("_")
	var out = ""
	for w in words:
		if w.is_empty():
			continue
		out += w.substr(0, 1).to_upper() + w.substr(1) + " "
	return out.strip_edges()

func clone(_board):
	var piece = self.duplicate()
	piece.board_handle = _board
	# The magic-circle selection marker is a purely visual child node; strip
	# it from simulation clones so it never runs its own effect logic and
	# never gets mistaken for gameplay state.
	if piece._magic_circle_instance != null:
		piece._magic_circle_instance.queue_free()
		piece._magic_circle_instance = null
	# self.duplicate() should carry these over already, but the check/checkmate
	# simulation (board.clone() -> _king_in_check_on) depends on the clone
	# matching the live piece exactly — copy explicitly so a buff (e.g. Spring
	# Horse) can never silently go missing on the simulated board.
	piece.status_bounce            = status_bounce
	piece.status_devour             = status_devour
	piece.status_spring_horse       = status_spring_horse
	piece.duel_partner              = duel_partner
	piece.duel_expires_after_turn   = duel_expires_after_turn
	piece.move_count                = move_count
	piece.en_passant_turn           = en_passant_turn
	piece.moved                     = moved
	piece.exhausted_turns           = exhausted_turns
	piece.exhausted_icon_alpha      = exhausted_icon_alpha
	return piece
	
func get_moveable_positions():
	match piece_type:
		Globals.PIECE_TYPES.PAWN: return pawn_move_pos()
		Globals.PIECE_TYPES.BISHOP: return bishop_threat_pos()
		Globals.PIECE_TYPES.ROOK: return rook_threat_pos()
		Globals.PIECE_TYPES.KNIGHT: return knight_threat_pos()
		Globals.PIECE_TYPES.QUEEN: return queen_threat_pos()
		Globals.PIECE_TYPES.KING: return king_threat_pos()
		_: return []

func get_threatened_positions():
	match piece_type:
		Globals.PIECE_TYPES.PAWN: return pawn_threat_pos()
		Globals.PIECE_TYPES.BISHOP: return bishop_threat_pos()
		Globals.PIECE_TYPES.ROOK: return rook_threat_pos()
		Globals.PIECE_TYPES.KNIGHT: return knight_threat_pos()
		Globals.PIECE_TYPES.QUEEN: return queen_threat_pos()
		Globals.PIECE_TYPES.KING: return king_threat_pos()
		_: return []


# Pawn Moves
const PAWN_SPOT_INCREMENTS_MOVE = [[0, 1]]
const PAWN_SPOT_INCREMENTS_MOVE_FIRST = [[0, 1], [0, 2]]
const PAWN_SPOT_INCREMENTS_TAKE = [[-1, 1], [1, 1]]

func pawn_threat_pos():
	var positions = []
	
	for inc in PAWN_SPOT_INCREMENTS_TAKE:
		var pos = board_handle.spot_search_threat(
			color,
			board_position[0], board_position[1],
			inc[0], inc[1] if color == Globals.COLORS.BLACK else -inc[1],
			true, false
		)
		if pos != null:
			positions.append(pos)
	return positions

func pawn_move_pos():
	var positions = []
	
	var increments = PAWN_SPOT_INCREMENTS_MOVE if moved else PAWN_SPOT_INCREMENTS_MOVE_FIRST
	for inc in increments:
		var pos = board_handle.spot_search_threat(
			color,
			board_position[0], board_position[1],
			inc[0], inc[1] if color == Globals.COLORS.BLACK else -inc[1],
			false, true
		)
		if pos != null:
			positions.append(pos)
		else:
			break
		
	for inc in PAWN_SPOT_INCREMENTS_TAKE:
		var pos = board_handle.spot_search_threat(
			color,
			board_position[0], board_position[1],
			inc[0], inc[1] if color == Globals.COLORS.BLACK else -inc[1],
			true, false
		)
		if pos != null:
			positions.append(pos)
	
	# En Passant moves
	positions += get_en_passant_positions()
	
	return positions

func get_en_passant_positions():
	var positions = []
	if piece_type != Globals.PIECE_TYPES.PAWN:
		return positions
	
	var direction = 1 if color == Globals.COLORS.BLACK else -1
	
	for dx in [-1, 1]:
		var adj_x = board_position.x + dx
		var adj_y = board_position.y
		if adj_x < 0 or adj_x > 7:
			continue
		var adj_piece = board_handle.get_piece(Vector2(adj_x, adj_y))
		if adj_piece != null and adj_piece.color != color and adj_piece.piece_type == Globals.PIECE_TYPES.PAWN:
			if adj_piece.en_passant_turn == board_handle.current_turn:
				positions.append(Vector2(adj_x, adj_y + direction))
	
	return positions

# Bishop Moves
const BISHOP_BEAM_INCREMENTS = [[1, 1], [1, -1], [-1, 1], [-1, -1]]
func bishop_threat_pos():
	var positions = []
	for inc in BISHOP_BEAM_INCREMENTS:
		positions += board_handle.beam_search_threat(
			color,
			board_position[0], board_position[1],
			inc[0], inc[1]
		)
	return positions

# Rook Moves
const ROOK_BEAM_INCREMENTS = [[0, 1], [0, -1], [1, 0], [-1, 0]]
func rook_threat_pos():
	var positions = []
	for inc in ROOK_BEAM_INCREMENTS:
		positions += board_handle.beam_search_threat(
			color,
			board_position[0], board_position[1],
			inc[0], inc[1]
		)
	return positions

# Knight Moves
const KNIGHT_SPOT_INCREMENTS =[[2, 1], [2, -1], [-2, 1], [-2, -1], [1, 2], [1, -2], [-1, 2], [-1, -2]];
func knight_threat_pos():
	var positions = []
	for inc in KNIGHT_SPOT_INCREMENTS:
		var pos = board_handle.spot_search_threat(
			color,
			board_position[0], board_position[1],
			inc[0], inc[1]
		)
		if pos != null:
			positions.append(pos)
	return positions

# Queen Moves
const QUEEN_BEAM_INCREMENTS = [[1, 1], [1, -1], [-1, 1], [-1, -1], [0, 1], [0, -1], [1, 0], [-1, 0]];
func queen_threat_pos():
	var positions = []
	for inc in QUEEN_BEAM_INCREMENTS:
		positions += board_handle.beam_search_threat(
			color,
			board_position[0], board_position[1],
			inc[0], inc[1]
		)
	return positions

# King Moves
const KING_SPOT_INCREMENTS = [[1, -1], [1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1]];
func king_threat_pos():
	var positions = []
	for inc in KING_SPOT_INCREMENTS:
		var pos = board_handle.spot_search_threat(
			color,
			board_position[0], board_position[1],
			inc[0], inc[1]
		)
		if pos != null:
			positions.append(pos)
	
	# Castling moves
	positions += get_castling_positions()
	
	return positions

func get_castling_positions():
	var positions = []
	if piece_type != Globals.PIECE_TYPES.KING or moved:
		return positions
	
	var row = board_position.y
	
	# Kingside castling
	var rook_ks = board_handle.get_piece(Vector2(7, row))
	if rook_ks != null and rook_ks.piece_type == Globals.PIECE_TYPES.ROOK and rook_ks.color == color and not rook_ks.moved:
		if board_handle.get_piece(Vector2(5, row)) == null and board_handle.get_piece(Vector2(6, row)) == null:
			positions.append(Vector2(6, row))
	
	# Queenside castling
	var rook_qs = board_handle.get_piece(Vector2(0, row))
	if rook_qs != null and rook_qs.piece_type == Globals.PIECE_TYPES.ROOK and rook_qs.color == color and not rook_qs.moved:
		if board_handle.get_piece(Vector2(1, row)) == null and board_handle.get_piece(Vector2(2, row)) == null and board_handle.get_piece(Vector2(3, row)) == null:
			positions.append(Vector2(2, row))
	
	return positions
