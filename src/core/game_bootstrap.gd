extends Node

const PARTY_INVENTORY_CONTROLLER_SCRIPT = preload("res://src/inventory/bridge/party_inventory_controller.gd")
const HUMANOID_DETAILS_CONTROLLER_SCRIPT = preload("res://src/ui/bridge/humanoid_details_controller.gd")
const WORLD_INTERACTION_CONTROLLER_SCRIPT = preload("res://src/world/bridge/world_interaction_controller.gd")
const CHARACTER_APPEARANCE_CONTROLLER_SCRIPT = preload("res://src/actors/projection/appearance/character_appearance_controller.gd")
const CONVERSATION_CONTROLLER_SCRIPT = preload("res://src/conversation/conversation_controller.gd")
const JOB_SYSTEM_CONTROLLER_SCRIPT = preload("res://src/settlements/sim/job_system_controller.gd")
const OWNERSHIP_CONTROLLER_SCRIPT = preload("res://src/settlements/sim/ownership_controller.gd")
const BUILDING_VISIBILITY_CONTROLLER_SCRIPT = preload("res://src/world/projection/building_visibility_controller.gd")
const WORLD_TIME_CONTROLLER_SCRIPT = preload("res://src/core/world_time_controller.gd")
const BLEED_SPLOTCH_CONTROLLER_SCRIPT = preload("res://src/world/projection/bleed_splotch_controller.gd")
const DAY_NIGHT_LIGHTING_CONTROLLER_SCRIPT = preload("res://src/world/projection/lighting/day_night_lighting_controller.gd")
const PERCEPTION_CONTROLLER_SCRIPT = preload("res://src/actors/bridge/perception/perception_controller.gd")
const WORLD_STATUS_CONTROLLER_SCRIPT = preload("res://src/world_sim/bridge/world_status_controller.gd")
const FACTION_CONTROLLER_SCRIPT = preload("res://src/world_sim/sim/faction_controller.gd")
const SETTLEMENT_CONTROLLER_SCRIPT = preload("res://src/settlements/bridge/settlement_controller.gd")
const TERRITORY_CONTROLLER_SCRIPT = preload("res://src/world_sim/sim/territory_controller.gd")
const ROAD_CONTROLLER_SCRIPT = preload("res://src/world_sim/sim/roads/road_controller.gd")
const WORLD_SIM_SQUAD_CONTROLLER_SCRIPT = preload("res://src/world_sim/sim/world_sim_squad_controller.gd")
const FACTION_WORLD_SIM_CONTROLLER_SCRIPT = preload("res://src/world_sim/sim/faction_world_sim_controller.gd")
const ENCOUNTER_CONTROLLER_SCRIPT = preload("res://src/world_sim/sim/encounter_controller.gd")
const WORLD_EVENT_CHOICE_CONTROLLER_SCRIPT = preload("res://src/world_sim/sim/world_event_choice_controller.gd")
const WORLD_SIMULATION_CONTROLLER_SCRIPT = preload("res://src/world_sim/sim/world_simulation_controller.gd")
const LAW_ORDER_CONTROLLER_SCRIPT = preload("res://src/settlements/sim/law/law_order_controller.gd")
const GECS_WORLD_CONTROLLER_SCRIPT = preload("res://src/core/gecs_world_controller.gd")
const ACTOR_QUERY_CONTROLLER_SCRIPT = preload("res://src/core/actor_query_controller.gd")
const AI_SCHEDULER_CONTROLLER_SCRIPT = preload("res://src/ai/bridge/ai_scheduler_controller.gd")
const POPULATION_CONTROLLER_SCRIPT = preload("res://src/world_sim/sim/population/population_controller.gd")
const POPULATION_REALIZATION_CONTROLLER_SCRIPT = preload("res://src/world_sim/bridge/population_realization_controller.gd")
const LEDGER_SIMULATION_CONTROLLER_SCRIPT = preload("res://src/world_sim/sim/ledger_simulation_controller.gd")
const WORLD_NAVIGATION_BAKER_SCRIPT = preload("res://src/core/navigation/world_navigation_baker.gd")
const GAME_HUD_SCENE = preload("res://src/ui/projection/game_hud.tscn")

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


func _ensure_world_navigation() -> void:
	# A scene that already ships its own NavigationRegion3D (e.g. an editor-baked
	# zone navmesh) must NOT also get the runtime baker: two regions on the same
	# navigation map overlap and produce erratic closest-point/pathing results.
	if _find_navigation_region(root_scene) != null:
		return
	var navigation := NavigationRegion3D.new()
	navigation.name = "WorldNavigation"
	navigation.set_script(WORLD_NAVIGATION_BAKER_SCRIPT)
	root_scene.add_child(navigation)


