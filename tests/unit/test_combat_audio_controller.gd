extends GutTest

const CONTROLLER_PATH := "res://features/combat/projection/combat_audio_controller.gd"
const PROFILE := preload("res://features/combat/resources/combat_item_audio_profile.gd")
const SURFACE = PROFILE.Surface
const KIND = PROFILE.WeaponKind

func _controller():
	if not ResourceLoader.exists(CONTROLLER_PATH):
		fail_test("Combat audio projection is not implemented")
		return null
	var controller = load(CONTROLLER_PATH).new()
	add_child_autofree(controller)
	return controller

func test_weapon_whoosh_plays_only_on_confirmed_opponent_dodge() -> void:
	var c = _controller()
	var position := Vector3(2, 1, 3)
	for kind in [KIND.BLADE, KIND.POLEARM, KIND.AXE, KIND.BLUNT, KIND.TOOL, KIND.BOW]:
		var attacker := {"weapon_kind": kind, "strike_surface": SURFACE.METAL}
		assert_true(c.plan_event({"phase": "swing"}, attacker, {}).is_empty(), "Starting an attack cannot predict a dodge")
		var layers: Array = c.plan_event({"phase": "dodge", "outcome": "dodged", "attacker_position": position}, attacker, {})
		assert_eq(layers.size(), 1, "One whoosh when the opponent actually dodges")
		if layers.size() == 1:
			var expected: StringName = &"swing_heavy" if kind in [KIND.AXE, KIND.BLUNT, KIND.TOOL] else &"swing_blade"
			assert_eq(layers[0].cue_id, expected)
			assert_eq(layers[0].position, position)
			assert_eq(layers[0].layer, &"action")
		for outcome in ["hit", "blocked", "missed", "cancelled", "refused", ""]:
			assert_true(c.plan_event({"phase": "dodge", "outcome": outcome}, attacker, {}).is_empty(), "Only an explicit dodge qualifies: " + outcome)
		for outcome in ["hit", "blocked"]:
			layers = c.plan_event({"phase": "contact", "outcome": outcome, "critical": true}, attacker, {"worn_surface": SURFACE.PLATE})
			assert_eq(layers.size(), 1, "Contact, including zero-damage blocks, does not add a whoosh")
			assert_eq(layers[0].layer, &"contact")
	assert_true(c.plan_event({"phase": "dodge", "outcome": "dodged"}, {"race_id": "rustdead", "weapon_kind": KIND.NONE}, {}).is_empty(), "Do not restore an unarmed punch whoosh")

func test_authored_zombie_bite_and_scratch_have_no_startup_sound() -> void:
	var c = _controller()
	var animations = load("res://features/actors/resources/characters/rustdead_combat_animation_set.tres")
	var expected := {"bite": "Zombie_Bite", "claw": "Zombie_Scratch"}
	assert_eq(animations.attacks.size(), expected.size())
	for attack in animations.attacks:
		assert_true(expected.has(attack.attack_id))
		assert_eq(attack.get_animation_names(), [expected[attack.attack_id]])
		for female in [false, true]:
			for kind in [KIND.NONE, KIND.AXE]:
				var attacker := {"race_id": "rustdead", "female": female, "weapon_kind": kind}
				assert_true(c.plan_event({"phase": "swing", "attack_id": attack.attack_id}, attacker, {}).is_empty(), "No generic vocal, punch, bite or whoosh at natural attack start")

func test_zombie_scratch_whoosh_requires_confirmed_opponent_dodge() -> void:
	var c = _controller()
	var position := Vector3(1, 2, 3)
	var event := {"phase": "dodge", "outcome": "dodged", "attack_id": "claw", "attacker_position": position}
	for kind in [KIND.NONE, KIND.AXE]:
		var attacker := {"race_id": "rustdead", "weapon_kind": kind}
		var layers: Array = c.plan_event(event, attacker, {})
		assert_eq(layers.size(), 1)
		if layers.size() == 1:
			assert_eq(layers[0].cue_id, &"swing_blade", "Scratch uses the existing non-punch miss swoosh, not a held axe")
			assert_eq(layers[0].layer, &"action")
			assert_eq(layers[0].position, position)
		for outcome in ["hit", "blocked", "missed", "cancelled", "refused", ""]:
			var other := event.duplicate()
			other.outcome = outcome
			assert_true(c.plan_event(other, attacker, {}).is_empty(), "Only the opponent's dodge permits a whoosh")
		event.attack_id = "bite"
		assert_true(c.plan_event(event, attacker, {}).is_empty(), "A dodged bite makes no flesh-bite sound or weapon swoosh")
		event.attack_id = "claw"

