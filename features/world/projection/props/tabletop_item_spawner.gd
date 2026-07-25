extends Node3D

class_name TabletopItemSpawner

const WORLD_ITEM_SCENE := preload("res://features/world/projection/items/world_item.tscn")

## Composable tabletop surface. Furniture remains its own body/workstation;
## this child authors stable slots and realizes durable item-stack records.

@export var surface_id := ""
@export var seed_salt := "tabletop"
@export var owner_faction_name := ""
@export var tabletop_half_extents := Vector2(1.35, 0.65)
@export var tabletop_pickup_clearance := 0.6
@export var tabletop_grab_horizontal_reach := 1.9
@export var tabletop_grab_vertical_reach := 2.05
@export var tabletop_pickup_nav_projection_limit := 1.25
@export var tabletop_pickup_vertical_projection_limit := 2.0
@export var theft_noise_radius := 1.2
@export_range(0, 100, 1) var theft_difficulty := 15

var _resolved_surface_id := ""
var _lifecycle: ItemLifecycleController
var _reconcile_queued := false
var _stock_reconcile_queued := false


func _ready() -> void:
	add_to_group("tabletop_item_spawner")
	add_to_group(BootstrapContext.SERVICE_CONSUMER_GROUP)
	if Engine.is_editor_hint():
		return
	if BootstrapContext.active != null and BootstrapContext.active.has_service(ItemLifecycleController.SERVICE_ID):
		_on_bootstrap_context_ready(BootstrapContext.active)


func _on_bootstrap_context_ready(context: BootstrapContext) -> void:
	if Engine.is_editor_hint() or context == null:
		return
	_lifecycle = context.get_optional(ItemLifecycleController.SERVICE_ID) as ItemLifecycleController
	if _lifecycle == null:
		return
	var gecs := context.get_optional(GecsWorldController.SERVICE_ID) as GecsWorldController
	if gecs != null and not gecs.world_reindexed.is_connected(_on_world_reindexed):
		gecs.world_reindexed.connect(_on_world_reindexed)
	var stock := context.get_optional(InventoryStockController.SERVICE_ID) as InventoryStockController
	if stock != null and not stock.stock_changed.is_connected(_on_stock_changed):
		stock.stock_changed.connect(_on_stock_changed)
	call_deferred("_seed_or_restore")


func _on_world_reindexed() -> void:
	_queue_reconcile()


func _on_stock_changed(settlement_id: String, _facility_id: String) -> void:
	if settlement_id == _settlement_id():
		_queue_stock_reconcile()


func _queue_reconcile() -> void:
	if _reconcile_queued:
		return
	_reconcile_queued = true
	_stock_reconcile_queued = false
	_reconcile_item_projections.call_deferred()


func _queue_stock_reconcile() -> void:
	if _reconcile_queued or _stock_reconcile_queued:
		return
	_stock_reconcile_queued = true
	_reconcile_stock_projections.call_deferred()


func _reconcile_item_projections() -> void:
	_reconcile_queued = false
	for child in get_children():
		if child is WorldItem:
			remove_child(child)
			child.free()
	_seed_or_restore()


func _reconcile_stock_projections() -> void:
	if not _stock_reconcile_queued:
		return
	_stock_reconcile_queued = false
	for child in get_children():
		if child is WorldItem and bool(child.get("stock_projection")):
			remove_child(child)
			child.free()
	for child in get_children():
		var slot := child as TabletopItemSlot
		if slot != null and slot.stock_projection:
			_spawn_stock_projection(slot)


