extends GutTest

const CARD = preload("res://features/ui/projection/party_portrait_card.tscn")
const CONVERSATION = preload("res://features/conversation/conversation_window.tscn")

var _window_state: Dictionary


func before_all() -> void:
	var window := get_tree().root
	_window_state = {"size": window.size, "content_scale_size": window.content_scale_size, "content_scale_factor": window.content_scale_factor, "content_scale_mode": window.content_scale_mode}
	window.size = Vector2i(800, 480)
	window.content_scale_size = Vector2i(800, 480)
	window.content_scale_factor = 1.0
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS


func after_all() -> void:
	var window := get_tree().root
	for key in _window_state:
		window.set(key, _window_state[key])


func test_party_capture_resolution_is_not_owned_by_layout() -> void:
	var card := CARD.instantiate()
	add_child_autofree(card)
	var container: SubViewportContainer = card.viewport.get_parent()
	assert_false(container.stretch, "UI layout must not overwrite capture resolution")
	assert_eq(card.portrait_image.custom_minimum_size, Vector2(68, 42), "Keep HUD compact")


func test_conversation_capture_resolution_is_not_owned_by_layout() -> void:
	var window := CONVERSATION.instantiate()
	add_child_autofree(window)
	for viewport in [window.left_viewport, window.right_viewport]:
		assert_false(viewport.get_parent().stretch, "Both speakers need independent capture resolution")


func test_party_rebuild_uses_supersampling_and_antialiasing() -> void:
	var card := CARD.instantiate()
	add_child_autofree(card)
	var actor := WorldActor.new()
	autofree(actor)
	card.member = actor
	await get_tree().process_frame
	card._rebuild_portrait()
	assert_gte(card.viewport.size.x, 136)
	assert_gte(card.viewport.size.y, 84)
	assert_eq(card.viewport.msaa_3d, Viewport.MSAA_4X)
	card._cancel_snapshot()


func test_conversation_rebuild_uses_supersampling_and_antialiasing() -> void:
	var window := CONVERSATION.instantiate()
	add_child_autofree(window)
	var actor := WorldActor.new()
	autofree(actor)
	window._rebuild_portrait(actor, window.left_portrait_root, window.left_viewport, window.left_portrait_image, window.left_portrait_camera, 0.0)
	assert_gte(window.left_viewport.size.x, 232)
	assert_gte(window.left_viewport.size.y, 264)
	assert_eq(window.left_viewport.msaa_3d, Viewport.MSAA_4X)


func _image_fixture() -> PortraitImage:
	var image := PortraitImage.new()
	image.size = Vector2(100, 60)
	add_child_autofree(image)
	return image


func test_screen_scale_and_supersampling_determine_capture_pixels() -> void:
	var image := _image_fixture()
	assert_eq(image.get_capture_size(), Vector2i(200, 120))
	image.scale = Vector2(2, 2)
	assert_eq(image.get_capture_size(), Vector2i(400, 240))
	image.scale = Vector2(1.25, 1.25)
	assert_eq(image.get_capture_size(), Vector2i(250, 150))
	image.supersampling = 3.0
	assert_eq(image.get_capture_size(), Vector2i(375, 225))


func test_resolution_cap_preserves_aspect_ratio() -> void:
	var image := _image_fixture()
	image.scale = Vector2(100, 100)
	image.max_capture_dimension = 1000
	assert_eq(image.get_capture_size(), Vector2i(1000, 600))
	image.scale = Vector2(2, 1)
	assert_eq(image.get_capture_size(), Vector2i(400, 240), "Nonuniform scale must not change camera framing")


func test_window_content_scaling_is_included_without_changing_control_size() -> void:
	var window := Window.new()
	window.size = Vector2i(800, 480)
	window.content_scale_size = Vector2i(400, 240)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	add_child_autofree(window)
	var image := PortraitImage.new()
	image.size = Vector2(100, 60)
	window.add_child(image)
	assert_eq(image.get_capture_size(), Vector2i(400, 240), "Include window stretch, not only the Control transform")
	window.content_scale_factor = 1.5
	assert_eq(image.get_capture_size(), Vector2i(600, 360))


