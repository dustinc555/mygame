extends SceneTree
## Regression-first hot-path contract for Jobs and farming offer dispatch.

const JOB_SYSTEM := preload("res://features/settlements/sim/job_system_controller.gd")
const FARM_WORK := preload("res://features/farming/bridge/farm_work_bridge.gd")
const FARM_CONTROLLER := preload("res://features/farming/sim/farm_controller.gd")
const TOMATO_CROP := preload("res://features/farming/resources/crops/tomato.tres")
const INVENTORY := preload("res://features/inventory/sim/inventory_data.gd")
const TOMATO := preload("res://features/inventory/resources/items/tomato.tres")
const TOMATO_SEEDS := preload("res://features/inventory/resources/items/tomato_seeds.tres")

class FakeGecs:
	extends Node
	signal world_reindexed
	var job_state: Dictionary = {}
	func get_job_system_state() -> Dictionary: return job_state
	func upsert_job_system_state(state: Dictionary) -> Dictionary:
		job_state = state
		return state
	func get_actor_job_contracts(_actor) -> Array: return []
	func get_settlement_states() -> Dictionary: return {}
	func expire_missed_job_contracts(_sim_time: float) -> int: return 0

class FakeFarm:
	extends Node
	signal plot_changed(plot_id: String, state: Dictionary)
	signal plot_removed(plot_id: String)
	var offer_snapshot_calls := 0
	var legacy_plot_calls := 0
	var plot_id := "farm:test"
	var include_first_offer := true
	var include_second_offer := false
	func get_available_work_records(_settlement_id := "") -> Array:
		offer_snapshot_calls += 1
		var records := []
		if include_first_offer:
			records.append(_work("0:0"))
		if include_second_offer:
			records.append(_work("1:0"))
		return records
	func get_plots() -> Dictionary:
		legacy_plot_calls += 1
		return {plot_id: {"plot_id": plot_id, "settlement_id": "", "owner_faction_id": "Player", "cells": {"0:0": {}, "1:0": {}}}}
	func is_active_field(_state) -> bool: return true
	func get_cell_work(_plot_id: String, cell_key: String) -> Dictionary:
		if cell_key == "1:0" and not include_second_offer:
			return {}
		return _work(cell_key)
	func _work(cell_key: String) -> Dictionary:
		return {
			"plot_id": plot_id,
			"cell_key": cell_key,
			"action": "till",
			"world_position": Vector3(float(cell_key.get_slice(":", 0)), 0.0, 0.0),
			"allowed_actor_ids": PackedStringArray(),
			"request_revision": 1,
		}

class FakeActor:
	extends Node3D
	var stable_id := ""
	var faction_name := "Player"
	var life_state := 0
	var active_provider: Node
	var inventory = null
	var player_party_member := true
	var active_player_order := false
	func is_player_party_member() -> bool: return player_party_member
	func has_active_player_order() -> bool: return active_player_order
	func get_active_job_provider(): return active_provider
	func get_inventory(): return inventory
	func get_skill_level(_skill_id: String) -> float: return 0.0

class SingleOfferProvider:
	extends Node3D
	var accept_count := 0
	var offer_count := 1
	var category := "crafting"
	var entry_id := "category:crafting"
	var display_name := "Crafting"
	var category_query_count := 0
	var offer_query_count := 0
	var active_actor_ids: Dictionary = {}
	var accepted_actor_ids := PackedStringArray()
	func get_available_work_offers(_settlement_id := "") -> Array:
		offer_query_count += 1
		var offers := []
		for index in offer_count:
			offers.append({
				"offer_id": "single:offer:%d" % index,
				"category": category,
				"job_entry_id": entry_id,
				"owner_faction_id": "Player",
				"world_position": Vector3(float(index), 0.0, 0.0),
				"provider": self,
			})
		return offers
	func get_job_category_specs(_settlement_id := "") -> Array:
		category_query_count += 1
		return [{"entry_id": entry_id, "category": category, "display_name": display_name}]
	func can_actor_accept_work_offer(_offer: Dictionary, _actor: Node) -> bool: return true
	func accept_work_offer(_offer: Dictionary, actor: Node) -> Dictionary:
		accept_count += 1
		active_actor_ids[actor.get_instance_id()] = true
		accepted_actor_ids.append(str(actor.get("stable_id")))
		return {"accepted": true}
	func has_active_work_for_actor(actor: Node) -> bool:
		return active_actor_ids.has(actor.get_instance_id())

