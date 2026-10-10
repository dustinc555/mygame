extends GutTest

const BAG = preload("res://features/inventory/resources/items/medium_leather_bag.tres")
const FOOD = preload("res://features/inventory/resources/items/food.tres")
const ITEM_STORAGE_VIEW = preload("res://features/inventory/bridge/item_storage_view.gd")
var actor: HumanoidCharacter
var bridge: GecsWorldController
var controller: PartyInventoryController
var transfer_partner: HumanoidCharacter

func before_each() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var context := BootstrapContext.new(root)
	bridge = GecsWorldController.new()
	root.add_child(bridge)
	context.register(GecsWorldController.SERVICE_ID, bridge)
	bridge.initialize(context)
	actor = HumanoidCharacter.new()
	actor.appearance_data = CharacterAppearanceData.new()
	actor.appearance_data.character_race = load("res://features/actors/resources/character_races/human.tres")
	actor.appearance_data.body_archetype = load("res://features/actors/resources/character_body_archetypes/human_male.tres")
	actor.stable_id = "test.storage.actor"
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(actor)
	bridge.register_actor(actor)
	controller = PartyInventoryController.new()
	root.add_child(controller)
	controller.set_process(false)
	controller._context = context
	controller.root_scene = root
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1500, 1000)
	root.add_child(viewport)
	var layer := Control.new()
	viewport.add_child(layer)
	layer.size = Vector2(1500, 1000)
	controller.inventory_window_layer = layer
	assert_true(actor.inventory.add_entry_with_contents(BAG, 1, {}, {}, "test.bag"))
	assert_true(actor.inventory.add_entry_with_contents(FOOD, 1, {}, {"quality": 0.7}, "test.food"))
	controller.open_inventory_for_member(actor)

func after_each() -> void:
	controller._close_all_inventory_windows()
	if is_instance_valid(transfer_partner):
		bridge.unregister_actor(transfer_partner)
	bridge.unregister_actor(actor)

func test_backpack_eat_menu_consumes_clicked_stack_not_personal_food() -> void:
	actor.hunger_enabled = true
	var window = controller.open_item_storage(actor, "test.bag")
	var storage: InventoryData = window.inventory_owner.inventory
	assert_true(storage.add_entry_with_contents(FOOD, 1, {}, {"batch": "first"}, "bag.first"))
	assert_true(storage.add_entry_with_contents(FOOD, 1, {}, {"batch": "clicked"}, "bag.clicked"))
	var first = storage.entries[0]
	var clicked = storage.entries[1]
	window._on_inventory_item_right_clicked(clicked, Vector2.ZERO, false)
	assert_ne(window.item_menu.get_item_index(InventoryWindow.ACTION_EAT), -1, "The shared menu must offer Eat in a backpack")
	# Exercise the production action signal even on the failing menu baseline.
	window._context_entry = clicked
	window._on_item_menu_id_pressed(InventoryWindow.ACTION_EAT)
	assert_true(actor.is_food_effect_active())
	assert_eq(actor.inventory.count_item(FOOD), 1, "Never debit a matching item in another inventory")
	assert_eq(storage.count_item(FOOD), 1)
	assert_true(storage.entries.has(first))
	assert_false(storage.entries.has(clicked))
	assert_eq(bridge.get_item_stack("test.bag").metadata.item_storage.entries.size(), 1)
	window._on_inventory_item_right_clicked(first, Vector2.ZERO, false)
	var eat_index: int = window.item_menu.get_item_index(InventoryWindow.ACTION_EAT)
	if eat_index >= 0:
		assert_true(window.item_menu.is_item_disabled(eat_index), "Digestion rules apply equally to a bag")
	window._context_entry = first
	window._on_item_menu_id_pressed(InventoryWindow.ACTION_EAT)
	assert_eq(storage.count_item(FOOD), 1, "Stale/direct actions cannot bypass digestion")


func test_shared_food_from_closed_equipped_bag_feeds_nearby_party_only() -> void:
	var sharing_script: Script
	for component in preload("res://features/inventory/inventory_module.gd").BRIDGE:
		if component.service == &"food_sharing":
			sharing_script = component.script
	assert_not_null(sharing_script, "Food sharing must be installed in production, not just the HUD")
	if sharing_script == null:
		return
	var party := PartyManager.new()
	party.name = "PartyManager"
	controller.root_scene.add_child(party)
	transfer_partner = HumanoidCharacter.new()
	transfer_partner.stable_id = "test.food.recipient"
	transfer_partner.hunger_enabled = true
	transfer_partner.process_mode = Node.PROCESS_MODE_DISABLED
	controller.root_scene.add_child(transfer_partner)
	bridge.register_actor(transfer_partner)
	party.set_party_members([actor, transfer_partner])
	actor.squad_name = "Provisions"
	transfer_partner.squad_name = "Builders"
	transfer_partner.position = Vector3(4, 0, 0)
	transfer_partner.get_needs().hunger_stage = NpcRules.HungerStage.HUNGRY
	var window = controller.open_item_storage(actor, "test.bag")
	assert_true(window.inventory_owner.inventory.add_entry_with_contents(FOOD, 1, {}, {"shared": true}, "shared.food"))
	controller._close_inventory_window(window)
	controller._on_inventory_equip_requested(actor, actor.inventory.entries[0], actor, "backpack")
	var sharing = sharing_script.new()
	controller.root_scene.add_child(sharing)
	sharing.initialize(controller._context)
	sharing.check_pending_meals()
	assert_false(transfer_partner.is_food_effect_active(), "Sharing defaults off")
	actor.call("set_share_food_enabled", true)
	sharing.check_pending_meals()
	assert_true(transfer_partner.is_food_effect_active())
	assert_eq(actor.inventory.count_item(FOOD), 1, "Donor's personal food is private")
	assert_false(InventoryData.has_stored_items(bridge.get_item_stack("test.bag").metadata))
	for open_window in controller.open_inventory_windows.values():
		assert_false(open_window.inventory_owner is ITEM_STORAGE_VIEW, "Automatic sharing does not open UI")
	sharing.free()


func test_open_bag_transfer_reopen_and_equip_keep_exact_contents() -> void:
	assert_true(controller.has_method("open_item_storage"), "Open Bag must expose a separate inventory window")
	if not controller.has_method("open_item_storage"):
		return
	var window = controller.call("open_item_storage", actor, "test.bag")
	assert_not_null(window)
	if window == null:
		return
	var view = window.inventory_owner
	var bag_inventory: InventoryData = view.get_inventory_for_display()
	assert_ne(bag_inventory, actor.inventory)
	var food = actor.inventory.entries[1]
	controller._on_inventory_transfer_requested(actor, view, food, Vector2i.ZERO)
	assert_eq(actor.inventory.count_item(FOOD), 0)
	assert_eq(bag_inventory.count_item(FOOD), 1)
	assert_eq(bag_inventory.entries[0].stack_id, "test.food")
	assert_eq(bridge.get_item_stack("test.bag").metadata.item_storage.entries[0].stack_id, "test.food")
	controller._close_inventory_window(window)
	var bag = actor.inventory.entries[0]
	controller._on_inventory_equip_requested(actor, bag, actor, "backpack")
	assert_eq(actor.get_equipped_item("backpack"), BAG)
	window = controller.call("open_item_storage", actor, "test.bag")
	assert_not_null(window)
	if window == null:
		return
	bag_inventory = window.inventory_owner.get_inventory_for_display()
	assert_eq(bag_inventory.entries[0].metadata, {"quality": 0.7})
	controller._on_inventory_transfer_requested(window.inventory_owner, actor, bag_inventory.entries[0], Vector2i.ZERO)
	assert_eq(actor.inventory.count_item(FOOD), 1)
	assert_eq(bag_inventory.entries.size(), 0)
	assert_false(InventoryData.has_stored_items(bridge.get_item_stack("test.bag").metadata))


func test_equipped_bag_uses_shared_carry_weight_even_when_closed() -> void:
	var window = controller.open_item_storage(actor, "test.bag")
	var view = window.inventory_owner
	actor.inventory.max_weight = BAG.unit_weight + FOOD.unit_weight
	assert_eq(window._get_drop_error({"source_owner": actor, "entry": actor.inventory.entries[1]}, Vector2i.ZERO), "", "Drag preview must allow moving already-carried weight")
	controller._on_inventory_transfer_requested(actor, view, actor.inventory.entries[1], Vector2i.ZERO)
	assert_eq(view.inventory.count_item(FOOD), 1, "Moving owned weight into the bag must work at the limit")
	controller._close_inventory_window(window)
	controller._on_inventory_equip_requested(actor, actor.inventory.entries[0], actor, "backpack")
	assert_almost_eq(actor.inventory.get_total_weight(), BAG.unit_weight + FOOD.unit_weight, 0.0001)
	assert_false(actor.inventory.add_item(FOOD), "Equipping/closing the bag cannot hide carried weight")
	window = controller.open_item_storage(actor, "test.bag")
	view = window.inventory_owner
	assert_false(view.inventory.add_item(FOOD), "The bag cannot create a second weight allowance")
	assert_eq(controller.primary_character_window._get_drop_error({"source_owner": view, "entry": view.inventory.entries[0]}, Vector2i.ZERO), "")
	controller._on_inventory_transfer_requested(view, actor, view.inventory.entries[0], Vector2i.ZERO)
	assert_eq(actor.inventory.count_item(FOOD), 1, "Moving weight out also works at the limit")
	assert_eq(view.inventory.count_item(FOOD), 0)
	controller._on_inventory_unequip_requested(actor, "backpack", actor, Vector2i(3, 0))
	assert_null(actor.get_equipped_item("backpack"), "Unequipping a bag does not add carried weight")
	assert_eq(actor.inventory.count_item(BAG), 1)


