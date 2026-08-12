extends Area3D

class_name FarmPlotProjection

const CROP_SOURCE := preload("res://assets/vendor/luceed-studio/farm-crops-01/crops01.glb")
const FARM_SIMULATION := preload("res://features/farming/sim/farm_simulation.gd")
const SOIL_ALBEDO := preload("res://assets/vendor/larkart-store/stylized-soil-02a/T_Soil02A_C.png")
const SOIL_NORMAL := preload("res://assets/vendor/larkart-store/stylized-soil-02a/T_Soil02A_N.png")
const SOIL_ROUGHNESS := preload("res://assets/vendor/larkart-store/stylized-soil-02a/T_Soil02A_R.png")
const SOIL_AO := preload("res://assets/vendor/larkart-store/stylized-soil-02a/T_Soil02A_AO.png")
const SOIL_MOUND_SADDLE_HEIGHT := 0.085
const SOIL_MOUND_CROWN_HEIGHT := 0.035
const SOIL_CROP_ROOT_HEIGHT := 0.132
const SOIL_OUTER_TAPER_FRACTION := 0.40
const SOIL_PERIMETER_SKIRT_DEPTH := 0.35
const SOIL_MESH_SUBDIVISIONS := 4
const SOIL_TEXTURE_WORLD_SCALE := 2.4
const SOIL_ASYNC_BUILD_CELL_THRESHOLD := 64
const SOIL_NEIGHBOR_WEST := 1 << 0
const SOIL_NEIGHBOR_EAST := 1 << 1
const SOIL_NEIGHBOR_NORTH := 1 << 2
const SOIL_NEIGHBOR_SOUTH := 1 << 3
const SOIL_NEIGHBOR_NORTHWEST := 1 << 4
const SOIL_NEIGHBOR_NORTHEAST := 1 << 5
const SOIL_NEIGHBOR_SOUTHEAST := 1 << 6
const SOIL_NEIGHBOR_SOUTHWEST := 1 << 7

static var _visual_cache: Dictionary = {}
static var _soil_material_cache: StandardMaterial3D

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
var _soil_signature := ""
var _soil_requested_signature := "<uninitialized>"
var _soil_build_signature := ""
var _soil_build_active := false
var _soil_pending_valid := false
var _soil_pending_signature := ""
var _soil_pending_cells: Dictionary = {}
var _soil_pending_cell_size := 1.25
var _soil_task_id := -1
var _soil_reclaimed_task_count := 0
var _soil_last_reclaim_result := FAILED
var _soil_shutting_down := false
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
	_soil_surface.material_override = build_soil_material()
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


func _exit_tree() -> void:
	_soil_shutting_down = true
	_clear_pending_connected_soil_build()
	if _soil_task_id >= 0:
		_reclaim_connected_soil_task()
	_soil_build_active = false
	_soil_build_signature = ""


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
	var pivot := Node3D.new()
	pivot.name = "Crop"
	instance.name = "Visual"
	pivot.add_child(instance)
	var live_stage := mini(visual_stage, FARM_SIMULATION.RIPE_VISUAL_STAGE_INDEX)
	var desired_height := lerpf(
		0.18,
		1.0,
		float(live_stage + 1) / float(FARM_SIMULATION.GROWTH_VISUAL_STAGE_COUNT)
	)
	var desired_diameter := lerpf(
		0.38,
		0.78,
		float(live_stage + 1) / float(FARM_SIMULATION.GROWTH_VISUAL_STAGE_COUNT)
	)
	fit_visual_group_to_ground(instance, desired_diameter, desired_height)
	instance.position.y += SOIL_CROP_ROOT_HEIGHT
	var grid: Vector2i = cell.get("grid_position", Vector2i.ZERO)
	pivot.rotation.y = deg_to_rad(float(posmod(grid.x * 17 + grid.y * 29, 15) - 7))
	holder.add_child(pivot)


