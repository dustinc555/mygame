extends Node

class_name FarmWorkBridge

signal work_offers_changed(settlement_id: String)
signal work_offer_delta(settlement_id: String, removed_offer_ids: PackedStringArray, upserted_offers: Array)
signal work_availability_changed(settlement_id: String)

const SERVICE_ID := &"farm_work"
const WATER_META := "farm_water"
const ACTIVE_SETTLEMENT_WORK_META := &"active_settlement_work"
## How far an "auto" field looks for seed stock when choosing its crop.
const AUTO_CROP_SEED_RADIUS := 60.0
const BUCKET_CAPACITY := 10.0
const WATERING_CAN_CAPACITY := 16.0
const WATER_PER_CELL := 5.0
const INTERACTION_RANGE := 1.65
const WORK_COMMIT_INTERVAL := 0.25
const TRAVEL_CHECK_INTERVAL := 0.1
const MAX_STALLED_SECONDS := 30.0
const UNREACHABLE_RETRY_MSEC := 15000
const FARM_CONTROLLER := preload("res://features/farming/sim/farm_controller.gd")

var _context: BootstrapContext
var _farm: Node
var _gecs: Node
var _job_system: Node
var _stock_controller: Node
var _assignments: Dictionary = {}
## actor instance ID -> exact checked-out tool and its origin container. Loans
## survive across consecutive farm cells; a low-urgency return offer appears
## only after no ordinary Farm offer can be accepted.
var _borrowed_tools: Dictionary = {}
var _unreachable_until_msec: Dictionary = {}
var _offer_cache: Array = []
var _offer_by_cell: Dictionary = {}
var _offer_cache_dirty := true
var _pending_work_commits: Array = []
var _process_sim_time := 0.0
var _last_process_usec := 0
var _last_assignment_loop_usec := 0
var _last_commit_flush_usec := 0
var _last_tool_equip_timings: Dictionary = {}


func initialize(context: BootstrapContext) -> void:
	_context = context
	_farm = context.get_optional(FARM_CONTROLLER.SERVICE_ID)
	_gecs = context.get_optional(&"gecs_world")
	_job_system = context.get_optional(&"job_system")
	_stock_controller = context.get_optional(InventoryStockController.SERVICE_ID)
	_bind_offer_cache_signals()
	if _gecs != null and not _gecs.world_reindexed.is_connected(_on_world_reindexed):
		_gecs.world_reindexed.connect(_on_world_reindexed)
	if _stock_controller != null and _stock_controller.has_signal("stock_changed") \
			and not _stock_controller.stock_changed.is_connected(_on_stock_changed):
		_stock_controller.stock_changed.connect(_on_stock_changed)
	add_to_group("job_provider")
	if _job_system != null and _job_system.has_method("register_job_provider"):
		_job_system.register_job_provider(self)
	# The sim cannot see world containers; lend it our view of seed stock so
	# "auto" fields can resolve a crop.
	if _farm != null and _farm.has_method("set_auto_crop_resolver"):
		_farm.call("set_auto_crop_resolver", Callable(self, "resolve_auto_crop"))
	set_process(false)


func teardown() -> void:
	_unbind_offer_cache_signals()
	if _gecs != null and _gecs.world_reindexed.is_connected(_on_world_reindexed):
		_gecs.world_reindexed.disconnect(_on_world_reindexed)
	if _stock_controller != null and is_instance_valid(_stock_controller) and _stock_controller.has_signal("stock_changed") \
			and _stock_controller.stock_changed.is_connected(_on_stock_changed):
		_stock_controller.stock_changed.disconnect(_on_stock_changed)
	if _job_system != null and is_instance_valid(_job_system) and _job_system.has_method("unregister_job_provider"):
		_job_system.unregister_job_provider(self)
	if _farm != null and is_instance_valid(_farm) and _farm.has_method("set_auto_crop_resolver"):
		_farm.call("set_auto_crop_resolver", Callable())
	_cancel_all_assignments()
	_job_system = null
	_stock_controller = null
	_gecs = null
	_farm = null


func get_provider_name() -> String:
	return "Settlement Farming"


func get_job_category_specs(_settlement_id := "") -> Array:
	return [{"entry_id": "category:farm", "category": "farm", "display_name": "Farm"}]


func get_available_work_offers(settlement_id := "") -> Array:
	var offers: Array = []
	if _farm == null:
		return offers
	_refresh_offer_cache_if_needed()
	var claimed_cells := {}
	for assignment_value in _assignments.values():
		var assignment: Dictionary = assignment_value
		claimed_cells["%s|%s" % [str(assignment.get("plot_id", "")), str(assignment.get("cell_key", ""))]] = true
	for offer_value in _offer_cache:
		var offer: Dictionary = offer_value
		var plot_id := str(offer.get("plot_id", ""))
		var cell_key := str(offer.get("cell_key", ""))
		var plot_settlement_id := str(offer.get("settlement_id", ""))
		if not settlement_id.is_empty() and plot_settlement_id != settlement_id:
			continue
		if claimed_cells.has("%s|%s" % [plot_id, cell_key]):
			continue
		offers.append(offer)
	_append_borrowed_tool_return_offers(offers, settlement_id)
	return offers


func _refresh_offer_cache_if_needed() -> void:
	if not _offer_cache_dirty:
		return
	_offer_cache_dirty = false
	_offer_cache.clear()
	_offer_by_cell.clear()
	if _farm == null:
		return
	if _farm.has_method("get_available_work_records"):
		for work_value in _farm.call("get_available_work_records"):
			_append_cached_offer(work_value as Dictionary)
		return
	# Compatibility for isolated providers/validators. Production FarmController
	# uses the one-snapshot API above; this legacy path is never on its hot road.
	if not _farm.has_method("get_plots") or not _farm.has_method("get_cell_work"):
		return
	for state_value in (_farm.call("get_plots") as Dictionary).values():
		var state: Dictionary = state_value
		if _farm.has_method("is_active_field") and not bool(_farm.call("is_active_field", state)):
			continue
		for cell_key_value in (state.get("cells", {}) as Dictionary).keys():
			var work: Dictionary = _farm.call("get_cell_work", str(state.get("plot_id", "")), str(cell_key_value))
			if work.is_empty():
				continue
			work["settlement_id"] = str(state.get("settlement_id", ""))
			work["owner_faction_id"] = str(state.get("owner_faction_id", ""))
			_append_cached_offer(work)


func _append_cached_offer(work: Dictionary) -> Dictionary:
	if work.is_empty():
		return {}
	var plot_id := str(work.get("plot_id", ""))
	var cell_key := str(work.get("cell_key", ""))
	if plot_id.is_empty() or cell_key.is_empty():
		return {}
	var offer := {
		"offer_id": "farming:%s:%s" % [plot_id, cell_key],
		"provider": self,
		"category": "farm",
		"plot_id": plot_id,
		"cell_key": cell_key,
		"settlement_id": str(work.get("settlement_id", "")),
		"owner_faction_id": str(work.get("owner_faction_id", "")),
		"world_position": work.get("world_position", Vector3.ZERO),
		"allowed_actor_ids": work.get("allowed_actor_ids", PackedStringArray()),
		"urgency": 0.5,
	}
	_offer_cache.append(offer)
	_offer_by_cell["%s|%s" % [plot_id, cell_key]] = offer
	return offer


func _append_borrowed_tool_return_offers(offers: Array, requested_settlement_id: String) -> void:
	for actor_key_value in _borrowed_tools.keys().duplicate():
		var actor_key := int(actor_key_value)
		if _assignments.has(actor_key):
			continue
		var loan: Dictionary = _borrowed_tools[actor_key]
		var actor_ref := loan.get("actor_ref") as WeakRef
		var store_ref := loan.get("store_ref") as WeakRef
		var actor := actor_ref.get_ref() as Node if actor_ref != null else null
		var store := store_ref.get_ref() as Node3D if store_ref != null else null
		if actor == null or not is_instance_valid(actor):
			_borrowed_tools.erase(actor_key)
			continue
		if store == null or not is_instance_valid(store):
			# The tool remains with the worker; only the vanished origin contract
			# is forgotten, so no item is destroyed or recreated.
			_borrowed_tools.erase(actor_key)
			continue
		var settlement_id := str(loan.get("settlement_id", ""))
		if not requested_settlement_id.is_empty() and settlement_id != requested_settlement_id:
			continue
		var offer := _borrowed_tool_return_offer(actor_key)
		if not offer.is_empty():
			offers.append(offer)


func _borrowed_tool_return_offer(actor_key: int) -> Dictionary:
	var loan: Dictionary = _borrowed_tools.get(actor_key, {})
	var actor_ref := loan.get("actor_ref") as WeakRef
	var store_ref := loan.get("store_ref") as WeakRef
	var actor := actor_ref.get_ref() as Node if actor_ref != null else null
	var store := store_ref.get_ref() as Node3D if store_ref != null else null
	if actor == null or store == null or not is_instance_valid(actor) or not is_instance_valid(store):
		return {}
	return {
		"offer_id": "farming:return_tool:%s" % _actor_work_id(actor),
		"provider": self,
		"category": "farm",
		"job_entry_id": "category:farm",
		"action": "return_borrowed_tool",
		"settlement_id": str(loan.get("settlement_id", "")),
		"owner_faction_id": str(loan.get("owner_faction_id", "")),
		"world_position": store.global_position,
		"allowed_actor_ids": PackedStringArray([_actor_work_id(actor)]),
		"urgency": -1.0,
	}


