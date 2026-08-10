extends Node

class_name FarmPlacementBridge

const SERVICE_ID := &"farm_placement"
const SOLVER := preload("res://features/farming/bridge/farm_placement_solver.gd")
const BUILDING_SOLVER := preload("res://features/settlements/bridge/building_placement_solver.gd")
const FARM_CONTROLLER := preload("res://features/farming/sim/farm_controller.gd")
const PREVIEW_ADD_COLOR := Color(0.08, 0.92, 0.28, 0.34)
const PREVIEW_REMOVE_COLOR := Color(0.92, 0.10, 0.08, 0.66)

signal placement_started(crop_id: String)
signal placement_finished(plot_id: String)
signal placement_cancelled

var _context: BootstrapContext
var _farm: Node
var _farm_work: Node
var _active := false
var _crop_id := "tomato"
var _owner_faction_id := "Player"
var _settlement_id := ""
var _anchor_set := false
var _anchor := Vector3.ZERO
var _drag_end := Vector3.ZERO
var _preview: Node3D
var _instruction: Label
var _latest_solution: Dictionary = {}
var _last_preview_signature := ""
var _mode := "create"
var _edit_plot_id := ""
var _target_actor: Node


func initialize(context: BootstrapContext) -> void:
	_context = context
	_farm = context.get_optional(FARM_CONTROLLER.SERVICE_ID)
	_farm_work = context.get_optional(&"farm_work")
	set_process_unhandled_input(true)


func begin_placement(crop_id: String, owner_faction_id := "", settlement_id := "") -> String:
	if _farm == null or (not crop_id.is_empty() and _farm.get_crop(crop_id) == null):
		return "Unknown crop"
	cancel_placement()
	_crop_id = crop_id
	_owner_faction_id = owner_faction_id if not owner_faction_id.is_empty() else _selected_faction()
	_settlement_id = settlement_id
	_mode = "create"
	_active = true
	_preview = Node3D.new()
	_preview.name = "FarmPlacementPreview"
	_context.projection_root.add_child(_preview)
	placement_started.emit(crop_id)
	return ""


func cancel_placement() -> void:
	if _preview != null and is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null
	_anchor_set = false
	_latest_solution.clear()
	_last_preview_signature = ""
	_mode = "create"
	_edit_plot_id = ""
	_target_actor = null
	if _active:
		placement_cancelled.emit()
	_active = false
	_set_escape_hint(false)


func is_placing() -> bool:
	return _active


func can_begin_manual_till(actor: Node) -> bool:
	return actor != null and is_instance_valid(actor) and _actor_has_equipped_tool(actor, "tool.hoe")


func begin_manual_till(actor: Node) -> String:
	if not can_begin_manual_till(actor):
		return "Equip a hoe first"
	cancel_placement()
	_mode = "manual_till"
	_target_actor = actor
	_active = true
	_preview = Node3D.new()
	_preview.name = "ManualTillPreview"
	_context.projection_root.add_child(_preview)
	return ""


func begin_field_edit(plot_id: String, mode: String, actor: Node) -> String:
	if mode not in ["expand", "shrink", "merge"]:
		return "Unknown field edit mode"
	if _farm == null or not _farm.can_actor_command_plot(actor, plot_id):
		return "Cannot edit: field belongs to another faction"
	cancel_placement()
	_mode = mode
	_edit_plot_id = plot_id
	_target_actor = actor
	_active = true
	_preview = Node3D.new()
	_preview.name = "FarmFieldEditPreview"
	_context.projection_root.add_child(_preview)
	_set_escape_hint(mode == "shrink")
	return ""


