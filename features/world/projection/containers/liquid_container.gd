@tool
extends StaticBody3D

class_name LiquidContainer

const LIQUID_HAUL_CARRIER := preload("res://features/inventory/bridge/liquid_haul_carrier.gd")

@export var display_name := "Tank"
@export var liquid_container_id := "tank"
@export var settlement_id := ""
@export var facility_id := ""
@export var owner_faction_name := ""
@export var public_water_access := false
@export var assigned_liquid_id := ""
@export var capacity_liters := 12000.0
@export var current_liters := 0.0
@export var reserved_incoming_liters := 0.0
@export var reserved_outgoing_liters := 0.0
@export var furniture_type := FurnitureRules.Type.CONTAINER
@export var interaction_distance := 2.8

var _bind_attempts := 0
var _pending_actor_ids: Dictionary = {}
var _authored_liquid_state: Dictionary = {}
var is_locked := false
var _refill := preload("res://features/inventory/bridge/direct_water_refill.gd").new()


func get_details_panel_data_at(_world_position: Vector3) -> Dictionary:
	var liquid_name := assigned_liquid_id.replace(".", " ").capitalize()
	var title := display_name
	if display_name == "Tank" and not liquid_name.is_empty():
		title = "%s Tank" % liquid_name
	var state := "Unassigned" if liquid_name.is_empty() else "Empty"
	if current_liters > 0.001:
		state = "Full" if current_liters >= capacity_liters - 0.001 else "Partly Full"
	return {
		"title": title,
		"state": state,
		"subtitle": "Owned by %s" % owner_faction_name if not owner_faction_name.is_empty() else "",
		"show_resource_bar": true,
		"resource_label": liquid_name if not liquid_name.is_empty() else "Capacity",
		"resource_ratio": clampf(current_liters / maxf(0.001, capacity_liters), 0.0, 1.0),
		"resource_value_text": "%s / %s L" % [str(snappedf(current_liters, 0.1)), str(snappedf(capacity_liters, 0.1))],
	}


func get_world_context_actions(actor: Node) -> Array:
	return _refill.actions(self, actor)


func perform_world_context_action(key: String, actors: Array) -> String:
	return _refill.start(self, key, actors)


func cancel_refill_interactions() -> void:
	_refill.cancel_all()


func can_take_water_legally(actor: Node) -> bool:
	return is_instance_valid(actor) and (public_water_access or _actor_can_access(actor))


func can_receive_water(actor: Node) -> bool:
	return is_instance_valid(actor) and free_capacity_for_liquid("water") > 0.001


func authorize_water_deposit(actor: Node) -> Dictionary:
	if not can_receive_water(actor):
		return {}
	var authorization := {
		"liquid_container_id": liquid_container_id,
		"owner_faction_name": owner_faction_name,
		"actor_faction_name": str(actor.get("faction_name")).strip_edges(),
		"owner_access_approved": _actor_can_access(actor),
		"public_access_approved": public_water_access,
		"theft_approved": false,
	}
	if not can_take_water_legally(actor):
		var ownership := BootstrapContext.service(&"ownership")
		if ownership == null or not bool(ownership.call("request_interaction", actor, self, "Pour Water")):
			return {}
		# Approved by the property-interaction boundary, not made legal.
		# The proof remains bound to the destination's current owner and ID.
		authorization["owner_access_approved"] = true
	return authorization


func deposit_poured_water_staged(offered: float, authorization: Dictionary) -> Dictionary:
	var storage := BootstrapContext.service(LiquidStorageController.SERVICE_ID)
	return storage.deposit_staged(liquid_container_id, "water", offered, authorization) if storage != null else {}


func rollback_poured_water(transaction: Dictionary) -> void:
	var storage := BootstrapContext.service(LiquidStorageController.SERVICE_ID)
	if storage != null:
		storage.rollback_staged_deposit(transaction)


