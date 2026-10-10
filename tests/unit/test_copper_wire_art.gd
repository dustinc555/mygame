extends GutTest
## The saved item must resolve to real coil geometry, not the world-item box.
const ITEM_PATH := "res://features/inventory/resources/items/copper_wire.tres"


func test_copper_wire_world_scene_contains_mesh_geometry() -> void:
	var item := load(ITEM_PATH) as ItemDefinition
	assert_not_null(item)
	if item == null:
		return
	assert_not_null(item.world_scene, "Copper wire needs an authored world model")
	if item.world_scene == null:
		return
	var model := item.world_scene.instantiate()
	autofree(model)
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	assert_gt(meshes.size(), 0, "World scene must contain actual wire geometry")
	for node: MeshInstance3D in meshes:
		assert_not_null(node.mesh)
		if node.mesh != null:
			assert_gt(node.mesh.get_surface_count(), 0)
			assert_gt(node.mesh.get_aabb().size.length(), 0.0)
			var material := node.get_active_material(0) as StandardMaterial3D
			assert_not_null(material, "The saved coil retains its copper material")
			if material != null:
				assert_not_null(material.albedo_texture, "The embedded copper texture must resolve")


func test_copper_wire_reserves_a_two_by_two_inventory_area() -> void:
	var item := load(ITEM_PATH) as ItemDefinition
	assert_eq(item.grid_size, Vector2i(2, 2))
	var bag := InventoryData.new(2, 2, 60.0, false)
	assert_true(bag.can_place_item(item, Vector2i.ZERO))
	assert_false(bag.can_place_item(item, Vector2i.RIGHT))
	assert_false(bag.can_place_item(item, Vector2i.DOWN))
	bag.rows = 1
	assert_false(bag.can_add_item(item), "A single inventory row cannot hold the coil")
