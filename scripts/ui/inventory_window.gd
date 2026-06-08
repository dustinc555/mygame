extends PanelContainer

class_name InventoryWindow

signal close_requested(inventory_owner)
signal transfer_requested(source_owner, target_owner, entry, target_cell)
signal quick_transfer_requested(inventory_owner, entry)
signal notice_requested(message)
signal item_action_requested(inventory_owner, entry, action)
signal equip_requested(source_owner, entry, target_owner, slot_name)
signal equipment_transfer_requested(source_owner, source_slot_name, target_owner, target_slot_name)
signal unequip_requested(source_owner, slot_name, target_owner, target_cell)
signal item_drop_requested(source_owner, entry)
signal equipment_drop_requested(source_owner, slot_name)
signal cursor_item_place_requested(data, target_owner, target_cell)
signal cursor_item_equip_requested(data, target_owner, slot_name)
signal sort_requested(inventory_owner)

@export var transfer_distance := 5.0

const ACTION_EAT := 1
const ACTION_TAKE_SILVER_1 := 101
const ACTION_TAKE_SILVER_5 := 105
const ACTION_TAKE_SILVER_10 := 110
const ACTION_TAKE_SILVER_HALF := 150
const ACTION_TAKE_SILVER_QUARTER := 125
const NO_POUCH_DEPOSIT := "__no_pouch_deposit__"
const PLAYER_STAT_LABELS := {
	"attack_damage": "Damage",
	"dodge_chance": "Dodge",
	"block_chance": "Block",
	"attack_range": "Range",
	"attack_cooldown": "Cooldown",
	"cut_ratio": "Cut",
	"strength": "Strength",
	"perception": "Perception",
	"dexterity": "Dexterity",
	"toughness": "Toughness",
	"endurance": "Endurance",
	"move_speed_multiplier": "Move Speed",
	"healing_rate": "Healing",
	"fatigue_recovery_rate": "Fatigue Recovery",
	"hunger_drain_rate": "Hunger Drain",
}
const GEAR_STAT_ORDER := [
	"attack_damage",
	"dodge_chance",
	"block_chance",
	"attack_range",
	"attack_cooldown",
	"cut_ratio",
	"strength",
	"dexterity",
	"toughness",
	"endurance",
	"perception",
]

var inventory_owner
var _dragging := false
var _drag_offset := Vector2.ZERO
var _inventory_body: HBoxContainer
var _equipment_section: VBoxContainer
var _equipment_grid: GridContainer
var _equipment_slots: Dictionary = {}
var _gear_effects_section: VBoxContainer
var _gear_effects_grid: GridContainer
var _gear_effect_debug_rows: Dictionary = {}
var _gear_effects_signature := "<unset>"

@onready var title_label: Label = $Margin/WindowVBox/TitleBar/TitleBarHBox/Title
@onready var auto_sort_button: Button = $Margin/WindowVBox/TitleBar/TitleBarHBox/AutoSortButton
@onready var close_button: Button = $Margin/WindowVBox/TitleBar/TitleBarHBox/CloseButton
@onready var warning_label: Label = $Margin/WindowVBox/WarningLabel
@onready var weight_label: Label = $Margin/WindowVBox/WeightLabel
@onready var inventory_grid: InventoryGridControl = $Margin/WindowVBox/InventoryGrid
@onready var title_bar: PanelContainer = $Margin/WindowVBox/TitleBar
@onready var item_menu: PopupMenu = $ItemMenu

var _context_entry


func _ready() -> void:
	_ensure_inventory_body()
	_ensure_equipment_section()
	_ensure_gear_effects_section()
	title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title_label.mouse_default_cursor_shape = Control.CURSOR_MOVE
	var title_row := title_bar.get_node_or_null("TitleBarHBox") as Control
	if title_row != null:
		title_row.mouse_default_cursor_shape = Control.CURSOR_MOVE
	auto_sort_button.pressed.connect(_on_auto_sort_pressed)
	close_button.pressed.connect(_on_close_pressed)
	title_bar.gui_input.connect(_on_title_bar_gui_input)
	inventory_grid.drop_validator = Callable(self, "_can_accept_drop")
	inventory_grid.drop_handler = Callable(self, "_handle_drop")
	inventory_grid.drop_error_provider = Callable(self, "_get_drop_error")
	inventory_grid.item_right_clicked.connect(_on_inventory_item_right_clicked)
	inventory_grid.invalid_drop_attempted.connect(_on_invalid_drop_attempted)
	inventory_grid.item_dropped_outside.connect(_on_inventory_item_dropped_outside)
	item_menu.id_pressed.connect(_on_item_menu_id_pressed)


