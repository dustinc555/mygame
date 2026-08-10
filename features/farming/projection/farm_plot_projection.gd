extends Area3D

class_name FarmPlotProjection

const CROP_SOURCE := preload("res://assets/vendor/luceed-studio/farm-crops-01/crops01.glb")
const FARM_SIMULATION := preload("res://features/farming/sim/farm_simulation.gd")

static var _visual_cache: Dictionary = {}

var plot_id := ""
var _farm: Node
var _state: Dictionary = {}
var _visual_root: Node3D
var _soil_surface: MeshInstance3D
var _stake_root: Node3D
var _selection_root: Node3D
var _selection_fill: MeshInstance3D
var _selection_border: MeshInstance3D
var _collision_root: Area3D
var _cell_holders: Dictionary = {}
var _visual_signatures: Dictionary = {}
var _collision_signature := ""
var _stake_signature := ""
var _inspected := false
var _field_details_mode := false


func _ready() -> void:
	add_to_group("farm_plot")
	_visual_root = Node3D.new()
	_visual_root.name = "Cells"
	add_child(_visual_root)
	_soil_surface = MeshInstance3D.new()
	_soil_surface.name = "ConnectedSoil"
	_visual_root.add_child(_soil_surface)
	_stake_root = Node3D.new()
	_stake_root.name = "BoundaryStakes"
	_visual_root.add_child(_stake_root)
	_stake_root.visible = false
	_selection_root = Node3D.new()
	_selection_root.name = "FieldSelection"
	_visual_root.add_child(_selection_root)
	_selection_fill = MeshInstance3D.new()
	_selection_fill.name = "GlassyInterior"
	_selection_root.add_child(_selection_fill)
	_selection_border = MeshInstance3D.new()
	_selection_border.name = "HardBorder"
	_selection_root.add_child(_selection_border)
	_selection_root.visible = false
	# CollisionShape3D only registers with a direct CollisionObject3D parent.
	# Keep the per-cell pick shapes under a child Area3D so right-click rays hit
	# designated grass cells as well as visibly cultivated soil.
	_collision_root = Area3D.new()
	_collision_root.name = "CellCollisions"
	_collision_root.monitorable = true
	add_child(_collision_root)
	_build_visual_cache()


func setup(state: Dictionary, farm: Node) -> void:
	_farm = farm
	plot_id = str(state.get("plot_id", ""))
	name = "FarmPlot_%s" % plot_id.replace(":", "_")
	update_state(state)


func update_state(state: Dictionary) -> void:
	_state = state.duplicate(true)
	if not is_node_ready():
		await ready
	_sync_visuals()


func get_world_context_actions(_actor: Node = null) -> Array:
	return []


func blocks_farm_placement() -> bool:
	return not bool(_state.get("field_deleted", false))


func begin_inspection_at(world_position: Vector3) -> void:
	var cell_key := _cell_key_at_world_position(world_position)
	var cell: Dictionary = (_state.get("cells", {}) as Dictionary).get(cell_key, {})
	var state := str(cell.get("state", FARM_SIMULATION.STATE_UNTILLED))
	_field_details_mode = not bool(_state.get("field_deleted", false)) and (str(cell.get("crop_id", "")).is_empty() \
			or state not in [FARM_SIMULATION.STATE_GROWING, FARM_SIMULATION.STATE_RIPE, FARM_SIMULATION.STATE_WITHERED]
	)
	_sync_selection_overlay()


func set_inspected(inspected: bool) -> void:
	_inspected = inspected
	if not inspected:
		_field_details_mode = false
	_sync_selection_overlay()


