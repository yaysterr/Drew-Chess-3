extends Node2D

# Hand card layout — cards auto-shrink so the hand always fits inside its
# panel instead of spilling off-screen when hand size temporarily exceeds
# Globals.MAX_HAND_SIZE (e.g. right before a forced discard).
const HAND_CARD_BASE_SIZE: Vector2 = Vector2(64, 90)
const HAND_CARD_MIN_WIDTH: float   = 40.0
const HAND_LIST_WIDTH: float       = 304.0   # matches WhiteHandList / BlackHandList rect width
const HAND_CARD_BASE_SEP: int      = 12
const HAND_CARD_MIN_SEP: int       = 4

# Returns {"size": Vector2, "sep": int} sized so `count` cards (at that size
# and separation) fit within HAND_LIST_WIDTH.
func _hand_card_layout(count: int) -> Dictionary:
	var sep: int = HAND_CARD_BASE_SEP
	var w: float = HAND_CARD_BASE_SIZE.x
	var h: float = HAND_CARD_BASE_SIZE.y
	if count <= 0:
		return {"size": Vector2(w, h), "sep": sep}

	var total: float = count * w + max(count - 1, 0) * sep
	if total > HAND_LIST_WIDTH:
		sep = HAND_CARD_MIN_SEP
		total = count * w + max(count - 1, 0) * sep
		if total > HAND_LIST_WIDTH:
			w = (HAND_LIST_WIDTH - max(count - 1, 0) * sep) / count
			w = max(w, HAND_CARD_MIN_WIDTH)
			h = w * (HAND_CARD_BASE_SIZE.y / HAND_CARD_BASE_SIZE.x)
	return {"size": Vector2(w, h), "sep": sep}

# Game States
var game_over: bool = false
var player_color
var status          # whose turn it is right now (COLORS.WHITE or BLACK)
var player2_type
var turn_count: int = 0   # 1 Turn = one side (White OR Black) makes one move
var round_count: int = 1  # 1 Round = White moves once AND Black moves once
var board_flipped: bool = false
var must_draw_first: bool = false  # ต้อง draw หรือ discard ก่อนเดินหมากทุกเทิร์น

# Turn state machine: Draw Phase -> Cleanup Phase -> Move Phase
enum TurnPhase { DRAW, CLEANUP, MOVE }
var turn_phase: int = TurnPhase.MOVE
var cleanup_discard_active: bool = false  # true while Cleanup Phase forces a discard down to MAX_HAND_SIZE
var has_cycled_this_turn: bool = false    # Cycling: exactly 1 use per turn, resets each turn
var cycling_active: bool = false          # true while the player is mid-Cycling card selection

# Input state — supports both Drag & Drop and Click-to-Move
var is_dragging: bool = false
var selected_piece = null
var previous_position = null
var click_selected_piece = null

# Promotion
var promotion_pending: bool = false
var promotion_piece = null

# Card Info panel — piece hover (see _process / _update_card_info_for_hovered_piece)
var _hovered_piece = null
var _card_hover_active: bool = false  # true while a hand-card button is being hovered

# True while the Sacrifice card's cinematic resolution animation is playing —
# input is locked so the player can't act on pieces mid-destruction.
var sacrifice_resolving: bool = false

# True while the Revive card's cinematic anchor-activation or resurrection
# animation is playing — input is locked, same as sacrifice_resolving above.
var revive_resolving: bool = false

# Revive card, Phase 1 — tracks which valid Bishop is currently hovered so
# its glow can be intensified (and un-intensified when the mouse moves off).
var _revive_hovered_bishop = null

@onready var board               = $BoardContainer/Board
@onready var board_container     = $BoardContainer
@onready var ui_control          = $UI/Control
@onready var overlay_panel       = $UI/Control/OverlayPanel
@onready var result_icon         = $UI/Control/ResultIcon
@onready var result_title        = $UI/Control/ResultTitle
@onready var result_subtitle     = $UI/Control/ResultSubtitle
@onready var divider             = $UI/Control/Divider
@onready var turn_label          = $UI/TurnPanel/TurnLabel
@onready var active_turn_label   = $UI/ActiveTurnLabel
@onready var promotion_panel     = $UI/PromotionPanel
@onready var side_panel          = $UI/SidePanel
@onready var coord_label         = $UI/CoordLabel
@onready var back_menu_btn       = $UI/BackMenuButton
@onready var white_card          = $UI/SidePanel/CardsRow/WhiteCard
@onready var black_card          = $UI/SidePanel/CardsRow/BlackCard

# Card UI nodes
@onready var deck_pile             = $UI/DeckPile
@onready var hand_list             = $UI/HandList
@onready var white_hand_panel      = $UI/WhiteHandPanel
@onready var white_hand_list       = $UI/WhiteHandList
@onready var black_hand_panel      = $UI/BlackHandPnl
@onready var black_hand_list       = $UI/BlackHandList
@onready var white_sp_label        = $UI/WhiteSPLabel
@onready var black_sp_label        = $UI/BlackSPLabel
@onready var white_sp_pips         = $UI/WhiteSPPips
@onready var black_sp_pips         = $UI/BlackSPPips
@onready var player_sp_label       = $UI/PlayerSPLabel
@onready var player_sp_pips        = $UI/PlayerSPPips
@onready var card_status_label     = $UI/StatusNotifyPanel/CardStatusLabel
@onready var discard_draw_button   = $UI/DiscardDrawButton
@onready var confirm_discard_button = $UI/ConfirmDiscardButton
@onready var cancel_discard_button  = $UI/CancelDiscardButton
@onready var card_info_title       = $UI/CardInfoPanel/CardInfoTitle
@onready var card_info_desc        = $UI/CardInfoPanel/CardInfoDesc
@onready var white_graveyard_flow  = $UI/GraveyardPanel/WhiteGraveyardFlow
@onready var black_graveyard_flow  = $UI/GraveyardPanel/BlackGraveyardFlow

const ACCENT_WIN  = Color(1.0, 0.710, 0.439, 1.0)
const ACCENT_LOSE = Color(0.886, 0.345, 0.412, 1.0)
const ORTHOGONAL_DIRS = [Vector2(1,0), Vector2(-1,0), Vector2(0,1), Vector2(0,-1)]

# ── Piece Value System ───────────────────────────────────────────────────────
# Base Value = permanent balance rating (standard chess values).
# Effective Value = Base Value adjusted for current board state
# (mobility, threat potential, board control, position).
const BASE_VALUE = {
	Globals.PIECE_TYPES.PAWN:   1.0,
	Globals.PIECE_TYPES.KNIGHT: 3.0,
	Globals.PIECE_TYPES.BISHOP: 3.0,
	Globals.PIECE_TYPES.ROOK:   5.0,
	Globals.PIECE_TYPES.QUEEN:  9.0,
	Globals.PIECE_TYPES.KING:   1000.0,  # effectively infinite / not tradable
}

func get_base_value(piece_type) -> float:
	return BASE_VALUE.get(piece_type, 1.0)

# Effective Value = Base Value scaled by mobility, threat potential and
# board control in the *current* position. This lets the same piece type
# carry a different practical worth depending on where/how it stands —
# e.g. a cornered Knight is worth less than a centralized one; a Pawn one
# step from promotion is worth dramatically more than a base Pawn.
func get_effective_value(piece) -> float:
	if piece == null:
		return 0.0
	var base = get_base_value(piece.piece_type)
	if piece.piece_type == Globals.PIECE_TYPES.KING:
		return base  # King value is never adjusted

	var mobility_moves = piece.get_moveable_positions() + piece.get_threatened_positions()
	var mobility_count  = mobility_moves.size()

	# Mobility factor: more reachable squares = more influence.
	# Normalize against a rough "typical" mobility per piece type so the
	# multiplier stays in a sane ±40% band instead of exploding for rooks/queens.
	var typical_mobility = {
		Globals.PIECE_TYPES.PAWN: 2.0, Globals.PIECE_TYPES.KNIGHT: 6.0,
		Globals.PIECE_TYPES.BISHOP: 8.0, Globals.PIECE_TYPES.ROOK: 10.0,
		Globals.PIECE_TYPES.QUEEN: 16.0,
	}.get(piece.piece_type, 4.0)
	var mobility_factor = clamp(mobility_count / max(typical_mobility, 1.0), 0.5, 1.4)

	# Threat potential: pieces it can actually capture right now are worth more.
	var threat_count = 0
	for pos in piece.get_threatened_positions():
		var occ = board.get_piece(pos)
		if occ != null and occ.color != piece.color:
			threat_count += 1
	var threat_bonus = 1.0 + (0.15 * threat_count)

	# Board control: central squares influence more of the board.
	var dx = abs(piece.board_position.x - 3.5)
	var dy = abs(piece.board_position.y - 3.5)
	var centrality = 1.0 - (clamp((dx + dy) / 7.0, 0.0, 1.0) * 0.25)

	# Special-case: a Pawn near promotion becomes far more valuable.
	var promotion_bonus = 1.0
	if piece.piece_type == Globals.PIECE_TYPES.PAWN:
		var home_row = 0.0 if piece.color == Globals.COLORS.BLACK else 7.0
		var promo_row = 7.0 if piece.color == Globals.COLORS.BLACK else 0.0
		var dist_to_promo = abs(piece.board_position.y - promo_row)
		if dist_to_promo <= 2:
			promotion_bonus = 1.0 + (0.5 * (3 - dist_to_promo))

	# Card-status synergy: pieces carrying an active skill effect punch
	# above their base weight (they can convert/retreat/duel-lock for free).
	var synergy_bonus = 1.0
	if piece.status_bounce or piece.status_devour or piece.status_spring_horse:
		synergy_bonus = 1.2
	if piece.duel_partner != null and _is_duel_active(piece):
		synergy_bonus *= 0.85  # locked into one target — less flexible right now

	return base * mobility_factor * threat_bonus * centrality * promotion_bonus * synergy_bonus

# Convenience: rank a list of pieces by effective value, highest first.
func _rank_by_effective_value(pieces: Array) -> Array:
	var copy = pieces.duplicate()
	copy.sort_custom(func(a, b): return get_effective_value(a) > get_effective_value(b))
	return copy

# ── Skill Card state ──────────────────────────────────────────────────────────
var player_sp: int = 0
var player_hand: Array = []
var player_deck: Array = []
var player_discard_pile: Array = []
var discard_mode: bool = false
var discard_selected: Array = []

var player_turn_number: int = 0
var pending_draws: int = 0
var pop_next_new_card: bool = false

# Bot card state
var bot_sp: int = 0
var bot_hand: Array = []
var bot_deck: Array = []
var bot_discard_pile: Array = []
var bot_turn_number: int = 0

# Card target-picking
var pending_card_index: int = -1
var pending_card_id = null
var pending_stage: int = 1
var pending_target_kind: String = "piece"
var pending_targets_needed: int = 0
var pending_selected_targets: Array = []
var pending_valid_targets: Array = []
var pending_extra: Dictionary = {}
var pending_acting_color = null  # PVP: which side (WHITE/BLACK) is playing this card

# ── Turn Log / Battle Log ───────────────────────────────────────────────────
var turn_log: Array = []          # committed entries, oldest first
var _log_move_piece_type = null
var _log_move_from: Vector2 = Vector2.ZERO
var _log_move_to: Vector2 = Vector2.ZERO
var _log_move_color = null
var _log_has_move: bool = false
var _log_captures: Array = []     # [{"piece": String, "cause": String}]
var _log_cards: Array = []        # [String]
var _log_events: Array = []       # [String]

# Turn Log UI — persistent panel (see UI/LogPanel in the scene), entries
# populated dynamically as one "card" Control per turn log entry.
var log_entries_box: VBoxContainer  = null
var log_scroll: ScrollContainer     = null

func _log_reset_move() -> void:
	_log_move_piece_type = null
	_log_move_from        = Vector2.ZERO
	_log_move_to          = Vector2.ZERO
	_log_move_color       = null
	_log_has_move         = false
	_log_captures         = []
	_log_cards            = []
	_log_events           = []

func _log_set_move(piece_type, from_pos: Vector2, to_pos: Vector2, color) -> void:
	_log_move_piece_type = piece_type
	_log_move_from        = from_pos
	_log_move_to          = to_pos
	_log_move_color       = color
	_log_has_move         = true

func _log_record_capture(piece_type, cause: String, captured_color = null) -> void:
	_log_captures.append({"piece": _piece_type_name(piece_type), "cause": cause})
	if captured_color != null:
		_graveyard_add(piece_type, captured_color)

# ── Graveyard panel ───────────────────────────────────────────────────────────
# Display: a fixed legend of 6 slots per color (Pawn/Knight/Bishop/Rook/Queen/
# King), each showing that type's captured icon with a live count underneath —
# not a growing row of one-icon-per-capture. The underlying data list per
# color is still kept in full (one entry per captured piece) so the Revive
# card can continue to pick and remove one *specific* captured piece; only
# the visual presentation is aggregated into per-type counts.
# Entry shape: {"id": int, "piece_type": ..., "color": ...}
const GRAVEYARD_ICON_SIZE := Vector2(16, 16)
const GRAVEYARD_SLOT_ORDER := [
	Globals.PIECE_TYPES.PAWN,
	Globals.PIECE_TYPES.KNIGHT,
	Globals.PIECE_TYPES.BISHOP,
	Globals.PIECE_TYPES.ROOK,
	Globals.PIECE_TYPES.QUEEN,
	Globals.PIECE_TYPES.KING,
]
var white_graveyard: Array = []
var black_graveyard: Array = []
var _graveyard_next_id: int = 0

# piece_type -> {"icon": TextureButton, "label": Label}
var _graveyard_slots_white: Dictionary = {}
var _graveyard_slots_black: Dictionary = {}

func _graveyard_list_for(color) -> Array:
	return white_graveyard if color == Globals.COLORS.WHITE else black_graveyard

func _graveyard_slots_for(color) -> Dictionary:
	return _graveyard_slots_white if color == Globals.COLORS.WHITE else _graveyard_slots_black

# Builds the fixed 6-slot legend row for one color (icon + count label per
# piece type). Called once per match start; safe to call again on restart
# since it clears any previously-built children first.
func _build_graveyard_slot_row(row: HBoxContainer, color) -> Dictionary:
	var slots: Dictionary = {}
	if row == null:
		return slots
	for child in row.get_children():
		child.queue_free()

	for piece_type in GRAVEYARD_SLOT_ORDER:
		var slot := VBoxContainer.new()
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.alignment             = BoxContainer.ALIGNMENT_CENTER
		slot.add_theme_constant_override("separation", 2)

		var icon := TextureButton.new()
		icon.texture_normal      = load(Globals.SPRITE_MAPPING[color][piece_type])
		icon.ignore_texture_size = true
		icon.stretch_mode        = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = GRAVEYARD_ICON_SIZE
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.focus_mode          = Control.FOCUS_NONE
		icon.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		icon.pressed.connect(_on_graveyard_icon_pressed.bind(piece_type, color))
		slot.add_child(icon)

		var label := Label.new()
		label.text = "0"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_override("font", preload("res://fonts/PressStart2P-Regular.ttf"))
		label.add_theme_font_size_override("font_size", 7)
		label.add_theme_color_override("font_color", Color(0.863, 0.796, 0.925, 0.85))
		slot.add_child(label)

		row.add_child(slot)
		slots[piece_type] = {"icon": icon, "label": label}
	return slots

