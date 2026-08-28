extends SceneTree

## Town worker contract: one durable occupation, town-scoped farming, batched
## skill-aware assignment, and reuse of the central Jobs dispatcher.
## Run: godot --headless --path . --script res://tools/validation/validate_town_worker_occupations.gd

const FARMER_ROLE_PATH := "res://features/settlements/resources/roles/farmer.tres"
const TOWN_SCRIPT_PATH := "res://features/settlements/bridge/settlement_town.gd"
const FIELD_SCENE_PATH := "res://features/settlements/bridge/settlement_field.tscn"
const POPULATION_SCRIPT_PATH := "res://features/world_sim/sim/population/population_controller.gd"
const JOB_SYSTEM_SCRIPT_PATH := "res://features/settlements/sim/job_system_controller.gd"
const HOME_PROJECTION_SCRIPT_PATH := "res://features/settlements/bridge/home_resident_projection.gd"
const CENSUS_SCRIPT_PATH := "res://features/settlements/sim/settlement_census.gd"
const ADA_PATH := "res://features/actors/resources/characters/ada.tres"
const POPULATION_COMPONENT_PATH := "res://features/world_sim/sim/population/c_game_population_record.gd"
const FIELD_SCRIPT_PATH := "res://features/settlements/bridge/settlement_field.gd"
const RUSTWASH_SCENE_PATH := "res://scenes/zones/rustwash_basin/rustwash_basin.tscn"
const TWO_TOWNS_SCENE_PATH := "res://scenes/test_levels/two_towns_road_test.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	load("res://addons/gecs/ecs/ecs.gd")
	_validate_farmer_role()
	_validate_no_pseudo_field_system()
	_validate_town_labor_specs()
	_validate_batch_assignment_contract()
	_validate_jobs_dispatch_binding()
	_validate_idle_residence_contract()
	_finish()


func _validate_farmer_role() -> void:
	var farmer_role: Resource = load(FARMER_ROLE_PATH)
	_expect(str(farmer_role.get("preferred_skill_id")) == SkillRules.LABOR_FARMING, "Farmer occupation must rank residents by Farming skill")
	var allowed := PackedStringArray(farmer_role.get("allowed_job_entry_ids"))
	_expect(allowed == PackedStringArray(["category:farm", "category:haul"]), "Farmer must perform Farm work first and Haul only as fallback")


func _validate_no_pseudo_field_system() -> void:
	var field_source := FileAccess.get_file_as_string(FIELD_SCRIPT_PATH)
	_expect(not field_source.contains("ACTIVITY_POINT_SCRIPT") and not field_source.contains("_ensure_activity_points"), "Real fields must not generate pseudo farmhand idle markers")
	var field_scene_source := FileAccess.get_file_as_string(FIELD_SCENE_PATH)
	_expect(not field_scene_source.contains("ActivityPoints") and not field_scene_source.contains("[node name=\"Staff\""), "Canonical real fields must not carry pseudo facility staff/activity roots")
	for scene_path in [RUSTWASH_SCENE_PATH, TWO_TOWNS_SCENE_PATH]:
		var source := FileAccess.get_file_as_string(scene_path)
		_expect(not source.contains("field_hand_a") and not source.contains("field_hand_b") and not source.contains("FieldHand"), "%s must not retain the May pseudo-field jobs or stand-around markers" % scene_path)


func _validate_town_labor_specs() -> void:
	var town: Node = (load(TOWN_SCRIPT_PATH) as Script).new()
	var definition := SettlementDefinition.new()
	definition.settlement_id = "town"
	town.set("settlement_definition", definition)
	var facilities := Node3D.new()
	facilities.name = "Facilities"
	town.add_child(facilities)
	var field := (load(FIELD_SCENE_PATH) as PackedScene).instantiate()
	field.set("dimensions", Vector2i(6, 4))
	facilities.add_child(field)
	var farmers: Array[Dictionary] = []
	for slot_value in town.call("get_assignment_slot_specs"):
		var slot: Dictionary = slot_value
		if str(slot.get("role_id", "")) == "farmer":
			farmers.append(slot)
	_expect(farmers.size() == 1, "A small real field creates one workload-derived farmer vacancy")
	field.set("dimensions", Vector2i(571, 1))
	farmers.clear()
	for slot_value in town.call("get_assignment_slot_specs"):
		var slot: Dictionary = slot_value
		if str(slot.get("role_id", "")) == "farmer":
			farmers.append(slot)
	_expect(farmers.size() == 3, "Canyon's 571 cells must derive exactly three farmers at 200 tiles per farmer")
	if not farmers.is_empty():
		_expect(str(farmers[0].get("assignment_scope", "")) == "town_labor" and int(farmers[0].get("population_cost", 1)) == 0, "Town jobs convert residents without creating population")
	var town_source := FileAccess.get_file_as_string(TOWN_SCRIPT_PATH)
	_expect(town_source.contains("FARM_TILES_PER_FARMER") and town_source.contains("_estimated_farmer_count"), "Farmer demand must use the simple farm-tile ratio")
	var canyon_source := FileAccess.get_file_as_string("res://features/world_sim/resources/settlements/canyon.tres")
	_expect(not canyon_source.contains("town_job_counts"), "Canyon must not hardcode a farmer count")
	town.free()


