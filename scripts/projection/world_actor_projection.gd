extends CharacterBody3D

class_name WorldActorProjection

const SELECTED_COLOR := Color(0.28, 0.78, 1.0, 1.0)
const FOCUSED_COLOR := Color(1.0, 0.74, 0.24, 1.0)
const SELECTION_RING_MAJOR_RADIUS := 1.12
const SELECTION_RING_TUBE_RADIUS := 0.075
const SELECTION_RING_TUBE_CENTER_Y := 0.06
const SELECTION_RING_MAJOR_SEGMENTS := 96
const SELECTION_RING_TUBE_SEGMENTS := 10
const ACTOR_COLLISION_RADIUS := 0.48
const ACTOR_COLLISION_HEIGHT := 1.75
const ACTOR_COLLISION_CENTER_Y := 0.9
const WORK_INDICATOR_TEXTURE_WIDTH := 96
const WORK_INDICATOR_TEXTURE_HEIGHT := 12
const WORK_INDICATOR_INSET := 3
const WORK_INDICATOR_PIXEL_SIZE := 0.012
const WORK_INDICATOR_Y := 2.45
const WORK_INDICATOR_LABEL_Y := 0.18
const RENDER_POSITION_EPSILON_SQUARED := 0.0004
const RENDER_YAW_EPSILON := 0.001

var actor_id := ""
var projection_kind := ""
var body_projection: Node
var _selection_area: Area3D
var _selection_ring: MeshInstance3D
var _selection_ring_material := StandardMaterial3D.new()
var _actor_collision_shape: CollisionShape3D
var _actor_collision_enabled := true
var _actor_collision_enabled_initialized := false
var _work_indicator_root: Node3D
var _work_indicator_sprite: Sprite3D
var _work_indicator_label: Label3D
var _work_indicator_progress_ratio := 0.0
var _selected := false
var _focused := false
var _render_target_position := Vector3.ZERO
var _render_target_position_initialized := false
var _render_target_yaw := 0.0
var _render_target_yaw_initialized := false
var _render_start_position := Vector3.ZERO
var _render_start_yaw := 0.0
var _render_elapsed := 0.0
var _render_duration := 0.0
var _render_interpolation_active := false
var _render_process_enabled := false
var _render_commit_uses_visual_transform := false
var _last_render_interpolation_frame := -1
var _last_combat_presentation_signature := ""

static var _work_indicator_textures_by_percent: Dictionary = {}

@export var floor_snap_distance := 0.9
@export var max_walkable_slope_degrees := 55.0
@export var navigation_agent_radius := 0.45
@export var navigation_agent_height := 2.0
@export_range(0.0, 0.25, 0.005) var render_interpolation_seconds := 0.06
@export_range(0.0, 200.0, 0.1) var render_interpolation_snap_distance := 12.0


func setup(target_actor_id: String, target_projection_kind: String, body_script: Script) -> void:
	actor_id = target_actor_id
	projection_kind = target_projection_kind
	name = "ActorProjection_%s" % _safe_node_name(actor_id)
	set_meta("actor_id", actor_id)
	add_to_group("world_actor_projection")
	add_to_group("projected_world_actor")
	floor_snap_length = floor_snap_distance
	floor_max_angle = deg_to_rad(max_walkable_slope_degrees)
	collision_layer = 1
	collision_mask = 1
	if projection_kind == "humanoid":
		add_to_group("projected_humanoid_actor")
		add_to_group("humanoid_projection_actor")
	_ensure_selection_nodes()
	_ensure_actor_collision_nodes()
	_set_body_script(body_script)
	_update_render_process_enabled()


func _process(delta: float) -> void:
	if _render_interpolation_active:
		advance_render_interpolation_for_frame(delta)


func apply_projection_snapshot(record: Dictionary, equipment_slots: Dictionary, combat_state: Dictionary = {}) -> void:
	_render_commit_uses_visual_transform = false
	_last_combat_presentation_signature = ""
	var record_actor_id := str(record.get("actor_id", record.get("stable_id", actor_id))).strip_edges()
	if not record_actor_id.is_empty():
		actor_id = record_actor_id
		set_meta("actor_id", actor_id)
	_apply_render_target_transform(
		_record_world_position(record),
		float(record.get("world_facing_yaw", _render_target_yaw if _render_target_yaw_initialized else rotation.y)),
		bool(record.get("world_facing_yaw_initialized", false))
	)
	visible = int(record.get("life_state", 0)) >= 0
	_set_actor_collision_enabled(int(record.get("life_state", 0)) == 0)
	if _work_indicator_root != null or record.has("work_action"):
		_update_work_indicator_state(record)
	if body_projection != null:
		body_projection.apply_projection_snapshot(record, equipment_slots, combat_state)