# Refreshes the count label for one (color, piece_type) slot from the live
# data list — called after any add/remove so the number on screen always
# matches the actual graveyard contents.
func _graveyard_refresh_count(color, piece_type) -> void:
	var slots = _graveyard_slots_for(color)
	if not slots.has(piece_type):
		return
	var count = _graveyard_list_for(color).filter(func(e): return e["piece_type"] == piece_type).size()
	var label = slots[piece_type]["label"]
	if is_instance_valid(label):
		label.text = str(count)

# Adds one captured piece to its color's data list (order preserved for
# Revive) and refreshes that type's on-screen count. Called from the single
# _log_record_capture choke point, so every capture source (normal moves,
# en passant, Land Mine, Sacrifice) updates the panel immediately and
# consistently.
func _graveyard_add(piece_type, captured_color) -> void:
	var entry = {"id": _graveyard_next_id, "piece_type": piece_type, "color": captured_color}
	_graveyard_next_id += 1
	_graveyard_list_for(captured_color).append(entry)
	_graveyard_refresh_count(captured_color, piece_type)

# Removes one specific entry from the Graveyard data list (used when it's
# revived) and refreshes that type's on-screen count.
func _graveyard_remove(entry) -> void:
	_graveyard_list_for(entry["color"]).erase(entry)
	_graveyard_refresh_count(entry["color"], entry["piece_type"])

# Handles clicking a Graveyard type slot — only does anything while Revive is
# waiting for its Graveyard-piece selection (stage 1) and at least one
# captured piece of this exact type/color is currently a valid choice. Since
# all captured pieces of the same type/color are functionally interchangeable
# for Revive's purposes, this simply picks the first matching valid entry.
func _on_graveyard_icon_pressed(piece_type, color) -> void:
	if pending_card_id != Globals.CARD_ID.REVIVE or pending_target_kind != "graveyard":
		return
	var picked = null
	for entry in pending_valid_targets:
		if entry["piece_type"] == piece_type and entry["color"] == color:
			picked = entry
			break
	if picked == null:
		return
	pending_selected_targets.append(picked)
	pending_valid_targets.erase(picked)
	_advance_card_stage()

# Dims out every Graveyard type slot that has no valid Revive target of that
# type, and restores full opacity to everything once selection ends.
func _refresh_graveyard_highlight() -> void:
	var active = (pending_card_id == Globals.CARD_ID.REVIVE and pending_target_kind == "graveyard")
	for color in [Globals.COLORS.WHITE, Globals.COLORS.BLACK]:
		var slots = _graveyard_slots_for(color)
		for piece_type in slots:
			var icon = slots[piece_type]["icon"]
			if icon == null or not is_instance_valid(icon):
				continue
			if not active:
				icon.modulate.a = 1.0
				continue
			var has_valid = false
			for entry in pending_valid_targets:
				if entry["piece_type"] == piece_type and entry["color"] == color:
					has_valid = true
					break
			icon.modulate.a = 1.0 if has_valid else 0.28

# Clears both graveyard data lists and rebuilds the fixed slot rows —
# called at the start of a new match.
func _graveyard_reset() -> void:
	if white_graveyard_flow == null or black_graveyard_flow == null:
		return
	white_graveyard = []
	black_graveyard = []
	_graveyard_slots_white = _build_graveyard_slot_row(white_graveyard_flow, Globals.COLORS.WHITE)
	_graveyard_slots_black = _build_graveyard_slot_row(black_graveyard_flow, Globals.COLORS.BLACK)

func _log_record_card(card_name: String, target_desc: String = "", effect_desc: String = "") -> void:
	var s = card_name
	if target_desc != "":
		s += " → " + target_desc
	if effect_desc != "":
		s += " (" + effect_desc + ")"
	_log_cards.append(s)

func _piece_log_desc(p) -> String:
	return _color_name(p.color) + " " + _piece_type_name(p.piece_type) + " at " + _square_name(p.board_position)

# Target/effect description for the single-target "simple" cards
# (Bounce, Devour, Spring Horse, Land Mine) — used by both the human and
# bot card-play paths so the Turn Log records what actually happened.
func _simple_card_log_desc(card_id, targets: Array) -> Dictionary:
	if targets.is_empty():
		return {"target": "", "effect": ""}
	match card_id:
		Globals.CARD_ID.BOUNCE:
			return {"target": _piece_log_desc(targets[0]), "effect": "retreats after next capture"}
		Globals.CARD_ID.DEVOUR:
			return {"target": _piece_log_desc(targets[0]), "effect": "transforms after next capture"}
		Globals.CARD_ID.SPRING_HORSE:
			return {"target": _piece_log_desc(targets[0]), "effect": "can hop adjacent pieces"}
		Globals.CARD_ID.LAND_MINE:
			return {"target": "square " + _square_name(targets[0]), "effect": "mine armed"}
		_:
			return {"target": "", "effect": ""}

func _log_record_event(text: String) -> void:
	_log_events.append(text)

func _square_name(pos: Vector2) -> String:
	if board == null:
		return "?"
	return board.cell_name(int(pos.x), int(pos.y))

func _color_name(color) -> String:
	return "White" if color == Globals.COLORS.WHITE else "Black"

# Commit whatever has accumulated (move + cards + captures + events) as one
# Turn Log entry for the side identified by `mover_color`. Called right
# before the turn actually flips to the other side.
func _log_commit_turn(mover_color) -> void:
	if mover_color == null:
		return
	if not _log_has_move and _log_cards.is_empty() and _log_captures.is_empty() and _log_events.is_empty():
		return
	var entry = {
		"round":    round_count,
		"turn":     turn_count + 1,
		"player":   _color_name(mover_color),
		"piece":    _piece_type_name(_log_move_piece_type) if _log_has_move else "",
		"from":     _square_name(_log_move_from) if _log_has_move else "",
		"to":       _square_name(_log_move_to) if _log_has_move else "",
		"cards":    _log_cards.duplicate(),
		"captures": _log_captures.duplicate(),
		"events":   _log_events.duplicate(),
	}
	turn_log.append(entry)
	_log_reset_move()
	_refresh_log_ui()

func _build_log_ui() -> void:
	log_scroll      = get_node_or_null("UI/LogPanel/LogScroll")
	log_entries_box = get_node_or_null("UI/LogPanel/LogScroll/LogEntries")
	if log_scroll == null or log_entries_box == null:
		push_warning("Turn Log UI: LogPanel/LogScroll/LogEntries not found in scene — log will not display.")
		return
	_refresh_log_ui()

func _log_detail_label(text: String) -> Label:
	var l = Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.863, 0.796, 0.925, 0.68))
	return l

# Builds one visually self-contained "card" for a single Turn Log entry:
# a colored left-border accent (by player) + header row + detail lines.
func _build_log_entry_node(entry: Dictionary) -> Control:
	var is_white = (entry.player == "White")
	var accent   = Color(1.0, 0.710, 0.439, 0.95) if is_white else Color(0.702, 0.616, 0.949, 0.95)

	var panel = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color                  = Color(1, 1, 1, 0.04)
	sb.border_width_left         = 3
	sb.border_color              = accent
	sb.corner_radius_top_left    = 5
	sb.corner_radius_top_right   = 5
	sb.corner_radius_bottom_left = 5
	sb.corner_radius_bottom_right = 5
	sb.content_margin_left       = 10
	sb.content_margin_top        = 7
	sb.content_margin_right      = 10
	sb.content_margin_bottom     = 7
	panel.add_theme_stylebox_override("panel", sb)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	panel.add_child(vbox)

	var header = Label.new()
	header.text = entry.player.to_upper() + "   ·   ROUND " + str(entry.round) + " · TURN " + str(entry.turn)
	header.add_theme_font_size_override("font_size", 13)
	header.add_theme_color_override("font_color", accent)
	vbox.add_child(header)

	if entry.piece != "":
		vbox.add_child(_log_detail_label("Move: " + entry.piece + "   " + entry.from + " → " + entry.to))
	if not entry.cards.is_empty():
		vbox.add_child(_log_detail_label("Cards: " + ", ".join(entry.cards)))
	if not entry.captures.is_empty():
		var caps = []
		for c in entry.captures:
			caps.append(String(c.piece) + " (" + String(c.cause) + ")")
		vbox.add_child(_log_detail_label("Captured: " + ", ".join(caps)))
	if not entry.events.is_empty():
		var ev_label = _log_detail_label("Event: " + ", ".join(entry.events))
		ev_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55, 0.95))
		vbox.add_child(ev_label)

	return panel

func _refresh_log_ui() -> void:
	if log_entries_box == null:
		return
	for child in log_entries_box.get_children():
		child.queue_free()

	if turn_log.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No turns played yet."
		empty_label.add_theme_font_size_override("font_size", 13)
		empty_label.add_theme_color_override("font_color", Color(0.863, 0.796, 0.925, 0.45))
		log_entries_box.add_child(empty_label)
		return

	# Chronological order — oldest first, newest last.
	for entry in turn_log:
		log_entries_box.add_child(_build_log_entry_node(entry))

	# Keep the newest entry visible by auto-scrolling to the bottom once the
	# newly added nodes have been laid out.
	await get_tree().process_frame
	if log_scroll:
		log_scroll.scroll_vertical = int(log_scroll.get_v_scroll_bar().max_value)

func _active_hand_array() -> Array:
	# Returns reference array for the side currently playing a card
	if player2_type == Globals.PLAYER_2_TYPE.HUMAN:
		return white_hand if pending_acting_color == Globals.COLORS.WHITE else black_hand
	return player_hand

func _active_discard_array() -> Array:
	if player2_type == Globals.PLAYER_2_TYPE.HUMAN:
		return white_discard_pile if pending_acting_color == Globals.COLORS.WHITE else black_discard_pile
	return player_discard_pile

func _active_sp() -> int:
	if player2_type == Globals.PLAYER_2_TYPE.HUMAN:
		return white_sp if pending_acting_color == Globals.COLORS.WHITE else black_sp
	return player_sp

func _set_active_sp(val: int) -> void:
	if player2_type == Globals.PLAYER_2_TYPE.HUMAN:
		if pending_acting_color == Globals.COLORS.WHITE: white_sp = val
		else: black_sp = val
	else:
		player_sp = val

# ── Helpers ───────────────────────────────────────────────────────────────────
func get_pos_under_mouse() -> Vector2:
	var local = board_container.to_local(get_global_mouse_position())
	var col = int(local.x / 66)
	var row = int(local.y / 66)
	# to_local() already accounts for the 180° rotation when board_flipped
	# (pieces are placed directly at board_position * CELL_SIZE in this same
	# local space, with no extra mirroring). So the (col,row) we just
	# computed already IS the correct board-space cell — clicking a black
	# piece shown at 7b should select board_position (1,6) ("7b") directly,
	# not its mirror. Do not re-flip here.
	return Vector2(col, row)

func opponent_color(c):
	return Globals.COLORS.BLACK if c == Globals.COLORS.WHITE else Globals.COLORS.WHITE

func _on_board(pos: Vector2) -> bool:
	return pos.x >= 0 and pos.x <= 7 and pos.y >= 0 and pos.y <= 7

func unique(arr: Array) -> Array:
	var d = {}
	for a in arr: d[a] = 1
	return d.keys()

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready():
	MusicManager.play_track(MusicManager.Track.GAMEPLAY)

	ui_control.hide()
	promotion_panel.hide()
	back_menu_btn.show()
	_build_log_ui()

	if Globals.game_mode == Globals.GAME_MODE.PVP:
		side_panel.hide()
		Globals.selected_color = Globals.COLORS.WHITE
		init_game()
	else:
		side_panel.show()
		hand_list.hide()
		white_hand_panel.hide()
		black_hand_panel.hide()
		white_hand_list.hide()
		black_hand_list.hide()
		player_sp_label.hide()
		player_sp_pips.hide()
		call_deferred("_setup_card_hover")

func _setup_card_hover():
	white_card.pivot_offset = white_card.size * 0.5
	black_card.pivot_offset = black_card.size * 0.5
	white_card.mouse_entered.connect(func(): _card_hover(white_card, true))
	white_card.mouse_exited.connect(func():  _card_hover(white_card, false))
	black_card.mouse_entered.connect(func(): _card_hover(black_card, true))
	black_card.mouse_exited.connect(func():  _card_hover(black_card, false))

func _card_hover(card: Button, entering: bool):
	var tw = create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(card, "scale", Vector2(1.05,1.05) if entering else Vector2.ONE, 0.14)

# ── Card Info: piece hover ──────────────────────────────────────────────────
# Polls the mouse every frame (rather than relying on per-piece signals, since
# pieces aren't Control/Area2D nodes with mouse_entered/exited of their own)
# and refreshes the Card Info panel whenever the hovered piece changes.
func _process(_delta) -> void:
	# Revive card hover feedback — runs independently of the Card Info panel
	# guards below, since it needs to work while side_panel/etc. state varies.
	if pending_card_id == Globals.CARD_ID.REVIVE and not game_over:
		if pending_target_kind == "piece":
			_update_revive_bishop_hover()
		elif pending_target_kind == "square":
			_update_revive_square_hover()

	if game_over or not ui_control.visible or side_panel.visible or _card_hover_active:
		return
	var pos   = get_pos_under_mouse()
	var piece = board.get_piece(pos) if _on_board(pos) else null
	if piece != _hovered_piece:
		_hovered_piece = piece
		_update_card_info_for_hovered_piece(piece)

# Phase 1 — intensifies the glow of whichever valid Bishop is under the
# mouse, restoring the previous one back to its plain "valid" glow.
func _update_revive_bishop_hover() -> void:
	var pos   = get_pos_under_mouse()
	var piece = board.get_piece(pos) if _on_board(pos) else null
	if piece == _revive_hovered_bishop:
		return
	if _revive_hovered_bishop != null and is_instance_valid(_revive_hovered_bishop) \
			and _revive_hovered_bishop in pending_valid_targets:
		_revive_hovered_bishop.set_revive_glow_state("valid")
	_revive_hovered_bishop = piece
	if piece != null and piece in pending_valid_targets:
		piece.set_revive_glow_state("hover")

# Phase 3 — golden pulse ring under the hovered valid destination square.
func _update_revive_square_hover() -> void:
	var pos = get_pos_under_mouse()
	if _on_board(pos) and pos in pending_valid_targets:
		board.set_revive_hover_square(pos)
	else:
		board.clear_revive_hover_square()

func _update_card_info_for_hovered_piece(piece) -> void:
	if piece == null:
		card_info_title.text = "—"
		card_info_desc.text  = "Hover a card, or a piece on the board, to see details."
		return

	card_info_title.text = "Piece: " + _color_name(piece.color) + " " + _piece_type_name(piece.piece_type)

	var lines: Array = []
	var move_desc = Globals.PIECE_MOVE_DESC.get(piece.piece_type, "")
	if move_desc != "":
		lines.append(move_desc)
		lines.append("")
	lines.append("Active Effects:")
	var effects: Array = piece.get_active_effects()
	if effects.is_empty():
		lines.append("- No Active Effects")
	else:
		for e in effects:
			lines.append("- " + e)
	var text := ""
	for i in range(lines.size()):
		text += lines[i]
		if i < lines.size() - 1:
			text += "\n"
	card_info_desc.text = text

