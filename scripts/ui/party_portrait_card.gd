extends Button

class_name PartyPortraitCard

signal portrait_pressed(actor_id: String, double_click: bool, add_select: bool)

const CHARACTER_VISUAL_NODE_NAME := "CharacterVisual"
const BODY_VISUAL_NODE_NAME := "BodyVisual"
const EQUIPMENT_VISUAL_NODE_NAME := "EquipmentProjection"
const PORTRAIT_VISUAL_YAW_OFFSET := PI
const PORTRAIT_IDLE_POSE_SECONDS := 0.45
const PORTRAIT_IDLE_ANIMATION_NAMES := ["Idle"]
const PORTRAIT_FOV := 26.0
const PORTRAIT_TARGET_HEIGHT_RATIO := 0.84
const PORTRAIT_DISTANCE_HEIGHT_RATIO := 0.70
const PORTRAIT_MIN_DISTANCE := 1.20
const PORTRAIT_CAMERA_SIDE_OFFSET := 0.08
const PORTRAIT_CAMERA_ELEVATION_OFFSET := 0.03
const PORTRAIT_SKIP_NODE_NAMES := {
	"InspectRing": true,
	"SelectionRing": true,
	"SelectionMarker": true,
	"SelectionHitArea": true,
	"NameLabel": true,
}

var actor_id := ""
var projection: Node
var record: Dictionary = {}
var _portrait_refresh_queued := false
var _portrait_signature := ""
var _is_selected := false
var _is_controlled := false
var _last_pose_animation := ""

@onready var viewport: SubViewport = $Margin/VBox/PortraitViewportContainer/SubViewport
@onready var portrait_camera: Camera3D = $Margin/VBox/PortraitViewportContainer/SubViewport/Camera3D
@onready var portrait_root: Node3D = $Margin/VBox/PortraitViewportContainer/SubViewport/PortraitRoot
@onready var portrait_image: TextureRect = $Margin/VBox/PortraitImage
@onready var name_label: Label = $Margin/VBox/Name


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_color_override("font_color", Color(0.92, 0.92, 0.92, 1.0))
	add_theme_color_override("font_hover_color", Color(0.92, 0.92, 0.92, 1.0))
	add_theme_color_override("font_pressed_color", Color(0.92, 0.92, 0.92, 1.0))
	add_theme_color_override("font_focus_color", Color(0.92, 0.92, 0.92, 1.0))
	add_theme_color_override("font_disabled_color", Color(0.92, 0.92, 0.92, 1.0))


func setup_projection(source_record: Dictionary, source_projection: Node) -> void:
	record = source_record.duplicate(true)
	actor_id = str(record.get("actor_id", record.get("stable_id", actor_id))).strip_edges()
	projection = source_projection
	set_meta("actor_id", actor_id)
	set_meta("party_panel_record", record.duplicate(true))
	if name_label == null:
		call_deferred("_deferred_setup")
		return
	name_label.text = str(record.get("member_name", actor_id))
	var next_signature := _make_portrait_signature()
	if next_signature != _portrait_signature:
		_portrait_signature = next_signature
		call_deferred("_rebuild_portrait")


func update_record(source_record: Dictionary) -> void:
	record = source_record.duplicate(true)
	actor_id = str(record.get("actor_id", record.get("stable_id", actor_id))).strip_edges()
	set_meta("actor_id", actor_id)
	set_meta("party_panel_record", record.duplicate(true))
	if name_label != null:
		name_label.text = str(record.get("member_name", actor_id))


func apply_state(is_selected: bool, is_controlled: bool) -> void:
	_is_selected = is_selected
	_is_controlled = is_controlled
	if name_label == null:
		return
	name_label.text = str(record.get("member_name", actor_id))
	if is_selected or is_controlled:
		_set_style(Color(0.26, 0.22, 0.12, 0.98), Color(1.0, 0.88, 0.45, 1.0), 3)
	else:
		_set_style(Color(0.16, 0.16, 0.18, 0.96), Color(0.34, 0.34, 0.38, 1.0), 1)


func refresh_portrait() -> void:
	if _portrait_refresh_queued:
		return
	_portrait_refresh_queued = true
	call_deferred("_deferred_refresh_portrait")


