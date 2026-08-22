@tool
extends WorldContainer

class_name BulkStoragePlatform

const CRATE_LABEL_SHADER = preload("res://features/world/projection/containers/displays/crate_label_projection.gdshader")
const CRATE_DISPLAY_SCENE = preload("res://features/world/projection/containers/displays/produce_crate_display_unit.tscn")
const AUTOMATIC_HAUL_RADIUS := 30.0

const FOOD_ITEM_PATHS := [
	"res://features/inventory/resources/items/tomato.tres",
	"res://features/inventory/resources/items/chili_pepper.tres",
	"res://features/inventory/resources/items/eggplant.tres",
	"res://features/inventory/resources/items/bell_pepper.tres",
	"res://features/inventory/resources/items/french_beans.tres",
]
const MATERIAL_ITEM_PATHS := [
	"res://features/inventory/resources/items/copper_ore.tres",
	"res://features/inventory/resources/items/copper_wire.tres",
	"res://features/inventory/resources/items/scrap_metal.tres",
	"res://features/inventory/resources/items/robot_parts.tres",
	"res://features/inventory/resources/items/broken_electronics.tres",
	"res://features/inventory/resources/items/rusted_junk.tres",
]
const DEPOSIT_ITEM_LABELS := {
	"food.tomato": "Tomatoes",
	"food.chili_pepper": "Chili Peppers",
	"food.eggplant": "Eggplants",
	"food.bell_pepper": "Bell Peppers",
	"food.french_beans": "French Beans",
}


@export var display_surface_height := 0.285:
	set(value):
		display_surface_height = value
		_queue_display_rebuild()
@export var display_profiles: Array[Resource] = []:
	set(value):
		display_profiles = value
		_queue_display_rebuild()
@export var storage_allow_food := true
@export var storage_allow_materials := false
@export var storage_item_overrides: Dictionary = {}

var _displayed_item_count := 0
var _display_positions: Array[Vector3] = []
var _display_rebuild_queued := false
var _pending_deposits: Dictionary = {}
var _haul_reservations: Dictionary = {}
var _haul_provider: Node

@onready var display_root: Node3D = $DisplayRoot


func _ready() -> void:
	add_to_group(BootstrapContext.SERVICE_CONSUMER_GROUP)
	if not Engine.is_editor_hint():
		_ensure_material_profiles()
	is_locked = false
	super._ready()
	if not inventory_changed.is_connected(_queue_display_rebuild):
		inventory_changed.connect(_queue_display_rebuild)
	_queue_display_rebuild()
	if not Engine.is_editor_hint() and BootstrapContext.active != null:
		_on_bootstrap_context_ready(BootstrapContext.active)


func _exit_tree() -> void:
	if _haul_provider != null and is_instance_valid(_haul_provider) and _haul_provider.has_method("unregister_platform"):
		_haul_provider.call("unregister_platform", self)
	_haul_provider = null
	super._exit_tree()


func _on_bootstrap_context_ready(context: BootstrapContext) -> void:
	if Engine.is_editor_hint() or context == null:
		return
	var provider := context.get_optional(&"bulk_storage_haul")
	if provider == _haul_provider:
		return
	if _haul_provider != null and is_instance_valid(_haul_provider) and _haul_provider.has_method("unregister_platform"):
		_haul_provider.call("unregister_platform", self)
	if provider != null and provider.has_method("register_platform"):
		provider.call("register_platform", self)


func bind_haul_provider(provider: Node) -> void:
	_haul_provider = provider


func unbind_haul_provider(provider: Node) -> void:
	if _haul_provider == provider:
		_haul_provider = null


func _configure_inventory_admission() -> void:
	if inventory != null and inventory.has_method("set_admission_validator"):
		inventory.call("set_admission_validator", Callable(self, "can_accept_item_count"))
	if inventory != null and inventory.has_method("set_stack_limit_resolver"):
		inventory.call("set_stack_limit_resolver", Callable(self, "get_storage_stack_limit"))


func can_accept_item_count(definition: ItemDefinition, amount: int) -> bool:
	return can_pack_item_count(definition, amount)


func get_storage_stack_limit(definition: ItemDefinition) -> int:
	var profile := _profile_for_definition(definition)
	return maxi(1, int(profile.get("units_per_visual"))) if profile != null else 1