func activate_at_world_position(world_position: Vector3) -> String:
	if not _active:
		return "No farming action selected"
	match _mode:
		"manual_till":
			return _activate_manual_till(world_position)
		"expand":
			return _activate_field_expansion(world_position)
		"shrink":
			return _activate_field_shrink(world_position)
		"merge":
			return _activate_field_merge(world_position)
	return "Paint the field by dragging"


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_placement()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		cancel_placement()
		get_viewport().set_input_as_handled()
		return
	if _mode == "manual_till":
		_handle_manual_till_input(event)
		return
	if _mode in ["expand", "shrink"]:
		_handle_field_edit_drag_input(event)
		return
	if _mode == "merge":
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var action_hit := _screen_hit(event.position)
			if not action_hit.is_empty():
				activate_at_world_position(action_hit.get("position", Vector3.ZERO))
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var hit := _screen_hit(event.position)
		if event.pressed and not hit.is_empty():
			_anchor = hit.get("position", Vector3.ZERO)
			_drag_end = _anchor
			_anchor_set = true
			_update_preview()
			get_viewport().set_input_as_handled()
		elif not event.pressed and _anchor_set:
			if not hit.is_empty():
				_drag_end = hit.get("position", _anchor)
				_update_preview()
			_finalize()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _anchor_set:
		var hit := _screen_hit(event.position)
		if not hit.is_empty():
			_drag_end = hit.get("position", _anchor)
			_update_preview()
			get_viewport().set_input_as_handled()


func _handle_manual_till_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var hit := _screen_hit(event.position)
		if event.pressed and not hit.is_empty():
			_anchor = hit.get("position", Vector3.ZERO)
			_drag_end = _anchor
			_anchor_set = true
			_update_manual_till_preview()
			get_viewport().set_input_as_handled()
		elif not event.pressed and _anchor_set:
			if not hit.is_empty():
				_drag_end = hit.get("position", _drag_end)
				_update_manual_till_preview()
			_finalize_manual_till()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _anchor_set:
		var hit := _screen_hit(event.position)
		if not hit.is_empty():
			_drag_end = hit.get("position", _drag_end)
			_update_manual_till_preview()
			get_viewport().set_input_as_handled()


func _handle_field_edit_drag_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var hit := _screen_hit(event.position)
		if event.pressed and not hit.is_empty():
			_anchor = hit.get("position", Vector3.ZERO)
			_drag_end = _anchor
			_anchor_set = true
			_update_field_edit_preview()
			get_viewport().set_input_as_handled()
		elif not event.pressed and _anchor_set:
			if not hit.is_empty():
				_drag_end = hit.get("position", _drag_end)
				_update_field_edit_preview()
			_finalize_field_edit_drag()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _anchor_set:
		var hit := _screen_hit(event.position)
		if not hit.is_empty():
			_drag_end = hit.get("position", _drag_end)
			_update_field_edit_preview()
			get_viewport().set_input_as_handled()


func manual_till_grid(anchor: Vector3, drag_end: Vector3, cell_size := FARM_CONTROLLER.DEFAULT_CELL_SIZE) -> Dictionary:
	var grid := SOLVER.build_grid(anchor, drag_end, cell_size)
	var dimensions: Vector2i = grid.get("dimensions", Vector2i.ONE)
	var keys := PackedStringArray()
	for z in dimensions.y:
		for x in dimensions.x:
			keys.append("%d:%d" % [x, z])
	grid["cell_keys"] = keys
	return grid


func _update_manual_till_preview() -> void:
	if _preview == null or not is_instance_valid(_preview) or _preview.get_world_3d() == null:
		return
	var grid := manual_till_grid(_anchor, _drag_end)
	grid["ignore_groups"] = PackedStringArray(["farm_plot"])
	grid["ignore_characters"] = true
	_latest_solution = SOLVER.sample_grid(_preview.get_world_3d().direct_space_state, grid)
	var eligible: Array[Vector3] = []
	var positions: Array = _latest_solution.get("positions", [])
	var keys := PackedStringArray(_latest_solution.get("cell_keys", PackedStringArray()))
	var blocked: Dictionary = _latest_solution.get("blocked_cells", {})
	for index in positions.size():
		var position := positions[index] as Vector3
		var key := keys[index] if index < keys.size() else str(index)
		var occupant: Dictionary = _farm.find_plot_cell_at_world_position(position)
		if occupant.is_empty():
			if not blocked.has(key):
				eligible.append(position)
			continue
		var plot_id := str(occupant.get("plot_id", ""))
		var cell_key := str(occupant.get("cell_key", ""))
		if _farm.can_actor_command_plot(_target_actor, plot_id) \
				and str(_farm.get_cell(plot_id, cell_key).get("state", "")) == "untilled":
			eligible.append(position)
	_latest_solution["eligible_positions"] = eligible
	_draw_green_preview(eligible)


