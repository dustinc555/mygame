extends Node3D

class_name CombatBeat1v1TestLevel

const COMBAT_ENCOUNTER_START_REQUEST_SCRIPT := preload("res://scripts/sim/battle/combat_encounter_start_request.gd")
const BOOTSTRAP_PATH := NodePath("GameBootstrap")
const COMBAT_CENTER := Vector3.ZERO
const SLOT_MARKER_RADIUS := 0.55
const SLOT_MARKER_HEIGHT := 0.035
const UI_POLL_INTERVAL_SECONDS := 0.1
const BOOTSTRAP_WAIT_FRAMES := 180

@export var auto_start := true

var _bootstrap: Node
var _gecs: Node
var _combat: Node
var _projection: Node
var _runner: Node
var _camera_rig: Node
var _ready_for_review := false
var _duel_request_tick := -1
var _active_encounter_id := ""
var _active_encounter_key := ""
var _battle_result: Dictionary = {}
var _combat_slots: Dictionary = {}
var _slot_by_occupant_id: Dictionary = {}
var _schedule_events: Array[Dictionary] = []
var _playback_active := false
var _playback_time := 0.0
var _playback_duration := 0.0
var _ui_elapsed := 0.0
var _paused := false
var _slot_marker_root: Node3D
var _notice_by_actor_id: Dictionary = {}

var _ui_layer: CanvasLayer
var _status_label: Label
var _result_label: Label
var _beat_label: Label
var _metrics_label: Label
var _controls_label: Label


func _ready() -> void:
	add_to_group("combat_beat_1v1_test_level")
	_build_review_ui()
	call_deferred("_prepare_review_scene")


func _process(delta: float) -> void:
	if not _ready_for_review:
		return
	if not _playback_active:
		_poll_for_resolved_duel()
	else:
		if not _paused:
			_playback_time = minf(_playback_time + delta, _playback_duration)
		_apply_playback_frame()
	_ui_elapsed += delta
	if _ui_elapsed >= UI_POLL_INTERVAL_SECONDS:
		_ui_elapsed = 0.0
		_render_review_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not _ready_for_review or not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_R:
			restart_duel()
			get_viewport().set_input_as_handled()
		KEY_SPACE:
			_paused = not _paused
			get_viewport().set_input_as_handled()


func restart_duel() -> void:
	if not _ready_for_review or _runner == null or not _runner.has_method("queue_command"):
		return
	var squad_ids := _active_squad_ids()
	if squad_ids.size() < 2:
		_set_status("Need two world squads from the 1v1 world definition.")
		return
	_playback_active = false
	_paused = false
	_playback_time = 0.0
	_playback_duration = 0.0
	_active_encounter_id = ""
	_active_encounter_key = ""
	_battle_result.clear()
	_combat_slots.clear()
	_slot_by_occupant_id.clear()
	_schedule_events.clear()
	_clear_runtime_visuals()
	_duel_request_tick = int(_runner.call("get_tick_count")) if _runner.has_method("get_tick_count") else 0
	if _projection != null:
		_projection.set("auto_project", true)
		if _projection.has_method("sync_projections"):
			_projection.call("sync_projections")
	_runner.call("queue_command", {"action": "reset_world_squads", "label": "Reset 1v1 CombatBeat test world"})
	_runner.call("queue_command", {
		"action": "start_combat_encounter",
		"start_request": _debug_1v1_start_request(squad_ids.slice(0, 2)),
		"label": "Start standalone 1v1 CombatBeat fight",
	})
	_set_status("Queued 1v1 GECS/BattleSim encounter.")


func get_review_state() -> Dictionary:
	return {
		"ready": _ready_for_review,
		"playback_active": _playback_active,
		"paused": _paused,
		"encounter_id": _active_encounter_id,
		"encounter_key": _active_encounter_key,
		"playback_time": _playback_time,
		"playback_duration": _playback_duration,
		"battle_result": _battle_result.duplicate(true),
		"combat_slots": _combat_slots.duplicate(true),
		"schedule_events": _schedule_events.duplicate(true),
		"projection_metrics": _projection.call("get_projection_performance_metrics") if _projection != null and _projection.has_method("get_projection_performance_metrics") else {},
	}


