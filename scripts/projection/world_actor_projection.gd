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
const NAVIGATION_MIN_HORIZONTAL_WAYPOINT_DISTANCE_SQUARED := 0.0025
const WORK_INDICATOR_TEXTURE_WIDTH := 96
const WORK_INDICATOR_TEXTURE_HEIGHT := 12
const WORK_INDICATOR_INSET := 3
const WORK_INDICATOR_PIXEL_SIZE := 0.012
const WORK_INDICATOR_Y := 2.45
const WORK_INDICATOR_LABEL_Y := 0.18
const MOVEMENT_MODE_WALK := 0
const MOVEMENT_MODE_RUN := 1
const MOVEMENT_MODE_SNEAK := 2
const SNEAK_MOVE_SPEED_MIN_MULTIPLIER := 0.45
const SNEAK_MOVE_SPEED_MAX_MULTIPLIER := 1.45
const SNEAK_MOVE_SPEED_MASTER_LEVEL := 80.0
const SNEAK_MOVE_SPEED_CURVE := 0.75

var actor_id := ""
var projection_kind := ""
var body_projection: Node
var _selection_area: Area3D
var _selection_ring: MeshInstance3D
var _selection_ring_material := StandardMaterial3D.new()
var _actor_collision_shape: CollisionShape3D
var _work_indicator_root: Node3D
var _work_indicator_sprite: Sprite3D
var _work_indicator_label: Label3D
var _work_indicator_progress_ratio := 0.0
var _selected := false
var _focused := false
var _gravity := ProjectSettings.get_setting("physics/3d/default_gravity") as float
var _runtime_move_active := false
var _runtime_move_target := Vector3.ZERO
var _runtime_move_order_key := ""
var _runtime_navigation_target_synced := false
var _runtime_navigation_synced_target := Vector3.ZERO
var _runtime_stuck_origin := Vector3.ZERO
var _runtime_stuck_target_distance := INF
var _runtime_stuck_seconds := 0.0
var _runtime_stuck_repath_attempts := 0
var _navigation_agent: NavigationAgent3D

static var _work_indicator_textures_by_percent: Dictionary = {}

@export var move_speed := 4.4
@export var acceleration := 10.0
@export var floor_snap_distance := 0.9
@export var max_walkable_slope_degrees := 55.0
@export var move_target_vertical_tolerance := 0.75
@export var navigation_agent_radius := 0.45
@export var navigation_agent_height := 2.0
@export var navigation_path_desired_distance := 0.75
@export var navigation_target_desired_distance := 0.6
@export var navigation_path_height_offset := 0.9
@export var navigation_unreachable_tolerance := 1.4
@export var stuck_check_seconds := 2.0
@export var stuck_min_progress := 0.12
@export var stuck_repath_attempt_limit := 8


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


func apply_projection_snapshot(record: Dictionary, equipment_slots: Dictionary, combat_state: Dictionary = {}) -> void:
	var record_actor_id := str(record.get("actor_id", record.get("stable_id", actor_id))).strip_edges()
	if not record_actor_id.is_empty():
		actor_id = record_actor_id
		set_meta("actor_id", actor_id)
	if not _runtime_move_active:
		var world_position := _record_world_position(record)
		global_position = world_position
	if not _runtime_move_active and bool(record.get("world_facing_yaw_initialized", false)):
		rotation.y = float(record.get("world_facing_yaw", rotation.y))
	visible = int(record.get("life_state", 0)) >= 0
	_set_actor_collision_enabled(int(record.get("life_state", 0)) == 0)
	if _work_indicator_root != null or record.has("work_action"):
		_update_work_indicator_state(record)
	if body_projection != null:
		body_projection.apply_projection_snapshot(record, equipment_slots, combat_state)


