extends Node

class_name WorldActorProjectionController

const WORLD_ACTOR_PROJECTION_SCRIPT := preload("res://scripts/projection/world_actor_projection.gd")
const HUMANOID_BODY_PROJECTION_SCRIPT := preload("res://scripts/projection/humanoid_body_projection.gd")
const PLACEHOLDER_BODY_PROJECTION_SCRIPT := preload("res://scripts/projection/placeholder_body_projection.gd")

@export var auto_project := true
@export_range(0.05, 5.0, 0.05) var projection_update_interval_seconds := 0.25
@export var projection_root_name := "WorldActorProjections"
@export var max_projected_actor_count := 0
@export var performance_logging_enabled := false
@export_range(0.1, 10.0, 0.1) var performance_log_interval_seconds := 1.0
@export_range(0.0, 50000.0, 100.0) var performance_log_threshold_usec := 1000.0
@export var combat_locomotion_projection_enabled := false
@export_range(0.1, 10.0, 0.1) var combat_locomotion_speed := 2.35
@export_range(0.25, 4.0, 0.05) var combat_local_avoidance_radius := 0.85
@export_range(1, 12, 1) var combat_local_avoidance_max_neighbors := 6
@export_range(0.5, 8.0, 0.1) var combat_local_avoidance_bin_size := 2.0
@export_range(0.0, 2.0, 0.05) var combat_local_avoidance_push_fraction := 0.35

var root_scene: Node
var _projection_root: Node3D
var _projection_by_actor_id: Dictionary = {}
var _initialized := false
var _update_elapsed := 0.0
var _unsupported_projection_kinds: Dictionary = {}
var _equipment_slots_cache_by_actor_id: Dictionary = {}
var _equipment_slots_cache_dirty := true
var _equipment_signal_bridge: Node
var _perf_log_next_msec_by_label: Dictionary = {}
var _last_projection_metrics: Dictionary = {}
var _combat_locomotion_display_position_by_actor_id: Dictionary = {}
var _combat_locomotion_last_update_msec := 0
var _combat_locomotion_last_metrics: Dictionary = {}


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	_initialized = false
	_try_initialize()


func _ready() -> void:
	add_to_group("world_actor_projection_controller")


func _exit_tree() -> void:
	_disconnect_equipment_cache_signal()


func _process(delta: float) -> void:
	if not auto_project or not _initialized:
		return
	_update_elapsed += delta
	if _update_elapsed < projection_update_interval_seconds:
		return
	_update_elapsed = 0.0
	sync_projections()


func sync_projections() -> void:
	var started_at_usec := Time.get_ticks_usec() if performance_logging_enabled else 0
	if not _try_initialize():
		return
	var bridge := _get_gecs_world()
	if bridge == null:
		return
	var records := _get_population_records_core(bridge)
	var equipment_by_actor := _equipment_slots_by_actor(bridge)
	var combat_display_records := _combat_locomotion_display_records(records) if combat_locomotion_projection_enabled else {}
	var expected_actor_ids := {}
	var metrics := _projection_metrics_base(records.size())
	for actor_id_value in _projection_record_keys(records):
		var record_value = records[actor_id_value]
		if not (record_value is Dictionary):
			continue
		var record: Dictionary = record_value
		var actor_id := str(record.get("actor_id", actor_id_value)).strip_edges()
		if actor_id.is_empty():
			continue
		var projection_kind := _projection_kind_for_record(record)
		if not can_project_kind(projection_kind):
			_note_unsupported_kind(projection_kind)
			metrics["unsupported_projection_count"] = int(metrics.get("unsupported_projection_count", 0)) + 1
			_remove_projection(actor_id)
			continue
		metrics["eligible_projection_count"] = int(metrics.get("eligible_projection_count", 0)) + 1
		if _projection_cap_reached(expected_actor_ids.size()):
			metrics["skipped_projection_count"] = int(metrics.get("skipped_projection_count", 0)) + 1
			continue
		expected_actor_ids[actor_id] = true
		var projection_record: Dictionary = combat_display_records.get(actor_id, record) if combat_display_records.has(actor_id) else record
		project_record_snapshot(projection_record, equipment_by_actor.get(actor_id, {}))
	_remove_stale_projections(expected_actor_ids)
	_remove_stale_combat_locomotion_state(expected_actor_ids)
	metrics["projected_actor_count"] = _projection_by_actor_id.size()
	metrics["realized_actor_count"] = _projection_by_actor_id.size()
	metrics["visible_actor_count"] = _visible_projection_count()
	metrics["projection_counts_by_kind"] = get_projection_counts_by_kind()
	metrics.merge(_combat_locomotion_report_metrics(), true)
	_last_projection_metrics = metrics
	_log_perf_duration("projection.sync_projections", started_at_usec, {"records": records.size(), "projections": _projection_by_actor_id.size(), "skipped": int(metrics.get("skipped_projection_count", 0))})


