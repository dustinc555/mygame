extends SceneTree

const GECS_WORLD_CONTROLLER_SCRIPT := preload("res://src/core/gecs_world_controller.gd")
const WORLD_TIME_CONTROLLER_SCRIPT := preload("res://src/core/world_time_controller.gd")
const SETTLEMENT_CONTROLLER_SCRIPT := preload("res://src/settlements/bridge/settlement_controller.gd")
const WORLD_SIMULATION_CONTROLLER_SCRIPT := preload("res://src/world_sim/sim/world_simulation_controller.gd")
const JOB_SYSTEM_CONTROLLER_SCRIPT := preload("res://src/settlements/sim/job_system_controller.gd")
const AI_SCHEDULER_CONTROLLER_SCRIPT := preload("res://src/ai/bridge/ai_scheduler_controller.gd")
const POPULATION_REALIZATION_CONTROLLER_SCRIPT := preload("res://src/world_sim/bridge/population_realization_controller.gd")
const LEDGER_SIMULATION_CONTROLLER_SCRIPT := preload("res://src/world_sim/sim/ledger_simulation_controller.gd")

const SAVE_PATH := "user://world_simulation_save_load_authority_validation.tres"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_file(SAVE_PATH)
	var root_node := Node.new()
	root.add_child(root_node)

	var controllers := _add_controllers(root_node)
	for controller in controllers:
		if controller.has_method("initialize"):
			controller.call("initialize", root_node)

	var world_time: Node = root_node.get_node("WorldTimeController")
	var gecs: Node = root_node.get_node("GecsWorldController")
	var job_system: Node = root_node.get_node("JobSystemController")
	var ai_scheduler: Node = root_node.get_node("AiSchedulerController")
	var population_realization: Node = root_node.get_node("PopulationRealizationController")
	var ledger_simulation: Node = root_node.get_node("LedgerSimulationController")
	var world_simulation: Node = root_node.get_node("WorldSimulationController")

	world_time.call("advance_hours", 6.5)
	world_time.call("set_speed_index", 2)
	world_time.call("request_manual_pause")
	job_system.call("apply_serialized_state", {"sim_time": 42.5})
	ai_scheduler.call("apply_serialized_state", {"sim_time": 7.25, "default_tick_interval_seconds": 0.35, "default_tick_jitter_seconds": 0.05})
	population_realization.call("apply_serialized_state", {"default_realization_policy": "near_player", "near_player_radius": 44.0, "realization_resync_interval_seconds": 0.75})
	ledger_simulation.call("apply_serialized_state", {"last_processed_minute": 1530, "last_batch_summary": {"updated_actor_count": 2}})
	gecs.call("upsert_world_sim_squad", {"squad_id": "squad_0003", "owner_id": "raider_camp", "owner_kind": "faction", "faction_id": "Raiders", "objective": "attack", "position": Vector3(1.0, 0.0, 2.0), "target_position": Vector3(10.0, 0.0, 0.0), "member_count": 3, "phase": "demand", "phase_timer": 4.0})

	if not bool(world_simulation.call("save_world_to_file", SAVE_PATH, false)):
		_fail("WorldSimulationController should save through GECS")

	world_time.call("apply_serialized_state", {"total_world_minutes": 15.0, "speed_index": 0, "manual_paused": false})
	job_system.call("apply_serialized_state", {"sim_time": 1.0})
	ai_scheduler.call("apply_serialized_state", {"sim_time": 1.0, "default_tick_interval_seconds": 1.0, "default_tick_jitter_seconds": 0.0})
	population_realization.call("apply_serialized_state", {"default_realization_policy": "full_town", "near_player_radius": 1.0, "realization_resync_interval_seconds": 2.0})
	ledger_simulation.call("apply_serialized_state", {"last_processed_minute": 1, "last_batch_summary": {"updated_actor_count": 0}})
	gecs.call("remove_world_sim_squad", "squad_0003")

	if not bool(world_simulation.call("load_world_from_file", SAVE_PATH)):
		_fail("WorldSimulationController should load through GECS")
	else:
		_validate_refreshed_controllers(world_time, job_system, ai_scheduler, population_realization, ledger_simulation, gecs, world_simulation)

	root_node.queue_free()
	await process_frame
	_remove_file(SAVE_PATH)

	if _failures.is_empty():
		print("WORLD_SIMULATION_SAVE_LOAD_AUTHORITY_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("WORLD_SIMULATION_SAVE_LOAD_AUTHORITY_FAILED count=%d" % _failures.size())
	quit(1)


func _add_controllers(parent: Node) -> Array[Node]:
	var specs := [
		{"name": "GecsWorldController", "script": GECS_WORLD_CONTROLLER_SCRIPT},
		{"name": "WorldTimeController", "script": WORLD_TIME_CONTROLLER_SCRIPT},
		{"name": "SettlementController", "script": SETTLEMENT_CONTROLLER_SCRIPT},
		{"name": "JobSystemController", "script": JOB_SYSTEM_CONTROLLER_SCRIPT},
		{"name": "AiSchedulerController", "script": AI_SCHEDULER_CONTROLLER_SCRIPT},
		{"name": "PopulationRealizationController", "script": POPULATION_REALIZATION_CONTROLLER_SCRIPT},
		{"name": "LedgerSimulationController", "script": LEDGER_SIMULATION_CONTROLLER_SCRIPT},
		{"name": "WorldSimulationController", "script": WORLD_SIMULATION_CONTROLLER_SCRIPT},
	]
	var controllers: Array[Node] = []
	for spec in specs:
		var controller := Node.new()
		controller.name = str(spec["name"])
		controller.set_script(spec["script"])
		parent.add_child(controller)
		controllers.append(controller)
	return controllers


func _validate_refreshed_controllers(world_time: Node, job_system: Node, ai_scheduler: Node, population_realization: Node, ledger_simulation: Node, gecs: Node, world_simulation: Node) -> void:
	var time_state: Dictionary = world_time.call("serialize_state")
	if absf(float(time_state.get("total_world_minutes", 0.0)) - ((6.0 * 60.0) + 6.5 * 60.0)) > 0.01:
		_fail("WorldSimulationController load should refresh world time")
	if int(time_state.get("speed_index", -1)) != 2 or not bool(time_state.get("manual_paused", false)):
		_fail("WorldSimulationController load should refresh world speed and pause")
	if absf(float(job_system.call("get_sim_time")) - 42.5) > 0.01:
		_fail("WorldSimulationController load should refresh job system state")
	if absf(float(ai_scheduler.call("get_sim_time")) - 7.25) > 0.01:
		_fail("WorldSimulationController load should refresh AI scheduler time")
	if absf(float(ai_scheduler.get("default_tick_interval_seconds")) - 0.35) > 0.01:
		_fail("WorldSimulationController load should refresh AI scheduler settings")
	if str(population_realization.get("default_realization_policy")) != "near_player" or absf(float(population_realization.get("near_player_radius")) - 44.0) > 0.01:
		_fail("WorldSimulationController load should refresh realization settings")
	var ledger_summary: Dictionary = ledger_simulation.call("get_debug_summary")
	if int(ledger_summary.get("updated_actor_count", 0)) != 2:
		_fail("WorldSimulationController load should refresh ledger summary")
	var squad_state := _world_sim_squad_by_id(gecs, "squad_0003")
	if str(squad_state.get("phase", "")) != "demand" or absf(float(squad_state.get("phase_timer", 0.0)) - 4.0) > 0.01:
		_fail("WorldSimulationController load should refresh GECS world-sim squad records")
	var serialized: Dictionary = world_simulation.call("serialize_state")
	var gecs_state: Dictionary = serialized.get("gecs", {})
	if int(gecs_state.get("world_entity_count", 0)) <= 0:
		_fail("WorldSimulationController serialization should include GECS state")


func _world_sim_squad_by_id(gecs: Node, squad_id: String) -> Dictionary:
	if gecs == null or not gecs.has_method("get_world_sim_squads"):
		return {}
	for record in gecs.call("get_world_sim_squads"):
		if record is Dictionary and str(record.get("squad_id", "")) == squad_id:
			return (record as Dictionary).duplicate(true)
	return {}


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _fail(message: String) -> void:
	_failures.append(message)
