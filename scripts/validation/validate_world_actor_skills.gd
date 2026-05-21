extends SceneTree

const COMBAT_COORDINATOR = preload("res://scripts/characters/combat_coordinator.gd")
const CHARACTER_SKILLS_WINDOW_SCRIPT = preload("res://scripts/ui/character_skills_window.gd")

class InitiativeDummy:
	extends Node3D
	var dexterity := 1.0

	func get_stat_value(stat_name: String) -> float:
		return dexterity if stat_name == "dexterity" else 0.0

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_catalog()
	_validate_progression()
	_validate_mining_speed_rules()
	_validate_world_actor_api()
	_validate_weighted_initiative()
	await _validate_scavenging_rules()
	await _validate_locked_mining_attempt_trains_without_ore()
	await _validate_stalled_mining_awards_no_xp()
	await _validate_skills_window_live_update()
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
	if SkillRules.get_xp_to_next_level(10) <= SkillRules.get_xp_to_next_level(1):
		_fail("Expected level 10 XP requirement to exceed level 1")
	if SkillRules.get_xp_to_next_level(80) <= SkillRules.get_xp_to_next_level(40):
		_fail("Expected level 80 XP requirement to exceed level 40")
	var first_delta := SkillRules.get_xp_to_next_level(2) - SkillRules.get_xp_to_next_level(1)
	var second_delta := SkillRules.get_xp_to_next_level(3) - SkillRules.get_xp_to_next_level(2)
	if second_delta <= first_delta:
		_fail("Expected smooth XP curve to get gradually harder every level")
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


func _validate_world_actor_api() -> void:
	var actor := WorldActor.new()
	actor.starting_skill_levels = {SkillRules.ATTRIBUTE_PERCEPTION: 30}
	if actor.get_skill_level(SkillRules.ATTRIBUTE_STRENGTH) != 1:
		_fail("Expected generic actor default skill level to be 1")
	if actor.get_skill_level(SkillRules.ATTRIBUTE_PERCEPTION) != 30:
		_fail("Expected starting skill level override to apply")
	actor.add_skill_xp(SkillRules.MOVEMENT_RUNNING, SkillRules.get_xp_to_next_level(1), "validation")
	if actor.get_skill_level(SkillRules.MOVEMENT_RUNNING) <= 1:
		_fail("Expected WorldActor.add_skill_xp to level a skill")
	actor.queue_free()


func _validate_mining_speed_rules() -> void:
	var node := MiningResourceNode.new()
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
	for child in root.get_children():
		if child is WorldItem and (child as WorldItem).item_definition == useful_item:
			dropped_item_count += 1
	if dropped_item_count <= 0:
		_fail("Expected full scavenger inventory to drop loot beside the pile")
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
	node.item_definition = ore
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
	node.item_definition = ore
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
	var actor := WorldActor.new()
	actor.name = "SkillWindowActor"
	var window := CHARACTER_SKILLS_WINDOW_SCRIPT.new() as Control
	root.add_child(actor)
	root.add_child(window)
	window.call("show_for_actor", actor)
	await process_frame
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


func _wait_frames(frames: int) -> void:
	for _index in range(frames):
		await process_frame


func _fail(message: String) -> void:
	_failures.append(message)
