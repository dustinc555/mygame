extends "res://tests/validation/test_case.gd"

const DEMO_WORLD_SCENE_PATH := "res://scenes/worlds/demo_world/demo_world.tscn"
const DEMO_WORLD_DEFINITION_PATH := "res://features/world_sim/resources/worlds/demo_world/demo_world.tres"
const DEMO_ZONE_DEFINITION_PATH := "res://features/world_sim/resources/zones/demo_zone/demo_zone.tres"
const POPULATION_APPEARANCE_PROFILE_DIR := "res://features/world_sim/resources/population_appearance_profiles"
const BANDAGE_ITEM_PATH := "res://features/inventory/resources/items/bandage.tres"
const AI_UTILITY_ADAPTER_PATH := "res://features/ai/bridge/ai_utility_adapter.gd"
const COMBAT_COORDINATOR_PATH := "res://features/combat/bridge/combat_coordinator.gd"
const SKIN_TEXTURE_BUILDER_PATH := "res://features/actors/projection/appearance/skin_texture_builder.gd"
const HUMAN_RACE_ID := "human"
const RUSTDEAD_RACE_ID := "rustdead"

var _failures: Array[String] = []
var _scene: Node
var _world_definition: Resource
var _zone_definition: Resource
var _bandage_item: Resource


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	_load_validation_resources()
	var demo_world_scene := load(DEMO_WORLD_SCENE_PATH) as PackedScene
	if demo_world_scene == null:
		_fail("Demo world scene should load from %s" % DEMO_WORLD_SCENE_PATH)
	_scene = demo_world_scene.instantiate() if demo_world_scene != null else null
	demo_world_scene = null
	if _scene == null:
		await _cleanup_scene()
		_print_failures_and_quit()
		return
	_scene.auto_open_character_creator = false
	root.add_child(_scene)
	current_scene = _scene
	await _wait_for_world()
	_validate_world_definition()
	_validate_population_appearance_profiles()
	_validate_loaded_towns()
	_validate_town_guard_burn_support()
	_validate_non_rustdead_humanoids()
	_validate_faction_relations()
	_validate_slavery_law_flag()
	await _cleanup_scene()
	if _failures.is_empty():
		print("DEMO_WORLD_TOPOLOGY_OK")
		quit(0)
		return
	_print_failures_and_quit()


func _print_failures_and_quit() -> void:
	for failure in _failures:
		push_error(failure)
	print("DEMO_WORLD_TOPOLOGY_FAILED count=%d" % _failures.size())
	quit(1)


func _load_validation_resources() -> void:
	_world_definition = load(DEMO_WORLD_DEFINITION_PATH) as Resource
	if _world_definition == null:
		_fail("Demo world definition should load from %s" % DEMO_WORLD_DEFINITION_PATH)
	_zone_definition = load(DEMO_ZONE_DEFINITION_PATH) as Resource
	if _zone_definition == null:
		_fail("Demo zone definition should load from %s" % DEMO_ZONE_DEFINITION_PATH)
	_bandage_item = load(BANDAGE_ITEM_PATH) as Resource
	if _bandage_item == null:
		_fail("Bandage item should load from %s" % BANDAGE_ITEM_PATH)


func _wait_for_world() -> void:
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		var towns := get_nodes_in_group("settlement_town")
		var nav := get_first_node_in_group("world_navigation_controller")
		if towns.size() != 3 or nav == null or not nav.is_idle() or nav.is_initial_navigation_pending() or paused:
			continue
		# Assignment projections are distance-driven independently of the
		# resident full_town policy. Ask the production assignment realizer for
		# the authored guards explicitly; no fake roster/equipment is injected.
		var realization := get_first_node_in_group("population_realization_controller")
		if realization != null:
			realization.set_process(false)
		var settlements := get_first_node_in_group("settlement_controller")
		for town in towns:
			var subjects := 0
			var id: String = town.get_settlement_id()
			for slot in settlements.get_assignment_slots_for_realization(id):
				if str(slot.get("role_id", "")).contains("guard") and bool(slot.get("filled", false)):
					if settlements.realize_assignment_slot(id, str(slot.assignment_domain), str(slot.slot_id)):
						subjects += 1
			if subjects == 0:
				_fail("%s has no authored filled guard assignment to realize" % id)
		print("DEMO_TOPOLOGY_READY towns=%d actors=%d tiles=%d" % [towns.size(), get_nodes_in_group("humanoid_character").size(), nav.baked_tile_count()])
		return
	_fail("Demo navigation and three towns did not become ready within 60 seconds")