func test_reopen_after_equipping_and_handover_invalidates_old_views() -> void:
	var window = controller.open_item_storage(actor, "test.bag")
	var stale: InventoryData = window.inventory_owner.inventory
	controller._on_inventory_transfer_requested(actor, window.inventory_owner, actor.inventory.entries[1], Vector2i.ZERO)
	controller._on_inventory_equip_requested(actor, actor.inventory.entries[0], actor, "backpack")
	var reopened = controller.open_item_storage(actor, "test.bag")
	assert_not_same(reopened.inventory_owner.inventory, stale)
	assert_false(stale.add_item(FOOD))
	assert_false(stale.remove_entry(stale.entries[0]))
	assert_eq(reopened.inventory_owner.inventory.count_item(FOOD), 1)
	controller._on_inventory_unequip_requested(actor, "backpack", actor, Vector2i.ZERO)
	var receiver := HumanoidCharacter.new()
	receiver.process_mode = Node.PROCESS_MODE_DISABLED
	controller.root_scene.add_child(receiver)
	var bag = actor.inventory.entries[0]
	controller._on_inventory_transfer_requested(actor, receiver, bag, Vector2i.ZERO)
	assert_eq(receiver.inventory.count_item(BAG), 1)
	reopened = controller.open_item_storage(receiver, "test.bag")
	assert_eq(reopened.inventory_owner.inventory.entries[0].stack_id, "test.food")
	assert_eq(reopened.inventory_owner.inventory.entries[0].metadata, {"quality": 0.7})
	var retained: InventoryData = reopened.inventory_owner.inventory
	receiver.free()
	assert_false(retained.add_item(FOOD))
	controller._enforce_open_inventory_context()
	assert_false(retained.is_accessible())


func test_bag_window_participates_in_merchant_trade_without_merging_inventories() -> void:
	var merchant := HumanoidCharacter.new()
	merchant.process_mode = Node.PROCESS_MODE_DISABLED
	controller.root_scene.add_child(merchant)
	var role := MerchantRole.new()
	role.name = "MerchantRole"
	role.trading_policy = {"buys_any": true, "sell_price": 2, "buy_price": 1}
	merchant.add_child(role)
	assert_true(actor.inventory.add_item_count(InventoryData.SILVER_ITEM, 20))
	var stock := role.get_shop_inventory()
	assert_true(stock.add_entry_with_contents(FOOD, 1, {}, {}, "merchant-food"))
	assert_true(stock.add_item_count(InventoryData.SILVER_ITEM, 20))
	controller.open_inventory_pair(actor, merchant)
	var window = controller.open_item_storage(actor, "test.bag")
	assert_not_null(window)
	if window == null:
		return
	var view = window.inventory_owner
	var storage: InventoryData = view.get_inventory_for_display()
	assert_same(window.trade_session, controller.trade_session)
	controller._on_inventory_transfer_requested(merchant, view, stock.entries[0], Vector2i.ZERO)
	assert_eq(storage.count_item(FOOD), 0)
	controller._confirm_trade()
	assert_eq(storage.count_item(FOOD), 1)
	assert_eq(actor.inventory.count_item(FOOD), 1, "Personal goods remain separate")
	assert_eq(actor.inventory.count_item(InventoryData.SILVER_ITEM), 18)
	if storage.entries.is_empty():
		return
	controller._offer_trade_item(view, storage.entries[0], -1)
	controller._confirm_trade()
	assert_eq(storage.count_item(FOOD), 0)
	assert_eq(actor.inventory.count_item(InventoryData.SILVER_ITEM), 19)
	assert_false(InventoryData.has_stored_items(bridge.get_item_stack("test.bag").metadata))


func test_bag_cannot_bypass_job_lock_or_accept_nested_bags() -> void:
	controller._on_inventory_equip_requested(actor, actor.inventory.entries[0], actor, "backpack")
	var window = controller.open_item_storage(actor, "test.bag")
	var view = window.inventory_owner
	assert_false(view.inventory.add_item(BAG))
	actor.get_inventory().set_work_inventory(InventoryData.new())
	assert_false(controller._can_transfer_between_owners(view, actor))
	assert_false(view.can_transfer_display_inventory_to(actor))
	assert_false(view.can_receive_inventory_transfer_from(actor))
	actor.get_inventory().set_work_inventory(null)
	assert_true(controller._can_transfer_between_owners(view, actor))


func test_save_load_restores_contents_and_refuses_old_window_writes() -> void:
	var population := PopulationController.new()
	controller.root_scene.add_child(population)
	controller._context.register(PopulationController.SERVICE_ID, population)
	population.initialize(controller._context)
	population.register_actor(actor)
	var simulation := WorldSimulationController.new()
	controller.root_scene.add_child(simulation)
	simulation.initialize(controller._context)
	controller._on_inventory_equip_requested(actor, actor.inventory.entries[0], actor, "backpack")
	var window = controller.open_item_storage(actor, "test.bag")
	controller._on_inventory_transfer_requested(actor, window.inventory_owner, actor.inventory.entries[0], Vector2i.ZERO)
	assert_true(simulation.save_world_to_file("user://backpack-roundtrip.tres"))
	var stale: InventoryData = window.inventory_owner.inventory
	assert_true(stale.add_item(FOOD))
	assert_true(simulation.load_world_from_file("user://backpack-roundtrip.tres"))
	assert_false(stale.add_item(FOOD), "Load invalidates old windows before deferred actor hydration")
	await get_tree().process_frame
	window = controller.open_item_storage(actor, "test.bag")
	assert_eq(window.inventory_owner.inventory.count_item(FOOD), 1)
	assert_eq(window.inventory_owner.inventory.entries[0].stack_id, "test.food")
	assert_eq(window.inventory_owner.inventory.entries[0].metadata, {"quality": 0.7})
	assert_almost_eq(actor.inventory.get_total_weight(), BAG.unit_weight + FOOD.unit_weight, 0.0001)


func _merchant() -> HumanoidCharacter:
	var merchant := HumanoidCharacter.new()
	merchant.process_mode = Node.PROCESS_MODE_DISABLED
	controller.root_scene.add_child(merchant)
	var role := MerchantRole.new()
	role.name = "MerchantRole"
	role.trading_policy = {"buys_any": true, "sell_price": 2, "buy_price": 1}
	merchant.add_child(role)
	assert_true(actor.inventory.add_item_count(InventoryData.SILVER_ITEM, 20))
	assert_true(role.get_shop_inventory().add_entry_with_contents(FOOD, 1, {}, {"quality": 0.4}, "stock.food"))
	controller.open_inventory_pair(actor, merchant)
	return merchant


func test_trade_cannot_sell_bag_while_buying_into_it() -> void:
	var merchant := _merchant()
	var stock: InventoryData = merchant.get_node("MerchantRole").get_shop_inventory()
	var window = controller.open_item_storage(actor, "test.bag")
	var session = controller.trade_session
	assert_eq(session.propose(1, stock.entries[0], window.trade_side, Vector2i.ZERO), "")
	assert_ne(session.propose(0, actor.inventory.entries[0], 1, Vector2i(3, 0)), "", "A pending destination cannot itself be sold")
	session.reset()
	assert_eq(session.propose(0, actor.inventory.entries[0], 1, Vector2i(3, 0)), "")
	assert_ne(session.propose(1, stock.entries[0], window.trade_side, Vector2i.ZERO), "", "An offered bag cannot receive purchases")


func test_failed_trade_restores_bag_personal_stock_and_purses() -> void:
	var merchant := _merchant()
	var stock: InventoryData = merchant.get_node("MerchantRole").get_shop_inventory()
	var window = controller.open_item_storage(actor, "test.bag")
	var session = controller.trade_session
	var before: Dictionary = bridge.get_item_stack("test.bag").duplicate(true)
	var original = stock.entries[0]
	assert_eq(session.propose(1, original, window.trade_side, Vector2i.ZERO), "")
	actor.inventory.max_weight = actor.inventory.get_total_weight()
	assert_ne(session.commit(), "", "Payment frees less weight than these goods require")
	assert_same(stock.entries[0], original)
	assert_eq(original.metadata, {"quality": 0.4})
	assert_eq(window.inventory_owner.inventory.entries.size(), 0)
	assert_eq(actor.inventory.count_item(FOOD), 1)
	assert_eq(actor.inventory.count_item(InventoryData.SILVER_ITEM), 20)
	assert_eq(stock.count_item(InventoryData.SILVER_ITEM), 0)
	assert_eq(bridge.get_item_stack("test.bag"), before)
	assert_true(session.is_current())


func test_equipping_from_bag_during_trade_preserves_exact_item_and_pending_deal() -> void:
	var dagger: ItemDefinition = load("res://features/inventory/resources/items/iron_dagger.tres")
	var window = controller.open_item_storage(actor, "test.bag")
	assert_true(window.inventory_owner.inventory.add_entry_with_contents(dagger, 1, {}, {"quality": 0.37}, "bag.dagger"))
	_merchant()
	window = controller.open_item_storage(actor, "test.bag")
	var view = window.inventory_owner
	var session = controller.trade_session
	assert_eq(session.propose(1, session.inventories[1].entries[0], window.trade_side, Vector2i(2, 0)), "")
	controller._on_inventory_equip_requested(view, view.inventory.entries[0], actor, "weapon")
	assert_eq(actor.get_equipped_item("weapon"), dagger)
	assert_eq(view.inventory.count_item(dagger), 0)
	assert_eq(bridge.get_item_stack("bag.dagger").get("metadata"), {"quality": 0.37})
	assert_true(session.is_current())
	assert_eq(session.offers.size(), 1)
	session.reset()
	assert_eq(actor.get_equipped_item("weapon"), dagger)
	controller._on_inventory_unequip_requested(actor, "weapon", view, Vector2i.ZERO)
	assert_null(actor.get_equipped_item("weapon"))
	assert_eq(view.inventory.entries[0].stack_id, "bag.dagger")
	assert_eq(view.inventory.entries[0].metadata, {"quality": 0.37})
	assert_true(session.is_current())


