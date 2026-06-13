extends SceneTree

const RUSTDEAD_DEMO_SCENE := preload("res://scenes/test_levels/rustdead_5v10_demo.tscn")
const RUSTDEAD_RACE := preload("res://resources/character_races/rustdead.tres")
const QUADBOT_RACE := preload("res://resources/character_races/quadbot.tres")
const QUADBOT_CHARACTER_SCRIPT := preload("res://scripts/characters/quadbot_character.gd")
const QUADBOT_BODY_PROJECTION_SCRIPT := preload("res://scripts/projection/quadbot_body_projection.gd")
const ROBOT_OIL := preload("res://resources/bleed_fluids/robot_oil.tres")
const SKIN_TEXTURE_BUILDER := preload("res://scripts/character_appearance/skin_texture_builder.gd")
const RUSTDEAD_TIER_LIBRARY := preload("res://scripts/characters/rustdead_tier_library.gd")
const BANDAGE := preload("res://resources/items/bandage.tres")
const CINDER_FLASK := preload("res://resources/items/cinder_flask.tres")

const PARTY_DEFAULT_SKILL_LEVEL := 40
const PARTY_SKILL_LEVELS := {
	"Mira": 60,
	"Tomas": 60,
}
const REQUIRED_RUSTDEAD_ANIMATIONS := ["Zombie_Idle", "Zombie_Walk_Fwd", "Zombie_Run_Fwd", "Zombie_Bite", "Zombie_Scratch", "Zombie_Spawn"]
const MAX_VISUAL_FOOT_SINK := 0.035
const WROUGHT_MIN_SKIN_METALLIC := 0.30
const ANCIENT_MIN_SKIN_METALLIC := 0.58

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
	_validate_generated_textures()
	await _load_scene()
	var party_members := _get_party_members()
	var rustdead_members := _get_rustdead_members()
	_validate_party_members(party_members)
	_validate_rustdead_members(rustdead_members)
	_validate_rustdead_animation_library(rustdead_members)
	await _validate_rustdead_cinder_burn_rules(party_members, rustdead_members)
	if _failures.is_empty():
		await _cleanup_scene()
		print("RUSTDEAD_5V10_DEMO_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	await _cleanup_scene()
	print("RUSTDEAD_5V10_DEMO_FAILED count=%d" % _failures.size())
	quit(1)


func _load_scene() -> void:
	_scene = RUSTDEAD_DEMO_SCENE.instantiate()
	root.add_child(_scene)
	await _wait_frames(16)


func _cleanup_scene() -> void:
	if _scene == null:
		return
	_scene.queue_free()
	_scene = null
	await _wait_frames(2)

func _validate_generated_textures() -> void:
	for body_type in [SKIN_TEXTURE_BUILDER.VISUAL_BODY_TYPE_MALE, SKIN_TEXTURE_BUILDER.VISUAL_BODY_TYPE_FEMALE]:
		for tone_index in range(SKIN_TEXTURE_BUILDER.get_skin_tone_count(SKIN_TEXTURE_BUILDER.RUSTDEAD_RACE_ID)):
			var path := SKIN_TEXTURE_BUILDER.get_generated_skin_texture_path(SKIN_TEXTURE_BUILDER.RUSTDEAD_RACE_ID, body_type, tone_index)
			if load(path) == null:
				_fail("Missing generated Rustdead skin texture: %s" % path)
	for tier in RUSTDEAD_TIER_LIBRARY.get_tiers():
		var indices: PackedInt32Array = tier.get("skin_tone_indices")
		if indices.is_empty():
			_fail("Rustdead tier %s should map to generated skin tone textures" % str(tier.get("display_name")))


func _get_party_members() -> Array[WorldActor]:
	var result: Array[WorldActor] = []
	var party_root := _scene.get_node_or_null("PartyMembers") if _scene != null else null
	if party_root == null:
		_fail("PartyMembers node was not found")
		return result
	for child in party_root.get_children():
		if child is WorldActor:
			result.append(child as WorldActor)
	return result


func _get_rustdead_members() -> Array[HumanoidCharacter]:
	var result: Array[HumanoidCharacter] = []
	if _scene == null:
		return result
	for child in _scene.get_children():
		if child is HumanoidCharacter and str(child.get("faction_name")) == "Rustdead":
			result.append(child as HumanoidCharacter)
	return result


func _validate_party_members(party_members: Array[WorldActor]) -> void:
	if party_members.size() != 6:
		_fail("Expected 6 party members including one robot, got %d" % party_members.size())
	var robot_count := 0
	for member in party_members:
		if _is_robot_party_member(member):
			robot_count += 1
			_validate_robot_party_member(member)
			continue
		var humanoid := member as HumanoidCharacter
		if humanoid == null:
			_fail("%s should be humanoid or robot party member" % member.name)
			continue
		_validate_skill_levels(humanoid, int(PARTY_SKILL_LEVELS.get(str(humanoid.member_name), PARTY_DEFAULT_SKILL_LEVEL)))
		_expect_equipped(humanoid, "weapon")
		_expect_equipped(humanoid, "chest")
		_expect_equipped(humanoid, "legs")
		_expect_equipped(humanoid, "feet")
		_expect_inventory_count(humanoid, BANDAGE, 1)
		_expect_inventory_count(humanoid, CINDER_FLASK, 1)
	if robot_count != 1:
		_fail("Expected exactly one robot party member, got %d" % robot_count)


func _is_robot_party_member(member: WorldActor) -> bool:
	var race = member.get("character_race") if member != null else null
	return race != null and str(race.get("race_id")) == "quadbot"


func _validate_robot_party_member(member: WorldActor) -> void:
	if member.get_script() != QUADBOT_CHARACTER_SCRIPT:
		_fail("%s should use QuadBotCharacter" % member.name)
		return
	if member.get("character_race") != QUADBOT_RACE:
		_fail("%s should use quadbot race" % member.name)
	if not member.is_player_party_member():
		_fail("%s should be a player party member" % member.name)
	if member.combat_stance != NpcRules.CombatStance.DEFENSIVE:
		_fail("%s should use normal defensive party combat stance" % member.name)
	if not member.ai_brain_enabled:
		_fail("%s should keep AI brain enabled" % member.name)
	var party_line_position := Vector2(-4.0, 9.0)
	var robot_position := Vector2(member.global_position.x, member.global_position.z)
	if robot_position.distance_to(party_line_position) > 3.0:
		_fail("%s should spawn with the party group, got %s" % [member.name, str(member.global_position)])
	var selection_ring := member.get_node_or_null("SelectionRing") as MeshInstance3D
	if selection_ring == null:
		_fail("%s should have a selection ring" % member.name)
	elif selection_ring.mesh == null:
		_fail("%s selection ring should have a mesh" % member.name)
	elif selection_ring.mesh is CylinderMesh:
		_fail("%s selection ring should not be a flat CylinderMesh disk" % member.name)
	if not is_equal_approx(member.max_hp, 200.0):
		_fail("%s should start with 200 Hull, got %.1f" % [member.name, member.max_hp])
	if member.get_health_vital_label() != "Hull":
		_fail("%s health vital should be Hull" % member.name)
	if member.call("get_bleed_fluid") != ROBOT_OIL or member.get_vital_fluid_label() != "Oil":
		_fail("%s should use Oil vital fluid" % member.name)
	if member.call("can_receive_bandage"):
		_fail("%s should not accept bandages" % member.name)
	if member.shows_hunger_vital() or member.shows_fatigue_vital():
		_fail("%s should hide hunger and fatigue vitals" % member.name)
	_validate_robot_skill_variance(member)
	var body = member.call("get_body_projection") if member.has_method("get_body_projection") else null
	if body == null or body.get_script() != QUADBOT_BODY_PROJECTION_SCRIPT:
		_fail("%s should use QuadBotBodyProjection" % member.name)
		return
	for animation_name in ["Idle", "Walk", "Run", "Attack"]:
		if not body.has_clip(animation_name):
			_fail("%s robot body missing %s animation" % [member.name, animation_name])
	if not body.play_clip("Idle", 0.0, true):
		_fail("%s robot body should play Idle animation" % member.name)
	elif body.get_current_clip() != "Idle" or not body.is_current_clip_playing():
		_fail("%s robot Idle animation should keep playing" % member.name)
	if body.has_clip("Death01") or body.has_clip("Death02"):
		_fail("%s robot body should not expose humanoid death clips" % member.name)


func _validate_rustdead_members(rustdead_members: Array[HumanoidCharacter]) -> void:
	if rustdead_members.size() != 10:
		_fail("Expected 10 Rustdead, got %d" % rustdead_members.size())
	var naked_count := 0
	var pants_no_chest_count := 0
	var fresh_hair_count := 0
	var fresh_male_beard_count := 0
	var seen_tiers := {}
	for member in rustdead_members:
		if str(member.character_race.get("race_id")) != "rustdead":
			_fail("%s should use rustdead race" % member.name)
		_validate_rustdead_tier(member, seen_tiers)
		if member.get_equipped_item("weapon") != null or member.get_equipped_item("offhand") != null:
			_fail("%s should not have a weapon or offhand in the demo" % member.name)
		if member.appearance_data == null or not bool(member.appearance_data.skin_color_customized):
			_fail("%s should have custom Fresh Rustdead skin color" % member.name)
		if not member.has_custom_skin_material():
			_fail("%s should have generated Rustdead skin material" % member.name)
		_validate_visual_feet(member)
		if member.appearance_data != null:
			if member.appearance_data.eyebrow_style != null:
				_fail("%s should not keep normal eyebrows" % member.name)
			if member.appearance_data.hair_style != null:
				fresh_hair_count += 1
			if member.appearance_data.visual_body_type == SKIN_TEXTURE_BUILDER.VISUAL_BODY_TYPE_MALE and member.appearance_data.beard_style != null:
				fresh_male_beard_count += 1
		var clothing_count := _get_clothing_count(member)
		if clothing_count == 0:
			naked_count += 1
		if member.get_equipped_item("legs") != null and member.get_equipped_item("chest") == null:
			pants_no_chest_count += 1
	if naked_count <= 0:
		_fail("At least one Rustdead should spawn with no clothes")
	if pants_no_chest_count <= 0:
		_fail("At least one Rustdead should spawn with pants/legs but no chest clothing")
	if fresh_hair_count <= 0:
		_fail("At least one fresh Rustdead should spawn with hair")
	if fresh_male_beard_count <= 0:
		_fail("At least one fresh male Rustdead should spawn with a beard")
	for tier in RUSTDEAD_TIER_LIBRARY.get_tiers():
		var tier_id := str(tier.call("get_id"))
		if not seen_tiers.has(tier_id):
			_fail("5v10 demo should include %s" % str(tier.get("display_name")))


func _validate_rustdead_tier(member: HumanoidCharacter, seen_tiers: Dictionary) -> void:
	if not member.has_method("get_rustdead_tier_definition"):
		_fail("%s should expose a Rustdead tier definition" % member.name)
		return
	var tier := member.call("get_rustdead_tier_definition") as Resource
	if tier == null:
		_fail("%s should have a Rustdead tier definition" % member.name)
		return
	var tier_id := str(tier.call("get_id")) if tier.has_method("get_id") else ""
	seen_tiers[tier_id] = true
	if str(member.member_name) != str(tier.get("display_name")):
		_fail("%s member_name should display as %s, got %s" % [member.name, str(tier.get("display_name")), str(member.member_name)])
	if member.has_method("get_rustdead_tier_id") and str(member.call("get_rustdead_tier_id")) != tier_id:
		_fail("%s tier id should be %s, got %s" % [member.name, tier_id, str(member.call("get_rustdead_tier_id"))])
	if member.has_method("get_rustdead_passive_bonus") and absf(float(member.call("get_rustdead_passive_bonus")) - float(tier.get("passive_bonus"))) > 0.001:
		_fail("%s passive bonus should match tier %s" % [member.name, tier_id])
	var hp_range: Vector2 = tier.call("get_max_hp_range")
	if member.max_hp < hp_range.x - 0.001 or member.max_hp > hp_range.y + 0.001:
		_fail("%s max HP %.2f should be in %s range %s" % [member.name, member.max_hp, tier_id, str(hp_range)])
	_validate_rustdead_skill_ranges(member, tier, tier_id)
	_validate_toughness_blood(member)
	_validate_metallic_skin_material(member, tier_id)


func _validate_toughness_blood(member: HumanoidCharacter) -> void:
	var toughness := member.get_skill_level(SkillRules.ATTRIBUTE_TOUGHNESS)
	var expected_max_blood := SkillRules.get_max_blood_for_toughness(member.get_base_max_blood(), toughness)
	if absf(member.max_blood - expected_max_blood) > 0.05:
		_fail("%s max blood %.2f should scale from Toughness %d to %.2f" % [member.name, member.max_blood, toughness, expected_max_blood])
	if toughness > 0 and member.max_blood <= 100.0:
		_fail("%s max blood should exceed 100 when Toughness is above zero" % member.name)
	if absf(member.blood - member.max_blood) > 0.05:
		_fail("%s should start with blood filled to max blood" % member.name)


func _validate_metallic_skin_material(member: HumanoidCharacter, tier_id: String) -> void:
	if tier_id != "wrought" and tier_id != "ancient":
		return
	var material := _find_rustdead_skin_material(member)
	if material == null:
		_fail("%s should expose a generated Rustdead skin material for metallic validation" % member.name)
		return
	var min_metallic := ANCIENT_MIN_SKIN_METALLIC if tier_id == "ancient" else WROUGHT_MIN_SKIN_METALLIC
	if material.metallic < min_metallic:
		_fail("%s %s skin should be metallic, got metallic=%.2f" % [member.name, tier_id, material.metallic])
	if tier_id == "ancient" and material.roughness > 0.45:
		_fail("%s Ancient Rustdead skin should be lower roughness chrome/iron, got %.2f" % [member.name, material.roughness])


func _validate_visual_feet(member: HumanoidCharacter) -> void:
	var body := member.get_body_projection()
	var foot_y := body.get_visual_foot_anchor_y() if body != null else INF
	if foot_y == INF:
		_fail("%s should expose a visual foot anchor" % member.name)
		return
	var ground_y := body.get_visual_ground_y() if body != null else 0.0
	if foot_y < ground_y - MAX_VISUAL_FOOT_SINK:
		_fail("%s visual feet should not sink below ground: foot=%.3f ground=%.3f" % [member.name, foot_y, ground_y])


func _find_rustdead_skin_material(root: Node) -> BaseMaterial3D:
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		for surface_index in range(mesh_instance.get_surface_override_material_count()):
			var material := mesh_instance.get_surface_override_material(surface_index) as BaseMaterial3D
			if material != null and material.albedo_texture != null and str(material.albedo_texture.resource_path).contains("/character_skin/rustdead/"):
				return material
	for child in root.get_children():
		var child_material := _find_rustdead_skin_material(child)
		if child_material != null:
			return child_material
	return null


func _validate_rustdead_animation_library(rustdead_members: Array[HumanoidCharacter]) -> void:
	if rustdead_members.is_empty():
		return
	var member := rustdead_members[0]
	var body := member.get_body_projection()
	var animation_player: AnimationPlayer = body.get_primary_animation_player() if body != null else null
	if animation_player == null:
		_fail("Rustdead animation player was not created")
		return
	for animation_name in REQUIRED_RUSTDEAD_ANIMATIONS:
		if not animation_player.has_animation(animation_name):
			_fail("Rustdead animation library missing %s" % animation_name)


func _validate_rustdead_cinder_burn_rules(party_members: Array[WorldActor], rustdead_members: Array[HumanoidCharacter]) -> void:
	if party_members.is_empty() or rustdead_members.is_empty():
		return
	var actor := party_members[0] as HumanoidCharacter
	var rustdead := rustdead_members[0]
	if actor == null:
		_fail("First party member should be humanoid for cinder validation")
		return
	rustdead.force_kill(actor)
	await _wait_frames(2)
	if rustdead.life_state == NpcRules.LifeState.DEAD:
		_fail("Rustdead should not enter DEAD from force_kill without cinder burn")
		return
	if not rustdead.is_downed_state():
		_fail("Rustdead should be downed after lethal non-fire damage")
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


func _validate_relaxed_rustdead_burn_reach(party_members: Array[WorldActor], rustdead_members: Array[HumanoidCharacter]) -> void:
	if party_members.size() < 2 or rustdead_members.size() < 2:
		return
	var actor := party_members[1] as HumanoidCharacter
	var rustdead := rustdead_members[1]
	if actor == null:
		_fail("Second party member should be humanoid for burn reach validation")
		return
	rustdead.force_kill(actor)
	await _wait_frames(2)
	if not rustdead.is_downed_state():
		_fail("Reach test Rustdead should be downed before burning")
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


func _validate_robot_skill_variance(member: WorldActor) -> void:
	var unique_levels := {}
	var total := 0
	var count := 0
	for definition in SkillRules.get_all_definitions():
		var actual := member.get_skill_level(definition.skill_id)
		if actual < QUADBOT_CHARACTER_SCRIPT.QUADBOT_SKILL_MIN_LEVEL or actual > QUADBOT_CHARACTER_SCRIPT.QUADBOT_SKILL_MAX_LEVEL:
			_fail("%s robot skill %s should be varied around %d, got %d" % [member.name, definition.skill_id, PARTY_DEFAULT_SKILL_LEVEL, actual])
		unique_levels[actual] = true
		total += actual
		count += 1
	if unique_levels.size() < 4:
		_fail("%s robot skills should not be flat" % member.name)
	if count > 0:
		var average := float(total) / float(count)
		if average < 32.0 or average > 48.0:
			_fail("%s robot skills should average near %d, got %.2f" % [member.name, PARTY_DEFAULT_SKILL_LEVEL, average])


func _validate_rustdead_skill_ranges(member: HumanoidCharacter, tier: Resource, tier_id: String) -> void:
	var tier_range: Vector2i = tier.call("get_stat_range")
	var non_tier_range := RUSTDEAD_TIER_LIBRARY.get_non_tier_skill_range()
	for definition in SkillRules.get_all_definitions():
		var actual := member.get_skill_level(definition.skill_id)
		var expected_range := tier_range if RUSTDEAD_TIER_LIBRARY.is_tier_scaled_skill_id(definition.skill_id) else non_tier_range
		var range_label := "tier" if RUSTDEAD_TIER_LIBRARY.is_tier_scaled_skill_id(definition.skill_id) else "non-tier Rustdead"
		if actual < expected_range.x or actual > expected_range.y:
			_fail("%s skill %s should be in %s range %d-%d, got %d" % [member.name, definition.skill_id, range_label, expected_range.x, expected_range.y, actual])
			return
	if tier_id == "ancient":
		_validate_ancient_non_tier_skill_is_low(member, SkillRules.ATTRIBUTE_CHARISMA)
		_validate_ancient_non_tier_skill_is_low(member, SkillRules.COMBAT_SWORDS_ONE_HANDED)
		_validate_ancient_non_tier_skill_is_low(member, SkillRules.SUBTERFUGE_SNEAKING)
		_validate_ancient_non_tier_skill_is_low(member, SkillRules.CRAFT_BLACKSMITHING)
		_validate_ancient_non_tier_skill_is_low(member, SkillRules.TECH_ROBOTICS)


func _validate_ancient_non_tier_skill_is_low(member: HumanoidCharacter, skill_id: String) -> void:
	var non_tier_range := RUSTDEAD_TIER_LIBRARY.get_non_tier_skill_range()
	var actual := member.get_skill_level(skill_id)
	if actual > non_tier_range.y:
		_fail("Ancient Rustdead %s should not scale non-physical skill %s above %d, got %d" % [member.name, skill_id, non_tier_range.y, actual])


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