# ── Input ─────────────────────────────────────────────────────────────────────
func _input(event):
	# Block all board input when: game over, promotion pending, side panel open
	if game_over or promotion_pending or side_panel.visible or sacrifice_resolving or revive_resolving:
		return
	# In PVB — block when it's bot's turn. In PVP — always allow (status controls which pieces are selectable)
	var is_pvp = (player2_type == Globals.PLAYER_2_TYPE.HUMAN)
	if not is_pvp and status != player_color:
		return

	# Block board input until the Draw Phase (and any forced Cleanup discard) is done.
	if turn_phase != TurnPhase.MOVE:
		if Input.is_action_just_pressed("left_click"):
			var mouse_pos = get_viewport().get_mouse_position()
			var board_rect = Rect2(376, 104, 528, 528)
			if board_rect.has_point(mouse_pos):
				if turn_phase == TurnPhase.DRAW:
					card_status_label.text = "Drawing..."
				else:
					card_status_label.text = "Discard down to " + str(Globals.MAX_HAND_SIZE) + " cards before moving."
				get_viewport().set_input_as_handled()
		return

	# Card targeting mode — board clicks select targets
	if pending_card_id != null:
		if Input.is_action_just_pressed("left_click"):
			_handle_card_target_click()
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_cancel_card_targeting()
		return

	# ── Click-to-move & Drag ──────────────────────────────────────────────────
	if Input.is_action_just_pressed("left_click"):
		var pos = get_pos_under_mouse()
		var clicked_piece = board.get_piece(pos)

		if clicked_piece != null and clicked_piece.color == status:
			# (re-)select a piece
			if click_selected_piece != null:
				click_selected_piece.z_index = 0
				click_selected_piece = null
			if is_dragging and selected_piece != null:
				selected_piece.position = previous_position
				selected_piece.z_index = 0
				selected_piece = null
				is_dragging = false

			selected_piece       = clicked_piece
			click_selected_piece = clicked_piece
			previous_position    = clicked_piece.position
			clicked_piece.z_index = 100
			_show_piece_highlights(clicked_piece)
			is_dragging = true

		elif click_selected_piece != null:
			# try to move the selected piece to the clicked square
			var moved = _execute_player_move(click_selected_piece, pos)
			click_selected_piece.z_index = 0
			click_selected_piece = null
			board.clear_highlights()
			if moved:
				selected_piece = null
				is_dragging    = false
		else:
			board.clear_highlights()

	elif event is InputEventMouseMotion and is_dragging and selected_piece != null:
		var mouse_in_board = board_container.to_local(get_global_mouse_position())
		selected_piece.position = mouse_in_board

	elif Input.is_action_just_released("left_click") and is_dragging:
		is_dragging = false
		if selected_piece == null:
			return
		var drop_pos = get_pos_under_mouse()
		var is_valid = _execute_player_move(selected_piece, drop_pos)
		if not is_valid:
			selected_piece.position = previous_position
			selected_piece.z_index  = 100
			_show_piece_highlights(selected_piece)
		else:
			selected_piece.z_index  = 0
			selected_piece          = null
			click_selected_piece    = null
			board.clear_highlights()

# ── Player move (human) ───────────────────────────────────────────────────────
# Returns true if the move was accepted; handles end-game + triggers bot turn.
func _execute_player_move(piece, to_pos: Vector2) -> bool:
	if not valid_move(piece.board_position, to_pos):
		return false

	_do_move(piece, to_pos)

	# Pawn promotion — hand off; promote_pawn() finishes the turn
	if promotion_pending:
		return true

	if _check_end_game_after_move():
		return true

	# PVP: start next player's turn directly; PVB: trigger bot
	var is_pvp = (player2_type == Globals.PLAYER_2_TYPE.HUMAN)
	if is_pvp:
		_start_pvp_turn()
	else:
		_bot_move()
	return true

# ── Core move logic (shared by human & bot) ───────────────────────────────────
func _do_move(piece, to_pos: Vector2) -> void:
	var from_pos = piece.board_position
	var did_capture = false
	var captured_type = null

	# En passant capture
	if piece.piece_type == Globals.PIECE_TYPES.PAWN and to_pos.x != from_pos.x:
		var dest = board.get_piece(to_pos)
		if dest == null:
			var cap = board.get_piece(Vector2(to_pos.x, from_pos.y))
			if cap != null:
				did_capture   = true
				captured_type = cap.piece_type
				board.delete_piece(cap)
				_log_record_capture(captured_type, "En Passant", cap.color)

	# Castling — move rook
	if piece.piece_type == Globals.PIECE_TYPES.KING and abs(to_pos.x - from_pos.x) == 2:
		var row = from_pos.y
		if to_pos.x == 6:
			var rk = board.get_piece(Vector2(7, row))
			if rk: rk.move_position(Vector2(5, row))
		elif to_pos.x == 2:
			var rk = board.get_piece(Vector2(0, row))
			if rk: rk.move_position(Vector2(3, row))

	# Normal capture
	var dest_piece = board.get_piece(to_pos)
	if dest_piece != null and dest_piece.color != piece.color:
		did_capture   = true
		captured_type = dest_piece.piece_type
		board.delete_piece(dest_piece)
		_log_record_capture(captured_type, "Normal Capture", dest_piece.color)

	var from_y = from_pos.y
	piece.move_position(to_pos)
	if not did_capture:
		# Captures keep using their existing capture-side audio; this is only
		# for plain moves onto an empty square.
		GameplaySfx.play_piece_move()
	board.current_turn += 1
	_log_set_move(piece.piece_type, from_pos, to_pos, piece.color)

	# En passant eligibility for next turn
	if piece.piece_type == Globals.PIECE_TYPES.PAWN and abs(to_pos.y - from_y) == 2:
		piece.en_passant_turn = board.current_turn

	# Skill card effects on capture (any side)
	if did_capture:
		if piece.status_devour and captured_type != Globals.PIECE_TYPES.KING:
			piece.promote_to(captured_type)
			_log_record_event("Devour triggered (transformed into " + _piece_type_name(captured_type) + ")")
			if piece.color == player_color:
				card_status_label.text = "Devour: transformed into the captured piece!"
			else:
				card_status_label.text = "Bot's Devour triggered — it transformed into your " + _piece_type_name(captured_type) + "!"
		if piece.status_bounce:
			_apply_bounce_retreat(piece, from_pos, to_pos)
			_log_record_event("Bounce triggered")
			if piece.color != player_color:
				card_status_label.text = "Bot's Bounce triggered — its piece retreated!"

	# Land Mine trigger
	for i in range(board.mines.size()):
		if board.mines[i].pos == to_pos:
			board.trigger_mine_explosion(to_pos)
			board.mines.remove_at(i)
			board.queue_redraw()
			if piece.piece_type != Globals.PIECE_TYPES.KING:
				var whose = "AI piece" if piece.color != player_color else "Your piece"
				card_status_label.text = whose + " was destroyed by a Land Mine!"
				_log_record_capture(piece.piece_type, "Land Mine", piece.color)
				board.delete_piece(piece)
			break

	_update_mine_visibility()

	# Pawn promotion (player only — bot auto-promotes)
	if piece.piece_type == Globals.PIECE_TYPES.PAWN:
		if (piece.color == Globals.COLORS.BLACK and to_pos.y == 7) or \
		   (piece.color == Globals.COLORS.WHITE and to_pos.y == 0):
			if piece.color == player_color:
				promotion_pending = true
				promotion_piece   = piece
				_show_promotion_panel(piece.color)
				# DON'T flip status yet — promote_pawn() does it
				return
			else:
				# Bot auto-promotes to Queen
				piece.promote_to(Globals.PIECE_TYPES.QUEEN)
				_log_record_event("Promoted to Queen")

	# Flip turn
	_flip_turn()

func _update_active_turn_label() -> void:
	if not active_turn_label:
		return
	var is_pvp = (player2_type == Globals.PLAYER_2_TYPE.HUMAN)
	if is_pvp:
		var side = "WHITE" if status == Globals.COLORS.WHITE else "BLACK"
		active_turn_label.text = side + "'S TURN"
		active_turn_label.add_theme_color_override("font_color", Color(1.0, 0.710, 0.439, 0.75))
	else:
		if status == player_color:
			active_turn_label.text = "YOUR TURN"
			active_turn_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6, 0.85))
		else:
			active_turn_label.text = "BOT THINKING..."
			active_turn_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4, 0.75))

func _flip_turn() -> void:
	var mover_color = status
	if _king_in_check_on(board, opponent_color(mover_color)):
		_log_record_event("Check")

	# Exhausted wears off by 1 turn for the mover's own pieces, now that
	# their turn has fully ended. Logged before the commit below so it lands
	# in this same turn's Turn Log entry.
	for p in board.pieces:
		if p.color != mover_color or not p.is_exhausted():
			continue
		p.exhausted_turns -= 1
		if p.exhausted_turns <= 0:
			p.exhausted_turns = 0
			_log_record_event(_color_name(p.color) + " " + _piece_type_name(p.piece_type) + "'s Exhausted status wore off")
	board.queue_redraw()

	_log_commit_turn(mover_color)

	# Skill Point gain — awarded here, once the mover's turn has completely
	# ended, and before the next player's turn begins. This is the single
	# shared End Turn choke point for PvP and PvB alike (see _do_move and
	# promote_pawn), so SP is never granted mid-turn (e.g. right after a
	# move or a card play).
	var is_pvp = (player2_type == Globals.PLAYER_2_TYPE.HUMAN)
	if is_pvp:
		if mover_color == Globals.COLORS.WHITE:
			white_sp = min(white_sp + 1, Globals.MAX_SKILL_POINTS)
		else:
			black_sp = min(black_sp + 1, Globals.MAX_SKILL_POINTS)
	else:
		if mover_color == player_color:
			player_sp = min(player_sp + 1, Globals.MAX_SKILL_POINTS)
		else:
			bot_sp = min(bot_sp + 1, Globals.MAX_SKILL_POINTS)

	status = opponent_color(status)
	turn_count += 1
	# A Round completes once both White and Black have moved (2 turns).
	round_count = int(turn_count / 2) + 1
	turn_label.text = "ROUND " + str(round_count) + "  ·  TURN " + str(turn_count)
	_update_active_turn_label()
	if discard_mode:
		discard_mode     = false
		discard_selected = []
	pvp_forced_discard_color = null
	cleanup_discard_active   = false
	cycling_active           = false
	must_draw_first = false
	turn_phase      = TurnPhase.DRAW

# ── End-game check ────────────────────────────────────────────────────────────
# Call AFTER _flip_turn(). Checks whether the side whose turn it now is
# has no legal moves (checkmate or stalemate).
# Returns true if the game ended.
func _check_end_game_after_move() -> bool:
	var moves = _get_all_valid_moves_for(status)
	if moves.is_empty():
		var in_check = _king_in_check_on(board, status)
		_log_append_to_last_entry(["Checkmate"] if in_check else ["Stalemate"])
		game_over = true
		# The side that just moved (opponent of current status) wins
		var winner_is_player = (opponent_color(status) == player_color)
		set_win(Globals.PLAYER.ONE if winner_is_player else Globals.PLAYER.TWO)
		return true
	return false

func _log_append_to_last_entry(events: Array) -> void:
	if turn_log.is_empty():
		return
	var last = turn_log[turn_log.size() - 1]
	for e in events:
		last.events.append(e)
	_refresh_log_ui()

# PVP card state (each side has their own)
var white_sp: int = 0
var white_hand: Array = []
var white_deck: Array = []
var white_discard_pile: Array = []
var black_sp: int = 0
var black_hand: Array = []
var black_deck: Array = []
var black_discard_pile: Array = []
var pvp_turn_number: int = 0
var pvp_has_drawn_this_turn: bool = false
var pvp_forced_discard_color = null  # non-null while a PVP side must discard 1 card before drawing (hand was full)

func _start_pvp_turn() -> void:
	# status was already flipped by _flip_turn(); start the new side's turn
	pvp_turn_number += 1
	pvp_has_drawn_this_turn = false
	has_cycled_this_turn    = false
	_update_active_turn_label()

	# Auto-flip the board so the side about to move sees their pieces at the bottom.
	_apply_board_flip(status == Globals.COLORS.BLACK)

	# NOTE: SP is granted during the End Turn process (see _flip_turn), not here.

	# Draw Phase — automatic: draw 1 card immediately, no button press required.
	turn_phase       = TurnPhase.DRAW
	must_draw_first  = true
	discard_mode     = false
	discard_selected = []
	_pvp_draw_card(status)
	pvp_has_drawn_this_turn = true
	card_status_label.text = ("White" if status == Globals.COLORS.WHITE else "Black") + " drew a card."
	_enter_cleanup_phase()

func _pvp_current_hand() -> Array:
	return white_hand if status == Globals.COLORS.WHITE else black_hand

func _pvp_current_sp() -> int:
	return white_sp if status == Globals.COLORS.WHITE else black_sp

func _pvp_set_sp(val: int) -> void:
	if status == Globals.COLORS.WHITE: white_sp = val
	else: black_sp = val

func _pvp_current_deck() -> Array:
	return white_deck if status == Globals.COLORS.WHITE else black_deck

func _pvp_current_discard() -> Array:
	return white_discard_pile if status == Globals.COLORS.WHITE else black_discard_pile


func _bot_color():
	return opponent_color(player_color)

func _bot_take_card_turn() -> void:
	bot_turn_number += 1
	# NOTE: SP is granted during the End Turn process (see _flip_turn), not here.

	# Draw Phase — always draw 1 card.
	_bot_draw_card()

	# Cleanup Phase — discard down to MAX_HAND_SIZE if the draw pushed hand over the cap.
	while bot_hand.size() > Globals.MAX_HAND_SIZE:
		var worst = _bot_find_worst_card()
		if worst < 0:
			worst = 0
		bot_discard_pile.append(bot_hand[worst])
		bot_hand.remove_at(worst)

	# Try to play a card if affordable and useful
	var best = _bot_pick_best_card()
	if best >= 0:
		_bot_play_card(best)

func _bot_find_worst_card() -> int:
	# Discard the card with no valid target, or with the lowest value-adjusted score
	var worst_idx = -1
	var worst_score = INF
	for i in range(bot_hand.size()):
		var cid = bot_hand[i]
		var targets = _bot_get_targets(cid)
		var score: float
		if targets.is_empty():
			score = -1.0  # always worth discarding first
		else:
			score = _bot_card_score(cid, targets)
		if score < worst_score:
			worst_score = score
			worst_idx = i
	return worst_idx

func _bot_pick_best_card() -> int:
	var best_idx = -1
	var best_score = 0
	for i in range(bot_hand.size()):
		var cid = bot_hand[i]
		var cost = Globals.CARD_DATA[cid].cost
		if bot_sp < cost:
			continue
		var targets = _bot_get_targets(cid)
		if targets.is_empty():
			continue
		var score = _bot_card_score(cid, targets)
		if score > best_score:
			best_score = score
			best_idx = i
	return best_idx

