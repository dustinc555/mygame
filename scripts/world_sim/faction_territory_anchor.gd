@tool
extends Node3D

class_name FactionTerritoryAnchor

@export var territory_id := ""
@export var display_name := "Faction Territory"
@export var faction_id := ""
@export var linked_settlement_id := ""
@export var linked_settlement_path: NodePath
@export_enum("polygon", "circle", "box") var shape_mode := "polygon":
	set(value):
		shape_mode = value
		_refresh_debug_mesh()
@export var polygon_points := PackedVector2Array():
	set(value):
		polygon_points = value
		_refresh_debug_mesh()
@export var radius := 40.0:
	set(value):
		radius = value
		_refresh_debug_mesh()
@export var box_size := Vector2(80.0, 80.0):
	set(value):
		box_size = value
		_refresh_debug_mesh()
@export var use_faction_primary_color := true:
	set(value):
		use_faction_primary_color = value
		_refresh_debug_mesh()
@export_range(0.0, 1.0, 0.01) var debug_alpha := 0.28:
	set(value):
		debug_alpha = clampf(float(value), 0.0, 1.0)
		_refresh_debug_mesh()
@export var debug_color := Color(0.0, 0.72, 0.72, 0.28):
	set(value):
		debug_color = value
		_refresh_debug_mesh()
@export var editor_show_debug_shape := true:
	set(value):
		editor_show_debug_shape = value
		_sync_debug_visibility()

var _debug_mesh: MeshInstance3D


func _enter_tree() -> void:
	call_deferred("_refresh_debug_mesh")


func _ready() -> void:
	add_to_group("faction_territory")
	_refresh_debug_mesh()


func get_territory_id() -> String:
	return territory_id if not territory_id.is_empty() else name


func get_territory_record() -> Dictionary:
	return {
		"territory_id": get_territory_id(),
		"display_name": display_name if not display_name.is_empty() else get_territory_id().capitalize(),
		"faction_id": get_resolved_faction_id(),
		"configured_faction_id": faction_id,
		"linked_settlement_id": get_linked_settlement_id(),
		"shape_mode": shape_mode,
		"center": global_position,
		"radius": radius,
		"box_size": box_size,
		"polygon_points": polygon_points,
	}


func get_linked_settlement_id() -> String:
	if not linked_settlement_id.strip_edges().is_empty():
		return linked_settlement_id.strip_edges()
	var settlement := _get_linked_settlement()
	if settlement != null and settlement.has_method("get_settlement_id"):
		return str(settlement.call("get_settlement_id"))
	return ""


func get_resolved_faction_id() -> String:
	var settlement_id := get_linked_settlement_id()
	if not settlement_id.is_empty():
		var controller_owner := _resolve_controller_settlement_owner(settlement_id)
		if not controller_owner.is_empty():
			return controller_owner
	var linked_settlement := _get_linked_settlement()
	var linked_owner := _resolve_settlement_node_owner(linked_settlement)
	if not linked_owner.is_empty():
		return linked_owner
	return faction_id


func contains_world_position(world_position: Vector3) -> bool:
	var local := to_local(world_position)
	var point := Vector2(local.x, local.z)
	match shape_mode:
		"circle":
			return point.length() <= radius
		"box":
			return absf(point.x) <= box_size.x * 0.5 and absf(point.y) <= box_size.y * 0.5
		_:
			return _point_in_polygon(point, _get_polygon_points())


