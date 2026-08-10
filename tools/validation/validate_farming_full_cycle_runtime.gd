extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_farming_full_cycle_runtime.gd

var _root: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_root = load("res://scenes/test_levels/farming_test.tscn").instantiate()
	get_root().add_child(_root)
	await create_timer(3.0).timeout
	var context := BootstrapContext.active
	var farm = context.get_optional(&"farming")
	var work = context.get_optional(&"farm_work")
	var time = context.get_optional(&"world_time")
	var worker := _root.get_node("PartyMembers/Ada")
	var job_system = context.get_optional(&"job_system")
	if job_system != null:
		for party_member in _root.get_node("PartyMembers").get_children():
			job_system.call("set_actor_jobs_enabled", party_member, false)
	var positions: Array[Vector3] = [Vector3(-3.0, 0.02, 1.0)]
	var plot: Dictionary = farm.create_plot(positions, Vector2i.ONE, "tomato", "Player", "farming_test")
	var plot_id := str(plot.get("plot_id", ""))
	if plot_id.is_empty():
		_fail("one-cell plot is created")
		return
	if not await _order_and_wait(farm, work, worker, plot_id, "till", "tilled", 12.0):
		return
	if not await _order_and_wait(farm, work, worker, plot_id, "plant", "growing", 12.0, "tomato"):
		return
	var hoe = load("res://features/inventory/resources/items/hoe.tres")
	if _inventory_count(worker.inventory, hoe) != 1:
		_fail("putting away the hoe returns the real tool to inventory")
		return
	var watering_can = load("res://features/inventory/resources/items/watering_can.tres")
	var watering_entry = _inventory_entry(worker.inventory, watering_can)
	if watering_entry == null:
		_fail("worker still carries the watering can before watering")
		return
	watering_entry.metadata["farm_water"] = 7.0
	worker.inventory.changed.emit()
	if not str(work.call("_ensure_tool", worker, "tool.water_container", "watering can")).is_empty() \
			or not is_equal_approx(float(work.call("_container_water", worker)), 7.0):
		_fail("equipping a partially filled watering can preserves its stored water")
		return
	work.call("_stow_weapon", worker)
	watering_entry = _inventory_entry(worker.inventory, watering_can)
	if watering_entry == null or not is_equal_approx(float(watering_entry.metadata.get("farm_water", 0.0)), 7.0):
		_fail("stowing a partially filled watering can preserves its stored water")
		return
	var dry_cell := _cell(farm, plot_id)
	var before_water := float(dry_cell.get("water", 0.0))
	farm.request_cell_operation(plot_id, "0:0", "water")
	var water_result := str(work.assign_cell(plot_id, "0:0", [worker]))
	if water_result.begins_with("Cannot"):
		_fail("worker accepted water order: %s" % water_result)
		return
	var watered := await _wait_for_water(farm, plot_id, before_water, 18.0)
	if not watered:
		_fail("worker watered the cell from a finite carried container: result=%s before=%.2f after=%.2f active=%s position=%s can_count=%d capacity=%.2f carried=%.2f" % [
			water_result,
			before_water,
			float(_cell(farm, plot_id).get("water", 0.0)),
			str(work.has_active_work_for_actor(worker)),
			str(worker.global_position),
			_inventory_count(worker.inventory, watering_can),
			float(work.call("_container_capacity", worker)),
			float(work.call("_container_water", worker)),
		])
		return
	var crop = farm.get_crop("tomato")
	crop.growth_minutes = 60.0
	time.advance_minutes(120.0)
	await create_timer(0.5).timeout
	if str(_cell(farm, plot_id).get("state", "")) != "ripe":
		_fail("watered crop reached ripe state after world-time advance")
		return
	if not await _order_and_wait(farm, work, worker, plot_id, "harvest", "tilled", 12.0):
		return
	if not await _run_wheat_harvest(context, farm, work, time):
		return
	var processor := _root.get_node("FarmSeedProcessor")
	var tomato_seed = load("res://features/inventory/resources/items/tomato_seeds.tres")
	var seeds_before := _inventory_count(processor.inventory, tomato_seed)
	var processing_result := str(work.assign_seed_processing(processor, "tomato", [worker]))
	if processing_result.begins_with("No ") or processing_result.begins_with("Cannot"):
		_fail("worker accepted seed-processing order: %s" % processing_result)
		return
	for _step in 150:
		await create_timer(0.1).timeout
		if _inventory_count(processor.inventory, tomato_seed) > seeds_before:
			print("FARMING_FULL_CYCLE_RUNTIME_OK")
			_root.free()
			quit(0)
			return
	_fail("worker physically processed produce into seeds")


func _inventory_count(inventory, definition) -> int:
	var total := 0
	if inventory == null:
		return total
	for entry in inventory.entries:
		if entry != null and entry.definition == definition:
			total += int(entry.count)
	return total


func _inventory_entry(inventory, definition):
	if inventory == null:
		return null
	for entry in inventory.entries:
		if entry != null and entry.definition == definition:
			return entry
	return null