func _draw_green_preview(positions: Array) -> void:
	_draw_cell_preview(positions, PREVIEW_ADD_COLOR)


func _draw_cell_preview(positions: Array, color: Color) -> void:
	for child in _preview.get_children():
		child.queue_free()
	for position_value in positions:
		var cell := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.16, 0.035, 1.16)
		cell.mesh = mesh
		cell.position = (position_value as Vector3) + Vector3.UP * 0.055
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		cell.material_override = material
		_preview.add_child(cell)


func _finalize_manual_till() -> void:
	var positions: Array[Vector3] = []
	for value in (_latest_solution.get("eligible_positions", []) as Array):
		positions.append(value as Vector3)
	_anchor_set = false
	if positions.is_empty():
		return
	_submit_manual_till_positions(positions, _anchor)


func _update_field_edit_preview() -> void:
	if _preview == null or not is_instance_valid(_preview) or not _can_edit_active_plot():
		return
	if _mode == "shrink":
		var keys: PackedStringArray = _farm.plot_cell_keys_in_rectangle(_edit_plot_id, _anchor, _drag_end)
		var positions: Array[Vector3] = []
		var cells: Dictionary = _farm.get_plot(_edit_plot_id).get("cells", {})
		for key in keys:
			if cells.has(key):
				positions.append((cells[key] as Dictionary).get("world_position", Vector3.ZERO))
		_latest_solution = {"cell_keys": keys, "eligible_positions": positions}
		_draw_cell_preview(positions, PREVIEW_REMOVE_COLOR)
		return
	var candidates: Array[Vector3] = _farm.plot_rectangle_positions(_edit_plot_id, _anchor, _drag_end)
	var additions: Array[Vector3] = []
	var viewport := get_viewport()
	if viewport == null or viewport.world_3d == null:
		return
	var candidate_keys := PackedStringArray()
	for index in candidates.size():
		candidate_keys.append("%d:0" % index)
	var sampled := SOLVER.sample_grid(viewport.world_3d.direct_space_state, {
		"positions": candidates,
		"cell_keys": candidate_keys,
		"dimensions": Vector2i(maxi(1, candidates.size()), 1),
		"cell_size": float(_farm.get_plot(_edit_plot_id).get("cell_size", FARM_CONTROLLER.DEFAULT_CELL_SIZE)),
		"ignore_groups": PackedStringArray(["farm_plot"]),
		"ignore_characters": true,
	})
	var blocked: Dictionary = sampled.get("blocked_cells", {})
	var sampled_positions: Array = sampled.get("positions", [])
	var sampled_keys := PackedStringArray(sampled.get("cell_keys", PackedStringArray()))
	for index in sampled_positions.size():
		var key := sampled_keys[index] if index < sampled_keys.size() else str(index)
		var position := sampled_positions[index] as Vector3
		if not blocked.has(key) and _farm.find_plot_cell_at_world_position(position, _edit_plot_id).is_empty():
			additions.append(position)
	_latest_solution = {"eligible_positions": additions}
	_draw_cell_preview(additions, PREVIEW_ADD_COLOR)


func _finalize_field_edit_drag() -> void:
	_anchor_set = false
	if _mode == "shrink":
		var keys := PackedStringArray(_latest_solution.get("cell_keys", PackedStringArray()))
		if keys.is_empty():
			return
		if not _farm.shrink_plot(_edit_plot_id, keys, _target_actor).is_empty():
			cancel_placement()
		return
	var positions: Array = _latest_solution.get("eligible_positions", [])
	if positions.is_empty():
		return
	if not _farm.expand_plot(_edit_plot_id, positions, _target_actor).is_empty():
		cancel_placement()


func _activate_manual_till(world_position: Vector3) -> String:
	var positions: Array[Vector3] = [world_position]
	return _submit_manual_till_positions(positions, world_position)