func _prepare_clothing_swap(old_clothes: ItemDefinition = preload("res://features/inventory/resources/items/ranger_jerkin.tres")) -> InventoryWindow:
	var new_clothes: ItemDefinition = load("res://features/inventory/resources/items/traveler_leather_jacket.tres")
	controller._on_inventory_equip_requested(actor, actor.inventory.entries[0], actor, "backpack")
	assert_true(actor.inventory.add_entry_with_contents(old_clothes, 1, {}, {"quality": 0.37}, "old.clothes"))
	controller._on_inventory_equip_requested(actor, actor.inventory.entries[-1], actor, "chest")
	var window = controller.open_item_storage(actor, "test.bag")
	assert_true(window.inventory_owner.inventory.add_entry_with_contents(new_clothes, 1, {}, {"quality": 0.63}, "new.clothes"))
	assert_true(window.inventory_owner.inventory.move_entry(window.inventory_owner.inventory.entries[0], Vector2i(6, 4)))
	assert_eq(actor.get_equipment().get_equipped_stack_id("chest"), "old.clothes")
	assert_eq(bridge.get_item_stack("old.clothes").get("metadata"), {"quality": 0.37})
	return window


func _drag_clothes_to_chest(window: InventoryWindow) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var grid: InventoryGridControl = window.inventory_grid
	var incoming = grid.inventory_data.entries[0]
	assert_eq(incoming.stack_id, "new.clothes")
	var from: Vector2 = grid.global_position + grid._item_rect(incoming).get_center()
	var slot: Control = controller.primary_character_window._equipment_slots["chest"]
	var to := slot.get_global_rect().get_center()
	_click(from, true)
	_pointer(from + Vector2(15, 0), true)
	await get_tree().process_frame
	assert_true(grid.get_viewport().gui_is_dragging())
	_pointer(to, true)
	await get_tree().process_frame
	_click(to, false)
	await get_tree().process_frame


func test_clothing_swap_from_bag_during_trade_returns_old_clothes_to_source_cell() -> void:
	_prepare_clothing_swap()
	_merchant()
	var window = controller.open_item_storage(actor, "test.bag")
	var old_clothes: ItemDefinition = actor.get_equipped_item("chest")
	var new_clothes: ItemDefinition = window.inventory_owner.inventory.entries[0].definition
	var session = controller.trade_session
	assert_eq(session.propose(1, session.inventories[1].entries[0], window.trade_side, Vector2i.ZERO), "")
	controller._refresh_trade()
	await _drag_clothes_to_chest(window)
	assert_eq(actor.get_equipment().get_equipped_stack_id("chest"), "new.clothes")
	assert_eq(actor.inventory.count_item(old_clothes), 0, "Swapping from a backpack must not send replaced clothes to pockets")
	var storage: InventoryData = window.inventory_owner.inventory
	assert_eq(storage.count_item(old_clothes), 1)
	assert_eq(storage.count_item(new_clothes), 0)
	if storage.entries.is_empty():
		return
	assert_eq(storage.entries[0].stack_id, "old.clothes")
	assert_eq(storage.entries[0].grid_position, Vector2i(6, 4), "Use the incoming clothes' vacated cells first")
	assert_eq(storage.entries[0].metadata, {"quality": 0.37})
	assert_eq(bridge.get_item_stack("new.clothes").get("metadata"), {"quality": 0.63})
	assert_eq(bridge.get_item_stack("test.bag").metadata.item_storage.entries[0].stack_id, "old.clothes")
	assert_true(session.is_current())
	assert_eq(session.offers.size(), 1)
	session.reset()
	assert_eq(storage.count_item(old_clothes), 1, "Reset cancels purchases, not an owned clothing swap")
	assert_eq(actor.get_equipment().get_equipped_stack_id("chest"), "new.clothes")


func test_clothing_swap_from_bag_without_trade_returns_exact_clothes_to_source_cell() -> void:
	var window := _prepare_clothing_swap()
	var old_clothes: ItemDefinition = actor.get_equipped_item("chest")
	var new_clothes: ItemDefinition = window.inventory_owner.inventory.entries[0].definition
	await _drag_clothes_to_chest(window)
	var storage: InventoryData = window.inventory_owner.inventory
	assert_eq(actor.get_equipment().get_equipped_stack_id("chest"), "new.clothes")
	assert_eq(actor.inventory.count_item(old_clothes), 0)
	assert_eq(storage.count_item(old_clothes), 1)
	assert_eq(storage.count_item(new_clothes), 0)
	if storage.entries.is_empty():
		return
	assert_eq(storage.entries[0].grid_position, Vector2i(6, 4))
	assert_eq(storage.entries[0].stack_id, "old.clothes")
	assert_eq(storage.entries[0].metadata, {"quality": 0.37})
	assert_eq(bridge.get_item_stack("new.clothes").get("metadata"), {"quality": 0.63})
	assert_eq(bridge.get_item_stack("test.bag").metadata.item_storage.entries[0].metadata, {"quality": 0.37})


func test_clothing_swap_refused_by_source_bag_leaves_both_items_unchanged() -> void:
	var window := _prepare_clothing_swap()
	var storage: InventoryData = window.inventory_owner.inventory
	var incoming = storage.entries[0]
	var before_bag: Dictionary = bridge.get_item_stack("test.bag").duplicate(true)
	var before_old: Dictionary = bridge.get_item_stack("old.clothes").duplicate(true)
	var before_pockets := actor.inventory.serialize_contents()
	storage.set_admission_validator(func(_definition, _count): return false)
	var notice := _show_notices()
	controller._on_inventory_equip_requested(window.inventory_owner, incoming, actor, "chest")
	assert_eq(actor.get_equipment().get_equipped_stack_id("chest"), "old.clothes")
	assert_eq(storage.entries.size(), 1)
	assert_true(storage.entries.has(incoming))
	assert_eq(incoming.metadata, {"quality": 0.63})
	assert_eq(actor.inventory.serialize_contents(), before_pockets, "Refusal must not silently spill clothing into personal inventory")
	assert_eq(bridge.get_item_stack("test.bag"), before_bag)
	assert_eq(bridge.get_item_stack("old.clothes"), before_old)
	assert_false(notice.label.text.is_empty())


func test_clothing_swap_during_trade_respects_shared_carrier_weight() -> void:
	_prepare_clothing_swap(load("res://features/inventory/resources/items/knight_cuirass.tres"))
	_merchant()
	var window = controller.open_item_storage(actor, "test.bag")
	var storage: InventoryData = window.inventory_owner.inventory
	actor.inventory.max_weight = actor.inventory.get_total_weight()
	var before := storage.serialize_contents()
	var pockets_before := actor.inventory.serialize_contents()
	var notice := _show_notices()
	controller._on_inventory_equip_requested(window.inventory_owner, storage.entries[0], actor, "chest")
	assert_eq(notice.label.text, "Too heavy")
	assert_eq(actor.get_equipment().get_equipped_stack_id("chest"), "old.clothes")
	assert_eq(storage.serialize_contents(), before)
	assert_eq(actor.inventory.serialize_contents(), pockets_before)
	assert_true(controller.trade_session.is_current())


func test_clothing_swap_personal_inventory_uses_its_vacated_cells() -> void:
	var window := _prepare_clothing_swap()
	var storage: InventoryData = window.inventory_owner.inventory
	controller._on_inventory_transfer_requested(window.inventory_owner, actor, storage.entries[0], Vector2i(6, 0))
	var incoming = actor.inventory.entries[-1]
	controller._on_inventory_equip_requested(actor, incoming, actor, "chest")
	assert_eq(actor.get_equipment().get_equipped_stack_id("chest"), "new.clothes")
	assert_eq(actor.inventory.entries[-1].stack_id, "old.clothes")
	assert_eq(actor.inventory.entries[-1].grid_position, Vector2i(6, 0))
	assert_eq(actor.inventory.entries[-1].metadata, {"quality": 0.37})
	assert_eq(storage.entries.size(), 0)


func test_clothing_swap_from_another_character_preserves_both_exact_items() -> void:
	var window := _prepare_clothing_swap()
	var donor := HumanoidCharacter.new()
	donor.stable_id = "test.clothing.donor"
	donor.process_mode = Node.PROCESS_MODE_DISABLED
	controller.root_scene.add_child(donor)
	bridge.register_actor(donor)
	controller._on_inventory_transfer_requested(window.inventory_owner, donor, window.inventory_owner.inventory.entries[0], Vector2i(5, 0))
	assert_eq(donor.inventory.entries.size(), 1)
	if donor.inventory.entries.is_empty():
		bridge.unregister_actor(donor)
		return
	controller._on_inventory_equip_requested(donor, donor.inventory.entries[0], actor, "chest")
	assert_eq(actor.get_equipment().get_equipped_stack_id("chest"), "new.clothes")
	assert_eq(donor.inventory.entries[0].stack_id, "old.clothes")
	assert_eq(donor.inventory.entries[0].grid_position, Vector2i(5, 0))
	assert_eq(donor.inventory.entries[0].metadata, {"quality": 0.37})
	assert_eq(bridge.get_item_stack("new.clothes").get("metadata"), {"quality": 0.63})
	assert_eq(bridge.get_item_stack("new.clothes").get("owner_actor_id"), actor.stable_id)
	assert_eq(bridge.get_item_stack("old.clothes").get("owner_actor_id"), donor.stable_id)
	bridge.unregister_actor(donor)


func _fill_empty_cells(inventory: InventoryData) -> void:
	var seeds: ItemDefinition = load("res://features/inventory/resources/items/tomato_seeds.tres")
	assert_eq(seeds.grid_size, Vector2i.ONE)
	for y in range(inventory.rows):
		for x in range(inventory.columns):
			var cell := Vector2i(x, y)
			if inventory.can_place_item(seeds, cell):
				inventory.entries.append(inventory.create_entry(seeds, cell))
	inventory.changed.emit()


func test_clothing_swap_succeeds_with_full_bag_and_full_personal_inventory() -> void:
	var window := _prepare_clothing_swap()
	_fill_empty_cells(window.inventory_owner.inventory)
	_fill_empty_cells(actor.inventory)
	actor.inventory.max_weight = actor.inventory.get_total_weight()
	var before := actor.inventory.serialize_contents()
	await _drag_clothes_to_chest(window)
	assert_eq(actor.get_equipment().get_equipped_stack_id("chest"), "new.clothes")
	assert_eq(actor.inventory.serialize_contents(), before)
	var storage: InventoryData = window.inventory_owner.inventory
	assert_eq(storage.entries[-1].stack_id, "old.clothes")
	assert_eq(storage.entries[-1].grid_position, Vector2i(6, 4))
	assert_almost_eq(actor.inventory.get_total_weight(), actor.inventory.max_weight, 0.0001)


