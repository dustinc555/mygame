extends SceneTree

## Validates generated placement data (not instantiated collision/navigation) against the real
## medium wood hall shell: exactly one counter, at least one table
## cluster, deterministic layouts per seed, different layouts across seeds,
## and no overlapping floor footprints. Uses load() at runtime, not preload:
## --script mode cannot compile GECS preload chains at parse time.

const SHELL_PATH := "res://features/world/projection/buildings/shells/modular/medium_wood_hall.tscn"
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
	building.set("building_id", "validation.facility_furnish")
	root.add_child(building)
	await process_frame
	await process_frame
	var first := _furnish(furnisher_script, building, rules, 1)
	var second := _furnish(furnisher_script, building, rules, 2)
	var first_again := _furnish(furnisher_script, building, rules, 1)
	_validate_layout(first, "seed 1", rules)
	_validate_layout(second, "seed 2", rules)
	_validate_levels(first, building, "seed 1")
	_validate_levels(second, building, "seed 2")
	_validate_nested_furnishing_ids()
	if not _same_layout(first, first_again):
		_fail("Same seed should reproduce the identical layout")
	if _same_layout(first, second):
		_fail("Different seeds should produce different layouts")
	building.queue_free()
	await process_frame
	_finish()


func _validate_nested_furnishing_ids() -> void:
	var authoring = load("res://addons/world_authoring/facility_tools.gd").new(null)
	var facility := (load("res://features/settlements/bridge/settlement_bar.tscn") as PackedScene).instantiate()
	facility.set("facility_id", "validation.furnish.ids")
	var cluster_scene := load("res://features/world/projection/props/furnishing/vignettes/table_cluster_2.tscn") as PackedScene
	var expected_surface_ids := {}
	for label in ["DiningA", "DiningB"]:
		var cluster := cluster_scene.instantiate()
		cluster.name = label
		# Match normal furnishing: stamp before mounting the authored instance.
		authoring._stamp_furniture_ids(cluster, facility)
		facility.add_child(cluster)
		authoring._own_facility_placement(cluster, facility)
		var surface := cluster.get_node("Table/TabletopSurface")
		var local_id := str(surface.get("surface_id"))
		if local_id.is_empty():
			_fail("Nested tabletop surface must receive a local ID before placement: %s" % label)
		elif expected_surface_ids.values().has(local_id):
			_fail("Independent furniture placements must not share a nested surface ID: %s" % local_id)
		expected_surface_ids[label] = local_id
		if str(surface.call("_get_surface_id")).is_empty():
			_fail("Stamped tabletop surface must resolve a durable facility-qualified host ID")
		authoring._stamp_furniture_ids(cluster, facility)
		if str(surface.get("surface_id")) != local_id:
			_fail("Repeated identity stamping must be idempotent")
	var packed := PackedScene.new()
	if packed.pack(facility) != OK:
		_fail("Authored furnished scene must pack")
	else:
		var restored := packed.instantiate()
		var restored_surface_ids := {}
		# Membership alone misses swapped IDs and two copies of one original ID.
		for label in expected_surface_ids:
			var surface := restored.get_node("%s/Table/TabletopSurface" % label)
			var local_id := str(surface.get("surface_id"))
			if local_id.is_empty() or local_id != expected_surface_ids[label]:
				_fail("Nested tabletop identity must remain attached to its placement: %s" % label)
			if restored_surface_ids.has(local_id):
				_fail("Restored tabletop identities must be unique: %s" % local_id)
			restored_surface_ids[local_id] = true
		restored.free()
	facility.free()
	authoring.teardown()


func _furnish(furnisher_script, building: Node3D, rules, seed_value: int) -> Array:
	var furnisher = furnisher_script.new()
	var placements: Array = furnisher.furnish(building, rules, seed_value)
	if placements.is_empty():
		_fail("Furnish produced nothing (seed %d): %s" % [seed_value, str(furnisher.last_error())])
	return placements


