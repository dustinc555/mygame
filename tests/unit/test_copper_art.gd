extends GutTest
## Saved copper art must load through gameplay's existing item/deposit scenes.

func test_ore_has_textured_non_emissive_geometry_at_item_scale() -> void:
	var item := load("res://features/inventory/resources/items/copper_ore.tres") as ItemDefinition
	assert_not_null(item)
	if item == null:
		return
	assert_not_null(item.world_scene)
	if item.world_scene == null:
		return
	var model := item.world_scene.instantiate()
	autofree(model)
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	assert_gt(meshes.size(), 0)
	for mesh: MeshInstance3D in meshes:
		assert_not_null(mesh.mesh)
		if mesh.mesh == null:
			continue
		assert_almost_eq(mesh.mesh.get_aabb().size.y, item.world_visual_height_meters, 0.001)
		for index in range(mesh.mesh.get_surface_count()):
			var material := mesh.get_active_material(index) as BaseMaterial3D
			assert_not_null(material)
			if material != null:
				assert_not_null(material.albedo_texture)
				assert_not_null(material.normal_texture)
				assert_false(material.emission_enabled, "Copper reflects light; it is not lava")


func test_ore_inventory_art_is_nonempty_and_transparent() -> void:
	var item := load("res://features/inventory/resources/items/copper_ore.tres") as ItemDefinition
	assert_eq(item.grid_size, Vector2i(3, 2), "An art replacement must not change bag space")
	assert_not_null(item.icon)
	if item.icon == null:
		return
	var image := item.icon.get_image()
	assert_not_null(image)
	if image == null:
		return
	assert_true(image.is_invisible() == false)
	assert_gt(image.get_used_rect().get_area(), 0)
	assert_eq(image.get_pixel(0, 0).a, 0.0, "Inventory art retains a transparent border")


func test_vein_collision_contains_the_visible_outcrop() -> void:
	var scene := load("res://features/world/bridge/resource_nodes/copper_node.tscn") as PackedScene
	var node := scene.instantiate() as Node3D
	autofree(node)
	var collision := node.get_node("CollisionShape3D") as CollisionShape3D
	var box := collision.shape as BoxShape3D
	assert_not_null(box)
	if box == null:
		return
	var extent := AABB(-box.size * 0.5, box.size).grow(0.001)
	var meshes := node.get_node("Visual").find_children("*", "MeshInstance3D", true, false)
	assert_gt(meshes.size(), 0)
	for mesh: MeshInstance3D in meshes:
		var transform := mesh.transform
		var parent := mesh.get_parent() as Node3D
		while parent != node:
			transform = parent.transform * transform
			parent = parent.get_parent() as Node3D
		var to_collision := collision.transform.affine_inverse() * transform
		for corner in range(8):
			assert_true(extent.has_point(to_collision * mesh.get_aabb().get_endpoint(corner)),
				"The new outcrop must not extend above or outside its pickable collision")
