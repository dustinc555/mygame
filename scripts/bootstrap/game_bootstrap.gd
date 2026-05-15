extends Node

const PARTY_INVENTORY_CONTROLLER_SCRIPT = preload("res://scripts/ui/party_inventory_controller.gd")
const HUMANOID_DETAILS_CONTROLLER_SCRIPT = preload("res://scripts/ui/humanoid_details_controller.gd")
const WORLD_INTERACTION_CONTROLLER_SCRIPT = preload("res://scripts/controllers/world_interaction_controller.gd")
const CONVERSATION_CONTROLLER_SCRIPT = preload("res://scripts/controllers/conversation_controller.gd")
const JOB_SYSTEM_CONTROLLER_SCRIPT = preload("res://scripts/controllers/job_system_controller.gd")
const OWNERSHIP_CONTROLLER_SCRIPT = preload("res://scripts/controllers/ownership_controller.gd")
const BUILDING_VISIBILITY_CONTROLLER_SCRIPT = preload("res://scripts/controllers/building_visibility_controller.gd")
const WORLD_TIME_CONTROLLER_SCRIPT = preload("res://scripts/controllers/world_time_controller.gd")
const DAY_NIGHT_LIGHTING_CONTROLLER_SCRIPT = preload("res://scripts/controllers/day_night_lighting_controller.gd")
const WORLD_STATUS_CONTROLLER_SCRIPT = preload("res://scripts/controllers/world_status_controller.gd")
const FACTION_CONTROLLER_SCRIPT = preload("res://scripts/controllers/faction_controller.gd")
const SETTLEMENT_CONTROLLER_SCRIPT = preload("res://scripts/controllers/settlement_controller.gd")
const WORLD_SQUAD_CONTROLLER_SCRIPT = preload("res://scripts/controllers/world_squad_controller.gd")
const WORLD_SIMULATION_CONTROLLER_SCRIPT = preload("res://scripts/controllers/world_simulation_controller.gd")
const WORLD_NAVIGATION_BAKER_SCRIPT = preload("res://scripts/navigation/world_navigation_baker.gd")
const GAME_HUD_SCENE = preload("res://scenes/ui/game_hud.tscn")

var root_scene: Node
var hud_layer: CanvasLayer


func _ready() -> void:
	root_scene = get_parent()
	call_deferred("_deferred_bootstrap")


func _deferred_bootstrap() -> void:
	_ensure_world_navigation()
	_ensure_hud()
	_ensure_controller("WorldTimeController", WORLD_TIME_CONTROLLER_SCRIPT)
	_ensure_controller("DayNightLightingController", DAY_NIGHT_LIGHTING_CONTROLLER_SCRIPT)
	_ensure_controller("FactionController", FACTION_CONTROLLER_SCRIPT)
	_ensure_controller("SettlementController", SETTLEMENT_CONTROLLER_SCRIPT)
	_ensure_controller("WorldSquadController", WORLD_SQUAD_CONTROLLER_SCRIPT)
	_ensure_controller("WorldSimulationController", WORLD_SIMULATION_CONTROLLER_SCRIPT)
	_ensure_controller("PartyInventoryController", PARTY_INVENTORY_CONTROLLER_SCRIPT)
	_ensure_controller("HumanoidDetailsController", HUMANOID_DETAILS_CONTROLLER_SCRIPT)
	_ensure_controller("ConversationController", CONVERSATION_CONTROLLER_SCRIPT)
	_ensure_controller("OwnershipController", OWNERSHIP_CONTROLLER_SCRIPT)
	_ensure_controller("JobSystemController", JOB_SYSTEM_CONTROLLER_SCRIPT)
	_ensure_controller("BuildingVisibilityController", BUILDING_VISIBILITY_CONTROLLER_SCRIPT)
	_ensure_controller("WorldStatusController", WORLD_STATUS_CONTROLLER_SCRIPT)
	_ensure_controller("WorldInteractionController", WORLD_INTERACTION_CONTROLLER_SCRIPT)


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


func _ensure_controller(node_name: String, script_resource: Script) -> void:
	var controller := get_node_or_null(node_name)
	if controller == null:
		controller = Node.new()
		controller.name = node_name
		controller.set_script(script_resource)
		add_child(controller)
	if controller.has_method("initialize"):
		controller.initialize(root_scene, hud_layer)