class FakeIndexedFarmGecs:
	extends Node
	var indexed_cell_reads := 0
	var indexed_header_reads := 0
	var legacy_all_plot_reads := 0
	func get_farm_plot_cell_record(_plot_id: String, cell_key: String) -> Dictionary:
		indexed_cell_reads += 1
		return {
			"plot_id": "farm:indexed",
			"owner_faction_id": "Player",
			"settlement_id": "indexed",
			"crop_policy_id": "tomato",
			"field_deleted": false,
			"cell_key": cell_key,
			"cell": {
				"state": "untilled",
				"requested_operation": "till",
				"requested_crop_id": "",
				"requested_actor_ids": PackedStringArray(),
				"request_revision": 1,
				"world_position": Vector3.ZERO,
			},
		}
	func get_farm_plot_header_state(_plot_id: String) -> Dictionary:
		indexed_header_reads += 1
		return {
			"plot_id": "farm:indexed",
			"owner_faction_id": "Player",
			"settlement_id": "indexed",
			"field_deleted": false,
		}
	func get_farm_plot_states() -> Dictionary:
		legacy_all_plot_reads += 1
		return {"farm:indexed": {
			"plot_id": "farm:indexed",
			"owner_faction_id": "Player",
			"settlement_id": "indexed",
			"crop_policy_id": "tomato",
			"field_deleted": false,
			"cells": {"0:0": {
				"state": "untilled",
				"requested_operation": "till",
				"request_revision": 1,
				"world_position": Vector3.ZERO,
			}},
		}}

class FakePopulation:
	extends Node
	var actors_by_id: Dictionary = {}
	func get_live_actor(actor_id: String):
		return actors_by_id.get(actor_id)

class FakeTravelActor:
	extends Node3D
	var active_player_order := false
	var move_target := Vector3.ZERO
	var moving := true
	var farming_visual_calls := 0
	func has_active_player_order() -> bool: return active_player_order
	func has_move_target() -> bool: return moving
	func get_move_target() -> Vector3: return move_target
	func set_move_target(target: Vector3, _issued_by_player := false) -> void:
		move_target = target
		moving = true
	func stop_movement() -> void:
		moving = false
	func set_farming_work_visual(_active: bool, _action: String, _target: Vector3, _progress: float) -> void:
		farming_visual_calls += 1

class FakeBatchWorkFarm:
	extends Node
	var apply_calls := 0
	var batch_calls := 0
	func apply_work(_plot_id: String, _cell_key: String, _action: String, seconds: float, _level := 0.0, _revision := -1) -> Dictionary:
		apply_calls += 1
		return {"completed": false, "required_seconds": 4.0, "progress_seconds": seconds}
	func apply_work_batch(requests: Array) -> Array:
		batch_calls += 1
		var results := []
		for request_value in requests:
			var request: Dictionary = request_value
			results.append({
				"completed": false,
				"required_seconds": 4.0,
				"progress_seconds": float(request.get("seconds", 0.0)),
			})
		return results

class FakePartialBatchFarm:
	extends Node
	var batch_calls := 0
	func apply_work_batch(requests: Array) -> Array:
		batch_calls += 1
		var results := []
		for request_value in requests:
			var request: Dictionary = request_value
			if str(request.get("cell_key", "")).begins_with("ok"):
				results.append({"completed": true, "required_seconds": 1.0, "progress_seconds": 1.0})
			else:
				results.append({})
		return results
	func get_expected_harvest_yield(_plot_id: String, _cell_key: String, _level := 0.0) -> int:
		return 4

class FakeBatchFarmGecs:
	extends Node
	var state: Dictionary = {}
	var upsert_count := 0
	func get_farm_plot_state(plot_id: String) -> Dictionary:
		return state.duplicate(true) if str(state.get("plot_id", "")) == plot_id else {}
	func get_farm_plot_states() -> Dictionary:
		var plot_id := str(state.get("plot_id", ""))
		return {plot_id: state.duplicate(true)} if not plot_id.is_empty() else {}
	func upsert_farm_plot_state(next_state: Dictionary) -> Dictionary:
		upsert_count += 1
		state = next_state.duplicate(true)
		return state.duplicate(true)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_farm_offer_cache_and_invalidation()
	_test_indexed_farm_cell_reads()
	_test_real_farm_batch_atomicity()
	_test_batched_bridge_commits()
	_test_batched_inventory_success_and_rollback()
	_test_cached_jobs_enabled_read_and_single_claim()
	_test_dynamic_provider_category_after_policy_cache()
	_test_jobs_policy_hydration()
	_test_production_dispatch_spreads_actor_work()
	_test_mixed_party_assignment_fairness()
	_test_busy_actor_skips_offer_collection()
	_test_travel_checks_are_staggered()
	_test_process_gate_keeps_immediate_arrival()
	_test_travel_elapsed_is_per_assignment()
	_test_displaced_worker_starts_fresh_travel_leg()
	_test_process_gate_preempts_player_order_immediately()
	_finish()


