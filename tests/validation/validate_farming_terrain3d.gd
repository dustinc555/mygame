extends SceneTree
## Run: python3 tests/run_validation.py --filter tests/validation/validate_farming_terrain3d.gd --jobs 1

const FARM_SOLVER := preload("res://features/farming/bridge/farm_placement_solver.gd")
const BUILDING_SOLVER := preload("res://features/settlements/bridge/building_placement_solver.gd")
const PLACEMENT_BRIDGE := preload("res://features/farming/bridge/farm_placement_bridge.gd")

# One test-owned 64m region at 1m vertex spacing: y = clamp(x - 16, 0, 16).
# Both flat cell footprints are inside x < 16; the steep cell is on a 45-degree
# plane, well away from the ramp ends and region seams. No world/art resources.
const REGION_SIZE := 64
const RAMP_START_X := 16.0
const RAMP_HEIGHT := 16.0
const FLAT_GROUND := Vector3(8.0, 0.0, 8.0)
const SECOND_FLAT_GROUND := Vector3(9.25, 0.0, 8.0)
const STEEP_GROUND := Vector3(24.0, 8.0, 8.0)
const SURFACE_TOLERANCE := 0.01


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

	func can_actor_command_plot_state(_actor: Node, _plot: Dictionary) -> bool:
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
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	var ground := FLAT_GROUND
	camera.global_position = ground + Vector3(0.0, 35.0, 20.0)
	camera.look_at(ground)
	var terrain := _create_terrain(root, camera)
	var space := root.get_world_3d().direct_space_state
	# Wait for the native collision to enter PhysicsServer, not a world scan.
	for _frame in 60:
		await physics_frame
		if not BUILDING_SOLVER.terrain_ray(space, ground + Vector3.UP * 40.0, ground - Vector3.UP * 40.0).is_empty():
			break
	_expect(terrain.data.get_regions_active().size() == 1, "fixture contains exactly one Terrain3D region")
	for sample in [FLAT_GROUND, SECOND_FLAT_GROUND, STEEP_GROUND]:
		var expected_normal := Vector3(-1.0, 1.0, 0.0).normalized() if sample == STEEP_GROUND else Vector3.UP
		var height := terrain.data.get_height(sample)
		var normal := terrain.data.get_normal(sample)
		_expect(absf(height - sample.y) < SURFACE_TOLERANCE, "fixture height matches authored position %s" % sample)
		_expect(normal.distance_to(expected_normal) < SURFACE_TOLERANCE, "fixture normal matches authored plane at %s" % sample)
		var hit := BUILDING_SOLVER.terrain_ray(space, sample + Vector3.UP * 40.0, sample - Vector3.UP * 40.0)
		_expect(hit.get("rid", RID()) == terrain.collision.get_rid(), "fixture ray hits native Terrain3D collision at %s" % sample)
		var hit_position: Vector3 = hit.get("position", Vector3.INF)
		var hit_normal: Vector3 = hit.get("normal", Vector3.ZERO)
		_expect(hit_position.distance_to(sample) < SURFACE_TOLERANCE, "fixture collision height matches authored position %s" % sample)
		_expect(hit_normal.distance_to(expected_normal) < SURFACE_TOLERANCE, "fixture collision normal matches authored plane at %s" % sample)
		print("FARMING_TERRAIN3D_FIXTURE position=%s data_height=%.3f data_slope_deg=%.3f collision_position=%s collision_slope_deg=%.3f" % [sample, height, rad_to_deg(normal.angle_to(Vector3.UP)), hit_position, rad_to_deg(hit_normal.angle_to(Vector3.UP))])
	var cursor_hit := BUILDING_SOLVER.terrain_ray(space, ground + Vector3.UP * 40.0, ground - Vector3.UP * 40.0)
	_expect(not cursor_hit.is_empty(), "building placement recognizes fixture Terrain3D")
	# Camera projection uses viewport coordinates, not the headless window's
	# physical size (which differs when the project applies content scaling).
	var screen_center := camera.get_viewport().get_visible_rect().get_center()
	var screen_hit := BUILDING_SOLVER.terrain_hit_from_screen(camera, screen_center)
	_expect(not screen_hit.is_empty(), "farming cursor ray reaches fixture Terrain3D")
	_expect((screen_hit.get("position", Vector3.INF) as Vector3).distance_to(ground) < SURFACE_TOLERANCE, "camera cursor reaches the authored flat cell")
	var solution := FARM_SOLVER.sample_grid(space, FARM_SOLVER.build_grid(ground, ground))
	_expect(bool(solution.get("valid", false)), "farming recognizes the same fixture Terrain3D ground")
	_expect(int(solution.get("terrain_cell_count", 0)) == 1, "farming samples one Terrain3D cell")
	var flat_pair := FARM_SOLVER.sample_grid(space, FARM_SOLVER.build_grid(ground, SECOND_FLAT_GROUND))
	_expect(int(flat_pair.get("valid_cell_count", 0)) == 2 and (flat_pair.get("blocked_cells", {}) as Dictionary).is_empty(), "both authored flat cells are buildable before adding obstacles")
	_expect(FARM_SOLVER.MAX_SLOPE_DEG == BUILDING_SOLVER.MAX_SLOPE_DEG, "farming uses the building slope tolerance")
	var steep_ground := STEEP_GROUND
	_expect(rad_to_deg(terrain.data.get_normal(steep_ground).angle_to(Vector3.UP)) > BUILDING_SOLVER.MAX_SLOPE_DEG, "authored 45-degree Terrain3D plane exceeds the shared placement tolerance")
	var steep_solution := FARM_SOLVER.sample_grid(space, FARM_SOLVER.build_grid(steep_ground, steep_ground))
	_expect(str((steep_solution.get("blocked_cells", {}) as Dictionary).get("0:0", "")) == "slope too steep", "fixture excessive slopes remain explicit invalid cells")
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
	_expect(plan_preview.get_child_count() == 1, "Plan Field draws a projected fixture Terrain3D cell")
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
	_expect(till_preview.get_child_count() == 1, "Till draws a projected fixture Terrain3D cell")

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
	_expect(bool((release_bridge.get("_latest_solution") as Dictionary).get("valid", false)), "late-blocker probe starts with a valid cached placement")
	var late_blocker := _add_static_box(root, ground + Vector3(0.36, 0.28, 0.0), Vector3(0.35, 0.5, 0.35))
	await physics_frame
	release_bridge.call("_finalize")
	_expect(release_farm.create_calls == 0, "Plan Field revalidates a late blocker before commit")

	# Existing untilled cells do not override physical placement rejection.
	var occupied_farm := RecordingFarm.new()
	occupied_farm.occupant = {"plot_id": "existing", "cell_key": "0:0", "plot": {"plot_id": "existing"}, "cell": {"state": "untilled"}}
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
	occupied_bridge.call("_update_manual_till_preview")
	var unblocked_till := _eligible_positions(occupied_bridge)
	_expect(unblocked_till.size() == 1 and (unblocked_till[0] as Vector3).distance_to(ground) < SURFACE_TOLERANCE, "the same existing untilled cell is eligible after removing its physical blocker")
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
	mixed_bridge.set("_drag_end", SECOND_FLAT_GROUND)
	var mixed_blocker := _add_static_box(root, SECOND_FLAT_GROUND + Vector3(0.35, 0.28, 0.0), Vector3(0.35, 0.5, 0.35))
	await physics_frame
	mixed_bridge.call("_update_preview")
	_expect(_preview_has_color(mixed_preview, PLACEMENT_BRIDGE.PREVIEW_ADD_COLOR), "mixed Plan Field drag keeps valid feedback")
	_expect(_preview_has_color(mixed_preview, PLACEMENT_BRIDGE.PREVIEW_INVALID_COLOR), "mixed Plan Field drag shows invalid feedback")
	mixed_bridge.call("_finalize")
	_expect(mixed_farm.create_calls == 1 and mixed_farm.created_positions.size() == 1, "mixed Plan Field drag commits only valid cells")
	_expect(mixed_farm.created_positions.size() == 1 and mixed_farm.created_positions[0].distance_to(FLAT_GROUND) < SURFACE_TOLERANCE, "mixed commit contains exactly the authored unblocked flat cell")
	print("FARMING_TERRAIN3D_COMMIT calls=%d positions=%s" % [mixed_farm.create_calls, mixed_farm.created_positions])
	mixed_blocker.free()
	await physics_frame

	# Field expansion keeps territory-rejected cells visible instead of dropping them.
	var expansion_farm := RecordingFarm.new()
	root.add_child(expansion_farm)
	var expansion_preview := Node3D.new()
	root.add_child(expansion_preview)
	var selective_territory := SelectiveTerritory.new()
	selective_territory.blocked_position = SECOND_FLAT_GROUND
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


func _create_terrain(parent: Node3D, camera: Camera3D) -> Terrain3D:
	var terrain := Terrain3D.new()
	terrain.name = "FarmingTerrainFixture"
	terrain.region_size = REGION_SIZE
	terrain.vertex_spacing = 1.0
	parent.add_child(terrain)
	terrain.set_camera(camera)
	terrain.material.world_background = Terrain3DMaterial.NONE
	var heights := Image.create_empty(REGION_SIZE, REGION_SIZE, false, Image.FORMAT_RF)
	for x in REGION_SIZE:
		var height := clampf(float(x) - RAMP_START_X, 0.0, RAMP_HEIGHT)
		for z in REGION_SIZE:
			heights.set_pixel(x, z, Color(height, 0.0, 0.0, 1.0))
	var maps: Array[Image] = [heights, null, null]
	terrain.data.import_images(maps, Vector3.ZERO, 0.0, 1.0)
	# Build all native region collision after importing, including the steep
	# patch outside the cursor focus. Camera still follows normal node lifecycle.
	terrain.collision.mode = Terrain3DCollision.FULL_GAME
	terrain.collision.build()
	return terrain


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