func apply_combat_projection_visual(visual_state: Dictionary) -> void:
	_runtime_move_active = false
	if visual_state.get("global_position", null) is Vector3:
		global_position = visual_state.get("global_position")
	if visual_state.has("facing_yaw"):
		rotation.y = float(visual_state.get("facing_yaw", rotation.y))
	if visual_state.has("rotation_x"):
		rotation.x = float(visual_state.get("rotation_x", rotation.x))
	else:
		rotation.x = 0.0
	scale = Vector3.ONE
	var presentation: Dictionary = visual_state.get("presentation", {}) if visual_state.get("presentation", {}) is Dictionary else {}
	var presentation_state := str(presentation.get("state", "")).strip_edges()
	_set_actor_collision_enabled(not presentation_state.begins_with("downed"))
	if body_projection != null and body_projection.has_method("apply_combat_presentation"):
		body_projection.call("apply_combat_presentation", presentation)


func get_combat_presentation_duration(presentation_state: String, event_id: String, fallback: float) -> float:
	if body_projection != null and body_projection.has_method("get_combat_presentation_duration"):
		return float(body_projection.call("get_combat_presentation_duration", presentation_state, event_id, fallback))
	return fallback


func get_combat_impact_ratio(presentation_state: String, event_id: String, fallback: float) -> float:
	if body_projection != null and body_projection.has_method("get_combat_impact_ratio"):
		return float(body_projection.call("get_combat_impact_ratio", presentation_state, event_id, fallback))
	return fallback


func advance_move_order(record: Dictionary, fixed_delta: float) -> Dictionary:
	var move_order: Dictionary = record.get("move_order", {}) if record.get("move_order", {}) is Dictionary else {}
	if not bool(move_order.get("active", false)):
		stop_runtime_move_order()
		return {}
	if int(record.get("life_state", 0)) != 0:
		stop_runtime_move_order()
		return {"blocked": true, "reason": "blocked"}
	var target = move_order.get("target_position", null)
	if not (target is Vector3):
		stop_runtime_move_order()
		return {"blocked": true, "reason": "invalid_target"}
	var target_position: Vector3 = target
	var order_key := _move_order_key(move_order)
	if not _runtime_move_active or _runtime_move_order_key != order_key or _runtime_move_target.distance_squared_to(target_position) > 0.0025:
		_start_runtime_move_order(target_position, order_key)
	if _is_close_to_runtime_target():
		stop_runtime_move_order()
		return {"arrived": true, "position": global_position, "facing_yaw": rotation.y}
	var movement_mode := int(move_order.get("movement_mode", record.get("movement_mode", MOVEMENT_MODE_WALK)))
	var desired_direction := _runtime_move_direction(fixed_delta)
	if desired_direction.length_squared() <= 0.0001:
		_apply_floor_motion(fixed_delta)
		velocity.x = move_toward(velocity.x, 0.0, acceleration * fixed_delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * fixed_delta)
		move_and_slide()
		_update_runtime_stuck_state(fixed_delta, desired_direction)
		return {"moving": false, "position": global_position, "facing_yaw": rotation.y, "movement_mode": movement_mode, "speed": 0.0, "horizontal_speed": 0.0, "direction": Vector3.ZERO}
	var target_speed := _move_speed_for_mode(record, movement_mode)
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	horizontal_velocity = horizontal_velocity.lerp(desired_direction * target_speed, minf(1.0, acceleration * fixed_delta))
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	_apply_floor_motion(fixed_delta)
	move_and_slide()
	rotation.y = atan2(desired_direction.x, desired_direction.z)
	rotation.x = lerp_angle(rotation.x, 0.0, minf(1.0, 10.0 * fixed_delta))
	rotation.z = lerp_angle(rotation.z, 0.0, minf(1.0, 10.0 * fixed_delta))
	_update_runtime_stuck_state(fixed_delta, desired_direction)
	if _is_close_to_runtime_target():
		stop_runtime_move_order()
		return {"arrived": true, "position": global_position, "facing_yaw": rotation.y}
	return {"moving": true, "position": global_position, "facing_yaw": rotation.y, "movement_mode": movement_mode, "speed": target_speed, "horizontal_speed": Vector2(velocity.x, velocity.z).length(), "direction": desired_direction}


func stop_runtime_move_order() -> void:
	_runtime_move_active = false
	_runtime_move_order_key = ""
	_runtime_navigation_target_synced = false
	velocity = Vector3.ZERO
	if _navigation_agent != null and is_instance_valid(_navigation_agent):
		_navigation_agent.velocity = Vector3.ZERO