func setup(target_owner) -> void:
	inventory_owner = target_owner
	if inventory_owner.has_signal("inventory_changed"):
		inventory_owner.inventory_changed.connect(refresh)
	refresh()
	call_deferred("fit_to_content")


func refresh() -> void:
	if inventory_owner == null:
		return
	title_label.text = _get_owner_inventory_title()
	var inventory = _get_owner_inventory()
	if _owner_shows_weight():
		weight_label.visible = true
		weight_label.text = "Weight: %.1f / %.1f" % [inventory.get_total_weight(), inventory.max_weight]
	else:
		weight_label.visible = false
	if inventory_owner.has_method("get_inventory_cell_size"):
		inventory_grid.cell_size = inventory_owner.get_inventory_cell_size()
	else:
		inventory_grid.cell_size = Vector2(30.0, 30.0)
	inventory_grid.set_inventory_data(inventory)
	inventory_grid.set_meta("source_owner", inventory_owner)
	_refresh_equipment_slots()
	_refresh_gear_effects()
	if not _dragging:
		call_deferred("fit_to_content")


func show_warning(message: String) -> void:
	warning_label.text = message
	warning_label.visible = true
	call_deferred("fit_to_content")


func clear_warning() -> void:
	warning_label.visible = false
	warning_label.text = ""
	call_deferred("fit_to_content")


func get_combat_stats_debug_state() -> Dictionary:
	return {
		"visible": _gear_effects_section.visible if _gear_effects_section != null else false,
		"columns": int(_gear_effects_grid.columns) if _gear_effects_grid != null else 0,
		"effects": _gear_effect_debug_rows.duplicate(true),
	}


func get_inventory_layout_debug_state() -> Dictionary:
	var body_order: Array[String] = []
	if _inventory_body != null:
		for child in _inventory_body.get_children():
			body_order.append(str(child.name))
	return {
		"has_body": _inventory_body != null,
		"body_order": body_order,
		"equipment_columns": int(_equipment_grid.columns) if _equipment_grid != null else 0,
		"combat_stat_columns": int(_gear_effects_grid.columns) if _gear_effects_grid != null else 0,
	}


func _can_accept_drop(data, target_cell: Vector2i) -> bool:
	clear_warning()
	return _get_drop_error(data, target_cell) == ""


func _get_drop_error(data, target_cell: Vector2i) -> String:
	if inventory_owner == null or typeof(data) != TYPE_DICTIONARY:
		return ""
	var pouch_deposit_error := _get_pouch_deposit_error(data, target_cell)
	if pouch_deposit_error != NO_POUCH_DEPOSIT:
		return pouch_deposit_error
	if data.has("cursor_item") and data.has("item_definition"):
		return _get_cursor_item_drop_error(data, target_cell)
	if data.has("equipment_owner") and data.has("equip_slot") and data.has("item_definition"):
		return _get_equipment_drop_to_grid_error(data, target_cell)
	if not data.has("entry") or not data.has("source_owner"):
		return ""
	var source_owner = data["source_owner"]
	var entry = data["entry"]
	var inventory = _get_owner_inventory()
	if source_owner == inventory_owner:
		if inventory.can_place_item(entry.definition, target_cell, entry):
			return ""
		return "No room"
	if _owners_too_far(source_owner, inventory_owner):
		return "Too far away"
	if _entry_is_silver_pouch(entry):
		return "Drop onto pouch"
	if inventory.use_weight and inventory.get_total_weight() + entry.definition.unit_weight * entry.count > inventory.max_weight:
		return "Too heavy"
	if not inventory.can_place_item(entry.definition, target_cell):
		return "No room"
	return ""


func _handle_drop(data, target_cell: Vector2i) -> void:
	if not _can_accept_drop(data, target_cell):
		return
	if data.has("cursor_item") and data.has("item_definition"):
		cursor_item_place_requested.emit(data, inventory_owner, target_cell)
	elif data.has("equipment_owner") and data.has("equip_slot"):
		unequip_requested.emit(data["equipment_owner"], data["equip_slot"], inventory_owner, target_cell)
	else:
		transfer_requested.emit(data["source_owner"], inventory_owner, data["entry"], target_cell)


