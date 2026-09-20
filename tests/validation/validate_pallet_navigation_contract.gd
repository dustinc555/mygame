extends SceneTree
## Reusable pallet contract: physical actors cannot pass through it and the
## world-nav bake discards walkable polygons from its footprint.

const PALLET_PATH := "res://features/world/projection/containers/bulk_storage_platform.tscn"
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var floor := StaticBody3D.new()
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(10.0, 0.2, 10.0)
	floor_collision.shape = floor_shape
	floor_collision.position.y = -0.1
	floor.add_child(floor_collision)
	fixture.add_child(floor)
	var pallet := (load(PALLET_PATH) as PackedScene).instantiate() as StaticBody3D
	pallet.set("container_id", "validation.pallet")
	pallet.set("settlement_id", "validation")
	fixture.add_child(pallet)
	await physics_frame
	_validate_navigation_bake(fixture, pallet)
	await _validate_physical_collision(fixture, pallet)
	root.remove_child(fixture)
	fixture.free()
	_finish()

func _validate_navigation_bake(fixture: Node3D, pallet: StaticBody3D) -> void:
	var mesh := _bake_fixture(fixture)
	if mesh.get_polygon_count() == 0:
		failures.append("Pallet bake must retain nonempty surrounding navigable floor")
	if not _walkable_at(mesh, Vector2(3.0, 3.0)):
		failures.append("Pallet bake must keep clear surrounding floor walkable")
	var probes := [Vector2.ZERO]
	var obstacle := pallet.get_node("NavigationObstacle3D") as NavigationObstacle3D
	for vertex in obstacle.vertices:
		probes.append(Vector2(vertex.x, vertex.z) * 0.9)
	for probe in probes:
		if _walkable_at(mesh, probe):
			failures.append("Navigation bake contains a walkable polygon in pallet footprint at %s" % probe)
	fixture.remove_child(pallet)
	var control := _bake_fixture(fixture)
	if control.get_polygon_count() == 0 or not _walkable_at(control, Vector2.ZERO):
		failures.append("Without pallet the same floor must bake a walkable center")
	fixture.add_child(pallet)


func _bake_fixture(fixture: Node3D) -> NavigationMesh:
	var settings := load("res://features/core/navigation/resources/world_navigation_settings.tres") as WorldNavigationSettings
	var mesh := WorldNavBakePipeline.build_template(settings, false)
	var geometry := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, geometry, fixture)
	NavigationServer3D.bake_from_source_geometry_data(mesh, geometry)
	return mesh


func _walkable_at(mesh: NavigationMesh, point: Vector2) -> bool:
	var vertices := mesh.get_vertices()
	for polygon_index in mesh.get_polygon_count():
		var polygon_indices := mesh.get_polygon(polygon_index)
		var polygon := PackedVector2Array()
		var average_height := 0.0
		for vertex_index in polygon_indices:
			var vertex: Vector3 = vertices[vertex_index]
			polygon.append(Vector2(vertex.x, vertex.z))
			average_height += vertex.y
		average_height /= maxf(polygon_indices.size(), 1)
		if average_height < 2.1 and Geometry2D.is_point_in_polygon(point, polygon):
			return true
	return false

func _validate_physical_collision(fixture: Node3D, pallet: StaticBody3D) -> void:
	var actor := CharacterBody3D.new()
	actor.collision_layer = 2
	actor.collision_mask = 9
	actor.floor_snap_length = 0.2
	var actor_collision := CollisionShape3D.new()
	var actor_shape := CapsuleShape3D.new()
	actor_shape.radius = 0.45
	actor_shape.height = 1.6
	actor_collision.shape = actor_shape
	actor.add_child(actor_collision)
	actor.position = Vector3(-2.0, 0.8, 0.0)
	fixture.add_child(actor)
	for _frame in 180:
		actor.velocity = Vector3(2.0, -1.0, 0.0)
		actor.move_and_slide()
		await physics_frame
	if actor.position.x > 0.8:
		failures.append("Physical actor walked through pallet collision")
	actor.position = Vector3(-2.0, 0.8, 2.5)
	for _frame in 180:
		actor.velocity = Vector3(2.0, -1.0, 0.0)
		actor.move_and_slide()
		await physics_frame
	if actor.position.x <= 0.8:
		failures.append("Clear-lane control must actually move across the same floor")
	if int(pallet.collision_layer) != 1:
		failures.append("Pallet is not on the ordinary physical furniture layer")

func _finish() -> void:
	if failures.is_empty():
		print("PALLET_NAVIGATION_CONTRACT_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("PALLET_NAVIGATION_CONTRACT_FAILED count=%d" % failures.size())
	quit(1)
