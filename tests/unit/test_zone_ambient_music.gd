extends GutTest

const ZONE_SCRIPT := preload("res://features/world/projection/zone_root.gd")
const PROFILE_PATH := "res://features/audio/resources/ambient_music_profile.gd"
const SAVED_ZONE := "user://zone_ambient_music_fixture.tscn"


func after_each() -> void:
	if FileAccess.file_exists(SAVED_ZONE):
		DirAccess.remove_absolute(SAVED_ZONE)


func test_zone_ambient_music_survives_scene_save_without_loading_recordings() -> void:
	assert_true(FileAccess.file_exists(PROFILE_PATH), "Zones need an ambient-music data profile")
	if not FileAccess.file_exists(PROFILE_PATH):
		return
	var profile = load(PROFILE_PATH).new()
	var tracks := PackedStringArray(["res://uninstalled_music/first.ogg", "res://uninstalled_music/second.wav"])
	profile.tracks = tracks
	var zone = autofree(ZONE_SCRIPT.new())
	zone.name = "MusicZone"
	zone.zone_id = "music_fixture"
	var fields: Array = zone.get_property_list().map(func(property): return str(property.name))
	assert_has(fields, "ambient_music", "The zone must expose its ambient music in the Inspector")
	if not fields.has("ambient_music"):
		return
	zone.ambient_music = profile
	var packed := PackedScene.new()
	assert_eq(packed.pack(zone), OK)
	assert_eq(ResourceSaver.save(packed, SAVED_ZONE), OK)
	var saved := ResourceLoader.load(SAVED_ZONE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	assert_not_null(saved)
	if saved == null:
		return
	var restored = autofree(saved.instantiate())
	assert_eq(restored.get_zone_id(), "music_fixture")
	assert_not_null(restored.ambient_music)
	if restored.ambient_music == null:
		return
	assert_eq(restored.ambient_music.tracks, tracks)
	assert_eq(restored.get_child_count(), 0, "Authoring music data must not create playback nodes")


func test_ambient_music_is_optional_and_editable_in_the_inspector() -> void:
	var zone = autofree(ZONE_SCRIPT.new())
	assert_null(zone.ambient_music)
	var profile = load(PROFILE_PATH).new()
	assert_eq(profile.tracks, PackedStringArray())
	var zone_properties: Array = zone.get_property_list().filter(func(property): return property.name == "ambient_music")
	assert_eq(zone_properties.size(), 1)
	if zone_properties.size() != 1:
		return
	assert_true((int(zone_properties[0].usage) & PROPERTY_USAGE_EDITOR) != 0)
	assert_true((int(zone_properties[0].usage) & PROPERTY_USAGE_STORAGE) != 0)
	var track_properties: Array = profile.get_property_list().filter(func(property): return property.name == "tracks")
	assert_eq(track_properties.size(), 1)
	if track_properties.size() != 1:
		return
	assert_true((int(track_properties[0].usage) & PROPERTY_USAGE_EDITOR) != 0)
	assert_true((int(track_properties[0].usage) & PROPERTY_USAGE_STORAGE) != 0)


func test_separate_zone_profiles_do_not_share_their_track_list() -> void:
	var first = load(PROFILE_PATH).new()
	var second = load(PROFILE_PATH).new()
	first.tracks.append("res://uninstalled_music/first.ogg")
	assert_eq(second.tracks, PackedStringArray())
	var first_zone = autofree(ZONE_SCRIPT.new())
	var second_zone = autofree(ZONE_SCRIPT.new())
	first_zone.ambient_music = first
	second_zone.ambient_music = second
	assert_ne(first_zone.ambient_music.tracks, second_zone.ambient_music.tracks)
	second_zone.ambient_music = first
	assert_same(first_zone.ambient_music, second_zone.ambient_music, "Zones may deliberately reuse a profile")