func apply_projection_transform_snapshot(record: Dictionary, render_delta := 0.0) -> void:
	_render_commit_uses_visual_transform = false
	var record_actor_id := str(record.get("actor_id", record.get("stable_id", actor_id))).strip_edges()
	if not record_actor_id.is_empty():
		actor_id = record_actor_id
		set_meta("actor_id", actor_id)
	_apply_render_target_transform(
		_record_world_position(record),
		float(record.get("world_facing_yaw", _render_target_yaw if _render_target_yaw_initialized else rotation.y)),
		bool(record.get("world_facing_yaw_initialized", false))
	)
	if render_delta > 0.0 and _render_interpolation_active:
		advance_render_interpolation_for_frame(render_delta)


func apply_combat_projection_visual(visual_state: Dictionary) -> void:
	if visual_state.get("global_position", null) is Vector3:
		global_position = visual_state.get("global_position")
	if visual_state.has("facing_yaw"):
		rotation.y = float(visual_state.get("facing_yaw", rotation.y))
	_render_commit_uses_visual_transform = true
	if _render_interpolation_active:
		_render_interpolation_active = false
		_update_render_process_enabled()
	if visual_state.has("rotation_x"):
		rotation.x = float(visual_state.get("rotation_x", rotation.x))
	else:
		rotation.x = 0.0
	scale = Vector3.ONE
	var presentation: Dictionary = visual_state.get("presentation", {}) if visual_state.get("presentation", {}) is Dictionary else {}
	var presentation_state := str(presentation.get("state", "")).strip_edges()
	_set_actor_collision_enabled(not presentation_state.begins_with("downed"))
	var presentation_signature := _combat_presentation_signature(presentation)
	if body_projection != null and body_projection.has_method("apply_combat_presentation") and presentation_signature != _last_combat_presentation_signature:
		_last_combat_presentation_signature = presentation_signature
		body_projection.call("apply_combat_presentation", presentation)


func get_combat_presentation_duration(presentation_state: String, event_id: String, fallback: float) -> float:
	if body_projection != null and body_projection.has_method("get_combat_presentation_duration"):
		return float(body_projection.call("get_combat_presentation_duration", presentation_state, event_id, fallback))
	return fallback


func get_combat_impact_ratio(presentation_state: String, event_id: String, fallback: float) -> float:
	if body_projection != null and body_projection.has_method("get_combat_impact_ratio"):
		return float(body_projection.call("get_combat_impact_ratio", presentation_state, event_id, fallback))
	return fallback


func advance_move_order(_record: Dictionary, _fixed_delta: float) -> Dictionary:
	stop_runtime_move_order()
	return {}


func stop_runtime_move_order() -> void:
	velocity = Vector3.ZERO


func has_runtime_move_order() -> bool:
	return false


func get_gecs_commit_transform() -> Dictionary:
	if _render_commit_uses_visual_transform:
		return {
			"last_world_position": global_position,
			"last_world_position_initialized": true,
			"world_facing_yaw": rotation.y,
			"world_facing_yaw_initialized": true,
		}
	return {
		"last_world_position": _render_target_position if _render_target_position_initialized else global_position,
		"last_world_position_initialized": true,
		"world_facing_yaw": _render_target_yaw if _render_target_yaw_initialized else rotation.y,
		"world_facing_yaw_initialized": true,
	}


func advance_render_interpolation_for_frame(delta: float) -> void:
	if not _render_interpolation_active:
		_update_render_process_enabled()
		return
	var frame := Engine.get_process_frames()
	if _last_render_interpolation_frame == frame:
		return
	_last_render_interpolation_frame = frame
	_advance_render_interpolation(delta)


func set_selected(selected: bool) -> void:
	_ensure_selection_nodes()
	_selected = selected
	_update_selection_ring_state()


func set_focused(focused: bool) -> void:
	_ensure_selection_nodes()
	_focused = focused
	_update_selection_ring_state()


func get_body_projection() -> Node:
	return body_projection