func _assert_larger_replacement_stays_in_source_bag(during_trade: bool, full_bag: bool) -> void:
	var sword: ItemDefinition = load("res://features/inventory/resources/items/steel_sword.tres")
	var dagger: ItemDefinition = load("res://features/inventory/resources/items/iron_dagger.tres")
	controller._on_inventory_equip_requested(actor, actor.inventory.entries[0], actor, "backpack")
	assert_true(actor.inventory.add_entry_with_contents(sword, 1, {}, {"quality": 0.37}, "old.weapon"))
	controller._on_inventory_equip_requested(actor, actor.inventory.entries[-1], actor, "weapon")
	var window = controller.open_item_storage(actor, "test.bag")
	var storage: InventoryData = window.inventory_owner.inventory
	assert_true(storage.add_entry_with_contents(dagger, 1, {}, {"quality": 0.63}, "new.weapon"))
	assert_true(storage.move_entry(storage.entries[0], Vector2i(9, 8)))
	if full_bag:
		_fill_empty_cells(storage)
	if during_trade:
		_merchant()
		window = controller.open_item_storage(actor, "test.bag")
		storage = window.inventory_owner.inventory
	var incoming = storage.entries[0]
	var before := storage.serialize_contents()
	var before_pockets := actor.inventory.serialize_contents()
	var notice := _show_notices()
	controller._on_inventory_equip_requested(window.inventory_owner, incoming, actor, "weapon")
	assert_eq(actor.inventory.serialize_contents(), before_pockets, "Never spill the larger replacement into pockets")
	if full_bag:
		assert_eq(actor.get_equipment().get_equipped_stack_id("weapon"), "old.weapon")
		assert_true(storage.entries.has(incoming))
		assert_eq(storage.serialize_contents(), before)
		assert_eq(notice.label.text, "No room for equipped item")
	else:
		assert_eq(actor.get_equipment().get_equipped_stack_id("weapon"), "new.weapon")
		assert_eq(storage.entries.size(), 1)
		assert_eq(storage.entries[0].stack_id, "old.weapon")
		assert_eq(storage.entries[0].grid_position, Vector2i.ZERO, "Use another spot in the same bag when the original position cannot fit")
		assert_eq(storage.entries[0].metadata, {"quality": 0.37})
	if during_trade:
		assert_true(controller.trade_session.is_current())


func test_equipment_swap_uses_another_cell_in_source_bag() -> void:
	_assert_larger_replacement_stays_in_source_bag(false, false)


func test_equipment_swap_during_trade_uses_another_cell_in_source_bag() -> void:
	_assert_larger_replacement_stays_in_source_bag(true, false)


func test_equipment_swap_refuses_when_larger_replacement_cannot_fit_source_bag() -> void:
	_assert_larger_replacement_stays_in_source_bag(false, true)


func test_equipment_swap_during_trade_refuses_when_larger_replacement_cannot_fit_source_bag() -> void:
	_assert_larger_replacement_stays_in_source_bag(true, true)


func test_cursor_placement_counts_bag_contents_and_shared_carrier_weight() -> void:
	var window = controller.open_item_storage(actor, "test.bag")
	actor.inventory.max_weight = actor.inventory.get_total_weight()
	assert_false(controller._place_cursor_item_in_inventory(window.inventory_owner.inventory, FOOD, 1, Vector2i.ZERO))
	assert_eq(window.inventory_owner.inventory.count_item(FOOD), 0)
	var contents := InventoryData.create_item_storage(BAG, {}, "external.bag")
	assert_true(contents.add_item(FOOD))
	var recipient := InventoryData.new()
	recipient.max_weight = BAG.unit_weight
	assert_false(controller._place_cursor_item_in_inventory(recipient, BAG, 1, Vector2i.ZERO, {}, {"item_storage": contents.serialize_contents()}))
	assert_eq(recipient.count_item(BAG), 0)


func test_bag_weight_label_shows_shared_carried_weight_during_trade() -> void:
	controller._on_inventory_equip_requested(actor, actor.inventory.entries[0], actor, "backpack")
	var window = controller.open_item_storage(actor, "test.bag")
	controller._on_inventory_transfer_requested(actor, window.inventory_owner, actor.inventory.entries[0], Vector2i.ZERO)
	window.refresh()
	assert_eq(window.weight_label.text, "2.0 / 60.0")
	_merchant()
	window = controller.open_item_storage(actor, "test.bag")
	var weight := "%.1f / %.1f" % [actor.inventory.get_total_weight(), actor.inventory.max_weight]
	assert_eq(window.weight_label.text, weight, "Trading must not hide equipped bag weight or show a second allowance")


func test_filled_bag_cannot_be_sold_through_direct_or_cursor_paths() -> void:
	var window = controller.open_item_storage(actor, "test.bag")
	controller._on_inventory_transfer_requested(actor, window.inventory_owner, actor.inventory.entries[1], Vector2i.ZERO)
	var bag = actor.inventory.entries[0]
	var merchant := _merchant()
	var role: MerchantRole = merchant.get_node("MerchantRole")
	assert_true(role.get_shop_inventory().add_item_count(InventoryData.SILVER_ITEM, 20))
	controller._end_trade()
	controller._sell_to_merchant(actor, merchant, bag, Vector2i(4, 0), role)
	assert_true(actor.inventory.entries.has(bag))
	assert_eq(role.get_shop_inventory().count_item(BAG), 0)
	assert_false(controller._try_sell_cursor_item({"source_owner": actor, "item_definition": BAG, "count": 1, "metadata": bag.metadata}, merchant, Vector2i(6, 0), role))
	assert_eq(actor.inventory.count_item(InventoryData.SILVER_ITEM), 20)
	assert_eq(role.get_shop_inventory().count_item(InventoryData.SILVER_ITEM), 20)


func test_unequip_bag_during_trade_does_not_count_weight_twice() -> void:
	controller._on_inventory_equip_requested(actor, actor.inventory.entries[0], actor, "backpack")
	_merchant()
	actor.inventory.max_weight = actor.inventory.get_total_weight()
	controller._on_inventory_unequip_requested(actor, "backpack", actor, Vector2i(4, 0))
	assert_null(actor.get_equipped_item("backpack"))
	assert_eq(actor.inventory.count_item(BAG), 1)
	assert_almost_eq(actor.inventory.get_total_weight(), actor.inventory.max_weight, 0.0001)


func test_ground_drop_and_pickup_keep_the_exact_bag_contents() -> void:
	var lifecycle := ItemLifecycleController.new()
	controller.root_scene.add_child(lifecycle)
	controller._context.register(ItemLifecycleController.SERVICE_ID, lifecycle)
	lifecycle.initialize(controller._context)
	var window = controller.open_item_storage(actor, "test.bag")
	controller._on_inventory_transfer_requested(actor, window.inventory_owner, actor.inventory.entries[1], Vector2i.ZERO)
	controller._on_inventory_equip_requested(actor, actor.inventory.entries[0], actor, "backpack")
	controller._on_inventory_equipment_drop_requested(actor, "backpack")
	lifecycle._drain_commands()
	assert_eq(bridge.get_item_stack("test.bag").get("location_kind"), "world_loose")
	var dropped: WorldItem
	for child in controller.root_scene.get_children():
		if child is WorldItem and child.stack_id == "test.bag":
			dropped = child
	assert_not_null(dropped)
	if dropped == null:
		return
	assert_true(dropped.try_pickup(actor))
	lifecycle._drain_commands()
	assert_eq(actor.inventory.count_item(BAG), 1)
	window = controller.open_item_storage(actor, "test.bag")
	assert_eq(window.inventory_owner.inventory.entries[0].stack_id, "test.food")
	assert_eq(window.inventory_owner.inventory.entries[0].metadata, {"quality": 0.7})
	assert_eq(bridge.get_item_stack("test.bag").get("location_kind"), "inventory")


func _pointer(at: Vector2, pressed := false) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	motion.relative = at - controller.inventory_window_layer.get_viewport().get_mouse_position()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	controller.inventory_window_layer.get_viewport().push_input(motion, true)


func _click(at: Vector2, pressed: bool, double_click := false, shift_pressed := false) -> void:
	_pointer(at, pressed)
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.double_click = double_click
	event.shift_pressed = shift_pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	controller.inventory_window_layer.get_viewport().push_input(event, true)


func _shift_click_stock(stack_id: String) -> void:
	await _shift_click_grid(controller.secondary_inventory_window, stack_id)