func can_pack_item_count(definition: ItemDefinition, amount: int) -> bool:
	if definition == null or amount <= 0:
		return false
	var profile := _profile_for_definition(definition)
	if profile == null:
		return false
	if not is_storage_item_enabled(definition):
		return false
	var active_profile := _active_profile()
	if active_profile != null and active_profile != profile:
		return false
	var reserved_profile := _reserved_profile()
	if active_profile == null and reserved_profile != null and reserved_profile != profile:
		return false
	if _profile_quantity(profile) + amount > int(profile.get("capacity")):
		return false
	return true


func deposit_item_count(definition: ItemDefinition, amount: int) -> bool:
	if not can_pack_item_count(definition, amount):
		return false
	return inventory.add_item_count(definition, amount)


func withdraw_item_count(definition: ItemDefinition, amount: int) -> bool:
	var profile := _profile_for_definition(definition)
	if profile == null or amount <= 0 or _profile_quantity(profile) < amount:
		return false
	return inventory.remove_item_count(definition, amount)


func get_stored_item_count(definition: ItemDefinition) -> int:
	return _profile_quantity(_profile_for_definition(definition))


func can_receive_inventory_entry(entry) -> bool:
	return can_receive_inventory_entry_with_metadata(entry, entry.metadata if entry != null else {})


func can_receive_inventory_entry_with_metadata(entry, metadata: Dictionary) -> bool:
	return (
		entry != null
		and entry.definition != null
		and int(entry.count) > 0
		and entry.contained_item_counts.is_empty()
		and can_pack_item_count(entry.definition, int(entry.count))
		and inventory.can_add_item_count_with_metadata(entry.definition, int(entry.count), metadata)
	)


func receive_inventory_entry(source_inventory, entry) -> bool:
	return receive_inventory_entry_with_metadata(source_inventory, entry, entry.metadata if entry != null else {})


func receive_inventory_entry_with_metadata(source_inventory, entry, metadata: Dictionary) -> bool:
	if source_inventory == null or not source_inventory.entries.has(entry) or not can_receive_inventory_entry_with_metadata(entry, metadata):
		return false
	var source_snapshot: Dictionary = source_inventory.call("_snapshot_standard_transaction")
	var target_snapshot: Dictionary = inventory.call("_snapshot_standard_transaction")
	source_inventory.entries.erase(entry)
	var added := bool(inventory.call("_add_standard_item_count", entry.definition, int(entry.count), false)) if metadata.is_empty() \
			else bool(inventory.call("_add_item_count_as_distinct_entries", entry.definition, int(entry.count), {}, metadata, false))
	if not added:
		source_inventory.call("_restore_standard_transaction", source_snapshot)
		inventory.call("_restore_standard_transaction", target_snapshot)
		return false
	source_inventory.changed.emit()
	inventory.changed.emit()
	return true


func receive_cursor_item(definition: ItemDefinition, amount: int, contained_item_counts: Dictionary = {}, metadata: Dictionary = {}) -> bool:
	if not can_receive_cursor_item(definition, amount, contained_item_counts, metadata):
		return false
	return inventory.add_item_count_with_metadata(definition, amount, metadata)


func can_receive_cursor_item(definition: ItemDefinition, amount: int, contained_item_counts: Dictionary = {}, metadata: Dictionary = {}) -> bool:
	return contained_item_counts.is_empty() and can_pack_item_count(definition, amount) \
			and inventory.can_add_item_count_with_metadata(definition, amount, metadata)


func get_world_context_actions(actor: Node = null) -> Array:
	if actor == null or actor.get("inventory") == null:
		return []
	var actions: Array = []
	var active_profile := _active_profile()
	var candidate_profiles: Array = [active_profile] if active_profile != null else display_profiles
	for profile in candidate_profiles:
		if profile == null:
			continue
		var item := profile.get("item_definition") as ItemDefinition
		if item == null or not is_storage_item_enabled(item):
			continue
		var carried := int(actor.inventory.count_item(item))
		var remaining_capacity := int(profile.get("capacity")) - _profile_quantity(profile)
		if carried <= 0 or remaining_capacity <= 0:
			continue
		actions.append({
			"key": "deposit_all|%d|%s" % [actor.get_instance_id(), _storage_item_key(item)],
			"label": "Deposit All %s" % _deposit_item_label(item),
		})
	return actions