func test_natural_zombie_contact_uses_attack_identity_and_defending_material() -> void:
	var c = _controller()
	var position := Vector3(2, 0, 0)
	var material_cues := {SURFACE.METAL: &"impact_metal", SURFACE.PLATE: &"impact_metal", SURFACE.CHAINMAIL: &"impact_chain", SURFACE.WOOD: &"impact_wood"}
	for attack_id in ["claw", "bite"]:
		for kind in [KIND.NONE, KIND.AXE]:
			var attacker := {"race_id": "rustdead", "weapon_kind": kind, "strike_surface": SURFACE.METAL}
			var event := {"phase": "contact", "outcome": "hit", "attack_id": attack_id, "target_position": position}
			var flesh: Array = c.plan_event(event, attacker, {"body_surface": SURFACE.FLESH})
			assert_eq(flesh.size(), 1)
			if flesh.size() == 1:
				assert_eq(flesh[0].cue_id, &"zombie_bite" if attack_id == "bite" else &"impact_slash")
				assert_eq(flesh[0].layer, &"contact")
				assert_eq(flesh[0].position, position)
			for surface in material_cues:
				for outcome in ["hit", "blocked"]:
					event.outcome = outcome
					event.critical = true
					var target := {"worn_surface": surface, "weapon_guard_surface": surface, "body_surface": SURFACE.FLESH}
					var layers: Array = c.plan_event(event, attacker, target)
					assert_eq(layers.size(), 1, "Armor or guard gets only its contact, even on criticals")
					if layers.size() == 1:
						assert_eq(layers[0].cue_id, material_cues[surface], "Teeth/claws are not a metal weapon parry")
						assert_eq(layers[0].layer, &"contact")
						assert_eq(layers[0].position, position)
						assert_gt(layers[0].gain_db, 0.0)
						assert_lte(layers[0].gain_db, 3.0)
			if attack_id == "bite":
				for surface in [SURFACE.CLOTH, SURFACE.LEATHER]:
					assert_true(c.plan_event(event, attacker, {"worn_surface": surface}).is_empty(), "Do not invent flesh penetration or an unapproved soft-armor bite sound")

func test_armed_zombie_weapon_animation_keeps_existing_voice_and_weapon_contact() -> void:
	var c = _controller()
	var attacker := {"race_id": "rustdead", "female": true, "weapon_kind": KIND.AXE, "strike_surface": SURFACE.METAL}
	var event := {"phase": "swing", "attack_id": "one_hand_light_a"}
	assert_eq(c.plan_event(event, attacker, {})[0].cue_id, &"zombie_female")
	event.phase = "dodge"
	event.outcome = "dodged"
	assert_eq(c.plan_event(event, attacker, {})[0].cue_id, &"swing_heavy")
	event.phase = "contact"
	event.outcome = "hit"
	assert_eq(c.plan_event(event, attacker, {"body_surface": SURFACE.FLESH})[0].cue_id, &"impact_axe")