func _test_farm_offer_cache_and_invalidation() -> void:
	var holder := Node.new()
	root.add_child(holder)
	var context := BootstrapContext.new(holder)
	var gecs := FakeGecs.new()
	var farm := FakeFarm.new()
	var bridge := FARM_WORK.new()
	holder.add_child(gecs)
	holder.add_child(farm)
	holder.add_child(bridge)
	context.register(&"gecs_world", gecs)
	context.register(&"farming", farm)
	bridge.initialize(context)
	var first: Array = bridge.get_available_work_offers()
	var second: Array = bridge.get_available_work_offers()
	_expect(first.size() == 1 and second.size() == 1, "cached farm offers remain complete")
	_expect(farm.offer_snapshot_calls == 1, "unchanged farm offers build from one source snapshot")
	_expect(farm.legacy_plot_calls == 0, "farm offer cache does not use per-cell legacy plot reads")
	farm.include_second_offer = true
	farm.plot_changed.emit("farm:test", {})
	var changed: Array = bridge.get_available_work_offers()
	_expect(changed.size() == 2, "plot mutation invalidates and refreshes farm offers")
	_expect(farm.offer_snapshot_calls == 2, "one plot mutation causes one lazy offer refresh")
	farm.include_first_offer = false
	farm.include_second_offer = false
	farm.plot_removed.emit("farm:test")
	_expect(bridge.get_available_work_offers().is_empty(), "removed plots cannot leave stale cached offers")
	farm.plot_id = "farm:replacement"
	farm.include_first_offer = true
	gecs.world_reindexed.emit()
	var replacement: Array = bridge.get_available_work_offers()
	_expect(replacement.size() == 1 and str(replacement[0].get("plot_id", "")) == "farm:replacement", "world reindex replaces old cached offers from authoritative state")
	_expect(farm.offer_snapshot_calls == 4, "remove and reindex each cause one lazy cache refresh")
	bridge.teardown()
	root.remove_child(holder)
	holder.free()


func _test_indexed_farm_cell_reads() -> void:
	var farm := FARM_CONTROLLER.new()
	var gecs := FakeIndexedFarmGecs.new()
	farm._gecs = gecs
	farm._crops["tomato"] = TOMATO_CROP
	var actor := FakeActor.new()
	actor.faction_name = "Player"
	var work := farm.get_cell_work("farm:indexed", "0:0")
	_expect(not work.is_empty() and str(work.get("action", "")) == "till", "indexed farm cell read preserves work semantics")
	_expect(farm.can_actor_command_plot(actor, "farm:indexed"), "indexed farm header preserves ownership semantics")
	_expect(gecs.indexed_cell_reads == 1, "cell work uses one indexed GECS cell read")
	_expect(gecs.indexed_header_reads == 1, "ownership uses one indexed GECS header read")
	_expect(gecs.legacy_all_plot_reads == 0, "single-cell work never materializes every farm plot")
	farm.free()
	gecs.free()
	actor.free()


func _test_real_farm_batch_atomicity() -> void:
	var farm := FARM_CONTROLLER.new()
	var gecs := FakeBatchFarmGecs.new()
	farm._gecs = gecs
	farm._crops["tomato"] = TOMATO_CROP
	gecs.state = {
		"plot_id": "farm:batch-real",
		"owner_faction_id": "Player",
		"settlement_id": "batch",
		"crop_policy_id": "",
		"field_deleted": false,
		"state_revision": 1,
		"cells": {"0:0": _untilled_cell(7)},
		"soil_remnants": {},
	}
	var observed := {"count": 0, "durable_state": "", "plot_changed": 0}
	farm.plot_changed.connect(func(_plot_id: String, _state: Dictionary) -> void:
		observed["plot_changed"] = int(observed["plot_changed"]) + 1
	)
	farm.work_completed.connect(func(_result: Dictionary) -> void:
		observed["count"] = int(observed["count"]) + 1
		observed["durable_state"] = str(((gecs.state.get("cells", {}) as Dictionary).get("0:0", {}) as Dictionary).get("state", ""))
	)
	var results := farm.apply_work_batch([
		{"plot_id": "farm:batch-real", "cell_key": "0:0", "action": "till", "seconds": 2.0, "expected_request_revision": 7},
		{"plot_id": "farm:batch-real", "cell_key": "0:0", "action": "till", "seconds": 2.0, "expected_request_revision": 7},
	])
	_expect(results.size() == 2 and not bool((results[0] as Dictionary).get("completed", true)) and bool((results[1] as Dictionary).get("completed", false)), "same-cell batch preserves ordered partial then completed results")
	_expect(is_equal_approx(float((results[0] as Dictionary).get("progress_seconds", 0.0)), 2.0) and is_equal_approx(float((results[1] as Dictionary).get("progress_seconds", 0.0)), 4.0), "same-cell batch applies both work deltas")
	_expect(gecs.upsert_count == 1, "same-plot batch persists exactly once")
	_expect(int(observed["count"]) == 1 and str(observed["durable_state"]) == "tilled", "completion emits once after durable state is visible")
	_expect(int(observed["plot_changed"]) == 1, "completed batch emits one projection change")
	gecs.state = {
		"plot_id": "farm:batch-real",
		"owner_faction_id": "Player",
		"settlement_id": "batch",
		"crop_policy_id": "",
		"field_deleted": false,
		"state_revision": 1,
		"cells": {"0:0": _untilled_cell(1), "1:0": _untilled_cell(1)},
		"soil_remnants": {},
	}
	gecs.upsert_count = 0
	var mixed := farm.apply_work_batch([
		{"plot_id": "farm:batch-real", "cell_key": "0:0", "action": "till", "seconds": 1.0, "expected_request_revision": 1},
		{"plot_id": "farm:batch-real", "cell_key": "1:0", "action": "till", "seconds": 1.0, "expected_request_revision": 0},
	])
	var persisted_cells: Dictionary = gecs.state.get("cells", {})
	_expect(not (mixed[0] as Dictionary).is_empty() and (mixed[1] as Dictionary).is_empty(), "mixed valid/stale batch keeps request-ordered success and rejection")
	_expect(gecs.upsert_count == 1 and is_equal_approx(float((persisted_cells["0:0"] as Dictionary).get("work_progress", 0.0)), 1.0), "mixed batch persists the valid cell once")
	_expect(is_equal_approx(float((persisted_cells["1:0"] as Dictionary).get("work_progress", 0.0)), 0.0), "mixed batch never mutates the stale cell")
	_expect(int(observed["plot_changed"]) == 1, "partial progress persists without rebuilding field offers or projection")
	farm.free()
	gecs.free()


