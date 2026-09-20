extends SceneTree
## Focused production menu -> actor approach -> exact-stack refill regression.
var failures: Array[String] = []
var ecs: Node

class Gecs:
	extends Node
	signal world_reindexed
	var states: Dictionary = {}
	var stacks: Dictionary = {}
	var reject_stack_write := false
	var liquids: Dictionary = {}
	func get_liquid_container_states(): return liquids.duplicate(true)
	func upsert_liquid_container_state(state: Dictionary):
		liquids[state.liquid_container_id] = state.duplicate(true)
		return state.duplicate(true)
	func get_farm_water_source_states(): return states.duplicate(true)
	func get_farm_water_source_state(id: String): return states.get(id, {}).duplicate(true)
	func upsert_farm_water_source_state(state: Dictionary):
		states[state.source_id] = state.duplicate(true)
		return state.duplicate(true)
	func get_item_stack(id: String): return stacks.get(id, {}).duplicate(true)
	func upsert_item_stack_record(state: Dictionary):
		if reject_stack_write: return {}
		stacks[state.stack_id] = state.duplicate(true)
		return state.duplicate(true)

class Theft:
	extends Node
	var attempts := 0
	var interactions := 0
	var allowed := false
	var on_interaction := Callable()
	func request_interaction(_actor, _source, _label):
		interactions += 1
		if on_interaction.is_valid(): on_interaction.call()
		return allowed
	func request_take_item(_actor, _source):
		attempts += 1
		return allowed

class HaulObserver:
	extends Node
	var inventory: RefCounted
	var unbalanced := false
	func notify_endpoint_changed(endpoint):
		if endpoint.get("current_liters") == 24.0 and inventory != null:
			unbalanced = float(inventory.entries[0].metadata.get("farm_water", 0.0)) != 16.0

class Actor:
	extends Node3D
	signal container_reached(actor: Node, target: Node)
	var faction_name := "Player"
	var inventory := InventoryData.new()
	var equipment: RefCounted
	func get_equipment(): return equipment
	var target: Node
	var interaction = load("res://features/actors/bridge/capabilities/interaction_capability.gd").new()
	var _has_move_target := false
	var move_target := Vector3.ZERO
	var work_active := false
	var work_progress := 0.0
	func get_interaction(): return interaction
	func set_farming_work_visual(active, _action, _point, progress):
		work_active = active
		work_progress = progress
	func finish_water_work():
		if is_instance_valid(target) and target.has_method("_process"): target._process(3.0)
	func get_inventory(): return inventory
	func _set_actor_move_target(point: Vector3):
		move_target = point
		_has_move_target = true
	func _clear_actor_move_target(): _has_move_target = false
	func assign_open_container(value: Node, _player := true):
		interaction.actor = self
		interaction.assign_open_container(value)
		target = value

class Equipment:
	extends RefCounted
	var definition = load("res://features/inventory/resources/items/watering_can.tres")
	var stack_id := "equipped.exact.can"
	func get_equipped_item(_slot): return definition
	func get_equipped_stack_id(_slot): return stack_id

func _initialize():
	if not Engine.has_singleton("ECS"):
		ecs = Node.new()
		Engine.register_singleton("ECS", ecs)
	call_deferred("_run")