## Player-facing inspection data for the exact cell that was clicked.
func get_details_panel_data_at(world_position: Vector3) -> Dictionary:
	if _field_details_mode and not bool(_state.get("field_deleted", false)):
		var crop_policy_id := str(_state.get("crop_policy_id", ""))
		var crop_policy = _farm.get_crop(crop_policy_id) if _farm != null and not crop_policy_id.is_empty() else null
		return {
			"title": str(_state.get("display_name", "Field")),
			"state": str(crop_policy.display_name) if crop_policy != null else "No Crop",
			"show_crop_bars": false,
		}
	var cell_key := _cell_key_at_world_position(world_position)
	var cells: Dictionary = _state.get("cells", {})
	if cell_key.is_empty() or not cells.has(cell_key):
		return {}
	var cell: Dictionary = cells[cell_key]
	var status := str(cell.get("state", FARM_SIMULATION.STATE_UNTILLED))
	var crop_id := str(cell.get("crop_id", ""))
	var crop: Variant = _farm.get_crop(crop_id) if _farm != null and not crop_id.is_empty() else null
	var has_crop := crop != null
	var title := "Soil"
	var state_label := "Empty"
	match status:
		FARM_SIMULATION.STATE_UNTILLED:
			title = "Untilled Soil"
			state_label = "Untilled"
		FARM_SIMULATION.STATE_TILLED:
			title = "Empty Tilled Soil"
			state_label = "Empty"
		FARM_SIMULATION.STATE_GROWING:
			title = "%s plant" % str(crop.display_name) if has_crop else "Growing plant"
			state_label = "Alive"
		FARM_SIMULATION.STATE_RIPE:
			title = "%s plant" % str(crop.display_name) if has_crop else "Mature plant"
			state_label = "Ready for Harvest"
		FARM_SIMULATION.STATE_WITHERED:
			title = "%s plant" % str(crop.display_name) if has_crop else "Dead plant"
			state_label = "Dead"
		FARM_SIMULATION.STATE_BLOCKED:
			title = "%s plant" % str(crop.display_name) if has_crop else "Blocked Soil"
			state_label = "Blocked"
	var water_capacity := maxf(0.0, float(crop.water_capacity)) if has_crop else 0.0
	var tool_requirement := ""
	if status == FARM_SIMULATION.STATE_RIPE and has_crop:
		var required_tool_label := str(crop.required_harvest_tool_label).strip_edges()
		if required_tool_label.is_empty() and not str(crop.required_harvest_tool_tag).is_empty():
			required_tool_label = str(crop.required_harvest_tool_tag).get_slice(".", 1)
		if not required_tool_label.is_empty():
			tool_requirement = "Requires tool: %s" % required_tool_label.capitalize()
	return {
		"title": title,
		"state": state_label,
		"tool_requirement": tool_requirement,
		"show_crop_bars": has_crop,
		"growth_ratio": clampf(float(cell.get("growth", 0.0)), 0.0, 1.0),
		"hydration_ratio": clampf(float(cell.get("water", 0.0)) / water_capacity, 0.0, 1.0) if water_capacity > 0.0 else 0.0,
	}


func get_details_panel_actions_at(world_position: Vector3, actor: Node = null) -> Array:
	if _field_details_mode:
		if actor == null or bool(_state.get("field_deleted", false)) \
				or not _farm.can_actor_command_plot(actor, plot_id):
			return []
		var field_actions: Array = [
			{"key": "farm_crop_menu", "label": "Crop"},
			{"key": "farm_plot|till", "label": "Till"},
			{"key": "farm_plot|expand", "label": "Expand"},
			{"key": "farm_plot|shrink", "label": "Subtract"},
		]
		if _has_mergeable_adjacent_plot(actor):
			field_actions.append({"key": "farm_plot|merge", "label": "Merge"})
		field_actions.append({"key": "farm_plot|delete", "label": "Delete"})
		return field_actions
	var actions := get_world_context_actions_at(actor, world_position)
	if not bool(_state.get("field_deleted", false)):
		actions.append({"key": "farm_select_field", "label": "Select Field"})
	return actions


func get_field_crop_options() -> Array:
	var options: Array = [{
		"crop_id": "",
		"label": "No Crop",
		"selected": str(_state.get("crop_policy_id", "")).is_empty(),
	}]
	for crop in _farm.get_crops() if _farm != null else []:
		var crop_id := str(crop.get("crop_id"))
		options.append({
			"crop_id": crop_id,
			"label": str(crop.get("display_name")),
			"selected": crop_id == str(_state.get("crop_policy_id", "")),
		})
	return options


func get_world_context_actions_at(actor: Node, world_position: Vector3) -> Array:
	if _farm == null:
		return []
	if actor != null and not _farm.can_actor_command_plot(actor, plot_id):
		return [{"key": "farm_owned", "label": "Owned by %s" % str(_state.get("owner_faction_id", "another faction"))}]
	var cell_key := _cell_key_at_world_position(world_position)
	var cells: Dictionary = _state.get("cells", {})
	if cell_key.is_empty() or not cells.has(cell_key):
		return []
	var cell: Dictionary = cells[cell_key]
	var actions: Array = []
	match str(cell.get("state", "")):
		FARM_SIMULATION.STATE_UNTILLED:
			actions.append(_cell_action("till", cell_key, "Till"))
		FARM_SIMULATION.STATE_TILLED:
			var crops: Array = _farm.get_crops()
			crops.sort_custom(func(a, b) -> bool: return str(a.display_name) < str(b.display_name))
			for crop in crops:
				if _actor_has_planting_item(actor, crop):
					actions.append(_cell_action("plant", cell_key, "Plant %s" % crop.display_name, str(crop.crop_id)))
		FARM_SIMULATION.STATE_GROWING:
			var needs_water := bool(_farm.call("cell_needs_water", plot_id, cell_key)) if _farm.has_method("cell_needs_water") else float(cell.get("water", 0.0)) <= 0.0
			if needs_water:
				actions.append(_cell_action("water", cell_key, "Water"))
		FARM_SIMULATION.STATE_RIPE:
			var crop = _farm.get_crop(str(cell.get("crop_id", "")))
			if _actor_can_harvest(actor, crop):
				actions.append(_cell_action("harvest", cell_key, "Harvest"))
		FARM_SIMULATION.STATE_WITHERED:
			actions.append(_cell_action("clear", cell_key, "Clear"))
	return actions