func _prepare_review_scene() -> void:
	_set_status("Waiting for GameBootstrap systems...")
	for _frame in range(BOOTSTRAP_WAIT_FRAMES):
		await get_tree().process_frame
		if _bind_bootstrap_systems() and _active_squad_ids().size() >= 2:
			_ready_for_review = true
			_configure_review_systems()
			_set_status("Ready. Press R to restart the CombatBeat 1v1.")
			if auto_start:
				restart_duel()
			return
	_set_status("Timed out waiting for GameBootstrap combat systems.")


func _bind_bootstrap_systems() -> bool:
	_bootstrap = get_node_or_null(BOOTSTRAP_PATH)
	if _bootstrap == null:
		return false
	_gecs = _bootstrap.get_node_or_null("GecsWorldController")
	_combat = _bootstrap.get_node_or_null("WorldMapCombatSimController")
	_projection = _bootstrap.get_node_or_null("WorldActorProjectionController")
	_runner = _bootstrap.get_node_or_null("WorldMapCombatFixedTickRunner")
	_camera_rig = get_node_or_null("CameraRig")
	return _gecs != null and _combat != null and _projection != null and _runner != null


func _configure_review_systems() -> void:
	if _projection != null:
		_projection.set("max_projected_actor_count", 2)
		_projection.set("projection_update_interval_seconds", 0.05)
	if _camera_rig != null and _camera_rig.has_method("focus_world_position"):
		_camera_rig.call("focus_world_position", COMBAT_CENTER)


func _poll_for_resolved_duel() -> void:
	if _combat == null or not _combat.has_method("get_world_encounter_state"):
		return
	var encounter := _latest_resolved_duel()
	if encounter.is_empty():
		return
	_begin_playback(encounter)


func _latest_resolved_duel() -> Dictionary:
	var state = _combat.call("get_world_encounter_state")
	if not (state is Dictionary):
		return {}
	var encounters = (state as Dictionary).get("encounters_by_id", {})
	if not (encounters is Dictionary):
		return {}
	var latest: Dictionary = {}
	var latest_tick := -1
	for encounter_id in (encounters as Dictionary).keys():
		var encounter = (encounters as Dictionary)[encounter_id]
		if not (encounter is Dictionary):
			continue
		var record: Dictionary = encounter
		if str(record.get("status", "")) != "resolved":
			continue
		if int(record.get("created_tick", -1)) < _duel_request_tick:
			continue
		var battle_result = record.get("battle_result", {})
		if not (battle_result is Dictionary):
			continue
		var resolved_tick := int(record.get("resolved_tick", record.get("created_tick", 0)))
		if resolved_tick > latest_tick:
			latest_tick = resolved_tick
			latest = record.duplicate(true)
	return latest


func _begin_playback(encounter: Dictionary) -> void:
	_active_encounter_id = str(encounter.get("encounter_id", ""))
	_active_encounter_key = "%s:%s" % [_active_encounter_id, str(encounter.get("resolved_tick", ""))]
	_battle_result = (encounter.get("battle_result", {}) as Dictionary).duplicate(true)
	_combat_slots = (_battle_result.get("combat_slots", {}) as Dictionary).duplicate(true) if _battle_result.get("combat_slots", {}) is Dictionary else {}
	_schedule_events = _dictionary_array((_battle_result.get("combat_schedule", {}) as Dictionary).get("events", []) if _battle_result.get("combat_schedule", {}) is Dictionary else [])
	_build_slot_lookup()
	if _projection != null:
		_projection.set("auto_project", true)
		if _projection.has_method("sync_projections"):
			_projection.call("sync_projections")
		_projection.set("auto_project", false)
	_create_slot_markers()
	_create_actor_notices()
	_playback_duration = _schedule_duration() + 1.4
	_playback_time = 0.0
	_playback_active = true
	_apply_playback_frame()
	_set_status("Playing resolved CombatBeat schedule from reusable BattleSim data.")


func _build_slot_lookup() -> void:
	_slot_by_occupant_id.clear()
	for slot_id in _combat_slots.keys():
		var slot = _combat_slots[slot_id]
		if not (slot is Dictionary):
			continue
		var occupant_id := str((slot as Dictionary).get("occupant_id", "")).strip_edges()
		if not occupant_id.is_empty():
			_slot_by_occupant_id[occupant_id] = (slot as Dictionary).duplicate(true)