func get_perception_eye_position() -> Vector3:
	return global_position + Vector3(0.0, navigation_agent_height * 0.82, 0.0)


func get_perception_forward_vector() -> Vector3:
	var forward := global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		return Vector3.BACK
	return forward.normalized()


func get_stealth_sample_positions() -> Array[Vector3]:
	var height := maxf(navigation_agent_height, 0.6)
	var side_offset := maxf(0.18, navigation_agent_radius * 0.62)
	return [
		global_position + Vector3(0.0, height * 0.32, 0.0),
		global_position + Vector3(0.0, height * 0.58, 0.0),
		global_position + Vector3(0.0, height * 0.84, 0.0),
		global_position + Vector3(side_offset, height * 0.58, 0.0),
		global_position + Vector3(-side_offset, height * 0.58, 0.0),
	]


func get_stealth_light_sample_position() -> Vector3:
	return global_position + Vector3(0.0, maxf(navigation_agent_height, 0.6) * 0.55, 0.0)


func get_stealth_indicator_position() -> Vector3:
	return global_position + Vector3(0.0, maxf(navigation_agent_height, 0.6) + 0.65, 0.0)


func get_projection_debug_state() -> Dictionary:
	var body_state: Dictionary = body_projection.get_projection_debug_state() if body_projection != null and body_projection.has_method("get_projection_debug_state") else {}
	return {
		"actor_id": actor_id,
		"projection_kind": projection_kind,
		"render_interpolation_active": _render_interpolation_active,
		"render_target_position": _render_target_position,
		"render_target_position_initialized": _render_target_position_initialized,
		"render_target_yaw": _render_target_yaw,
		"render_target_yaw_initialized": _render_target_yaw_initialized,
		"body_state": body_state,
	}


func get_work_indicator_debug_state() -> Dictionary:
	return {
		"visible": _work_indicator_root != null and _work_indicator_root.visible,
		"progress": _work_indicator_progress(),
		"texture_ready": _work_indicator_sprite != null and _work_indicator_sprite.texture != null,
	}


func is_body_ragdoll_active() -> bool:
	return body_projection != null and body_projection.has_method("is_ragdoll_active") and bool(body_projection.call("is_ragdoll_active"))


func _apply_render_target_transform(target_position: Vector3, target_yaw: float, target_yaw_initialized: bool) -> void:
	if not _render_target_position_initialized:
		_render_target_position = target_position
		_render_target_position_initialized = true
		global_position = target_position
		_render_start_position = target_position
		if target_yaw_initialized:
			_render_target_yaw = target_yaw
			_render_target_yaw_initialized = true
			rotation.y = target_yaw
			_render_start_yaw = target_yaw
		_render_interpolation_active = false
		_last_render_interpolation_frame = -1
		_update_render_process_enabled()
		return
	var target_changed := _render_target_position.distance_squared_to(target_position) > RENDER_POSITION_EPSILON_SQUARED
	if target_yaw_initialized:
		target_changed = target_changed or not _render_target_yaw_initialized or absf(angle_difference(_render_target_yaw, target_yaw)) > RENDER_YAW_EPSILON
	_render_target_position = target_position
	if target_yaw_initialized:
		_render_target_yaw = target_yaw
		_render_target_yaw_initialized = true
	var position_delta_squared := global_position.distance_squared_to(_render_target_position)
	var yaw_delta := absf(angle_difference(rotation.y, _render_target_yaw)) if _render_target_yaw_initialized else 0.0
	if not target_changed and _render_interpolation_active:
		_update_render_process_enabled()
		return
	var snap_distance_squared := render_interpolation_snap_distance * render_interpolation_snap_distance
	if render_interpolation_seconds <= 0.0 or (render_interpolation_snap_distance > 0.0 and position_delta_squared > snap_distance_squared):
		_snap_to_render_target()
		return
	if position_delta_squared <= RENDER_POSITION_EPSILON_SQUARED and yaw_delta <= RENDER_YAW_EPSILON:
		_snap_to_render_target()
		return
	_render_start_position = global_position
	_render_start_yaw = rotation.y
	_render_elapsed = 0.0
	_render_duration = maxf(render_interpolation_seconds, 0.001)
	_render_interpolation_active = true
	_last_render_interpolation_frame = -1
	_update_render_process_enabled()


