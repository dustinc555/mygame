@tool
extends HSplitContainer

## Resource page for the Zone workspace. Definitions are shared runtime data;
## all edits go through the owning tool context's UndoRedo boundary.
var _tools: RefCounted
var _zone: Node3D
var _entries: Array = []
var _filtered: Array = []
var _selected: Resource
var _search: LineEdit
var _category: OptionButton
var _catalog: ItemList
var _result_count: Label
var _preview: TextureRect
var _title: Label
var _description: Label
var _settings: VBoxContainer
var _stock_min: SpinBox
var _stock_max: SpinBox
var _refill_enabled: CheckBox
var _weeks_min: SpinBox
var _weeks_max: SpinBox
var _place: Button
var _cancel: Button
var _status: Label
var _settings_notice: Label
var _footer: HBoxContainer
var _scale := 1.0
var _updating := false
var _placing := false
var _thumbnails := {}

func setup(tools: RefCounted) -> void:
	_tools = tools
	_scale = EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_offset = 0
	var library := VBoxContainer.new()
	library.custom_minimum_size.x = 320 * _scale
	library.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library.add_theme_constant_override("separation", 8)
	add_child(library)
	var filters := HBoxContainer.new()
	library.add_child(filters)
	_search = LineEdit.new()
	_search.name = "ResourceSearch"
	_search.placeholder_text = "Search deposits…"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_value: String): _filter_catalog())
	filters.add_child(_search)
	_category = OptionButton.new()
	_category.name = "ResourceCategory"
	_category.add_item("All resources")
	_category.item_selected.connect(func(_index: int): _filter_catalog())
	filters.add_child(_category)
	_catalog = ItemList.new()
	_catalog.name = "ResourceCatalog"
	_catalog.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_catalog.icon_mode = ItemList.ICON_MODE_TOP
	_catalog.fixed_icon_size = Vector2i(roundi(112 * _scale), roundi(80 * _scale))
	_catalog.fixed_column_width = roundi(160 * _scale)
	_catalog.max_columns = 0
	_catalog.max_text_lines = 2
	_catalog.same_column_width = true
	_catalog.add_theme_constant_override("h_separation", 10)
	_catalog.add_theme_constant_override("v_separation", 12)
	_catalog.item_selected.connect(_select_entry)
	_catalog.item_activated.connect(func(index: int):
		_select_entry(index)
		_begin_placement())
	library.add_child(_catalog)
	_result_count = Label.new()
	_result_count.modulate.a = 0.65
	library.add_child(_result_count)
	var details := VBoxContainer.new()
	details.custom_minimum_size.x = 340 * _scale
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 9)
	add_child(details)
	_title = Label.new()
	_title.text = "Choose a resource"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_font_size_override("font_size", roundi(20 * _scale))
	details.add_child(_title)
	var detail_tabs := TabContainer.new()
	detail_tabs.name = "ResourceDetailTabs"
	detail_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(detail_tabs)
	var placement := VBoxContainer.new()
	placement.name = "Place"
	placement.add_theme_constant_override("separation", 12)
	detail_tabs.add_child(placement)
	var hero := HBoxContainer.new()
	hero.add_theme_constant_override("separation", 12)
	placement.add_child(hero)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(104, 104) * _scale
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hero.add_child(_preview)
	var intro := VBoxContainer.new()
	intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero.add_child(intro)

	_description = Label.new()
	_description.text = "Pick a deposit to preview its rules and place it in this zone."
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.modulate.a = 0.72
	intro.add_child(_description)
	var actions := HBoxContainer.new()
	placement.add_child(actions)
	_place = Button.new()
	_place.name = "PlaceResource"
	_place.text = "Place in Zone"
	_place.custom_minimum_size.y = 36 * _scale
	_place.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_place.disabled = true
	_place.pressed.connect(_begin_placement)
	actions.add_child(_place)
	_cancel = Button.new()
	_cancel.name = "CancelResourcePlacement"
	_cancel.text = "Stop Placing"
	_cancel.visible = false
	_cancel.pressed.connect(func(): _tools.call("cancel_resource_placement"))
	actions.add_child(_cancel)
	_status = Label.new()
	_status.name = "PlacementInstructions"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate.a = 0.75
	placement.add_child(_status)
	var settings_scroll := ScrollContainer.new()
	settings_scroll.name = "Type Defaults"
	settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_tabs.add_child(settings_scroll)
	_settings = VBoxContainer.new()
	_settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings.visible = false
	_settings.add_theme_constant_override("separation", 7)
	settings_scroll.add_child(_settings)
	var settings_title := Label.new()
	settings_title.text = "Shared resource defaults"
	settings_title.add_theme_font_size_override("font_size", roundi(16 * _scale))
	_settings.add_child(settings_title)
	var hint := Label.new()
	hint.text = "Affects every deposit of this type. Existing stock and queued refill dates stay unchanged."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate.a = 0.65
	_settings.add_child(hint)
	var stock := _range_row("Stock per refill", "uses", 1, 100000, 1)
	_stock_min = stock[0]
	_stock_max = stock[1]
	_stock_min.name = "MinimumStock"
	_stock_max.name = "MaximumStock"
	_stock_min.value_changed.connect(func(value: float): _set_definition_property("min_stock", int(value)))
	_stock_max.value_changed.connect(func(value: float): _set_definition_property("max_stock", int(value)))
	_refill_enabled = CheckBox.new()
	_refill_enabled.name = "RefillEnabled"
	_refill_enabled.text = "Refill after depletion"
	_refill_enabled.toggled.connect(func(value: bool): _set_definition_property("refill_enabled", value))
	_settings.add_child(_refill_enabled)
	var weeks := _range_row("Refill delay", "weeks", 0.25, 1040, 0.25)
	_weeks_min = weeks[0]
	_weeks_max = weeks[1]
	_weeks_min.name = "MinimumRefillWeeks"
	_weeks_max.name = "MaximumRefillWeeks"
	_weeks_min.tooltip_text = "Minimum delay after depletion, in in-game weeks. New depletion only; existing deadlines are saved."
	_weeks_max.tooltip_text = "Maximum delay after depletion, in in-game weeks. A random delay is chosen once per depletion."
	_weeks_min.value_changed.connect(func(value: float): _set_definition_property("refill_min_weeks", value))
	_weeks_max.value_changed.connect(func(value: float): _set_definition_property("refill_max_weeks", value))
	_settings_notice = Label.new()
	_settings_notice.text = "In-game weeks. Changes save automatically; Undo restores them."
	_settings_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_settings_notice.modulate.a = 0.7
	_settings.add_child(_settings_notice)
	var footer := HBoxContainer.new()
	_footer = footer
	details.add_child(footer)
	var definition_button := Button.new()
	definition_button.text = "Open All Type Settings"
	definition_button.pressed.connect(func():
		if _selected != null:
			_tools.call("inspect_resource_definition", _selected))
	footer.add_child(definition_button)
	var scene_button := Button.new()
	scene_button.text = "Open Deposit Scene"
	scene_button.tooltip_text = "Edit this type's mesh, collision, work speed and loot in its reusable source scene."
	scene_button.pressed.connect(func():
		if _selected != null:
			_tools.call("open_resource_scene", _selected))
	footer.add_child(scene_button)
	_entries = _tools.get_resource_catalog()
	var categories: Array[String] = []
	for entry: Resource in _entries:
		var category := str(entry.get("category"))
		if not categories.has(category):
			categories.append(category)
	categories.sort()
	for category in categories:
		_category.add_item(category)
	_filter_catalog()

