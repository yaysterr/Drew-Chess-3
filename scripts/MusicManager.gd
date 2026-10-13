extends Node

## MusicManager — centralized, modular background music system.
##
## Usage from any scene:
##   MusicManager.play_track(MusicManager.Track.MAIN_MENU)
##   MusicManager.play_track(MusicManager.Track.GAMEPLAY)
##
## Behavior:
##   - Each track loops seamlessly forever once started.
##   - Switching to a different track crossfades: the old track fades out
##     while the new one fades in over FADE_DURATION seconds, so there is
##     never an abrupt stop/restart or silent gap.
##   - Calling play_track() with the track that is already playing (or
##     mid-fade-in) does nothing, so the same music never doubles up.
##   - Two internal AudioStreamPlayers are swapped back and forth so the
##     outgoing and incoming track can overlap during the crossfade.
##
## Future-proofing:
##   Adding music for a new scene is a two-line change: add an entry to the
##   Track enum below, and add its file path to TRACK_PATHS. No other code
##   (including this script's playback/fade logic) needs to change. If a
##   track's audio file hasn't been added to the project yet, playback is
##   skipped gracefully with a warning instead of crashing.

enum Track { NONE, MAIN_MENU, GAMEPLAY }

# Map each track id to its audio file. Add new tracks here.
const TRACK_PATHS := {
	Track.MAIN_MENU: "res://audio/music/main_menu_theme.ogg",
	Track.GAMEPLAY:  "res://audio/music/gameplay_theme.ogg",
}

const FADE_DURATION := 0.75   # seconds — within the requested 0.5-1.0s crossfade window

# Music sits under the sound effects, which in this project range roughly
# -4 dB (impactful hits like the Land Mine explosion) to -16 dB (subtle
# ticks). -7 dB is ~44% of full linear amplitude (20*log10(0.44) ≈ -7.1dB),
# putting music clearly under the SFX layer per the 40-50% requirement
# while still being audible as an ambient bed.
const MUSIC_VOLUME_DB := -7.0
const SILENT_DB        := -80.0

var _player_a: AudioStreamPlayer
var _player_b: AudioStreamPlayer
var _active_player: AudioStreamPlayer
var _current_track: int = Track.NONE
var _fade_tween: Tween


func _ready() -> void:
	# Keep playing/fading through any future pause-menu logic.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player_a = _make_player()
	_player_b = _make_player()
	_active_player = _player_a


func _make_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.volume_db    = SILENT_DB
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	return p


## Crossfade into the given track. Safe to call every time a scene loads —
## if that track is already the active/incoming one, this is a no-op.
func play_track(track: int) -> void:
	if track == _current_track:
		return

	if track == Track.NONE or not TRACK_PATHS.has(track):
		_fade_out_current()
		_current_track = Track.NONE
		return

	var path: String = TRACK_PATHS[track]
	if not ResourceLoader.exists(path):
		push_warning("MusicManager: no music file at '%s' yet — skipping playback for track %d." % [path, track])
		_current_track = track
		return

	var stream: AudioStream = load(path)
	_enable_seamless_loop(stream)

	var incoming := _player_b if _active_player == _player_a else _player_a
	incoming.stream    = stream
	incoming.volume_db = SILENT_DB
	incoming.play()

	var outgoing := _active_player

	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()

	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	_fade_tween.tween_property(incoming, "volume_db", MUSIC_VOLUME_DB, FADE_DURATION)
	_fade_tween.tween_property(outgoing, "volume_db", SILENT_DB, FADE_DURATION)
	_fade_tween.chain().tween_callback(outgoing.stop)

	_active_player  = incoming
	_current_track  = track


## Stops whatever is playing with a fade-out (used when no scene music applies).
func stop_music() -> void:
	_fade_out_current()
	_current_track = Track.NONE


func _fade_out_current() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	if not _active_player.playing:
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(_active_player, "volume_db", SILENT_DB, FADE_DURATION)
	_fade_tween.tween_callback(_active_player.stop)


func _enable_seamless_loop(stream: AudioStream) -> void:
	# Ogg Vorbis / MP3 both loop natively via this flag with no gap.
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		stream.loop = true
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD


func _notification(what: int) -> void:
	# Make sure music does not linger past the app closing.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _player_a: _player_a.stop()
		if _player_b: _player_b.stop()