func _bot_get_targets(cid) -> Array:
	var bc = _bot_color()
	var pc = player_color
	match cid:
		Globals.CARD_ID.BOUNCE:
			return board.pieces.filter(func(p): return p.color == bc)
		Globals.CARD_ID.DEVOUR:
			return board.pieces.filter(func(p): return p.color == bc and p.piece_type != Globals.PIECE_TYPES.KING)
		Globals.CARD_ID.SPRING_HORSE:
			return board.pieces.filter(func(p): return p.color == bc and p.piece_type == Globals.PIECE_TYPES.KNIGHT)
		Globals.CARD_ID.LAND_MINE:
			return _bot_land_mine_squares()
		Globals.CARD_ID.SACRIFICE:
			return _bot_sacrifice_targets()
		Globals.CARD_ID.YOU_AND_ME:
			return board.pieces.filter(func(p): return p.color == pc and p.piece_type != Globals.PIECE_TYPES.KING)
		_: return []

func _bot_land_mine_squares() -> Array:
	var bc = _bot_color()
	if _active_mine_count(bc) >= MAX_ACTIVE_MINES:
		return []
	var seen = {}
	for pawn in board.pieces.filter(func(p): return p.color == bc and p.piece_type == Globals.PIECE_TYPES.PAWN):
		for pos in _get_land_mine_forward_squares(pawn):
			seen[pos] = true
	return seen.keys()

func _bot_sacrifice_targets() -> Array:
	var bc = _bot_color()
	var pc = player_color
	var result = []
	for p in board.pieces:
		if p.color != pc: continue
		if p.piece_type == Globals.PIECE_TYPES.KING: continue  # King can never be targeted
		if _is_duel_active(p): continue
		if _sacrifice_requirements_met(p, bc):
			result.append(p)
	return result

func _bot_card_score(cid, targets: Array) -> float:
	var bc = _bot_color()
	var pc = player_color
	match cid:
		Globals.CARD_ID.BOUNCE:
			# Bounce protects a piece that's about to make a valuable capture —
			# score scales with the value of what it could capture this turn.
			var best = 0.0
			var moves = _get_all_valid_moves_for(bc)
			for m in moves:
				if m[0] in targets:
					var occ = board.get_piece(m[1])
					if occ != null:
						best = max(best, get_effective_value(occ) * 0.3)
			return max(best, 0.3)
		Globals.CARD_ID.DEVOUR:
			# Score by how much upside the bot gets: a low-value attacker
			# threatening a high-value enemy piece is the ideal Devour setup.
			var best = 0.0
			for p in targets:
				var own_val = get_effective_value(p)
				var moves = _get_all_valid_moves_for(bc)
				for m in moves:
					if m[0] == p:
						var occ = board.get_piece(m[1])
						if occ != null and occ.color == pc:
							var upside = get_effective_value(occ) - own_val
							best = max(best, 2.0 + upside)
			return max(best, 1.2)
		Globals.CARD_ID.SPRING_HORSE:
			# More valuable when the knight has good mobility to exploit.
			if targets.is_empty(): return 0.0
			var best = 0.0
			for p in targets:
				best = max(best, get_effective_value(p) * 0.6)
			return best
		Globals.CARD_ID.LAND_MINE:
			return 1.5 if not targets.is_empty() else 0.0
		Globals.CARD_ID.SACRIFICE:
			# Score by the effective value of the best enemy piece it can remove.
			if targets.is_empty(): return 0.0
			var best_val = 0.0
			for p in targets:
				best_val = max(best_val, get_effective_value(p))
			return best_val * 0.5
		Globals.CARD_ID.YOU_AND_ME:
			# Locking the enemy's most valuable piece in a duel is the goal.
			var best = 0.0
			for p in targets:
				best = max(best, get_effective_value(p) * 0.35)
			return max(best, 1.0)
		_: return 0.0

func _bot_pick_best_mine_square(squares: Array) -> Vector2:
	# Prefer squares that sit on a path toward the bot's pieces from the
	# player's most valuable mobile pieces — i.e. squares more likely to be
	# stepped on by something worth a lot.
	var pc = player_color
	var enemy_pieces = _rank_by_effective_value(board.pieces.filter(func(p): return p.color == pc))
	var best = squares[0]
	var best_score = -1.0
	for sq in squares:
		var score = 0.0
		for p in enemy_pieces:
			var reachable = p.get_moveable_positions() + p.get_threatened_positions()
			if sq in reachable:
				score += get_effective_value(p)
		if score > best_score:
			best_score = score
			best = sq
	return best

func _bot_play_card(index: int) -> void:
	var cid = bot_hand[index]
	var data = Globals.CARD_DATA[cid]
	var targets = _bot_get_targets(cid)
	if targets.is_empty():
		return
	bot_sp -= data.cost
	bot_discard_pile.append(bot_hand[index])
	bot_hand.remove_at(index)

	var log_target = ""
	var log_effect = ""

	match cid:
		Globals.CARD_ID.BOUNCE:
			var t = _bot_pick_best_piece_for_bounce(targets)
			t.status_bounce = true
			card_status_label.text = "Bot used Bounce on its " + _piece_type_name(t.piece_type) + "."
			log_target = _piece_log_desc(t)
			log_effect = "retreats after next capture"
		Globals.CARD_ID.DEVOUR:
			var t = _bot_pick_best_attacker(targets)
			t.status_devour = true
			card_status_label.text = "Bot used Devour on its " + _piece_type_name(t.piece_type) + "."
			log_target = _piece_log_desc(t)
			log_effect = "transforms after next capture"
		Globals.CARD_ID.SPRING_HORSE:
			targets[0].status_spring_horse = true
			card_status_label.text = "Bot used Spring Horse on its Knight."
			log_target = _piece_log_desc(targets[0])
			log_effect = "can hop adjacent pieces"
		Globals.CARD_ID.LAND_MINE:
			var sq = _bot_pick_best_mine_square(targets)
			var bc = _bot_color()
			board.mines.append({"pos": sq, "placed_turn": bot_turn_number, "owner": bc})
			board.register_mine_placed(sq)
			_update_mine_visibility()
			card_status_label.text = "Bot planted a Land Mine."
			log_target = "square " + _square_name(sq)
			log_effect = "mine armed"
		Globals.CARD_ID.SACRIFICE:
			var target = _rank_by_effective_value(targets)[0]  # remove the most valuable option
			var bc = _bot_color()
			log_target = _piece_log_desc(target)
			var value = get_base_value(target.piece_type)
			var paid_pieces = []
			if value <= 1.0:
				# Pay with the bot's own lowest-value piece that is either the
				# same type as the target or itself Value 1.
				var pool = _sacrifice_value1_pool(bc, target.piece_type)
				paid_pieces.append(_rank_by_effective_value(pool)[pool.size() - 1])
			else:
				# Must pay with exactly 1 piece of the same type + 1 Pawn.
				var same  = board.pieces.filter(func(p): return p.color == bc and p.piece_type == target.piece_type)
				var pawns = board.pieces.filter(func(p): return p.color == bc and p.piece_type == Globals.PIECE_TYPES.PAWN)
				paid_pieces.append(_rank_by_effective_value(same)[same.size() - 1])
				paid_pieces.append(_rank_by_effective_value(pawns)[pawns.size() - 1])
			GameplaySfx.play_sacrifice_resolve()
			for pay_piece in paid_pieces:
				_log_record_capture(pay_piece.piece_type, "Sacrifice card (paid)", pay_piece.color)
				board.delete_piece(pay_piece)
			_log_record_capture(target.piece_type, "Sacrifice card", target.color)
			board.delete_piece(target)
			card_status_label.text = "Bot used Sacrifice to remove your " + _piece_type_name(target.piece_type) + "!"
			log_effect = "removed target; paid " + str(paid_pieces.size()) + " piece(s)"
		Globals.CARD_ID.YOU_AND_ME:
			var enemy = _rank_by_effective_value(targets)[0]  # lock down the most valuable enemy piece
			var bc = _bot_color()
			var own_pieces = board.pieces.filter(func(p): return p.color == bc and p.piece_type != Globals.PIECE_TYPES.KING)
			if own_pieces.is_empty():
				return
			var own = _bot_pick_best_duel_partner(own_pieces, enemy)
			own.duel_partner               = enemy
			enemy.duel_partner             = own
			own.duel_expires_after_turn    = player_turn_number + 2
			enemy.duel_expires_after_turn  = player_turn_number + 2
			board.queue_redraw()
			card_status_label.text = "Bot used You and Me — your " + _piece_type_name(enemy.piece_type) + " is locked in a duel!"
			log_target = _piece_log_desc(enemy)
			log_effect = "paired with bot's " + _piece_type_name(own.piece_type) + " for 3 turns"
	_log_record_card(data.name, log_target, log_effect)

func _bot_pick_best_piece_for_bounce(pieces: Array):
	# Prefer the piece set to capture the highest-value enemy piece this turn
	var bc = _bot_color()
	var moves = _get_all_valid_moves_for(bc)
	var best = null
	var best_val = -1.0
	for m in moves:
		if m[0] in pieces:
			var occ = board.get_piece(m[1])
			if occ != null:
				var v = get_effective_value(occ)
				if v > best_val:
					best_val = v
					best = m[0]
	return best if best != null else _rank_by_effective_value(pieces)[0]

func _bot_pick_best_attacker(pieces: Array):
	# Devour transforms the attacker into the captured piece, so the bot
	# should attack with its *lowest* effective-value piece — maximum upside.
	var ranked = _rank_by_effective_value(pieces)
	return ranked[ranked.size() - 1]

func _bot_pick_best_duel_partner(own_pieces: Array, enemy):
	# Pick own piece whose effective value is closest to the enemy's —
	# an even trade-off keeps the duel lock from being a net loss either way.
	var enemy_val = get_effective_value(enemy)
	var best = null
	var best_diff = INF
	for p in own_pieces:
		var diff = abs(get_effective_value(p) - enemy_val)
		if diff < best_diff:
			best_diff = diff
			best = p
	return best if best != null else own_pieces.pick_random()

# ── Bot move ──────────────────────────────────────────────────────────────────
func _bot_move() -> void:
	if player2_type != Globals.PLAYER_2_TYPE.AI:
		refresh_card_ui()
		return

	# Bot card turn — draw, maybe play a card
	_bot_take_card_turn()

	# A card effect (e.g. Sacrifice) could in principle have removed the last
	# of the bot's — or even the human's — legal responses on its own, before
	# any physical move happens. Use the exact same shared Check/Checkmate/
	# Stalemate engine as every other move in the game (never a bot-only copy).
	if _check_end_game_after_move():
		return

	# It's now the bot's turn (status == opponent's color); the shared check
	# above already guarantees at least one legal move exists here.
	var moves = _get_all_valid_moves_for(status)
	var pick  = moves.pick_random()
	var piece = pick[0]
	var pos   = pick[1]

	_do_move(piece, pos)

	if _check_end_game_after_move():
		return

	_start_player_turn()

# ── Promotion ─────────────────────────────────────────────────────────────────
func promote_pawn(new_type: Globals.PIECE_TYPES):
	if promotion_piece == null:
		return
	promotion_piece.promote_to(new_type)
	_log_record_event("Promoted to " + _piece_type_name(new_type))
	promotion_piece   = null
	promotion_pending = false
	promotion_panel.hide()

	# Now flip the turn (was held during promotion)
	_flip_turn()

	if _check_end_game_after_move():
		return
	var is_pvp = (player2_type == Globals.PLAYER_2_TYPE.HUMAN)
	if is_pvp:
		_start_pvp_turn()
	else:
		_bot_move()

# ── Highlight helpers ─────────────────────────────────────────────────────────
func _show_piece_highlights(piece) -> void:
	var move_pos    : Array = []
	var capture_pos : Array = []
	var special_pos : Array = []

	var candidates = _get_candidate_positions(piece)
	for pos in candidates:
		if valid_move(piece.board_position, pos):
			var target = board.get_piece(pos)
			if piece.piece_type == Globals.PIECE_TYPES.KING and abs(pos.x - piece.board_position.x) == 2:
				special_pos.append(pos)
			elif piece.piece_type == Globals.PIECE_TYPES.PAWN and target == null and pos.x != piece.board_position.x:
				special_pos.append(pos)  # en passant
			elif target != null and target.color != piece.color:
				capture_pos.append(pos)
			else:
				move_pos.append(pos)

	board.show_highlights(move_pos, capture_pos, special_pos)

func _get_candidate_positions(piece) -> Array:
	var candi = piece.get_moveable_positions()
	if piece.piece_type == Globals.PIECE_TYPES.PAWN:
		candi += piece.get_threatened_positions()
	if piece.piece_type == Globals.PIECE_TYPES.KNIGHT and piece.status_spring_horse:
		candi += _get_spring_horse_moves(piece)
	return unique(candi)

# ── Move validation ───────────────────────────────────────────────────────────
func valid_move(from_pos: Vector2, to_pos: Vector2) -> bool:
	var mover_color = status  # color of whoever is moving
	var live_src    = board.get_piece(from_pos)   # has status flags (spring_horse etc.)
	var board_copy  = board.clone()
	var src         = board_copy.get_piece(from_pos)
	if src == null or live_src == null:
		return false

	# The King can never be captured — checkmate, not capture, is how the game
	# ends. This is an explicit, unconditional rule (not just a side effect of
	# checkmate detection working correctly), so a move onto the enemy King's
	# square is never legal, no matter what.
	var dest_check = board.get_piece(to_pos)
	if dest_check != null and dest_check.piece_type == Globals.PIECE_TYPES.KING:
		return false

	if live_src.is_exhausted():
		card_status_label.text = "That piece is Exhausted and cannot move."
		return false

	# Spring Horse extra moves — must check live_src for status flag
	if live_src.piece_type == Globals.PIECE_TYPES.KNIGHT and live_src.status_spring_horse:
		var sh_moves = _get_spring_horse_moves(live_src)
		if to_pos in sh_moves:
			return _simulate_and_check(from_pos, to_pos, mover_color)

	# Normal move list check
	if to_pos not in live_src.get_moveable_positions() and to_pos not in live_src.get_threatened_positions():
		return false

	# Duel restriction — only applies when a human player is involved
	var live_dst = board.get_piece(to_pos)
	if live_src != null and live_dst != null and live_dst.color != live_src.color:
		var involves_player = (live_src.color == player_color or live_dst.color == player_color)
		if involves_player and not _capture_allowed_by_duel(live_src, live_dst):
			if live_src.color == player_color and _is_duel_active(live_src):
				card_status_label.text = "Duel active — this piece can only capture its bound target."
			elif live_dst.color == player_color and _is_duel_active(live_dst):
				card_status_label.text = "Duel active — that piece can only be captured by its bound attacker."
			return false

	return _simulate_and_check(from_pos, to_pos, mover_color)

