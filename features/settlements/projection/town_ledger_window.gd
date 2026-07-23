extends PanelContainer

class_name TownLedgerWindow

signal close_requested(stack_id: String)

const COVER := Color("2b1a11")
const COVER_RAISED := Color("3b2517")
const COVER_EDGE := Color("8a6530")
const PAPER_LEFT := Color("e5d6ad")
const PAPER_RIGHT := Color("ddc99b")
const PAPER_EDGE := Color("9f8350")
const INK := Color("2a2119")
const MUTED_INK := Color("705b3d")
const GOLD := Color("d0aa50")
const CURRENT := Color("8eaa72")
const OUTDATED := Color("c76750")
const ROWS_PER_PAGE := 10

var stack_id := ""
var _report: Dictionary = {}
var _title: Label
var _status: Label
var _close_button: Button
var _tabs: TabContainer
var _pages: Dictionary = {}
var _spreads: Array[GridContainer] = []


func _ready() -> void:
	_build()
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()


func setup(item_stack_id: String, report: Dictionary) -> void:
	stack_id = item_stack_id
	set_report(report)


func set_report(report: Dictionary) -> void:
	_report = report.duplicate(true)
	if is_node_ready():
		_render()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit(stack_id)
		get_viewport().set_input_as_handled()


func _build() -> void:
	var cover := StyleBoxFlat.new()
	cover.bg_color = COVER
	cover.border_color = COVER_EDGE
	cover.set_border_width_all(5)
	cover.set_corner_radius_all(12)
	cover.shadow_color = Color(0, 0, 0, 0.6)
	cover.shadow_size = 12
	add_theme_stylebox_override("panel", cover)
	var outer_margin := MarginContainer.new()
	outer_margin.add_theme_constant_override("margin_left", 12)
	outer_margin.add_theme_constant_override("margin_right", 12)
	outer_margin.add_theme_constant_override("margin_top", 10)
	outer_margin.add_theme_constant_override("margin_bottom", 12)
	add_child(outer_margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	outer_margin.add_child(column)
	column.add_child(_build_header())
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_tabs()
	column.add_child(_tabs)
	for section in ["Overview", "People", "Buildings", "Food", "Stores"]:
		var spread := _build_spread(section)
		_tabs.add_child(spread)
	_render()


func _build_header() -> Control:
	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 8)
	header_margin.add_theme_constant_override("margin_right", 4)
	header_margin.add_theme_constant_override("margin_top", 4)
	header_margin.add_theme_constant_override("margin_bottom", 8)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	header_margin.add_child(header)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_color_override("font_color", GOLD)
	_title.add_theme_font_size_override("font_size", 27)
	header.add_child(_title)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 14)
	header.add_child(_status)
	_close_button = Button.new()
	_close_button.text = "Close book"
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.add_theme_color_override("font_color", PAPER_LEFT)
	_close_button.add_theme_color_override("font_hover_color", INK)
	var close_normal := StyleBoxFlat.new()
	close_normal.bg_color = COVER_RAISED
	close_normal.border_color = COVER_EDGE.darkened(0.25)
	close_normal.set_border_width_all(1)
	close_normal.set_corner_radius_all(3)
	close_normal.content_margin_left = 12
	close_normal.content_margin_right = 12
	var close_hover := close_normal.duplicate() as StyleBoxFlat
	close_hover.bg_color = GOLD
	_close_button.add_theme_stylebox_override("normal", close_normal)
	_close_button.add_theme_stylebox_override("hover", close_hover)
	_close_button.pressed.connect(func(): close_requested.emit(stack_id))
	header.add_child(_close_button)
	return header_margin