func _begin_borrowed_tool_return(actor: Node) -> String:
	if actor == null or not (actor is Node3D):
		return "Worker unavailable"
	var actor_key := actor.get_instance_id()
	var loan: Dictionary = _borrowed_tools.get(actor_key, {})
	if loan.is_empty() or _assignments.has(actor_key):
		return "No borrowed tool to return"
	var store_ref := loan.get("store_ref") as WeakRef
	var store := store_ref.get_ref() as Node3D if store_ref != null else null
	if store == null or not is_instance_valid(store):
		_borrowed_tools.erase(actor_key)
		return "Borrowed tool origin is gone"
	_stow_weapon(actor)
	var target: Vector3 = store.get_interaction_position(actor) if store.has_method("get_interaction_position") else store.global_position
	_assignments[actor_key] = {
		"actor": actor,
		"action": "return_borrowed_tool",
		"stage": "return_tool",
		"expected_target": target,
		"automatic": true,
		"traveling": true,
		"last_travel_check_time": _process_sim_time,
		"travel_seconds": 0.0,
		"stalled_seconds": 0.0,
		"last_actor_position": (actor as Node3D).global_position,
	}
	_mark_settlement_work_active(actor, true)
	set_process(true)
	_move_actor(actor, target, false)
	return "Worker assigned to return tool"


func _bind_offer_cache_signals() -> void:
	if _farm == null:
		return
	if _farm.has_signal("plot_changed") and not _farm.plot_changed.is_connected(_on_offer_source_changed):
		_farm.plot_changed.connect(_on_offer_source_changed)
	if _farm.has_signal("plot_cells_changed") and not _farm.plot_cells_changed.is_connected(_on_offer_cells_changed):
		_farm.plot_cells_changed.connect(_on_offer_cells_changed)
	if _farm.has_signal("plot_removed") and not _farm.plot_removed.is_connected(_on_offer_source_removed):
		_farm.plot_removed.connect(_on_offer_source_removed)


func _unbind_offer_cache_signals() -> void:
	if _farm == null:
		return
	if _farm.has_signal("plot_changed") and _farm.plot_changed.is_connected(_on_offer_source_changed):
		_farm.plot_changed.disconnect(_on_offer_source_changed)
	if _farm.has_signal("plot_cells_changed") and _farm.plot_cells_changed.is_connected(_on_offer_cells_changed):
		_farm.plot_cells_changed.disconnect(_on_offer_cells_changed)
	if _farm.has_signal("plot_removed") and _farm.plot_removed.is_connected(_on_offer_source_removed):
		_farm.plot_removed.disconnect(_on_offer_source_removed)


func _on_offer_source_changed(_plot_id: String, state: Dictionary) -> void:
	_offer_cache_dirty = true
	work_offers_changed.emit(str(state.get("settlement_id", "")))


func _on_offer_cells_changed(plot_id: String, changed_cells: Dictionary, settlement_id: String) -> void:
	_refresh_offer_cache_if_needed()
	var removed_ids := PackedStringArray()
	var upserted: Array = []
	for cell_key_value in changed_cells.keys():
		var cell_key := str(cell_key_value)
		var cache_key := "%s|%s" % [plot_id, cell_key]
		var previous: Dictionary = _offer_by_cell.get(cache_key, {})
		if not previous.is_empty():
			var previous_id := str(previous.get("offer_id", ""))
			removed_ids.append(previous_id)
			_remove_cached_offer(previous_id)
		var next_work: Dictionary = _farm.call("get_cell_work", plot_id, cell_key) if _farm != null and _farm.has_method("get_cell_work") else {}
		if not next_work.is_empty():
			var next_offer := _append_cached_offer(next_work)
			if not next_offer.is_empty():
				upserted.append(next_offer)
	work_offer_delta.emit(settlement_id, removed_ids, upserted)


func _remove_cached_offer(offer_id: String) -> void:
	if offer_id.is_empty():
		return
	for index in range(_offer_cache.size() - 1, -1, -1):
		if str((_offer_cache[index] as Dictionary).get("offer_id", "")) == offer_id:
			var removed: Dictionary = _offer_cache[index]
			_offer_by_cell.erase("%s|%s" % [str(removed.get("plot_id", "")), str(removed.get("cell_key", ""))])
			_offer_cache.remove_at(index)
			return


func _on_offer_source_removed(_plot_id: String) -> void:
	_offer_cache_dirty = true
	work_offers_changed.emit("")


func _on_stock_changed(settlement_id: String, _facility_id: String) -> void:
	work_availability_changed.emit(settlement_id)


func accept_work_offer(offer: Dictionary, actor: Node) -> String:
	if actor == null:
		return "Select a worker first"
	if str(offer.get("action", "")) == "return_borrowed_tool":
		return _begin_borrowed_tool_return(actor)
	return assign_cell(str(offer.get("plot_id", "")), str(offer.get("cell_key", "")), [actor], true)


func has_active_work_for_actor(actor: Node) -> bool:
	return actor != null and _assignments.has(actor.get_instance_id())


func has_active_work_for_plot(plot_id: String) -> bool:
	if plot_id.is_empty():
		return false
	for assignment_value in _assignments.values():
		if str((assignment_value as Dictionary).get("plot_id", "")) == plot_id:
			return true
	return false


func get_active_cell_keys_for_plot(plot_id: String) -> PackedStringArray:
	var keys := PackedStringArray()
	for assignment_value in _assignments.values():
		var assignment: Dictionary = assignment_value
		if str(assignment.get("plot_id", "")) != plot_id:
			continue
		var key := str(assignment.get("cell_key", ""))
		if not key.is_empty() and not keys.has(key):
			keys.append(key)
	return keys


## Report physical work already underway when a logical field is retired.
func retire_plot_work(plot_id: String) -> PackedStringArray:
	var active_keys := PackedStringArray()
	if plot_id.is_empty():
		return active_keys
	for actor_key_value in _assignments.keys():
		var assignment: Dictionary = _assignments.get(actor_key_value, {})
		if str(assignment.get("plot_id", "")) == plot_id:
			active_keys.append(str(assignment.get("cell_key", "")))
	return active_keys


func cancel_work_for_actor(actor: Node) -> bool:
	if actor == null or not _assignments.has(actor.get_instance_id()):
		return false
	_cancel(actor.get_instance_id())
	return true


## Population LOD destroys the worker projection. Return town-owned borrowed
## tools while both the actor and origin container still exist, then discard
## only the volatile assignment.
func prepare_actor_for_derealization(actor: Node) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var actor_key := actor.get_instance_id()
	if _borrowed_tools.has(actor_key):
		_complete_tool_return(actor_key)
		return
	if _assignments.has(actor_key):
		_cancel(actor_key)


func assign_cell(plot_id: String, cell_key: String, actors: Array, automatic := false) -> String:
	if _farm == null or _farm.get_cell_work(plot_id, cell_key).is_empty():
		return "Cell work is no longer valid"
	if actors.is_empty():
		return "Select a worker first"
	var first_failure := ""
	for actor_value in actors:
		var actor := actor_value as Node3D
		if actor == null or not is_instance_valid(actor):
			continue
		if not _farm.can_actor_command_plot(actor, plot_id):
			first_failure = "Cannot work: field belongs to another faction"
			continue
		var result := _assign_cell_to_actor(actor, plot_id, cell_key, automatic, false, -1, [], not automatic, not automatic)
		if result.is_empty():
			return "1 worker assigned"
		if first_failure.is_empty():
			first_failure = result
	return first_failure if not first_failure.is_empty() else "No selected worker can take this cell"


func assign_cell_sequence(targets: Array, actor: Node, manual := true) -> String:
	if actor == null or not is_instance_valid(actor) or not (actor is Node3D):
		return "Select a worker first"
	if targets.is_empty():
		return "No eligible field work"
	var pending: Array = targets.duplicate(true)
	var target_count := pending.size()
	var result := _start_next_command_target(actor as Node3D, pending)
	return "%d cells queued" % target_count if result.is_empty() else result


func _start_next_command_target(actor: Node3D, pending: Array) -> String:
	var first_failure := ""
	while not pending.is_empty():
		var target: Dictionary = pending.pop_front()
		var plot_id := str(target.get("plot_id", ""))
		var cell_key := str(target.get("cell_key", ""))
		var result := _assign_cell_to_actor(
			actor,
			plot_id,
			cell_key,
			false,
			false,
			int(target.get("request_revision", -1)),
			pending,
			true,
			true
		)
		if result.is_empty():
			return ""
		if first_failure.is_empty():
			first_failure = result
		if result == "Cannot work: field belongs to another faction":
			return result
		if result not in ["No eligible field work", "Field work request changed", "Cell is already assigned"]:
			_cancel_command_target(target, actor)
			_cancel_command_targets(pending, actor)
			pending.clear()
			return result
	return first_failure if not first_failure.is_empty() else "No eligible field work"


func _cancel_command_targets(targets: Array, actor: Node) -> void:
	for target_value in targets:
		_cancel_command_target(target_value as Dictionary, actor)


