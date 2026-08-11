extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_town_placement_exclusion.gd

const TEST_SCENE_PATH := "res://scenes/test_levels/farming_test.tscn"
const SETTLEMENT_TOWN_PATH := "res://features/settlements/bridge/settlement_town.gd"
const RUSTWASH_ZONE_PATH := "res://scenes/zones/rustwash_basin/rustwash_basin.tscn"


class PlacementTownFixture extends Node3D:
	var owner_faction_id := "Farmers"
	var border_radius := 10.0

	func _ready() -> void:
		add_to_group("settlement_town")

	func get_faction_id() -> String:
		return owner_faction_id

	func get_settlement_id() -> String:
		return "duplicate-authority-fixture"

	func contains_town_border_position(world_position: Vector3, extra_margin := 0.0) -> bool:
		return Vector2(global_position.x, global_position.z).distance_to(Vector2(world_position.x, world_position.z)) <= border_radius + maxf(0.0, extra_margin)


var _failures: Array[String] = []
var _scene: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(TEST_SCENE_PATH) as PackedScene
	if packed == null:
		_failures.append("could not load bootstrap test scene")
		_finish()
		return
	_scene = packed.instantiate()
	root.add_child(_scene)
	await create_timer(4.0).timeout
	_validate_live_town_margin_shape()
	_validate_faction_and_buffer_permission()
	_validate_missing_authority_fails_closed()
	await _validate_rustwash_canyon_runtime()
	_finish()


func _validate_live_town_margin_shape() -> void:
	var town_script := load(SETTLEMENT_TOWN_PATH) as Script
	if town_script == null:
		_failures.append("could not load SettlementTown after bootstrap")
		return
	var town := town_script.new() as Node3D
	town.set("auto_town_border_from_footprint", true)
	town.set("town_border_padding", 0.0)
	var facilities := Node3D.new()
	facilities.name = "Facilities"
	var footprint := MeshInstance3D.new()
	var footprint_mesh := BoxMesh.new()
	footprint_mesh.size = Vector3(20.0, 1.0, 10.0)
	footprint.mesh = footprint_mesh
	facilities.add_child(footprint)
	town.add_child(facilities)
	root.add_child(town)
	var shape: Dictionary = town.call("get_town_border_record")
	_expect(str(shape.get("shape_mode", "")) == "box", "facility footprint produces the authored box border")
	_expect(bool(town.call("contains_town_border_position", Vector3(27.5, 0.0, 0.0), 18.0)), "box border includes an 18m axis margin")
	_expect(not bool(town.call("contains_town_border_position", Vector3(23.0, 0.0, 18.0), 18.0)), "box margin uses shortest distance instead of a square corner expansion")
	_expect(town.has_method("overlaps_town_border_footprint"), "town border exposes authoritative building-footprint overlap")
	if town.has_method("overlaps_town_border_footprint"):
		var footprint_polygon := PackedVector2Array([Vector2(27.0, -2.0), Vector2(31.0, -2.0), Vector2(31.0, 2.0), Vector2(27.0, 2.0)])
		_expect(bool(town.call("overlaps_town_border_footprint", footprint_polygon, 18.0)), "building footprint cannot cross the town exclusion when its origin is outside")
	var bounds_min: Vector2 = shape.get("bounds_min", Vector2.ZERO)
	var bounds_max: Vector2 = shape.get("bounds_max", Vector2.ZERO)
	town.scale = Vector3(2.0, 1.0, 0.5)
	var local_edge := Vector3(bounds_max.x, 0.0, (bounds_min.y + bounds_max.y) * 0.5)
	var world_edge: Vector3 = town.to_global(local_edge)
	var outward := Vector3(town.global_basis.x.x, 0.0, town.global_basis.x.z).normalized()
	_expect(bool(town.call("contains_town_border_position", world_edge + outward * 17.5, 18.0)), "scaled box includes a world-space point within the 18m margin")
	_expect(not bool(town.call("contains_town_border_position", world_edge + outward * 18.5, 18.0)), "scaled box excludes a world-space point beyond the 18m margin")
	town.scale = Vector3.ONE
	var construction := get_first_node_in_group("construction_controller")
	_expect(construction != null and not bool(construction.call("can_place", Vector3(29.0, 0.0, 0.0), "Raiders", Vector2(4.0, 4.0), 0.0).get("allowed", true)), "construction rejects a footprint crossing the exclusion when its origin is outside")
	town.remove_from_group("settlement_town")
	var circle = load(SETTLEMENT_TOWN_PATH).new()
	circle.set("auto_town_border_from_footprint", false)
	circle.set("town_border_radius", 10.0)
	circle.scale = Vector3(2.0, 1.0, 0.5)
	root.add_child(circle)
	var circle_edge: Vector3 = circle.to_global(Vector3(10.0, 0.0, 0.0))
	var circle_outward := Vector3(circle.global_basis.x.x, 0.0, circle.global_basis.x.z).normalized()
	_expect(bool(circle.call("contains_town_border_position", circle_edge + circle_outward * 17.5, 18.0)), "scaled circle includes a world-space point within the 18m margin")
	_expect(not bool(circle.call("contains_town_border_position", circle_edge + circle_outward * 18.5, 18.0)), "scaled circle excludes a world-space point beyond the 18m margin")
	var footprint_center: Vector3 = circle_edge + circle_outward * 19.0
	var footprint_corners := PackedVector2Array([
		Vector2(footprint_center.x - 2.0, footprint_center.z - 2.0),
		Vector2(footprint_center.x + 2.0, footprint_center.z - 2.0),
		Vector2(footprint_center.x + 2.0, footprint_center.z + 2.0),
		Vector2(footprint_center.x - 2.0, footprint_center.z + 2.0),
	])
	_expect(bool(circle.call("overlaps_town_border_footprint", footprint_corners, 18.0)), "scaled circle checks the footprint against its live world geometry")
	circle.remove_from_group("settlement_town")
	circle.queue_free()


