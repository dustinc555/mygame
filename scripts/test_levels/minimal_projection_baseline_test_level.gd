extends Node3D

class_name MinimalProjectionBaselineTestLevel

const BOOTSTRAP_PATH := NodePath("GameBootstrap")
const PROJECTION_ROOT_NAME := "WorldActorProjections"
const BOOTSTRAP_WAIT_FRAMES := 180
const UI_REFRESH_SECONDS := 0.25

@export var scenario_id := "projection_baseline_1v1"
@export_range(1, 128, 1) var side_a_count := 1
@export_range(1, 128, 1) var side_b_count := 1
@export_range(1, 16, 1) var formation_columns := 8
@export var side_separation := 7.0
@export var actor_spacing := 1.55
@export var auto_start := true

var _bootstrap: Node
var _gecs: Node
var _projection: Node
var _runner: Node
var _camera_rig: Node
var _ready_for_benchmark := false
var _setup_complete := false
var _last_projection_sync_ms := 0.0
var _average_projection_sync_ms := 0.0
var _projection_sync_sample_count := 0
var _fps_sum := 0.0
var _min_fps := INF
var _fps_frame_count := 0
var _fps_elapsed_seconds := 0.0
var _ui_elapsed := 0.0

var _ui_layer: CanvasLayer
var _status_label: Label
var _metrics_label: Label


func _ready() -> void:
	add_to_group("minimal_projection_baseline_test_level")
	_build_ui()
	call_deferred("_prepare_benchmark")


func _process(delta: float) -> void:
	if not _ready_for_benchmark:
		return
	_record_frame_sample(delta)
	_ui_elapsed += delta
	if _ui_elapsed >= UI_REFRESH_SECONDS:
		_ui_elapsed = 0.0
		_render_ui()


func get_benchmark_state() -> Dictionary:
	var projection_metrics := _projection_metrics()
	return {
		"ready": _ready_for_benchmark,
		"setup_complete": _setup_complete,
		"scenario_id": scenario_id,
		"scene_path": scene_file_path,
		"expected_actor_count": _expected_actor_count(),
		"projected_actor_count": int(projection_metrics.get("projected_actor_count", 0)),
		"visible_actor_count": int(projection_metrics.get("visible_actor_count", 0)),
		"projection_counts_by_kind": projection_metrics.get("projection_counts_by_kind", {}).duplicate(true) if projection_metrics.get("projection_counts_by_kind", {}) is Dictionary else {},
		"active_animation_count": _active_animation_count(),
		"average_fps": _average_fps(),
		"min_fps": _min_fps if _fps_frame_count > 0 else 0.0,
		"sample_frame_count": _fps_frame_count,
		"sample_elapsed_seconds": _fps_elapsed_seconds,
		"last_projection_sync_ms": _last_projection_sync_ms,
		"average_projection_sync_ms": _average_projection_sync_ms,
		"projection_sync_sample_count": _projection_sync_sample_count,
		"gecs_tick_ms": _gecs_tick_ms(),
		"battle_sim_included": false,
	}


func measure_projection_sync(sample_count := 5) -> Dictionary:
	if _projection == null or not _projection.has_method("sync_projections"):
		return {"samples": 0, "average_ms": 0.0, "last_ms": 0.0}
	var safe_count := maxi(1, sample_count)
	var total_ms := 0.0
	for _index in range(safe_count):
		var started_usec := Time.get_ticks_usec()
		_projection.call("sync_projections")
		_last_projection_sync_ms = float(Time.get_ticks_usec() - started_usec) / 1000.0
		total_ms += _last_projection_sync_ms
	_average_projection_sync_ms = total_ms / float(safe_count)
	_projection_sync_sample_count = safe_count
	return {"samples": safe_count, "average_ms": _average_projection_sync_ms, "last_ms": _last_projection_sync_ms}


func _prepare_benchmark() -> void:
	_set_status("Waiting for projection baseline systems...")
	for _frame in range(BOOTSTRAP_WAIT_FRAMES):
		await get_tree().process_frame
		if _bind_systems():
			if auto_start:
				_start_benchmark()
			return
	_set_status("Timed out waiting for GameBootstrap projection systems.")


func _bind_systems() -> bool:
	_bootstrap = get_node_or_null(BOOTSTRAP_PATH)
	if _bootstrap == null:
		return false
	_gecs = _bootstrap.get_node_or_null("GecsWorldController")
	_projection = _bootstrap.get_node_or_null("WorldActorProjectionController")
	_runner = _bootstrap.get_node_or_null("WorldMapCombatFixedTickRunner")
	_camera_rig = get_node_or_null("CameraRig")
	return _gecs != null and _projection != null


func _start_benchmark() -> void:
	if _setup_complete:
		return
	if _gecs.has_method("clear_population_records"):
		_gecs.call("clear_population_records")
	_seed_population_records()
	if _projection != null:
		_projection.set("auto_project", true)
		_projection.set("max_projected_actor_count", 0)
		_projection.set("projection_update_interval_seconds", 0.05)
	measure_projection_sync(3)
	if _camera_rig != null and _camera_rig.has_method("focus_world_position"):
		_camera_rig.call("focus_world_position", Vector3.ZERO)
	_setup_complete = true
	_ready_for_benchmark = true
	_set_status("Projection baseline ready: %s actors" % _expected_actor_count())
	_render_ui()