func test_guard_uses_both_contact_materials_and_critical_keeps_surface() -> void:
	var c = _controller()
	if c == null:
		return
	var attacker := {"weapon_kind": KIND.POLEARM, "strike_surface": SURFACE.METAL}
	var target := {"weapon_guard_surface": SURFACE.WOOD, "shield_guard_surface": SURFACE.METAL, "worn_surface": SURFACE.CHAINMAIL}
	var event := {"phase": "contact", "outcome": "blocked", "has_shield": false, "critical": false}
	assert_eq(c.plan_event(event, attacker, target)[0].cue_id, &"impact_wood")
	target.weapon_guard_surface = SURFACE.METAL
	assert_eq(c.plan_event(event, attacker, target)[0].cue_id, &"clash_metal")
	attacker.strike_surface = SURFACE.WOOD
	assert_eq(c.plan_event(event, attacker, target)[0].cue_id, &"impact_metal", "Wood striking steel is not steel/steel")
	event.has_shield = true
	attacker.strike_surface = SURFACE.METAL
	assert_eq(c.plan_event(event, attacker, target)[0].cue_id, &"impact_metal", "Shield is not a sword parry")
	event.outcome = "hit"
	event.critical = true
	var hit: Dictionary = c.plan_event(event, attacker, target)[0]
	assert_eq(hit.cue_id, &"impact_chain")
	assert_gt(hit.gain_db, 0.0)
	assert_lte(hit.gain_db, 3.0)
	target.worn_surface = SURFACE.NONE
	target.body_surface = SURFACE.BONE
	assert_true(c.plan_event(event, attacker, target).is_empty(), "No punch proxy for bone")
	target.body_surface = SURFACE.FLESH
	event.attack_id = "sword_stab"
	assert_eq(c.plan_event(event, attacker, target)[0].cue_id, &"impact_stab")
	event.outcome = "dodged"
	assert_eq(c.plan_event(event, attacker, target).size(), 0)

func test_unarmed_metal_body_block_is_not_a_weapon_parry() -> void:
	var c = _controller()
	if c == null:
		return
	var attacker := {"weapon_kind": KIND.BLADE, "strike_surface": SURFACE.METAL}
	var target := {"weapon_guard_surface": SURFACE.NONE, "worn_surface": SURFACE.NONE, "body_surface": SURFACE.METAL}
	var event := {"phase": "contact", "outcome": "blocked", "has_shield": false}
	assert_eq(c.plan_event(event, attacker, target)[0].cue_id, &"impact_metal")

func test_generic_unarmed_is_silent_except_for_existing_material_contact() -> void:
	var c = _controller()
	var attacker := {"race_id": "human", "weapon_kind": KIND.NONE, "strike_surface": SURFACE.FLESH}
	var event := {"phase": "swing", "attack_id": "punch"}
	assert_true(c.plan_event(event, attacker, {}).is_empty(), "No generic unarmed swing")
	event.phase = "contact"
	for outcome in ["hit", "blocked"]:
		event.outcome = outcome
		for surface in [SURFACE.FLESH, SURFACE.CLOTH, SURFACE.LEATHER, SURFACE.BONE, SURFACE.STONE]:
			assert_true(c.plan_event(event, attacker, {"body_surface": surface}).is_empty(), "No generic unarmed impact: %s / %s" % [outcome, surface])
		for surface in [SURFACE.METAL, SURFACE.PLATE, SURFACE.CHAINMAIL, SURFACE.WOOD]:
			var expected: StringName = &"impact_chain" if surface == SURFACE.CHAINMAIL else (&"impact_wood" if surface == SURFACE.WOOD else &"impact_metal")
			var layers: Array = c.plan_event(event, attacker, {"worn_surface": surface})
			assert_eq(layers.size(), 1, "Material contact remains without a punch layer")
			assert_eq(layers[0].cue_id, expected)
	event.outcome = "dodged"
	assert_true(c.plan_event(event, attacker, {"worn_surface": SURFACE.PLATE}).is_empty())

func test_no_punch_fallback_for_hard_bodies_or_blunt_weapons() -> void:
	var c = _controller()
	var event := {"phase": "contact", "outcome": "hit", "attack_id": "claw"}
	for race_id in ["human", "rustdead"]:
		for kind in KIND.values():
			var attacker := {"race_id": race_id, "weapon_kind": kind}
			for surface in [SURFACE.BONE, SURFACE.STONE]:
				assert_true(c.plan_event(event, attacker, {"body_surface": surface}).is_empty(), "No hard-body punch fallback: %s / %s / %s" % [race_id, kind, surface])
	for kind in [KIND.BLUNT, KIND.TOOL, KIND.BOW]:
		assert_true(c.plan_event(event, {"weapon_kind": kind}, {"body_surface": SURFACE.FLESH}).is_empty(), "Do not repurpose punch impacts as weapon sounds")

