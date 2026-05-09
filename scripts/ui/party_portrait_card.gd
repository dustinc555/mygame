extends Button

class_name PartyPortraitCard

signal portrait_pressed(member, double_click, add_select)

const CHARACTER_VISUAL_NODE_NAME := "CharacterVisual"
const PORTRAIT_VISUAL_YAW_OFFSET := PI
const PORTRAIT_IDLE_POSE_SECONDS := 0.45
const PORTRAIT_IDLE_ANIMATION_NAMES := ["Idle_FoldArms", "Idle"]
const PORTRAIT_SKIP_NODE_NAMES := {
	"InspectRing": true,
	"SelectionRing": true,
}

var member: HumanoidCharacter

@onready var viewport: SubViewport = $Margin/VBox/PortraitViewportContainer/SubViewport
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


func setup(target_member: HumanoidCharacter) -> void:
	member = target_member
	if name_label == null:
		call_deferred("_deferred_setup")
		return
	name_label.text = target_member.member_name
	call_deferred("_rebuild_portrait")


func apply_state(is_selected: bool, is_followed: bool) -> void:
	if name_label == null or member == null:
		return
	name_label.text = member.member_name
	if is_selected or is_followed:
		_set_style(Color(0.26, 0.22, 0.12, 0.98), Color(1.0, 0.88, 0.45, 1.0), 3)
	else:
		_set_style(Color(0.16, 0.16, 0.18, 0.96), Color(0.34, 0.34, 0.38, 1.0), 1)


func _deferred_setup() -> void:
	if member == null or name_label == null:
		return
	name_label.text = member.member_name
	call_deferred("_rebuild_portrait")


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
	for child in member.get_children():
		_add_portrait_copy(child)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	call_deferred("_capture_snapshot")


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


func _capture_snapshot() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if image == null:
		return
	var texture := ImageTexture.create_from_image(image)
	portrait_image.texture = texture


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
