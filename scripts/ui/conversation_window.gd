extends PanelContainer

class_name ConversationWindow

signal response_selected(response_index)

const CHARACTER_VISUAL_NODE_NAME := "CharacterVisual"
const PORTRAIT_VISUAL_YAW_OFFSET := PI
const PORTRAIT_INWARD_YAW := 0.13962634
const PORTRAIT_IDLE_POSE_SECONDS := 0.45
const PORTRAIT_IDLE_ANIMATION_NAMES := ["Idle"]
const PORTRAIT_FOV := 24.0
const PORTRAIT_TARGET_HEIGHT_RATIO := 0.84
const PORTRAIT_DISTANCE_HEIGHT_RATIO := 0.76
const PORTRAIT_MIN_DISTANCE := 1.18
const PORTRAIT_CAMERA_SIDE_OFFSET := 0.05
const PORTRAIT_CAMERA_ELEVATION_OFFSET := 0.02
const PORTRAIT_SKIP_NODE_NAMES := {
	"InspectRing": true,
	"SelectionRing": true,
}

var _buttons: Array[Button] = []

@onready var speaker_label: Label = $Margin/Layout/CenterColumn/SpeakerLabel
@onready var transcript_label: RichTextLabel = $Margin/Layout/CenterColumn/Transcript
@onready var response_container: VBoxContainer = $Margin/Layout/CenterColumn/Responses
@onready var left_name_label: Label = $Margin/Layout/LeftPortraitPanel/Margin/VBox/Name
@onready var left_viewport: SubViewport = $Margin/Layout/LeftPortraitPanel/Margin/VBox/PortraitViewportContainer/SubViewport
@onready var left_portrait_camera: Camera3D = $Margin/Layout/LeftPortraitPanel/Margin/VBox/PortraitViewportContainer/SubViewport/Camera3D
@onready var left_portrait_root: Node3D = $Margin/Layout/LeftPortraitPanel/Margin/VBox/PortraitViewportContainer/SubViewport/PortraitRoot
@onready var left_portrait_image: TextureRect = $Margin/Layout/LeftPortraitPanel/Margin/VBox/PortraitImage
@onready var right_name_label: Label = $Margin/Layout/RightPortraitPanel/Margin/VBox/Name
@onready var right_viewport: SubViewport = $Margin/Layout/RightPortraitPanel/Margin/VBox/PortraitViewportContainer/SubViewport
@onready var right_portrait_camera: Camera3D = $Margin/Layout/RightPortraitPanel/Margin/VBox/PortraitViewportContainer/SubViewport/Camera3D
@onready var right_portrait_root: Node3D = $Margin/Layout/RightPortraitPanel/Margin/VBox/PortraitViewportContainer/SubViewport/PortraitRoot
@onready var right_portrait_image: TextureRect = $Margin/Layout/RightPortraitPanel/Margin/VBox/PortraitImage

var _response_style := StyleBoxFlat.new()
var _response_hover_style := StyleBoxFlat.new()


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	_response_style.bg_color = Color(0.2, 0.17, 0.13, 1.0)
	_response_style.border_color = Color(0.46, 0.38, 0.24, 1.0)
	_response_style.set_border_width_all(1)
	_response_style.set_corner_radius_all(6)
	_response_style.content_margin_left = 10
	_response_style.content_margin_right = 10
	_response_style.content_margin_top = 8
	_response_style.content_margin_bottom = 8
	_response_hover_style = _response_style.duplicate()
	_response_hover_style.bg_color = Color(0.28, 0.22, 0.15, 1.0)


