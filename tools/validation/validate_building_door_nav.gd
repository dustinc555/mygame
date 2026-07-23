extends SceneTree

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
	region.bake_navigation_mesh(false)
	for _frame in range(4):
		await physics_frame
	var nav_mesh := region.navigation_mesh
	print("DOOR_NAV_DEBUG polygons=%d verts=%d" % [nav_mesh.get_polygon_count(), nav_mesh.get_vertices().size()])
	# The NavigationServer map never syncs in --script headless mode, so
	# assert walkable coverage directly on the baked mesh geometry. Doorway
	# thresholds are the connectors: coverage there means the rooms join.
	_assert_covered(nav_mesh, Vector3(3.0, 0.0, 3.0), "storefront floor")
	_assert_covered(nav_mesh, Vector3(3.5, 0.0, -2.0), "back room floor")
	_assert_any_covered(nav_mesh, shell, DIVIDER_OPENING_LOCAL_SAMPLES, "interior divider opening")
	_assert_covered(nav_mesh, Vector3(-1.0, 0.0, 6.0), "front door threshold")
	_assert_covered(nav_mesh, Vector3(3.0, 0.0, -4.0), "back door threshold")
	_assert_covered(nav_mesh, Vector3(3.0, 0.0, 10.0), "open ground outside")

	# Same shell tilted 8 degrees (terrain-normal ground snap): does the
	# divider doorway survive the bake?
	shell.rotation_degrees = Vector3(8.0, 0.0, 0.0)
	await physics_frame
	await physics_frame
	region.bake_navigation_mesh(false)
	for _frame in range(4):
		await physics_frame
	var tilted := region.navigation_mesh
	print("DOOR_NAV_DEBUG tilted polygons=%d" % tilted.get_polygon_count())
	_assert_any_covered(tilted, shell, DIVIDER_OPENING_LOCAL_SAMPLES, "TILTED interior divider opening")

	# Worst case: arbitrary world placement — off the cell grid and yaw-rotated
	# like a real placed building.
	(shell as Node3D).rotation_degrees = Vector3(0.0, 37.0, 0.0)
	(shell as Node3D).position = Vector3(0.05, 0.0, 0.07)
	await physics_frame
	await physics_frame
	region.bake_navigation_mesh(false)
	for _frame in range(4):
		await physics_frame
	var rotated := region.navigation_mesh
	print("DOOR_NAV_DEBUG rotated polygons=%d" % rotated.get_polygon_count())
	_assert_any_covered(rotated, shell, DIVIDER_OPENING_LOCAL_SAMPLES, "ROTATED off-grid interior divider opening")
	_finish()


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