func _untilled_cell(revision: int) -> Dictionary:
	return {
		"state": "untilled",
		"crop_id": "",
		"requested_operation": "till",
		"requested_crop_id": "",
		"requested_actor_ids": PackedStringArray(),
		"request_revision": revision,
		"work_progress": 0.0,
		"world_position": Vector3.ZERO,
	}


func _test_batched_bridge_commits() -> void:
	var holder := Node.new()
	root.add_child(holder)
	var farm := FakeBatchWorkFarm.new()
	var bridge := FARM_WORK.new()
	holder.add_child(farm)
	holder.add_child(bridge)
	bridge._farm = farm
	var actors := []
	for index in 2:
		var actor := FakeActor.new()
		actor.stable_id = "batch:%d" % index
		holder.add_child(actor)
		actors.append(actor)
		bridge._assignments[actor.get_instance_id()] = {
			"actor": actor,
			"plot_id": "farm:batch",
			"cell_key": "%d:0" % index,
			"action": "till",
			"world_position": Vector3.ZERO,
			"expected_target": Vector3.ZERO,
			"stage": "work",
			"required_seconds": 4.0,
			"progress_seconds": 0.0,
			"pending_work_seconds": 0.0,
			"request_revision": 1,
		}
	bridge._process(0.3)
	_expect(farm.batch_calls == 1, "one projected actor frame batches all due farm commits")
	_expect(farm.apply_calls == 0, "batched projected farm commits avoid per-actor writes")
	for actor_value in actors:
		var actor: FakeActor = actor_value
		var assignment: Dictionary = bridge._assignments.get(actor.get_instance_id(), {})
		_expect(is_equal_approx(float(assignment.get("progress_seconds", 0.0)), 0.3), "batched commits preserve each actor's work progress")
	root.remove_child(holder)
	holder.free()


func _test_batched_inventory_success_and_rollback() -> void:
	var holder := Node.new()
	root.add_child(holder)
	var farm := FakePartialBatchFarm.new()
	var bridge := FARM_WORK.new()
	holder.add_child(farm)
	holder.add_child(bridge)
	bridge._farm = farm
	var plant_ok := FakeActor.new()
	var plant_stale := FakeActor.new()
	plant_ok.stable_id = "plant:ok"
	plant_stale.stable_id = "plant:stale"
	plant_ok.inventory = INVENTORY.new(4, 4, 0.0, false)
	plant_stale.inventory = INVENTORY.new(4, 4, 0.0, false)
	plant_ok.inventory.add_item_count(TOMATO_SEEDS, 1)
	plant_stale.inventory.add_item_count(TOMATO_SEEDS, 1)
	holder.add_child(plant_ok)
	holder.add_child(plant_stale)
	bridge._assignments[plant_ok.get_instance_id()] = _resource_assignment(plant_ok, "plant", "ok:plant")
	bridge._assignments[plant_stale.get_instance_id()] = _resource_assignment(plant_stale, "plant", "stale:plant")
	bridge._process(1.1)
	_expect(plant_ok.inventory.count_item(TOMATO_SEEDS) == 0, "successful batched Plant consumes exactly one seed")
	_expect(plant_stale.inventory.count_item(TOMATO_SEEDS) == 1, "failed batched Plant restores its consumed seed")
	var harvest_ok := FakeActor.new()
	var harvest_stale := FakeActor.new()
	harvest_ok.stable_id = "harvest:ok"
	harvest_stale.stable_id = "harvest:stale"
	harvest_ok.inventory = INVENTORY.new(4, 4, 0.0, false)
	harvest_stale.inventory = INVENTORY.new(4, 4, 0.0, false)
	holder.add_child(harvest_ok)
	holder.add_child(harvest_stale)
	bridge._assignments[harvest_ok.get_instance_id()] = _resource_assignment(harvest_ok, "harvest", "ok:harvest")
	bridge._assignments[harvest_stale.get_instance_id()] = _resource_assignment(harvest_stale, "harvest", "stale:harvest")
	bridge._process(1.1)
	_expect(harvest_ok.inventory.count_item(TOMATO) == 4, "successful batched Harvest retains exactly its authoritative yield")
	_expect(harvest_stale.inventory.count_item(TOMATO) == 0, "failed batched Harvest rolls tentative yield back completely")
	_expect(farm.batch_calls == 2, "Plant and Harvest each use one shared batch transaction")
	root.remove_child(holder)
	holder.free()