func _validate_world_definition() -> void:
	if _world_definition == null or _zone_definition == null:
		return
	if str(_world_definition.call("get_id")) != "demo_world":
		_fail("Demo world definition should use stable id demo_world")
	if (_world_definition.get("zone_definitions") as Array).size() != 1:
		_fail("Demo world should define exactly one zone")
	if str(_zone_definition.call("get_id")) != "demo_zone":
		_fail("Demo zone definition should use stable id demo_zone")
	if (_zone_definition.get("settlement_placements") as Array).size() != 3:
		_fail("Demo zone should define exactly three settlement placements")
	if (_zone_definition.get("starting_relations") as Array).size() != 3:
		_fail("Demo zone should define exactly three starting relations")
	var settlement_ids := {}
	for placement in _zone_definition.get("settlement_placements"):
		var placement_id := str(placement.call("get_id")) if placement != null and placement.has_method("get_id") else ""
		if placement_id.is_empty():
			_fail("Settlement placement should have a stable id")
		if settlement_ids.has(placement_id):
			_fail("Duplicate settlement placement id %s" % placement_id)
		settlement_ids[placement_id] = true
		var definition := placement.get("settlement_definition") as Resource
		if definition == null:
			_fail("Placement %s should reference a settlement definition" % placement_id)
		elif definition.get("faction_definition") == null:
			_fail("Settlement %s should reference an owning faction" % placement_id)
		if placement.get("town_scene") == null:
			_fail("Placement %s should reference a packaged town scene" % placement_id)


func _validate_loaded_towns() -> void:
	var towns := _scene.get_node_or_null("Zones/DemoZone/Towns")
	if towns == null:
		_fail("Demo zone should have a runtime Towns root")
		return
	for town_name in ["SurfCity", "EastRaidersCamp", "ParadiseHills"]:
		var town := towns.get_node_or_null(town_name)
		if town == null:
			_fail("Town %s should be loaded by ZoneLoader" % town_name)
			continue
		_validate_town_contract(town, town_name)


func _validate_town_guard_burn_support() -> void:
	var towns := _scene.get_node_or_null("Zones/DemoZone/Towns")
	if towns == null:
		return
	for town_name in ["SurfCity", "EastRaidersCamp", "ParadiseHills"]:
		var town := towns.get_node_or_null(town_name)
		if town == null:
			continue
		var furnace := town.get_node_or_null("DynamicFacilities/BodyFurnace")
		if furnace == null or not furnace.is_in_group("body_furnace"):
			_fail("%s should include a body furnace in DynamicFacilities" % town_name)
		var guards := town.get_node_or_null("Guards")
		if guards == null or guards.get_child_count() == 0:
			_fail("%s must realize guard subjects" % town_name)
			continue
		var guard_subjects := 0
		for child in guards.get_children():
			var guard := child as HumanoidCharacter
			if guard == null:
				continue
			guard_subjects += 1
			if not guard.is_auto_heal_enabled():
				_fail("%s guard %s should default Auto Heal on" % [town_name, guard.name])

			if guard.inventory == null or guard.inventory.count_item(_bandage_item) < 1:
				_fail("%s guard %s should start with bandages" % [town_name, guard.name])
			# Current guard assignments use the soldier character type (weapon,
			# shield, bandage), not the retired inline two-flask roster. The
			# authored furnace above supplies the default corpse-burn route.
			var soldier := load("res://features/world_sim/resources/character_types/soldier.tres") as Resource
			for item in soldier.starting_equipment:
				if not guard.get_equipment().get_equipped_items().values().has(item) and (guard.inventory == null or guard.inventory.count_item(item) < 1):
					_fail("%s guard %s lacks soldier loadout item %s" % [town_name, guard.name, item.resource_path])
		if guard_subjects == 0:
			_fail("%s has no real humanoid guard subject" % town_name)