class EquippedActor extends Node3D:
	var items: Dictionary = {}
	var appearance_data := CharacterAppearanceData.new()
	func get_equipped_item(slot: String) -> ItemDefinition:
		return items.get(slot)
	func get_resolved_visual_body_type() -> int:
		return appearance_data.visual_body_type
	func get_resolved_body_archetype() -> Resource:
		return appearance_data.body_archetype

func _item(worn: int, guard := SURFACE.NONE, strike := SURFACE.NONE, kind := KIND.NONE) -> ItemDefinition:
	var item := ItemDefinition.new()
	var profile := PROFILE.new()
	profile.worn_surface = worn
	profile.guard_surface = guard
	profile.strike_surface = strike
	profile.weapon_kind = kind
	item.combat_audio = profile
	return item

func test_actor_snapshot_uses_torso_order_current_equipment_and_body_not_boots() -> void:
	var c = _controller()
	if c == null:
		return
	if not c.has_method("snapshot_actor"):
		fail_test("Live equipment/body snapshot is missing")
		return
	var actor := EquippedActor.new()
	add_child_autofree(actor)
	var race := CharacterRaceDefinition.new()
	race.race_id = "quadbot"
	actor.appearance_data.character_race = race
	actor.items = {"feet": _item(SURFACE.PLATE), "head": _item(SURFACE.PLATE), "undershirt": _item(SURFACE.CLOTH)}
	assert_eq(c.snapshot_actor(actor).worn_surface, SURFACE.CLOTH)
	actor.items.chest = _item(SURFACE.LEATHER)
	assert_eq(c.snapshot_actor(actor).worn_surface, SURFACE.LEATHER)
	actor.items.erase("chest")
	actor.items.erase("undershirt")
	assert_eq(c.snapshot_actor(actor).worn_surface, SURFACE.NONE)
	assert_eq(c.snapshot_actor(actor).body_surface, SURFACE.METAL)
	actor.items.weapon = _item(SURFACE.NONE, SURFACE.WOOD, SURFACE.METAL, KIND.POLEARM)
	var snapshot: Dictionary = c.snapshot_actor(actor)
	assert_eq(snapshot.weapon_guard_surface, SURFACE.WOOD)
	assert_eq(snapshot.strike_surface, SURFACE.METAL)
	actor.items.erase("weapon")
	assert_eq(c.snapshot_actor(actor).weapon_kind, KIND.NONE)
	actor.free()
	assert_eq(c.snapshot_actor(actor), {}, "LOD-freed actors are checked before casting or access")

class SyntheticCue extends "res://features/audio/resources/game_sound_cue.gd":
	var sample: AudioStreamWAV
	func _init() -> void:
		paths = PackedStringArray(["synthetic_a", "synthetic_b"])
		sample = AudioStreamWAV.new()
		sample.mix_rate = 8000
		sample.format = AudioStreamWAV.FORMAT_8_BITS
		var pcm := PackedByteArray()
		pcm.resize(8000)
		sample.data = pcm
	func get_stream(_path: String) -> AudioStream:
		return sample

class EventSource extends Node:
	signal combat_audio_event(event: Dictionary)
	var actors: Dictionary = {}
	func get_actor_by_stable_id(id: String):
		return actors.get(id)

func _playback_controller():
	var c = _controller()
	if c == null:
		return null
	if not c.has_method("play_cue"):
		fail_test("Real bounded 3D playback is missing")
		return null
	c.settings = c.settings.duplicate()
	c.settings.max_voices = 2
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.current = true
	var cue := SyntheticCue.new()
	cue.cue_id = &"test"
	c.bank = c.bank.get_script().new()
	c.bank.cues.clear()
	c.bank.cues.append(cue)
	return c

