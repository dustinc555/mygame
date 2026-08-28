@tool
@icon("res://addons/world_authoring/icons/facility_field.svg")
extends "res://features/settlements/bridge/settlement_facility_instance.gd"

class_name SettlementField

## A worked field: the facility half is the worksite (owner faction, employed
## field hands, settlement ledger), and the soil half is a real FarmController
## plot seeded from this node's authored footprint when the world loads.
##
## The footprint is authored as GRID COORDINATES, not world positions, so the
## soil follows the facility when it is moved and so the coordinates map
## straight onto the plot's own "x:y" cell keys. `dimensions` is the bounding
## box; `cell_coordinates` is the subset of it that is actually soil (empty
## means the full rectangle, which is what a freshly placed field gets).

const FIELD_FUNCTION = preload("res://features/world_sim/resources/facility_functions/field.tres")
## Must match FarmController.DEFAULT_CELL_SIZE — the plot grid is not resizable.
const CELL_SIZE := 1.25
## Crop policy meaning "plant whatever seed stock is actually in reach".
const AUTO_CROP_POLICY := "auto"
## Territory and navigation are not ready on the first frames of a fresh world;
## the seed attempt retries before giving up quietly.
const SEED_RETRIES := 30
@export var dimensions := Vector2i(6, 4):
	set(value):
		dimensions = Vector2i(maxi(1, value.x), maxi(1, value.y))
		_repair_authoring_tree()
## Painted soil cells as grid coordinates inside `dimensions`. Empty = every
## cell of the bounding box.
@export var cell_coordinates: PackedVector2Array = PackedVector2Array():
	set(value):
		cell_coordinates = value
		_repair_authoring_tree()
## A crop id from FarmController.get_crops(), "auto", or "" for manual only.
@export var crop_policy_id := AUTO_CROP_POLICY
## Queue the first tilling so a new field starts being worked without a player
## hoe gesture. The same thing granary_town_test.gd does by hand.
@export var auto_till_on_seed := true

var _plot_id := ""
var _terrain_cache: Node


## Re-seat the footprint on the current ground. Terrain edits do not notify the
## nodes standing on them, so re-sculpting under a field needs this.
func refit_to_terrain() -> void:
	_terrain_cache = null


func _ready() -> void:
	_remove_legacy_footprint_visual()
	_repair_authoring_tree()
	super._ready()
	if Engine.is_editor_hint():
		return
	call_deferred("_seed_plot", SEED_RETRIES)


func _repair_authoring_tree() -> void:
	_apply_field_defaults()
	super._repair_authoring_tree()
	if not is_inside_tree():
		return
	# Real field work is published by FarmController. Fields own no fake staff,
	# ambient stand-around points, or abstract facility job provider.


func _apply_field_defaults() -> void:
	if facility_function == null:
		facility_function = FIELD_FUNCTION
	building_root_path = NodePath("")
	staff_root_path = NodePath("")
	service_points_root_path = NodePath("")
	# A field has no building, no containers of its own, and no bespoke job
	# provider — the farm plot publishes its own work.
	storage_root_path = NodePath("")
	job_providers_root_path = NodePath("")
	activity_points_root_path = NodePath("")
	facility_type = "farm"
	if display_name.is_empty() or display_name == "Facility":
		display_name = "Field"


## The authored footprint in this facility's local space, paired with the plot
## cell keys the coordinates map to.
func get_footprint() -> Dictionary:
	var coordinates := _footprint_coordinates()
	var positions: Array[Vector3] = []
	var keys := PackedStringArray()
	for coordinate in coordinates:
		var grid := Vector2i(int(coordinate.x), int(coordinate.y))
		positions.append(Vector3(float(grid.x) * CELL_SIZE, 0.0, float(grid.y) * CELL_SIZE))
		keys.append("%d:%d" % [grid.x, grid.y])
	return {"positions": positions, "cell_keys": keys, "dimensions": dimensions}


func _footprint_coordinates() -> Array[Vector2i]:
	var coordinates: Array[Vector2i] = []
	var seen := {}
	for value in cell_coordinates:
		var grid := Vector2i(int(value.x), int(value.y))
		if grid.x < 0 or grid.y < 0 or grid.x >= dimensions.x or grid.y >= dimensions.y:
			continue
		if seen.has(grid):
			continue
		seen[grid] = true
		coordinates.append(grid)
	if coordinates.is_empty():
		for y in dimensions.y:
			for x in dimensions.x:
				coordinates.append(Vector2i(x, y))
	return coordinates


## Old editor builds accidentally serialized this developer visualization into
## production scenes. Remove it in both editor and runtime; only FieldPainter
## owns temporary footprint feedback now.
func _remove_legacy_footprint_visual() -> void:
	var visual := get_node_or_null("FootprintVisual")
	if visual != null:
		remove_child(visual)
		visual.queue_free()


