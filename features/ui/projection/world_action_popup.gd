extends PopupPanel
class_name WorldActionPopup

## World-action rows need individual warning colors. PopupMenu only offers
## whole-menu font colors, which misleadingly made Heal/Carry look illegal.
signal id_pressed(id: int)

var _rows := VBoxContainer.new()

func _init() -> void:
	add_child(_rows)

func _ready() -> void:
	add_theme_stylebox_override("panel", get_theme_stylebox("panel", "PopupMenu"))
	_rows.add_theme_constant_override("separation", 0)
	about_to_popup.connect(_focus_first.call_deferred)

func set_actions(actions: Array) -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for action in actions:
		var button := Button.new()
		button.text = str(action.get("label", "Action"))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(140, 30)
		button.disabled = bool(action.get("disabled", false))
		button.tooltip_text = str(action.get("tooltip", ""))
		var normal := StyleBoxEmpty.new()
		normal.content_margin_left = 10
		normal.content_margin_right = 14
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", get_theme_stylebox("hover", "PopupMenu"))
		button.add_theme_stylebox_override("focus", get_theme_stylebox("hover", "PopupMenu"))
		button.add_theme_font_override("font", get_theme_font("font", "PopupMenu"))
		button.add_theme_font_size_override("font_size", get_theme_font_size("font_size", "PopupMenu"))
		var color: Color = action.get("color", Color.TRANSPARENT)
		if color.a <= 0.0:
			color = get_theme_color("font_color", "PopupMenu")
		for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
			button.add_theme_color_override(state, color)
		button.pressed.connect(_choose.bind(int(action.get("id", -1))))
		_rows.add_child(button)
	reset_size()

func get_action_button(index: int) -> Button:
	return _rows.get_child(index) as Button

func _focus_first() -> void:
	if _rows.get_child_count() > 0 and visible:
		get_action_button(0).grab_focus()

func _choose(id: int) -> void:
	hide()
	id_pressed.emit(id)