func _run_wheat_harvest(context: BootstrapContext, farm: Node, work: Node, time: Node) -> bool:
	var worker := _root.get_node("PartyMembers/Bram")
	var wheat_seed = load("res://features/inventory/resources/items/wheat_seeds.tres")
	var wheat_item = load("res://features/inventory/resources/items/wheat.tres")
	worker.inventory.add_item_count(wheat_seed, 1)
	var position := Vector3(-6.0, 0.02, 6.0)
	var positions: Array[Vector3] = [position]
	var plot: Dictionary = farm.create_plot(positions, Vector2i.ONE, "wheat", "Player", "farming_test")
	var plot_id := str(plot.get("plot_id", ""))
	if plot_id.is_empty():
		_fail("wheat field is created")
		return false
	if not await _order_and_wait(farm, work, worker, plot_id, "till", "tilled", 12.0):
		return false
	if not await _order_and_wait(farm, work, worker, plot_id, "plant", "growing", 12.0, "wheat"):
		return false
	var before_water := float(_cell(farm, plot_id).get("water", 0.0))
	farm.request_cell_operation(plot_id, "0:0", "water")
	var water_result := str(work.assign_cell(plot_id, "0:0", [worker]))
	if water_result.begins_with("Cannot") or not await _wait_for_water(farm, plot_id, before_water, 18.0):
		_fail("wheat worker waters the crop")
		return false
	var crop = farm.get_crop("wheat")
	crop.growth_minutes = 60.0
	time.advance_minutes(120.0)
	await create_timer(0.5).timeout
	if str(_cell(farm, plot_id).get("state", "")) != "ripe":
		_fail("wheat reaches ready for harvest")
		return false
	var projection = null
	for candidate in get_nodes_in_group("farm_plot"):
		if str(candidate.get("plot_id")) == plot_id:
			projection = candidate
			break
	var world_interaction = context.get_optional(&"world_interaction")
	var party_manager = _root.get_node("PartyManager")
	if projection == null or world_interaction == null:
		_fail("wheat right-click interaction target exists")
		return false
	var scythe = load("res://features/inventory/resources/items/scythe.tres")
	var equipment = worker.get_equipment()
	var replaced_weapon = equipment.get_equipped_item("weapon") if equipment != null else null
	if replaced_weapon == null or replaced_weapon == scythe:
		_fail("wheat worker reaches harvest with a different farming tool equipped")
		return false
	var scythes_before := _inventory_count(worker.inventory, scythe)
	var replaced_before := _inventory_count(worker.inventory, replaced_weapon)
	party_manager.select_only(worker)
	var actions: Array = projection.call("get_world_context_actions_at", worker, position)
	var harvest_key := ""
	for action_value in actions:
		var action: Dictionary = action_value
		if str(action.get("label", "")) == "Harvest":
			harvest_key = str(action.get("key", ""))
			break
	if harvest_key.is_empty():
		_fail("wheat right-click exposes Harvest to the worker carrying a scythe")
		return false
	var before_count := _inventory_count(worker.inventory, wheat_item)
	world_interaction.call("_dispatch_world_context_action", projection, harvest_key)
	for _step in 120:
		await create_timer(0.1).timeout
		if str(_cell(farm, plot_id).get("state", "")) == "tilled" and _inventory_count(worker.inventory, wheat_item) > before_count:
			if equipment.get_equipped_item("weapon") != scythe \
					or _inventory_count(worker.inventory, scythe) != scythes_before - 1 \
					or _inventory_count(worker.inventory, replaced_weapon) != replaced_before + 1:
				_fail("wheat auto-equipping moves the scythe out of inventory and safely stores the replaced weapon")
				return false
			return true
	_fail("right-click Harvest physically completes wheat and adds it to inventory")
	return false


func _order_and_wait(farm: Node, work: Node, worker: Node, plot_id: String, action: String, expected_state: String, seconds: float, crop_id := "") -> bool:
	farm.request_cell_operation(plot_id, "0:0", action, crop_id)
	var result := str(work.assign_cell(plot_id, "0:0", [worker]))
	if result.begins_with("Cannot"):
		_fail("worker accepted %s order: %s" % [action, result])
		return false
	for _step in int(seconds * 10.0):
		await create_timer(0.1).timeout
		if str(_cell(farm, plot_id).get("state", "")) == expected_state:
			return true
	_fail("%s completed physically" % action)
	return false


func _wait_for_water(farm: Node, plot_id: String, before: float, seconds: float) -> bool:
	for _step in int(seconds * 10.0):
		await create_timer(0.1).timeout
		if float(_cell(farm, plot_id).get("water", 0.0)) > before + 1.0:
			return true
	return false


func _cell(farm: Node, plot_id: String) -> Dictionary:
	return ((farm.get_plot(plot_id).get("cells", {}) as Dictionary).get("0:0", {}) as Dictionary)


func _fail(message: String) -> void:
	push_error(message)
	print("FARMING_FULL_CYCLE_RUNTIME_FAILED")
	if _root != null and is_instance_valid(_root):
		_root.free()
	quit(1)