func _build_spread(section: String) -> GridContainer:
	var spread := GridContainer.new()
	spread.name = section
	spread.columns = 2
	spread.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spread.add_theme_constant_override("h_separation", 10)
	spread.add_theme_constant_override("v_separation", 8)
	var page_texts: Array[RichTextLabel] = []
	for side in range(2):
		var page := PanelContainer.new()
		page.name = "LeftPage" if side == 0 else "RightPage"
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		page.custom_minimum_size = Vector2(0, 220)
		var paper := StyleBoxFlat.new()
		paper.bg_color = PAPER_LEFT if side == 0 else PAPER_RIGHT
		paper.border_color = PAPER_EDGE
		paper.set_border_width_all(2)
		paper.corner_radius_top_left = 5 if side == 0 else 1
		paper.corner_radius_bottom_left = 5 if side == 0 else 1
		paper.corner_radius_top_right = 1 if side == 0 else 5
		paper.corner_radius_bottom_right = 1 if side == 0 else 5
		paper.shadow_color = Color(0.08, 0.04, 0.02, 0.48)
		paper.shadow_size = 6
		page.add_theme_stylebox_override("panel", paper)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 20 if side == 0 else 26)
		margin.add_theme_constant_override("margin_right", 26 if side == 0 else 20)
		margin.add_theme_constant_override("margin_top", 20)
		margin.add_theme_constant_override("margin_bottom", 10)
		page.add_child(margin)
		var page_column := VBoxContainer.new()
		page_column.add_theme_constant_override("separation", 5)
		margin.add_child(page_column)
		var text := RichTextLabel.new()
		text.bbcode_enabled = true
		text.fit_content = false
		text.scroll_active = true
		text.size_flags_vertical = Control.SIZE_EXPAND_FILL
		text.add_theme_color_override("default_color", INK)
		text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
		text.add_theme_font_size_override("normal_font_size", 16)
		page_column.add_child(text)
		var rule := HSeparator.new()
		rule.add_theme_color_override("separator", PAPER_EDGE.lightened(0.15))
		page_column.add_child(rule)
		var page_number := Label.new()
		page_number.text = str(_spreads.size() * 2 + side + 1)
		page_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		page_number.add_theme_color_override("font_color", MUTED_INK)
		page_number.add_theme_font_size_override("font_size", 12)
		page_column.add_child(page_number)
		spread.add_child(page)
		page_texts.append(text)
	_pages[section.to_lower()] = page_texts
	_spreads.append(spread)
	return spread


func _style_tabs() -> void:
	_tabs.clip_tabs = true
	_tabs.add_theme_color_override("font_selected_color", INK)
	_tabs.add_theme_color_override("font_hovered_color", INK)
	_tabs.add_theme_color_override("font_unselected_color", PAPER_LEFT)
	_tabs.add_theme_font_size_override("font_size", 17)
	_tabs.add_theme_constant_override("side_margin", 0)
	_tabs.add_theme_constant_override("tab_separation", 0)
	var selected := StyleBoxFlat.new()
	selected.bg_color = PAPER_LEFT
	selected.border_color = PAPER_EDGE
	selected.border_width_left = 2
	selected.border_width_top = 2
	selected.border_width_right = 2
	selected.border_width_bottom = 0
	selected.corner_radius_top_left = 4
	selected.corner_radius_top_right = 4
	selected.content_margin_left = 14
	selected.content_margin_right = 14
	selected.content_margin_top = 8
	selected.content_margin_bottom = 8
	_tabs.add_theme_stylebox_override("tab_selected", selected)
	var unselected := selected.duplicate() as StyleBoxFlat
	unselected.bg_color = COVER.darkened(0.22)
	unselected.border_color = COVER_EDGE.darkened(0.2)
	unselected.border_width_bottom = 2
	_tabs.add_theme_stylebox_override("tab_unselected", unselected)
	var hovered := selected.duplicate() as StyleBoxFlat
	hovered.bg_color = PAPER_RIGHT
	hovered.border_width_bottom = 2
	_tabs.add_theme_stylebox_override("tab_hovered", hovered)
	var tabbar_background := StyleBoxFlat.new()
	tabbar_background.bg_color = COVER
	_tabs.add_theme_stylebox_override("tabbar_background", tabbar_background)
	var panel := StyleBoxFlat.new()
	panel.bg_color = COVER
	_tabs.add_theme_stylebox_override("panel", panel)


func _apply_responsive_layout() -> void:
	_apply_layout_for_viewport(get_viewport_rect().size)


func _apply_layout_for_viewport(viewport_size: Vector2) -> void:
	var narrow := viewport_size.x < 760.0
	custom_minimum_size = Vector2.ZERO
	if _tabs != null:
		_tabs.tab_alignment = TabBar.ALIGNMENT_LEFT
		_tabs.add_theme_font_size_override("font_size", 14 if narrow else 17)
	_title.add_theme_font_size_override("font_size", 22 if narrow else 27)
	_status.add_theme_font_size_override("font_size", 12 if narrow else 14)
	_close_button.text = "Close" if narrow else "Close book"
	_update_status_text(narrow)
	for spread in _spreads:
		spread.columns = 1 if narrow else 2
	size = Vector2(minf(viewport_size.x - 48.0, 1040.0), minf(viewport_size.y - 36.0, 760.0))
	position = (viewport_size - size) * 0.5


func _render() -> void:
	if _title == null:
		return
	_title.text = "%s Civic Ledger" % str(_report.get("settlement_name", "Town"))
	var current := str(_report.get("record_state", "outdated")) == "current"
	_status.add_theme_color_override("font_color", CURRENT if current else OUTDATED)
	_update_status_text(get_viewport_rect().size.x < 760.0)
	_render_overview(_report.get("overview", {}) as Dictionary)
	_render_people(_report.get("people", []) as Array)
	_render_table_spread("buildings", ["Name", "Purpose", "Owner"], _report.get("buildings", []) as Array, ["name", "purpose", "owner"], "No buildings are entered in this ledger.")
	_render_food(_report.get("food", []) as Array)
	_render_table_spread("stores", ["Item", "Quantity"], _report.get("stores", []) as Array, ["item", "quantity"], "No non-food goods are recorded in town stores.")