func get_debug_state() -> Dictionary:
	var source := _portrait_source()
	return {
		"actor_id": actor_id,
		"name": name_label.text if name_label != null else "",
		"button_text": text,
		"selected": _is_selected,
		"controlled": _is_controlled,
		"has_texture": portrait_image != null and portrait_image.texture != null,
		"portrait_child_count": portrait_root.get_child_count() if portrait_root != null else 0,
		"portrait_source_child_names": _child_names(source),
		"portrait_yaw_offset": PORTRAIT_VISUAL_YAW_OFFSET,
		"pose_animation": _last_pose_animation,
		"tooltip": tooltip_text,
		"record": record.duplicate(true),
	}


func _deferred_setup() -> void:
	if name_label == null:
		return
	name_label.text = str(record.get("member_name", actor_id))
	_portrait_signature = _make_portrait_signature()
	call_deferred("_rebuild_portrait")


func _deferred_refresh_portrait() -> void:
	_portrait_refresh_queued = false
	if not is_inside_tree() or portrait_root == null:
		return
	_rebuild_portrait()


func _gui_input(event: InputEvent) -> void:
	if actor_id.is_empty():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		portrait_pressed.emit(actor_id, event.double_click, event.alt_pressed)


func _rebuild_portrait() -> void:
	_clear_portrait_root()
	_last_pose_animation = ""
	portrait_image.texture = null
	var source := _portrait_source()
	if source == null:
		return
	for child in source.get_children():
		_add_portrait_copy(child)
	_frame_portrait_camera()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	call_deferred("_capture_snapshot")


func _portrait_source() -> Node:
	if projection == null or not is_instance_valid(projection):
		return null
	if projection.has_method("get_portrait_source"):
		var source = projection.call("get_portrait_source")
		if source is Node:
			return source
	if projection.has_method("get_body_projection"):
		var body = projection.call("get_body_projection")
		if body is Node:
			if (body as Node).has_method("get_portrait_source"):
				var body_source = (body as Node).call("get_portrait_source")
				if body_source is Node:
					return body_source
			return body
	return projection


func _frame_portrait_camera() -> void:
	if portrait_camera == null:
		return
	portrait_camera.fov = PORTRAIT_FOV
	var bounds := _calculate_local_mesh_bounds(portrait_root)
	if bounds.size.length() <= 0.001:
		var fallback_target := Vector3(0.0, 1.58, 0.0)
		portrait_camera.position = fallback_target + Vector3(PORTRAIT_CAMERA_SIDE_OFFSET, PORTRAIT_CAMERA_ELEVATION_OFFSET, PORTRAIT_MIN_DISTANCE)
		portrait_camera.look_at(fallback_target, Vector3.UP)
		return
	var height := maxf(bounds.size.y, 1.4)
	var center := bounds.get_center()
	var target := Vector3(clampf(center.x, -0.12, 0.12), bounds.position.y + height * PORTRAIT_TARGET_HEIGHT_RATIO, clampf(center.z, -0.10, 0.10))
	var distance := maxf(PORTRAIT_MIN_DISTANCE, height * PORTRAIT_DISTANCE_HEIGHT_RATIO)
	portrait_camera.position = target + Vector3(PORTRAIT_CAMERA_SIDE_OFFSET, height * 0.015 + PORTRAIT_CAMERA_ELEVATION_OFFSET, distance)
	portrait_camera.look_at(target, Vector3.UP)


func _add_portrait_copy(source: Node) -> void:
	var source_name := String(source.name)
	if PORTRAIT_SKIP_NODE_NAMES.has(source_name):
		return
	var is_body_visual := source_name == BODY_VISUAL_NODE_NAME
	var is_equipment_visual := source_name == EQUIPMENT_VISUAL_NODE_NAME
	if source_name != CHARACTER_VISUAL_NODE_NAME and not is_body_visual and not is_equipment_visual and not (source is MeshInstance3D):
		return
	var mesh_source := source as MeshInstance3D
	if mesh_source != null and not mesh_source.visible:
		return
	var copy := source.duplicate()
	if not (copy is Node3D):
		copy.queue_free()
		return
	copy.transform = (source as Node3D).transform
	if is_body_visual:
		copy.name = CHARACTER_VISUAL_NODE_NAME
	if source_name == CHARACTER_VISUAL_NODE_NAME or is_body_visual or is_equipment_visual:
		copy.rotation.y += PORTRAIT_VISUAL_YAW_OFFSET
	_duplicate_portrait_materials(copy)
	portrait_root.add_child(copy)
	if source_name == CHARACTER_VISUAL_NODE_NAME or is_body_visual:
		_apply_portrait_idle_pose(copy)