func _simulate_and_check(from_pos: Vector2, to_pos: Vector2, mover_color) -> bool:
	var bc  = board.clone()
	var src = bc.get_piece(from_pos)

	# Castling — check the king doesn't pass through check
	if src.piece_type == Globals.PIECE_TYPES.KING and abs(to_pos.x - from_pos.x) == 2:
		var mid_x = int((from_pos.x + to_pos.x) / 2.0)
		var bm    = board.clone()
		var km    = bm.get_piece(from_pos)
		km.move_position(Vector2(mid_x, from_pos.y), false)
		if _king_in_check_on(bm, mover_color):
			return false

	# En passant simulation
	if src.piece_type == Globals.PIECE_TYPES.PAWN and to_pos.x != from_pos.x:
		var dst = bc.get_piece(to_pos)
		if dst == null:
			var cap = bc.get_piece(Vector2(to_pos.x, from_pos.y))
			if cap != null:
				bc.delete_piece(cap, false)

	var dst = bc.get_piece(to_pos)
	if dst != null and dst.color != src.color:
		bc.delete_piece(dst, false)

	# Castling — move rook in simulation
	if src.piece_type == Globals.PIECE_TYPES.KING and abs(to_pos.x - from_pos.x) == 2:
		var row = from_pos.y
		if to_pos.x == 6:
			var rk = bc.get_piece(Vector2(7, row)); if rk: rk.move_position(Vector2(5, row), false)
		elif to_pos.x == 2:
			var rk = bc.get_piece(Vector2(0, row)); if rk: rk.move_position(Vector2(3, row), false)

	src.move_position(to_pos, false)

	# Make sure own king is not left in check
	return not _king_in_check_on(bc, mover_color)

func _king_in_check_on(bc, color) -> bool:
	var king_pos = bc.white_king_pos if color == Globals.COLORS.WHITE else bc.black_king_pos
	for p in bc.pieces:
		if p.color == color:
			continue
		# You and Me: a piece under the duel effect cannot threaten the enemy
		# king — ignore it entirely during check/checkmate threat detection
		# until the effect expires.
		if _is_duel_active(p):
			continue
		if king_pos in p.get_threatened_positions():
			return true
		# Spring Horse: a Knight with the buff can also reach king via the hop
		if p.piece_type == Globals.PIECE_TYPES.KNIGHT and p.status_spring_horse:
			if king_pos in _get_spring_horse_moves(p):
				return true
	return false

# Get all legal moves for a given color
func _get_all_valid_moves_for(color) -> Array:
	var result = []
	var old_status = status
	status = color  # valid_move() uses status for check-detection
	for piece in board.pieces:
		if piece.color != color:
			continue
		var candi = _get_candidate_positions(piece)
		for pos in candi:
			if valid_move(piece.board_position, pos):
				result.append([piece, pos])
	status = old_status
	return result

# ── Spring Horse ──────────────────────────────────────────────────────────────
func _get_spring_horse_moves(piece) -> Array:
	# Use the piece's own board_handle so this works correctly on both the
	# live board and any cloned board used during check/checkmate simulation.
	var bh = piece.board_handle
	var result = []
	for dir in ORTHOGONAL_DIRS:
		var adj     = piece.board_position + dir
		var landing = piece.board_position + dir * 2
		if not _on_board(landing):
			continue
		if bh.get_piece(adj) == null:
			continue
		var lp = bh.get_piece(landing)
		if lp != null and lp.color == piece.color:
			continue
		result.append(landing)
	return result

# ── Bounce retreat ────────────────────────────────────────────────────────────
# Knocks the capturing piece back 1 square along the direction it just moved.
func _apply_bounce_retreat(piece, from_pos: Vector2, to_pos: Vector2) -> void:
	var dir = Vector2(sign(to_pos.x - from_pos.x), sign(to_pos.y - from_pos.y))
	if dir == Vector2.ZERO:
		return
	var retreat_pos = to_pos - dir
	if not _on_board(retreat_pos):
		return
	if board.get_piece(retreat_pos) != null:
		return  # retreat square occupied — nowhere to bounce back to
	piece.move_position(retreat_pos)

# ── Duel helpers ──────────────────────────────────────────────────────────────
func _is_duel_active(piece) -> bool:
	return piece != null and piece.duel_partner != null and player_turn_number <= piece.duel_expires_after_turn

func _capture_allowed_by_duel(attacker, defender) -> bool:
	# Use board_position for comparison since cloned boards have different object refs
	if _is_duel_active(attacker):
		if attacker.duel_partner == null or attacker.duel_partner.board_position != defender.board_position:
			return false
	if _is_duel_active(defender):
		if defender.duel_partner == null or defender.duel_partner.board_position != attacker.board_position:
			return false
	return true

# ── Promotion panel ───────────────────────────────────────────────────────────
func _show_promotion_panel(col: Globals.COLORS):
	var q_icon  = promotion_panel.get_node("PromoBox/QueenIcon")
	var r_icon  = promotion_panel.get_node("PromoBox/RookIcon")
	var kn_icon = promotion_panel.get_node("PromoBox/KnightIcon")
	var b_icon  = promotion_panel.get_node("PromoBox/BishopIcon")
	q_icon.texture  = load(Globals.SPRITE_MAPPING[col][Globals.PIECE_TYPES.QUEEN])
	r_icon.texture  = load(Globals.SPRITE_MAPPING[col][Globals.PIECE_TYPES.ROOK])
	kn_icon.texture = load(Globals.SPRITE_MAPPING[col][Globals.PIECE_TYPES.KNIGHT])
	b_icon.texture  = load(Globals.SPRITE_MAPPING[col][Globals.PIECE_TYPES.BISHOP])
	promotion_panel.show()

# Applies (or removes) the 180° board flip: rotates the BoardContainer and
# re-derotates each piece sprite so the given side's pieces render at the
# bottom of the screen. Reused by both the initial PvB flip and the
# automatic per-turn PvP flip below.
func _apply_board_flip(flip: bool) -> void:
	board_flipped = flip
	if board_flipped:
		# BoardContainer position is (376,104), board is 528x528 (8x66)
		# Rotate 180° around board center by shifting position
		board_container.rotation_degrees = 180.0
		board_container.position = Vector2(376 + 528, 104 + 528)
	else:
		board_container.rotation_degrees = 0.0
		board_container.position = Vector2(376, 104)
	board.flipped = board_flipped
	board.queue_redraw()
	board.apply_flip_to_pieces()

# ── Game init ─────────────────────────────────────────────────────────────────
func init_game():
	game_over         = false
	is_dragging       = false
	promotion_pending = false
	must_draw_first   = false
	click_selected_piece = null
	selected_piece    = null
	player_color      = Globals.selected_color
	status            = Globals.COLORS.WHITE   # White always moves first
	turn_count        = 0
	round_count       = 1
	board.current_turn = 0
	turn_label.text   = "ROUND 1  ·  TURN 0"
	player2_type = Globals.PLAYER_2_TYPE.HUMAN if Globals.game_mode == Globals.GAME_MODE.PVP else Globals.PLAYER_2_TYPE.AI

	var is_pvp = (player2_type == Globals.PLAYER_2_TYPE.HUMAN)
	if is_pvp:
		# PvP: board auto-flips every turn so whoever is about to move sees
		# their own pieces at the bottom. White moves first.
		_apply_board_flip(status == Globals.COLORS.BLACK)
	else:
		# PvB: flip once so the human player's chosen color is always at the bottom.
		_apply_board_flip(player_color == Globals.COLORS.BLACK)

	_setup_cards()
	_graveyard_reset()

	if is_pvp:
		_update_active_turn_label()
		pvp_turn_number         = 1
		pvp_has_drawn_this_turn = false
		has_cycled_this_turn    = false
		# NOTE: no starting SP grant here — under the new rule, SP is only
		# awarded once a turn completely ends (see _flip_turn), so the very
		# first mover of the game correctly begins turn 1 with 0 SP.
		# Draw Phase — automatic, no button press required.
		turn_phase       = TurnPhase.DRAW
		must_draw_first  = true
		discard_mode     = false
		discard_selected = []
		_pvp_draw_card(Globals.COLORS.WHITE)
		pvp_has_drawn_this_turn = true
		card_status_label.text = "White drew a card."
		_enter_cleanup_phase()
	elif player_color == Globals.COLORS.WHITE:
		_update_active_turn_label()
		_start_player_turn()
	else:
		_update_active_turn_label()
		_bot_move()

# ── Result screen ─────────────────────────────────────────────────────────────
func set_win(who: Globals.PLAYER):
	game_over = true
	refresh_card_ui()
	var is_pvp = (player2_type == Globals.PLAYER_2_TYPE.HUMAN)
	var is_win: bool
	var title: String
	if is_pvp:
		# who = PLAYER.ONE means White won (status flipped to Black = Black has no moves)
		var white_won = (who == Globals.PLAYER.ONE)
		is_win = true
		title  = "WHITE WINS" if white_won else "BLACK WINS"
	else:
		is_win = (who == Globals.PLAYER.ONE)
		title  = "VICTORY" if is_win else "DEFEAT"
	var accent = ACCENT_WIN if is_win else ACCENT_LOSE

	result_title.text = title
	result_title.add_theme_color_override("font_color", accent)
	result_subtitle.text = "FINISHED ON ROUND " + str(round_count) + " (TURN " + str(turn_count) + ")"
	result_icon.texture  = load("res://pieces_new/W-King64x64.png") if (is_pvp or is_win) else load("res://pieces_new/B-king64x64.png")
	result_icon.flip_v   = not is_win and not is_pvp
	result_icon.modulate = accent
	divider.color        = Color(accent.r, accent.g, accent.b, 0.4)

	var ps = overlay_panel.get_theme_stylebox("panel").duplicate()
	ps.border_color = accent
	overlay_panel.add_theme_stylebox_override("panel", ps)
	ui_control.modulate.a = 0.0
	overlay_panel.scale   = Vector2(0.85, 0.85)
	ui_control.show()

	var tw = create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(ui_control,    "modulate:a",   1.0,        0.22)
	tw.parallel().tween_property(overlay_panel, "scale", Vector2.ONE, 0.32)

# ── Skill Card system ─────────────────────────────────────────────────────────
func _setup_cards() -> void:
	player_sp           = 0
	player_hand         = []
	player_discard_pile = []
	player_deck         = _build_shuffled_deck()
	discard_mode        = false
	discard_selected    = []
	pending_draws       = 0
	turn_phase              = TurnPhase.DRAW
	must_draw_first          = false
	cleanup_discard_active   = false
	cycling_active           = false
	has_cycled_this_turn     = false
	player_turn_number  = 0
	board.mines         = []
	board.current_player_turn = 0
	# Bot card state
	bot_sp              = 0
	bot_hand            = []
	bot_discard_pile    = []
	bot_deck            = _build_shuffled_deck()
	bot_turn_number     = 0
	# PVP card state
	white_sp            = 0
	white_hand          = []
	white_deck          = _build_shuffled_deck()
	white_discard_pile  = []
	black_sp            = 0
	black_hand          = []
	black_deck          = _build_shuffled_deck()
	black_discard_pile  = []
	pvp_turn_number     = 0
	pvp_has_drawn_this_turn = false
	pvp_forced_discard_color = null
	card_status_label.text = ""
	refresh_card_ui()

func _build_shuffled_deck() -> Array:
	var deck = []
	for id in Globals.CARD_DATA.keys():
		for _i in range(Globals.DECK_COPIES_PER_CARD):
			deck.append(id)
	deck.shuffle()
	return deck

# Draw probability by SP cost category: 1 SP → 50%, 2 SP → 35%, 3 SP → 15%.
# Every card within the same cost category has an equal chance of being the
# one picked (weight ÷ card count in that category).
const SP_COST_DRAW_WEIGHTS = {1: 0.50, 2: 0.35, 3: 0.15}

# Picks one card out of `deck` using the weighted-by-SP-cost rule above:
# first roll which cost category the draw comes from, then pick uniformly
# among the remaining cards of that cost. Removes and returns that card id
# (mutates `deck` in place, same contract as the old deck.pop_back()).
# Returns null if the deck is empty.
func _weighted_draw_from_deck(deck: Array):
	if deck.is_empty():
		return null

	# Group the cards still left in this deck by their SP cost.
	var by_cost: Dictionary = {}
	for card_id in deck:
		var cost = Globals.CARD_DATA[card_id].cost
		if not by_cost.has(cost):
			by_cost[cost] = []
		by_cost[cost].append(card_id)

	# Only categories actually present get a slice of the probability; any
	# cost outside the 1/2/3 scheme (none currently exist) falls back to an
	# equal share so the system still degrades gracefully.
	var weights: Dictionary = {}
	var weight_total := 0.0
	for cost in by_cost.keys():
		var w = SP_COST_DRAW_WEIGHTS.get(cost, 1.0)
		weights[cost] = w
		weight_total += w

	# Roll for the cost category first...
	var roll     = randf() * weight_total
	var running  := 0.0
	var chosen_cost = by_cost.keys()[0]
	for cost in by_cost.keys():
		running += weights[cost]
		if roll <= running:
			chosen_cost = cost
			break

	# ...then pick uniformly among every remaining card of that cost.
	var pool: Array = by_cost[chosen_cost]
	var card_id = pool[randi() % pool.size()]

	deck.erase(card_id)  # removes exactly one matching instance
	return card_id

func _draw_card() -> void:
	if player_deck.is_empty():
		if player_discard_pile.is_empty():
			return
		player_deck         = player_discard_pile.duplicate()
		player_discard_pile = []
		player_deck.shuffle()
	player_hand.append(_weighted_draw_from_deck(player_deck))

func _bot_draw_card() -> void:
	if bot_deck.is_empty():
		if bot_discard_pile.is_empty():
			return
		bot_deck         = bot_discard_pile.duplicate()
		bot_discard_pile = []
		bot_deck.shuffle()
	bot_hand.append(_weighted_draw_from_deck(bot_deck))

func _start_player_turn() -> void:
	player_turn_number           += 1
	board.current_player_turn     = player_turn_number
	board.queue_redraw()
	# NOTE: SP is granted during the End Turn process (see _flip_turn), not here.
	has_cycled_this_turn = false

	# Draw Phase — automatic: draw 1 card immediately, no button press required.
	# (Cleanup Phase handles trimming the hand back down afterward if needed.)
	turn_phase       = TurnPhase.DRAW
	pending_draws    = 0
	must_draw_first  = true
	discard_mode     = false
	discard_selected = []
	_draw_card()
	pop_next_new_card = true
	card_status_label.text = "Drew a card."
	_enter_cleanup_phase()

func _pvp_draw_card(color) -> void:
	var hand    = white_hand    if color == Globals.COLORS.WHITE else black_hand
	var deck    = white_deck    if color == Globals.COLORS.WHITE else black_deck
	var discard = white_discard_pile if color == Globals.COLORS.WHITE else black_discard_pile
	if deck.is_empty():
		if discard.is_empty():
			return
		deck.append_array(discard)
		discard.clear()
		deck.shuffle()
	var card = _weighted_draw_from_deck(deck)
	hand.append(card)
	# Write back (arrays are passed by value from ternary so set explicitly)
	if color == Globals.COLORS.WHITE:
		white_hand = hand; white_deck = deck; white_discard_pile = discard
	else:
		black_hand = hand; black_deck = deck; black_discard_pile = discard

func _on_deck_pile_pressed() -> void:
	# Drawing is now automatic at the start of the Draw Phase — the deck pile
	# is a visual/informational element only and no longer clickable.
	pass

# ── Turn phase transitions ────────────────────────────────────────────────────
func _turn_hand_size() -> int:
	if player2_type == Globals.PLAYER_2_TYPE.HUMAN:
		return white_hand.size() if status == Globals.COLORS.WHITE else black_hand.size()
	return player_hand.size()

