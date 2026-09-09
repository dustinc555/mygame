extends RefCounted
## Source-local, volatile interaction intent. No stock is reserved while walking;
## exact stacks and current permission are revalidated at the arrival boundary.
const CARRIER := preload("res://features/inventory/bridge/liquid_haul_carrier.gd")
const CAN := "refill_watering_can"
const VESSELS := "refill_water_containers"
const POUR := "pour_water"
const ARRIVAL_DISTANCE := 1.0
const WORK_SECONDS := 3.0
var pending: Dictionary = {}

class Approach:
	extends Node3D
	var is_locked := false
	# Allow the normal nav-clamped stopping tolerance around the outer slot,
	# not the solid source center. The transaction checks this same reach.
	var interaction_distance := ARRIVAL_DISTANCE
	var source_ref: WeakRef
	var owner_ref: WeakRef
	var actor_ref: WeakRef
	var actor_id := 0
	var working := false
	var elapsed := 0.0
	func _ready() -> void:
		set_process(false)
	func begin_timed_interaction(actor: Node) -> void:
		if working or is_queued_for_deletion():
			return
		var owner = owner_ref.get_ref()
		if owner == null or int(owner.pending.get(actor_id, {}).get("approach_id", 0)) != get_instance_id():
			return
		if actor.global_position.distance_to(global_position) > ARRIVAL_DISTANCE:
			return
		working = true
		elapsed = 0.0
		_set_visual(actor, true)
		set_process(true)
	func _set_visual(actor: Node, active: bool) -> void:
		if actor.has_method("set_farming_work_visual"):
			var source = source_ref.get_ref()
			actor.set_farming_work_visual(active, "water", source.global_position if is_instance_valid(source) else global_position, elapsed / WORK_SECONDS)
	func _process(delta: float) -> void:
		if not working or is_queued_for_deletion():
			return
		var actor = actor_ref.get_ref()
		var source = source_ref.get_ref()
		if not is_instance_valid(actor) or not is_instance_valid(source) or actor.is_queued_for_deletion() or source.is_queued_for_deletion():
			cancel()
			return
		var life_state = actor.get("life_state")
		if life_state != null and int(life_state) != NpcRules.LifeState.ALIVE:
			cancel()
			return
		var interaction = actor.get_interaction()
		if interaction.current_container_target != self or actor.global_position.distance_to(global_position) > ARRIVAL_DISTANCE:
			cancel()
			return
		elapsed = minf(WORK_SECONDS, elapsed + maxf(0.0, delta))
		_set_visual(actor, true)
		if elapsed < WORK_SECONDS:
			return
		var owner = owner_ref.get_ref()
		if owner != null:
			owner._arrived(actor, source, source_ref)
		if is_instance_valid(actor) and interaction.current_container_target == self:
			interaction.stop_container_interaction()
		else:
			queue_free()
	func get_interaction_position(_actor: Node) -> Vector3:
		return global_position
	func resolve_interaction(_actor: Node) -> bool:
		return false
	func register_interactor(actor: Node) -> void:
		actor_ref = weakref(actor)
		actor_id = actor.get_instance_id()
		actor.connect("container_reached", _arrived)
		actor.tree_exiting.connect(queue_free, CONNECT_ONE_SHOT)
	func release_interactor(actor: Node) -> void:
		if working:
			_set_visual(actor, false)
		working = false
		set_process(false)
		var owner = owner_ref.get_ref()
		if owner != null:
			owner.release(actor, get_instance_id())
		queue_free()
	func cancel() -> void:
		var actor = actor_ref.get_ref() if actor_ref != null else null
		if is_instance_valid(actor):
			var interaction = actor.get_interaction()
			if interaction.current_container_target == self:
				interaction.stop_container_interaction()
			else:
				release_interactor(actor)
		else:
			queue_free()
	func _exit_tree() -> void:
		var actor = actor_ref.get_ref() if actor_ref != null else null
		if working and is_instance_valid(actor):
			_set_visual(actor, false)
		working = false
		if is_instance_valid(actor) and actor.is_connected("container_reached", _arrived):
			actor.disconnect("container_reached", _arrived)
		var owner = owner_ref.get_ref()
		if owner != null:
			owner._release_id(actor_id, get_instance_id())
	func _arrived(actor: Node, reached: Node) -> void:
		if reached != self:
			return
		begin_timed_interaction(actor)