func _validate_population_appearance_profiles() -> void:
	var checked_profiles := 0
	var files := Array(DirAccess.get_files_at(POPULATION_APPEARANCE_PROFILE_DIR))
	files.sort()
	for file_name_value in files:
		var file_name := str(file_name_value)
		if not file_name.ends_with(".tres"):
			continue
		var path := "%s/%s" % [POPULATION_APPEARANCE_PROFILE_DIR, file_name]
		var profile := load(path) as Resource
		if profile == null or not profile.has_method("create_appearance"):
			_fail("Invalid population appearance profile: %s" % path)
			continue
		var allowed_races: Array = profile.get("allowed_races") if profile.get("allowed_races") is Array else []
		if not allowed_races.is_empty():
			continue
		checked_profiles += 1
		var rng := RandomNumberGenerator.new()
		rng.seed = 1001
		for sample_index in range(8):
			var appearance := profile.call("create_appearance", rng) as Resource
			var race := appearance.get("character_race") as Resource if appearance != null else null
			var race_id := _race_id(race)
			if race_id != HUMAN_RACE_ID:
				_fail("Population appearance profile %s should default to human race, got %s on sample %d" % [path, race_id, sample_index + 1])
				break

	if checked_profiles == 0:
		_fail("No default-race profiles were sampled")


func _validate_non_rustdead_humanoids() -> void:
	var subjects := get_nodes_in_group("humanoid_character")
	if subjects.is_empty():
		_fail("Race checks require realized humanoid subjects")
	for node in subjects:
		var actor := node as HumanoidCharacter
		if actor == null:
			continue
		var faction_name := str(actor.get("faction_name"))
		var race_id := _race_id(actor.appearance_data.character_race if actor.appearance_data != null else null)
		if faction_name == "Rustdead":
			if race_id != RUSTDEAD_RACE_ID:
				_fail("Rustdead actor %s should use Rustdead race, got %s" % [actor.name, race_id])
			continue
		if race_id == RUSTDEAD_RACE_ID:
			_fail("Non-Rustdead actor %s in faction %s spawned with Rustdead race" % [actor.name, faction_name])


func _validate_town_contract(town: Node, town_name: String) -> void:
	var required_roots := [
		"StateLabel",
		"Housing",
		"Facilities",
		"Storage",
		"Residents",
		"ActivityPoints",
		"Guards",
		"GuardPosts",
		"DynamicBuildings",
		"DynamicFacilities",
		"RoadSpawn",
		"DefenseSpawn",
	]
	for path in required_roots:
		if town.get_node_or_null(path) == null:
			_fail("%s missing required town node %s" % [town_name, path])
	if town.get("settlement_definition") == null:
		_fail("%s should have a settlement definition" % town_name)
	var housing := town.get_node_or_null("Housing")
	if housing == null or housing.get_child_count() < 1:
		_fail("%s should author at least one home" % town_name)
	else:
		var home := housing.get_child(0)
		if str(home.get("building_id")).strip_edges().is_empty():
			_fail("%s home should have a stable building id" % town_name)
	var facilities := town.get_node_or_null("Facilities")
	if facilities == null:
		return
	var required_facility_names := ["Jail", "Bar", "Keep"]
	var seen_facility_ids := {}
	for facility_name in required_facility_names:
		var facility := facilities.get_node_or_null(facility_name)
		if facility == null:
			_fail("%s should include facility %s" % [town_name, facility_name])
			continue
		var facility_id := str(facility.get("facility_id")).strip_edges()
		if facility_id.is_empty():
			_fail("%s/%s should have a stable facility_id" % [town_name, facility_name])
		if str(facility.get("building_id")).strip_edges().is_empty():
			_fail("%s/%s should have a stable building_id" % [town_name, facility_name])
		if seen_facility_ids.has(facility_id):
			_fail("%s has duplicate facility_id %s" % [town_name, facility_id])
		seen_facility_ids[facility_id] = true


