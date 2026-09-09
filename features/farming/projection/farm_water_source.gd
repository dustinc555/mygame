extends StaticBody3D

class_name FarmWaterSource

const LIQUID_HAUL_CARRIER := preload("res://features/inventory/bridge/liquid_haul_carrier.gd")

@export var display_name := "Water Barrels"
@export var source_id := "water_source"
@export var settlement_id := ""
@export_enum("well", "storage") var source_kind := "storage"
@export var owner_faction_name := "Player"
@export var public_water_access := false
@export var renewable := true
@export_range(0.0, 100000.0, 0.1) var capacity := 200.0
@export_range(0.0, 100000.0, 0.1) var current_water := 200.0
@export_range(0.0, 100000.0, 0.1) var reserved_incoming_water := 0.0
@export_range(0.0, 100000.0, 0.1) var reserved_outgoing_water := 0.0
@export_range(0.0, 1000.0, 0.1) var recharge_per_world_hour := 0.0
@export_range(0.1, 20.0, 0.1) var interaction_distance := 1.6
@export_range(1, 1000, 1) var theft_value := 10
@export_range(0.0, 20.0, 0.1) var theft_noise_radius := 4.0
@export_range(0, 100, 1) var theft_difficulty := 25

var _gecs: Node
var _farm: Node
var _ownership: Node
var _haul_provider: Node
var _bind_attempts := 0
var _authored_water_state: Dictionary = {}
var is_locked := false
var _refill := preload("res://features/inventory/bridge/direct_water_refill.gd").new()


func get_world_context_actions(actor: Node) -> Array:
	return _refill.actions(self, actor)


func perform_world_context_action(key: String, actors: Array) -> String:
	return _refill.start(self, key, actors)


func register_interactor(actor: Node) -> void:
	_refill.register(self, actor)


func release_interactor(actor: Node) -> void:
	_refill.release(actor)


func resolve_interaction(_actor: Node) -> bool:
	return false # Refills never open the inventory-pair UI.


func can_take_water_legally(actor: Node) -> bool:
	return is_instance_valid(actor) and (public_water_access or _actor_can_take_without_stealing(actor))


func can_receive_water(actor: Node) -> bool:
	# A finite well buffer can receive water; an infinite source has no deficit.
	return not renewable and is_instance_valid(actor) and free_capacity() > 0.001


func authorize_water_deposit(actor: Node) -> Dictionary:
	if not can_receive_water(actor):
		return {}
	var authorization := _owner_authorization(actor)
	authorization["owner_access_approved"] = _actor_can_take_without_stealing(actor)
	authorization["public_access_approved"] = public_water_access
	if not can_take_water_legally(actor):
		if _ownership == null or not bool(_ownership.call("request_interaction", actor, self, "Pour Water")):
			return {}
		# Ownership may permit the physical act while witnesses still treat
		# it as illegal property use. This is not a theft or free legal access.
		authorization["owner_access_approved"] = true
	return authorization


func deposit_poured_water_staged(offered: float, authorization: Dictionary) -> Dictionary:
	if _farm == null or renewable:
		return {}
	return {"liters": float(_farm.deposit_water_source(source_id, offered, authorization, false)), "authorization": authorization}


func rollback_poured_water(transaction: Dictionary) -> void:
	if is_instance_valid(_farm):
		_farm.draw_water_source(source_id, float(transaction.get("liters", 0.0)), transaction.get("authorization", {}), false)


func authorize_water_withdrawal(actor: Node) -> Dictionary:
	if not is_instance_valid(actor) or available_water() <= 0.0:
		return {}
	var legal := can_take_water_legally(actor)
	var authorization := _owner_authorization(actor)
	authorization["owner_access_approved"] = _actor_can_take_without_stealing(actor)
	authorization["public_access_approved"] = public_water_access
	if not legal:
		if _ownership == null or not _ownership.has_method("request_take_item") or not bool(_ownership.call("request_take_item", actor, self)):
			return {}
		authorization["theft_approved"] = true
	return authorization


func draw_refill_water_staged(requested: float, authorization: Dictionary) -> Dictionary:
	if _farm == null:
		return {}
	return {"drawn": float(_farm.draw_water_source(source_id, requested, authorization, false))}