func _add_wheat(holder: Node3D, stage: int, crop_state: String) -> void:
	var live_stage := mini(stage, FARM_SIMULATION.RIPE_VISUAL_STAGE_INDEX)
	var height := lerpf(0.10, 1.02, float(live_stage + 1) / float(FARM_SIMULATION.GROWTH_VISUAL_STAGE_COUNT))
	var material := StandardMaterial3D.new()
	material.roughness = 0.92
	match crop_state:
		FARM_SIMULATION.STATE_RIPE:
			material.albedo_color = Color(0.56, 0.38, 0.09)
		FARM_SIMULATION.STATE_WITHERED:
			material.albedo_color = Color(0.29, 0.19, 0.075)
		_:
			material.albedo_color = Color(0.30, 0.49, 0.14)
	var positions := [
		Vector2(-0.21, -0.18), Vector2(0.0, -0.22), Vector2(0.22, -0.15),
		Vector2(-0.24, 0.03), Vector2(0.03, 0.0), Vector2(0.24, 0.08),
		Vector2(-0.16, 0.23), Vector2(0.08, 0.22), Vector2(0.25, 0.26),
	]
	var stalk_mesh := CylinderMesh.new()
	stalk_mesh.top_radius = 0.012
	stalk_mesh.bottom_radius = 0.022
	stalk_mesh.height = height
	stalk_mesh.radial_segments = 5
	var stalk_multimesh := MultiMesh.new()
	stalk_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	stalk_multimesh.mesh = stalk_mesh
	stalk_multimesh.instance_count = positions.size()
	for index in positions.size():
		var point: Vector2 = positions[index]
		var height_scale := lerpf(0.86, 1.08, float(index * 7 % 9) / 8.0)
		var basis := Basis(Vector3.UP, deg_to_rad(float(index * 37 % 13 - 6)))
		basis = Basis(Vector3.RIGHT, deg_to_rad(float(index * 5 % 9 - 4))) * basis
		basis = basis.scaled(Vector3(1.0, height_scale, 1.0))
		stalk_multimesh.set_instance_transform(index, Transform3D(basis, Vector3(point.x, SOIL_CROP_ROOT_HEIGHT + height * height_scale * 0.5, point.y)))
	var stalks := MultiMeshInstance3D.new()
	stalks.name = "WheatStalks"
	stalks.multimesh = stalk_multimesh
	stalks.material_override = material
	holder.add_child(stalks)
	if live_stage < 3:
		return
	var head_height := lerpf(0.075, 0.16, float(live_stage - 2) / float(FARM_SIMULATION.RIPE_VISUAL_STAGE_INDEX - 2))
	var head_mesh := CapsuleMesh.new()
	head_mesh.radius = 0.034
	head_mesh.height = head_height
	head_mesh.radial_segments = 5
	head_mesh.rings = 2
	var head_multimesh := MultiMesh.new()
	head_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	head_multimesh.mesh = head_mesh
	head_multimesh.instance_count = positions.size()
	for index in positions.size():
		var point: Vector2 = positions[index]
		var height_scale := lerpf(0.86, 1.08, float(index * 7 % 9) / 8.0)
		var basis := Basis(Vector3.RIGHT, deg_to_rad(float(index * 5 % 9 - 4)))
		head_multimesh.set_instance_transform(index, Transform3D(basis, Vector3(point.x, SOIL_CROP_ROOT_HEIGHT + height * height_scale + head_height * 0.35, point.y)))
	var heads := MultiMeshInstance3D.new()
	heads.name = "WheatHeads"
	heads.multimesh = head_multimesh
	heads.material_override = material
	holder.add_child(heads)