func has_runtime_move_order() -> bool:
	return _runtime_move_active


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


func get_projection_debug_state() -> Dictionary:
	var body_state: Dictionary = body_projection.get_projection_debug_state() if body_projection != null and body_projection.has_method("get_projection_debug_state") else {}
	return {
		"actor_id": actor_id,
		"projection_kind": projection_kind,
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
	_ensure_actor_collision_nodes()
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


func _start_runtime_move_order(target_position: Vector3, order_key: String) -> void:
	_runtime_move_active = true
	_runtime_move_target = target_position
	_runtime_move_order_key = order_key
	_runtime_navigation_target_synced = false
	_runtime_stuck_repath_attempts = 0
	_reset_runtime_stuck_tracking()
	_ensure_navigation_agent()


func _move_order_key(move_order: Dictionary) -> String:
	return "%s:%s" % [str(move_order.get("issued_msec", 0)), str(move_order.get("target_position", Vector3.ZERO))]


func _runtime_move_direction(_delta: float) -> Vector3:
	if _is_close_to_runtime_target():
		return Vector3.ZERO
	_ensure_navigation_agent()
	if _navigation_agent != null and _has_navigation_data():
		return _navigation_move_direction()
	return _direct_runtime_move_direction()


func _navigation_move_direction() -> Vector3:
	_sync_navigation_target_if_needed()
	if _navigation_agent.is_navigation_finished():
		if _is_close_to_runtime_target() or _is_navigation_final_position_close_enough():
			return _navigation_point_direction(_runtime_move_target)
		return Vector3.ZERO
	var next_path_position := _navigation_agent.get_next_path_position()
	var direct_direction := _navigation_point_direction(next_path_position)
	if direct_direction.length_squared() > 0.0001:
		return direct_direction
	var path := _navigation_agent.get_current_navigation_path()
	var path_index := maxi(0, _navigation_agent.get_current_navigation_path_index())
	for index in range(path_index, path.size()):
		var to_point := path[index] - global_position
		to_point.y = 0.0
		if to_point.length_squared() > NAVIGATION_MIN_HORIZONTAL_WAYPOINT_DISTANCE_SQUARED:
			return to_point.normalized()
	return Vector3.ZERO


func _direct_runtime_move_direction() -> Vector3:
	var to_target := _runtime_move_target - global_position
	to_target.y = 0.0
	if to_target.length_squared() <= 0.0001:
		return Vector3.ZERO
	return to_target.normalized()


func _navigation_point_direction(point: Vector3) -> Vector3:
	var to_point := point - global_position
	to_point.y = 0.0
	if to_point.length_squared() <= 0.0001:
		return Vector3.ZERO
	return to_point.normalized()


func _sync_navigation_target_if_needed() -> void:
	if _navigation_agent == null:
		return
	_navigation_agent.target_desired_distance = navigation_target_desired_distance
	if _runtime_navigation_target_synced and _runtime_navigation_synced_target.distance_squared_to(_runtime_move_target) <= 0.0025:
		return
	_navigation_agent.target_position = _runtime_move_target
	_runtime_navigation_synced_target = _runtime_move_target
	_runtime_navigation_target_synced = true
	_reset_runtime_stuck_tracking()


func _ensure_navigation_agent() -> void:
	if _navigation_agent != null and is_instance_valid(_navigation_agent):
		return
	_navigation_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if _navigation_agent == null:
		_navigation_agent = NavigationAgent3D.new()
		_navigation_agent.name = "NavigationAgent3D"
		add_child(_navigation_agent)
	_navigation_agent.radius = navigation_agent_radius
	_navigation_agent.height = navigation_agent_height
	_navigation_agent.path_desired_distance = navigation_path_desired_distance
	_navigation_agent.target_desired_distance = navigation_target_desired_distance
	_navigation_agent.path_height_offset = navigation_path_height_offset
	_navigation_agent.avoidance_enabled = false
	_navigation_agent.keep_y_velocity = false
	_navigation_agent.simplify_path = false
	_navigation_agent.simplify_epsilon = 0.0


func _has_navigation_data() -> bool:
	return _navigation_agent != null and NavigationServer3D.map_get_iteration_id(_navigation_agent.get_navigation_map()) > 0


func _is_navigation_final_position_close_enough() -> bool:
	if _navigation_agent == null:
		return false
	var final_position := _navigation_agent.get_final_position()
	return _horizontal_distance(final_position, _runtime_move_target) <= navigation_unreachable_tolerance and absf(final_position.y - _runtime_move_target.y) <= move_target_vertical_tolerance


func _is_close_to_runtime_target() -> bool:
	return _horizontal_distance(global_position, _runtime_move_target) <= navigation_target_desired_distance and absf(global_position.y - _runtime_move_target.y) <= move_target_vertical_tolerance


func _apply_floor_motion(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
		apply_floor_snap()


func _move_speed_for_mode(record: Dictionary, movement_mode: int) -> float:
	match movement_mode:
		MOVEMENT_MODE_RUN:
			return move_speed * _run_speed_multiplier(record)
		MOVEMENT_MODE_SNEAK:
			return move_speed * _sneak_move_speed_multiplier(record)
	return move_speed


func _run_speed_multiplier(record: Dictionary) -> float:
	var skill_levels: Dictionary = record.get("skill_levels", {}) if record.get("skill_levels", {}) is Dictionary else {}
	var level := float(skill_levels.get(SkillRules.MOVEMENT_RUNNING, SkillRules.DEFAULT_LEVEL))
	return NpcRules.RUN_SPEED_MULTIPLIER + SkillRules.get_diminishing_bonus(level, 0.42, 55.0)


func _sneak_move_speed_multiplier(record: Dictionary) -> float:
	var skill_levels: Dictionary = record.get("skill_levels", {}) if record.get("skill_levels", {}) is Dictionary else {}
	var sneak_level := float(skill_levels.get(SkillRules.SUBTERFUGE_SNEAKING, SkillRules.DEFAULT_LEVEL))
	var ratio := clampf((sneak_level - float(SkillRules.DEFAULT_LEVEL)) / maxf(SNEAK_MOVE_SPEED_MASTER_LEVEL - float(SkillRules.DEFAULT_LEVEL), 0.001), 0.0, 1.0)
	var mastery := pow(ratio, SNEAK_MOVE_SPEED_CURVE)
	return lerpf(SNEAK_MOVE_SPEED_MIN_MULTIPLIER, SNEAK_MOVE_SPEED_MAX_MULTIPLIER, mastery)


func _update_runtime_stuck_state(delta: float, desired_direction: Vector3) -> void:
	if not _runtime_move_active:
		return
	if desired_direction.length_squared() <= 0.0001:
		_runtime_stuck_seconds += delta
		if _runtime_stuck_seconds >= stuck_check_seconds:
			_handle_runtime_stuck()
		return
	if _has_made_runtime_stuck_progress():
		_reset_runtime_stuck_tracking()
		_runtime_stuck_repath_attempts = 0
		return
	_runtime_stuck_seconds += delta
	if _runtime_stuck_seconds >= stuck_check_seconds:
		_handle_runtime_stuck()


func _handle_runtime_stuck() -> void:
	if _is_close_to_runtime_target():
		return
	if _navigation_agent != null and _is_navigation_final_position_close_enough() and _runtime_stuck_repath_attempts < stuck_repath_attempt_limit:
		_runtime_navigation_target_synced = false
		_runtime_stuck_repath_attempts += 1
		_reset_runtime_stuck_tracking()
		return
	_reset_runtime_stuck_tracking()


func _reset_runtime_stuck_tracking() -> void:
	_runtime_stuck_origin = global_position
	_runtime_stuck_target_distance = _horizontal_distance(global_position, _runtime_move_target) if _runtime_move_active else INF
	_runtime_stuck_seconds = 0.0


func _has_made_runtime_stuck_progress() -> bool:
	if _horizontal_distance(global_position, _runtime_stuck_origin) >= stuck_min_progress:
		return true
	var target_distance := _horizontal_distance(global_position, _runtime_move_target)
	return _runtime_stuck_target_distance < INF and target_distance <= _runtime_stuck_target_distance - stuck_min_progress


func _horizontal_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()


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
