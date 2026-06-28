extends SceneTree

const SETTLEMENT_BAR_SCENE := preload("res://features/settlements/bridge/settlement_bar.tscn")
const PARADISE_HILLS_SCENE := preload("res://scenes/zones/demo_zone/towns/paradise_hills.tscn")
const SURF_CITY_SCENE := preload("res://scenes/zones/demo_zone/towns/surf_city.tscn")
const EAST_RAIDERS_CAMP_SCENE := preload("res://scenes/zones/demo_zone/towns/east_raiders_camp.tscn")
const WORLD_ITEM_SCENE := preload("res://features/world/projection/items/world_item.tscn")
const WORLD_INTERACTION_CONTROLLER_SCRIPT := preload("res://features/world/bridge/world_interaction_controller.gd")
const TABLE_PLATE_ITEM := preload("res://features/inventory/resources/items/table_plate.tres")
const MUG_ITEM := preload("res://features/inventory/resources/items/mug.tres")
const TABLE_FORK_ITEM := preload("res://features/inventory/resources/items/table_fork.tres")
const TABLE_SPOON_ITEM := preload("res://features/inventory/resources/items/table_spoon.tres")
const TABLE_KNIFE_ITEM := preload("res://features/inventory/resources/items/table_knife.tres")
const BOTTLE_1_ITEM := preload("res://features/inventory/resources/items/bottle_1.tres")
const BOTTLE_2_ITEM := preload("res://features/inventory/resources/items/bottle_2.tres")
const SMALL_BOTTLE_ITEM := preload("res://features/inventory/resources/items/small_bottle.tres")
const CHALICE_ITEM := preload("res://features/inventory/resources/items/chalice.tres")
const TALL_CANDLE_ITEM := preload("res://features/inventory/resources/items/candle_1.tres")
const SHORT_CANDLE_ITEM := preload("res://features/inventory/resources/items/candle_2.tres")
const STUBBY_CANDLE_ITEM := preload("res://features/inventory/resources/items/candle_3.tres")
const CANDLESTICK_ITEM := preload("res://features/inventory/resources/items/candlestick.tres")
const BREAD_ITEM := preload("res://features/inventory/resources/items/bread.tres")

const TABLETOP_ITEM_DEFINITIONS := [
	TABLE_PLATE_ITEM,
	MUG_ITEM,
	TABLE_FORK_ITEM,
	TABLE_SPOON_ITEM,
	TABLE_KNIFE_ITEM,
	BOTTLE_1_ITEM,
	BOTTLE_2_ITEM,
	SMALL_BOTTLE_ITEM,
	CHALICE_ITEM,
	TALL_CANDLE_ITEM,
	SHORT_CANDLE_ITEM,
	STUBBY_CANDLE_ITEM,
	CANDLESTICK_ITEM,
	BREAD_ITEM,
]

