extends Node

class_name InventoryStockController

signal stock_changed(settlement_id: String, facility_id: String)

const SERVICE_ID := &"inventory_stock"
const CONTAINER_COMPONENT_PATH := "res://features/inventory/sim/c_game_inventory_container.gd"
const STACK_COMPONENT_PATH := "res://features/inventory/sim/c_game_item_stack.gd"
const ENTITY_PATH := "res://addons/gecs/ecs/entity.gd"

var _gecs_world: Node
var _container_component_script
var _stack_component_script
var _entity_script

var _containers_by_id: Dictionary = {}
var _stacks_by_id: Dictionary = {}
var _stack_ids_by_container: Dictionary = {}
var _container_ids_by_settlement: Dictionary = {}
var _container_ids_by_facility: Dictionary = {}
var _settlement_stock: Dictionary = {}
var _facility_stock: Dictionary = {}
var _live_projection_by_container_id: Dictionary = {}
var _definition_by_path: Dictionary = {}
var _definition_by_item_id: Dictionary = {}
var _display_name_by_item_id: Dictionary = {}


func initialize(context: BootstrapContext) -> void:
	_gecs_world = context.require(&"gecs_world")
	_container_component_script = load(CONTAINER_COMPONENT_PATH)
	_stack_component_script = load(STACK_COMPONENT_PATH)
	_entity_script = load(ENTITY_PATH)
	if _gecs_world != null and not _gecs_world.world_reindexed.is_connected(rebuild_from_gecs):
		_gecs_world.world_reindexed.connect(rebuild_from_gecs)
	rebuild_from_gecs()


func rebuild_from_gecs() -> void:
	_containers_by_id.clear()
	_stacks_by_id.clear()
	_stack_ids_by_container.clear()
	_container_ids_by_settlement.clear()
	_container_ids_by_facility.clear()
	_settlement_stock.clear()
	_facility_stock.clear()
	if _gecs_world == null or _gecs_world.world == null:
		return
	for entity in _gecs_world.world.query.with_all([_container_component_script]).execute():
		var component = entity.get_component(_container_component_script)
		if component != null and not str(component.container_id).is_empty():
			_index_container(entity, component)
	for entity in _gecs_world.world.query.with_all([_stack_component_script]).execute():
		var component = entity.get_component(_stack_component_script)
		if component != null and _containers_by_id.has(str(component.container_id)):
			_index_stack(entity, component)
	for container_id in _containers_by_id.keys():
		_add_container_aggregate(str(container_id))
	for container_id in _live_projection_by_container_id.keys():
		_hydrate_live_projection(str(container_id))


func bind_world_container(container: Node) -> bool:
	if container == null or not is_instance_valid(container):
		return false
	var container_id := str(container.get("container_id")).strip_edges()
	if container_id.is_empty():
		return false
	_live_projection_by_container_id[container_id] = weakref(container)
	if not _containers_by_id.has(container_id):
		return false
	_hydrate_live_projection(container_id)
	return true


func detach_world_container(container_id: String, container: Node) -> void:
	var projection_ref := _live_projection_by_container_id.get(container_id) as WeakRef
	if projection_ref != null and projection_ref.get_ref() == container:
		_live_projection_by_container_id.erase(container_id)


## Called after the projection has mirrored its InventoryData into GECS.
func sync_world_container(container: Node) -> void:
	if container == null or not is_instance_valid(container):
		return
	var container_id := str(container.get("container_id")).strip_edges()
	if container_id.is_empty():
		return
	_live_projection_by_container_id[container_id] = weakref(container)
	_remove_indexed_container(container_id)
	var container_entity = _gecs_world.get_inventory_container_entity(container_id)
	if container_entity == null or not is_instance_valid(container_entity):
		return
	var container_component = container_entity.get_component(_container_component_script)
	if container_component == null:
		return
	_index_container(container_entity, container_component)
	for entry in container.inventory.entries:
		var stack_entity = _gecs_world.get_item_stack_entity(str(entry.stack_id))
		if stack_entity == null or not is_instance_valid(stack_entity):
			continue
		var stack_component = stack_entity.get_component(_stack_component_script)
		if stack_component != null and str(stack_component.container_id) == container_id:
			_index_stack(stack_entity, stack_component)
	_add_container_aggregate(container_id)
	var settlement_id := str(container_component.settlement_id)
	if bool(container_component.contributes_to_town_stock) and not settlement_id.is_empty():
		stock_changed.emit(settlement_id, str(container_component.facility_id))


