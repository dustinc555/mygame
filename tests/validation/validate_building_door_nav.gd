extends "res://tests/validation/test_case.gd"

## Bakes the medium wood hall shell on a flat floor with the real world nav
## settings and asserts NavigationServer paths connect: outside -> main hall
## (front door), and main hall -> back room (interior divider opening).
## Uses load() at runtime: --script mode cannot compile GECS preload chains.

const SHELL_SCENE_PATH := "res://features/world/projection/buildings/shells/modular/medium_wood_hall.tscn"
const SETTINGS_PATH := "res://features/core/navigation/resources/world_navigation_settings.tres"
const PIPELINE_PATH := "res://features/core/navigation/world_nav_bake_pipeline.gd"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var settings := load(SETTINGS_PATH)
	var pipeline := load(PIPELINE_PATH)
	var shell_scene := load(SHELL_SCENE_PATH) as PackedScene
	if settings == null or pipeline == null or shell_scene == null:
		_fail("Missing settings, pipeline, or shell scene")
		_finish()
		return
	var region := NavigationRegion3D.new()
	region.navigation_mesh = pipeline.call("build_template", settings, false)
	root.add_child(region)
	var navigation_map := region.get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(navigation_map, settings.cell_size)
	NavigationServer3D.map_set_cell_height(navigation_map, settings.cell_height)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120.0, 1.0, 120.0)
	shape.shape = box
	floor_body.add_child(shape)
	region.add_child(floor_body)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	var shell := shell_scene.instantiate()
	shell.set("building_id", "validation.medium_wood_hall")
	region.add_child(shell)
	# The neutral hall has an intentionally open divider passage centered here;
	# it no longer carries the removed function-specific WoodWear door node.
	const DIVIDER_OPENING_LOCAL_SAMPLES := [
		Vector3(0.25, 0.0, 0.0),
		Vector3(0.5, 0.0, 0.0),
		Vector3(0.75, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(1.25, 0.0, 0.0),
		Vector3(1.5, 0.0, 0.0),
		Vector3(1.75, 0.0, 0.0),
	]
	await physics_frame
	await physics_frame
	await _bake_and_sync(region)
	var nav_mesh := region.navigation_mesh
	print("DOOR_NAV_DEBUG polygons=%d verts=%d" % [nav_mesh.get_polygon_count(), nav_mesh.get_vertices().size()])
	# Geometry coverage is supporting evidence only; synchronized paths and
	# actual movement below prove the portals connect and have clearance.
	_assert_covered(nav_mesh, Vector3(3.0, 0.0, 3.0), "storefront floor")
	_assert_covered(nav_mesh, Vector3(3.5, 0.0, -2.0), "back room floor")
	_assert_any_covered(nav_mesh, shell, DIVIDER_OPENING_LOCAL_SAMPLES, "interior divider opening")
	_assert_covered(nav_mesh, Vector3(-1.0, 0.0, 6.0), "front door threshold")
	_assert_covered(nav_mesh, Vector3(3.0, 0.0, -4.0), "back door threshold")
	_assert_covered(nav_mesh, Vector3(3.0, 0.0, 10.0), "open ground outside")
	for door in get_nodes_in_group("world_door"):
		if shell.is_ancestor_of(door):
			door.apply_door_state({"is_open": true}, false)
	var actor: CharacterBody3D = load("res://features/core/party/party_member.tscn").instantiate()
	region.add_child(actor)
	actor.global_position = Vector3(-1, 0.5, 10)
	await _traverse(actor, Vector3(-1, 0.1, 4), navigation_map, "outside through front portal")
	await _traverse(actor, Vector3(3, 0.1, 3), navigation_map, "main hall")
	await _traverse(actor, Vector3(3.5, 0.1, -2), navigation_map, "main hall through divider into back room")
	actor.queue_free()
	await process_frame

	# Same shell tilted 8 degrees (terrain-normal ground snap): does the
	# divider doorway survive the bake?
	shell.rotation_degrees = Vector3(8.0, 0.0, 0.0)
	await physics_frame
	await physics_frame
	await _bake_and_sync(region)
	var tilted := region.navigation_mesh
	print("DOOR_NAV_DEBUG tilted polygons=%d" % tilted.get_polygon_count())
	_assert_any_covered(tilted, shell, DIVIDER_OPENING_LOCAL_SAMPLES, "TILTED interior divider opening")

	# Worst case: arbitrary world placement — off the cell grid and yaw-rotated
	# like a real placed building.
	(shell as Node3D).rotation_degrees = Vector3(0.0, 37.0, 0.0)
	(shell as Node3D).position = Vector3(0.05, 0.0, 0.07)
	await physics_frame
	await physics_frame
	await _bake_and_sync(region)
	var rotated := region.navigation_mesh
	print("DOOR_NAV_DEBUG rotated polygons=%d" % rotated.get_polygon_count())
	_assert_any_covered(rotated, shell, DIVIDER_OPENING_LOCAL_SAMPLES, "ROTATED off-grid interior divider opening")
	_assert_path(navigation_map, shell.to_global(Vector3(3, 0.1, 3)), shell.to_global(Vector3(3.5, 0.1, -2)), "rotated room connection")
	region.queue_free()
	await process_frame
	_finish()


func _bake_and_sync(region: NavigationRegion3D) -> void:
	var map := region.get_world_3d().navigation_map
	var previous := NavigationServer3D.map_get_iteration_id(map)
	region.bake_navigation_mesh(false)
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		await create_timer(0.01).timeout
		if NavigationServer3D.map_get_iteration_id(map) > previous and NavigationServer3D.map_get_closest_point_owner(map, region.navigation_mesh.get_vertices()[0]) == region.get_rid():
			return
	_fail("Baked region did not synchronize to the NavigationServer map")


func _assert_path(map: RID, start: Vector3, target: Vector3, label: String) -> bool:
	var path := NavigationServer3D.map_get_path(map, start, target, true)
	if path.size() < 2 or path[-1].distance_to(target) > 0.4:
		_fail("%s must have a complete path, got %s" % [label, path])
		return false
	return true


func _traverse(actor: CharacterBody3D, target: Vector3, map: RID, label: String) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while NavigationServer3D.map_get_iteration_id(map) == 0 and Time.get_ticks_msec() < deadline:
		await physics_frame
	if not _assert_path(map, actor.global_position, target, label):
		return
	var start := actor.global_position
	actor.set_move_target(target)
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if not actor.has_move_target():
			break
	var end := actor.global_position
	if actor.has_move_target() or end.distance_to(start) < 0.5 or Vector2(end.x - target.x, end.z - target.z).length() > actor.navigation_target_desired_distance + 0.05 or absf(end.y - target.y) > 0.8:
		_fail("%s physical traversal failed: end=%s target=%s moving=%s" % [label, end, target, actor.has_move_target()])
	else:
		print("DOOR_NAV_WALK_OK ", label)


func _assert_any_covered(nav_mesh: NavigationMesh, shell: Node3D, local_samples: Array, label: String) -> void:
	for local_point in local_samples:
		var world_point: Vector3 = shell.global_transform * (local_point as Vector3)
		var polygon_index := _covered_polygon(nav_mesh, world_point)
		if polygon_index >= 0:
			print("DOOR_NAV_OK %s covered at %s (poly %d)" % [label, world_point, polygon_index])
			return
	_fail("%s has NO walkable navmesh coverage across its authored gap" % label)


func _assert_covered(nav_mesh: NavigationMesh, world_point: Vector3, label: String) -> void:
	var polygon_index := _covered_polygon(nav_mesh, world_point)
	if polygon_index >= 0:
		print("DOOR_NAV_OK %s covered (poly %d)" % [label, polygon_index])
		return
	_fail("%s has NO walkable navmesh coverage at %s" % [label, world_point])


func _covered_polygon(nav_mesh: NavigationMesh, world_point: Vector3) -> int:
	var vertices := nav_mesh.get_vertices()
	for polygon_index in range(nav_mesh.get_polygon_count()):
		var polygon := nav_mesh.get_polygon(polygon_index)
		for corner in range(1, polygon.size() - 1):
			var a := vertices[polygon[0]]
			var b := vertices[polygon[corner]]
			var c := vertices[polygon[corner + 1]]
			if absf(minf(a.y, minf(b.y, c.y)) - world_point.y) > 1.0:
				continue
			if _triangle_contains_xz(a, b, c, world_point):
				return polygon_index
	return -1


func _triangle_contains_xz(a: Vector3, b: Vector3, c: Vector3, p: Vector3) -> bool:
	var pa := Vector2(a.x, a.z)
	var pb := Vector2(b.x, b.z)
	var pc := Vector2(c.x, c.z)
	var pp := Vector2(p.x, p.z)
	var d1 := (pp - pa).cross(pb - pa)
	var d2 := (pp - pb).cross(pc - pb)
	var d3 := (pp - pc).cross(pa - pc)
	var has_negative := d1 < 0.0 or d2 < 0.0 or d3 < 0.0
	var has_positive := d1 > 0.0 or d2 > 0.0 or d3 > 0.0
	return not (has_negative and has_positive)


func _finish() -> void:
	if _failures.is_empty():
		print("BUILDING_DOOR_NAV_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("BUILDING_DOOR_NAV_FAILED count=%d" % _failures.size())
	quit(1)


func _fail(message: String) -> void:
	_failures.append(message)