func authorize_water_withdrawal(actor: Node) -> Dictionary:
	if not is_instance_valid(actor) or available_water() <= 0.0:
		return {}
	var authorization := {
		"liquid_container_id": liquid_container_id,
		"owner_faction_name": owner_faction_name,
		"actor_faction_name": str(actor.get("faction_name")),
		"owner_access_approved": _actor_can_access(actor),
		"public_access_approved": public_water_access,
		"theft_approved": false,
	}
	if not can_take_water_legally(actor):
		var ownership := BootstrapContext.service(&"ownership")
		if ownership == null or not bool(ownership.call("request_take_item", actor, self)):
			return {}
		authorization["theft_approved"] = true
	return authorization


func draw_refill_water_staged(requested: float, authorization: Dictionary) -> Dictionary:
	var storage := BootstrapContext.service(LiquidStorageController.SERVICE_ID)
	if storage == null:
		return {}
	var previous: Dictionary = storage.get_container_state(liquid_container_id)
	var drawn := float(storage.draw(liquid_container_id, "water", requested, authorization, false))
	return {"drawn": drawn, "liquid_container_id": liquid_container_id, "previous_state": previous}


func publish_refill_water(transaction: Dictionary) -> void:
	var storage := BootstrapContext.service(LiquidStorageController.SERVICE_ID)
	if storage != null:
		storage.publish_staged_transactions([transaction])


func rollback_refill_water(transaction: Dictionary) -> void:
	var storage := BootstrapContext.service(LiquidStorageController.SERVICE_ID)
	if storage != null:
		storage.rollback_staged_draw(transaction)


func get_theft_value() -> int:
	return 10


func get_theft_noise_radius() -> float:
	return 4.0


func get_theft_difficulty() -> int:
	return 25


func _ready() -> void:
	add_to_group(FurnitureRules.FURNITURE_GROUP)
	add_to_group("liquid_container")
	if Engine.is_editor_hint():
		return
	_inherit_facility_context()
	_authored_liquid_state = _current_liquid_state()
	_authored_liquid_state["reserved_incoming_liters"] = 0.0
	_authored_liquid_state["reserved_outgoing_liters"] = 0.0
	call_deferred("_bind_state")
	call_deferred("_bind_haul_provider")


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	var storage := BootstrapContext.service(LiquidStorageController.SERVICE_ID)
	if storage != null:
		storage.call("detach_liquid_container", liquid_container_id, self)
	var hauling := BootstrapContext.service(&"haul")
	if hauling != null and hauling.has_method("unregister_endpoint"):
		hauling.call("unregister_endpoint", self)


func assign_liquid(liquid_id: String, actor: Node = null) -> bool:
	var normalized := liquid_id.strip_edges().to_lower()
	var storage := BootstrapContext.service(LiquidStorageController.SERVICE_ID) if not Engine.is_editor_hint() else null
	if storage != null:
		var assigned := bool(storage.call("assign_liquid", liquid_container_id, normalized, _owner_authorization(actor)))
		if assigned:
			_bind_haul_provider()
		return assigned
	if not Engine.is_editor_hint():
		return false
	if current_liters > 0.001 or reserved_incoming_liters > 0.001 or reserved_outgoing_liters > 0.001:
		return assigned_liquid_id == normalized
	assigned_liquid_id = normalized
	return true


func apply_liquid_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	liquid_container_id = str(state.get("liquid_container_id", liquid_container_id))
	settlement_id = str(state.get("settlement_id", settlement_id))
	facility_id = str(state.get("facility_id", facility_id))
	owner_faction_name = str(state.get("owner_faction_name", owner_faction_name))
	public_water_access = bool(state.get("public_water_access", public_water_access))
	assigned_liquid_id = str(state.get("assigned_liquid_id", assigned_liquid_id))
	capacity_liters = maxf(0.0, float(state.get("capacity_liters", capacity_liters)))
	current_liters = clampf(float(state.get("current_liters", current_liters)), 0.0, capacity_liters)
	reserved_incoming_liters = maxf(0.0, float(state.get("reserved_incoming_liters", reserved_incoming_liters)))
	reserved_outgoing_liters = maxf(0.0, float(state.get("reserved_outgoing_liters", reserved_outgoing_liters)))
	var hauling := BootstrapContext.service(&"haul") if not Engine.is_editor_hint() else null
	if hauling != null and hauling.has_method("notify_endpoint_changed"):
		hauling.call("notify_endpoint_changed", self)


func get_authored_liquid_state() -> Dictionary:
	return _authored_liquid_state.duplicate(true)