func _validate_faction_relations() -> void:
	var faction_controller := _get_controller("faction_controller")
	if faction_controller == null:
		_fail("Faction controller missing")
		return
	if str(faction_controller.call("get_diplomatic_state", "SurfCity", "EastRaiders")) != "war":
		_fail("SurfCity and EastRaiders should start in formal war")
	if not bool(faction_controller.call("are_hostile", "SurfCity", "EastRaiders")):
		_fail("SurfCity and EastRaiders should be hostile because they are at war")
	if str(faction_controller.call("get_diplomatic_state", "SurfCity", "ParadiseHills")) != "neutral":
		_fail("SurfCity and ParadiseHills should be formally neutral")
	if bool(faction_controller.call("are_hostile", "SurfCity", "ParadiseHills")):
		_fail("SurfCity and ParadiseHills should dislike each other without being hostile")
	if str(faction_controller.call("get_diplomatic_state", "EastRaiders", "ParadiseHills")) != "neutral":
		_fail("EastRaiders and ParadiseHills should be formally neutral")
	if int(faction_controller.call("get_faction_outlook", "SurfCity", "ParadiseHills")) != -55:
		_fail("SurfCity outlook toward ParadiseHills should be -55")
	if str(faction_controller.call("get_faction_outlook_label", "SurfCity", "ParadiseHills")) != "Disliked":
		_fail("SurfCity outlook label toward ParadiseHills should be Disliked")
	if int(faction_controller.call("get_faction_outlook", "EastRaiders", "ParadiseHills")) != -10:
		_fail("EastRaiders outlook toward ParadiseHills should be -10")


func _validate_slavery_law_flag() -> void:
	var faction_controller := _get_controller("faction_controller")
	if faction_controller == null:
		return
	var paradise_definition := faction_controller.call("get_faction_definition", "ParadiseHills") as Resource
	if paradise_definition == null:
		_fail("ParadiseHills faction definition missing")
		return
	var law_profile := paradise_definition.get("law_profile") as Resource
	if law_profile == null:
		_fail("ParadiseHills should have a law profile")
		return
	if str(law_profile.get("slavery_policy")) != "legal":
		_fail("ParadiseHills law should mark slavery as legal")


func _get_controller(group_name: String) -> Node:
	var nodes := get_nodes_in_group(group_name)
	return nodes[0] if not nodes.is_empty() else null


func _race_id(race: Resource) -> String:
	return str(race.get("race_id")).strip_edges().to_lower() if race != null else ""


func _wait_frames(count: int) -> void:
	for _i in range(count):
		await process_frame


func _cleanup_scene() -> void:
	if _scene != null and is_instance_valid(_scene):
		root.remove_child(_scene)
		_scene.free()
	_scene = null
	_world_definition = null
	_zone_definition = null
	_bandage_item = null
	await process_frame
	await physics_frame
	_cleanup_runtime_state()
	await process_frame


func _cleanup_runtime_state() -> void:
	var combat_coordinator = load(COMBAT_COORDINATOR_PATH)
	if combat_coordinator != null and combat_coordinator.has_method("reset_all_state"):
		combat_coordinator.reset_all_state()
	var ai_utility_adapter = load(AI_UTILITY_ADAPTER_PATH)
	if ai_utility_adapter != null and ai_utility_adapter.has_method("clear_runtime_caches"):
		ai_utility_adapter.clear_runtime_caches()
	var skin_texture_builder = load(SKIN_TEXTURE_BUILDER_PATH)
	if skin_texture_builder != null and skin_texture_builder.has_method("clear_runtime_caches"):
		skin_texture_builder.clear_runtime_caches()


func _fail(message: String) -> void:
	_failures.append(message)