func _run():
	var holder := Node3D.new()
	root.add_child(holder)
	var context := BootstrapContext.new(holder, null)
	BootstrapContext.active = context
	var gecs := Gecs.new()
	var theft := Theft.new()
	var farm = load("res://features/farming/sim/farm_controller.gd").new()
	for service in [gecs, theft, farm]: holder.add_child(service)
	context.register(&"gecs_world", gecs)
	context.register(&"farming", farm)
	context.register(&"ownership", theft)
	farm._gecs = gecs
	var actor := Actor.new()
	holder.add_child(actor)
	actor.inventory.add_item(load("res://features/inventory/resources/items/watering_can.tres"))
	var source = load("res://features/farming/projection/farm_water_source.gd").new()
	source.renewable = false
	holder.add_child(source)
	source._bind_durable_state()
	_check(source.has_method("get_world_context_actions"), "well exposes production refill context actions")
	if source.has_method("get_world_context_actions"):
		var actions: Array = source.get_world_context_actions(actor)
		_check(actions.size() == 1 and actions[0].label == "Refill Water Containers", "carried vessels offer batch refill, not equipped-can action")
		actor.position = Vector3(20, 0, 0)
		source.perform_world_context_action(actions[0].key, [actor])
		_check(actor.move_target == source.get_interaction_position(actor), "action assigns physical container approach")
		_check(float(actor.inventory.entries[0].metadata.get("farm_water", 0)) == 0, "dispatch cannot remotely fill")
		actor.position = Vector3(-2.0, 0, 0)
		actor.interaction.process_container_interaction()
		_check(actor.interaction.current_container_target != null, "production actuator must reach approach slot before completion")
		actor.position = actor.move_target
		actor.interaction.process_container_interaction()
		_check(float(actor.inventory.entries[0].metadata.get("farm_water", 0)) == 0 and actor.work_active, "arrival starts timed watering visual without transferring")
		if actor.target.has_method("_process"): actor.target._process(2.9)
		_check(float(actor.inventory.entries[0].metadata.get("farm_water", 0)) == 0 and actor.work_progress > 0.9, "water remains uncommitted before three seconds")
		if actor.target.has_method("_process"): actor.target._process(0.1)
		_check(not actor.work_active, "work visual clears at completion")
		_check(float(actor.inventory.entries[0].metadata.get("farm_water", 0)) == 16.0 and source.current_water == 184.0, "arrival fills exact real vessel and conserves liters")
		actor.inventory.set_entry_metadata(actor.inventory.entries[0], {})
		source.owner_faction_name = "Foreign"
		source.perform_world_context_action("refill_water_containers", [actor])
		actor.position = actor.move_target
		actor.interaction.process_container_interaction()
		actor.target._process(1.0)
		actor.interaction.stop_container_interaction()
		actor.finish_water_work()
		_check(not actor.work_active and source.current_water == 184.0 and actor.inventory.entries[0].metadata.get("farm_water", 0.0) == 0.0, "mid-work interruption clears bar and transfers no water")
		source._bind_durable_state()
		_check(source.get_world_context_actions(actor)[0].has("color"), "private foreign action is red")
		source.perform_world_context_action("refill_water_containers", [actor])
		actor.position = source.get_interaction_position(actor)
		actor.container_reached.emit(actor, actor.target)
		actor.finish_water_work()
		_check(theft.attempts == 1 and source.current_water == 184.0, "denied theft draws zero")
		var state: Dictionary = farm.get_water_source(source.source_id)
		state.public_water_access = true
		gecs.upsert_farm_water_source_state(state)
		source._apply_durable_state(state)
		_check(not source.get_world_context_actions(actor)[0].has("color"), "explicit public foreign action is legal")
		actor.inventory.max_weight = actor.inventory.get_total_weight() + 2.25
		source.perform_world_context_action("refill_water_containers", [actor])
		actor.position = source.get_interaction_position(actor)
		actor.container_reached.emit(actor, actor.target)
		actor.finish_water_work()
		_check(theft.attempts == 1 and is_equal_approx(source.current_water, 181.75), "public refill respects exact fractional weight budget without theft")
		var liquid = load("res://features/world/projection/containers/liquid_container.gd").new()
		_check(liquid.has_method("get_world_context_actions"), "generic tank exposes same production refill route")
		var storage = load("res://features/inventory/sim/liquid_storage_controller.gd").new()
		holder.add_child(storage)
		storage.initialize(context)
		context.register(&"liquid_storage", storage)
		liquid.owner_faction_name = "Foreign"
		liquid.public_water_access = true
		liquid.assigned_liquid_id = "water"
		liquid.current_liters = 40.0
		holder.add_child(liquid)
		liquid._bind_state()
		actor.inventory.max_weight = 100.0
		actor.inventory.set_entry_metadata(actor.inventory.entries[0], {})
		var observer := HaulObserver.new()
		holder.add_child(observer)
		observer.inventory = actor.inventory
		context.register(&"haul", observer)
		liquid.perform_world_context_action("refill_water_containers", [actor])
		actor.position = actor.move_target
		actor.interaction.process_container_interaction()
		actor.finish_water_work()
		_check(liquid.current_liters == 24.0 and theft.attempts == 1, "public tank production route fills exact liters without theft")
		_check(not observer.unbalanced, "endpoint observers never see source debit before carrier credit")
		actor.inventory.set_entry_metadata(actor.inventory.entries[0], {"farm_water": 3.0, "carried_liquids": {"water": 16.0}})
		var carrier = load("res://features/inventory/bridge/liquid_haul_carrier.gd")
		_check(carrier.amount(actor, "water") == 3.0, "haul reads authoritative water after farming consumption, not stale mirror")
		_check(carrier.free_capacity(actor, "water") == 13.0, "stale mirror cannot consume vessel capacity twice")
		actor.inventory.set_entry_metadata(actor.inventory.entries[0], {"carried_liquids": {"water": 3.0}})
		_check(is_equal_approx(actor.inventory.get_total_weight(), actor.inventory.entries[0].definition.unit_weight + 3.0), "generic-only water metadata contributes carried mass")
		actor.equipment = Equipment.new()
		gecs.stacks[actor.equipment.stack_id] = {"stack_id": actor.equipment.stack_id, "metadata": {"farm_water": 4.5, "marker": "preserve"}}
		var equipped_actions: Array = source.get_world_context_actions(actor).filter(func(action): return str(action.get("key", "")).begins_with("refill_"))
		_check(equipped_actions.size() == 2 and equipped_actions[0].label == "Refill Watering Can", "equipped can and carried vessels have separate exact scopes")
		var before: float = source.current_water
		source.perform_world_context_action("refill_watering_can", [actor])
		actor.position = actor.move_target
		actor.interaction.process_container_interaction()
		actor.finish_water_work()
		_check(gecs.stacks[actor.equipment.stack_id].metadata.farm_water == 16.0 and source.current_water == before - 11.5 and carrier.amount(actor, "water") == 3.0, "equipped action updates only exact GECS equipment stack and conserves liters")
		_check(gecs.stacks[actor.equipment.stack_id].metadata.marker == "preserve", "equipment mutation preserves unrelated stack metadata")
		var cancelled_entry = actor.inventory.entries[0]
		var cancelled_metadata: Dictionary = cancelled_entry.metadata.duplicate(true)
		_check(carrier.free_capacity(actor, "water") > 0.0 and source.current_water > 0.0, "cancelled refill has available vessel capacity and funded source")
		source.perform_world_context_action("refill_water_containers", [actor])
		var cancelled_target: Node = actor.target
		actor.interaction.stop_container_interaction()
		before = source.current_water
		actor.position = actor.move_target
		actor.container_reached.emit(actor, cancelled_target)
		cancelled_target._process(load("res://features/inventory/bridge/direct_water_refill.gd").WORK_SECONDS)
		_check(source.current_water == before and cancelled_entry.metadata == cancelled_metadata \
			and not actor.work_active, "cancelled approach cannot transfer after late arrival and full work interval")
		source.perform_world_context_action("refill_water_containers", [actor])
		var replaced_target: Node = actor.target
		source.perform_world_context_action("refill_water_containers", [actor])
		replaced_target.free()
		actor.position = actor.move_target
		actor.interaction.process_container_interaction()
		actor.finish_water_work()
		_check(carrier.amount(actor, "water") == 16.0, "old approach teardown cannot cancel a replacement command")
		gecs.stacks[actor.equipment.stack_id].metadata.farm_water = 0.0
		gecs.reject_stack_write = true
		before = source.current_water
		source.perform_world_context_action("refill_watering_can", [actor])
		actor.position = actor.move_target
		actor.interaction.process_container_interaction()
		actor.finish_water_work()
		_check(source.current_water == before and farm.get_water_source(source.source_id).current_water == before, "failed durable recipient write rolls back silent source debit")
		gecs.reject_stack_write = false
		actor.equipment = null
		_check(source.get_world_context_actions(actor).filter(func(action): return str(action.get("key", "")).begins_with("refill_")).is_empty(), "full carried vessels expose no refill action")
		actor.inventory.set_entry_metadata(actor.inventory.entries[0], {})
		source.perform_world_context_action("refill_water_containers", [actor])
		var refill = source._refill
		var source_id: String = source.source_id
		before = source.current_water
		source.free()
		actor.interaction.process_container_interaction()
		_check(refill.pending.is_empty() and actor.interaction.current_container_target == null and farm.get_water_source(source_id).current_water == before, "source LOD teardown clears volatile approach without deleting or drawing durable water")
		for path in ["res://features/farming/sim/c_game_farm_water_source_state.gd", "res://features/inventory/sim/c_game_liquid_container_state.gd"]:
			var component = load(path).new()
			component.apply_state({"public_water_access": true})
			_check(component.to_state().get("public_water_access", false), "explicit public water permission round-trips durable component: " + path.get_file())
	holder.free()
	BootstrapContext.active = null
	if ecs != null:
		Engine.unregister_singleton("ECS")
		ecs.free()
	print("DIRECT_WATER_REFILL_OK" if failures.is_empty() else "DIRECT_WATER_REFILL_FAILED: %s" % [failures])
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, label: String):
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ", label)
