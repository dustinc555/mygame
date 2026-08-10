extends StaticBody3D

class_name FarmWaterSource

@export var source_id := "water_source"
@export var renewable := true
@export_range(0.0, 100000.0, 0.1) var capacity := 200.0
@export_range(0.0, 100000.0, 0.1) var current_water := 200.0
@export_range(0.0, 1000.0, 0.1) var recharge_per_world_hour := 0.0

var _gecs: Node
var _farm: Node
var _bind_attempts := 0
var _status_label: Label3D
var _bar_fill: MeshInstance3D


func _ready() -> void:
	add_to_group("farm_water_source")
	if not has_node("CollisionShape3D"):
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.2, 1.0, 1.2)
		collision.shape = shape
		collision.position.y = 0.5
		add_child(collision)
	_build_status_visual()
	call_deferred("_bind_durable_state")


func available_water() -> float:
	return INF if renewable else maxf(0.0, current_water)


func draw_water(requested: float) -> float:
	var amount := maxf(0.0, requested)
	if _farm == null or not _farm.has_method("draw_water_source"):
		return 0.0
	var drawn := float(_farm.draw_water_source(source_id, amount))
	_reload_durable_state()
	return drawn


func get_world_context_actions(_actor: Node = null) -> Array:
	return [{"key": "water_source_status", "label": "Water: Renewable" if renewable else "Water: %.1f / %.1f" % [current_water, capacity]}]


func perform_world_context_action(_key: String, _actors: Array = []) -> String:
	return "Renewable water source" if renewable else "%.1f / %.1f water remaining" % [current_water, capacity]


func _bind_durable_state() -> void:
	var context := BootstrapContext.active
	if context == null:
		_bind_attempts += 1
		if _bind_attempts < 50 and is_inside_tree():
			get_tree().create_timer(0.1).timeout.connect(_bind_durable_state)
		else:
			_update_status_visual()
		return
	_gecs = context.get_optional(&"gecs_world")
	_farm = context.get_optional(&"farming")
	if _farm == null or not _farm.has_method("register_water_source"):
		push_error("FarmWaterSource '%s' requires the farming controller" % source_id)
		return
	if source_id.strip_edges().is_empty():
		push_error("FarmWaterSource requires a stable source_id")
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
	renewable = bool(state.get("renewable", renewable))
	recharge_per_world_hour = float(state.get("recharge_per_world_minute", recharge_per_world_hour / 60.0)) * 60.0
	_update_status_visual()


func _build_status_visual() -> void:
	_status_label = Label3D.new()
	_status_label.position = Vector3(0, 1.55, 0)
	_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status_label.font_size = 42
	_status_label.outline_size = 8
	_status_label.modulate = Color(0.75, 0.9, 1.0)
	add_child(_status_label)
	var back := MeshInstance3D.new()
	var back_mesh := BoxMesh.new()
	back_mesh.size = Vector3(1.02, 0.12, 0.025)
	back.mesh = back_mesh
	back.position = Vector3(0, 1.32, 0)
	back.material_override = _material(Color(0.06, 0.08, 0.1))
	add_child(back)
	_bar_fill = MeshInstance3D.new()
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(1.0, 0.08, 0.035)
	_bar_fill.mesh = fill_mesh
	_bar_fill.position = Vector3(0, 1.32, -0.02)
	_bar_fill.material_override = _material(Color(0.1, 0.5, 1.0))
	add_child(_bar_fill)


func _update_status_visual() -> void:
	if _status_label == null or _bar_fill == null:
		return
	_status_label.text = "Renewable" if renewable else "%.0f / %.0f" % [current_water, capacity]
	var ratio := 1.0 if renewable else clampf(current_water / maxf(0.001, capacity), 0.0, 1.0)
	_bar_fill.scale.x = ratio
	_bar_fill.position.x = -0.5 * (1.0 - ratio)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