func _find_navigation_region(node: Node) -> NavigationRegion3D:
	if node is NavigationRegion3D:
		return node
	for child in node.get_children():
		var found := _find_navigation_region(child)
		if found != null:
			return found
	return null


func _ensure_hud() -> void:
	hud_layer = root_scene.get_node_or_null("GameHUD")
	if hud_layer == null:
		hud_layer = GAME_HUD_SCENE.instantiate()
		hud_layer.name = "GameHUD"
		root_scene.add_child(hud_layer)


func _controller_specs() -> Array[Dictionary]:
	return [
		{"name": "GecsWorldController", "script": GECS_WORLD_CONTROLLER_SCRIPT},
		{"name": "WorldTimeController", "script": WORLD_TIME_CONTROLLER_SCRIPT},
		{"name": "ActorQueryController", "script": ACTOR_QUERY_CONTROLLER_SCRIPT},
		{"name": "AiSchedulerController", "script": AI_SCHEDULER_CONTROLLER_SCRIPT},
		{"name": "BleedSplotchController", "script": BLEED_SPLOTCH_CONTROLLER_SCRIPT},
		{"name": "DayNightLightingController", "script": DAY_NIGHT_LIGHTING_CONTROLLER_SCRIPT},
		{"name": "PerceptionController", "script": PERCEPTION_CONTROLLER_SCRIPT},
		{"name": "FactionController", "script": FACTION_CONTROLLER_SCRIPT},
		{"name": "PopulationController", "script": POPULATION_CONTROLLER_SCRIPT},
		{"name": "PopulationRealizationController", "script": POPULATION_REALIZATION_CONTROLLER_SCRIPT},
		{"name": "SettlementController", "script": SETTLEMENT_CONTROLLER_SCRIPT},
		{"name": "TerritoryController", "script": TERRITORY_CONTROLLER_SCRIPT},
		{"name": "RoadController", "script": ROAD_CONTROLLER_SCRIPT},
		{"name": "WorldEventChoiceController", "script": WORLD_EVENT_CHOICE_CONTROLLER_SCRIPT},
		{"name": "WorldSimSquadController", "script": WORLD_SIM_SQUAD_CONTROLLER_SCRIPT},
		{"name": "FactionWorldSimController", "script": FACTION_WORLD_SIM_CONTROLLER_SCRIPT},
		{"name": "EncounterController", "script": ENCOUNTER_CONTROLLER_SCRIPT},
		{"name": "WorldSimulationController", "script": WORLD_SIMULATION_CONTROLLER_SCRIPT},
		{"name": "LedgerSimulationController", "script": LEDGER_SIMULATION_CONTROLLER_SCRIPT},
		{"name": "LawOrderController", "script": LAW_ORDER_CONTROLLER_SCRIPT},
		{"name": "PartyInventoryController", "script": PARTY_INVENTORY_CONTROLLER_SCRIPT},
		{"name": "HumanoidDetailsController", "script": HUMANOID_DETAILS_CONTROLLER_SCRIPT},
		{"name": "CharacterAppearanceController", "script": CHARACTER_APPEARANCE_CONTROLLER_SCRIPT},
		{"name": "ConversationController", "script": CONVERSATION_CONTROLLER_SCRIPT},
		{"name": "OwnershipController", "script": OWNERSHIP_CONTROLLER_SCRIPT},
		{"name": "JobSystemController", "script": JOB_SYSTEM_CONTROLLER_SCRIPT},
		{"name": "BuildingVisibilityController", "script": BUILDING_VISIBILITY_CONTROLLER_SCRIPT},
		{"name": "WorldStatusController", "script": WORLD_STATUS_CONTROLLER_SCRIPT},
		{"name": "WorldInteractionController", "script": WORLD_INTERACTION_CONTROLLER_SCRIPT},
	]


func _ensure_controller_node(node_name: String, script_resource: Script) -> void:
	var controller := get_node_or_null(node_name)
	if controller == null:
		controller = Node.new()
		controller.name = node_name
		controller.set_script(script_resource)
		add_child(controller)


func _initialize_controller(node_name: String) -> void:
	var controller := get_node_or_null(node_name)
	if controller == null:
		return
	if controller.has_method("initialize"):
		controller.initialize(root_scene, hud_layer)