func _validate_faction_and_buffer_permission() -> void:
	var territory := get_first_node_in_group("territory_controller")
	if territory == null:
		_failures.append("runtime TerritoryController unavailable")
		return
	_expect(territory.has_method("get_build_permissions"), "territory authority exposes a batched preview query")
	territory.set("town_build_exclusion_margin", 18.0)
	var town := PlacementTownFixture.new()
	root.add_child(town)
	_expect(bool(territory.call("get_build_permission", Vector3.ZERO, "Farmers").get("can_build", false)), "town owner can place inside own border")
	_expect(not bool(territory.call("get_build_permission", Vector3(5.0, 0.0, 0.0), "Raiders").get("can_build", true)), "foreign faction cannot place inside town")
	_expect(not bool(territory.call("get_build_permission", Vector3(24.0, 0.0, 0.0), "Raiders").get("can_build", true)), "foreign faction cannot place inside 18m border buffer")
	_expect(bool(territory.call("get_build_permission", Vector3(29.0, 0.0, 0.0), "Raiders").get("can_build", false)), "foreign faction can place beyond border buffer")
	var construction := get_first_node_in_group("construction_controller")
	_expect(construction != null and not bool(construction.call("can_place", Vector3(5.0, 0.0, 0.0), "Raiders").get("allowed", true)), "building placement consumes the live foreign-town exclusion")
	var gecs = construction.get("_gecs") if construction != null else null
	if construction != null and gecs != null:
		gecs.call("upsert_settlement_state", "duplicate-authority-fixture", {
			"settlement_id": "duplicate-authority-fixture",
			"faction_id": "Farmers",
			"world_position": Vector3.ZERO,
			"radius": 90.0,
			"constructed": false,
		})
		_expect(bool(construction.call("can_place", Vector3(29.0, 0.0, 0.0), "Raiders").get("allowed", false)), "construction does not reapply a duplicate GECS circle after authoritative town geometry")
		gecs.call("upsert_settlement_state", "duplicate-authority-fixture", {
			"settlement_id": "duplicate-authority-fixture",
			"faction_id": "Farmers",
			"world_position": Vector3.INF,
			"radius": 0.0,
			"constructed": false,
		})
	var farm := _find_named_node(_scene, "FarmController")
	if farm == null:
		_failures.append("runtime FarmController unavailable")
	else:
		var rejected_positions: Array[Vector3] = [Vector3(5.0, 0.0, 0.0)]
		var rejected_plot: Dictionary = farm.call("create_plot", rejected_positions, Vector2i.ONE, "", "Raiders")
		_expect(rejected_plot.is_empty(), "authoritative farm commit rejects a foreign-town cell")
	var farm_placement := _find_named_node(_scene, "FarmPlacementBridge")
	if farm_placement == null:
		_failures.append("runtime FarmPlacementBridge unavailable")
	else:
		var preview_solution := {
			"positions": [Vector3(5.0, 0.0, 0.0), Vector3(29.0, 0.0, 0.0)],
			"cell_keys": PackedStringArray(["0:0", "1:0"]),
			"blocked_cells": {},
		}
		farm_placement.call("_apply_territory_blocks", preview_solution, "Raiders")
		var blocked: Dictionary = preview_solution.get("blocked_cells", {})
		_expect(blocked.has("0:0") and not blocked.has("1:0") and int(preview_solution.get("valid_cell_count", 0)) == 1, "farm preview marks only foreign-town cells invalid")
	town.remove_from_group("settlement_town")