var _failures: Array[String] = []


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	var bar := SETTLEMENT_BAR_SCENE.instantiate()
	root.add_child(bar)
	await process_frame
	await process_frame
	_validate_tabletop_item_definitions()
	_validate_tables(bar)
	await _validate_tabletop_raycast_prefers_item(bar)
	await _validate_demo_town_bar(PARADISE_HILLS_SCENE, "ParadiseHills")
	await _validate_demo_town_bar(SURF_CITY_SCENE, "SurfCity")
	await _validate_demo_town_bar(EAST_RAIDERS_CAMP_SCENE, "EastRaidersCamp")
	await _validate_world_item_label_visibility()
	await _validate_candle_drop_stability()
	if _failures.is_empty():
		print("TAVERN_TABLETOP_SPAWNER_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("TAVERN_TABLETOP_SPAWNER_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_demo_town_bar(town_scene: PackedScene, town_name: String) -> void:
	var town := town_scene.instantiate()
	root.add_child(town)
	await process_frame
	await process_frame
	var bar := town.get_node_or_null("Facilities/Bar")
	if bar == null:
		_fail("%s should ship with Facilities/Bar" % town_name)
		return
	_validate_tables(bar)


func _validate_tabletop_raycast_prefers_item(bar: Node) -> void:
	var item := _find_first_spawned_table_item(bar)
	if item == null:
		_fail("Could not find a spawned tabletop item for raycast validation")
		return
	var camera := Camera3D.new()
	camera.name = "ValidationTopdownCamera"
	root.add_child(camera)
	camera.current = true
	camera.global_position = item.global_position + Vector3(0.0, 4.0, 0.02)
	camera.look_at(item.global_position, Vector3.FORWARD)
	await physics_frame
	var interaction := WORLD_INTERACTION_CONTROLLER_SCRIPT.new() as WorldInteractionController
	interaction.camera = camera
	root.add_child(interaction)
	var hit: Dictionary = interaction.call("_raycast_target_from_screen", camera.unproject_position(item.global_position))
	var collider: Object = hit.get("collider") if not hit.is_empty() else null
	if collider != item:
		_fail("Right-click raycast through tabletop should resolve the spawned item, got %s" % [str(collider)])
	interaction.queue_free()
	camera.queue_free()


func _find_first_spawned_table_item(bar: Node) -> WorldItem:
	var furniture := bar.get_node_or_null("Furniture")
	if furniture == null:
		return null
	for table_name in ["TableA", "TableB", "TableC", "TableD"]:
		var spawned_root := furniture.get_node_or_null("%s/SpawnedTabletopItems" % table_name)
		if spawned_root == null:
			continue
		for child in spawned_root.get_children():
			var item := child as WorldItem
			if item != null:
				return item
	return null


func _validate_tabletop_item_definitions() -> void:
	for definition in TABLETOP_ITEM_DEFINITIONS:
		if definition == null:
			_fail("Tabletop item definitions should not include null resources")
			continue
		if int(definition.max_stack) != 1:
			_fail("Tabletop item %s should not be stackable, max_stack=%d" % [definition.display_name, int(definition.max_stack)])
		_validate_tabletop_inventory_entry_count(definition)


func _validate_tabletop_inventory_entry_count(definition: ItemDefinition) -> void:
	var inventory := InventoryData.new(10, 8, 0.0, false)
	if not inventory.add_item_count(definition, 2):
		_fail("Tabletop item %s should fit two distinct inventory entries" % definition.display_name)
		return
	var entry_count := 0
	var total_count := 0
	for entry in inventory.entries:
		if entry.definition != definition:
			continue
		entry_count += 1
		total_count += int(entry.count)
		if int(entry.count) != 1:
			_fail("Tabletop item %s should not share inventory stacks, entry count=%d" % [definition.display_name, int(entry.count)])
	if entry_count != 2 or total_count != 2:
		_fail("Tabletop item %s should create two one-count inventory entries, got entries=%d total=%d" % [definition.display_name, entry_count, total_count])


func _validate_tables(bar: Node) -> void:
	var furniture := bar.get_node_or_null("Furniture")
	if furniture == null:
		_fail("Settlement bar should have a Furniture root")
		return
	for table_name in ["TableA", "TableB", "TableC", "TableD"]:
		_validate_table(furniture.get_node_or_null(table_name), table_name)


func _validate_table(table: Node, table_name: String) -> void:
	if table == null:
		_fail("Missing %s" % table_name)
		return
	var table_node := table as Node3D
	if table_node == null:
		_fail("%s should be a Node3D" % table_name)
		return
	if table.get_node_or_null("Top2") != null or table.get_node_or_null("LegFrontLeft2") != null:
		_fail("%s should not keep stale primitive table override children" % table_name)
	if not table.is_in_group("tabletop_item_spawner"):
		_fail("%s should use the tabletop item spawner" % table_name)
	var prop_slots := table.get_node_or_null("PropSlots")
	if prop_slots == null:
		_fail("%s should inherit reviewed PropSlots" % table_name)
	var spawned_root := table.get_node_or_null("SpawnedTabletopItems")
	if spawned_root == null:
		_fail("%s should create SpawnedTabletopItems" % table_name)
		return
	var spawned_items: Array[WorldItem] = []
	for child in spawned_root.get_children():
		var item := child as WorldItem
		if item != null:
			spawned_items.append(item)
	if spawned_items.size() < 3:
		_fail("%s should spawn at least 3 tabletop items, got %d" % [table_name, spawned_items.size()])
	var pickup_actor := Node3D.new()
	pickup_actor.name = "ValidationPickupActor"
	table.add_child(pickup_actor)
	pickup_actor.global_position = table_node.global_position + table_node.global_transform.basis.z.normalized() * 3.0
	for item in spawned_items:
		if item.item_definition == null:
			_fail("%s spawned an item without an ItemDefinition" % table_name)
		if not item.freeze:
			_fail("%s spawned tabletop item %s should be frozen" % [table_name, item.name])
		if not item.has_meta("tabletop_slot"):
			_fail("%s spawned tabletop item %s should record its slot" % [table_name, item.name])
		_validate_tabletop_item_surface_height(table_node, prop_slots, item, table_name)
		_validate_tabletop_pickup_position(table_node, item, pickup_actor, table_name)
	pickup_actor.queue_free()


func _validate_tabletop_item_surface_height(table: Node3D, prop_slots: Node, item: WorldItem, table_name: String) -> void:
	var slot_name := str(item.get_meta("tabletop_slot", ""))
	var slot := prop_slots.get_node_or_null(slot_name) as Node3D
	if slot == null:
		_fail("%s tabletop item %s should reference an existing slot" % [table_name, item.name])
		return
	var visual_bounds := item.get_visual_world_bounds()
	var surface_offset := -0.13
	var table_offset = table.get("tabletop_spawn_surface_offset")
	if table_offset is float or table_offset is int:
		surface_offset = float(table_offset)
	var expected_bottom_y := slot.global_position.y + surface_offset
	if absf(visual_bounds.position.y - expected_bottom_y) > 0.02:
		_fail("%s tabletop item %s should sit at lowered tabletop surface %.3f, got %.3f" % [table_name, item.name, expected_bottom_y, visual_bounds.position.y])


func _validate_tabletop_pickup_position(table: Node3D, item: WorldItem, pickup_actor: Node3D, table_name: String) -> void:
	var pickup_position := item.get_pickup_position(pickup_actor)
	if pickup_position.distance_to(item.global_position) < 0.35:
		_fail("%s tabletop item %s should route pickup to a nearby floor access point" % [table_name, item.name])
	var local_item := table.global_transform.affine_inverse() * item.global_position
	var local_pickup := table.global_transform.affine_inverse() * pickup_position
	var half_extents := _get_table_pickup_half_extents(table)
	if local_pickup.y > local_item.y - 0.4:
		_fail("%s tabletop item %s pickup access should be below the tabletop" % [table_name, item.name])
	if absf(local_pickup.x) < 1.35 and absf(local_pickup.z) < 0.6:
		_fail("%s tabletop item %s pickup access should be outside the table footprint" % [table_name, item.name])
	if _get_table_footprint_clearance(local_pickup, half_extents) < 0.45:
		_fail("%s tabletop item %s pickup access should leave room for the actor radius" % [table_name, item.name])
	if _is_near_sittable_seat(pickup_position, table):
		_fail("%s tabletop item %s pickup access should avoid nearby stools" % [table_name, item.name])
	if not item.is_pickup_reachable_from(pickup_actor, pickup_position, 1.8):
		_fail("%s tabletop item %s should be grabbable from its route access point" % [table_name, item.name])
	_validate_tabletop_short_stop_pickup(table, item, pickup_actor, table_name, pickup_position)
	_validate_tabletop_strict_pickup_reach(table, item, pickup_actor, table_name, pickup_position)


func _validate_tabletop_short_stop_pickup(table: Node3D, item: WorldItem, pickup_actor: Node3D, table_name: String, pickup_position: Vector3) -> void:
	var route_direction := pickup_position - item.global_position
	route_direction.y = 0.0
	if route_direction.length_squared() <= 0.001:
		return
	var arrival_slack := _get_float_property(table, "tabletop_pickup_arrival_slack", 0.25)
	var grab_reach := _get_float_property(table, "tabletop_grab_horizontal_reach", 1.9)
	var short_stop := pickup_position + route_direction.normalized() * arrival_slack
	short_stop.y = pickup_position.y
	if not item.is_pickup_reachable_from(pickup_actor, short_stop, grab_reach):
		_fail("%s tabletop item %s should be grabbable when the actor stops just short of its route point" % [table_name, item.name])


func _validate_tabletop_strict_pickup_reach(table: Node3D, item: WorldItem, pickup_actor: Node3D, table_name: String, pickup_position: Vector3) -> void:
	var inverse := table.global_transform.affine_inverse()
	var item_local := inverse * item.global_position
	var pickup_local := inverse * pickup_position
	var half_extents := _get_table_pickup_half_extents(table)
	var grab_reach := _get_float_property(table, "tabletop_grab_horizontal_reach", 1.9)
	var route_direction := pickup_position - item.global_position
	route_direction.y = 0.0
	if route_direction.length_squared() > 0.001:
		var beyond_reach := item.global_position + route_direction.normalized() * (grab_reach + 0.2)
		beyond_reach.y = pickup_position.y
		if item.is_pickup_reachable_from(pickup_actor, beyond_reach, grab_reach):
			_fail("%s tabletop item %s should reject pickup from beyond its direct grab reach" % [table_name, item.name])
	var opposite_end_sign := -1.0 if item_local.x >= 0.0 else 1.0
	var opposite_end_local := Vector3(opposite_end_sign * (half_extents.x + 0.55), pickup_local.y, item_local.z)
	var opposite_end := table.global_transform * opposite_end_local
	if item.is_pickup_reachable_from(pickup_actor, opposite_end, grab_reach):
		_fail("%s tabletop item %s should reject pickup from the opposite table end" % [table_name, item.name])
	if absf(item_local.z) > 0.3:
		var opposite_side_sign := -1.0 if item_local.z >= 0.0 else 1.0
		var opposite_side_local := Vector3(item_local.x, pickup_local.y, opposite_side_sign * (half_extents.y + 1.0))
		var opposite_side := table.global_transform * opposite_side_local
		if item.is_pickup_reachable_from(pickup_actor, opposite_side, grab_reach):
			_fail("%s tabletop item %s should reject pickup from the opposite table side" % [table_name, item.name])


func _get_table_footprint_clearance(local_position: Vector3, half_extents: Vector2) -> float:
	return maxf(absf(local_position.x) - half_extents.x, absf(local_position.z) - half_extents.y)


func _get_table_pickup_half_extents(table: Node3D) -> Vector2:
	var collision := table.get_node_or_null("BodyCollision") as CollisionShape3D
	if collision != null and collision.shape is BoxShape3D:
		var box := collision.shape as BoxShape3D
		return Vector2(maxf(box.size.x * 0.5, 0.1), maxf(box.size.z * 0.5, 0.1))
	return Vector2(1.35, 0.65)


func _get_float_property(node: Object, property_name: String, fallback: float) -> float:
	var value = node.get(property_name)
	if value is float or value is int:
		return float(value)
	return fallback


func _is_near_sittable_seat(world_position: Vector3, table: Node3D) -> bool:
	var seat_clearance := _get_float_property(table, "tabletop_pickup_seat_clearance", 0.6)
	for node in get_nodes_in_group("sittable_seat"):
		var seat := node as Node3D
		if seat == null or not is_instance_valid(seat):
			continue
		if seat.global_position.distance_squared_to(table.global_position) > 16.0:
			continue
		var distance := Vector2(world_position.x - seat.global_position.x, world_position.z - seat.global_position.z).length()
		if distance < seat_clearance:
			return true
	return false


func _validate_world_item_label_visibility() -> void:
	var item := WORLD_ITEM_SCENE.instantiate() as WorldItem
	root.add_child(item)
	await process_frame
	item.setup(MUG_ITEM, 1)
	var label := item.get_node_or_null("Label3D") as Label3D
	if label == null:
		_fail("WorldItem should have a Label3D")
		item.queue_free()
		return
	item._input(_make_alt_event(false, KEY_LOCATION_LEFT))
	if label.visible:
		_fail("World item labels should be hidden by default")
	item._input(_make_alt_event(true, KEY_LOCATION_RIGHT))
	if label.visible:
		_fail("World item labels should not show for right Alt")
	item._input(_make_alt_event(true, KEY_LOCATION_LEFT))
	if not label.visible:
		_fail("World item labels should show for left Alt")
	item._input(_make_alt_event(false, KEY_LOCATION_LEFT))
	if label.visible:
		_fail("World item labels should hide when left Alt is released")
	item.queue_free()


func _make_alt_event(pressed: bool, location: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ALT
	event.physical_keycode = KEY_ALT
	event.location = location
	event.pressed = pressed
	return event


func _validate_candle_drop_stability() -> void:
	var candle := WORLD_ITEM_SCENE.instantiate() as WorldItem
	root.add_child(candle)
	await process_frame
	candle.setup(STUBBY_CANDLE_ITEM, 1)
	if candle.lock_rotation:
		_fail("Stubby Candle should not use candle-specific rotation locking")
	_validate_generic_world_item_collision(candle, "Stubby Candle")
	var mug := WORLD_ITEM_SCENE.instantiate() as WorldItem
	root.add_child(mug)
	await process_frame
	mug.setup(MUG_ITEM, 1)
	if mug.lock_rotation:
		_fail("Mug should not use rotation locking")
	_validate_generic_world_item_collision(mug, "Mug")
	candle.queue_free()
	mug.queue_free()


func _validate_generic_world_item_collision(item: WorldItem, item_name: String) -> void:
	var collision_shape := item.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or not (collision_shape.shape is BoxShape3D):
		_fail("%s should use the generated WorldItem box collider" % item_name)
	var model_root := item.get_node_or_null("ModelRoot")
	if model_root != null and _has_nested_collision_node(model_root):
		_fail("%s should strip imported collision bodies from its visual" % item_name)


func _has_nested_collision_node(node: Node) -> bool:
	for child in node.get_children():
		if child is CollisionObject3D or child is CollisionShape3D:
			return true
		if _has_nested_collision_node(child):
			return true
	return false


func _fail(message: String) -> void:
	_failures.append(message)
