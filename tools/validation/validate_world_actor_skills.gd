extends SceneTree

const COMBAT_COORDINATOR = preload("res://features/combat/bridge/combat_coordinator.gd")
const CHARACTER_SKILLS_WINDOW_SCRIPT = preload("res://features/ui/projection/character_skills_window.gd")
const HUMANOID_DETAILS_CONTROLLER_SCRIPT = preload("res://features/ui/bridge/humanoid_details_controller.gd")
const COPPER_ORE = preload("res://features/inventory/resources/items/copper_ore.tres")
const PICKAXE = preload("res://features/inventory/resources/items/rusted_pickaxe.tres")
const WORLD_ITEM_SCENE = preload("res://features/world/projection/items/world_item.tscn")
const PARTY_INVENTORY_CONTROLLER_SCRIPT = preload("res://features/inventory/bridge/party_inventory_controller.gd")
const GAME_HUD_SCENE = preload("res://features/ui/projection/game_hud.tscn")

class InitiativeDummy:
	extends Node3D
	var dexterity := 1.0

	func get_stat_value(stat_name: String) -> float:
		return dexterity if stat_name == "dexterity" else 0.0


class OffsetDropOwner:
	extends Node3D
	var collision_bottom_local_y := 0.0

	func get_inventory_world_position() -> Vector3:
		return global_position

	func get_collision_bottom_local_y() -> float:
		return collision_bottom_local_y

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_catalog()
	_validate_progression()
	_validate_mining_speed_rules()
	_validate_toughness_max_blood_rules()
	await _validate_mining_interaction_radius()
	await _validate_copper_ore_world_visual()
	_validate_world_actor_api()
	_validate_weighted_initiative()
	await _validate_inventory_toggle_behavior()
	await _validate_mining_pickaxe_requirement()
	await _validate_scavenging_rules()
	await _validate_locked_mining_attempt_trains_without_ore()
	await _validate_stalled_mining_awards_no_xp()
	await _validate_skills_window_live_update()
	await _validate_inspected_npc_skills_button()
	if _failures.is_empty():
		print("WORLD_ACTOR_SKILLS_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("WORLD_ACTOR_SKILLS_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_catalog() -> void:
	var required_ids := [
		SkillRules.ATTRIBUTE_STRENGTH,
		SkillRules.ATTRIBUTE_PERCEPTION,
		SkillRules.ATTRIBUTE_DEXTERITY,
		SkillRules.ATTRIBUTE_TOUGHNESS,
		SkillRules.ATTRIBUTE_ENDURANCE,
		SkillRules.ATTRIBUTE_CHARISMA,
		SkillRules.COMBAT_SWORDS_ONE_HANDED,
		SkillRules.COMBAT_AXES_ONE_HANDED,
		SkillRules.COMBAT_DAGGERS,
		SkillRules.COMBAT_UNARMED,
		SkillRules.MOVEMENT_RUNNING,
		SkillRules.LABOR_MINING,
		SkillRules.LABOR_SCAVENGING,
		SkillRules.LABOR_FARMING,
		SkillRules.LABOR_FISHING,
		SkillRules.LABOR_CONSTRUCTION,
		SkillRules.CRAFT_BLACKSMITHING,
		SkillRules.CRAFT_WEAVING,
		SkillRules.CRAFT_LEATHERWORKING,
		SkillRules.SUBTERFUGE_SNEAKING,
		SkillRules.SUBTERFUGE_SLEIGHT_OF_HAND,
		SkillRules.SUBTERFUGE_LOCKPICKING,
		SkillRules.KNOWLEDGE_MEDICINE,
		SkillRules.TECH_ROBOTICS,
		SkillRules.KNOWLEDGE_ARCHEOLOGY,
	]
	for skill_id in required_ids:
		var definition := SkillRules.get_definition(skill_id)
		if definition == null:
			_fail("Missing skill definition: %s" % skill_id)
	if SkillRules.get_definition(SkillRules.KNOWLEDGE_MEDICINE) != null and SkillRules.get_definition(SkillRules.KNOWLEDGE_MEDICINE).display_name != "Medical":
		_fail("Expected medicine display name to be Medical")


func _validate_progression() -> void:
	var level_1_xp := SkillRules.get_xp_to_next_level(1)
	var level_10_xp := SkillRules.get_xp_to_next_level(10)
	var level_20_xp := SkillRules.get_xp_to_next_level(20)
	var level_50_xp := SkillRules.get_xp_to_next_level(50)
	var level_80_xp := SkillRules.get_xp_to_next_level(80)
	var level_100_xp := SkillRules.get_xp_to_next_level(100)
	if SkillRules.get_xp_to_next_level(10) <= SkillRules.get_xp_to_next_level(1):
		_fail("Expected level 10 XP requirement to exceed level 1")
	if SkillRules.get_xp_to_next_level(80) <= SkillRules.get_xp_to_next_level(40):
		_fail("Expected level 80 XP requirement to exceed level 40")
	if level_10_xp > level_1_xp * 1.35:
		_fail("Expected levels 1-10 to stay fast, got level1=%.1f level10=%.1f" % [level_1_xp, level_10_xp])
	if level_20_xp < level_10_xp * 1.2:
		_fail("Expected levels 10-20 to start taking longer, got level10=%.1f level20=%.1f" % [level_10_xp, level_20_xp])
	if level_50_xp < level_20_xp * 2.0:
		_fail("Expected levels 30-50 to require sustained investment, got level20=%.1f level50=%.1f" % [level_20_xp, level_50_xp])
	if level_80_xp < level_50_xp * 5.0:
		_fail("Expected level 80+ mastery to slow sharply, got level50=%.1f level80=%.1f" % [level_50_xp, level_80_xp])
	if level_100_xp < level_80_xp * 10.0:
		_fail("Expected level 100+ to be absurdly slow, got level80=%.1f level100=%.1f" % [level_80_xp, level_100_xp])
	if SkillRules.get_xp_to_next_level(5) <= level_1_xp or SkillRules.get_xp_to_next_level(15) <= level_10_xp:
		_fail("Expected smooth XP curve to trend harder without relying on buckets")
	_validate_chance_check_xp_rules()
	var level_10_ratio := SkillRules.get_xp_to_next_level(10) / SkillRules.get_xp_to_next_level(9)
	var level_11_ratio := SkillRules.get_xp_to_next_level(11) / SkillRules.get_xp_to_next_level(10)
	if absf(level_11_ratio - level_10_ratio) > 0.08:
		_fail("Expected no bucket jump around level 10")
	var mining_ore_xp := SkillRules.get_xp_to_next_level(SkillRules.DEFAULT_LEVEL) / 4.0
	var mining_set := ActorSkillSet.new()
	mining_set.add_skill_xp(SkillRules.LABOR_MINING, mining_ore_xp, "validation_one_ore")
	if mining_set.get_skill_level(SkillRules.LABOR_MINING) != SkillRules.DEFAULT_LEVEL:
		_fail("Expected one ore worth of mining XP to stay below first level-up")
	mining_set.add_skill_xp(SkillRules.LABOR_MINING, mining_ore_xp * 3.0, "validation_four_ore")
	if mining_set.get_skill_level(SkillRules.LABOR_MINING) != SkillRules.DEFAULT_LEVEL + 1:
		_fail("Expected four ore worth of mining XP to reach level 2")
	var skill_set := ActorSkillSet.new()
	skill_set.set_skill_level(SkillRules.ATTRIBUTE_STRENGTH, 99)
	skill_set.add_skill_xp(SkillRules.ATTRIBUTE_STRENGTH, SkillRules.get_xp_to_next_level(99) + SkillRules.get_xp_to_next_level(100) + 1.0, "validation")
	if skill_set.get_skill_level(SkillRules.ATTRIBUTE_STRENGTH) < 101:
		_fail("Expected skills to progress beyond 100 without a cap")


func _validate_chance_check_xp_rules() -> void:
	if absf(SkillRules.get_chance_check_xp(0.1, true) - 20.0) > 0.01:
		_fail("Very Low chance successes should award high check XP")
	if absf(SkillRules.get_chance_check_xp(0.1, false) - 10.0) > 0.01:
		_fail("Very Low chance failures should award meaningful check XP")
	if absf(SkillRules.get_chance_check_xp(0.3, true) - 12.0) > 0.01:
		_fail("Low chance successes should award boosted check XP")
	if absf(SkillRules.get_chance_check_xp(0.5, true) - 5.0) > 0.01:
		_fail("Even chance successes should keep the baseline check XP")
	if absf(SkillRules.get_chance_check_xp(0.75, true) - 3.0) > 0.01:
		_fail("High chance successes should still award modest check XP")
	if absf(SkillRules.get_chance_check_xp(0.9, true) - 0.5) > 0.01:
		_fail("Very High chance successes should be tiny check XP")
	if absf(SkillRules.get_chance_check_xp(0.3, true, 0.5) - 6.0) > 0.01:
		_fail("Check XP scale should reduce repeatable training sources")


func _validate_world_actor_api() -> void:
	var actor := WorldActor.new()
	actor.starting_skill_levels = {SkillRules.ATTRIBUTE_PERCEPTION: 30}
	if actor.get_skill_level(SkillRules.ATTRIBUTE_STRENGTH) != 1:
		_fail("Expected generic actor default skill level to be 1")
	if actor.get_skill_level(SkillRules.ATTRIBUTE_PERCEPTION) != 30:
		_fail("Expected starting skill level override to apply")
	if absf(actor.get_stat_value("perception") - 30.0) > 0.01 or absf(actor.get_perception_skill_level() - 30.0) > 0.01:
		_fail("Expected generic actor Perception stat hook to use actor stat values")
	actor.set_skill_level(SkillRules.SUBTERFUGE_SNEAKING, 44)
	if absf(actor.get_stat_value("stealth") - 44.0) > 0.01 or absf(actor.get_stealth_skill_level() - 44.0) > 0.01:
		_fail("Expected generic actor stealth stat hook to use actor stat values")
	actor.add_skill_xp(SkillRules.MOVEMENT_RUNNING, SkillRules.get_xp_to_next_level(1), "validation")
	if actor.get_skill_level(SkillRules.MOVEMENT_RUNNING) <= 1:
		_fail("Expected WorldActor.add_skill_xp to level a skill")
	actor.queue_free()

	var humanoid := HumanoidCharacter.new()
	humanoid.set_skill_level(SkillRules.ATTRIBUTE_PERCEPTION, 33)
	humanoid.set_skill_level(SkillRules.SUBTERFUGE_SNEAKING, 55)
	if absf(humanoid.get_stat_value("perception") - 33.0) > 0.01 or absf(humanoid.get_perception_skill_level() - 33.0) > 0.01:
		_fail("Expected humanoid Perception stat hook to use actor stat values")
	if absf(humanoid.get_stat_value("stealth") - 55.0) > 0.01 or absf(humanoid.get_stealth_skill_level() - 55.0) > 0.01:
		_fail("Expected humanoid stealth stat hook to use actor stat values")
	humanoid.queue_free()


func _validate_toughness_max_blood_rules() -> void:
	var actor := WorldActor.new()
	actor.max_blood = 80.0
	actor.blood = 80.0
	actor.starting_skill_levels = {SkillRules.ATTRIBUTE_TOUGHNESS: 40}
	if actor.get_skill_level(SkillRules.ATTRIBUTE_TOUGHNESS) != 40:
		_fail("Expected starting Toughness override to apply before max blood validation")
	var expected_max_blood := SkillRules.get_max_blood_for_toughness(80.0, 40.0)
	if absf(actor.max_blood - expected_max_blood) > 0.01:
		_fail("Expected generic WorldActor max blood to scale from Toughness, got %.3f expected %.3f" % [actor.max_blood, expected_max_blood])
	if absf(actor.blood - actor.max_blood) > 0.01:
		_fail("Expected full generic WorldActor blood to refill to Toughness-scaled max at spawn")
	var wounded_blood := actor.max_blood * 0.5
	actor.blood = wounded_blood
	actor.set_skill_level(SkillRules.ATTRIBUTE_TOUGHNESS, 80)
	var expected_higher_max_blood := SkillRules.get_max_blood_for_toughness(80.0, 80.0)
	if absf(actor.max_blood - expected_higher_max_blood) > 0.01:
		_fail("Expected generic WorldActor max blood to refresh after Toughness changes")
	if absf(actor.blood - wounded_blood) > 0.01:
		_fail("Expected wounded blood value to stay wounded when Toughness changes, got %.3f expected %.3f" % [actor.blood, wounded_blood])
	actor.free()


func _validate_mining_speed_rules() -> void:
	var node := MiningResourceNode.new()
	node.resource_node_id = "validation.mining_speed"
	node.required_mining_level = 0
	node.slow_mine_seconds = 15.0
	node.fast_mine_seconds = 7.0
	node.levels_to_fast_speed = 30

	var actor := WorldActor.new()
	actor.set_skill_level(SkillRules.ATTRIBUTE_STRENGTH, SkillRules.DEFAULT_LEVEL)
	actor.set_skill_level(SkillRules.LABOR_MINING, 1)
	var fresh_copper_seconds := node.get_effective_mine_duration(actor)
	if absf(fresh_copper_seconds - 14.7333) > 0.05:
		_fail("Expected fresh copper mining to be near 15s, got %.3f" % fresh_copper_seconds)

	actor.set_skill_level(SkillRules.LABOR_MINING, 30)
	var skilled_copper_seconds := node.get_effective_mine_duration(actor)
	if absf(skilled_copper_seconds - 7.0) > 0.01:
		_fail("Expected mining 30 to reach copper skill speed floor, got %.3f" % skilled_copper_seconds)

	actor.set_skill_level(SkillRules.ATTRIBUTE_STRENGTH, 80)
	var strong_copper_seconds := node.get_effective_mine_duration(actor)
	if strong_copper_seconds >= skilled_copper_seconds or strong_copper_seconds < 6.2:
		_fail("Expected strength to give a small mining speed bonus, got %.3f from %.3f" % [strong_copper_seconds, skilled_copper_seconds])

	node.required_mining_level = 10
	actor.set_skill_level(SkillRules.ATTRIBUTE_STRENGTH, SkillRules.DEFAULT_LEVEL)
	actor.set_skill_level(SkillRules.LABOR_MINING, 9)
	if node.can_produce_ore_for(actor):
		_fail("Expected mining below ore unlock to fail production")
	if absf(node.get_effective_mine_duration(actor) - 15.0) > 0.01:
		_fail("Expected below-unlock mining attempts to use slow ore speed")
	actor.set_skill_level(SkillRules.LABOR_MINING, 40)
	if not node.can_produce_ore_for(actor):
		_fail("Expected ore to produce once mining reaches unlock")
	if absf(node.get_effective_mine_duration(actor) - 7.0) > 0.01:
		_fail("Expected ore to reach fast speed 30 levels past unlock")
	actor.queue_free()
	node.queue_free()


func _validate_mining_interaction_radius() -> void:
	var ore := ItemDefinition.new()
	ore.display_name = "Validation Radius Ore"
	ore.unit_weight = 1.0
	ore.grid_size = Vector2i(1, 1)

	var node := MiningResourceNode.new()
	node.name = "ValidationRadiusNode"
	node.resource_node_id = "validation.radius_node"
	node.item_definition = ore
	node.required_tool_tag = ""
	node.slow_mine_seconds = 1.0
	node.fast_mine_seconds = 1.0
	node.slot_distance = 0.0
	node.interaction_radius = 0.25
	root.add_child(node)

	var far_miner := HumanoidCharacter.new()
	far_miner.name = "ValidationFarMiner"
	far_miner.show_nameplate = false
	far_miner.fatigue_enabled = false
	root.add_child(far_miner)
	far_miner.position = Vector3(0.35, 0.0, 0.0)
	await process_frame
	far_miner._current_mining_node = node
	var far_xp_before := far_miner.get_skill_xp(SkillRules.LABOR_MINING)
	far_miner._process_mining(0.5)
	if far_miner._get_stored_mining_progress(node) > 0.001:
		_fail("Expected mining outside node interaction radius to make no progress")
	if far_miner.get_skill_xp(SkillRules.LABOR_MINING) > far_xp_before + 0.001:
		_fail("Expected mining outside node interaction radius to award no XP")

	var near_miner := HumanoidCharacter.new()
	near_miner.name = "ValidationNearMiner"
	near_miner.show_nameplate = false
	near_miner.fatigue_enabled = false
	root.add_child(near_miner)
	near_miner.position = Vector3(0.2, 0.0, 0.0)
	await process_frame
	near_miner._current_mining_node = node
	near_miner._process_mining(0.5)
	if near_miner._get_stored_mining_progress(node) <= 0.001:
		_fail("Expected mining inside node interaction radius to progress")

	far_miner.queue_free()
	near_miner.queue_free()
	node.queue_free()


func _validate_copper_ore_world_visual() -> void:
	if COPPER_ORE.world_scene == null:
		_fail("Expected copper ore to have a world scene")
		return
	if absf(COPPER_ORE.world_visual_height_meters - 0.14) > 0.001:
		_fail("Expected copper ore world visual height override to be 0.14m")

	var world_item := WORLD_ITEM_SCENE.instantiate() as WorldItem
	root.add_child(world_item)
	await process_frame
	world_item.setup(COPPER_ORE, 1)
	await process_frame
	if not (world_item is RigidBody3D):
		_fail("Expected dropped world items to use RigidBody3D physics")
	var model_root := world_item.get_node_or_null("ModelRoot")
	var bounds := _calculate_local_mesh_bounds(model_root)
	if bounds.size.y < 0.12 or bounds.size.y > 0.16:
		_fail("Expected dropped copper ore visual to be head-sized, got height %.3fm" % bounds.size.y)
	var collision_shape := world_item.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or not (collision_shape.shape is BoxShape3D):
		_fail("Expected dropped copper ore to rebuild a visual-bounds physics collider")
	world_item.place_on_ground_at(Vector3(1.0, 0.0, 1.0))
	var bottom_y := world_item.global_position.y + bounds.position.y
	if bottom_y <= 0.0 or bottom_y > 0.04:
		_fail("Expected dropped copper ore visual bottom above ground, got y=%.3f" % bottom_y)
	world_item.queue_free()

	var drop_root := Node3D.new()
	root.add_child(drop_root)
	var floor_body := StaticBody3D.new()
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	drop_root.add_child(floor_body)
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(10.0, 1.0, 10.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	var drop_source := OffsetDropOwner.new()
	drop_source.position = Vector3(2.0, -0.6, 2.0)
	drop_source.collision_bottom_local_y = 0.6
	drop_root.add_child(drop_source)
	var expected_drop_xz := Vector2(drop_source.position.x, drop_source.position.z - 0.9)
	var blocking_character := CharacterBody3D.new()
	blocking_character.name = "ValidationDropBlockingCharacter"
	blocking_character.add_to_group("humanoid_character")
	blocking_character.add_to_group("party_member")
	blocking_character.position = Vector3(expected_drop_xz.x, 0.0, expected_drop_xz.y)
	drop_root.add_child(blocking_character)
	var blocking_collision := CollisionShape3D.new()
	var blocking_capsule := CapsuleShape3D.new()
	blocking_capsule.radius = 0.45
	blocking_capsule.height = 1.1
	blocking_collision.shape = blocking_capsule
	blocking_collision.position.y = 0.95
	blocking_character.add_child(blocking_collision)
	await physics_frame
	var controller := PARTY_INVENTORY_CONTROLLER_SCRIPT.new() as PartyInventoryController
	controller.root_scene = drop_root
	controller.call("_spawn_world_item", drop_source, COPPER_ORE, 5)
	await process_frame
	var spawned_items: Array[WorldItem] = []
	for child in drop_root.get_children():
		if child is WorldItem:
			spawned_items.append(child as WorldItem)
	if spawned_items.size() != 1:
		_fail("Expected one physical projection for the dropped copper stack, got %d" % spawned_items.size())
	else:
		if spawned_items[0].quantity != 5:
			_fail("Expected dropped copper ore stack quantity to stay 5")
		var world_bounds := spawned_items[0].get_visual_world_bounds()
		if world_bounds.position.y < -0.001:
			_fail("Expected dropped copper ore visual bottom above floor, got y=%.3f" % world_bounds.position.y)
		var item_xz := Vector2(spawned_items[0].global_position.x, spawned_items[0].global_position.z)
		if item_xz.distance_to(expected_drop_xz) > 0.05:
			_fail("Expected dropped copper ore to stay beside source, got %.3f from target" % item_xz.distance_to(expected_drop_xz))
	var falling_item := WORLD_ITEM_SCENE.instantiate() as WorldItem
	drop_root.add_child(falling_item)
	falling_item.setup(COPPER_ORE, 1)
	falling_item.place_bottom_at(Vector3(-2.0, 0.0, 0.0), 1.5)
	await _wait_physics_frames(90)
	var falling_bounds := falling_item.get_visual_world_bounds()
	if falling_bounds.position.y > 0.25:
		_fail("Expected dropped copper ore physics to fall to the floor, got bottom y=%.3f" % falling_bounds.position.y)
	if falling_bounds.position.y < -0.08:
		_fail("Expected dropped copper ore physics to stop on the floor, got bottom y=%.3f" % falling_bounds.position.y)
	controller.free()
	drop_root.queue_free()


func _validate_weighted_initiative() -> void:
	var low_dex := InitiativeDummy.new()
	low_dex.name = "LowDex"
	low_dex.dexterity = 1.0
	var high_dex := InitiativeDummy.new()
	high_dex.name = "HighDex"
	high_dex.dexterity = 3.0
	root.add_child(low_dex)
	root.add_child(high_dex)
	var low_wins := 0
	var high_wins := 0
	for _index in range(400):
		var winner = COMBAT_COORDINATOR.choose_initiative_winner_for_validation([low_dex, high_dex])
		if winner == low_dex:
			low_wins += 1
		elif winner == high_dex:
			high_wins += 1
	COMBAT_COORDINATOR.release_character(low_dex)
	COMBAT_COORDINATOR.release_character(high_dex)
	low_dex.queue_free()
	high_dex.queue_free()
	if low_wins <= 0:
		_fail("Expected low dex participant to eventually win initiative contests")
	if high_wins <= low_wins:
		_fail("Expected high dex participant to win more initiative contests, low=%d high=%d" % [low_wins, high_wins])
	if low_wins < 45 or low_wins > 180:
		_fail("Expected 1-vs-3 dex initiative to stay near weighted range, low=%d high=%d" % [low_wins, high_wins])


func _validate_inventory_toggle_behavior() -> void:
	var layer := Control.new()
	layer.name = "ValidationInventoryWindowLayer"
	layer.size = Vector2(1280.0, 720.0)
	root.add_child(layer)

	var party_manager := PartyManager.new()
	root.add_child(party_manager)
	var mira := HumanoidCharacter.new()
	mira.name = "ValidationMira"
	mira.member_name = "Mira"
	mira.show_nameplate = false
	mira.fatigue_enabled = false
	root.add_child(mira)
	var tomas := HumanoidCharacter.new()
	tomas.name = "ValidationTomas"
	tomas.member_name = "Tomas"
	tomas.show_nameplate = false
	tomas.fatigue_enabled = false
	root.add_child(tomas)
	var container_owner := HumanoidCharacter.new()
	container_owner.name = "ValidationContainerOwner"
	container_owner.member_name = "Container"
	container_owner.show_nameplate = false
	container_owner.fatigue_enabled = false
	root.add_child(container_owner)
	await process_frame
	mira.set_player_party_member(true)
	tomas.set_player_party_member(true)
	party_manager.set_party_members([mira, tomas])
	party_manager.select_only(mira)

	var controller := PARTY_INVENTORY_CONTROLLER_SCRIPT.new() as PartyInventoryController
	controller.party_manager = party_manager
	controller.inventory_window_layer = layer
	controller.open_selected_inventory()
	await process_frame
	if not _is_live_inventory_window_for(controller.primary_character_window, mira):
		_fail("Expected inventory toggle to open selected Mira inventory")
	if _count_live_inventory_windows(layer) != 1:
		_fail("Expected one inventory window after first inventory toggle")

	controller.call("_open_secondary_inventory", container_owner)
	await process_frame
	if not _is_live_inventory_window_for(controller.secondary_inventory_window, container_owner):
		_fail("Expected validation secondary inventory to open")
	controller.open_selected_inventory()
	await process_frame
	if controller.primary_character_window != null or controller.secondary_inventory_window != null:
		_fail("Expected pressing inventory toggle for the same selected owner to close primary and secondary windows")
	if _count_live_inventory_windows(layer) != 0:
		_fail("Expected all inventory windows to be gone after same-owner toggle close")

	controller.open_selected_inventory()
	await process_frame
	party_manager.select_only(tomas)
	controller.open_selected_inventory()
	await process_frame
	if not _is_live_inventory_window_for(controller.primary_character_window, tomas):
		_fail("Expected inventory toggle to switch to newly selected Tomas inventory")
	if _count_live_inventory_windows(layer) != 1:
		_fail("Expected one inventory window after switching selected owner")

	controller.call("_close_all_inventory_windows")
	await process_frame
	mira.position = Vector3.ZERO
	tomas.position = Vector3(3.0, 0.0, 0.0)
	controller.open_inventory_pair(mira, tomas)
	await process_frame
	controller.call("_enforce_open_inventory_context")
	if _count_live_inventory_windows(layer) != 2:
		_fail("Expected in-range paired inventories to stay open")
	tomas.position = Vector3(8.0, 0.0, 0.0)
	controller.call("_enforce_open_inventory_context")
	await process_frame
	if _count_live_inventory_windows(layer) != 0:
		_fail("Expected paired inventories to close when owners move out of range")

	party_manager.select_only(mira)
	mira.position = Vector3.ZERO
	controller.open_selected_inventory()
	await process_frame
	mira.position = Vector3(12.0, 0.0, 0.0)
	controller.call("_enforce_open_inventory_context")
	if _count_live_inventory_windows(layer) != 1:
		_fail("Expected own inventory to stay open while only its owner moves")
	mira.assign_attack_target(tomas)
	controller.call("_enforce_open_inventory_context")
	await process_frame
	if _count_live_inventory_windows(layer) != 0:
		_fail("Expected open inventories to close when an involved party member enters combat")
	mira.stop_attack_assignment()
	tomas.stop_attack_assignment()

	controller.open_inventory_pair(mira, container_owner)
	await process_frame
	container_owner.assign_attack_target(mira)
	controller.call("_enforce_open_inventory_context")
	await process_frame
	if _count_live_inventory_windows(layer) != 0:
		_fail("Expected paired inventories to close when the secondary owner enters combat")
	container_owner.stop_attack_assignment()
	mira.stop_attack_assignment()

	controller.call("_close_all_inventory_windows")
	mira.position = Vector3.ZERO
	tomas.position = Vector3(10.0, 0.0, 0.0)
	party_manager.select_only(mira)
	var interaction_controller := WorldInteractionController.new()
	root.add_child(interaction_controller)
	interaction_controller.party_manager = party_manager
	interaction_controller.inventory_controller = controller
	interaction_controller.context_member = tomas
	interaction_controller.call("_on_context_menu_id_pressed", WorldInteractionController.ACTION_INVENTORY)
	await process_frame
	if _count_live_inventory_windows(layer) != 0:
		_fail("Expected far party-member trade to wait for reach before opening inventories")
	if mira.get("_current_trade_target") != tomas:
		_fail("Expected far party-member trade to assign a trade target")
	interaction_controller.call("_on_party_member_trade_target_reached", mira, tomas)
	await process_frame
	if not _is_live_inventory_window_for(controller.primary_character_window, mira) or not _is_live_inventory_window_for(controller.secondary_inventory_window, tomas):
		_fail("Expected party-member trade reached callback to open paired inventories")
	interaction_controller.queue_free()

	controller.call("_close_all_inventory_windows")
	controller.free()
	layer.queue_free()
	party_manager.queue_free()
	mira.queue_free()
	tomas.queue_free()
	container_owner.queue_free()


func _validate_mining_pickaxe_requirement() -> void:
	var ore := ItemDefinition.new()
	ore.display_name = "Validation Copper"
	ore.unit_weight = 1.0
	ore.grid_size = Vector2i(1, 1)
	ore.max_stack = 1

	var node := MiningResourceNode.new()
	node.name = "ValidationPickaxeCopper"
	node.resource_node_id = "validation.pickaxe_copper"
	node.item_definition = ore
	node.slow_mine_seconds = 1.0
	node.fast_mine_seconds = 1.0
	node.slot_distance = 0.0
	root.add_child(node)

	var no_pick_miner := HumanoidCharacter.new()
	no_pick_miner.name = "ValidationNoPickMiner"
	no_pick_miner.show_nameplate = false
	no_pick_miner.fatigue_enabled = false
	root.add_child(no_pick_miner)
	await process_frame
	no_pick_miner._current_mining_node = node
	var no_pick_xp_before := no_pick_miner.get_skill_xp(SkillRules.LABOR_MINING)
	no_pick_miner._process_mining(1.2)
	if no_pick_miner.get_skill_xp(SkillRules.LABOR_MINING) > no_pick_xp_before + 0.001:
		_fail("Expected mining without a pickaxe to award no XP")
	if no_pick_miner.has_mining_assignment():
		_fail("Expected mining without a pickaxe to stop the mining assignment")

	var swap_miner := HumanoidCharacter.new()
	swap_miner.name = "ValidationPickMiner"
	swap_miner.show_nameplate = false
	swap_miner.inventory_columns = 4
	swap_miner.inventory_rows = 4
	swap_miner.fatigue_enabled = false
	root.add_child(swap_miner)
	await process_frame
	var old_weapon := ItemDefinition.new()
	old_weapon.display_name = "Validation Sword"
	old_weapon.grid_size = Vector2i(1, 1)
	old_weapon.unit_weight = 1.0
	old_weapon.equip_slot = ItemDefinition.EQUIP_SLOT_WEAPON
	swap_miner.equip_item_to_slot(old_weapon, ItemDefinition.EQUIP_SLOT_WEAPON)
	swap_miner.inventory.add_item(PICKAXE)
	swap_miner.assign_mining_resource(node, false)
	if swap_miner.get_equipped_item(ItemDefinition.EQUIP_SLOT_WEAPON) != PICKAXE:
		_fail("Expected mining assignment to auto-equip inventory pickaxe")
	if swap_miner.inventory.count_item(old_weapon) != 1:
		_fail("Expected mining auto-equip to stow previous weapon in inventory")

	var blocked_miner := HumanoidCharacter.new()
	blocked_miner.name = "ValidationBlockedPickMiner"
	blocked_miner.show_nameplate = false
	blocked_miner.inventory_columns = 2
	blocked_miner.inventory_rows = 3
	blocked_miner.fatigue_enabled = false
	root.add_child(blocked_miner)
	await process_frame
	var oversized_weapon := ItemDefinition.new()
	oversized_weapon.display_name = "Oversized Validation Weapon"
	oversized_weapon.grid_size = Vector2i(3, 3)
	oversized_weapon.unit_weight = 1.0
	oversized_weapon.equip_slot = ItemDefinition.EQUIP_SLOT_WEAPON
	blocked_miner.equip_item_to_slot(oversized_weapon, ItemDefinition.EQUIP_SLOT_WEAPON)
	blocked_miner.inventory.add_item(PICKAXE)
	blocked_miner.assign_mining_resource(node, false)
	if blocked_miner.get_equipped_item(ItemDefinition.EQUIP_SLOT_WEAPON) != oversized_weapon:
		_fail("Expected mining to keep current weapon equipped when it cannot be stowed")
	if blocked_miner.has_mining_assignment():
		_fail("Expected mining to be blocked when current weapon cannot be stowed")
	if blocked_miner.inventory.count_item(PICKAXE) != 1:
		_fail("Expected blocked mining swap to return pickaxe to inventory")

	var visual_miner := HumanoidCharacter.new()
	visual_miner.name = "ValidationAnimationMiner"
	visual_miner.show_nameplate = false
	visual_miner.fatigue_enabled = false
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.1
	collision.shape = capsule
	collision.position.y = 0.95
	visual_miner.add_child(collision)
	var body_mesh := MeshInstance3D.new()
	body_mesh.name = "BodyMesh"
	body_mesh.mesh = CapsuleMesh.new()
	body_mesh.position.y = 0.95
	visual_miner.add_child(body_mesh)
	root.add_child(visual_miner)
	await process_frame
	var body := visual_miner.get_body_projection()
	var animation_player: AnimationPlayer = body.get_primary_animation_player() if body != null else null
	if animation_player == null or not animation_player.has_animation("Mining"):
		_fail("Expected humanoid character animation library to include Mining")
	visual_miner._current_mining_node = node
	visual_miner._mining_active = true
	visual_miner._update_character_animation(0.1)
	if body == null or body.get_current_clip() != "Mining":
		_fail("Expected active mining to play Mining")

	no_pick_miner.queue_free()
	swap_miner.queue_free()
	blocked_miner.queue_free()
	visual_miner.queue_free()
	node.queue_free()


func _validate_scavenging_rules() -> void:
	var useful_item := ItemDefinition.new()
	useful_item.display_name = "Validation Scrap"
	useful_item.grid_size = Vector2i(1, 1)
	useful_item.unit_weight = 1.0
	useful_item.max_stack = 1

	var low_actor := WorldActor.new()
	var high_actor := WorldActor.new()
	low_actor.set_skill_level(SkillRules.LABOR_SCAVENGING, 1)
	high_actor.set_skill_level(SkillRules.LABOR_SCAVENGING, 45)
	high_actor.set_skill_level(SkillRules.ATTRIBUTE_PERCEPTION, 30)
	high_actor.set_skill_level(SkillRules.ATTRIBUTE_DEXTERITY, 30)
	var chance_node := ScavengingResourceNode.new()
	chance_node.scavenging_difficulty = 25
	var low_chance := chance_node.get_useful_loot_chance(low_actor)
	var high_chance := chance_node.get_useful_loot_chance(high_actor)
	if low_chance <= 0.0:
		_fail("Expected low scavenging useful chance to remain possible")
	if high_chance <= low_chance:
		_fail("Expected high scavenging useful chance to exceed low chance")
	low_actor.queue_free()
	high_actor.queue_free()
	chance_node.queue_free()

	var scavenger := HumanoidCharacter.new()
	scavenger.name = "ValidationScavenger"
	scavenger.show_nameplate = false
	scavenger.inventory_columns = 1
	scavenger.inventory_rows = 1
	scavenger.max_carry_weight = 0.0
	scavenger.fatigue_enabled = false
	root.add_child(scavenger)
	await process_frame

	var node := ScavengingResourceNode.new()
	node.name = "ValidationScrapPile"
	node.resource_node_id = "validation.scrap_pile"
	node.randomize_charges_on_ready = false
	node.current_charges = 1
	node.slow_scavenge_seconds = 1.0
	node.fast_scavenge_seconds = 1.0
	node.slot_distance = 0.0
	node.min_useful_chance = 1.0
	node.max_useful_chance = 1.0
	node.useful_loot = [useful_item]
	var label := Label3D.new()
	label.name = "Label3D"
	node.add_child(label)
	root.add_child(node)
	await process_frame

	scavenger._current_scavenging_node = node
	var xp_before := scavenger.get_skill_xp(SkillRules.LABOR_SCAVENGING)
	scavenger._process_scavenging(1.2)
	var xp_after := scavenger.get_skill_xp(SkillRules.LABOR_SCAVENGING)
	if xp_after <= xp_before:
		_fail("Expected scavenging attempt to award XP")
	if node.current_charges != 0:
		_fail("Expected scavenging attempt to consume exactly one charge")
	if not node.is_depleted():
		_fail("Expected empty scrap pile to be depleted")
	if not label.text.contains("Depleted"):
		_fail("Expected depleted scrap pile label to say Depleted")
	var dropped_item_count := 0
	var dropped_items: Array[WorldItem] = []
	for child in root.get_children():
		if child is WorldItem and (child as WorldItem).item_definition == useful_item:
			dropped_items.append(child as WorldItem)
			dropped_item_count += 1
	if dropped_item_count <= 0:
		_fail("Expected full scavenger inventory to drop loot beside the pile")
	for dropped_item in dropped_items:
		dropped_item.queue_free()
	scavenger.queue_free()
	node.queue_free()


func _validate_locked_mining_attempt_trains_without_ore() -> void:
	var ore := ItemDefinition.new()
	ore.display_name = "Validation Locked Ore"
	ore.unit_weight = 1.0
	ore.grid_size = Vector2i(1, 1)
	ore.max_stack = 1

	var miner := HumanoidCharacter.new()
	miner.name = "ValidationLockedMiner"
	miner.show_nameplate = false
	miner.fatigue_enabled = false
	root.add_child(miner)
	await process_frame
	miner.set_skill_level(SkillRules.LABOR_MINING, 1)
	miner.set_skill_level(SkillRules.ATTRIBUTE_STRENGTH, SkillRules.DEFAULT_LEVEL)

	var node := MiningResourceNode.new()
	node.name = "ValidationLockedOre"
	node.resource_node_id = "validation.locked_ore"
	node.item_definition = ore
	node.required_tool_tag = ""
	node.required_mining_level = 10
	node.slow_mine_seconds = 1.0
	node.fast_mine_seconds = 0.5
	node.slot_distance = 0.0
	root.add_child(node)
	await process_frame

	miner._current_mining_node = node
	var xp_before := miner.get_skill_xp(SkillRules.LABOR_MINING)
	miner._process_mining(1.2)
	var xp_after := miner.get_skill_xp(SkillRules.LABOR_MINING)
	if miner.inventory.count_item(ore) != 0:
		_fail("Expected locked mining attempt to produce no ore")
	if xp_after <= xp_before:
		_fail("Expected locked mining attempt to train mining")
	if miner._get_stored_mining_progress(node) > 0.001:
		_fail("Expected completed locked mining attempt to reset progress")
	miner.queue_free()
	node.queue_free()


func _validate_stalled_mining_awards_no_xp() -> void:
	var ore := ItemDefinition.new()
	ore.display_name = "Validation Ore"
	ore.unit_weight = 1.0
	ore.grid_size = Vector2i(1, 1)
	ore.max_stack = 1

	var miner := HumanoidCharacter.new()
	miner.name = "ValidationMiner"
	miner.show_nameplate = false
	miner.inventory_columns = 1
	miner.inventory_rows = 1
	miner.max_carry_weight = 0.0
	miner.fatigue_enabled = false
	root.add_child(miner)
	await process_frame

	var node := MiningResourceNode.new()
	node.name = "ValidationCopper"
	node.resource_node_id = "validation.stalled_copper"
	node.item_definition = ore
	node.required_tool_tag = ""
	node.slow_mine_seconds = 1.0
	node.fast_mine_seconds = 1.0
	node.slot_distance = 0.0
	root.add_child(node)
	await process_frame

	miner._current_mining_node = node
	miner._store_mining_progress(node, 1.0)
	var xp_before := miner.get_skill_xp(SkillRules.LABOR_MINING)
	for _index in range(6):
		miner._process_mining(0.5)
	var xp_after := miner.get_skill_xp(SkillRules.LABOR_MINING)
	if xp_after > xp_before + 0.001:
		_fail("Expected stalled full-inventory mining to award no XP, before=%.3f after=%.3f" % [xp_before, xp_after])
	if miner._mining_active:
		_fail("Expected stalled full-inventory mining to mark mining inactive")
	miner.queue_free()
	node.queue_free()


func _validate_skills_window_live_update() -> void:
	root.size = Vector2i(1280, 720)
	var actor := WorldActor.new()
	actor.name = "SkillWindowActor"
	var window := CHARACTER_SKILLS_WINDOW_SCRIPT.new() as Control
	root.add_child(actor)
	root.add_child(window)
	window.call("show_for_actor", actor)
	await process_frame
	var columns_root := window.get("columns_root") as HBoxContainer
	if columns_root == null:
		_fail("Expected skills window to build a two-column section root")
	elif columns_root.get_child_count() != 2:
		_fail("Expected skills window to use two columns, got %d" % columns_root.get_child_count())
	else:
		for section_path in [
			"SkillsColumn1/CoreAttributesSection",
			"SkillsColumn1/CombatSection",
			"SkillsColumn1/SubterfugeSection",
			"SkillsColumn2/MovementSection",
			"SkillsColumn2/LaborSection",
			"SkillsColumn2/CraftSection",
			"SkillsColumn2/KnowledgeTechSection",
		]:
			var section_panel := columns_root.get_node_or_null(section_path) as Control
			if section_panel == null:
				_fail("Expected skills window section missing: %s" % section_path)
			elif section_panel.size_flags_horizontal != Control.SIZE_EXPAND_FILL or section_panel.size_flags_vertical != Control.SIZE_EXPAND_FILL:
				_fail("Expected skills window section to stretch to its borders: %s" % section_path)
	if _node_tree_contains_type(window, "ScrollContainer"):
		_fail("Skills window should not require a scrolling skill list")
	var title_bar := window.get("title_bar") as Control
	var title_padding := title_bar.get_node_or_null("TitlePadding") as MarginContainer if title_bar != null else null
	if title_padding == null:
		_fail("Expected skills window title bar to include name padding")
	elif title_padding.get_theme_constant("margin_left") < 10 or title_padding.get_theme_constant("margin_right") < 10:
		_fail("Expected skills window title padding to keep actor names off the title border")
	var start_position := window.position
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.global_position = start_position + Vector2(24.0, 18.0)
	window.call("_on_title_bar_gui_input", press)
	var motion := InputEventMouseMotion.new()
	motion.global_position = press.global_position + Vector2(90.0, 54.0)
	window.call("_on_title_bar_gui_input", motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.global_position = motion.global_position
	window.call("_on_title_bar_gui_input", release)
	if window.position.distance_to(start_position) < 10.0:
		_fail("Expected skills window title bar drag to move the window")
	var controls_by_skill: Dictionary = window.get("_row_controls_by_skill")
	var mining_controls: Dictionary = controls_by_skill.get(SkillRules.LABOR_MINING, {})
	var xp_label := mining_controls.get("xp_label") as Label
	if xp_label == null:
		_fail("Expected skills window to build a mining XP row")
	else:
		var before_text := xp_label.text
		actor.add_skill_xp(SkillRules.LABOR_MINING, 12.0, "validation_live_window")
		await _wait_frames(12)
		if xp_label.text == before_text:
			_fail("Expected visible skills window to update mining XP live")
	window.queue_free()
	actor.queue_free()


func _validate_inspected_npc_skills_button() -> void:
	root.size = Vector2i(1280, 720)
	var hud := GAME_HUD_SCENE.instantiate() as CanvasLayer
	if hud == null:
		_fail("Expected game HUD scene to instantiate for NPC skills validation")
		return
	hud.name = "ValidationNpcSkillsHUD"
	root.add_child(hud)
	var npc := HumanoidCharacter.new()
	npc.name = "ValidationRustdeadStats"
	npc.member_name = "Ancient Rustdead"
	npc.faction_name = "Rustdead"
	npc.show_nameplate = false
	npc.fatigue_enabled = false
	npc.starting_skill_levels = {SkillRules.ATTRIBUTE_TOUGHNESS: 80, SkillRules.COMBAT_UNARMED: 80}
	root.add_child(npc)
	var controller := HUMANOID_DETAILS_CONTROLLER_SCRIPT.new() as HumanoidDetailsController
	controller.name = "ValidationHumanoidDetailsController"
	root.add_child(controller)
	controller.initialize(BootstrapContext.new(root, hud))
	await _wait_frames(3)
	controller.inspect_target(npc)
	await _wait_frames(2)
	var skills_button := hud.get_node_or_null("HudLayout/BottomHud/InspectorSlot/HumanoidDetailsPanel/Margin/DetailsVBox/ActionRow/PrimaryActionButton") as Button
	if skills_button == null:
		_fail("Expected inspected NPC details panel to expose a primary action button")
	elif skills_button.text != "Skills" or not skills_button.visible or skills_button.disabled:
		_fail("Expected inspected NPC Skills button to be visible and enabled, got text=%s visible=%s disabled=%s" % [skills_button.text, str(skills_button.visible), str(skills_button.disabled)])
	else:
		skills_button.pressed.emit()
		await _wait_frames(2)
		var skills_window := hud.get_node_or_null("CharacterSkillsWindow") as Control
		if skills_window == null or not skills_window.visible:
			_fail("Expected inspected NPC Skills button to open the skills window")
		else:
			var title_label := skills_window.get("title_label") as Label
			if title_label == null or not title_label.text.contains("Ancient Rustdead"):
				_fail("Expected inspected NPC skills window title to use NPC display name")
	controller.queue_free()
	npc.queue_free()
	hud.queue_free()


func _node_tree_contains_type(node: Node, class_name_text: String) -> bool:
	if node == null:
		return false
	if node.is_class(class_name_text):
		return true
	for child in node.get_children():
		if _node_tree_contains_type(child, class_name_text):
			return true
	return false


func _wait_frames(frames: int) -> void:
	for _index in range(frames):
		await process_frame


func _wait_physics_frames(frames: int) -> void:
	for _index in range(frames):
		await physics_frame


func _is_live_inventory_window_for(window, owner) -> bool:
	return window is InventoryWindow and is_instance_valid(window) and not window.is_queued_for_deletion() and window.inventory_owner == owner


func _count_live_inventory_windows(parent: Node) -> int:
	var count := 0
	for child in parent.get_children():
		if child is InventoryWindow and is_instance_valid(child) and not child.is_queued_for_deletion():
			count += 1
	return count


func _calculate_local_mesh_bounds(root_node: Node) -> AABB:
	var result := {
		"has_bounds": false,
		"bounds": AABB(),
	}
	if root_node != null:
		_accumulate_local_mesh_bounds(root_node, Transform3D.IDENTITY, result)
	return result["bounds"]


func _accumulate_local_mesh_bounds(node: Node, parent_transform: Transform3D, result: Dictionary) -> void:
	var local_transform := parent_transform
	if node is Node3D:
		local_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_bounds := _transform_aabb((node as MeshInstance3D).mesh.get_aabb(), local_transform)
		if result["has_bounds"]:
			result["bounds"] = (result["bounds"] as AABB).merge(mesh_bounds)
		else:
			result["bounds"] = mesh_bounds
			result["has_bounds"] = true
	for child in node.get_children():
		_accumulate_local_mesh_bounds(child, local_transform, result)


func _transform_aabb(bounds: AABB, transform: Transform3D) -> AABB:
	var first := true
	var transformed_bounds := AABB()
	for x in [bounds.position.x, bounds.position.x + bounds.size.x]:
		for y in [bounds.position.y, bounds.position.y + bounds.size.y]:
			for z in [bounds.position.z, bounds.position.z + bounds.size.z]:
				var point := transform * Vector3(x, y, z)
				if first:
					transformed_bounds = AABB(point, Vector3.ZERO)
					first = false
				else:
					transformed_bounds = transformed_bounds.expand(point)
	return transformed_bounds


func _fail(message: String) -> void:
	_failures.append(message)
