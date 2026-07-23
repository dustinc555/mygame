extends SceneTree

const WINDOW := preload("res://features/settlements/projection/town_ledger_window.tscn")

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stock := InventoryStockController.new()
	stock.call("_definition", "res://features/inventory/resources/items/bread.tres")
	stock.call("_definition", "res://features/inventory/resources/items/bottle_1.tres")
	stock.call("_definition", "res://features/inventory/resources/items/food.tres")
	_assert(stock.get_item_display_name("food.bread") == "Bread", "Ledger stock must resolve authored item IDs to display names")
	_assert(stock.get_item_display_name("res://features/inventory/resources/items/bottle_1.tres") == "Green Bottle", "Ledger stock must resolve path-backed items without exposing resource paths")
	_assert(stock.get_item_display_name("food.generic") == "Provisions", "Generic food must use a player-facing stock name")
	stock.free()
	var controller_source := FileAccess.get_file_as_string("res://features/settlements/bridge/town_ledger_controller.gd")
	_assert(controller_source.contains("LEDGER_METADATA_KEY") and not controller_source.contains("_ledger_component"), "Ledger truth must live on durable stack metadata")
	_assert(controller_source.contains("_queue_settlement_refresh") and controller_source.contains("_flush_queued_settlement_refreshes.call_deferred"), "Population signal bursts must coalesce to one ledger refresh per settlement")
	_assert(controller_source.contains("maxi(physical_beds, maxi(0, int(building.get(\"housing_capacity\", 0))))"), "Ledger housing must honor the larger physical or authored capacity")
	get_root().size = Vector2i(900, 700)
	var window := WINDOW.instantiate() as TownLedgerWindow
	get_root().add_child(window)
	window.setup("stack:test", {
		"settlement_name": "Test Town", "record_state": "outdated", "reported_at_text": "Day 4, 09:30",
		"overview": {"population": 3, "housing_capacity": 5, "food_outlook": "Running low", "provisions": 4.0, "reserve": "2.0 days", "daily_use": 3.0, "daily_output": 1.0, "daily_balance": -2.0},
		"people": [{"name": "Mara", "job": "Warden", "workplace": "Town Jail"}],
		"buildings": [
			{"name": "Town Jail", "purpose": "Jail", "owner": "Mara"},
			{"name": "Town Keep", "purpose": "Keep", "owner": "Vaughn"},
			{"name": "Town Bar", "purpose": "Bar", "owner": "Vacant"},
		],
		"food": [{"food": "Bread", "stored": 5, "produced": "2.0", "consumed": "3.0", "remaining": "5.0 days"}],
		"stores": [{"item": "Green Bottle", "quantity": 1}],
	})
	await process_frame
	window._apply_responsive_layout()
	var tabs := window.find_child("@TabContainer*", true, false) as TabContainer
	if tabs == null:
		for child in window.find_children("*", "TabContainer", true, false):
			tabs = child as TabContainer
			break
	_assert(tabs != null and tabs.get_tab_count() == 5, "Ledger UI must render five distinct report sections")
	if tabs != null:
		var names: Array[String] = []
		for index in range(tabs.get_tab_count()):
			names.append(tabs.get_tab_title(index))
			var spread := tabs.get_tab_control(index) as GridContainer
			_assert(spread != null and spread.get_child_count() == 2, "Ledger section %s must render an open two-page spread" % names[index])
			if spread != null:
				for page in spread.get_children():
					_assert(page is PanelContainer, "Ledger page must own its paper background")
					if page is PanelContainer:
						var paper := page.get_theme_stylebox("panel") as StyleBoxFlat
						_assert(paper != null and paper.bg_color.a > 0.99, "Ledger paper must be opaque")
		_assert(names == ["Overview", "People", "Buildings", "Food", "Stores"], "Ledger section order is wrong: %s" % [names])
		var selected := tabs.get_theme_stylebox("tab_selected") as StyleBoxFlat
		var unselected := tabs.get_theme_stylebox("tab_unselected") as StyleBoxFlat
		_assert(selected != null and _contrast_ratio(tabs.get_theme_color("font_selected_color"), selected.bg_color) >= 4.5, "Selected ledger tab lacks readable contrast")
		_assert(unselected != null and _contrast_ratio(tabs.get_theme_color("font_unselected_color"), unselected.bg_color) >= 4.5, "Unselected ledger tabs lack readable contrast")
	var rendered_text := ""
	for page_texts in (window.get("_pages") as Dictionary).values():
		for page_text in page_texts:
			rendered_text += (page_text as RichTextLabel).text
	for required in ["Name", "Job", "Workplace", "Purpose", "Owner", "Food", "Stock", "Made/day", "Used/day", "Remaining", "Item", "Quantity"]:
		_assert(rendered_text.contains(required), "Ledger is missing player-facing column '%s'" % required)
	for redundant_column in ["Status", "Condition"]:
		_assert(not rendered_text.contains(redundant_column), "Ledger must not show redundant column '%s'" % redundant_column)
	for forbidden in ["res://", "realized", "realization_state", "slot_id", "container_id", ".stock."]:
		_assert(not rendered_text.contains(forbidden), "Ledger leaked internal value '%s'" % forbidden)
	var pages := window.get("_pages") as Dictionary
	var building_pages := pages.get("buildings", []) as Array
	_assert((building_pages[0] as RichTextLabel).text.contains("Town Jail") and (building_pages[0] as RichTextLabel).text.contains("Town Keep") and (building_pages[0] as RichTextLabel).text.contains("Town Bar"), "Buildings must fill the left page before overflowing")
	_assert((building_pages[1] as RichTextLabel).text.is_empty(), "Three buildings must not spill onto the right page")
	var people_pages := pages.get("people", []) as Array
	_assert((people_pages[1] as RichTextLabel).text.is_empty(), "People must not show unrelated vacancy content or an unnecessary continuation")
	var overflow_split := window.call("_split_for_pages", range(11)) as Array
	_assert((overflow_split[0] as Array).size() == 10 and (overflow_split[1] as Array).size() == 1, "Ledger must fill ten visible rows before continuing on the right page")
	_assert(not rendered_text.contains("___"), "Ledger headings must not use decorative underscore rules")
	_assert(not rendered_text.contains("[font_size="), "Ledger pages must not repeat section headings inside the page")
	var food_text := ((pages.get("food", []) as Array)[0] as RichTextLabel).text
	var stores_text := ((pages.get("stores", []) as Array)[0] as RichTextLabel).text
	_assert(food_text.contains("Bread") and not food_text.contains("Green Bottle"), "Food tab must contain only food items")
	_assert(stores_text.contains("Green Bottle") and not stores_text.contains("Bread"), "Stores tab must contain only non-food items")
	var viewport_size := window.get_viewport_rect().size
	_assert(window.size.x <= viewport_size.x and window.size.y <= viewport_size.y, "Ledger window %s must fit viewport %s" % [window.size, viewport_size])
	window._apply_layout_for_viewport(Vector2(700, 700))
	_assert(window.size.x <= 700.0 and window.size.y <= 700.0, "Ledger must fit a narrow viewport: ledger=%s" % window.size)
	for spread in (window.get("_spreads") as Array):
		_assert((spread as GridContainer).columns == 1, "Ledger pages must stack on a narrow viewport")
	window._apply_layout_for_viewport(Vector2(1086, 621))
	_assert(window.position.x >= 20.0 and window.position.y >= 16.0, "Ledger cover must leave room for its border and shadow")
	_assert(window.position.x + window.size.x <= 1066.0 and window.position.y + window.size.y <= 605.0, "Ledger cover must stay inside its safe viewport inset")
	if _failed:
		window.free()
		quit(1)
		return
	print("TOWN_LEDGER_UI_OK")
	window.free()
	quit()


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)


func _contrast_ratio(foreground: Color, background: Color) -> float:
	var lighter := maxf(foreground.get_luminance(), background.get_luminance())
	var darker := minf(foreground.get_luminance(), background.get_luminance())
	return (lighter + 0.05) / (darker + 0.05)
