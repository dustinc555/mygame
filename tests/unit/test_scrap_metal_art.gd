extends GutTest

const ITEM_PATH := "res://features/inventory/resources/items/scrap_metal.tres"
const WORLD_ITEM := preload("res://features/world/projection/items/world_item.tscn")


func test_scrap_drop_uses_authored_metal_mesh_instead_of_fallback_box() -> void:
	var item := load(ITEM_PATH) as ItemDefinition
	assert_not_null(item.world_scene, "Salvaged metal needs its own dropped model")
	if item.world_scene == null:
		return
	var drop := WORLD_ITEM.instantiate() as WorldItem
	add_child_autofree(drop)
	drop.setup(item, 1)
	var visual := drop.model_root.get_child(0)
	assert_eq(visual.scene_file_path, item.world_scene.resource_path)
	var meshes := visual.find_children("*", "MeshInstance3D", true, false)
	assert_gt(meshes.size(), 0, "The authored drop contains real geometry")
	for mesh: MeshInstance3D in meshes:
		assert_not_null(mesh.mesh)
		assert_gt(mesh.mesh.get_surface_count(), 0)
		for surface in mesh.mesh.get_surface_count():
			assert_not_null(mesh.get_active_material(surface), mesh.name + ": no untextured faces")
	var bounds := drop._calculate_local_mesh_bounds(drop.model_root)
	assert_almost_eq(maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)), 0.36, 0.001, "Dropped salvage remains hand-sized, not the generic drop scale")


func test_scrap_occupies_two_by_two_cells_without_changing_weight_or_stacking() -> void:
	var item := load(ITEM_PATH) as ItemDefinition
	assert_eq(item.display_name, "Mixed Metal Scrap")
	assert_eq(item.grid_size, Vector2i(2, 2))
	assert_eq(item.unit_weight, 1.5)
	assert_eq(item.max_stack, 1)
	var narrow := InventoryData.new(2, 1)
	assert_false(narrow.add_item(item), "The former two-by-one space no longer fits the bundle")
	assert_eq(narrow.entries.size(), 0, "A refused placement cannot add an entry")
	var square := InventoryData.new(2, 2)
	assert_true(square.add_item(item))
	assert_eq(square.entries.size(), 1)
	assert_false(square.add_item(item), "One bundle fills the two-by-two space")


func test_scrap_has_a_saved_transparent_model_picture() -> void:
	var item := load(ITEM_PATH) as ItemDefinition
	assert_not_null(item.icon)
	if item.icon == null:
		return
	assert_eq(item.icon.resource_path, "res://assets/items/icons/scrap_metal.png")
	var image := item.icon.get_image()
	assert_not_null(image)
	if image == null:
		return
	if image.is_compressed():
		assert_eq(image.decompress(), OK)
	var visible := image.get_used_rect()
	assert_gt(visible.size.x, 0)
	assert_gt(visible.size.y, 0)
	assert_gt(visible.position.x, 0)
	assert_gt(visible.position.y, 0)
	assert_lt(visible.end.x, image.get_width())
	assert_lt(visible.end.y, image.get_height())