## A cell's transform in this field's local space, lifted to sit ON the terrain
## rather than on the field's own flat plane — otherwise the tiles sink into
## any slope. The runtime soil mesh conforms for the same reason.
func cell_local_transform(grid: Vector2i, lift := 0.06) -> Transform3D:
	var offset := Vector3(float(grid.x) * CELL_SIZE, 0.0, float(grid.y) * CELL_SIZE)
	var world: Vector3 = global_transform * offset
	var height := sample_terrain_height(world)
	if is_nan(height):
		return Transform3D(Basis(), offset + Vector3(0.0, lift, 0.0))
	var conformed := global_transform.affine_inverse() * Vector3(world.x, height + lift, world.z)
	return Transform3D(Basis(), conformed)


## Terrain surface height under a world position, or NAN where no terrain
## covers it. Mirrors TerrainCameraController.get_terrain_height, but works in
## the editor too: Terrain3D's data.get_height is a heightmap lookup, NOT the
## GPU intersection that stalls the pipeline.
func sample_terrain_height(world_position: Vector3) -> float:
	var terrain := _find_terrain()
	if terrain == null:
		return NAN
	var data = terrain.get("data")
	if data == null or not data.has_method("get_height"):
		return NAN
	return float(data.get_height(world_position))


func _find_terrain() -> Node:
	if _terrain_cache != null and is_instance_valid(_terrain_cache):
		return _terrain_cache
	var root := get_tree().edited_scene_root if Engine.is_editor_hint() and get_tree() != null else null
	if root == null:
		root = get_tree().current_scene if get_tree() != null else null
	if root == null:
		return null
	_terrain_cache = _find_terrain_recursive(root)
	return _terrain_cache


func _find_terrain_recursive(node: Node) -> Node:
	if node.is_class("Terrain3D"):
		return node
	for child in node.get_children():
		var found := _find_terrain_recursive(child)
		if found != null:
			return found
	return null


## --- Plot seeding ---------------------------------------------------------------


func get_plot_id() -> String:
	return _plot_id


func _seed_plot(retries_remaining: int) -> void:
	if not is_inside_tree():
		return
	var context = BootstrapContext.active
	var farm = context.get_optional(&"farming") if context != null else null
	if farm == null:
		if retries_remaining > 0:
			call_deferred("_seed_plot", retries_remaining - 1)
		return
	if not _plot_id.is_empty() and farm.has_method("is_active_field") and bool(farm.call("is_active_field", _plot_id)):
		return
	var footprint := get_footprint()
	var local_positions: Array[Vector3] = footprint["positions"]
	if local_positions.is_empty():
		return
	var world_positions: Array[Vector3] = []
	for position in local_positions:
		world_positions.append(global_transform * position)
	# "auto" is a policy, not a crop, so the plot is created cropless and the
	# policy is stamped on afterwards.
	var seed_crop_id := crop_policy_id if _is_real_crop(farm, crop_policy_id) else ""
	var created: Dictionary = farm.call(
		"create_plot",
		world_positions,
		dimensions,
		seed_crop_id,
		get_property_owner_faction(),
		_effective_settlement_id(),
		{},
		footprint["cell_keys"],
	)
	if created.is_empty():
		# Territory refusal or overlapping soil. Both can be transient while the
		# world is still assembling, so retry, then stop without spamming.
		if retries_remaining > 0:
			call_deferred("_seed_plot", retries_remaining - 1)
		return
	_plot_id = str(created.get("plot_id", ""))
	_apply_crop_policy(farm)
	if auto_till_on_seed:
		_request_initial_tilling(farm, created)


func _is_real_crop(farm: Object, candidate: String) -> bool:
	if candidate.is_empty() or candidate == AUTO_CROP_POLICY:
		return false
	return farm.has_method("get_crop") and farm.call("get_crop", candidate) != null


func _apply_crop_policy(farm: Object) -> void:
	if crop_policy_id != AUTO_CROP_POLICY or _plot_id.is_empty():
		return
	if not farm.has_method("set_plot_crop_policy_unchecked"):
		return
	farm.call("set_plot_crop_policy_unchecked", _plot_id, AUTO_CROP_POLICY)


func _request_initial_tilling(farm: Object, plot: Dictionary) -> void:
	var plot_id := str(plot.get("plot_id", ""))
	var cells: Dictionary = plot.get("cells", {})
	for cell_key_value in cells.keys():
		var cell: Dictionary = cells.get(cell_key_value, {})
		if str(cell.get("state", "")) != "untilled":
			continue
		if not str(cell.get("requested_operation", "")).is_empty():
			continue
		farm.call("request_cell_operation", plot_id, str(cell_key_value), "till")