func project_record_snapshot(record: Dictionary, equipment_slots: Dictionary = {}, combat_state: Dictionary = {}) -> Node:
	if not _try_initialize() or record.is_empty():
		return null
	var actor_id := str(record.get("actor_id", record.get("stable_id", ""))).strip_edges()
	if actor_id.is_empty():
		return null
	var projection_kind := _projection_kind_for_record(record)
	if not can_project_kind(projection_kind):
		_note_unsupported_kind(projection_kind)
		return null
	var projection := _get_or_create_projection(actor_id, projection_kind)
	if projection == null:
		return null
	projection.apply_projection_snapshot(record, equipment_slots, combat_state)
	return projection


func can_project_kind(projection_kind: String) -> bool:
	return _body_script_for_kind(projection_kind) != null


func get_projection_for_actor(actor_id: String) -> Node:
	var projection = _projection_by_actor_id.get(actor_id)
	return projection as Node if projection != null and is_instance_valid(projection) else null


func get_projection_count() -> int:
	return _projection_by_actor_id.size()


func get_projection_counts_by_kind() -> Dictionary:
	var counts := {}
	for projection in _projection_by_actor_id.values():
		if projection == null or not is_instance_valid(projection):
			continue
		var kind := str((projection as Node).get("projection_kind"))
		counts[kind] = int(counts.get(kind, 0)) + 1
	return counts


func get_unsupported_projection_kinds() -> Dictionary:
	return _unsupported_projection_kinds.duplicate()


func get_projection_performance_metrics() -> Dictionary:
	var metrics := _last_projection_metrics.duplicate(true)
	metrics["projected_actor_count"] = _projection_by_actor_id.size()
	metrics["realized_actor_count"] = _projection_by_actor_id.size()
	metrics["visible_actor_count"] = _visible_projection_count()
	metrics["max_projected_actor_count"] = maxi(0, max_projected_actor_count)
	metrics["projection_cap_active"] = max_projected_actor_count > 0
	metrics["projection_counts_by_kind"] = get_projection_counts_by_kind()
	metrics.merge(_combat_locomotion_report_metrics(), true)
	return metrics