func get_automatic_haul_offers(requested_settlement_id := "") -> Array:
	var offers: Array = []
	if not requested_settlement_id.is_empty() and settlement_id != requested_settlement_id:
		return offers
	for profile in _automatic_haul_profiles():
		var item := profile.get("item_definition") as ItemDefinition
		if item == null or not is_storage_item_enabled(item) or _remaining_unreserved_capacity(profile) <= 0:
			continue
		offers.append({
			"offer_id": "bulk_haul:%s:%s" % [container_id, _storage_item_key(item)],
			"category": "haul",
			"job_entry_id": "category:haul",
			"settlement_id": settlement_id,
			"owner_faction_id": "",
			"faction_neutral": true,
			"world_position": global_position,
			"urgency": 0.0,
			"platform": self,
			"item_path": item.resource_path,
		})
	return offers


func get_automatic_haul_offer(requested_settlement_id := "") -> Dictionary:
	var offers := get_automatic_haul_offers(requested_settlement_id)
	return offers[0] as Dictionary if not offers.is_empty() else {}


func can_actor_accept_automatic_haul(actor: Node, item_path: String) -> bool:
	if actor == null or not (actor is Node3D) or actor.get("inventory") == null or _haul_reservations.has(actor.get_instance_id()):
		return false
	if (actor as Node3D).global_position.distance_to(global_position) > AUTOMATIC_HAUL_RADIUS:
		return false
	var profile := _active_profile()
	var item := load(item_path) as ItemDefinition if not item_path.is_empty() and ResourceLoader.exists(item_path) else null
	if item == null:
		return false
	if profile == null:
		profile = _profile_for_definition(item)
	var reserved_profile := _reserved_profile()
	return profile != null and (reserved_profile == null or reserved_profile == profile) \
			and (_active_profile() == null or _active_profile() == profile) and is_storage_item_enabled(item) \
			and int(actor.inventory.count_item(item)) > 0 and _remaining_unreserved_capacity(profile) > 0


func begin_automatic_haul(actor: Node, item_path: String) -> bool:
	if not can_actor_accept_automatic_haul(actor, item_path) or not actor.has_method("assign_open_container"):
		return false
	var item := load(item_path) as ItemDefinition
	var profile := _profile_for_definition(item)
	var amount := mini(int(actor.inventory.count_item(item)), _remaining_unreserved_capacity(profile))
	if amount <= 0:
		return false
	var actor_key := actor.get_instance_id()
	actor.call("assign_open_container", self, false)
	_haul_reservations[actor_key] = {"item_path": item_path, "amount": amount}
	_pending_deposits[actor_key] = {
		"item_path": item_path,
		"max_amount": amount,
		"automatic": true,
	}
	_notify_haul_offer_changed()
	return true


func has_pending_automatic_haul(actor: Node) -> bool:
	if actor == null:
		return false
	var pending = _pending_deposits.get(actor.get_instance_id())
	return pending is Dictionary and bool((pending as Dictionary).get("automatic", false))


func cancel_pending_automatic_haul(actor: Node) -> void:
	if actor == null:
		return
	_clear_pending_deposit(actor.get_instance_id())


func cancel_pending_automatic_haul_by_actor_key(actor_key: int) -> void:
	_clear_pending_deposit(actor_key)


func perform_world_context_action(action_key: String, actors: Array) -> String:
	if not action_key.begins_with("deposit_all|"):
		return ""
	var parts := action_key.split("|", false, 2)
	if parts.size() != 3:
		return ""
	var actor_instance_id := int(parts[1])
	var item := _storage_item_from_key(str(parts[2]))
	if item == null:
		return ""
	for actor in actors:
		if actor == null or not is_instance_valid(actor) or actor.get_instance_id() != actor_instance_id:
			continue
		var valid_action := false
		for action in get_world_context_actions(actor):
			if str(action.get("key", "")) == action_key:
				valid_action = true
				break
		if not valid_action or not actor.has_method("assign_open_container"):
			return ""
		actor.call("assign_open_container", self)
		_pending_deposits[actor_instance_id] = {
			"item_path": item.resource_path,
			"max_amount": 0,
			"automatic": false,
		}
		return ""
	return ""