func _advance_render_interpolation(delta: float) -> void:
	if not _render_interpolation_active:
		_update_render_process_enabled()
		return
	_render_elapsed += maxf(delta, 0.0)
	var ratio := clampf(_render_elapsed / maxf(_render_duration, 0.001), 0.0, 1.0)
	global_position = _render_start_position.lerp(_render_target_position, ratio)
	if _render_target_yaw_initialized:
		rotation.y = lerp_angle(_render_start_yaw, _render_target_yaw, ratio)
	if ratio >= 1.0:
		_snap_to_render_target()


func _snap_to_render_target() -> void:
	if _render_target_position_initialized:
		global_position = _render_target_position
		_render_start_position = _render_target_position
	if _render_target_yaw_initialized:
		rotation.y = _render_target_yaw
		_render_start_yaw = _render_target_yaw
	_render_elapsed = 0.0
	_render_duration = 0.0
	_render_interpolation_active = false
	_update_render_process_enabled()


func _update_render_process_enabled() -> void:
	if _render_process_enabled == _render_interpolation_active and is_processing() == _render_interpolation_active:
		return
	_render_process_enabled = _render_interpolation_active
	set_process(_render_process_enabled)


func _combat_presentation_signature(presentation: Dictionary) -> String:
	var state := str(presentation.get("state", "")).strip_edges()
	var event_id := str(presentation.get("event_id", state)).strip_edges()
	match state:
		"attack", "reaction", "block", "downed", "move":
			return "%s:%s:%.3f" % [state, event_id, float(presentation.get("progress", 0.0))]
	return "%s:%s" % [state, event_id]


func _set_body_script(body_script: Script) -> void:
	if body_projection != null:
		remove_child(body_projection)
		body_projection.queue_free()
	body_projection = null
	if body_script == null:
		return
	var body = body_script.new()
	if not (body is Node) or not body.has_method("apply_projection_snapshot"):
		if body is Node:
			(body as Node).queue_free()
		return
	body_projection = body as Node
	body_projection.name = "BodyProjection"
	add_child(body_projection)


func _ensure_selection_nodes() -> void:
	if _selection_area == null:
		_selection_area = Area3D.new()
		_selection_area.name = "SelectionHitArea"
		_selection_area.input_ray_pickable = true
		_selection_area.set_meta("actor_id", actor_id)
		_selection_area.add_to_group("projected_world_actor_hit_area")
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		var shape := CapsuleShape3D.new()
		shape.radius = 0.55
		shape.height = 1.8
		collision.shape = shape
		collision.position = Vector3(0.0, 0.95, 0.0)
		_selection_area.add_child(collision)
		add_child(_selection_area)
	if _selection_ring == null:
		_selection_ring = MeshInstance3D.new()
		_selection_ring.name = "SelectionRing"
		_selection_ring.mesh = _make_selection_ring_mesh()
		_selection_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_selection_ring.material_override = _selection_ring_material
		_selection_ring.visible = false
		_setup_selection_ring_material()
		add_child(_selection_ring)
	if _selection_area != null:
		_selection_area.set_meta("actor_id", actor_id)
	set_meta("actor_id", actor_id)
	_update_work_indicator_state({})


func _ensure_actor_collision_nodes() -> void:
	if _actor_collision_shape == null:
		_actor_collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _actor_collision_shape == null:
		_actor_collision_shape = CollisionShape3D.new()
		_actor_collision_shape.name = "CollisionShape3D"
		var shape := CapsuleShape3D.new()
		shape.radius = ACTOR_COLLISION_RADIUS
		shape.height = ACTOR_COLLISION_HEIGHT
		_actor_collision_shape.shape = shape
		_actor_collision_shape.position = Vector3(0.0, ACTOR_COLLISION_CENTER_Y, 0.0)
		add_child(_actor_collision_shape)
	set_meta("actor_id", actor_id)
	add_to_group("projected_world_actor_collision")


func _set_actor_collision_enabled(enabled: bool) -> void:
	if _actor_collision_enabled_initialized and _actor_collision_enabled == enabled:
		return
	_ensure_actor_collision_nodes()
	_actor_collision_enabled = enabled
	_actor_collision_enabled_initialized = true
	if _actor_collision_shape != null:
		_actor_collision_shape.disabled = not enabled
	collision_layer = 1 if enabled else 0
	collision_mask = 1 if enabled else 0