func _update_status_text(narrow: bool) -> void:
	if _status == null:
		return
	var reported_at := str(_report.get("reported_at_text", "an unknown date"))
	var current := str(_report.get("record_state", "outdated")) == "current"
	_status.text = ("Updated %s" if narrow else "Entries current through %s") % reported_at
	if not current:
		_status.text += "\nOUT OF DATE"


func _render_overview(overview: Dictionary) -> void:
	var population := int(overview.get("population", 0))
	var beds := int(overview.get("housing_capacity", 0))
	var housing_note := "Room for %d more" % (beds - population) if beds >= population else "Short by %d beds" % (population - beds)
	var balance := float(overview.get("daily_balance", 0.0))
	var balance_text := "Even"
	if balance > 0.01:
		balance_text = "Surplus of %.1f" % balance
	elif balance < -0.01:
		balance_text = "Deficit of %.1f" % absf(balance)
	_set_page_text("overview", 0, _key_value_rows([
		["Residents", population],
		["Beds", beds],
		["Housing", housing_note],
	]))
	_set_page_text("overview", 1, _key_value_rows([
		["Food outlook", str(overview.get("food_outlook", "Unknown"))],
		["Food stored", "%.1f" % float(overview.get("provisions", 0.0))],
		["Estimated reserve", str(overview.get("reserve", "Unknown"))],
		["Daily food use", "%.1f" % float(overview.get("daily_use", 0.0))],
		["Daily food output", "%.1f" % float(overview.get("daily_output", 0.0))],
		["Food balance", balance_text],
	]))


func _render_people(rows: Array) -> void:
	var split := _split_for_pages(rows)
	var people_columns: Array = [2, 2, 4]
	_set_page_text("people", 0, _table(["Name", "Job", "Workplace"], split[0], ["name", "job", "workplace"], "No residents are entered in this ledger.", people_columns))
	var right := ""
	if not split[1].is_empty():
		right = _table(["Name", "Job", "Workplace"], split[1], ["name", "job", "workplace"], "", people_columns)
	_set_page_text("people", 1, right)


func _render_food(rows: Array) -> void:
	var split := _split_for_pages(rows)
	var headers: Array[String] = ["Food", "Stock", "Made/day", "Used/day", "Remaining"]
	var fields: Array[String] = ["food", "stored", "produced", "consumed", "remaining"]
	var weights: Array = [3, 2, 2, 2, 3]
	_set_page_text("food", 0, _table(headers, split[0], fields, "No food is stored in town.", weights))
	var right := ""
	if not split[1].is_empty():
		right = _table(headers, split[1], fields, "", weights)
	_set_page_text("food", 1, right)


func _render_table_spread(key: String, headers: Array[String], rows: Array, fields: Array[String], empty_text: String) -> void:
	var split := _split_for_pages(rows)
	var column_weights: Array = [4, 2] if fields.size() == 2 else [4, 2, 3]
	_set_page_text(key, 0, _table(headers, split[0], fields, empty_text, column_weights))
	var right := ""
	if not split[1].is_empty():
		right = _table(headers, split[1], fields, "", column_weights)
	_set_page_text(key, 1, right)


func _split_for_pages(rows: Array) -> Array:
	return [rows.slice(0, ROWS_PER_PAGE), rows.slice(ROWS_PER_PAGE)]


func _table(headers: Array[String], rows: Array, fields: Array[String], empty_text: String, column_weights: Array) -> String:
	if rows.is_empty():
		return "[color=#705b3d][i]%s[/i][/color]" % empty_text
	var output := "[table=%d]" % headers.size()
	for index in range(headers.size()):
		output += "[cell expand=%d bg=#d1bd8d padding=2,3,10,5][color=#705b3d][b]%s[/b][/color][/cell]" % [column_weights[index], headers[index]]
	for row_value in rows:
		var row := row_value as Dictionary
		for index in range(fields.size()):
			output += "[cell expand=%d padding=0,3,10,3]%s[/cell]" % [column_weights[index], str(row.get(fields[index], "-"))]
	return output + "[/table]"


func _key_value_rows(rows: Array) -> String:
	var output := "[table=2]"
	for row in rows:
		output += "[cell][color=#705b3d][b]%s[/b][/color][/cell][cell]%s[/cell]" % [str(row[0]), str(row[1])]
	return output + "[/table]"


func _set_page_text(key: String, page_index: int, text: String) -> void:
	var page_texts := _pages.get(key, []) as Array
	if page_index >= 0 and page_index < page_texts.size():
		(page_texts[page_index] as RichTextLabel).text = text
