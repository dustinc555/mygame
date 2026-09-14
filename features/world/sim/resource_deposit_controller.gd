extends Node
class_name ResourceDepositController
## GECS owns stock. Weak scene bindings only project it, never reseed it.
const SERVICE_ID := &"resource_deposits"
const DEFINITION = preload("res://features/world/resources/resource_deposit_definition.gd")
const SETTINGS := preload("res://features/world/resources/resource_deposit_settings.tres")
var settings: Resource = SETTINGS
signal deposit_changed(deposit_id: String, state: Dictionary)
var _gecs: Node
var _world_time: Node
var _ownership: Node
var _definitions: Dictionary = {}
var _bindings: Dictionary = {}
var _rng := RandomNumberGenerator.new()
## Advanced runtime budgets, not balance settings. One callback is indivisible.
var max_refills_per_frame: int:
	get: return settings.max_refills_per_frame
	set(value): settings.max_refills_per_frame = value
var refill_budget_usec: int:
	get: return roundi(settings.refill_budget_milliseconds * 1000.0)
	set(value): settings.refill_budget_milliseconds = float(value) / 1000.0
var last_drain_count := 0
var last_drain_usec := 0
var _due: Array[Dictionary] = []
var _heap_index: Dictionary = {}
var _committing: Dictionary = {}
var _delivery_actor_by_id: Dictionary = {}
var _reconciling := false
var _draining := false

func initialize(context: BootstrapContext) -> void:
	_gecs = context.require(&"gecs_world")
	_world_time = context.require(&"world_time")
	_ownership = context.get_optional(&"ownership")
	_rng.randomize()
	_world_time.world_minutes_advanced.connect(_on_world_minutes_advanced)
	set_process(false)
	_gecs.world_reindexed.connect(_on_world_reindexed)
	_on_world_reindexed()

func teardown() -> void:
	if is_instance_valid(_gecs) and _gecs.world_reindexed.is_connected(_on_world_reindexed):
		_gecs.world_reindexed.disconnect(_on_world_reindexed)
	_reconciling = false
	if is_instance_valid(_world_time) and _world_time.world_minutes_advanced.is_connected(_on_world_minutes_advanced):
		_world_time.world_minutes_advanced.disconnect(_on_world_minutes_advanced)
	_due.clear()
	_heap_index.clear()
	_committing.clear()
	_delivery_actor_by_id.clear()
	_draining = false
	set_process(false)
	_bindings.clear()
	_definitions.clear()
	_gecs = null
	_world_time = null
	_ownership = null

