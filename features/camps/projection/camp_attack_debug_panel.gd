extends VBoxContainer

## Manual input to the camp simulation. Only stable IDs are retained between
## opening the panel and submitting; the simulation revalidates the command.
var context: BootstrapContext
var _from: OptionButton
var _to: OptionButton
var _count: SpinBox
var _spawn: Button
var _status: Label

func _ready() -> void:
	name = "CampAttack"
	add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "Spawn Attack"
	title.add_theme_font_size_override("font_size", 22)
	add_child(title)
	var description := Label.new()
	description.text = "Spawn extra camp warriors using the camp's faction, race mix and equipment."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(description)
	var fields := GridContainer.new()
	fields.columns = 2
	fields.add_theme_constant_override("h_separation", 12)
	fields.add_theme_constant_override("v_separation", 10)
	add_child(fields)
	_from = _make_picker(fields, "FromCamp", "From camp")
	_to = _make_picker(fields, "ToTown", "To town")
	var count_label := Label.new()
	count_label.text = "Fighters"
	fields.add_child(count_label)
	_count = SpinBox.new()
	_count.name = "FighterCount"
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.min_value = 1
	_count.max_value = 100
	_count.allow_greater = true
	_count.step = 1
	_count.value = 10
	fields.add_child(_count)
	var buttons := HBoxContainer.new()
	add_child(buttons)
	_spawn = Button.new()
	_spawn.name = "SpawnAttack"
	_spawn.text = "Spawn Attack"
	_spawn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spawn.pressed.connect(_submit)
	buttons.add_child(_spawn)
	var refresh := Button.new()
	refresh.name = "RefreshDestinations"
	refresh.text = "Refresh"
	refresh.tooltip_text = "Reload camps and towns from the simulation."
	refresh.pressed.connect(refresh_destinations)
	buttons.add_child(refresh)
	_status = Label.new()
	_status.name = "CommandStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	visibility_changed.connect(_on_visibility_changed)
	refresh_destinations()

func _make_picker(fields: GridContainer, node_name: String, label_text: String) -> OptionButton:
	var label := Label.new()
	label.text = label_text
	fields.add_child(label)
	var picker := OptionButton.new()
	picker.name = node_name
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.fit_to_longest_item = false
	picker.clip_text = true
	picker.item_selected.connect(_selection_changed)
	fields.add_child(picker)
	return picker

func _service(id: StringName) -> Node:
	var current := context if context != null else BootstrapContext.active
	return current.get_optional(id) if current != null else null

func _on_visibility_changed() -> void:
	if is_visible_in_tree() and is_instance_valid(_status):
		refresh_destinations()

func refresh_destinations() -> void:
	var from_id := _selected_id(_from)
	var to_id := _selected_id(_to)
	_reset_picker(_from, "Choose a camp…")
	_reset_picker(_to, "Choose a town…")
	var world := _service(&"gecs_world")
	if world == null or _service(&"camps") == null:
		_status.text = "World simulation is not available."
		_selection_changed()
		return
	var camps: Dictionary = world.get_camp_states()
	var camp_ids := camps.keys()
	camp_ids.sort()
	for id in camp_ids:
		var camp: Dictionary = camps[id]
		if str(camp.get("status", "")) != "occupied":
			continue
		_add_destination(_from, str(id), "%s · %s" % [str(id), _faction_name(str(camp.faction_id))], from_id)
	var towns: Dictionary = world.get_settlement_states()
	var town_ids := towns.keys()
	town_ids.sort()
	for id in town_ids:
		var town: Dictionary = towns[id]
		if not town.get("world_position", Vector3.INF).is_finite():
			continue
		var title := str(town.get("display_name", ""))
		if title.is_empty():
			title = str(id)
		_add_destination(_to, str(id), "%s · %s" % [title, _faction_name(str(town.get("faction_id", "")))], to_id)
	_status.text = "Choose a camp and town. Relations are not changed by this command."
	_selection_changed()

func _reset_picker(picker: OptionButton, prompt: String) -> void:
	picker.clear()
	picker.add_item(prompt)
	picker.set_item_metadata(0, "")
	picker.select(0)

func _add_destination(picker: OptionButton, id: String, title: String, previous: String) -> void:
	picker.add_item(title)
	var index := picker.item_count - 1
	picker.set_item_metadata(index, id)
	if previous == id:
		picker.select(index)

func _selected_id(picker: OptionButton) -> String:
	return str(picker.get_selected_metadata()) if picker.selected >= 0 else ""

func _faction_name(id: String) -> String:
	var factions := _service(&"faction")
	var definition: Resource = factions.get_faction_definition(id) if factions != null else null
	return str(definition.get("display_name")) if definition != null else id

func _selection_changed(_index: int = -1) -> void:
	_spawn.disabled = _selected_id(_from).is_empty() or _selected_id(_to).is_empty() or _service(&"camps") == null

func _submit() -> void:
	var camps := _service(&"camps")
	if camps == null:
		_status.text = "World simulation is not available."
		_spawn.disabled = true
		return
	_count.apply()
	var result: Dictionary = camps.spawn_attack_squad(_selected_id(_from), _selected_id(_to), int(_count.value))
	_status.text = str(result.message)
