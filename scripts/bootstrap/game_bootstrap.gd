extends Node

const JOB_SYSTEM_CONTROLLER_SCRIPT = preload("res://scripts/controllers/job_system_controller.gd")
const WORLD_TIME_CONTROLLER_SCRIPT = preload("res://scripts/controllers/world_time_controller.gd")
const BLEED_SPLOTCH_CONTROLLER_SCRIPT = preload("res://scripts/controllers/bleed_splotch_controller.gd")
const DAY_NIGHT_LIGHTING_CONTROLLER_SCRIPT = preload("res://scripts/controllers/day_night_lighting_controller.gd")
const WORLD_STATUS_CONTROLLER_SCRIPT = preload("res://scripts/controllers/world_status_controller.gd")
const FACTION_CONTROLLER_SCRIPT = preload("res://scripts/controllers/faction_controller.gd")
const SETTLEMENT_CONTROLLER_SCRIPT = preload("res://scripts/controllers/settlement_controller.gd")
const TERRITORY_CONTROLLER_SCRIPT = preload("res://scripts/controllers/territory_controller.gd")
const ROAD_CONTROLLER_SCRIPT = preload("res://scripts/controllers/road_controller.gd")
const SETTLEMENT_ACTIVITY_CONTROLLER_SCRIPT = preload("res://scripts/controllers/settlement_activity_controller.gd")
const WORLD_SIMULATION_CONTROLLER_SCRIPT = preload("res://scripts/controllers/world_simulation_controller.gd")
const GECS_WORLD_CONTROLLER_SCRIPT = preload("res://scripts/controllers/gecs_world_controller.gd")
const ACTOR_QUERY_CONTROLLER_SCRIPT = preload("res://scripts/controllers/actor_query_controller.gd")
const POPULATION_CONTROLLER_SCRIPT = preload("res://scripts/controllers/population_controller.gd")
const POPULATION_REALIZATION_CONTROLLER_SCRIPT = preload("res://scripts/controllers/population_realization_controller.gd")
const WORLD_ACTOR_PROJECTION_CONTROLLER_SCRIPT = preload("res://scripts/controllers/world_actor_projection_controller.gd")
const WORLD_ITEM_PROJECTION_CONTROLLER_SCRIPT = preload("res://scripts/controllers/world_item_projection_controller.gd")
const WORLD_SELECTION_CONTROLLER_SCRIPT = preload("res://scripts/controllers/world_selection_controller.gd")
const WORLD_PLAYER_CONTROL_CONTROLLER_SCRIPT = preload("res://scripts/controllers/world_player_control_controller.gd")
const WORLD_MOVEMENT_ORDER_SIM_CONTROLLER_SCRIPT = preload("res://scripts/controllers/world_movement_order_sim_controller.gd")
const WORLD_INVENTORY_SIM_CONTROLLER_SCRIPT = preload("res://scripts/controllers/world_inventory_sim_controller.gd")
const WORLD_PARTY_PANEL_CONTROLLER_SCRIPT = preload("res://scripts/controllers/world_party_panel_controller.gd")
const PARTY_INVENTORY_CONTROLLER_SCRIPT = preload("res://scripts/ui/party_inventory_controller.gd")
const LEDGER_SIMULATION_CONTROLLER_SCRIPT = preload("res://scripts/controllers/ledger_simulation_controller.gd")
const WORLD_MAP_COMBAT_SIM_CONTROLLER_SCRIPT = preload("res://scripts/controllers/world_map_combat_sim_controller.gd")
const WORLD_NAVIGATION_BAKER_SCRIPT = preload("res://scripts/navigation/world_navigation_baker.gd")
const FIXED_TICK_SIM_RUNNER_SCRIPT = preload("res://scripts/simulation/fixed_tick_sim_runner.gd")
const GAME_HUD_SCENE = preload("res://scenes/ui/game_hud.tscn")
const WORLD_MAP_COMBAT_SQUAD_ID_PREFIX := "world_squad"
const WORLD_MAP_COMBAT_MEMBER_ID_PREFIX := "world_squad_member"
const WORLD_MAP_COMBAT_POPULATION_SOURCE := "world_squad"