# Called immediately after the Draw Phase's draw completes.
# If the hand exceeds MAX_HAND_SIZE, forces a discard (looping until the hand
# is back within the limit); otherwise moves straight to the Move Phase.
func _enter_cleanup_phase() -> void:
	turn_phase      = TurnPhase.CLEANUP
	must_draw_first = false
	if _turn_hand_size() > Globals.MAX_HAND_SIZE:
		cleanup_discard_active = true
		discard_mode           = true
		discard_selected       = []
		var over = _turn_hand_size() - Globals.MAX_HAND_SIZE
		card_status_label.text = "Hand size exceeds " + str(Globals.MAX_HAND_SIZE) + " — discard " + str(over) + " card(s) to continue."
		refresh_card_ui()
	else:
		_enter_move_phase()

func _enter_move_phase() -> void:
	turn_phase              = TurnPhase.MOVE
	must_draw_first          = false
	cleanup_discard_active   = false
	discard_mode             = false
	discard_selected         = []
	pvp_forced_discard_color = null
	if player2_type == Globals.PLAYER_2_TYPE.HUMAN:
		card_status_label.text = ("White" if status == Globals.COLORS.WHITE else "Black") + ": your move."
	else:
		card_status_label.text = "Your move."
	refresh_card_ui()

func _pop_in(node: Control) -> void:
	node.modulate.a = 0.0
	node.scale      = Vector2(0.3, 0.3)
	await get_tree().process_frame
	node.pivot_offset = node.size * 0.5
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(node, "scale",      Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "modulate:a", 1.0,         0.18)

func refresh_card_ui() -> void:
	if white_sp_pips == null:
		return
	var is_pvp = (player2_type == Globals.PLAYER_2_TYPE.HUMAN)

	if is_pvp:
		hand_list.hide()
		white_hand_panel.show()
		black_hand_panel.show()
		white_hand_list.show()
		black_hand_list.show()
		white_sp_label.show()
		black_sp_label.show()
		white_sp_pips.show()
		black_sp_pips.show()
		player_sp_label.hide()
		player_sp_pips.hide()
		white_sp_pips.set_value(white_sp)
		black_sp_pips.set_value(black_sp)
		white_sp_label.text = "WHITE SP: " + str(white_sp) + " / " + str(Globals.MAX_SKILL_POINTS)
		black_sp_label.text = "BLACK SP: " + str(black_sp) + " / " + str(Globals.MAX_SKILL_POINTS)
		_refresh_pvp_hand(white_hand_list, white_hand, Globals.COLORS.WHITE)
		_refresh_pvp_hand(black_hand_list, black_hand, Globals.COLORS.BLACK)

		var cur_hand      = white_hand if status == Globals.COLORS.WHITE else black_hand
		var is_move_phase = turn_phase == TurnPhase.MOVE and not game_over and not promotion_pending

		if discard_mode:
			confirm_discard_button.visible  = true
			confirm_discard_button.text     = "DISCARD (" + str(discard_selected.size()) + ")"
			confirm_discard_button.disabled = discard_selected.size() == 0
			cancel_discard_button.visible   = cycling_active  # Cleanup Phase discard cannot be cancelled
			discard_draw_button.visible     = false
		else:
			confirm_discard_button.visible = false
			cancel_discard_button.visible  = false
			discard_draw_button.visible    = true
			discard_draw_button.disabled   = not is_move_phase or has_cycled_this_turn or cur_hand.is_empty()
			discard_draw_button.text       = "CYCLING (USED)" if has_cycled_this_turn else "CYCLE"

		# Drawing is automatic now — the deck pile is a visual/count display only.
		deck_pile.disabled = true
		deck_pile.dimmed   = true
		deck_pile.queue_redraw()
		return

	# PVB mode — the human player's hand reuses the exact White Hand Panel
	# widgets (position, size, spacing, styling, animations) from PVP mode.
	# The Black hand panel is fully hidden (background panel included, not
	# just its card list) so no empty box is left on the right side. The
	# bot continues to draw/hold/play cards internally via its own hand
	# data — only its UI panel is removed.
	hand_list.hide()
	black_hand_panel.hide()
	black_hand_list.hide()
	black_sp_label.hide()
	black_sp_pips.hide()
	player_sp_label.hide()
	player_sp_pips.hide()

	white_hand_panel.show()
	white_hand_list.show()
	white_sp_label.show()
	white_sp_pips.show()
	white_sp_pips.set_value(player_sp)
	white_sp_label.text = "SP: " + str(player_sp) + " / " + str(Globals.MAX_SKILL_POINTS)

	var is_player_turn   = (status == player_color) and not game_over and not promotion_pending
	var cards_interactive = is_player_turn and pending_card_id == null

	for child in white_hand_list.get_children():
		child.queue_free()

	var pvb_layout = _hand_card_layout(player_hand.size())
	white_hand_list.add_theme_constant_override("separation", int(pvb_layout.sep))

	for i in range(player_hand.size()):
		var card_id = player_hand[i]
		var data    = Globals.CARD_DATA[card_id]
		var affordable        = player_sp >= data.cost
		var mine_capped        = card_id == Globals.CARD_ID.LAND_MINE and _active_mine_count(player_color) >= MAX_ACTIVE_MINES
		var is_pending_this   = (pending_card_id != null and i == pending_card_index)
		var interactive_here  = is_pending_this or (pending_card_id == null and cards_interactive)

		var btn = load("res://scripts/card_visual.gd").new()
		btn.mode              = 1
		btn.custom_minimum_size = pvb_layout.size
		btn.card_title        = data.name
		btn.card_cost         = data.cost
		btn.art_path          = data.get("art_path", "")
		btn.marked            = discard_mode and (i in discard_selected)
		btn.armed             = is_pending_this
		btn.dimmed            = (not interactive_here) or mine_capped or \
								(pending_card_id == null and not discard_mode and not affordable)
		btn.disabled          = not interactive_here or mine_capped
		white_hand_list.add_child(btn)
		btn.pressed.connect(_on_hand_card_pressed.bind(i))
		btn.mouse_entered.connect(_on_card_hover.bind(card_id, player_color))
		btn.mouse_exited.connect(_on_card_hover_end)

		if i == player_hand.size() - 1 and pop_next_new_card:
			_pop_in(btn)

	pop_next_new_card = false

	discard_draw_button.visible      = not discard_mode
	discard_draw_button.disabled     = turn_phase != TurnPhase.MOVE or has_cycled_this_turn or player_hand.is_empty() or not cards_interactive
	discard_draw_button.text         = "CYCLING (USED)" if has_cycled_this_turn else "CYCLE"
	confirm_discard_button.visible   = discard_mode
	cancel_discard_button.visible    = discard_mode and cycling_active  # Cleanup Phase discard cannot be cancelled
	confirm_discard_button.text      = "DISCARD (" + str(discard_selected.size()) + ")"
	confirm_discard_button.disabled  = discard_selected.size() == 0

	# Drawing is automatic now — the deck pile is a visual/count display only.
	deck_pile.disabled = true
	deck_pile.dimmed   = true
	deck_pile.queue_redraw()

func _refresh_pvp_hand(list: HBoxContainer, hand: Array, color) -> void:
	for child in list.get_children():
		child.queue_free()
	var is_this_turn = (status == color) and not game_over and not promotion_pending
	var is_discard_here = discard_mode and status == color
	var layout = _hand_card_layout(hand.size())
	list.add_theme_constant_override("separation", int(layout.sep))
	for i in range(hand.size()):
		var card_id = hand[i]
		var data    = Globals.CARD_DATA[card_id]
		var sp      = white_sp if color == Globals.COLORS.WHITE else black_sp
		var mine_capped = card_id == Globals.CARD_ID.LAND_MINE and _active_mine_count(color) >= MAX_ACTIVE_MINES
		var is_pending_this  = (pending_card_id != null and color == status and i == pending_card_index)
		var interactive_here = is_pending_this or (pending_card_id == null and is_this_turn and sp >= data.cost and not mine_capped)
		var btn = load("res://scripts/card_visual.gd").new()
		btn.mode              = 1
		btn.custom_minimum_size = layout.size
		btn.card_title        = data.name
		btn.card_cost         = data.cost
		btn.art_path          = data.get("art_path", "")
		btn.armed             = is_pending_this
		if is_discard_here:
			btn.marked    = i in discard_selected
			btn.dimmed    = false
			btn.disabled  = false
		elif discard_mode:
			btn.dimmed    = true
			btn.disabled  = true
		else:
			btn.dimmed    = not is_this_turn or sp < data.cost or mine_capped
			btn.disabled  = not is_this_turn or mine_capped
		list.add_child(btn)
		btn.pressed.connect(_on_pvp_hand_card_pressed.bind(i, color))
		btn.mouse_entered.connect(_on_card_hover.bind(card_id, color))
		btn.mouse_exited.connect(_on_card_hover_end)

func _on_card_hover(card_id, color = player_color) -> void:
	_card_hover_active = true
	var data = Globals.CARD_DATA[card_id]
	card_info_title.text = data.name + "  (" + data.category + ")"
	var desc = data.desc
	if card_id == Globals.CARD_ID.LAND_MINE:
		var count = _active_mine_count(color)
		desc += "\n\nActive Mines: " + str(count) + " / " + str(MAX_ACTIVE_MINES)
		if count >= MAX_ACTIVE_MINES:
			desc += "\nMaximum Active Mines Reached"
	card_info_desc.text = desc

func _on_card_hover_end() -> void:
	_card_hover_active = false
	_hovered_piece      = null  # force a fresh refresh next time a piece is hovered
	card_info_title.text = "—"
	card_info_desc.text  = "Hover a card to see its description."

func _on_hand_card_pressed(index: int) -> void:
	if status != player_color or game_over or promotion_pending:
		return
	if pending_card_id != null:
		if index == pending_card_index:
			_cancel_card_targeting()
		return
	if index < 0 or index >= player_hand.size():
		return

	pending_acting_color = player_color

	if discard_mode:
		if index in discard_selected:
			discard_selected.erase(index)
		else:
			discard_selected = [index]  # exactly 1 card per discard action
		refresh_card_ui()
		return

	var card_id = player_hand[index]
	var data    = Globals.CARD_DATA[card_id]
	if player_sp < data.cost:
		card_status_label.text = "Not enough SP for " + data.name + " (needs " + str(data.cost) + ")"
		return
	if card_id == Globals.CARD_ID.LAND_MINE and _active_mine_count(player_color) >= MAX_ACTIVE_MINES:
		card_status_label.text = "Maximum Active Land Mines Reached (" + str(MAX_ACTIVE_MINES) + "/" + str(MAX_ACTIVE_MINES) + ")."
		return

	var valid = _get_valid_targets_for_card(card_id)
	if valid.is_empty():
		card_status_label.text = "No valid target for " + data.name + " right now."
		return

	pending_card_index     = index
	pending_card_id        = card_id
	pending_stage          = 1
	pending_extra          = {}
	pending_target_kind    = _target_kind_for_card(card_id)
	pending_targets_needed = 1
	pending_selected_targets = []
	pending_valid_targets  = valid
	card_status_label.text = "Select target for " + data.name + " (click card again or Esc to cancel)..."
	_highlight_card_targets()
	refresh_card_ui()

func _on_pvp_hand_card_pressed(index: int, color) -> void:
	if game_over or promotion_pending:
		return
	if discard_mode:
		# Only the currently active side may pick from their own hand during discard
		if status != color:
			return
		var hand_size = (white_hand if color == Globals.COLORS.WHITE else black_hand).size()
		if index < 0 or index >= hand_size:
			return
		if index in discard_selected:
			discard_selected.erase(index)
		else:
			discard_selected = [index]  # exactly 1 card per discard action
		refresh_card_ui()
		return
	if status != color:
		return
	if pending_card_id != null:
		if index == pending_card_index and pending_acting_color == color:
			_cancel_card_targeting()
		return

	var hand = white_hand if color == Globals.COLORS.WHITE else black_hand
	if index < 0 or index >= hand.size():
		return

	pending_acting_color = color

	var card_id = hand[index]
	var data    = Globals.CARD_DATA[card_id]
	var sp      = white_sp if color == Globals.COLORS.WHITE else black_sp
	if sp < data.cost:
		card_status_label.text = "Not enough SP for " + data.name + " (needs " + str(data.cost) + ")"
		return
	if card_id == Globals.CARD_ID.LAND_MINE and _active_mine_count(color) >= MAX_ACTIVE_MINES:
		card_status_label.text = "Maximum Active Land Mines Reached (" + str(MAX_ACTIVE_MINES) + "/" + str(MAX_ACTIVE_MINES) + ")."
		return

	var valid = _get_valid_targets_for_card(card_id, color)
	if valid.is_empty():
		card_status_label.text = "No valid target for " + data.name + " right now."
		return

	pending_card_index     = index
	pending_card_id        = card_id
	pending_stage          = 1
	pending_extra          = {}
	pending_target_kind    = _target_kind_for_card(card_id)
	pending_targets_needed = 1
	pending_selected_targets = []
	pending_valid_targets  = valid
	card_status_label.text = "Select target for " + data.name + " (click card again or Esc to cancel)..."
	_highlight_card_targets()
	refresh_card_ui()

func _target_kind_for_card(card_id) -> String:
	match card_id:
		Globals.CARD_ID.LAND_MINE: return "piece"
		Globals.CARD_ID.REVIVE:    return "graveyard"
		_: return "piece"

func _get_valid_targets_for_card(card_id, acting_color = player_color) -> Array:
	match card_id:
		Globals.CARD_ID.BOUNCE:      return _get_own_pieces_incl_king(acting_color)
		Globals.CARD_ID.DEVOUR:      return _get_own_non_king_pieces(acting_color)
		Globals.CARD_ID.SPRING_HORSE: return _get_own_knights(acting_color)
		Globals.CARD_ID.LAND_MINE:   return _get_land_mine_pawns(acting_color)
		Globals.CARD_ID.SACRIFICE:   return _get_sacrifice_targets(acting_color)
		Globals.CARD_ID.YOU_AND_ME:  return _front_most_pieces(opponent_color(acting_color))
		Globals.CARD_ID.REVIVE:      return _get_revive_graveyard_pool(acting_color)
		_: return []

func _get_own_pieces_incl_king(acting_color = player_color) -> Array:
	return board.pieces.filter(func(p): return p.color == acting_color and not p.is_exhausted())

func _get_own_non_king_pieces(acting_color = player_color) -> Array:
	return board.pieces.filter(func(p): return p.color == acting_color and p.piece_type != Globals.PIECE_TYPES.KING and not p.is_exhausted())

func _get_own_knights(acting_color = player_color) -> Array:
	return board.pieces.filter(func(p): return p.color == acting_color and p.piece_type == Globals.PIECE_TYPES.KNIGHT and not p.is_exhausted())

func _get_own_pieces_of_type(piece_type, acting_color = player_color) -> Array:
	return board.pieces.filter(func(p): return p.color == acting_color and p.piece_type == piece_type and not p.is_exhausted())

func _get_own_pawns(acting_color = player_color) -> Array:
	return _get_own_pieces_of_type(Globals.PIECE_TYPES.PAWN, acting_color)

func _is_square_mined(pos: Vector2) -> bool:
	for m in board.mines:
		if m.pos == pos: return true
	return false

# ── Land Mine balance cap ────────────────────────────────────────────────────
const MAX_ACTIVE_MINES := 5

# "Active" = currently on the board. Triggered/destroyed/removed mines are
# taken out of board.mines immediately (see _do_move's explosion handling),
# so this count is always accurate without any extra bookkeeping.
func _active_mine_count(color) -> int:
	var n = 0
	for m in board.mines:
		if m.get("owner", null) == color:
			n += 1
	return n