func _on_close_pressed() -> void:
	close_requested.emit(inventory_owner)


func _on_auto_sort_pressed() -> void:
	if inventory_owner == null:
		return
	clear_warning()
	if inventory_owner != null and inventory_owner.has_method("get_stack_snapshot"):
		sort_requested.emit(inventory_owner)
		return
	if not _get_owner_inventory().auto_sort():
		show_warning("Sort failed")


func _on_inventory_item_right_clicked(entry, _local_position: Vector2, shift_pressed: bool) -> void:
	if inventory_owner == null or entry == null:
		return
	if shift_pressed:
		quick_transfer_requested.emit(inventory_owner, entry)
		return
	var can_eat := false
	if inventory_owner.has_method("can_eat_inventory_entry"):
		can_eat = inventory_owner.can_eat_inventory_entry(entry)
	else:
		can_eat = inventory_owner.has_method("can_eat_item") and inventory_owner.can_eat_item(entry.definition)
	var can_take_silver := _can_take_silver_from_pouch(entry)
	if not can_eat and not can_take_silver:
		return
	_context_entry = entry
	item_menu.clear()
	if can_eat:
		item_menu.add_item("Eat", ACTION_EAT)
	if can_take_silver:
		item_menu.add_item("Take 1", ACTION_TAKE_SILVER_1)
		item_menu.add_item("Take 5", ACTION_TAKE_SILVER_5)
		item_menu.add_item("Take 10", ACTION_TAKE_SILVER_10)
		item_menu.add_item("Take 1/2", ACTION_TAKE_SILVER_HALF)
		item_menu.add_item("Take 1/4", ACTION_TAKE_SILVER_QUARTER)
	var item_rect := inventory_grid._item_rect(entry)
	var popup_position := inventory_grid.get_global_position() + item_rect.position + Vector2(item_rect.size.x + 8.0, 0.0)
	item_menu.position = Vector2i(popup_position)
	item_menu.popup()


func _on_invalid_drop_attempted(message: String) -> void:
	if message == "Too far away":
		notice_requested.emit(message)


func _on_inventory_item_dropped_outside(source_owner, entry) -> void:
	if Rect2(global_position, size).has_point(get_global_mouse_position()):
		return
	item_drop_requested.emit(source_owner, entry)


func _on_title_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		_dragging = mouse_button.pressed
		if _dragging:
			_drag_offset = _event_global_position(mouse_button) - position
			move_to_front()
		accept_event()
		return

	if event is InputEventMouseMotion and _dragging:
		position = _clamp_position_to_viewport(_event_global_position(event) - _drag_offset)
		accept_event()


func is_user_dragging() -> bool:
	return _dragging


func _event_global_position(event: InputEvent) -> Vector2:
	if event is InputEventMouse:
		return (event as InputEventMouse).global_position
	return get_global_mouse_position()


func _get_owner_display_name() -> String:
	if inventory_owner != null and inventory_owner.has_method("get_inventory_display_name"):
		return inventory_owner.get_inventory_display_name()
	return inventory_owner.name


func _get_owner_inventory_title() -> String:
	if inventory_owner != null and inventory_owner.has_method("get_inventory_display_title"):
		return inventory_owner.get_inventory_display_title()
	return "%s Inventory" % _get_owner_display_name()


func _get_owner_inventory():
	if inventory_owner != null and inventory_owner.has_method("get_inventory_for_display"):
		return inventory_owner.get_inventory_for_display()
	return inventory_owner.inventory


func _owners_too_far(source_owner, target_owner) -> bool:
	if source_owner == null or target_owner == null:
		return false
	if source_owner.has_method("get_inventory_world_position") and target_owner.has_method("get_inventory_world_position"):
		return source_owner.get_inventory_world_position().distance_to(target_owner.get_inventory_world_position()) > transfer_distance
	return false


func _owner_shows_weight() -> bool:
	if inventory_owner != null and inventory_owner.has_method("shows_inventory_weight"):
		return inventory_owner.shows_inventory_weight()
	return true


func _owner_shows_equipment() -> bool:
	if inventory_owner != null and inventory_owner.has_method("shows_inventory_equipment"):
		return inventory_owner.shows_inventory_equipment()
	return true


