extends SceneTree

# Validates the GameBootstrap composition-root cut: the four layer roots exist,
# every controller lives under its correct layer root (no migration junk-drawer),
# the BootstrapContext registry resolves services by id, and
# WorldSimulationController's injected dependencies are wired.

const DEMO_WORLD_SCENE_PATH := "res://scenes/worlds/demo_world/demo_world.tscn"
const AI_UTILITY_ADAPTER_PATH := "res://features/ai/bridge/ai_utility_adapter.gd"
const COMBAT_COORDINATOR_PATH := "res://features/combat/bridge/combat_coordinator.gd"
const SKIN_TEXTURE_BUILDER_PATH := "res://features/actors/projection/appearance/skin_texture_builder.gd"

# Every controller, keyed by the layer root it must live under. The feature
# modules declare these placements; there is no longer any not-yet-migrated set.
const LAYERED_CONTROLLERS := {
	"CoreServices": ["GecsWorldController", "WorldTimeController", "ActorQueryController"],
	"ProjectionRoot": [
		"BuildingVisibilityController", "BleedSplotchController", "DayNightLightingController",
		"CharacterAppearanceController",
	],
	"WorldSimRoot": [
		"WorldSimulationController", "FactionController", "PopulationController", "TerritoryController",
		"RoadController", "WorldEventChoiceController", "WorldSimSquadController", "FactionWorldSimController",
		"EncounterController", "LedgerSimulationController", "LawOrderController", "OwnershipController",
		"JobSystemController",
	],
	"BridgeRoot": [
		"WorldInteractionController", "WorldStatusController", "PopulationRealizationController",
		"PerceptionController", "AiSchedulerController", "SettlementController", "PartyInventoryController",
		"ConversationController", "HumanoidDetailsController",
	],
}

# Service ids that must resolve through the BootstrapContext registry. Proves the
# DI mechanism works end-to-end for moved core/world/world_sim controllers.
const REQUIRED_SERVICE_IDS := [
	&"gecs_world",
	&"world_time",
	&"actor_query",
	&"world_simulation",
	&"world_status",
	&"world_interaction",
	&"building_visibility",
	&"day_night_lighting",
]

const WORLD_SIM_DEPENDENCIES := {
	"world_time": "WorldTimeController",
	"settlement_controller": "SettlementController",
	"territory_controller": "TerritoryController",
	"road_controller": "RoadController",
	"world_sim_squad_controller": "WorldSimSquadController",
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
	var demo_world_scene := load(DEMO_WORLD_SCENE_PATH) as PackedScene
	if demo_world_scene == null:
		_fail("Demo world scene should load from %s" % DEMO_WORLD_SCENE_PATH)
		_print_failures_and_quit()
		return
	_scene = demo_world_scene.instantiate()
	demo_world_scene = null
	root.add_child(_scene)
	await _wait_frames(180)
	_validate_layer_roots()
	_validate_controller_placement()
	_validate_context_registry()
	_validate_single_gecs_controller()
	_validate_world_simulation_dependencies()
	_validate_world_sim_plugins()
	await _cleanup_scene()
	if _failures.is_empty():
		print("BOOTSTRAP_CONTROLLER_WIRING_OK")
		quit(0)
		return
	_print_failures_and_quit()


func _print_failures_and_quit() -> void:
	for failure in _failures:
		push_error(failure)
	print("BOOTSTRAP_CONTROLLER_WIRING_FAILED count=%d" % _failures.size())
	quit(1)


func _bootstrap() -> Node:
	return _scene.get_node_or_null("GameBootstrap") if _scene != null else null


func _validate_layer_roots() -> void:
	var bootstrap := _bootstrap()
	if bootstrap == null:
		_fail("Demo world should have GameBootstrap")
		return
	for root_name in LAYERED_CONTROLLERS.keys():
		if bootstrap.get_node_or_null(root_name) == null:
			_fail("GameBootstrap missing layer root %s" % root_name)


func _validate_controller_placement() -> void:
	var bootstrap := _bootstrap()
	if bootstrap == null:
		return
	# Every controller must live under its declared layer root.
	for root_name in LAYERED_CONTROLLERS.keys():
		var root_node := bootstrap.get_node_or_null(root_name)
		if root_node == null:
			continue
		for controller_name in LAYERED_CONTROLLERS[root_name]:
			if root_node.get_node_or_null(controller_name) == null:
				_fail("%s should contain %s" % [root_name, controller_name])


func _validate_context_registry() -> void:
	var bootstrap := _bootstrap()
	if bootstrap == null:
		return
	var context = bootstrap.get("_context")
	if context == null:
		_fail("GameBootstrap should expose a BootstrapContext after wiring")
		return
	for service_id in REQUIRED_SERVICE_IDS:
		if context.get_optional(service_id) == null:
			_fail("BootstrapContext registry missing service '%s'" % service_id)


func _validate_single_gecs_controller() -> void:
	var gecs_nodes := get_nodes_in_group("gecs_world_controller")
	if gecs_nodes.size() != 1:
		_fail("Expected exactly one gecs_world_controller, found %d" % gecs_nodes.size())


func _validate_world_simulation_dependencies() -> void:
	var bootstrap := _bootstrap()
	if bootstrap == null:
		return
	# Controllers now live across layer roots, so resolve by recursive search.
	var world_sim := bootstrap.find_child("WorldSimulationController", true, false)
	if world_sim == null:
		_fail("WorldSimulationController missing")
		return
	if not bool(world_sim.get("_initialized")):
		_fail("WorldSimulationController should initialize after bootstrap wiring")
	for property_name in WORLD_SIM_DEPENDENCIES.keys():
		var expected_name := str(WORLD_SIM_DEPENDENCIES[property_name])
		var expected_node := bootstrap.find_child(expected_name, true, false)
		var actual_node = world_sim.get(str(property_name))
		if actual_node == null:
			_fail("WorldSimulationController dependency %s is null" % property_name)
		elif expected_node != null and actual_node != expected_node:
			_fail("WorldSimulationController dependency %s does not point at %s" % [property_name, expected_name])


func _validate_world_sim_plugins() -> void:
	var bootstrap := _bootstrap()
	if bootstrap == null:
		return
	var ticker := bootstrap.find_child("WorldSimSquadController", true, false)
	if ticker == null:
		_fail("WorldSimSquadController missing")
		return
	var plugin := ticker.get_node_or_null("NestWorldSimPlugin")
	if plugin == null:
		_fail("NestWorldSimPlugin should be registered under WorldSimSquadController")
		return
	if not plugin.is_in_group("nest_world_sim_plugin"):
		_fail("NestWorldSimPlugin should publish the nest_world_sim_plugin group")
	if ticker.has_method("get_world_sim_plugin") and ticker.call("get_world_sim_plugin", "nests") != plugin:
		_fail("WorldSimSquadController should register the nests plugin")


func _wait_frames(count: int) -> void:
	for _i in range(count):
		await process_frame


func _cleanup_scene() -> void:
	if _scene != null and is_instance_valid(_scene):
		root.remove_child(_scene)
		_scene.free()
	_scene = null
	await process_frame
	await physics_frame
	_cleanup_runtime_state()
	await _wait_frames(6)


func _cleanup_runtime_state() -> void:
	var ecs_node := root.get_node_or_null("ECS")
	if ecs_node != null:
		if Engine.has_singleton("ECS"):
			Engine.unregister_singleton("ECS")
		ecs_node.free()
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