var root_scene: Node
var hud_layer: CanvasLayer


func _ready() -> void:
	root_scene = get_parent()
	call_deferred("_deferred_bootstrap")


func _deferred_bootstrap() -> void:
	_ensure_world_navigation()
	_ensure_hud()
	var controller_specs := _controller_specs()
	for spec in controller_specs:
		_ensure_controller_node(str(spec["name"]), spec["script"])
	for spec in controller_specs:
		_initialize_controller(str(spec["name"]))
	_ensure_world_movement_order_runner()
	_ensure_world_inventory_runner()
	_ensure_world_map_combat_runner()
	call_deferred("_wire_world_map_combat_ui")


func _ensure_world_navigation() -> void:
	if root_scene.find_child("WorldNavigation", true, false) != null:
		return
	var navigation := NavigationRegion3D.new()
	navigation.name = "WorldNavigation"
	navigation.set_script(WORLD_NAVIGATION_BAKER_SCRIPT)
	root_scene.add_child(navigation)


func _ensure_hud() -> void:
	hud_layer = root_scene.get_node_or_null("GameHUD")
	if hud_layer == null:
		hud_layer = GAME_HUD_SCENE.instantiate()
		hud_layer.name = "GameHUD"
		root_scene.add_child(hud_layer)


func _controller_specs() -> Array[Dictionary]:
	return [
		{"name": "GecsWorldController", "script": GECS_WORLD_CONTROLLER_SCRIPT},
		{"name": "WorldMapCombatSimController", "script": WORLD_MAP_COMBAT_SIM_CONTROLLER_SCRIPT},
		{"name": "WorldTimeController", "script": WORLD_TIME_CONTROLLER_SCRIPT},
		{"name": "ActorQueryController", "script": ACTOR_QUERY_CONTROLLER_SCRIPT},
		{"name": "BleedSplotchController", "script": BLEED_SPLOTCH_CONTROLLER_SCRIPT},
		{"name": "DayNightLightingController", "script": DAY_NIGHT_LIGHTING_CONTROLLER_SCRIPT},
		{"name": "FactionController", "script": FACTION_CONTROLLER_SCRIPT},
		{"name": "PopulationController", "script": POPULATION_CONTROLLER_SCRIPT},
		{"name": "PopulationRealizationController", "script": POPULATION_REALIZATION_CONTROLLER_SCRIPT},
		{"name": "WorldActorProjectionController", "script": WORLD_ACTOR_PROJECTION_CONTROLLER_SCRIPT},
		{"name": "WorldItemProjectionController", "script": WORLD_ITEM_PROJECTION_CONTROLLER_SCRIPT},
		{"name": "WorldSelectionController", "script": WORLD_SELECTION_CONTROLLER_SCRIPT},
		{"name": "WorldPlayerControlController", "script": WORLD_PLAYER_CONTROL_CONTROLLER_SCRIPT},
		{"name": "WorldMovementOrderSimController", "script": WORLD_MOVEMENT_ORDER_SIM_CONTROLLER_SCRIPT},
		{"name": "WorldInventorySimController", "script": WORLD_INVENTORY_SIM_CONTROLLER_SCRIPT},
		{"name": "WorldPartyPanelController", "script": WORLD_PARTY_PANEL_CONTROLLER_SCRIPT},
		{"name": "PartyInventoryController", "script": PARTY_INVENTORY_CONTROLLER_SCRIPT},
		{"name": "SettlementController", "script": SETTLEMENT_CONTROLLER_SCRIPT},
		{"name": "TerritoryController", "script": TERRITORY_CONTROLLER_SCRIPT},
		{"name": "RoadController", "script": ROAD_CONTROLLER_SCRIPT},
		{"name": "WorldSimulationController", "script": WORLD_SIMULATION_CONTROLLER_SCRIPT},
		{"name": "LedgerSimulationController", "script": LEDGER_SIMULATION_CONTROLLER_SCRIPT},
		{"name": "SettlementActivityController", "script": SETTLEMENT_ACTIVITY_CONTROLLER_SCRIPT},
		{"name": "JobSystemController", "script": JOB_SYSTEM_CONTROLLER_SCRIPT},
		{"name": "WorldStatusController", "script": WORLD_STATUS_CONTROLLER_SCRIPT},
	]