func publish_refill_water(_transaction: Dictionary) -> void:
	if is_instance_valid(_farm):
		_farm.water_source_changed.emit(source_id, _farm.get_water_source(source_id))


func rollback_refill_water(transaction: Dictionary) -> void:
	if is_instance_valid(_farm) and not renewable:
		_farm._restore_water_source(source_id, float(transaction.get("drawn", 0.0)), false)


func _ready() -> void:
	add_to_group("farm_water_source")
	_inherit_facility_context()
	_authored_water_state = _current_water_state()
	_authored_water_state["reserved_incoming_water"] = 0.0
	_authored_water_state["reserved_outgoing_water"] = 0.0
	if not has_node("CollisionShape3D"):
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.2, 1.0, 1.2)
		collision.shape = shape
		collision.position.y = 0.5
		add_child(collision)
	call_deferred("_bind_durable_state")


func _exit_tree() -> void:
	if _haul_provider != null and is_instance_valid(_haul_provider) and _haul_provider.has_method("unregister_endpoint"):
		_haul_provider.call("unregister_endpoint", self)


func available_water() -> float:
	return INF if renewable else maxf(0.0, current_water - reserved_outgoing_water)


func free_capacity() -> float:
	return maxf(0.0, capacity - current_water - reserved_incoming_water)


func get_interaction_position(actor: Node) -> Vector3:
	var direction := Vector3.FORWARD
	if actor is Node3D:
		direction = (actor.global_position - global_position) as Vector3
		direction.y = 0.0
	if direction.length_squared() <= 0.001:
		direction = Vector3.FORWARD
	return global_position + direction.normalized() * interaction_distance


func draw_water_for_actor(requested: float, actor: Node) -> Dictionary:
	if actor == null:
		return {"drawn": 0.0, "message": "Select a worker first"}
	if requested <= 0.0 or available_water() <= 0.0:
		return {"drawn": 0.0, "message": "Water source is dry"}
	if _farm == null or not _farm.has_method("draw_water_source"):
		return {"drawn": 0.0, "message": "Water source is unavailable"}
	var owner_access_approved := can_take_water_legally(actor)
	var theft_approved := false
	if not owner_access_approved:
		if _ownership == null or not _ownership.has_method("request_take_item"):
			return {"drawn": 0.0, "message": "Cannot verify ownership of %s" % display_name}
		if not bool(_ownership.call("request_take_item", actor, self)):
			return {"drawn": 0.0, "message": "Cannot take water from %s" % display_name}
		theft_approved = true
	var authorization := {
		"source_id": source_id,
		"owner_faction_name": owner_faction_name,
		"actor_faction_name": _actor_faction_name(actor),
		"owner_access_approved": owner_access_approved,
		"theft_approved": theft_approved,
		"public_access_approved": public_water_access,
	}
	var drawn := float(_farm.call("draw_water_source", source_id, requested, authorization))
	return {
		"drawn": drawn,
		"message": "Water source is dry" if drawn <= 0.0 else "",
	}


func deposit_water_for_actor(offered: float, actor: Node) -> Dictionary:
	if actor == null:
		return {"deposited": 0.0, "message": "Select a worker first"}
	if source_kind != "storage":
		return {"deposited": 0.0, "message": "%s is not water storage" % display_name}
	if offered <= 0.0 or free_capacity() <= 0.0:
		return {"deposited": 0.0, "message": "%s is full" % display_name}
	if not _actor_can_take_without_stealing(actor):
		return {"deposited": 0.0, "message": "Cannot use %s" % display_name}
	if _farm == null or not _farm.has_method("deposit_water_source"):
		return {"deposited": 0.0, "message": "Water storage is unavailable"}
	var authorization := {
		"source_id": source_id,
		"owner_faction_name": owner_faction_name,
		"actor_faction_name": _actor_faction_name(actor),
		"owner_access_approved": true,
		"theft_approved": false,
	}
	var deposited := float(_farm.call("deposit_water_source", source_id, offered, authorization))
	return {
		"deposited": deposited,
		"message": "%s is full" % display_name if deposited <= 0.0 else "",
	}