func _resource_assignment(actor: FakeActor, action: String, cell_key: String) -> Dictionary:
	return {
		"actor": actor,
		"plot_id": "farm:resource-batch",
		"cell_key": cell_key,
		"action": action,
		"crop_id": "tomato",
		"world_position": Vector3.ZERO,
		"expected_target": Vector3.ZERO,
		"stage": "work",
		"required_seconds": 1.0,
		"progress_seconds": 0.0,
		"pending_work_seconds": 0.0,
		"request_revision": 1,
		"seed_item": TOMATO_SEEDS,
		"produce_item": TOMATO,
	}


func _test_cached_jobs_enabled_read_and_single_claim() -> void:
	var holder := Node.new()
	root.add_child(holder)
	var context := BootstrapContext.new(holder)
	var gecs := FakeGecs.new()
	var provider := SingleOfferProvider.new()
	var jobs := JOB_SYSTEM.new()
	holder.add_child(gecs)
	holder.add_child(provider)
	holder.add_child(jobs)
	context.register(&"gecs_world", gecs)
	context.register(&"job_system", jobs)
	jobs.initialize(context)
	jobs.register_job_provider(provider)
	var actors: Array[Node] = []
	for index in 2:
		var actor := FakeActor.new()
		actor.stable_id = "actor:%d" % index
		holder.add_child(actor)
		actors.append(actor)
		_expect(jobs.set_actor_jobs_enabled(actor, true), "actor Jobs policy enables")
	provider.category_query_count = 0
	for _read in 100:
		_expect(jobs.is_actor_jobs_enabled(actors[0]), "cached Jobs-enabled read stays true")
	_expect(provider.category_query_count == 0, "Jobs-enabled boolean reads do not rebuild provider categories")
	jobs._process_party_job_dispatch()
	_expect(provider.accept_count == 1, "one offer can be claimed only once in a shared dispatch burst")
	root.remove_child(holder)
	holder.free()


func _test_dynamic_provider_category_after_policy_cache() -> void:
	var holder := Node.new()
	root.add_child(holder)
	var context := BootstrapContext.new(holder)
	var gecs := FakeGecs.new()
	var jobs := JOB_SYSTEM.new()
	var actor := FakeActor.new()
	actor.stable_id = "dynamic:actor"
	holder.add_child(gecs)
	holder.add_child(jobs)
	holder.add_child(actor)
	context.register(&"gecs_world", gecs)
	context.register(&"job_system", jobs)
	jobs.initialize(context)
	_expect(jobs.set_actor_jobs_enabled(actor, true), "dynamic category actor Jobs policy enables before provider registration")
	var farm_rank_before := jobs.get_actor_job_entry_rank(actor, "category:farm")
	var provider := SingleOfferProvider.new()
	provider.category = "forestry"
	provider.entry_id = "category:forestry"
	provider.display_name = "Forestry"
	holder.add_child(provider)
	jobs.register_job_provider(provider)
	var forestry_rows := 0
	for row_value in jobs.get_actor_ranked_jobs(actor):
		if str((row_value as Dictionary).get("entry_id", "")) == "category:forestry":
			forestry_rows += 1
	_expect(forestry_rows == 1, "late provider category appears exactly once after policy caching")
	_expect(jobs.is_actor_jobs_enabled(actor) and jobs.get_actor_job_entry_rank(actor, "category:farm") == farm_rank_before, "late provider category preserves Jobs toggle and existing ranks")
	jobs._process_party_job_dispatch()
	_expect(provider.accept_count == 1, "late provider category offer dispatches through the cached policy")
	jobs.unregister_job_provider(provider)
	var forestry_after_unregister := 0
	for row_value in jobs.get_actor_ranked_jobs(actor):
		if str((row_value as Dictionary).get("entry_id", "")) == "category:forestry":
			forestry_after_unregister += 1
	_expect(forestry_after_unregister == 0 and jobs.is_actor_jobs_enabled(actor), "unregistered provider category disappears without resetting Jobs")
	root.remove_child(holder)
	holder.free()