func test_playback_uses_real_3d_players_nonrepeat_variants_distance_and_bound() -> void:
	var c = _playback_controller()
	if c == null:
		return
	var first: AudioStreamPlayer3D = c.play_cue(&"test", Vector3(1, 0, 0))
	assert_not_null(first)
	assert_true(first.playing)
	assert_true(first.stream is AudioStreamWAV)
	assert_eq(first.global_position, Vector3(1, 0, 0))
	var path: String = first.get_meta("clip_path")
	var second: AudioStreamPlayer3D = c.play_cue(&"test", Vector3(2, 0, 0))
	assert_ne(second.get_meta("clip_path"), path)
	assert_ne(first, second)
	var third: AudioStreamPlayer3D = c.play_cue(&"test", Vector3(3, 0, 0))
	assert_eq(third, first, "Full pool reuses oldest voice rather than allocating")
	assert_eq(c.get_child_count(), 2)
	assert_null(c.play_cue(&"test", Vector3(1000, 0, 0)))
	assert_eq(c.get_child_count(), 2)
	c.settings.enabled = false
	assert_null(c.play_cue(&"test", Vector3.ZERO))
	c.settings.enabled = true
	c.settings.max_distance_m = 2.0
	assert_null(c.play_cue(&"test", Vector3(3, 0, 0)), "Live settings apply at next event")
	c.settings.volume_db = -10.0
	var tuned: AudioStreamPlayer3D = c.play_cue(&"test", Vector3.ZERO, 1.5)
	assert_almost_eq(tuned.volume_db, -14.5, 0.001)
	assert_eq(tuned.max_distance, 2.0)

func test_real_playback_pause_completion_and_teardown_release_voices() -> void:
	var c = _playback_controller()
	if c == null:
		return
	var short_pcm := PackedByteArray()
	short_pcm.resize(240)
	c.bank.cues[0].sample.data = short_pcm
	var player: AudioStreamPlayer3D = c.play_cue(&"test", Vector3.ZERO)
	# Actual short stream completion, not a synthetic finished signal.
	await wait_until(func(): return player.stream == null, 1.0)
	assert_false(player.playing)
	assert_null(player.stream)
	player = c.play_cue(&"test", Vector3.ZERO)
	get_tree().paused = true
	assert_false(player.playing, "Pause discards stale combat one-shots")
	assert_null(c.play_cue(&"test", Vector3.ZERO))
	get_tree().paused = false
	assert_not_null(c.play_cue(&"test", Vector3.ZERO))
	c.teardown()
	assert_eq(c.get_child_count(), 0)

func test_injected_event_lifecycle_dedup_lod_replacement_and_rebind() -> void:
	var c = _playback_controller()
	if c == null:
		return
	var source := EventSource.new()
	add_child_autofree(source)
	var actor := EquippedActor.new()
	add_child_autofree(actor)
	actor.items.weapon = _item(SURFACE.NONE, SURFACE.METAL, SURFACE.METAL, KIND.BLADE)
	source.actors = {"a": actor, "b": actor}
	var context := BootstrapContext.new(self)
	context.register(&"gecs_world", source)
	c.bank.cues[0].cue_id = &"swing_blade"
	c.initialize(context)
	c.initialize(context)
	var event := {"phase": "dodge", "outcome": "dodged", "attacker_id": "a", "target_id": "b", "source_instance_id": actor.get_instance_id(), "sequence": 1, "attacker_position": Vector3(1, 0, 0)}
	source.combat_audio_event.emit(event)
	source.combat_audio_event.emit(event)
	assert_eq(c.get_child_count(), 1, "Reinitialize/duplicate delivery cannot duplicate playback")
	var player: AudioStreamPlayer3D = c.get_child(0)
	actor.free()
	assert_eq(player.global_position, Vector3(1, 0, 0), "Voice owns captured position, never a followed actor")
	event.sequence = 2
	source.combat_audio_event.emit(event)
	assert_eq(c.get_child_count(), 1)
	var replacement := EquippedActor.new()
	add_child_autofree(replacement)
	replacement.items.weapon = _item(SURFACE.NONE, SURFACE.METAL, SURFACE.METAL, KIND.BLADE)
	source.actors.a = replacement
	event.source_instance_id = replacement.get_instance_id()
	event.sequence = 1
	source.combat_audio_event.emit(event)
	assert_eq(c.get_child_count(), 2, "Same durable actor can restart its sequence after LOD")
	var other := EventSource.new()
	add_child_autofree(other)
	other.actors.a = replacement
	var second_context := BootstrapContext.new(self)
	second_context.register(&"gecs_world", other)
	c.initialize(second_context)
	assert_eq(c.get_child_count(), 0)
	source.combat_audio_event.emit(event)
	assert_eq(c.get_child_count(), 0, "Old source disconnected")
	other.combat_audio_event.emit(event)
	assert_eq(c.get_child_count(), 1)
	c.teardown()
	other.combat_audio_event.emit(event)
	assert_eq(c.get_child_count(), 0)

