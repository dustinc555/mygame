extends SceneTree
## Real actor navigation and selected HUD through reusable well/tank scenes.
var _scene: Node
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	_scene = load("res://scenes/test_levels/farming_test.tscn").instantiate()
	var facility = load("res://features/settlements/bridge/settlement_tank.tscn").instantiate()
	facility.facility_id = "validation.pour_tank"
	facility.building_id = "validation.pour_tank"
	facility.owner_faction_id = "Foreign"
	facility.position = Vector3(6, 0, 3)
	facility.object_property_overrides = {"assigned_liquid_id": "water", "capacity_liters": 100.0, "current_liters": 0.0}
	_scene.add_child(facility)
	var well = load("res://features/world/projection/props/water/well_1.tscn").instantiate()
	well.source_id = "validation.pour_well"
	well.owner_faction_name = "Player"
	well.renewable = false
	well.capacity = 80.0
	well.current_water = 80.0
	well.recharge_per_world_hour = 0.0
	well.position = Vector3(-7, 0, 7)
	_scene.add_child(well)
	root.add_child(_scene)
	await create_timer(3.0).timeout
	var context := BootstrapContext.active
	var actor: Node = _scene.get_node("PartyMembers/Ada")
	var jobs = context.get_optional(&"job_system")
	for member in _scene.get_node("PartyMembers").get_children():
		jobs.set_actor_jobs_enabled(member, false)
	var tank: Node = facility.get_single_object()
	var details = context.get_optional(&"humanoid_details")
	details.inspect_target_at(tank, tank.global_position)
	details._update_panel()
	if details.name_label.text != "Water Tank" or not details.farm_hydration_row.visible or details.farm_hydration_label.text != "Water":
		_fail("authored water tank selection must display Water Tank and visible Water gauge")
		return
	if not await _perform(well, actor, "refill_water_containers", 64.0): return
	if tank.can_take_water_legally(actor):
		_fail("runtime fixture must exercise private foreign tank pouring")
		return
	if not await _perform(tank, actor, "pour_water", 16.0): return
	details._update_panel()
	if details.farm_hydration_value.text != "16.0 / 100.0 L":
		_fail("selected tank gauge must update after physical deposit: " + details.farm_hydration_value.text)
		return
	var storage = context.get_optional(&"liquid_storage")
	var tank_state: Dictionary = storage.get_container_state(tank.liquid_container_id)
	tank_state.public_water_access = true
	storage._save_state(tank_state)
	if not await _perform(tank, actor, "refill_water_containers", 0.0): return
	var farm = context.get_optional(&"farming")
	var well_state: Dictionary = farm.get_water_source(well.source_id)
	well_state.owner_faction_name = "Foreign"
	context.get_optional(&"gecs_world").upsert_farm_water_source_state(well_state)
	well._apply_durable_state(well_state)
	if not await _perform(well, actor, "pour_water", 80.0): return
	if not is_zero_approx(_durable_carrier_liters(actor)) or not is_equal_approx(float(farm.get_water_source(well.source_id).current_water), 80.0) or not is_zero_approx(float(storage.get_container_state(tank.liquid_container_id).current_liters)):
		_fail("final durable balances must be well 80 L, tank 0 L, carried/equipped 0 L")
		return
	print("WATER_INTERACTIONS_RUNTIME_OK real actor poured into foreign tank and well through production ownership; HUD 0 -> 16 L; conserved 80 L")
	_scene.free()
	quit(0)
func _perform(target: Node, actor: Node, key: String, expected: float) -> bool:
	var has_action := false
	for action in target.get_world_context_actions(actor):
		if action.get("key", "") == key:
			has_action = true
			if key == "pour_water" and not target.can_take_water_legally(actor) and not action.has("color"):
				_fail("private foreign pour must be red")
				return false
	if not has_action:
		_fail("missing " + key + " at " + str(target.name))
		return false
	var before := _amount(target)
	var carrier_before := _durable_carrier_liters(actor)
	var response: String = target.perform_world_context_action(key, [actor])
	if not response.is_empty():
		_fail(response)
		return false
	if not is_equal_approx(_amount(target), before):
		_fail("transfer happened before physical arrival")
		return false
	var deadline := Time.get_ticks_msec() + 25000
	var work_started := -1
	var saw_clip := false
	var saw_bar := false
	while Time.get_ticks_msec() < deadline:
		await create_timer(0.1).timeout
		if actor.is_actively_farming():
			if work_started < 0: work_started = Time.get_ticks_msec()
			saw_clip = saw_clip or actor._body.get_current_clip() == "Farm_Watering"
			var ui = BootstrapContext.service(&"world_interaction")
			if ui != null:
				ui._update_progress_bars()
				var bar = ui.work_progress_bars.get(actor)
				saw_bar = saw_bar or (bar != null and bar.visible and bar.value > 0.0)
			if not is_equal_approx(_amount(target), before):
				_fail("water transferred before work finished")
				return false
		if is_equal_approx(_amount(target), expected):
			if work_started < 0 or Time.get_ticks_msec() - work_started < 2800 or not saw_clip or not saw_bar or actor.is_actively_farming():
				_fail("timed work/animation/bar not proven: start=%d clip=%s bar=%s" % [work_started, saw_clip, saw_bar])
				return false
			var durable_target := float(BootstrapContext.service(&"liquid_storage").get_container_state(target.liquid_container_id).current_liters) if target is LiquidContainer else float(BootstrapContext.service(&"farming").get_water_source(target.source_id).current_water)
			if not is_equal_approx(durable_target, expected) or not is_equal_approx(before + carrier_before, durable_target + _durable_carrier_liters(actor)):
				_fail("transfer must conserve exact durable target and all carried/equipped water")
				return false
			return true
	_fail("physical " + key + " stalled at " + str(actor.global_position) + " toward " + str(target.get_interaction_position(actor)))
	return false
func _amount(target: Node) -> float:
	return float(target.current_liters) if target is LiquidContainer else float(target.current_water)
func _durable_carrier_liters(actor: Node) -> float:
	var gecs = BootstrapContext.service(&"gecs_world")
	var carrier = load("res://features/inventory/bridge/liquid_haul_carrier.gd")
	var ids := {}
	var inventory = actor.get_inventory().inventory
	for entry in inventory.entries: ids[str(entry.stack_id)] = true
	var equipment = actor.get_equipment()
	var equipped_id := str(equipment.get_equipped_stack_id("weapon"))
	if not equipped_id.is_empty(): ids[equipped_id] = true
	var total := 0.0
	for id in ids:
		var stack: Dictionary = gecs.get_item_stack(id)
		total += carrier.water_from_metadata(stack.get("metadata", {}))
	return total
func _fail(message: String) -> void:
	push_error("WATER_INTERACTIONS_RUNTIME_FAILED: " + message)
	_scene.free()
	quit(1)