func _current_liquid_state() -> Dictionary:
	return {
		"public_water_access": public_water_access,
		"liquid_container_id": liquid_container_id,
		"settlement_id": settlement_id,
		"facility_id": facility_id,
		"owner_faction_name": owner_faction_name,
		"world_position": global_position,
		"assigned_liquid_id": assigned_liquid_id,
		"capacity_liters": capacity_liters,
		"current_liters": current_liters,
		"reserved_incoming_liters": reserved_incoming_liters,
		"reserved_outgoing_liters": reserved_outgoing_liters,
	}


func available_liquid(liquid_id: String) -> float:
	if assigned_liquid_id != liquid_id.strip_edges().to_lower():
		return 0.0
	return maxf(0.0, current_liters - reserved_outgoing_liters)


func free_capacity_for_liquid(liquid_id: String) -> float:
	var normalized := liquid_id.strip_edges().to_lower()
	if assigned_liquid_id != normalized:
		return 0.0
	return maxf(0.0, capacity_liters - current_liters - reserved_incoming_liters)


func deposit_liquid_for_actor(liquid_id: String, offered_liters: float, actor: Node) -> Dictionary:
	if not _actor_can_access(actor) or assigned_liquid_id != liquid_id.strip_edges().to_lower():
		return {"deposited": 0.0}
	var storage := BootstrapContext.service(LiquidStorageController.SERVICE_ID)
	var deposited := float(storage.call("deposit", liquid_container_id, liquid_id, offered_liters, \
			_owner_authorization(actor))) if storage != null else 0.0
	return {"deposited": deposited}


func draw_liquid_for_actor(liquid_id: String, requested_liters: float, actor: Node) -> Dictionary:
	if assigned_liquid_id != liquid_id.strip_edges().to_lower() or requested_liters <= 0.0 or available_liquid(liquid_id) <= 0.0:
		return {"drawn": 0.0}
	var authorization := authorize_water_withdrawal(actor) if liquid_id == "water" else _owner_authorization(actor)
	var storage := BootstrapContext.service(LiquidStorageController.SERVICE_ID)
	var drawn := float(storage.call("draw", liquid_container_id, liquid_id, requested_liters, \
			authorization)) if storage != null else 0.0
	return {"drawn": drawn}


## Water compatibility is intentionally an adapter over generic liquid storage.
func available_water() -> float:
	return available_liquid("water")


func free_capacity() -> float:
	return free_capacity_for_liquid("water")


func deposit_water_for_actor(offered_liters: float, actor: Node) -> Dictionary:
	return deposit_liquid_for_actor("water", offered_liters, actor)


func draw_water_for_actor(requested_liters: float, actor: Node) -> Dictionary:
	return draw_liquid_for_actor("water", requested_liters, actor)


func reserve_outgoing_water_for_actor(requested_liters: float, actor: Node) -> float:
	if not _actor_can_access(actor):
		return 0.0
	var storage := BootstrapContext.service(LiquidStorageController.SERVICE_ID)
	return float(storage.call("reserve_outgoing", liquid_container_id, "water", requested_liters, \
			_owner_authorization(actor))) if storage != null else 0.0


func release_outgoing_water_reservation(liters: float, actor: Node = null) -> float:
	var storage := BootstrapContext.service(LiquidStorageController.SERVICE_ID)
	return float(storage.call("release_outgoing", liquid_container_id, "water", liters, \
			_owner_authorization(actor))) if storage != null else 0.0


func draw_reserved_water_for_actor(requested_liters: float, actor: Node) -> Dictionary:
	if not _actor_can_access(actor):
		return {"drawn": 0.0}
	var storage := BootstrapContext.service(LiquidStorageController.SERVICE_ID)
	return {"drawn": float(storage.call("draw_reserved", liquid_container_id, "water", requested_liters, \
			_owner_authorization(actor))) if storage != null else 0.0}


func reserve_incoming_water_for_actor(requested_liters: float, actor: Node) -> float:
	if not _actor_can_access(actor):
		return 0.0
	var storage := BootstrapContext.service(LiquidStorageController.SERVICE_ID)
	return float(storage.call("reserve_incoming", liquid_container_id, "water", requested_liters, \
			_owner_authorization(actor))) if storage != null else 0.0