func actions(source: Node, actor: Node) -> Array:
	var result: Array = []
	if not is_instance_valid(actor):
		return result
	for key in [CAN, VESSELS]:
		if source.available_water() <= 0.0 or _targets(actor, key).is_empty():
			continue
		var action := {"key": key, "label": "Refill Watering Can" if key == CAN else "Refill Water Containers"}
		if not source.can_take_water_legally(actor):
			action["color"] = Color(1.0, 0.3, 0.3)
		result.append(action)
	if source.can_receive_water(actor) and not _targets(actor, POUR).is_empty():
		var action := {"key": POUR, "label": "Pour Water Into %s" % source.display_name}
		if not source.can_take_water_legally(actor):
			action["color"] = Color(1.0, 0.3, 0.3)
		result.append(action)
	return result

func start(source: Node, key: String, actors: Array) -> String:
	if key not in [CAN, VESSELS, POUR]:
		return ""
	# The world menu belongs to the first selected actor, not an implicit group.
	if actors.is_empty():
		return "Select a worker first"
	var actor = actors[0]
	if not is_instance_valid(actor) or not actor.has_method("assign_open_container") or not actor.has_signal("container_reached"):
		return "Cannot refill water"
	var targets := _targets(actor, key)
	if targets.is_empty() or (not source.can_receive_water(actor) if key == POUR else source.available_water() <= 0.0):
		return "No refillable water container"
	var point: Vector3 = source.get_interaction_position(actor)
	var approach := Approach.new()
	approach.source_ref = weakref(source)
	approach.owner_ref = weakref(self)
	source.add_child(approach)
	approach.global_position = point
	actor.assign_open_container(approach)
	if approach.actor_ref == null:
		approach.queue_free()
		return "Cannot start refill"
	pending[actor.get_instance_id()] = {"targets": targets, "point": point, "approach_id": approach.get_instance_id(), "pouring": key == POUR}
	return ""

func register(source: Node, actor: Node) -> void:
	if actor.has_signal("container_reached"):
		var callback := _arrived.bind(weakref(source))
		if not actor.is_connected("container_reached", callback):
			actor.connect("container_reached", callback)

func release(actor: Node, approach_id := 0) -> void:
	if is_instance_valid(actor):
		_release_id(actor.get_instance_id(), approach_id)

func _release_id(actor_id: int, approach_id: int) -> void:
	if approach_id == 0 or int(pending.get(actor_id, {}).get("approach_id", 0)) == approach_id:
		pending.erase(actor_id)

func cancel_all() -> void:
	for intent in pending.values():
		var approach = instance_from_id(int(intent.get("approach_id", 0)))
		if is_instance_valid(approach):
			approach.cancel()
	pending.clear()

