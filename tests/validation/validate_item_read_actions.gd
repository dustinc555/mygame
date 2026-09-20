extends "res://tests/validation/test_case.gd"
## UI-to-read-service dispatch and real ownership refusal. The report source is
## an explicit seam fixture; town report generation/persistence has its own tests.

const LEDGER := preload("res://features/inventory/resources/items/town_ledger.tres")
const MAP := preload("res://features/inventory/resources/items/town_map.tres")
const SILVER := preload("res://features/inventory/resources/items/silver.tres")
var _failures: Array[String] = []


class ReportSource extends Node:
	var queries: Array[String] = []
	func get_report(stack_id: String) -> Dictionary:
		queries.append(stack_id)
		return {} if stack_id == "unbound.ledger" else {"settlement_id": "test.town", "stack_id": stack_id}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_expect(LEDGER.read_behavior == ItemDefinition.ReadBehavior.TOWN_LEDGER, "Town ledger exposes typed Read behavior")
	_expect(MAP.read_behavior == ItemDefinition.ReadBehavior.DUD, "Map Read is a harmless dud")
	var fixture := Node3D.new()
	root.add_child(fixture)
	var party := PartyManager.new()
	party.name = "PartyManager"
	fixture.add_child(party)
	var hud := CanvasLayer.new()
	var windows := Control.new()
	windows.name = "InventoryWindowLayer"
	hud.add_child(windows)
	fixture.add_child(hud)
	var context := BootstrapContext.new(fixture, hud)
	var reports := ReportSource.new()
	fixture.add_child(reports)
	context.register(&"town_ledger", reports)
	var ownership := OwnershipController.new()
	fixture.add_child(ownership)
	ownership.initialize(context)
	context.register(OwnershipController.SERVICE_ID, ownership)
	var reader := ItemReadBridge.new()
	fixture.add_child(reader)
	reader.initialize(context)
	context.register(ItemReadBridge.SERVICE_ID, reader)
	var inventory := PartyInventoryController.new()
	fixture.add_child(inventory)
	inventory.initialize(context)
	var actor := HumanoidCharacter.new()
	actor.stable_id = "validation.reader"
	actor.faction_name = "Player"
	fixture.add_child(actor)
	party.set_party_members([actor])
	party.select_only(actor)
	var observed := {"opens": [], "notices": []}
	reader.read_open_requested.connect(func(id: String, definition: ItemDefinition, payload: Dictionary): observed.opens.append([id, definition, payload]))
	reader.read_notice_requested.connect(func(message: String): observed.notices.append(message))
	_expect(actor.inventory.add_entry_with_contents(LEDGER, 1, {}, {"test": true}, "inventory.ledger"), "Inventory ledger fixture adds")
	var entry = actor.inventory.entries[0]
	inventory.open_inventory_for_member(actor)
	await process_frame
	var window := inventory.primary_character_window
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	event.position = window.inventory_grid._item_rect(entry).get_center()
	window.inventory_grid._gui_input(event)
	_expect(window.item_menu.get_item_index(InventoryWindow.ACTION_READ) >= 0, "Real inventory context menu contains Read")
	window.item_menu.id_pressed.emit(InventoryWindow.ACTION_READ)
	window.item_menu.hide()
	_expect(reports.queries == ["inventory.ledger"] and observed.opens.size() == 1 and observed.opens[0][0] == "inventory.ledger" and observed.opens[0][1] == LEDGER, "Inventory menu dispatch reaches the read service for the exact stack")
	_expect(actor.inventory.entries.has(entry) and entry.metadata == {"test": true}, "Reading never consumes or mutates the ledger")
	var unbound = actor.inventory.create_entry(LEDGER, Vector2i.ZERO, 1, {}, {}, "unbound.ledger")
	_expect(not reader.read_inventory_item(actor, unbound) and observed.opens.size() == 1 and observed.notices.size() == 1, "Unbound ledger reports a notice, never opens an empty report")
	var map_entry = actor.inventory.create_entry(MAP, Vector2i.ZERO, 1, {}, {}, "map.dud")
	_expect(reader.read_inventory_item(actor, map_entry) and observed.opens.size() == 1 and observed.notices.size() == 2 and reports.queries.size() == 2, "Dud read emits notice without querying reports or opening ledger UI")
	var item := (load("res://features/world/projection/items/world_item.tscn") as PackedScene).instantiate() as WorldItem
	item.owner_faction_name = "Owners"
	item.item_definition = LEDGER
	item.stack_id = "world.private.ledger"
	fixture.add_child(item)
	var witness := HumanoidCharacter.new()
	witness.stable_id = "validation.read_owner"
	witness.faction_name = "Owners"
	fixture.add_child(witness)
	var action := reader.get_world_read_action(actor, item)
	_expect(action.get("label") == "Read (Private)" and action.get("illegal", false), "Foreign ledger Read is visibly private")
	# Enter the production world menu callback with its selected WorldItem.
	var world := WorldInteractionController.new()
	fixture.add_child(world)
	world.party_manager = party
	world.item_read_controller = reader
	world.context_world_item = item
	world._on_context_menu_id_pressed(WorldInteractionController.ACTION_READ_ITEM)
	_expect(observed.opens.size() == 1 and reports.queries.size() == 2 and is_instance_valid(item) and not item.is_queued_for_deletion(), "Ownership refusal prevents report query/open and preserves world item")
	actor.faction_name = "Owners"
	action = reader.get_world_read_action(actor, item)
	_expect(action.get("label") == "Read" and not action.get("illegal", true), "Owner reads without private warning")
	world._on_context_menu_id_pressed(WorldInteractionController.ACTION_READ_ITEM)
	_expect(observed.opens.size() == 2 and observed.opens[1][0] == "world.private.ledger" and reports.queries[-1] == "world.private.ledger", "Authorized world menu dispatch opens exact ledger")
	item.item_definition = SILVER
	_expect(reader.get_world_read_action(actor, item).is_empty() and not reader.read_world_item(actor, item) and observed.opens.size() == 2, "Unreadable item offers no Read and cannot dispatch")
	inventory._close_all_inventory_windows()
	fixture.queue_free()
	await process_frame
	for failure in _failures:
		push_error(failure)
	print("ITEM_READ_ACTIONS_OK" if _failures.is_empty() else "ITEM_READ_ACTIONS_FAILED")
	quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
