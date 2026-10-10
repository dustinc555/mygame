extends GutTest

func test_atlas_generates_requested_tiles_and_replaces_changed_geography() -> void:
	var path := "res://features/world_map/bridge/world_atlas_controller.gd"
	assert_true(ResourceLoader.exists(path), "Atlas must render bounded requests, not a giant world screenshot")
	if not ResourceLoader.exists(path):
		return
	var atlas = load(path).new()
	add_child_autofree(atlas)
	var h := Image.create(16, 16, false, Image.FORMAT_RF)
	h.fill(Color(10, 0, 0))
	var c := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	c.fill(Color(0.7, 0.6, 0.4))
	atlas.source.raster.set_patch("fixture", Rect2(0, 0, 256, 256), h, c)
	atlas.invalidate(Rect2(0, 0, 256, 256))
	var tiles: Array = atlas.request_view(Rect2(0, 0, 256, 256), 0.5)
	assert_gt(tiles.size(), 0)
	var until := Time.get_ticks_msec() + 5000
	while not atlas.is_idle() and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	assert_true(atlas.is_idle(), "Requested geography finishes asynchronously")
	tiles = atlas.request_view(Rect2(0, 0, 256, 256), 0.5)
	assert_not_null(tiles[0].get("texture"))
	var old_texture = tiles[0].get("texture")
	c.fill(Color(0.3, 0.6, 0.3))
	atlas.source.raster.set_patch("fixture", Rect2(0, 0, 256, 256), h, c)
	atlas.invalidate(Rect2(0, 0, 256, 256))
	atlas.request_view(Rect2(0, 0, 256, 256), 0.5)
	until = Time.get_ticks_msec() + 5000
	while not atlas.is_idle() and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	tiles = atlas.request_view(Rect2(0, 0, 256, 256), 0.5)
	assert_not_null(tiles[0].get("texture"))
	assert_ne(tiles[0].get("texture"), old_texture, "Changed terrain cannot reuse stale imagery")

func test_distant_world_growth_keeps_tile_requests_bounded_and_close_cancels_queue() -> void:
	var atlas = load("res://features/world_map/bridge/world_atlas_controller.gd").new()
	add_child_autofree(atlas)
	var height := Image.create(4, 4, false, Image.FORMAT_RF)
	height.fill(Color(10, 0, 0))
	atlas.source.raster.set_patch("origin", Rect2(0, 0, 256, 256), height, null)
	atlas.source.raster.set_patch("remote", Rect2(100000, -80000, 256, 256), height, null)
	atlas.invalidate(Rect2(0, -80000, 100256, 80256))
	var tiles: Array = atlas.request_view(atlas.bounds, 0.005)
	assert_lt(tiles.size(), 100, "Continental extent requests a screen of tiles, never meter-sized world pixels")
	assert_eq(atlas.request_view(Rect2(), 1.0).size(), 0)
	assert_true(atlas.is_idle(), "Closing before work starts leaves no raster queue")