func release_incoming_water_reservation(liters: float, actor: Node = null) -> float:
	var storage := BootstrapContext.service(LiquidStorageController.SERVICE_ID)
	return float(storage.call("release_incoming", liquid_container_id, "water", liters, \
			_owner_authorization(actor))) if storage != null else 0.0


func deposit_reserved_water_for_actor(offered_liters: float, actor: Node) -> Dictionary:
	if not _actor_can_access(actor):
		return {"deposited": 0.0}
	var storage := BootstrapContext.service(LiquidStorageController.SERVICE_ID)
	return {"deposited": float(storage.call("deposit_reserved", liquid_container_id, "water", offered_liters, \
			_owner_authorization(actor))) if storage != null else 0.0}


func get_haul_endpoint_id() -> String:
	return liquid_container_id


func get_haul_resource_ids() -> PackedStringArray:
	return PackedStringArray() if assigned_liquid_id.is_empty() else PackedStringArray([assigned_liquid_id])


func get_haul_available(resource_id: String) -> float:
	return available_liquid(resource_id)


func get_haul_free_capacity(resource_id: String) -> float:
	return free_capacity_for_liquid(resource_id)


func get_haul_transfer_capacity(resource_id: String, actor: Node) -> float:
	return LIQUID_HAUL_CARRIER.free_capacity(actor, resource_id)


func get_carried_haul_amount(resource_id: String, actor: Node) -> float:
	return LIQUID_HAUL_CARRIER.amount(actor, resource_id)


func reserve_haul_outgoing(resource_id: String, requested: float, actor: Node) -> float:
	if not _actor_can_access(actor):
		return 0.0
	var storage := BootstrapContext.service(LiquidStorageController.SERVICE_ID)
	return float(storage.call("reserve_outgoing", liquid_container_id, resource_id, requested, \
			_owner_authorization(actor))) if storage != null else 0.0


func release_haul_outgoing(resource_id: String, amount: float, actor: Node = null) -> float:
	var storage := BootstrapContext.service(LiquidStorageController.SERVICE_ID)
	return float(storage.call("release_outgoing", liquid_container_id, resource_id, amount, \
			_owner_authorization(actor))) if storage != null else 0.0


func reserve_haul_incoming(resource_id: String, requested: float, actor: Node) -> float:
	if not _actor_can_access(actor):
		return 0.0
	var storage := BootstrapContext.service(LiquidStorageController.SERVICE_ID)
	return float(storage.call("reserve_incoming", liquid_container_id, resource_id, requested, \
			_owner_authorization(actor))) if storage != null else 0.0


func release_haul_incoming(resource_id: String, amount: float, actor: Node = null) -> float:
	var storage := BootstrapContext.service(LiquidStorageController.SERVICE_ID)
	if storage == null:
		return 0.0
	if actor == null:
		return float(storage.call("release_incoming_system", liquid_container_id, resource_id, amount))
	return float(storage.call("release_incoming", liquid_container_id, resource_id, amount, _owner_authorization(actor)))


func load_reserved_haul(resource_id: String, requested: float, actor: Node) -> float:
	if not _actor_can_access(actor):
		return 0.0
	var before := LIQUID_HAUL_CARRIER.amount(actor, resource_id)
	var offered := minf(maxf(0.0, requested), LIQUID_HAUL_CARRIER.free_capacity(actor, resource_id))
	if offered <= 0.0 or not LIQUID_HAUL_CARRIER.set_amount(actor, resource_id, before + offered, false):
		return 0.0
	var storage := BootstrapContext.service(LiquidStorageController.SERVICE_ID)
	var drawn := float(storage.call("draw_reserved", liquid_container_id, resource_id, offered, \
			_owner_authorization(actor))) if storage != null else 0.0
	LIQUID_HAUL_CARRIER.set_amount(actor, resource_id, before + drawn)
	return drawn


