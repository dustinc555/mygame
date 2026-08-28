@tool
extends RefCounted

## Viewport cell painter for a SettlementField's footprint. A field is an AREA
## of ground, not a point with a scene, so it is the one facility the normal
## placement ghost cannot author. Left-drag paints soil cells where the cursor
## crosses the field's plane; Shift (or right-drag) erases. The painted set is
## stored on the node as grid coordinates, so it survives moving the field and
## maps straight onto the plot's own "x:y" cell keys.
##
## Cells sitting inside ANOTHER faction's town border are drawn in red: that is
## the same rule TerritoryController applies as "too_close_to_town", checked
## here against the town nodes directly because the territory service only
## exists at runtime.

const VALID_COLOR := Color(0.35, 0.75, 0.28, 0.55)
const REFUSED_COLOR := Color(0.85, 0.22, 0.18, 0.6)
const BORDER_THICKNESS := 0.06
## Matches FarmController.DEFAULT_CELL_SIZE and SettlementField.CELL_SIZE — the
## plot grid is not resizable, so this is a shared constant, not a preference.
const CELL_SIZE := 1.25

var _plugin: EditorPlugin
var _field: Node3D
var _preview: Node3D
var _painting := false
var _erasing := false
var _coordinates := {}
var _refused := {}
var _on_changed := Callable()
## Towns do not move while you paint, so the (recursive, whole-scene) search for
## them happens once per session instead of once per mouse-motion event.
var _foreign_towns: Array[Node] = []
## The grid cell the cursor was last resolved to. Most motion events during a
## drag land on the cell already painted; those must cost nothing.
var _last_grid := Vector2i(-9999, -9999)
var _multi_mesh: MultiMesh
## Refusal depends on a cell's WORLD position, so it is cached per coordinate
## and dropped whenever the field itself moves.
var _refusal_cache := {}


func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin


func is_active() -> bool:
	return _field != null and is_instance_valid(_field)


func active_field() -> Node3D:
	return _field


func cell_count() -> int:
	return _coordinates.size()


func refused_count() -> int:
	return _refused.size()


func begin(field: Node3D, on_changed := Callable()) -> bool:
	if field == null or not is_instance_valid(field):
		return false
	_field = field
	_on_changed = on_changed
	_last_grid = Vector2i(-9999, -9999)
	_foreign_towns = _find_foreign_towns()
	_refusal_cache.clear()
	_coordinates.clear()
	for value in PackedVector2Array(field.get("cell_coordinates")):
		_coordinates[Vector2i(int(value.x), int(value.y))] = true
	if _coordinates.is_empty():
		# An unpainted field is the full rectangle; start from that so the first
		# stroke edits a real shape instead of a blank one.
		var dimensions: Vector2i = field.get("dimensions")
		for y in dimensions.y:
			for x in dimensions.x:
				_coordinates[Vector2i(x, y)] = true
	_rebuild_preview()
	return true


func end() -> void:
	if _field != null and is_instance_valid(_field) and _field.has_method("_repair_authoring_tree"):
		_field.call("_repair_authoring_tree")
	_free_preview()
	_field = null
	_painting = false
	_erasing = false
	_coordinates.clear()
	_refused.clear()
	_foreign_towns.clear()
	_refusal_cache.clear()
	_last_grid = Vector2i(-9999, -9999)
	_on_changed = Callable()


func handle_3d_input(camera: Camera3D, event: InputEvent) -> int:
	if not is_active() or camera == null:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			if button.pressed:
				_painting = true
				_erasing = button.button_index == MOUSE_BUTTON_RIGHT or button.shift_pressed
				_paint_at(camera, button.position)
			else:
				_painting = false
				_commit()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion and _painting:
		_paint_at(camera, (event as InputEventMouseMotion).position)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			end()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _paint_at(camera: Camera3D, mouse_position: Vector2) -> void:
	var point = _field_plane_point(camera, mouse_position)
	if point == null:
		return
	var local: Vector3 = _field.global_transform.affine_inverse() * (point as Vector3)
	var grid := Vector2i(floori(local.x / CELL_SIZE + 0.5), floori(local.z / CELL_SIZE + 0.5))
	# A drag fires dozens of motion events per cell crossed. Only the first one
	# per cell can change anything.
	if grid == _last_grid:
		return
	_last_grid = grid
	if _erasing:
		if not _coordinates.has(grid):
			return
		_coordinates.erase(grid)
	else:
		if grid.x < 0 or grid.y < 0:
			# Negative coordinates cannot be expressed as plot cell keys inside
			# the bounding box; rebase instead of silently dropping the stroke.
			_rebase(Vector2i(mini(grid.x, 0), mini(grid.y, 0)))
			grid = Vector2i(maxi(grid.x, 0), maxi(grid.y, 0))
		if _coordinates.has(grid):
			return
		_coordinates[grid] = true
	_rebuild_preview()


