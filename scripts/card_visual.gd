extends Button

# mode 0 = face-down deck pile (stack of 3 backs)
# mode 1 = a single face-up hand card (art + name only — cost is on the art itself)
@export var mode: int = 1

var card_title: String = ""
var card_cost: int = 0
var art_path: String = ""
var art_texture: Texture2D = null
var marked: bool = false   # highlighted for discarding
var armed: bool = false    # currently waiting for a target pick — click again to cancel
var dimmed: bool = false   # not currently usable

const BG          = Color(0.196, 0.161, 0.278, 1.0)
const BG_BACK     = Color(0.122, 0.094, 0.176, 1.0)
const BORDER      = Color(1.0, 0.710, 0.439, 1.0)
const BORDER_DIM  = Color(1.0, 0.710, 0.439, 0.30)
const BORDER_MARK = Color(0.886, 0.345, 0.412, 1.0)
const BORDER_ARMED = Color(1.0, 0.85, 0.3, 1.0)
const TEXT_COLOR  = Color(0.863, 0.796, 0.925, 1.0)
const STRIP_BG    = Color(0.094, 0.063, 0.137, 0.6)
const CARD_FONT   = preload("res://fonts/PressStart2P-Regular.ttf")

var name_label: Label = null

func _ready() -> void:
	flat = true
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())

	if mode == 1:
		if art_path != "":
			art_texture = _load_art_texture(art_path)

		name_label = Label.new()
		name_label.add_theme_font_override("font", CARD_FONT)
		name_label.add_theme_font_size_override("font_size", 7)
		name_label.add_theme_color_override("font_color", TEXT_COLOR)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		name_label.offset_top = -36
		name_label.offset_bottom = -6
		name_label.offset_left = 4
		name_label.offset_right = -4
		add_child(name_label)
		name_label.text = card_title

# While armed (selected/pending), redraw every frame so the floating arrow
# above the card animates smoothly. Cheap no-op otherwise.
func _process(_delta: float) -> void:
	if armed:
		queue_redraw()

# Loads a PNG straight from disk into a usable texture, bypassing Godot's
# resource-import cache entirely. New asset files dropped into the project
# (like these card images) don't have an .import cache yet until the
# editor has scanned them once, and plain load() can return null until
# then — Image.load() reads the raw file bytes directly, so it works
# immediately regardless of import state.
func _load_art_texture(path: String) -> Texture2D:
	var img = Image.new()
	var err = img.load(path)
	if err != OK:
		return null
	return ImageTexture.create_from_image(img)

func _draw() -> void:
	var size = get_size()
	if mode == 0:
		_draw_stack(size)
	else:
		_draw_single(size)

func _draw_stack(size: Vector2) -> void:
	var card_w = size.x - 8.0
	var card_h = size.y - 8.0
	var border_color = BORDER_DIM if dimmed else BORDER
	for i in range(3):
		var off = Vector2(i * 4.0, i * 4.0)
		var rect = Rect2(off, Vector2(card_w, card_h))
		draw_rect(rect, BG_BACK)
		draw_rect(rect, border_color, false, 2.0)
		if i == 2:
			_draw_back_pattern(rect, border_color)

func _draw_single(size: Vector2) -> void:
	var rect = Rect2(Vector2.ZERO, size)
	var border_color = BORDER_ARMED if armed else (BORDER_MARK if marked else (BORDER_DIM if dimmed else BORDER))
	var inset = 2.0
	var art_rect = Rect2(Vector2(inset, inset), size - Vector2(inset * 2.0, inset * 2.0))

	if art_texture != null:
		draw_texture_rect(art_texture, art_rect, false)
		if dimmed:
			draw_rect(art_rect, Color(0.094, 0.063, 0.137, 0.55))
	else:
		draw_rect(rect, BG)

	draw_rect(rect, border_color, false, 3.0 if armed else (2.5 if marked else 2.0))

	# Dark strip behind the name label so it stays legible over the art
	draw_rect(Rect2(Vector2(0, size.y - 32), Vector2(size.x, 32)), STRIP_BG)

	if armed:
		_draw_selection_arrow(size)

# A gentle, continuously-floating arrow above the currently selected card.
# Uses the engine clock (not a per-instance timer) so the animation stays
# smooth and un-jumpy even though refresh_card_ui() recreates this button
# node from scratch on every UI refresh.
func _draw_selection_arrow(size: Vector2) -> void:
	var t    = Time.get_ticks_msec() / 1000.0
	var bob  = sin(t * 2.6) * 3.0           # gentle float, ~3px amplitude
	var cx   = size.x * 0.5
	var tip_y    = -5.0 + bob               # arrow tip, closest to the card
	var shaft_len = 7.0
	var head_w    = 6.0
	var head_h    = 6.0
	var col      = Color(1.0, 0.85, 0.3, 0.95)
	var glow_col = Color(1.0, 0.85, 0.3, 0.28)

	# Soft glow pass first (larger, translucent, behind the solid arrow)
	draw_line(Vector2(cx, tip_y - shaft_len - 3.0), Vector2(cx, tip_y - head_h + 2.0), glow_col, 5.0, true)
	var glow_head = PackedVector2Array([
		Vector2(cx - head_w - 2.0, tip_y - head_h - 2.0),
		Vector2(cx + head_w + 2.0, tip_y - head_h - 2.0),
		Vector2(cx, tip_y + 2.0),
	])
	draw_colored_polygon(glow_head, glow_col)

	# Shaft
	draw_line(Vector2(cx, tip_y - shaft_len), Vector2(cx, tip_y - head_h), col, 2.2, true)
	# Arrowhead — a small triangle pointing down at the card
	var head = PackedVector2Array([
		Vector2(cx - head_w, tip_y - head_h),
		Vector2(cx + head_w, tip_y - head_h),
		Vector2(cx, tip_y),
	])
	draw_colored_polygon(head, col)

func _draw_back_pattern(rect: Rect2, line_color: Color) -> void:
	var c = rect.position + rect.size * 0.5
	var r1 = min(rect.size.x, rect.size.y) * 0.28
	var r2 = r1 * 0.55
	draw_arc(c, r1, 0, TAU, 28, line_color, 1.5)
	draw_arc(c, r2, 0, TAU, 20, line_color, 1.5)
	draw_line(c - Vector2(r1, 0), c + Vector2(r1, 0), line_color, 1.5)
	draw_line(c - Vector2(0, r1), c + Vector2(0, r1), line_color, 1.5)