func _ensure_controller_node(node_name: String, script_resource: Script) -> void:
	var controller := get_node_or_null(node_name)
	if controller == null:
		controller = Node.new()
		controller.name = node_name
		controller.set_script(script_resource)
		add_child(controller)
	if node_name == "WorldMapCombatSimController":
		_configure_world_map_combat_controller(controller)
	if node_name == "WorldActorProjectionController":
		controller.set("projection_update_interval_seconds", 0.05)
	if node_name == "WorldItemProjectionController":
		controller.set("projection_update_interval_seconds", 0.1)


func _configure_world_map_combat_controller(controller: Node) -> void:
	controller.set("use_isolated_ecs_world", false)
	controller.set("process_ecs_world_on_fixed_tick", false)
	controller.set("squad_id_prefix", WORLD_MAP_COMBAT_SQUAD_ID_PREFIX)
	controller.set("member_id_prefix", WORLD_MAP_COMBAT_MEMBER_ID_PREFIX)
	controller.set("population_generation_source", WORLD_MAP_COMBAT_POPULATION_SOURCE)


func _initialize_controller(node_name: String) -> void:
	var controller := get_node_or_null(node_name)
	if controller == null:
		return
	if controller.has_method("initialize"):
		controller.initialize(root_scene, hud_layer)


func _ensure_world_map_combat_runner() -> void:
	var runner := get_node_or_null("WorldMapCombatFixedTickRunner")
	if runner == null:
		runner = Node.new()
		runner.name = "WorldMapCombatFixedTickRunner"
		runner.set_script(FIXED_TICK_SIM_RUNNER_SCRIPT)
		runner.set("target_path", NodePath("../WorldMapCombatSimController"))
		add_child(runner)
	else:
		runner.set("target_path", NodePath("../WorldMapCombatSimController"))


func _ensure_world_movement_order_runner() -> void:
	var runner := get_node_or_null("WorldMovementOrderFixedTickRunner")
	if runner == null:
		runner = Node.new()
		runner.name = "WorldMovementOrderFixedTickRunner"
		runner.set_script(FIXED_TICK_SIM_RUNNER_SCRIPT)
		runner.set("target_path", NodePath("../WorldMovementOrderSimController"))
		add_child(runner)
	else:
		runner.set("target_path", NodePath("../WorldMovementOrderSimController"))


func _ensure_world_inventory_runner() -> void:
	var runner := get_node_or_null("WorldInventoryFixedTickRunner")
	if runner == null:
		runner = Node.new()
		runner.name = "WorldInventoryFixedTickRunner"
		runner.set_script(FIXED_TICK_SIM_RUNNER_SCRIPT)
		runner.set("target_path", NodePath("../WorldInventorySimController"))
		add_child(runner)
	else:
		runner.set("target_path", NodePath("../WorldInventorySimController"))


func _wire_world_map_combat_ui() -> void:
	var runner := get_node_or_null("WorldMapCombatFixedTickRunner")
	if runner == null or not runner.has_method("queue_command") or get_tree() == null:
		return
	var queue_callable := Callable(runner, "queue_command")
	for panel in get_tree().get_nodes_in_group("world_map_squad_command_panel"):
		if panel == null or not panel.has_signal("command_requested"):
			continue
		if not panel.is_connected("command_requested", queue_callable):
			panel.connect("command_requested", queue_callable)