func _seed_or_restore() -> void:
	if _lifecycle == null:
		return
	_resolved_surface_id = _get_surface_id()
	if _resolved_surface_id.is_empty():
		push_warning("TabletopItemSpawner '%s' needs an explicit surface_id or an owning facility_id" % get_path())
		return
	var existing_by_slot: Dictionary = {}
	for record in _lifecycle.get_stack_records_for_host(_resolved_surface_id):
		var record_metadata := record.get("metadata", {}) as Dictionary
		var seeded_slot_id := str(record.get("placement_slot_id", record_metadata.get("tabletop_origin_slot_id", "")))
		if seeded_slot_id.is_empty():
			seeded_slot_id = str(record_metadata.get("tabletop_origin_slot_id", ""))
		existing_by_slot[seeded_slot_id] = record
		if str(record.get("location_kind", "")) == "tabletop_slot":
			_realize_record(record)
	for child in get_children():
		var slot := child as TabletopItemSlot
		if slot == null:
			continue
		if slot.stock_projection:
			_spawn_stock_projection(slot)
			continue
		if existing_by_slot.has(slot.slot_id):
			continue
		var definition := slot.choose_definition(_make_slot_rng(slot.slot_id))
		if definition == null:
			continue
		var stack_id := "%s.slot.%s" % [_resolved_surface_id, slot.slot_id]
		var metadata := {
			"tabletop_seeded": true,
			"tabletop_origin_host_id": _resolved_surface_id,
			"tabletop_origin_slot_id": slot.slot_id,
		}
		var item := _create_world_item(definition, stack_id, slot.slot_id, _settlement_id(), metadata)
		if item == null:
			continue
		add_child(item)
		item.global_transform = slot.global_transform
		_configure_item(item)
		item.place_bottom_at(slot.global_position, slot.global_position.y)
		var result := _lifecycle.submit_world_stack({
			"stack_id": stack_id,
			"container_id": "world",
			"owner_actor_id": "",
			"item_definition_path": definition.resource_path,
			"count": 1,
			"grid_position": Vector2i.ZERO,
			"contained_item_counts": {},
			"metadata": metadata,
			"location_kind": "tabletop_slot",
			"world_transform": item.global_transform,
			"placement_host_id": _resolved_surface_id,
			"placement_slot_id": slot.slot_id,
			"location_settlement_id": _settlement_id(),
		})
		if not bool(result.get("accepted", false)):
			item.queue_free()


func _spawn_stock_projection(slot: TabletopItemSlot) -> void:
	var settlement_id := _settlement_id()
	var stock := BootstrapContext.service(InventoryStockController.SERVICE_ID) as InventoryStockController
	if stock == null or settlement_id.is_empty():
		return
	var snapshot := stock.get_settlement_stock_snapshot(settlement_id)
	var definition := slot.choose_available_definition(_make_slot_rng(slot.slot_id), snapshot.get("items", {}), _food_spawn_scale(settlement_id))
	if definition == null:
		return
	var item := _create_world_item(definition, "display.%s.%s" % [_resolved_surface_id, slot.slot_id], slot.slot_id, settlement_id, {})
	if item == null:
		return
	item.stock_projection = true
	item.stock_source_settlement_id = settlement_id
	add_child(item)
	item.global_transform = slot.global_transform
	_configure_item(item)
	item.place_bottom_at(slot.global_position, slot.global_position.y)


func _food_spawn_scale(settlement_id: String) -> float:
	var food := BootstrapContext.service(SettlementFoodController.SERVICE_ID) as SettlementFoodController
	if food == null:
		return 1.0
	match str(food.get_status(settlement_id).get("pressure_state", "supplied")):
		"starving":
			return 0.12
		"hungry":
			return 0.5
		_:
			return 1.0


func _realize_record(record: Dictionary) -> void:
	var definition := load(str(record.get("item_definition_path", ""))) as ItemDefinition
	if definition == null:
		return
	var item := _create_world_item(definition, str(record["stack_id"]), str(record.get("placement_slot_id", "")), str(record.get("location_settlement_id", "")), record.get("metadata", {}))
	if item == null:
		return
	var saved_world_transform: Transform3D = record.get("world_transform", global_transform)
	item.transform = global_transform.affine_inverse() * saved_world_transform
	add_child(item)
	_configure_item(item)


func _create_world_item(definition: ItemDefinition, stack_id: String, slot_id: String, settlement_id: String, metadata: Dictionary) -> WorldItem:
	var item := WORLD_ITEM_SCENE.instantiate() as WorldItem
	if item == null:
		return null
	item.stack_id = stack_id
	item.item_definition = definition
	item.item_metadata = metadata.duplicate(true)
	item.location_kind = "tabletop_slot"
	item.placement_host_id = _resolved_surface_id
	item.placement_slot_id = slot_id
	item.location_settlement_id = settlement_id
	return item