func _duplicate_portrait_materials(node: Node) -> void:
	if node is MeshInstance3D and node.material_override != null:
		node.material_override = node.material_override.duplicate()
	for child in node.get_children():
		_duplicate_portrait_materials(child)


func _apply_portrait_idle_pose(root: Node) -> void:
	var animation_player := _find_animation_player(root)
	if animation_player == null:
		return
	var animation_name := _get_portrait_idle_animation_name(animation_player)
	if animation_name.is_empty():
		return
	animation_player.play(animation_name)
	animation_player.seek(PORTRAIT_IDLE_POSE_SECONDS, true)
	animation_player.advance(0.0)
	animation_player.stop(false)
	_last_pose_animation = animation_name


func _get_portrait_idle_animation_name(animation_player: AnimationPlayer) -> String:
	for animation_name_value in PORTRAIT_IDLE_ANIMATION_NAMES:
		var animation_name := String(animation_name_value)
		if animation_player.has_animation(animation_name):
			return animation_name
	return ""


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for child in root.get_children():
		var animation_player := _find_animation_player(child)
		if animation_player != null:
			return animation_player
	return null


func _clear_portrait_root() -> void:
	for child in portrait_root.get_children():
		portrait_root.remove_child(child)
		child.queue_free()


func _calculate_local_mesh_bounds(root: Node) -> AABB:
	var result := {"has_bounds": false, "bounds": AABB()}
	_accumulate_local_mesh_bounds(root, Transform3D.IDENTITY, result)
	return result["bounds"] if bool(result["has_bounds"]) else AABB()


func _accumulate_local_mesh_bounds(node: Node, parent_transform: Transform3D, result: Dictionary) -> void:
	var local_transform := parent_transform
	if node is Node3D:
		local_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.visible and mesh_instance.mesh != null:
			var mesh_bounds := _transform_aabb(mesh_instance.mesh.get_aabb(), local_transform)
			if result["has_bounds"]:
				result["bounds"] = (result["bounds"] as AABB).merge(mesh_bounds)
			else:
				result["bounds"] = mesh_bounds
				result["has_bounds"] = true
	for child in node.get_children():
		_accumulate_local_mesh_bounds(child, local_transform, result)


func _transform_aabb(bounds: AABB, transform: Transform3D) -> AABB:
	var first := true
	var transformed_bounds := AABB()
	for x in [bounds.position.x, bounds.position.x + bounds.size.x]:
		for y in [bounds.position.y, bounds.position.y + bounds.size.y]:
			for z in [bounds.position.z, bounds.position.z + bounds.size.z]:
				var point := transform * Vector3(x, y, z)
				if first:
					transformed_bounds = AABB(point, Vector3.ZERO)
					first = false
				else:
					transformed_bounds = transformed_bounds.expand(point)
	return transformed_bounds


func _capture_snapshot() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		portrait_image.texture = viewport.get_texture()
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_release_projection_portrait_source()
		return
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if image == null:
		return
	var texture := ImageTexture.create_from_image(image)
	portrait_image.texture = texture
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_clear_portrait_root()
	_release_projection_portrait_source()


func _set_style(background: Color, border: Color, border_width: int) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	add_theme_stylebox_override("normal", style)
	add_theme_stylebox_override("hover", style)
	add_theme_stylebox_override("pressed", style)
	add_theme_stylebox_override("focus", style)


func _make_portrait_signature() -> String:
	var body_state := _body_debug_state()
	var attached: Array = body_state.get("attached_item_paths", []) if body_state.get("attached_item_paths", []) is Array else []
	return "%s:%s:%s:%s:%s" % [
		actor_id,
		str(record.get("member_name", "")),
		str(record.get("equipment_summary", "")),
		str(body_state.get("body_archetype", "")),
		str(attached),
	]


func _body_debug_state() -> Dictionary:
	var debug_state := {}
	if projection != null and is_instance_valid(projection) and projection.has_method("get_projection_debug_state"):
		debug_state = projection.call("get_projection_debug_state")
	return debug_state.get("body_state", {}) if debug_state.get("body_state", {}) is Dictionary else {}


func _release_projection_portrait_source() -> void:
	if projection == null or not is_instance_valid(projection) or not projection.has_method("get_body_projection"):
		return
	var body = projection.call("get_body_projection")
	if body is Node and (body as Node).has_method("release_portrait_source"):
		(body as Node).call("release_portrait_source")


func _child_names(node: Node) -> Array[String]:
	var names: Array[String] = []
	if node == null:
		return names
	for child in node.get_children():
		names.append(String(child.name))
	return names
