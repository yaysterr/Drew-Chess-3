extends Node

## UISfx — plays subtle UI sound effects (button clicks that change scenes).
## Usage: UISfx.play_click()

const CLICK_STREAM := preload("res://audio/ui_click.wav")

# Moderate, unobtrusive level — a soft wooden tap, not an arcade blip.
const CLICK_VOLUME_DB := -9.0

var _player: AudioStreamPlayer

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.stream = CLICK_STREAM
	_player.volume_db = CLICK_VOLUME_DB
	# Sound effects should not be paused by gameplay pause logic, if any is added later.
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player)

func play_click() -> void:
	# Restart cleanly if pressed again quickly, avoiding overlapping/harsh stacking.
	_player.stop()
	_player.play()