func _actor_has_planting_item(actor: Node, crop) -> bool:
	if actor == null or crop == null or crop.seed_item == null:
		return false
	var has_inventory_property := false
	for property in actor.get_property_list():
		if str(property.get("name", "")) == "inventory":
			has_inventory_property = true
			break
	if not has_inventory_property:
		return false
	var inventory = actor.get("inventory")
	return inventory != null and inventory.has_method("count_item") \
			and int(inventory.call("count_item", crop.seed_item)) >= maxi(1, int(crop.seed_cost_per_cell))


func _actor_can_harvest(actor: Node, crop) -> bool:
	if crop == null or str(crop.required_harvest_tool_tag).is_empty():
		return true
	if actor == null:
		return false
	var equipment = actor.call("get_equipment") if actor.has_method("get_equipment") else null
	var equipped = equipment.call("get_equipped_item", "weapon") if equipment != null and equipment.has_method("get_equipped_item") else null
	if equipped != null and equipped.has_method("has_tool_tag") and bool(equipped.call("has_tool_tag", str(crop.required_harvest_tool_tag))):
		return true
	var inventory = actor.get("inventory") if _has_object_property(actor, "inventory") else null
	if inventory == null or equipment == null or not equipment.has_method("can_equip_item_to_slot"):
		return false
	for entry in inventory.entries:
		if entry != null and entry.definition != null and entry.definition.has_tool_tag(str(crop.required_harvest_tool_tag)):
			return bool(equipment.call("can_equip_item_to_slot", entry.definition, "weapon"))
	return false


func _has_object_property(target: Object, property_name: String) -> bool:
	if target == null:
		return false
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _has_mergeable_adjacent_plot(actor: Node) -> bool:
	return actor != null and _farm != null and _farm.has_method("has_mergeable_adjacent_plot") \
			and bool(_farm.call("has_mergeable_adjacent_plot", plot_id, actor))


func perform_world_context_action(action_key: String, actors: Array = []) -> String:
	if _farm == null:
		return "Farming unavailable"
	if action_key == "farm_select_field":
		if bool(_state.get("field_deleted", false)):
			return ""
		_field_details_mode = true
		_sync_selection_overlay()
		return "Field selected"
	var parts := action_key.split("|", true)
	if parts.size() == 2 and parts[0] == "farm_policy":
		if actors.is_empty():
			return "Select a field owner first"
		var actor := actors[0] as Node
		if actor == null or not _farm.can_actor_command_plot(actor, plot_id):
			return "Cannot edit: field belongs to another faction"
		var saved: Dictionary = _farm.set_plot_crop_policy(plot_id, str(parts[1]), actor)
		if saved.is_empty():
			return "Crop policy could not be changed"
		var crop = _farm.get_crop(str(parts[1])) if not str(parts[1]).is_empty() else null
		return "Field set to %s" % (str(crop.get("display_name")) if crop != null else "No Crop")
	if parts.size() == 2 and parts[0] == "farm_plot":
		if actors.is_empty():
			return "Select a field owner first"
		var actor := actors[0] as Node
		if actor == null or not _farm.can_actor_command_plot(actor, plot_id):
			return ""
		var context := BootstrapContext.active
		if parts[1] == "till" or parts[1] == "till_all":
			var placement = context.get_optional(&"farm_placement") if context != null else null
			if parts[1] == "till":
				return str(placement.call("begin_manual_till", actor)) if placement != null and placement.has_method("begin_manual_till") else ""
			var allowed_actor_ids := _work_actor_ids([actor])
			var order: Dictionary = _farm.prepare_plot_till(plot_id, actor, allowed_actor_ids)
			var work_bridge = context.get_optional(&"farm_work") if context != null else null
			if order.is_empty() or work_bridge == null or not work_bridge.has_method("assign_cell_sequence"):
				return "No soil needs tilling"
			return str(work_bridge.call("assign_cell_sequence", order.get("targets", []), actor, true))
		if parts[1] == "delete":
			var deleted: Dictionary = _farm.delete_field(plot_id, actor)
			if not deleted.is_empty():
				_field_details_mode = false
				update_state(deleted)
			return ""
		var placement = context.get_optional(&"farm_placement") if context != null else null
		if placement == null or not placement.has_method("begin_field_edit"):
			return "Field editing unavailable"
		return str(placement.call("begin_field_edit", plot_id, str(parts[1]), actor))
	if action_key == "farm_owned":
		return "Field belongs to %s" % str(_state.get("owner_faction_id", "another faction"))
	if parts.size() >= 3 and parts[0] == "farm_field":
		if actors.is_empty():
			return "Select a worker first"
		var actor := actors[0] as Node
		if actor == null or not _farm.can_actor_command_plot(actor, plot_id):
			return ""
		var operation := str(parts[1])
		var preferred_cell_key := str(parts[2])
		var crop_id := str(parts[3]) if parts.size() >= 4 else ""
		var allowed_actor_ids := _work_actor_ids([actor])
		var order: Dictionary = _farm.prepare_plot_operation(plot_id, operation, crop_id, allowed_actor_ids, preferred_cell_key, actor)
		var context := BootstrapContext.active
		var work_bridge = context.get_optional(&"farm_work") if context != null else null
		if order.is_empty() or work_bridge == null or not work_bridge.has_method("assign_cell_sequence"):
			return "No valid field cells"
		return str(work_bridge.call("assign_cell_sequence", order.get("targets", []), actor, true))
	if parts.size() < 3 or parts[0] != "farm_cell":
		return "Unknown farming action"
	var operation := str(parts[1])
	var cell_key := str(parts[2])
	var crop_id := str(parts[3]) if parts.size() >= 4 else ""
	if actors.is_empty():
		return "Select a worker first"
	var authorized_actors: Array = []
	for actor_value in actors:
		var actor := actor_value as Node
		if actor != null and _farm.can_actor_command_plot(actor, plot_id):
			authorized_actors.append(actor)
	if authorized_actors.is_empty():
		return ""
	var allowed_actor_ids := _work_actor_ids(authorized_actors)
	if _farm.request_cell_operation(plot_id, cell_key, operation, crop_id, allowed_actor_ids).is_empty():
		return "Cell work is no longer valid"
	var context := BootstrapContext.active
	var work_bridge = context.get_optional(&"farm_work") if context != null else null
	if work_bridge == null:
		return "Farm workers unavailable"
	return work_bridge.assign_cell(plot_id, cell_key, authorized_actors)