func resolve_pending_deposit(actor: Node) -> Dictionary:
	if actor == null:
		return {"handled": false, "amount": 0}
	var actor_instance_id := actor.get_instance_id()
	if not _pending_deposits.has(actor_instance_id):
		return {"handled": false, "amount": 0}
	var pending_value = _pending_deposits[actor_instance_id]
	var pending: Dictionary = pending_value as Dictionary if pending_value is Dictionary else {"item_path": str(pending_value)}
	var item_path := str(pending.get("item_path", ""))
	var max_amount := int(pending.get("max_amount", 0))
	_clear_pending_deposit(actor_instance_id)
	if item_path.is_empty() or not ResourceLoader.exists(item_path) or actor.get("inventory") == null:
		return {"handled": true, "amount": 0}
	var item := load(item_path) as ItemDefinition
	var profile := _profile_for_definition(item)
	if item == null or profile == null:
		return {"handled": true, "amount": 0}
	var carried := int(actor.inventory.count_item(item))
	var remaining_capacity := maxi(0, int(profile.get("capacity")) - _profile_quantity(profile))
	var amount := mini(carried, remaining_capacity)
	if max_amount > 0:
		amount = mini(amount, max_amount)
	if amount <= 0:
		return {"handled": true, "amount": 0}
	if not actor.inventory.transfer_item_count_to_preserving_metadata(item, amount, inventory):
		return {"handled": true, "amount": 0}
	return {"handled": true, "amount": amount, "item_name": _deposit_item_label(item)}


func release_interactor(member: HumanoidCharacter) -> void:
	super.release_interactor(member)
	if member != null:
		_clear_pending_deposit(member.get_instance_id())


func can_release_inventory_entry(entry, target_inventory) -> bool:
	return can_release_inventory_entry_with_metadata(entry, target_inventory, entry.metadata if entry != null else {})


func can_release_inventory_entry_with_metadata(entry, target_inventory, metadata: Dictionary) -> bool:
	return entry != null and target_inventory != null and entry.definition != null \
			and inventory.entries.has(entry) and int(entry.count) > 0 \
			and target_inventory.can_add_item_count_with_metadata(entry.definition, 1, metadata)


func release_inventory_entry(entry, target_inventory) -> bool:
	return release_inventory_entry_with_metadata(entry, target_inventory, entry.metadata if entry != null else {})


func release_inventory_entry_with_metadata(entry, target_inventory, metadata: Dictionary) -> bool:
	return release_inventory_entry_count_with_metadata(entry, target_inventory, 1, metadata) == 1


func release_inventory_entry_count_with_metadata(entry, target_inventory, requested_count: int, metadata: Dictionary) -> int:
	if entry == null or target_inventory == null or entry.definition == null or requested_count <= 0 \
			or not inventory.entries.has(entry):
		return 0
	var amount := int(target_inventory.call(
		"get_max_addable_item_count_with_metadata",
		entry.definition,
		mini(requested_count, int(entry.count)),
		metadata
	)) if target_inventory.has_method("get_max_addable_item_count_with_metadata") else 0
	if amount <= 0:
		return 0
	var source_snapshot: Dictionary = inventory.call("_snapshot_standard_transaction")
	var target_snapshot: Dictionary = target_inventory.call("_snapshot_standard_transaction")
	entry.count -= amount
	if entry.count <= 0:
		inventory.entries.erase(entry)
	var added := bool(target_inventory.call("add_prevalidated_item_count_with_metadata", entry.definition, amount, metadata, false)) \
			if target_inventory.has_method("add_prevalidated_item_count_with_metadata") else false
	if not added:
		inventory.call("_restore_standard_transaction", source_snapshot)
		target_inventory.call("_restore_standard_transaction", target_snapshot)
		return 0
	inventory.changed.emit()
	target_inventory.changed.emit()
	return amount


func get_inventory_transfer_count(_entry) -> int:
	return 1


func _seed_starting_inventory() -> void:
	for stock in starting_items:
		if stock != null and stock.item_definition != null and stock.quantity > 0:
			deposit_item_count(stock.item_definition, stock.quantity)


func _pack_item_count(definition: ItemDefinition, amount: int, emit_changed: bool) -> bool:
	return bool(inventory.call("_add_standard_item_count", definition, amount, emit_changed))