func _ensure_work_indicator_nodes() -> void:
	if _work_indicator_root != null and is_instance_valid(_work_indicator_root):
		return
	_work_indicator_root = Node3D.new()
	_work_indicator_root.name = "WorkIndicator"
	_work_indicator_root.position = Vector3(0.0, WORK_INDICATOR_Y, 0.0)
	_work_indicator_root.visible = false
	add_child(_work_indicator_root)
	_work_indicator_sprite = Sprite3D.new()
	_work_indicator_sprite.name = "WorkProgressBar"
	_work_indicator_sprite.texture = _work_indicator_texture_for_progress(0.0)
	_work_indicator_sprite.pixel_size = WORK_INDICATOR_PIXEL_SIZE
	_work_indicator_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_work_indicator_sprite.no_depth_test = true
	_work_indicator_sprite.shaded = false
	_work_indicator_sprite.double_sided = true
	_work_indicator_root.add_child(_work_indicator_sprite)
	_work_indicator_label = Label3D.new()
	_work_indicator_label.name = "WorkProgressLabel"
	_work_indicator_label.position = Vector3(0.0, WORK_INDICATOR_LABEL_Y, 0.0)
	_work_indicator_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_work_indicator_label.font_size = 18
	_work_indicator_label.modulate = Color(1.0, 0.86, 0.52, 1.0)
	_work_indicator_label.outline_size = 4
	_work_indicator_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.8)
	_work_indicator_root.add_child(_work_indicator_label)


func _update_work_indicator_state(record: Dictionary) -> void:
	var work_action: Dictionary = record.get("work_action", {}) if record.get("work_action", {}) is Dictionary else {}
	var is_mining := bool(work_action.get("active", false)) and str(work_action.get("type", "")).strip_edges() == "mine_resource"
	if not is_mining:
		if _work_indicator_root != null:
			_work_indicator_root.visible = false
		_work_indicator_progress_ratio = 0.0
		return
	_ensure_work_indicator_nodes()
	_work_indicator_root.visible = true
	var progress := clampf(float(work_action.get("progress_ratio", 0.0)), 0.0, 1.0)
	_work_indicator_progress_ratio = progress
	if _work_indicator_sprite != null:
		_work_indicator_sprite.texture = _work_indicator_texture_for_progress(progress)
	var display_name := str(work_action.get("display_name", "Mining")).strip_edges()
	if display_name.is_empty():
		display_name = "Mining"
	if _work_indicator_label != null:
		_work_indicator_label.text = "%s %d%%" % [display_name, int(round(progress * 100.0))]


func _work_indicator_progress() -> float:
	if _work_indicator_root == null or not _work_indicator_root.visible:
		return 0.0
	return _work_indicator_progress_ratio


