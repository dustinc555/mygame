extends SceneTree

const DEMO_WORLD_SCENE := preload("res://scenes/worlds/demo_world/demo_world.tscn")
const DEMO_WORLD_DEFINITION := preload("res://resources/worlds/demo_world/demo_world.tres")
const POPULATION_APPEARANCE_PROFILE_DIR := "res://resources/world_sim/population_appearance_profiles"
const BANDAGE_ITEM := preload("res://resources/items/bandage.tres")
const CINDER_FLASK_ITEM := preload("res://resources/items/cinder_flask.tres")
const HUMAN_RACE_ID := "human"
const RUSTDEAD_RACE_ID := "rustdead"

var _failures: Array[String] = []
var _scene: Node


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	_scene = DEMO_WORLD_SCENE.instantiate()
	root.add_child(_scene)
	await _wait_frames(140)
	_validate_world_definition()
	_validate_population_appearance_profiles()
	_validate_loaded_towns()
	_validate_town_guard_burn_support()
	_validate_non_rustdead_humanoids()
	_validate_faction_relations()
	_validate_slavery_law_flag()
	if _failures.is_empty():
		print("DEMO_WORLD_TOPOLOGY_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("DEMO_WORLD_TOPOLOGY_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_world_definition() -> void:
	if str(DEMO_WORLD_DEFINITION.call("get_id")) != "demo_world":
		_fail("Demo world definition should use stable id demo_world")
	if (DEMO_WORLD_DEFINITION.get("settlement_placements") as Array).size() != 3:
		_fail("Demo world should define exactly three settlement placements")
	if (DEMO_WORLD_DEFINITION.get("starting_relations") as Array).size() != 3:
		_fail("Demo world should define exactly three starting relations")
	var settlement_ids := {}
	for placement in DEMO_WORLD_DEFINITION.get("settlement_placements"):
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
	var towns := _scene.get_node_or_null("Towns")
	if towns == null:
		_fail("Demo world should have a runtime Towns root")
		return
	for town_name in ["SurfCity", "EastRaidersCamp", "ParadiseHills"]:
		var town := towns.get_node_or_null(town_name)
		if town == null:
			_fail("Town %s should be loaded by WorldLoader" % town_name)
			continue
		_validate_town_contract(town, town_name)


func _validate_town_guard_burn_support() -> void:
	var towns := _scene.get_node_or_null("Towns")
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
		if guards == null:
			continue
		for child in guards.get_children():
			var guard := child as HumanoidCharacter
			if guard == null:
				continue
			if not guard.is_auto_heal_enabled():
				_fail("%s guard %s should default Auto Heal on" % [town_name, guard.name])
			if not guard.is_auto_burn_rustdead_enabled():
				_fail("%s guard %s should default Burn Rustdead on" % [town_name, guard.name])
			if guard.inventory == null or guard.inventory.count_item(BANDAGE_ITEM) < 1:
				_fail("%s guard %s should start with bandages" % [town_name, guard.name])
			if guard.inventory == null or guard.inventory.count_item(CINDER_FLASK_ITEM) != 2:
				_fail("%s guard %s should start with exactly 2 Cinder Flasks" % [town_name, guard.name])


func _validate_population_appearance_profiles() -> void:
	var files := Array(DirAccess.get_files_at(POPULATION_APPEARANCE_PROFILE_DIR))
	files.sort()
	for file_name_value in files:
		var file_name := str(file_name_value)
		if not file_name.ends_with(".tres"):
			continue
		var path := "%s/%s" % [POPULATION_APPEARANCE_PROFILE_DIR, file_name]
		var profile := load(path) as Resource
		if profile == null or not profile.has_method("create_appearance"):
			continue
		var allowed_races: Array = profile.get("allowed_races") if profile.get("allowed_races") is Array else []
		if not allowed_races.is_empty():
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = 1001
		for sample_index in range(8):
			var appearance := profile.call("create_appearance", rng) as Resource
			var race := appearance.get("character_race") as Resource if appearance != null else null
			var race_id := _race_id(race)
			if race_id != HUMAN_RACE_ID:
				_fail("Population appearance profile %s should default to human race, got %s on sample %d" % [path, race_id, sample_index + 1])
				break


func _validate_non_rustdead_humanoids() -> void:
	for node in get_nodes_in_group("humanoid_character"):
		var actor := node as HumanoidCharacter
		if actor == null:
			continue
		var faction_name := str(actor.get("faction_name"))
		var race_id := _race_id(actor.get("character_race"))
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
		if str(home.get("population_capacity_id")).strip_edges().is_empty():
			_fail("%s home should have a stable population capacity id" % town_name)
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


func _fail(message: String) -> void:
	_failures.append(message)
