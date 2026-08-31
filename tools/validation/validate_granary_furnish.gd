extends SceneTree

## Validates the granary furnish pass: pallets land on the floor of both a
## big hall and a cramped cottage, the layout mode ADAPTS to the shell (rows
## down a wide hall, a wall line in a cottage), pallets never overlap each
## other or other furniture, and the same seed reproduces the same floor.
## Run: godot --headless --path . --script res://tools/validation/validate_granary_furnish.gd

const BIG_SHELL_PATH := "res://features/world/projection/buildings/shells/modular/medium_wood_hall_20x12.tscn"
const SMALL_SHELL_PATH := "res://features/world/projection/buildings/shells/modular/small_wood_cottage.tscn"
const FURNISHER_PATH := "res://features/world/projection/props/furnishing/facility_furnisher.gd"
const RULES_PATH := "res://features/settlements/resources/furnishing/granary.tres"
const FUNCTION_PATH := "res://features/world_sim/resources/facility_functions/granary.tres"
## The pallet's own collision box (1.2 x 1.08) is the footprint the solver
## uses, so two pallets closer than this on both axes are overlapping.
const PALLET_FOOTPRINT := Vector2(1.2, 1.08)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var rules := load(RULES_PATH)
	var furnisher_script := load(FURNISHER_PATH)
	var function_definition := load(FUNCTION_PATH)
	if rules == null or furnisher_script == null or function_definition == null:
		_fail("Failed to load granary rules, function definition, or furnisher")
		_finish()
		return
	if str(function_definition.get("function_id")) != "granary" or str(function_definition.get("facility_type")) != "storage":
		_fail("Granary function must be function_id 'granary' of facility_type 'storage'")
	# The dock resolves furnish rules by function id first, so the rules file
	# must be named for the function or a granary silently furnishes as a
	# generic storage shed.
	if RULES_PATH != "res://features/settlements/resources/furnishing/%s.tres" % str(function_definition.get("function_id")):
		_fail("Granary rules must live at furnishing/<function_id>.tres to resolve from the dock")
	if rules.pallet_scenes.is_empty():
		_fail("Granary rules author no pallet scenes")
	else:
		var pallet := (rules.pallet_scenes[0] as PackedScene).instantiate()
		if str(pallet.get("container_type")) != "food" or not bool(pallet.get("contributes_to_town_stock")):
			_fail("A hand-placed storage pallet must default to authoritative Food storage")
		var nav_obstacle := pallet.get_node_or_null("NavigationObstacle3D") as NavigationObstacle3D
		if not (pallet is CollisionObject3D) or int((pallet as CollisionObject3D).collision_layer) != 1 \
				or nav_obstacle == null or not nav_obstacle.affect_navigation_mesh:
			_fail("Storage pallet must physically collide and author a baked navigation obstruction")
		pallet.free()
	if int(rules.min_pallets) < 1:
		_fail("A granary that furnishes with no pallet is non-functional; min_pallets must be >= 1")
	var facility_tools_source := FileAccess.get_file_as_string("res://addons/world_authoring/facility_tools.gd")
	var hand_place_body := facility_tools_source.get_slice("func _place_furniture_piece", 1).get_slice("func _on_field_painted", 0)
	if not hand_place_body.contains("_stamp_furniture_ids(node, facility)"):
		_fail("Hand-placed container furniture is not stamped into its facility/settlement")
	var big := await _furnish_shell(BIG_SHELL_PATH, furnisher_script, rules, 1)
	var big_again := await _furnish_shell(BIG_SHELL_PATH, furnisher_script, rules, 1)
	var small := await _furnish_shell(SMALL_SHELL_PATH, furnisher_script, rules, 1)
	var player_built := await _furnish_shell(BIG_SHELL_PATH, furnisher_script, rules, 1, false)
	_validate_pallets(big, "20x12 hall", 4)
	_validate_pallets(small, "cottage", 1)
	_validate_no_overlap(big, "20x12 hall")
	_validate_no_overlap(small, "cottage")
	if not _same_layout(big, big_again):
		_fail("Same seed must reproduce the identical granary floor")
	# The whole point of "auto": a 20x12 hall is wide enough for rows, a
	# cottage is not, and the same rules file must produce both.
	var big_rows := _row_count(big)
	var small_rows := _row_count(small)
	if big_rows < 2:
		_fail("20x12 hall should lay pallets out in at least 2 rows, got %d" % big_rows)
	if _pallets(small).size() > 0 and small_rows > 1:
		_fail("Cottage should line pallets along its walls, not stack %d rows" % small_rows)
	var stocked_utilities := big.filter(func(p): return p["kind"] == "utility" and p.has("stock") and not (p["stock"] as Array).is_empty())
	if stocked_utilities.size() < 2:
		_fail("Developer-authored granary must bake seed and tool starter recipes")
	if not player_built.filter(func(p): return p.has("stock")).is_empty():
		_fail("Player-built granary furnishing must never mint starter stock")
	for container in big.filter(func(p): return p["kind"] == "container"):
		if str(container.get("container_type", "")) != "food":
			_fail("Granary crates and barrels must author as Food containers")
	_finish()


