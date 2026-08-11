extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_farming_terrain3d.gd

const TERRAIN_SCENE := preload("res://scenes/zones/rustwash_basin/terrain/rustwash_basin_terrain.tscn")
const FARM_SOLVER := preload("res://features/farming/bridge/farm_placement_solver.gd")
const BUILDING_SOLVER := preload("res://features/settlements/bridge/building_placement_solver.gd")
const PLACEMENT_BRIDGE := preload("res://features/farming/bridge/farm_placement_bridge.gd")


class EmptyFarm:
	extends Node

	func find_plot_cell_at_world_position(_position: Vector3) -> Dictionary:
		return {}
	func find_plot_cells_at_world_positions(positions: Array, _excluded_plot_id := "", _cell_size := 1.25) -> Array[Dictionary]:
		var results: Array[Dictionary] = []
		for _position in positions:
			results.append({})
		return results


class AllowTerritory:
	extends Node

	func get_build_permission(_position: Vector3, _faction_id := "") -> Dictionary:
		return {"can_build": true}
	func get_build_permissions(positions: Array, _faction_id := "") -> Array[Dictionary]:
		var permissions: Array[Dictionary] = []
		for _position in positions:
			permissions.append({"can_build": true})
		return permissions


class SelectiveTerritory:
	extends Node
	var blocked_position := Vector3.ZERO
	func get_build_permissions(positions: Array, _faction_id := "") -> Array[Dictionary]:
		var permissions: Array[Dictionary] = []
		for position in positions:
			var world_position := position as Vector3
			var matches_blocked := Vector2(world_position.x, world_position.z).is_equal_approx(Vector2(blocked_position.x, blocked_position.z))
			permissions.append({"can_build": not matches_blocked})
		return permissions