func test_authored_bank_maps_every_planned_family_without_eager_wav_dependencies() -> void:
	var path := "res://features/combat/resources/audio/default_combat_sound_bank.tres"
	if not ResourceLoader.exists(path):
		fail_test("Authored cue bank is missing")
		return
	var bank = load(path)
	for cue_id in [&"swing_blade", &"swing_heavy", &"clash_metal", &"impact_metal", &"impact_chain", &"impact_wood", &"impact_slash", &"impact_stab", &"impact_axe", &"zombie_male", &"zombie_female", &"zombie_bite"]:
		var cue = bank.get_cue(cue_id)
		assert_not_null(cue, str(cue_id))
		if cue != null:
			assert_gt(cue.paths.size(), 1, str(cue_id) + " has nonrepeat variants")

func test_authored_bank_excludes_all_punch_clips_and_retired_fallbacks() -> void:
	var bank = load("res://features/combat/resources/audio/default_combat_sound_bank.tres")
	for cue_id in [&"swing_unarmed", &"impact_blunt", &"impact_bone", &"impact_stone"]:
		assert_null(bank.get_cue(cue_id), str(cue_id) + " is outside the approved sound scope")
	for cue in bank.cues:
		for path in cue.paths:
			assert_false(path.to_lower().contains("punch"), "No punch recordings, including the rejected cartoon impact: " + path)

func test_combat_module_instantiates_the_controller_with_injected_source() -> void:
	var path := "res://features/combat/combat_module.gd"
	if not ResourceLoader.exists(path):
		fail_test("Combat projection module is missing")
		return
	var module = load(path)
	var entry: Dictionary = module.PROJECTION[0]
	var source := EventSource.new()
	add_child_autofree(source)
	var context := BootstrapContext.new(self)
	context.register(&"gecs_world", source)
	var controller: Node = entry.script.new()
	add_child_autofree(controller)
	controller.initialize(context)
	assert_eq(entry.service, &"combat_audio")
	assert_eq(source.get_signal_connection_list("combat_audio_event").size(), 1)
	controller.teardown()
	assert_eq(source.get_signal_connection_list("combat_audio_event").size(), 0)

