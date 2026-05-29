extends SceneTree

const DEMO_WORLD_SCENE := preload("res://scenes/worlds/demo_world/demo_world.tscn")

const REQUIRED_CONTROLLERS := [
	"GecsWorldController",
	"WorldTimeController",
	"ActorQueryController",
	"AiSchedulerController",
	"BleedSplotchController",
	"DayNightLightingController",
	"PerceptionController",
	"FactionController",
	"PopulationController",
	"PopulationRealizationController",
	"SettlementController",
	"TerritoryController",
	"RoadController",
	"WorldEventChoiceController",
	"WorldSquadController",
	"WorldSimulationController",
	"LedgerSimulationController",
	"LawOrderController",
	"SettlementActivityController",
	"PartyInventoryController",
	"HumanoidDetailsController",
	"CharacterAppearanceController",
	"ConversationController",
	"OwnershipController",
	"JobSystemController",
	"BuildingVisibilityController",
	"WorldStatusController",
	"WorldInteractionController",
]

const WORLD_SIM_DEPENDENCIES := {
	"world_time": "WorldTimeController",
	"settlement_controller": "SettlementController",
	"territory_controller": "TerritoryController",
	"road_controller": "RoadController",
	"world_squad_controller": "WorldSquadController",
	"population_controller": "PopulationController",
	"ai_scheduler_controller": "AiSchedulerController",
	"actor_query_controller": "ActorQueryController",
	"gecs_world_controller": "GecsWorldController",
	"population_realization_controller": "PopulationRealizationController",
	"ledger_simulation_controller": "LedgerSimulationController",
	"faction_controller": "FactionController",
	"law_order_controller": "LawOrderController",
	"world_event_choice_controller": "WorldEventChoiceController",
	"job_system_controller": "JobSystemController",
}

var _failures: Array[String] = []
var _scene: Node


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	_scene = DEMO_WORLD_SCENE.instantiate()
	root.add_child(_scene)
	await _wait_frames(180)
	_validate_bootstrap_controllers()
	_validate_single_gecs_controller()
	_validate_world_simulation_dependencies()
	if _failures.is_empty():
		print("BOOTSTRAP_CONTROLLER_WIRING_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("BOOTSTRAP_CONTROLLER_WIRING_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_bootstrap_controllers() -> void:
	var bootstrap := _scene.get_node_or_null("GameBootstrap")
	if bootstrap == null:
		_fail("Demo world should have GameBootstrap")
		return
	for controller_name in REQUIRED_CONTROLLERS:
		if bootstrap.get_node_or_null(controller_name) == null:
			_fail("GameBootstrap missing controller %s" % controller_name)


func _validate_single_gecs_controller() -> void:
	var gecs_nodes := get_nodes_in_group("gecs_world_controller")
	if gecs_nodes.size() != 1:
		_fail("Expected exactly one gecs_world_controller, found %d" % gecs_nodes.size())


func _validate_world_simulation_dependencies() -> void:
	var bootstrap := _scene.get_node_or_null("GameBootstrap")
	if bootstrap == null:
		return
	var world_sim := bootstrap.get_node_or_null("WorldSimulationController")
	if world_sim == null:
		_fail("WorldSimulationController missing")
		return
	if not bool(world_sim.get("_initialized")):
		_fail("WorldSimulationController should initialize after bootstrap wiring")
	for property_name in WORLD_SIM_DEPENDENCIES.keys():
		var expected_name := str(WORLD_SIM_DEPENDENCIES[property_name])
		var expected_node := bootstrap.get_node_or_null(expected_name)
		var actual_node = world_sim.get(str(property_name))
		if actual_node == null:
			_fail("WorldSimulationController dependency %s is null" % property_name)
		elif expected_node != null and actual_node != expected_node:
			_fail("WorldSimulationController dependency %s does not point at %s" % [property_name, expected_name])


func _wait_frames(count: int) -> void:
	for _i in range(count):
		await process_frame


func _fail(message: String) -> void:
	_failures.append(message)