func _ensure_inventory_body() -> void:
	if _inventory_body != null:
		return
	var window_vbox := $Margin/WindowVBox as VBoxContainer
	_inventory_body = HBoxContainer.new()
	_inventory_body.name = "InventoryBody"
	_inventory_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_body.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_inventory_body.add_theme_constant_override("separation", 12)
	var grid_index := inventory_grid.get_index()
	window_vbox.remove_child(inventory_grid)
	window_vbox.add_child(_inventory_body)
	window_vbox.move_child(_inventory_body, grid_index)
	inventory_grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	inventory_grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_inventory_body.add_child(inventory_grid)


func _ensure_equipment_section() -> void:
	if _equipment_section != null:
		return
	_ensure_inventory_body()
	_equipment_section = VBoxContainer.new()
	_equipment_section.name = "EquipmentSection"
	_equipment_section.visible = false
	_equipment_section.custom_minimum_size = Vector2(258.0, 0.0)
	_equipment_section.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_equipment_section.add_theme_constant_override("separation", 4)
	var heading := Label.new()
	heading.name = "EquipmentHeading"
	heading.text = "Equipment"
	heading.add_theme_font_size_override("font_size", 11)
	_equipment_section.add_child(heading)
	_equipment_grid = GridContainer.new()
	_equipment_grid.name = "EquipmentGrid"
	_equipment_grid.columns = 2
	_equipment_grid.add_theme_constant_override("h_separation", 5)
	_equipment_grid.add_theme_constant_override("v_separation", 5)
	_equipment_section.add_child(_equipment_grid)
	_inventory_body.add_child(_equipment_section)


func _ensure_gear_effects_section() -> void:
	if _gear_effects_section != null:
		return
	_ensure_inventory_body()
	_gear_effects_section = VBoxContainer.new()
	_gear_effects_section.name = "CombatStatsSection"
	_gear_effects_section.visible = false
	_gear_effects_section.custom_minimum_size = Vector2(320.0, 0.0)
	_gear_effects_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gear_effects_section.add_theme_constant_override("separation", 4)
	var heading := Label.new()
	heading.name = "CombatStatsHeading"
	heading.text = "Combat Stats"
	heading.add_theme_font_size_override("font_size", 11)
	_gear_effects_section.add_child(heading)
	_gear_effects_grid = GridContainer.new()
	_gear_effects_grid.name = "CombatStatsGrid"
	_gear_effects_grid.columns = 2
	_gear_effects_grid.add_theme_constant_override("h_separation", 12)
	_gear_effects_grid.add_theme_constant_override("v_separation", 5)
	_gear_effects_section.add_child(_gear_effects_grid)
	_inventory_body.add_child(_gear_effects_section)


func _refresh_equipment_slots() -> void:
	if _equipment_section == null or _equipment_grid == null:
		return
	if inventory_owner == null or not _owner_shows_equipment() or not inventory_owner.has_method("get_equipment_slot_names"):
		_equipment_section.visible = false
		return
	_equipment_section.visible = true
	var slot_names: Array[String] = inventory_owner.get_equipment_slot_names()
	var existing_keys := _equipment_slots.keys()
	for existing_slot in existing_keys:
		if slot_names.has(str(existing_slot)):
			continue
		var existing_control: Control = _equipment_slots[existing_slot]
		_equipment_slots.erase(existing_slot)
		existing_control.queue_free()
	for slot_name in slot_names:
		var slot_control: EquipmentSlotControl = _equipment_slots.get(slot_name)
		if slot_control == null:
			slot_control = EquipmentSlotControl.new()
			_equipment_grid.add_child(slot_control)
			_equipment_slots[slot_name] = slot_control
			slot_control.slot_drop_requested.connect(_on_equipment_slot_drop_requested)
			slot_control.slot_drag_dropped_outside.connect(_on_equipment_slot_drag_dropped_outside)
		var slot_label := slot_name.capitalize()
		if inventory_owner.has_method("get_equipment_slot_label"):
			slot_label = inventory_owner.get_equipment_slot_label(slot_name)
		slot_control.setup(inventory_owner, slot_name, slot_label)