func _combat_locomotion_display_records(records: Dictionary) -> Dictionary:
	var elapsed_seconds := _combat_locomotion_elapsed_seconds()
	var states: Array[Dictionary] = []
	for actor_id_value in _projection_record_keys(records):
		var record_value = records[actor_id_value]
		if not (record_value is Dictionary):
			continue
		var record: Dictionary = record_value
		var actor_id := str(record.get("actor_id", actor_id_value)).strip_edges()
		if actor_id.is_empty() or not _record_has_projection_goal(record):
			continue
		var raw_position := _record_world_position(record)
		var current_position := _combat_locomotion_current_position(actor_id, raw_position)
		var goal_position := _record_projection_goal_position(record, raw_position)
		var speed := maxf(float(record.get("projection_locomotion_speed", combat_locomotion_speed)), 0.0)
		var proposed_position := _combat_locomotion_step_position(current_position, goal_position, speed, elapsed_seconds)
		states.append({
			"actor_id": actor_id,
			"record": record,
			"current_position": current_position,
			"proposed_position": proposed_position,
			"goal_position": goal_position,
			"speed": speed,
		})
	var bins := _combat_locomotion_bins(states)
	var stats := {
		"pair_checks": 0,
		"overlap_violations": 0,
		"pass_through_violations": 0,
	}
	var display_records := {}
	for state_index in range(states.size()):
		var state: Dictionary = states[state_index]
		var record: Dictionary = state.get("record", {})
		var actor_id := str(state.get("actor_id", ""))
		var current_position: Vector3 = state.get("current_position", Vector3.ZERO)
		var adjusted_position := _combat_locomotion_adjusted_position(state, state_index, states, bins, stats)
		adjusted_position = _combat_locomotion_apply_bounds(adjusted_position, record)
		adjusted_position = _combat_locomotion_clamp_step(current_position, adjusted_position, float(state.get("speed", combat_locomotion_speed)), elapsed_seconds)
		adjusted_position = _combat_locomotion_apply_bounds(adjusted_position, record)
		if _combat_locomotion_violates_bounds(adjusted_position, record):
			stats["pass_through_violations"] = int(stats.get("pass_through_violations", 0)) + 1
		_combat_locomotion_display_position_by_actor_id[actor_id] = adjusted_position
		var display_record := record.duplicate(true)
		display_record["last_world_position"] = adjusted_position
		display_record["last_world_position_initialized"] = true
		_apply_combat_locomotion_animation(display_record, current_position, adjusted_position, float(state.get("speed", combat_locomotion_speed)), elapsed_seconds)
		display_records[actor_id] = display_record
	_combat_locomotion_last_metrics = {
		"combat_locomotion_enabled": true,
		"combat_locomotion_actor_count": states.size(),
		"combat_locomotion_pair_checks": int(stats.get("pair_checks", 0)),
		"combat_locomotion_max_pair_checks": states.size() * maxi(1, combat_local_avoidance_max_neighbors),
		"combat_locomotion_overlap_violations": int(stats.get("overlap_violations", 0)),
		"combat_locomotion_pass_through_violations": int(stats.get("pass_through_violations", 0)),
	}
	return display_records


func _combat_locomotion_elapsed_seconds() -> float:
	var now_msec := Time.get_ticks_msec()
	if _combat_locomotion_last_update_msec <= 0:
		_combat_locomotion_last_update_msec = now_msec
		return projection_update_interval_seconds
	var elapsed := clampf(float(now_msec - _combat_locomotion_last_update_msec) / 1000.0, 0.0, 0.25)
	_combat_locomotion_last_update_msec = now_msec
	return elapsed


func _record_has_projection_goal(record: Dictionary) -> bool:
	return record.get("projection_goal_position", null) is Vector3


func _record_projection_goal_position(record: Dictionary, fallback: Vector3) -> Vector3:
	var value = record.get("projection_goal_position", fallback)
	return value if value is Vector3 else fallback


func _combat_locomotion_current_position(actor_id: String, raw_position: Vector3) -> Vector3:
	var current = _combat_locomotion_display_position_by_actor_id.get(actor_id, raw_position)
	return current if current is Vector3 else raw_position


func _combat_locomotion_step_position(current_position: Vector3, goal_position: Vector3, speed: float, elapsed_seconds: float) -> Vector3:
	var to_goal := goal_position - current_position
	to_goal.y = 0.0
	var distance := to_goal.length()
	if distance <= 0.03 or speed <= 0.0 or elapsed_seconds <= 0.0:
		return current_position
	var step_distance := minf(speed * elapsed_seconds, distance)
	return current_position + to_goal.normalized() * step_distance