func _cancel_command_target(target: Dictionary, actor: Node) -> void:
	if _farm == null or actor == null or target.is_empty() or not _farm.has_method("cancel_cell_operation"):
		return
	_farm.call(
		"cancel_cell_operation",
		str(target.get("plot_id", "")),
		str(target.get("cell_key", "")),
		int(target.get("request_revision", -1)),
		_actor_work_id(actor)
	)


func assign_seed_processing(processor: Node3D, crop_id: String, actors: Array) -> String:
	if processor == null or not processor.has_method("can_process_crop"):
		return "Seed processor unavailable"
	if actors.is_empty():
		return "Select a worker first"
	var first_failure := ""
	for actor_value in actors:
		var actor := actor_value as Node3D
		if actor == null or _assignments.has(actor.get_instance_id()):
			continue
		if not _can_actor_access_store(actor, processor):
			first_failure = "Cannot process seeds: storage is locked or private"
			continue
		if not bool(processor.call("can_process_crop", crop_id, actor)):
			first_failure = "No produce available or seed storage is full"
			continue
		_stow_weapon(actor)
		var target: Vector3 = processor.get_interaction_position(actor) if processor.has_method("get_interaction_position") else processor.global_position
		_assignments[actor.get_instance_id()] = {
			"actor": actor, "action": "process_seeds", "processor": processor,
			"crop_id": crop_id, "expected_target": target, "progress_seconds": 0.0,
			"stage": "work", "automatic": false, "traveling": true, "travel_check_accumulated": 0.0,
			"last_travel_check_time": _process_sim_time,
			"travel_seconds": 0.0, "stalled_seconds": 0.0,
			"last_actor_position": actor.global_position,
		}
		_mark_settlement_work_active(actor, true)
		set_process(true)
		_move_actor(actor, target, true)
		_set_farming_visual(actor, false, "", target, 0.0)
		return "Worker assigned to process seeds"
	return first_failure if not first_failure.is_empty() else "Selected workers are already busy"


func _process(delta: float) -> void:
	var process_started := Time.get_ticks_usec()
	if _farm == null or _assignments.is_empty():
		_last_process_usec = 0
		set_process(false)
		return
	_pending_work_commits.clear()
	_process_sim_time += maxf(0.0, delta)
	var assignment_loop_started := Time.get_ticks_usec()
	for actor_key in _assignments.keys().duplicate():
		var assignment: Dictionary = _assignments.get(actor_key, {})
		var travel_elapsed := delta
		if bool(assignment.get("traveling", false)):
			if not assignment.has("last_travel_check_time"):
				assignment["last_travel_check_time"] = _process_sim_time - maxf(0.0, delta)
			var actor := _live_node_3d(assignment.get("actor"))
			if actor == null:
				_cancel(int(actor_key))
				continue
			var player_override := actor != null and bool(assignment.get("automatic", false)) \
					and actor.has_method("has_active_player_order") and bool(actor.call("has_active_player_order"))
			var expected: Vector3 = assignment.get("expected_target", Vector3.ZERO)
			var in_interaction_range := actor != null and actor.global_position.distance_to(expected) <= INTERACTION_RANGE
			travel_elapsed = maxf(0.0, _process_sim_time - float(assignment.get("last_travel_check_time", _process_sim_time)))
			if not player_override and not in_interaction_range \
					and actor != null and _has_move_target(actor) \
					and travel_elapsed + 0.000001 < TRAVEL_CHECK_INTERVAL:
				_assignments[actor_key] = assignment
				continue
			assignment["last_travel_check_time"] = _process_sim_time
			_assignments[actor_key] = assignment
		_process_assignment(int(actor_key), delta, true, travel_elapsed)
	_last_assignment_loop_usec = Time.get_ticks_usec() - assignment_loop_started
	var commit_flush_started := Time.get_ticks_usec()
	_flush_pending_work_commits()
	_last_commit_flush_usec = Time.get_ticks_usec() - commit_flush_started
	_last_process_usec = Time.get_ticks_usec() - process_started


func get_last_process_msec() -> float:
	return float(_last_process_usec) / 1000.0


func get_last_process_breakdown() -> Dictionary:
	return {
		"assignment_loop_msec": float(_last_assignment_loop_usec) / 1000.0,
		"commit_flush_msec": float(_last_commit_flush_usec) / 1000.0,
	}


func _assign_cell_to_actor(actor: Node3D, plot_id: String, cell_key: String, automatic := false, equipped_only := false, expected_request_revision := -1, command_targets: Array = [], replace_claimed := false, replace_actor_work := false) -> String:
	var actor_key := actor.get_instance_id()
	var actor_was_busy := _assignments.has(actor_key)
	if actor_was_busy and automatic:
		return "Selected worker is already busy"
	if _farm.has_method("can_actor_command_plot") and not bool(_farm.call("can_actor_command_plot", actor, plot_id)):
		return "Cannot work: field belongs to another faction"
	var claimed: Array[String] = []
	for assignment in _assignments.values():
		if str(assignment.get("plot_id", "")) == plot_id:
			claimed.append(str(assignment.get("cell_key", "")))
	_append_unreachable_cells(plot_id, claimed)
	var cell_is_claimed := claimed.has(cell_key)
	var work: Dictionary = _farm.get_cell_work(plot_id, cell_key)
	if work.is_empty():
		return "No eligible field work"
	if expected_request_revision >= 0 and int(work.get("request_revision", -1)) != expected_request_revision:
		return "Field work request changed"
	var allowed_actor_ids := PackedStringArray(work.get("allowed_actor_ids", PackedStringArray()))
	if not allowed_actor_ids.is_empty() and not allowed_actor_ids.has(_actor_work_id(actor)):
		return "Cell is reserved for another selected worker"
	var tool_tag := str(work.get("required_tool_tag", ""))
	var tool_label := str(work.get("required_tool_label", "tool"))
	var owner_faction_id := str(work.get("owner_faction_id", ""))
	var settlement_id := str(work.get("settlement_id", ""))
	var seed_store: Node3D = null
	if str(work.get("action", "")) == "plant" and not _has_item(actor, work.get("seed_item"), 1):
		seed_store = _nearest_seed_store(actor.global_position, work.get("seed_item"), owner_faction_id, settlement_id, actor)
		if seed_store == null:
			var message := "Cannot plant: no %s in pockets or seed storage" % _item_name(work.get("seed_item"), "seeds")
			_speak(actor, message)
			return message
	if str(work.get("action", "")) == "harvest":
		var produce = work.get("produce_item")
		var inventory = _inventory(actor)
		var expected_yield := _expected_harvest_yield(actor, work)
		if inventory == null or expected_yield <= 0 or not inventory.can_add_item_count(produce, expected_yield):
			var message := "Cannot harvest: no inventory space"
			_speak(actor, message)
			return message
	if actor_was_busy:
		var current: Dictionary = _assignments.get(actor_key, {})
		if str(current.get("plot_id", "")) == plot_id \
				and str(current.get("cell_key", "")) == cell_key \
				and int(current.get("request_revision", -1)) == int(work.get("request_revision", -1)) \
				and str(current.get("action", "")) == str(work.get("action", "")) \
				and str(current.get("crop_id", "")) == str(work.get("crop_id", "")):
			if not command_targets.is_empty():
				current["command_targets"] = command_targets.duplicate(true)
				_assignments[actor_key] = current
			return ""
		if not replace_actor_work:
			return "Selected worker is already busy"
		_cancel(actor_key)
	if cell_is_claimed:
		if not replace_claimed:
			return "Cell is already assigned"
		_cancel_claimed_cell(plot_id, cell_key)
	var tool_loan := {}
	var tool_failure := ""
	if equipped_only:
		tool_failure = _require_equipped_tool(actor, tool_tag, tool_label)
	elif tool_tag.is_empty() or _actor_has_tool(actor, tool_tag):
		tool_failure = _ensure_tool(actor, tool_tag, tool_label)
	elif automatic and _is_town_worker(actor, settlement_id):
		if _borrowed_tools.has(actor_key):
			tool_failure = "Return borrowed tool before switching tools"
		else:
			tool_loan = _nearest_tool_store(
				actor.global_position,
				tool_tag,
				owner_faction_id,
				settlement_id,
				actor
			)
			if tool_loan.is_empty():
				tool_failure = "Cannot %s: no %s in town tool storage" % [_verb_for_tag(tool_tag), tool_label]
	else:
		tool_failure = "Cannot %s: no %s" % [_verb_for_tag(tool_tag), tool_label]
	if not tool_failure.is_empty():
		_speak(actor, tool_failure)
		return tool_failure
	work["actor"] = actor
	work["expected_target"] = work.get("world_position", Vector3.ZERO)
	work["pending_work_seconds"] = 0.0
	work["travel_seconds"] = 0.0
	work["stalled_seconds"] = 0.0
	work["traveling"] = true
	work["travel_check_accumulated"] = 0.0
	work["last_travel_check_time"] = _process_sim_time
	work["last_actor_position"] = actor.global_position
	work["stage"] = "work"
	work["automatic"] = automatic
	if not command_targets.is_empty():
		work["command_targets"] = command_targets.duplicate(true)
	if not tool_loan.is_empty():
		work["stage"] = "fetch_tool"
		work["tool_store"] = tool_loan.get("store")
		work["borrowed_tool"] = tool_loan.get("definition")
		var tool_store := tool_loan.get("store") as Node3D
		work["expected_target"] = tool_store.get_interaction_position(actor) if tool_store.has_method("get_interaction_position") else tool_store.global_position
	elif seed_store != null:
		work["stage"] = "fetch_seed"
		work["seed_store"] = seed_store
		work["expected_target"] = seed_store.get_interaction_position(actor) if seed_store.has_method("get_interaction_position") else seed_store.global_position
	_assignments[actor_key] = work
	_mark_settlement_work_active(actor, true)
	set_process(true)
	if not tool_loan.is_empty():
		# Town employment reserves and checks out the exact stack immediately.
		# The worker still travels and works physically, but storage-path failures
		# can no longer prevent a calculated farmer from starting.
		_complete_tool_fetch(actor_key)
		return "" if _assignments.has(actor_key) else "Cannot check out required tool"
	if str(work.get("action", "")) == "water":
		_prepare_water_assignment(actor_key)
	_move_actor(actor, work.get("expected_target", Vector3.ZERO), not automatic)
	_set_farming_visual(actor, false, "", work.get("expected_target", Vector3.ZERO), 0.0)
	return ""