func _refresh_gear_effects() -> void:
	if _gear_effects_section == null or _gear_effects_grid == null:
		return
	if inventory_owner == null or not _owner_shows_equipment() or not inventory_owner.has_method("get_equipment_stat_profile"):
		_gear_effects_section.visible = false
		if _gear_effects_signature != "<hidden>":
			_clear_children(_gear_effects_grid)
			_gear_effect_debug_rows.clear()
			_gear_effects_signature = "<hidden>"
		return
	_gear_effects_section.visible = true
	var breakdowns := _gear_effect_breakdowns()
	var signature := _gear_effect_signature(breakdowns)
	if signature == _gear_effects_signature:
		return
	_gear_effects_signature = signature
	_clear_children(_gear_effects_grid)
	_gear_effect_debug_rows.clear()
	if breakdowns.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No combat stats"
		empty_label.add_theme_font_size_override("font_size", 10)
		empty_label.add_theme_color_override("font_color", Color(0.62, 0.59, 0.52, 1.0))
		_gear_effects_grid.add_child(empty_label)
		return
	for breakdown in breakdowns:
		var stat_root := VBoxContainer.new()
		stat_root.name = "%sGearEffect" % _to_pascal_case(str(breakdown.get("label", "Gear")).replace(" ", "_"))
		stat_root.custom_minimum_size = Vector2(145.0, 0.0)
		stat_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stat_root.add_theme_constant_override("separation", 1)
		_gear_effects_grid.add_child(stat_root)

		var summary_label := Label.new()
		summary_label.text = str(breakdown.get("summary", ""))
		summary_label.add_theme_font_size_override("font_size", 11)
		summary_label.add_theme_color_override("font_color", Color(0.92, 0.87, 0.76, 1.0))
		summary_label.clip_text = true
		stat_root.add_child(summary_label)

		var source_entries: Array = breakdown.get("sources", []) if breakdown.get("sources", []) is Array else []
		_gear_effect_debug_rows[str(breakdown.get("label", "Gear"))] = {
			"summary": str(breakdown.get("summary", "")),
			"base": str(breakdown.get("base", "")),
			"sources": _source_texts(source_entries),
			"source_tones": _source_tones(source_entries),
			"final": str(breakdown.get("final", "")),
		}
		for source_entry in source_entries:
			if source_entry is Dictionary:
				_add_gear_source_label(stat_root, source_entry as Dictionary)


func _gear_effect_breakdowns() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var profile: Dictionary = inventory_owner.call("get_equipment_stat_profile") if inventory_owner != null and inventory_owner.has_method("get_equipment_stat_profile") else {}
	if profile.is_empty():
		return result
	var modifier_totals: Dictionary = profile.get("modifier_totals", {}) if profile.get("modifier_totals", {}) is Dictionary else {}
	var base_stats: Dictionary = profile.get("base_stats", {}) if profile.get("base_stats", {}) is Dictionary else {}
	var effective_stats: Dictionary = profile.get("effective_stats", {}) if profile.get("effective_stats", {}) is Dictionary else {}
	for stat_name in _ordered_gear_stats(_combat_stat_names(base_stats, effective_stats, modifier_totals)):
		var total: Dictionary = modifier_totals.get(stat_name, {}) if modifier_totals.get(stat_name, {}) is Dictionary else {}
		var modifiers: Array = total.get("modifiers", []) if total.get("modifiers", []) is Array else []
		var base_value := float(base_stats.get(stat_name, 0.0))
		var final_value := float(effective_stats.get(stat_name, base_value))
		var source_entries: Array[Dictionary] = []
		for modifier in modifiers:
			if not (modifier is Dictionary):
				continue
			var modifier_data := modifier as Dictionary
			var contribution := _modifier_contribution_text(stat_name, modifier_data)
			if contribution.is_empty():
				continue
			var source_name := str(modifier_data.get("item_name", "Gear")).strip_edges()
			if source_name.is_empty():
				source_name = "Gear"
			source_entries.append({
				"text": "%s %s" % [contribution, source_name],
				"tone": "positive" if _modifier_is_helpful(stat_name, modifier_data) else "negative",
			})
		source_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("text", "")) < str(b.get("text", "")))
		result.append({
			"stat_name": stat_name,
			"label": _gear_stat_label(stat_name),
			"summary": "%s %s%s" % [_gear_stat_label(stat_name), _format_stat_value(stat_name, final_value), _stat_delta_text(stat_name, final_value - base_value)],
			"base": "Base %s" % _format_stat_value(stat_name, base_value),
			"sources": source_entries,
			"final": "Final %s" % _format_stat_value(stat_name, final_value),
		})
	return result