func _test_jobs_policy_hydration() -> void:
	var holder := Node.new()
	root.add_child(holder)
	var gecs := FakeGecs.new()
	var actor := FakeActor.new()
	actor.stable_id = "hydrate:actor"
	holder.add_child(gecs)
	holder.add_child(actor)
	actor.add_to_group("party_member")
	var first_context := BootstrapContext.new(holder)
	first_context.register(&"gecs_world", gecs)
	var first := JOB_SYSTEM.new()
	holder.add_child(first)
	first_context.register(&"job_system", first)
	first.initialize(first_context)
	_expect(first.set_actor_jobs_enabled(actor, true), "initial persisted Jobs toggle enables")
	var saved_enabled: Dictionary = (gecs.job_state.get("actor_policies", {}) as Dictionary).get(actor.stable_id, {})
	_expect(bool(saved_enabled.get("jobs_enabled", false)), "GECS stores the enabled Jobs value")
	holder.remove_child(first)
	first.free()
	var enabled_context := BootstrapContext.new(holder)
	enabled_context.register(&"gecs_world", gecs)
	var enabled := JOB_SYSTEM.new()
	var provider := SingleOfferProvider.new()
	holder.add_child(provider)
	holder.add_child(enabled)
	enabled_context.register(&"job_system", enabled)
	enabled.initialize(enabled_context)
	enabled.register_job_provider(provider)
	_expect(enabled.is_actor_jobs_enabled(actor) and enabled._enabled_party_actors.has(actor.get_instance_id()), "fresh controller hydrates enabled policy and dispatch membership")
	enabled._process_party_job_dispatch()
	_expect(provider.accept_count == 1, "hydrated enabled policy dispatches automatic work")
	_expect(enabled.set_actor_jobs_enabled(actor, false), "persisted Jobs toggle disables")
	holder.remove_child(enabled)
	enabled.free()
	var disabled_context := BootstrapContext.new(holder)
	disabled_context.register(&"gecs_world", gecs)
	var disabled := JOB_SYSTEM.new()
	holder.add_child(disabled)
	disabled_context.register(&"job_system", disabled)
	disabled.initialize(disabled_context)
	disabled.register_job_provider(provider)
	var accepts_before := provider.accept_count
	disabled._process_party_job_dispatch()
	_expect(not disabled.is_actor_jobs_enabled(actor) and not disabled._enabled_party_actors.has(actor.get_instance_id()), "fresh controller hydrates disabled policy without dispatch membership")
	_expect(provider.accept_count == accepts_before, "hydrated disabled policy cannot dispatch work")
	root.remove_child(holder)
	holder.free()


func _test_production_dispatch_spreads_actor_work() -> void:
	var holder := Node.new()
	root.add_child(holder)
	var context := BootstrapContext.new(holder)
	var gecs := FakeGecs.new()
	var provider := SingleOfferProvider.new()
	provider.offer_count = 2
	var jobs := JOB_SYSTEM.new()
	holder.add_child(gecs)
	holder.add_child(provider)
	holder.add_child(jobs)
	context.register(&"gecs_world", gecs)
	context.register(&"job_system", jobs)
	jobs.initialize(context)
	jobs.register_job_provider(provider)
	for index in 2:
		var actor := FakeActor.new()
		actor.stable_id = "cadence:%d" % index
		holder.add_child(actor)
		_expect(jobs.set_actor_jobs_enabled(actor, true), "cadence actor Jobs policy enables")
	var slot := float(JOB_SYSTEM.DISPATCH_SLOT_SECONDS)
	jobs._process(slot)
	_expect(provider.accept_count == 1, "production cadence starts at most one new actor task per frame")
	jobs._process(slot * 0.49)
	_expect(provider.accept_count == 1, "sub-slot frame time cannot dispatch the next actor early")
	jobs._process(slot * 0.51 + 0.000001)
	_expect(provider.accept_count == 2, "production cadence advances the next actor on the following frame")
	root.remove_child(holder)
	holder.free()