func _sync_connected_soil(cells: Dictionary) -> void:
	if _soil_surface == null or _soil_shutting_down:
		return
	var created_cells := cells_with_created_soil(cells)
	var signature_parts := PackedStringArray()
	var cell_size := float(_state.get("cell_size", 1.25))
	signature_parts.append("cell_size=%s" % cell_size)
	for key_value in created_cells:
		var cell: Dictionary = created_cells[key_value]
		signature_parts.append("%s@%s" % [str(key_value), cell.get("world_position", Vector3.ZERO)])
	signature_parts.sort()
	var signature := "|".join(signature_parts)
	if signature == _soil_requested_signature and (_soil_surface.mesh != null or _soil_build_active or _soil_pending_valid):
		return
	_soil_requested_signature = signature
	_clear_pending_connected_soil_build()
	if created_cells.is_empty():
		_soil_surface.mesh = ArrayMesh.new()
		_soil_signature = signature
		return
	if created_cells.size() <= SOIL_ASYNC_BUILD_CELL_THRESHOLD:
		_soil_surface.mesh = build_connected_soil_mesh(created_cells, cell_size)
		_soil_signature = signature
		return
	_soil_pending_valid = true
	_soil_pending_signature = signature
	_soil_pending_cells = created_cells.duplicate(true)
	_soil_pending_cell_size = cell_size
	if not _soil_build_active:
		_begin_connected_soil_build()


func _begin_connected_soil_build() -> void:
	if _soil_shutting_down or not _soil_pending_valid:
		return
	var cells := _soil_pending_cells
	var cell_size := _soil_pending_cell_size
	_soil_build_signature = _soil_pending_signature
	_clear_pending_connected_soil_build()
	_soil_build_active = true
	_soil_task_id = WorkerThreadPool.add_task(
		_build_connected_soil_task.bind(cells, cell_size, _soil_build_signature),
		false,
		"FarmConnectedSoil"
	)
	if _soil_task_id < 0:
		_soil_build_active = false
		var mesh := build_connected_soil_mesh(cells, cell_size)
		if _soil_build_signature == _soil_requested_signature:
			_soil_surface.mesh = mesh
			_soil_signature = _soil_build_signature


func _build_connected_soil_task(cells: Dictionary, cell_size: float, signature: String) -> void:
	var mesh := build_connected_soil_mesh(cells, cell_size)
	_finish_connected_soil_build.call_deferred(signature, mesh)


func _finish_connected_soil_build(completed_signature: String, completed_mesh: ArrayMesh) -> void:
	if _soil_task_id >= 0:
		_reclaim_connected_soil_task()
	_soil_build_active = false
	if _soil_shutting_down:
		_clear_pending_connected_soil_build()
		return
	if completed_mesh != null and completed_signature == _soil_requested_signature:
		_soil_surface.mesh = completed_mesh
		_soil_signature = completed_signature
	if _soil_pending_valid:
		_begin_connected_soil_build()


func _clear_pending_connected_soil_build() -> void:
	_soil_pending_valid = false
	_soil_pending_signature = ""
	_soil_pending_cells = {}


func _reclaim_connected_soil_task() -> void:
	if _soil_task_id < 0:
		return
	_soil_last_reclaim_result = int(WorkerThreadPool.wait_for_task_completion(_soil_task_id))
	_soil_task_id = -1
	if _soil_last_reclaim_result != OK:
		push_warning("Connected-soil worker task reclamation failed: %d" % _soil_last_reclaim_result)
		return
	_soil_reclaimed_task_count += 1


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
	if _soil_material_cache != null:
		return _soil_material_cache
	_soil_material_cache = StandardMaterial3D.new()
	_soil_material_cache.albedo_texture = SOIL_ALBEDO
	_soil_material_cache.albedo_color = Color(0.68, 0.58, 0.48)
	_soil_material_cache.vertex_color_use_as_albedo = true
	_soil_material_cache.normal_enabled = true
	_soil_material_cache.normal_texture = SOIL_NORMAL
	_soil_material_cache.normal_scale = 0.42
	_soil_material_cache.roughness = 0.94
	_soil_material_cache.roughness_texture = SOIL_ROUGHNESS
	_soil_material_cache.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	_soil_material_cache.ao_enabled = true
	_soil_material_cache.ao_texture = SOIL_AO
	_soil_material_cache.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	_soil_material_cache.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_soil_material_cache.cull_mode = BaseMaterial3D.CULL_BACK
	return _soil_material_cache