func _combat_locomotion_bins(states: Array[Dictionary]) -> Dictionary:
	var bins := {}
	for state_index in range(states.size()):
		var state: Dictionary = states[state_index]
		var position: Vector3 = state.get("proposed_position", Vector3.ZERO)
		var key := _combat_locomotion_bin_key(_combat_locomotion_bin_coords(position))
		if not bins.has(key):
			bins[key] = []
		(bins[key] as Array).append(state_index)
	return bins


func _combat_locomotion_adjusted_position(state: Dictionary, state_index: int, states: Array[Dictionary], bins: Dictionary, stats: Dictionary) -> Vector3:
	var proposed_position: Vector3 = state.get("proposed_position", Vector3.ZERO)
	var coords := _combat_locomotion_bin_coords(proposed_position)
	var max_neighbors := maxi(1, combat_local_avoidance_max_neighbors)
	var checked_neighbors := 0
	var separation := Vector3.ZERO
	for x_offset in range(-1, 2):
		if checked_neighbors >= max_neighbors:
			break
		for z_offset in range(-1, 2):
			if checked_neighbors >= max_neighbors:
				break
			var key := _combat_locomotion_bin_key(Vector2i(coords.x + x_offset, coords.y + z_offset))
			var neighbor_indices = bins.get(key, [])
			if not (neighbor_indices is Array):
				continue
			for neighbor_index in neighbor_indices:
				if checked_neighbors >= max_neighbors:
					break
				var other_index := int(neighbor_index)
				if other_index == state_index or other_index < 0 or other_index >= states.size():
					continue
				var other_state: Dictionary = states[other_index]
				var other_position: Vector3 = other_state.get("proposed_position", Vector3.ZERO)
				var delta := proposed_position - other_position
				delta.y = 0.0
				var distance := delta.length()
				checked_neighbors += 1
				stats["pair_checks"] = int(stats.get("pair_checks", 0)) + 1
				if distance < combat_local_avoidance_radius * 0.75:
					stats["overlap_violations"] = int(stats.get("overlap_violations", 0)) + 1
				if distance >= combat_local_avoidance_radius:
					continue
				var away := delta.normalized() if distance > 0.001 else _combat_locomotion_fallback_away(state_index, other_index)
				separation += away * ((combat_local_avoidance_radius - maxf(distance, 0.001)) / combat_local_avoidance_radius)
	if separation.length_squared() <= 0.000001:
		return proposed_position
	var max_push := combat_local_avoidance_radius * maxf(combat_local_avoidance_push_fraction, 0.0)
	return proposed_position + separation.normalized() * minf(separation.length() * combat_local_avoidance_radius, max_push)


func _combat_locomotion_clamp_step(current_position: Vector3, target_position: Vector3, speed: float, elapsed_seconds: float) -> Vector3:
	if elapsed_seconds <= 0.0:
		return target_position
	var delta := target_position - current_position
	delta.y = 0.0
	var max_step := speed * elapsed_seconds + combat_local_avoidance_radius * maxf(combat_local_avoidance_push_fraction, 0.0) + 0.001
	if delta.length() <= max_step:
		return target_position
	return current_position + delta.normalized() * max_step


func _combat_locomotion_apply_bounds(position: Vector3, record: Dictionary) -> Vector3:
	var bounds: Dictionary = record.get("projection_locomotion_bounds", {}) if record.get("projection_locomotion_bounds", {}) is Dictionary else {}
	var result := position
	if bounds.has("min_x"):
		result.x = maxf(result.x, float(bounds.get("min_x", result.x)))
	if bounds.has("max_x"):
		result.x = minf(result.x, float(bounds.get("max_x", result.x)))
	if bounds.has("min_z"):
		result.z = maxf(result.z, float(bounds.get("min_z", result.z)))
	if bounds.has("max_z"):
		result.z = minf(result.z, float(bounds.get("max_z", result.z)))
	return result


