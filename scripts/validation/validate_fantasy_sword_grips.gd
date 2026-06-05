extends SceneTree

const PARTY_MEMBER_SCENE := preload("res://scenes/characters/party_member.tscn")
const WORLD_ITEM_SCENE := preload("res://scenes/world/items/world_item.tscn")
const HUMAN_MALE_BODY_ARCHETYPE := preload("res://resources/character_body_archetypes/human_male.tres")
const HUMAN_FEMALE_BODY_ARCHETYPE := preload("res://resources/character_body_archetypes/human_female.tres")
const BRONZE_SWORD_ITEM := preload("res://resources/items/bronze_sword.tres")
const FANTASY_STEEL_SWORD_ITEM := preload("res://resources/items/fantasy_steel_sword.tres")

const MIN_HELD_SWORD_LONG_AXIS := 0.6
const MAX_HELD_SWORD_LONG_AXIS := 1.05
const WORLD_EQUIPPED_SIZE_TOLERANCE := 0.06

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var bronze_held_axes := [
		await _validate_held_sword(HUMAN_MALE_BODY_ARCHETYPE, "male", BRONZE_SWORD_ITEM, "Bronze Sword"),
		await _validate_held_sword(HUMAN_FEMALE_BODY_ARCHETYPE, "female", BRONZE_SWORD_ITEM, "Bronze Sword"),
	]
	await _validate_dropped_sword_size(BRONZE_SWORD_ITEM, "Bronze Sword", bronze_held_axes)
	var steel_held_axes := [
		await _validate_held_sword(HUMAN_MALE_BODY_ARCHETYPE, "male", FANTASY_STEEL_SWORD_ITEM, "Steel Sword"),
		await _validate_held_sword(HUMAN_FEMALE_BODY_ARCHETYPE, "female", FANTASY_STEEL_SWORD_ITEM, "Steel Sword"),
	]
	await _validate_dropped_sword_size(FANTASY_STEEL_SWORD_ITEM, "Steel Sword", steel_held_axes)
	if _failures.is_empty():
		print("FANTASY_SWORD_GRIPS_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("FANTASY_SWORD_GRIPS_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_held_sword(body_archetype: Resource, body_label: String, item_definition: ItemDefinition, item_name: String) -> float:
	var member := PARTY_MEMBER_SCENE.instantiate() as PartyMember
	if member == null:
		_fail("Could not instantiate PartyMember for %s %s validation" % [body_label, item_name])
		return 0.0
	member.name = "Validation_%s_%s" % [body_label, item_name.replace(" ", "")]
	member.member_name = body_label.capitalize()
	member.body_archetype = body_archetype
	member.starting_equipment = [item_definition]
	root.add_child(member)
	await process_frame
	await process_frame
	if member.get_equipped_item(ItemDefinition.EQUIP_SLOT_WEAPON) != item_definition:
		_fail("%s %s should equip into the weapon slot" % [body_label, item_name])
		member.queue_free()
		await process_frame
		return 0.0
	var weapon_visual := _find_node_by_name(member, "EquippedWeaponVisual")
	if weapon_visual == null:
		_fail("%s %s should create an EquippedWeaponVisual node" % [body_label, item_name])
		member.queue_free()
		await process_frame
		return 0.0
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(weapon_visual, meshes)
	if meshes.is_empty():
		_fail("%s %s equipped visual should contain a MeshInstance3D" % [body_label, item_name])
		member.queue_free()
		await process_frame
		return 0.0
	var longest_axis := 0.0
	for mesh in meshes:
		if not mesh.visible or mesh.mesh == null:
			continue
		var bounds := _mesh_global_bounds(mesh)
		longest_axis = maxf(longest_axis, maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)))
	if longest_axis < MIN_HELD_SWORD_LONG_AXIS or longest_axis > MAX_HELD_SWORD_LONG_AXIS:
		_fail("%s %s held visual should be full-sized, longest axis %.3f" % [body_label, item_name, longest_axis])
	member.queue_free()
	await process_frame
	return longest_axis


func _validate_dropped_sword_size(item_definition: ItemDefinition, item_name: String, held_axes: Array) -> void:
	var item := WORLD_ITEM_SCENE.instantiate() as WorldItem
	if item == null:
		_fail("Could not instantiate WorldItem for dropped %s validation" % item_name)
		return
	root.add_child(item)
	await process_frame
	item.setup(item_definition, 1)
	await process_frame
	var world_bounds := item.get_visual_world_bounds()
	var world_longest_axis := maxf(world_bounds.size.x, maxf(world_bounds.size.y, world_bounds.size.z))
	for held_axis in held_axes:
		var equipped_longest_axis := float(held_axis)
		if equipped_longest_axis <= 0.0:
			continue
		if absf(world_longest_axis - equipped_longest_axis) > WORLD_EQUIPPED_SIZE_TOLERANCE:
			_fail("Dropped %s should match equipped size, dropped %.3f equipped %.3f" % [item_name, world_longest_axis, equipped_longest_axis])
	item.queue_free()
	await process_frame


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
