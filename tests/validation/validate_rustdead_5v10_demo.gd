extends "res://tests/validation/test_case.gd"

const RUSTDEAD_DEMO_SCENE := preload("res://scenes/test_levels/rustdead_5v10_demo.tscn")
const RUSTDEAD_RACE := preload("res://features/actors/resources/character_races/rustdead.tres")
const SKIN_TEXTURE_BUILDER := preload("res://features/actors/projection/appearance/skin_texture_builder.gd")
const RUSTDEAD_TIER_LIBRARY := preload("res://features/actors/projection/rustdead/rustdead_tier_library.gd")
const BANDAGE := preload("res://features/inventory/resources/items/bandage.tres")
const CINDER_FLASK := preload("res://features/inventory/resources/items/cinder_flask.tres")

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
	paused = false


func _cleanup_scene() -> void:
	if _scene == null:
		return
	_scene.queue_free()
	_scene = null
	await _wait_frames(2)

func _validate_generated_textures() -> void:
	SKIN_TEXTURE_BUILDER.clear_runtime_caches()
	var race_id := str(RUSTDEAD_RACE.race_id)
	var tones: Array = SKIN_TEXTURE_BUILDER.get_skin_tones_for_race(race_id)
	var supported_variants := SKIN_TEXTURE_BUILDER.get_supported_body_variants()
	if supported_variants.is_empty():
		_fail("Generated skin source coverage must not be empty")
	var checked := 0
	for archetype_value in [RUSTDEAD_RACE.default_male_archetype, RUSTDEAD_RACE.default_female_archetype]:
		var archetype := archetype_value as CharacterBodyArchetypeDefinition
		if archetype == null:
			_fail("Rustdead must author both body archetypes for skin texture coverage")
			continue
		# Discover the actual authored bodies, not just the loader's heroic default.
		var variants: Array[String] = []
		for scene: PackedScene in [archetype.visual_scene, archetype.regular_visual_scene, archetype.heroic_visual_scene, archetype.teen_visual_scene]:
			if scene == null:
				continue
			var body := scene.instantiate()
			var variant := SKIN_TEXTURE_BUILDER.detect_body_variant(body)
			body.free()
			if not variants.has(variant):
				variants.append(variant)
		if variants.is_empty():
			_fail("Rustdead body %s must provide a visual scene" % archetype.archetype_id)
		for variant in variants:
			if not supported_variants.has(variant):
				_fail("Authored Rustdead body %s/%s is absent from generator source coverage" % [archetype.archetype_id, variant])
		for variant in supported_variants:
			if not variants.has(variant):
				_fail("Generated skin variant %s has no authored Rustdead body %s" % [variant, archetype.archetype_id])
			for tone_index in range(tones.size()):
				var path := SKIN_TEXTURE_BUILDER.get_generated_skin_texture_path(race_id, archetype.visual_body_type, tone_index, variant)
				var texture := SKIN_TEXTURE_BUILDER.get_skin_texture(race_id, archetype.visual_body_type, tones[tone_index], variant)
				checked += 1
				if texture == null:
					_fail("Missing generated Rustdead skin texture: %s" % path)
				elif texture.resource_path != path or texture.get_width() <= 0 or texture.get_height() <= 0:
					_fail("Rustdead skin must load the exact nonempty generated texture: %s" % path)
	print("RUSTDEAD_SKIN_TEXTURES_CHECKED count=%d" % checked)
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
	if party_members.size() != 5:
		_fail("Expected 5 humanoid party members, got %d" % party_members.size())
	for member in party_members:
		var humanoid := member as HumanoidCharacter
		if humanoid == null:
			_fail("%s should be a humanoid party member" % member.name)
			continue
		_validate_skill_levels(humanoid, int(PARTY_SKILL_LEVELS.get(str(humanoid.member_name), PARTY_DEFAULT_SKILL_LEVEL)))
		_expect_equipped(humanoid, "weapon")
		_expect_equipped(humanoid, "chest")
		_expect_equipped(humanoid, "legs")
		_expect_equipped(humanoid, "feet")
		_expect_inventory_count(humanoid, BANDAGE, 1)
		_expect_inventory_count(humanoid, CINDER_FLASK, 1)