func test_root_canvas_layer_includes_window_stretch() -> void:
	var window := get_tree().root
	var old_factor := window.content_scale_factor
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	var image := PortraitImage.new()
	image.size = Vector2(100, 60)
	layer.add_child(image)
	window.content_scale_factor = 2.0
	var capture := image.get_capture_size()
	window.content_scale_factor = old_factor
	assert_eq(capture, Vector2i(400, 240), "HUD CanvasLayer must include root-window scaling")


func test_resize_burst_coalesces_and_unchanged_layout_keeps_cache() -> void:
	var image := _image_fixture()
	var viewport := SubViewport.new()
	add_child_autofree(viewport)
	image.prepare_capture(viewport)
	watch_signals(image)
	image.size = Vector2(120, 60)
	image.size = Vector2(160, 90)
	assert_signal_not_emitted(image, "capture_size_changed")
	image._resize_timer.stop()
	image._on_resize_settled()
	assert_signal_emit_count(image, "capture_size_changed", 1)
	image.prepare_capture(viewport)
	assert_eq(viewport.size, Vector2i(320, 180))
	image.position = Vector2(50, 30)
	image._queue_resolution_check()
	image._on_resize_settled()
	assert_true(image._resize_timer.is_stopped())
	assert_signal_emit_count(image, "capture_size_changed", 1, "Moving a cached portrait must not rebuild it")
	assert_false(image.is_processing(), "No per-frame portrait polling")


func test_hidden_portrait_defers_resize_until_shown() -> void:
	var image := _image_fixture()
	var viewport := SubViewport.new()
	add_child_autofree(viewport)
	image.prepare_capture(viewport)
	watch_signals(image)
	image.hide()
	image.size = Vector2(200, 120)
	image._on_resize_settled()
	assert_signal_not_emitted(image, "capture_size_changed")
	image.show()
	assert_false(image._resize_timer.is_stopped())
	image._resize_timer.stop()
	image._on_resize_settled()
	assert_signal_emit_count(image, "capture_size_changed", 1)


func test_party_scale_refresh_is_coalesced_with_appearance_refresh() -> void:
	var card := CARD.instantiate()
	add_child_autofree(card)
	var actor := WorldActor.new()
	autofree(actor)
	card.setup(actor)
	await get_tree().process_frame
	card.portrait_image.scale = Vector2(2, 2)
	card.portrait_image._on_resize_settled()
	card.refresh_portrait()
	assert_true(card._portrait_refresh_queued)
	await get_tree().process_frame
	assert_eq(card.viewport.size, Vector2i(272, 168))
	assert_false(card._portrait_refresh_queued)
	card._cancel_snapshot()


func test_conversation_appearance_connections_replace_and_disconnect_on_close() -> void:
	var window := CONVERSATION.instantiate()
	add_child_autofree(window)
	var first := HumanoidCharacter.new()
	var second := HumanoidCharacter.new()
	autofree(first)
	autofree(second)
	window.show_conversation("First", "", [], first, first)
	assert_true(first.is_connected("appearance_changed", window._queue_portrait_refresh))
	window.show_conversation("Second", "", [], second, null)
	assert_false(first.is_connected("appearance_changed", window._queue_portrait_refresh))
	second.emit_signal("appearance_changed")
	assert_true(window._portrait_refresh_queued)
	window.hide_conversation()
	await get_tree().process_frame
	assert_false(second.is_connected("appearance_changed", window._queue_portrait_refresh))
	assert_null(window.left_portrait_image.texture)
	assert_eq(window.left_viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED)
	assert_false(RenderingServer.frame_post_draw.is_connected(window._finish_snapshots))


func test_conversation_teardown_disconnects_pending_draw_callback() -> void:
	var window := CONVERSATION.instantiate()
	add_child(window)
	window.show()
	window._capture_snapshot()
	await get_tree().process_frame
	await get_tree().process_frame
	var finish: Callable = window._finish_snapshots
	window.free()
	assert_false(RenderingServer.frame_post_draw.is_connected(finish))
