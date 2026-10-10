extends GutTest

const RASTER_PATH := "res://features/world_map/projection/map_terrain_raster.gd"

func test_atlas_uses_real_heights_colors_and_world_bounds_without_inventing_land() -> void:
	assert_true(ResourceLoader.exists(RASTER_PATH), "Map imagery must come from actual terrain data")
	if not ResourceLoader.exists(RASTER_PATH):
		return
	var raster = load(RASTER_PATH).new()
	var height := Image.create(16, 16, false, Image.FORMAT_RF)
	var color := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	height.fill(Color(10, 0, 0))
	color.fill(Color(0.5, 0.7, 0.3))
	raster.set_patch("west", Rect2(-64, -64, 128, 128), height, color)
	assert_eq(raster.get_bounds(), Rect2(-64, -64, 128, 128))
	var area := Rect2(-128, -128, 256, 256)
	var image: Image = raster.render(area, 64, raster.snapshot(area), {})
	assert_eq(image.get_size(), Vector2i(64, 64))
	assert_gt(image.get_pixel(32, 32).a, 0.9)
	assert_gt(image.get_pixel(32, 32).g, image.get_pixel(32, 32).r, "Authored green terrain stays green")
	assert_eq(image.get_pixel(0, 0).a, 0.0, "Missing world data is not invented ocean or land")
	for y in range(16):
		for x in range(16):
			height.set_pixel(x, y, Color(float(x * x), 0, 0))
	raster.set_patch("west", Rect2(-64, -64, 128, 128), height, color)
	var updated: Image = raster.render(area, 64, raster.snapshot(area), {})
	assert_true(updated.get_data() != image.get_data(), "Terrain edits change the geographic image")
	raster.set_patch("east", Rect2(1000, 500, 128, 128), height, color)
	assert_eq(raster.get_bounds().end, Vector2(1128, 628), "New real regions expand the map")
	raster.remove_patch("east")
	assert_eq(raster.get_bounds(), Rect2(-64, -64, 128, 128))

func test_authored_terrain_holes_remain_transparent() -> void:
	var raster = load(RASTER_PATH).new()
	var height := Image.create(4, 4, false, Image.FORMAT_RF)
	height.fill(Color(10, 0, 0))
	var control := PackedInt32Array()
	control.resize(16)
	control[5] = 4
	var flags := Image.create_from_data(4, 4, false, Image.FORMAT_RF, control.to_byte_array())
	raster.set_patch("holes", Rect2(0, 0, 4, 4), height, null, flags)
	var result: Image = raster.render(Rect2(0, 0, 4, 4), 4, raster.snapshot(Rect2(0, 0, 4, 4)), {})
	assert_eq(result.get_pixel(1, 1).a, 0.0)
	assert_eq(result.get_pixel(2, 2).a, 1.0)

func test_world_source_tracks_actual_building_placement_and_removal() -> void:
	var source_path := "res://features/world_map/bridge/map_world_source.gd"
	assert_true(ResourceLoader.exists(source_path), "World geometry must feed the map automatically")
	if not ResourceLoader.exists(source_path):
		return
	var root := Node3D.new()
	add_child(root)
	var building := WorldBuilding.new()
	building.building_id = "map.test.building"
	root.add_child(building)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = Vector3(12, 6, 8)
	building.add_child(mesh)
	building.position = Vector3(100, 0, -50)
	var source = load(source_path).new()
	source.register_node(building)
	var records: Array = source.features_near(Vector2(100, -50), 30)
	assert_eq(records.size(), 1)
	if not records.is_empty():
		assert_eq(records[0]["world"], Vector2(100, -50))
		assert_gt(records[0]["polygons"].size(), 0, "Draw the actual placed geometry")
		var polygon: PackedVector2Array = records[0]["polygons"][0]
		var outline := Rect2(polygon[0], Vector2.ZERO)
		for point in polygon:
			outline = outline.expand(point)
		assert_eq(outline, Rect2(94, -54, 12, 8), "Merged footprint remains in real world coordinates")
	building.position.x = 300
	source.register_node(building)
	assert_eq(source.features_near(Vector2(100, -50), 30).size(), 0)
	assert_eq(source.features_near(Vector2(300, -50), 30).size(), 1)
	source.unregister_node(building)
	assert_eq(source.features_near(Vector2(300, -50), 30).size(), 0)
	source.dispose()
	root.queue_free()
	await get_tree().process_frame

func test_native_terrain_regions_refresh_only_edited_geography() -> void:
	var root := Node3D.new()
	add_child(root)
	var camera := Camera3D.new()
	root.add_child(camera)
	var terrain = ClassDB.instantiate("Terrain3D")
	terrain.region_size = 256
	terrain.collision_mode = 0
	root.add_child(terrain)
	terrain.set_camera(camera)
	terrain.set_physics_process(false)
	var height := Image.create(512, 256, false, Image.FORMAT_RF)
	height.fill(Color(12, 0, 0))
	terrain.data.import_images([height, null, null], Vector3.ZERO, 0.0, 1.0)
	var source = load("res://features/world_map/bridge/map_world_source.gd").new()
	source.register_node(terrain)
	assert_eq(source.raster.get_bounds(), Rect2(0, 0, 512, 256))
	var before: Dictionary = source.raster.snapshot(Rect2(0, 0, 512, 256))
	var east_image: Image
	for record in before[Vector2i.ZERO]:
		if record["area"].position.x == 256:
			east_image = record["height"]
	var region = terrain.data.get_region(Vector2i.ZERO)
	region.get_height_map().fill(Color(100, 0, 0))
	terrain.data.emit_signal("maps_edited", AABB(Vector3(20, 0, 20), Vector3(20, 1, 20)))
	await get_tree().process_frame
	var after: Dictionary = source.raster.snapshot(Rect2(0, 0, 512, 256))
	for record in after[Vector2i.ZERO]:
		if record["area"].position.x == 256:
			assert_same(record["height"], east_image, "Unchanged region snapshot is retained")
		else:
			assert_eq(record["height"].get_pixel(30, 30).r, 100.0, "Native terrain edit refreshes map heights")
	# Installed Terrain3D uses this deprecated native rendering entry point.
	# Godot reports it once per process, so it may precede this test in a full
	# run. Acknowledge only this exact compatibility warning, not map errors.
	for error in get_errors():
		if error.contains_text("instance_reset_physics_interpolation() is deprecated."):
			assert_engine_error("instance_reset_physics_interpolation() is deprecated.")
	source.dispose()
	root.queue_free()
	await get_tree().process_frame
