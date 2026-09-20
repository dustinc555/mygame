extends Node
## Normal actor lifecycle + real inventory windows. Shift events enter the grid's
## GUI handler (not OS pointer injection), never the private commerce helpers.

const SILVER = preload("res://features/inventory/resources/items/silver.tres")
const CAN = preload("res://features/inventory/resources/items/watering_can.tres")
const SEEDS = preload("res://features/inventory/resources/items/tomato_seeds.tres")
const STACK_ID := "merchant.exact.can"
const CONTENTS := {"water_liters": 2.75}
const METADATA := {"quality": 0.63, "origin": {"maker": "ordinary merchant"}}
const NAVIGATION_FIXTURE := preload("res://tests/validation/helpers/navigation_fixture.gd")

var _controller: PartyInventoryController
var _player: WorldActor
var _merchant: WorldActor
var _role: MerchantRole
var _gecs: GecsWorldController
var _context: BootstrapContext
var _population: PopulationController
var _failures: Array[String] = []
var _checks := 0
var _actor_kind := ""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var floor_fixture := NAVIGATION_FIXTURE.new()
	add_child(floor_fixture)
	floor_fixture.add_floor()
	var party := PartyManager.new()
	party.name = "PartyManager"
	add_child(party)
	var hud := CanvasLayer.new()
	hud.name = "GameHUD"
	var windows := Control.new()
	windows.name = "InventoryWindowLayer"
	hud.add_child(windows)
	add_child(hud)
	_controller = PartyInventoryController.new()
	add_child(_controller)
	var context := BootstrapContext.new(self, hud)
	_context = context
	BootstrapContext.active = context
	_gecs = GecsWorldController.new()
	add_child(_gecs)
	context.register(GecsWorldController.SERVICE_ID, _gecs)
	_gecs.initialize(context)
	_controller.initialize(context)
	_player = _make_actor("buyer", true)
	_gecs.register_actor(_player)
	party.set_party_members([_player])
	party.select_only(_player)
	for humanoid in [false, true]:
		_actor_kind = "HumanoidCharacter" if humanoid else "WorldActor"
		_merchant = _make_actor("merchant", humanoid)
		_gecs.register_actor(_merchant)
		_role = MerchantRole.new()
		_role.name = "MerchantRole"
		_merchant.add_child(_role)
		await get_tree().process_frame
		_check(await floor_fixture.wait_until(func(): return _player.is_on_floor() and _merchant.is_on_floor(), 5.0), "ordinary buyer and merchant settle on the fixture floor with physics enabled")
		_check(not _controller._owners_too_far(_player, _merchant), "trade begins inside the ordinary five-metre inventory range")
		_check(_player.inventory != null and _merchant.inventory != null, "normal readiness initializes personal inventories")
		_check(_merchant.get_inventory_for_display() == _role.get_shop_inventory(), "ordinary actor displays its attached role's stock")
		var price := MerchantPrice.new()
		price.item_definition = CAN
		price.buy_price = 2
		price.sell_price = 3
		_role.prices = [price]
		await _test_buy_and_sell()
		await _test_stack_quantity()
		for direction in ["buy", "sell"]:
			for refusal in ["funds", "full_grid", "weight", "admission", "silver_capacity", "unpriced", "unsellable"]:
				await _test_refusal(direction, refusal)
		await _test_zero_price()
		await _test_work_inventory_lock()
		for refusal in ["none", "funds", "admission", "silver_capacity", "full_grid"]:
			await _test_cursor_sale(refusal)
		for refusal in ["none", "funds", "replacement_space", "silver_capacity", "durable_identity"]:
			await _test_equipment_purchase(refusal)
		await _test_equipment_metadata_round_trip()
		_controller._close_all_inventory_windows()
		_gecs.unregister_actor(_merchant)
		_merchant.queue_free()
		await get_tree().process_frame
	await _test_nonmerchant_context()
	await _test_persistence_lifecycle()
	_controller._close_all_inventory_windows()
	await get_tree().process_frame
	BootstrapContext.active = null
	if _failures.is_empty():
		print("MERCHANT_TRANSACTIONS_OK checks=%d" % _checks)
	else:
		for failure in _failures:
			printerr("MERCHANT_TRANSACTIONS_FAILED: ", failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _test_buy_and_sell() -> void:
	_reset_trade("buy")
	var shop := _role.get_shop_inventory()
	var personal_before := _inventory_snapshot(_merchant.inventory)
	_controller.open_inventory_pair(_player, _merchant)
	await get_tree().process_frame
	var observed := {"count": 0}
	var observer := func():
		observed.count += 1
		_check(_player.inventory.count_item(SILVER) == 7 and shop.count_item(SILVER) == 23 and _exact_stack(_player.inventory, STACK_ID, CAN, 1) and _entry(shop, STACK_ID) == null, "purchase observers only see the complete exchange")
	shop.changed.connect(observer)
	_player.inventory.changed.connect(observer)
	_shift_click(_controller.secondary_inventory_window, _entry(shop, STACK_ID))
	shop.changed.disconnect(observer)
	_player.inventory.changed.disconnect(observer)
	_check(observed.count == 2, "purchase emits one completed update per inventory")
	await get_tree().process_frame
	_check(_exact_stack(_player.inventory, STACK_ID, CAN, 1) and _entry(shop, STACK_ID) == null, "Shift-click buys exact stack, contents and metadata")
	_check(_player.inventory.count_item(SILVER) == 7 and shop.count_item(SILVER) == 23,
		"purchase charges both balances (buyer=%d merchant=%d; expected 7/23)" % [_player.inventory.count_item(SILVER), shop.count_item(SILVER)])
	_check(_player.get_equipment().get_equipped_item("weapon") == null, "paired purchase does not auto-equip")
	_check_durable_inventories("Shift purchase")
	_shift_click(_controller.primary_character_window, _entry(_player.inventory, STACK_ID))
	await get_tree().process_frame
	_check(_entry(_player.inventory, STACK_ID) == null and _exact_stack(shop, STACK_ID, CAN, 1), "Shift-click sells exact purchased stack back")
	_check(_player.inventory.count_item(SILVER) == 9 and shop.count_item(SILVER) == 21, "sale moves both silver balances")
	_check(_inventory_snapshot(_merchant.inventory) == personal_before, "trade never debits merchant personal inventory instead of role stock")
	_check_durable_stack(STACK_ID, _merchant.stable_id + ".shop_inventory", _merchant.stable_id, "Shift sale")
	_check_durable_inventories("Shift sale")


func _test_refusal(direction: String, refusal: String) -> void:
	_reset_trade(direction)
	var shop := _role.get_shop_inventory()
	var source := shop if direction == "buy" else _player.inventory
	var target := _player.inventory if direction == "buy" else shop
	var payer := target
	var price: MerchantPrice = _role.prices[0]
	var entry = _entry(source, STACK_ID)
	match refusal:
		"funds":
			_check(payer.remove_item_count(SILVER, payer.count_item(SILVER)), "drain payer silver fixture")
		"full_grid":
			_fill_grid(target)
			_check(target.find_first_space(CAN) == Vector2i(-1, -1), "full receiver fixture has no item space")
		"weight":
			target.use_weight = true
			target.max_weight = target.get_total_weight()
			_check(target.find_first_space(CAN) != Vector2i(-1, -1), "overweight receiver still has geometric space")
		"admission":
			target.set_admission_validator(func(definition, _count): return definition != CAN)
		"silver_capacity":
			# Goods can move, but their seller cannot accept payment by weight.
			source.use_weight = true
			source.max_weight = source.get_total_weight() - source.get_entry_weight(entry)
		"unpriced":
			price.buy_price = -1
			price.sell_price = -1
		"unsellable":
			var unsellable := CAN.duplicate() as ItemDefinition
			unsellable.sellable = false
			entry.definition = unsellable
			# Prices match resource identity. An unpriced clone would hide a broken
			# sellability guard behind the separate missing-price refusal.
			price.item_definition = unsellable
			var trade_price: int = _role.get_sell_price(unsellable) if direction == "buy" else _role.get_buy_price(unsellable)
			_check(trade_price > 0 and payer.count_item(SILVER) >= trade_price * entry.count, "unsellable fixture is positively priced and its payer can afford it")
			_check(source.can_move_entry_to_inventory(entry, target, target.find_first_space(unsellable)), "unsellable fixture otherwise passes goods admission and capacity")
			_check(source.can_add_item_count(SILVER, trade_price * entry.count), "unsellable fixture seller can accept payment")
	var before_source := _inventory_snapshot(source)
	var before_target := _inventory_snapshot(target)
	var durable_before := _gecs.get_inventory_stacks()
	var sequences := [source.next_stack_sequence, target.next_stack_sequence]
	var personal_before := _inventory_snapshot(_merchant.inventory)
	_controller.open_inventory_pair(_player, _merchant)
	await get_tree().process_frame
	var observed := {"count": 0}
	var observer := func(): observed.count += 1
	source.changed.connect(observer)
	target.changed.connect(observer)
	_shift_click(_controller.secondary_inventory_window if direction == "buy" else _controller.primary_character_window, entry)
	source.changed.disconnect(observer)
	target.changed.disconnect(observer)
	await get_tree().process_frame
	_check(observed.count == 0 and sequences == [source.next_stack_sequence, target.next_stack_sequence], "%s refusal (%s) does not publish or allocate partial state" % [direction, refusal])
	_check(_inventory_snapshot(source) == before_source and _inventory_snapshot(target) == before_target,
		"%s refusal (%s) preserves all goods, metadata and both currency inventories" % [direction, refusal])
	_check(source.entries.has(entry), "%s refusal (%s) retains the exact live source entry" % [direction, refusal])
	_check(_inventory_snapshot(_merchant.inventory) == personal_before, "%s refusal (%s) leaves personal merchant bag unchanged" % [direction, refusal])
	_check(_gecs.get_inventory_stacks() == durable_before, "%s refusal (%s) leaves durable stock and currency unchanged" % [direction, refusal])


func _test_stack_quantity() -> void:
	_reset_trade("buy")
	var shop := _role.get_shop_inventory()
	_check(shop.remove_entry(_entry(shop, STACK_ID)), "remove one-item fixture")
	_check(shop.add_entry_with_contents(SEEDS, 3, CONTENTS, METADATA, STACK_ID), "seed three-item priced stack")
	var price: MerchantPrice = _role.prices[0]
	price.item_definition = SEEDS
	_controller.open_inventory_pair(_player, _merchant)
	await get_tree().process_frame
	_shift_click(_controller.secondary_inventory_window, _entry(shop, STACK_ID))
	await get_tree().process_frame
	_check(_exact_stack(_player.inventory, STACK_ID, SEEDS, 3) and _entry(shop, STACK_ID) == null and _player.inventory.count_item(SILVER) == 1 and shop.count_item(SILVER) == 29, "purchase prices the entire exact quantity")
	_shift_click(_controller.primary_character_window, _entry(_player.inventory, STACK_ID))
	await get_tree().process_frame
	_check(_exact_stack(shop, STACK_ID, SEEDS, 3) and _entry(_player.inventory, STACK_ID) == null and _player.inventory.count_item(SILVER) == 7 and shop.count_item(SILVER) == 23, "sale prices the entire exact quantity")
	price.item_definition = CAN


func _test_zero_price() -> void:
	_reset_trade("buy")
	var shop := _role.get_shop_inventory()
	var price: MerchantPrice = _role.prices[0]
	price.sell_price = 0
	_controller.open_inventory_pair(_player, _merchant)
	await get_tree().process_frame
	_shift_click(_controller.secondary_inventory_window, _entry(shop, STACK_ID))
	await get_tree().process_frame
	_check(_exact_stack(_player.inventory, STACK_ID, CAN, 1) and _entry(shop, STACK_ID) == null, "explicit zero price transfers goods without false insufficient-funds refusal")
	_check(_player.inventory.count_item(SILVER) == 10 and shop.count_item(SILVER) == 20, "zero-price transfer preserves both balances")


func _test_work_inventory_lock() -> void:
	_reset_trade("buy")
	var work := InventoryData.new(4, 4, 100.0, false)
	_check(work.add_entry_with_contents(CAN, 1, CONTENTS, METADATA, "work.can"), "seed locked work bag")
	_merchant.get_inventory().set_work_inventory(work)
	_controller.open_inventory_pair(_player, _merchant)
	await get_tree().process_frame
	var before := [_inventory_snapshot(work), _inventory_snapshot(_player.inventory), _inventory_snapshot(_role.get_shop_inventory())]
	_shift_click(_controller.secondary_inventory_window, _entry(work, "work.can"))
	await get_tree().process_frame
	_check(before == [_inventory_snapshot(work), _inventory_snapshot(_player.inventory), _inventory_snapshot(_role.get_shop_inventory())], "merchant work bag stays locked and cannot charge stock prices")
	_merchant.get_inventory().set_work_inventory(null)


func _test_cursor_sale(refusal: String) -> void:
	_reset_trade("sell")
	var shop := _role.get_shop_inventory()
	var entry = _entry(_player.inventory, STACK_ID)
	_controller.open_inventory_pair(_player, _merchant)
	await get_tree().process_frame
	if not is_instance_valid(_controller.secondary_inventory_window):
		print("MERCHANT_PAIR_REFUSAL ", JSON.stringify({
			"kind": _actor_kind, "refusal": refusal,
			"player": _player.global_position, "merchant": _merchant.global_position,
			"distance": _player.global_position.distance_to(_merchant.global_position),
			"out_of_range": _controller._owners_too_far(_player, _merchant),
			"player_physics": _player.is_physics_processing(), "merchant_physics": _merchant.is_physics_processing(),
		}))
	_check(_player.inventory.remove_entry(entry), "lift cursor sale fixture from source once")
	_controller._start_cursor_item_drag(_player, entry.definition, entry.count, entry.contained_item_counts, entry.metadata, entry.stack_id)
	var cursor: CursorItemDragSource = _controller.cursor_item_drag_source
	var data := cursor._make_drag_data()
	match refusal:
		"funds": shop.remove_item_count(SILVER, shop.count_item(SILVER))
		"admission": shop.set_admission_validator(func(definition, _count): return definition != CAN)
		"silver_capacity":
			_player.inventory.use_weight = true
			_player.inventory.max_weight = _player.inventory.get_total_weight()
		"full_grid": _fill_grid(shop)
	var before := [_inventory_snapshot(shop), _inventory_snapshot(_player.inventory), _inventory_snapshot(_merchant.inventory)]
	var durable_before := _gecs.get_inventory_stacks()
	var updates := {"count": 0}
	var observe := func():
		updates.count += 1
		if refusal == "none":
			_check(_player.inventory.count_item(SILVER) == 12 and shop.count_item(SILVER) == 18 and _exact_stack(shop, STACK_ID, CAN, 1) and not cursor._has_item, "cursor sale observers see payment, exact goods and consumed cursor together")
	shop.changed.connect(observe)
	_player.inventory.changed.connect(observe)
	var cell := shop.find_first_space(CAN)
	_controller.secondary_inventory_window._handle_drop(data, cell)
	shop.changed.disconnect(observe)
	_player.inventory.changed.disconnect(observe)
	if refusal == "none":
		_check(_exact_stack(shop, STACK_ID, CAN, 1) and not cursor._has_item and _player.inventory.count_item(SILVER) == 12 and shop.count_item(SILVER) == 18 and updates.count == 2, "cursor sale preserves exact contents and metadata while charging both balances")
		_check_durable_stack(STACK_ID, _merchant.stable_id + ".shop_inventory", _merchant.stable_id, "cursor sale")
		_check_durable_inventories("cursor sale")
	else:
		_check(before == [_inventory_snapshot(shop), _inventory_snapshot(_player.inventory), _inventory_snapshot(_merchant.inventory)] and updates.count == 0, "cursor sale refusal (%s) preserves all inventories without publication" % refusal)
		_check(cursor._has_item and cursor._make_drag_data() == data, "cursor sale refusal (%s) keeps exact goods on cursor" % refusal)
		_check(_gecs.get_inventory_stacks() == durable_before, "cursor refusal (%s) preserves durable stock and both balances" % refusal)
	cursor.consume_drag(int(data.cursor_drag_id))
	await get_tree().process_frame


func _test_equipment_purchase(refusal: String) -> void:
	var actor_id := _player.stable_id
	_player.get_equipment().unequip_item_from_slot("weapon")
	_reset_trade("buy")
	var shop := _role.get_shop_inventory()
	var entry = _entry(shop, STACK_ID)
	if refusal == "funds":
		_player.inventory.remove_item_count(SILVER, _player.inventory.count_item(SILVER))
	if refusal == "durable_identity":
		_player.stable_id = ""
	if refusal == "replacement_space":
		_player.get_equipment().equip_item_to_slot(CAN, "weapon", "existing.weapon")
		_fill_grid(_player.inventory)
	if refusal == "silver_capacity":
		shop.use_weight = true
		shop.max_weight = shop.get_total_weight() - shop.get_entry_weight(entry)
	_controller.open_inventory_pair(_player, _merchant)
	await get_tree().process_frame
	var equipment := _player.get_equipment()
	var before := [_inventory_snapshot(shop), _inventory_snapshot(_player.inventory), _inventory_snapshot(_merchant.inventory), equipment.get_equipped_item("weapon"), equipment.get_equipped_stack_id("weapon")]
	var updates := {"count": 0}
	var observe := func():
		updates.count += 1
		if refusal == "none":
			_check(_player.inventory.count_item(SILVER) == 7 and shop.count_item(SILVER) == 23 and not shop.entries.has(entry) and equipment.get_equipped_stack_id("weapon") == STACK_ID, "equipment purchase observers never see an unpaid or unremoved item")
	shop.changed.connect(observe)
	_player.inventory.changed.connect(observe)
	var slot: EquipmentSlotControl = _controller.primary_character_window._equipment_slots.get("weapon")
	_check(slot != null and slot._can_drop_data(Vector2.ZERO, {"entry": entry, "source_owner": _merchant}), "merchant item fits real target equipment slot")
	if slot != null:
		slot._drop_data(Vector2.ZERO, {"entry": entry, "source_owner": _merchant})
	shop.changed.disconnect(observe)
	_player.inventory.changed.disconnect(observe)
	if refusal == "none":
		_check(equipment.get_equipped_stack_id("weapon") == STACK_ID and equipment.get_equipped_item("weapon") == CAN and not shop.entries.has(entry) and _player.inventory.count_item(SILVER) == 7 and shop.count_item(SILVER) == 23 and updates.count == 2, "drag-to-equipment buys exact stack with one complete update per inventory")
	else:
		_check(before == [_inventory_snapshot(shop), _inventory_snapshot(_player.inventory), _inventory_snapshot(_merchant.inventory), equipment.get_equipped_item("weapon"), equipment.get_equipped_stack_id("weapon")] and updates.count == 0 and shop.entries.has(entry), "equipment purchase refusal (%s) preserves balances, exact goods and old equipment" % refusal)
	if _controller.cursor_item_drag_source != null:
		_controller.cursor_item_drag_source.consume_drag(_controller.cursor_item_drag_source._active_drag_id)
	equipment.unequip_item_from_slot("weapon")
	_player.stable_id = actor_id
	await get_tree().process_frame


func _test_equipment_metadata_round_trip() -> void:
	_reset_trade("buy")
	var equipment := _player.get_equipment()
	# Registration supplies the production capability-to-GECS bindings.
	_controller.open_inventory_pair(_player, _merchant)
	await get_tree().process_frame
	var slot: EquipmentSlotControl = _controller.primary_character_window._equipment_slots.get("weapon")
	slot._drop_data(Vector2.ZERO, {"entry": _entry(_role.get_shop_inventory(), STACK_ID), "source_owner": _merchant})
	var saved := _gecs.get_item_stack(STACK_ID)
	_check(saved.get("contained_item_counts") == CONTENTS and saved.get("metadata") == METADATA and saved.get("location_kind") == "equipment", "merchant-to-equipment preserves exact durable contents and metadata before actor sync")
	var cell := _player.inventory.find_first_space(CAN)
	_controller.primary_character_window._handle_drop({"equipment_owner": _player, "equip_slot": "weapon", "item_definition": CAN}, cell)
	_check(_exact_stack(_player.inventory, STACK_ID, CAN, 1) and equipment.get_equipped_item("weapon") == null, "ordinary equipment-to-grid restores bought stack with all durable payload")
	await get_tree().process_frame


func _test_nonmerchant_context() -> void:
	_actor_kind = "nonmerchant"
	_clear_inventory(_player.inventory)
	var peer := _make_actor("peer", true)
	_check(_player.inventory.add_entry_with_contents(CAN, 1, CONTENTS, METADATA, STACK_ID), "seed ordinary transfer stack")
	_controller.open_inventory_pair(_player, peer)
	await get_tree().process_frame
	_shift_click(_controller.primary_character_window, _entry(_player.inventory, STACK_ID))
	await get_tree().process_frame
	_check(_exact_stack(peer.inventory, STACK_ID, CAN, 1) and _entry(_player.inventory, STACK_ID) == null, "paired nonmerchant Shift-click transfers forward")
	_shift_click(_controller.secondary_inventory_window, _entry(peer.inventory, STACK_ID), MOUSE_BUTTON_RIGHT)
	await get_tree().process_frame
	_check(_exact_stack(_player.inventory, STACK_ID, CAN, 1) and _entry(peer.inventory, STACK_ID) == null, "paired Shift-right-click transfers back with metadata")
	_check(_player.get_equipment().get_equipped_item("weapon") == null and peer.get_equipment().get_equipped_item("weapon") == null, "paired ordinary transfers never equip either actor")
	_controller.open_inventory_for_member(_player)
	await get_tree().process_frame
	_shift_click(_controller.primary_character_window, _entry(_player.inventory, STACK_ID))
	await get_tree().process_frame
	_check(_player.get_equipment().get_equipped_item("weapon") == CAN and _player.get_equipment().get_equipped_stack_id("weapon") == STACK_ID and _entry(_player.inventory, STACK_ID) == null, "standalone Shift-click still equips the same stack")
	_controller._close_all_inventory_windows()
	peer.queue_free()
	await get_tree().process_frame


func _reset_trade(direction: String) -> void:
	_clear_inventory(_player.inventory)
	_clear_inventory(_merchant.inventory)
	var shop := _role.get_shop_inventory()
	_clear_inventory(shop)
	var price: MerchantPrice = _role.prices[0]
	price.item_definition = CAN
	price.buy_price = 2
	price.sell_price = 3
	_check(_player.inventory.add_item_count(SILVER, 10), "seed buyer silver")
	_check(shop.add_item_count(SILVER, 20), "seed merchant stock silver")
	_check(_merchant.inventory.add_item_count(SILVER, 91), "seed decoy merchant personal silver")
	var source := shop if direction == "buy" else _player.inventory
	_check(source.add_entry_with_contents(CAN, 1, CONTENTS, METADATA, STACK_ID), "seed distinct traded stack")


func _clear_inventory(inventory: InventoryData) -> void:
	inventory.entries.clear()
	inventory.use_weight = false
	inventory.max_weight = 100.0
	inventory.set_admission_validator(Callable())
	inventory.changed.emit()


func _fill_grid(inventory: InventoryData) -> void:
	var cell := inventory.find_first_space(SEEDS)
	while cell != Vector2i(-1, -1):
		_check(inventory.add_entry_with_contents(SEEDS, 1, {}, {"blocker": str(cell)}), "seed blocker")
		cell = inventory.find_first_space(SEEDS)


func _make_actor(id: String, humanoid: bool, merchant_role: MerchantRole = null) -> WorldActor:
	var actor: WorldActor = HumanoidCharacter.new() if humanoid else WorldActor.new()
	actor.name = id
	actor.member_name = id.capitalize()
	actor.stable_id = "validation.merchant." + id
	actor.inventory_columns = 8
	actor.inventory_rows = 6
	actor.max_carry_weight = 100.0
	# Bare actor constructors have no authored main collider. Both kinds need
	# a physical floor contact, including after merchant projection replacement.
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	collision.shape = shape
	collision.position.y = shape.height * 0.5
	actor.add_child(collision)
	actor.position = Vector3(0.0 if id == "buyer" else 2.0, 0.2, 0.0)
	if merchant_role != null:
		actor.add_child(merchant_role)
	add_child(actor)
	return actor


func _test_persistence_lifecycle() -> void:
	# Use production registration and warm-load hydration, not signal lambdas.
	var query := ActorQueryController.new()
	add_child(query)
	_context.register(ActorQueryController.SERVICE_ID, query)
	query.initialize(_context)
	_population = PopulationController.new()
	add_child(_population)
	_context.register(PopulationController.SERVICE_ID, _population)
	_population.initialize(_context)
	_player.get_equipment().unequip_item_from_slot("weapon")
	_clear_inventory(_player.inventory)
	_population.register_actor(_player)
	for humanoid in [false, true]:
		_actor_kind = "persistent HumanoidCharacter" if humanoid else "persistent WorldActor"
		var id := "persistent_humanoid" if humanoid else "persistent_actor"
		_merchant = _make_stocked_merchant(id, humanoid)
		await get_tree().process_frame
		var shop := _role.get_shop_inventory()
		var container_id := _merchant.stable_id + ".shop_inventory"
		_check(shop.count_item(SEEDS) == 3 and shop.count_item(SILVER) == 20, "uninitialized merchant seeds authored stock once")
		_check(_gecs.get_inventory_container_entity(container_id) != null, "shop has a distinct durable container even before trade")
		_clear_inventory(_player.inventory)
		_check(_player.inventory.add_item_count(SILVER, 10), "seed persistent buyer silver")
		_check(_merchant.inventory.add_item_count(SILVER, 91), "seed persistent personal decoy")
		_check(_player.inventory.add_entry_with_contents(CAN, 1, CONTENTS, METADATA, STACK_ID), "seed persistent sale payload")
		_controller.open_inventory_pair(_player, _merchant)
		await get_tree().process_frame
		_shift_click(_controller.primary_character_window, _entry(_player.inventory, STACK_ID))
		_check_durable_stack(STACK_ID, container_id, _merchant.stable_id, "persistent Shift sale")
		_check(_player.inventory.count_item(SILVER) == 12 and shop.count_item(SILVER) == 18, "persistent sale settles both balances")
		var sold_snapshot := _canonical_inventory_snapshot(shop)
		var sequence := shop.next_stack_sequence
		var path := "user://merchant_persistence_%s.tres" % id
		_check(_gecs.save_gecs_world(path), "write actual sold-stock save")
		_shift_click(_controller.secondary_inventory_window, _entry(shop, STACK_ID))
		_check_durable_stack(STACK_ID, _player.stable_id + ".inventory", _player.stable_id, "purchase sold stack back")
		_check(_player.inventory.count_item(SILVER) == 9 and shop.count_item(SILVER) == 21, "buyback settles both balances")
		_check(_gecs.load_gecs_world(path), "warm disk load succeeds")
		await get_tree().process_frame
		await get_tree().process_frame
		_check(_role.get_shop_inventory() == shop and _canonical_inventory_snapshot(shop) == sold_snapshot and shop.next_stack_sequence == sequence, "warm load restores exact stock, grid, allocator and existing UI inventory reference")
		_check(_entry(_player.inventory, STACK_ID) == null and _player.inventory.count_item(SILVER) == 12 and shop.count_item(SILVER) == 18 and _merchant.inventory.count_item(SILVER) == 91, "warm load rolls back both balances without merging the merchant personal bag")
		_check_durable_stack(STACK_ID, container_id, _merchant.stable_id, "warm-loaded sale")
		_check_durable_inventories("warm-loaded sale")
		# Re-open through normal binding after load, then prove refusal is durable too.
		_controller.open_inventory_pair(_player, _merchant)
		await get_tree().process_frame
		_player.inventory.set_admission_validator(func(definition, _count): return definition != CAN)
		var before_refusal := _gecs.get_inventory_stacks()
		_shift_click(_controller.secondary_inventory_window, _entry(shop, STACK_ID))
		_check(_gecs.get_inventory_stacks() == before_refusal and _canonical_inventory_snapshot(shop) == sold_snapshot and _player.inventory.count_item(SILVER) == 12, "post-load refused purchase preserves exact durable goods and both balances")
		_player.inventory.set_admission_validator(Callable())
		_shift_click(_controller.secondary_inventory_window, _entry(shop, STACK_ID))
		var entry = _entry(_player.inventory, STACK_ID)
		_check(entry != null, "post-load buyback uses restored shop")
		if entry != null:
			_check(_player.inventory.remove_entry(entry), "lift exact post-load cursor goods")
			_controller._start_cursor_item_drag(_player, entry.definition, entry.count, entry.contained_item_counts, entry.metadata, entry.stack_id)
			var cursor: CursorItemDragSource = _controller.cursor_item_drag_source
			_controller.secondary_inventory_window._handle_drop(cursor._make_drag_data(), shop.find_first_space(CAN))
			_check(not cursor._has_item and _player.inventory.count_item(SILVER) == 11 and shop.count_item(SILVER) == 19, "post-load cursor sale settles both balances and cursor")
		_check_durable_stack(STACK_ID, container_id, _merchant.stable_id, "post-load cursor sale")
		_check_durable_inventories("post-load cursor sale")
		_check(shop.remove_item_count(SEEDS, 3), "take all authored seed stock")
		var replacement_snapshot := _canonical_inventory_snapshot(shop)
		sequence = shop.next_stack_sequence
		_check(_gecs.save_gecs_world(path), "save cursor sale with starting goods taken")
		_controller._close_all_inventory_windows()
		var old_actor: WeakRef = weakref(_merchant)
		var old_role: WeakRef = weakref(_role)
		_population.unregister_actor(_merchant)
		_merchant.queue_free()
		await get_tree().process_frame
		_check(old_actor.get_ref() == null and old_role.get_ref() == null, "ordinary actor and attached merchant projection are actually destroyed")
		_check_durable_stack(STACK_ID, container_id, "validation.merchant." + id, "unprojected sold stock")
		_check(_gecs.load_gecs_world(path), "load stock while merchant projection is absent")
		await get_tree().process_frame
		_check_durable_stack(STACK_ID, container_id, "validation.merchant." + id, "unprojected disk-loaded stock")
		_merchant = _make_stocked_merchant(id, humanoid)
		await get_tree().process_frame
		shop = _role.get_shop_inventory()
		_check(_canonical_inventory_snapshot(shop) == replacement_snapshot and shop.next_stack_sequence == sequence and shop.count_item(SEEDS) == 0, "same-identity replacement hydrates sold stock and never reseeds taken starting goods")
		_check_durable_stack(STACK_ID, container_id, _merchant.stable_id, "replacement sold stock")
		_clear_inventory(shop)
		_check(_gecs.get_inventory_stacks(container_id).is_empty() and _gecs.get_inventory_container_entity(container_id) != null, "empty shop remains an initialized durable container")
		_check(_gecs.save_gecs_world(path), "save initialized empty stock")
		_check(shop.add_item_count(SILVER, 1), "mutate live empty-shop save")
		_check(_gecs.load_gecs_world(path), "load initialized empty stock")
		await get_tree().process_frame
		await get_tree().process_frame
		_check(shop.entries.is_empty(), "warm load restores empty shop instead of reseeding")
		_population.unregister_actor(_merchant)
		_merchant.queue_free()
		await get_tree().process_frame
		_merchant = _make_stocked_merchant(id, humanoid)
		await get_tree().process_frame
		_check(_role.get_shop_inventory().entries.is_empty(), "replacement preserves initialized empty shop despite nonempty authored stock")
		_population.unregister_actor(_merchant)
		_merchant.queue_free()
		await get_tree().process_frame
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _make_stocked_merchant(id: String, humanoid: bool) -> WorldActor:
	_role = MerchantRole.new()
	_role.name = "MerchantRole"
	for fixture in [[SILVER, 20], [SEEDS, 3]]:
		var stock := MerchantStock.new()
		stock.item_definition = fixture[0]
		stock.quantity = fixture[1]
		_role.initial_stock.append(stock)
	var price := MerchantPrice.new()
	price.item_definition = CAN
	price.buy_price = 2
	price.sell_price = 3
	_role.prices = [price]
	var actor := _make_actor(id, humanoid, _role)
	_population.register_actor(actor)
	return actor


func _entry(inventory: InventoryData, stack_id: String):
	for entry in inventory.entries:
		if entry.stack_id == stack_id:
			return entry
	return null


func _exact_stack(inventory: InventoryData, stack_id: String, definition: ItemDefinition, count: int) -> bool:
	var entry = _entry(inventory, stack_id)
	return entry != null and entry.definition == definition and entry.count == count \
		and entry.contained_item_counts == CONTENTS and entry.metadata == METADATA


func _inventory_snapshot(inventory: InventoryData) -> Array:
	var result: Array = []
	for entry in inventory.entries:
		result.append([entry.stack_id, entry.definition, entry.grid_position, entry.count, entry.contained_item_counts.duplicate(true), entry.metadata.duplicate(true)])
	return result


func _canonical_inventory_snapshot(inventory: InventoryData) -> Array:
	# GECS query iteration order is not inventory order; grid positions and all
	# payload fields remain exact. Refusal tests still compare live entry order.
	var result := _inventory_snapshot(inventory)
	result.sort_custom(func(a: Array, b: Array): return str(a[0]) < str(b[0]))
	return result


func _check_durable_inventories(label: String) -> void:
	for fixture in [[_player.inventory, _player.stable_id + ".inventory"], [_merchant.inventory, _merchant.stable_id + ".inventory"], [_role.get_shop_inventory(), _merchant.stable_id + ".shop_inventory"]]:
		var saved: Array = []
		for record in _gecs.get_inventory_stacks(fixture[1]):
			saved.append([record.stack_id, load(record.item_definition_path), record.grid_position, record.count, record.contained_item_counts, record.metadata])
		saved.sort_custom(func(a: Array, b: Array): return str(a[0]) < str(b[0]))
		_check(saved == _canonical_inventory_snapshot(fixture[0]), "%s: %s durable goods and contained silver match the complete live inventory" % [label, fixture[1]])


func _shift_click(window: InventoryWindow, entry, button := MOUSE_BUTTON_LEFT) -> void:
	if window == null or entry == null:
		_check(false, "Shift-click requires live window and exact source entry")
		return
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.shift_pressed = true
	event.position = window.inventory_grid._item_rect(entry).get_center()
	window.inventory_grid._gui_input(event)


func _check_durable_stack(stack_id: String, container_id: String, actor_id: String, label: String) -> void:
	var records: Array[Dictionary] = []
	for record in _gecs.get_inventory_stacks():
		if record.get("stack_id") == stack_id:
			records.append(record)
	_check(records.size() == 1, "%s: exact stack has ONE durable location (actual=%s)" % [label, records])
	if records.size() == 1:
		var record := records[0]
		_check(record.get("container_id") == container_id and record.get("owner_actor_id") == actor_id and record.get("location_kind") == "inventory" and record.get("item_definition_path") == CAN.resource_path and record.get("count") == 1 and record.get("contained_item_counts") == CONTENTS and record.get("metadata") == METADATA, "%s: durable destination retains exact payload" % label)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append("%s: %s" % [_actor_kind, label])