# Cloak reveal check — a mine becomes visible while any enemy piece (relative
# to whoever placed it) sits within the surrounding 3x3 area, and re-cloaks
# smoothly once no enemy remains in range. Purely visual (board.gd fades the
# alpha); the mine's actual function never changes.
func _update_mine_visibility() -> void:
	for m in board.mines:
		var owner_color = m.get("owner", null)
		var enemy_near = false
		for p in board.pieces:
			if owner_color != null and p.color == owner_color:
				continue
			if max(abs(p.board_position.x - m.pos.x), abs(p.board_position.y - m.pos.y)) <= 1:
				enemy_near = true
				break
		board.set_mine_revealed(m.pos, enemy_near)

# The 3 squares directly in front of a Pawn (diagonal-left, straight, diagonal-
# right), from that Pawn's own forward direction — White moves toward row 0,
# Black moves toward row 7. Only empty, unmined, on-board squares qualify.
func _get_land_mine_forward_squares(pawn) -> Array:
	var dir = -1 if pawn.color == Globals.COLORS.WHITE else 1
	var result = []
	for dx in [-1, 0, 1]:
		var pos = pawn.board_position + Vector2(dx, dir)
		if not _on_board(pos): continue
		if board.get_piece(pos) != null: continue
		if _is_square_mined(pos): continue
		result.append(pos)
	return result

# Only Pawns that actually have at least one legal forward square are
# selectable — an unusable Pawn shouldn't appear as a valid target.
func _get_land_mine_pawns(acting_color = player_color) -> Array:
	if _active_mine_count(acting_color) >= MAX_ACTIVE_MINES:
		return []
	return _get_own_pawns(acting_color).filter(func(p): return not _get_land_mine_forward_squares(p).is_empty())

func _get_sacrifice_targets(acting_color = player_color) -> Array:
	var result = []
	for p in board.pieces:
		if p.color == acting_color: continue
		if p.piece_type == Globals.PIECE_TYPES.KING: continue  # King can never be targeted
		if _is_duel_active(p): continue
		if _sacrifice_requirements_met(p, acting_color):
			result.append(p)
	return result

# Value-1 targets (e.g. Pawns) can be paid with either a friendly piece of the
# same type, or any friendly piece whose base Value is also 1.
func _sacrifice_value1_pool(acting_color, target_type) -> Array:
	return board.pieces.filter(func(p):
		return p.color == acting_color \
			and p.piece_type != Globals.PIECE_TYPES.KING \
			and (p.piece_type == target_type or get_base_value(p.piece_type) == 1.0)
	)

# Checks whether the player has the required friendly pieces to pay for a
# given enemy target: Value 1 → 1 matching piece; Value > 1 → 1 piece of the
# exact same type PLUS 1 additional Pawn.
func _sacrifice_requirements_met(target, acting_color) -> bool:
	var value = get_base_value(target.piece_type)
	if value <= 1.0:
		return not _sacrifice_value1_pool(acting_color, target.piece_type).is_empty()
	else:
		var same_pool = _get_own_pieces_of_type(target.piece_type, acting_color)
		var pawn_pool = _get_own_pawns(acting_color)
		return not same_pool.is_empty() and not pawn_pool.is_empty()

func _front_most_pieces(color) -> Array:
	var by_col = {}
	for p in board.pieces:
		if p.color != color: continue
		if not by_col.has(p.board_position.x): by_col[p.board_position.x] = []
		by_col[p.board_position.x].append(p)
	var result = []
	for col in by_col.keys():
		var best = null
		for p in by_col[col]:
			if best == null: best = p
			elif color == Globals.COLORS.WHITE and p.board_position.y < best.board_position.y: best = p
			elif color == Globals.COLORS.BLACK and p.board_position.y > best.board_position.y: best = p
		if best != null and best.piece_type != Globals.PIECE_TYPES.KING:
			result.append(best)
	return result

func _piece_type_name(t) -> String:
	match t:
		Globals.PIECE_TYPES.PAWN:   return "Pawn"
		Globals.PIECE_TYPES.KNIGHT: return "Knight"
		Globals.PIECE_TYPES.BISHOP: return "Bishop"
		Globals.PIECE_TYPES.ROOK:   return "Rook"
		Globals.PIECE_TYPES.QUEEN:  return "Queen"
		Globals.PIECE_TYPES.KING:   return "King"
		_: return "piece"

# ── Revive ────────────────────────────────────────────────────────────────────
# Mana cost to revive a given piece type, or -1 if that type can never be
# revived (King, Bishop, or anything outside the cost table).
func _revive_cost_for(piece_type) -> int:
	return Globals.REVIVE_MANA_COST.get(piece_type, -1)

# Every empty square orthogonally/diagonally adjacent to `pos`.
func _get_empty_adjacent_squares(pos: Vector2) -> Array:
	var result = []
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0: continue
			var p = pos + Vector2(dx, dy)
			if not _on_board(p): continue
			if board.get_piece(p) != null: continue
			result.append(p)
	return result

# Living, non-Exhausted Bishops belonging to acting_color that have at least
# one empty adjacent square — i.e. Bishops that could actually anchor a
# Revive. Filtering here means stage 2 never offers a Bishop that would fail
# the "no valid empty adjacent squares" check at stage 3.
func _get_own_bishops_with_space(acting_color = player_color) -> Array:
	return board.pieces.filter(func(p):
		return p.color == acting_color \
			and p.piece_type == Globals.PIECE_TYPES.BISHOP \
			and not p.is_exhausted() \
			and not _get_empty_adjacent_squares(p.board_position).is_empty()
	)

# Graveyard entries acting_color may legally revive right now: not King/Bishop,
# and currently affordable. Also requires at least one usable Bishop to exist —
# otherwise Revive can't be completed no matter which piece is chosen, so the
# card should show as having no valid targets at all.
func _get_revive_graveyard_pool(acting_color = player_color) -> Array:
	if _get_own_bishops_with_space(acting_color).is_empty():
		return []
	var sp = _active_sp()
	return _graveyard_list_for(acting_color).filter(func(e):
		var cost = _revive_cost_for(e["piece_type"])
		return cost > 0 and sp >= cost
	)

func _highlight_card_targets() -> void:
	if pending_target_kind == "graveyard":
		board.clear_highlights()
		_refresh_graveyard_highlight()
	elif pending_target_kind == "square":
		board.show_highlights(pending_valid_targets, [])
	else:
		board.show_highlights([], pending_valid_targets.map(func(p): return p.board_position))

func _handle_card_target_click() -> void:
	# Graveyard-piece selection is driven by button presses on the panel
	# itself (_on_graveyard_icon_pressed), not by clicking the board.
	if pending_target_kind == "graveyard":
		return

	var pos   = get_pos_under_mouse()
	var picked = null

	if pending_target_kind == "square":
		for v in pending_valid_targets:
			if v == pos: picked = v; break
	else:
		var pa = board.get_piece(pos)
		if pa != null and pa in pending_valid_targets:
			picked = pa

	if picked == null:
		return

	pending_selected_targets.append(picked)
	pending_valid_targets.erase(picked)

	if pending_card_id == Globals.CARD_ID.SACRIFICE and pending_target_kind == "piece":
		GameplaySfx.play_sacrifice_select()

	if pending_selected_targets.size() >= pending_targets_needed:
		_advance_card_stage()
	else:
		card_status_label.text = "Select target " + str(pending_selected_targets.size()+1) + \
								 " of " + str(pending_targets_needed) + \
								 " for " + Globals.CARD_DATA[pending_card_id].name + "..."
		_highlight_card_targets()

func _cancel_card_targeting() -> void:
	_clear_pending_card_state()
	board.clear_highlights()
	card_status_label.text = "Cancelled."
	refresh_card_ui()

func _clear_pending_card_state(keep_sacrifice_circles: bool = false) -> void:
	if pending_card_id == Globals.CARD_ID.SACRIFICE and not keep_sacrifice_circles:
		_sacrifice_hide_all_magic_circles()
	_revive_clear_bishop_glow()
	_revive_hovered_bishop = null
	board.clear_revive_hover_square()
	pending_card_index       = -1
	pending_card_id          = null
	pending_stage            = 1
	pending_target_kind      = "piece"
	pending_targets_needed   = 0
	pending_selected_targets = []
	pending_valid_targets    = []
	pending_extra            = {}
	pending_acting_color     = null
	_refresh_graveyard_highlight()

# Fades out the magic circle beneath every piece currently marked as part of
# the in-progress Sacrifice (whether it's being cancelled or resolved).
func _sacrifice_hide_all_magic_circles() -> void:
	for key in ["sac_target", "sac_same_type", "sac_pawn"]:
		if pending_extra.has(key):
			var p = pending_extra[key]
			if p != null and is_instance_valid(p):
				p.hide_magic_selection()

func _advance_card_stage() -> void:
	match pending_card_id:
		Globals.CARD_ID.SACRIFICE:  _sacrifice_stage_advance()
		Globals.CARD_ID.YOU_AND_ME: _you_and_me_stage_advance()
		Globals.CARD_ID.REVIVE:     _revive_stage_advance()
		Globals.CARD_ID.LAND_MINE:  _land_mine_stage_advance()
		_:                          _finish_simple_card()

func _finish_simple_card() -> void:
	var data    = Globals.CARD_DATA[pending_card_id]
	var targets = pending_selected_targets.duplicate()
	var card_id = pending_card_id
	var hand    = _active_hand_array()
	var discard = _active_discard_array()
	_set_active_sp(_active_sp() - data.cost)
	discard.append(hand[pending_card_index])
	hand.remove_at(pending_card_index)
	_clear_pending_card_state()
	board.clear_highlights()
	_apply_card_effect(card_id, targets)
	var desc = _simple_card_log_desc(card_id, targets)
	_log_record_card(data.name, desc.target, desc.effect)
	refresh_card_ui()

func _apply_card_effect(card_id, targets: Array) -> void:
	match card_id:
		Globals.CARD_ID.BOUNCE:
			targets[0].status_bounce = true
			card_status_label.text = "Bounce granted — it'll retreat after its next capture."
		Globals.CARD_ID.DEVOUR:
			targets[0].status_devour = true
			card_status_label.text = "Devour granted — it'll transform after its next capture."
		Globals.CARD_ID.SPRING_HORSE:
			targets[0].status_spring_horse = true
			card_status_label.text = "Spring Horse granted — this Knight can now hop adjacent pieces."

# ── Land Mine ─────────────────────────────────────────────────────────────────
# Stage 1: pick one of your own Pawns (only Pawns with a usable forward square
#          are selectable — see _get_land_mine_pawns).
# Stage 2: pick one of that Pawn's 3 forward squares (diag-left / straight /
#          diag-right) → resolve. The mine immediately gains Cloak.
func _land_mine_stage_advance() -> void:
	if pending_stage == 1:
		var pawn = pending_selected_targets[0]
		pending_extra["mine_pawn"] = pawn
		var squares = _get_land_mine_forward_squares(pawn)
		if squares.is_empty():
			# Shouldn't happen — stage 1's pool already filtered for this —
			# but fail safely rather than resolve onto an invalid square.
			card_status_label.text = "That Pawn has no open square in front of it."
			_cancel_card_targeting()
			return
		pending_stage            = 2
		pending_target_kind      = "square"
		pending_targets_needed   = 1
		pending_selected_targets = []
		pending_valid_targets    = squares
		card_status_label.text  = "Select a square in front of that Pawn..."
		_highlight_card_targets()
		refresh_card_ui()
	else:
		_land_mine_resolve()

func _land_mine_resolve() -> void:
	var data    = Globals.CARD_DATA[Globals.CARD_ID.LAND_MINE]
	var square  = pending_selected_targets[0]
	var pawn    = pending_extra["mine_pawn"]
	var color   = pending_acting_color
	var hand    = _active_hand_array()
	var discard = _active_discard_array()
	_set_active_sp(_active_sp() - data.cost)
	discard.append(hand[pending_card_index])
	hand.remove_at(pending_card_index)
	_clear_pending_card_state()
	board.clear_highlights()

	board.mines.append({"pos": square, "placed_turn": player_turn_number, "owner": color})
	board.register_mine_placed(square)
	_update_mine_visibility()
	card_status_label.text = "Mine planted in front of your Pawn — it fades from sight..."
	_log_record_card(data.name, "square " + _square_name(square) + " (in front of " + _piece_log_desc(pawn) + ")", "mine armed, Cloaked")
	refresh_card_ui()

# ── Sacrifice ─────────────────────────────────────────────────────────────────
# Stage 1: pick the enemy target (handled generically before this is called).
# Stage 2: Value 1 target  → pick 1 friendly piece (same type OR any Value-1) → resolve.
#          Value >1 target → pick 1 friendly piece of the exact same type     → stage 3.
# Stage 3: (Value >1 only) → pick 1 additional friendly Pawn                  → resolve.
func _sacrifice_stage_advance() -> void:
	if pending_stage == 1:
		var target = pending_selected_targets[0]
		pending_extra["sac_target"]    = target
		target.show_magic_selection()
		var value = get_base_value(target.piece_type)
		var value_is_one = value <= 1.0
		pending_extra["sac_value_one"] = value_is_one
		pending_stage             = 2
		pending_selected_targets  = []
		if value_is_one:
			pending_targets_needed = 1
			pending_valid_targets  = _sacrifice_value1_pool(pending_acting_color, target.piece_type)
			card_status_label.text = "Select 1 friendly " + _piece_type_name(target.piece_type) + \
									 " (or any Value 1 piece) to sacrifice..."
		else:
			pending_targets_needed = 1
			pending_valid_targets  = _get_own_pieces_of_type(target.piece_type, pending_acting_color)
			card_status_label.text = "Select 1 of your own " + _piece_type_name(target.piece_type) + \
									 "s to sacrifice (1 of 2 required)..."
		_highlight_card_targets()
		refresh_card_ui()
	elif pending_stage == 2:
		pending_extra["sac_same_type"] = pending_selected_targets[0]
		pending_extra["sac_same_type"].show_magic_selection()
		if pending_extra["sac_value_one"]:
			_sacrifice_resolve()
		else:
			pending_stage            = 3
			pending_selected_targets = []
			pending_targets_needed   = 1
			pending_valid_targets    = _get_own_pawns(pending_acting_color)
			if pending_valid_targets.is_empty():
				_clear_pending_card_state()
				board.clear_highlights()
				card_status_label.text = "You don't have a Pawn to complete the Sacrifice."
				refresh_card_ui()
				return
			card_status_label.text = "Select 1 friendly Pawn to sacrifice as well (2 of 2 required)..."
			_highlight_card_targets()
			refresh_card_ui()
	else:
		pending_extra["sac_pawn"] = pending_selected_targets[0]
		pending_extra["sac_pawn"].show_magic_selection()
		_sacrifice_resolve()

const ENERGY_LINK_SCENE = preload("res://scenes/EnergyLink.tscn")
const SACRIFICE_LINK_DURATION  := 0.7   # time to let the energy link build/pulse
const SACRIFICE_BURST_LEAD_OUT := 0.6   # time to let the final burst play out