func _submit_manual_till_positions(positions: Array[Vector3], anchor_position: Vector3) -> String:
	if _target_actor == null or not is_instance_valid(_target_actor):
		cancel_placement()
		return "Select a worker first"
	if not _actor_has_equipped_tool(_target_actor, "tool.hoe"):
		cancel_placement()
		return "Equip a hoe first"
	var order: Dictionary = _farm.prepare_manual_till(positions, _target_actor, anchor_position)
	var target_count := (order.get("targets", []) as Array).size()
	if target_count == 0:
		return "No tillable soil selected"
	if _farm_work == null or not _farm_work.has_method("assign_cell_sequence"):
		return "Farm workers unavailable"
	var assignment_result := str(_farm_work.call("assign_cell_sequence", order.get("targets", []), _target_actor, true))
	if not assignment_result.contains("queued"):
		return assignment_result
	cancel_placement()
	return "%d cells designated" % target_count


func _activate_field_expansion(world_position: Vector3) -> String:
	if not _can_edit_active_plot():
		cancel_placement()
		return "Cannot edit this field"
	var viewport := get_viewport()
	if viewport == null or viewport.world_3d == null:
		return "Field ground unavailable"
	var plot: Dictionary = _farm.get_plot(_edit_plot_id)
	var sampled := SOLVER.sample_grid(viewport.world_3d.direct_space_state, {
		"positions": [world_position],
		"cell_keys": PackedStringArray(["0:0"]),
		"dimensions": Vector2i.ONE,
		"cell_size": float(plot.get("cell_size", FARM_CONTROLLER.DEFAULT_CELL_SIZE)),
		"ignore_groups": PackedStringArray(["farm_plot"]),
		"ignore_characters": true,
	})
	if not bool(sampled.get("valid", false)) or int(sampled.get("valid_cell_count", 0)) != 1:
		return "That tile is blocked"
	var positions: Array = sampled.get("positions", [])
	if positions.is_empty() or _farm.expand_plot(_edit_plot_id, [positions[0]], _target_actor).is_empty():
		return "Field must remain connected and cannot overlap"
	return "Field expanded. Click another tile or right-click to finish."


func _activate_field_shrink(world_position: Vector3) -> String:
	if not _can_edit_active_plot():
		cancel_placement()
		return "Cannot edit this field"
	var target: Dictionary = _farm.find_plot_cell_at_world_position(world_position)
	if str(target.get("plot_id", "")) != _edit_plot_id:
		return "Click a tile in this field"
	var keys := PackedStringArray([str(target.get("cell_key", ""))])
	if _farm.shrink_plot(_edit_plot_id, keys, _target_actor).is_empty():
		return "Cannot remove that tile without splitting the field"
	return "Field tile removed. Click another tile or right-click to finish."


func _activate_field_merge(world_position: Vector3) -> String:
	if not _can_edit_active_plot():
		cancel_placement()
		return "Cannot edit this field"
	var target: Dictionary = _farm.find_plot_cell_at_world_position(world_position)
	var absorbed_plot_id := str(target.get("plot_id", ""))
	if absorbed_plot_id.is_empty() or absorbed_plot_id == _edit_plot_id:
		return "Click a different adjacent field"
	var merged: Dictionary = _farm.merge_adjacent_plots(_edit_plot_id, absorbed_plot_id, _target_actor)
	if merged.is_empty():
		return "Fields must be adjacent and owned by the same authority"
	cancel_placement()
	return "Fields merged"


func _can_edit_active_plot() -> bool:
	return _target_actor != null and is_instance_valid(_target_actor) \
		and not _edit_plot_id.is_empty() and _farm.can_actor_command_plot(_target_actor, _edit_plot_id)


func _actor_has_equipped_tool(actor: Node, tool_tag: String) -> bool:
	if actor == null or not actor.has_method("get_equipment"):
		return false
	var equipment = actor.call("get_equipment")
	if equipment == null:
		return false
	var equipped = equipment.call("get_equipped_item", "weapon")
	return equipped != null and equipped.has_method("has_tool_tag") and bool(equipped.call("has_tool_tag", tool_tag))


func _work_actor_ids(actors: Array) -> PackedStringArray:
	var actor_ids := PackedStringArray()
	for actor_value in actors:
		var actor := actor_value as Node
		if actor == null:
			continue
		var actor_id := str(actor.get("stable_id")) if actor.get("stable_id") != null else ""
		if actor_id.is_empty():
			actor_id = str(actor.get_meta("stable_id", ""))
		if actor_id.is_empty():
			actor_id = "instance:%d" % actor.get_instance_id()
		if not actor_ids.has(actor_id):
			actor_ids.append(actor_id)
	return actor_ids


