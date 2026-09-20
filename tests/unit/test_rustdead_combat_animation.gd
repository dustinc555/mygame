extends GutTest

const RUSTDEAD = preload("res://features/actors/projection/rustdead/rustdead_humanoid_character.gd")
const HUMAN = preload("res://features/actors/projection/humanoid/humanoid_character.gd")


# Exercise the real actor chooser and projection with tiny clips, without meshes,
# world startup, frame waits, or replacing the behavior under test.
func _actor(rustdead: bool, clips: Dictionary) -> HumanoidCharacter:
	var actor: HumanoidCharacter = RUSTDEAD.new() if rustdead else HUMAN.new()
	autofree(actor)
	var body := actor._create_body_projection() as HumanoidBodyProjection
	actor.add_child(body)
	actor._body = body
	var player := AnimationPlayer.new()
	body.add_child(player)
	var library := AnimationLibrary.new()
	for clip_name in clips:
		var clip := Animation.new()
		clip.length = float(clips[clip_name])
		library.add_animation(clip_name, clip)
	player.add_animation_library("", library)
	body._character_animation_player = player
	body._character_animation_players = [player]
	actor._combat_rng.seed = 8123
	return actor


func test_rustdead_selects_bite_and_claw_instead_of_available_human_punches() -> void:
	var actor := _actor(true, {"Zombie_Bite": 1.2, "Zombie_Scratch": 0.8, "Punch_Jab": 0.3, "Punch_Cross": 0.4})
	var chosen: Array[String] = []
	for index in range(32):
		var spec := actor.get_system_combat_attack_spec()
		var names: PackedStringArray = spec.get("animation_names", PackedStringArray())
		for clip_name in names:
			if not chosen.has(clip_name):
				chosen.append(clip_name)
	chosen.sort()
	assert_eq(chosen, ["Zombie_Bite", "Zombie_Scratch"], "The public combat spec must choose zombie attacks, not merely load them")


func test_missing_zombie_clips_does_not_fall_back_to_human_punches() -> void:
	var actor := _actor(true, {"Punch_Jab": 0.3, "Punch_Cross": 0.4})
	assert_true(actor.get_system_combat_attack_spec().is_empty())


func test_bite_timing_uses_bite_clip_not_human_punch_length() -> void:
	var actor := _actor(true, {"Zombie_Bite": 1.2, "Punch_Jab": 0.3, "Punch_Cross": 0.4})
	var spec := actor.get_system_combat_attack_spec()
	assert_eq(spec.get("animation_names"), PackedStringArray(["Zombie_Bite"]))
	assert_almost_eq(float(spec.get("total_seconds", 0.0)), 1.2, 0.001)
	assert_almost_eq(float(spec.get("first_clip_seconds", 0.0)), 1.2, 0.001)
	assert_almost_eq(float(spec.get("impact_seconds", 0.0)), 0.54, 0.001)


func test_claw_remains_available_when_bite_clip_is_missing() -> void:
	var actor := _actor(true, {"Zombie_Scratch": 0.8, "Punch_Jab": 0.3, "Punch_Cross": 0.4})
	var spec := actor.get_system_combat_attack_spec()
	assert_eq(spec.get("animation_names"), PackedStringArray(["Zombie_Scratch"]))
	assert_almost_eq(float(spec.get("total_seconds", 0.0)), 0.8, 0.001)
	assert_almost_eq(float(spec.get("impact_seconds", 0.0)), 0.36, 0.001)


func test_human_unarmed_attacks_remain_punches() -> void:
	var actor := _actor(false, {"Zombie_Bite": 1.2, "Zombie_Scratch": 0.8, "Punch_Jab": 0.3, "Punch_Cross": 0.4})
	var chosen: Array[String] = []
	for index in range(32):
		var spec := actor.get_system_combat_attack_spec()
		for clip_name in spec.animation_names:
			if not chosen.has(clip_name):
				chosen.append(clip_name)
	chosen.sort()
	assert_eq(chosen, ["Punch_Cross", "Punch_Jab"])
