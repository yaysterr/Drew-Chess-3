extends Node2D

@onready var pvp_card = $CardsContainer/PvPCard
@onready var pvb_card = $CardsContainer/PvBCard
@onready var bot_knight = $CardsContainer/PvBCard/IconRow/BotKnight

var time_elapsed: float = 0.0
var pvp_hovered: bool = false
var pvb_hovered: bool = false

func _ready():
	MusicManager.play_track(MusicManager.Track.MAIN_MENU)

	pvp_card.pivot_offset = pvp_card.size * 0.5
	pvb_card.pivot_offset = pvb_card.size * 0.5
	pvp_card.mouse_entered.connect(func(): _on_card_hover(pvp_card, true, "pvp"))
	pvp_card.mouse_exited.connect(func(): _on_card_hover(pvp_card, false, "pvp"))
	pvb_card.mouse_entered.connect(func(): _on_card_hover(pvb_card, true, "pvb"))
	pvb_card.mouse_exited.connect(func(): _on_card_hover(pvb_card, false, "pvb"))

func _process(delta):
	time_elapsed += delta
	# Animate bot knight icon - gentle pulse
	var pulse = 0.75 + 0.25 * sin(time_elapsed * 2.2)
	bot_knight.modulate = Color(1.0, 0.710 * pulse + 0.29, 0.439 * pulse + 0.56, 1.0)

func _on_card_hover(card: Button, entering: bool, which: String):
	if which == "pvp":
		pvp_hovered = entering
	else:
		pvb_hovered = entering
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	var target_scale = Vector2(1.04, 1.04) if entering else Vector2(1.0, 1.0)
	tween.tween_property(card, "scale", target_scale, 0.15)

func _on_pvp_pressed():
	UISfx.play_click()
	Globals.game_mode = Globals.GAME_MODE.PVP
	var tween = create_tween()
	tween.tween_property(pvp_card, "scale", Vector2(0.95, 0.95), 0.07)
	tween.tween_callback(func():
		SceneTransition.go("res://scenes/game.tscn")
	)

func _on_pvb_pressed():
	UISfx.play_click()
	Globals.game_mode = Globals.GAME_MODE.PVB
	var tween = create_tween()
	tween.tween_property(pvb_card, "scale", Vector2(0.95, 0.95), 0.07)
	tween.tween_callback(func():
		SceneTransition.go("res://scenes/game.tscn")
	)

func _on_back_pressed():
	UISfx.play_click()
	SceneTransition.go("res://scenes/MainMenu.tscn")
