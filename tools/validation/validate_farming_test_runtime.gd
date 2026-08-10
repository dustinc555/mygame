extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_farming_test_runtime.gd

var _root: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed = load("res://scenes/test_levels/farming_test.tscn")
	if packed == null:
		_fail("scene does not load")
		return
	_root = packed.instantiate()
	get_root().add_child(_root)
	await create_timer(4.0).timeout
	var context := BootstrapContext.active
	if context == null:
		_fail("bootstrap context is active")
		return
	var farm = context.get_optional(&"farming")
	var placement = context.get_optional(&"farm_placement")
	var work = context.get_optional(&"farm_work")
	var details = context.get_optional(&"humanoid_details")
	var gecs = context.get_optional(&"gecs_world")
	var job_system = context.get_optional(&"job_system")
	var world_interaction = context.get_optional(&"world_interaction")
	if farm == null or placement == null or farm.get_plots().is_empty():
		_fail("starter plot exists in durable farming service")
		return
	if get_nodes_in_group("farm_plot").is_empty():
		_fail("starter plot has a runtime projection")
		return
	if gecs == null or not gecs.get_farm_water_source_states().has("farming_test.cistern"):
		_fail("finite water source registers durable state")
		return
	var build_button := _root.get_node_or_null("GameHUD/BuildMenuButton") as Button
	if build_button == null:
		_fail("settlement Build button exists outside character details")
		return
	build_button.pressed.emit()
	await process_frame
	var build_popup := build_button.get_node_or_null("BuildPopup") as PopupMenu
	var farming_popup := build_popup.get_node_or_null("FarmingBuildMenu") as PopupMenu if build_popup != null else null
	if build_popup == null or not build_popup.visible or build_popup.get_item_text(0) != "Farming" \
			or farming_popup == null or farming_popup.get_item_text(0) != "Plan Field":
		_fail("Build opens Farming > Plan Field")
		return
	build_popup.hide()
	placement.begin_placement("", "Player", "farming_test")
	if not placement.is_placing():
		_fail("No Crop rectangle placement mode opens")
		return
	placement.cancel_placement()
	var ada := _root.get_node_or_null("PartyMembers/Ada") as Node
	if ada == null or work == null or details == null or job_system == null or world_interaction == null:
		_fail("farming character interaction services exist")
		return
	if str(ada.get_meta("assigned_settlement_id", "")) != "farming_test":
		_fail("party members belong to the farming test city")
		return
	var jobs_button := _root.get_node_or_null("GameHUD/HudLayout/BottomHud/RightHud/BottomInfoRow/CommandDock/Margin/CommandColumn/BehaviorRows/AssistRow/JobsButton") as Button
	var assist_row := jobs_button.get_parent() as Control if jobs_button != null else null
	if jobs_button == null or not jobs_button.toggle_mode or assist_row == null:
		_fail("character AI bar exposes Jobs as a normal on/off button")
		return
	if jobs_button.position.x + jobs_button.size.x > assist_row.size.x + 0.5:
		_fail("Jobs button fits inside the Assist row")
		return
	for button_name in ["AutoHealButton", "BurnRustdeadButton", "JobsButton"]:
		var assist_button := assist_row.get_node_or_null(button_name) as Button
		var assist_style := assist_button.get_theme_stylebox("normal") as StyleBoxFlat if assist_button != null else null
		if assist_style == null or mini(
			mini(assist_style.corner_radius_top_left, assist_style.corner_radius_top_right),
			mini(assist_style.corner_radius_bottom_left, assist_style.corner_radius_bottom_right)
		) <= 0:
			_fail("%s is an independent fully rounded Assist-row button" % button_name)
			return
	var party_manager := _root.get_node("PartyManager")
	party_manager.select_only(ada)
	job_system.call("set_actor_jobs_enabled", ada, false)
	world_interaction.call("_on_jobs_button_toggled", true)
	if not bool(job_system.call("is_actor_jobs_enabled", ada)):
		_fail("AI bar Jobs button controls the selected character")
		return
	world_interaction.call("_on_jobs_button_toggled", false)
	var equipment = ada.call("get_equipment") if ada.has_method("get_equipment") else null
	var inventory_capability = ada.call("get_inventory") if ada.has_method("get_inventory") else null
	if inventory_capability != null and inventory_capability.get("inventory") == null and inventory_capability.has_method("initialize_from_actor"):
		inventory_capability.call("initialize_from_actor")
	var inventory = inventory_capability.get("inventory") if inventory_capability != null else null
	var hoe_entry = null
	for entry in inventory.entries if inventory != null else []:
		if entry != null and entry.definition != null and entry.definition.has_tool_tag("tool.hoe"):
			hoe_entry = entry
			break
	if equipment != null and hoe_entry != null:
		equipment.equip_item_to_slot(hoe_entry.definition, "weapon", hoe_entry.stack_id)
	if equipment == null or hoe_entry == null or equipment.get_equipped_item("weapon") != hoe_entry.definition:
		_fail("Ada can equip her hoe")
		return
	details.inspect_humanoid(ada)
	await process_frame
	var action_row := _root.get_node_or_null("GameHUD/HudLayout/BottomHud/InspectorSlot/HumanoidDetailsPanel/Margin/DetailsVBox/ActionRow") as Control
	var character_actions: PackedStringArray = _visible_button_labels(action_row) if action_row != null else PackedStringArray()
	if not character_actions.has("Till"):
		_fail("equipped hoe exposes Till on the selected character details panel")
		return
	if character_actions.has("Plan Field"):
		_fail("settlement field planning is absent from character details")
		return
	if not placement.has_method("begin_manual_till") or not placement.has_method("activate_at_world_position"):
		_fail("farming placement bridge exposes exact-cell manual till targeting")
		return
	var plot: Dictionary = farm.get_plots().values()[0]
	var untilled_keys: Array[String] = []
	for key_value in (plot.get("cells", {}) as Dictionary).keys():
		if str(((plot.get("cells", {}) as Dictionary)[key_value] as Dictionary).get("state", "")) == "untilled":
			untilled_keys.append(str(key_value))
			if untilled_keys.size() == 2:
				break
	if untilled_keys.size() < 2:
		_fail("starter field has two untilled target cells")
		return
	var untilled_key := untilled_keys[0]
	var untilled_position: Vector3 = ((plot.get("cells", {}) as Dictionary)[untilled_key] as Dictionary).get("world_position", Vector3.ZERO)
	var second_untilled_position: Vector3 = ((plot.get("cells", {}) as Dictionary)[untilled_keys[1]] as Dictionary).get("world_position", Vector3.ZERO)
	placement.call("begin_manual_till", ada)
	if not placement.is_placing():
		_fail("Till button enters click-or-drag rectangle targeting mode")
		return
	var selected_till_positions: Array[Vector3] = [untilled_position, second_untilled_position]
	var till_result := str(placement.call("_submit_manual_till_positions", selected_till_positions, untilled_position))
	var designated_work: Dictionary = farm.get_cell_work(str(plot.get("plot_id", "")), untilled_key)
	if not till_result.begins_with("2 cells designated") or str(designated_work.get("action", "")) != "till":
		_fail("Till Ground designates every selected field cell")
		return
	var active_assignment: Dictionary = work.get("_assignments").get(ada.get_instance_id(), {})
	if PackedStringArray(designated_work.get("allowed_actor_ids", PackedStringArray())).size() != 1 \
			or not bool(work.call("has_active_work_for_actor", ada)) \
			or (active_assignment.get("command_targets", []) as Array).size() != 1:
		_fail("Till Ground creates a complete manual actor sequence even with Jobs disabled")
		return
	var first_assigned_key := str(active_assignment.get("cell_key", ""))
	var first_completion: Dictionary = farm.apply_work(
		str(active_assignment.get("plot_id", "")),
		first_assigned_key,
		str(active_assignment.get("action", "")),
		999.0,
		0.0,
		int(active_assignment.get("request_revision", -1))
	)
	if not bool(first_completion.get("completed", false)):
		_fail("the first manual Till cell completes through normal farm work")
		return
	work.call("_finish_and_continue", ada.get_instance_id())
	var continued_assignment: Dictionary = work.get("_assignments").get(ada.get_instance_id(), {})
	if continued_assignment.is_empty() or str(continued_assignment.get("cell_key", "")) == first_assigned_key:
		_fail("manual Till continues to the next selected cell without Jobs")
		return
	var continued_plot_id := str(continued_assignment.get("plot_id", ""))
	var continued_cell_key := str(continued_assignment.get("cell_key", ""))
	work.call("cancel_work_for_actor", ada)
	if not farm.get_cell_work(continued_plot_id, continued_cell_key).is_empty():
		_fail("interrupting manual Till withdraws its unfinished actor-reserved cells")
		return
	var bram := _root.get_node_or_null("PartyMembers/Bram") as Node
	var ada_id := str(ada.get("stable_id"))
	var protected_request: Dictionary = farm.request_cell_operation(continued_plot_id, continued_cell_key, "till", "", PackedStringArray([ada_id]))
	var protected_revision := int(((protected_request.get("cells", {}) as Dictionary).get(continued_cell_key, {}) as Dictionary).get("request_revision", -1))
	if bram == null or not str(work.assign_cell(continued_plot_id, continued_cell_key, [ada])).begins_with("1 worker assigned"):
		_fail("valid current Till work is assigned before the stale-sequence probe")
		return
	var invalid_exact_result := str(work.assign_cell(continued_plot_id, continued_cell_key, [bram]))
	if invalid_exact_result.begins_with("1 worker assigned") or not work.has_active_work_for_actor(ada):
		_fail("an unauthorized exact-cell command cannot cancel another actor's valid current sequence")
		return
	var stale_result := str(work.assign_cell_sequence([{
		"plot_id": continued_plot_id,
		"cell_key": continued_cell_key,
		"request_revision": protected_revision + 1,
	}], bram, true))
	if stale_result.contains("queued") or not work.has_active_work_for_actor(ada):
		_fail("a stale Shift target cannot cancel another actor's valid current sequence")
		return
	work.cancel_work_for_actor(ada)
	var expansion_position := untilled_position + Vector3(-float(plot.get("cell_size", 1.25)), 0.0, 0.0)
	placement.call("begin_field_edit", str(plot.get("plot_id", "")), "expand", ada)
	if not placement.is_placing():
		_fail("owned field enters expansion mode")
		return
	if not str(placement.call("activate_at_world_position", expansion_position)).contains("expanded"):
		_fail("owner can add one adjacent field cell")
		return
	placement.call("begin_field_edit", str(plot.get("plot_id", "")), "shrink", ada)
	if not placement.is_placing():
		_fail("owned field enters shrink mode")
		return
	if not str(placement.call("activate_at_world_position", expansion_position)).contains("removed"):
		_fail("owner can remove one field cell")
		return
	placement.cancel_placement()
	var projection = null
	for candidate in get_nodes_in_group("farm_plot"):
		if str(candidate.get("plot_id")) == str(plot.get("plot_id", "")):
			projection = candidate
			break
	if projection == null:
		_fail("field projection remains available for field management")
		return
	details.inspect_target_at(projection, untilled_position)
	await process_frame
	var crop_button: Button
	for child in action_row.get_children():
		var button := child as Button
		if button != null and button.visible and button.text == "Crop":
			crop_button = button
			break
	if crop_button == null:
		_fail("selected field exposes one concise Crop picker")
		return
	details.call("_open_farm_crop_menu", crop_button)
	var crop_menu := details.get("_farm_crop_menu") as PopupMenu
	if crop_menu == null or crop_menu.item_count != farm.get_crops().size() + 1:
		_fail("Crop picker contains No Crop and every available crop")
		return
	for item_index in crop_menu.item_count:
		if str(crop_menu.get_item_metadata(item_index)) == "tomato":
			details.call("_on_farm_crop_menu_selected", crop_menu.get_item_id(item_index))
			break
	await process_frame
	if str(farm.get_plot(str(plot.get("plot_id", ""))).get("crop_policy_id", "")) != "tomato":
		_fail("Crop picker routes an owned field policy change through gameplay authority")
		return
	print("FARMING_TEST_RUNTIME_OK")
	_root.free()
	quit(0)


func _visible_button_labels(parent: Node) -> Array[String]:
	var labels: Array[String] = []
	for child in parent.get_children():
		var button := child as Button
		if button != null and button.visible and not button.disabled:
			labels.append(button.text)
	return labels


func _fail(message: String) -> void:
	push_error(message)
	print("FARMING_TEST_RUNTIME_FAILED")
	if _root != null and is_instance_valid(_root):
		_root.free()
	quit(1)