func _combat_locomotion_violates_bounds(position: Vector3, record: Dictionary) -> bool:
	var bounds: Dictionary = record.get("projection_locomotion_bounds", {}) if record.get("projection_locomotion_bounds", {}) is Dictionary else {}
	if bounds.has("min_x") and position.x < float(bounds.get("min_x", position.x)) - 0.001:
		return true
	if bounds.has("max_x") and position.x > float(bounds.get("max_x", position.x)) + 0.001:
		return true
	if bounds.has("min_z") and position.z < float(bounds.get("min_z", position.z)) - 0.001:
		return true
	if bounds.has("max_z") and position.z > float(bounds.get("max_z", position.z)) + 0.001:
		return true
	return false


func _apply_combat_locomotion_animation(record: Dictionary, previous_position: Vector3, next_position: Vector3, speed: float, elapsed_seconds: float) -> void:
	var movement := next_position - previous_position
	movement.y = 0.0
	var horizontal_speed := movement.length() / maxf(elapsed_seconds, 0.001)
	if movement.length() > 0.01:
		record["world_facing_yaw"] = atan2(movement.x, movement.z)
		record["world_facing_yaw_initialized"] = true
	record["locomotion_state"] = {
		"animation_state": "walk" if horizontal_speed > 0.05 else "idle",
		"speed": speed,
		"horizontal_speed": horizontal_speed,
	}


func _combat_locomotion_bin_coords(position: Vector3) -> Vector2i:
	var safe_size := maxf(combat_local_avoidance_bin_size, 0.5)
	return Vector2i(floori(position.x / safe_size), floori(position.z / safe_size))


func _combat_locomotion_bin_key(coords: Vector2i) -> String:
	return "%d,%d" % [coords.x, coords.y]


func _combat_locomotion_fallback_away(first_index: int, second_index: int) -> Vector3:
	var angle := TAU * float((first_index * 31 + second_index * 17) % 64) / 64.0
	return Vector3(cos(angle), 0.0, sin(angle)).normalized()


func _remove_stale_combat_locomotion_state(expected_actor_ids: Dictionary) -> void:
	for actor_id_value in _combat_locomotion_display_position_by_actor_id.keys():
		var actor_id := str(actor_id_value)
		if not expected_actor_ids.has(actor_id):
			_combat_locomotion_display_position_by_actor_id.erase(actor_id)


func _combat_locomotion_report_metrics() -> Dictionary:
	if not combat_locomotion_projection_enabled:
		return {
			"combat_locomotion_enabled": false,
			"combat_locomotion_actor_count": 0,
			"combat_locomotion_pair_checks": 0,
			"combat_locomotion_max_pair_checks": 0,
			"combat_locomotion_overlap_violations": 0,
			"combat_locomotion_pass_through_violations": 0,
		}
	if _combat_locomotion_last_metrics.is_empty():
		return {
			"combat_locomotion_enabled": true,
			"combat_locomotion_actor_count": 0,
			"combat_locomotion_pair_checks": 0,
			"combat_locomotion_max_pair_checks": 0,
			"combat_locomotion_overlap_violations": 0,
			"combat_locomotion_pass_through_violations": 0,
		}
	return _combat_locomotion_last_metrics.duplicate(true)


func _try_initialize() -> bool:
	if _initialized:
		return true
	if root_scene == null:
		root_scene = get_parent()
	if root_scene == null or not is_inside_tree():
		return false
	_projection_root = root_scene.get_node_or_null(projection_root_name) as Node3D
	if _projection_root == null:
		_projection_root = Node3D.new()
		_projection_root.name = projection_root_name
		root_scene.add_child(_projection_root)
	_initialized = true
	return true