class RecordingFarm:
	extends Node

	var occupant: Dictionary = {}
	var create_calls := 0
	var created_positions: Array[Vector3] = []

	func find_plot_cell_at_world_position(_position: Vector3, _excluded_plot_id := "", _cell_size := 1.25) -> Dictionary:
		return occupant.duplicate(true)
	func find_plot_cells_at_world_positions(positions: Array, _excluded_plot_id := "", _cell_size := 1.25) -> Array[Dictionary]:
		var results: Array[Dictionary] = []
		for _position in positions:
			results.append(occupant.duplicate(true))
		return results

	func plot_rectangle_positions(_plot_id: String, anchor: Vector3, drag_end: Vector3) -> Array[Vector3]:
		return [anchor, drag_end]

	func get_plot(_plot_id: String) -> Dictionary:
		return {"cell_size": 1.25}

	func can_actor_command_plot(_actor: Node, _plot_id: String) -> bool:
		return true

	func get_cell(_plot_id: String, _cell_key: String) -> Dictionary:
		return {"state": "untilled"}

	func create_plot(positions: Array[Vector3], _dimensions: Vector2i, _crop_id: String, _owner_faction_id: String, _settlement_id := "", _blocked_cells: Dictionary = {}, _cell_keys := PackedStringArray()) -> Dictionary:
		create_calls += 1
		created_positions.assign(positions)
		return {"plot_id": "review-test"}

	func request_cell_operation(_plot_id: String, _cell_key: String, _operation: String, _crop_id := "", _allowed_actor_ids := PackedStringArray()) -> Dictionary:
		return {}

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var territory := AllowTerritory.new()
	root.add_child(territory)
	var terrain = TERRAIN_SCENE.instantiate()
	root.add_child(terrain)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	camera.global_position = Vector3(3.37, 80.0, -17.41)
	camera.look_at(Vector3(3.37, 20.0, -37.41))
	terrain.set_camera(camera)
	await physics_frame
	await physics_frame
	await physics_frame

	var ground := _find_valid_slope_sample(terrain)
	_expect(ground.is_finite(), "World1 Terrain3D has ground within the building slope tolerance")
	camera.global_position = ground + Vector3(0.0, 35.0, 20.0)
	camera.look_at(ground)
	terrain.set_camera(camera)
	await physics_frame
	var space := root.get_world_3d().direct_space_state
	var cursor_hit := BUILDING_SOLVER.terrain_ray(space, ground + Vector3.UP * 40.0, ground - Vector3.UP * 40.0)
	_expect(not cursor_hit.is_empty(), "building placement recognizes World1 Terrain3D")
	var screen_hit := BUILDING_SOLVER.terrain_hit_from_screen(camera, get_root().size * 0.5)
	_expect(not screen_hit.is_empty(), "farming cursor ray reaches World1 Terrain3D")
	var solution := FARM_SOLVER.sample_grid(space, FARM_SOLVER.build_grid(ground, ground))
	_expect(bool(solution.get("valid", false)), "farming recognizes the same World1 Terrain3D ground")
	_expect(int(solution.get("terrain_cell_count", 0)) == 1, "farming samples one Terrain3D cell")
	_expect(FARM_SOLVER.MAX_SLOPE_DEG == BUILDING_SOLVER.MAX_SLOPE_DEG, "farming uses the building slope tolerance")
	var steep_ground := _find_steep_slope_sample(terrain)
	_expect(steep_ground.is_finite(), "World1 Terrain3D includes an excessive-slope sample")
	var steep_solution := FARM_SOLVER.sample_grid(space, FARM_SOLVER.build_grid(steep_ground, steep_ground))
	_expect(str((steep_solution.get("blocked_cells", {}) as Dictionary).get("0:0", "")) == "slope too steep", "World1 excessive slopes remain explicit invalid cells")
	var steep_preview := Node3D.new()
	root.add_child(steep_preview)
	var steep_bridge := PLACEMENT_BRIDGE.new()
	root.add_child(steep_bridge)
	steep_bridge.set("_territory", territory)
	steep_bridge.set("_preview", steep_preview)
	steep_bridge.set("_anchor", steep_ground)
	steep_bridge.set("_drag_end", steep_ground)
	steep_bridge.call("_update_preview")
	_expect(_preview_has_color(steep_preview, PLACEMENT_BRIDGE.PREVIEW_INVALID_COLOR), "Plan Field visibly rejects an excessive Terrain3D slope")
	var plan_preview := Node3D.new()
	root.add_child(plan_preview)
	var plan_bridge := PLACEMENT_BRIDGE.new()
	root.add_child(plan_bridge)
	plan_bridge.set("_territory", territory)
	plan_bridge.set("_preview", plan_preview)
	plan_bridge.set("_anchor", ground)
	plan_bridge.set("_drag_end", ground)
	plan_bridge.call("_update_preview")
	_expect(plan_preview.get_child_count() == 1, "Plan Field draws a projected World1 Terrain3D cell")
	var till_preview := Node3D.new()
	root.add_child(till_preview)
	var till_bridge := PLACEMENT_BRIDGE.new()
	root.add_child(till_bridge)
	till_bridge.set("_territory", territory)
	var empty_farm := EmptyFarm.new()
	root.add_child(empty_farm)
	till_bridge.set("_farm", empty_farm)
	till_bridge.set("_preview", till_preview)
	till_bridge.set("_anchor", ground)
	till_bridge.set("_drag_end", ground)
	till_bridge.call("_update_manual_till_preview")
	_expect(till_preview.get_child_count() == 1, "Till draws a projected World1 Terrain3D cell")

	# A release must resample even if the drag signature did not change.
	var release_farm := RecordingFarm.new()
	root.add_child(release_farm)
	var release_preview := Node3D.new()
	root.add_child(release_preview)
	var release_bridge := PLACEMENT_BRIDGE.new()
	root.add_child(release_bridge)
	release_bridge.set("_territory", territory)
	release_bridge.set("_farm", release_farm)
	release_bridge.set("_preview", release_preview)
	release_bridge.set("_anchor", ground)
	release_bridge.set("_drag_end", ground)
	release_bridge.call("_update_preview")
	var late_blocker := _add_static_box(root, ground + Vector3(0.36, 0.28, 0.0), Vector3(0.35, 0.5, 0.35))
	await physics_frame
	release_bridge.call("_finalize")
	_expect(release_farm.create_calls == 0, "Plan Field revalidates a late blocker before commit")

	# Existing untilled cells do not override physical placement rejection.
	var occupied_farm := RecordingFarm.new()
	occupied_farm.occupant = {"plot_id": "existing", "cell_key": "0:0"}
	root.add_child(occupied_farm)
	var occupied_preview := Node3D.new()
	root.add_child(occupied_preview)
	var occupied_bridge := PLACEMENT_BRIDGE.new()
	root.add_child(occupied_bridge)
	occupied_bridge.set("_territory", territory)
	var occupied_actor := Node.new()
	root.add_child(occupied_actor)
	occupied_bridge.set("_farm", occupied_farm)
	occupied_bridge.set("_preview", occupied_preview)
	occupied_bridge.set("_target_actor", occupied_actor)
	occupied_bridge.set("_anchor", ground)
	occupied_bridge.set("_drag_end", ground)
	occupied_bridge.call("_update_manual_till_preview")
	_expect((_eligible_positions(occupied_bridge)).is_empty(), "Till rejects a blocked existing untilled cell")
	_expect(_preview_has_color(occupied_preview, PLACEMENT_BRIDGE.PREVIEW_INVALID_COLOR), "blocked existing Till cell is visibly invalid")

	late_blocker.free()
	await physics_frame
	# Ignored character overlaps must not consume the query before a static blocker.
	var crowded_bodies: Array[Node] = []
	var crowded_blocker := _add_static_box(root, ground + Vector3(0.25, 0.28, 0.0), Vector3(0.18, 0.5, 0.18))
	for index in 13:
		var angle := TAU * float(index) / 13.0
		var offset := Vector3(cos(angle) * 0.47, 0.18, sin(angle) * 0.47)
		crowded_bodies.append(_add_character_box(root, ground + offset, Vector3(0.12, 0.3, 0.12)))
	await physics_frame
	var crowded_grid := FARM_SOLVER.build_grid(ground, ground)
	crowded_grid["ignore_characters"] = true
	var crowded_solution := FARM_SOLVER.sample_grid(space, crowded_grid)
	_expect(str((crowded_solution.get("blocked_cells", {}) as Dictionary).get("0:0", "")) == "occupied", "ignored characters cannot hide a real static blocker")
	for body in crowded_bodies:
		body.free()
	crowded_blocker.free()
	await physics_frame

	# A mixed drag renders both states and commits only the still-valid cell.
	var mixed_farm := RecordingFarm.new()
	root.add_child(mixed_farm)
	var mixed_preview := Node3D.new()
	root.add_child(mixed_preview)
	var mixed_bridge := PLACEMENT_BRIDGE.new()
	root.add_child(mixed_bridge)
	mixed_bridge.set("_territory", territory)
	mixed_bridge.set("_farm", mixed_farm)
	mixed_bridge.set("_preview", mixed_preview)
	mixed_bridge.set("_anchor", ground)
	mixed_bridge.set("_drag_end", ground + Vector3(1.25, 0.0, 0.0))
	var second_sample := ground + Vector3(1.25, 0.0, 0.0)
	second_sample.y = float(terrain.data.get_height(second_sample))
	var mixed_blocker := _add_static_box(root, second_sample + Vector3(0.35, 0.28, 0.0), Vector3(0.35, 0.5, 0.35))
	await physics_frame
	mixed_bridge.call("_update_preview")
	_expect(_preview_has_color(mixed_preview, PLACEMENT_BRIDGE.PREVIEW_ADD_COLOR), "mixed Plan Field drag keeps valid feedback")
	_expect(_preview_has_color(mixed_preview, PLACEMENT_BRIDGE.PREVIEW_INVALID_COLOR), "mixed Plan Field drag shows invalid feedback")
	mixed_bridge.call("_finalize")
	_expect(mixed_farm.create_calls == 1 and mixed_farm.created_positions.size() == 1, "mixed Plan Field drag commits only valid cells")
	mixed_blocker.free()
	await physics_frame

	# Field expansion keeps territory-rejected cells visible instead of dropping them.
	var expansion_farm := RecordingFarm.new()
	root.add_child(expansion_farm)
	var expansion_preview := Node3D.new()
	root.add_child(expansion_preview)
	var selective_territory := SelectiveTerritory.new()
	selective_territory.blocked_position = ground + Vector3(1.25, 0.0, 0.0)
	root.add_child(selective_territory)
	var expansion_bridge := PLACEMENT_BRIDGE.new()
	root.add_child(expansion_bridge)
	var expansion_actor := Node.new()
	root.add_child(expansion_actor)
	expansion_bridge.set("_farm", expansion_farm)
	expansion_bridge.set("_territory", selective_territory)
	expansion_bridge.set("_preview", expansion_preview)
	expansion_bridge.set("_target_actor", expansion_actor)
	expansion_bridge.set("_edit_plot_id", "existing")
	expansion_bridge.set("_anchor", ground)
	expansion_bridge.set("_drag_end", selective_territory.blocked_position)
	expansion_bridge.call("_update_field_edit_preview")
	_expect(_preview_has_color(expansion_preview, PLACEMENT_BRIDGE.PREVIEW_ADD_COLOR), "field expansion keeps valid feedback")
	_expect(_preview_has_color(expansion_preview, PLACEMENT_BRIDGE.PREVIEW_INVALID_COLOR), "field expansion shows territory-rejected cells as invalid")
	_finish()