func _work_actor_ids(actors: Array) -> PackedStringArray:
	var actor_ids := PackedStringArray()
	for actor_value in actors:
		var actor := actor_value as Node
		if actor == null or not is_instance_valid(actor):
			continue
		var actor_id := ""
		for property in actor.get_property_list():
			if str(property.get("name", "")) == "stable_id":
				actor_id = str(actor.get("stable_id"))
				break
		if actor_id.is_empty():
			actor_id = str(actor.get_meta("stable_id", ""))
		if actor_id.is_empty():
			actor_id = "instance:%d" % actor.get_instance_id()
		if not actor_ids.has(actor_id):
			actor_ids.append(actor_id)
	return actor_ids


func _cell_action(operation: String, cell_key: String, label: String, crop_id := "") -> Dictionary:
	return {"key": "farm_cell|%s|%s|%s" % [operation, cell_key, crop_id], "label": label}


func _cell_key_at_world_position(world_position: Vector3) -> String:
	var cells: Dictionary = _state.get("cells", {})
	var nearest_key := ""
	var nearest_distance := INF
	for key_value in cells.keys():
		var cell: Dictionary = cells[key_value]
		var position: Vector3 = cell.get("world_position", Vector3.ZERO)
		var distance := Vector2(position.x, position.z).distance_squared_to(Vector2(world_position.x, world_position.z))
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_key = str(key_value)
	return nearest_key


func _sync_visuals() -> void:
	var cells: Dictionary = _state.get("cells", {})
	for existing_key in _cell_holders.keys().duplicate():
		if cells.has(existing_key):
			continue
		var stale_holder = _cell_holders.get(existing_key)
		if stale_holder != null and is_instance_valid(stale_holder):
			_visual_root.remove_child(stale_holder)
			stale_holder.queue_free()
		_cell_holders.erase(existing_key)
		_visual_signatures.erase(existing_key)
	for key_value in cells.keys():
		var key := str(key_value)
		var cell: Dictionary = cells[key_value]
		var position: Vector3 = cell.get("world_position", Vector3.ZERO)
		var holder = _cell_holders.get(key) as Node3D
		if holder == null or not is_instance_valid(holder):
			holder = Node3D.new()
			holder.name = "Cell_%s" % key.replace(":", "_")
			_visual_root.add_child(holder)
			_cell_holders[key] = holder
		holder.position = position
		var signature := _cell_visual_signature(cell)
		if _visual_signatures.get(key) != signature:
			for child in holder.get_children():
				holder.remove_child(child)
				child.queue_free()
			_add_crop(holder, cell)
			_visual_signatures[key] = signature
	var soil_cells := cells.duplicate(true)
	for remnant_key in (_state.get("soil_remnants", {}) as Dictionary):
		if not soil_cells.has(remnant_key):
			soil_cells[remnant_key] = (_state.get("soil_remnants", {}) as Dictionary)[remnant_key]
	_sync_connected_soil(soil_cells)
	_sync_boundary_stakes(cells)
	_update_collision(cells)
	_sync_selection_overlay()


func _cell_visual_signature(cell: Dictionary) -> String:
	return "%s|%s|%d" % [
		str(cell.get("state", "")),
		str(cell.get("crop_id", "")),
		crop_visual_stage_index(cell),
	]


