extends Node

## GameplaySfx — centralized gameplay sound effects (Land Mine, Sacrifice,
## piece movement). Follows the same one-player-per-sound pattern as UISfx:
## each sound owns a single dedicated AudioStreamPlayer that is stopped and
## restarted on retrigger, so rapid repeats (e.g. quick Sacrifice selections
## or successive piece moves) never stack into overlapping/clipping noise.
## Usage: GameplaySfx.play_land_mine_place(), etc.

const LAND_MINE_PLACE_STREAM     := preload("res://audio/land_mine_place.wav")
const LAND_MINE_EXPLOSION_STREAM := preload("res://audio/land_mine_explosion.wav")
const SACRIFICE_SELECT_STREAM    := preload("res://audio/sacrifice_select.wav")
const SACRIFICE_RESOLVE_STREAM   := preload("res://audio/sacrifice_resolve.wav")
const PIECE_MOVE_STREAM          := preload("res://audio/piece_move.wav")

# Volume levels tuned to sit alongside the existing Revive/UI sfx
# (-9 dB for a subtle UI tap, -8/-12 dB for Revive's charge/resurrect beats).
const VOL_LAND_MINE_PLACE     := -16.0  # subtle rune-engraving — should not draw attention
const VOL_LAND_MINE_EXPLOSION := -4.0   # powerful, but still bus-safe (no clipping)
const VOL_SACRIFICE_SELECT    := -11.0  # short confirm tick, similar level to UI click
const VOL_SACRIFICE_RESOLVE   := -5.0   # dramatic, but balanced against the explosion
const VOL_PIECE_MOVE          := -13.0  # short, responsive, never overpowering

var _land_mine_place_player: AudioStreamPlayer
var _land_mine_explosion_player: AudioStreamPlayer
var _sacrifice_select_player: AudioStreamPlayer
var _sacrifice_resolve_player: AudioStreamPlayer
var _piece_move_player: AudioStreamPlayer

func _ready() -> void:
	_land_mine_place_player     = _make_player(LAND_MINE_PLACE_STREAM, VOL_LAND_MINE_PLACE)
	_land_mine_explosion_player = _make_player(LAND_MINE_EXPLOSION_STREAM, VOL_LAND_MINE_EXPLOSION)
	_sacrifice_select_player    = _make_player(SACRIFICE_SELECT_STREAM, VOL_SACRIFICE_SELECT)
	_sacrifice_resolve_player   = _make_player(SACRIFICE_RESOLVE_STREAM, VOL_SACRIFICE_RESOLVE)
	_piece_move_player          = _make_player(PIECE_MOVE_STREAM, VOL_PIECE_MOVE)

func _make_player(stream: AudioStream, volume_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream    = stream
	p.volume_db = volume_db
	# Keep sfx playable even if gameplay pause logic is ever added later.
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	return p

# Restarts cleanly if triggered again quickly — prevents duplicate/overlapping
# playback of the same sound stacking on top of itself.
func _play(p: AudioStreamPlayer) -> void:
	p.stop()
	p.play()

func play_land_mine_place() -> void:
	_play(_land_mine_place_player)

func play_land_mine_explosion() -> void:
	_play(_land_mine_explosion_player)

func play_sacrifice_select() -> void:
	_play(_sacrifice_select_player)

func play_sacrifice_resolve() -> void:
	_play(_sacrifice_resolve_player)

func play_piece_move() -> void:
	_play(_piece_move_player)