func unload_reserved_haul(resource_id: String, requested: float, actor: Node) -> float:
	if not _actor_can_access(actor):
		return 0.0
	var before := LIQUID_HAUL_CARRIER.amount(actor, resource_id)
	var offered := minf(maxf(0.0, requested), before)
	if offered <= 0.0 or not LIQUID_HAUL_CARRIER.set_amount(actor, resource_id, before - offered, false):
		return 0.0
	var storage := BootstrapContext.service(LiquidStorageController.SERVICE_ID)
	var deposited := float(storage.call("deposit_reserved", liquid_container_id, resource_id, offered, \
			_owner_authorization(actor))) if storage != null else 0.0
	LIQUID_HAUL_CARRIER.set_amount(actor, resource_id, before - deposited)
	return deposited


func get_owner_faction_name() -> String:
	return owner_faction_name


func register_interactor(actor: Node) -> void:
	if actor != null:
		_pending_actor_ids[actor.get_instance_id()] = true
		_refill.register(self, actor)


func release_interactor(actor: Node) -> void:
	if actor != null:
		_pending_actor_ids.erase(actor.get_instance_id())
		_refill.release(actor)


func resolve_interaction(actor: Node) -> bool:
	if actor == null or not _pending_actor_ids.has(actor.get_instance_id()):
		return false
	_pending_actor_ids.erase(actor.get_instance_id())
	return false # Liquid refills have no inventory-pair surface.


func get_interaction_position(_actor: Node) -> Vector3:
	var point := global_position + global_basis.z.normalized() * interaction_distance
	if Engine.is_editor_hint() or not is_inside_tree():
		return point
	var map := get_world_3d().navigation_map
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return point
	return NavigationServer3D.map_get_closest_point(map, point)


func remove_from_simulation() -> bool:
	var storage := BootstrapContext.service(LiquidStorageController.SERVICE_ID)
	return bool(storage.call("remove_container", liquid_container_id)) if storage != null else false


func sync_durable_context() -> void:
	if Engine.is_editor_hint():
		return
	_inherit_facility_context()
	_bind_state()
	_bind_haul_provider()


func _bind_state() -> void:
	if Engine.is_editor_hint() or liquid_container_id.strip_edges().is_empty():
		return
	var storage := BootstrapContext.service(LiquidStorageController.SERVICE_ID)
	if storage == null and _bind_attempts < 8:
		_bind_attempts += 1
		call_deferred("_bind_state")
		return
	if storage != null:
		storage.call("bind_liquid_container", self)


func _bind_haul_provider() -> void:
	if Engine.is_editor_hint():
		return
	var hauling := BootstrapContext.service(&"haul")
	if hauling != null and hauling.has_method("register_endpoint"):
		hauling.call("register_endpoint", self)


func _inherit_facility_context() -> void:
	var current := get_parent()
	while current != null:
		if current.has_method("get_facility_id"):
			var inherited_facility_id := str(current.call("get_facility_id")).strip_edges()
			if not inherited_facility_id.is_empty():
				facility_id = inherited_facility_id
				if liquid_container_id.strip_edges().is_empty() or liquid_container_id == "tank":
					liquid_container_id = "%s.tank" % inherited_facility_id
		if current.has_method("get_property_owner_faction"):
			owner_faction_name = str(current.call("get_property_owner_faction")).strip_edges()
		if current.has_method("get_settlement_id"):
			var inherited_settlement := str(current.call("get_settlement_id")).strip_edges()
			if not inherited_settlement.is_empty():
				settlement_id = inherited_settlement
		if settlement_id.is_empty() and current.has_method("_effective_settlement_id"):
			settlement_id = str(current.call("_effective_settlement_id")).strip_edges()
		current = current.get_parent()


func _actor_can_access(actor: Node) -> bool:
	if actor == null or owner_faction_name.strip_edges().is_empty():
		return false
	if actor.has_method("is_authorized_for_owner"):
		return bool(actor.call("is_authorized_for_owner", null, owner_faction_name))
	return str(actor.get("faction_name")) == owner_faction_name


func _owner_authorization(actor: Node) -> Dictionary:
	if not _actor_can_access(actor):
		return {}
	return {
		"liquid_container_id": liquid_container_id,
		"owner_faction_name": owner_faction_name,
		"actor_faction_name": str(actor.get("faction_name")).strip_edges(),
		"owner_access_approved": true,
		"theft_approved": false,
	}