func _process_assignment(actor_key: int, delta: float, defer_commit := false, travel_elapsed := -1.0) -> void:
	var assignment: Dictionary = _assignments.get(actor_key, {})
	var actor := _live_node_3d(assignment.get("actor"))
	if actor == null:
		_cancel(actor_key)
		return
	if bool(assignment.get("automatic", false)) and actor.has_method("has_active_player_order") and bool(actor.call("has_active_player_order")):
		_cancel(actor_key)
		return
	var expected: Vector3 = assignment.get("expected_target", Vector3.ZERO)
	if _has_conflicting_player_order(actor, expected):
		_cancel(actor_key)
		return
	if actor.global_position.distance_to(expected) > INTERACTION_RANGE:
		var started_travel_leg := not bool(assignment.get("traveling", false))
		if started_travel_leg:
			_reset_travel_state(assignment, actor)
		else:
			assignment["traveling"] = true
		_assignments[actor_key] = assignment
		_set_farming_visual(actor, false, "", expected, 0.0)
		var timeout_delta := delta if started_travel_leg else travel_elapsed if travel_elapsed >= 0.0 else delta
		if _travel_timed_out(actor_key, assignment, actor, timeout_delta):
			if str(assignment.get("stage", "work")) == "work" and not str(assignment.get("plot_id", "")).is_empty():
				_mark_temporarily_unreachable(assignment)
			_speak(actor, "Cannot reach farming target; trying other work")
			_cancel(actor_key)
			return
		if not _has_move_target(actor):
			_move_actor(actor, expected, not bool(assignment.get("automatic", false)))
		return
	_stop_actor_movement(actor)
	assignment["traveling"] = false
	assignment["travel_check_accumulated"] = 0.0
	assignment["travel_seconds"] = 0.0
	assignment["stalled_seconds"] = 0.0
	assignment["last_actor_position"] = actor.global_position
	_assignments[actor_key] = assignment
	if str(assignment.get("stage", "work")) == "refill":
		_complete_refill(actor_key)
		return
	if str(assignment.get("stage", "work")) == "fetch_tool":
		_complete_tool_fetch(actor_key)
		return
	if str(assignment.get("stage", "work")) == "fetch_seed":
		_complete_seed_fetch(actor_key)
		return
	if str(assignment.get("stage", "work")) == "return_tool":
		_complete_tool_return(actor_key)
		return
	var action := str(assignment.get("action", ""))
	if action == "process_seeds":
		_process_seed_assignment(actor_key, delta)
		return
	if action == "water" and _container_water(actor) < WATER_PER_CELL:
		_prepare_water_assignment(actor_key)
		return
	var required := maxf(0.01, float(assignment.get("required_seconds", 1.0)))
	var pending := float(assignment.get("pending_work_seconds", 0.0)) + maxf(0.0, delta)
	var durable_progress := float(assignment.get("progress_seconds", 0.0))
	var displayed_progress := minf(required, durable_progress + pending)
	assignment["pending_work_seconds"] = pending
	_assignments[actor_key] = assignment
	_set_farming_visual(actor, true, action, expected, displayed_progress / required)
	var completing := displayed_progress >= required
	if pending < WORK_COMMIT_INTERVAL and not completing:
		return

	var inventory = _inventory(actor)
	var completion_item = null
	var completion_amount := 0
	if completing and action == "plant":
		completion_item = assignment.get("seed_item")
		completion_amount = 1
		if not _consume_item(actor, completion_item, completion_amount):
			_speak(actor, "Cannot plant: no %s" % _item_name(completion_item, "seeds"))
			_cancel(actor_key)
			return
	elif completing and action == "harvest":
		completion_item = assignment.get("produce_item")
		completion_amount = _expected_harvest_yield(actor, assignment)
		if inventory == null or completion_item == null or completion_amount <= 0 \
				or not inventory.can_add_item_count(completion_item, completion_amount) \
				or not inventory.add_item_count(completion_item, completion_amount):
			_speak(actor, "Cannot harvest: no inventory space")
			_cancel(actor_key)
			return

	var commit := {
		"actor_key": actor_key,
		"actor": actor,
		"assignment": assignment,
		"action": action,
		"expected": expected,
		"durable_progress": durable_progress,
		"required": required,
		"pending": pending,
		"farming_level": _farming_level(actor),
		"completion_item": completion_item,
		"completion_amount": completion_amount,
	}
	if defer_commit and _farm.has_method("apply_work_batch"):
		_pending_work_commits.append(commit)
		return
	var result: Dictionary = _farm.apply_work(
		str(assignment.get("plot_id", "")),
		str(assignment.get("cell_key", "")),
		action,
		pending,
		float(commit.get("farming_level", 0.0)),
		int(assignment.get("request_revision", -1))
	)
	_finalize_work_commit(commit, result)


func _flush_pending_work_commits() -> void:
	if _pending_work_commits.is_empty():
		return
	var commits := _pending_work_commits.duplicate(false)
	_pending_work_commits.clear()
	var requests: Array = []
	for commit_value in commits:
		var commit: Dictionary = commit_value
		var assignment: Dictionary = commit.get("assignment", {})
		requests.append({
			"plot_id": str(assignment.get("plot_id", "")),
			"cell_key": str(assignment.get("cell_key", "")),
			"action": str(commit.get("action", "")),
			"seconds": float(commit.get("pending", 0.0)),
			"farming_level": float(commit.get("farming_level", 0.0)),
			"expected_request_revision": int(assignment.get("request_revision", -1)),
		})
	var results: Array = _farm.call("apply_work_batch", requests)
	for index in commits.size():
		var result: Dictionary = results[index] if index < results.size() and results[index] is Dictionary else {}
		_finalize_work_commit(commits[index], result)


func _finalize_work_commit(commit: Dictionary, result: Dictionary) -> void:
	var actor_key := int(commit.get("actor_key", 0))
	var actor := _live_node_3d(commit.get("actor"))
	var assignment: Dictionary = commit.get("assignment", {})
	var action := str(commit.get("action", ""))
	var completion_item = commit.get("completion_item")
	var completion_amount := int(commit.get("completion_amount", 0))
	if actor == null or not is_instance_valid(actor) or not _assignments.has(actor_key):
		_rollback_completion_item(actor, action, completion_item, completion_amount)
		return
	if result.is_empty():
		_rollback_completion_item(actor, action, completion_item, completion_amount)
		_speak(actor, "Field work is no longer valid")
		_cancel(actor_key)
		return
	var required := maxf(0.01, float(result.get("required_seconds", commit.get("required", 1.0))))
	assignment["required_seconds"] = required
	assignment["progress_seconds"] = float(result.get("progress_seconds", commit.get("durable_progress", 0.0)))
	assignment["pending_work_seconds"] = 0.0
	_assignments[actor_key] = assignment
	_set_farming_visual(actor, true, action, commit.get("expected", Vector3.ZERO), float(assignment["progress_seconds"]) / required)
	if not bool(result.get("completed", false)):
		_rollback_completion_item(actor, action, completion_item, completion_amount)
		return
	if action == "water":
		_set_container_water(actor, maxf(0.0, _container_water(actor) - WATER_PER_CELL))
	_finish_and_continue(actor_key)


func _rollback_completion_item(actor: Node, action: String, item, amount: int) -> void:
	if item == null or amount <= 0:
		return
	var inventory = _inventory(actor)
	if inventory == null:
		return
	if action == "plant":
		inventory.add_item_count(item, amount)
	elif action == "harvest":
		inventory.remove_item_count(item, amount)


func _travel_timed_out(actor_key: int, assignment: Dictionary, actor: Node3D, delta: float) -> bool:
	var previous: Vector3 = assignment.get("last_actor_position", actor.global_position)
	var moved := actor.global_position.distance_to(previous)
	assignment["travel_seconds"] = float(assignment.get("travel_seconds", 0.0)) + maxf(0.0, delta)
	assignment["stalled_seconds"] = 0.0 if moved >= 0.05 else float(assignment.get("stalled_seconds", 0.0)) + maxf(0.0, delta)
	assignment["last_actor_position"] = actor.global_position
	_assignments[actor_key] = assignment
	# Distance is not failure. Long routes remain valid while the actor is making
	# progress; only an actually stalled route times out.
	return float(assignment["stalled_seconds"]) >= MAX_STALLED_SECONDS