func _get_linked_settlement() -> Node:
	if not linked_settlement_path.is_empty():
		var linked := get_node_or_null(linked_settlement_path)
		if linked != null:
			return linked
	var settlement_id := linked_settlement_id.strip_edges()
	if settlement_id.is_empty() or not is_inside_tree():
		return null
	for group_name in ["settlement_town", "settlement_anchor"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if node != null and node.has_method("get_settlement_id") and str(node.call("get_settlement_id")) == settlement_id:
				return node
	return null


func _resolve_controller_settlement_owner(settlement_id: String) -> String:
	if not is_inside_tree():
		return ""
	for controller in get_tree().get_nodes_in_group("settlement_controller"):
		if controller != null and controller.has_method("get_settlement_state"):
			var state: Dictionary = controller.call("get_settlement_state", settlement_id)
			var owner := str(state.get("faction_id", ""))
			if not owner.is_empty():
				return owner
	return ""


func _resolve_settlement_node_owner(settlement: Node) -> String:
	if settlement == null:
		return ""
	var definition = settlement.get("settlement_definition") if _has_property(settlement, "settlement_definition") else null
	if definition != null and definition.has_method("get_faction_id"):
		return str(definition.call("get_faction_id"))
	return ""


func set_debug_visible(value: bool) -> void:
	if _debug_mesh == null or not is_instance_valid(_debug_mesh):
		_create_debug_mesh()
	if _debug_mesh != null:
		_debug_mesh.visible = editor_show_debug_shape if Engine.is_editor_hint() else value


func _create_debug_mesh() -> void:
	var points := _get_polygon_points()
	if points.size() < 3:
		return
	_debug_mesh = get_node_or_null("TerritoryDebug") as MeshInstance3D
	if _debug_mesh == null:
		_debug_mesh = MeshInstance3D.new()
		_debug_mesh.name = "TerritoryDebug"
		add_child(_debug_mesh)
		_set_editor_owner(_debug_mesh)
	_debug_mesh.mesh = _build_polygon_mesh(points)
	_debug_mesh.position = Vector3(0.0, 0.14, 0.0)
	_debug_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_debug_mesh.material_override = _make_debug_material(_get_debug_color())
	_debug_mesh.visible = Engine.is_editor_hint() and editor_show_debug_shape


func _refresh_debug_mesh() -> void:
	if not is_inside_tree():
		return
	_create_debug_mesh()


func _sync_debug_visibility() -> void:
	if _debug_mesh == null or not is_instance_valid(_debug_mesh):
		return
	if Engine.is_editor_hint():
		_debug_mesh.visible = editor_show_debug_shape


func _get_polygon_points() -> PackedVector2Array:
	match shape_mode:
		"circle":
			return _circle_points(radius, 96)
		"box":
			return PackedVector2Array([
				Vector2(-box_size.x * 0.5, -box_size.y * 0.5),
				Vector2(box_size.x * 0.5, -box_size.y * 0.5),
				Vector2(box_size.x * 0.5, box_size.y * 0.5),
				Vector2(-box_size.x * 0.5, box_size.y * 0.5),
			])
		_:
			if polygon_points.size() >= 3:
				return polygon_points
			return _circle_points(radius, 96)


func _circle_points(target_radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(max(segments, 3)):
		var angle := TAU * float(index) / float(max(segments, 3))
		points.append(Vector2(cos(angle), sin(angle)) * target_radius)
	return points


func _get_debug_color() -> Color:
	if use_faction_primary_color:
		var faction_definition := _get_resolved_faction_definition()
		if faction_definition != null and _has_property(faction_definition, "primary_color"):
			var color: Color = faction_definition.get("primary_color")
			color.a = debug_alpha
			return color
	return debug_color


func _get_resolved_faction_definition() -> Resource:
	var resolved_faction_id := get_resolved_faction_id()
	if resolved_faction_id.is_empty() or not is_inside_tree():
		return null
	for registry in _get_world_sim_registries():
		if registry == null or not _has_property(registry, "faction_definitions"):
			continue
		for faction_definition in registry.get("faction_definitions"):
			var definition := faction_definition as Resource
			if definition == null:
				continue
			if definition.has_method("get_id") and str(definition.call("get_id")) == resolved_faction_id:
				return definition
			if _has_property(definition, "faction_id") and str(definition.get("faction_id")) == resolved_faction_id:
				return definition
	return null


func _get_world_sim_registries() -> Array[Node]:
	var registries: Array[Node] = []
	if not is_inside_tree():
		return registries
	for registry in get_tree().get_nodes_in_group("world_sim_registry"):
		if registry is Node and not registries.has(registry):
			registries.append(registry)
	_collect_registry_nodes(get_tree().root, registries)
	return registries


func _collect_registry_nodes(node: Node, registries: Array[Node]) -> void:
	if node == null:
		return
	if _has_property(node, "faction_definitions") and not registries.has(node):
		registries.append(node)
	for child in node.get_children():
		_collect_registry_nodes(child, registries)


func _build_polygon_mesh(points: PackedVector2Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	vertices.append(Vector3.ZERO)
	for point in points:
		vertices.append(Vector3(point.x, 0.0, point.y))
	var indices := PackedInt32Array()
	for index in range(1, points.size() + 1):
		indices.append(0)
		indices.append(index)
		indices.append(1 if index == points.size() else index + 1)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _point_in_polygon(point: Vector2, points: PackedVector2Array) -> bool:
	if points.size() < 3:
		return false
	var inside := false
	var j := points.size() - 1
	for i in range(points.size()):
		var pi := points[i]
		var pj := points[j]
		var denominator := pj.y - pi.y
		if absf(denominator) < 0.0001:
			denominator = 0.0001
		if ((pi.y > point.y) != (pj.y > point.y)) and point.x < (pj.x - pi.x) * (point.y - pi.y) / denominator + pi.x:
			inside = not inside
		j = i
	return inside


func _has_property(target: Object, property_name: String) -> bool:
	if target == null:
		return false
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _make_debug_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	return material


func _set_editor_owner(node: Node) -> void:
	if not Engine.is_editor_hint():
		return
	var tree := get_tree()
	if tree == null:
		return
	var edited_root := tree.edited_scene_root
	if edited_root != null:
		node.owner = edited_root