func _get_or_create_projection(actor_id: String, projection_kind: String) -> Node:
	var existing := get_projection_for_actor(actor_id)
	if existing != null and str(existing.get("projection_kind")) == projection_kind:
		return existing
	_remove_projection(actor_id)
	var body_script := _body_script_for_kind(projection_kind)
	if body_script == null:
		return null
	var projection := WORLD_ACTOR_PROJECTION_SCRIPT.new() as Node
	_projection_root.add_child(projection)
	projection.setup(actor_id, projection_kind, body_script)
	_projection_by_actor_id[actor_id] = projection
	return projection


func _remove_stale_projections(expected_actor_ids: Dictionary) -> void:
	var existing_ids := _projection_by_actor_id.keys()
	for actor_id_value in existing_ids:
		var actor_id := str(actor_id_value)
		if not expected_actor_ids.has(actor_id):
			_remove_projection(actor_id)


func _remove_projection(actor_id: String) -> void:
	var projection = _projection_by_actor_id.get(actor_id)
	if projection != null and is_instance_valid(projection):
		(projection as Node).queue_free()
	_projection_by_actor_id.erase(actor_id)
	_combat_locomotion_display_position_by_actor_id.erase(actor_id)


func _equipment_slots_by_actor(bridge: Node) -> Dictionary:
	_bind_equipment_cache_signal(bridge)
	if _equipment_slots_cache_dirty:
		_equipment_slots_cache_by_actor_id = _load_equipment_slots_by_actor(bridge)
		_equipment_slots_cache_dirty = false
	return _equipment_slots_cache_by_actor_id


func _load_equipment_slots_by_actor(bridge: Node) -> Dictionary:
	var result := {}
	if bridge == null or not bridge.has_method("get_equipment_slots"):
		return result
	for slot in bridge.call("get_equipment_slots"):
		if not (slot is Dictionary):
			continue
		var actor_id := str((slot as Dictionary).get("actor_id", "")).strip_edges()
		var slot_name := str((slot as Dictionary).get("slot_name", "")).strip_edges()
		var item_path := str((slot as Dictionary).get("item_definition_path", "")).strip_edges()
		if actor_id.is_empty() or slot_name.is_empty() or item_path.is_empty():
			continue
		var actor_slots: Dictionary = result.get(actor_id, {})
		actor_slots[slot_name] = item_path
		result[actor_id] = actor_slots
	return result


func _bind_equipment_cache_signal(bridge: Node) -> void:
	if bridge == _equipment_signal_bridge:
		return
	_disconnect_equipment_cache_signal()
	if bridge == null or not bridge.has_signal("inventory_state_changed"):
		return
	var callable := Callable(self, "_on_equipment_cache_changed")
	if bridge.is_connected("inventory_state_changed", callable):
		_equipment_signal_bridge = bridge
		return
	bridge.connect("inventory_state_changed", callable)
	_equipment_signal_bridge = bridge


func _disconnect_equipment_cache_signal() -> void:
	if _equipment_signal_bridge == null or not is_instance_valid(_equipment_signal_bridge):
		_equipment_signal_bridge = null
		return
	var callable := Callable(self, "_on_equipment_cache_changed")
	if _equipment_signal_bridge.has_signal("inventory_state_changed") and _equipment_signal_bridge.is_connected("inventory_state_changed", callable):
		_equipment_signal_bridge.disconnect("inventory_state_changed", callable)
	_equipment_signal_bridge = null


func _on_equipment_cache_changed(_result: Dictionary = {}) -> void:
	_equipment_slots_cache_dirty = true


func _projection_kind_for_record(record: Dictionary) -> String:
	var explicit_kind := str(record.get("projection_kind", "")).strip_edges()
	if not explicit_kind.is_empty():
		return explicit_kind
	var appearance = record.get("appearance", {})
	if appearance is Dictionary and (not str((appearance as Dictionary).get("body_archetype", "")).is_empty() or int((appearance as Dictionary).get("visual_body_type", 0)) > 0):
		return "humanoid"
	return ""