func _finish_and_continue(actor_key: int, completed := true) -> void:
	var assignment: Dictionary = _assignments.get(actor_key, {})
	var actor := _live_node_3d(assignment.get("actor"))
	var command_targets: Array = assignment.get("command_targets", [])
	_assignments.erase(actor_key)
	if actor != null and is_instance_valid(actor) and not command_targets.is_empty():
		var next_result := _start_next_command_target(actor, command_targets)
		if next_result.is_empty():
			return
	_mark_settlement_work_active(actor, false)
	_set_farming_visual(actor, false, "", Vector3.ZERO, 0.0)
	_refresh_process_state()
	var return_offer := _borrowed_tool_return_offer(actor_key)
	if not return_offer.is_empty():
		work_offer_delta.emit(
			str(return_offer.get("settlement_id", "")),
			PackedStringArray(),
			[return_offer]
		)


func _process_seed_assignment(actor_key: int, delta: float) -> void:
	var assignment: Dictionary = _assignments.get(actor_key, {})
	var actor := _live_node_3d(assignment.get("actor"))
	var processor := _live_node(assignment.get("processor"))
	if actor == null or processor == null or not is_instance_valid(processor):
		_cancel(actor_key)
		return
	if not _can_actor_access_store(actor, processor):
		_speak(actor, "Cannot process seeds: storage is locked or private")
		_cancel(actor_key)
		return
	var duration := maxf(0.1, float(processor.get("processing_seconds")))
	var progress := minf(duration, float(assignment.get("progress_seconds", 0.0)) + delta)
	assignment["progress_seconds"] = progress
	_assignments[actor_key] = assignment
	_set_farming_visual(actor, true, "process_seeds", assignment.get("expected_target", Vector3.ZERO), progress / duration)
	if progress < duration:
		return
	var result: Dictionary = processor.call("complete_processing", str(assignment.get("crop_id", "")), actor)
	_speak(actor, str(result.get("message", "Seed processing finished")))
	_cancel(actor_key)


func _prepare_water_assignment(actor_key: int) -> void:
	var assignment: Dictionary = _assignments.get(actor_key, {})
	var actor := _live_node_3d(assignment.get("actor"))
	if actor == null:
		return
	if _container_water(actor) >= WATER_PER_CELL:
		return
	var source: Node3D = _nearest_water_source(actor.global_position) as Node3D
	if source == null:
		_speak(actor, "Cannot water: no water source")
		_cancel(actor_key)
		return
	assignment["stage"] = "refill"
	assignment["water_source"] = source
	assignment["expected_target"] = source.global_position
	_reset_travel_state(assignment, actor)
	_assignments[actor_key] = assignment
	_set_farming_visual(actor, false, "", source.global_position, 0.0)
	_move_actor(actor, source.global_position, not bool(assignment.get("automatic", false)))


func _complete_refill(actor_key: int) -> void:
	var assignment: Dictionary = _assignments.get(actor_key, {})
	var actor := _live_node_3d(assignment.get("actor"))
	var source = assignment.get("water_source")
	if actor == null or source == null or not is_instance_valid(source):
		_cancel(actor_key)
		return
	var capacity := _container_capacity(actor)
	var draw_result := {"drawn": 0.0, "message": "Water source is dry"}
	if not source.has_method("draw_water_for_actor"):
		_speak(actor, "Cannot take water: source has no ownership contract")
		_cancel(actor_key)
		return
	draw_result = source.call("draw_water_for_actor", capacity - _container_water(actor), actor)
	var drawn := float(draw_result.get("drawn", 0.0))
	if drawn <= 0.0:
		_speak(actor, str(draw_result.get("message", "Cannot take water")))
		_cancel(actor_key)
		return
	_set_container_water(actor, _container_water(actor) + drawn)
	assignment["stage"] = "work"
	assignment["expected_target"] = assignment.get("world_position", Vector3.ZERO)
	_reset_travel_state(assignment, actor)
	_assignments[actor_key] = assignment
	_move_actor(actor, assignment["expected_target"], not bool(assignment.get("automatic", false)))


func _complete_tool_fetch(actor_key: int) -> void:
	var assignment: Dictionary = _assignments.get(actor_key, {})
	var actor := _live_node_3d(assignment.get("actor"))
	var store := _live_node(assignment.get("tool_store"))
	var definition := assignment.get("borrowed_tool") as ItemDefinition
	if actor == null or store == null or not is_instance_valid(store) or definition == null:
		_release_assignment_tool_reservation(actor_key, assignment)
		_cancel(actor_key)
		return
	var owner_faction_id := str(assignment.get("owner_faction_id", ""))
	if not _can_actor_access_store(actor, store, owner_faction_id):
		_release_assignment_tool_reservation(actor_key, assignment)
		_speak(actor, "Cannot borrow tool: storage is locked or private")
		_cancel(actor_key)
		return
	var inventory = _inventory(actor)
	var reservation: Dictionary = store.call("get_item_reservation_snapshot", actor) if store.has_method("get_item_reservation_snapshot") else {}
	if inventory == null or reservation.is_empty() or not store.has_method("withdraw_reserved_item_to") \
			or not bool(store.call("withdraw_reserved_item_to", definition, actor, inventory)):
		_release_assignment_tool_reservation(actor_key, assignment)
		_speak(actor, "Cannot borrow tool: it is no longer available")
		_cancel(actor_key)
		return
	var equipment = actor.get_equipment() if actor.has_method("get_equipment") else null
	var previous_definition = equipment.get_equipped_item("weapon") if equipment != null else null
	var previous_stack_id := str(equipment.get_equipped_stack_id("weapon")) if equipment != null and equipment.has_method("get_equipped_stack_id") else ""
	_borrowed_tools[actor_key] = {
		"actor_ref": weakref(actor),
		"store_ref": weakref(store),
		"definition": definition,
		"stack_id": str(reservation.get("stack_id", "")),
		"previous_definition": previous_definition,
		"previous_stack_id": previous_stack_id,
		"settlement_id": str(assignment.get("settlement_id", "")),
		"owner_faction_id": owner_faction_id,
	}
	var tool_failure := _ensure_tool(actor, str(assignment.get("required_tool_tag", "")), str(assignment.get("required_tool_label", "tool")))
	if not tool_failure.is_empty():
		if store.has_method("return_borrowed_item_from"):
			store.call("return_borrowed_item_from", definition, actor, inventory, str(reservation.get("stack_id", "")))
		_borrowed_tools.erase(actor_key)
		_speak(actor, tool_failure)
		_cancel(actor_key)
		return
	var seed_store := _live_node_3d(assignment.get("seed_store"))
	if seed_store != null and is_instance_valid(seed_store) and not _has_item(actor, assignment.get("seed_item"), 1):
		assignment["stage"] = "fetch_seed"
		assignment["expected_target"] = seed_store.get_interaction_position(actor) if seed_store.has_method("get_interaction_position") else seed_store.global_position
	else:
		assignment["stage"] = "work"
		assignment["expected_target"] = assignment.get("world_position", Vector3.ZERO)
	_reset_travel_state(assignment, actor)
	_assignments[actor_key] = assignment
	_move_actor(actor, assignment["expected_target"], not bool(assignment.get("automatic", false)))


func _complete_seed_fetch(actor_key: int) -> void:
	var assignment: Dictionary = _assignments.get(actor_key, {})
	var actor := _live_node_3d(assignment.get("actor"))
	var store := _live_node(assignment.get("seed_store"))
	var seed_item = assignment.get("seed_item")
	if actor == null or store == null or not is_instance_valid(store) or store.get("inventory") == null:
		_cancel(actor_key)
		return
	if not _can_actor_access_store(actor, store, str(assignment.get("owner_faction_id", ""))):
		_speak(actor, "Cannot plant: seed storage is locked or private")
		_cancel(actor_key)
		return
	var inventory = _inventory(actor)
	if inventory == null or not store.inventory.has_method("transfer_item_count_to") \
			or not store.inventory.transfer_item_count_to(seed_item, 1, inventory):
		_speak(actor, "Cannot plant: seed storage is empty or worker cannot carry seeds")
		_cancel(actor_key)
		return
	assignment["stage"] = "work"
	assignment["expected_target"] = assignment.get("world_position", Vector3.ZERO)
	_reset_travel_state(assignment, actor)
	_assignments[actor_key] = assignment
	_move_actor(actor, assignment["expected_target"], not bool(assignment.get("automatic", false)))