func _validate_layout(placements: Array, label: String, rules: Resource) -> void:
	var counters := placements.filter(func(p): return p["kind"] == "counter")
	var clusters := placements.filter(func(p): return p["kind"] == "cluster")
	var claimed_wall_faces := {}
	var exterior_entry_lights := 0
	if counters.size() != 1:
		_fail("%s: expected exactly 1 counter, got %d" % [label, counters.size()])
	if clusters.is_empty():
		_fail("%s: expected at least 1 table cluster" % label)
	# Independently compare oriented rectangles at each storey, using the
	# authored sizes rather than assuming a 2m center-distance is clearance.
	var floor_placements: Array = []
	for placement in placements:
		var kind := str(placement["kind"])
		var scene := placement.get("scene") as PackedScene
		if scene == null:
			_fail("%s: placement has no loadable scene" % label)
			continue
		var instance := scene.instantiate()
		if instance == null:
			_fail("%s: placement scene must instantiate" % label)
			continue
		var size := Vector2.ZERO
		if kind == "counter":
			size = rules.counter_footprint
		elif kind == "bed":
			size = rules.bed_footprint
		elif kind == "cluster":
			size = instance.get("footprint_meters")
		elif kind in ["utility", "container", "pallet"]:
			var shape := instance.get("collision_shape") as Shape3D
			if shape is BoxShape3D:
				size = Vector2(shape.size.x, shape.size.z)
			elif shape is CylinderShape3D:
				size = Vector2.ONE * shape.radius * 2.0
		instance.free()
		if kind in ["counter", "bed", "cluster", "utility", "container", "pallet"]:
			if size.x <= 0.0 or size.y <= 0.0:
				_fail("%s: floor placement %s must expose positive footprint" % [label, kind])
			else:
				floor_placements.append({"transform": placement.transform, "size": size})
	for i in range(floor_placements.size()):
		for j in range(i + 1, floor_placements.size()):
			if _footprints_overlap(floor_placements[i], floor_placements[j]):
				_fail("%s: floor footprints %d and %d overlap" % [label, i, j])
	for placement in placements:
		if placement["kind"] == "shelf" and absf(fmod((placement["transform"] as Transform3D).origin.y, 3.0) - 1.6) > 0.2:
			_fail("%s: shelf not at mount height" % label)
		if placement["kind"] != "shelf" and placement["kind"] != "light":
			continue
		var wall_face_key := str(placement.get("wall_face_key", ""))
		if wall_face_key.is_empty():
			_fail("%s: wall-mounted item has no wall-face claim" % label)
		elif claimed_wall_faces.has(wall_face_key):
			_fail("%s: multiple wall-mounted items claim wall face %s" % [label, wall_face_key])
		else:
			claimed_wall_faces[wall_face_key] = true
		exterior_entry_lights += 1 if bool(placement.get("exterior_entry_light", false)) else 0
	if exterior_entry_lights != 2:
		_fail("%s: expected one light at each of the hall's two exterior entrances, got %d" % [label, exterior_entry_lights])


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
		if a[index].get("scene") != b[index].get("scene") or not transform_a.is_equal_approx(transform_b):
			return false
	return true


# Separating-axis test; touching rectangles are not overlapping.
func _footprints_overlap(a: Dictionary, b: Dictionary) -> bool:
	var ta: Transform3D = a.transform
	var tb: Transform3D = b.transform
	if absf(ta.origin.y - tb.origin.y) > 0.5:
		return false
	var ax := Vector2(ta.basis.x.x, ta.basis.x.z)
	var az := Vector2(ta.basis.z.x, ta.basis.z.z)
	var bx := Vector2(tb.basis.x.x, tb.basis.x.z)
	var bz := Vector2(tb.basis.z.x, tb.basis.z.z)
	var delta := Vector2(tb.origin.x - ta.origin.x, tb.origin.z - ta.origin.z)
	for axis in [ax.normalized(), az.normalized(), bx.normalized(), bz.normalized()]:
		var ra: float = (absf(axis.dot(ax)) * a.size.x + absf(axis.dot(az)) * a.size.y) * 0.5
		var rb: float = (absf(axis.dot(bx)) * b.size.x + absf(axis.dot(bz)) * b.size.y) * 0.5
		if absf(delta.dot(axis)) >= ra + rb - 0.001:
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
