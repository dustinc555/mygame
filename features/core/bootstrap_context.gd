extends RefCounted

class_name BootstrapContext

## Wiring context built by GameBootstrap (the composition root) and injected into
## every controller's initialize(). Controllers resolve their dependencies by
## stable service id through this object instead of reaching into the scene tree
## (no get_parent(), no group scans, no "GameBootstrap/Foo" paths).
##
## Layer roots model the execution layers described in AGENT.md:
##   projection -> camera-facing scene work, world_sim -> durable far ticking,
##   bridge -> mapping sim <-> projection. CoreServices sits level above them.
##
## Leaf scene nodes the bootstrap does not construct (spawned actors, authored
## buildings) reach the active context through BootstrapContext.active /
## BootstrapContext.service(). A static on the class_name is used instead of an
## autoload so the symbol resolves at compile time everywhere -- including bare
## `--script` validation runs where autoload globals are not registered.

const LAYER_CORE := &"core"
const LAYER_PROJECTION := &"projection"
const LAYER_SIM := &"sim"
const LAYER_BRIDGE := &"bridge"

## Live context published by the composition root (GameBootstrap) for leaf scene
## nodes that have no injection point. Set on startup, cleared on teardown.
static var active: BootstrapContext

var root_scene: Node
var hud_layer: CanvasLayer

var core_services: Node
var projection_root: Node
var world_sim_root: Node
var bridge_root: Node

var _services: Dictionary = {}


func _init(scene: Node = null, hud: CanvasLayer = null) -> void:
	root_scene = scene
	hud_layer = hud


func register(service_id: StringName, node: Node) -> void:
	if service_id == &"":
		push_error("BootstrapContext.register: empty service id for %s" % node)
		return
	if node == null:
		push_error("BootstrapContext.register: null node for service '%s'" % service_id)
		return
	if _services.has(service_id) and _services[service_id] != node:
		push_error("BootstrapContext.register: service '%s' already registered" % service_id)
		return
	_services[service_id] = node


func has_service(service_id: StringName) -> bool:
	return _services.has(service_id)


## Resolve a required dependency. Logs an error if it is missing so wiring gaps
## surface during validation instead of failing silently far away.
func require(service_id: StringName) -> Node:
	var node := _services.get(service_id, null) as Node
	if node == null:
		push_error("BootstrapContext.require: no service registered for '%s'" % service_id)
	return node


## Resolve an optional dependency. Returns null without logging when absent.
func get_optional(service_id: StringName) -> Node:
	return _services.get(service_id, null) as Node


## Null-safe service resolution for leaf scene nodes. Returns null when no context
## is active (e.g. a test/demo scene without a bootstrap), matching prior misses.
static func service(service_id: StringName) -> Node:
	return active.get_optional(service_id) if active != null else null


func root_for(layer: StringName) -> Node:
	match layer:
		LAYER_CORE:
			return core_services
		LAYER_PROJECTION:
			return projection_root
		LAYER_SIM:
			return world_sim_root
		LAYER_BRIDGE:
			return bridge_root
	push_error("BootstrapContext.root_for: unknown layer '%s'" % layer)
	return null