## Shift every painted cell so the origin corner stays at (0,0) after a stroke
## reaches above or left of the current bounds. The field node moves by the
## same offset, so the soil does not jump in the world.
func _rebase(offset: Vector2i) -> void:
	if offset == Vector2i.ZERO:
		return
	var shifted := {}
	for coordinate in _coordinates:
		shifted[(coordinate as Vector2i) - offset] = true
	_coordinates = shifted
	_refusal_cache.clear()
	_last_grid = Vector2i(-9999, -9999)
	_field.global_position += _field.global_transform.basis * Vector3(float(offset.x) * CELL_SIZE, 0.0, float(offset.y) * CELL_SIZE)


func _commit() -> void:
	if not is_active():
		return
	var coordinates := _coordinates.keys()
	coordinates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x)
	var painted := PackedVector2Array()
	var bounds := Vector2i.ZERO
	for coordinate_value in coordinates:
		var coordinate: Vector2i = coordinate_value
		painted.append(Vector2(coordinate))
		bounds = Vector2i(maxi(bounds.x, coordinate.x + 1), maxi(bounds.y, coordinate.y + 1))
	if painted.is_empty():
		return
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Paint Field")
	undo_redo.add_do_property(_field, "dimensions", Vector2i(maxi(1, bounds.x), maxi(1, bounds.y)))
	undo_redo.add_do_property(_field, "cell_coordinates", painted)
	undo_redo.add_undo_property(_field, "dimensions", _field.get("dimensions"))
	undo_redo.add_undo_property(_field, "cell_coordinates", _field.get("cell_coordinates"))
	undo_redo.commit_action()
	if _on_changed.is_valid():
		_on_changed.call()


## --- Preview --------------------------------------------------------------------


## One MultiMeshInstance3D, created once and never re-parented. Painting only
## writes per-instance transforms and colors into its buffer — the previous
## version freed and rebuilt a MeshInstance3D (plus its own BoxMesh and
## StandardMaterial3D) per cell per mouse-motion event, inside the edited
## scene, which also made the editor's Scene dock refresh on every move.
func _rebuild_preview() -> void:
	if not is_active():
		return
	var scene_root := _plugin.get_editor_interface().get_edited_scene_root()
	if scene_root == null:
		return
	_ensure_preview(scene_root)
	if _multi_mesh == null:
		return
	_refused.clear()
	# Instances are authored in the field's local space, so the whole preview
	# follows the field by transform alone.
	_preview.global_transform = _field.global_transform
	var coordinates := _coordinates.keys()
	var refused_by_coordinate := {}
	var transforms := {}
	for coordinate_value in coordinates:
		var coordinate: Vector2i = coordinate_value
		var cell_transform: Transform3D = _field.call("cell_local_transform", coordinate, 0.07) \
				if _field.has_method("cell_local_transform") \
				else Transform3D(Basis(), Vector3(float(coordinate.x) * CELL_SIZE, 0.07, float(coordinate.y) * CELL_SIZE))
		transforms[coordinate] = cell_transform
		var refused := bool(_refusal_cache.get(coordinate, false)) if _refusal_cache.has(coordinate) \
				else _is_refused(_field.global_transform * cell_transform.origin, _foreign_towns)
		_refusal_cache[coordinate] = refused
		refused_by_coordinate[coordinate] = refused
		if refused:
			_refused[coordinate] = true
	var segments: Array[Dictionary] = []
	var edges := [
		{"neighbor": Vector2i(0, -1), "offset": Vector3(0.0, 0.0, -CELL_SIZE * 0.5), "rotation": 0.0},
		{"neighbor": Vector2i(0, 1), "offset": Vector3(0.0, 0.0, CELL_SIZE * 0.5), "rotation": 0.0},
		{"neighbor": Vector2i(-1, 0), "offset": Vector3(-CELL_SIZE * 0.5, 0.0, 0.0), "rotation": PI * 0.5},
		{"neighbor": Vector2i(1, 0), "offset": Vector3(CELL_SIZE * 0.5, 0.0, 0.0), "rotation": PI * 0.5},
	]
	for coordinate_value in coordinates:
		var coordinate: Vector2i = coordinate_value
		var refused := bool(refused_by_coordinate[coordinate])
		for edge in edges:
			var neighbor: Vector2i = coordinate + (edge["neighbor"] as Vector2i)
			var neighbor_exists := _coordinates.has(neighbor)
			var neighbor_refused := bool(refused_by_coordinate.get(neighbor, false))
			if neighbor_exists and neighbor_refused == refused:
				continue
			# A valid/refused seam is shared; only one cell contributes it.
			if neighbor_exists and (coordinate.y > neighbor.y or (coordinate.y == neighbor.y and coordinate.x > neighbor.x)):
				continue
			_append_border_segment(
				segments,
				transforms[coordinate] as Transform3D,
				edge["offset"] as Vector3,
				float(edge["rotation"]),
				REFUSED_COLOR if refused or neighbor_refused else VALID_COLOR,
			)
	_multi_mesh.instance_count = segments.size()
	for index in segments.size():
		_multi_mesh.set_instance_transform(index, segments[index]["transform"])
		_multi_mesh.set_instance_color(index, segments[index]["color"])


