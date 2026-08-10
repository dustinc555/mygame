extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_farm_controller.gd

class FakeGecs:
	extends Node
	signal world_reindexed
	var states := {}
	var water_states := {}
	func upsert_farm_plot_state(state: Dictionary) -> Dictionary:
		states[str(state.get("plot_id", ""))] = state.duplicate(true)
		return states[str(state.get("plot_id", ""))].duplicate(true)
	func get_farm_plot_states() -> Dictionary:
		return states.duplicate(true)
	func remove_farm_plot_state(plot_id: String) -> void:
		states.erase(plot_id)
	func upsert_farm_water_source_state(state: Dictionary) -> Dictionary:
		water_states[str(state.get("source_id", ""))] = state.duplicate(true)
		return water_states[str(state.get("source_id", ""))].duplicate(true)
	func get_farm_water_source_states() -> Dictionary:
		return water_states.duplicate(true)

class FakeTime:
	extends Node
	signal minute_changed(absolute_minute: int, day: int, hour: int, minute: int)
	var absolute_minute := 0
	func get_absolute_minute() -> int:
		return absolute_minute

class FakeActor:
	extends Node
	var faction_name := ""
	var stable_id := "test-actor"

class FakeRetiringWork:
	extends Node
	var active_keys := PackedStringArray()
	var retired_plot_id := ""
	var controller: Node
	var queued_cell_key := ""
	var queued_revision := -1
	var queued_actor_id := ""
	func retire_plot_work(plot_id: String) -> PackedStringArray:
		retired_plot_id = plot_id
		if controller != null and not queued_cell_key.is_empty():
			controller.cancel_cell_operation(plot_id, queued_cell_key, queued_revision, queued_actor_id)
		return active_keys.duplicate()
	func get_active_cell_keys_for_plot(_plot_id: String) -> PackedStringArray:
		return active_keys.duplicate()

var failures: Array[String] = []


