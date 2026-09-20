extends RefCounted

## Transient disposal execution, owned by InteractionCapability. Orders, inventory
## transactions and actor lookup remain at their existing authorities.
const FLASK_TAG := "tool.cinder_flask"
const RESERVED_BY := "auto_burn_reserved_by_instance_id"

# Furnaces have no ActorQuery record. Index their static projections once, then
# maintain membership from tree lifecycle events; never scan the group per actor.
static var _tree_ref: WeakRef
static var _furnace_cells: Dictionary = {}
static var _furnace_locations: Dictionary = {}
static var _max_assist_radius := 0.0
static var _furnace_cell_size := 1.0

var _target_ref: WeakRef
var _furnace_ref: WeakRef
var _dirty := true
var _last_position := Vector3.INF
var _last_held := false
var _body_available := false
var _ready_at_msec := 0
var assignment_queries := 0


func target() -> Node:
	return _target_ref.get_ref() if _target_ref != null else null


func furnace() -> Node:
	return _furnace_ref.get_ref() if _furnace_ref != null else null


func bind(interaction) -> void:
	var actor = interaction.actor
	var tree: SceneTree = actor.get_tree()
	if _tree_ref == null or _tree_ref.get_ref() != tree:
		_tree_ref = weakref(tree)
		_furnace_cells.clear()
		_furnace_locations.clear()
		_max_assist_radius = 0.0
		tree.node_added.connect(_on_node_added)
		tree.node_removed.connect(_on_node_removed)
		for node in tree.get_nodes_in_group("body_furnace"):
			_register_furnace(node)
	changed(interaction)


func changed(interaction) -> void:
	var actor = interaction.actor
	if not is_instance_valid(actor) or not actor.is_inside_tree():
		return
	_max_assist_radius = maxf(_max_assist_radius, _radius(actor))
	_dirty = true
	_ready_at_msec = 0
	interaction.physics_process_enabled = actor.is_auto_burn_rustdead_enabled() or _target_ref != null or _furnace_ref != null
	var available: bool = actor.requires_fire_to_die() and not actor.is_carried() and (actor.is_downed_state() or actor.life_state == NpcRules.LifeState.DEAD) and not actor.is_fire_destruction_in_progress()
	if available != _body_available:
		_body_available = available
		_wake_nearby.call_deferred(actor.global_position)


func tick(interaction) -> void:
	var actor = interaction.actor
	if not is_instance_valid(actor) or not actor.is_inside_tree():
		return
	var held: bool = not actor.is_auto_burn_rustdead_enabled() or actor.is_carried() or actor.is_sitting() or actor.is_in_combat() or actor.has_active_player_order()
	if held != _last_held:
		_dirty = true
	_last_held = held
	if held:
		cancel(interaction)
		interaction.physics_process_enabled = actor.is_auto_burn_rustdead_enabled()
		return
	if (_target_ref != null and not _live(target())) or (_furnace_ref != null and not _live(furnace())):
		cancel(interaction)
		_dirty = true
	# Position changes matter, idle frames do not. Physical travel/finish/carry
	# still runs in the normal actor order processor, not this decision helper.
	if actor.global_position != _last_position:
		_last_position = actor.global_position
		_dirty = true
	try_assign(interaction)