func test_zombie_native_playback_starts_only_the_resolved_natural_attack_sound() -> void:
	var c = _playback_controller()
	if c == null:
		return
	c.settings.max_voices = 4
	c.bank.cues.clear()
	# Include forbidden startup/punch cues so accidental requests really start a player.
	for id in [&"zombie_female", &"zombie_male", &"swing_unarmed", &"impact_blunt", &"impact_metal", &"impact_slash", &"zombie_bite", &"swing_blade"]:
		var cue := SyntheticCue.new()
		cue.cue_id = id
		c.bank.cues.append(cue)
	var source := EventSource.new()
	add_child_autofree(source)
	var attacker := EquippedActor.new()
	var defender := EquippedActor.new()
	add_child_autofree(attacker)
	add_child_autofree(defender)
	attacker.appearance_data.character_race = load("res://features/actors/resources/character_races/rustdead.tres")
	attacker.appearance_data.visual_body_type = CharacterAppearanceData.VISUAL_BODY_TYPE_FEMALE
	source.actors = {"a": attacker, "b": defender}
	var context := BootstrapContext.new(self)
	context.register(&"gecs_world", source)
	for case in [
		["claw", "hit", SURFACE.NONE, &"impact_slash"],
		["claw", "hit", SURFACE.PLATE, &"impact_metal"],
		["claw", "blocked", SURFACE.PLATE, &"impact_metal"],
		["claw", "dodged", SURFACE.PLATE, &"swing_blade"],
		["bite", "hit", SURFACE.NONE, &"zombie_bite"],
		["bite", "hit", SURFACE.PLATE, &"impact_metal"],
		["bite", "blocked", SURFACE.PLATE, &"impact_metal"],
		["bite", "dodged", SURFACE.NONE, &""],
	]:
		c.initialize(context)
		defender.items = {} if case[2] == SURFACE.NONE else {"chest": _item(case[2])}
		var event := {"phase": "swing", "attacker_id": "a", "target_id": "b", "source_instance_id": attacker.get_instance_id(), "sequence": 1, "attack_id": case[0], "attacker_position": Vector3(1, 0, 0), "target_position": Vector3(2, 0, 0)}
		source.combat_audio_event.emit(event)
		assert_eq(c.get_child_count(), 0, "Natural attack startup is silent: " + case[0])
		event.phase = "dodge" if case[1] == "dodged" else "contact"
		event.outcome = case[1]
		source.combat_audio_event.emit(event)
		source.combat_audio_event.emit(event)
		var expected_count := 0 if case[3] == &"" else 1
		assert_eq(c.get_child_count(), expected_count, "Only the resolved cue, once: %s" % [case])
		if expected_count == 1 and c.get_child_count() == 1:
			var player: AudioStreamPlayer3D = c.get_child(0)
			assert_true(player.playing)
			assert_same(player.stream, c.bank.get_cue(case[3]).sample)
			assert_eq(player.global_position, event.attacker_position if case[1] == "dodged" else event.target_position)

func test_authored_bite_cue_contains_only_infected_bite_recordings() -> void:
	var bank = load("res://features/combat/resources/audio/default_combat_sound_bank.tres")
	var cue = bank.get_cue(&"zombie_bite")
	var expected := PackedStringArray([
		"CREAHmn_Zombie infected bite 2_GfxSounds_FantasyGameBundle.wav",
		"CREAHmn_Zombie infected bite 3_GfxSounds_FantasyGameBundle.wav",
		"CREAHmn_Zombie infected bite 5_GfxSounds_FantasyGameBundle.wav",
		"CREAHmn_Zombie infected bite 6_GfxSounds_FantasyGameBundle.wav",
	])
	var names := PackedStringArray()
	for path in cue.paths:
		names.append(path.get_file())
	assert_eq(names, expected)

func test_generic_unarmed_native_playback_starts_only_armor_contact() -> void:
	var c = _playback_controller()
	c.bank.cues.clear()
	for id in [&"impact_metal", &"swing_unarmed", &"impact_blunt"]:
		var cue := SyntheticCue.new()
		cue.cue_id = id
		c.bank.cues.append(cue)
	var source := EventSource.new()
	add_child_autofree(source)
	var attacker := EquippedActor.new()
	var defender := EquippedActor.new()
	add_child_autofree(attacker)
	add_child_autofree(defender)
	source.actors = {"a": attacker, "b": defender}
	var context := BootstrapContext.new(self)
	context.register(&"gecs_world", source)
	c.initialize(context)
	var event := {"phase": "swing", "attacker_id": "a", "target_id": "b", "source_instance_id": attacker.get_instance_id(), "sequence": 1, "attack_id": "punch", "attacker_position": Vector3.ZERO, "target_position": Vector3(1, 0, 0)}
	source.combat_audio_event.emit(event)
	assert_eq(c.get_child_count(), 0, "No native punch swing player")
	event.phase = "contact"
	event.outcome = "hit"
	source.combat_audio_event.emit(event)
	assert_eq(c.get_child_count(), 0, "No native flesh-punch player")
	defender.items.chest = _item(SURFACE.PLATE)
	event.sequence = 2
	source.combat_audio_event.emit(event)
	assert_eq(c.get_child_count(), 1, "Only armor contact starts a player")
	assert_true(c.get_child(0).playing)
	assert_same(c.get_child(0).stream, c.bank.cues[0].sample)
