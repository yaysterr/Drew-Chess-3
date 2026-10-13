extends Node2D

@onready var title_label = $Title
@onready var title_shadow = $TitleShadow
@onready var play_button = $PlayButton
@onready var divider_left = $DividerLeft
@onready var divider_right = $DividerRight
@onready var divider_line = $DividerLine

var time_elapsed: float = 0.0
var base_title_scale: Vector2
var _is_hovering: bool = false

func _ready():
	MusicManager.play_track(MusicManager.Track.MAIN_MENU)

	base_title_scale = title_label.scale
	title_label.pivot_offset = title_label.size * 0.5
	title_shadow.pivot_offset = title_shadow.size * 0.5

	play_button.pivot_offset = play_button.size * 0.5
	play_button.mouse_entered.connect(_on_play_hover_start)
	play_button.mouse_exited.connect(_on_play_hover_end)

func _process(delta):
	time_elapsed += delta

	# Title "breathing" pulse + glow flicker via color shift
	var breathe = 1.0 + sin(time_elapsed * 1.4) * 0.02
	title_label.scale = base_title_scale * breathe
	title_shadow.scale = base_title_scale * breathe

	var glow = 0.5 + 0.5 * sin(time_elapsed * 1.4)
	title_label.modulate = Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.85, 0.6), glow)

	# Divider knights + line: slow shimmer pulse
	var shimmer = 0.65 + 0.35 * sin(time_elapsed * 1.6)
	divider_left.modulate.a = shimmer
	divider_right.modulate.a = shimmer
	divider_line.modulate.a = 0.3 + 0.5 * shimmer

	# Button idle pulse (subtle scale breathing when not hovered)
	if not _is_hovering:
		var btn_breathe = 1.0 + sin(time_elapsed * 2.2) * 0.025
		play_button.scale = Vector2(btn_breathe, btn_breathe)

func _on_play_hover_start():
	_is_hovering = true
	var tween = create_tween()
	tween.tween_property(play_button, "scale", Vector2(1.12, 1.12), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_play_hover_end():
	_is_hovering = false
	var tween = create_tween()
	tween.tween_property(play_button, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_play_pressed():
	UISfx.play_click()
	var tween = create_tween()
	tween.tween_property(play_button, "scale", Vector2(0.92, 0.92), 0.06)
	tween.tween_callback(func():
		SceneTransition.go("res://scenes/ModeSelect.tscn")
	)