func _furnish_shell(shell_path: String, furnisher_script, rules, seed_value: int, include_starting_stock := true) -> Array:
	var shell_scene := load(shell_path) as PackedScene
	if shell_scene == null:
		_fail("Failed to load shell %s" % shell_path)
		return []
	var building := shell_scene.instantiate() as Node3D
	building.set("building_id", "validation.granary_furnish")
	root.add_child(building)
	await process_frame
	await process_frame
	var furnisher = furnisher_script.new()
	var placements: Array = furnisher.furnish(building, rules, seed_value, include_starting_stock)
	if placements.is_empty():
		_fail("Furnish produced nothing for %s: %s" % [shell_path.get_file(), str(furnisher.last_error())])
	building.queue_free()
	return placements


func _pallets(placements: Array) -> Array:
	return placements.filter(func(p): return p["kind"] == "pallet")


func _validate_pallets(placements: Array, label: String, minimum: int) -> void:
	var pallets := _pallets(placements)
	if pallets.size() < minimum:
		_fail("%s: expected at least %d pallets, got %d" % [label, minimum, pallets.size()])
	for pallet in pallets:
		var origin: Vector3 = (pallet["transform"] as Transform3D).origin
		if absf(origin.y) > 0.01:
			_fail("%s: pallet floats off the floor plane at y=%f" % [label, origin.y])
		if str(pallet.get("container_type", "")) != "food":
			_fail("%s: furnished granary pallet must be stamped as Food storage" % label)
	# A granary is a store room, not a bunk house.
	if not placements.filter(func(p): return p["kind"] == "bed").is_empty():
		_fail("%s: granary furnished a bed" % label)


## Nothing on the floor may share space with anything else on the floor.
func _validate_no_overlap(placements: Array, label: String) -> void:
	var floor_kinds := ["pallet", "container", "cluster", "utility", "counter"]
	var floor_placements := placements.filter(func(p): return floor_kinds.has(str(p["kind"])))
	for i in range(floor_placements.size()):
		for j in range(i + 1, floor_placements.size()):
			var a: Transform3D = floor_placements[i]["transform"]
			var b: Transform3D = floor_placements[j]["transform"]
			var delta := Vector2(a.origin.x - b.origin.x, a.origin.z - b.origin.z).abs()
			var clearance := PALLET_FOOTPRINT.x * 0.5 + PALLET_FOOTPRINT.y * 0.5
			if delta.x < clearance and delta.y < clearance:
				_fail("%s: %s and %s overlap at %s / %s" % [label, floor_placements[i]["kind"], floor_placements[j]["kind"], a.origin, b.origin])


## Distinct pallet coordinates on the axis rows are stacked along. Rows share
## a coordinate to within a cell, so a wall line around a room reads as many
## rows and a real row block reads as few.
func _row_count(placements: Array) -> int:
	var pallets := _pallets(placements)
	if pallets.is_empty():
		return 0
	var xs := {}
	var zs := {}
	for pallet in pallets:
		var origin: Vector3 = (pallet["transform"] as Transform3D).origin
		xs[snappedf(origin.x, 0.25)] = true
		zs[snappedf(origin.z, 0.25)] = true
	return mini(xs.size(), zs.size())


func _same_layout(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for index in range(a.size()):
		if a[index]["kind"] != b[index]["kind"]:
			return false
		var transform_a: Transform3D = a[index]["transform"]
		var transform_b: Transform3D = b[index]["transform"]
		if transform_a.origin.distance_to(transform_b.origin) > 0.001:
			return false
	return true


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("GRANARY_FURNISH_OK")
	else:
		print("GRANARY_FURNISH_FAILED count=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
