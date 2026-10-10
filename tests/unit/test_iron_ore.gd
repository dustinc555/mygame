extends GutTest
## Iron content exercises the same deposit transaction and storage as other ore.
const ITEM_PATH := "res://features/inventory/resources/items/iron_ore.tres"
const NODE_PATH := "res://features/world/bridge/resource_nodes/iron_node.tscn"
const DEFINITION_PATH := "res://features/world/resources/resource_deposits/iron.tres"
const AUTHORING = preload("res://addons/world_authoring/resource_authoring.gd")

class Miner extends Node:
	var tool: ItemDefinition
	func get_skill_level(_skill: String) -> int:
		return 30
	func get_equipped_item(_slot: String) -> ItemDefinition:
		return tool

class Ledger extends Node:
	@warning_ignore("unused_signal")
	signal world_reindexed
	var states: Dictionary = {}
	func get_resource_deposit_states() -> Dictionary:
		return states.duplicate(true)
	func get_resource_deposit_state(id: String) -> Dictionary:
		return states.get(id, {}).duplicate(true)
	func upsert_resource_deposit_state(state: Dictionary) -> Dictionary:
		states[state.deposit_id] = state.duplicate(true)
		return state.duplicate(true)

var controller: ResourceDepositController

func after_each() -> void:
	if is_instance_valid(controller):
		controller.teardown()
	controller = null

func _item() -> ItemDefinition:
	assert_true(ResourceLoader.exists(ITEM_PATH), "Iron ore must exist as saved item content")
	return load(ITEM_PATH) as ItemDefinition if ResourceLoader.exists(ITEM_PATH) else null

func _vein() -> MiningResourceNode:
	assert_true(ResourceLoader.exists(NODE_PATH), "Iron needs a reusable vein scene")
	if not ResourceLoader.exists(NODE_PATH):
		return null
	return autofree(load(NODE_PATH).instantiate()) as MiningResourceNode

func _bind(vein: MiningResourceNode) -> void:
	var ledger: Ledger = add_child_autofree(Ledger.new())
	var clock: WorldTimeController = add_child_autofree(WorldTimeController.new())
	clock.set_process(false)
	controller = add_child_autofree(ResourceDepositController.new())
	var context := BootstrapContext.new(self)
	context.register(&"gecs_world", ledger)
	context.register(&"world_time", clock)
	context.register(&"resource_deposits", controller)
	controller.initialize(context)
	controller._reconcile_after_load()
	vein.resource_node_id = "unit.iron"
	vein._on_bootstrap_context_ready(context)

func _miner() -> Miner:
	var miner: Miner = add_child_autofree(Miner.new())
	miner.tool = load("res://features/inventory/resources/items/rusted_pickaxe.tres")
	return miner

func test_iron_item_has_real_art_and_copper_sized_inventory_contract() -> void:
	var item := _item()
	if item == null:
		return
	assert_eq(item.display_name, "Iron Ore")
	assert_eq(item.grid_size, Vector2i(3, 2))
	assert_eq(item.unit_weight, 4.0)
	assert_not_null(item.icon)
	assert_not_null(item.world_scene)
	assert_eq(item.world_visual_height_meters, 0.14)
	if item.world_scene != null:
		var model: Node = autofree(item.world_scene.instantiate())
		assert_gt(model.find_children("*", "MeshInstance3D", true, false).size(), 0)
	var bag := InventoryData.new(3, 2, 60.0, false)
	assert_true(bag.add_item_count(item, 1))
	assert_false(bag.add_item_count(item, 1), "Ore retains its full footprint")

func test_catalog_discovers_iron_and_scene_has_its_own_definition() -> void:
	var vein := _vein()
	if vein == null:
		return
	assert_eq(vein.deposit_definition.resource_path, DEFINITION_PATH)
	assert_eq(vein.deposit_definition.deposit_type_id, "iron")
	assert_eq(vein.item_definition, _item())
	assert_true(vein.deposit_definition.validation_errors().is_empty())
	var matches := 0
	for definition in AUTHORING.load_catalog():
		if definition.deposit_type_id == "iron":
			matches += 1
			assert_eq(definition.scene_path, NODE_PATH)
	assert_eq(matches, 1)

