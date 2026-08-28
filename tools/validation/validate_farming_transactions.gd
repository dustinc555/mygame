extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_farming_transactions.gd

const WORK_BRIDGE = preload("res://features/farming/bridge/farm_work_bridge.gd")
const INVENTORY = preload("res://features/inventory/sim/inventory_data.gd")
const TOMATO = preload("res://features/inventory/resources/items/tomato.tres")
const TOMATO_SEEDS = preload("res://features/inventory/resources/items/tomato_seeds.tres")
const TOMATO_CROP = preload("res://features/farming/resources/crops/tomato.tres")

class FakeFarm:
	extends Node
	var action := "till"
	var progress := 0.0
	var required := 1.0
	var invalid_apply := false
	var apply_calls := 0
	var reset_count := 0
	var allow_commands := true
	var cancel_calls := 0
	func get_plot(_plot_id: String) -> Dictionary:
		return {"plot_id": "farm:test", "owner_faction_id": "Player", "settlement_id": "settlement:test", "cells": {"0:0": {"requested_operation": action}}}
	func get_plots() -> Dictionary:
		return {"farm:test": get_plot("farm:test")}
	func get_next_work(_plot_id: String, excluded := PackedStringArray()) -> Dictionary:
		if excluded.has("0:0"):
			return {}
		return {
			"plot_id": "farm:test", "cell_key": "0:0", "action": action,
			"world_position": Vector3.ZERO, "crop_id": "tomato",
			"required_tool_tag": "", "required_tool_label": "",
			"required_seconds": required, "progress_seconds": progress,
			"seed_item": TOMATO_SEEDS, "produce_item": TOMATO,
		}
	func get_cell_work(plot_id: String, cell_key: String) -> Dictionary:
		return get_next_work(plot_id) if cell_key == "0:0" else {}
	func apply_work(_plot_id: String, _cell_key: String, requested_action: String, seconds: float, _level := 0.0, _expected_request_revision := -1) -> Dictionary:
		apply_calls += 1
		if invalid_apply:
			return {}
		progress = minf(required, progress + maxf(0.0, seconds))
		var completed := progress >= required
		if completed and requested_action == "harvest":
			reset_count += 1
		return {
			"completed": completed, "required_seconds": required, "progress_seconds": progress,
			"produce_item": TOMATO, "yield": 4,
		}
	func get_crop(_crop_id: String):
		return TOMATO_CROP
	func can_actor_command_plot(_actor: Node, _plot_id: String) -> bool:
		return allow_commands
	func cancel_cell_operation(_plot_id: String, _cell_key: String, _revision: int, _actor_id: String) -> Dictionary:
		cancel_calls += 1
		return {}

class FakeActor:
	extends Node3D
	var faction_name := "Player"
	var player_party_member := true
	var life_state := 0
	var carried = null
	var move_target := Vector3.ZERO
	var moving := false
	var active_player_order := false
	var last_move_issued_by_player := false
	func get_inventory():
		return carried
	func has_move_target() -> bool:
		return moving
	func get_move_target() -> Vector3:
		return move_target
	func set_move_target(target: Vector3, issued := false) -> void:
		move_target = target
		moving = true
		last_move_issued_by_player = issued
		active_player_order = issued
	func is_player_party_member() -> bool:
		return player_party_member
	func has_active_player_order() -> bool:
		return active_player_order
	func get_active_job_provider():
		return null
	func get_skill_level(_skill: String) -> float:
		return 0.0

class LimitedInventory:
	extends RefCounted
	var entries := []
	var add_attempts: Array[int] = []
	func can_add_item_count(_definition, amount: int) -> bool:
		return amount <= 1
	func add_item_count(_definition, amount: int) -> bool:
		add_attempts.append(amount)
		return can_add_item_count(_definition, amount)
	func remove_item_count(_definition, _amount: int) -> bool:
		return false

class FakeStore:
	extends Node3D
	var container_kind := "farm_seed"
	var is_locked := true
	var inventory = null
	var owner_faction_name := "Player"
	var released_reservations := 0
	func get_owner_faction_name() -> String:
		return owner_faction_name
	func release_item_reservation(_actor_key: int) -> void:
		released_reservations += 1

