extends SceneTree
## Reverse transfers use the same physical actor interaction as refilling.
var failures: Array[String] = []
var ecs: Node
func _initialize() -> void:
	if not Engine.has_singleton("ECS"):
		ecs = Node.new()
		Engine.register_singleton("ECS", ecs)
	call_deferred("_run")
func _run() -> void:
	var fixtures = load("res://tests/validation/validate_direct_water_refill.gd")
	var holder := Node3D.new()
	root.add_child(holder)
	var context := BootstrapContext.new(holder, null)
	BootstrapContext.active = context
	var gecs = fixtures.Gecs.new()
	var farm = load("res://features/farming/sim/farm_controller.gd").new()
	var storage = load("res://features/inventory/sim/liquid_storage_controller.gd").new()
	var theft = fixtures.Theft.new()
	for service in [gecs, farm, storage, theft]: holder.add_child(service)
	context.register(&"gecs_world", gecs)
	context.register(&"farming", farm)
	context.register(&"liquid_storage", storage)
	context.register(&"ownership", theft)
	farm._gecs = gecs
	storage.initialize(context)
	var actor = fixtures.Actor.new()
	holder.add_child(actor)
	actor.inventory.use_weight = false
	actor.inventory.add_item(load("res://features/inventory/resources/items/watering_can.tres"))
	var tank = load("res://features/world/projection/containers/liquid_container.gd").new()
	tank.owner_faction_name = "Player"
	tank.assigned_liquid_id = "water"
	tank.capacity_liters = 100.0
	tank.current_liters = 95.0
	holder.add_child(tank)
	tank._bind_state()
	var well = load("res://features/farming/projection/farm_water_source.gd").new()
	well.display_name = "Well"
	well.source_kind = "well"
	well.renewable = false
	well.capacity = 100.0
	well.current_water = 95.0
	holder.add_child(well)
	well._bind_durable_state()
	var carrier = load("res://features/inventory/bridge/liquid_haul_carrier.gd")
	for target in [tank, well]:
		actor.inventory.set_entry_metadata(actor.inventory.entries[0], carrier.metadata_with_water({}, 16.0))
		var actions: Array = target.get_world_context_actions(actor)
		var key := _pour_key(actions)
		_expect(not key.is_empty(), "filled vessel offers pouring into " + target.display_name)
		if key.is_empty(): continue
		actor.position = Vector3(30, 0, 0)
		target.perform_world_context_action(key, [actor])
		_expect(carrier.amount(actor, "water") == 16.0 and target.free_capacity() == 5.0, "pouring cannot transfer remotely")
		actor.position = actor.move_target
		actor.interaction.process_container_interaction()
		_expect(carrier.amount(actor, "water") == 16.0 and actor.work_active, "pour begins work without transferring")
		actor.target._process(2.9)
		_expect(carrier.amount(actor, "water") == 16.0 and actor.work_progress > 0.9, "pour waits three seconds")
		actor.target._process(0.1)
		_expect(carrier.amount(actor, "water") == 11.0 and target.free_capacity() == 0.0, "arrival transfers only available capacity and keeps excess carried")
		_expect(_pour_key(target.get_world_context_actions(actor)).is_empty(), "full destination hides pour action")
	# Empty destinations are valid even though there is nothing to withdraw.
	var state: Dictionary = storage.get_container_state(tank.liquid_container_id)
	state.current_liters = 0.0
	storage._save_state(state)
	actor.equipment = fixtures.Equipment.new()
	gecs.stacks[actor.equipment.stack_id] = {"stack_id": actor.equipment.stack_id, "metadata": carrier.metadata_with_water({"marker": "keep"}, 4.0)}
	var key := _pour_key(tank.get_world_context_actions(actor))
	_expect(not key.is_empty(), "empty water tank accepts equipped and carried water")
	if not key.is_empty():
		tank.perform_world_context_action(key, [actor])
		actor.position = actor.move_target
		actor.interaction.process_container_interaction()
		actor.finish_water_work()
		_expect(tank.current_liters == 15.0 and carrier.amount(actor, "water") == 0.0 and gecs.stacks[actor.equipment.stack_id].metadata.farm_water == 0.0, "pour drains both exact vessels into the durable tank")
		_expect(gecs.stacks[actor.equipment.stack_id].metadata.marker == "keep", "pour preserves unrelated equipment metadata")
		gecs.stacks[actor.equipment.stack_id].metadata.farm_water = 4.0
		gecs.reject_stack_write = true
		tank.perform_world_context_action(key, [actor])
		actor.position = actor.move_target
		actor.interaction.process_container_interaction()
		actor.finish_water_work()
		_expect(tank.current_liters == 15.0 and storage.get_container_state(tank.liquid_container_id).current_liters == 15.0, "failed carried debit rolls back tank credit before publication")
		gecs.reject_stack_write = false
		var cancelled_stack: Dictionary = gecs.stacks[actor.equipment.stack_id].duplicate(true)
		var cancelled_carried: Dictionary = actor.inventory.entries[0].metadata.duplicate(true)
		_expect(float(cancelled_stack.metadata.farm_water) > 0.0 and tank.free_capacity() > 0.0, "cancelled pour starts with funded vessel and destination capacity")
		tank.perform_world_context_action(key, [actor])
		var old_target: Node = actor.target
		actor.interaction.stop_container_interaction()
		actor.container_reached.emit(actor, old_target)
		old_target._process(load("res://features/inventory/bridge/direct_water_refill.gd").WORK_SECONDS)
		_expect(tank.current_liters == 15.0 and gecs.stacks[actor.equipment.stack_id] == cancelled_stack \
			and actor.inventory.entries[0].metadata == cancelled_carried and not actor.work_active, "cancelled pour cannot transfer after late arrival and full work interval")
	# Ownership changes legality, not whether the physical action is offered.
	state = storage.get_container_state(tank.liquid_container_id)
	state.owner_faction_name = "Foreign"
	storage._save_state(state)
	_expect(_pour_is_red(tank.get_world_context_actions(actor)), "private foreign tank offers red pouring")
	tank.perform_world_context_action("pour_water", [actor])
	actor.position = actor.move_target
	actor.interaction.process_container_interaction()
	actor.finish_water_work()
	_expect(theft.interactions == 1 and tank.current_liters == 15.0, "witness intervention prevents transfer through the ownership boundary")
	theft.allowed = true
	tank.perform_world_context_action("pour_water", [actor])
	actor.position = actor.move_target
	actor.interaction.process_container_interaction()
	actor.finish_water_work()
	_expect(theft.interactions == 2 and tank.current_liters == 19.0 and gecs.stacks[actor.equipment.stack_id].metadata.farm_water == 0.0, "uninterrupted illegal pour transfers exact liters into foreign tank")
	gecs.stacks[actor.equipment.stack_id].metadata = carrier.metadata_with_water({}, 4.0)
	theft.on_interaction = func(): tank.cancel_refill_interactions()
	tank.perform_world_context_action("pour_water", [actor])
	actor.position = actor.move_target
	actor.interaction.process_container_interaction()
	actor.finish_water_work()
	_expect(tank.current_liters == 19.0 and gecs.stacks[actor.equipment.stack_id].metadata.farm_water == 4.0, "property reaction cancelling the order cannot commit a stale pour")
	theft.on_interaction = Callable()
	state = storage.get_container_state(tank.liquid_container_id)
	state.public_water_access = true
	storage._save_state(state)
	_expect(not _pour_key(tank.get_world_context_actions(actor)).is_empty(), "public tank allows pouring without theft")
	_expect(not _pour_is_red(tank.get_world_context_actions(actor)), "public tank pouring is not red")
	var calls_before: int = theft.interactions
	tank.perform_world_context_action("pour_water", [actor])
	actor.position = actor.move_target
	actor.interaction.process_container_interaction()
	actor.finish_water_work()
	_expect(tank.current_liters == 23.0 and gecs.stacks[actor.equipment.stack_id].metadata.farm_water == 0.0 and theft.interactions == calls_before, "public foreign tank accepts exact water without an illegal-use check")
	# The rejection must have water to lose, and begin the real timed path
	# while the tank is compatible. Recheck compatibility at commit, not only
	# when building its menu.
	gecs.stacks[actor.equipment.stack_id].metadata = carrier.metadata_with_water({"marker": "reject-keeps-water"}, 4.0)
	_expect(_pour_key(tank.get_world_context_actions(actor)) == "pour_water", "nonempty vessel can pour before destination changes liquid")
	tank.perform_world_context_action("pour_water", [actor])
	actor.position = actor.move_target
	actor.interaction.process_container_interaction()
	_expect(actor.work_active, "compatibility rejection starts from active timed pouring")
	actor.target._process(2.9)
	state = storage.get_container_state(tank.liquid_container_id)
	state.assigned_liquid_id = "beer"
	storage._save_state(state)
	actor.finish_water_work()
	_expect(_pour_key(tank.get_world_context_actions(actor)).is_empty(), "water cannot be poured into a beer tank")
	var rejected_state: Dictionary = storage.get_container_state(tank.liquid_container_id)
	_expect(rejected_state.assigned_liquid_id == "beer" and rejected_state.current_liters == 23.0 and tank.current_liters == 23.0, "timed incompatible pour preserves destination liquid and exact durable amount")
	_expect(gecs.stacks[actor.equipment.stack_id].metadata.farm_water == 4.0 and gecs.stacks[actor.equipment.stack_id].metadata.marker == "reject-keeps-water" and not actor.work_active, "rejected timed pour preserves nonempty exact vessel and releases work")
	_expect(theft.attempts == 0, "depositing never invokes a taking/theft action")
	# Well rollback must be just as atomic as the tank's staged deposit.
	well.draw_water_for_actor(5.0, actor)
	var well_state: Dictionary = farm.get_water_source(well.source_id)
	well_state.owner_faction_name = "Foreign"
	gecs.upsert_farm_water_source_state(well_state)
	well._apply_durable_state(well_state)
	gecs.stacks[actor.equipment.stack_id].metadata = carrier.metadata_with_water({}, 4.0)
	_expect(_pour_is_red(well.get_world_context_actions(actor)), "private foreign well offers red pouring")
	well.perform_world_context_action("pour_water", [actor])
	actor.position = actor.move_target
	actor.interaction.process_container_interaction()
	actor.finish_water_work()
	_expect(theft.interactions == calls_before + 1 and well.current_water == 99.0 and gecs.stacks[actor.equipment.stack_id].metadata.farm_water == 0.0, "uninterrupted illegal pour reaches foreign well without taking/theft XP")
	well_state.current_water = 95.0
	well_state.owner_faction_name = "Player"
	gecs.upsert_farm_water_source_state(well_state)
	well._apply_durable_state(well_state)
	gecs.stacks[actor.equipment.stack_id].metadata = carrier.metadata_with_water({}, 4.0)
	gecs.reject_stack_write = true
	well.perform_world_context_action("pour_water", [actor])
	actor.position = actor.move_target
	actor.interaction.process_container_interaction()
	actor.finish_water_work()
	_expect(well.current_water == 95.0 and farm.get_water_source(well.source_id).current_water == 95.0, "failed carried debit rolls back well credit before publication")
	gecs.reject_stack_write = false
	# Incoming reservations cap direct pours too, including fractional liters.
	state = storage.get_container_state(tank.liquid_container_id)
	state.assigned_liquid_id = "water"
	state.owner_faction_name = "Player"
	state.current_liters = 95.0
	storage._save_state(state)
	tank.reserve_incoming_water_for_actor(3.75, actor)
	tank.perform_world_context_action("pour_water", [actor])
	actor.position = actor.move_target
	actor.interaction.process_container_interaction()
	actor.finish_water_work()
	_expect(is_equal_approx(tank.current_liters, 96.25) and is_equal_approx(float(gecs.stacks[actor.equipment.stack_id].metadata.farm_water), 2.75), "pour respects reserved incoming capacity and fractional vessel remainder")
	tank.release_incoming_water_reservation(3.75, actor)
	well.perform_world_context_action("pour_water", [actor])
	var retained_refill = well._refill
	var retained_id: String = well.source_id
	well.free()
	actor.interaction.process_container_interaction()
	_expect(retained_refill.pending.is_empty() and actor.interaction.current_container_target == null and farm.get_water_source(retained_id).current_water == 95.0, "destination LOD cancels pour without losing carried water or durable stock")
	holder.free()
	BootstrapContext.active = null
	if ecs != null:
		Engine.unregister_singleton("ECS")
		ecs.free()
	for failure in failures: push_error(failure)
	print("WATER_POURING_OK" if failures.is_empty() else "WATER_POURING_FAILED")
	quit(0 if failures.is_empty() else 1)
func _pour_key(actions: Array) -> String:
	for action in actions:
		if str(action.get("key", "")) == "pour_water": return "pour_water"
	return ""
func _pour_is_red(actions: Array) -> bool:
	for action in actions:
		if action.get("key", "") == "pour_water": return action.get("color", Color.TRANSPARENT) == Color(1.0, 0.3, 0.3)
	return false
func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