func _shift_click_grid(window: InventoryWindow, stack_id: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var grid := window.inventory_grid
	var entry: InventoryData.InventoryEntry
	for candidate in grid.inventory_data.entries:
		if candidate.stack_id == stack_id:
			entry = candidate
			break
	assert_not_null(entry, "The exact item is present in the real inventory grid")
	if entry == null:
		return
	var at := grid.global_position + grid._item_rect(entry).get_center()
	_click(at, true, false, true)
	_click(at, false, false, true)


func _shift_click_equipment(window: InventoryWindow, slot_name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var slot: EquipmentSlotControl = window._equipment_slots[slot_name]
	var at := slot.global_position + slot.get_equipped_item_rect().get_center()
	_click(at, true, false, true)
	_click(at, false, false, true)


func _open_transfer_pair(looting := true) -> void:
	controller._on_inventory_equip_requested(actor, actor.inventory.entries[0], actor, "backpack")
	actor.player_party_member = true
	transfer_partner = HumanoidCharacter.new()
	transfer_partner.process_mode = Node.PROCESS_MODE_DISABLED
	transfer_partner.stable_id = "test.transfer.partner"
	transfer_partner.appearance_data = actor.appearance_data.duplicate()
	controller.root_scene.add_child(transfer_partner)
	bridge.register_actor(transfer_partner)
	assert_true(transfer_partner.inventory.add_entry_with_contents(FOOD, 1, {}, {"quality": 0.41}, "partner.food"))
	if looting:
		var ownership := OwnershipController.new()
		controller.root_scene.add_child(ownership)
		controller._context.register(OwnershipController.SERVICE_ID, ownership)
		ownership.initialize(controller._context)
		# A healthy actor forced unconscious can recover during GUI layout.
		# Keep this routing fixture lootable while GECS continues processing.
		transfer_partner.life_state = NpcRules.LifeState.DEAD
		controller.open_npc_inventory(actor, transfer_partner, "loot")
	else:
		transfer_partner.player_party_member = true
		controller.open_inventory_pair(actor, transfer_partner)
	assert_not_null(controller.secondary_inventory_window)


func test_shift_click_loose_loot_prefers_open_bag() -> void:
	_open_transfer_pair()
	var window = controller.open_item_storage(actor, "test.bag")
	var notice := _show_notices()
	watch_signals(controller.secondary_inventory_window)
	await _shift_click_grid(controller.secondary_inventory_window, "partner.food")
	assert_eq(transfer_partner.life_state, NpcRules.LifeState.DEAD, "The fixture stays lootable until the click")
	assert_signal_emitted(controller.secondary_inventory_window, "quick_equip_requested")
	assert_eq(notice.label.text, "", "A fitting unseen take must not be refused")
	assert_eq(window.inventory_owner.inventory.count_item(FOOD), 1)
	assert_eq(actor.inventory.count_item(FOOD), 1, "Pockets remain separate")
	assert_eq(transfer_partner.inventory.count_item(FOOD), 0)
	var stored: Array = bridge.get_item_stack("test.bag").metadata.get("item_storage", {}).get("entries", [])
	assert_eq(stored.size(), 1)
	if not stored.is_empty():
		assert_eq(stored[0].stack_id, "partner.food")
		assert_eq(stored[0].metadata, {"quality": 0.41})


func test_shift_click_loot_closed_bag_uses_pockets_then_auto_opens_fallback() -> void:
	_open_transfer_pair()
	var window = controller.open_item_storage(actor, "test.bag")
	controller._close_inventory_window(window)
	await _shift_click_grid(controller.secondary_inventory_window, "partner.food")
	assert_null(_window_for_bag("test.bag"), "Closed storage does not open while pockets fit")
	assert_eq(actor.inventory.count_item(FOOD), 2)
	assert_true(transfer_partner.inventory.add_entry_with_contents(FOOD, 1, {}, {"quality": 0.52}, "partner.second"))
	_fill_empty_cells(actor.inventory)
	await _shift_click_grid(controller.secondary_inventory_window, "partner.second")
	window = _window_for_bag("test.bag")
	assert_not_null(window, "Full pockets automatically open the equipped bag")
	if window == null:
		return
	assert_true(window.visible)
	assert_eq(window.inventory_owner.inventory.count_item(FOOD), 1)
	assert_eq(actor.inventory.count_item(FOOD), 2)
	assert_eq(transfer_partner.inventory.count_item(FOOD), 0)
	assert_eq(bridge.get_item_stack("test.bag").metadata.item_storage.entries[0].stack_id, "partner.second")


func test_shift_click_loot_open_full_bag_falls_back_then_both_full_refuses() -> void:
	_open_transfer_pair()
	var window = controller.open_item_storage(actor, "test.bag")
	_fill_empty_cells(window.inventory_owner.inventory)
	var original_storage: Dictionary = bridge.get_item_stack("test.bag").metadata.duplicate(true)
	var notice := _show_notices()
	await _shift_click_grid(controller.secondary_inventory_window, "partner.food")
	assert_eq(actor.inventory.count_item(FOOD), 2)
	assert_eq(transfer_partner.inventory.count_item(FOOD), 0)
	assert_eq(notice.label.text, "")
	_fill_empty_cells(actor.inventory)
	assert_true(transfer_partner.inventory.add_entry_with_contents(FOOD, 1, {}, {"quality": 0.52}, "partner.second"))
	await _shift_click_grid(controller.secondary_inventory_window, "partner.second")
	assert_eq(notice.label.text, "No room")
	assert_eq(transfer_partner.inventory.count_item(FOOD), 1)
	assert_eq(actor.inventory.count_item(FOOD), 2)
	assert_eq(bridge.get_item_stack("test.bag").metadata, original_storage)
	assert_eq(bridge.get_item_stack("partner.second").get("owner_actor_id"), transfer_partner.stable_id)
	assert_eq(bridge.get_item_stack("partner.second").get("metadata"), {"quality": 0.52})


func _equip_partner_item(item: ItemDefinition, slot_name: String, id: String, metadata := {}) -> void:
	assert_true(transfer_partner.inventory.add_entry_with_contents(item, 1, {}, metadata, id))
	controller._on_inventory_equip_requested(transfer_partner, transfer_partner.inventory.entries[-1], transfer_partner, slot_name)
	assert_eq(transfer_partner.get_equipment().get_equipped_stack_id(slot_name), id)
	assert_eq(bridge.get_item_stack(id).get("metadata"), metadata)


func test_shift_click_equipped_loot_preserves_exact_item_in_open_bag() -> void:
	_open_transfer_pair()
	var sword: ItemDefinition = load("res://features/inventory/resources/items/iron_sword.tres")
	_equip_partner_item(sword, "weapon", "partner.sword", {"quality": 0.37})
	var window = controller.open_item_storage(actor, "test.bag")
	await _shift_click_equipment(controller.secondary_inventory_window, "weapon")
	assert_null(transfer_partner.get_equipped_item("weapon"))
	assert_null(actor.get_equipped_item("weapon"), "Shift-click loots, rather than equips")
	assert_eq(actor.inventory.count_item(sword), 0)
	assert_eq(window.inventory_owner.inventory.count_item(sword), 1)
	var stored: Array = bridge.get_item_stack("test.bag").metadata.get("item_storage", {}).get("entries", [])
	assert_eq(stored.size(), 1)
	if not stored.is_empty():
		assert_eq(stored[0].stack_id, "partner.sword")
		assert_eq(stored[0].metadata, {"quality": 0.37})


func test_shift_click_filled_equipped_bag_goes_to_pockets_without_nesting() -> void:
	_open_transfer_pair()
	var contents := InventoryData.create_item_storage(BAG, {}, "partner.bag")
	assert_true(contents.add_entry_with_contents(FOOD, 1, {}, {"quality": 0.23}, "partner.stored"))
	var metadata := {InventoryData.ITEM_STORAGE_KEY: contents.serialize_contents()}
	_equip_partner_item(BAG, "backpack", "partner.bag", metadata)
	var window = controller.open_item_storage(actor, "test.bag")
	await _shift_click_equipment(controller.secondary_inventory_window, "backpack")
	assert_null(transfer_partner.get_equipped_item("backpack"))
	assert_eq(window.inventory_owner.inventory.count_item(BAG), 0)
	assert_eq(actor.inventory.count_item(BAG), 1)
	assert_eq(bridge.get_item_stack("partner.bag").get("metadata"), metadata)
	assert_eq(bridge.get_item_stack("partner.bag").get("owner_actor_id"), actor.stable_id)
	assert_eq(bridge.get_item_stack("partner.bag").get("location_kind"), "inventory")


func test_shift_click_party_transfer_uses_recipient_bag_in_both_directions() -> void:
	_open_transfer_pair(false)
	_equip_partner_item(BAG, "backpack", "partner.bag")
	var own_bag = controller.open_item_storage(actor, "test.bag")
	var other_bag = controller.open_item_storage(transfer_partner, "partner.bag")
	await _shift_click_grid(controller.primary_character_window, "test.food")
	assert_eq(actor.inventory.count_item(FOOD), 0)
	assert_eq(transfer_partner.inventory.count_item(FOOD), 1)
	assert_eq(other_bag.inventory_owner.inventory.count_item(FOOD), 1)
	assert_eq(own_bag.inventory_owner.inventory.count_item(FOOD), 0, "Do not transfer to the source character's own open bag")
	await _shift_click_grid(other_bag, "test.food")
	assert_eq(own_bag.inventory_owner.inventory.count_item(FOOD), 1)
	assert_eq(other_bag.inventory_owner.inventory.count_item(FOOD), 0)
	assert_eq(transfer_partner.inventory.count_item(FOOD), 1, "A source bag belongs to its owner's side, not a third participant")
	assert_eq(actor.inventory.count_item(FOOD), 0)
	assert_eq(bridge.get_item_stack("test.bag").metadata.item_storage.entries[0].stack_id, "test.food")
	assert_eq(bridge.get_item_stack("test.bag").metadata.item_storage.entries[0].metadata, {"quality": 0.7})


func test_shift_click_loot_currency_pouch_preserves_contents_and_identity() -> void:
	_open_transfer_pair()
	var pouch: ItemDefinition = load("res://features/inventory/resources/items/silver_pouch.tres")
	assert_true(transfer_partner.inventory.add_entry_with_contents(pouch, 1, {InventoryData.SILVER_ITEM.resource_path: 7}, {"quality": 0.28}, "partner.purse"))
	var window = controller.open_item_storage(actor, "test.bag")
	await _shift_click_grid(controller.secondary_inventory_window, "partner.purse")
	assert_eq(window.inventory_owner.inventory.count_item(InventoryData.SILVER_ITEM), 7)
	assert_eq(actor.inventory.count_item(InventoryData.SILVER_ITEM), 0)
	assert_eq(transfer_partner.inventory.count_item(InventoryData.SILVER_ITEM), 0)
	var stored: Array = bridge.get_item_stack("test.bag").metadata.get("item_storage", {}).get("entries", [])
	assert_eq(stored.size(), 1)
	if not stored.is_empty():
		assert_eq(stored[0].stack_id, "partner.purse")
		assert_eq(stored[0].metadata, {"quality": 0.28})
		assert_eq(stored[0].contained_item_counts, {InventoryData.SILVER_ITEM.resource_path: 7})


func test_shift_click_buy_prefers_open_backpack_through_pointer_input() -> void:
	controller._on_inventory_equip_requested(actor, actor.inventory.entries[0], actor, "backpack")
	var merchant := _merchant()
	var stock: InventoryData = merchant.get_node("MerchantRole").get_shop_inventory()
	var window = controller.open_item_storage(actor, "test.bag")
	await _shift_click_stock("stock.food")
	assert_eq(controller.trade_session.views[window.trade_side].count_item(FOOD), 1, "The open backpack receives the pending purchase before pockets")
	assert_eq(controller.trade_session.views[0].count_item(FOOD), 1, "Personal inventory remains separate")
	assert_eq(stock.count_item(FOOD), 1, "Shift-click only proposes the purchase")
	assert_eq(window.inventory_owner.inventory.count_item(FOOD), 0)
	controller._confirm_trade()
	assert_eq(window.inventory_owner.inventory.count_item(FOOD), 1)
	assert_eq(actor.inventory.count_item(FOOD), 1)
	assert_eq(actor.inventory.count_item(InventoryData.SILVER_ITEM), 18)
	assert_eq(stock.count_item(FOOD), 0)
	assert_eq(stock.count_item(InventoryData.SILVER_ITEM), 2)
	var stored: Array = bridge.get_item_stack("test.bag").metadata.get("item_storage", {}).get("entries", [])
	assert_eq(stored.size(), 1)
	if not stored.is_empty():
		assert_eq(stored[0].stack_id, "stock.food")
		assert_eq(stored[0].metadata, {"quality": 0.4})


func test_shift_click_buy_adds_remaining_stack_to_its_existing_bag_offer() -> void:
	var seeds: ItemDefinition = load("res://features/inventory/resources/items/tomato_seeds.tres")
	controller._on_inventory_equip_requested(actor, actor.inventory.entries[0], actor, "backpack")
	var merchant := _merchant()
	var stock: InventoryData = merchant.get_node("MerchantRole").get_shop_inventory()
	assert_true(stock.add_entry_with_contents(seeds, 3, {}, {"quality": 0.6}, "stock.seeds"))
	controller._cancel_trade()
	var window = controller.open_item_storage(actor, "test.bag")
	controller._offer_trade_item(merchant, stock.entries[-1], 1)
	assert_eq(window.inventory_grid.inventory_data.count_item(seeds), 1, "Buy one reserves a cell in the open bag")
	await _shift_click_stock("stock.seeds")
	assert_eq(window.inventory_grid.inventory_data.count_item(seeds), 3, "Buying the rest grows the existing bag offer without moving it to pockets")
	assert_eq(controller.trade_session.views[0].count_item(seeds), 0)
	assert_eq(controller.trade_session.offers.size(), 1)
	controller._confirm_trade()
	assert_eq(window.inventory_owner.inventory.count_item(seeds), 3)
	assert_eq(actor.inventory.count_item(seeds), 0)
	assert_eq(stock.count_item(seeds), 0)
	assert_eq(actor.inventory.count_item(InventoryData.SILVER_ITEM), 14)
	assert_eq(stock.count_item(InventoryData.SILVER_ITEM), 6)
	var stored: Array = bridge.get_item_stack("test.bag").metadata.get("item_storage", {}).get("entries", [])
	assert_eq(stored.size(), 1)
	if not stored.is_empty():
		assert_eq(stored[0].stack_id, "stock.seeds")
		assert_eq(stored[0].metadata, {"quality": 0.6})


func _fill_inventory_with_food(inventory: InventoryData) -> void:
	for _index in range(inventory.columns * inventory.rows):
		if inventory.find_first_space(FOOD) == Vector2i(-1, -1):
			return
		assert_true(inventory.add_entry_with_contents(FOOD), "Fill the actual grid, not a mocked capacity check")
	assert_eq(inventory.find_first_space(FOOD), Vector2i(-1, -1))


func _window_for_bag(stack_id: String) -> InventoryWindow:
	for window in controller.open_inventory_windows.values():
		if window.inventory_owner is ITEM_STORAGE_VIEW and window.inventory_owner.stack_id == stack_id:
			return window
	return null


func test_shift_click_buy_auto_opens_unopened_equipped_bag_when_pockets_are_full() -> void:
	controller._on_inventory_equip_requested(actor, actor.inventory.entries[0], actor, "backpack")
	var merchant := _merchant()
	_fill_inventory_with_food(actor.inventory)
	controller._cancel_trade()
	assert_null(_window_for_bag("test.bag"))
	var personal_count := actor.inventory.count_item(FOOD)
	await _shift_click_stock("stock.food")
	var window := _window_for_bag("test.bag")
	assert_not_null(window, "Full pockets automatically open the equipped bag")
	if window == null:
		return
	assert_true(window.visible)
	assert_eq(window.inventory_grid.inventory_data.count_item(FOOD), 1)
	assert_eq(controller.trade_session.views[0].count_item(FOOD), personal_count)
	controller._confirm_trade()
	assert_eq(window.inventory_owner.inventory.count_item(FOOD), 1)
	assert_eq(actor.inventory.count_item(FOOD), personal_count)
	assert_eq(actor.inventory.count_item(InventoryData.SILVER_ITEM), 18)
	assert_eq(merchant.get_node("MerchantRole").get_shop_inventory().count_item(FOOD), 0)


func test_shift_click_buy_closed_bag_uses_pockets_then_reopens_without_losing_offers() -> void:
	controller.inventory_window_layer.get_viewport().size = Vector2i(1152, 648)
	controller.inventory_window_layer.size = Vector2(1152, 648)
	controller._on_inventory_equip_requested(actor, actor.inventory.entries[0], actor, "backpack")
	var merchant := _merchant()
	var stock: InventoryData = merchant.get_node("MerchantRole").get_shop_inventory()
	assert_true(stock.add_entry_with_contents(FOOD, 1, {}, {}, "stock.second"))
	assert_true(stock.add_entry_with_contents(FOOD, 1, {}, {}, "stock.third"))
	_fill_inventory_with_food(actor.inventory)
	assert_true(actor.inventory.remove_entry(actor.inventory.entries[-1]), "Leave room for exactly one purchase in pockets")
	controller._cancel_trade()
	var personal_count := actor.inventory.count_item(FOOD)
	var window = controller.open_item_storage(actor, "test.bag")
	await _shift_click_stock("stock.food")
	assert_eq(window.inventory_grid.inventory_data.count_item(FOOD), 1)
	_click(window.close_button.get_global_rect().get_center(), true)
	_click(window.close_button.get_global_rect().get_center(), false)
	assert_false(window.visible)
	await _shift_click_stock("stock.second")
	assert_false(window.visible, "Closing the bag restores pockets-first and does not open it unnecessarily")
	assert_eq(controller.trade_session.views[0].count_item(FOOD), personal_count + 1)
	assert_eq(controller.trade_session.views[window.trade_side].count_item(FOOD), 1, "The earlier bag offer is retained")
	await _shift_click_stock("stock.third")
	assert_true(window.visible, "Once preview pockets are full the existing bag reopens")
	assert_eq(controller.trade_session.offers.size(), 3)
	assert_eq(controller.trade_session.views[window.trade_side].count_item(FOOD), 2)
	for _frame in range(6):
		await get_tree().process_frame
	assert_false(window.get_global_rect().intersects(controller.secondary_inventory_window.get_global_rect()), "Auto-opening restores the three-window layout")
	assert_false(window.get_global_rect().intersects(controller.primary_character_window.get_global_rect()))
	controller._confirm_trade()
	assert_eq(actor.inventory.count_item(FOOD), personal_count + 1)
	assert_eq(window.inventory_owner.inventory.count_item(FOOD), 2)
	assert_eq(actor.inventory.count_item(InventoryData.SILVER_ITEM), 20 - 3 * 2)
	assert_eq(stock.count_item(FOOD), 0)
	assert_eq(stock.count_item(InventoryData.SILVER_ITEM), 3 * 2)


func _show_notices() -> FloatingNotice:
	var notice := FloatingNotice.new()
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.name = "Label"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice.add_child(label)
	controller.inventory_window_layer.add_child(notice)
	notice.set_process(false)
	controller.floating_notice = notice
	return notice


func test_shift_click_buy_fills_bag_then_pockets_and_only_refuses_when_both_are_full() -> void:
	controller._on_inventory_equip_requested(actor, actor.inventory.entries[0], actor, "backpack")
	var merchant := _merchant()
	var stock: InventoryData = merchant.get_node("MerchantRole").get_shop_inventory()
	assert_true(stock.add_entry_with_contents(FOOD, 1, {}, {}, "stock.second"))
	assert_true(stock.add_entry_with_contents(FOOD, 1, {}, {}, "stock.third"))
	var window = controller.open_item_storage(actor, "test.bag")
	var storage: InventoryData = window.inventory_owner.inventory
	_fill_inventory_with_food(storage)
	_fill_inventory_with_food(actor.inventory)
	assert_true(storage.remove_entry(storage.entries[-1]))
	assert_true(actor.inventory.remove_entry(actor.inventory.entries[-1]))
	controller._cancel_trade()
	var bag_count := storage.count_item(FOOD)
	var personal_count := actor.inventory.count_item(FOOD)
	var notice := _show_notices()
	await _shift_click_stock("stock.food")
	assert_eq(window.inventory_grid.inventory_data.count_item(FOOD), bag_count + 1)
	assert_eq(controller.trade_session.views[0].count_item(FOOD), personal_count)
	await _shift_click_stock("stock.second")
	assert_eq(controller.trade_session.views[0].count_item(FOOD), personal_count + 1)
	assert_eq(window.inventory_grid.inventory_data.count_item(FOOD), bag_count + 1)
	assert_eq(notice.label.text, "", "Falling back to pockets is not a failed purchase")
	await _shift_click_stock("stock.third")
	assert_eq(notice.label.text, "No room")
	assert_eq(controller.trade_session.offers.size(), 2, "A refusal cannot overwrite either pending purchase")
	assert_eq(storage.count_item(FOOD), bag_count)
	assert_eq(actor.inventory.count_item(FOOD), personal_count)
	assert_eq(stock.count_item(FOOD), 3)
	assert_eq(actor.inventory.count_item(InventoryData.SILVER_ITEM), 20)
	assert_eq(stock.count_item(InventoryData.SILVER_ITEM), 0)
	controller._on_inventory_window_close_requested(window.inventory_owner)
	await _shift_click_stock("stock.third")
	assert_true(window.visible, "A closed bag is opened for the fallback even when it is also full")
	assert_eq(notice.label.text, "No room")
	assert_eq(controller.trade_session.offers.size(), 2)
	controller._cancel_trade()
	assert_eq(window.inventory_grid.inventory_data.count_item(FOOD), bag_count)
	assert_eq(controller.trade_session.views[0].count_item(FOOD), personal_count)
	await _shift_click_stock("stock.third")
	assert_eq(window.inventory_grid.inventory_data.count_item(FOOD), bag_count + 1, "Reset releases the previously reserved bag cell")
	controller._confirm_trade()
	assert_eq(storage.count_item(FOOD), bag_count + 1)
	assert_eq(actor.inventory.count_item(FOOD), personal_count)
	assert_eq(stock.count_item(FOOD), 2)
	assert_eq(actor.inventory.count_item(InventoryData.SILVER_ITEM), 18)
	assert_eq(stock.count_item(InventoryData.SILVER_ITEM), 2)


func test_shift_click_buy_does_not_nest_a_purchased_bag() -> void:
	controller._on_inventory_equip_requested(actor, actor.inventory.entries[0], actor, "backpack")
	var merchant := _merchant()
	var stock: InventoryData = merchant.get_node("MerchantRole").get_shop_inventory()
	assert_true(stock.add_entry_with_contents(BAG, 1, {}, {}, "stock.bag"))
	controller._cancel_trade()
	var window = controller.open_item_storage(actor, "test.bag")
	await _shift_click_stock("stock.bag")
	assert_eq(window.inventory_grid.inventory_data.count_item(BAG), 0)
	assert_eq(controller.trade_session.views[0].count_item(BAG), 1, "A bag that cannot enter storage can still be bought into pockets")
	controller._confirm_trade()
	assert_eq(window.inventory_owner.inventory.count_item(BAG), 0)
	assert_eq(actor.inventory.count_item(BAG), 1)
	assert_eq(stock.count_item(BAG), 0)
	assert_eq(actor.inventory.count_item(InventoryData.SILVER_ITEM), 18)


func test_shift_click_buy_does_not_auto_open_an_unequipped_carried_bag() -> void:
	var merchant := _merchant()
	_fill_inventory_with_food(actor.inventory)
	controller._cancel_trade()
	var notice := _show_notices()
	var personal_count := actor.inventory.count_item(FOOD)
	await _shift_click_stock("stock.food")
	assert_null(_window_for_bag("test.bag"), "Automatic fallback is the equipped backpack, not every carried container")
	assert_eq(notice.label.text, "No room")
	assert_eq(controller.trade_session.offers.size(), 0)
	assert_eq(actor.inventory.count_item(FOOD), personal_count)
	assert_eq(actor.inventory.count_item(InventoryData.SILVER_ITEM), 20)
	assert_eq(merchant.get_node("MerchantRole").get_shop_inventory().count_item(FOOD), 1)


func test_open_button_and_popup_header_close_work_through_pointer_input() -> void:
	controller._on_inventory_equip_requested(actor, actor.inventory.entries[0], actor, "backpack")
	await get_tree().process_frame
	await get_tree().process_frame
	var slot: EquipmentSlotControl = controller.primary_character_window._equipment_slots["backpack"]
	var button: Button = slot.find_child("OpenBagButton", true, false)
	assert_true(button.visible)
	assert_true(slot.is_ancestor_of(button), "Open belongs to the backpack slot, not a detached bottom row")
	var artwork := Rect2(slot.global_position, slot.get_equipped_item_rect().size)
	assert_false(artwork.intersects(button.get_global_rect()), "Opening the bag must not cover its artwork or drag target")
	_click(button.get_global_rect().get_center(), true)
	_click(button.get_global_rect().get_center(), false)
	assert_eq(controller.open_inventory_windows.size(), 2)
	var window = controller.open_item_storage(actor, "test.bag")
	await get_tree().process_frame
	window.position = Vector2(800, 100)
	var start: Vector2 = window.position
	var grip: Vector2 = window.grab_area.get_global_rect().get_center()
	_click(grip, true)
	_pointer(grip + Vector2(80, 40), true)
	_click(grip + Vector2(80, 40), false)
	assert_eq(window.position, start + Vector2(80, 40))
	_click(window.close_button.get_global_rect().get_center(), true)
	_click(window.close_button.get_global_rect().get_center(), false)
	assert_eq(controller.open_inventory_windows.size(), 1)
	_click(artwork.get_center(), true, true)
	_click(artwork.get_center(), false)
	assert_eq(controller.open_inventory_windows.size(), 2, "Double-clicking the equipped bag opens its inventory")


func _drag_item(source: InventoryGridControl, target: InventoryGridControl, entry, cell: Vector2i) -> void:
	var from: Vector2 = source.global_position + source._item_rect(entry).get_center()
	var destination = InventoryData.InventoryEntry.new(entry.definition, cell)
	var to: Vector2 = target.global_position + target._item_rect(destination).get_center()
	_click(from, true)
	_pointer(from + Vector2(15, 0), true)
	await get_tree().process_frame
	assert_true(source.get_viewport().gui_is_dragging(), "The engine started an actual item drag")
	_pointer(to, true)
	await get_tree().process_frame
	_click(to, false)
	await get_tree().process_frame


func test_pointer_drag_personal_bag_and_merchant_reset_settlement() -> void:
	controller._on_inventory_equip_requested(actor, actor.inventory.entries[0], actor, "backpack")
	var window = controller.open_item_storage(actor, "test.bag")
	await get_tree().process_frame
	await get_tree().process_frame
	controller.primary_character_window.position = Vector2(20, 20)
	window.position = Vector2(980, 20)
	await _drag_item(controller.primary_character_window.inventory_grid, window.inventory_grid, actor.inventory.entries[0], Vector2i.ZERO)
	assert_eq(actor.inventory.count_item(FOOD), 0)
	assert_eq(window.inventory_owner.inventory.count_item(FOOD), 1)
	await _drag_item(window.inventory_grid, controller.primary_character_window.inventory_grid, window.inventory_owner.inventory.entries[0], Vector2i.ZERO)
	assert_eq(actor.inventory.count_item(FOOD), 1)
	assert_eq(window.inventory_owner.inventory.count_item(FOOD), 0)
	var merchant := _merchant()
	window = controller.open_item_storage(actor, "test.bag")
	await get_tree().process_frame
	await get_tree().process_frame
	var shop: InventoryWindow = controller.secondary_inventory_window
	controller.primary_character_window.position = Vector2(20, 20)
	shop.position = Vector2(550, 20)
	window.position = Vector2(980, 20)
	var stock: InventoryData = merchant.get_node("MerchantRole").get_shop_inventory()
	await _drag_item(shop.inventory_grid, window.inventory_grid, shop.inventory_grid.inventory_data.entries[0], Vector2i.ZERO)
	assert_eq(controller.trade_session.offers.size(), 1)
	var reset: Button = shop.find_child("CancelTradeButton", true, false)
	_click(reset.get_global_rect().get_center(), true)
	_click(reset.get_global_rect().get_center(), false)
	assert_eq(controller.trade_session.offers.size(), 0)
	assert_eq(stock.count_item(FOOD), 1)
	await _drag_item(shop.inventory_grid, window.inventory_grid, shop.inventory_grid.inventory_data.entries[0], Vector2i.ZERO)
	_click(shop.trade_button.get_global_rect().get_center(), true)
	_click(shop.trade_button.get_global_rect().get_center(), false)
	assert_eq(window.inventory_owner.inventory.count_item(FOOD), 1)
	assert_eq(actor.inventory.count_item(InventoryData.SILVER_ITEM), 18)
	assert_eq(actor.inventory.count_item(FOOD), 1)
	await _drag_item(window.inventory_grid, shop.inventory_grid, window.inventory_grid.inventory_data.entries[0], Vector2i(4, 0))
	_click(shop.trade_button.get_global_rect().get_center(), true)
	_click(shop.trade_button.get_global_rect().get_center(), false)
	assert_eq(window.inventory_owner.inventory.count_item(FOOD), 0)
	assert_eq(actor.inventory.count_item(InventoryData.SILVER_ITEM), 19)


func test_buying_bag_directly_to_equipment_still_checks_carry_limit() -> void:
	var merchant := _merchant()
	var stock: InventoryData = merchant.get_node("MerchantRole").get_shop_inventory()
	assert_true(stock.add_entry_with_contents(BAG, 1, {}, {}, "stock.bag"))
	controller.trade_session.reset()
	var entry = stock.entries[-1]
	actor.inventory.max_weight = actor.inventory.get_total_weight()
	assert_eq(controller.trade_session.propose_equipment(1, entry, "backpack"), "")
	assert_ne(controller.trade_session.commit(), "")
	assert_null(actor.get_equipped_item("backpack"))
	assert_eq(actor.inventory.count_item(InventoryData.SILVER_ITEM), 20)
	assert_true(stock.entries.has(entry))


func test_medium_bag_shows_full_ten_by_ten_grid_and_accepts_bottom_corner() -> void:
	controller._on_inventory_equip_requested(actor, actor.inventory.entries[0], actor, "backpack")
	var window = controller.open_item_storage(actor, "test.bag")
	await get_tree().process_frame
	await get_tree().process_frame
	var storage: InventoryData = window.inventory_owner.inventory
	assert_eq(Vector2i(storage.columns, storage.rows), Vector2i(10, 10))
	assert_gte(window.grid_scroll.size.y, 318.0, "All ten rows are visible without scrolling at the normal viewport size")
	assert_eq(window.inventory_grid.cell_size, Vector2(30, 30), "Keep the existing readable cell scale")
	await _drag_item(controller.primary_character_window.inventory_grid, window.inventory_grid, actor.inventory.entries[0], Vector2i(8, 8))
	assert_eq(storage.count_item(FOOD), 1, "The lower-right corner is usable, not just drawn")
	if not storage.entries.is_empty():
		assert_eq(storage.entries[0].grid_position, Vector2i(8, 8))


func test_backpack_and_trade_windows_remain_separate_in_default_sized_viewport() -> void:
	var viewport := controller.inventory_window_layer.get_viewport()
	viewport.size = Vector2i(1152, 648)
	controller.inventory_window_layer.size = Vector2(1152, 648)
	controller._on_inventory_equip_requested(actor, actor.inventory.entries[0], actor, "backpack")
	_merchant()
	var shop := controller.secondary_inventory_window
	var original_shop_width := shop.size.x
	var bag_window = controller.open_item_storage(actor, "test.bag")
	for _frame in range(6):
		await get_tree().process_frame
	var windows := [controller.primary_character_window, bag_window, shop]
	for index in range(windows.size()):
		var rect: Rect2 = windows[index].get_global_rect()
		assert_true(Rect2(Vector2.ZERO, Vector2(1152, 648)).encloses(rect), "Window and its controls stay on screen")
		for other in range(index + 1, windows.size()):
			assert_false(rect.intersects(windows[other].get_global_rect()), "Personal, backpack and trader windows must not obscure each other")
	assert_eq(shop.inventory_grid.cell_size, Vector2(30, 30))
	assert_eq(shop.size.y, controller.primary_character_window.size.y, "Keep the accepted matching-height shopping layout")
	controller._cancel_trade()
	for _frame in range(4):
		await get_tree().process_frame
	assert_false(shop.get_global_rect().intersects(bag_window.get_global_rect()), "Reset does not restore overlapping widths")
	controller._on_inventory_window_close_requested(bag_window.inventory_owner)
	for _frame in range(4):
		await get_tree().process_frame
	assert_almost_eq(shop.size.x, original_shop_width, 0.1, "Closing storage restores the ordinary merchant width")


func test_slot_open_action_hides_for_empty_and_unpurchased_bags() -> void:
	var slot: EquipmentSlotControl = controller.primary_character_window._equipment_slots["backpack"]
	var button: Button = slot.find_child("OpenBagButton", true, false)
	assert_false(button.visible)
	controller._on_inventory_equip_requested(actor, actor.inventory.entries[0], actor, "backpack")
	assert_true(button.visible)
	var merchant := _merchant()
	var stock: InventoryData = merchant.get_node("MerchantRole").get_shop_inventory()
	assert_true(stock.add_entry_with_contents(BAG, 1, {}, {}, "stock.other-bag"))
	controller._cancel_trade()
	assert_eq(controller.trade_session.propose_equipment(1, stock.entries[-1], "backpack"), "")
	controller._refresh_trade()
	assert_false(button.visible, "The preview of an unpurchased bag must not open the old equipped bag")
	controller._cancel_trade()
	assert_true(button.visible)
	controller._on_inventory_unequip_requested(actor, "backpack", actor, Vector2i(4, 0))
	assert_false(button.visible)


func test_equipped_bag_still_drags_without_triggering_open() -> void:
	controller._on_inventory_equip_requested(actor, actor.inventory.entries[0], actor, "backpack")
	await get_tree().process_frame
	await get_tree().process_frame
	var player := controller.primary_character_window
	var slot: EquipmentSlotControl = player._equipment_slots["backpack"]
	var start := slot.global_position + slot.get_equipped_item_rect().get_center()
	var destination := InventoryData.InventoryEntry.new(BAG, Vector2i(4, 0))
	var end := player.inventory_grid.global_position + player.inventory_grid._item_rect(destination).get_center()
	_click(start, true)
	_pointer(start + Vector2(15, 0), true)
	await get_tree().process_frame
	assert_true(slot.get_viewport().gui_is_dragging())
	_pointer(end, true)
	await get_tree().process_frame
	_click(end, false)
	await get_tree().process_frame
	assert_null(actor.get_equipped_item("backpack"))
	assert_eq(actor.inventory.count_item(BAG), 1)
	assert_eq(controller.open_inventory_windows.size(), 1, "Dragging is not an Open action")


func test_narrow_trader_can_scroll_to_offscreen_stock_and_trade_into_bag() -> void:
	controller.inventory_window_layer.get_viewport().size = Vector2i(1152, 648)
	controller.inventory_window_layer.size = Vector2(1152, 648)
	controller._on_inventory_equip_requested(actor, actor.inventory.entries[0], actor, "backpack")
	var merchant := _merchant()
	var stock: InventoryData = merchant.get_node("MerchantRole").get_shop_inventory()
	assert_true(stock.move_entry(stock.entries[0], Vector2i(13, 0)))
	controller._cancel_trade()
	var window = controller.open_item_storage(actor, "test.bag")
	for _frame in range(6):
		await get_tree().process_frame
	var shop := controller.secondary_inventory_window
	var scrollbar := shop.grid_scroll.get_h_scroll_bar()
	assert_true(scrollbar.visible)
	var click := scrollbar.get_global_rect().end - Vector2(4, scrollbar.size.y * 0.5)
	_click(click, true)
	_click(click, false)
	await get_tree().process_frame
	assert_gt(shop.grid_scroll.scroll_horizontal, 0)
	var entry = shop.inventory_grid.inventory_data.entries[0]
	assert_true(shop.grid_scroll.get_global_rect().has_point(shop.inventory_grid.global_position + shop.inventory_grid._item_rect(entry).get_center()))
	await _drag_item(shop.inventory_grid, window.inventory_grid, entry, Vector2i(8, 8))
	assert_eq(controller.trade_session.offers.size(), 1)
	_click(shop.trade_button.get_global_rect().get_center(), true)
	_click(shop.trade_button.get_global_rect().get_center(), false)
	assert_eq(window.inventory_owner.inventory.count_item(FOOD), 1)
	assert_eq(stock.count_item(FOOD), 0)
	assert_eq(actor.inventory.count_item(InventoryData.SILVER_ITEM), 18)


func test_sack_biscuit_drag_holds_over_valid_and_occupied_cells_before_release() -> void:
	controller._on_inventory_equip_requested(actor, actor.inventory.entries[0], actor, "backpack")
	var bag_window = controller.open_item_storage(actor, "test.bag")
	var gloves: ItemDefinition = load("res://features/inventory/resources/items/traveler_hide_gloves.tres")
	assert_true(bag_window.inventory_owner.inventory.add_entry_with_contents(gloves, 1, {}, {}, "stored.gloves"))
	controller._close_inventory_window(bag_window)
	gloves = null
	bag_window = null
	await get_tree().process_frame
	var sack: WorldContainer = load("res://features/world/projection/props/furniture/sack.tscn").instantiate()
	sack.container_id = "test.hover.sack"
	sack.process_mode = Node.PROCESS_MODE_DISABLED
	controller.root_scene.add_child(sack)
	assert_true(sack.inventory.add_entry_with_contents(FOOD, 1, {}, {"quality": 0.8}, "sack.biscuits"))
	controller.open_inventory_pair(actor, sack)
	await get_tree().process_frame
	await get_tree().process_frame
	controller.primary_character_window.position = Vector2(20, 20)
	controller.secondary_inventory_window.position = Vector2(980, 20)
	var source := controller.secondary_inventory_window.inventory_grid
	var target := controller.primary_character_window.inventory_grid
	await _hold_biscuit_drag(source, target, sack.inventory.entries[0], actor.inventory.entries[0].grid_position)
	assert_eq(sack.inventory.count_item(FOOD), 0)
	assert_eq(actor.inventory.count_item(FOOD), 2)
	assert_eq(actor.inventory.entries[-1].stack_id, "sack.biscuits")
	assert_eq(actor.inventory.entries[-1].metadata, {"quality": 0.8})
	bag_window = controller.open_item_storage(actor, "test.bag")
	await get_tree().process_frame
	await get_tree().process_frame
	controller.primary_character_window.position = Vector2(20, 20)
	bag_window.position = Vector2(500, 20)
	controller.secondary_inventory_window.position = Vector2(980, 20)
	assert_true(sack.inventory.add_entry_with_contents(FOOD, 1, {}, {"quality": 0.6}, "sack.second"))
	await _hold_biscuit_drag(source, bag_window.inventory_grid, sack.inventory.entries[0], Vector2i.ZERO)
	assert_eq(sack.inventory.count_item(FOOD), 0)
	assert_eq(bag_window.inventory_owner.inventory.count_item(FOOD), 1)
	assert_eq(actor.inventory.count_item(FOOD), 2, "Open bag contents remain separate")
	var saved: Array = bridge.get_item_stack("test.bag").metadata.item_storage.entries
	assert_eq(saved[-1].stack_id, "sack.second")
	assert_eq(saved[-1].metadata, {"quality": 0.6})


func _hold_biscuit_drag(source: InventoryGridControl, target: InventoryGridControl, entry, occupied_cell: Vector2i) -> void:
	var from := source.global_position + source._item_rect(entry).get_center()
	_click(from, true)
	_pointer(from + Vector2(15, 0), true)
	await get_tree().process_frame
	assert_true(source.get_viewport().gui_is_dragging())
	var source_count: int = source.inventory_data.entries.size()
	for cell in [Vector2i(4, 2), occupied_cell, Vector2i(5, 2), Vector2i(6, 2)]:
		var at := target.global_position + target._item_rect_from_definition(FOOD, cell).get_center()
		_pointer(at, true)
		for _frame in 4:
			await get_tree().process_frame
		assert_eq(target._preview_visible, cell != occupied_cell, "Actual held pointer updates the landing preview")
		assert_eq(source.inventory_data.entries.size(), source_count, "Holding a drag cannot transfer goods")
	var to := target.global_position + target._item_rect_from_definition(FOOD, Vector2i(6, 2)).get_center()
	_click(to, false)
	await get_tree().process_frame
	assert_false(source.get_viewport().gui_is_dragging())