func _test_mixed_party_assignment_fairness() -> void:
	var holder := Node.new()
	root.add_child(holder)
	var context := BootstrapContext.new(holder)
	var gecs := FakeGecs.new()
	var population := FakePopulation.new()
	var provider := SingleOfferProvider.new()
	provider.offer_count = 2
	var jobs := JOB_SYSTEM.new()
	holder.add_child(gecs)
	holder.add_child(population)
	holder.add_child(provider)
	holder.add_child(jobs)
	context.register(&"gecs_world", gecs)
	context.register(&"population", population)
	context.register(&"job_system", jobs)
	jobs.initialize(context)
	jobs.register_job_provider(provider)
	var party_actor := FakeActor.new()
	party_actor.stable_id = "mixed:party"
	holder.add_child(party_actor)
	_expect(jobs.set_actor_jobs_enabled(party_actor, true), "mixed party actor Jobs policy enables")
	var assignment_actor := FakeActor.new()
	assignment_actor.stable_id = "mixed:assignment"
	assignment_actor.player_party_member = false
	holder.add_child(assignment_actor)
	population.actors_by_id[assignment_actor.stable_id] = assignment_actor
	jobs._assignment_workers[assignment_actor.stable_id] = {
		"actor_id": assignment_actor.stable_id,
		"settlement_id": "mixed-town",
		"facility_id": "mixed-facility",
		"allowed_job_entry_ids": PackedStringArray(["category:crafting"]),
		"schedule_enabled": false,
	}
	jobs._assignment_actor_order.append(assignment_actor.stable_id)
	jobs._process_party_job_dispatch(1)
	_expect(provider.accept_count == 1 and provider.accepted_actor_ids.has(party_actor.stable_id), "mixed cadence gives the first bounded slot to party work")
	jobs._process_party_job_dispatch(1)
	_expect(provider.accept_count == 2 and provider.accepted_actor_ids.has(assignment_actor.stable_id), "mixed cadence gives the next bounded slot to assignment work")
	root.remove_child(holder)
	holder.free()


func _test_busy_actor_skips_offer_collection() -> void:
	var holder := Node.new()
	root.add_child(holder)
	var context := BootstrapContext.new(holder)
	var gecs := FakeGecs.new()
	var provider := SingleOfferProvider.new()
	var jobs := JOB_SYSTEM.new()
	var actor := FakeActor.new()
	actor.stable_id = "busy:actor"
	holder.add_child(gecs)
	holder.add_child(provider)
	holder.add_child(jobs)
	holder.add_child(actor)
	context.register(&"gecs_world", gecs)
	context.register(&"job_system", jobs)
	jobs.initialize(context)
	jobs.register_job_provider(provider)
	_expect(jobs.set_actor_jobs_enabled(actor, true), "busy actor Jobs policy enables")
	actor.active_player_order = true
	provider.offer_query_count = 0
	jobs._process_party_job_dispatch(1)
	_expect(provider.offer_query_count == 0, "busy actor is rejected before provider offer collection")
	root.remove_child(holder)
	holder.free()


func _test_travel_checks_are_staggered() -> void:
	var holder := Node.new()
	root.add_child(holder)
	var farm := FakeBatchWorkFarm.new()
	var bridge := FARM_WORK.new()
	var actor := FakeTravelActor.new()
	actor.position = Vector3(50.0, 0.0, 0.0)
	actor.move_target = Vector3.ZERO
	holder.add_child(farm)
	holder.add_child(bridge)
	holder.add_child(actor)
	bridge._farm = farm
	bridge._assignments[actor.get_instance_id()] = {
		"actor": actor,
		"plot_id": "farm:travel",
		"cell_key": "0:0",
		"action": "till",
		"expected_target": Vector3.ZERO,
		"world_position": Vector3.ZERO,
		"stage": "work",
		"automatic": true,
		"traveling": true,
		"travel_check_accumulated": 0.0,
		"travel_seconds": 0.0,
		"stalled_seconds": 0.0,
		"last_actor_position": actor.global_position,
	}
	for _frame in 10:
		bridge._process(0.01)
	var assignment: Dictionary = bridge._assignments.get(actor.get_instance_id(), {})
	_expect(actor.farming_visual_calls <= 2, "traveling farm workers are not fully reprocessed every frame")
	_expect(float(assignment.get("travel_seconds", 0.0)) >= 0.09, "staggered travel checks preserve timeout elapsed time")
	root.remove_child(holder)
	holder.free()


func _test_process_gate_keeps_immediate_arrival() -> void:
	var holder := Node.new()
	root.add_child(holder)
	var farm := FakeBatchWorkFarm.new()
	var bridge := FARM_WORK.new()
	var actor := FakeTravelActor.new()
	actor.position = Vector3(50.0, 0.0, 0.0)
	actor.move_target = Vector3.ZERO
	holder.add_child(farm)
	holder.add_child(bridge)
	holder.add_child(actor)
	bridge._farm = farm
	bridge._assignments[actor.get_instance_id()] = {
		"actor": actor,
		"plot_id": "farm:arrival",
		"cell_key": "0:0",
		"action": "till",
		"expected_target": Vector3.ZERO,
		"world_position": Vector3.ZERO,
		"stage": "work",
		"automatic": true,
		"traveling": true,
		"travel_seconds": 0.0,
		"stalled_seconds": 0.0,
		"last_actor_position": actor.global_position,
		"required_seconds": 4.0,
		"progress_seconds": 0.0,
		"pending_work_seconds": 0.0,
	}
	for _frame in 9:
		bridge._process(0.01)
	actor.position = Vector3(1.0, 0.0, 0.0)
	bridge._process(0.01)
	var assignment: Dictionary = bridge._assignments.get(actor.get_instance_id(), {})
	_expect(not bool(assignment.get("traveling", true)) and not actor.moving, "process gate stops navigation immediately when a worker enters farm range")
	_expect(actor.farming_visual_calls > 0, "immediate farm arrival begins the existing work presentation")
	_expect(float(assignment.get("pending_work_seconds", 0.0)) <= 0.011, "arrival counts only the current frame as productive work")
	root.remove_child(holder)
	holder.free()