func try_assign(interaction) -> bool:
	var actor = interaction.actor
	if not _live(actor) or not actor.is_auto_burn_rustdead_enabled():
		return false
	if actor.is_carried() or actor.is_sitting() or actor.is_in_combat() or actor.has_active_player_order():
		return false
	if interaction.current_order_type != interaction.ORDER_TYPE_NONE or not _dirty or Time.get_ticks_msec() < _ready_at_msec:
		return false
	var bridge = BootstrapContext.service(&"gecs_world")
	if bridge == null:
		return false # No scene-group substitute for the canonical actor index.
	_dirty = false
	assignment_queries += 1
	var carried = actor.get_carried_character()
	if _live(carried):
		if not carried.requires_fire_to_die():
			return false
		var destination = _accessible_furnace(actor, carried)
		if destination == null:
			return false
		_furnace_ref = weakref(destination)
		interaction.assign_place_carried_in_furnace_target(destination, false)
		if interaction.current_place_furnace_target == destination:
			return true
		release_furnace(interaction)
		return false
	var destination = _accessible_furnace(actor)
	if destination == null and _find_flask(actor.inventory) == null:
		return false
	var best = null
	var best_distance := _radius(actor) * _radius(actor)
	# ActorQuery's public nearby helper is ALIVE-only. The same GECS indexed
	# query with alive=false includes downed/dead bodies without a parallel index.
	for body in bridge._query_actor_nodes({"position": actor.global_position, "radius": _radius(actor), "alive": false}):
		if not _live(body) or body == actor or not body.requires_fire_to_die() or body.is_carried() or body.is_fire_destruction_in_progress():
			continue
		if _reserved_by_other(body, actor):
			continue
		if destination != null:
			if not destination.can_accept_body(body):
				continue
		elif not body.can_be_destroyed_by_cinder():
			continue
		var distance: float = actor.global_position.distance_squared_to(body.global_position)
		if distance <= best_distance:
			best_distance = distance
			best = body
	if best == null:
		return false
	best.set_meta(RESERVED_BY, actor.get_instance_id())
	_target_ref = weakref(best)
	if destination != null:
		if destination.reserve_for(actor, best):
			_furnace_ref = weakref(destination)
			interaction.assign_carry_target(best, false)
			if interaction.current_carry_target == best:
				return true
	else:
		interaction.assign_finish_off_target(best, false)
		if interaction.current_finish_off_target == best:
			return true
	release(interaction)
	return false


func burn(interaction, body, show_notices := true) -> bool:
	var actor = interaction.actor
	if not _live(actor) or not _live(body) or actor.life_state != NpcRules.LifeState.ALIVE:
		return false
	if not body.has_method("begin_cinder_burn") or not body.can_be_destroyed_by_cinder():
		return false
	if not actor._is_close_enough_to_downed_interaction_target(body):
		return false
	var inventory = actor.inventory
	var flask = _find_flask(inventory)
	if flask == null:
		if show_notices:
			actor.show_world_speech("Need a Cinder Flask", 4.0)
		return false
	# Use InventoryData's transaction snapshot/restore, including live entry
	# identity and allocator state. Publish only AFTER fire accepts the debit;
	# synchronous inventory observers cannot invalidate the unpaid target.
	var snapshot: Dictionary = inventory._snapshot_standard_transaction()
	if not inventory._remove_standard_item_count(flask, 1, false):
		return false
	if not _live(body) or not body.begin_cinder_burn(actor):
		inventory._restore_standard_transaction(snapshot)
		return false
	inventory.changed.emit()
	return true


func _find_flask(inventory):
	if inventory != null:
		for entry in inventory.entries:
			if entry != null and entry.count > 0 and entry.definition != null and FLASK_TAG in entry.definition.tool_tags:
				return entry.definition
	return null


func cancel(interaction) -> void:
	# Only cancel our automatic orders. A replacement manual order owns itself.
	if not interaction.order_was_player_issued:
		if _target_ref != null and interaction.current_order_type == interaction.ORDER_TYPE_CARRY:
			interaction.stop_carry_assignment()
		if _target_ref != null and interaction.current_order_type == interaction.ORDER_TYPE_FINISH_OFF:
			interaction.stop_finish_off_assignment()
		if _furnace_ref != null and interaction.current_order_type == interaction.ORDER_TYPE_PLACE_IN_FURNACE:
			interaction.stop_place_in_furnace_assignment()
	release(interaction)


func release_target(interaction) -> void:
	var body = target()
	_target_ref = null
	if is_instance_valid(body) and is_instance_valid(interaction.actor) and int(body.get_meta(RESERVED_BY, 0)) == interaction.actor.get_instance_id():
		body.remove_meta(RESERVED_BY)
		if body.is_inside_tree():
			_wake_nearby.call_deferred(body.global_position)
	_dirty = true


func release_furnace(interaction) -> void:
	var destination = furnace()
	_furnace_ref = null
	if is_instance_valid(destination):
		destination.release_reservation(interaction.actor)
		if destination.is_inside_tree():
			_wake_nearby.call_deferred(destination.global_position)
	_dirty = true


func release(interaction) -> void:
	release_target(interaction)
	release_furnace(interaction)


func teardown(interaction) -> void:
	release(interaction)
	if is_instance_valid(interaction.actor) and interaction.actor.is_inside_tree() and interaction.actor.requires_fire_to_die():
		_wake_nearby.call_deferred(interaction.actor.global_position)