func _ensure_material_profiles() -> void:
	for item_path in MATERIAL_ITEM_PATHS:
		if not ResourceLoader.exists(item_path):
			continue
		var item := load(item_path) as ItemDefinition
		if item == null or _profile_for_definition(item) != null:
			continue
		var profile := BulkStorageDisplayProfile.new()
		profile.item_definition = item
		profile.unit_scene = CRATE_DISPLAY_SCENE
		profile.label_texture = item.icon
		profile.capacity = 600
		profile.units_per_visual = 20
		profile.spacing = Vector2(0.53, 0.3)
		profile.layer_height = 0.306
		profile.layer_columns = 2
		profile.layer_rows = 3
		profile.max_layers = 5
		display_profiles.append(profile)


func get_details_panel_data_at(_world_position: Vector3) -> Dictionary:
	return {
		"title": display_name,
		"subtitle": "",
		"detail": "",
		"state": "",
		"info_rows": [{"label": "Ownership", "value": get_owner_faction_name() if not get_owner_faction_name().is_empty() else "None"}],
	}


func get_details_panel_actions_at(_world_position: Vector3, actor: Node = null) -> Array:
	return [{
		"key": "storage_filter_menu",
		"label": "Set Storage Type",
		"disabled": not can_actor_edit_storage_policy(actor),
	}]


func can_actor_edit_storage_policy(actor: Node) -> bool:
	if actor == null:
		return false
	var explicit_owner := get_explicit_owner_character()
	if explicit_owner != null:
		return explicit_owner == actor
	var owner_faction := get_owner_faction_name()
	return not owner_faction.is_empty() and str(actor.get("faction_name")) == owner_faction


func get_storage_filter_options() -> Array:
	return [
		_storage_category_option("food", "Food", FOOD_ITEM_PATHS, storage_allow_food),
		_storage_category_option("materials", "Materials", MATERIAL_ITEM_PATHS, storage_allow_materials),
	]


func set_storage_category_enabled(category_id: String, enabled: bool, actor: Node) -> bool:
	if not can_actor_edit_storage_policy(actor):
		return false
	match category_id:
		"food":
			storage_allow_food = enabled
			_clear_category_overrides(FOOD_ITEM_PATHS)
		"materials":
			storage_allow_materials = enabled
			_clear_category_overrides(MATERIAL_ITEM_PATHS)
		_:
			return false
	_sync_inventory_to_gecs()
	_notify_haul_offer_changed()
	return true


func set_storage_item_enabled(item_key: String, enabled: bool, actor: Node) -> bool:
	if not can_actor_edit_storage_policy(actor):
		return false
	var item := _storage_item_from_key(item_key)
	if item == null:
		return false
	var category_default := storage_allow_food if FOOD_ITEM_PATHS.has(item.resource_path) else storage_allow_materials
	if enabled == category_default:
		storage_item_overrides.erase(item_key)
	else:
		storage_item_overrides[item_key] = enabled
	_sync_inventory_to_gecs()
	_notify_haul_offer_changed()
	return true


func is_storage_item_enabled(definition: ItemDefinition) -> bool:
	if definition == null:
		return false
	var key := _storage_item_key(definition)
	if storage_item_overrides.has(key):
		return bool(storage_item_overrides[key])
	if FOOD_ITEM_PATHS.has(definition.resource_path):
		return storage_allow_food
	if MATERIAL_ITEM_PATHS.has(definition.resource_path):
		return storage_allow_materials
	return false


func hydrate_storage_policy_from_gecs(food_enabled: bool, materials_enabled: bool, overrides: Dictionary) -> void:
	storage_allow_food = food_enabled
	storage_allow_materials = materials_enabled
	storage_item_overrides = overrides.duplicate(true)


func _storage_category_option(category_id: String, label: String, item_paths: Array, category_enabled: bool) -> Dictionary:
	var items: Array = []
	var enabled_count := 0
	for item_path in item_paths:
		if not ResourceLoader.exists(item_path):
			continue
		var item := load(item_path) as ItemDefinition
		if item == null:
			continue
		var enabled := is_storage_item_enabled(item)
		if enabled:
			enabled_count += 1
		items.append({"item_key": _storage_item_key(item), "label": item.display_name, "selected": enabled})
	return {
		"category_id": category_id,
		"label": label,
		"selected": not items.is_empty() and enabled_count == items.size(),
		"indeterminate": enabled_count > 0 and enabled_count < items.size(),
		"items": items,
	}


