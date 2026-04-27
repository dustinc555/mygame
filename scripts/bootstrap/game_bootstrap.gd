extends Node

const PARTY_INVENTORY_CONTROLLER_SCRIPT = preload("res://scripts/ui/party_inventory_controller.gd")
const HUMANOID_DETAILS_CONTROLLER_SCRIPT = preload("res://scripts/ui/humanoid_details_controller.gd")
const WORLD_INTERACTION_CONTROLLER_SCRIPT = preload("res://scripts/controllers/world_interaction_controller.gd")
const GAME_HUD_SCENE = preload("res://scenes/ui/game_hud.tscn")

var root_scene: Node
var hud_layer: CanvasLayer


func _ready() -> void:
	root_scene = get_parent()
	call_deferred("_deferred_bootstrap")


func _deferred_bootstrap() -> void:
	_ensure_hud()
	_ensure_controller("PartyInventoryController", PARTY_INVENTORY_CONTROLLER_SCRIPT)
	_ensure_controller("HumanoidDetailsController", HUMANOID_DETAILS_CONTROLLER_SCRIPT)
	_ensure_controller("WorldInteractionController", WORLD_INTERACTION_CONTROLLER_SCRIPT)


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