func set_zone(zone: Node3D) -> void:
	_zone = zone if is_instance_valid(zone) else null
	refresh_selected()

func _range_row(label_text: String, suffix: String, minimum: float, maximum: float, step: float) -> Array[SpinBox]:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	_settings.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var result: Array[SpinBox] = []
	for caption in ["Min", "Max"]:
		if caption == "Max":
			var separator := Label.new()
			separator.text = "–"
			row.add_child(separator)
		var field := SpinBox.new()
		field.min_value = minimum
		field.max_value = maximum
		field.step = step
		field.tooltip_text = caption + "imum " + label_text.to_lower()
		field.suffix = suffix
		field.custom_minimum_size.x = 126 * _scale
		row.add_child(field)
		result.append(field)
	return result

func _filter_catalog() -> void:
	if _catalog == null:
		return
	var query := _search.text.strip_edges().to_lower()
	var category := "" if _category.selected <= 0 else _category.get_item_text(_category.selected)
	_filtered.clear()
	_catalog.clear()
	var selected_index := -1
	for entry: Resource in _entries:
		if not category.is_empty() and str(entry.get("category")) != category:
			continue
		var haystack := "%s %s %s" % [entry.get("display_name"), entry.get("category"), entry.get("description")]
		if not query.is_empty() and not haystack.to_lower().contains(query):
			continue
		var index := _catalog.add_item(str(entry.get("display_name")), _thumbnails.get(entry.resource_path))
		_catalog.set_item_tooltip(index, "%s\n%s" % [entry.get("category"), entry.get("description")])
		_filtered.append(entry)
		if entry == _selected:
			selected_index = index
		if not _thumbnails.has(entry.resource_path) and _tools.has_method("request_resource_preview"):
			_tools.call("request_resource_preview", entry, Callable(self, "set_resource_preview"))
	_result_count.text = "%d resources · Double-click to place" % _filtered.size() if not _filtered.is_empty() else "No matching resources"
	if selected_index < 0 and not _filtered.is_empty():
		selected_index = 0
	if selected_index >= 0:
		_catalog.select(selected_index)
		_select_entry(selected_index)
	else:
		_selected = null
		refresh_selected()