func _apply_playback_frame() -> void:
	_reset_projection_transforms_to_slots()
	_hide_notices()
	var active_events := _active_events(_playback_time)
	for event in active_events:
		_apply_schedule_event_visual(event, _playback_time)
	if _playback_time >= _schedule_duration():
		_apply_aftermath_visuals()


func _reset_projection_transforms_to_slots() -> void:
	for occupant_id in _slot_by_occupant_id.keys():
		var projection := _projection_for_actor(str(occupant_id))
		if projection == null:
			continue
		var slot: Dictionary = _slot_by_occupant_id[occupant_id]
		projection.global_position = _slot_position(slot)
		projection.rotation = Vector3(0.0, float(slot.get("facing_yaw", 0.0)), 0.0)
		projection.scale = Vector3.ONE


func _apply_schedule_event_visual(event: Dictionary, playback_time: float) -> void:
	var event_type := str(event.get("event_type", ""))
	var progress := _event_progress(event, playback_time)
	var attacker_slot := _slot_for_id(str(event.get("attacker_slot_id", "")))
	var defender_slot := _slot_for_id(str(event.get("defender_slot_id", "")))
	var attacker_id := str(attacker_slot.get("occupant_id", ""))
	var defender_id := str(defender_slot.get("occupant_id", ""))
	var attacker_projection := _projection_for_actor(attacker_id)
	var defender_projection := _projection_for_actor(defender_id)
	match event_type:
		"move_to_slot":
			_apply_move_to_slot(attacker_projection, attacker_slot, defender_projection, defender_slot, progress)
		"face_target":
			_face_slots(attacker_projection, attacker_slot, defender_projection, defender_slot)
		"attack":
			_apply_attack_lunge(attacker_projection, attacker_slot, defender_slot, progress)
			_show_notice(attacker_id, "ATTACK", Color(1.0, 0.82, 0.32, 1.0))
		"reaction":
			_apply_reaction(defender_projection, defender_slot, attacker_slot, progress)
			_show_notice(defender_id, "%s %.1f" % [str(event.get("result", "hit")).to_upper(), float(event.get("damage", 0.0))], Color(1.0, 0.36, 0.24, 1.0))


func _apply_move_to_slot(attacker_projection: Node3D, attacker_slot: Dictionary, defender_projection: Node3D, defender_slot: Dictionary, progress: float) -> void:
	_move_projection_in_from_back(attacker_projection, attacker_slot, defender_slot, progress)
	_move_projection_in_from_back(defender_projection, defender_slot, attacker_slot, progress)


func _move_projection_in_from_back(projection: Node3D, slot: Dictionary, opposing_slot: Dictionary, progress: float) -> void:
	if projection == null:
		return
	var slot_position := _slot_position(slot)
	var opposing_position := _slot_position(opposing_slot)
	var away := (slot_position - opposing_position)
	away.y = 0.0
	if away.length_squared() <= 0.001:
		away = Vector3.FORWARD
	away = away.normalized()
	projection.global_position = slot_position + away * (1.3 * (1.0 - progress))


func _face_slots(attacker_projection: Node3D, attacker_slot: Dictionary, defender_projection: Node3D, defender_slot: Dictionary) -> void:
	if attacker_projection != null:
		attacker_projection.rotation.y = _facing_yaw(_slot_position(attacker_slot), _slot_position(defender_slot))
	if defender_projection != null:
		defender_projection.rotation.y = _facing_yaw(_slot_position(defender_slot), _slot_position(attacker_slot))


func _apply_attack_lunge(projection: Node3D, attacker_slot: Dictionary, defender_slot: Dictionary, progress: float) -> void:
	if projection == null:
		return
	var attacker_position := _slot_position(attacker_slot)
	var defender_position := _slot_position(defender_slot)
	var direction := defender_position - attacker_position
	direction.y = 0.0
	if direction.length_squared() <= 0.001:
		return
	var lunge := sin(progress * PI) * 0.75
	projection.global_position = attacker_position + direction.normalized() * lunge
	projection.rotation.y = _facing_yaw(attacker_position, defender_position)
	projection.scale = Vector3.ONE * (1.0 + sin(progress * PI) * 0.035)