func _init() -> void:
	var controller = load("res://features/farming/sim/farm_controller.gd").new()
	var gecs := FakeGecs.new()
	var time := FakeTime.new()
	root.add_child(gecs)
	root.add_child(time)
	root.add_child(controller)
	controller._gecs = gecs
	controller._world_time = time
	for crop_id in controller.CROP_PATHS:
		controller._crops[crop_id] = load(controller.CROP_PATHS[crop_id])
	var positions: Array[Vector3] = [Vector3.ZERO, Vector3(1.25, 0, 0)]
	var plot: Dictionary = controller.create_plot(positions, Vector2i(2, 1), "tomato", "Player")
	_expect(not plot.is_empty(), "creates a durable plot")
	_expect((plot.get("cells", {}) as Dictionary).size() == 2, "creates one state record per cell")
	_expect(controller.create_plot(positions, Vector2i(2, 1), "wheat", "Player").is_empty(), "durable field authority rejects world-space overlap with an existing field")
	var painted_positions: Array[Vector3] = [Vector3(5.0, 0, 5.0), Vector3(6.25, 0, 5.0), Vector3(6.25, 0, 6.25)]
	var painted: Dictionary = controller.create_plot(painted_positions, Vector2i(2, 2), "tomato", "Player", "", {}, PackedStringArray(["0:0", "1:0", "1:1"]))
	_expect((painted.get("cells", {}) as Dictionary).size() == 3 and not (painted.get("cells", {}) as Dictionary).has("0:1"), "painted plot persists only painted cells")
	var excessive_positions: Array[Vector3] = []
	excessive_positions.resize(300)
	_expect(controller.create_plot(excessive_positions, Vector2i(20, 15), "tomato", "Player").is_empty(), "rejects plots above the authored cell limit")
	controller.request_cell_operation(str(plot.plot_id), "0:0", "till")
	var work: Dictionary = controller.get_next_work(str(plot.plot_id))
	_expect(str(work.get("action", "")) == "till" and str(work.get("cell_key", "")) == "0:0", "individual till exposes only its requested cell")
	var partial: Dictionary = controller.apply_work(str(plot.plot_id), str(work.cell_key), "till", 1.0)
	_expect(not bool(partial.get("completed", true)), "short work preserves partial progress")
	var persisted: Dictionary = controller.get_plot(str(plot.plot_id))
	_expect(float((persisted.cells[work.cell_key] as Dictionary).work_progress) > 0.0, "partial progress persists in GECS state")
	var completed: Dictionary = controller.apply_work(str(plot.plot_id), str(work.cell_key), "till", 20.0)
	_expect(bool(completed.get("completed", false)), "enough work completes tilling")
	persisted = controller.get_plot(str(plot.plot_id))
	_expect(str((persisted.cells[work.cell_key] as Dictionary).state) == "tilled", "completed tilling changes only its cell")
	controller.refresh_obstacle(str(plot.plot_id), str(work.cell_key), true, "temporary rock")
	controller.refresh_obstacle(str(plot.plot_id), str(work.cell_key), false)
	persisted = controller.get_plot(str(plot.plot_id))
	_expect(str((persisted.cells[work.cell_key] as Dictionary).state) == "tilled", "temporary obstruction restores the displaced cell state")
	controller.request_cell_operation(str(plot.plot_id), str(work.cell_key), "plant", "bell_pepper")
	var plant_work: Dictionary = controller.get_cell_work(str(plot.plot_id), str(work.cell_key))
	_expect(str(plant_work.get("crop_id", "")) == "bell_pepper", "individual plant order stores its selected crop on that cell")
	var bell_request_revision := int(plant_work.get("request_revision", -1))
	controller.request_cell_operation(str(plot.plot_id), str(work.cell_key), "plant", "tomato")
	_expect(controller.apply_work(str(plot.plot_id), str(work.cell_key), "plant", 20.0, 0.0, bell_request_revision).is_empty(), "reissued Plant crop invalidates the old seed/work transaction")
	_expect(str(controller.get_cell_work(str(plot.plot_id), str(work.cell_key)).get("crop_id", "")) == "tomato", "reissued Plant order exposes only its latest crop transaction")
	var owner := FakeActor.new()
	owner.faction_name = "Player"
	var outsider := FakeActor.new()
	outsider.faction_name = "Raiders"
	var retiring_work := FakeRetiringWork.new()
	root.add_child(retiring_work)
	retiring_work.controller = controller
	var controller_context := BootstrapContext.new(root)
	controller_context.register(&"farm_work", retiring_work)
	controller._context = controller_context
	_expect(controller.has_method("prepare_plot_till"), "selected fields expose one whole-field till transaction")
	if controller.has_method("prepare_plot_till"):
		var whole_positions: Array[Vector3] = [Vector3(70.0, 0.0, 70.0), Vector3(71.25, 0.0, 70.0), Vector3(72.5, 0.0, 70.0)]
		var whole_plot: Dictionary = controller.create_plot(whole_positions, Vector2i(3, 1), "", "Player")
		var whole_state: Dictionary = controller.get_plot(str(whole_plot.get("plot_id", "")))
		whole_state["cells"]["1:0"] = controller.FARM_SIMULATION.complete_tilling(whole_state["cells"]["1:0"])
		whole_state["cells"]["2:0"] = controller.FARM_SIMULATION.block_cell(whole_state["cells"]["2:0"], "occupied")
		controller.call("_save_plot", whole_state)
		var whole_order: Dictionary = controller.call("prepare_plot_till", str(whole_plot.get("plot_id", "")), owner)
		var whole_targets: Array = whole_order.get("targets", [])
		_expect(whole_targets.size() == 1 and str((whole_targets[0] as Dictionary).get("cell_key", "")) == "0:0", "whole-field Till skips cultivated and blocked cells")
		_expect(controller.call("prepare_plot_till", str(whole_plot.get("plot_id", "")), outsider).is_empty(), "whole-field Till is owner-gated")
		var plant_positions: Array[Vector3] = [Vector3(75.0, 0.0, 70.0), Vector3(76.25, 0.0, 70.0), Vector3(77.5, 0.0, 70.0)]
		var plant_plot: Dictionary = controller.create_plot(plant_positions, Vector2i(3, 1), "", "Player")
		var plant_state: Dictionary = controller.get_plot(str(plant_plot.get("plot_id", "")))
		plant_state["cells"]["0:0"] = controller.FARM_SIMULATION.complete_tilling(plant_state["cells"]["0:0"])
		plant_state["cells"]["1:0"] = controller.FARM_SIMULATION.complete_tilling(plant_state["cells"]["1:0"])
		controller.call("_save_plot", plant_state)
		var actor_ids := PackedStringArray([owner.stable_id])
		var plant_order: Dictionary = controller.prepare_plot_operation(str(plant_plot.get("plot_id", "")), "plant", "tomato", actor_ids, "1:0")
		var plant_targets: Array = plant_order.get("targets", [])
		_expect(plant_targets.size() == 2 and str((plant_targets[0] as Dictionary).get("cell_key", "")) == "1:0", "Shift Plant targets every valid tilled cell and starts with the clicked slot")
		_expect(PackedStringArray(controller.get_cell_work(str(plant_plot.get("plot_id", "")), "0:0").get("allowed_actor_ids", PackedStringArray())) == actor_ids \
				and controller.get_cell_work(str(plant_plot.get("plot_id", "")), "2:0").is_empty(), "field-wide manual work is actor-reserved and skips cells where that action is invalid")
		_expect(controller.prepare_plot_operation(str(plant_plot.get("plot_id", "")), "plant", "tomato", actor_ids, "2:0").is_empty(), "a stale invalid clicked slot rejects the whole Shift action instead of fanning out elsewhere")
		var harvest_positions: Array[Vector3] = [Vector3(75.0, 0.0, 75.0), Vector3(76.25, 0.0, 75.0)]
		var harvest_plot: Dictionary = controller.create_plot(harvest_positions, Vector2i(2, 1), "", "Player")
		var harvest_state: Dictionary = controller.get_plot(str(harvest_plot.get("plot_id", "")))
		harvest_state["cells"]["0:0"]["state"] = "ripe"
		harvest_state["cells"]["0:0"]["crop_id"] = "tomato"
		harvest_state["cells"]["1:0"]["state"] = "ripe"
		harvest_state["cells"]["1:0"]["crop_id"] = "wheat"
		controller.call("_save_plot", harvest_state)
		var harvest_order: Dictionary = controller.prepare_plot_operation(str(harvest_plot.get("plot_id", "")), "harvest", "", actor_ids, "0:0", owner)
		var harvest_targets: Array = harvest_order.get("targets", [])
		_expect(harvest_targets.size() == 1 and str((harvest_targets[0] as Dictionary).get("cell_key", "")) == "0:0", "Shift Harvest skips mixed-crop cells whose required tool the selected actor cannot equip")
	_expect(controller.has_method("plot_cell_keys_in_rectangle"), "field subtraction can clip a rectangle to exact sparse membership")
	if controller.has_method("plot_cell_keys_in_rectangle"):
		var clipped: PackedStringArray = controller.call("plot_cell_keys_in_rectangle", str(painted.get("plot_id", "")), Vector3(5.0, 0.0, 5.0), Vector3(6.25, 0.0, 6.25))
		_expect(clipped.size() == 3 and not clipped.has("0:1"), "subtraction preview excludes non-field cells inside its rectangle")
	_expect(controller.has_method("delete_field"), "owned selected fields expose logical deletion")
	if controller.has_method("delete_field"):
		var deletion_positions: Array[Vector3] = [Vector3(80.0, 0.0, 80.0), Vector3(81.25, 0.0, 80.0), Vector3(82.5, 0.0, 80.0)]
		var deletion_plot: Dictionary = controller.create_plot(deletion_positions, Vector2i(3, 1), "tomato", "Player")
		var deletion_id := str(deletion_plot.get("plot_id", ""))
		var deletion_state: Dictionary = controller.get_plot(deletion_id)
		deletion_state["cells"]["0:0"] = controller.FARM_SIMULATION.complete_planting(controller.FARM_SIMULATION.complete_tilling(deletion_state["cells"]["0:0"]), "tomato", 20.0)
		deletion_state["cells"]["1:0"] = controller.FARM_SIMULATION.complete_tilling(deletion_state["cells"]["1:0"])
		controller.call("_save_plot", deletion_state)
		controller.request_cell_operation(deletion_id, "2:0", "till")
		var queued_request: Dictionary = controller.request_cell_operation(deletion_id, "1:0", "plant", "tomato", PackedStringArray(["owner-test"]))
		var queued_revision := int((queued_request.get("cells", {}) as Dictionary)["1:0"].get("request_revision", -1))
		retiring_work.queued_cell_key = "1:0"
		retiring_work.queued_revision = queued_revision
		retiring_work.queued_actor_id = "owner-test"
		retiring_work.active_keys = PackedStringArray(["2:0"])
		_expect(controller.call("delete_field", deletion_id, outsider).is_empty(), "another faction cannot delete the field")
		var deleted: Dictionary = controller.call("delete_field", deletion_id, owner)
		_expect(bool(deleted.get("field_deleted", false)), "deletion retires the logical field immediately")
		_expect((deleted.get("cells", {}) as Dictionary).size() == 3, "deletion preserves living crops, cultivated soil, and the active physical cell")
		_expect(not bool(controller.call("is_active_field", deleted)), "deleted remnant state is no longer a field")
		_expect(str(controller.get_cell(deletion_id, "1:0").get("requested_operation", "")).is_empty() and int(controller.get_cell(deletion_id, "1:0").get("request_revision", -1)) > queued_revision, "delete refetches queue-cancellation revisions instead of overwriting them with a stale snapshot")
		_expect(controller.get_next_work(deletion_id).is_empty(), "deleted remnants cannot publish new automatic work claims")
		_expect(retiring_work.retired_plot_id == deletion_id, "deletion retires the field work queue immediately")
		var active_work: Dictionary = controller.get_cell_work(deletion_id, "2:0")
		var active_finish: Dictionary = controller.apply_work(deletion_id, "2:0", "till", 20.0, 0.0, int(active_work.get("request_revision", -1)))
		_expect(bool(active_finish.get("completed", false)) and bool(controller.get_cell(deletion_id, "2:0").get("soil_created", false)), "the active cell can finish after logical field deletion")
		var retired_plant_request: Dictionary = controller.request_cell_operation(deletion_id, "1:0", "plant", "tomato", PackedStringArray(["owner-test"]))
		_expect(controller.get_next_work(deletion_id).is_empty(), "direct retired-cell work never becomes an automatic field offer")
		var retired_plant_work: Dictionary = controller.get_cell_work(deletion_id, "1:0")
		var retired_plant_finish: Dictionary = controller.apply_work(deletion_id, "1:0", "plant", 20.0, 0.0, int(retired_plant_work.get("request_revision", -1)))
		_expect(not retired_plant_request.is_empty() and bool(retired_plant_finish.get("completed", false)), "direct Plant remains functional on physical tilled soil after field deletion")
		var replanned: Dictionary = controller.create_plot(deletion_positions, Vector2i(3, 1), "", "Player")
		var replanned_cells: Dictionary = replanned.get("cells", {})
		_expect(controller.is_active_field(replanned) and replanned_cells.size() == 3, "a field can be redrawn directly over retired cultivated cells")
		_expect(str((replanned_cells.get("0:0", {}) as Dictionary).get("crop_id", "")) == "tomato" and str((replanned_cells.get("1:0", {}) as Dictionary).get("crop_id", "")) == "tomato", "redrawing preserves existing plants instead of replacing physical cell state")
		var fresh_position := Vector3(80.0, 0.0, 81.25)
		var fresh_positions: Array[Vector3] = [fresh_position]
		var fresh_order: Dictionary = controller.prepare_manual_till(fresh_positions, owner, fresh_position)
		var fresh_id := str(fresh_order.get("plot_id", ""))
		_expect(not fresh_id.is_empty() and fresh_id != deletion_id and controller.is_active_field(fresh_id), "new tilling beside remnants starts a new field instead of reviving deleted identity")
		var interrupted_position := Vector3(85.0, 0.0, 80.0)
		var interrupted_positions: Array[Vector3] = [interrupted_position]
		var interrupted_plot: Dictionary = controller.create_plot(interrupted_positions, Vector2i.ONE, "", "Player")
		var interrupted_id := str(interrupted_plot.get("plot_id", ""))
		controller.request_cell_operation(interrupted_id, "0:0", "till")
		retiring_work.active_keys = PackedStringArray(["0:0"])
		controller.delete_field(interrupted_id, owner)
		var interrupted_revision := int(controller.get_cell(interrupted_id, "0:0").get("request_revision", -1))
		retiring_work.active_keys.clear()
		controller.call("_reconcile_deleted_requests", controller.get_plot(interrupted_id))
		_expect(controller.get_cell_work(interrupted_id, "0:0").is_empty() and int(controller.get_cell(interrupted_id, "0:0").get("request_revision", -1)) > interrupted_revision, "reload interruption cancels and invalidates a retired active-cell request that no worker still owns")
		var offer_bridge = load("res://features/farming/bridge/farm_work_bridge.gd").new()
		offer_bridge._farm = controller
		root.add_child(offer_bridge)
		var deleted_offer_found := false
		for offer_value in offer_bridge.get_available_work_offers():
			if str((offer_value as Dictionary).get("plot_id", "")) in [deletion_id, interrupted_id]:
				deleted_offer_found = true
		_expect(not deleted_offer_found, "deleted remnant requests are never enumerated as fresh automatic work offers")
	var split_positions: Array[Vector3] = [Vector3(90.0, 0.0, 90.0), Vector3(91.25, 0.0, 90.0), Vector3(92.5, 0.0, 90.0), Vector3(93.75, 0.0, 90.0), Vector3(95.0, 0.0, 90.0)]
	var split_plot: Dictionary = controller.create_plot(split_positions, Vector2i(5, 1), "wheat", "Player")
	var split_id := str(split_plot.get("plot_id", ""))
	var count_before_split: int = controller.get_plots().size()
	var split_result: Dictionary = controller.shrink_plot(split_id, PackedStringArray(["2:0"]), owner)
	var inherited_fields: Array[Dictionary] = []
	for split_value in controller.get_plots().values():
		var candidate: Dictionary = split_value
		if not bool(candidate.get("field_deleted", false)) \
				and str(candidate.get("display_name", "")) == str(split_plot.get("display_name", "")) \
				and ((candidate.get("cells", {}) as Dictionary).has("0:0") or (candidate.get("cells", {}) as Dictionary).has("3:0")):
			inherited_fields.append(candidate)
	_expect(not split_result.is_empty() and controller.get_plots().size() == count_before_split + 1, "subtracting through a field splits disconnected islands")
	_expect(inherited_fields.size() == 2, "each disconnected island remains a separately managed field")
	_expect(controller.has_method("prepare_manual_till"), "controller exposes one durable manual-till rectangle transaction")
	if controller.has_method("prepare_manual_till"):
		var manual_positions: Array[Vector3] = [Vector3(20.0, 0.0, 20.0), Vector3(21.25, 0.0, 20.0)]
		var manual_order: Dictionary = controller.call("prepare_manual_till", manual_positions, owner, manual_positions[0])
		var manual_plot_id := str(manual_order.get("plot_id", ""))
		var manual_keys := PackedStringArray(manual_order.get("cell_keys", PackedStringArray()))
		var manual_plot: Dictionary = controller.get_plot(manual_plot_id)
		_expect(not manual_plot.is_empty() and str(manual_plot.get("crop_policy_id", "missing")).is_empty(), "manual hoeing starts a No Crop field")
		_expect(manual_keys.size() == 2, "one click-drag preserves every eligible rectangle cell")
		for manual_key in manual_keys:
			var manual_work: Dictionary = controller.get_cell_work(manual_plot_id, manual_key)
			_expect(str(manual_work.get("action", "")) == "till", "every manual rectangle cell receives exact till work")
			_expect(PackedStringArray(manual_work.get("allowed_actor_ids", PackedStringArray())) == PackedStringArray([owner.stable_id]), "Till Ground reserves every selected square for its commanded actor")
			_expect(int((manual_order.get("targets", []) as Array)[0].get("request_revision", -1)) >= 0, "manual rectangle snapshots each durable request revision")
		var adjacent_positions: Array[Vector3] = [Vector3(22.5, 0.0, 20.0)]
		var adjacent_order: Dictionary = controller.call("prepare_manual_till", adjacent_positions, owner, adjacent_positions[0])
		_expect(str(adjacent_order.get("plot_id", "")) == manual_plot_id, "adjacent No Crop hoeing expands the existing field")
		var recovery_keys := PackedStringArray(adjacent_order.get("cell_keys", PackedStringArray()))
		var edge_key := recovery_keys[0] if not recovery_keys.is_empty() else "2:0"
		var member_key := manual_keys[0]
		for recovery_key in [member_key, edge_key]:
			var recovery_work: Dictionary = controller.get_cell_work(manual_plot_id, recovery_key)
			controller.apply_work(manual_plot_id, recovery_key, "till", 999.0, 0.0, int(recovery_work.get("request_revision", -1)))
		var shrunk_for_recovery: Dictionary = controller.shrink_plot(manual_plot_id, PackedStringArray([edge_key]), owner)
		_expect(not shrunk_for_recovery.is_empty(), "removing an edge cell preserves a contiguous logical field")
		_expect(not (shrunk_for_recovery.get("cells", {}) as Dictionary).has(edge_key), "removed soil is no longer logical field membership")
		_expect((shrunk_for_recovery.get("soil_remnants", {}) as Dictionary).has(edge_key), "removed cultivated soil remains physically authoritative during recovery")
		controller.call("_advance_plot", manual_plot_id, 2879)
		_expect((controller.get_plot(manual_plot_id).get("soil_remnants", {}) as Dictionary).has(edge_key), "projection teardown before the threshold cannot recover removed soil")
		controller.call("_advance_plot", manual_plot_id, 2880)
		var recovered_plot: Dictionary = controller.get_plot(manual_plot_id)
		_expect(not (recovered_plot.get("soil_remnants", {}) as Dictionary).has(edge_key), "elapsed authoritative time removes recovered physical remnants")
		_expect((recovered_plot.get("cells", {}) as Dictionary).has(member_key), "soil recovery never deletes logical field membership")
		_expect(not bool(((recovered_plot.get("cells", {}) as Dictionary)[member_key] as Dictionary).get("soil_created", true)), "empty No Crop member soil also recovers to natural ground")
		var detached_position := Vector3(23.75, 0.0, 20.0)
		var detached_state: Dictionary = controller.get_plot(manual_plot_id)
		var detached_remnants: Dictionary = detached_state.get("soil_remnants", {}).duplicate(true)
		var detached_cell: Dictionary = controller.FARM_SIMULATION.complete_tilling(controller.FARM_SIMULATION.new_cell(Vector2i(3, 0), detached_position))
		detached_cell["soil_recovery_started_minute"] = 0
		detached_remnants["3:0"] = detached_cell
		detached_state["soil_remnants"] = detached_remnants
		controller.call("_save_plot", detached_state)
		var detached_positions: Array[Vector3] = [detached_position]
		var reclaimed_remnant: Dictionary = controller.create_plot(detached_positions, Vector2i.ONE, "", "Player")
		var reclaimed_remnant_cell: Dictionary = ((reclaimed_remnant.get("cells", {}) as Dictionary).values()[0] as Dictionary) if not (reclaimed_remnant.get("cells", {}) as Dictionary).is_empty() else {}
		_expect(bool(reclaimed_remnant_cell.get("soil_created", false)), "replanning over detached cultivated soil preserves its physical state")
		_expect(not (controller.get_plot(manual_plot_id).get("soil_remnants", {}) as Dictionary).has("3:0"), "replanning transfers a detached soil remnant instead of duplicating it")
		var policy_plot: Dictionary = controller.set_plot_crop_policy(manual_plot_id, "tomato", owner)
		_expect(str(policy_plot.get("crop_policy_id", "")) == "tomato", "field management sets a durable crop policy")
		_expect(str(controller.get_cell_work(manual_plot_id, member_key).get("action", "")) == "till", "crop policy schedules labor without instantly changing recovered ground")
		var merge_left_positions: Array[Vector3] = [Vector3(30.0, 0.0, 30.0)]
		var merge_right_positions: Array[Vector3] = [Vector3(32.5, 0.0, 30.0)]
		var merge_left: Dictionary = controller.create_plot(merge_left_positions, Vector2i.ONE, "", "Player")
		var merge_right: Dictionary = controller.create_plot(merge_right_positions, Vector2i.ONE, "", "Player")
		var bridge_positions: Array[Vector3] = [Vector3(31.25, 0.0, 30.0)]
		var bridge_order: Dictionary = controller.call("prepare_manual_till", bridge_positions, owner, bridge_positions[0])
		var merged_plot_id := str(bridge_order.get("plot_id", ""))
		_expect((controller.get_plot(merged_plot_id).get("cells", {}) as Dictionary).size() == 3, "touching behavior-identical fields automatically become one field")
		_expect(controller.get_plot(str(merge_left.get("plot_id", ""))).is_empty() or controller.get_plot(str(merge_right.get("plot_id", ""))).is_empty(), "automatic merge removes the absorbed field identity")
		var distinct_left_positions: Array[Vector3] = [Vector3(40.0, 0.0, 40.0)]
		var distinct_right_positions: Array[Vector3] = [Vector3(42.5, 0.0, 40.0)]
		var distinct_left: Dictionary = controller.create_plot(distinct_left_positions, Vector2i.ONE, "", "Player")
		var distinct_right: Dictionary = controller.create_plot(distinct_right_positions, Vector2i.ONE, "", "Player")
		var distinct_right_state: Dictionary = controller.get_plot(str(distinct_right.get("plot_id", "")))
		distinct_right_state["priority"] = 1
		controller.call("_save_plot", distinct_right_state)
		var distinct_bridge: Array[Vector3] = [Vector3(41.25, 0.0, 40.0)]
		controller.call("prepare_manual_till", distinct_bridge, owner, distinct_bridge[0])
		_expect(not controller.get_plot(str(distinct_left.get("plot_id", ""))).is_empty() and not controller.get_plot(str(distinct_right.get("plot_id", ""))).is_empty(), "different behavioral settings prevent automatic merging")
		_expect(controller.has_method("merge_adjacent_plots"), "field management exposes explicit adjacent-field merge")
		if controller.has_method("merge_adjacent_plots"):
			_expect(not controller.has_mergeable_adjacent_plot(str(distinct_left.get("plot_id", "")), null), "Merge requires explicit acting-character authority")
			_expect(controller.has_mergeable_adjacent_plot(str(distinct_left.get("plot_id", "")), owner), "Merge is offered when the owned field actually has an adjacent merge target")
			_expect(not controller.has_mergeable_adjacent_plot(str(distinct_left.get("plot_id", "")), outsider), "Merge is hidden when the acting character cannot command the adjacent field")
			var manual_merge: Dictionary = controller.call("merge_adjacent_plots", str(distinct_left.get("plot_id", "")), str(distinct_right.get("plot_id", "")), owner)
			_expect(not manual_merge.is_empty() and int(manual_merge.get("priority", -1)) == 0 and controller.get_plot(str(distinct_right.get("plot_id", ""))).is_empty(), "manual merge makes the clicked field inherit the source field's settings")
			_expect(not controller.has_mergeable_adjacent_plot(str(distinct_left.get("plot_id", "")), owner), "Merge disappears after the only adjacent field is absorbed")
			var busy_left_positions: Array[Vector3] = [Vector3(50.0, 0.0, 50.0)]
			var busy_right_positions: Array[Vector3] = [Vector3(51.25, 0.0, 50.0)]
			var busy_left: Dictionary = controller.create_plot(busy_left_positions, Vector2i.ONE, "", "Player")
			var busy_right: Dictionary = controller.create_plot(busy_right_positions, Vector2i.ONE, "", "Player")
			var busy_left_state: Dictionary = controller.get_plot(str(busy_left.get("plot_id", "")))
			var busy_key := str((busy_left_state.get("cells", {}) as Dictionary).keys()[0])
			busy_left_state["cells"][busy_key]["work_progress"] = 0.5
			controller.call("_save_plot", busy_left_state)
			_expect(not controller.has_mergeable_adjacent_plot(str(busy_left.get("plot_id", "")), owner), "Merge is hidden while either adjacent field has active work")
			_expect(controller.merge_adjacent_plots(str(busy_left.get("plot_id", "")), str(busy_right.get("plot_id", "")), owner).is_empty(), "field restructuring refuses to invalidate live cell work")
	_expect(controller.can_actor_command_plot(owner, str(plot.plot_id)), "owning faction can command its field")
	_expect(not controller.can_actor_command_plot(outsider, str(plot.plot_id)), "other factions cannot command the field")
	_expect(controller.has_method("expand_plot") and controller.has_method("shrink_plot"), "controller exposes durable sparse field edit operations")
	if controller.has_method("expand_plot") and controller.has_method("shrink_plot"):
		var outsider_expansion: Dictionary = controller.call("expand_plot", str(plot.plot_id), [Vector3(-1.25, 0.0, 0.0)], outsider)
		_expect(outsider_expansion.is_empty(), "other factions cannot expand the field")
		var expanded: Dictionary = controller.call("expand_plot", str(plot.plot_id), [Vector3(-1.25, 0.0, 0.0)], owner)
		_expect((expanded.get("cells", {}) as Dictionary).has("-1:0"), "owner can add one adjacent sparse field cell without rekeying existing work")
		var disconnected: Dictionary = controller.call("expand_plot", str(plot.plot_id), [Vector3(-5.0, 0.0, 0.0)], owner)
		_expect(disconnected.is_empty(), "field expansion rejects disconnected cells")
		var outsider_shrink: Dictionary = controller.call("shrink_plot", str(plot.plot_id), PackedStringArray(["-1:0"]), outsider)
		_expect(outsider_shrink.is_empty(), "other factions cannot shrink the field")
		var shrunk: Dictionary = controller.call("shrink_plot", str(plot.plot_id), PackedStringArray(["-1:0"]), owner)
		_expect(not (shrunk.get("cells", {}) as Dictionary).has("-1:0") and (shrunk.get("cells", {}) as Dictionary).size() == 2, "owner can remove one field cell")
	var reloaded_state: Dictionary = controller.get_plot(str(plot.plot_id))
	var growing_cell: Dictionary = controller.FARM_SIMULATION.complete_planting(controller.FARM_SIMULATION.complete_tilling(controller.FARM_SIMULATION.new_cell(Vector2i(1, 0), positions[1])), "tomato", 24.0)
	(reloaded_state.cells as Dictionary)["1:0"] = growing_cell
	reloaded_state.last_simulated_minute = 0
	gecs.upsert_farm_plot_state(reloaded_state)
	time.absolute_minute = 5000
	controller._on_world_reindexed()
	_expect(int(controller.get_plot(str(plot.plot_id)).last_simulated_minute) == 0, "world reindex waits for the restored save clock instead of advancing against the pre-load session clock")
	time.absolute_minute = 60
	controller.call("_reconcile_after_world_reindex")
	var advanced_state: Dictionary = controller.get_plot(str(plot.plot_id))
	_expect(int(advanced_state.last_simulated_minute) == 60 and float(((advanced_state.cells as Dictionary)["1:0"] as Dictionary).growth) > 0.0, "load reindex advances crops from durable elapsed world time")
	gecs.upsert_farm_water_source_state({"source_id": "cistern", "renewable": false, "capacity": 20.0, "current_water": 5.0, "recharge_per_world_minute": 0.1, "last_processed_minute": 0})
	time.absolute_minute = 120
	controller._on_world_reindexed()
	controller.call("_reconcile_after_world_reindex")
	var advanced_water: Dictionary = gecs.get_farm_water_source_states().get("cistern", {})
	_expect(is_equal_approx(float(advanced_water.get("current_water", 0.0)), 17.0) and int(advanced_water.get("last_processed_minute", 0)) == 120, "off-screen finite water sources recharge from elapsed world time")
	_expect(controller.has_method("draw_water_source") and is_equal_approx(float(controller.call("draw_water_source", "cistern", 4.0)), 4.0), "controller owns finite water draws")
	owner.free()
	outsider.free()
	controller.free()
	gecs.free()
	time.free()
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FARM_CONTROLLER_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FARM_CONTROLLER_FAILED count=%d" % failures.size())
	quit(1)