func get_settlement_stock_snapshot(settlement_id: String) -> Dictionary:
	return (_settlement_stock.get(settlement_id, {}) as Dictionary).duplicate(true)


func get_facility_stock_snapshot(facility_id: String) -> Dictionary:
	return (_facility_stock.get(facility_id, {}) as Dictionary).duplicate(true)


func get_settlement_container_snapshot(settlement_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for container_id_value in (_container_ids_by_settlement.get(settlement_id, {}) as Dictionary).keys():
		var container_id := str(container_id_value)
		var record := _containers_by_id.get(container_id, {}) as Dictionary
		if record.is_empty():
			continue
		var component = record["component"]
		result.append({
			"container_id": container_id,
			"facility_id": str(component.facility_id),
			"container_kind": str(component.container_kind),
			"stock": _container_contribution(container_id),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["container_id"]) < str(b["container_id"]))
	return result


func get_item_display_name(item_id: String) -> String:
	var clean_id := item_id.strip_edges()
	if _display_name_by_item_id.has(clean_id):
		return str(_display_name_by_item_id[clean_id])
	if clean_id.begins_with("res://"):
		var definition := _definition(clean_id)
		if definition != null:
			return definition.display_name
	var leaf := clean_id.get_slice(".", clean_id.get_slice_count(".") - 1)
	return leaf.replace("_", " ").capitalize() if not leaf.is_empty() else "Unknown Item"


func get_item_profile(item_key: String) -> Dictionary:
	var clean_key := item_key.strip_edges()
	var definition := _definition_by_item_id.get(clean_key) as ItemDefinition
	if definition == null and clean_key.begins_with("res://"):
		definition = _definition(clean_key)
	if definition == null:
		return {}
	return {
		"item_id": _item_id(definition),
		"display_name": definition.display_name,
		"food_type_id": definition.food_type_id,
		"food_units_per_item": definition.settlement_food_units,
		"is_food": not definition.food_type_id.is_empty() and definition.settlement_food_units > 0.0,
	}


func normalize_item_counts(item_counts: Dictionary) -> Dictionary:
	var normalized: Dictionary = {}
	for item_key in item_counts:
		var profile := get_item_profile(str(item_key))
		if profile.is_empty():
			continue
		var item_id := str(profile.get("item_id", ""))
		normalized[item_id] = int(normalized.get(item_id, 0)) + int(item_counts[item_key])
	return normalized


func ensure_seeded_container(settlement_id: String, seed: Resource) -> bool:
	var container_id := str(seed.get("container_id")).strip_edges() if seed != null else ""
	if settlement_id.is_empty() or seed == null or container_id.is_empty():
		return false
	if _containers_by_id.has(container_id):
		return true
	var entity = _entity_script.new()
	entity.name = "Inventory_%x" % container_id.hash()
	entity.id = "inventory:%s" % container_id
	var component = _container_component_script.new()
	component.container_id = container_id
	component.settlement_id = settlement_id
	component.facility_id = str(seed.get("facility_id"))
	component.container_kind = str(seed.get("container_kind"))
	component.contributes_to_town_stock = bool(seed.get("contributes_to_town_stock"))
	component.columns = int(seed.get("columns"))
	component.rows = int(seed.get("rows"))
	component.max_weight = float(seed.get("max_weight"))
	component.accepts_input = true
	component.is_world_container = true
	_gecs_world.world.add_entity(entity, [component])
	_gecs_world.register_inventory_container_entity(container_id, entity)
	_index_container(entity, component)
	var sequence := 1
	for stack_seed in Array(seed.get("stacks")):
		var item := stack_seed.get("item") as ItemDefinition if stack_seed != null else null
		var count := int(stack_seed.get("count")) if stack_seed != null else 0
		if stack_seed == null or item == null or count <= 0:
			continue
		var stack_id: String = str(stack_seed.get("stack_id")).strip_edges()
		if stack_id.is_empty():
			stack_id = "%s.stack.%d" % [container_id, sequence]
		sequence += 1
		_create_stack(container_id, stack_id, item, count, Vector2i(sequence - 2, 0))
	component.next_stack_sequence = sequence
	_add_container_aggregate(container_id)
	return true


func get_total_food_units(settlement_id: String) -> float:
	var units := 0.0
	for value in (get_settlement_stock_snapshot(settlement_id).get("food_units", {}) as Dictionary).values():
		units += float(value)
	return units


func prime_item_definition_paths(paths: PackedStringArray) -> void:
	for path in paths:
		_definition(path)


func consume_food_units(settlement_id: String, requested_units: float, facility_id := "") -> Dictionary:
	var result := {"food_units": 0.0, "items": {}}
	if requested_units <= 0.0:
		return result
	var plans: Dictionary = {}
	for container_id in _eligible_container_ids(settlement_id, facility_id):
		var inventory := _inventory_from_gecs(container_id)
		var entries: Array = inventory.entries.duplicate()
		entries.sort_custom(func(left, right): return str(left.stack_id) < str(right.stack_id))
		for entry in entries:
			if float(result["food_units"]) >= requested_units:
				break
			var units_per_item := float(entry.definition.settlement_food_units)
			if units_per_item <= 0.0 or str(entry.definition.food_type_id).is_empty():
				continue
			var needed := int(ceil((requested_units - float(result["food_units"])) / units_per_item))
			var removed: int = mini(needed, entry.count)
			entry.count -= removed
			if entry.count <= 0:
				inventory.entries.erase(entry)
			var path: String = entry.definition.resource_path
			result["items"][path] = int(result["items"].get(path, 0)) + removed
			result["food_units"] = float(result["food_units"]) + units_per_item * removed
		if plans.has(container_id) or float(result["food_units"]) > 0.0:
			plans[container_id] = inventory
		if float(result["food_units"]) >= requested_units:
			break
	if plans.is_empty():
		return result
	for container_id in plans:
		_commit_container_inventory(str(container_id), plans[container_id])
	stock_changed.emit(settlement_id, facility_id)
	return result


func add_production_outputs(settlement_id: String, outputs: Array, facility_id := "") -> Dictionary:
	var item_counts: Dictionary = {}
	for output in outputs:
		if output == null:
			continue
		var definition := output.get("item") as ItemDefinition
		if definition == null and output is Dictionary:
			definition = _definition_by_path.get(str(output.get("item_definition_path", ""))) as ItemDefinition
		var count := int(output.get("count"))
		if definition != null and count > 0:
			_definition_by_path[definition.resource_path] = definition
			item_counts[definition.resource_path] = int(item_counts.get(definition.resource_path, 0)) + count
	return add_item_counts(settlement_id, item_counts, facility_id)


func add_item_counts(settlement_id: String, item_counts: Dictionary, facility_id := "") -> Dictionary:
	var added := {"food_units": 0.0, "items": {}}
	var container_ids := _eligible_container_ids(settlement_id, facility_id)
	if container_ids.is_empty():
		return added
	var plans: Dictionary = {}
	for path_value in item_counts.keys():
		var definition := _definition_by_path.get(str(path_value)) as ItemDefinition
		var remaining := int(item_counts[path_value])
		if definition == null or remaining <= 0:
			continue
		for container_id in container_ids:
			var inventory: InventoryData = plans.get(container_id, _inventory_from_gecs(container_id))
			var accepted := _maximum_add_count(inventory, definition, remaining)
			if accepted <= 0:
				continue
			inventory.add_item_count(definition, accepted)
			plans[container_id] = inventory
			remaining -= accepted
			if remaining == 0:
				break
		if remaining > 0:
			return {"food_units": 0.0, "items": {}}
		added["items"][definition.resource_path] = int(item_counts[path_value])
		added["food_units"] = float(added["food_units"]) + definition.settlement_food_units * int(item_counts[path_value])
	if plans.is_empty():
		return added
	for container_id in plans:
		_commit_container_inventory(str(container_id), plans[container_id])
	stock_changed.emit(settlement_id, facility_id)
	return added


func transfer_food_units(source_settlement_id: String, target_settlement_id: String, requested_units: float) -> Dictionary:
	var removed := consume_food_units(source_settlement_id, requested_units)
	if (removed["items"] as Dictionary).is_empty():
		return removed
	var added := add_item_counts(target_settlement_id, removed["items"])
	if added["items"] != removed["items"]:
		# Restore the source if the receiving granary cannot accept the complete haul.
		add_item_counts(source_settlement_id, removed["items"])
		return {"food_units": 0.0, "items": {}}
	return removed


## Positive counts add stock; negative counts remove stock. Planning happens on
## detached InventoryData copies, so no GECS component changes until the full
## request has passed capacity/availability checks.
func transact_item_count(settlement_id: String, definition: ItemDefinition, count_delta: int, facility_id := "") -> bool:
	if settlement_id.is_empty() or definition == null or count_delta == 0:
		return false
	if not definition.resource_path.is_empty():
		_definition_by_path[definition.resource_path] = definition
	var container_ids := _eligible_container_ids(settlement_id, facility_id)
	if container_ids.is_empty():
		return false
	var plans: Array[Dictionary] = []
	if count_delta > 0:
		var remaining_to_add := count_delta
		for container_id in container_ids:
			var inventory := _inventory_from_gecs(container_id)
			var accepted := _maximum_add_count(inventory, definition, remaining_to_add)
			if accepted <= 0:
				continue
			inventory.add_item_count(definition, accepted)
			plans.append({"container_id": container_id, "inventory": inventory})
			remaining_to_add -= accepted
			if remaining_to_add == 0:
				break
		if remaining_to_add > 0:
			return false
	else:
		var item_id := _item_id(definition)
		var stock := get_facility_stock_snapshot(facility_id) if not facility_id.is_empty() else get_settlement_stock_snapshot(settlement_id)
		if int((stock.get("items", {}) as Dictionary).get(item_id, 0)) < -count_delta:
			return false
		var remaining_to_remove := -count_delta
		for container_id in container_ids:
			var inventory := _inventory_from_gecs(container_id)
			var removed := _remove_from_inventory(inventory, item_id, remaining_to_remove)
			if removed <= 0:
				continue
			plans.append({"container_id": container_id, "inventory": inventory})
			remaining_to_remove -= removed
			if remaining_to_remove == 0:
				break
		if remaining_to_remove > 0:
			return false
	for plan in plans:
		_commit_container_inventory(str(plan["container_id"]), plan["inventory"])
	stock_changed.emit(settlement_id, facility_id)
	return true


func _inventory_from_gecs(container_id: String) -> InventoryData:
	var record := _containers_by_id[container_id] as Dictionary
	var component = record["component"]
	var inventory := InventoryData.new(int(component.columns), int(component.rows), float(component.max_weight), float(component.max_weight) > 0.0)
	inventory.configure_stack_allocator(container_id, _next_sequence_for_container(container_id, int(component.next_stack_sequence)))
	var stack_ids := (_stack_ids_by_container.get(container_id, {}) as Dictionary).keys()
	stack_ids.sort()
	for stack_id_value in stack_ids:
		var stack_record := _stacks_by_id.get(str(stack_id_value), {}) as Dictionary
		if stack_record.is_empty():
			continue
		var stack = stack_record["component"]
		var definition := _definition(str(stack.item_definition_path))
		if definition == null:
			continue
		inventory.entries.append(inventory.create_entry(
			definition,
			stack.grid_position,
			int(stack.count),
			stack.contained_item_counts,
			stack.metadata,
			str(stack.stack_id)
		))
	return inventory


func _maximum_add_count(inventory: InventoryData, definition: ItemDefinition, requested: int) -> int:
	var low := 0
	var high := requested
	while low < high:
		var middle := (low + high + 1) / 2
		if inventory.can_add_item_count(definition, middle):
			low = middle
		else:
			high = middle - 1
	return low


func _remove_from_inventory(inventory: InventoryData, item_id: String, amount: int) -> int:
	var matching_entries: Array = []
	for entry in inventory.entries:
		if entry != null and entry.definition != null and _item_id(entry.definition) == item_id:
			matching_entries.append(entry)
	matching_entries.sort_custom(func(left, right): return str(left.stack_id) < str(right.stack_id))
	var remaining := amount
	for entry in matching_entries:
		var removed: int = mini(remaining, entry.count)
		entry.count -= removed
		remaining -= removed
		if entry.count <= 0:
			inventory.entries.erase(entry)
		if remaining == 0:
			break
	return amount - remaining


func _commit_container_inventory(container_id: String, inventory: InventoryData) -> void:
	var record := _containers_by_id[container_id] as Dictionary
	var container_component = record["component"]
	var stale_stack_ids := (_stack_ids_by_container.get(container_id, {}) as Dictionary).duplicate()
	_remove_indexed_container(container_id)
	container_component.next_stack_sequence = inventory.next_stack_sequence
	_index_container(record["entity"], container_component)
	for entry in inventory.entries:
		stale_stack_ids.erase(entry.stack_id)
		_gecs_world.upsert_item_stack_record({
			"stack_id": entry.stack_id,
			"container_id": container_id,
			"owner_actor_id": "",
			"item_definition_path": entry.definition.resource_path,
			"count": entry.count,
			"grid_position": entry.grid_position,
			"contained_item_counts": entry.contained_item_counts,
			"metadata": entry.metadata,
			"location_kind": "inventory",
		})
		var entity = _gecs_world.get_item_stack_entity(entry.stack_id)
		var component = entity.get_component(_stack_component_script) if entity != null and is_instance_valid(entity) else null
		if component == null:
			continue
		_index_stack(entity, component)
	for stack_id_value in stale_stack_ids.keys():
		_gecs_world.remove_item_stack_entity(str(stack_id_value))
	_add_container_aggregate(container_id)
	_hydrate_live_projection(container_id)


func _create_stack(container_id: String, stack_id: String, definition: ItemDefinition, count: int, grid_position: Vector2i) -> void:
	var entity = _entity_script.new()
	entity.name = "InventoryStack_%x" % stack_id.hash()
	entity.id = "item_stack:%s" % stack_id
	var component = _stack_component_script.new()
	component.stack_id = stack_id
	component.container_id = container_id
	component.item_definition_path = definition.resource_path
	component.count = count
	component.grid_position = grid_position
	_gecs_world.world.add_entity(entity, [component])
	_gecs_world.register_item_stack_entity(stack_id, entity)
	_index_stack(entity, component)


func _index_container(entity, component) -> void:
	var container_id := str(component.container_id)
	_containers_by_id[container_id] = {"entity": entity, "component": component}
	_stack_ids_by_container[container_id] = {}
	if not bool(component.contributes_to_town_stock):
		return
	_add_to_scope_index(_container_ids_by_settlement, str(component.settlement_id), container_id)
	_add_to_scope_index(_container_ids_by_facility, str(component.facility_id), container_id)


func _index_stack(entity, component) -> void:
	var stack_id := str(component.stack_id)
	var container_id := str(component.container_id)
	_stacks_by_id[stack_id] = {"entity": entity, "component": component}
	var stack_ids := _stack_ids_by_container.get(container_id, {}) as Dictionary
	stack_ids[stack_id] = true
	_stack_ids_by_container[container_id] = stack_ids


func _remove_indexed_container(container_id: String) -> void:
	if not _containers_by_id.has(container_id):
		return
	_remove_container_aggregate(container_id)
	var component = (_containers_by_id[container_id] as Dictionary)["component"]
	_remove_from_scope_index(_container_ids_by_settlement, str(component.settlement_id), container_id)
	_remove_from_scope_index(_container_ids_by_facility, str(component.facility_id), container_id)
	for stack_id in (_stack_ids_by_container.get(container_id, {}) as Dictionary).keys():
		_stacks_by_id.erase(str(stack_id))
	_stack_ids_by_container.erase(container_id)
	_containers_by_id.erase(container_id)


func _eligible_container_ids(settlement_id: String, facility_id: String) -> Array[String]:
	var source: Dictionary = _container_ids_by_facility.get(facility_id, {}) if not facility_id.is_empty() else _container_ids_by_settlement.get(settlement_id, {})
	var result: Array[String] = []
	for container_id_value in (source as Dictionary).keys():
		var container_id := str(container_id_value)
		var record := _containers_by_id.get(container_id, {}) as Dictionary
		if not record.is_empty() and bool(record["component"].accepts_input) and str(record["component"].settlement_id) == settlement_id:
			result.append(container_id)
	result.sort()
	return result


func _hydrate_live_projection(container_id: String) -> void:
	var projection_ref := _live_projection_by_container_id.get(container_id) as WeakRef
	var container := projection_ref.get_ref() as Node if projection_ref != null else null
	if container == null or not is_instance_valid(container) or not _containers_by_id.has(container_id):
		if container == null:
			_live_projection_by_container_id.erase(container_id)
		return
	var snapshots: Array = []
	var stack_ids := (_stack_ids_by_container.get(container_id, {}) as Dictionary).keys()
	stack_ids.sort()
	for stack_id in stack_ids:
		var component = (_stacks_by_id[str(stack_id)] as Dictionary)["component"]
		snapshots.append({
			"stack_id": str(component.stack_id),
			"item_definition_path": str(component.item_definition_path),
			"definition": _definition(str(component.item_definition_path)),
			"count": int(component.count),
			"grid_position": component.grid_position,
			"contained_item_counts": component.contained_item_counts.duplicate(true),
			"metadata": component.metadata.duplicate(true),
		})
	var component = (_containers_by_id[container_id] as Dictionary)["component"]
	if container.has_method("hydrate_storage_policy_from_gecs"):
		container.call(
			"hydrate_storage_policy_from_gecs",
			bool(component.storage_allow_food),
			bool(component.storage_allow_materials),
			component.storage_item_overrides
		)
	container.call("hydrate_inventory_from_gecs", snapshots, _next_sequence_for_container(container_id, int(component.next_stack_sequence)))


func _add_container_aggregate(container_id: String) -> void:
	var record := _containers_by_id.get(container_id, {}) as Dictionary
	if record.is_empty() or not bool(record["component"].contributes_to_town_stock):
		return
	var contribution := _container_contribution(container_id)
	record["contribution"] = contribution
	var component = record["component"]
	_apply_contribution(_settlement_stock, str(component.settlement_id), contribution, 1)
	if not str(component.facility_id).is_empty():
		_apply_contribution(_facility_stock, str(component.facility_id), contribution, 1)


func _remove_container_aggregate(container_id: String) -> void:
	var record := _containers_by_id.get(container_id, {}) as Dictionary
	var contribution := record.get("contribution", {}) as Dictionary
	if contribution.is_empty():
		return
	var component = record["component"]
	_apply_contribution(_settlement_stock, str(component.settlement_id), contribution, -1)
	if not str(component.facility_id).is_empty():
		_apply_contribution(_facility_stock, str(component.facility_id), contribution, -1)


func _container_contribution(container_id: String) -> Dictionary:
	var result := {"items": {}, "food_types": {}, "food_units": {}}
	for stack_id in (_stack_ids_by_container.get(container_id, {}) as Dictionary).keys():
		var stack = (_stacks_by_id[str(stack_id)] as Dictionary)["component"]
		var definition := _definition(str(stack.item_definition_path))
		if definition == null:
			continue
		var item_id := _item_id(definition)
		_add_count(result["items"], item_id, int(stack.count))
		var food_type_id := definition.food_type_id.strip_edges()
		if not food_type_id.is_empty() and definition.settlement_food_units > 0.0:
			_add_count(result["food_types"], food_type_id, int(stack.count))
			_add_float(result["food_units"], food_type_id, definition.settlement_food_units * int(stack.count))
	return result


func _apply_contribution(index: Dictionary, scope_id: String, contribution: Dictionary, direction: int) -> void:
	if scope_id.is_empty():
		return
	var aggregate := index.get(scope_id, {"items": {}, "food_types": {}, "food_units": {}}) as Dictionary
	for key in (contribution["items"] as Dictionary).keys():
		_add_count(aggregate["items"], str(key), int(contribution["items"][key]) * direction)
	for key in (contribution["food_types"] as Dictionary).keys():
		_add_count(aggregate["food_types"], str(key), int(contribution["food_types"][key]) * direction)
	for key in (contribution["food_units"] as Dictionary).keys():
		_add_float(aggregate["food_units"], str(key), float(contribution["food_units"][key]) * direction)
	if (aggregate["items"] as Dictionary).is_empty():
		index.erase(scope_id)
	else:
		index[scope_id] = aggregate


func _add_to_scope_index(index: Dictionary, scope_id: String, container_id: String) -> void:
	if scope_id.is_empty():
		return
	var ids := index.get(scope_id, {}) as Dictionary
	ids[container_id] = true
	index[scope_id] = ids


func _remove_from_scope_index(index: Dictionary, scope_id: String, container_id: String) -> void:
	var ids := index.get(scope_id, {}) as Dictionary
	ids.erase(container_id)
	if ids.is_empty():
		index.erase(scope_id)


func _next_sequence_for_container(container_id: String, stored_sequence: int) -> int:
	var next_sequence := maxi(1, stored_sequence)
	var prefix := "%s.stack." % container_id
	for stack_id_value in (_stack_ids_by_container.get(container_id, {}) as Dictionary).keys():
		var stack_id := str(stack_id_value)
		if stack_id.begins_with(prefix):
			next_sequence = maxi(next_sequence, int(stack_id.trim_prefix(prefix)) + 1)
	return next_sequence


func _definition(path: String) -> ItemDefinition:
	if path.is_empty():
		return null
	if _definition_by_path.has(path):
		var cached := _definition_by_path[path] as ItemDefinition
		_index_definition_display_name(cached)
		return cached
	var definition := load(path) as ItemDefinition
	if definition != null:
		_definition_by_path[path] = definition
		_index_definition_display_name(definition)
	return definition


func _index_definition_display_name(definition: ItemDefinition) -> void:
	if definition == null:
		return
	var item_id := _item_id(definition)
	if not item_id.is_empty():
		_definition_by_item_id[item_id] = definition
		_display_name_by_item_id[item_id] = definition.display_name


func _item_id(definition: ItemDefinition) -> String:
	var authored_id := definition.item_id.strip_edges()
	return authored_id if not authored_id.is_empty() else definition.resource_path


func _add_count(target: Dictionary, key: String, delta: int) -> void:
	var next := int(target.get(key, 0)) + delta
	if next == 0:
		target.erase(key)
	else:
		target[key] = next


func _add_float(target: Dictionary, key: String, delta: float) -> void:
	var next := float(target.get(key, 0.0)) + delta
	if is_zero_approx(next):
		target.erase(key)
	else:
		target[key] = next