func reserve_outgoing_water_for_actor(requested: float, actor: Node) -> float:
	if actor == null or not _actor_can_take_without_stealing(actor) or _farm == null \
			or not _farm.has_method("reserve_water_source_outgoing"):
		return 0.0
	return float(_farm.call("reserve_water_source_outgoing", source_id, requested, _owner_authorization(actor)))


func release_outgoing_water_reservation(liters: float) -> float:
	return float(_farm.call("release_water_source_outgoing", source_id, liters)) \
			if _farm != null and _farm.has_method("release_water_source_outgoing") else 0.0


func draw_reserved_water_for_actor(requested: float, actor: Node) -> Dictionary:
	if actor == null or not _actor_can_take_without_stealing(actor) or _farm == null \
			or not _farm.has_method("draw_reserved_water_source"):
		return {"drawn": 0.0}
	return {"drawn": float(_farm.call("draw_reserved_water_source", source_id, requested, _owner_authorization(actor)))}


func reserve_incoming_water_for_actor(requested: float, actor: Node) -> float:
	if actor == null or source_kind != "storage" or not _actor_can_take_without_stealing(actor) or _farm == null \
			or not _farm.has_method("reserve_water_source_incoming"):
		return 0.0
	return float(_farm.call("reserve_water_source_incoming", source_id, requested, _owner_authorization(actor)))


func release_incoming_water_reservation(liters: float) -> float:
	return float(_farm.call("release_water_source_incoming", source_id, liters)) \
			if _farm != null and _farm.has_method("release_water_source_incoming") else 0.0


func deposit_reserved_water_for_actor(offered: float, actor: Node) -> Dictionary:
	if actor == null or source_kind != "storage" or not _actor_can_take_without_stealing(actor) or _farm == null \
			or not _farm.has_method("deposit_reserved_water_source"):
		return {"deposited": 0.0}
	return {"deposited": float(_farm.call("deposit_reserved_water_source", source_id, offered, _owner_authorization(actor)))}


func get_haul_endpoint_id() -> String:
	return source_id


func get_haul_resource_ids() -> PackedStringArray:
	return PackedStringArray(["water"])


func get_haul_available(resource_id: String) -> float:
	return available_water() if resource_id == "water" else 0.0


func get_haul_free_capacity(resource_id: String) -> float:
	return free_capacity() if resource_id == "water" and source_kind == "storage" else 0.0


func get_haul_transfer_capacity(resource_id: String, actor: Node) -> float:
	return LIQUID_HAUL_CARRIER.free_capacity(actor, resource_id) if resource_id == "water" else 0.0


func get_carried_haul_amount(resource_id: String, actor: Node) -> float:
	return LIQUID_HAUL_CARRIER.amount(actor, resource_id)


func reserve_haul_outgoing(resource_id: String, requested: float, actor: Node) -> float:
	return reserve_outgoing_water_for_actor(requested, actor) if resource_id == "water" else 0.0


func release_haul_outgoing(resource_id: String, amount: float, _actor: Node = null) -> float:
	return release_outgoing_water_reservation(amount) if resource_id == "water" else 0.0


func reserve_haul_incoming(resource_id: String, requested: float, actor: Node) -> float:
	return reserve_incoming_water_for_actor(requested, actor) if resource_id == "water" else 0.0


func release_haul_incoming(resource_id: String, amount: float, _actor: Node = null) -> float:
	return release_incoming_water_reservation(amount) if resource_id == "water" else 0.0


func load_reserved_haul(resource_id: String, requested: float, actor: Node) -> float:
	if resource_id != "water":
		return 0.0
	var before := LIQUID_HAUL_CARRIER.amount(actor, resource_id)
	var offered := minf(maxf(0.0, requested), LIQUID_HAUL_CARRIER.free_capacity(actor, resource_id))
	if offered <= 0.0 or not LIQUID_HAUL_CARRIER.set_amount(actor, resource_id, before + offered, false):
		return 0.0
	var drawn := float(draw_reserved_water_for_actor(offered, actor).get("drawn", 0.0))
	LIQUID_HAUL_CARRIER.set_amount(actor, resource_id, before + drawn)
	return drawn