func _seed_population_records() -> void:
	var side_a_offset := -side_separation * 0.5
	var side_b_offset := side_separation * 0.5
	for index in range(side_a_count):
		_upsert_actor_record("a", index, side_a_offset, PI)
	for index in range(side_b_count):
		_upsert_actor_record("b", index, side_b_offset, 0.0)


func _upsert_actor_record(side_id: String, index: int, x_offset: float, facing_yaw: float) -> void:
	if _gecs == null or not _gecs.has_method("upsert_population_record_core"):
		return
	var actor_id := "projection_baseline.%s.%s.%03d" % [scenario_id, side_id, index + 1]
	_gecs.call("upsert_population_record_core", {
		"actor_id": actor_id,
		"stable_id": actor_id,
		"member_name": "%s %s%03d" % [scenario_id, side_id.to_upper(), index + 1],
		"faction_id": "baseline_%s" % side_id,
		"squad_name": "baseline_%s" % side_id,
		"role_id": "projection_baseline_actor",
		"projection_kind": "humanoid",
		"life_state": 0,
		"hp": 100.0,
		"max_hp": 100.0,
		"blood": 100.0,
		"max_blood": 100.0,
		"base_attack_damage": 1.0,
		"realization_state": "ledger",
		"ledger_activity_state": "projection_baseline",
		"last_world_position": _formation_position(index, x_offset),
		"last_world_position_initialized": true,
		"world_facing_yaw": facing_yaw,
		"world_facing_yaw_initialized": true,
		"locomotion_state": {"animation_state": "idle", "speed": 0.0, "horizontal_speed": 0.0},
		"important": true,
	})


func _formation_position(index: int, x_offset: float) -> Vector3:
	var side_count := _side_count_for_x(x_offset)
	var columns := maxi(1, mini(formation_columns, side_count))
	var row := int(index / columns)
	var column := index % columns
	var centered_column := float(column) - float(columns - 1) * 0.5
	var side_direction := -1.0 if x_offset < 0.0 else 1.0
	return Vector3(x_offset + side_direction * float(row) * actor_spacing, 0.0, centered_column * actor_spacing)


func _side_count_for_x(x_offset: float) -> int:
	return side_a_count if x_offset < 0.0 else side_b_count


func _record_frame_sample(delta: float) -> void:
	if delta <= 0.0:
		return
	var fps := 1.0 / delta
	_fps_sum += fps
	_min_fps = minf(_min_fps, fps)
	_fps_frame_count += 1
	_fps_elapsed_seconds += delta


func _average_fps() -> float:
	return _fps_sum / maxf(float(_fps_frame_count), 1.0)


func _projection_metrics() -> Dictionary:
	if _projection != null and _projection.has_method("get_projection_performance_metrics"):
		var metrics = _projection.call("get_projection_performance_metrics")
		return metrics if metrics is Dictionary else {}
	return {}


func _active_animation_count() -> int:
	var projection_root := get_node_or_null(PROJECTION_ROOT_NAME)
	if projection_root == null:
		return 0
	var count := 0
	for child in projection_root.get_children():
		if child == null or not child.has_method("get_projection_debug_state"):
			continue
		var debug_value = child.call("get_projection_debug_state")
		var debug_state: Dictionary = debug_value if debug_value is Dictionary else {}
		var body_state: Dictionary = debug_state.get("body_state", {}) if debug_state.get("body_state", {}) is Dictionary else {}
		if not str(body_state.get("world_animation", "")).strip_edges().is_empty():
			count += 1
	return count


func _gecs_tick_ms() -> float:
	if _runner != null and _runner.has_method("get_average_tick_time_ms"):
		return float(_runner.call("get_average_tick_time_ms"))
	return 0.0


func _expected_actor_count() -> int:
	return maxi(0, side_a_count) + maxi(0, side_b_count)


func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "ProjectionBaselineUILayer"
	add_child(_ui_layer)
	var panel := PanelContainer.new()
	panel.name = "ProjectionBaselinePanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(16.0, 16.0)
	panel.custom_minimum_size = Vector2(420.0, 86.0)
	_ui_layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	_status_label = Label.new()
	_metrics_label = Label.new()
	_status_label.text = "Projection baseline starting..."
	_metrics_label.text = "Metrics pending"
	column.add_child(_status_label)
	column.add_child(_metrics_label)


func _render_ui() -> void:
	if _metrics_label == null:
		return
	var state := get_benchmark_state()
	_metrics_label.text = "FPS avg %.1f min %.1f | actors %d/%d visible %d | anim %d | sync %.3f ms | tick %.3f ms" % [
		float(state.get("average_fps", 0.0)),
		float(state.get("min_fps", 0.0)),
		int(state.get("projected_actor_count", 0)),
		int(state.get("expected_actor_count", 0)),
		int(state.get("visible_actor_count", 0)),
		int(state.get("active_animation_count", 0)),
		float(state.get("average_projection_sync_ms", 0.0)),
		float(state.get("gecs_tick_ms", 0.0)),
	]


func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text
