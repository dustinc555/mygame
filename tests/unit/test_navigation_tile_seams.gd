extends GutTest

func test_roundoff_at_zero_does_not_split_a_baked_tile_seam() -> void:
	# Opposite bake volumes can put the same border on either side of zero.
	# This is a controlled mesh fixture, not any authored world or town.
	var west := _tile(Vector3(-4, 0.5, 0), Vector3(0.000001, 0.5, 4))
	var east := _tile(Vector3(-0.000001, 0.5, 0), Vector3(4, 0.5, 4))
	NavigationMeshPostprocess.apply(west)
	NavigationMeshPostprocess.apply(east)
	var map := NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(map, 0.1)
	NavigationServer3D.map_set_cell_height(map, 0.1)
	NavigationServer3D.map_set_use_edge_connections(map, false)
	NavigationServer3D.map_set_use_async_iterations(map, false)
	NavigationServer3D.map_set_active(map, true)
	var regions: Array[RID] = []
	for mesh in [west, east]:
		var region := NavigationServer3D.region_create()
		NavigationServer3D.region_set_use_async_iterations(region, false)
		NavigationServer3D.region_set_navigation_mesh(region, mesh)
		NavigationServer3D.region_set_map(region, map)
		regions.append(region)
	await get_tree().physics_frame
	await get_tree().physics_frame
	NavigationServer3D.map_force_update(map)
	var finish := NavigationServer3D.map_get_closest_point(map, Vector3(2, 0.5, 2))
	var path := NavigationServer3D.map_get_path(map, Vector3(-2, 0.5, 2), finish, true)
	assert_false(path.is_empty())
	if not path.is_empty():
		assert_almost_eq(path[-1], finish, Vector3.ONE * 0.001, "Baked borders join exactly without the all-pairs margin pass")
	for region in regions:
		NavigationServer3D.free_rid(region)
	NavigationServer3D.free_rid(map)

func _tile(start: Vector3, finish: Vector3) -> NavigationMesh:
	var mesh := NavigationMesh.new()
	mesh.cell_size = 0.1
	mesh.cell_height = 0.1
	mesh.vertices = PackedVector3Array([start, Vector3(finish.x, start.y, start.z), finish, Vector3(start.x, start.y, finish.z)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	return mesh

func test_generated_tiles_do_not_spend_runtime_work_bridging_real_gaps() -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child(viewport)
	var controller := WorldNavigationController.new()
	viewport.add_child(controller)
	controller.set_process(false)
	var map := viewport.find_world_3d().navigation_map
	NavigationServer3D.map_set_use_async_iterations(map, false)
	NavigationServer3D.map_set_cell_size(map, 0.1)
	NavigationServer3D.map_set_cell_height(map, 0.1)
	for coord in [Vector2i(-1, 0), Vector2i.ZERO]:
		controller._ensure_tile(coord)
		var mesh := _tile(Vector3(-4, 0.5, 0), Vector3(-0.1, 0.5, 4)) if coord.x < 0 else _tile(Vector3(0.1, 0.5, 0), Vector3(4, 0.5, 4))
		controller._assign_tile_mesh(coord, mesh)
		assert_false(controller._tiles[coord].region.use_edge_connections, "Generated tiles use exact joins, not the global all-pairs margin pass")
	await get_tree().physics_frame
	await get_tree().physics_frame
	NavigationServer3D.map_force_update(map)
	var path := NavigationServer3D.map_get_path(map, Vector3(-2, 0.5, 2), Vector3(2, 0.5, 2), true)
	assert_true(path.is_empty() or path[-1].x < 0.0, "A real gap is not a walkable tile seam")
	viewport.queue_free()
	await get_tree().process_frame

func test_real_baker_connects_sloped_tiles_across_both_signed_axes() -> void:
	var settings := WorldNavigationSettings.new()
	settings.cell_size = 0.1
	settings.tile_size = 32.0
	settings.tile_height = 32.0
	var template := WorldNavBakePipeline.build_template(settings, true)
	var map := NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(map, settings.cell_size)
	NavigationServer3D.map_set_cell_height(map, settings.cell_height)
	NavigationServer3D.map_set_use_edge_connections(map, false)
	NavigationServer3D.map_set_use_async_iterations(map, false)
	NavigationServer3D.map_set_active(map, true)
	var regions: Array[RID] = []
	for x in [-1, 0]:
		for z in [-1, 0]:
			var geometry := NavigationMeshSourceGeometryData3D.new()
			var a := Vector3(-40, -2.8, -40)
			var b := Vector3(-40, -1.2, 40)
			var c := Vector3(40, 2.8, 40)
			var d := Vector3(40, 1.2, -40)
			# Godot source faces use clockwise winding when viewed from above.
			geometry.add_faces(PackedVector3Array([a, c, b, a, d, c]), Transform3D.IDENTITY)
			var mesh := WorldNavBakePipeline.bake_tile(template, Vector2i(x, z), settings, [], geometry)
			assert_gt(mesh.get_polygon_count(), 0)
			var region := NavigationServer3D.region_create()
			NavigationServer3D.region_set_use_async_iterations(region, false)
			NavigationServer3D.region_set_navigation_mesh(region, mesh)
			NavigationServer3D.region_set_map(region, map)
			regions.append(region)
	await get_tree().physics_frame
	await get_tree().physics_frame
	NavigationServer3D.map_force_update(map)
	for pair in [[Vector3(-16, 0, -16), Vector3(16, 0, -16)], [Vector3(-16, 0, -16), Vector3(-16, 0, 16)], [Vector3(-16, 0, -16), Vector3(16, 0, 16)]]:
		var finish := NavigationServer3D.map_get_closest_point(map, pair[1])
		var path := NavigationServer3D.map_get_path(map, pair[0], finish, true)
		assert_false(path.is_empty())
		if not path.is_empty():
			assert_almost_eq(path[-1], finish, Vector3.ONE * 0.001)
	for region in regions:
		NavigationServer3D.free_rid(region)
	NavigationServer3D.free_rid(map)
