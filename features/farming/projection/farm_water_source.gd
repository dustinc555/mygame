extends StaticBody3D

class_name FarmWaterSource

@export var display_name := "Water Barrels"
@export var source_id := "water_source"
@export var owner_faction_name := "Player"
@export var renewable := true
@export_range(0.0, 100000.0, 0.1) var capacity := 200.0
@export_range(0.0, 100000.0, 0.1) var current_water := 200.0
@export_range(0.0, 1000.0, 0.1) var recharge_per_world_hour := 0.0
@export_range(1, 1000, 1) var theft_value := 10
@export_range(0.0, 20.0, 0.1) var theft_noise_radius := 4.0
@export_range(0, 100, 1) var theft_difficulty := 25

var _gecs: Node
var _farm: Node
var _ownership: Node
var _bind_attempts := 0


func _ready() -> void:
	add_to_group("farm_water_source")
	if not has_node("CollisionShape3D"):
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.2, 1.0, 1.2)
		collision.shape = shape
		collision.position.y = 0.5
		add_child(collision)
	call_deferred("_bind_durable_state")


func available_water() -> float:
	return INF if renewable else maxf(0.0, current_water)


func draw_water_for_actor(requested: float, actor: Node) -> Dictionary:
	if actor == null:
		return {"drawn": 0.0, "message": "Select a worker first"}
	if requested <= 0.0 or available_water() <= 0.0:
		return {"drawn": 0.0, "message": "Water source is dry"}
	if _farm == null or not _farm.has_method("draw_water_source"):
		return {"drawn": 0.0, "message": "Water source is unavailable"}
	var owner_access_approved := _actor_can_take_without_stealing(actor)
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
	}
	var drawn := float(_farm.call("draw_water_source", source_id, requested, authorization))
	_reload_durable_state()
	return {
		"drawn": drawn,
		"message": "Water source is dry" if drawn <= 0.0 else "",
	}


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
	var context := BootstrapContext.active
	if context == null:
		_bind_attempts += 1
		if _bind_attempts < 50 and is_inside_tree():
			get_tree().create_timer(0.1).timeout.connect(_bind_durable_state)
		return
	_gecs = context.get_optional(&"gecs_world")
	_farm = context.get_optional(&"farming")
	_ownership = context.get_optional(&"ownership")
	if _farm == null or not _farm.has_method("register_water_source"):
		push_error("FarmWaterSource '%s' requires the farming controller" % source_id)
		return
	if source_id.strip_edges().is_empty():
		push_error("FarmWaterSource requires a stable source_id")
		return
	if owner_faction_name.strip_edges().is_empty():
		push_error("FarmWaterSource '%s' requires an owner faction" % source_id)
		return
	for source_value in get_tree().get_nodes_in_group("farm_water_source"):
		var source := source_value as Node
		if source != null and source != self and str(source.get("source_id")) == source_id:
			push_error("Duplicate FarmWaterSource source_id '%s'" % source_id)
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
		"source_id": source_id,
		"world_position": global_position,
		"owner_faction_name": owner_faction_name,
		"capacity": capacity,
		"current_water": current_water,
		"renewable": renewable,
		"recharge_per_world_minute": recharge_per_world_hour / 60.0,
		"last_processed_minute": now,
	})
	_apply_durable_state(saved)


func _on_world_reindexed() -> void:
	_reload_durable_state.call_deferred()


func _on_water_source_changed(changed_source_id: String, state: Dictionary) -> void:
	if changed_source_id == source_id:
		_apply_durable_state(state)


func _reload_durable_state() -> void:
	if _farm == null or not _farm.has_method("get_water_source"):
		return
	_apply_durable_state(_farm.get_water_source(source_id))


func _apply_durable_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	capacity = float(state.get("capacity", capacity))
	current_water = float(state.get("current_water", current_water))
	owner_faction_name = str(state.get("owner_faction_name", owner_faction_name))
	renewable = bool(state.get("renewable", renewable))
	recharge_per_world_hour = float(state.get("recharge_per_world_minute", recharge_per_world_hour / 60.0)) * 60.0


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


func _format_amount(value: float) -> String:
	return str(int(round(value))) if is_equal_approx(value, round(value)) else "%.1f" % value
