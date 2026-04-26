extends PanelContainer

class_name InventoryWindow

signal close_requested(member)
signal transfer_requested(source_member, target_member, entry, target_cell)

@export var transfer_distance := 5.0

var member: PartyMember
var _dragging := false
var _drag_offset := Vector2.ZERO

@onready var title_label: Label = $Margin/WindowVBox/TitleBar/TitleBarHBox/Title
@onready var auto_sort_button: Button = $Margin/WindowVBox/TitleBar/TitleBarHBox/AutoSortButton
@onready var close_button: Button = $Margin/WindowVBox/TitleBar/TitleBarHBox/CloseButton
@onready var warning_label: Label = $Margin/WindowVBox/WarningLabel
@onready var weight_label: Label = $Margin/WindowVBox/WeightLabel
@onready var inventory_grid: InventoryGridControl = $Margin/WindowVBox/InventoryGrid
@onready var title_bar: PanelContainer = $Margin/WindowVBox/TitleBar


func _ready() -> void:
	auto_sort_button.pressed.connect(_on_auto_sort_pressed)
	close_button.pressed.connect(_on_close_pressed)
	title_bar.gui_input.connect(_on_title_bar_gui_input)
	inventory_grid.drop_validator = Callable(self, "_can_accept_drop")
	inventory_grid.drop_handler = Callable(self, "_handle_drop")


func setup(target_member: PartyMember) -> void:
	member = target_member
	member.inventory_changed.connect(refresh)
	refresh()


func refresh() -> void:
	if member == null:
		return
	title_label.text = "%s Inventory" % member.member_name
	weight_label.text = "Weight: %.1f / %.1f" % [member.inventory.get_total_weight(), member.inventory.max_weight]
	inventory_grid.set_inventory_data(member.inventory)
	inventory_grid.set_meta("source_member", member)


func show_warning(message: String) -> void:
	warning_label.text = message
	warning_label.visible = true


func clear_warning() -> void:
	warning_label.visible = false
	warning_label.text = ""


func _can_accept_drop(data, target_cell: Vector2i) -> bool:
	clear_warning()
	if member == null or typeof(data) != TYPE_DICTIONARY:
		return false
	if not data.has("entry") or not data.has("source_member"):
		return false
	var source_member = data["source_member"]
	var entry = data["entry"]
	if source_member == member:
		if member.inventory.can_place_item(entry.definition, target_cell, entry):
			return true
		return false
	if source_member.global_position.distance_to(member.global_position) > transfer_distance:
		show_warning("Too far away")
		return false
	if member.inventory.get_total_weight() + entry.definition.unit_weight * entry.count > member.inventory.max_weight:
		show_warning("Too heavy")
		return false
	if not member.inventory.can_place_item(entry.definition, target_cell):
		return false
	return true


func _handle_drop(data, target_cell: Vector2i) -> void:
	if not _can_accept_drop(data, target_cell):
		return
	transfer_requested.emit(data["source_member"], member, data["entry"], target_cell)


func _on_close_pressed() -> void:
	close_requested.emit(member)


func _on_auto_sort_pressed() -> void:
	if member == null:
		return
	clear_warning()
	if not member.inventory.auto_sort():
		show_warning("Sort failed")


func _on_title_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _dragging:
			_drag_offset = get_global_mouse_position() - position
		accept_event()
		return

	if event is InputEventMouseMotion and _dragging:
		position = get_global_mouse_position() - _drag_offset
		accept_event()
