extends RefCounted

## World-scoped audio input wiring. The user's MusicPlayer remains an autoload.
const ZONE_MUSIC := preload("res://features/audio/bridge/zone_music_controller.gd")

const CORE := []
const PROJECTION := []
const SIM := []
const BRIDGE := [
	{"name": "ZoneMusicController", "script": ZONE_MUSIC, "service": ZONE_MUSIC.SERVICE_ID},
]