func _validate_rustdead_members(rustdead_members: Array[HumanoidCharacter]) -> void:
	if rustdead_members.size() != 10:
		_fail("Expected 10 Rustdead, got %d" % rustdead_members.size())
	var naked_count := 0
	var pants_no_chest_count := 0
	var fresh_hair_count := 0
	var fresh_male_beard_count := 0
	var seen_tiers := {}
	for member in rustdead_members:
		if not member is RustdeadHumanoidCharacter:
			_fail("Demo must spawn concrete Rustdead actors, not generic humanoids")
		if str(member.appearance_data.character_race.get("race_id")) != "rustdead":
			_fail("%s should use rustdead race" % member.name)
		_validate_rustdead_tier(member, seen_tiers)
		if member.get_equipped_item("weapon") != null or member.get_equipped_item("offhand") != null:
			_fail("%s should not have a weapon or offhand in the demo" % member.name)
		if member.appearance_data == null or not bool(member.appearance_data.skin_color_customized):
			_fail("%s should have custom Fresh Rustdead skin color" % member.name)
		if not SKIN_TEXTURE_BUILDER.has_custom_skin_materials(member.get_character_visual_root()):
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
	var ground_y := body.get_visual_ground_y() if body != null else 0.0
	if not is_finite(foot_y) or not is_finite(ground_y):
		_fail("%s should expose a visual foot anchor" % member.name)
		return
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
	# The authored groups start out of reach. The burn command must refuse
	# there without debit; test the fire/timer consequences from legal reach.
	if actor._is_close_enough_to_downed_interaction_target(rustdead):
		_fail("Cinder fixture should begin with the authored distant party/body positions")
	elif actor.get_interaction().burn_target_with_cinder_flask(rustdead, false):
		_fail("Distant Cinder Flask burn must be refused")
	if actor.inventory.count_item(CINDER_FLASK) != before_flasks:
		_fail("Distant burn refusal must preserve the carried flask")
	var anchor := rustdead.get_follow_anchor_position()
	actor.global_position = Vector3(anchor.x - actor.interact_distance * 0.5, actor.global_position.y, anchor.z)
	if not actor.get_interaction().call("burn_target_with_cinder_flask", rustdead, false):
		_fail("Party member should be able to start Cinder Flask burn; alive=%s flasks=%d reachable=%s actor=%s body=%s" % [actor.life_state, before_flasks, actor._is_close_enough_to_downed_interaction_target(rustdead), actor.global_position, rustdead.get_follow_anchor_position()])
		return
	if rustdead.life_state != NpcRules.LifeState.DEAD:
		_fail("Rustdead should enter DEAD as soon as cinder burn starts")
	if not rustdead.is_fire_destruction_in_progress():
		_fail("Cinder burn fire effect should keep running after immediate death")
	var burn_anchor_before_finish := rustdead.get_follow_anchor_position()
	var after_flasks := actor.inventory.count_item(CINDER_FLASK)
	if after_flasks != before_flasks - 1:
		_fail("Cinder Flask should be consumed when burning Rustdead")
	await create_timer(0.2).timeout
	if rustdead.is_fire_destruction_in_progress():
		_fail("Cinder fire timer must finish after the authored duration; processing=%s paused=%s remaining=%.3f" % [rustdead.is_processing(), paused, rustdead._cinder_burn_remaining])
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
	print("RUSTDEAD_CINDER_CONSUMPTION_TIMER_AND_CORPSE_EXECUTED")
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
	var approach_start := actor.global_position
	actor.assign_finish_off_target(rustdead, true)
	actor.get_interaction().process_finish_off_interaction()
	if actor.get_interaction().current_finish_off_target != rustdead:
		_fail("Out-of-reach Burn must retain the commanded body and begin approaching")
	# Keep the authored 2.65m start and real reach predicate. Six awaited
	# signals do not prove an actor has walked into range; wait for the effect
	# with an explicit bound, and reject premature cancellation or remote burn.
	var deadline := Time.get_ticks_msec() + 5000
	while rustdead.life_state != NpcRules.LifeState.DEAD and actor.get_interaction().current_finish_off_target == rustdead and Time.get_ticks_msec() < deadline:
		await physics_frame
		await process_frame
	var after_flasks := actor.inventory.count_item(CINDER_FLASK)
	if Vector2(actor.global_position.x - approach_start.x, actor.global_position.z - approach_start.z).length() < 0.05:
		_fail("Out-of-reach Burn must physically move its actor toward the body")
	if after_flasks != before_flasks - 1:
		_fail("Relaxed downed Rustdead burn reach should consume a Cinder Flask")
	if rustdead.life_state != NpcRules.LifeState.DEAD:
		_fail("Relaxed downed Rustdead burn reach should mark DEAD immediately")
	if not rustdead.is_fire_destruction_in_progress() and rustdead.life_state != NpcRules.LifeState.DEAD:
		_fail("Relaxed downed Rustdead burn reach should start cinder burn")
	print("RUSTDEAD_RELAXED_REACH_AND_FLASK_DEBIT_EXECUTED")


func _validate_skill_levels(member: HumanoidCharacter, expected_level: int) -> void:
	for definition in SkillRules.get_all_definitions():
		var actual := member.get_skill_level(definition.skill_id)
		if actual != expected_level:
			_fail("%s skill %s should be %d, got %d" % [member.name, definition.skill_id, expected_level, actual])
			return


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
