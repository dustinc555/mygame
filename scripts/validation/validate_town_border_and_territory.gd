extends SceneTree

const SETTLEMENT_TOWN_SCRIPT := preload("res://scripts/world_sim/settlement_town.gd")
const ACTIVITY_POINT_SCRIPT := preload("res://scripts/world_sim/settlement_activity_point.gd")
const FACTION_TERRITORY_ANCHOR_SCRIPT := preload("res://scripts/world_sim/faction_territory_anchor.gd")
const SETTLEMENT_CONTROLLER_SCRIPT := preload("res://scripts/controllers/settlement_controller.gd")
const TERRITORY_CONTROLLER_SCRIPT := preload("res://scripts/controllers/territory_controller.gd")
const TWO_TOWNS_SCENE := preload("res://scenes/test_levels/two_towns_road_test.tscn")
const FARMER_FACTION := preload("res://resources/world_sim/factions/farmers.tres")
const RAIDER_FACTION := preload("res://resources/world_sim/factions/raiders.tres")
const TERRITORY_DEBUG_ALPHA := 0.28

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_faction_primary_colors()
	_validate_auto_town_border()
	await _validate_two_towns_territory_split()
	_validate_linked_territory_owner()
	await process_frame
	if _failures.is_empty():
		print("TOWN_BORDER_AND_TERRITORY_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("TOWN_BORDER_AND_TERRITORY_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_auto_town_border() -> void:
	var town := Node3D.new()
	town.name = "TestTown"
	town.set_script(SETTLEMENT_TOWN_SCRIPT)
	town.set("town_border_radius", 5.0)
	town.set("town_border_padding", 1.0)
	root.add_child(town)
	_add_mesh_node(_ensure_child(town, "Housing"), "House", Vector3.ZERO, Vector3(2.0, 1.0, 2.0))
	_add_mesh_node(_ensure_child(town, "Keeps"), "Keep", Vector3(8.0, 0.0, 0.0), Vector3(2.0, 1.0, 2.0))
	_add_mesh_node(_ensure_child(town, "Fields"), "FarField", Vector3(100.0, 0.0, 0.0), Vector3(20.0, 1.0, 20.0))
	var activity_root := _ensure_child(town, "ActivityPoints")
	var activity := Marker3D.new()
	activity.name = "FarActivity"
	activity.position = Vector3(200.0, 0.0, 0.0)
	activity.set_script(ACTIVITY_POINT_SCRIPT)
	activity_root.add_child(activity)
	var record: Dictionary = town.call("get_town_border_record")
	if str(record.get("shape_mode", "")) != "box":
		_fail("Town border should use auto footprint box when footprint nodes exist")
	var bounds_max: Vector2 = record.get("bounds_max", Vector2.ZERO)
	if bounds_max.x >= 25.0:
		_fail("Town border footprint should exclude fields and far activity markers")
	if not bool(town.call("contains_town_border_position", town.global_transform * Vector3(8.0, 0.0, 0.0))):
		_fail("Town border should contain included keep footprint")
	if bool(town.call("contains_town_border_position", town.global_transform * Vector3(100.0, 0.0, 0.0))):
		_fail("Town border should not contain excluded far field footprint")
	var debug := town.get_node_or_null("TownBorderDebug") as MeshInstance3D
	if debug == null or not (debug.mesh is ArrayMesh):
		_fail("Town border debug should render as a dashed outline mesh")
	town.queue_free()


func _validate_faction_primary_colors() -> void:
	var farmer_color: Color = FARMER_FACTION.get("primary_color")
	var raider_color: Color = RAIDER_FACTION.get("primary_color")
	if absf(farmer_color.a - 1.0) > 0.001:
		_fail("Farmer faction primary_color should be opaque identity color")
	if absf(raider_color.a - 1.0) > 0.001:
		_fail("Raider faction primary_color should be opaque identity color")
	if _color_rgb_distance(farmer_color, raider_color) < 0.25:
		_fail("Farmer and Raider faction primary colors should be visually distinct")


func _validate_two_towns_territory_split() -> void:
	var scene := TWO_TOWNS_SCENE.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var farmer_territory := scene.get_node_or_null("Settlements/FarmerCrossing/Territory")
	var raider_territory := scene.get_node_or_null("Settlements/RaiderCamp/Territory")
	if farmer_territory == null or raider_territory == null:
		_fail("Two towns scene should author both faction territories")
		scene.queue_free()
		return
	if not bool(farmer_territory.call("contains_world_position", Vector3(-45.0, 0.0, 0.0))):
		_fail("Farmer territory should claim the west half of the map")
	if bool(farmer_territory.call("contains_world_position", Vector3(45.0, 0.0, 0.0))):
		_fail("Farmer territory should not claim the east half of the map")
	if not bool(raider_territory.call("contains_world_position", Vector3(45.0, 0.0, 0.0))):
		_fail("Raider territory should claim the east half of the map")
	if bool(raider_territory.call("contains_world_position", Vector3(-45.0, 0.0, 0.0))):
		_fail("Raider territory should not claim the west half of the map")
	if not bool(farmer_territory.call("contains_world_position", Vector3(-0.5, 0.0, 0.0))):
		_fail("Farmer territory should cover up to the west side of the center split")
	if not bool(raider_territory.call("contains_world_position", Vector3(0.5, 0.0, 0.0))):
		_fail("Raider territory should cover from the east side of the center split")
	_validate_territory_debug_color(farmer_territory, FARMER_FACTION.get("primary_color"), "Farmer")
	_validate_territory_debug_color(raider_territory, RAIDER_FACTION.get("primary_color"), "Raider")
	scene.queue_free()
	await process_frame


func _validate_linked_territory_owner() -> void:
	var settlement_controller := SETTLEMENT_CONTROLLER_SCRIPT.new()
	root.add_child(settlement_controller)
	settlement_controller.set("settlement_states", {
		"TestTown": {"settlement_id": "TestTown", "faction_id": "Farmers"},
	})
	var territory := Node3D.new()
	territory.name = "LinkedTerritory"
	territory.position = Vector3(50.0, 0.0, 0.0)
	territory.set_script(FACTION_TERRITORY_ANCHOR_SCRIPT)
	territory.set("shape_mode", "box")
	territory.set("box_size", Vector2(20.0, 20.0))
	territory.set("faction_id", "Fallback")
	territory.set("linked_settlement_id", "TestTown")
	root.add_child(territory)
	if str(territory.call("get_resolved_faction_id")) != "Farmers":
		_fail("Linked territory should resolve owner from settlement controller state")
	settlement_controller.call("set_settlement_owner", "TestTown", "Raiders", "validation")
	if str(territory.call("get_resolved_faction_id")) != "Raiders":
		_fail("Linked territory should follow settlement owner changes")
	var territory_controller := TERRITORY_CONTROLLER_SCRIPT.new()
	root.add_child(territory_controller)
	var permission: Dictionary = territory_controller.call("get_build_permission", Vector3(50.0, 0.0, 0.0), "Farmers")
	if str(permission.get("reason", "")) != "foreign_faction_territory" or str(permission.get("faction_id", "")) != "Raiders":
		_fail("Build permission should use resolved linked territory owner")
	territory_controller.queue_free()
	territory.queue_free()
	settlement_controller.queue_free()


func _validate_territory_debug_color(territory: Node, primary_color: Color, label: String) -> void:
	var debug := territory.get_node_or_null("TerritoryDebug") as MeshInstance3D
	if debug == null:
		_fail("%s territory should have a debug mesh" % label)
		return
	var material := debug.material_override as StandardMaterial3D
	if material == null:
		_fail("%s territory debug mesh should have a material" % label)
		return
	var expected := primary_color
	expected.a = TERRITORY_DEBUG_ALPHA
	if _color_rgba_distance(material.albedo_color, expected) > 0.02:
		_fail("%s territory debug color should derive from faction primary_color with debug alpha" % label)


func _color_rgb_distance(left: Color, right: Color) -> float:
	return Vector3(left.r - right.r, left.g - right.g, left.b - right.b).length()


func _color_rgba_distance(left: Color, right: Color) -> float:
	return Vector4(left.r - right.r, left.g - right.g, left.b - right.b, left.a - right.a).length()


func _ensure_child(parent: Node, child_name: String) -> Node3D:
	var child := parent.get_node_or_null(child_name) as Node3D
	if child != null:
		return child
	child = Node3D.new()
	child.name = child_name
	parent.add_child(child)
	return child


func _add_mesh_node(parent: Node, node_name: String, position: Vector3, size: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.position = position
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	parent.add_child(node)
	return node


func _fail(message: String) -> void:
	_failures.append(message)
