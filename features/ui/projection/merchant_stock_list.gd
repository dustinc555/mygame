extends VBoxContainer

## A read-only catalog over the merchant's real stock. Grouping never merges
## stacks or changes their IDs/packing. The inventory controller owns purchases.
signal purchase_requested(goods: Array, quantity: int)

@export var preferred_list_height := 380.0

var role: MerchantRole
var buyer_inventory: InventoryData
var offers: Array[Dictionary] = []
var stock_scroll: ScrollContainer
var stock_grid: GridContainer
var purse: Label
var merchant_purse: Label
var quantity: SpinBox
var buy_button: Button
var checkout: HBoxContainer
var _selected: Dictionary = {}


func _ready() -> void:
	name = "MerchantStockList"
	add_theme_constant_override("separation", 12)
	var money := HBoxContainer.new()
	add_child(money)
	purse = Label.new()
	purse.tooltip_text = "Your silver"
	purse.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	money.add_child(purse)
	merchant_purse = Label.new()
	merchant_purse.tooltip_text = "Merchant's silver"
	money.add_child(merchant_purse)
	stock_scroll = ScrollContainer.new()
	stock_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stock_scroll.custom_minimum_size.y = preferred_list_height
	stock_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(stock_scroll)
	stock_grid = GridContainer.new()
	stock_grid.columns = 4
	stock_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stock_grid.add_theme_constant_override("h_separation", 6)
	stock_grid.add_theme_constant_override("v_separation", 8)
	stock_scroll.add_child(stock_grid)
	# Reserve the action strip so selecting goods never moves the stock shelf.
	var action_strip := Control.new()
	action_strip.custom_minimum_size.y = 38
	add_child(action_strip)
	checkout = HBoxContainer.new()
	action_strip.add_child(checkout)
	checkout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	quantity = SpinBox.new()
	quantity.min_value = 1
	quantity.max_value = 1
	quantity.step = 1
	quantity.custom_minimum_size.x = 72
	quantity.tooltip_text = "Quantity"
	checkout.add_child(quantity)
	buy_button = Button.new()
	buy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	checkout.add_child(buy_button)

	quantity.value_changed.connect(func(_value): _update_checkout())
	buy_button.pressed.connect(func():
		if not buy_button.disabled and not _selected.is_empty():
			purchase_requested.emit(_selected.entries.duplicate(), int(quantity.value))
	)
	_update_checkout()


func setup(merchant: MerchantRole) -> void:
	role = merchant
	refresh()


func set_buyer_inventory(inventory: InventoryData) -> void:
	if buyer_inventory == inventory:
		return
	if buyer_inventory != null and buyer_inventory.changed.is_connected(_update_checkout):
		buyer_inventory.changed.disconnect(_update_checkout)
	buyer_inventory = inventory
	if buyer_inventory != null:
		buyer_inventory.changed.connect(_update_checkout)
	_update_checkout()


func refresh() -> void:
	if not is_instance_valid(role):
		_rebuild_rows()
		return
	var inventory := role.get_shop_inventory()
	offers = collect_offers(inventory)
	_rebuild_rows()


static func collect_offers(inventory: InventoryData) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	# Only equal state can share a row. Worn bandages, filled vessels and stolen
	# provenance remain distinct; the exact entries are retained for settlement.
	var by_definition: Dictionary = {}
	for entry in inventory.entries:
		if entry.definition == null or not entry.definition.sellable or entry.definition.is_currency_item() or entry.definition.is_currency_container():
			continue
		var variants: Array = by_definition.get(entry.definition, [])
		var group: Dictionary = {}
		for candidate in variants:
			var exemplar = candidate.entries[0]
			if exemplar.metadata == entry.metadata and exemplar.contained_item_counts == entry.contained_item_counts:
				group = candidate
				break
		if group.is_empty():
			group = {"definition": entry.definition, "entries": [], "quantity": 0}
			variants.append(group)
			by_definition[entry.definition] = variants
			result.append(group)
		group.entries.append(entry)
		group.quantity += entry.count
	result.sort_custom(func(a, b): return a.definition.display_name.naturalnocasecmp_to(b.definition.display_name) < 0)
	return result