func _sacrifice_resolve() -> void:
	var data    = Globals.CARD_DATA[Globals.CARD_ID.SACRIFICE]
	var target  = pending_extra["sac_target"]
	var sacs    = [pending_extra["sac_same_type"]]
	if pending_extra.has("sac_pawn"):
		sacs.append(pending_extra["sac_pawn"])
	var hand    = _active_hand_array()
	var discard = _active_discard_array()
	_set_active_sp(_active_sp() - data.cost)
	discard.append(hand[pending_card_index])
	hand.remove_at(pending_card_index)
	# Keep the magic circles alive — this function animates them out itself,
	# timed with the energy link + final burst below.
	_clear_pending_card_state(true)
	board.clear_highlights()
	var target_desc = _piece_log_desc(target)
	_log_record_card(data.name, target_desc, "activated")
	refresh_card_ui()

	sacrifice_resolving = true
	card_status_label.text = "The sacrifice is bound..."

	# Energy link — a brief glowing tether from each sacrificed piece to the
	# target, so the connection reads clearly before anything is destroyed.
	var links: Array = []
	for p in sacs:
		var link = ENERGY_LINK_SCENE.instantiate()
		link.point_a = p.position
		link.point_b = target.position
		board.add_child(link)
		links.append(link)
	await get_tree().create_timer(SACRIFICE_LINK_DURATION).timeout

	# Final burst — pieces and their magic circles erupt together, then are
	# actually destroyed, giving the moment real impact.
	card_status_label.text = "Sacrifice erupts!"
	GameplaySfx.play_sacrifice_resolve()
	# Cache anything we still need for display text below — target/sacs get
	# queue_free()'d by their own death animation partway through the final
	# await, so they can't be safely read again after this point.
	var target_type_name = _piece_type_name(target.piece_type)
	for link in links:
		link.fade_out_and_free()
	for p in sacs:
		_log_record_capture(p.piece_type, "Sacrifice card (paid)", p.color)
		p.burst_magic_selection()
		board.delete_piece(p)
	target.burst_magic_selection()
	_log_record_capture(target.piece_type, "Sacrifice card", target.color)
	board.delete_piece(target)

	await get_tree().create_timer(SACRIFICE_BURST_LEAD_OUT).timeout

	sacrifice_resolving = false
	card_status_label.text = "Sacrifice resolved — enemy " + target_type_name + " destroyed."
	refresh_card_ui()

# ── You and Me ────────────────────────────────────────────────────────────────
func _you_and_me_stage_advance() -> void:
	if pending_stage == 1:
		var enemy         = pending_selected_targets[0]
		pending_extra["you_enemy"] = enemy
		var base_cost     = Globals.CARD_DATA[Globals.CARD_ID.YOU_AND_ME].cost
		var needs_queen   = (enemy.piece_type == Globals.PIECE_TYPES.QUEEN)
		var cur_sp        = _active_sp()
		var filtered      = []
		# ผู้เล่นเลือกได้จากทุก piece ของตัวเอง (ยกเว้น King)
		for p in board.pieces:
			if p.color != pending_acting_color: continue
			if p.piece_type == Globals.PIECE_TYPES.KING: continue
			if p.is_exhausted(): continue
			if needs_queen and p.piece_type != Globals.PIECE_TYPES.QUEEN and cur_sp < base_cost + 2:
				continue
			filtered.append(p)
		if filtered.is_empty():
			card_status_label.text = "No valid partner for You and Me."
			_cancel_card_targeting()
			return
		pending_stage            = 2
		pending_targets_needed   = 1
		pending_selected_targets = []
		pending_valid_targets    = filtered
		card_status_label.text   = "Select your own piece to pair with it..."
		_highlight_card_targets()
		refresh_card_ui()
	else:
		var enemy    = pending_extra["you_enemy"]
		var own      = pending_selected_targets[0]
		var base     = Globals.CARD_DATA[Globals.CARD_ID.YOU_AND_ME].cost
		var extra    = 2 if (enemy.piece_type == Globals.PIECE_TYPES.QUEEN and own.piece_type != Globals.PIECE_TYPES.QUEEN) else 0
		var hand     = _active_hand_array()
		var discard  = _active_discard_array()
		_set_active_sp(_active_sp() - (base + extra))
		discard.append(hand[pending_card_index])
		hand.remove_at(pending_card_index)
		_clear_pending_card_state()
		board.clear_highlights()
		own.duel_partner                = enemy
		enemy.duel_partner              = own
		own.duel_expires_after_turn     = player_turn_number + 2
		enemy.duel_expires_after_turn   = player_turn_number + 2
		_log_record_card("You and Me", _piece_log_desc(enemy), "paired with your " + _piece_type_name(own.piece_type) + " for 3 turns" + (" (+2 SP surcharge)" if extra > 0 else ""))
		card_status_label.text = "You and Me: bound for 3 of your turns." + (" (+2 SP surcharge)" if extra > 0 else "")
		board.queue_redraw()
		refresh_card_ui()

# ── Revive ────────────────────────────────────────────────────────────────────
# Stage 1: pick a piece from your own Graveyard (handled via graveyard icon
#          presses, not board clicks — see _on_graveyard_icon_pressed).
# Stage 2: pick one of your living, non-Exhausted Bishops as the anchor.
# Stage 3: pick one empty square adjacent to that Bishop → resolve.
func _revive_stage_advance() -> void:
	if pending_stage == 1:
		var entry = pending_selected_targets[0]
		pending_extra["revive_entry"] = entry
		var bishops = _get_own_bishops_with_space(pending_acting_color)
		pending_stage            = 2
		pending_target_kind      = "piece"
		pending_targets_needed   = 1
		pending_selected_targets = []
		pending_valid_targets    = bishops
		card_status_label.text  = "Select a living Bishop to anchor the revival..."
		_highlight_card_targets()
		_refresh_graveyard_highlight()  # leaving the graveyard-selection stage
		_revive_apply_bishop_glow(bishops)  # Phase 1 — glow valid, dim invalid
		refresh_card_ui()
	elif pending_stage == 2:
		var bishop  = pending_selected_targets[0]
		pending_extra["revive_bishop"] = bishop
		var squares = _get_empty_adjacent_squares(bishop.board_position)
		if squares.is_empty():
			# Shouldn't happen — stage 2's pool already filtered for this —
			# but fail safely rather than revive onto an invalid square.
			_revive_clear_bishop_glow()
			card_status_label.text = "No empty square beside that Bishop."
			_cancel_card_targeting()
			return
		_revive_clear_bishop_glow()
		board.clear_highlights()
		revive_resolving = true
		card_status_label.text = "The anchor awakens..."
		_revive_camera_push_in()
		await bishop.play_revive_anchor_charge()  # Phase 2 — ~1s
		revive_resolving = false

		pending_stage            = 3
		pending_target_kind      = "square"
		pending_targets_needed   = 1
		pending_selected_targets = []
		pending_valid_targets    = squares
		card_status_label.text  = "Select an empty square beside the Bishop..."
		_highlight_card_targets()  # Phase 3 — highlight valid adjacent tiles
		refresh_card_ui()
	else:
		_revive_resolve()

# Phase 1 — every Bishop on the board glows gold if it's a valid anchor for
# this Revive, or appears dimmed if it isn't. Purely visual.
func _revive_apply_bishop_glow(valid_bishops: Array) -> void:
	for p in board.pieces:
		if p.piece_type != Globals.PIECE_TYPES.BISHOP:
			continue
		if p in valid_bishops:
			p.set_revive_glow_state("valid")
		else:
			p.set_revive_glow_state("dim")

func _revive_clear_bishop_glow() -> void:
	for p in board.pieces:
		if p.piece_type == Globals.PIECE_TYPES.BISHOP:
			p.clear_revive_glow()

# Phase 2 / Phase 6 — a very subtle push-in/settle-back on the board itself
# (there's no Camera2D in this scene), standing in for "camera zoom" without
# any screen shake or hard cuts.
func _revive_camera_push_in() -> void:
	var t := create_tween()
	t.tween_property(board, "scale", Vector2(1.018, 1.018), 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _revive_camera_settle() -> void:
	var t := create_tween()
	t.tween_property(board, "scale", Vector2.ONE, 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

const REVIVE_BEAM_LEAD_IN  := 0.5   # let the beam descend before the piece appears
const REVIVE_AURA_SETTLE   := 0.4   # let the Exhausted auras read before settling

func _revive_resolve() -> void:
	var data   = Globals.CARD_DATA[Globals.CARD_ID.REVIVE]
	var entry  = pending_extra["revive_entry"]
	var bishop = pending_extra["revive_bishop"]
	var square = pending_selected_targets[0]
	var color  = pending_acting_color
	var cost   = _revive_cost_for(entry["piece_type"])

	var hand    = _active_hand_array()
	var discard = _active_discard_array()
	_set_active_sp(_active_sp() - cost)
	discard.append(hand[pending_card_index])
	hand.remove_at(pending_card_index)
	_clear_pending_card_state()
	board.clear_highlights()

	revive_resolving = true
	card_status_label.text = "The light descends..."

	# Phase 4 — a beam of light descends onto the target square, then the
	# revived piece rises up out of it and materializes into place.
	board.spawn_revive_beam(square)
	await get_tree().create_timer(REVIVE_BEAM_LEAD_IN).timeout

	_graveyard_remove(entry)
	var revived = board.spawn_piece(entry["piece_type"], color, square)
	await revived.play_revive_materialize()

	_apply_exhausted(bishop, 1)
	_apply_exhausted(revived, cost)

	# Phase 5 — purple Exhausted aura on both the revived piece and its
	# anchor Bishop, easing into the persistent on-board Exhausted icon.
	revived.play_revive_purple_aura(true)
	bishop.play_revive_purple_aura(false)
	await get_tree().create_timer(REVIVE_AURA_SETTLE).timeout

	# Phase 6 — settle back to the normal view and restore play.
	_revive_camera_settle()

	var target_desc = _color_name(color) + " " + _piece_type_name(entry["piece_type"]) + " → " + _square_name(square)
	_log_record_card(data.name, target_desc, "revived beside " + _color_name(bishop.color) + " Bishop")
	card_status_label.text = "Revived your " + _piece_type_name(entry["piece_type"]) + "!"
	board.queue_redraw()
	revive_resolving = false
	refresh_card_ui()

# Grants Exhausted to a piece, stacking additively onto any remaining
# duration, and logs the application to the Turn Log.
func _apply_exhausted(piece, duration: int) -> void:
	piece.exhausted_turns += duration
	_log_record_event(_color_name(piece.color) + " " + _piece_type_name(piece.piece_type) + \
		" gains Exhausted (" + str(duration) + ") — now Exhausted (" + str(piece.exhausted_turns) + ")")
	board.queue_redraw()

# ── Cycling (discard 1, draw 1 — once per turn, Move Phase only) ──────────────
func _on_discard_draw_pressed() -> void:
	if game_over or promotion_pending or pending_card_id != null:
		return
	if turn_phase != TurnPhase.MOVE or has_cycled_this_turn or discard_mode:
		return
	var is_pvp = (player2_type == Globals.PLAYER_2_TYPE.HUMAN)
	if not is_pvp and status != player_color:
		return
	cycling_active   = true
	discard_mode     = true
	discard_selected = []
	card_status_label.text = "Cycling: pick 1 card to discard, then press DISCARD."
	refresh_card_ui()

func _on_confirm_discard_pressed() -> void:
	if discard_selected.size() == 0:
		return
	var is_pvp = (player2_type == Globals.PLAYER_2_TYPE.HUMAN)
	var idx    = discard_selected[0]
	var discarded_name: String

	if is_pvp:
		var color   = status
		var hand    = white_hand if color == Globals.COLORS.WHITE else black_hand
		var discard = white_discard_pile if color == Globals.COLORS.WHITE else black_discard_pile
		discarded_name = Globals.CARD_DATA[hand[idx]].name
		discard.append(hand[idx])
		hand.remove_at(idx)
		if color == Globals.COLORS.WHITE:
			white_hand = hand; white_discard_pile = discard
		else:
			black_hand = hand; black_discard_pile = discard
		pending_acting_color = color
	else:
		discarded_name = Globals.CARD_DATA[player_hand[idx]].name
		player_discard_pile.append(player_hand[idx])
		player_hand.remove_at(idx)

	discard_selected = []

	if cleanup_discard_active:
		_log_record_card("Discarded " + discarded_name + " (Cleanup Phase)")
		if _turn_hand_size() > Globals.MAX_HAND_SIZE:
			# Still over the limit — loop back and prompt for another discard.
			var over = _turn_hand_size() - Globals.MAX_HAND_SIZE
			card_status_label.text = "Discard " + str(over) + " more card(s) to reach hand size " + str(Globals.MAX_HAND_SIZE) + "."
			refresh_card_ui()
		else:
			discard_mode = false
			_enter_move_phase()
		return

	if cycling_active:
		cycling_active        = false
		discard_mode          = false
		has_cycled_this_turn  = true
		if is_pvp:
			_pvp_draw_card(status)
		else:
			_draw_card()
			pop_next_new_card = true
		_log_record_card("Cycled " + discarded_name)
		card_status_label.text = "Cycled: discarded " + discarded_name + " and drew a new card."
		refresh_card_ui()
		return

	discard_mode = false
	refresh_card_ui()

func _on_cancel_discard_pressed() -> void:
	if cleanup_discard_active:
		# Forced (Cleanup Phase) discard — cannot cancel.
		card_status_label.text = "Hand size exceeds " + str(Globals.MAX_HAND_SIZE) + " — you must discard before continuing."
		return
	cycling_active         = false
	discard_mode           = false
	discard_selected        = []
	card_status_label.text = ""
	refresh_card_ui()

# ── Button callbacks ──────────────────────────────────────────────────────────
func _on_button_pressed():
	UISfx.play_click()
	get_tree().reload_current_scene()

func _on_exit_pressed():
	UISfx.play_click()
	SceneTransition.go("res://scenes/MainMenu.tscn")

func _on_back_menu_pressed():
	UISfx.play_click()
	SceneTransition.go("res://scenes/MainMenu.tscn")

func _on_restart_pressed():
	UISfx.play_click()
	$UI/RestartConfirmDialog.popup_centered()

func _on_restart_confirmed():
	get_tree().reload_current_scene()

func _on_back_side_pressed():
	UISfx.play_click()
	SceneTransition.go("res://scenes/ModeSelect.tscn")

func _on_side_white_pressed():
	Globals.selected_color = Globals.COLORS.WHITE
	var tw = create_tween()
	tw.tween_property(white_card, "scale", Vector2(0.95, 0.95), 0.07)
	tw.tween_callback(func():
		side_panel.hide()
		back_menu_btn.show()
		init_game()
	)

func _on_side_black_pressed():
	Globals.selected_color = Globals.COLORS.BLACK
	var tw = create_tween()
	tw.tween_property(black_card, "scale", Vector2(0.95, 0.95), 0.07)
	tw.tween_callback(func():
		side_panel.hide()
		back_menu_btn.show()
		init_game()
	)

func _on_promote_queen():  promote_pawn(Globals.PIECE_TYPES.QUEEN)
func _on_promote_rook():   promote_pawn(Globals.PIECE_TYPES.ROOK)
func _on_promote_knight(): promote_pawn(Globals.PIECE_TYPES.KNIGHT)
func _on_promote_bishop(): promote_pawn(Globals.PIECE_TYPES.BISHOP)