func _complete_tool_return(actor_key: int) -> void:
	var assignment: Dictionary = _assignments.get(actor_key, {})
	var actor := _live_node(assignment.get("actor"))
	var loan: Dictionary = _borrowed_tools.get(actor_key, {})
	var store_ref := loan.get("store_ref") as WeakRef
	var store := store_ref.get_ref() as Node if store_ref != null else null
	var definition := loan.get("definition") as ItemDefinition
	var borrowed_stack_id := str(loan.get("stack_id", ""))
	if actor == null or not is_instance_valid(actor):
		_assignments.erase(actor_key)
		_borrowed_tools.erase(actor_key)
		_refresh_process_state()
		return
	if store == null or not is_instance_valid(store) or definition == null:
		# Origin furniture disappeared. Keep the real tool with the worker and
		# end only the loan contract.
		_borrowed_tools.erase(actor_key)
		_cancel(actor_key)
		return
	var inventory = _inventory(actor)
	var equipment = actor.get_equipment() if actor.has_method("get_equipment") else null
	var returned := false
	if equipment != null and equipment.get_equipped_item("weapon") == definition \
			and str(equipment.get_equipped_stack_id("weapon")) == borrowed_stack_id \
			and store.has_method("return_borrowed_equipped_item"):
		returned = bool(store.call("return_borrowed_equipped_item", definition, actor, equipment, borrowed_stack_id, _stack_snapshot(borrowed_stack_id)))
	elif inventory != null and store.has_method("return_borrowed_item_from"):
		returned = bool(store.call("return_borrowed_item_from", definition, actor, inventory, borrowed_stack_id))
	if not returned:
		_cancel(actor_key)
		return
	var previous_definition := loan.get("previous_definition") as ItemDefinition
	var previous_stack_id := str(loan.get("previous_stack_id", ""))
	if previous_definition != null:
		var previous_entry = _find_inventory_entry_by_stack_id(inventory, previous_stack_id, previous_definition)
		if previous_entry != null and equipment != null:
			_equip_carried_tool(actor, equipment, previous_entry)
	_borrowed_tools.erase(actor_key)
	_assignments.erase(actor_key)
	_mark_settlement_work_active(actor, false)
	_set_farming_visual(actor, false, "", Vector3.ZERO, 0.0)
	_refresh_process_state()
	var settlement_id := str(loan.get("settlement_id", ""))
	work_offer_delta.emit(
		settlement_id,
		PackedStringArray(["farming:return_tool:%s" % _actor_work_id(actor)]),
		[]
	)
	work_availability_changed.emit(settlement_id)


func _ensure_tool(actor: Node, tag: String, label: String) -> String:
	if tag.is_empty():
		_stow_weapon(actor)
		return ""
	var equipment = actor.get_equipment() if actor.has_method("get_equipment") else null
	if equipment != null:
		var equipped = equipment.get_equipped_item("weapon")
		if equipped != null and equipped.has_tool_tag(tag):
			return ""
	var entry = _find_tool_entry(actor, tag)
	if entry == null:
		return "Cannot %s: no %s" % [_verb_for_tag(tag), label]
	if not _equip_carried_tool(actor, equipment, entry):
		return "Cannot equip %s" % label
	return ""


func _equip_carried_tool(actor: Node, equipment, entry) -> bool:
	var profile_started := Time.get_ticks_usec()
	var inventory = _inventory(actor)
	if equipment == null or entry == null or inventory == null or not inventory.entries.has(entry) \
			or not equipment.has_method("can_equip_item_to_slot") \
			or not bool(equipment.call("can_equip_item_to_slot", entry.definition, "weapon")):
		return false
	var replaced = equipment.get_equipped_item("weapon")
	var replaced_stack_id := str(equipment.get_equipped_stack_id("weapon")) if equipment.has_method("get_equipped_stack_id") else ""
	if replaced != null and not _can_store_replaced_after_entry_removal(inventory, entry, replaced, replaced_stack_id):
		return false
	var incoming_snapshot := {
		"definition": entry.definition,
		"count": int(entry.count),
		"contained_item_counts": entry.contained_item_counts.duplicate(true),
		"metadata": entry.metadata.duplicate(true),
		"stack_id": str(entry.stack_id),
	}
	var replaced_snapshot := _stack_snapshot(replaced_stack_id)
	var preflight_usec := Time.get_ticks_usec() - profile_started
	if equipment.has_method("begin_equipment_update_batch"):
		equipment.begin_equipment_update_batch()
	var equip_started := Time.get_ticks_usec()
	equipment.equip_item_to_slot(entry.definition, "weapon", str(entry.stack_id))
	var equip_usec := Time.get_ticks_usec() - equip_started
	var remove_started := Time.get_ticks_usec()
	var equipped_success: bool = equipment.get_equipped_item("weapon") == entry.definition
	var removed_success: bool = equipped_success and inventory.remove_entry(entry)
	var remove_usec := Time.get_ticks_usec() - remove_started
	if not equipped_success or not removed_success:
		_restore_replaced_equipment(equipment, replaced, replaced_stack_id)
		_end_equipment_batch(equipment)
		return false
	if replaced != null and not inventory.add_entry_with_contents(
			replaced,
			int(replaced_snapshot.get("count", 1)),
			replaced_snapshot.get("contained_item_counts", {}),
			replaced_snapshot.get("metadata", {}),
			replaced_stack_id
	):
		_restore_replaced_equipment(equipment, replaced, replaced_stack_id)
		inventory.add_entry_with_contents(
			incoming_snapshot["definition"],
			int(incoming_snapshot["count"]),
			incoming_snapshot["contained_item_counts"],
			incoming_snapshot["metadata"],
			str(incoming_snapshot["stack_id"])
		)
		_end_equipment_batch(equipment)
		return false
	var end_batch_started := Time.get_ticks_usec()
	_end_equipment_batch(equipment)
	var end_batch_usec := Time.get_ticks_usec() - end_batch_started
	var restore_started := Time.get_ticks_usec()
	_restore_equipped_stack_contents(incoming_snapshot, "weapon")
	var restore_usec := Time.get_ticks_usec() - restore_started
	_last_tool_equip_timings = {
		"preflight_msec": float(preflight_usec) / 1000.0,
		"equip_msec": float(equip_usec) / 1000.0,
		"inventory_remove_msec": float(remove_usec) / 1000.0,
		"end_batch_msec": float(end_batch_usec) / 1000.0,
		"restore_stack_msec": float(restore_usec) / 1000.0,
		"total_msec": float(Time.get_ticks_usec() - profile_started) / 1000.0,
	}
	return true


func get_last_tool_equip_timings() -> Dictionary:
	return _last_tool_equip_timings.duplicate(true)


func _restore_equipped_stack_contents(snapshot: Dictionary, slot_name: String) -> void:
	if _gecs == null or not _gecs.has_method("upsert_item_stack_record"):
		return
	var stack_id := str(snapshot.get("stack_id", "")).strip_edges()
	var record := _stack_snapshot(stack_id)
	if record.is_empty():
		return
	record["count"] = int(snapshot.get("count", 1))
	record["contained_item_counts"] = (snapshot.get("contained_item_counts", {}) as Dictionary).duplicate(true)
	record["metadata"] = (snapshot.get("metadata", {}) as Dictionary).duplicate(true)
	record["container_id"] = ""
	record["location_kind"] = "equipment"
	record["placement_slot_id"] = slot_name
	_gecs.call("upsert_item_stack_record", record)


func _restore_replaced_equipment(equipment, replaced, replaced_stack_id: String) -> void:
	equipment.unequip_item_from_slot("weapon")
	if replaced != null:
		equipment.equip_item_to_slot(replaced, "weapon", replaced_stack_id)


func _end_equipment_batch(equipment) -> void:
	if equipment.has_method("end_equipment_update_batch"):
		equipment.end_equipment_update_batch()


func _can_store_replaced_after_entry_removal(inventory, incoming_entry, replaced, replaced_stack_id: String) -> bool:
	var snapshot := _stack_snapshot(replaced_stack_id)
	var replaced_count := int(snapshot.get("count", 1))
	var replaced_contents: Dictionary = snapshot.get("contained_item_counts", {})
	if inventory.use_weight:
		var incoming_weight: float = inventory.get_item_weight(incoming_entry.definition, int(incoming_entry.count), incoming_entry.contained_item_counts)
		var replaced_weight: float = inventory.get_item_weight(replaced, replaced_count, replaced_contents)
		if inventory.get_total_weight() - incoming_weight + replaced_weight > inventory.max_weight:
			return false
	for y in range(inventory.rows - replaced.grid_size.y + 1):
		for x in range(inventory.columns - replaced.grid_size.x + 1):
			if inventory.can_place_item(replaced, Vector2i(x, y), incoming_entry):
				return true
	return false


func _stack_snapshot(stack_id: String) -> Dictionary:
	if stack_id.is_empty() or _gecs == null or not _gecs.has_method("get_item_stack"):
		return {}
	return _gecs.call("get_item_stack", stack_id)


func _require_equipped_tool(actor: Node, tag: String, label: String) -> String:
	if tag.is_empty():
		return ""
	var equipment = actor.get_equipment() if actor != null and actor.has_method("get_equipment") else null
	var equipped = equipment.get_equipped_item("weapon") if equipment != null else null
	if equipped != null and equipped.has_method("has_tool_tag") and bool(equipped.call("has_tool_tag", tag)):
		return ""
	return "Equip a %s first" % label