func _eligible_positions(bridge: Node) -> Array:
	return (bridge.get("_latest_solution") as Dictionary).get("eligible_positions", []) as Array


func _preview_has_color(preview: Node3D, expected: Color) -> bool:
	for child in preview.get_children():
		var mesh := child as MeshInstance3D
		var material := mesh.material_override as StandardMaterial3D if mesh != null else null
		if material != null and material.albedo_color == expected:
			return true
	return false


func _add_static_box(parent: Node3D, position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	body.add_child(_box_shape(size))
	parent.add_child(body)
	return body


func _add_character_box(parent: Node3D, position: Vector3, size: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.position = position
	body.add_child(_box_shape(size))
	parent.add_child(body)
	return body


func _box_shape(size: Vector3) -> CollisionShape3D:
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	return collision


func _find_valid_slope_sample(terrain) -> Vector3:
	var minimum_up_dot := cos(deg_to_rad(BUILDING_SOLVER.MAX_SLOPE_DEG))
	for z_value in range(-100, 101, 5):
		for x_value in range(-100, 101, 5):
			var sample := Vector3(float(x_value), 0.0, float(z_value))
			var height := float(terrain.data.get_height(sample))
			if is_nan(height):
				continue
			var normal := terrain.data.get_normal(sample) as Vector3
			if normal.dot(Vector3.UP) >= minimum_up_dot:
				return Vector3(sample.x, height, sample.z)
	return Vector3.INF


func _find_steep_slope_sample(terrain) -> Vector3:
	var minimum_up_dot := cos(deg_to_rad(BUILDING_SOLVER.MAX_SLOPE_DEG))
	for z_value in range(-100, 101, 5):
		for x_value in range(-100, 101, 5):
			var sample := Vector3(float(x_value), 0.0, float(z_value))
			var height := float(terrain.data.get_height(sample))
			if is_nan(height):
				continue
			var normal := terrain.data.get_normal(sample) as Vector3
			if normal.dot(Vector3.UP) < minimum_up_dot:
				return Vector3(sample.x, height, sample.z)
	return Vector3.INF


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("FARMING_TERRAIN3D_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("FARMING_TERRAIN3D_FAILED count=%d" % _failures.size())
	quit(1)
