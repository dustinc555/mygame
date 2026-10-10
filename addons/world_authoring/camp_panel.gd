@tool
extends HBoxContainer

var _tools: RefCounted
var _zone: Node3D
var _camps: Array[Node] = []
var _list: ItemList
var _settings: VBoxContainer
var _selected: Node
var _updating := false
var _controls: Dictionary = {}

func setup(tools: RefCounted) -> void:
	_tools = tools
	name = "Camps"
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 230
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(left)
	var add := Button.new()
	add.name = "PlaceCamp"
	add.text = "+ Place Camp Marker"
	add.pressed.connect(func(): _tools.begin_camp_placement())
	left.add_child(add)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(index: int): select_camp(_camps[index]))
	left.add_child(_list)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_settings = VBoxContainer.new()
	_settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_settings)

func set_zone(zone: Node3D) -> void:
	_zone = zone
	refresh()

func refresh() -> void:
	_camps.clear()
	_list.clear()
	if is_instance_valid(_zone):
		_collect(_zone)
	for camp in _camps:
		_list.add_item(str(camp.name))
	if not is_instance_valid(_selected) or not _camps.has(_selected):
		_selected = _camps[0] if not _camps.is_empty() else null
	select_camp(_selected)

func _collect(node: Node) -> void:
	for child in node.get_children():
		if child is CampMarker:
			_camps.append(child)
		else:
			_collect(child)

func select_camp(camp: Node) -> void:
	_selected = camp
	_updating = true
	_controls.clear()
	for child in _settings.get_children():
		_settings.remove_child(child)
		child.queue_free()
	if not is_instance_valid(camp):
		var help := Label.new()
		help.text = "Place a marker, then set its faction, size and patrol range here."
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_settings.add_child(help)
		_updating = false
		return
	var index := _camps.find(camp)
	if index >= 0:
		_list.select(index)
	var title := Label.new()
	title.text = str(camp.name)
	_settings.add_child(title)
	var inspect := Button.new()
	inspect.text = "Select Marker in Viewport"
	inspect.pressed.connect(func(): _tools.open_town_editor(camp))
	_settings.add_child(inspect)
	var identity := LineEdit.new()
	identity.text = str(camp.get("camp_id"))
	_controls["camp_id"] = identity
	identity.tooltip_text = "Stable Camp ID. Do not change after shipping saves."
	identity.text_submitted.connect(func(value: String): _tools.set_zone_property(camp, "camp_id", value.strip_edges()))
	_settings.add_child(identity)
	_resource(camp, "faction", "Faction Owner", "FactionDefinition")
	_resource(camp, "camp_type", "Camp Type / Furniture / Replenishment", "Resource")
	var size_row := HBoxContainer.new()
	var size_label := Label.new()
	size_label.text = "Camp size"
	size_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_row.add_child(size_label)
	var size_picker := OptionButton.new()
	for label in ["Small", "Medium", "Large"]:
		size_picker.add_item(label)
	size_picker.select(int(camp.get("camp_size")))
	size_picker.item_selected.connect(func(value: int):
		if not _updating:
			_tools.set_zone_property(camp, "camp_size", value))
	_controls["camp_size"] = size_picker
	size_row.add_child(size_picker)
	_settings.add_child(size_row)
	for field in [
		["roaming_radius", "Squad roaming radius (metres)", 10, 2000, 10],
		["squad_count", "Roaming squads", 1, 4, 1],
		["squad_size", "Members per squad", 1, 20, 1],
		["generation_seed", "Generation seed", 0, 999999, 1],
	]:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = field[1]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var spin := SpinBox.new()
		spin.min_value = field[2]
		spin.max_value = field[3]
		spin.step = field[4]
		spin.allow_greater = field[0] == "roaming_radius"
		if spin.allow_greater:
			spin.tooltip_text = "Maximum distance from camp for patrol destinations. Type any larger distance; this never enlarges the camp."
		spin.value = float(camp.get(field[0]))
		var property := str(field[0])
		_controls[property] = spin
		spin.value_changed.connect(func(value: float):
			if not _updating:
				_tools.set_zone_property(camp, property, value))
		row.add_child(spin)
		_settings.add_child(row)
	var hint := Label.new()
	hint.text = "Size selects compact layout, initial population and furnishing amounts. Roaming radius only controls squads and has no upper cap. Camp type owns the editable size presets. Saved population and loot are never regenerated."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_settings.add_child(hint)
	_updating = false

func _resource(camp: Node, property: String, caption: String, base: String) -> void:
	var label := Label.new()
	label.text = caption
	_settings.add_child(label)
	var picker := EditorResourcePicker.new()
	picker.base_type = base
	picker.edited_resource = camp.get(property)
	_controls[property] = picker
	picker.resource_changed.connect(func(value: Resource):
		if not _updating:
			_tools.set_zone_property(camp, property, value))
	picker.resource_selected.connect(func(value: Resource, _inspect: bool): EditorInterface.edit_resource(value))
	_settings.add_child(picker)

func refresh_property(camp: Node, property: String) -> void:
	if is_instance_valid(camp):
		camp.update_configuration_warnings()
	if camp != _selected or not _controls.has(property):
		return
	var control: Control = _controls[property]
	_updating = true
	if control is SpinBox:
		control.set_value_no_signal(float(camp.get(property)))
	elif control is LineEdit:
		control.text = str(camp.get(property))
	elif control is EditorResourcePicker:
		control.edited_resource = camp.get(property)
	elif control is OptionButton:
		control.select(int(camp.get(property)))
	_updating = false