func unload_reserved_haul(resource_id: String, requested: float, actor: Node) -> float:
	if resource_id != "water":
		return 0.0
	var before := LIQUID_HAUL_CARRIER.amount(actor, resource_id)
	var offered := minf(maxf(0.0, requested), before)
	if offered <= 0.0 or not LIQUID_HAUL_CARRIER.set_amount(actor, resource_id, before - offered, false):
		return 0.0
	var deposited := float(deposit_reserved_water_for_actor(offered, actor).get("deposited", 0.0))
	LIQUID_HAUL_CARRIER.set_amount(actor, resource_id, before - deposited)
	return deposited


func get_details_panel_data_at(_world_position: Vector3) -> Dictionary:
	var state := "Renewable"
	if not renewable:
		if current_water <= 0.001:
			state = "Empty"
		elif current_water >= capacity - 0.001:
			state = "Full"
		else:
			state = "Partly Full"
	var ratio := 1.0 if renewable else clampf(current_water / maxf(0.001, capacity), 0.0, 1.0)
	return {
		"title": display_name,
		"state": state,
		"subtitle": "Owned by %s" % owner_faction_name,
		"show_resource_bar": not renewable,
		"resource_label": "Water",
		"resource_ratio": ratio,
		"resource_value_text": "%s / %s" % [_format_amount(current_water), _format_amount(capacity)],
	}


func get_owner_faction_name() -> String:
	return owner_faction_name


func get_theft_value() -> int:
	return theft_value


func get_theft_noise_radius() -> float:
	return theft_noise_radius


func get_theft_difficulty() -> int:
	return theft_difficulty


func _bind_durable_state() -> void:
	_inherit_facility_context()
	var context := BootstrapContext.active
	if context == null:
		_bind_attempts += 1
		if _bind_attempts < 50 and is_inside_tree():
			get_tree().create_timer(0.1).timeout.connect(_bind_durable_state)
		return
	_gecs = context.get_optional(&"gecs_world")
	_farm = context.get_optional(&"farming")
	_ownership = context.get_optional(&"ownership")
	_haul_provider = context.get_optional(&"haul")
	if _farm == null or not _farm.has_method("register_water_source"):
		push_error("FarmWaterSource '%s' requires the farming controller" % source_id)
		return
	if source_id.strip_edges().is_empty():
		push_error("FarmWaterSource requires a stable source_id")
		return
	if _farm.has_signal("water_source_changed") and not _farm.water_source_changed.is_connected(_on_water_source_changed):
		_farm.water_source_changed.connect(_on_water_source_changed)
	if _gecs != null and not _gecs.world_reindexed.is_connected(_on_world_reindexed):
		_gecs.world_reindexed.connect(_on_world_reindexed)
	var now := 0
	var world_time := context.get_optional(&"world_time")
	if world_time != null:
		now = int(world_time.get_absolute_minute())
	var saved: Dictionary = _farm.register_water_source({
		"public_water_access": public_water_access,
		"source_id": source_id,
		"settlement_id": settlement_id,
		"source_kind": source_kind,
		"world_position": global_position,
		"owner_faction_name": owner_faction_name,
		"capacity": capacity,
		"current_water": current_water,
		"reserved_incoming_water": reserved_incoming_water,
		"reserved_outgoing_water": reserved_outgoing_water,
		"renewable": renewable,
		"recharge_per_world_minute": recharge_per_world_hour / 60.0,
		"last_processed_minute": now,
	})
	_apply_durable_state(saved)
	if _haul_provider != null and _haul_provider.has_method("register_endpoint"):
		_haul_provider.call("register_endpoint", self)


func _on_world_reindexed() -> void:
	_refill.cancel_all()
	_reload_durable_state.call_deferred()


## Projection teardown is not demolition. Call this only from an explicit
## facility/furniture removal path that intends to erase durable water state.
func remove_from_simulation() -> bool:
	return _farm != null and _farm.has_method("remove_water_source") \
			and bool(_farm.call("remove_water_source", source_id))


func sync_durable_context() -> void:
	if Engine.is_editor_hint():
		return
	_inherit_facility_context()
	_bind_durable_state()


func _on_water_source_changed(changed_source_id: String, state: Dictionary) -> void:
	if changed_source_id == source_id:
		_apply_durable_state(state)