func _apply_reaction(projection: Node3D, defender_slot: Dictionary, attacker_slot: Dictionary, progress: float) -> void:
	if projection == null:
		return
	var defender_position := _slot_position(defender_slot)
	var attacker_position := _slot_position(attacker_slot)
	var away := defender_position - attacker_position
	away.y = 0.0
	if away.length_squared() <= 0.001:
		return
	projection.global_position = defender_position + away.normalized() * sin(progress * PI) * 0.28
	projection.rotation.y = _facing_yaw(defender_position, attacker_position)
	projection.scale = Vector3.ONE * (1.0 - sin(progress * PI) * 0.025)


func _apply_aftermath_visuals() -> void:
	var casualties := _casualty_actor_ids()
	for actor_id in casualties:
		var projection := _projection_for_actor(actor_id)
		if projection == null:
			continue
		var slot: Dictionary = _slot_by_occupant_id.get(actor_id, {})
		projection.global_position = _slot_position(slot) + Vector3(0.0, 0.18, 0.0)
		projection.rotation = Vector3(deg_to_rad(-78.0), float(slot.get("facing_yaw", 0.0)), 0.0)
		projection.scale = Vector3.ONE * 0.96
		_show_notice(actor_id, "DOWN", Color(0.95, 0.2, 0.16, 1.0))


