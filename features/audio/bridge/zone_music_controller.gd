extends Node

## Supplies zone data only. MusicPlayer owns loading, selection and playback.
const SERVICE_ID := &"zone_music"
const MUSIC_PLAYER_SERVICE_ID := &"music_player"
const WORLD_ZONES := preload("res://features/world/bridge/world_zone_controller.gd")
const OWNER_META := &"zone_music_source_owner"

var _zones: WORLD_ZONES
var _player: Node
var _zone: Zone
var _last_profile: AmbientMusicProfile
var _published := false


func initialize(context: BootstrapContext) -> void:
	_zones = context.get_optional(WORLD_ZONES.SERVICE_ID) as WORLD_ZONES
	_player = context.get_optional(MUSIC_PLAYER_SERVICE_ID)
	if _player == null or not _player.has_method("set_music_profile"):
		return
	# A retiring world must not clear the replacement world's autoload input.
	_player.set_meta(OWNER_META, get_instance_id())
	if _zones != null:
		_zones.zone_changed.connect(_on_zone_changed)
		_on_zone_changed(_zones.get_current_zone())
	else:
		_on_zone_changed(null)


func _on_zone_changed(zone: Zone) -> void:
	_disconnect_zone()
	_zone = zone
	if _zone != null:
		_zone.ambient_music_changed.connect(_publish_profile)
		_zone.tree_exiting.connect(_on_zone_exiting)
	_publish_profile()


func _publish_profile() -> void:
	if not _owns_player():
		return
	var profile: AmbientMusicProfile = _zone.ambient_music if is_instance_valid(_zone) else null
	if _published and profile == _last_profile:
		return
	_last_profile = profile
	_published = true
	_player.call("set_music_profile", profile)


func _on_zone_exiting() -> void:
	_on_zone_changed(null)


func _disconnect_zone() -> void:
	if not is_instance_valid(_zone):
		return
	if _zone.ambient_music_changed.is_connected(_publish_profile):
		_zone.ambient_music_changed.disconnect(_publish_profile)
	if _zone.tree_exiting.is_connected(_on_zone_exiting):
		_zone.tree_exiting.disconnect(_on_zone_exiting)


func _owns_player() -> bool:
	return is_instance_valid(_player) and not _player.is_queued_for_deletion() and _player.get_meta(OWNER_META, 0) == get_instance_id()


func _exit_tree() -> void:
	_disconnect_zone()
	_zone = null
	if is_instance_valid(_zones) and _zones.zone_changed.is_connected(_on_zone_changed):
		_zones.zone_changed.disconnect(_on_zone_changed)
	if _owns_player():
		_player.remove_meta(OWNER_META)
		_player.call("set_music_profile", null)
	_zones = null
	_player = null
