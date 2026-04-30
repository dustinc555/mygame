extends PanelContainer

class_name ConversationWindow

signal response_selected(response_index)

var _buttons: Array[Button] = []

@onready var speaker_label: Label = $Margin/Layout/CenterColumn/SpeakerLabel
@onready var transcript_label: RichTextLabel = $Margin/Layout/CenterColumn/Transcript
@onready var response_container: VBoxContainer = $Margin/Layout/CenterColumn/Responses
@onready var left_name_label: Label = $Margin/Layout/LeftPortraitPanel/Margin/VBox/Name
@onready var left_viewport: SubViewport = $Margin/Layout/LeftPortraitPanel/Margin/VBox/PortraitViewportContainer/SubViewport
@onready var left_portrait_root: Node3D = $Margin/Layout/LeftPortraitPanel/Margin/VBox/PortraitViewportContainer/SubViewport/PortraitRoot
@onready var left_portrait_image: TextureRect = $Margin/Layout/LeftPortraitPanel/Margin/VBox/PortraitImage
@onready var right_name_label: Label = $Margin/Layout/RightPortraitPanel/Margin/VBox/Name
@onready var right_viewport: SubViewport = $Margin/Layout/RightPortraitPanel/Margin/VBox/PortraitViewportContainer/SubViewport
@onready var right_portrait_root: Node3D = $Margin/Layout/RightPortraitPanel/Margin/VBox/PortraitViewportContainer/SubViewport/PortraitRoot
@onready var right_portrait_image: TextureRect = $Margin/Layout/RightPortraitPanel/Margin/VBox/PortraitImage

var _response_style := StyleBoxFlat.new()
var _response_hover_style := StyleBoxFlat.new()


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
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
	_rebuild_portrait(left_actor, left_portrait_root, left_viewport, left_portrait_image)
	_rebuild_portrait(right_actor, right_portrait_root, right_viewport, right_portrait_image)
	for button in _buttons:
		button.queue_free()
	_buttons.clear()
	for index in range(responses.size()):
		var response_data: Dictionary = responses[index]
		var button := Button.new()
		button.text = response_data.get("text", "")
		button.disabled = response_data.get("disabled", false)
		button.focus_mode = Control.FOCUS_NONE
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_stylebox_override("normal", _response_style)
		button.add_theme_stylebox_override("hover", _response_hover_style)
		button.add_theme_stylebox_override("pressed", _response_hover_style)
		button.add_theme_stylebox_override("focus", _response_hover_style)
		button.add_theme_color_override("font_color", Color(0.95, 0.92, 0.86, 1.0))
		button.add_theme_color_override("font_hover_color", Color(0.98, 0.96, 0.9, 1.0))
		button.add_theme_color_override("font_pressed_color", Color(0.98, 0.96, 0.9, 1.0))
		button.add_theme_color_override("font_focus_color", Color(0.98, 0.96, 0.9, 1.0))
		button.add_theme_color_override("font_disabled_color", Color(0.62, 0.58, 0.52, 1.0))
		button.pressed.connect(_on_response_pressed.bind(index))
		response_container.add_child(button)
		_buttons.append(button)
	visible = true
	if not _buttons.is_empty() and not _buttons[0].disabled:
		_buttons[0].grab_focus()


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


func _rebuild_portrait(actor, portrait_root: Node3D, viewport: SubViewport, portrait_image: TextureRect) -> void:
	_clear_portrait_root(portrait_root)
	portrait_image.texture = null
	if actor == null:
		return
	for child in actor.get_children():
		if not (child is MeshInstance3D):
			continue
		if child.name == "SelectionRing" or child.name == "InspectRing":
			continue
		var copy = child.duplicate()
		if copy is MeshInstance3D:
			copy.transform = child.transform
			if child.material_override != null:
				copy.material_override = child.material_override.duplicate()
			portrait_root.add_child(copy)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	call_deferred("_capture_snapshot", viewport, portrait_image)


func _clear_portrait_root(portrait_root: Node3D) -> void:
	for child in portrait_root.get_children():
		portrait_root.remove_child(child)
		child.queue_free()


func _capture_snapshot(viewport: SubViewport, portrait_image: TextureRect) -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if image == null:
		return
	portrait_image.texture = ImageTexture.create_from_image(image)