func _storage_item_key(definition: ItemDefinition) -> String:
	return definition.item_id if not definition.item_id.is_empty() else definition.resource_path


func _deposit_item_label(definition: ItemDefinition) -> String:
	return str(DEPOSIT_ITEM_LABELS.get(definition.item_id, definition.display_name))


func _storage_item_from_key(item_key: String) -> ItemDefinition:
	for item_path in FOOD_ITEM_PATHS + MATERIAL_ITEM_PATHS:
		var item := load(item_path) as ItemDefinition if ResourceLoader.exists(item_path) else null
		if item != null and _storage_item_key(item) == item_key:
			return item
	return null


func _clear_category_overrides(item_paths: Array) -> void:
	for item_path in item_paths:
		var item := load(item_path) as ItemDefinition if ResourceLoader.exists(item_path) else null
		if item != null:
			storage_item_overrides.erase(_storage_item_key(item))


func _queue_display_rebuild() -> void:
	if not is_inside_tree() or _display_rebuild_queued:
		return
	_display_rebuild_queued = true
	call_deferred("_rebuild_stock_display")


func _rebuild_stock_display() -> void:
	_display_rebuild_queued = false
	if display_root == null:
		return
	for child in display_root.get_children():
		display_root.remove_child(child)
		child.queue_free()
	_display_positions.clear()
	_displayed_item_count = 0
	if inventory == null:
		return
	var profile: Resource = _active_profile()
	if profile == null:
		return
	_displayed_item_count = _profile_quantity(profile)
	var representative_count := _profile_stack_count(profile)
	_display_positions = _build_display_positions(profile, representative_count)
	if bool(profile.call("uses_stacked_container_layout")):
		_rebuild_batched_container_display(profile)
	elif bool(profile.call("uses_batched_display")):
		_rebuild_batched_display(profile)
	else:
		_rebuild_scene_display(profile)


func _rebuild_scene_display(profile: Resource) -> void:
	var unit_scene := profile.get("unit_scene") as PackedScene
	if unit_scene == null:
		return
	for index in _display_positions.size():
		var unit := unit_scene.instantiate() as Node3D
		if unit == null:
			continue
		unit.name = "Stock%02d" % (index + 1)
		unit.position = _display_positions[index]
		unit.rotation.y = 0.0 if bool(profile.call("uses_stacked_container_layout")) else _stable_unit_yaw(index)
		display_root.add_child(unit)
		if unit.has_method("set_label_texture"):
			unit.call("set_label_texture", profile.get("label_texture") as Texture2D)


func _rebuild_batched_container_display(profile: Resource) -> void:
	var unit_scene := profile.get("unit_scene") as PackedScene
	var label_texture := profile.get("label_texture") as Texture2D
	if unit_scene == null or _display_positions.is_empty():
		return
	var template := unit_scene.instantiate() as Node3D
	if template == null:
		return
	var mesh_parts: Array[Dictionary] = []
	for child in template.get_children():
		_collect_template_mesh_parts(child, Transform3D.IDENTITY, mesh_parts)
	for index in mesh_parts.size():
		var part := mesh_parts[index]
		var node_name := "CrateMeshes" if index == 0 else "CrateMeshes%02d" % (index + 1)
		_add_container_multimesh(
			node_name,
			part["mesh"] as Mesh,
			part["material"] as Material,
			part["transform"] as Transform3D,
			label_texture
		)
	template.free()


func _collect_template_mesh_parts(node: Node, parent_transform: Transform3D, parts: Array[Dictionary]) -> void:
	var current_transform := parent_transform
	if node is Node3D:
		current_transform *= (node as Node3D).transform
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		if instance.mesh != null:
			parts.append({
				"mesh": instance.mesh,
				"material": instance.material_override,
				"transform": current_transform,
			})
	for child in node.get_children():
		_collect_template_mesh_parts(child, current_transform, parts)


func _add_container_multimesh(
	node_name: String,
	mesh: Mesh,
	material: Material,
	local_transform: Transform3D,
	label_texture: Texture2D
) -> void:
	if mesh == null:
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = _display_positions.size()
	for index in _display_positions.size():
		var unit_transform := Transform3D(Basis.IDENTITY, _display_positions[index])
		multimesh.set_instance_transform(index, unit_transform * local_transform)
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = _crate_projected_label_material(mesh, material, label_texture)
	display_root.add_child(instance)


