@tool
extends PanelContainer

## Zone workspace: scope/header plus independent Overview, Towns and Resources
## pages. The tool context owns edits and placement; this view owns no game state.
const RESOURCE_BROWSER := preload("res://addons/world_authoring/zone_resource_browser.gd")

var _tools: RefCounted
var _zone: Node3D
var _tabs: TabContainer
var _heading: Label
var _scene_label: Label
var _summary: Label
var _zone_id: LineEdit
var _town_list: ItemList
var _town_nodes: Array = []
var _resource_browser: Control
var _updating := false

func setup(tools: RefCounted) -> void:
	_tools = tools
	name = "ZoneAuthoring"
	var scale := EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
	custom_minimum_size = Vector2(0, 480 * scale)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	content.add_child(header)
	_heading = Label.new()
	_heading.name = "ZoneHeading"
	_heading.add_theme_font_size_override("font_size", roundi(22 * scale))
	header.add_child(_heading)
	_scene_label = Label.new()
	_scene_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scene_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_scene_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_scene_label.modulate.a = 0.7
	header.add_child(_scene_label)
	_tabs = TabContainer.new()
	_tabs.name = "WorkspaceTabs"
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_tabs)
	_tabs.add_child(_build_overview())
	_tabs.add_child(_build_towns())
	_resource_browser = RESOURCE_BROWSER.new()
	_resource_browser.name = "Resources"
	_resource_browser.setup(tools)
	_tabs.add_child(_resource_browser)

func set_zone(zone: Node3D) -> void:
	var next := zone if is_instance_valid(zone) else null
	if _zone == next:
		return
	_zone = next
	refresh()
	_resource_browser.set_zone(_zone)

func refresh() -> void:
	if not is_instance_valid(_zone):
		_zone = null
	_updating = true
	_heading.text = "Zone · %s" % _zone.name if _zone != null else "Zone Authoring"
	var scene_path := _zone.scene_file_path if _zone != null else ""
	_scene_label.text = scene_path.get_file() if not scene_path.is_empty() else "Save the zone scene to keep your edits"
	_scene_label.tooltip_text = scene_path
	_zone_id.text = str(_zone.get("zone_id")) if _zone != null and _zone.has_method("get_zone_id") else ""
	_town_nodes = _tools.get_zone_towns(_zone) if _zone != null else []
	var deposits: Array = _tools.get_zone_resources(_zone) if _zone != null else []
	_summary.text = "%d towns     ·     %d resource deposits" % [_town_nodes.size(), deposits.size()]
	_town_list.clear()
	for town in _town_nodes:
		if is_instance_valid(town):
			_town_list.add_item(str(town.name))
	_updating = false

func show_resources() -> void:
	_tabs.current_tab = 2

func select_resource_definition(definition: Resource) -> void:
	show_resources()
	_resource_browser.select_definition(definition)

func set_placement_active(active: bool, label := "") -> void:
	_resource_browser.set_placement_active(active, label)

func refresh_resource_settings() -> void:
	_resource_browser.refresh_selected()

func _build_overview() -> Control:
	var page := VBoxContainer.new()
	page.name = "Overview"
	page.add_theme_constant_override("separation", 14)
	var title := Label.new()
	title.text = "Shape this part of the world"
	title.add_theme_font_size_override("font_size", 18)
	page.add_child(title)
	var description := Label.new()
	description.text = "Place independent resources, create towns, and move between the focused authoring tools."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.modulate.a = 0.75
	page.add_child(description)
	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 17)
	page.add_child(_summary)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	page.add_child(actions)
	var resources := Button.new()
	resources.text = "Place Resources"
	resources.custom_minimum_size.y = 36
	resources.pressed.connect(show_resources)
	actions.add_child(resources)
	var towns := Button.new()
	towns.text = "Manage Towns"
	towns.pressed.connect(func(): _tabs.current_tab = 1)
	actions.add_child(towns)
	page.add_child(HSeparator.new())
	var identity := HBoxContainer.new()
	var label := Label.new()
	label.text = "Zone ID"
	label.custom_minimum_size.x = 100
	identity.add_child(label)
	_zone_id = LineEdit.new()
	_zone_id.name = "ZoneId"
	_zone_id.placeholder_text = "Uses the zone name when empty"
	_zone_id.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_zone_id.tooltip_text = "Stable identity used by saved games. Renaming an established ID can disconnect existing saved state."
	_zone_id.text_submitted.connect(_commit_zone_id)
	_zone_id.focus_exited.connect(func(): _commit_zone_id(_zone_id.text))
	identity.add_child(_zone_id)
	page.add_child(identity)
	var performance := Button.new()
	performance.name = "ResourcePerformanceSettings"
	performance.text = "Advanced: Resource Refill Performance"
	performance.tooltip_text = "Global limits on refill work per frame. Gameplay refill intervals live in Resources → Type Defaults."
	performance.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	performance.pressed.connect(func(): _tools.call("inspect_resource_performance_settings"))
	page.add_child(performance)
	return page

func _build_towns() -> Control:
	var page := VBoxContainer.new()
	page.name = "Towns"
	page.add_theme_constant_override("separation", 10)
	var bar := HBoxContainer.new()
	page.add_child(bar)
	var title := Label.new()
	title.text = "Towns in this zone"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title)
	var add := Button.new()
	add.name = "AddTown"
	add.text = "+ Add Town"
	add.pressed.connect(func(): _tools.call("_on_add_town_pressed"))
	bar.add_child(add)
	var open := Button.new()
	open.text = "Open Town Editor"
	open.pressed.connect(_open_selected_town)
	bar.add_child(open)
	_town_list = ItemList.new()
	_town_list.name = "ZoneTowns"
	_town_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_town_list.item_activated.connect(func(_index: int): _open_selected_town())
	page.add_child(_town_list)
	var hint := Label.new()
	hint.text = "Open a town to edit its facilities and residents. Resource deposits do not need to belong to a town."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate.a = 0.65
	page.add_child(hint)
	return page

func _open_selected_town() -> void:
	var indices := _town_list.get_selected_items()
	if indices.is_empty():
		return
	var index := indices[0]
	if index < _town_nodes.size() and is_instance_valid(_town_nodes[index]):
		_tools.call("open_town_editor", _town_nodes[index])

func _commit_zone_id(value: String) -> void:
	if _updating or not is_instance_valid(_zone) or not _zone.has_method("get_zone_id"):
		return
	_tools.call("set_zone_property", _zone, "zone_id", value.strip_edges())