func _validate_missing_authority_fails_closed() -> void:
	var construction := get_first_node_in_group("construction_controller")
	var farm := _find_named_node(_scene, "FarmController")
	var farm_placement := _find_named_node(_scene, "FarmPlacementBridge")
	if construction == null or farm == null or farm_placement == null:
		_failures.append("runtime placement services unavailable for fail-closed checks")
		return
	var construction_territory = construction.get("_territory")
	construction.set("_territory", null)
	_expect(not bool(construction.call("can_place", Vector3(5000.0, 0.0, 5000.0), "Player").get("allowed", true)), "building placement fails closed without territory authority")
	construction.set("_territory", construction_territory)
	var farm_territory = farm.get("_territory")
	farm.set("_territory", null)
	_expect(not bool(farm.call("_can_create_field_at", Vector3(5000.0, 0.0, 5000.0), "Player")), "farm commits fail closed without territory authority")
	farm.set("_territory", farm_territory)
	var placement_territory = farm_placement.get("_territory")
	farm_placement.set("_territory", null)
	var preview_solution := {
		"positions": [Vector3(5000.0, 0.0, 5000.0)],
		"cell_keys": PackedStringArray(["0:0"]),
		"blocked_cells": {},
	}
	farm_placement.call("_apply_territory_blocks", preview_solution, "Player")
	_expect((preview_solution.get("blocked_cells", {}) as Dictionary).has("0:0") and not bool(preview_solution.get("valid", true)), "farm preview fails closed without territory authority")
	farm_placement.set("_territory", placement_territory)


func _validate_rustwash_canyon_runtime() -> void:
	var packed := load(RUSTWASH_ZONE_PATH) as PackedScene
	if packed == null:
		_failures.append("could not load Rustwash Basin zone")
		return
	var zone_template := packed.instantiate()
	var canyon_template := zone_template.get_node_or_null("Towns/Canyon") as Node3D
	if canyon_template == null:
		_failures.append("Rustwash Canyon town unavailable")
		zone_template.free()
		return
	var canyon_transform := canyon_template.transform
	canyon_template.get_parent().remove_child(canyon_template)
	zone_template.free()
	var canyon := canyon_template
	canyon.transform = canyon_transform
	root.add_child(canyon)
	await process_frame
	var shape: Dictionary = canyon.call("get_town_border_record")
	_expect(str(shape.get("shape_mode", "")) == "box", "Rustwash Canyon uses its live authored facility-footprint border")
	var canyon_faction := str(canyon.call("get_faction_id"))
	_expect(not canyon_faction.is_empty() and canyon_faction != "Player", "Rustwash Canyon remains a foreign-owned town")
	var territory := get_first_node_in_group("territory_controller")
	var center := canyon.global_position
	_expect(territory != null and not bool(territory.call("get_build_permission", center, "Player").get("can_build", true)), "Player cannot place inside Rustwash Canyon")
	var bounds_min: Vector2 = shape.get("bounds_min", Vector2.ZERO)
	var bounds_max: Vector2 = shape.get("bounds_max", Vector2.ZERO)
	var edge_center := Vector2(bounds_max.x, (bounds_min.y + bounds_max.y) * 0.5)
	var buffered_axis_local := edge_center + Vector2(17.5, 0.0)
	var outside_corner_local := bounds_max + Vector2(13.0, 13.0)
	var buffered_axis := canyon.global_transform * Vector3(buffered_axis_local.x, 0.0, buffered_axis_local.y)
	var outside_corner := canyon.global_transform * Vector3(outside_corner_local.x, 0.0, outside_corner_local.y)
	_expect(not bool(territory.call("get_build_permission", buffered_axis, "Player").get("can_build", true)), "Player cannot place within Canyon's live 18m border margin")
	_expect(bool(territory.call("get_build_permission", outside_corner, "Player").get("can_build", false)), "Canyon box corners do not overblock beyond the 18m distance")
	var construction := get_first_node_in_group("construction_controller")
	_expect(construction != null and not bool(construction.call("can_place", center, "Player").get("allowed", true)), "building placement rejects Rustwash Canyon center")
	var farm := _find_named_node(_scene, "FarmController")
	if farm != null:
		var positions: Array[Vector3] = [center]
		_expect((farm.call("create_plot", positions, Vector2i.ONE, "", "Player") as Dictionary).is_empty(), "farm commit rejects Rustwash Canyon center")
	canyon.remove_from_group("settlement_town")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _find_named_node(parent: Node, target_name: String) -> Node:
	if parent.name == target_name:
		return parent
	for child in parent.get_children():
		var found := _find_named_node(child, target_name)
		if found != null:
			return found
	return null


func _finish() -> void:
	if _failures.is_empty():
		print("TOWN_PLACEMENT_EXCLUSION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("TOWN_PLACEMENT_EXCLUSION_FAILED count=%d" % _failures.size())
	quit(1)