func _crate_projected_label_material(mesh: Mesh, override_material: Material, label_texture: Texture2D) -> Material:
	var source_material := override_material as StandardMaterial3D
	if source_material == null and mesh.get_surface_count() > 0:
		source_material = mesh.surface_get_material(0) as StandardMaterial3D
	if label_texture == null:
		return source_material
	var material := ShaderMaterial.new()
	material.shader = CRATE_LABEL_SHADER
	if source_material != null:
		material.set_shader_parameter("base_color_texture", source_material.albedo_texture)
		material.set_shader_parameter("normal_texture", source_material.normal_texture)
		material.set_shader_parameter("orm_texture", source_material.metallic_texture)
	material.set_shader_parameter("label_texture", label_texture)
	return material


func _rebuild_batched_display(profile: Resource) -> void:
	var body_mesh := profile.get("body_mesh") as Mesh
	var body_material := profile.get("body_material") as Material
	var body_transform: Transform3D = profile.get("body_local_transform")
	_add_multimesh("Bodies", body_mesh, body_material, body_transform, 1)

	var stem_mesh := profile.get("stem_mesh") as Mesh
	var stem_material := profile.get("stem_material") as Material
	var stem_transform: Transform3D = profile.get("stem_local_transform")
	_add_multimesh("Stems", stem_mesh, stem_material, stem_transform, 1)

	var accent_mesh := profile.get("accent_mesh") as Mesh
	var accent_material := profile.get("accent_material") as Material
	var accent_transform: Transform3D = profile.get("accent_local_transform")
	var accents_per_unit := int(profile.get("accents_per_unit"))
	_add_multimesh("Accents", accent_mesh, accent_material, accent_transform, accents_per_unit)


func _add_multimesh(
	node_name: String,
	mesh: Mesh,
	material: Material,
	local_transform: Transform3D,
	instances_per_unit: int
) -> void:
	if mesh == null or _display_positions.is_empty():
		return
	var safe_instances_per_unit := maxi(1, instances_per_unit)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = _display_positions.size() * safe_instances_per_unit
	var instance_index := 0
	for unit_index in _display_positions.size():
		var unit_transform := Transform3D(
			Basis(Vector3.UP, _stable_unit_yaw(unit_index)),
			_display_positions[unit_index]
		)
		for sub_index in safe_instances_per_unit:
			var ring_rotation := TAU * float(sub_index) / float(safe_instances_per_unit)
			var sub_transform := Transform3D(Basis(Vector3.UP, ring_rotation), Vector3.ZERO)
			multimesh.set_instance_transform(instance_index, unit_transform * sub_transform * local_transform)
			instance_index += 1
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = material
	display_root.add_child(instance)


func _active_profile() -> Resource:
	for profile in display_profiles:
		var item_definition := profile.get("item_definition") as ItemDefinition if profile != null else null
		if profile == null or item_definition == null:
			continue
		if _profile_quantity(profile) > 0:
			return profile
	return null


func _automatic_haul_profiles() -> Array:
	var active := _active_profile()
	if active != null:
		return [active]
	var reserved := _reserved_profile()
	if reserved != null:
		return [reserved]
	var profiles: Array = []
	for profile in display_profiles:
		var item := profile.get("item_definition") as ItemDefinition if profile != null else null
		if item != null and is_storage_item_enabled(item):
			profiles.append(profile)
	return profiles


func _reserved_profile() -> Resource:
	for reservation_value in _haul_reservations.values():
		var reservation: Dictionary = reservation_value
		var item_path := str(reservation.get("item_path", ""))
		if not item_path.is_empty() and ResourceLoader.exists(item_path):
			var profile := _profile_for_definition(load(item_path) as ItemDefinition)
			if profile != null:
				return profile
	return null


func _profile_for_definition(definition: ItemDefinition) -> Resource:
	for profile in display_profiles:
		if profile != null and bool(profile.call("matches", definition)):
			return profile
	return null


func _profile_quantity(profile: Resource) -> int:
	var total := 0
	if profile == null or inventory == null:
		return total
	for entry in inventory.entries:
		if entry != null and bool(profile.call("matches", entry.definition)):
			total += int(entry.count)
	return total


