extends CanvasLayer

## SceneTransition — chess-themed diagonal page-turn wipe (no flash/flicker)
## Usage: SceneTransition.go("res://scenes/MyScene.tscn")

signal transition_finished

const WIPE_DURATION   := 0.38
const HOLD_DURATION    := 0.08
const REVEAL_DURATION := 0.32

var _busy: bool = false

@onready var overlay: ColorRect = $Overlay

const TRANSITION_STREAM := preload("res://audio/scene_transition.wav")
# Kept comfortably below typical BGM level so it never overpowers the music.
const TRANSITION_VOLUME_DB := -10.0

var _sfx: AudioStreamPlayer

func _ready() -> void:
	layer = 128
	# visible = false already set in .tscn; assign shader material
	overlay.material = _make_wipe_material()

	_sfx = AudioStreamPlayer.new()
	_sfx.stream = TRANSITION_STREAM
	_sfx.volume_db = TRANSITION_VOLUME_DB
	_sfx.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_sfx)

# ── Public API ────────────────────────────────────────────────────────────────

func go(scene_path: String) -> void:
	if _busy:
		return
	_busy = true
	await _play_out()
	get_tree().change_scene_to_file(scene_path)
	# Use a timer instead of process_frame to avoid triggering _ready() conflicts
	await get_tree().create_timer(0.05).timeout
	await _play_in()
	_busy = false
	emit_signal("transition_finished")

# ── Internal ──────────────────────────────────────────────────────────────────

func _play_out() -> void:
	# Page-turn wipe covers screen: progress 0 → 1. No flash — the leading
	# edge glow is a soft, constant-brightness stripe, not a brightness pulse.
	overlay.visible = true
	_set_progress(0.0)
	overlay.material.set_shader_parameter("reveal_mode", false)

	# Transition sound starts the instant the page-turn begins; its length
	# (~0.78s) matches wipe + hold + reveal, so it ends as the animation does.
	_sfx.play()

	var t1 := create_tween()
	t1.tween_method(_set_progress, 0.0, 1.0, WIPE_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await t1.finished

	await get_tree().create_timer(HOLD_DURATION).timeout

func _play_in() -> void:
	# Page-turn wipe reveals screen from opposite corner: progress 0 → 1 in reveal_mode
	overlay.material.set_shader_parameter("reveal_mode", true)
	_set_progress(0.0)
	var t := create_tween()
	t.tween_method(_set_progress, 0.0, 1.0, REVEAL_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await t.finished
	overlay.visible = false

func _set_progress(v: float) -> void:
	overlay.material.set_shader_parameter("progress", v)

func _make_wipe_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _get_wipe_shader()
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("reveal_mode", false)
	mat.set_shader_parameter("wipe_color", Color(0.06, 0.06, 0.10, 1.0))
	mat.set_shader_parameter("edge_color", Color(1.0, 0.71, 0.44, 1.0))
	return mat

func _get_wipe_shader() -> Shader:
	var src := """
shader_type canvas_item;

uniform float progress    : hint_range(0.0, 1.0) = 0.0;
uniform bool  reveal_mode = false;
uniform vec4  wipe_color  : source_color = vec4(0.06, 0.06, 0.10, 1.0);
uniform vec4  edge_color  : source_color = vec4(1.0, 0.71, 0.44, 1.0);

void fragment() {
	// Cover  : diagonal sweeps top-left → bottom-right  (diag 0→1 covered)
	// Reveal : diagonal sweeps bottom-right → top-left  (diag 1→0 revealed)
	float diag = (UV.x + UV.y) * 0.5;

	// In reveal_mode flip the axis so wipe goes opposite direction
	float axis = reveal_mode ? (1.0 - diag) : diag;

	// Wider, softer band than before so the leading edge reads as a smooth
	// gradient sweep (page-turn) rather than a hard, high-contrast line —
	// this is what previously read as a "flash" at the wipe boundary.
	float band   = 0.09;
	float edge_lo = progress - band;
	float edge_hi = progress + band * 0.5;

	if (axis < edge_lo) {
		// Fully covered by dark panel
		COLOR = wipe_color;
	} else if (axis < progress) {
		// Leading-edge gradient — same peak brightness as edge_color, no overshoot,
		// so there is no brightness spike/pulse, just a smooth color blend.
		float t = (axis - edge_lo) / (progress - edge_lo);
		COLOR   = mix(edge_color, wipe_color, t);
		COLOR.a = 1.0;
	} else if (axis < edge_hi) {
		// Soft fade-out behind edge
		float t = (axis - progress) / (edge_hi - progress);
		COLOR   = edge_color;
		COLOR.a = 1.0 - t;
	} else {
		// Transparent — shows scene beneath
		COLOR = vec4(0.0);
	}
}
"""
	var sh := Shader.new()
	sh.code = src
	return sh