class FakeProcessor:
	extends Node3D
	var is_locked := true
	var processing_seconds := 1.0
	var owner_faction_name := "Player"
	func can_process_crop(_crop_id: String) -> bool:
		return true
	func get_owner_faction_name() -> String:
		return owner_faction_name
	func get_interaction_position(_actor: Node) -> Vector3:
		return global_position

var failures: Array[String] = []
var last_delta_upserts: Array = []


func _on_work_offer_delta(_settlement_id: String, _removed: PackedStringArray, upserted: Array) -> void:
	last_delta_upserts = upserted.duplicate(true)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var bridge = WORK_BRIDGE.new()
	var farm := FakeFarm.new()
	root.add_child(farm)
	root.add_child(bridge)
	bridge.work_offer_delta.connect(_on_work_offer_delta)
	bridge._farm = farm
	var actor := FakeActor.new()
	actor.carried = INVENTORY.new(2, 1, 0.0, false)
	actor.carried.add_item_count(TOMATO_SEEDS, 1)
	root.add_child(actor)

	bridge._assignments[actor.get_instance_id()] = _assignment(actor, "plant")
	bridge._process_assignment(actor.get_instance_id(), 0.5)
	_expect(actor.carried.count_item(TOMATO_SEEDS) == 1, "plant interruption does not consume a seed before completion")
	bridge._cancel(actor.get_instance_id())
	bridge._assignments[actor.get_instance_id()] = _assignment(actor, "plant")
	bridge._assignments[actor.get_instance_id()]["progress_seconds"] = farm.progress
	bridge._process_assignment(actor.get_instance_id(), 0.6)
	_expect(actor.carried.count_item(TOMATO_SEEDS) == 0, "resumed planting consumes exactly one seed at completion")

	farm.progress = 0.0
	farm.apply_calls = 0
	bridge._assignments[actor.get_instance_id()] = _assignment(actor, "till")
	bridge._process_assignment(actor.get_instance_id(), 0.01)
	_expect(farm.apply_calls == 0, "work persistence is rate-limited instead of running every frame")
	bridge._cancel(actor.get_instance_id())

	bridge._assignments[actor.get_instance_id()] = _assignment(actor, "water")
	var automatic_busy_result := bridge.assign_cell("farm:test", "0:0", [actor], true)
	_expect(automatic_busy_result == "Selected worker is already busy" and str((bridge._assignments[actor.get_instance_id()] as Dictionary).get("action", "")) == "water", "automatic dispatch never interrupts active work")
	var manual_override_result := bridge.assign_cell("farm:test", "0:0", [actor])
	_expect(manual_override_result == "1 worker assigned" and str((bridge._assignments[actor.get_instance_id()] as Dictionary).get("action", "")) == "till", "manual cell order interrupts the selected actor's automatic farm work")
	_expect(actor.last_move_issued_by_player, "manual cell work is issued as a player order")
	_expect(bridge.cancel_work_for_actor(actor) and not bridge._assignments.has(actor.get_instance_id()), "a later manual context order cancels manually initiated farm work")
	bridge._assignments[actor.get_instance_id()] = _assignment(actor, "till")
	farm.allow_commands = false
	var cancel_calls_before_unauthorized := farm.cancel_calls
	var unauthorized_sequence_result := bridge.assign_cell_sequence([{
		"plot_id": "farm:test", "cell_key": "0:0", "request_revision": -1,
	}], actor, true)
	_expect(unauthorized_sequence_result.begins_with("Cannot work") and bridge._assignments.has(actor.get_instance_id()) and farm.cancel_calls == cancel_calls_before_unauthorized, "unauthorized field sequences cannot replace work or cancel durable requests")
	farm.allow_commands = true
	bridge._cancel(actor.get_instance_id())
	actor.active_player_order = false
	var automatic_assignment_result := bridge.assign_cell("farm:test", "0:0", [actor], true)
	_expect(automatic_assignment_result == "1 worker assigned" and not actor.last_move_issued_by_player, "Jobs work is issued as ambient automatic movement")
	bridge._cancel(actor.get_instance_id())
	var interrupted_auto_assignment := _assignment(actor, "till")
	interrupted_auto_assignment["automatic"] = true
	bridge._assignments[actor.get_instance_id()] = interrupted_auto_assignment
	actor.active_player_order = true
	bridge._process_assignment(actor.get_instance_id(), 0.01)
	_expect(not bridge._assignments.has(actor.get_instance_id()), "any later manual player order immediately cancels active farm work")
	actor.active_player_order = false

	farm.invalid_apply = true
	farm.action = "plant"
	farm.progress = 0.0
	actor.carried.add_item_count(TOMATO_SEEDS, 1)
	var seeds_before_stale_apply: int = actor.carried.count_item(TOMATO_SEEDS)
	var stale_plant_assignment := _assignment(actor, "plant")
	stale_plant_assignment["request_revision"] = 1
	bridge._assignments[actor.get_instance_id()] = stale_plant_assignment
	bridge._process_assignment(actor.get_instance_id(), 1.1)
	_expect(not bridge._assignments.has(actor.get_instance_id()), "stale request revision cancels the live planting assignment")
	_expect(actor.carried.count_item(TOMATO_SEEDS) == seeds_before_stale_apply, "stale Plant apply rolls its consumed seed back")
	farm.action = "till"
	farm.invalid_apply = false

	var stranded := FakeActor.new()
	stranded.carried = INVENTORY.new()
	root.add_child(stranded)
	stranded.global_position = Vector3(50.0, 0.0, 0.0)
	var stranded_assignment := _assignment(stranded, "till")
	stranded_assignment["expected_target"] = Vector3.ZERO
	var reservation_store := FakeStore.new()
	root.add_child(reservation_store)
	stranded_assignment["stage"] = "fetch_tool"
	stranded_assignment["tool_store"] = reservation_store
	bridge._assignments[stranded.get_instance_id()] = stranded_assignment
	for _step in 400:
		bridge._process_assignment(stranded.get_instance_id(), 0.1)
		if not bridge._assignments.has(stranded.get_instance_id()):
			break
	_expect(not bridge._assignments.has(stranded.get_instance_id()), "unreachable cell assignment times out and releases its worker")
	_expect(reservation_store.released_reservations == 1, "timed-out tool travel releases its exact reservation instead of leaking it")
	bridge._unreachable_until_msec.clear()

	farm.action = "harvest"
	farm.progress = 0.0
	farm.reset_count = 0
	var limited_actor := FakeActor.new()
	limited_actor.carried = LimitedInventory.new()
	root.add_child(limited_actor)
	var harvest_message := bridge._assign_cell_to_actor(limited_actor, "farm:test", "0:0")
	_expect(harvest_message == "Cannot harvest: no inventory space", "harvest reserves capacity for the full yield")
	_expect(farm.reset_count == 0, "failed harvest capacity leaves the ripe cell intact")

	var store := FakeStore.new()
	store.inventory = INVENTORY.new()
	store.inventory.add_item_count(TOMATO_SEEDS, 2)
	store.add_to_group("world_container")
	root.add_child(store)
	bridge._borrowed_tools[actor.get_instance_id()] = {
		"actor_ref": weakref(actor), "store_ref": weakref(store),
		"settlement_id": "settlement:test", "owner_faction_id": "Player",
	}
	var completed_assignment := _assignment(actor, "till")
	completed_assignment["automatic"] = true
	bridge._assignments[actor.get_instance_id()] = completed_assignment
	last_delta_upserts.clear()
	bridge._finish_and_continue(actor.get_instance_id())
	_expect(last_delta_upserts.size() == 1 and str(last_delta_upserts[0].get("action", "")) == "return_borrowed_tool", "finishing a borrowed-tool batch publishes its return offer without a full provider rescan")
	bridge._borrowed_tools.erase(actor.get_instance_id())
	var nearest_store = _nearest_seed_store(bridge, actor)
	_expect(nearest_store == null, "locked seed stores are never auto-accessed")
	var processor := FakeProcessor.new()
	root.add_child(processor)
	_expect(bridge.assign_seed_processing(processor, "tomato", [actor]).begins_with("Cannot"), "locked processors reject worker assignments")

	_expect(not bridge.has_method("_assign_continuous_workers"), "farming has no field-owned continuous worker recruiter")
	_expect(not bridge.has_method("_can_auto_assign"), "farming cannot enlist unselected party members")
	_expect(bridge.has_method("get_available_work_offers"), "farming exposes work to the shared settlement scheduler")
	if bridge.has_method("get_available_work_offers"):
		bridge._assignments[actor.get_instance_id()] = _assignment(actor, farm.action)
		_expect((bridge.call("get_available_work_offers", "settlement:test") as Array).is_empty(), "claimed cells are not advertised to other Jobs workers")
		bridge._cancel(actor.get_instance_id())
		var offers: Array = bridge.call("get_available_work_offers", "settlement:test")
		_expect(offers.size() == 1, "requested cell work produces one cell-level work offer")
		if offers.size() == 1:
			_expect(str(offers[0].get("category", "")) == "farm", "cell work uses the shared Farm category")
			_expect(str(offers[0].get("plot_id", "")) == "farm:test", "field work offer identifies its plot")
			_expect(str(offers[0].get("cell_key", "")) == "0:0", "field work offer identifies its exact cell")

	var exchange_inventory = INVENTORY.new(1, 1, 0.0, false)
	exchange_inventory.add_item_count(TOMATO, 1)
	var exchanged := bool(exchange_inventory.call("exchange_item_counts", TOMATO, 1, TOMATO_SEEDS, 4)) if exchange_inventory.has_method("exchange_item_counts") else false
	_expect(exchanged and exchange_inventory.count_item(TOMATO) == 0 and exchange_inventory.count_item(TOMATO_SEEDS) == 4, "seed processing atomically exchanges produce even when removal frees the only slot")
	var source_inventory = INVENTORY.new(1, 1, 0.0, false)
	var target_inventory = INVENTORY.new(1, 1, 0.0, false)
	source_inventory.add_item_count(TOMATO_SEEDS, 1)
	var transferred := bool(source_inventory.call("transfer_item_count_to", TOMATO_SEEDS, 1, target_inventory)) if source_inventory.has_method("transfer_item_count_to") else false
	_expect(transferred and source_inventory.count_item(TOMATO_SEEDS) == 0 and target_inventory.count_item(TOMATO_SEEDS) == 1, "seed fetch transfers between inventories atomically")

	var lod_actor := FakeActor.new()
	root.add_child(lod_actor)
	var lod_actor_key := lod_actor.get_instance_id()
	var lod_assignment := _assignment(lod_actor, "till")
	lod_assignment["automatic"] = true
	lod_assignment["traveling"] = true
	bridge._assignments[lod_actor_key] = lod_assignment
	lod_actor.free()
	bridge._process(0.1)
	_expect(not bridge._assignments.has(lod_actor_key), "LOD-unloaded workers cancel volatile farm assignments without casting freed projections")

	actor.free()
	stranded.free()
	reservation_store.free()
	limited_actor.free()
	store.free()
	processor.free()
	bridge.free()
	farm.free()
	_finish()


func _nearest_seed_store(bridge: Node, actor: Node3D):
	for method in bridge.get_method_list():
		if str(method.get("name", "")) != "_nearest_seed_store":
			continue
		var arguments: Array = method.get("args", [])
		if arguments.size() >= 5:
			return bridge.call("_nearest_seed_store", Vector3.ZERO, TOMATO_SEEDS, "Player", "settlement:test", actor)
		return bridge.call("_nearest_seed_store", Vector3.ZERO, TOMATO_SEEDS, "Player")
	return null


func _assignment(actor: Node3D, action: String) -> Dictionary:
	return {
		"actor": actor, "plot_id": "farm:test", "cell_key": "0:0", "action": action,
		"world_position": Vector3.ZERO, "expected_target": Vector3.ZERO, "stage": "work",
		"required_seconds": 1.0, "progress_seconds": 0.0, "pending_work_seconds": 0.0,
		"seed_item": TOMATO_SEEDS, "produce_item": TOMATO, "crop_id": "tomato",
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FARMING_TRANSACTIONS_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FARMING_TRANSACTIONS_FAILED count=%d" % failures.size())
	quit(1)