func _profile_stack_count(profile: Resource) -> int:
	var total := 0
	if profile == null or inventory == null:
		return total
	for entry in inventory.entries:
		if entry != null and int(entry.count) > 0 and bool(profile.call("matches", entry.definition)):
			total += 1
	return total


func _remaining_unreserved_capacity(profile: Resource) -> int:
	if profile == null:
		return 0
	return maxi(0, int(profile.get("capacity")) - _profile_quantity(profile) - _reserved_quantity(profile))


func _reserved_quantity(profile: Resource) -> int:
	var total := 0
	if profile == null:
		return total
	for reservation_value in _haul_reservations.values():
		var reservation: Dictionary = reservation_value
		var item_path := str(reservation.get("item_path", ""))
		var item := load(item_path) as ItemDefinition if not item_path.is_empty() and ResourceLoader.exists(item_path) else null
		if item != null and bool(profile.call("matches", item)):
			total += maxi(0, int(reservation.get("amount", 0)))
	return total


func _clear_pending_deposit(actor_key: int) -> void:
	_pending_deposits.erase(actor_key)
	_haul_reservations.erase(actor_key)
	_notify_haul_offer_changed()


func _notify_haul_offer_changed() -> void:
	if _haul_provider != null and is_instance_valid(_haul_provider) and _haul_provider.has_method("notify_platform_changed"):
		_haul_provider.call("notify_platform_changed", self)


func _build_display_positions(profile: Resource, count: int) -> Array[Vector3]:
	if bool(profile.call("uses_stacked_container_layout")):
		return _build_stacked_container_positions(profile, count)
	var positions: Array[Vector3] = []
	var base_columns := int(profile.get("base_columns"))
	var base_rows := int(profile.get("base_rows"))
	var upper_columns := int(profile.get("upper_columns"))
	var upper_rows := int(profile.get("upper_rows"))
	var spacing: Vector2 = profile.get("spacing")
	var layer_height := float(profile.get("layer_height"))
	var base_capacity := base_columns * base_rows
	var base_count := mini(count, base_capacity)
	positions.append_array(_layer_positions(
		base_count,
		base_columns,
		spacing,
		display_surface_height
	))
	var upper_count := mini(maxi(0, count - base_count), upper_columns * upper_rows)
	positions.append_array(_layer_positions(
		upper_count,
		upper_columns,
		spacing,
		display_surface_height + layer_height
	))
	return positions


func _build_stacked_container_positions(profile: Resource, count: int) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	if count <= 0:
		return positions
	var columns := int(profile.get("layer_columns"))
	var rows := int(profile.get("layer_rows"))
	var max_layers := int(profile.get("max_layers"))
	var spacing: Vector2 = profile.get("spacing")
	var layer_height := float(profile.get("layer_height"))
	var layer_capacity := maxi(1, columns * rows)
	var remaining := count
	for layer in max_layers:
		if remaining <= 0:
			break
		var layer_count := mini(remaining, layer_capacity)
		positions.append_array(_layer_positions(
			layer_count,
			columns,
			spacing,
			display_surface_height + float(layer) * layer_height
		))
		remaining -= layer_count
	return positions


func _layer_positions(count: int, columns: int, spacing: Vector2, y: float) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	if count <= 0:
		return positions
	var row_count := ceili(float(count) / float(maxi(1, columns)))
	var remaining := count
	for row in row_count:
		var row_items := mini(columns, remaining)
		var start_x := -0.5 * float(row_items - 1) * spacing.x
		var z := (float(row_count - 1) * 0.5 - float(row)) * spacing.y
		for column in row_items:
			positions.append(Vector3(start_x + float(column) * spacing.x, y, z))
		remaining -= row_items
	return positions


func _stable_unit_yaw(index: int) -> float:
	const YAW_SEQUENCE := [0.0, 0.16, -0.12, 0.08, -0.18]
	return YAW_SEQUENCE[index % YAW_SEQUENCE.size()]


func get_displayed_item_count() -> int:
	return _displayed_item_count


func get_displayed_visual_count() -> int:
	return _display_positions.size()


func get_display_slot_positions() -> Array[Vector3]:
	return _display_positions.duplicate()