func bind_deposit(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	var id := str(node.get("resource_node_id"))
	var definition = node.get("deposit_definition")
	if id.strip_edges().is_empty() or not definition is DEFINITION or _gecs == null:
		return false
	var current := _live_node(id)
	if current != null and current != node:
		return false
	var state := get_deposit_state(id)
	if not state.is_empty() and state.deposit_type_id != definition.deposit_type_id:
		return false
	_definitions[id] = definition
	_bindings[id] = weakref(node)
	if state.is_empty():
		var stock_range: Vector2i = definition.get_stock_range()
		state = _gecs.upsert_resource_deposit_state({"deposit_id": id,
			"deposit_type_id": definition.deposit_type_id, "definition_path": definition.resource_path,
			"stock": _rng.randi_range(stock_range.x, stock_range.y), "refill_at_minute": -1.0, "revision": 0})
	_index_due(state)
	_project(id, state)
	return not state.is_empty()

func detach_deposit(id: String, node: Node) -> void:
	if _live_node(id) == node:
		_bindings.erase(id)

func get_deposit_state(id: String) -> Dictionary:
	return _gecs.get_resource_deposit_state(id) if _gecs != null else {}

func remove_deposit(id: String) -> void:
	_remove_due(id)
	_gecs.remove_resource_deposit_state(id)
	_bindings.erase(id)
	_definitions.erase(id)

## Delivery adapters may only spend a one-shot permit issued after authorization.
## This prevents direct calls from minting loot without spending durable stock.
func claim_attempt_delivery(node: Node, actor: Node) -> bool:
	if not is_instance_valid(node) or not is_instance_valid(actor):
		return false
	var id := str(node.get("resource_node_id"))
	if _live_node(id) != node or int(_delivery_actor_by_id.get(id, 0)) != actor.get_instance_id():
		return false
	_delivery_actor_by_id.erase(id)
	return true

func complete_attempt(node: Node, actor: Node, inventory = null) -> Dictionary:
	if not is_instance_valid(node) or not is_instance_valid(actor):
		return {"success": false, "message": "Unavailable"}
	var id := str(node.get("resource_node_id"))
	if _reconciling or _live_node(id) != node or _committing.has(id):
		return {"success": false, "message": "Unavailable"}
	var state := get_deposit_state(id)
	if state.is_empty() or int(state.stock) <= 0:
		return {"success": false, "message": "Depleted", "depleted": true}
	_committing[id] = true
	if node.has_method("can_complete_deposit_attempt") and not node.can_complete_deposit_attempt(actor):
		_committing.erase(id)
		return {"success": false, "message": "Requirements not met"}
	var metadata: Dictionary = {}
	if OwnershipUtils.is_owned(node):
		if _ownership == null or not _ownership.request_take_item(actor, node):
			_committing.erase(id)
			return {"success": false, "message": "Access denied"}
		metadata = _ownership.get_take_item_metadata(actor, node)
	# Inventory signals can trigger GECS synchronization/save or another worker.
	# Publish them only after stock and its deadline have also committed.
	var destination = inventory if inventory != null else actor.get("inventory")
	var signals_were_blocked := false
	if destination != null:
		signals_were_blocked = destination.is_blocking_signals()
		destination.set_block_signals(true)
	_delivery_actor_by_id[id] = actor.get_instance_id()
	var result: Dictionary = node.deliver_deposit_attempt(actor, inventory, metadata)
	_delivery_actor_by_id.erase(id)
	if result.get("success", false):
		state.stock = int(state.stock) - 1
		state.revision = int(state.revision) + 1
		if state.stock == 0:
			var definition = _definitions[id]
			if definition.refill_enabled:
				var delay: Vector2 = definition.get_refill_range_minutes()
				state.refill_at_minute = float(_world_time.total_world_minutes) + _rng.randf_range(delay.x, delay.y)
		state = _gecs.upsert_resource_deposit_state(state)
		_index_due(state)
		_project(id, state)
		deposit_changed.emit(id, state)
		result["depleted"] = int(state.stock) == 0
	if destination != null:
		destination.set_block_signals(signals_were_blocked)
		if result.get("success", false) and result.get("inventory_changed", true) and not signals_were_blocked:
			destination.changed.emit()
	_committing.erase(id)
	return result

## GECS emits this before WorldSimulationController hydrates the saved clock.
## Stop stale work synchronously; never advance a loaded record in this callback.
func _on_world_reindexed() -> void:
	_due.clear()
	_heap_index.clear()
	set_process(false)
	if not _reconciling:
		_reconciling = true
		call_deferred("_reconcile_after_load")

func _reconcile_after_load() -> void:
	if not _reconciling or _gecs == null:
		return
	var states: Dictionary = _gecs.get_resource_deposit_states()
	for id in states:
		var state: Dictionary = states[id]
		var path := str(state.get("definition_path", ""))
		if not _definitions.has(id) and not path.is_empty() and ResourceLoader.exists(path):
			var definition = load(path)
			if definition is DEFINITION:
				_definitions[id] = definition
		_index_due(state)
	_reconciling = false
	# Only known weak bindings, never a scene-tree scan. Missing old-save state
	# seeds from authored data once; current saved values always win.
	for id in _bindings.keys():
		var node := _live_node(id)
		if node != null:
			bind_deposit(node)
		else:
			_bindings.erase(id)
	_on_world_minutes_advanced(float(_world_time.total_world_minutes))

func _process(_delta: float) -> void:
	drain_due()

func _on_world_minutes_advanced(_minute: float) -> void:
	set_process(not _reconciling and not _due.is_empty() and float(_due[0].at) <= float(_world_time.total_world_minutes))

func drain_due() -> int:
	if _draining:
		return 0
	last_drain_count = 0
	if _reconciling or _world_time == null:
		return 0
	_draining = true
	var started := Time.get_ticks_usec()
	var now := float(_world_time.total_world_minutes)
	while not _reconciling and not _due.is_empty() and float(_due[0].at) <= now:
		if last_drain_count >= maxi(1, max_refills_per_frame) or Time.get_ticks_usec() - started >= maxi(1, refill_budget_usec):
			break
		var id := str(_due[0].id)
		_remove_due(id)
		last_drain_count += 1
		var state := get_deposit_state(id)
		var definition = _definitions.get(id)
		if state.is_empty() or int(state.stock) > 0 or definition == null:
			continue
		var stock_range: Vector2i = definition.get_stock_range()
		state.stock = _rng.randi_range(stock_range.x, stock_range.y)
		state.refill_at_minute = -1.0
		state.revision = int(state.revision) + 1
		state = _gecs.upsert_resource_deposit_state(state)
		_project(id, state)
		deposit_changed.emit(id, state)
	_draining = false
	last_drain_usec = Time.get_ticks_usec() - started
	_on_world_minutes_advanced(now)
	return last_drain_count

func get_queue_size() -> int:
	return _due.size()

## Indexed binary heap: at most one event per depleted deposit, O(log n) edits.
func _index_due(state: Dictionary) -> void:
	var id := str(state.get("deposit_id", ""))
	_remove_due(id)
	if int(state.get("stock", 0)) > 0 or float(state.get("refill_at_minute", -1.0)) < 0:
		return
	_heap_index[id] = _due.size()
	_due.append({"id": id, "at": float(state.refill_at_minute)})
	_sift_up(_due.size() - 1)
	_on_world_minutes_advanced(float(_world_time.total_world_minutes))

func _remove_due(id: String) -> void:
	if not _heap_index.has(id):
		return
	var index := int(_heap_index[id])
	_swap(index, _due.size() - 1)
	_due.pop_back()
	_heap_index.erase(id)
	if index < _due.size():
		_sift_down(_sift_up(index))

func _swap(a: int, b: int) -> void:
	var entry := _due[a]
	_due[a] = _due[b]
	_due[b] = entry
	_heap_index[str(_due[a].id)] = a
	_heap_index[str(_due[b].id)] = b

func _sift_up(index: int) -> int:
	while index > 0:
		var parent := (index - 1) / 2
		if float(_due[parent].at) <= float(_due[index].at):
			break
		_swap(parent, index)
		index = parent
	return index

func _sift_down(index: int) -> void:
	while index * 2 + 1 < _due.size():
		var child := index * 2 + 1
		if child + 1 < _due.size() and float(_due[child + 1].at) < float(_due[child].at):
			child += 1
		if float(_due[index].at) <= float(_due[child].at):
			break
		_swap(index, child)
		index = child

func _live_node(id: String) -> Node:
	var ref: WeakRef = _bindings.get(id)
	return ref.get_ref() if ref != null else null

func _project(id: String, state: Dictionary) -> void:
	var node := _live_node(id)
	if node != null and node.has_method("apply_deposit_state"):
		node.apply_deposit_state(state)
