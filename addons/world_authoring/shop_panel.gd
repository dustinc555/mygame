@tool
extends VBoxContainer

## Shop-only authoring. Search and quantity edits never rebuild the facility
## workspace or reload its item catalog. Undo restores only these controls.
var _tools: RefCounted
var _shop: Node
var _profiles: Array[Resource] = []
var _picker: OptionButton
var _search: LineEdit
var _rows: VBoxContainer
var _controls := {}
var _numbers := {}
var _updating := false
var _capacity_warning: Label
var _capacity_revision := 0
var _capacity_inputs: Array = []
var _catalog_started := false
var _catalog_revision := 0
var _catalog_status: Label


func _enter_tree() -> void:
	if _tools != null:
		set_shop.call_deferred(_shop)


func _exit_tree() -> void:
	# The router unmounts (but retains) the dock when changing editor context.
	# Cancel yielded work and restart it safely if this panel is mounted again.
	_catalog_revision += 1
	_capacity_revision += 1
	_catalog_started = false
	_capacity_inputs.clear()


func setup(tools: RefCounted) -> void:
	_tools = tools
	if _tools.has_signal("item_catalog_changed"):
		_tools.connect("item_catalog_changed", _on_item_catalog_changed)
	_picker = OptionButton.new()
	for file in DirAccess.get_files_at("res://features/settlements/resources/merchants"):
		if file.get_extension() != "tres": continue
		var profile := load("res://features/settlements/resources/merchants/" + file) as MerchantProfile
		if profile == null: continue
		_profiles.append(profile)
		_picker.add_item(profile.display_name)
	_picker.item_selected.connect(_on_profile_selected)
	add_child(_picker)
	for field in [{"key": "starting_silver", "text": "Starting silver (seed once)", "min": 0, "max": 100000}, {"key": "stock_columns", "text": "Stock columns", "min": 4, "max": 64}, {"key": "stock_rows", "text": "Stock rows", "min": 4, "max": 64}, {"key": "replenishment_days", "text": "Replenish every game days", "min": 1, "max": 365}, {"key": "replenishment_hour", "text": "Replenish at hour", "min": 0, "max": 23}]:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = field.text
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var number := SpinBox.new()
		number.min_value = field.min
		number.max_value = field.max
		number.value_changed.connect(_on_number_changed.bind(str(field.key)))
		row.add_child(number)
		_numbers[field.key] = number
		add_child(row)
	var hint := Label.new()
	hint.text = "Target stock · Replenishes · Reset clears this shop's override.\nDefaults seed new traders; saved characters keep their goods and policy."
	add_child(hint)
	_capacity_warning = Label.new()
	_capacity_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_capacity_warning)
	_search = LineEdit.new()
	_search.placeholder_text = "Search items by name or ID…"
	_search.text_changed.connect(_filter)
	add_child(_search)
	_catalog_status = Label.new()
	_catalog_status.text = "Loading item catalog…"
	add_child(_catalog_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 180
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	add_child(scroll)


func set_shop(shop: Node) -> void:
	_shop = shop
	if not is_instance_valid(_shop) or not is_inside_tree(): return
	if not _catalog_started:
		_catalog_started = true
		_build_catalog_rows()
	refresh()


func _build_catalog_rows() -> void:
	var revision := _catalog_revision
	await get_tree().process_frame
	if revision != _catalog_revision: return
	var deadline := Time.get_ticks_usec() + 2000
	for item in _tools.container_item_options("general"):
		if not item.sellable or item.is_currency_item(): continue
		if _controls.has(item.resource_path): continue
		_add_item_row(item)
		if Time.get_ticks_usec() >= deadline:
			refresh()
			await get_tree().process_frame
			if revision != _catalog_revision: return
			deadline = Time.get_ticks_usec() + 2000
	_catalog_status.visible = _tools.has_method("is_item_catalog_loading") and _tools.call("is_item_catalog_loading")
	refresh()


func _on_item_catalog_changed() -> void:
	_catalog_revision += 1
	_catalog_status.show()
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_controls.clear()
	_catalog_started = false
	if is_instance_valid(_shop): set_shop(_shop)


func _add_item_row(item: ItemDefinition) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = item.display_name
	label.tooltip_text = item.resource_path
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var quantity := SpinBox.new()
	quantity.max_value = 9999
	quantity.custom_minimum_size.x = 100
	row.add_child(quantity)
	var replenish := CheckBox.new()
	replenish.text = "Replenishes"
	row.add_child(replenish)
	var reset := Button.new()
	reset.text = "Reset"
	row.add_child(reset)
	quantity.value_changed.connect(_on_quantity_changed.bind(item.resource_path))
	replenish.toggled.connect(_on_replenishes_changed.bind(item.resource_path))
	reset.pressed.connect(_reset_item.bind(item.resource_path))
	_rows.add_child(row)
	_controls[item.resource_path] = {"row": row, "quantity": quantity, "replenishes": replenish, "reset": reset, "search": (item.display_name + " " + item.item_id).to_lower()}


func refresh() -> void:
	if not is_instance_valid(_shop) or not is_inside_tree(): return
	_updating = true
	_picker.select(-1)
	for index in _profiles.size():
		if _profiles[index] == _shop.merchant_profile: _picker.select(index)
	for key in _numbers: _numbers[key].value = _shop.get(key)
	var rules: Dictionary = _shop.effective_stock()
	for path in _controls:
		var rule: Dictionary = rules.get(path, {})
		var controls: Dictionary = _controls[path]
		controls.quantity.value = int(rule.get("quantity", 0))
		controls.replenishes.button_pressed = bool(rule.get("replenishes", false))
		controls.reset.disabled = not _shop.stock_overrides.has(path)
	_updating = false
	var inputs: Array = [rules, _shop.stock_columns, _shop.stock_rows, _shop.starting_silver]
	if inputs != _capacity_inputs:
		_capacity_inputs = inputs.duplicate(true)
		_capacity_revision += 1
		_check_capacity(_capacity_revision, inputs)
	_filter(_search.text)


func _check_capacity(revision: int, inputs: Array) -> void:
	_capacity_warning.text = "Checking stock capacity…"
	_capacity_warning.show()
	# Do not run packing inside a click callback or replay stale edits.
	await get_tree().process_frame
	if revision != _capacity_revision: return
	var check := SettlementShop.StockCapacityCheck.new(inputs[0], inputs[1], inputs[2], inputs[3])
	while not check.done:
		var deadline := Time.get_ticks_usec() + 2000
		while not check.done and Time.get_ticks_usec() < deadline:
			check.step()
		if not check.done:
			await get_tree().process_frame
			if revision != _capacity_revision: return
	_capacity_warning.text = check.warning
	_capacity_warning.visible = not check.warning.is_empty()


func _filter(text: String) -> void:
	var needle := text.strip_edges().to_lower()
	for controls in _controls.values():
		controls.row.visible = needle.is_empty() or str(controls.search).contains(needle)


func _on_profile_selected(index: int) -> void:
	if not _updating and index >= 0:
		_tools.set_shop_property(_shop, "merchant_profile", _profiles[index], self)


func _on_number_changed(value: float, key: String) -> void:
	if not _updating:
		_tools.set_shop_property(_shop, key, int(value), self)


func _on_quantity_changed(value: float, path: String) -> void:
	_set_item_override(path, "quantity", int(value))


func _on_replenishes_changed(value: bool, path: String) -> void:
	_set_item_override(path, "replenishes", value)


func _set_item_override(path: String, key: String, value: Variant) -> void:
	if _updating or not is_instance_valid(_shop): return
	var overrides: Dictionary = _shop.stock_overrides.duplicate(true)
	var rule: Dictionary = (_shop.effective_stock().get(path, {"quantity": 0, "replenishes": false}) as Dictionary).duplicate(true)
	rule[key] = value
	overrides[path] = rule
	_tools.set_shop_property(_shop, "stock_overrides", overrides, self)


func _reset_item(path: String) -> void:
	if not is_instance_valid(_shop): return
	var overrides: Dictionary = _shop.stock_overrides.duplicate(true)
	overrides.erase(path)
	_tools.set_shop_property(_shop, "stock_overrides", overrides, self)
