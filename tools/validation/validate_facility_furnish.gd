extends SceneTree

## Validates the facility furnish pass end-to-end against the real
## woodbrick_shop_medium shell: exactly one counter, at least one table
## cluster, deterministic layouts per seed, different layouts across seeds,
## and no overlapping floor footprints. Uses load() at runtime, not preload:
## --script mode cannot compile GECS preload chains at parse time.

const SHELL_PATH := "res://features/world/projection/buildings/shells/modular/woodbrick_shop_medium.tscn"
const FURNISHER_PATH := "res://features/world/projection/props/furnishing/facility_furnisher.gd"
const RULES_PATH := "res://features/settlements/resources/furnishing/bar.tres"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var shell_scene := load(SHELL_PATH) as PackedScene
	var furnisher_script := load(FURNISHER_PATH)
	var rules := load(RULES_PATH)
	if shell_scene == null or furnisher_script == null or rules == null:
		_fail("Failed to load shell, furnisher, or rules")
		_finish()
		return
	var building := shell_scene.instantiate() as Node3D
	root.add_child(building)
	await process_frame
	await process_frame
	var first := _furnish(furnisher_script, building, rules, 1)
	var second := _furnish(furnisher_script, building, rules, 2)
	var first_again := _furnish(furnisher_script, building, rules, 1)
	_validate_layout(first, "seed 1")
	_validate_layout(second, "seed 2")
	_validate_levels(first, building, "seed 1")
	_validate_levels(second, building, "seed 2")
	if not _same_layout(first, first_again):
		_fail("Same seed should reproduce the identical layout")
	if _same_layout(first, second):
		_fail("Different seeds should produce different layouts")
	building.queue_free()
	_finish()


func _furnish(furnisher_script, building: Node3D, rules, seed_value: int) -> Array:
	var furnisher = furnisher_script.new()
	var placements: Array = furnisher.furnish(building, rules, seed_value)
	if placements.is_empty():
		_fail("Furnish produced nothing (seed %d): %s" % [seed_value, str(furnisher.last_error())])
	return placements


func _validate_layout(placements: Array, label: String) -> void:
	var counters := placements.filter(func(p): return p["kind"] == "counter")
	var clusters := placements.filter(func(p): return p["kind"] == "cluster")
	if counters.size() != 1:
		_fail("%s: expected exactly 1 counter, got %d" % [label, counters.size()])
	if clusters.is_empty():
		_fail("%s: expected at least 1 table cluster" % label)
	# Floor pieces must not overlap: cluster/counter centers need breathing room.
	var floor_placements := counters + clusters
	for i in range(floor_placements.size()):
		for j in range(i + 1, floor_placements.size()):
			var a: Transform3D = floor_placements[i]["transform"]
			var b: Transform3D = floor_placements[j]["transform"]
			if Vector2(a.origin.x, a.origin.z).distance_to(Vector2(b.origin.x, b.origin.z)) < 2.0:
				_fail("%s: floor placements %d and %d overlap" % [label, i, j])
	for placement in placements:
		if placement["kind"] == "shelf" and absf(fmod((placement["transform"] as Transform3D).origin.y, 3.0) - 1.6) > 0.2:
			_fail("%s: shelf not at mount height" % label)


## Regressions that shipped once and must never again: shelves mounted over
## window bays (a foundation wall below the window used to count as a solid
## anchor), and upper floors left empty.
func _validate_levels(placements: Array, building: Node3D, label: String) -> void:
	var beds := placements.filter(func(p): return p["kind"] == "bed")
	if beds.is_empty():
		_fail("%s: expected beds on the upper floor" % label)
	for bed in beds:
		if (bed["transform"] as Transform3D).origin.y < 2.0:
			_fail("%s: bed placed below the upper floor plane" % label)
	var window_walls: Array[Node3D] = []
	for piece_value in building.call("get_modular_pieces"):
		var piece := piece_value as Node3D
		if piece != null and str(piece.get("category")) == "wall_window":
			window_walls.append(piece)
	for placement in placements:
		if placement["kind"] != "shelf":
			continue
		var shelf: Transform3D = placement["transform"]
		var shelf_base_y := shelf.origin.y - 1.6
		for window in window_walls:
			var same_level := absf(window.position.y - shelf_base_y) < 0.8
			var same_bay := Vector2(shelf.origin.x, shelf.origin.z).distance_to(Vector2(window.position.x, window.position.z)) < 0.9
			if same_level and same_bay:
				_fail("%s: shelf mounted on a window bay at %s" % [label, shelf.origin])


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
		print("FACILITY_FURNISH_OK")
	else:
		print("FACILITY_FURNISH_FAILED count=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