static func crop_visual_stage_index(cell: Dictionary) -> int:
	match str(cell.get("state", "")):
		FARM_SIMULATION.STATE_RIPE:
			return FARM_SIMULATION.RIPE_VISUAL_STAGE_INDEX
		FARM_SIMULATION.STATE_WITHERED:
			return FARM_SIMULATION.WITHERED_VISUAL_STAGE_INDEX
	return clampi(
		int(cell.get("stage_index", 0)),
		0,
		FARM_SIMULATION.RIPE_VISUAL_STAGE_INDEX
	)


func _add_soil(holder: Node3D, cell: Dictionary) -> void:
	var material := StandardMaterial3D.new()
	var status := str(cell.get("state", ""))
	material.albedo_color = soil_color_for_state(status)
	var visual := _instantiate_cached_visual("Ground_Soil01")
	if visual != null:
		visual.name = "Soil"
		for mesh_value in visual.find_children("*", "MeshInstance3D", true, false):
			(mesh_value as MeshInstance3D).material_override = material
		fit_visual_group_to_ground(visual, 1.10, 0.12)
		visual.position.y += 0.02
		holder.add_child(visual)
		return
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Soil"
	var box := BoxMesh.new()
	box.size = Vector3(1.12, 0.08, 1.12)
	mesh_instance.mesh = box
	mesh_instance.material_override = material
	fit_mesh_to_ground(mesh_instance, 1.12, 0.08)
	mesh_instance.position.y += 0.02
	holder.add_child(mesh_instance)


static func soil_color_for_state(status: String) -> Color:
	return Color(0.33, 0.24, 0.14) if status == FARM_SIMULATION.STATE_UNTILLED else Color(0.24, 0.13, 0.07)


func _add_crop(holder: Node3D, cell: Dictionary) -> void:
	var crop_id := str(cell.get("crop_id", ""))
	if crop_id.is_empty() or _farm == null:
		return
	var crop: Variant = _farm.get_crop(crop_id)
	if crop == null:
		return
	var visual_stage := crop_visual_stage_index(cell)
	var crop_state := str(cell.get("state", ""))
	if crop.procedural_visual == "wheat":
		_add_wheat(holder, visual_stage, crop_state)
		return
	var instance := _instantiate_cached_visual(crop.get_stage_node_name(visual_stage))
	if instance == null:
		return
	instance.name = "Crop"
	var live_stage := mini(visual_stage, FARM_SIMULATION.RIPE_VISUAL_STAGE_INDEX)
	var desired_height := lerpf(
		0.18,
		1.24,
		float(live_stage + 1) / float(FARM_SIMULATION.GROWTH_VISUAL_STAGE_COUNT)
	)
	fit_visual_group_to_ground(instance, 1.02, desired_height)
	holder.add_child(instance)


func _add_wheat(holder: Node3D, stage: int, crop_state: String) -> void:
	var live_stage := mini(stage, FARM_SIMULATION.RIPE_VISUAL_STAGE_INDEX)
	var height := lerpf(0.08, 1.05, float(live_stage + 1) / float(FARM_SIMULATION.GROWTH_VISUAL_STAGE_COUNT))
	for index in 7:
		var stalk := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.018
		cylinder.bottom_radius = 0.026
		cylinder.height = height
		stalk.mesh = cylinder
		stalk.position = Vector3((index % 3 - 1) * 0.16, height * 0.5, (index / 3 - 1) * 0.16)
		var material := StandardMaterial3D.new()
		match crop_state:
			FARM_SIMULATION.STATE_RIPE:
				material.albedo_color = Color(0.78, 0.62, 0.18)
			FARM_SIMULATION.STATE_WITHERED:
				material.albedo_color = Color(0.34, 0.23, 0.10)
			_:
				material.albedo_color = Color(0.39, 0.61, 0.19)
		stalk.material_override = material
		holder.add_child(stalk)


func _sync_connected_soil(cells: Dictionary) -> void:
	if _soil_surface == null:
		return
	_soil_surface.mesh = build_connected_soil_mesh(cells_with_created_soil(cells), float(_state.get("cell_size", 1.25)))
	_soil_surface.material_override = build_soil_material()


static func cells_with_created_soil(cells: Dictionary) -> Dictionary:
	var created: Dictionary = {}
	for key_value in cells.keys():
		var cell: Dictionary = cells[key_value]
		if _cell_has_created_soil(cell):
			created[key_value] = cell
	return created


static func _cell_has_created_soil(cell: Dictionary) -> bool:
	if cell.has("soil_created"):
		return bool(cell.get("soil_created", false))
	var state := str(cell.get("state", FARM_SIMULATION.STATE_UNTILLED))
	if state == FARM_SIMULATION.STATE_BLOCKED:
		var displaced = cell.get("displaced_state")
		return _cell_has_created_soil(displaced as Dictionary) if displaced is Dictionary else false
	return state != FARM_SIMULATION.STATE_UNTILLED


