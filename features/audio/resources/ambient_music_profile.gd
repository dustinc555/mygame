@tool
extends Resource
class_name AmbientMusicProfile

## Background music selections, not environmental sound effects.
## Keep licensed recordings optional; the music player owns loading and playback.
@export_file("*.wav", "*.ogg", "*.mp3") var tracks: PackedStringArray = PackedStringArray()