func _active_events(playback_time: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event in _schedule_events:
		var start_time := float(event.get("start_time", 0.0))
		var duration := maxf(float(event.get("duration", 0.0)), 0.001)
		if playback_time >= start_time and playback_time <= start_time + duration:
			result.append(event)
	return result


func _event_progress(event: Dictionary, playback_time: float) -> float:
	var start_time := float(event.get("start_time", 0.0))
	var duration := maxf(float(event.get("duration", 0.0)), 0.001)
	return clampf((playback_time - start_time) / duration, 0.0, 1.0)


func _schedule_duration() -> float:
	var duration := 0.0
	for event in _schedule_events:
		duration = maxf(duration, float(event.get("start_time", 0.0)) + float(event.get("duration", 0.0)))
	return duration


func _slot_for_id(slot_id: String) -> Dictionary:
	var slot = _combat_slots.get(slot_id, {})
	return slot.duplicate(true) if slot is Dictionary else {}


func _slot_position(slot: Dictionary) -> Vector3:
	var value = slot.get("world_position_hint", COMBAT_CENTER)
	return value if value is Vector3 else COMBAT_CENTER


func _projection_for_actor(actor_id: String) -> Node3D:
	if _projection == null or actor_id.strip_edges().is_empty() or not _projection.has_method("get_projection_for_actor"):
		return null
	return _projection.call("get_projection_for_actor", actor_id) as Node3D


func _active_squad_ids() -> Array[String]:
	var result: Array[String] = []
	for squad_id in _active_squad_records().keys():
		result.append(str(squad_id))
	result.sort()
	return result


func _debug_1v1_start_request(squad_ids: Array[String]) -> Dictionary:
	var active_squads := _active_squad_records()
	return {
		"encounter_id": "encounter:debug:combat_beat_1v1:%d" % _duel_request_tick,
		"initial_intent": COMBAT_ENCOUNTER_START_REQUEST_SCRIPT.INTENT_DEBUG,
		"source_type": "debug_1v1",
		"encounter_center": COMBAT_CENTER,
		"projection_importance": "important",
		"visibility_flags": {"force_visible": true},
		"projection_flags": {"important": true},
		"battle_sim_config": {
			"resolve_to_completion": true,
			"max_completion_beats": 96,
			"detailed_beat_limit": 96,
		},
		"sides": [
			_encounter_start_side("side_a", squad_ids[0], active_squads) if squad_ids.size() > 0 else {},
			_encounter_start_side("side_b", squad_ids[1], active_squads) if squad_ids.size() > 1 else {},
		],
	}


func _encounter_start_side(side_id: String, squad_id: String, active_squads: Dictionary) -> Dictionary:
	var squad: Dictionary = active_squads.get(squad_id, {}) if active_squads.get(squad_id, {}) is Dictionary else {}
	return {
		"side_id": side_id,
		"squad_id": squad_id,
		"faction_id": str(squad.get("faction_id", "")),
		"party_id": str(squad.get("party_id", "")),
		"role_markers": ["debug"],
		"member_refs": _encounter_member_refs(squad_id, squad),
		"starting_position": squad.get("location", COMBAT_CENTER) if squad.get("location", null) is Vector3 else COMBAT_CENTER,
		"projection_importance": "important",
	}


func _encounter_member_refs(squad_id: String, squad: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var party_id := str(squad.get("party_id", ""))
	for member_id in _string_array(squad.get("member_ids", [])):
		result.append({
			"member_id": member_id,
			"actor_id": member_id,
			"squad_id": squad_id,
			"party_id": party_id,
			"role_markers": ["debug"],
		})
	return result


func _active_squad_records() -> Dictionary:
	if _combat == null or not _combat.has_method("get_world_squad_state"):
		return {}
	var state = _combat.call("get_world_squad_state")
	if not (state is Dictionary):
		return {}
	var active_squads = (state as Dictionary).get("active_squads", {})
	return active_squads.duplicate(true) if active_squads is Dictionary else {}


func _casualty_actor_ids() -> Array[String]:
	var result: Array[String] = []
	var casualties = _battle_result.get("member_casualties", {})
	if not (casualties is Dictionary):
		return result
	for _squad_id in (casualties as Dictionary).keys():
		var entries = casualties[_squad_id]
		if not (entries is Array):
			continue
		for entry in entries:
			if entry is Dictionary:
				var actor_id := str((entry as Dictionary).get("actor_id", (entry as Dictionary).get("member_id", ""))).strip_edges()
				if not actor_id.is_empty() and not result.has(actor_id):
					result.append(actor_id)
	return result


func _create_slot_markers() -> void:
	_clear_slot_markers()
	_slot_marker_root = Node3D.new()
	_slot_marker_root.name = "CombatBeatSlotMarkers"
	add_child(_slot_marker_root)
	for slot_id in _combat_slots.keys():
		var slot = _combat_slots[slot_id]
		if not (slot is Dictionary):
			continue
		var marker := MeshInstance3D.new()
		marker.name = "SlotMarker_%s" % _safe_node_name(str(slot_id))
		var mesh := CylinderMesh.new()
		mesh.top_radius = SLOT_MARKER_RADIUS
		mesh.bottom_radius = SLOT_MARKER_RADIUS
		mesh.height = SLOT_MARKER_HEIGHT
		mesh.radial_segments = 32
		marker.mesh = mesh
		marker.position = _slot_position(slot) + Vector3(0.0, SLOT_MARKER_HEIGHT * 0.5, 0.0)
		marker.material_override = _slot_marker_material(str((slot as Dictionary).get("side", "")))
		_slot_marker_root.add_child(marker)


func _clear_slot_markers() -> void:
	if _slot_marker_root != null and is_instance_valid(_slot_marker_root):
		_slot_marker_root.queue_free()
	_slot_marker_root = null


func _slot_marker_material(side: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.18, 0.42, 1.0, 0.42) if side == "a" else Color(1.0, 0.22, 0.16, 0.42)
	return material


func _create_actor_notices() -> void:
	_notice_by_actor_id.clear()
	for occupant_id in _slot_by_occupant_id.keys():
		var projection := _projection_for_actor(str(occupant_id))
		if projection == null:
			continue
		var label := Label3D.new()
		label.name = "CombatBeatNotice"
		label.position = Vector3(0.0, 2.65, 0.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 34
		label.outline_size = 8
		label.visible = false
		projection.add_child(label)
		_notice_by_actor_id[str(occupant_id)] = label


func _show_notice(actor_id: String, text: String, color: Color) -> void:
	var label = _notice_by_actor_id.get(actor_id)
	if label == null or not is_instance_valid(label):
		return
	(label as Label3D).text = text
	(label as Label3D).modulate = color
	(label as Label3D).visible = true


func _hide_notices() -> void:
	for label in _notice_by_actor_id.values():
		if label != null and is_instance_valid(label):
			(label as Label3D).visible = false


func _clear_runtime_visuals() -> void:
	_hide_notices()
	for label in _notice_by_actor_id.values():
		if label != null and is_instance_valid(label):
			(label as Node).queue_free()
	_notice_by_actor_id.clear()
	_clear_slot_markers()


func _build_review_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "CombatBeatReviewOverlay"
	_ui_layer.layer = 40
	add_child(_ui_layer)
	var panel := PanelContainer.new()
	panel.name = "ReviewPanel"
	panel.offset_left = 16.0
	panel.offset_top = 16.0
	panel.offset_right = 620.0
	panel.offset_bottom = 188.0
	panel.add_theme_stylebox_override("panel", _panel_style())
	_ui_layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	var title := _ui_label("CombatBeat 1v1 Test Level", Color(0.95, 0.84, 0.58, 1.0), 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var restart_button := Button.new()
	restart_button.text = "Restart 1v1"
	restart_button.focus_mode = Control.FOCUS_NONE
	restart_button.pressed.connect(restart_duel)
	row.add_child(restart_button)
	_status_label = _ui_label("Booting...", Color(0.72, 0.7, 0.62, 1.0), 11)
	_result_label = _ui_label("Result: none", Color(0.86, 0.88, 0.78, 1.0), 11)
	_beat_label = _ui_label("Beat: none", Color(0.7, 0.74, 0.86, 1.0), 11)
	_metrics_label = _ui_label("Metrics: waiting", Color(0.64, 0.68, 0.62, 1.0), 11)
	_controls_label = _ui_label("R restart | Space pause | WASD/mouse camera", Color(0.54, 0.5, 0.44, 1.0), 10)
	column.add_child(_status_label)
	column.add_child(_result_label)
	column.add_child(_beat_label)
	column.add_child(_metrics_label)
	column.add_child(_controls_label)


func _render_review_ui() -> void:
	if _status_label == null:
		return
	var schedule: Dictionary = _battle_result.get("combat_schedule", {}) if _battle_result.get("combat_schedule", {}) is Dictionary else {}
	var continuity: Dictionary = _battle_result.get("combat_continuity", {}) if _battle_result.get("combat_continuity", {}) is Dictionary else {}
	var outcome := str(_battle_result.get("outcome", "none"))
	var summary := str(_battle_result.get("summary", "")).strip_edges()
	_result_label.text = "Result: %s%s" % [outcome, " | %s" % summary if not summary.is_empty() else ""]
	var current_event := _current_event_text()
	_beat_label.text = "Playback %.2f / %.2f | %s" % [_playback_time, _playback_duration, current_event]
	var projection_metrics: Dictionary = _projection.call("get_projection_performance_metrics") if _projection != null and _projection.has_method("get_projection_performance_metrics") else {}
	_metrics_label.text = "Schedule events %d/%d | skipped %d | slots %d | continuity %s | projected %d cap %s" % [
		int(schedule.get("scheduled_event_count", _schedule_events.size())),
		int(schedule.get("total_beat_count", 0)),
		int(schedule.get("skipped_event_count", 0)),
		_combat_slots.size(),
		str(continuity.get("projection_state", "none")),
		int(projection_metrics.get("projected_actor_count", 0)),
		str(projection_metrics.get("max_projected_actor_count", 0)),
	]


func _current_event_text() -> String:
	var active_events := _active_events(_playback_time)
	if active_events.is_empty():
		return "Event: none"
	var event := active_events[0]
	var beat_id := str(event.get("beat_id", ""))
	var beat_label := beat_id.get_slice(":", maxi(0, beat_id.get_slice_count(":") - 1)) if not beat_id.is_empty() else "none"
	return "Event: %s beat %s" % [str(event.get("event_type", "")), beat_label]


func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


func _ui_label(text: String, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.04, 0.035, 0.92)
	style.border_color = Color(0.42, 0.34, 0.19, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style


func _facing_yaw(from_position: Vector3, target_position: Vector3) -> float:
	var delta := target_position - from_position
	if absf(delta.x) < 0.001 and absf(delta.z) < 0.001:
		return 0.0
	return atan2(delta.x, delta.z)


func _dictionary_array(value) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (value is Array):
		return result
	for entry in value:
		if entry is Dictionary:
			result.append((entry as Dictionary).duplicate(true))
	return result


func _string_array(value) -> Array[String]:
	var result: Array[String] = []
	if not (value is Array) and not (value is PackedStringArray):
		return result
	for entry in value:
		var text := str(entry).strip_edges()
		if not text.is_empty():
			result.append(text)
	return result


func _safe_node_name(value: String) -> String:
	var result := value.strip_edges()
	for character in [".", ":", "/", "\\", " "]:
		result = result.replace(character, "_")
	return result if not result.is_empty() else "unknown"