func _configure_item(item: WorldItem) -> void:
	item.owner_faction_name = owner_faction_name
	item.theft_noise_radius = theft_noise_radius
	item.theft_difficulty = theft_difficulty
	item.set_meta("tabletop_slot", item.placement_slot_id)
	item.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	item.freeze = true
	item.sleeping = true
	item.gravity_scale = 0.0


func get_tabletop_pickup_position(item: Node3D, actor = null) -> Vector3:
	var inverse := global_transform.affine_inverse()
	var item_local := inverse * item.global_position
	var actor_local := item_local
	if actor is Node3D:
		actor_local = inverse * (actor as Node3D).global_position
	var candidates := [
		Vector3(-tabletop_half_extents.x - tabletop_pickup_clearance, 0.0, clampf(item_local.z, -tabletop_half_extents.y, tabletop_half_extents.y)),
		Vector3(tabletop_half_extents.x + tabletop_pickup_clearance, 0.0, clampf(item_local.z, -tabletop_half_extents.y, tabletop_half_extents.y)),
		Vector3(clampf(item_local.x, -tabletop_half_extents.x, tabletop_half_extents.x), 0.0, -tabletop_half_extents.y - tabletop_pickup_clearance),
		Vector3(clampf(item_local.x, -tabletop_half_extents.x, tabletop_half_extents.x), 0.0, tabletop_half_extents.y + tabletop_pickup_clearance),
	]
	var best := global_position
	var best_distance := INF
	for local_position in candidates:
		var projected := _project_to_navigation(global_transform * local_position)
		var distance := Vector2(local_position.x - actor_local.x, local_position.z - actor_local.z).length()
		if distance < best_distance:
			best = projected
			best_distance = distance
	return best


func is_tabletop_item_reachable_from(item: Node3D, _actor, actor_position: Vector3, reach_distance: float) -> bool:
	if absf(actor_position.y - item.global_position.y) > tabletop_grab_vertical_reach:
		return false
	return Vector2(actor_position.x - item.global_position.x, actor_position.z - item.global_position.z).length() <= minf(reach_distance, tabletop_grab_horizontal_reach)


func _project_to_navigation(position: Vector3) -> Vector3:
	if not is_inside_tree() or get_world_3d() == null:
		return position
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return position
	var closest := NavigationServer3D.map_get_closest_point(map, position)
	if Vector2(closest.x - position.x, closest.z - position.z).length() > tabletop_pickup_nav_projection_limit:
		return position
	if absf(closest.y - position.y) > tabletop_pickup_vertical_projection_limit:
		return position
	return closest


func _get_surface_id() -> String:
	var facility_id := _facility_id()
	var local_id := surface_id.strip_edges()
	if facility_id.is_empty() or local_id.is_empty():
		return ""
	return "%s.%s" % [facility_id, local_id]


func _facility_id() -> String:
	var current := get_parent()
	while current != null:
		if current.has_method("get_facility_id"):
			var resolved := str(current.call("get_facility_id"))
			if not resolved.is_empty():
				return resolved
		for property in current.get_property_list():
			if str(property.get("name", "")) == "facility_id":
				var value := str(current.get("facility_id"))
				if not value.is_empty():
					return value
		current = current.get_parent()
	return ""


func _settlement_id() -> String:
	var current := get_parent()
	while current != null:
		if current.has_method("get_settlement_id"):
			return str(current.call("get_settlement_id"))
		for property in current.get_property_list():
			if str(property.get("name", "")) == "settlement_id":
				var value := str(current.get("settlement_id"))
				if not value.is_empty():
					return value
		current = current.get_parent()
	return ""


func _make_slot_rng(slot_id: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = maxi(1, abs(("%s|%s|%s" % [_get_surface_id(), seed_salt, slot_id]).hash()))
	return rng
