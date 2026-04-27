extends Button

class_name PartyPortraitCard

signal portrait_pressed(member, double_click, add_select)

var member: PartyMember

@onready var viewport: SubViewport = $Margin/VBox/PortraitViewportContainer/SubViewport
@onready var portrait_root: Node3D = $Margin/VBox/PortraitViewportContainer/SubViewport/PortraitRoot
@onready var name_label: Label = $Margin/VBox/Name


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_color_override("font_color", Color(0.92, 0.92, 0.92, 1.0))
	add_theme_color_override("font_hover_color", Color(0.92, 0.92, 0.92, 1.0))
	add_theme_color_override("font_pressed_color", Color(0.92, 0.92, 0.92, 1.0))
	add_theme_color_override("font_focus_color", Color(0.92, 0.92, 0.92, 1.0))
	add_theme_color_override("font_disabled_color", Color(0.92, 0.92, 0.92, 1.0))


func setup(target_member: PartyMember) -> void:
	member = target_member
	if name_label == null:
		call_deferred("_deferred_setup")
		return
	name_label.text = target_member.member_name
	call_deferred("_rebuild_portrait")


func apply_state(is_selected: bool, is_followed: bool) -> void:
	if name_label == null or member == null:
		return
	var prefix := ""
	if is_followed:
		prefix = "[Follow] "
	elif is_selected:
		prefix = "[Selected] "
	name_label.text = prefix + member.member_name
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


func _set_style(background: Color, border: Color, border_width: int) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	add_theme_stylebox_override("normal", style)
	add_theme_stylebox_override("hover", style)
	add_theme_stylebox_override("pressed", style)
	add_theme_stylebox_override("focus", style)