func _validate_batch_assignment_contract() -> void:
	var population: Node = (load(POPULATION_SCRIPT_PATH) as Script).new()
	_expect(population.has_method("claim_records_for_assignments"), "Population assignment must batch every dirty town from one resident snapshot")
	_expect(population.has_method("score_record_for_assignment"), "Skill-aware assignment score must be explicit and testable")
	if population.has_method("score_record_for_assignment"):
		var farmer_slot := {"preferred_skill_id": SkillRules.LABOR_FARMING, "character_type_id": "default"}
		var skilled := {"actor_id": "skilled", "skill_levels": {SkillRules.LABOR_FARMING: 40}, "character_type_id": "default"}
		var weak := {"actor_id": "weak", "skill_levels": {SkillRules.LABOR_FARMING: 2}, "character_type_id": "default"}
		_expect(int(population.call("score_record_for_assignment", skilled, farmer_slot)) > int(population.call("score_record_for_assignment", weak, farmer_slot)), "Higher Farming skill must win a Farming occupation")
	var available := {"actor_id": "generated", "settlement_id": "town", "life_state": 0, "role_id": "resident", "available_for_work": true, "assignments": {}, "assignment_exclusivity_groups": {}}
	var unavailable := available.duplicate(true)
	unavailable["actor_id"] = "ada"
	unavailable["available_for_work"] = false
	_expect(bool(population.call("_eligible_for_assignment", available, "town", "employment", "employment")), "Generated available residents may be selected for town jobs")
	_expect(not bool(population.call("_eligible_for_assignment", unavailable, "town", "employment", "employment")), "Manually placed unavailable characters must never be auto-selected")
	population.free()
	var ada: Resource = load(ADA_PATH)
	_expect(ada.get("available_for_work") == false, "Ada must author available_for_work off")
	var census_source := FileAccess.get_file_as_string(CENSUS_SCRIPT_PATH)
	_expect(census_source.contains("assignment_scope") and census_source.contains("town_labor"), "Loading-screen census must leave town jobs vacant until generated residents exist")
	var component = (load(POPULATION_COMPONENT_PATH) as Script).new()
	component.call("apply_record", {"generation_source": "assignment_preferred"})
	_expect(component.get("available_for_work") == false, "Old manually placed records migrate to unavailable")
	component.call("apply_record", {"generation_source": "assignment_auto.residence"})
	_expect(component.get("available_for_work") == true, "Old auto-generated resident records migrate to available")


func _validate_jobs_dispatch_binding() -> void:
	var jobs: Node = (load(JOB_SYSTEM_SCRIPT_PATH) as Script).new()
	var state := {
		"settlement_id": "town",
		"facilities": {},
		"assignment_slots": {
			"employment:town.farmer.0": {
				"slot_id": "town.farmer.0",
				"assignment_domain": "employment",
				"assignment_scope": "town_labor",
				"role_id": "farmer",
				"filled": true,
				"uses_settlement_jobs": true,
				"occupant_actor_id": "farmer.a",
				"facility_id": "",
				"owner_id": "town",
				"allowed_job_entry_ids": PackedStringArray(["category:farm", "category:haul"]),
			},
			"employment:town.farmer.1": {
				"slot_id": "town.farmer.1", "assignment_domain": "employment",
				"assignment_scope": "town_labor", "role_id": "farmer", "filled": true,
				"uses_settlement_jobs": true, "occupant_actor_id": "farmer.b",
				"facility_id": "", "owner_id": "town",
				"allowed_job_entry_ids": PackedStringArray(["category:farm", "category:haul"]),
			},
			"employment:town.farmer.2": {
				"slot_id": "town.farmer.2", "assignment_domain": "employment",
				"assignment_scope": "town_labor", "role_id": "farmer", "filled": true,
				"uses_settlement_jobs": true, "occupant_actor_id": "farmer.c",
				"facility_id": "", "owner_id": "town",
				"allowed_job_entry_ids": PackedStringArray(["category:farm", "category:haul"]),
			},
		},
	}
	jobs.call("_rebuild_assignment_workers_for_settlement", "town", state)
	var workers: Dictionary = jobs.get("_assignment_workers")
	_expect(workers.has("farmer.a"), "Central Jobs dispatcher must bind town-scoped occupations without a facility ID")
	if workers.has("farmer.a"):
		var assignment: Dictionary = workers["farmer.a"]
		_expect(str(assignment.get("duty_scope_id", "")) == "town", "Town labor duty must bind to its town")
		_expect(PackedStringArray(assignment.get("allowed_job_entry_ids", PackedStringArray())) == PackedStringArray(["category:farm", "category:haul"]), "Dispatcher must preserve occupation work categories")
	jobs._pending_assignment_actor_ids.clear()
	jobs._pending_assignment_actor_order.clear()
	jobs._pending_assignment_actor_head = 0
	for actor_id in ["farmer.a", "farmer.b", "farmer.c"]:
		jobs.notify_assignment_worker_realized(actor_id)
	_expect(jobs._pending_assignment_actor_ids.size() == 3, "all three re-realized farmers re-enter dispatch after one LOD round trip")
	jobs.free()


func _validate_idle_residence_contract() -> void:
	var jobs_source := FileAccess.get_file_as_string(JOB_SYSTEM_SCRIPT_PATH)
	_expect(jobs_source.contains("work_offers_changed") and jobs_source.contains("_queue_assignment_worker"), "Assignment workers must wake from provider events instead of 60 Hz polling")
	var home_source := FileAccess.get_file_as_string(HOME_PROJECTION_SCRIPT_PATH)
	_expect(home_source.contains("_send_home_fallback") and home_source.contains("set_move_target"), "Idle residents without a free chair or bed must still walk home")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("TOWN_WORKER_OCCUPATIONS_OK")
	else:
		print("TOWN_WORKER_OCCUPATIONS_FAILED count=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