func _sync_boundary_stakes(cells: Dictionary) -> void:
	if _stake_root == null:
		return
	var positions := [] if bool(_state.get("field_deleted", false)) else boundary_stake_positions(cells, float(_state.get("cell_size", 1.25)))
	var signature_parts := PackedStringArray()
	for point in positions:
		signature_parts.append(str(point.snapped(Vector3.ONE * 0.001)))
	var signature := "|".join(signature_parts)
	if signature == _stake_signature:
		return
	_stake_signature = signature
	for child in _stake_root.get_children():
		child.queue_free()
	var stake_mesh := CylinderMesh.new()
	stake_mesh.top_radius = 0.012
	stake_mesh.bottom_radius = 0.026
	stake_mesh.height = 0.32
	stake_mesh.radial_segments = 6
	var stake_material := StandardMaterial3D.new()
	stake_material.albedo_color = Color(0.24, 0.13, 0.055)
	stake_material.roughness = 1.0
	for point in positions:
		var stake := MeshInstance3D.new()
		stake.name = "BoundaryStake"
		stake.mesh = stake_mesh
		stake.material_override = stake_material
		stake.position = point + Vector3.UP * 0.16
		_stake_root.add_child(stake)


static func boundary_stake_positions(cells: Dictionary, cell_size: float) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	if cells.is_empty():
		return positions
	var spacing := maxf(0.25, cell_size)
	var cells_by_grid: Dictionary = {}
	for cell_value in cells.values():
		var cell: Dictionary = cell_value
		var grid: Vector2i = cell.get("grid_position", Vector2i.ZERO)
		cells_by_grid["%d:%d" % [grid.x, grid.y]] = cell
	var corner_sums: Dictionary = {}
	var corner_counts: Dictionary = {}
	var edge_specs := [
		{"neighbor": Vector2i(0, -1), "corners": [Vector2i.ZERO, Vector2i(1, 0)]},
		{"neighbor": Vector2i(1, 0), "corners": [Vector2i(1, 0), Vector2i(1, 1)]},
		{"neighbor": Vector2i(0, 1), "corners": [Vector2i(1, 1), Vector2i(0, 1)]},
		{"neighbor": Vector2i(-1, 0), "corners": [Vector2i(0, 1), Vector2i.ZERO]},
	]
	for cell_value in cells.values():
		var cell: Dictionary = cell_value
		var grid: Vector2i = cell.get("grid_position", Vector2i.ZERO)
		var center: Vector3 = cell.get("world_position", Vector3.ZERO)
		for edge_value in edge_specs:
			var edge: Dictionary = edge_value
			var neighbor: Vector2i = grid + (edge.get("neighbor", Vector2i.ZERO) as Vector2i)
			if cells_by_grid.has("%d:%d" % [neighbor.x, neighbor.y]):
				continue
			for offset_value in edge.get("corners", []):
				var offset: Vector2i = offset_value
				var corner := grid + offset
				var key := "%d:%d" % [corner.x, corner.y]
				var point := center + Vector3((float(offset.x) - 0.5) * spacing, 0.02, (float(offset.y) - 0.5) * spacing)
				corner_sums[key] = (corner_sums.get(key, Vector3.ZERO) as Vector3) + point
				corner_counts[key] = int(corner_counts.get(key, 0)) + 1
	var corner_keys: Array = corner_sums.keys()
	corner_keys.sort()
	for key_value in corner_keys:
		var key := str(key_value)
		positions.append((corner_sums[key] as Vector3) / float(maxi(1, int(corner_counts.get(key, 1)))))
	return positions


func _sync_selection_overlay() -> void:
	if _selection_root == null or not is_instance_valid(_selection_root):
		return
	_selection_root.visible = _inspected and _field_details_mode and not bool(_state.get("field_deleted", false))
	if not _selection_root.visible:
		return
	var cells: Dictionary = _state.get("cells", {})
	var cell_size := float(_state.get("cell_size", 1.25))
	_selection_fill.mesh = build_field_selection_mesh(cells, cell_size, false)
	_selection_border.mesh = build_field_selection_mesh(cells, cell_size, true)
	var fill_material := StandardMaterial3D.new()
	fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	fill_material.albedo_color = Color(0.08, 0.92, 0.22, 0.09)
	_selection_fill.material_override = fill_material
	var border_material := StandardMaterial3D.new()
	border_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	border_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	border_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	border_material.albedo_color = Color(0.04, 0.95, 0.20, 0.96)
	_selection_border.material_override = border_material