static func build_connected_soil_mesh(cells: Dictionary, cell_size: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if cells.is_empty():
		return mesh
	var spacing := maxf(0.25, cell_size)
	var cells_by_grid: Dictionary = {}
	var corner_height_sums: Dictionary = {}
	var corner_height_counts: Dictionary = {}
	for cell_value in cells.values():
		var cell: Dictionary = cell_value
		var grid: Vector2i = cell.get("grid_position", Vector2i.ZERO)
		cells_by_grid[_soil_grid_key(grid)] = cell
		var center: Vector3 = cell.get("world_position", Vector3.ZERO)
		for corner_offset in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
			var corner: Vector2i = grid + (corner_offset as Vector2i)
			var corner_key := _soil_grid_key(corner)
			corner_height_sums[corner_key] = float(corner_height_sums.get(corner_key, 0.0)) + center.y
			corner_height_counts[corner_key] = int(corner_height_counts.get(corner_key, 0)) + 1
	var corner_heights: Dictionary = {}
	for corner_key_value in corner_height_sums:
		var corner_key := str(corner_key_value)
		corner_heights[corner_key] = float(corner_height_sums[corner_key]) / float(maxi(1, int(corner_height_counts[corner_key])))
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var point_indices: Dictionary = {}
	var sorted_keys: Array = cells.keys()
	sorted_keys.sort()
	for key_value in sorted_keys:
		var cell: Dictionary = cells[key_value]
		var center: Vector3 = cell.get("world_position", Vector3.ZERO)
		var grid: Vector2i = cell.get("grid_position", Vector2i.ZERO)
		var neighbor_mask := 0
		neighbor_mask |= SOIL_NEIGHBOR_WEST if cells_by_grid.has(_soil_grid_key(grid + Vector2i.LEFT)) else 0
		neighbor_mask |= SOIL_NEIGHBOR_EAST if cells_by_grid.has(_soil_grid_key(grid + Vector2i.RIGHT)) else 0
		neighbor_mask |= SOIL_NEIGHBOR_NORTH if cells_by_grid.has(_soil_grid_key(grid + Vector2i.UP)) else 0
		neighbor_mask |= SOIL_NEIGHBOR_SOUTH if cells_by_grid.has(_soil_grid_key(grid + Vector2i.DOWN)) else 0
		neighbor_mask |= SOIL_NEIGHBOR_NORTHWEST if cells_by_grid.has(_soil_grid_key(grid + Vector2i.LEFT + Vector2i.UP)) else 0
		neighbor_mask |= SOIL_NEIGHBOR_NORTHEAST if cells_by_grid.has(_soil_grid_key(grid + Vector2i.RIGHT + Vector2i.UP)) else 0
		neighbor_mask |= SOIL_NEIGHBOR_SOUTHEAST if cells_by_grid.has(_soil_grid_key(grid + Vector2i.RIGHT + Vector2i.DOWN)) else 0
		neighbor_mask |= SOIL_NEIGHBOR_SOUTHWEST if cells_by_grid.has(_soil_grid_key(grid + Vector2i.LEFT + Vector2i.DOWN)) else 0
		var h00 := float(corner_heights.get(_soil_grid_key(grid), center.y))
		var h10 := float(corner_heights.get(_soil_grid_key(grid + Vector2i.RIGHT), center.y))
		var h11 := float(corner_heights.get(_soil_grid_key(grid + Vector2i.ONE), center.y))
		var h01 := float(corner_heights.get(_soil_grid_key(grid + Vector2i.DOWN), center.y))
		var bilinear_center := (h00 + h10 + h11 + h01) * 0.25
		var terrain_center_correction := center.y - bilinear_center
		var crown_scale := lerpf(0.92, 1.08, float(posmod(grid.x * 31 + grid.y * 17, 17)) / 16.0)
		var row_size := SOIL_MESH_SUBDIVISIONS + 1
		var cell_point_indices := PackedInt32Array()
		cell_point_indices.resize(row_size * row_size)
		for sub_z in row_size:
			for sub_x in row_size:
				var point_key := Vector2i(
					grid.x * SOIL_MESH_SUBDIVISIONS + sub_x,
					grid.y * SOIL_MESH_SUBDIVISIONS + sub_z
				)
				var point_index := int(point_indices.get(point_key, -1))
				if point_index < 0:
					var u := float(sub_x) / float(SOIL_MESH_SUBDIVISIONS)
					var v := float(sub_z) / float(SOIL_MESH_SUBDIVISIONS)
					var edge_factor := _soil_edge_factor(u, v, neighbor_mask)
					var point := _connected_soil_point(center, spacing, u, v, h00, h10, h11, h01, terrain_center_correction, crown_scale, edge_factor)
					var side_brightness := lerpf(0.52, 1.0, smoothstep(0.0, 0.92, edge_factor))
					point_index = vertices.size()
					vertices.append(point)
					uvs.append(Vector2(point.x, point.z) / SOIL_TEXTURE_WORLD_SCALE)
					colors.append(Color(side_brightness, side_brightness, side_brightness))
					point_indices[point_key] = point_index
				cell_point_indices[sub_z * row_size + sub_x] = point_index
		for sub_z in SOIL_MESH_SUBDIVISIONS:
			for sub_x in SOIL_MESH_SUBDIVISIONS:
				var p00 := cell_point_indices[sub_z * row_size + sub_x]
				var p10 := cell_point_indices[sub_z * row_size + sub_x + 1]
				var p11 := cell_point_indices[(sub_z + 1) * row_size + sub_x + 1]
				var p01 := cell_point_indices[(sub_z + 1) * row_size + sub_x]
				for point_index in [p00, p10, p11, p00, p11, p01]:
					indices.append(point_index)
		if (neighbor_mask & SOIL_NEIGHBOR_NORTH) == 0:
			for sub_x in SOIL_MESH_SUBDIVISIONS:
				_append_soil_skirt_segment(vertices, uvs, colors, indices, cell_point_indices[sub_x], cell_point_indices[sub_x + 1])
		if (neighbor_mask & SOIL_NEIGHBOR_EAST) == 0:
			for sub_z in SOIL_MESH_SUBDIVISIONS:
				_append_soil_skirt_segment(vertices, uvs, colors, indices, cell_point_indices[sub_z * row_size + SOIL_MESH_SUBDIVISIONS], cell_point_indices[(sub_z + 1) * row_size + SOIL_MESH_SUBDIVISIONS])
		if (neighbor_mask & SOIL_NEIGHBOR_SOUTH) == 0:
			for sub_x in SOIL_MESH_SUBDIVISIONS:
				_append_soil_skirt_segment(vertices, uvs, colors, indices, cell_point_indices[row_size * row_size - 1 - sub_x], cell_point_indices[row_size * row_size - 2 - sub_x])
		if (neighbor_mask & SOIL_NEIGHBOR_WEST) == 0:
			for sub_z in SOIL_MESH_SUBDIVISIONS:
				_append_soil_skirt_segment(vertices, uvs, colors, indices, cell_point_indices[(SOIL_MESH_SUBDIVISIONS - sub_z) * row_size], cell_point_indices[(SOIL_MESH_SUBDIVISIONS - sub_z - 1) * row_size])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var surface_tool := SurfaceTool.new()
	surface_tool.create_from_arrays(arrays)
	surface_tool.generate_normals()
	surface_tool.generate_tangents()
	return surface_tool.commit()


static func _append_soil_skirt_segment(vertices: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array, top_a_index: int, top_b_index: int) -> void:
	var top_a := vertices[top_a_index]
	var top_b := vertices[top_b_index]
	var bottom_a := top_a - Vector3.UP * SOIL_PERIMETER_SKIRT_DEPTH
	var bottom_b := top_b - Vector3.UP * SOIL_PERIMETER_SKIRT_DEPTH
	var horizontal_a := (top_a.x + top_a.z) / SOIL_TEXTURE_WORLD_SCALE
	var horizontal_b := (top_b.x + top_b.z) / SOIL_TEXTURE_WORLD_SCALE
	var side_top_a_index := vertices.size()
	for point in [top_a, top_b, bottom_b, bottom_a]:
		vertices.append(point)
	uvs.append(Vector2(horizontal_a, 0.0))
	uvs.append(Vector2(horizontal_b, 0.0))
	uvs.append(Vector2(horizontal_b, SOIL_PERIMETER_SKIRT_DEPTH / SOIL_TEXTURE_WORLD_SCALE))
	uvs.append(Vector2(horizontal_a, SOIL_PERIMETER_SKIRT_DEPTH / SOIL_TEXTURE_WORLD_SCALE))
	colors.append(Color(0.52, 0.52, 0.52))
	colors.append(Color(0.52, 0.52, 0.52))
	colors.append(Color(0.34, 0.34, 0.34))
	colors.append(Color(0.34, 0.34, 0.34))
	# Godot treats clockwise triangle winding as front-facing. These faces point
	# outward so back-face culling hides only the buried interior side.
	for point_index in [side_top_a_index, side_top_a_index + 2, side_top_a_index + 1, side_top_a_index, side_top_a_index + 3, side_top_a_index + 2]:
		indices.append(point_index)


static func _connected_soil_point(center: Vector3, spacing: float, u: float, v: float, h00: float, h10: float, h11: float, h01: float, terrain_center_correction: float, crown_scale: float, edge_factor: float) -> Vector3:
	var north_height := lerpf(h00, h10, u)
	var south_height := lerpf(h01, h11, u)
	var base_height := lerpf(north_height, south_height, v)
	var center_weight := sin(PI * u) * sin(PI * v)
	base_height += terrain_center_correction * center_weight
	var x := center.x + (u - 0.5) * spacing
	var z := center.z + (v - 0.5) * spacing
	var cell_crown := pow(center_weight, 1.35) * SOIL_MOUND_CROWN_HEIGHT * crown_scale
	var surface_variation := sin(x * 1.37 + z * 0.61) * cos(z * 1.11 - x * 0.47) * 0.004
	var mound_height := (SOIL_MOUND_SADDLE_HEIGHT + cell_crown + surface_variation) * edge_factor
	return Vector3(x, base_height + 0.012 + mound_height, z)


static func _soil_grid_key(grid: Vector2i) -> String:
	return "%d:%d" % [grid.x, grid.y]


static func _soil_edge_factor(u: float, v: float, neighbor_mask: int) -> float:
	var has_west := (neighbor_mask & SOIL_NEIGHBOR_WEST) != 0
	var has_east := (neighbor_mask & SOIL_NEIGHBOR_EAST) != 0
	var has_north := (neighbor_mask & SOIL_NEIGHBOR_NORTH) != 0
	var has_south := (neighbor_mask & SOIL_NEIGHBOR_SOUTH) != 0
	var factor := 1.0
	if not has_west:
		factor *= smoothstep(0.0, SOIL_OUTER_TAPER_FRACTION, u)
	if not has_east:
		factor *= smoothstep(0.0, SOIL_OUTER_TAPER_FRACTION, 1.0 - u)
	if not has_north:
		factor *= smoothstep(0.0, SOIL_OUTER_TAPER_FRACTION, v)
	if not has_south:
		factor *= smoothstep(0.0, SOIL_OUTER_TAPER_FRACTION, 1.0 - v)
	if has_west and has_north and (neighbor_mask & SOIL_NEIGHBOR_NORTHWEST) == 0:
		factor *= smoothstep(0.0, SOIL_OUTER_TAPER_FRACTION, Vector2(u, v).length())
	if has_east and has_north and (neighbor_mask & SOIL_NEIGHBOR_NORTHEAST) == 0:
		factor *= smoothstep(0.0, SOIL_OUTER_TAPER_FRACTION, Vector2(1.0 - u, v).length())
	if has_east and has_south and (neighbor_mask & SOIL_NEIGHBOR_SOUTHEAST) == 0:
		factor *= smoothstep(0.0, SOIL_OUTER_TAPER_FRACTION, Vector2(1.0 - u, 1.0 - v).length())
	if has_west and has_south and (neighbor_mask & SOIL_NEIGHBOR_SOUTHWEST) == 0:
		factor *= smoothstep(0.0, SOIL_OUTER_TAPER_FRACTION, Vector2(u, 1.0 - v).length())
	return factor


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