func show_conversation(speaker_name: String, transcript: String, responses: Array, left_actor, right_actor) -> void:
	speaker_label.text = speaker_name
	transcript_label.text = transcript
	left_name_label.text = _get_actor_name(left_actor, "Speaker")
	right_name_label.text = _get_actor_name(right_actor, "Listener")
	_rebuild_portrait(left_actor, left_portrait_root, left_viewport, left_portrait_image, left_portrait_camera, PORTRAIT_INWARD_YAW)
	_rebuild_portrait(right_actor, right_portrait_root, right_viewport, right_portrait_image, right_portrait_camera, -PORTRAIT_INWARD_YAW)
	for button in _buttons:
		button.queue_free()
	_buttons.clear()
	for index in range(responses.size()):
		var response_data: Dictionary = responses[index]
		var button := Button.new()
		button.text = response_data.get("text", "")
		button.disabled = response_data.get("disabled", false)
		button.focus_mode = Control.FOCUS_ALL
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_stylebox_override("normal", _response_style)
		button.add_theme_stylebox_override("hover", _response_hover_style)
		button.add_theme_stylebox_override("pressed", _response_hover_style)
		button.add_theme_stylebox_override("focus", _response_hover_style)
		var font_color: Color = response_data.get("font_color", Color(0.95, 0.92, 0.86, 1.0))
		button.add_theme_color_override("font_color", font_color)
		button.add_theme_color_override("font_hover_color", font_color.lightened(0.08))
		button.add_theme_color_override("font_pressed_color", font_color.lightened(0.08))
		button.add_theme_color_override("font_focus_color", font_color.lightened(0.08))
		button.add_theme_color_override("font_disabled_color", Color(0.62, 0.58, 0.52, 1.0))
		button.pressed.connect(_on_response_pressed.bind(index))
		response_container.add_child(button)
		_buttons.append(button)
	visible = true
	for button in _buttons:
		if not button.disabled:
			button.call_deferred("grab_focus")
			break


func hide_conversation() -> void:
	visible = false
	for button in _buttons:
		button.queue_free()
	_buttons.clear()
	speaker_label.text = ""
	transcript_label.text = ""
	left_name_label.text = ""
	right_name_label.text = ""
	left_portrait_image.texture = null
	right_portrait_image.texture = null
	_clear_portrait_root(left_portrait_root)
	_clear_portrait_root(right_portrait_root)


func _on_response_pressed(response_index: int) -> void:
	response_selected.emit(response_index)


func _get_actor_name(actor, fallback: String) -> String:
	if actor != null:
		return actor.member_name
	return fallback


func _rebuild_portrait(actor, portrait_root: Node3D, viewport: SubViewport, portrait_image: TextureRect, portrait_camera: Camera3D, visual_yaw_offset: float) -> void:
	_clear_portrait_root(portrait_root)
	portrait_image.texture = null
	if actor == null:
		return
	var visual_root: Node = actor.get_character_visual_root() if actor.has_method("get_character_visual_root") else null
	if visual_root != null:
		_add_portrait_copy(visual_root, portrait_root, visual_yaw_offset)
	for child in actor.get_children():
		if child == visual_root:
			continue
		_add_portrait_copy(child, portrait_root, visual_yaw_offset)
	_frame_portrait_camera(portrait_root, portrait_camera)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	call_deferred("_capture_snapshot", viewport, portrait_image)


func _frame_portrait_camera(portrait_root: Node3D, portrait_camera: Camera3D) -> void:
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
	var target := Vector3(clampf(center.x, -0.10, 0.10), bounds.position.y + height * PORTRAIT_TARGET_HEIGHT_RATIO, clampf(center.z, -0.08, 0.08))
	var distance := maxf(PORTRAIT_MIN_DISTANCE, height * PORTRAIT_DISTANCE_HEIGHT_RATIO)
	portrait_camera.position = target + Vector3(PORTRAIT_CAMERA_SIDE_OFFSET, height * 0.01 + PORTRAIT_CAMERA_ELEVATION_OFFSET, distance)
	portrait_camera.look_at(target, Vector3.UP)


func _add_portrait_copy(source: Node, portrait_root: Node3D, visual_yaw_offset: float) -> void:
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
		copy.rotation.y += PORTRAIT_VISUAL_YAW_OFFSET + visual_yaw_offset
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


func _clear_portrait_root(portrait_root: Node3D) -> void:
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


func _capture_snapshot(viewport: SubViewport, portrait_image: TextureRect) -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if image == null:
		return
	portrait_image.texture = ImageTexture.create_from_image(image)
