extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_granary_town_level.gd

const LEVEL_PATH := "res://scenes/test_levels/granary_town_test.tscn"
const WORKER_PATH := "res://features/actors/resources/characters/granary_worker.tres"


var failures: Array[String] = []
var _ecs_placeholder: Node


func _initialize() -> void:
	if not Engine.has_singleton("ECS"):
		_ecs_placeholder = Node.new()
		Engine.register_singleton("ECS", _ecs_placeholder)
	call_deferred("_run")


func _run() -> void:
	var home_source := FileAccess.get_file_as_string("res://features/settlements/bridge/home_resident_projection.gd")
	_expect(home_source.find("granary") < 0 and home_source.find("FACILITY_DUTY_CONTRACT.is_active") >= 0, "residence precedence uses the generic facility-duty contract with no Granary hardcode")
	_expect(not ResourceLoader.exists("res://features/settlements/bridge/scheduled_farm_worker_provider.gd"), "farming-specific scheduled provider is removed")
	_expect(ResourceLoader.exists(LEVEL_PATH), "granary town test level exists")
	_expect(ResourceLoader.exists(WORKER_PATH), "granary resident-worker has one permanent character record")
	if not ResourceLoader.exists(LEVEL_PATH):
		_finish()
		return
	var packed := load(LEVEL_PATH) as PackedScene
	var level = packed.instantiate() if packed != null else null
	_expect(level != null, "granary town level instantiates")
	if level == null:
		_finish()
		return
	var bootstrap := level.get_node_or_null("GameBootstrap")
	if bootstrap != null:
		level.remove_child(bootstrap)
		bootstrap.free()
	var population_spawner := level.get_node_or_null("GranaryTown/PopulationSpawner")
	if population_spawner != null:
		population_spawner.get_parent().remove_child(population_spawner)
		population_spawner.free()
	root.add_child(level)
	await process_frame
	var town = level.get_node_or_null("GranaryTown")
	var granary = level.get_node_or_null("GranaryTown/Facilities/Granary")
	var house = level.get_node_or_null("GranaryTown/Housing/WorkerHouse")
	_expect(town != null and town.has_method("get_faction_id") and str(town.call("get_faction_id")) == "Player", "level authors one player-owned town")
	_expect(granary != null and granary.has_method("count_role_slots") and str(granary.facility_type) == "storage" \
			and str(granary.owner_faction_id) == "Player", "town has one player-owned Granary facility")
	_expect(granary != null and bool(granary.door_schedule_enabled) and int(granary.door_open_hour) == 8 \
			and int(granary.door_close_hour) == 20, "Granary operates from 08:00 through 20:00")
	_expect(granary != null and granary.count_role_slots("worker", "employment") == 1, "Granary has one WORKER employment slot")
	_expect(house != null and house.has_method("count_role_slots") and str(house.facility_type) == "housing" \
			and house.count_role_slots("resident", "residence") == 1, "tiny house has one Resident slot")
	if granary != null and house != null:
		var worker_slot = granary.get_role_slot("worker", 0)
		var resident_slot = house.get_role_slot("resident", 0)
		_expect(worker_slot != null and resident_slot != null and worker_slot.named_character == resident_slot.named_character \
				and worker_slot.named_character != null, "the same permanent NPC owns both employment and residence assignments")
	var platforms = granary.get_node_or_null("StoragePlatforms") if granary != null else null
	_expect(platforms != null and platforms.get_child_count() == 5, "Granary reuses five committed physical produce platforms")
	_expect(granary == null or granary.get_node_or_null("ScheduledFarmWorkerProvider") == null, "Granary has no bespoke work dispatcher")
	var scenario = level.get_node_or_null("Scenario")
	_expect(scenario != null and scenario.has_method("get_authored_field_specs"), "level exposes authored field specifications")
	if scenario != null and scenario.has_method("get_authored_field_specs"):
		var specs: Array = scenario.call("get_authored_field_specs")
		_expect(specs.size() == 3, "level authors exactly three fields")
		var crops: Dictionary = {}
		for spec_value in specs:
			var spec: Dictionary = spec_value
			_expect(spec.get("dimensions") == Vector2i(4, 4), "every field is exactly 4x4")
			crops[str(spec.get("crop_id", ""))] = true
		_expect(crops.size() == 3 and not crops.has(""), "the three 4x4 fields use different crop policies")
	root.remove_child(level)
	level.free()
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if _ecs_placeholder != null:
		Engine.unregister_singleton("ECS")
		_ecs_placeholder.free()
	if failures.is_empty():
		print("GRANARY_TOWN_LEVEL_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("GRANARY_TOWN_LEVEL_FAILED count=%d" % failures.size())
	quit(1)