func _arrived(actor: Node, reached: Node, source_ref: WeakRef) -> void:
	var source = source_ref.get_ref()
	if not is_instance_valid(source) or reached != source or not is_instance_valid(actor):
		return
	var id := actor.get_instance_id()
	var intent: Dictionary = pending.get(id, {})
	if intent.is_empty() or not source.is_inside_tree() or not actor.is_inside_tree():
		pending.erase(id)
		return
	# Match the actuator's physical reach, but also require the approached slot.
	if actor.global_position.distance_to(intent.point) > ARRIVAL_DISTANCE:
		pending.erase(id)
		return
	for target in intent.targets:
		if not is_instance_valid(actor) or not is_instance_valid(source) or actor.is_queued_for_deletion() or source.is_queued_for_deletion() or pending.get(id, {}) != intent:
			break
		var carrier := _resolve(actor, target)
		if bool(intent.get("pouring", false)):
			_pour_one(source, actor, target, intent)
			continue
		if carrier.is_empty() or _free(actor, carrier) <= 0.001:
			continue
		var authorization: Dictionary = source.authorize_water_withdrawal(actor)
		# Theft can synchronously cancel orders or remove projections.
		if authorization.is_empty() or not is_instance_valid(actor) or not is_instance_valid(source) or pending.get(id, {}) != intent:
			break
		carrier = _resolve(actor, target)
		if carrier.is_empty():
			continue
		var requested := minf(_free(actor, carrier), source.available_water())
		if requested <= 0.001:
			continue
		var before := _water(carrier.metadata)
		var transaction: Dictionary = source.draw_refill_water_staged(requested, authorization)
		var moved := float(transaction.get("drawn", 0.0))
		if moved <= 0.0:
			continue
		if not _set_water(carrier, before + moved):
			source.rollback_refill_water(transaction)
			break
		# Both sides are settled before any observer is notified.
		source.publish_refill_water(transaction)
		var inventory = carrier.inventory
		if is_instance_valid(inventory):
			inventory.changed.emit()
	if pending.get(id, {}) == intent:
		pending.erase(id)

func _pour_one(destination: Node, actor: Node, target: Dictionary, intent: Dictionary) -> void:
	var carrier := _resolve(actor, target)
	if carrier.is_empty() or _has_other_liquid(carrier.metadata):
		return
	var before := _water(carrier.metadata)
	if before <= 0.001:
		return
	var authorization: Dictionary = destination.authorize_water_deposit(actor)
	# Property reactions can synchronously cancel orders or unload actors.
	if authorization.is_empty() or not is_instance_valid(actor) or not is_instance_valid(destination):
		return
	if actor.is_queued_for_deletion() or destination.is_queued_for_deletion() or pending.get(actor.get_instance_id(), {}) != intent:
		return
	carrier = _resolve(actor, target)
	if carrier.is_empty() or _has_other_liquid(carrier.metadata):
		return
	before = _water(carrier.metadata)
	if before <= 0.001:
		return
	var transaction: Dictionary = destination.deposit_poured_water_staged(before, authorization)
	var moved := float(transaction.get("liters", 0.0))
	if moved <= 0.0:
		return
	if not _set_water(carrier, before - moved):
		destination.rollback_poured_water(transaction)
		return
	# Settle exact durable carrier debit before observers see destination credit.
	destination.publish_refill_water(transaction)
	if is_instance_valid(carrier.inventory):
		carrier.inventory.changed.emit()

func _targets(actor: Node, key: String) -> Array:
	var result: Array = []
	var inventory = CARRIER._inventory(actor)
	if inventory == null:
		return result
	if key in [VESSELS, POUR]:
		for entry in inventory.entries:
			if entry == null or entry.definition == null or entry.count != 1:
				continue
			if not entry.definition.has_tool_tag("tool.water_container") and not entry.definition.has_tool_tag("tool.liquid_container"):
				continue
			var target := {"stack_id": str(entry.stack_id), "equipped": false}
			var carrier := _resolve(actor, target)
			if _eligible_carrier(actor, carrier, key == POUR):
				result.append(target)
	if key in [CAN, POUR] and actor.has_method("get_equipment"):
		var equipment = actor.get_equipment()
		if equipment != null and equipment.has_method("get_equipped_stack_id"):
			var definition = equipment.get_equipped_item("weapon")
			if definition != null and str(definition.item_id) == "tool.watering_can":
				var target := {"stack_id": str(equipment.get_equipped_stack_id("weapon")), "equipped": true}
				var carrier := _resolve(actor, target)
				if _eligible_carrier(actor, carrier, key == POUR):
					result.push_front(target)
	return result

func _eligible_carrier(actor: Node, carrier: Dictionary, pouring: bool) -> bool:
	if carrier.is_empty() or _has_other_liquid(carrier.metadata):
		return false
	return _water(carrier.metadata) > 0.001 if pouring else _free(actor, carrier) > 0.001