func _stow_weapon(actor: Node) -> void:
	if actor == null or not actor.has_method("get_equipment"):
		return
	var equipment = actor.get_equipment()
	var inventory = _inventory(actor)
	if equipment == null or inventory == null or not equipment.has_method("unequip_item_from_slot"):
		return
	var equipped = equipment.get_equipped_item("weapon")
	if equipped == null:
		return
	var stack_id := str(equipment.get_equipped_stack_id("weapon")) if equipment.has_method("get_equipped_stack_id") else ""
	var snapshot := _stack_snapshot(stack_id)
	var count := int(snapshot.get("count", 1))
	var contents: Dictionary = snapshot.get("contained_item_counts", {})
	var metadata: Dictionary = snapshot.get("metadata", {})
	if not inventory.can_add_entry_with_contents(equipped, count, contents, metadata):
		return
	if equipment.has_method("begin_equipment_update_batch"):
		equipment.begin_equipment_update_batch()
	equipment.unequip_item_from_slot("weapon")
	if not inventory.add_entry_with_contents(equipped, count, contents, metadata, stack_id):
		equipment.equip_item_to_slot(equipped, "weapon", stack_id)
	_end_equipment_batch(equipment)


func _find_tool_entry(actor: Node, tag: String):
	var inventory = _inventory(actor)
	if inventory == null:
		return null
	for entry in inventory.entries:
		if entry != null and entry.definition != null and entry.definition.has_tool_tag(tag):
			return entry
	return null


func _find_inventory_entry_by_stack_id(inventory, stack_id: String, definition: ItemDefinition):
	if inventory == null:
		return null
	for entry in inventory.entries:
		if entry == null or entry.definition != definition:
			continue
		if stack_id.is_empty() or str(entry.stack_id) == stack_id:
			return entry
	return null


func _water_entry(actor: Node):
	return _find_tool_entry(actor, "tool.water_container")


func _container_capacity(actor: Node) -> float:
	var entry = _water_entry(actor)
	var definition = entry.definition if entry != null else _equipped_water_definition(actor)
	if definition == null:
		return 0.0
	return WATERING_CAN_CAPACITY if str(definition.item_id) == "tool.watering_can" else BUCKET_CAPACITY


func _container_water(actor: Node) -> float:
	var entry = _water_entry(actor)
	if entry != null:
		return float(entry.metadata.get(WATER_META, 0.0))
	var snapshot := _equipped_water_snapshot(actor)
	return float((snapshot.get("metadata", {}) as Dictionary).get(WATER_META, 0.0))


func _set_container_water(actor: Node, amount: float) -> void:
	var entry = _water_entry(actor)
	var inventory = _inventory(actor)
	var clamped := clampf(amount, 0.0, _container_capacity(actor))
	if entry != null and inventory != null:
		entry.metadata[WATER_META] = clamped
		inventory.changed.emit()
		return
	var snapshot := _equipped_water_snapshot(actor)
	if snapshot.is_empty() or _gecs == null or not _gecs.has_method("upsert_item_stack_record"):
		return
	var metadata: Dictionary = snapshot.get("metadata", {}).duplicate(true)
	metadata[WATER_META] = clamped
	snapshot["metadata"] = metadata
	_gecs.call("upsert_item_stack_record", snapshot)


func _equipped_water_definition(actor: Node):
	var equipment = actor.get_equipment() if actor != null and actor.has_method("get_equipment") else null
	var equipped = equipment.get_equipped_item("weapon") if equipment != null else null
	return equipped if equipped != null and equipped.has_tool_tag("tool.water_container") else null


func _equipped_water_snapshot(actor: Node) -> Dictionary:
	var equipment = actor.get_equipment() if actor != null and actor.has_method("get_equipment") else null
	if equipment == null or _equipped_water_definition(actor) == null or not equipment.has_method("get_equipped_stack_id"):
		return {}
	return _stack_snapshot(str(equipment.get_equipped_stack_id("weapon")))


func _nearest_water_source(position: Vector3):
	var best = null
	var best_distance := INF
	for source in get_tree().get_nodes_in_group("farm_water_source"):
		if source == null or source.available_water() <= 0.0:
			continue
		var distance: float = position.distance_squared_to(source.global_position)
		if distance < best_distance:
			best = source
			best_distance = distance
	return best


## Resolver for a plot whose crop policy is "auto": the crop whose seeds this
## field can actually reach the most of. Returning "" is a valid answer — the
## field then queues no planting work rather than asking for seed nobody has.
func resolve_auto_crop(state: Dictionary) -> String:
	if _farm == null:
		return ""
	var origin: Vector3 = state.get("origin", Vector3.ZERO)
	var owner_faction_id := str(state.get("owner_faction_id", ""))
	var settlement_id := str(state.get("settlement_id", ""))
	var best_crop_id := ""
	var best_count := 0
	for crop in _farm.call("get_crops"):
		if crop == null or crop.seed_item == null:
			continue
		var count := _reachable_seed_count(origin, crop.seed_item, owner_faction_id, settlement_id)
		# Ties break on the crop list's own order (sorted by display name), so
		# an auto field is deterministic rather than flickering between crops.
		if count > best_count:
			best_count = count
			best_crop_id = str(crop.crop_id)
	return best_crop_id


func _reachable_seed_count(position: Vector3, seed_item, owner_faction_id: String, settlement_id: String) -> int:
	# Crop policy belongs to durable world state, so it must continue resolving
	# when every physical container projection is outside LOD. The settlement
	# stock index is authoritative and O(1); live geometry remains relevant only
	# when a projected worker chooses the exact store it will walk to below.
	if _stock_controller != null and _stock_controller.has_method("get_settlement_stock_snapshot") and seed_item != null:
		var stock: Dictionary = _stock_controller.call("get_settlement_stock_snapshot", settlement_id)
		var item_id := str(seed_item.get("item_id")).strip_edges()
		if item_id.is_empty():
			item_id = str(seed_item.get("resource_path"))
		return int((stock.get("items", {}) as Dictionary).get(item_id, 0))
	var total := 0
	for container_value in _seed_container_candidates(settlement_id):
		var container := container_value as Node3D
		if container == null:
			continue
		var container_owner := str(container.call("get_owner_faction_name")) if container.has_method("get_owner_faction_name") else ""
		if not owner_faction_id.is_empty() and not container_owner.is_empty() and container_owner != owner_faction_id:
			continue
		var inventory = container.get("inventory")
		if inventory == null:
			continue
		if position.distance_squared_to(container.global_position) > AUTO_CROP_SEED_RADIUS * AUTO_CROP_SEED_RADIUS:
			continue
		for entry in inventory.entries:
			if entry != null and entry.definition == seed_item:
				total += int(entry.count)
	return total


func _nearest_seed_store(position: Vector3, seed_item, owner_faction_id: String, settlement_id: String, actor: Node = null) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for container_value in _seed_container_candidates(settlement_id):
		var container := container_value as Node3D
		if container == null:
			continue
		if actor != null and not _can_actor_access_store(actor, container, owner_faction_id):
			continue
		var container_owner := str(container.call("get_owner_faction_name")) if container.has_method("get_owner_faction_name") else ""
		if not owner_faction_id.is_empty() and not container_owner.is_empty() and container_owner != owner_faction_id:
			continue
		if container.get("inventory") == null or not _inventory_has(container.inventory, seed_item, 1):
			continue
		var distance := position.distance_squared_to(container.global_position)
		if distance < best_distance:
			best = container
			best_distance = distance
	return best


func _seed_container_candidates(settlement_id: String) -> Array[Node]:
	if settlement_id.is_empty():
		return []
	var stock_controller := BootstrapContext.service(InventoryStockController.SERVICE_ID)
	if stock_controller == null or not stock_controller.has_method("get_live_container_candidates"):
		return []
	var candidates: Array[Node] = []
	candidates.assign(stock_controller.call("get_live_container_candidates", settlement_id, PackedStringArray(["seeds"])))
	return candidates


func _nearest_tool_store(position: Vector3, tool_tag: String, owner_faction_id: String, settlement_id: String, actor: Node) -> Dictionary:
	if actor == null or tool_tag.is_empty() or settlement_id.is_empty():
		return {}
	var candidates := _tool_container_candidates(settlement_id)
	candidates.sort_custom(func(a: Node, b: Node) -> bool:
		return position.distance_squared_to((a as Node3D).global_position) < position.distance_squared_to((b as Node3D).global_position))
	for store in candidates:
		if not (store is Node3D) or not _can_actor_access_store(actor, store, owner_faction_id) \
				or not store.has_method("find_reservable_tool") or not store.has_method("reserve_item_for_actor"):
			continue
		var definition := store.call("find_reservable_tool", tool_tag, actor) as ItemDefinition
		if definition != null and bool(store.call("reserve_item_for_actor", definition, actor, 1)):
			return {"store": store, "definition": definition}
	return {}


func _tool_container_candidates(settlement_id: String) -> Array[Node]:
	if settlement_id.is_empty():
		return []
	var stock_controller := BootstrapContext.service(InventoryStockController.SERVICE_ID)
	if stock_controller == null or not stock_controller.has_method("get_live_container_candidates"):
		return []
	var candidates: Array[Node] = []
	candidates.assign(stock_controller.call("get_live_container_candidates", settlement_id, PackedStringArray(["tools"])))
	return candidates


func _actor_has_tool(actor: Node, tool_tag: String) -> bool:
	if actor == null or tool_tag.is_empty():
		return tool_tag.is_empty()
	var equipment = actor.get_equipment() if actor.has_method("get_equipment") else null
	var equipped = equipment.get_equipped_item("weapon") if equipment != null else null
	return (equipped != null and equipped.has_tool_tag(tool_tag)) or _find_tool_entry(actor, tool_tag) != null