func _append_border_segment(segments: Array[Dictionary], cell_transform: Transform3D, offset: Vector3, rotation: float, color: Color) -> void:
	segments.append({
		"transform": Transform3D(Basis(Vector3.UP, rotation), cell_transform.origin + offset),
		"color": color,
	})


func _ensure_preview(scene_root: Node) -> void:
	if _preview != null and is_instance_valid(_preview) and _multi_mesh != null:
		return
	var tile := BoxMesh.new()
	tile.size = Vector3(CELL_SIZE + BORDER_THICKNESS, 0.05, BORDER_THICKNESS)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# One material for every cell; per-cell valid/refused rides on instance color.
	material.vertex_color_use_as_albedo = true
	tile.material = material
	_multi_mesh = MultiMesh.new()
	# Format flags must be set before instance_count or the buffer is rebuilt.
	_multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	_multi_mesh.use_colors = true
	_multi_mesh.mesh = tile
	var instance := MultiMeshInstance3D.new()
	instance.name = "FieldPaintPreview"
	instance.multimesh = _multi_mesh
	# No owner: a preview must never be saved into the scene file.
	scene_root.add_child(instance)
	_preview = instance


## Towns that are NOT this field's owner faction. Own-faction towns never
## refuse their own fields, which is the rule TerritoryController uses.
func _find_foreign_towns() -> Array[Node]:
	var towns: Array[Node] = []
	var scene_root := _plugin.get_editor_interface().get_edited_scene_root()
	if scene_root == null:
		return towns
	var owner_faction := ""
	if _field.has_method("get_property_owner_faction"):
		owner_faction = str(_field.call("get_property_owner_faction"))
	_collect_towns(scene_root, owner_faction, towns)
	return towns


func _collect_towns(node: Node, owner_faction: String, towns: Array[Node]) -> void:
	if node.has_method("contains_town_border_position") and node.has_method("get_faction_id"):
		var faction := str(node.call("get_faction_id"))
		if owner_faction.is_empty() or faction.is_empty() or faction != owner_faction:
			towns.append(node)
	for child in node.get_children():
		_collect_towns(child, owner_faction, towns)


func _is_refused(world_position: Vector3, foreign_towns: Array[Node]) -> bool:
	for town in foreign_towns:
		if bool(town.call("contains_town_border_position", world_position)):
			return true
	return false


func _free_preview() -> void:
	if _preview != null and is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null
	_multi_mesh = null


## The cursor is resolved against the FIELD'S OWN horizontal plane, not against
## the terrain. That is both more correct and vastly cheaper: a field is a flat
## grid at the field's height (the soil mesh conforms to terrain at runtime), and
## Terrain3D here is collision_mode FULL_GAME, so in the editor there is no
## terrain collider and every terrain query would fall through to
## get_intersection(gpu_mode) — a GPU render plus readback stall, per mouse
## motion event. This is a handful of floating point operations instead.
func _field_plane_point(camera: Camera3D, mouse_position: Vector2) -> Variant:
	var origin := _field.global_position
	var normal := _field.global_transform.basis.y.normalized()
	if normal.is_zero_approx():
		normal = Vector3.UP
	var plane := Plane(normal, origin)
	var from := camera.project_ray_origin(mouse_position)
	var direction := camera.project_ray_normal(mouse_position)
	var hit = plane.intersects_ray(from, direction)
	return hit
