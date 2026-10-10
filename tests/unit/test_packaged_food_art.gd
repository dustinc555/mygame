extends GutTest
## Authored packaged food: inventory capacity and the real dropped-item projection.
const ITEM_PATH := "res://features/inventory/resources/items/food.tres"
const WORLD_ITEM := preload("res://features/world/projection/items/world_item.tscn")


func test_dry_biscuits_need_two_rows_of_bag_space() -> void:
	var item := load(ITEM_PATH) as ItemDefinition
	var short_bag := InventoryData.new(2, 1, 60.0, false)
	assert_false(short_bag.add_item_count(item, 1), "A sealed biscuit tin cannot fit a single inventory row")
	assert_eq(short_bag.count_item(item), 0, "Refusing a too-short bag must not add the item")
	var square_bag := InventoryData.new(2, 2, 60.0, false)
	assert_true(square_bag.add_item_count(item, 1))
	assert_eq(square_bag.count_item(item), 1)
	assert_false(square_bag.add_item_count(item, 1), "One tin occupies all four cells")
	assert_eq(square_bag.count_item(item), 1)


func test_biscuit_drop_uses_the_authored_tin_at_handheld_scale() -> void:
	var item := load(ITEM_PATH) as ItemDefinition
	assert_not_null(item.world_scene, "Packaged food must not use the fallback box")
	if item.world_scene == null:
		return
	var drop := WORLD_ITEM.instantiate() as WorldItem
	add_child_autofree(drop)
	drop.freeze = true
	drop.setup(item, 1)
	await get_tree().process_frame # Let replaced fallback/previous visuals finish queue_free.
	var visual := drop.model_root.get_child(0)
	assert_eq(visual.scene_file_path, item.world_scene.resource_path)
	var meshes := visual.find_children("*", "MeshInstance3D", true, false)
	assert_gt(meshes.size(), 0)
	for mesh: MeshInstance3D in meshes:
		assert_not_null(mesh.mesh)
		assert_gt(mesh.mesh.get_surface_count(), 0)
	var shape := drop.collision_shape_node.shape as BoxShape3D
	assert_not_null(shape)
	if shape != null:
		assert_between(shape.size.x, 0.19, 0.21, "Tin stays about twenty centimetres wide, not the generic oversized drop")
		assert_between(shape.size.y, 0.10, 0.12)
		assert_between(shape.size.z, 0.19, 0.21)