func _is_town_worker(actor: Node, settlement_id: String) -> bool:
	if actor == null or settlement_id.is_empty():
		return false
	if actor.has_method("is_player_party_member") and bool(actor.call("is_player_party_member")):
		return false
	if str(actor.get_meta("settlement_id", "")) == settlement_id:
		return true
	return _has_property(actor, "settlement_id") and str(actor.get("settlement_id")) == settlement_id


func _expected_harvest_yield(actor: Node, work: Dictionary) -> int:
	var plot_id := str(work.get("plot_id", ""))
	var cell_key := str(work.get("cell_key", ""))
	var level := _farming_level(actor)
	if _farm != null and _farm.has_method("get_expected_harvest_yield"):
		var from_controller := int(_farm.call("get_expected_harvest_yield", plot_id, cell_key, level))
		if from_controller > 0:
			return from_controller
	var crop = _farm.get_crop(str(work.get("crop_id", ""))) if _farm != null and _farm.has_method("get_crop") else null
	if crop == null:
		return 0
	var base_yield := maxi(0, int(crop.get("base_yield")))
	var per_level := maxf(0.0, float(crop.get("yield_per_farming_level")))
	return maxi(1, int(round(float(base_yield) * (1.0 + maxf(0.0, level) * per_level)))) if base_yield > 0 else 0


func _can_actor_access_store(actor: Node, store: Node, required_faction_id := "") -> bool:
	if actor == null or store == null or not is_instance_valid(store):
		return false
	if store.has_method("can_actor_access"):
		return bool(store.call("can_actor_access", actor))
	if _has_property(store, "is_locked") and bool(store.get("is_locked")):
		return false
	var actor_faction := str(actor.get("faction_name")) if _has_property(actor, "faction_name") else ""
	if actor_faction.is_empty() and _has_property(actor, "faction_id"):
		actor_faction = str(actor.get("faction_id"))
	if not required_faction_id.is_empty() and actor_faction != required_faction_id:
		return false
	var store_owner := str(store.call("get_owner_faction_name")) if store.has_method("get_owner_faction_name") else ""
	return store_owner.is_empty() or actor_faction == store_owner


func _has_property(value: Object, property_name: String) -> bool:
	if value == null:
		return false
	for property in value.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _reset_travel_state(assignment: Dictionary, actor: Node3D) -> void:
	assignment["traveling"] = true
	assignment["travel_check_accumulated"] = 0.0
	assignment["last_travel_check_time"] = _process_sim_time
	assignment["travel_seconds"] = 0.0
	assignment["stalled_seconds"] = 0.0
	assignment["last_actor_position"] = actor.global_position


func _mark_temporarily_unreachable(assignment: Dictionary) -> void:
	var plot_id := str(assignment.get("plot_id", ""))
	var cell_key := str(assignment.get("cell_key", ""))
	if plot_id.is_empty() or cell_key.is_empty():
		return
	_unreachable_until_msec["%s|%s" % [plot_id, cell_key]] = Time.get_ticks_msec() + UNREACHABLE_RETRY_MSEC


func _append_unreachable_cells(plot_id: String, exclusions: Array[String]) -> void:
	var now := Time.get_ticks_msec()
	for cooldown_key_value in _unreachable_until_msec.keys().duplicate():
		var cooldown_key := str(cooldown_key_value)
		if int(_unreachable_until_msec[cooldown_key_value]) <= now:
			_unreachable_until_msec.erase(cooldown_key_value)
			continue
		var prefix := "%s|" % plot_id
		if cooldown_key.begins_with(prefix):
			exclusions.append(cooldown_key.trim_prefix(prefix))


func _on_world_reindexed() -> void:
	_cancel_all_assignments()
	_unreachable_until_msec.clear()
	_offer_cache_dirty = true


func _cancel_claimed_cell(plot_id: String, cell_key: String) -> void:
	for actor_key_value in _assignments.keys().duplicate():
		var assignment: Dictionary = _assignments.get(actor_key_value, {})
		if str(assignment.get("plot_id", "")) == plot_id and str(assignment.get("cell_key", "")) == cell_key:
			_cancel(int(actor_key_value))


func _cancel_all_assignments() -> void:
	for actor_key_value in _assignments.keys():
		_cancel(int(actor_key_value))


func _inventory(actor: Node):
	if actor == null:
		return null
	var value = actor.call("get_inventory") if actor.has_method("get_inventory") else actor.get("inventory")
	if value != null and value.has_method("get_inventory_for_display"):
		var carried = value.get("inventory")
		if carried == null and value.has_method("initialize_from_actor"):
			value.call("initialize_from_actor")
			carried = value.get("inventory")
		return carried
	return value


func _has_item(actor: Node, definition, amount: int) -> bool:
	var inventory = _inventory(actor)
	return _inventory_has(inventory, definition, amount)


func _inventory_has(inventory, definition, amount: int) -> bool:
	if inventory == null or definition == null:
		return false
	var count := 0
	for entry in inventory.entries:
		if entry != null and entry.definition == definition:
			count += int(entry.count)
	return count >= amount


func _consume_item(actor: Node, definition, amount: int) -> bool:
	var inventory = _inventory(actor)
	return inventory != null and inventory.remove_item_count(definition, amount)


func _move_actor(actor: Node, target: Vector3, issued_by_player := false) -> void:
	if actor.has_method("set_move_target"):
		actor.set_move_target(target, issued_by_player)


func _stop_actor_movement(actor: Node) -> void:
	if actor != null and actor.has_method("stop_movement"):
		actor.call("stop_movement")
	elif actor is CharacterBody3D:
		(actor as CharacterBody3D).velocity = Vector3.ZERO


func _has_move_target(actor: Node) -> bool:
	return actor.has_method("has_move_target") and actor.has_move_target()


func _has_conflicting_player_order(actor: Node, expected: Vector3) -> bool:
	if not _has_move_target(actor) or not actor.has_method("get_move_target"):
		return false
	return actor.get_move_target().distance_to(expected) > 0.35


func _cancel(actor_key: int) -> void:
	var assignment: Dictionary = _assignments.get(actor_key, {})
	var settlement_id := str(assignment.get("settlement_id", ""))
	_release_assignment_tool_reservation(actor_key, assignment)
	var actor := _live_node(assignment.get("actor"))
	if actor != null and not bool(assignment.get("automatic", false)):
		_cancel_command_target({
			"plot_id": assignment.get("plot_id", ""),
			"cell_key": assignment.get("cell_key", ""),
			"request_revision": assignment.get("request_revision", -1),
		}, actor)
		_cancel_command_targets(assignment.get("command_targets", []), actor)
	_mark_settlement_work_active(actor, false)
	_set_farming_visual(actor, false, "", Vector3.ZERO, 0.0)
	_assignments.erase(actor_key)
	_refresh_process_state()
	if not settlement_id.is_empty():
		work_offers_changed.emit(settlement_id)


func _release_assignment_tool_reservation(actor_key: int, assignment: Dictionary) -> void:
	if str(assignment.get("stage", "")) != "fetch_tool":
		return
	var store := _live_node(assignment.get("tool_store"))
	if store != null and is_instance_valid(store) and store.has_method("release_item_reservation"):
		store.call("release_item_reservation", actor_key)


static func _live_node(value: Variant) -> Node:
	if value == null or not is_instance_valid(value):
		return null
	return value as Node


static func _live_node_3d(value: Variant) -> Node3D:
	var node := _live_node(value)
	return node as Node3D if node is Node3D else null


func _actor_work_id(actor: Node) -> String:
	if actor == null:
		return ""
	for property in actor.get_property_list():
		if str(property.get("name", "")) == "stable_id":
			var stable_id := str(actor.get("stable_id"))
			if not stable_id.is_empty():
				return stable_id
	var metadata_id := str(actor.get_meta("stable_id", ""))
	return metadata_id if not metadata_id.is_empty() else "instance:%d" % actor.get_instance_id()


func _mark_settlement_work_active(actor: Node, active: bool) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	if active:
		actor.set_meta(ACTIVE_SETTLEMENT_WORK_META, get_instance_id())
	elif int(actor.get_meta(ACTIVE_SETTLEMENT_WORK_META, 0)) == get_instance_id():
		actor.remove_meta(ACTIVE_SETTLEMENT_WORK_META)


func _refresh_process_state() -> void:
	set_process(not _assignments.is_empty())


func _set_farming_visual(actor: Node, active: bool, action: String, target: Vector3, progress: float) -> void:
	if actor != null and actor.has_method("set_farming_work_visual"):
		actor.set_farming_work_visual(active, action, target, progress)


func _farming_level(actor: Node) -> float:
	return float(actor.get_skill_level("labor.farming")) if actor.has_method("get_skill_level") else 0.0


func _speak(_actor: Node, _message: String) -> void:
	# Farming feedback remains physical and UI-driven; world warning/status text
	# is deliberately suppressed.
	pass


func _item_name(item, fallback: String) -> String:
	return str(item.display_name) if item != null else fallback


func _verb_for_tag(tag: String) -> String:
	if tag == "tool.hoe": return "till"
	if tag == "tool.water_container": return "water"
	if tag == "tool.scythe": return "harvest"
	return "work"
