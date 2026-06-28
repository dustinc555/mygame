extends Button

class_name PartyPortraitCard

signal portrait_pressed(member, double_click, add_select)

const CHARACTER_VISUAL_NODE_NAME := "CharacterVisual"
const PORTRAIT_VISUAL_YAW_OFFSET := PI
const PORTRAIT_IDLE_POSE_SECONDS := 0.45
const PORTRAIT_IDLE_ANIMATION_NAMES := ["Idle"]
const PORTRAIT_FOV := 26.0
const PORTRAIT_TARGET_HEIGHT_RATIO := 0.84
const PORTRAIT_DISTANCE_HEIGHT_RATIO := 0.70
const PORTRAIT_MIN_DISTANCE := 1.20
const PORTRAIT_CAMERA_SIDE_OFFSET := 0.08
const PORTRAIT_CAMERA_ELEVATION_OFFSET := 0.03
# TODO: make better by moving species portrait framing into BodyProjection metadata instead of branching here.
const ROBOT_PORTRAIT_TARGET_HEIGHT_RATIO := 0.66
const ROBOT_PORTRAIT_DISTANCE_HEIGHT_RATIO := 1.12
const ROBOT_PORTRAIT_MIN_DISTANCE := 1.75
const ROBOT_PORTRAIT_CAMERA_ELEVATION_OFFSET := 0.02
const PORTRAIT_SKIP_NODE_NAMES := {
	"InspectRing": true,
	"SelectionRing": true,
}

var member: WorldActor
var _portrait_refresh_queued := false

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


func setup(target_member: WorldActor) -> void:
	_disconnect_member_appearance_changed()
	member = target_member
	_connect_member_appearance_changed()
	if name_label == null:
		call_deferred("_deferred_setup")
		return
	name_label.text = target_member.member_name
	call_deferred("_rebuild_portrait")


func _exit_tree() -> void:
	_disconnect_member_appearance_changed()


func apply_state(is_selected: bool, is_followed: bool) -> void:
	if name_label == null or member == null:
		return
	name_label.text = member.member_name
	if is_selected or is_followed:
		_set_style(Color(0.26, 0.22, 0.12, 0.98), Color(1.0, 0.88, 0.45, 1.0), 3)
	else:
		_set_style(Color(0.16, 0.16, 0.18, 0.96), Color(0.34, 0.34, 0.38, 1.0), 1)


func refresh_portrait() -> void:
	if _portrait_refresh_queued:
		return
	_portrait_refresh_queued = true
	call_deferred("_deferred_refresh_portrait")


func _deferred_setup() -> void:
	if member == null or name_label == null:
		return
	name_label.text = member.member_name
	call_deferred("_rebuild_portrait")


func _deferred_refresh_portrait() -> void:
	_portrait_refresh_queued = false
	if not is_inside_tree() or member == null or portrait_root == null:
		return
	_rebuild_portrait()


func _connect_member_appearance_changed() -> void:
	if member == null or not member.has_signal("appearance_changed"):
		return
	var changed_callable := Callable(self, "_on_member_appearance_changed")
	if not member.is_connected("appearance_changed", changed_callable):
		member.connect("appearance_changed", changed_callable)


func _disconnect_member_appearance_changed() -> void:
	if member == null or not is_instance_valid(member) or not member.has_signal("appearance_changed"):
		return
	var changed_callable := Callable(self, "_on_member_appearance_changed")
	if member.is_connected("appearance_changed", changed_callable):
		member.disconnect("appearance_changed", changed_callable)


func _on_member_appearance_changed() -> void:
	refresh_portrait()


func _gui_input(event: InputEvent) -> void:
	if member == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		portrait_pressed.emit(member, event.double_click, event.alt_pressed)


func _rebuild_portrait() -> void:
	for child in portrait_root.get_children():
		portrait_root.remove_child(child)
		child.queue_free()
	if member == null:
		return
	var visual_root := member.get_character_visual_root()
	if visual_root != null:
		_add_portrait_copy(visual_root)
	for child in member.get_children():
		if child == visual_root:
			continue
		_add_portrait_copy(child)
	_frame_portrait_camera()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	call_deferred("_capture_snapshot")


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
	var target_ratio := ROBOT_PORTRAIT_TARGET_HEIGHT_RATIO if _is_robot_member() else PORTRAIT_TARGET_HEIGHT_RATIO
	var distance_ratio := ROBOT_PORTRAIT_DISTANCE_HEIGHT_RATIO if _is_robot_member() else PORTRAIT_DISTANCE_HEIGHT_RATIO
	var min_distance := ROBOT_PORTRAIT_MIN_DISTANCE if _is_robot_member() else PORTRAIT_MIN_DISTANCE
	var elevation_offset := ROBOT_PORTRAIT_CAMERA_ELEVATION_OFFSET if _is_robot_member() else PORTRAIT_CAMERA_ELEVATION_OFFSET
	var target := Vector3(clampf(center.x, -0.12, 0.12), bounds.position.y + height * target_ratio, clampf(center.z, -0.10, 0.10))
	var distance := maxf(min_distance, height * distance_ratio)
	portrait_camera.position = target + Vector3(PORTRAIT_CAMERA_SIDE_OFFSET, height * 0.015 + elevation_offset, distance)
	portrait_camera.look_at(target, Vector3.UP)


func _add_portrait_copy(source: Node) -> void:
	var source_name := String(source.name)
	if PORTRAIT_SKIP_NODE_NAMES.has(source_name):
		return
	if source_name != CHARACTER_VISUAL_NODE_NAME and not (source is MeshInstance3D):
		return
	var mesh_source := source as MeshInstance3D
	if mesh_source != null and not mesh_source.visible:
		return
	var copy := source.duplicate()
	if not (copy is Node3D):
		copy.queue_free()
		return
	copy.transform = (source as Node3D).transform
	if source_name == CHARACTER_VISUAL_NODE_NAME:
		copy.rotation.y += PORTRAIT_VISUAL_YAW_OFFSET
	_duplicate_portrait_materials(copy)
	portrait_root.add_child(copy)
	if source_name == CHARACTER_VISUAL_NODE_NAME:
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
	animation_player.stop(true)


func _get_portrait_idle_animation_name(animation_player: AnimationPlayer) -> String:
	for animation_name_value in PORTRAIT_IDLE_ANIMATION_NAMES:
		var animation_name := String(animation_name_value)
		if animation_player.has_animation(animation_name):
			return animation_name
	return ""


func _is_robot_member() -> bool:
	var race = member.get("character_race") if member != null else null
	if race == null:
		return false
	return str(race.get("race_id")) == "quadbot"


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for child in root.get_children():
		var animation_player := _find_animation_player(child)
		if animation_player != null:
			return animation_player
	return null


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
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if image == null:
		return
	if image.get_format() == Image.FORMAT_RGB8:
		image.convert(Image.FORMAT_RGBA8)
	var texture := ImageTexture.create_from_image(image)
	portrait_image.texture = texture
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_replace_portrait_copy_with_snapshot_marker()


func _replace_portrait_copy_with_snapshot_marker() -> void:
	if portrait_root == null:
		return
	for child in portrait_root.get_children():
		portrait_root.remove_child(child)
		child.queue_free()
	var marker := Node3D.new()
	marker.name = "PortraitSnapshotMarker"
	portrait_root.add_child(marker)


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
