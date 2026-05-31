extends SceneTree

const RUSTDEAD_DEMO_SCENE := preload("res://scenes/test_levels/rustdead_5v10_demo.tscn")
const RUSTDEAD_RACE := preload("res://resources/character_races/rustdead.tres")
const SKIN_TEXTURE_BUILDER := preload("res://scripts/character_appearance/skin_texture_builder.gd")
const BANDAGE := preload("res://resources/items/bandage.tres")
const CINDER_FLASK := preload("res://resources/items/cinder_flask.tres")

const DEMO_SCENE_PATH := "res://scenes/test_levels/rustdead_5v10_demo.tscn"
const PARTY_SKILL_LEVEL := 40
const RUSTDEAD_SKILL_LEVEL := 20
const REQUIRED_RUSTDEAD_ANIMATIONS := ["Zombie_Idle", "Zombie_Walk_Fwd", "Zombie_Run_Fwd", "Zombie_Bite", "Zombie_Scratch", "Zombie_Spawn"]

var _failures: Array[String] = []
var _scene: Node


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _finalize() -> void:
	Engine.time_scale = 1.0
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.paused = false


func _run() -> void:
	_validate_default_scene()
	_validate_generated_textures()
	await _load_scene()
	var party_members := _get_party_members()
	var rustdead_members := _get_rustdead_members()
	_validate_party_members(party_members)
	_validate_rustdead_members(rustdead_members)
	_validate_rustdead_animation_library(rustdead_members)
	await _validate_rustdead_cinder_burn_rules(party_members, rustdead_members)
	if _failures.is_empty():
		print("RUSTDEAD_5V10_DEMO_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("RUSTDEAD_5V10_DEMO_FAILED count=%d" % _failures.size())
	quit(1)


func _load_scene() -> void:
	_scene = RUSTDEAD_DEMO_SCENE.instantiate()
	root.add_child(_scene)
	await _wait_frames(16)


func _validate_default_scene() -> void:
	var main_scene := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if main_scene != DEMO_SCENE_PATH:
		_fail("Project default scene should be %s, got %s" % [DEMO_SCENE_PATH, main_scene])


func _validate_generated_textures() -> void:
	for body_type in [SKIN_TEXTURE_BUILDER.VISUAL_BODY_TYPE_MALE, SKIN_TEXTURE_BUILDER.VISUAL_BODY_TYPE_FEMALE]:
		for tone_index in range(SKIN_TEXTURE_BUILDER.get_skin_tone_count(SKIN_TEXTURE_BUILDER.RUSTDEAD_RACE_ID)):
			var path := SKIN_TEXTURE_BUILDER.get_generated_skin_texture_path(SKIN_TEXTURE_BUILDER.RUSTDEAD_RACE_ID, body_type, tone_index)
			if load(path) == null:
				_fail("Missing generated Rustdead skin texture: %s" % path)


func _get_party_members() -> Array[HumanoidCharacter]:
	var result: Array[HumanoidCharacter] = []
	var party_root := _scene.get_node_or_null("PartyMembers") if _scene != null else null
	if party_root == null:
		_fail("PartyMembers node was not found")
		return result
	for child in party_root.get_children():
		if child is HumanoidCharacter:
			result.append(child as HumanoidCharacter)
	return result


func _get_rustdead_members() -> Array[HumanoidCharacter]:
	var result: Array[HumanoidCharacter] = []
	if _scene == null:
		return result
	for child in _scene.get_children():
		if child is HumanoidCharacter and str(child.get("faction_name")) == "Rustdead":
			result.append(child as HumanoidCharacter)
	return result


func _validate_party_members(party_members: Array[HumanoidCharacter]) -> void:
	if party_members.size() != 5:
		_fail("Expected 5 party members, got %d" % party_members.size())
	for member in party_members:
		_validate_skill_levels(member, PARTY_SKILL_LEVEL)
		_expect_equipped(member, "weapon")
		_expect_equipped(member, "chest")
		_expect_equipped(member, "legs")
		_expect_equipped(member, "feet")
		_expect_inventory_count(member, BANDAGE, 1)
		_expect_inventory_count(member, CINDER_FLASK, 1)


func _validate_rustdead_members(rustdead_members: Array[HumanoidCharacter]) -> void:
	if rustdead_members.size() != 10:
		_fail("Expected 10 Rustdead, got %d" % rustdead_members.size())
	var naked_count := 0
	var pants_no_chest_count := 0
	for member in rustdead_members:
		_validate_skill_levels(member, RUSTDEAD_SKILL_LEVEL)
		if str(member.character_race.get("race_id")) != "rustdead":
			_fail("%s should use rustdead race" % member.name)
		if member.get_equipped_item("weapon") != null or member.get_equipped_item("offhand") != null:
			_fail("%s should not have a weapon or offhand in the demo" % member.name)
		if member.appearance_data == null or not bool(member.appearance_data.skin_color_customized):
			_fail("%s should have custom Fresh Rustdead skin color" % member.name)
		if not member.has_custom_skin_material():
			_fail("%s should have generated Rustdead skin material" % member.name)
		var clothing_count := _get_clothing_count(member)
		if clothing_count == 0:
			naked_count += 1
		if member.get_equipped_item("legs") != null and member.get_equipped_item("chest") == null:
			pants_no_chest_count += 1
	if naked_count <= 0:
		_fail("At least one Rustdead should spawn with no clothes")
	if pants_no_chest_count <= 0:
		_fail("At least one Rustdead should spawn with pants/legs but no chest clothing")


func _validate_rustdead_animation_library(rustdead_members: Array[HumanoidCharacter]) -> void:
	if rustdead_members.is_empty():
		return
	var member := rustdead_members[0]
	var animation_player: AnimationPlayer = member.get("_character_animation_player")
	if animation_player == null:
		_fail("Rustdead animation player was not created")
		return
	for animation_name in REQUIRED_RUSTDEAD_ANIMATIONS:
		if not animation_player.has_animation(animation_name):
			_fail("Rustdead animation library missing %s" % animation_name)


func _validate_rustdead_cinder_burn_rules(party_members: Array[HumanoidCharacter], rustdead_members: Array[HumanoidCharacter]) -> void:
	if party_members.is_empty() or rustdead_members.is_empty():
		return
	var actor := party_members[0]
	var rustdead := rustdead_members[0]
	rustdead.force_kill(actor)
	await _wait_frames(2)
	if rustdead.life_state == NpcRules.LifeState.DEAD:
		_fail("Rustdead should not enter DEAD from force_kill without cinder burn")
		return
	if rustdead.life_state != NpcRules.LifeState.UNCONSCIOUS:
		_fail("Rustdead should be unconscious after lethal non-fire damage")
		return
	if not rustdead.requires_fire_to_die() or not rustdead.can_be_destroyed_by_cinder():
		_fail("Downed Rustdead should require and allow cinder destruction")
		return
	var before_flasks := actor.inventory.count_item(CINDER_FLASK)
	rustdead.cinder_burn_duration_seconds = 0.1
	if not actor.burn_target_with_cinder_flask(rustdead, false):
		_fail("Party member should be able to start Cinder Flask burn")
		return
	if rustdead.life_state != NpcRules.LifeState.DEAD:
		_fail("Rustdead should enter DEAD as soon as cinder burn starts")
	if not rustdead.is_fire_destruction_in_progress():
		_fail("Cinder burn fire effect should keep running after immediate death")
	var burn_anchor_before_finish := rustdead.get_follow_anchor_position()
	var after_flasks := actor.inventory.count_item(CINDER_FLASK)
	if after_flasks != before_flasks - 1:
		_fail("Cinder Flask should be consumed when burning Rustdead")
	await _wait_frames(18)
	var burn_anchor_after_finish := rustdead.get_follow_anchor_position()
	var burn_anchor_shift := Vector2(burn_anchor_before_finish.x - burn_anchor_after_finish.x, burn_anchor_before_finish.z - burn_anchor_after_finish.z).length()
	if burn_anchor_shift > 1.2:
		_fail("Burned Rustdead corpse should not teleport away from its ragdoll position")
	if rustdead.life_state != NpcRules.LifeState.DEAD:
		_fail("Rustdead should enter DEAD after cinder burn finishes")
	if not rustdead.is_inside_tree():
		_fail("Burned Rustdead corpse should remain in the scene")
	if not rustdead.is_cinder_burned():
		_fail("Burned Rustdead should be marked cinder burned")
	elif not rustdead.has_cinder_burned_visuals():
		_fail("Burned Rustdead should have charred body materials")
	await _validate_relaxed_rustdead_burn_reach(party_members, rustdead_members)


func _validate_relaxed_rustdead_burn_reach(party_members: Array[HumanoidCharacter], rustdead_members: Array[HumanoidCharacter]) -> void:
	if party_members.size() < 2 or rustdead_members.size() < 2:
		return
	var actor := party_members[1]
	var rustdead := rustdead_members[1]
	rustdead.force_kill(actor)
	await _wait_frames(2)
	if rustdead.life_state != NpcRules.LifeState.UNCONSCIOUS:
		_fail("Reach test Rustdead should be unconscious before burning")
		return
	var anchor := rustdead.get_follow_anchor_position()
	actor.global_position = Vector3(anchor.x + 2.65, actor.global_position.y, anchor.z)
	var before_flasks := actor.inventory.count_item(CINDER_FLASK)
	rustdead.cinder_burn_duration_seconds = 0.2
	actor.assign_finish_off_target(rustdead, true)
	await _wait_frames(6)
	var after_flasks := actor.inventory.count_item(CINDER_FLASK)
	if after_flasks != before_flasks - 1:
		_fail("Relaxed downed Rustdead burn reach should consume a Cinder Flask")
	if rustdead.life_state != NpcRules.LifeState.DEAD:
		_fail("Relaxed downed Rustdead burn reach should mark DEAD immediately")
	if not rustdead.is_fire_destruction_in_progress() and rustdead.life_state != NpcRules.LifeState.DEAD:
		_fail("Relaxed downed Rustdead burn reach should start cinder burn")


func _validate_skill_levels(member: HumanoidCharacter, expected_level: int) -> void:
	for definition in SkillRules.get_all_definitions():
		var actual := member.get_skill_level(definition.skill_id)
		if actual != expected_level:
			_fail("%s skill %s should be %d, got %d" % [member.name, definition.skill_id, expected_level, actual])
			return


func _expect_equipped(member: HumanoidCharacter, slot_name: String) -> void:
	if member.get_equipped_item(slot_name) == null:
		_fail("%s should have %s equipped" % [member.name, slot_name])


func _expect_inventory_count(member: HumanoidCharacter, item_definition: ItemDefinition, minimum_count: int) -> void:
	if member.inventory == null:
		_fail("%s should have inventory" % member.name)
		return
	var actual := member.inventory.count_item(item_definition)
	if actual < minimum_count:
		_fail("%s should have at least %d %s, got %d" % [member.name, minimum_count, item_definition.display_name, actual])


func _get_clothing_count(member: HumanoidCharacter) -> int:
	var count := 0
	for slot_name in ["undershirt", "hands", "chest", "legs", "feet", "backpack", "head"]:
		if member.get_equipped_item(slot_name) != null:
			count += 1
	return count


func _wait_frames(frame_count: int) -> void:
	for _index in range(frame_count):
		await process_frame


func _fail(message: String) -> void:
	_failures.append(message)
