This folder is where MusicManager (scripts/MusicManager.gd) looks for background
music. It currently uses these two files:

  main_menu_theme.ogg   -> played on MainMenu and ModeSelect screens
  gameplay_theme.ogg    -> played during the game scene (PvP & PvB)

Both are OGG Vorbis so looping is sample-accurate and gapless (converted from
the originally supplied MP3s). Godot's importer also lets you set a custom
loop point in the Import dock if a track has an intro that shouldn't repeat.

Adding a new scene's music later: add a Track enum entry + a TRACK_PATHS
entry in MusicManager.gd, then call
MusicManager.play_track(MusicManager.Track.YOUR_NEW_TRACK) from that
scene's _ready(). Nothing else needs to change.
