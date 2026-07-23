extends Node

## Composition root.
##
## GameBootstrap is the only thing that knows the controller topology. It builds
## the four layer roots, installs explicit feature modules into them, registers
## every controller as a service in a BootstrapContext, and injects that context
## into each controller's initialize(). Controllers therefore never reach into the
## scene tree to find each other -- they resolve dependencies by stable service id
## through the context.
##
##   GameBootstrap
##     CoreServices    (engine-level services, level above the layers)
##     ProjectionRoot  (camera-facing scene work)
##     WorldSimRoot    (durable far/off-camera ticking)
##     BridgeRoot      (maps sim <-> projection)
##
## Each feature contributes a module declaring its controllers per layer. Every
## controller is registered in the context before any initialize() runs, so a
## controller can resolve any dependency by service id regardless of install order.

const CORE_SERVICES_MODULE := preload("res://features/core/core_services_module.gd")
const WORLD_MODULE := preload("res://features/world/world_module.gd")
const WORLD_SIM_MODULE := preload("res://features/world_sim/world_sim_module.gd")
const FACTIONS_MODULE := preload("res://features/factions/factions_module.gd")
const ACTORS_MODULE := preload("res://features/actors/actors_module.gd")
const AI_MODULE := preload("res://features/ai/ai_module.gd")
const SETTLEMENTS_MODULE := preload("res://features/settlements/settlements_module.gd")
const INVENTORY_MODULE := preload("res://features/inventory/inventory_module.gd")
const CONVERSATION_MODULE := preload("res://features/conversation/conversation_module.gd")
const UI_MODULE := preload("res://features/ui/ui_module.gd")
const DOORS_MODULE := preload("res://features/doors/doors_module.gd")

# Core services install first (time / GECS / actor lookup that everything else
# resolves); feature modules follow. Order does not affect correctness -- all
# controllers are registered before the initialize() pass -- but keeping core
# first matches the dependency direction.
const MODULES := [
	CORE_SERVICES_MODULE,
	WORLD_MODULE,
	FACTIONS_MODULE,
	WORLD_SIM_MODULE,
	ACTORS_MODULE,
	AI_MODULE,
	SETTLEMENTS_MODULE,
	INVENTORY_MODULE,
	DOORS_MODULE,
	CONVERSATION_MODULE,
	UI_MODULE,
]

const GAME_HUD_SCENE := preload("res://features/ui/projection/game_hud.tscn")

var root_scene: Node
var hud_layer: CanvasLayer

var core_services: Node
var projection_root: Node
var world_sim_root: Node
var bridge_root: Node

var _context: BootstrapContext


func _ready() -> void:
	root_scene = get_parent()
	call_deferred("_deferred_bootstrap")


func _deferred_bootstrap() -> void:
	_ensure_hud()
	_create_roots()

	_context = BootstrapContext.new(root_scene, hud_layer)
	_context.core_services = core_services
	_context.projection_root = projection_root
	_context.world_sim_root = world_sim_root
	_context.bridge_root = bridge_root
	BootstrapContext.active = _context

	var installed: Array[Node] = []
	for module in MODULES:
		installed.append_array(_install_module(module))

	for controller in installed:
		if controller.has_method("initialize"):
			controller.initialize(_context)
	get_tree().call_group(BootstrapContext.SERVICE_CONSUMER_GROUP, "_on_bootstrap_context_ready", _context)


func _exit_tree() -> void:
	if _context != null and BootstrapContext.active == _context:
		BootstrapContext.active = null


func _create_roots() -> void:
	core_services = _ensure_root("CoreServices")
	projection_root = _ensure_root("ProjectionRoot")
	world_sim_root = _ensure_root("WorldSimRoot")
	bridge_root = _ensure_root("BridgeRoot")


func _ensure_root(node_name: String) -> Node:
	var existing := get_node_or_null(node_name)
	if existing != null:
		return existing
	var root := Node.new()
	root.name = node_name
	add_child(root)
	return root


func _install_module(module) -> Array[Node]:
	var nodes: Array[Node] = []
	nodes.append_array(_install_specs(module.CORE, core_services))
	nodes.append_array(_install_specs(module.PROJECTION, projection_root))
	nodes.append_array(_install_specs(module.SIM, world_sim_root))
	nodes.append_array(_install_specs(module.BRIDGE, bridge_root))
	return nodes


func _install_specs(specs: Array, parent_node: Node) -> Array[Node]:
	var nodes: Array[Node] = []
	for spec in specs:
		var node := _install_spec(spec, parent_node)
		if node != null:
			nodes.append(node)
	return nodes


func _install_spec(spec: Dictionary, parent_node: Node) -> Node:
	var node_name := str(spec["name"])
	var node := parent_node.get_node_or_null(node_name)
	if node == null:
		node = Node.new()
		node.name = node_name
		node.set_script(spec["script"])
		parent_node.add_child(node)
	_context.register(spec["service"], node)
	return node


func _ensure_hud() -> void:
	hud_layer = root_scene.get_node_or_null("GameHUD")
	if hud_layer == null:
		hud_layer = GAME_HUD_SCENE.instantiate()
		hud_layer.name = "GameHUD"
		root_scene.add_child(hud_layer)
