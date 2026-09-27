extends HBoxContainer

## Bounded category/action browser. Features supply their own panels; this view
## only handles discovery, filtering and selection, never simulation commands.
var _entries: Dictionary = {}
var _selected_id := ""
var _search: LineEdit
var _actions: Tree
var _content: VBoxContainer
var _empty: Label

func _ready() -> void:
	name = "WorldSimActions"
	custom_minimum_size = Vector2(660, 340)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 16)
	var navigation := VBoxContainer.new()
	navigation.custom_minimum_size.x = 200
	add_child(navigation)
	_search = LineEdit.new()
	_search.name = "ActionSearch"
	_search.placeholder_text = "Find an action…"
	_search.clear_button_enabled = true
	navigation.add_child(_search)
	_search.text_changed.connect(_rebuild_actions)
	_actions = Tree.new()
	_actions.name = "ActionList"
	_actions.hide_root = true
	_actions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_actions.select_mode = Tree.SELECT_ROW
	_actions.item_selected.connect(_on_action_selected)
	navigation.add_child(_actions)
	var scroll := ScrollContainer.new()
	scroll.name = "ActionScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	_empty = Label.new()
	_empty.text = "No matching actions."
	_content.add_child(_empty)

func add_action(id: String, category: String, title: String, panel: Control) -> void:
	assert(not id.is_empty() and not _entries.has(id), "World Sim actions need unique IDs")
	panel.hide()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entries[id] = {"category": category, "title": title, "panel": panel}
	_content.add_child(panel)
	_rebuild_actions(_search.text)

func _rebuild_actions(query: String) -> void:
	_actions.clear()
	var root := _actions.create_item()
	var categories: Dictionary = {}
	var selected: TreeItem
	var first: TreeItem
	for id in _entries:
		var entry: Dictionary = _entries[id]
		if not query.strip_edges().is_empty() and not (str(entry.category) + " " + str(entry.title)).containsn(query.strip_edges()):
			continue
		if not categories.has(entry.category):
			var category := _actions.create_item(root)
			category.set_text(0, str(entry.category))
			category.set_selectable(0, false)
			categories[entry.category] = category
		var item := _actions.create_item(categories[entry.category])
		item.set_text(0, str(entry.title))
		item.set_metadata(0, id)
		if first == null:
			first = item
		if id == _selected_id:
			selected = item
	if selected == null:
		selected = first
	if selected != null:
		selected.select(0)
		_show_action(str(selected.get_metadata(0)))
	else:
		_show_action("")

func _on_action_selected() -> void:
	var item := _actions.get_selected()
	if item != null:
		_show_action(str(item.get_metadata(0)))

func _show_action(id: String) -> void:
	_selected_id = id
	for entry_id in _entries:
		var panel: Control = _entries[entry_id].panel
		panel.visible = entry_id == id
	_empty.visible = id.is_empty()
