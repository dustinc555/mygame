extends SceneTree
## Run: godot --headless --path . --script res://tests/validation/validate_bulk_take_all_runtime.gd

const TOMATO := preload("res://features/inventory/resources/items/tomato.tres")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := (load("res://scenes/test_levels/bulk_storage_test.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		var ready_context := BootstrapContext.active
		var ready_controller = ready_context.get_optional(&"party_inventory") if ready_context != null and ready_context.root_scene == game else null
		var ready_actor = game.get_node_or_null("PartyMembers/Ada")
		if ready_controller != null and bool(ready_controller.get("_initialized")) and ready_actor != null and ready_actor.get("inventory") != null:
			break
		await process_frame
	var context := BootstrapContext.active
	var controller = context.get_optional(&"party_inventory") if context != null else null
	var ada = game.get_node("PartyMembers/Ada")
	var bram = game.get_node("PartyMembers/Bram")
	var party_manager = game.get_node("PartyManager")
	var platform = game.get_node("StoragePlatforms/SamplePlatform")
	_expect(controller != null, "party inventory controller exists")
	_expect(ada.inventory.count_item(TOMATO) == 25 and platform.get_stored_item_count(TOMATO) == 50, "runtime Take All fixture starts with 15 free actor slots")
	if controller != null:
		platform.deposit_item_count(TOMATO, 849)
		# Stage beside the platform on this demo's flat floor. This checks the
		# paired transfer, not travel or the still-building navigation map.
		var fixture_position: Vector3 = platform.global_position + platform.global_basis.z.normalized() * 2.0
		fixture_position.y = ada.global_position.y
		ada.global_position = fixture_position
		_expect(not bool(controller.call("_owners_too_far", ada, platform)), "paired recipient starts inside ordinary inventory reach")
		party_manager.set_selection([bram])
		controller.open_inventory_pair(ada, platform)
		await process_frame
		if bool(controller.call("_owners_too_far", ada, platform)) or not is_instance_valid(controller.get("secondary_inventory_window")):
			print("BULK_PAIR_BOUNDARY ", JSON.stringify({
				"actor": ada.global_position, "platform": platform.global_position,
				"distance": ada.global_position.distance_to(platform.global_position),
				"out_of_range": controller.call("_owners_too_far", ada, platform),
			}))
		var actor_entry = ada.inventory.entries[0]
		controller.call("_on_inventory_quick_transfer_requested", ada, actor_entry)
		await process_frame
		_expect(ada.inventory.count_item(TOMATO) == 24 and platform.get_stored_item_count(TOMATO) == 900, "quick transfer fills a partial platform crate even when no empty platform grid cell remains")
		var entry = platform.inventory.entries[0]
		var started := Time.get_ticks_usec()
		controller.call("_on_inventory_item_action_requested", platform, entry, "take_all")
		var elapsed_usec := Time.get_ticks_usec() - started
		_expect(elapsed_usec < 50000, "runtime Take All completes below a generous 50 ms interaction ceiling")
		await process_frame
	_expect(ada.inventory.count_item(TOMATO) == 40, "runtime Take All fills the character inventory paired with the platform")
	_expect(bram.inventory.count_item(TOMATO) == 0, "Take All never redirects into a different focused character")
	_expect(platform.get_stored_item_count(TOMATO) == 884, "runtime Take All leaves overflow from the clicked stack on the platform")
	root.remove_child(game)
	game.free()
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("BULK_TAKE_ALL_RUNTIME_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("BULK_TAKE_ALL_RUNTIME_FAILED count=%d" % failures.size())
	quit(1)
