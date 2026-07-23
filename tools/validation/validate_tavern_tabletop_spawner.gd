extends SceneTree

const TABLE_PATH := "res://features/world/projection/props/bar_table.tscn"
const SHELF_PATH := "res://features/world/projection/props/furniture/shelf_stocked.tscn"

var _failed := false


func _init() -> void:
	_validate_scene(TABLE_PATH, 5)
	_validate_scene(SHELF_PATH, 2)
	var table_source := FileAccess.get_file_as_string(TABLE_PATH)
	var world_item_source := FileAccess.get_file_as_string("res://features/world/projection/items/world_item.gd")
	var spawner_source := FileAccess.get_file_as_string("res://features/world/projection/props/tabletop_item_spawner.gd")
	_assert(table_source.contains("slot_id = \"food\"\nstock_projection = true"), "Bar food must be a stock-backed visual projection")
	_assert(world_item_source.contains("transact_item_count(stock_source_settlement_id, item_definition, -quantity)"), "Taking projected food must debit indexed town stock")
	_assert(not world_item_source.contains("func _sync_world_item_to_gecs"), "World item projections must not write durable GECS state directly")
	var gecs_source := FileAccess.get_file_as_string("res://features/core/gecs_world_controller.gd")
	_assert(not gecs_source.contains("func sync_world_item") and not gecs_source.contains("get_nodes_in_group(\"world_item\")"), "GECS must not scrape item projections for durable state")
	_assert(spawner_source.contains("BootstrapContext.SERVICE_CONSUMER_GROUP") and spawner_source.contains("func _on_bootstrap_context_ready"), "Tabletop spawners must initialize from explicit bootstrap readiness")
	_assert(spawner_source.contains("stock.stock_changed.connect(_on_stock_changed)") and spawner_source.contains("_queue_reconcile"), "Stock-backed tabletop visuals must reconcile after indexed stock changes")
	_assert(not spawner_source.contains("BootstrapContext.service(ItemLifecycleController.SERVICE_ID)"), "Tabletop seeding must not race bootstrap through a one-shot service lookup")
	var identity_source := spawner_source.get_slice("func _get_surface_id", 1).get_slice("func _facility_id", 0)
	_assert(not identity_source.contains("global_position") and not identity_source.contains("surface.%x"), "Persistent tabletop identity must not derive from world position")
	if _failed:
		quit(1)
		return
	print("TAVERN_TABLETOP_SPAWNER_OK")
	quit()


func _validate_scene(path: String, expected_slots: int) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		_fail("Missing tabletop scene %s" % path)
		return
	if not text.contains("tabletop_item_spawner.gd") or not text.contains("tabletop_item_slot.gd"):
		_fail("%s must compose a tabletop surface and authored slot nodes" % path)
	if text.contains("script = ExtResource(\"2_spawner\")") or text.contains("script = ExtResource(\"1_spawner\")"):
		_fail("%s still inherits spawning at the furniture root" % path)
	var slot_count := text.count("slot_id = ")
	if slot_count != expected_slots:
		_fail("%s expected %d authored slots, found %d" % [path, expected_slots, slot_count])
	if not text.contains("optional_items = Array[ItemDefinition]"):
		_fail("%s must author explicit item choices instead of hardcoded categories" % path)


func _fail(message: String) -> void:
	_failed = true
	push_error(message)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)
