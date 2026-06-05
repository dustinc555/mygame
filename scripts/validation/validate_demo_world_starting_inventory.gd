extends SceneTree

const DEMO_WORLD_SCENE := preload("res://scenes/worlds/demo_world/demo_world.tscn")
const TABLE_FORK_ITEM := preload("res://resources/items/table_fork.tres")
const TABLE_KNIFE_ITEM := preload("res://resources/items/table_knife.tres")
const TABLE_SPOON_ITEM := preload("res://resources/items/table_spoon.tres")

const MIN_EQUIPPED_UTENSIL_LONG_AXIS := 0.18

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := DEMO_WORLD_SCENE.instantiate()
	scene.set("auto_open_character_creator", false)
	scene.set("auto_spawn_default_character", false)
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var member = scene.call("spawn_default_character") as HumanoidCharacter
	await process_frame
	if member == null:
		_fail("Demo world should spawn a default character")
	else:
		_validate_item_entry(member, TABLE_FORK_ITEM, "Fork")
		_validate_item_entry(member, TABLE_KNIFE_ITEM, "Table Knife")
		_validate_item_entry(member, TABLE_SPOON_ITEM, "Spoon")
		_validate_equipped_utensil_visual(member, TABLE_FORK_ITEM, "Fork")
		_validate_equipped_utensil_visual(member, TABLE_KNIFE_ITEM, "Table Knife")
		_validate_equipped_utensil_visual(member, TABLE_SPOON_ITEM, "Spoon")
	if _failures.is_empty():
		print("DEMO_WORLD_STARTING_INVENTORY_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("DEMO_WORLD_STARTING_INVENTORY_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_item_entry(member: HumanoidCharacter, item_definition: ItemDefinition, item_name: String) -> void:
	if member.inventory == null:
		_fail("Spawned character should have inventory data")
		return
	var matching_entries := 0
	var total_count := 0
	for entry in member.inventory.entries:
		if entry.definition != item_definition:
			continue
		matching_entries += 1
		total_count += int(entry.count)
		if int(entry.count) != 1:
			_fail("%s should be a one-count non-stack entry, got count=%d" % [item_name, int(entry.count)])
	if matching_entries != 1 or total_count != 1:
		_fail("Spawned character should start with exactly one %s, got entries=%d total=%d" % [item_name, matching_entries, total_count])


func _validate_equipped_utensil_visual(member: HumanoidCharacter, item_definition: ItemDefinition, item_name: String) -> void:
	member.equip_item_to_slot(item_definition, ItemDefinition.EQUIP_SLOT_WEAPON)
	if member.get_equipped_item(ItemDefinition.EQUIP_SLOT_WEAPON) != item_definition:
		_fail("%s should equip into the weapon slot" % item_name)
		return
	var weapon_visual := _find_node_by_name(member, "EquippedWeaponVisual")
	if weapon_visual == null:
		_fail("%s should create an EquippedWeaponVisual node" % item_name)
		return
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(weapon_visual, meshes)
	if meshes.is_empty():
		_fail("%s equipped visual should contain a MeshInstance3D" % item_name)
		return
	var longest_axis := 0.0
	for mesh in meshes:
		if not mesh.visible or mesh.mesh == null:
			continue
		var bounds := _mesh_global_bounds(mesh)
		longest_axis = maxf(longest_axis, maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)))
	if longest_axis < MIN_EQUIPPED_UTENSIL_LONG_AXIS:
		_fail("%s equipped visual should be visible-sized, longest axis %.3f" % [item_name, longest_axis])


func _find_node_by_name(root_node: Node, node_name: String) -> Node:
	if root_node.name == node_name:
		return root_node
	for child in root_node.get_children():
		var found := _find_node_by_name(child, node_name)
		if found != null:
			return found
	return null


func _collect_mesh_instances(root_node: Node, result: Array[MeshInstance3D]) -> void:
	if root_node is MeshInstance3D:
		result.append(root_node as MeshInstance3D)
	for child in root_node.get_children():
		_collect_mesh_instances(child, result)


func _mesh_global_bounds(mesh_instance: MeshInstance3D) -> AABB:
	if mesh_instance.mesh == null:
		return AABB(mesh_instance.global_position, Vector3.ZERO)
	var local := mesh_instance.mesh.get_aabb()
	var corners := [
		local.position,
		local.position + Vector3(local.size.x, 0.0, 0.0),
		local.position + Vector3(0.0, local.size.y, 0.0),
		local.position + Vector3(0.0, 0.0, local.size.z),
		local.position + Vector3(local.size.x, local.size.y, 0.0),
		local.position + Vector3(local.size.x, 0.0, local.size.z),
		local.position + Vector3(0.0, local.size.y, local.size.z),
		local.position + local.size,
	]
	var first: Vector3 = mesh_instance.global_transform * corners[0]
	var bounds := AABB(first, Vector3.ZERO)
	for index in range(1, corners.size()):
		bounds = bounds.expand(mesh_instance.global_transform * corners[index])
	return bounds


func _fail(message: String) -> void:
	_failures.append(message)
