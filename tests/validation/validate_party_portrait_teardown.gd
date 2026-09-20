extends "res://tests/validation/test_case.gd"
## Destruction at the real snapshot wait boundary; headless does not prove portrait pixels.
const CARD := preload("res://features/ui/projection/party_portrait_card.tscn")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var initial_draw_callbacks := RenderingServer.frame_post_draw.get_connections().size()
	for queued in [false, true]:
		var card := CARD.instantiate()
		root.add_child(card)
		var id := card.get_instance_id()
		card.call("_capture_snapshot")
		if queued:
			card.queue_free()
		else:
			card.free()
		await process_frame
		await process_frame
		if is_instance_id_valid(id):
			push_error("portrait must be destroyed while snapshot is pending")
			quit(1)
			return
	# Reach the draw-wait phase as well; headless may not emit post_draw itself.
	var waiting_card := CARD.instantiate()
	root.add_child(waiting_card)
	waiting_card.call("_capture_snapshot")
	await process_frame
	await process_frame
	waiting_card.free()
	await process_frame
	if RenderingServer.frame_post_draw.get_connections().size() != initial_draw_callbacks:
		push_error("portrait teardown must release the renderer callback")
		quit(1)
		return
	print("PARTY_PORTRAIT_TEARDOWN_OK")
	quit(0)