static func build_field_selection_mesh(cells: Dictionary, cell_size: float, border_only: bool) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if cells.is_empty():
		return mesh
	var spacing := maxf(0.25, cell_size)
	var half := spacing * 0.5
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var cells_by_grid: Dictionary = {}
	for cell_value in cells.values():
		var cell: Dictionary = cell_value
		var grid: Vector2i = cell.get("grid_position", Vector2i.ZERO)
		cells_by_grid["%d:%d" % [grid.x, grid.y]] = true
	if border_only:
		var edges := [
			{"neighbor": Vector2i(0, -1), "a": Vector3(-half, 0.085, -half), "b": Vector3(half, 0.085, -half)},
			{"neighbor": Vector2i(1, 0), "a": Vector3(half, 0.085, -half), "b": Vector3(half, 0.085, half)},
			{"neighbor": Vector2i(0, 1), "a": Vector3(half, 0.085, half), "b": Vector3(-half, 0.085, half)},
			{"neighbor": Vector2i(-1, 0), "a": Vector3(-half, 0.085, half), "b": Vector3(-half, 0.085, -half)},
		]
		for cell_value in cells.values():
			var cell: Dictionary = cell_value
			var grid: Vector2i = cell.get("grid_position", Vector2i.ZERO)
			var center: Vector3 = cell.get("world_position", Vector3.ZERO)
			for edge_value in edges:
				var edge: Dictionary = edge_value
				var neighbor: Vector2i = grid + (edge.get("neighbor", Vector2i.ZERO) as Vector2i)
				if cells_by_grid.has("%d:%d" % [neighbor.x, neighbor.y]):
					continue
				var a := center + (edge.get("a", Vector3.ZERO) as Vector3)
				var b := center + (edge.get("b", Vector3.ZERO) as Vector3)
				var direction := (b - a).normalized()
				var perpendicular := Vector3(-direction.z, 0.0, direction.x) * 0.035
				_append_quad(vertices, a - perpendicular, b - perpendicular, b + perpendicular, a + perpendicular)
	else:
		for cell_value in cells.values():
			var center: Vector3 = (cell_value as Dictionary).get("world_position", Vector3.ZERO) + Vector3.UP * 0.075
			_append_quad(
				vertices,
				center + Vector3(-half, 0.0, -half),
				center + Vector3(half, 0.0, -half),
				center + Vector3(half, 0.0, half),
				center + Vector3(-half, 0.0, half)
			)
	for _index in vertices.size():
		normals.append(Vector3.UP)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _append_quad(vertices: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for point in [a, b, c, a, c, d]:
		vertices.append(point)


static func build_soil_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_BACK
	return material


static func build_connected_soil_mesh(cells: Dictionary, cell_size: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if cells.is_empty():
		return mesh
	var spacing := maxf(0.25, cell_size)
	var corner_positions: Dictionary = {}
	var corner_colors: Dictionary = {}
	var corner_counts: Dictionary = {}
	var cells_by_grid: Dictionary = {}
	for cell_value in cells.values():
		var cell: Dictionary = cell_value
		var grid: Vector2i = cell.get("grid_position", Vector2i.ZERO)
		cells_by_grid["%d:%d" % [grid.x, grid.y]] = cell
		var center: Vector3 = cell.get("world_position", Vector3.ZERO)
		var color := soil_color_for_state(str(cell.get("state", "")))
		for offset in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
			var corner: Vector2i = grid + (offset as Vector2i)
			var key := "%d:%d" % [corner.x, corner.y]
			var point := center + Vector3((float(offset.x) - 0.5) * spacing, 0.025, (float(offset.y) - 0.5) * spacing)
			corner_positions[key] = (corner_positions.get(key, Vector3.ZERO) as Vector3) + point
			corner_colors[key] = (corner_colors.get(key, Color(0, 0, 0, 0)) as Color) + color
			corner_counts[key] = int(corner_counts.get(key, 0)) + 1
	var resolved_positions: Dictionary = {}
	var resolved_colors: Dictionary = {}
	for key_value in corner_positions.keys():
		var key := str(key_value)
		var count := maxi(1, int(corner_counts.get(key, 1)))
		var point: Vector3 = (corner_positions[key] as Vector3) / float(count)
		var parts := key.split(":", false, 1)
		var corner := Vector2i(int(parts[0]), int(parts[1]))
		var adjacent := 0
		for offset in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i.ZERO]:
			var candidate: Vector2i = corner + (offset as Vector2i)
			if cells_by_grid.has("%d:%d" % [candidate.x, candidate.y]):
				adjacent += 1
		if adjacent < 4:
			var noise := absi(corner.x * 73856093 ^ corner.y * 19349663)
			point.x += (float(noise % 101) / 100.0 - 0.5) * spacing * 0.10
			point.z += (float((noise / 101) % 101) / 100.0 - 0.5) * spacing * 0.10
		resolved_positions[key] = point
		resolved_colors[key] = (corner_colors[key] as Color) / float(count)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for cell_value in cells.values():
		var cell: Dictionary = cell_value
		var grid: Vector2i = cell.get("grid_position", Vector2i.ZERO)
		var keys := [
			"%d:%d" % [grid.x, grid.y],
			"%d:%d" % [grid.x + 1, grid.y],
			"%d:%d" % [grid.x + 1, grid.y + 1],
			"%d:%d" % [grid.x, grid.y + 1],
		]
		# Godot front faces wind clockwise when viewed from above.
		for index in [0, 1, 2, 0, 2, 3]:
			vertices.append(resolved_positions[keys[index]] as Vector3)
			normals.append(Vector3.UP)
			colors.append(resolved_colors[keys[index]] as Color)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _update_collision(cells: Dictionary) -> void:
	if _collision_root == null:
		return
	var signature_parts := PackedStringArray()
	for key_value in cells.keys():
		var cell: Dictionary = cells[key_value]
		signature_parts.append("%s@%s" % [str(key_value), cell.get("world_position", Vector3.ZERO)])
	signature_parts.sort()
	var signature := "|".join(signature_parts)
	if signature == _collision_signature:
		return
	_collision_signature = signature
	for child in _collision_root.get_children():
		child.queue_free()
	var cell_size := float(_state.get("cell_size", 1.25))
	for cell_value in cells.values():
		var cell: Dictionary = cell_value
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(cell_size * 0.94, 0.4, cell_size * 0.94)
		collision.shape = shape
		collision.position = (cell.get("world_position", Vector3.ZERO) as Vector3) + Vector3.UP * 0.2
		_collision_root.add_child(collision)


static func _build_visual_cache() -> void:
	if not _visual_cache.is_empty():
		return
	var source := CROP_SOURCE.instantiate()
	_cache_visual_nodes_recursive(source)
	source.free()


static func fit_mesh_to_ground(instance: MeshInstance3D, target_diameter: float, target_height: float) -> void:
	if instance == null or instance.mesh == null:
		return
	var box := instance.mesh.get_aabb()
	if box.size.length_squared() <= 0.000001:
		return
	var horizontal := maxf(box.size.x, box.size.z)
	var horizontal_scale := target_diameter / horizontal if horizontal > 0.0001 else INF
	var vertical_scale := target_height / box.size.y if box.size.y > 0.0001 else INF
	var uniform_scale := minf(horizontal_scale, vertical_scale)
	if not is_finite(uniform_scale) or uniform_scale <= 0.0:
		uniform_scale = 1.0
	instance.scale = Vector3.ONE * uniform_scale
	var center := box.get_center()
	instance.position = Vector3(-center.x * uniform_scale, -box.position.y * uniform_scale, -center.z * uniform_scale)


static func fit_visual_group_to_ground(group: Node3D, target_diameter: float, target_height: float) -> void:
	if group == null:
		return
	var mesh_nodes: Array = group.find_children("*", "MeshInstance3D", true, false)
	if mesh_nodes.is_empty():
		return
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	for mesh_value in mesh_nodes:
		var mesh_instance := mesh_value as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var relative := _transform_from_ancestor(mesh_instance, group)
		var box := mesh_instance.mesh.get_aabb()
		for x in [box.position.x, box.end.x]:
			for y in [box.position.y, box.end.y]:
				for z in [box.position.z, box.end.z]:
					var point := relative * Vector3(x, y, z)
					minimum = minimum.min(point)
					maximum = maximum.max(point)
	var size := maximum - minimum
	if not size.is_finite() or size.length_squared() <= 0.000001:
		return
	var horizontal := maxf(size.x, size.z)
	var horizontal_scale := target_diameter / horizontal if horizontal > 0.0001 else INF
	var vertical_scale := target_height / size.y if size.y > 0.0001 else INF
	var uniform_scale := minf(horizontal_scale, vertical_scale)
	if not is_finite(uniform_scale) or uniform_scale <= 0.0:
		uniform_scale = 1.0
	group.scale = Vector3.ONE * uniform_scale
	var center := (minimum + maximum) * 0.5
	group.position = Vector3(-center.x * uniform_scale, -minimum.y * uniform_scale, -center.z * uniform_scale)


static func _cache_visual_nodes_recursive(node: Node) -> void:
	var node_name := str(node.name)
	if node is Node3D and (node_name == "Ground_Soil01" or (node_name.begins_with("Crop_") and node_name.contains("_Stage"))):
		var entries: Array[Dictionary] = []
		for mesh_value in node.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := mesh_value as MeshInstance3D
			if mesh_instance.mesh != null:
				entries.append({"mesh": mesh_instance.mesh, "transform": _transform_from_ancestor(mesh_instance, node)})
		if not entries.is_empty():
			_visual_cache[node_name] = entries
	for child in node.get_children():
		_cache_visual_nodes_recursive(child)


static func _instantiate_cached_visual(key: String) -> Node3D:
	var entries: Array = _visual_cache.get(key, [])
	if entries.is_empty():
		return null
	var visual := Node3D.new()
	for entry_value in entries:
		var entry: Dictionary = entry_value
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = entry.get("mesh") as Mesh
		mesh_instance.transform = entry.get("transform", Transform3D.IDENTITY)
		visual.add_child(mesh_instance)
	return visual


static func _transform_from_ancestor(node: Node3D, ancestor: Node) -> Transform3D:
	var result := node.transform
	var current := node.get_parent()
	while current != null and current != ancestor:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result