func _ordered_gear_stats(stat_names: Array) -> Array[String]:
	var remaining := {}
	for stat_name_value in stat_names:
		remaining[str(stat_name_value)] = true
	var result: Array[String] = []
	for stat_name in GEAR_STAT_ORDER:
		if remaining.has(stat_name):
			result.append(stat_name)
			remaining.erase(stat_name)
	var rest: Array[String] = []
	for stat_name_value in remaining.keys():
		rest.append(str(stat_name_value))
	rest.sort()
	result.append_array(rest)
	return result


func _combat_stat_names(base_stats: Dictionary, effective_stats: Dictionary, modifier_totals: Dictionary) -> Array[String]:
	var names := {}
	for stat_name in GEAR_STAT_ORDER:
		names[stat_name] = true
	for stat_name in base_stats.keys():
		names[str(stat_name)] = true
	for stat_name in effective_stats.keys():
		names[str(stat_name)] = true
	for stat_name in modifier_totals.keys():
		names[str(stat_name)] = true
	var result: Array[String] = []
	for stat_name in names.keys():
		result.append(str(stat_name))
	return result


func _gear_effect_signature(breakdowns: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for breakdown in breakdowns:
		parts.append(str(breakdown.get("stat_name", "")))
		parts.append(str(breakdown.get("summary", "")))
		parts.append(str(breakdown.get("base", "")))
		parts.append(str(breakdown.get("final", "")))
		var sources: Array = breakdown.get("sources", []) if breakdown.get("sources", []) is Array else []
		for source in sources:
			if source is Dictionary:
				parts.append(str((source as Dictionary).get("text", "")))
				parts.append(str((source as Dictionary).get("tone", "")))
	return "\n".join(parts)


func _add_gear_source_label(parent: VBoxContainer, source: Dictionary) -> void:
	var text := str(source.get("text", "")).strip_edges()
	if text.is_empty():
		return
	var label := Label.new()
	label.text = "  %s" % text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", _gear_source_color(str(source.get("tone", ""))))
	label.clip_text = true
	parent.add_child(label)


func _gear_source_color(tone: String) -> Color:
	return Color(0.48, 0.86, 0.45, 1.0) if tone == "positive" else Color(0.92, 0.32, 0.28, 1.0)


func _source_texts(source_entries: Array) -> Array[String]:
	var result: Array[String] = []
	for source in source_entries:
		if source is Dictionary:
			result.append(str((source as Dictionary).get("text", "")))
	return result


func _source_tones(source_entries: Array) -> Array[String]:
	var result: Array[String] = []
	for source in source_entries:
		if source is Dictionary:
			result.append(str((source as Dictionary).get("tone", "")))
	return result


func _gear_stat_label(stat_name: String) -> String:
	return str(PLAYER_STAT_LABELS.get(stat_name, _display_token(stat_name)))


func _modifier_contribution_text(stat_name: String, modifier: Dictionary) -> String:
	var parts: Array[String] = []
	var add_value := float(modifier.get("add", 0.0))
	var mul_value := float(modifier.get("mul", 1.0))
	if not is_equal_approx(add_value, 0.0):
		parts.append(_format_stat_delta(stat_name, add_value))
	if not is_equal_approx(mul_value, 1.0):
		parts.append("x%s" % _format_decimal(mul_value, 2))
	return ", ".join(parts)


func _modifier_is_helpful(stat_name: String, modifier: Dictionary) -> bool:
	var add_value := float(modifier.get("add", 0.0))
	var mul_value := float(modifier.get("mul", 1.0))
	var impact := add_value
	if not is_equal_approx(mul_value, 1.0):
		impact += mul_value - 1.0
	if not _higher_is_better(stat_name):
		impact = -impact
	return impact >= 0.0


func _higher_is_better(stat_name: String) -> bool:
	match stat_name:
		"attack_cooldown", "hunger_drain_rate":
			return false
		_:
			return true


func _stat_delta_text(stat_name: String, delta: float) -> String:
	if is_equal_approx(delta, 0.0):
		return ""
	return " (%s)" % _format_stat_delta(stat_name, delta)


func _format_stat_delta(stat_name: String, value: float) -> String:
	var prefix := "+" if value > 0.0 else "-"
	return "%s%s" % [prefix, _format_stat_value(stat_name, absf(value))]


func _format_stat_value(stat_name: String, value: float) -> String:
	if _is_percent_stat(stat_name):
		return "%s%%" % _format_decimal(value * 100.0, 0)
	match stat_name:
		"attack_cooldown", "attack_range":
			return _format_decimal(value, 2)
		_:
			return _format_decimal(value, 1)


func _is_percent_stat(stat_name: String) -> bool:
	return stat_name.ends_with("_chance") or stat_name.ends_with("_ratio")


func _format_decimal(value: float, digits: int) -> String:
	var rounded := snappedf(value, pow(10.0, -digits))
	var text := str(rounded)
	if text.contains("."):
		while text.ends_with("0"):
			text = text.substr(0, text.length() - 1)
		if text.ends_with("."):
			text = text.substr(0, text.length() - 1)
	return text


func _display_token(value: String) -> String:
	var text := value.strip_edges()
	if text.is_empty():
		return "-"
	var words := text.replace(".", "_").split("_")
	for index in range(words.size()):
		words[index] = str(words[index]).capitalize()
	return " ".join(words)


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _to_pascal_case(value: String) -> String:
	var result := ""
	for part in value.split("_"):
		if part.is_empty():
			continue
		result += part.substr(0, 1).to_upper() + part.substr(1).to_lower()
	return result


func _get_equipment_drop_to_grid_error(data: Dictionary, target_cell: Vector2i) -> String:
	var source_owner = data["equipment_owner"]
	var definition: ItemDefinition = data["item_definition"]
	if source_owner != inventory_owner and _owners_too_far(source_owner, inventory_owner):
		return "Too far away"
	var inventory = _get_owner_inventory()
	if inventory.use_weight and inventory.get_total_weight() + definition.unit_weight > inventory.max_weight:
		return "Too heavy"
	if not inventory.can_place_item(definition, target_cell):
		return "No room"
	return ""


func _get_cursor_item_drop_error(data: Dictionary, target_cell: Vector2i) -> String:
	var source_owner = data.get("source_owner", null)
	var definition: ItemDefinition = data["item_definition"]
	var count := int(data.get("count", 1))
	var contained_item_counts: Dictionary = data.get("contained_item_counts", {})
	if source_owner != inventory_owner and _owners_too_far(source_owner, inventory_owner):
		return "Too far away"
	if source_owner != null and source_owner != inventory_owner and _definition_is_silver_pouch(definition):
		return "Drop onto pouch"
	var inventory = _get_owner_inventory()
	if inventory.use_weight and inventory.get_total_weight() + inventory.get_item_weight(definition, count, contained_item_counts) > inventory.max_weight:
		return "Too heavy"
	if not inventory.can_place_item(definition, target_cell):
		return "No room"
	return ""


func _on_equipment_slot_drop_requested(slot_name: String, data) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	if data.has("cursor_item") and data.has("item_definition"):
		cursor_item_equip_requested.emit(data, inventory_owner, slot_name)
	elif data.has("entry") and data.has("source_owner"):
		equip_requested.emit(data["source_owner"], data["entry"], inventory_owner, slot_name)
	elif data.has("equipment_owner") and data.has("equip_slot"):
		equipment_transfer_requested.emit(data["equipment_owner"], data["equip_slot"], inventory_owner, slot_name)


func _on_equipment_slot_drag_dropped_outside(slot_name: String) -> void:
	if Rect2(global_position, size).has_point(get_global_mouse_position()):
		return
	equipment_drop_requested.emit(inventory_owner, slot_name)


func _on_item_menu_id_pressed(action_id: int) -> void:
	if inventory_owner == null or _context_entry == null:
		return
	match action_id:
		ACTION_EAT:
			if inventory_owner.has_method("consume_inventory_entry"):
				inventory_owner.consume_inventory_entry(_context_entry)
			else:
				item_action_requested.emit(inventory_owner, _context_entry, "eat")
		ACTION_TAKE_SILVER_1:
			item_action_requested.emit(inventory_owner, _context_entry, "take_silver_1")
		ACTION_TAKE_SILVER_5:
			item_action_requested.emit(inventory_owner, _context_entry, "take_silver_5")
		ACTION_TAKE_SILVER_10:
			item_action_requested.emit(inventory_owner, _context_entry, "take_silver_10")
		ACTION_TAKE_SILVER_HALF:
			item_action_requested.emit(inventory_owner, _context_entry, "take_silver_half")
		ACTION_TAKE_SILVER_QUARTER:
			item_action_requested.emit(inventory_owner, _context_entry, "take_silver_quarter")
	_context_entry = null


func _can_take_silver_from_pouch(entry) -> bool:
	if inventory_owner == null or entry == null:
		return false
	var party_value = inventory_owner.get("player_party_member")
	if party_value == null or not bool(party_value):
		return false
	var inventory = _get_owner_inventory()
	if inventory == null or not inventory.has_method("is_entry_currency_container") or not bool(inventory.call("is_entry_currency_container", entry, InventoryData.SILVER_ITEM)):
		return false
	return int(inventory.call("get_entry_contained_item_count", entry, InventoryData.SILVER_ITEM)) > 0


func _get_pouch_deposit_error(data: Dictionary, target_cell: Vector2i) -> String:
	var inventory = _get_owner_inventory()
	if inventory == null or not inventory.has_method("is_entry_currency_container"):
		return NO_POUCH_DEPOSIT
	var target_entry = inventory.get_entry_at_cell(target_cell)
	if target_entry == null or not bool(inventory.call("is_entry_currency_container", target_entry, InventoryData.SILVER_ITEM)):
		return NO_POUCH_DEPOSIT
	if data.has("entry") and data["entry"] == target_entry:
		return "Same pouch"
	if not _drag_data_is_silver_or_pouch(data):
		return NO_POUCH_DEPOSIT
	var source_owner = data.get("source_owner", null)
	if source_owner != inventory_owner and _owners_too_far(source_owner, inventory_owner):
		return "Too far away"
	if _drag_data_silver_amount(data) <= 0:
		return "No silver"
	if int(inventory.call("get_entry_remaining_currency_capacity", target_entry, InventoryData.SILVER_ITEM)) <= 0:
		return "Pouch full"
	return ""


func _drag_data_is_silver_or_pouch(data: Dictionary) -> bool:
	var definition = null
	if data.has("entry") and data["entry"] != null:
		definition = data["entry"].definition
	elif data.has("item_definition"):
		definition = data["item_definition"]
	if definition == null:
		return false
	return str(definition.currency_id) == str(InventoryData.SILVER_ITEM.currency_id)


func _entry_is_silver_pouch(entry) -> bool:
	return entry != null and _definition_is_silver_pouch(entry.definition)


func _definition_is_silver_pouch(definition) -> bool:
	return definition != null and str(definition.currency_id) == str(InventoryData.SILVER_ITEM.currency_id) and int(definition.currency_container_capacity) > 0


func _drag_data_silver_amount(data: Dictionary) -> int:
	if data.has("entry") and data["entry"] != null:
		var entry = data["entry"]
		if entry.definition != null and int(entry.definition.currency_container_capacity) > 0:
			var source_inventory = data.get("source_inventory", null)
			if source_inventory != null and source_inventory.has_method("get_entry_contained_item_count"):
				return int(source_inventory.call("get_entry_contained_item_count", entry, InventoryData.SILVER_ITEM))
			return int(entry.contained_item_counts.get(str(InventoryData.SILVER_ITEM.resource_path), 0))
		return int(entry.count)
	if data.has("item_definition"):
		var definition = data["item_definition"]
		if definition != null and int(definition.currency_container_capacity) > 0:
			var contained: Dictionary = data.get("contained_item_counts", {})
			return int(contained.get(str(InventoryData.SILVER_ITEM.resource_path), 0))
		return int(data.get("count", 1))
	return 0


func clamp_to_viewport() -> void:
	position = _clamp_position_to_viewport(position)


func fit_to_content() -> void:
	if not is_inside_tree():
		return
	size = get_combined_minimum_size()
	clamp_to_viewport()


func _clamp_position_to_viewport(target_position: Vector2) -> Vector2:
	var viewport_rect := get_viewport_rect()
	var max_x := maxf(0.0, viewport_rect.size.x - size.x)
	var max_y := maxf(0.0, viewport_rect.size.y - size.y)
	return Vector2(clampf(target_position.x, 0.0, max_x), clampf(target_position.y, 0.0, max_y))