static func item_category(definition: ItemDefinition) -> String:
	if definition.nutrition_value > 0:
		return "Food"
	if definition.has_any_tool_tag():
		return "Tools"
	if definition.is_equippable():
		return "Equipment"
	return "Supplies"


func _rebuild_rows() -> void:
	var previous := _selected
	for child in stock_grid.get_children():
		stock_grid.remove_child(child)
		child.queue_free()
	_selected = {}
	if not is_instance_valid(role):
		offers.clear()
		_update_selection()
		return
	for offer in offers:
		var tile := _make_stock_tile(offer)
		stock_grid.add_child(tile)
		if not previous.is_empty() and _same_variant(previous, offer):
			_selected = offer
			tile.button_pressed = true
	_update_selection()


func _make_stock_tile(offer: Dictionary) -> Button:
	var definition: ItemDefinition = offer.definition
	var tile := Button.new()
	tile.custom_minimum_size = Vector2(72, 98)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.toggle_mode = true
	tile.tooltip_text = _describe(offer)
	var art := TextureRect.new()
	art.texture = definition.icon
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.offset_left = 8
	art.offset_right = -8
	art.offset_top = 10
	art.offset_bottom = -24
	if definition.icon == null:
		var fallback := Label.new()
		fallback.text = definition.display_name
		fallback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.add_theme_font_size_override("font_size", 11)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.add_child(fallback)
		fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var count := Label.new()
	count.text = str(offer.quantity)
	count.add_theme_font_size_override("font_size", 11)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(count)
	count.position = Vector2(5, 2)
	var price := Label.new()
	var amount := role.get_sell_price(definition)
	price.text = "%d s" % amount if amount >= 0 else "—"
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price.add_theme_font_size_override("font_size", 12)
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(price)
	price.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	price.offset_left = 5
	price.offset_right = -5
	price.offset_top = -22
	price.offset_bottom = -3
	tile.pressed.connect(func(): _select_offer(offer))
	return tile


static func _same_variant(a: Dictionary, b: Dictionary) -> bool:
	return a.definition == b.definition and a.entries[0].metadata == b.entries[0].metadata and a.entries[0].contained_item_counts == b.entries[0].contained_item_counts


static func _describe(offer: Dictionary) -> String:
	var definition: ItemDefinition = offer.definition
	var text := "%s · %s · %.2f weight each · %d × %d spaces" % [definition.display_name, item_category(definition), definition.unit_weight, definition.grid_size.x, definition.grid_size.y]
	var entry = offer.entries[0]
	if definition.bandage_max_uses > 0:
		text += " · %d/%d uses" % [int(entry.contained_item_counts.get(InventoryData.ENTRY_BANDAGE_USES_KEY, definition.bandage_max_uses)), definition.bandage_max_uses]
	if bool(entry.metadata.get(InventoryData.META_STOLEN, false)):
		text += " · Stolen"
	return text


func _select_offer(offer: Dictionary) -> void:
	_selected = offer
	for i in range(stock_grid.get_child_count()):
		stock_grid.get_child(i).set_pressed_no_signal(_same_variant(offers[i], offer))
	quantity.value = 1
	_update_selection()


func _update_selection() -> void:
	quantity.max_value = 1 if _selected.is_empty() else _selected.quantity
	_update_checkout()


func _update_checkout() -> void:
	var price := -1 if _selected.is_empty() or not is_instance_valid(role) else role.get_sell_price(_selected.definition)
	var total := maxi(0, price) * int(quantity.value)
	var affordable := buyer_inventory != null and buyer_inventory.count_item(InventoryData.SILVER_ITEM) >= total
	if is_instance_valid(role):
		merchant_purse.text = "%d silver" % role.get_shop_inventory().count_item(InventoryData.SILVER_ITEM)
	else:
		merchant_purse.text = "Unavailable"
	purse.text = "%d silver" % buyer_inventory.count_item(InventoryData.SILVER_ITEM) if buyer_inventory != null else ""
	checkout.visible = not _selected.is_empty()
	buy_button.disabled = price < 0 or not affordable
	buy_button.text = "Buy · %d silver" % total
	buy_button.tooltip_text = "Not enough silver" if price >= 0 and not affordable else ""