func test_mining_delivers_iron_and_debits_only_its_own_stock() -> void:
	var vein := _vein()
	if vein == null:
		return
	_bind(vein)
	var before := vein.get_stock()
	var bag := InventoryData.new(6, 2, 60.0, false)
	assert_true(vein.complete_mining_attempt(_miner(), bag).get("success", false))
	assert_eq(bag.count_item(_item()), 1)
	assert_eq(bag.count_item(load("res://features/inventory/resources/items/copper_ore.tres")), 0)
	assert_eq(vein.get_stock(), before - 1)

func test_full_bag_and_missing_pickaxe_preserve_stock() -> void:
	var vein := _vein()
	if vein == null:
		return
	_bind(vein)
	var before := vein.get_stock()
	var miner := _miner()
	var small_bag := InventoryData.new(1, 1, 60.0, false)
	assert_false(vein.complete_mining_attempt(miner, small_bag).get("success", false))
	assert_eq(vein.get_stock(), before)
	miner.tool = null
	var bag := InventoryData.new(6, 2, 60.0, false)
	assert_false(vein.complete_mining_attempt(miner, bag).get("success", false))
	assert_eq(vein.get_stock(), before)
	assert_eq(bag.count_item(_item()), 0)

func test_iron_rebind_preserves_remaining_stock() -> void:
	var vein := _vein()
	if vein == null:
		return
	_bind(vein)
	var bag := InventoryData.new(6, 2, 60.0, false)
	assert_true(vein.complete_mining_attempt(_miner(), bag).get("success", false))
	var remaining := vein.get_stock()
	controller.detach_deposit(vein.resource_node_id, vein)
	var replacement := _vein()
	if replacement == null:
		return
	replacement.resource_node_id = vein.resource_node_id
	replacement._deposit_controller = weakref(controller)
	assert_true(controller.bind_deposit(replacement))
	assert_eq(replacement.get_stock(), remaining, "Reprojection must not refill iron")

func test_material_storage_accepts_iron_only_when_enabled() -> void:
	var item := _item()
	if item == null:
		return
	var platform: BulkStoragePlatform = autofree(BulkStoragePlatform.new())
	platform._ensure_material_profiles()
	assert_false(platform.is_storage_item_enabled(item))
	platform.storage_allow_materials = true
	assert_true(platform.is_storage_item_enabled(item))
	assert_eq(platform.get_storage_stack_limit(item), 20)

func test_iron_art_has_baked_surface_detail_and_bounded_geometry() -> void:
	var paths := [
		"res://assets/items/ore/iron/iron_vein.glb",
		"res://assets/items/ore/iron/iron_ore.glb",
	]
	var triangle_limits := [25000, 6000]
	for index in paths.size():
		var model: Node = autofree(load(paths[index]).instantiate())
		var triangles := 0
		for mesh_node: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			for surface in mesh_node.mesh.get_surface_count():
				var material := mesh_node.mesh.surface_get_material(surface) as StandardMaterial3D
				assert_not_null(material)
				if material == null:
					continue
				assert_not_null(material.albedo_texture)
				assert_true(material.normal_enabled)
				assert_not_null(material.normal_texture)
				assert_not_null(material.roughness_texture)
				assert_not_null(material.metallic_texture)
				triangles += int(mesh_node.mesh.surface_get_array_index_len(surface) / 3.0)
		assert_gt(triangles, 0)
		assert_lt(triangles, triangle_limits[index])

func test_iron_collision_matches_rebuilt_visual_bounds() -> void:
	var vein: MiningResourceNode = add_child_autofree(load(NODE_PATH).instantiate())
	var shape_node := vein.get_node("CollisionShape3D") as CollisionShape3D
	var box := shape_node.shape as BoxShape3D
	assert_not_null(box)
	if box == null:
		return
	var collision := AABB(shape_node.position - box.size * 0.5, box.size).grow(0.002)
	var mesh_nodes := vein.get_node("Visual").find_children("*", "MeshInstance3D", true, false)
	assert_false(mesh_nodes.is_empty())
	for mesh_node: MeshInstance3D in mesh_nodes:
		var relative := vein.global_transform.affine_inverse() * mesh_node.global_transform
		var bounds: AABB = relative * mesh_node.get_aabb()
		assert_true(collision.encloses(bounds), "Rebuilt iron must remain inside its fitted collider")
