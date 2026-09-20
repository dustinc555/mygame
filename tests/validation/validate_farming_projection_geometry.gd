extends SceneTree
## Run: godot --headless --path . --script res://tests/validation/validate_farming_projection_geometry.gd

const PROJECTION = preload("res://features/farming/projection/farm_plot_projection.gd")


func _initialize() -> void:
	var projection = PROJECTION.new()
	var passed := projection is Area3D
	projection.free()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(10.0, 2.0, 8.0)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	PROJECTION.fit_mesh_to_ground(instance, 1.0, 0.2)
	var box := instance.get_aabb()
	var corners := [box.position, box.end]
	var world_min_y := INF
	var world_max_xz := 0.0
	for corner in corners:
		var p: Vector3 = instance.transform * corner
		world_min_y = minf(world_min_y, p.y)
		world_max_xz = maxf(world_max_xz, maxf(absf(p.x), absf(p.z)))
	passed = passed and absf(world_min_y) < 0.001 and world_max_xz <= 0.501
	instance.free()
	var group := Node3D.new()
	var offset_piece := MeshInstance3D.new()
	var offset_mesh := BoxMesh.new()
	offset_mesh.size = Vector3(90.0, 8.0, 90.0)
	offset_piece.mesh = offset_mesh
	offset_piece.position = Vector3(440.0, -4.0, -400.0)
	group.add_child(offset_piece)
	var target_diameter := 1.1
	var target_height := 0.12
	PROJECTION.fit_visual_group_to_ground(group, target_diameter, target_height)
	var transformed_center: Vector3 = group.transform * offset_piece.transform * offset_mesh.get_aabb().get_center()
	var transformed_bottom: Vector3 = group.transform * offset_piece.transform * offset_mesh.get_aabb().position
	passed = passed and absf(transformed_center.x) < 0.001 and absf(transformed_center.z) < 0.001 and absf(transformed_bottom.y) < 0.001
	var fitted_bounds: AABB = group.transform * offset_piece.transform * offset_mesh.get_aabb()
	var fitted_span := maxf(fitted_bounds.size.x, fitted_bounds.size.z)
	var size_matches := fitted_bounds.size.x > 0.0 and fitted_bounds.size.y > 0.0 and fitted_bounds.size.z > 0.0 \
		and fitted_span <= target_diameter + 0.001 and fitted_bounds.size.y <= target_height + 0.001 \
		and (is_equal_approx(fitted_span, target_diameter) or is_equal_approx(fitted_bounds.size.y, target_height))
	if not size_matches:
		push_error("oversized crop group must scale to the requested diameter and height")
	passed = size_matches and passed
	group.free()
	if passed:
		print("FARMING_PROJECTION_GEOMETRY_OK")
		quit(0)
		return
	push_error("plot remains an Area3D and fitting helpers ground/center oversized mesh groups")
	print("FARMING_PROJECTION_GEOMETRY_FAILED")
	quit(1)