func _test_travel_elapsed_is_per_assignment() -> void:
	var holder := Node.new()
	root.add_child(holder)
	var farm := FakeBatchWorkFarm.new()
	var bridge := FARM_WORK.new()
	var older := FakeTravelActor.new()
	var newer := FakeTravelActor.new()
	older.position = Vector3(50.0, 0.0, 0.0)
	newer.position = Vector3(60.0, 0.0, 0.0)
	holder.add_child(farm)
	holder.add_child(bridge)
	holder.add_child(older)
	holder.add_child(newer)
	bridge._farm = farm
	bridge._assignments[older.get_instance_id()] = _travel_assignment(older, "older")
	for _frame in 5:
		bridge._process(0.01)
	bridge._assignments[newer.get_instance_id()] = _travel_assignment(newer, "newer")
	for _frame in 5:
		bridge._process(0.01)
	var older_state: Dictionary = bridge._assignments.get(older.get_instance_id(), {})
	var newer_state: Dictionary = bridge._assignments.get(newer.get_instance_id(), {})
	_expect(is_equal_approx(float(older_state.get("travel_seconds", 0.0)), 0.1), "older travel leg receives its own elapsed time")
	_expect(is_equal_approx(float(newer_state.get("travel_seconds", 0.0)), 0.0), "new travel leg cannot inherit an older worker's due slot")
	for _frame in 5:
		bridge._process(0.01)
	newer_state = bridge._assignments.get(newer.get_instance_id(), {})
	_expect(is_equal_approx(float(newer_state.get("travel_seconds", 0.0)), 0.1), "new travel leg receives its own complete interval when due")
	root.remove_child(holder)
	holder.free()


func _travel_assignment(actor: FakeTravelActor, cell_key: String) -> Dictionary:
	return {
		"actor": actor,
		"plot_id": "farm:travel-elapsed",
		"cell_key": cell_key,
		"action": "till",
		"expected_target": Vector3.ZERO,
		"world_position": Vector3.ZERO,
		"stage": "work",
		"automatic": true,
		"traveling": true,
		"travel_seconds": 0.0,
		"stalled_seconds": 0.0,
		"last_actor_position": actor.global_position,
	}


func _test_displaced_worker_starts_fresh_travel_leg() -> void:
	var holder := Node.new()
	root.add_child(holder)
	var farm := FakeBatchWorkFarm.new()
	var bridge := FARM_WORK.new()
	var actor := FakeTravelActor.new()
	actor.position = Vector3(50.0, 0.0, 0.0)
	holder.add_child(farm)
	holder.add_child(bridge)
	holder.add_child(actor)
	bridge._farm = farm
	bridge._process_sim_time = 5.0
	var assignment := _travel_assignment(actor, "displaced")
	assignment["traveling"] = false
	assignment["last_travel_check_time"] = 0.0
	bridge._assignments[actor.get_instance_id()] = assignment
	bridge._process(0.01)
	bridge._process(0.01)
	var displaced: Dictionary = bridge._assignments.get(actor.get_instance_id(), {})
	_expect(float(displaced.get("travel_seconds", 0.0)) <= 0.011, "displaced worker starts a fresh travel leg without inheriting old work time")
	root.remove_child(holder)
	holder.free()


func _test_process_gate_preempts_player_order_immediately() -> void:
	var holder := Node.new()
	root.add_child(holder)
	var farm := FakeBatchWorkFarm.new()
	var bridge := FARM_WORK.new()
	var actor := FakeTravelActor.new()
	actor.position = Vector3(50.0, 0.0, 0.0)
	holder.add_child(farm)
	holder.add_child(bridge)
	holder.add_child(actor)
	bridge._farm = farm
	bridge._assignments[actor.get_instance_id()] = _travel_assignment(actor, "preempt")
	bridge._process(0.01)
	actor.active_player_order = true
	bridge._process(0.01)
	_expect(not bridge._assignments.has(actor.get_instance_id()), "player order preempts traveling farm work below travel cadence")
	root.remove_child(holder)
	holder.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("JOBS_SCHEDULER_HOT_PATH_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("JOBS_SCHEDULER_HOT_PATH_FAILED count=%d" % _failures.size())
	quit(1)