static func _live(node) -> bool:
	return is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion()


static func _radius(actor) -> float:
	# Existing Inspector control: local assist range, never an invented parallel
	# disposal radius or hidden resource-retry timeout.
	return maxf(actor.assist_scan_radius, actor.interact_distance)


static func _cell(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / _furnace_cell_size), floori(position.z / _furnace_cell_size))


static func _sync_furnace_cell_size() -> void:
	var bridge = BootstrapContext.service(&"gecs_world")
	if bridge == null or is_equal_approx(_furnace_cell_size, maxf(bridge.spatial_cell_size, 1.0)):
		return
	_furnace_cell_size = maxf(bridge.spatial_cell_size, 1.0)
	# Bootstrap can arrive after leaf ready; re-bucket existing weak projections
	# once on that boundary or on an authored spatial-cell-size edit.
	var references: Array = []
	for bucket in _furnace_cells.values():
		references.append_array(bucket.values())
	_furnace_cells.clear()
	_furnace_locations.clear()
	for reference in references:
		_register_furnace(reference.get_ref())


static func _on_node_added(node: Node) -> void:
	if node.has_method("can_accept_body") and node.has_method("reserve_for"):
		_register_furnace.call_deferred(node)


static func _register_furnace(node) -> void:
	if not _live(node):
		return
	var id: int = node.get_instance_id()
	if _furnace_locations.has(id):
		return
	var cell := _cell(node.global_position)
	if not _furnace_cells.has(cell):
		_furnace_cells[cell] = {}
	_furnace_cells[cell][id] = weakref(node)
	_furnace_locations[id] = {"cell": cell, "position": node.global_position}
	_wake_nearby(node.global_position)


static func _on_node_removed(node: Node) -> void:
	var id := node.get_instance_id()
	if not _furnace_locations.has(id):
		return
	var location: Dictionary = _furnace_locations[id]
	_furnace_cells[location.cell].erase(id)
	if _furnace_cells[location.cell].is_empty():
		_furnace_cells.erase(location.cell)
	_furnace_locations.erase(id)
	_wake_nearby.call_deferred(location.position)


static func _accessible_furnace(actor, body = null):
	_sync_furnace_cell_size()
	var minimum := _cell(actor.global_position - Vector3.ONE * _radius(actor))
	var maximum := _cell(actor.global_position + Vector3.ONE * _radius(actor))
	var best = null
	var best_distance := _radius(actor) * _radius(actor)
	for x in range(minimum.x, maximum.x + 1):
		for z in range(minimum.y, maximum.y + 1):
			for reference in _furnace_cells.get(Vector2i(x, z), {}).values():
				var candidate = reference.get_ref()
				if not _live(candidate) or not candidate.is_available_for(actor, body):
					continue
				var distance: float = actor.global_position.distance_squared_to(candidate.global_position)
				if distance <= best_distance:
					best_distance = distance
					best = candidate
	return best


static func _reserved_by_other(body, actor) -> bool:
	var owner_id := int(body.get_meta(RESERVED_BY, 0))
	return owner_id != 0 and owner_id != actor.get_instance_id() and is_instance_id_valid(owner_id)


static func _wake_nearby(position: Vector3) -> void:
	var query = BootstrapContext.service(&"actor_query")
	if query == null:
		return
	var scheduler = BootstrapContext.service(&"ai_scheduler")
	for actor in query.get_nearby_actors(position, _max_assist_radius):
		if not _live(actor) or not actor.is_auto_burn_rustdead_enabled() or actor.global_position.distance_to(position) > _radius(actor):
			continue
		var interaction = actor.get_interaction()
		if interaction == null:
			continue
		var disposal = interaction.rustdead_disposal
		disposal._dirty = true
		# Coalesce availability bursts with existing authored AI jitter, without
		# stealing the actor's AI decision tick or imposing a starving work budget.
		if disposal._ready_at_msec <= Time.get_ticks_msec():
			var jitter: float = scheduler.default_tick_jitter_seconds if scheduler != null else 0.0
			disposal._ready_at_msec = Time.get_ticks_msec() + actor.get_instance_id() % maxi(1, int(jitter * 1000.0))
		interaction.physics_process_enabled = true