func _work_indicator_texture_for_progress(progress: float) -> Texture2D:
	var percent := clampi(int(round(clampf(progress, 0.0, 1.0) * 100.0)), 0, 100)
	var cached = _work_indicator_textures_by_percent.get(percent)
	if cached is Texture2D:
		return cached
	var image := Image.create(WORK_INDICATOR_TEXTURE_WIDTH, WORK_INDICATOR_TEXTURE_HEIGHT, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	image.fill_rect(Rect2i(Vector2i.ZERO, Vector2i(WORK_INDICATOR_TEXTURE_WIDTH, WORK_INDICATOR_TEXTURE_HEIGHT)), Color(0.018, 0.014, 0.011, 0.92))
	image.fill_rect(Rect2i(Vector2i(1, 1), Vector2i(WORK_INDICATOR_TEXTURE_WIDTH - 2, WORK_INDICATOR_TEXTURE_HEIGHT - 2)), Color(0.055, 0.045, 0.034, 0.94))
	var inner_width := maxi(WORK_INDICATOR_TEXTURE_WIDTH - WORK_INDICATOR_INSET * 2, 1)
	var inner_height := maxi(WORK_INDICATOR_TEXTURE_HEIGHT - WORK_INDICATOR_INSET * 2, 1)
	var fill_width := clampi(int(floor(float(inner_width) * clampf(progress, 0.0, 1.0))), 0, inner_width)
	if fill_width > 0:
		image.fill_rect(Rect2i(Vector2i(WORK_INDICATOR_INSET, WORK_INDICATOR_INSET), Vector2i(fill_width, inner_height)), Color(0.72, 0.39, 0.16, 0.96))
		image.fill_rect(Rect2i(Vector2i(WORK_INDICATOR_INSET, WORK_INDICATOR_INSET), Vector2i(fill_width, 1)), Color(1.0, 0.74, 0.31, 0.92))
	image.fill_rect(Rect2i(Vector2i.ZERO, Vector2i(WORK_INDICATOR_TEXTURE_WIDTH, 1)), Color(0.0, 0.0, 0.0, 1.0))
	image.fill_rect(Rect2i(Vector2i(0, WORK_INDICATOR_TEXTURE_HEIGHT - 1), Vector2i(WORK_INDICATOR_TEXTURE_WIDTH, 1)), Color(0.0, 0.0, 0.0, 1.0))
	image.fill_rect(Rect2i(Vector2i.ZERO, Vector2i(1, WORK_INDICATOR_TEXTURE_HEIGHT)), Color(0.0, 0.0, 0.0, 1.0))
	image.fill_rect(Rect2i(Vector2i(WORK_INDICATOR_TEXTURE_WIDTH - 1, 0), Vector2i(1, WORK_INDICATOR_TEXTURE_HEIGHT)), Color(0.0, 0.0, 0.0, 1.0))
	var texture := ImageTexture.create_from_image(image)
	_work_indicator_textures_by_percent[percent] = texture
	return texture


func _setup_selection_ring_material() -> void:
	_selection_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_selection_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_selection_ring_material.no_depth_test = false
	_selection_ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_selection_ring_material.emission_enabled = true
	_selection_ring_material.emission_energy_multiplier = 1.35
	_selection_ring_material.albedo_color = SELECTED_COLOR
	_selection_ring_material.emission = SELECTED_COLOR


func _update_selection_ring_state() -> void:
	if _selection_ring == null:
		return
	_selection_ring.visible = _selected or _focused
	var color := FOCUSED_COLOR if _focused else SELECTED_COLOR
	_selection_ring_material.albedo_color = color
	_selection_ring_material.emission = color


func _make_selection_ring_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for major_index in range(SELECTION_RING_MAJOR_SEGMENTS):
		var major_angle := TAU * float(major_index) / float(SELECTION_RING_MAJOR_SEGMENTS)
		var radial_direction := Vector3(cos(major_angle), 0.0, sin(major_angle))
		for tube_index in range(SELECTION_RING_TUBE_SEGMENTS):
			var tube_angle := TAU * float(tube_index) / float(SELECTION_RING_TUBE_SEGMENTS)
			var tube_cos := cos(tube_angle)
			var tube_sin := sin(tube_angle)
			vertices.append(radial_direction * (SELECTION_RING_MAJOR_RADIUS + SELECTION_RING_TUBE_RADIUS * tube_cos) + Vector3.UP * (SELECTION_RING_TUBE_CENTER_Y + SELECTION_RING_TUBE_RADIUS * tube_sin))
			normals.append((radial_direction * tube_cos + Vector3.UP * tube_sin).normalized())
	for major_index in range(SELECTION_RING_MAJOR_SEGMENTS):
		var next_major_index := (major_index + 1) % SELECTION_RING_MAJOR_SEGMENTS
		for tube_index in range(SELECTION_RING_TUBE_SEGMENTS):
			var next_tube_index := (tube_index + 1) % SELECTION_RING_TUBE_SEGMENTS
			var current := major_index * SELECTION_RING_TUBE_SEGMENTS + tube_index
			var next_tube := major_index * SELECTION_RING_TUBE_SEGMENTS + next_tube_index
			var next_major := next_major_index * SELECTION_RING_TUBE_SEGMENTS + tube_index
			var next_both := next_major_index * SELECTION_RING_TUBE_SEGMENTS + next_tube_index
			indices.append(current)
			indices.append(next_major)
			indices.append(next_tube)
			indices.append(next_tube)
			indices.append(next_major)
			indices.append(next_both)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _record_world_position(record: Dictionary) -> Vector3:
	var record_position = record.get("last_world_position", record.get("world_position", Vector3.ZERO))
	return record_position if record_position is Vector3 else Vector3.ZERO


func _safe_node_name(value: String) -> String:
	var result := value.strip_edges()
	for character in [".", ":", "/", "\\", " "]:
		result = result.replace(character, "_")
	return result if not result.is_empty() else "unknown"