func _resolve(actor: Node, target: Dictionary) -> Dictionary:
	var inventory = CARRIER._inventory(actor)
	if inventory == null:
		return {}
	if not target.equipped:
		for entry in inventory.entries:
			if str(entry.stack_id) == str(target.stack_id) and entry.count == 1:
				return {"entry": entry, "inventory": inventory, "metadata": entry.metadata.duplicate(true), "capacity": _capacity(entry.definition)}
		return {}
	var equipment = actor.get_equipment() if actor.has_method("get_equipment") else null
	var gecs := BootstrapContext.service(&"gecs_world")
	if equipment == null or gecs == null or str(equipment.get_equipped_stack_id("weapon")) != str(target.stack_id):
		return {}
	var definition = equipment.get_equipped_item("weapon")
	if definition == null or str(definition.item_id) != "tool.watering_can":
		return {}
	var snapshot: Dictionary = gecs.get_item_stack(str(target.stack_id))
	if snapshot.is_empty():
		return {}
	return {"snapshot": snapshot, "gecs": gecs, "inventory": inventory, "metadata": snapshot.get("metadata", {}).duplicate(true), "capacity": _capacity(definition)}

func _free(actor: Node, carrier: Dictionary) -> float:
	var metadata: Dictionary = carrier.metadata
	if _has_other_liquid(metadata):
		return 0.0
	var free := maxf(0.0, float(carrier.capacity) - _water(metadata))
	var inventory = carrier.inventory
	if inventory.use_weight:
		var equipped_water := 0.0
		if actor.has_method("get_equipment"):
			var equipment = actor.get_equipment()
			var gecs := BootstrapContext.service(&"gecs_world")
			if equipment != null and gecs != null and equipment.has_method("get_equipped_stack_id"):
				var snapshot: Dictionary = gecs.get_item_stack(str(equipment.get_equipped_stack_id("weapon")))
				equipped_water = _water(snapshot.get("metadata", {}))
		free = minf(free, maxf(0.0, inventory.max_weight - inventory.get_total_weight() - equipped_water))
	return free

func _has_other_liquid(metadata: Dictionary) -> bool:
	for liquid in (metadata.get("carried_liquids", {}) as Dictionary):
		if str(liquid) != "water" and float(metadata.carried_liquids[liquid]) > 0.0:
			return true
	return false

func _set_water(carrier: Dictionary, liters: float) -> bool:
	var metadata: Dictionary = CARRIER.metadata_with_water(carrier.metadata, liters)
	if carrier.has("entry"):
		if not bool(carrier.inventory.set_entry_metadata(carrier.entry, metadata, false)):
			return false
		# Live inventory signals normally mirror metadata to GECS. Settle an
		# existing durable stack now, before source observers can save or unload.
		var gecs := BootstrapContext.service(&"gecs_world")
		var snapshot: Dictionary = gecs.get_item_stack(str(carrier.entry.stack_id)) if gecs != null else {}
		if not snapshot.is_empty():
			snapshot["metadata"] = metadata
			var saved: Dictionary = gecs.upsert_item_stack_record(snapshot)
			if saved.is_empty():
				carrier.inventory.set_entry_metadata(carrier.entry, carrier.metadata, false)
				return false
		return true
	var snapshot: Dictionary = carrier.snapshot.duplicate(true)
	snapshot["metadata"] = metadata
	var saved: Dictionary = carrier.gecs.upsert_item_stack_record(snapshot)
	return not saved.is_empty() and str(saved.get("stack_id", "")) == str(snapshot.get("stack_id", "")) and is_equal_approx(_water(saved.get("metadata", {})), liters)

func _water(metadata: Dictionary) -> float:
	return CARRIER.water_from_metadata(metadata)

func _capacity(definition) -> float:
	return CARRIER.WATERING_CAN_CAPACITY if str(definition.item_id) == "tool.watering_can" else CARRIER.DEFAULT_CAPACITY