func _reload_durable_state() -> void:
	if _farm == null or not _farm.has_method("get_water_source"):
		return
	var state: Dictionary = _farm.get_water_source(source_id)
	if state.is_empty():
		var seed := _authored_water_state.duplicate(true)
		seed["source_id"] = source_id
		seed["settlement_id"] = settlement_id
		seed["owner_faction_name"] = owner_faction_name
		seed["world_position"] = global_position
		seed["reserved_incoming_water"] = 0.0
		seed["reserved_outgoing_water"] = 0.0
		var context := BootstrapContext.active
		var world_time := context.get_optional(&"world_time") if context != null else null
		seed["last_processed_minute"] = int(world_time.get_absolute_minute()) if world_time != null else 0
		state = _farm.register_water_source(seed)
		_apply_durable_state(state)
		return
	_apply_durable_state(state)


func _current_water_state() -> Dictionary:
	return {
		"public_water_access": public_water_access,
		"source_id": source_id,
		"settlement_id": settlement_id,
		"source_kind": source_kind,
		"world_position": global_position,
		"owner_faction_name": owner_faction_name,
		"capacity": capacity,
		"current_water": current_water,
		"reserved_incoming_water": reserved_incoming_water,
		"reserved_outgoing_water": reserved_outgoing_water,
		"renewable": renewable,
		"recharge_per_world_minute": recharge_per_world_hour / 60.0,
	}


func _apply_durable_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	capacity = float(state.get("capacity", capacity))
	current_water = float(state.get("current_water", current_water))
	reserved_incoming_water = float(state.get("reserved_incoming_water", reserved_incoming_water))
	reserved_outgoing_water = float(state.get("reserved_outgoing_water", reserved_outgoing_water))
	settlement_id = str(state.get("settlement_id", settlement_id))
	source_kind = str(state.get("source_kind", source_kind))
	owner_faction_name = str(state.get("owner_faction_name", owner_faction_name))
	public_water_access = bool(state.get("public_water_access", public_water_access))
	renewable = bool(state.get("renewable", renewable))
	recharge_per_world_hour = float(state.get("recharge_per_world_minute", recharge_per_world_hour / 60.0)) * 60.0
	if _haul_provider != null and is_instance_valid(_haul_provider) and _haul_provider.has_method("notify_endpoint_changed"):
		_haul_provider.call("notify_endpoint_changed", self)


func _inherit_facility_context() -> void:
	var current := get_parent()
	while current != null:
		if current.has_method("get_facility_id"):
			var facility_id := str(current.call("get_facility_id")).strip_edges()
			if (source_id.strip_edges().is_empty() or source_id == "water_source") and not facility_id.is_empty():
				source_id = "%s.%s" % [facility_id, str(name).to_snake_case()]
			if settlement_id.strip_edges().is_empty() and current.has_method("_effective_settlement_id"):
				settlement_id = str(current.call("_effective_settlement_id")).strip_edges()
			if current.has_method("get_property_owner_faction"):
				owner_faction_name = str(current.call("get_property_owner_faction")).strip_edges()
			return
		current = current.get_parent()


func _actor_can_take_without_stealing(actor: Node) -> bool:
	if actor == null or owner_faction_name.is_empty():
		return false
	if actor.has_method("is_authorized_for_owner"):
		return bool(actor.call("is_authorized_for_owner", null, owner_faction_name))
	return _actor_faction_name(actor) == owner_faction_name


func _actor_faction_name(actor: Node) -> String:
	if actor == null:
		return ""
	var actor_faction := ""
	for property in actor.get_property_list():
		var property_name := str(property.get("name", ""))
		if property_name == "faction_name" and not str(actor.get("faction_name")).is_empty():
			actor_faction = str(actor.get("faction_name"))
			break
		if property_name == "faction_id":
			actor_faction = str(actor.get("faction_id"))
	return actor_faction


func _owner_authorization(actor: Node) -> Dictionary:
	return {
		"source_id": source_id,
		"owner_faction_name": owner_faction_name,
		"actor_faction_name": _actor_faction_name(actor),
		"owner_access_approved": true,
		"theft_approved": false,
	}


func _format_amount(value: float) -> String:
	return str(int(round(value))) if is_equal_approx(value, round(value)) else "%.1f" % value