func _body_script_for_kind(projection_kind: String) -> Script:
	match projection_kind:
		"humanoid":
			return HUMANOID_BODY_PROJECTION_SCRIPT
		"animal_placeholder", "robot_placeholder":
			return PLACEHOLDER_BODY_PROJECTION_SCRIPT
	return null


func _projection_metrics_base(source_record_count: int) -> Dictionary:
	return {
		"source_record_count": source_record_count,
		"eligible_projection_count": 0,
		"projected_actor_count": _projection_by_actor_id.size(),
		"realized_actor_count": _projection_by_actor_id.size(),
		"visible_actor_count": _visible_projection_count(),
		"max_projected_actor_count": maxi(0, max_projected_actor_count),
		"projection_cap_active": max_projected_actor_count > 0,
		"skipped_projection_count": 0,
		"unsupported_projection_count": 0,
		"projection_counts_by_kind": get_projection_counts_by_kind(),
	}


func _projection_cap_reached(current_expected_count: int) -> bool:
	return max_projected_actor_count > 0 and current_expected_count >= max_projected_actor_count


func _projection_record_keys(records: Dictionary) -> Array:
	if max_projected_actor_count <= 0:
		return records.keys()
	return _sorted_record_keys(records)


func _sorted_record_keys(records: Dictionary) -> Array:
	var keys := records.keys()
	keys.sort_custom(func(first, second) -> bool:
		return _record_sort_actor_id(records, first) < _record_sort_actor_id(records, second)
	)
	return keys


func _record_sort_actor_id(records: Dictionary, key) -> String:
	var record_value = records.get(key)
	if record_value is Dictionary:
		return str((record_value as Dictionary).get("actor_id", key)).strip_edges()
	return str(key).strip_edges()


func _record_world_position(record: Dictionary) -> Vector3:
	var record_position = record.get("last_world_position", record.get("world_position", Vector3.ZERO))
	return record_position if record_position is Vector3 else Vector3.ZERO


func _visible_projection_count() -> int:
	var count := 0
	for projection in _projection_by_actor_id.values():
		if projection != null and is_instance_valid(projection) and bool((projection as Node).get("visible")):
			count += 1
	return count


func _note_unsupported_kind(projection_kind: String) -> void:
	var key := projection_kind if not projection_kind.is_empty() else "<empty>"
	_unsupported_projection_kinds[key] = int(_unsupported_projection_kinds.get(key, 0)) + 1


func _get_gecs_world() -> Node:
	if not is_inside_tree():
		return null
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("GecsWorldController")
		if local != null:
			return local
	var existing := get_tree().get_first_node_in_group("gecs_world_controller")
	if existing != null and (parent_node == null or existing.get_parent() == parent_node):
		return existing
	return null


func _get_population_records_core(bridge: Node) -> Dictionary:
	if bridge.has_method("get_population_records_core"):
		var core_records = bridge.call("get_population_records_core")
		return core_records if core_records is Dictionary else {}
	if bridge.has_method("get_population_records"):
		var records = bridge.call("get_population_records")
		return records if records is Dictionary else {}
	return {}


func _log_perf_duration(label: String, started_at_usec: int, metadata: Dictionary = {}) -> void:
	if not performance_logging_enabled or started_at_usec <= 0:
		return
	var elapsed_usec := int(Time.get_ticks_usec() - started_at_usec)
	if float(elapsed_usec) < performance_log_threshold_usec:
		return
	var now_msec := Time.get_ticks_msec()
	var next_msec := int(_perf_log_next_msec_by_label.get(label, 0))
	if now_msec < next_msec:
		return
	_perf_log_next_msec_by_label[label] = now_msec + int(performance_log_interval_seconds * 1000.0)
	var suffix := ""
	for key in metadata.keys():
		suffix += " %s=%s" % [str(key), str(metadata[key])]
	print("PERF %s %.3fms%s" % [label, float(elapsed_usec) / 1000.0, suffix])