func _screen_hit(screen_position: Vector2) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	return BUILDING_SOLVER.terrain_hit_from_screen(camera, screen_position)


func _update_preview() -> void:
	if _preview == null or not is_instance_valid(_preview):
		return
	var grid := SOLVER.build_grid(_anchor, _drag_end, FARM_CONTROLLER.DEFAULT_CELL_SIZE)
	if grid.is_empty():
		return
	var dimensions: Vector2i = grid.get("dimensions", Vector2i.ONE)
	var rectangle_keys := PackedStringArray()
	for z in dimensions.y:
		for x in dimensions.x:
			rectangle_keys.append("%d:%d" % [x, z])
	grid["cell_keys"] = rectangle_keys
	var signature := "%s|%s|%s" % [str(_anchor), str(_drag_end), "|".join(PackedStringArray(grid.get("cell_keys", PackedStringArray())))]
	if signature == _last_preview_signature:
		return
	_last_preview_signature = signature
	_latest_solution = SOLVER.sample_grid(_preview.get_world_3d().direct_space_state, grid)
	for child in _preview.get_children():
		child.queue_free()
	var blocked: Dictionary = _latest_solution.get("blocked_cells", {})
	var positions: Array = _latest_solution.get("positions", [])
	var cell_keys := PackedStringArray(_latest_solution.get("cell_keys", PackedStringArray()))
	for index in positions.size():
		var key := cell_keys[index] if index < cell_keys.size() else str(index)
		if blocked.has(key):
			continue
		var cell := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.16, 0.045, 1.16)
		cell.mesh = mesh
		cell.position = positions[index] + Vector3.UP * 0.06
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.1, 0.85, 0.3, 0.42)
		cell.material_override = material
		_preview.add_child(cell)



func _finalize() -> void:
	if not bool(_latest_solution.get("valid", false)):
		_anchor_set = false
		return
	var positions: Array[Vector3] = []
	var cell_keys := PackedStringArray()
	var blocked: Dictionary = _latest_solution.get("blocked_cells", {})
	var solved_positions: Array = _latest_solution.get("positions", [])
	var solved_keys := PackedStringArray(_latest_solution.get("cell_keys", PackedStringArray()))
	for index in solved_positions.size():
		var key := solved_keys[index] if index < solved_keys.size() else ""
		if key.is_empty() or blocked.has(key):
			continue
		positions.append(solved_positions[index] as Vector3)
		cell_keys.append(key)
	var state: Dictionary = _farm.create_plot(
		positions,
		_latest_solution.get("dimensions", Vector2i.ONE),
		_crop_id,
		_owner_faction_id,
		_settlement_id,
		{},
		cell_keys
	)
	if state.is_empty():
		return
	var plot_id := str(state.get("plot_id", ""))
	for cell_key in cell_keys:
		_farm.request_cell_operation(plot_id, cell_key, "till")
	cancel_placement()
	placement_finished.emit(plot_id)


func _selected_faction() -> String:
	var manager := get_tree().get_first_node_in_group("party_manager")
	if manager != null:
		for actor in manager.selected_members:
			var faction := str(actor.get("faction_name"))
			if not faction.is_empty():
				return faction
	return "Player"


func _set_escape_hint(visible: bool) -> void:
	if not visible:
		if _instruction != null and is_instance_valid(_instruction):
			_instruction.queue_free()
		_instruction = null
		return
	if _instruction != null and is_instance_valid(_instruction):
		return
	_instruction = Label.new()
	_instruction.name = "FarmDeletionEscapeHint"
	_instruction.text = "Press Esc to cancel deletion"
	_instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_instruction.add_theme_color_override("font_color", Color.WHITE)
	_instruction.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_instruction.add_theme_constant_override("shadow_offset_x", 1)
	_instruction.add_theme_constant_override("shadow_offset_y", 1)
	_instruction.add_theme_font_size_override("font_size", 18)
	_instruction.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_instruction.position = Vector2(-220, 24)
	_instruction.size = Vector2(440, 32)
	var overlay_parent: Node = _context.hud_layer if _context.hud_layer != null else _context.root_scene
	overlay_parent.add_child(_instruction)