func _select_entry(index: int) -> void:
	if index < 0 or index >= _filtered.size():
		return
	_selected = _filtered[index] as Resource
	refresh_selected()

func select_definition(definition: Resource) -> void:
	if definition == null or not definition.has_method("validation_errors"):
		return
	_search.text = ""
	_category.select(0)
	_selected = definition
	_filter_catalog()
	# Existing custom definitions remain editable even when they are not part
	# of the placement catalog; never silently show another type's defaults.
	if _selected != definition:
		_catalog.deselect_all()
		_selected = definition
		refresh_selected()
	if not _thumbnails.has(definition.resource_path) and _tools.has_method("request_resource_preview"):
		_tools.call("request_resource_preview", definition, Callable(self, "set_resource_preview"))

func refresh_selected() -> void:
	_updating = true
	var valid := _selected != null
	_settings.visible = valid
	_footer.visible = valid
	_place.disabled = not valid or not is_instance_valid(_zone) or _placing
	if not valid:
		_title.text = "Choose a resource"
		_description.text = "Search the catalog or choose another category."
		_preview.texture = null
		_updating = false
		return
	_title.text = str(_selected.get("display_name"))
	_description.text = str(_selected.get("description"))
	_preview.texture = _thumbnails.get(_selected.resource_path)
	_stock_min.value = float(_selected.get("min_stock"))
	_stock_max.value = float(_selected.get("max_stock"))
	var unit := "ore" if str(_selected.get("category")) == "Ore" else "attempts"
	_stock_min.suffix = unit
	_stock_max.suffix = unit
	_refill_enabled.button_pressed = bool(_selected.get("refill_enabled"))
	_weeks_min.value = float(_selected.get("refill_min_weeks"))
	_weeks_max.value = float(_selected.get("refill_max_weeks"))
	_weeks_min.editable = _refill_enabled.button_pressed
	_weeks_max.editable = _refill_enabled.button_pressed
	if not _placing:
		_status.text = "Click Place, then position the deposit on the terrain."
	_updating = false

func set_resource_preview(resource_path: String, texture: Texture2D) -> void:
	if texture == null:
		return
	_thumbnails[resource_path] = texture
	for index in range(_filtered.size()):
		if (_filtered[index] as Resource).resource_path == resource_path:
			_catalog.set_item_icon(index, texture)
	if _selected != null and _selected.resource_path == resource_path:
		_preview.texture = texture

func _set_definition_property(property: String, value: Variant) -> void:
	if _updating or _selected == null:
		return
	var error := str(_tools.call("set_resource_definition_property", _selected, property, value))
	refresh_selected()
	if not error.is_empty():
		_status.text = error
		_settings_notice.text = error
	else:
		_settings_notice.text = "In-game weeks. Changes save automatically; Undo restores them."

func _begin_placement() -> void:
	if _selected == null or not is_instance_valid(_zone):
		return
	_tools.call("begin_resource_placement", _selected)

func set_placement_active(active: bool, label := "") -> void:
	_placing = active
	_cancel.visible = active
	refresh_selected()
	if active:
		_status.text = "Placing %s · Click to place again. Drag to rotate; R turns; wheel adjusts height. Esc / right-click finishes." % label
