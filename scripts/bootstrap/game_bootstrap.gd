extends Node

const PARTY_INVENTORY_CONTROLLER_SCRIPT = preload("res://scripts/ui/party_inventory_controller.gd")
const HUMANOID_DETAILS_CONTROLLER_SCRIPT = preload("res://scripts/ui/humanoid_details_controller.gd")
const WORLD_INTERACTION_CONTROLLER_SCRIPT = preload("res://scripts/controllers/world_interaction_controller.gd")

var root_scene: Node


func _ready() -> void:
	root_scene = get_parent()
	_ensure_controller("PartyInventoryController", PARTY_INVENTORY_CONTROLLER_SCRIPT)
	_ensure_controller("HumanoidDetailsController", HUMANOID_DETAILS_CONTROLLER_SCRIPT)
	_ensure_controller("WorldInteractionController", WORLD_INTERACTION_CONTROLLER_SCRIPT)


func _ensure_controller(node_name: String, script_resource: Script) -> void:
	var controller := get_node_or_null(node_name)
	if controller == null:
		controller = Node.new()
		controller.name = node_name
		controller.set_script(script_resource)
		add_child(controller)
	if controller.has_method("initialize"):
		controller.initialize(root_scene)
