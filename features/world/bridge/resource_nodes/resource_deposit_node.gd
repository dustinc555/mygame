extends StaticBody3D
## Shared leaf bridge: authoring identity/settings in, durable stock projection out.
const DEPOSIT_DEFINITION = preload("res://features/world/resources/resource_deposit_definition.gd")
@export var resource_node_id := ""
@export var deposit_definition: DEPOSIT_DEFINITION
@export var owner_character_path: NodePath
@export var owner_faction_name := ""
var _deposit_controller: WeakRef
var _deposit_bound := false

func _ready() -> void:
	add_to_group(BootstrapContext.SERVICE_CONSUMER_GROUP)
	if BootstrapContext.active != null:
		_on_bootstrap_context_ready(BootstrapContext.active)

func _on_bootstrap_context_ready(context: BootstrapContext) -> void:
	var controller := context.get_optional(&"resource_deposits")
	if controller == null:
		return
	# Legacy authored scenes had blank IDs. Path-scoped migration is deterministic
	# and independent; newly placed content should always author an explicit ID.
	if resource_node_id.is_empty() and context.root_scene != null and is_inside_tree():
		resource_node_id = "legacy:%s:%s" % [context.root_scene.scene_file_path, context.root_scene.get_path_to(self)]
	_deposit_controller = weakref(controller)
	_deposit_bound = controller.bind_deposit(self)

func _exit_tree() -> void:
	var controller := _controller()
	if controller != null:
		controller.detach_deposit(resource_node_id, self)
	_deposit_bound = false

func _controller() -> Node:
	return _deposit_controller.get_ref() if _deposit_controller != null else null

func apply_deposit_state(_state: Dictionary) -> void:
	_deposit_bound = true

func get_stock() -> int:
	var controller := _controller()
	if not _deposit_bound or controller == null:
		return 0
	return int(controller.get_deposit_state(resource_node_id).get("stock", 0))

func is_depleted() -> bool:
	return get_stock() <= 0

func _complete_deposit_attempt(actor: Node, inventory = null) -> Dictionary:
	var controller := _controller()
	if not _deposit_bound or controller == null:
		return {"success": false, "message": "Unavailable"}
	return controller.complete_attempt(self, actor, inventory)

func _claim_deposit_delivery(actor: Node) -> bool:
	var controller := _controller()
	return controller != null and controller.claim_attempt_delivery(self, actor)

func get_explicit_owner_character() -> Node:
	return get_node_or_null(owner_character_path) if not owner_character_path.is_empty() else null

func get_owner_faction_name() -> String:
	if not owner_faction_name.is_empty():
		return owner_faction_name
	var owner_character := get_explicit_owner_character()
	return str(owner_character.get("faction_name")) if owner_character != null else ""
