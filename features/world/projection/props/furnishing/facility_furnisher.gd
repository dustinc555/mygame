extends RefCounted

class_name FacilityFurnisher

## Furnish-pass solver: given a modular building shell and a FurnishRules
## recipe, produce furniture placements (building-local transforms) for the
## ground floor. The solver contributes NO taste — vignette scenes and the
## rules resource own the look. It contributes correctness:
##   - anchors derived from the modular pieces themselves (a wall side is
##     interior when the floor cell beside it is walkable, which also
##     handles divider walls that face interior on both sides)
##   - door keep-clear corridors
##   - an occupancy grid plus a flood-fill guarantee that a walk path
##     survives from every door to the counter and every table cluster
## Deterministic: the same seed always produces the same layout.

const CELL := 0.25
const WALL_THICKNESS := 0.4
const CLUSTER_MARGIN := 0.35
const DOOR_CORRIDOR_HALF_WIDTH := 1.0
const DOOR_CORRIDOR_DEPTH := 2.2
const DOOR_GAP_HALF_WIDTH := 0.95
const CUSTOMER_STRIP_METERS := 1.2

const STATE_BLOCKED := 0
const STATE_FREE := 1
const STATE_WALK_ONLY := 2  # reserved for movement: door corridors, staff/customer strips
const STATE_OCCUPIED := 3

var _grid := PackedByteArray()
var _grid_width := 0
var _grid_height := 0
var _grid_origin := Vector2.ZERO
var _door_cells: Array[Vector2i] = []
var _exterior_door_interior_sides := {}
var _region_labels := PackedInt32Array()
var _main_region := -1
var _exterior_regions := {}
var _last_error := ""
var _pending_required_clusters: Array = []
var _pending_required_utilities: Array = []
var _include_starting_stock := false


func last_error() -> String:
	return _last_error


## Returns an array of placements:
##   {"scene": PackedScene, "transform": Transform3D (building-local), "kind": String}
## Every storey is furnished: the ground floor gets counter + table clusters +
## shelves, upper floors get beds + shelves. Rules may allow ground-floor beds
## for one-storey homes.
## Empty array + last_error() on failure.
func furnish(building: Node3D, rules: FurnishRules, seed_value: int, include_starting_stock := false) -> Array[Dictionary]:
	_last_error = ""
	_include_starting_stock = include_starting_stock
	_pending_required_clusters = rules.required_cluster_scenes.duplicate()
	_pending_required_utilities = rules.utility_scenes.duplicate()
	var pieces := _collect_pieces(building)
	var level_ys := _floor_level_ys(pieces)
	if level_ys.is_empty():
		_last_error = "Shell has no floor pieces."
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_value)
	var placements: Array[Dictionary] = []
	for level_index in range(level_ys.size()):
		var level_placements := _furnish_level(pieces, rules, rng, level_index, level_ys[level_index])
		if level_index == 0 and level_placements.is_empty():
			return []
		placements.append_array(level_placements)
	if not _pending_required_clusters.is_empty():
		var scene: PackedScene = _pending_required_clusters[0]
		_last_error = "Required cluster '%s' fits on no storey of this shell." % str(scene.resource_path).get_file()
		return []
	if not _pending_required_utilities.is_empty() and rules.utilities_required:
		var scene: PackedScene = _pending_required_utilities[0]
		_last_error = "Required utility '%s' fits nowhere on the ground floor." % str(scene.resource_path).get_file()
		return []
	var kind_counts := {}
	for placement in placements:
		var kind := str(placement.get("kind", ""))
		kind_counts[kind] = int(kind_counts.get(kind, 0)) + 1
	for requirement in [
		["pallet", rules.min_pallets],
		["bed", rules.min_beds],
		["container", rules.min_containers],
		["shelf", rules.min_shelves],
		["light", rules.min_lights],
	]:
		var kind := str(requirement[0])
		var minimum := int(requirement[1])
		if int(kind_counts.get(kind, 0)) < minimum:
			_last_error = "Required %s count is %d, but only %d fit this shell." % [kind, minimum, int(kind_counts.get(kind, 0))]
			return []
	return placements


## One storey: build the walkability grid from THIS level's floors and walls
## (walls have their origin at their base, so a wall belongs to the level
## whose floor plane it stands on — foundation and other storeys' walls never
## leak in), place the level's archetypes, and lift everything to floor
## height at the end.
func _furnish_level(pieces: Array[Dictionary], rules: FurnishRules, rng: RandomNumberGenerator, level_index: int, floor_y: float) -> Array[Dictionary]:
	var floors: Array[Dictionary] = []
	var walls: Array[Dictionary] = []
	var blockers: Array[Dictionary] = []
	var stair_pieces: Array[Dictionary] = []
	for piece in pieces:
		var category: String = piece["category"]
		var piece_y: float = (piece["transform"] as Transform3D).origin.y
		if category == "floor" and absf(piece_y - floor_y) < 0.5:
			floors.append(piece)
		elif (category == "wall" or category == "wall_door" or category == "wall_window") and absf(piece_y - floor_y) < 0.5:
			walls.append(piece)
		elif (category == "corner" or category == "overhang") and absf(piece_y - floor_y) < 0.5:
			# Solid structural masonry (round corner towers, overhang corners)
			# seals the perimeter like a wall does. Without it the interior
			# flood leaks through the corner gaps to the grid border and the
			# whole building classifies as exterior — nothing gets furnished.
			blockers.append(piece)
		elif category == "stairs" and piece_y > floor_y - 3.6 and piece_y < floor_y + 0.5:
			# A stair run blocks the level it starts on AND feeds the level it
			# arrives at (its footprint marks the upper stairwell mouth).
			stair_pieces.append(piece)
	if floors.is_empty():
		if level_index == 0:
			_last_error = "Shell has no ground-floor floor pieces."
		return []
	_build_grid(floors, walls, blockers)
	var stair_mouth_cells: Array[Vector2i] = []
	for stair in stair_pieces:
		var size: Vector3 = stair["bounds"]
		_stamp_oriented_box(stair["transform"], Vector2(size.x + 0.6, size.z + 0.6), 0.0, STATE_WALK_ONLY, [STATE_FREE])
		_stamp_oriented_box(stair["transform"], Vector2(size.x, size.z), 0.0, STATE_BLOCKED, [])
		for cell in _box_cells(stair["transform"], Vector2(size.x + 0.6, size.z + 0.6), 0.0):
			if _state(cell) == STATE_WALK_ONLY:
				stair_mouth_cells.append(cell)
	if _door_cells.is_empty():
		# Upper floors have no doors; they are entered from the stairs, so the
		# stair mouth seeds the walkability flood.
		_door_cells = stair_mouth_cells
	if _door_cells.is_empty():
		if level_index == 0:
			_last_error = "Shell has no ground-floor door; nothing can reach the interior."
		return []
	_label_regions()
	var anchors := _wall_anchors(walls)
	var claimed_wall_faces := {}
	var placements: Array[Dictionary] = []
	if level_index == 0:
		var exterior_light := _place_exterior_entry_light(walls, anchors, rules, rng, claimed_wall_faces)
		if not exterior_light.is_empty():
			placements.append(exterior_light)
		var counter := _place_counter(anchors, rules, rng)
		if not counter.is_empty():
			placements.append(counter)
		# Pallets first: they ARE the facility's function (a granary without
		# them is not a granary), so in a shell too small for everything they
		# win the floor over support furniture like a seed barrel.
		placements.append_array(_place_pallets(anchors, rules, rng, placements))
		# Function-required wall storage claims its anchor before room layouts.
		placements.append_array(_place_utilities(anchors, rules, rng, placements))
		placements.append_array(_place_clusters(rules, rng, placements))
		if rules.beds_on_ground_floor:
			placements.append_array(_place_beds(anchors, rules, rng))
		placements.append_array(_place_containers(anchors, rules, rng, placements))
		placements.append_array(_place_shelves(anchors, rules, rng, counter, claimed_wall_faces))
		placements.append_array(_place_lights(anchors, rules, rng, claimed_wall_faces))
	else:
		if rules.clusters_on_upper_floors:
			placements.append_array(_place_clusters(rules, rng, placements))
		placements.append_array(_place_beds(anchors, rules, rng))
		placements.append_array(_place_shelves(anchors, rules, rng, {}, claimed_wall_faces))
		placements.append_array(_place_lights(anchors, rules, rng, claimed_wall_faces))
	if not _walkability_holds(placements):
		if level_index == 0:
			_last_error = "Walkability check failed after placement (solver bug guard)."
		return []
	for placement in placements:
		var lifted: Transform3D = placement["transform"]
		lifted.origin.y += floor_y
		placement["transform"] = lifted
		placement["level_index"] = level_index
	return placements


## --- Anchor extraction --------------------------------------------------------


func _collect_pieces(building: Node3D) -> Array[Dictionary]:
	var to_building := building.global_transform.affine_inverse()
	var result: Array[Dictionary] = []
	if not building.has_method("get_modular_pieces"):
		return result
	var pieces: Array = building.call("get_modular_pieces")
	pieces.sort_custom(func(a, b): return str(a.name) < str(b.name))
	for piece_value in pieces:
		var piece := piece_value as Node3D
		if piece == null:
			continue
		result.append({
			"node": piece,
			"transform": to_building * piece.global_transform,
			"bounds": piece.get("bounds_size_meters"),
			"category": str(piece.get("category")),
		})
	return result


## Distinct storey floor heights, ascending: floor pieces cluster tightly at
## each level's plane (ground 0, upper ~3) with roofs excluded by category.
func _floor_level_ys(pieces: Array[Dictionary]) -> Array[float]:
	var level_ys: Array[float] = []
	for piece in pieces:
		if piece["category"] != "floor":
			continue
		var piece_y: float = (piece["transform"] as Transform3D).origin.y
		var found := false
		for existing_y in level_ys:
			if absf(existing_y - piece_y) < 0.5:
				found = true
				break
		if not found:
			level_ys.append(piece_y)
	level_ys.sort()
	return level_ys


func _build_grid(floors: Array[Dictionary], walls: Array[Dictionary], blockers: Array[Dictionary] = []) -> void:
	var rect := Rect2()
	var has_rect := false
	for floor_piece in floors:
		var piece_rect := _piece_rect(floor_piece)
		rect = piece_rect if not has_rect else rect.merge(piece_rect)
		has_rect = true
	_grid_origin = rect.position
	_grid_width = int(ceil(rect.size.x / CELL))
	_grid_height = int(ceil(rect.size.y / CELL))
	_grid = PackedByteArray()
	_grid.resize(_grid_width * _grid_height)
	_grid.fill(STATE_BLOCKED)
	for floor_piece in floors:
		_stamp_rect(_piece_rect(floor_piece), STATE_FREE, [STATE_BLOCKED])
	for wall in walls:
		_stamp_oriented_box(wall["transform"], Vector2(wall["bounds"].x, WALL_THICKNESS), 0.0, STATE_BLOCKED, [])
	for blocker in blockers:
		_stamp_oriented_box(blocker["transform"], Vector2(blocker["bounds"].x, blocker["bounds"].z), 0.0, STATE_BLOCKED, [])
	_door_cells.clear()
	_exterior_door_interior_sides.clear()
	var interior_mouths: Array[Vector2i] = []
	for wall in walls:
		if wall["category"] != "wall_door":
			continue
		var wall_transform: Transform3D = wall["transform"]
		var along := Vector2(wall_transform.basis.x.x, wall_transform.basis.x.z).normalized()
		var normal := Vector2(wall_transform.basis.z.x, wall_transform.basis.z.z).normalized()
		var center := Vector2(wall_transform.origin.x, wall_transform.origin.z)
		# Carve the doorway through the wall stamp so rooms genuinely connect
		# on the grid — the walkability flood must pass through real openings,
		# not be faked by seeding both sides.
		var gap_offset := 0.0 - DOOR_GAP_HALF_WIDTH
		while gap_offset <= DOOR_GAP_HALF_WIDTH:
			var depth := -WALL_THICKNESS
			while depth <= WALL_THICKNESS:
				var gap_cell := _cell_at(center + along * gap_offset + normal * depth)
				if _in_grid(gap_cell):
					_set_state(gap_cell, STATE_WALK_ONLY)
				depth += CELL
			gap_offset += CELL
		# A door side is exterior when there is no walkable floor beyond it;
		# only exterior entrances seed the walkability flood.
		var interior_sides: Array[float] = []
		for side: float in [1.0, -1.0]:
			var probe := _cell_at(center + normal * side * (WALL_THICKNESS * 0.5 + 0.6))
			if _in_grid(probe) and _state(probe) != STATE_BLOCKED:
				interior_sides.append(side)
		var is_entrance := interior_sides.size() == 1
		if is_entrance:
			_exterior_door_interior_sides[wall["node"].get_instance_id()] = interior_sides[0]
		for side in interior_sides:
			var step := 0.0
			while step < DOOR_CORRIDOR_DEPTH:
				var offset := 0.0 - DOOR_CORRIDOR_HALF_WIDTH
				while offset <= DOOR_CORRIDOR_HALF_WIDTH:
					var point: Vector2 = center + normal * side * (WALL_THICKNESS * 0.5 + 0.1 + step) + along * offset
					var cell := _cell_at(point)
					if _in_grid(cell) and _state(cell) == STATE_FREE:
						_set_state(cell, STATE_WALK_ONLY)
					if step < 0.6 and _in_grid(cell) and _state(cell) != STATE_BLOCKED:
						if is_entrance:
							_door_cells.append(cell)
						else:
							interior_mouths.append(cell)
					offset += CELL
				step += CELL
	# Shells with no exterior door on this level (odd but possible) fall back
	# to seeding from every door mouth rather than failing outright.
	if _door_cells.is_empty():
		_door_cells = interior_mouths


## A wall side is a usable interior anchor when the cell just inside it is
## walkable floor — true for exterior walls (one side) and dividers (both).
func _wall_anchors(walls: Array[Dictionary]) -> Array[Dictionary]:
	var anchors: Array[Dictionary] = []
	for wall in walls:
		var wall_transform: Transform3D = wall["transform"]
		var normal3 := wall_transform.basis.z.normalized()
		for side: float in [1.0, -1.0]:
			var normal: Vector2 = Vector2(normal3.x, normal3.z) * side
			var center := Vector2(wall_transform.origin.x, wall_transform.origin.z)
			var probe: Vector2 = center + normal * (WALL_THICKNESS * 0.5 + 0.4)
			var cell := _cell_at(probe)
			var is_known_door_interior: bool = wall["category"] == "wall_door" and is_equal_approx(float(_exterior_door_interior_sides.get(wall["node"].get_instance_id(), 0.0)), side)
			if not is_known_door_interior:
				if not _in_grid(cell) or _state(cell) == STATE_BLOCKED:
					continue
				# Interior faces only — a porch under an exterior wall face is
				# walkable floor, but nothing mounts or stands out there.
				if not _is_interior_region(_region_of(probe)):
					continue
			anchors.append({
				"name": str(wall["node"].name) + ("+" if side > 0.0 else "-"),
				"wall_node_id": wall["node"].get_instance_id(),
				"wall_face_key": _wall_face_key(wall, side),
				"side": side,
				"category": wall["category"],
				"position": center,
				"mount_position": _wall_mount_position(wall, center),
				"normal": normal,
				"along": Vector2(wall_transform.basis.x.x, wall_transform.basis.x.z).normalized(),
			})
	return anchors


func _wall_face_key(wall: Dictionary, side: float) -> String:
	return "%d:%d" % [wall["node"].get_instance_id(), 1 if side > 0.0 else -1]


func _wall_mount_position(wall: Dictionary, center: Vector2) -> Vector2:
	if wall["category"] != "wall_door":
		return center
	var transform: Transform3D = wall["transform"]
	var along := Vector2(transform.basis.x.x, transform.basis.x.z).normalized()
	return center + along * minf(float((wall["bounds"] as Vector3).x) * 0.35, 0.7)


## --- Archetypes ----------------------------------------------------------------


## Counter goes against a solid wall, as far from the doors as possible,
## facing the room, with a reserved staff strip behind it and a customer
## strip in front.
func _place_counter(anchors: Array[Dictionary], rules: FurnishRules, rng: RandomNumberGenerator) -> Dictionary:
	if rules.counter_scenes.is_empty():
		return {}
	# The counter belongs in the main hall (largest walkable room), against a
	# solid wall, as far from the doors as that room allows — never exiled to
	# a back room just because it is farther from the entrance.
	var candidates := anchors.filter(func(anchor):
		if anchor["category"] != "wall":
			return false
		var probe: Vector2 = anchor["position"] + (anchor["normal"] as Vector2) * (WALL_THICKNESS * 0.5 + 0.6)
		return _region_of(probe) == _main_region)
	candidates.sort_custom(func(a, b): return _door_distance(a["position"]) > _door_distance(b["position"]))
	for anchor in candidates:
		var normal: Vector2 = anchor["normal"]
		var center_distance := WALL_THICKNESS * 0.5 + rules.counter_staff_strip_meters + rules.counter_footprint.y * 0.5
		var counter_center: Vector2 = anchor["position"] + normal * center_distance
		var yaw := atan2(normal.x, normal.y)
		var counter_transform := Transform3D(Basis(Vector3.UP, yaw), Vector3(counter_center.x, 0.0, counter_center.y))
		if not _region_is(counter_transform, rules.counter_footprint, 0.0, [STATE_FREE]):
			continue
		var staff_center: Vector2 = anchor["position"] + normal * (WALL_THICKNESS * 0.5 + rules.counter_staff_strip_meters * 0.5)
		var staff_transform := Transform3D(Basis(Vector3.UP, yaw), Vector3(staff_center.x, 0.0, staff_center.y))
		var customer_center: Vector2 = counter_center + normal * (rules.counter_footprint.y * 0.5 + CUSTOMER_STRIP_METERS * 0.5)
		var customer_transform := Transform3D(Basis(Vector3.UP, yaw), Vector3(customer_center.x, 0.0, customer_center.y))
		if not _region_is(customer_transform, Vector2(rules.counter_footprint.x, CUSTOMER_STRIP_METERS), 0.0, [STATE_FREE, STATE_WALK_ONLY]):
			continue
		_stamp_oriented_box(counter_transform, rules.counter_footprint, 0.0, STATE_OCCUPIED, [STATE_FREE])
		_stamp_oriented_box(staff_transform, Vector2(rules.counter_footprint.x + 0.5, rules.counter_staff_strip_meters), 0.0, STATE_WALK_ONLY, [STATE_FREE])
		_stamp_oriented_box(customer_transform, Vector2(rules.counter_footprint.x, CUSTOMER_STRIP_METERS), 0.0, STATE_WALK_ONLY, [STATE_FREE])
		return {
			"kind": "counter",
			"scene": rules.counter_scenes[rng.randi_range(0, rules.counter_scenes.size() - 1)],
			"transform": counter_transform,
			"reach_probe": customer_transform.origin,
		}
	return {}


func _place_clusters(rules: FurnishRules, rng: RandomNumberGenerator, existing: Array[Dictionary]) -> Array[Dictionary]:
	var placements: Array[Dictionary] = []
	if rules.cluster_scenes.is_empty() and _pending_required_clusters.is_empty():
		return placements
	# Seeded-shuffled sweep over every candidate cell: still random-feeling
	# across seeds, but exhaustive — if a cluster can fit anywhere, it fits.
	var candidates: Array[Vector2i] = []
	for y in range(_grid_height):
		for x in range(_grid_width):
			var candidate := Vector2i(x, y)
			if _state(candidate) == STATE_FREE and _is_interior_region(_region_labels[y * _grid_width + x]):
				candidates.append(candidate)
	for index in range(candidates.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var held := candidates[index]
		candidates[index] = candidates[swap]
		candidates[swap] = held
	# Required clusters first: they claim space before any optional roll and
	# each gets the full exhaustive sweep on this storey. Whatever is still
	# pending after the last storey fails the furnish in furnish().
	for scene_index in range(_pending_required_clusters.size() - 1, -1, -1):
		var required_scene: PackedScene = _pending_required_clusters[scene_index]
		var required_footprint := _vignette_footprint(required_scene)
		for cell in candidates:
			if _state(cell) != STATE_FREE:
				continue
			var placement := _try_stamp_cluster(required_scene, required_footprint, cell, rules.cluster_margin, rng, existing + placements)
			if not placement.is_empty():
				placements.append(placement)
				_pending_required_clusters.remove_at(scene_index)
				break
	if rules.cluster_scenes.is_empty():
		return placements
	var footprints := {}
	for scene in rules.cluster_scenes:
		footprints[scene] = _vignette_footprint(scene)
	var free_area := _count_state(STATE_FREE) * CELL * CELL
	var target := clampi(int(free_area / maxf(rules.square_meters_per_cluster, 1.0)), 1, rules.max_clusters)
	var placed := 0
	for cell in candidates:
		if placed >= target:
			break
		if _state(cell) != STATE_FREE:
			continue
		var scene: PackedScene = rules.cluster_scenes[rng.randi_range(0, rules.cluster_scenes.size() - 1)]
		var placement := _try_stamp_cluster(scene, footprints[scene], cell, rules.cluster_margin, rng, existing + placements)
		if placement.is_empty():
			continue
		placements.append(placement)
		placed += 1
	return placements


## One cluster fit attempt at one candidate cell: footprint must be free,
## the breathing margin may border walk corridors (people walking past a
## table is fine, a table standing IN the corridor is not), and the stamp
## must not strand any earlier placement's reach probe.
func _try_stamp_cluster(scene: PackedScene, footprint: Vector2, cell: Vector2i, margin: float, rng: RandomNumberGenerator, already_placed: Array[Dictionary]) -> Dictionary:
	var yaw := (PI * 0.5) * rng.randi_range(0, 3) + deg_to_rad(rng.randf_range(-5.0, 5.0))
	var origin := _cell_center(cell)
	var cluster_transform := Transform3D(Basis(Vector3.UP, yaw), Vector3(origin.x, 0.0, origin.y))
	if not _region_is(cluster_transform, footprint, 0.0, [STATE_FREE]):
		return {}
	if not _region_is(cluster_transform, footprint, margin, [STATE_FREE, STATE_WALK_ONLY]):
		return {}
	_stamp_oriented_box(cluster_transform, footprint, 0.0, STATE_OCCUPIED, [STATE_FREE])
	var probe := origin + Vector2(cos(yaw), -sin(yaw)) * (footprint.x * 0.5 + margin + CELL)
	var placement := {
		"kind": "cluster",
		"scene": scene,
		"transform": cluster_transform,
		"reach_probe": Vector3(probe.x, 0.0, probe.y),
	}
	var check: Array[Dictionary] = already_placed.duplicate()
	check.append(placement)
	if not _walkability_holds(check):
		_stamp_oriented_box(cluster_transform, footprint, 0.0, STATE_FREE, [STATE_OCCUPIED])
		return {}
	return placement


## Beds stand against upper-floor walls, headboard to the wall, foot into the
## room. Windows behind a bed are fine; doors are not.
func _place_beds(anchors: Array[Dictionary], rules: FurnishRules, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var placements: Array[Dictionary] = []
	if rules.bed_scenes.is_empty():
		return placements
	var candidates := anchors.filter(func(anchor): return anchor["category"] != "wall_door")
	for index in range(candidates.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var held = candidates[index]
		candidates[index] = candidates[swap]
		candidates[swap] = held
	var rejects := {"chance": 0, "free": 0, "margin": 0, "walk": 0}
	for anchor in candidates:
		if placements.size() >= rules.max_beds:
			break
		if rng.randf() > rules.bed_chance:
			rejects["chance"] += 1
			continue
		var normal: Vector2 = anchor["normal"]
		var along: Vector2 = anchor["along"]
		var slide := rng.randf_range(-0.25, 0.25)
		var center: Vector2 = anchor["position"] + normal * (WALL_THICKNESS * 0.5 + rules.bed_footprint.y * 0.5 + 0.05) + along * slide
		var yaw := atan2(normal.x, normal.y)
		var bed_transform := Transform3D(Basis(Vector3.UP, yaw), Vector3(center.x, 0.0, center.y))
		if not _region_is(bed_transform, rules.bed_footprint, 0.0, [STATE_FREE]):
			rejects["free"] += 1
			continue
		# Against-wall margin: the ring legitimately overlaps the wall band
		# behind the headboard, so only OTHER FURNITURE may not crowd it.
		if _region_touches(bed_transform, rules.bed_footprint, CLUSTER_MARGIN, STATE_OCCUPIED):
			rejects["margin"] += 1
			continue
		_stamp_oriented_box(bed_transform, rules.bed_footprint, 0.0, STATE_OCCUPIED, [STATE_FREE])
		var probe: Vector2 = center + normal * (rules.bed_footprint.y * 0.5 + CLUSTER_MARGIN + CELL)
		var placement := {
			"kind": "bed",
			"scene": rules.bed_scenes[rng.randi_range(0, rules.bed_scenes.size() - 1)],
			"transform": bed_transform,
			"reach_probe": Vector3(probe.x, 0.0, probe.y),
		}
		var check: Array[Dictionary] = placements.duplicate()
		check.append(placement)
		if not _walkability_holds(check):
			_stamp_oriented_box(bed_transform, rules.bed_footprint, 0.0, STATE_FREE, [STATE_OCCUPIED])
			rejects["walk"] += 1
			continue
		placements.append(placement)
	if not OS.get_environment("FURNISH_DEBUG").is_empty():
		print("beds: %d placed, %d candidates, rejects %s" % [placements.size(), candidates.size(), rejects])
	return placements


## Containers (crates/barrels) stand against solid walls in whatever floor
## space the tables left over — door corridors and staff/customer strips are
## WALK_ONLY on the grid, so the FREE-state requirement keeps them out of
## traffic without any explicit door logic. Each placed container carries a
## stock list rolled from the rules' loot table, baked into the saved node.
## Utility pieces: one guaranteed wall placement per scene. Optional starter
## stock is baked only when the caller explicitly enables developer/world
## generation; runtime player furnishing stays empty.
func _place_utilities(anchors: Array[Dictionary], rules: FurnishRules, rng: RandomNumberGenerator, existing: Array[Dictionary]) -> Array[Dictionary]:
	var placements: Array[Dictionary] = []
	if _pending_required_utilities.is_empty():
		return placements
	var candidates := anchors.filter(func(anchor): return anchor["category"] == "wall")
	for index in range(candidates.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var held = candidates[index]
		candidates[index] = candidates[swap]
		candidates[swap] = held
	for scene_index in range(_pending_required_utilities.size() - 1, -1, -1):
		var scene: PackedScene = _pending_required_utilities[scene_index]
		var footprint := _container_footprint(scene)
		for anchor in candidates:
			var normal: Vector2 = anchor["normal"]
			var center: Vector2 = anchor["position"] + normal * (WALL_THICKNESS * 0.5 + footprint.y * 0.5 + 0.05)
			var yaw := atan2(normal.x, normal.y)
			var utility_transform := Transform3D(Basis(Vector3.UP, yaw), Vector3(center.x, 0.0, center.y))
			if not _region_is(utility_transform, footprint, 0.0, [STATE_FREE]):
				continue
			if _region_touches(utility_transform, footprint, CLUSTER_MARGIN, STATE_OCCUPIED):
				continue
			_stamp_oriented_box(utility_transform, footprint, 0.0, STATE_OCCUPIED, [STATE_FREE])
			var probe: Vector2 = center + normal * (footprint.y * 0.5 + CLUSTER_MARGIN + CELL)
			var placement := {
				"kind": "utility",
				"scene": scene,
				"transform": utility_transform,
				"reach_probe": Vector3(probe.x, 0.0, probe.y),
			}
			var utility_index := rules.utility_scenes.find(scene)
			if _include_starting_stock and utility_index >= 0 and utility_index < rules.utility_stock_tables.size():
				var stock_table := rules.utility_stock_tables[utility_index]
				if stock_table != null:
					placement["stock"] = stock_table.roll(rng)
			# Same rule as containers: the stamp must not strand any earlier
			# placement's reach probe, or the whole level gets rejected by
			# the final walkability guard.
			var check: Array[Dictionary] = existing + placements
			check.append(placement)
			if not _walkability_holds(check):
				_stamp_oriented_box(utility_transform, footprint, 0.0, STATE_FREE, [STATE_OCCUPIED])
				continue
			placements.append(placement)
			_pending_required_utilities.remove_at(scene_index)
			break
	return placements


## Bulk storage pallets — the one archetype whose layout the SHELL decides
## rather than the rules file. A hall wide enough for two rows plus a
## walkable aisle gets rows down its long axis; anything tighter lines its
## pallets along the walls instead, which is what a cottage-sized store
## wants. "auto" measures; the explicit modes override.
func _place_pallets(anchors: Array[Dictionary], rules: FurnishRules, rng: RandomNumberGenerator, existing: Array[Dictionary]) -> Array[Dictionary]:
	var placements: Array[Dictionary] = []
	if rules.pallet_scenes.is_empty() or rules.max_pallets <= 0:
		return placements
	var footprints := {}
	var span := Vector2.ZERO
	for scene in rules.pallet_scenes:
		var footprint := _container_footprint(scene)
		footprints[scene] = footprint
		# Row/line spacing must clear the BIGGEST pallet in the pool, or a
		# large one lands flush against its neighbour.
		span = Vector2(maxf(span.x, footprint.x), maxf(span.y, footprint.y))
	var layout := str(rules.pallet_layout)
	if layout == "auto":
		layout = "aisle_rows" if _aisle_rows_fit(rules, span) else "wall_line"
	if layout == "aisle_rows":
		placements = _place_pallet_rows(rules, rng, footprints, span, existing)
		# Rows that survive the fit math can still lose to furniture already
		# on the floor. An empty granary is worse than a lined-up one.
		if placements.is_empty():
			layout = "wall_line"
	if layout == "wall_line":
		placements = _place_pallet_wall_line(anchors, rules, rng, footprints, span, existing)
	_assign_pallet_items(placements, rules)
	return placements


## Rows need two things: the room's SHORT span must clear two rows plus the
## aisle and both wall strips, and there must be enough free floor left that
## an aisle is a better use of it than open walking space. The area gate is
## what keeps a cottage-sized store room lining its walls even when its
## bounding box looks wide enough.
func _aisle_rows_fit(rules: FurnishRules, span: Vector2) -> bool:
	var rect := _main_region_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return false
	var needed := span.y * 2.0 + rules.pallet_aisle_meters + rules.pallet_wall_clearance * 2.0
	if minf(rect.size.x, rect.size.y) < needed:
		return false
	return _count_state(STATE_FREE) * CELL * CELL >= rules.pallet_rows_min_floor_area


## Rows run along the room's long axis. Capacity is SCANNED, not computed:
## an L-shaped hall's bounding box covers floor that isn't there, so each row
## line is dry-fitted first and rows that land in the void drop out. The
## pallet budget is then dealt round-robin across the surviving rows, centre
## outward, so a cap of 8 in a 12-slot hall reads as two tidy rows of four
## rather than one long row and an empty aisle.
func _place_pallet_rows(rules: FurnishRules, rng: RandomNumberGenerator, footprints: Dictionary, span: Vector2, existing: Array[Dictionary]) -> Array[Dictionary]:
	var placements: Array[Dictionary] = []
	var rect := _main_region_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return placements
	var rows_along_x := rect.size.x >= rect.size.y
	var long_span := rect.size.x if rows_along_x else rect.size.y
	var short_span := rect.size.y if rows_along_x else rect.size.x
	var row_pitch := maxf(span.y + rules.pallet_aisle_meters, CELL)
	var column_pitch := maxf(span.x + rules.pallet_gap_meters, CELL)
	var rows_fit := int(floor((short_span - rules.pallet_wall_clearance * 2.0 + rules.pallet_aisle_meters) / row_pitch))
	var columns_fit := int(floor((long_span - rules.pallet_wall_clearance * 2.0 + rules.pallet_gap_meters) / column_pitch))
	if rows_fit < 1 or columns_fit < 1:
		return placements
	# Shape the block like the room rather than filling every row that fits:
	# a budget of 8 in a long hall wants two rows of four flanking a central
	# aisle, not four stubby rows clumped in the middle of an empty floor.
	var aspect := long_span / maxf(short_span, CELL)
	var rows := clampi(int(round(sqrt(rules.max_pallets / maxf(aspect, 0.01)))), 1, rows_fit)
	var columns := clampi(int(ceil(float(rules.max_pallets) / float(rows))), 1, columns_fit)
	# A budget too big for that many columns opens more rows again.
	rows = clampi(int(ceil(float(rules.max_pallets) / float(columns))), rows, rows_fit)
	var center := rect.get_center()
	var center_long := center.x if rows_along_x else center.y
	var center_short := center.y if rows_along_x else center.x
	var first_long := center_long - (columns * span.x + (columns - 1) * rules.pallet_gap_meters) * 0.5 + span.x * 0.5
	var first_short := center_short - (rows * span.y + (rows - 1) * rules.pallet_aisle_meters) * 0.5 + span.y * 0.5
	var yaw := 0.0 if rows_along_x else PI * 0.5
	var footprint: Vector2 = footprints[rules.pallet_scenes[0]]
	# Pass one: which slots are real floor?
	var open_slots: Array = []
	for row in range(rows):
		var short_offset := first_short + row * row_pitch
		var slots: Array[Vector2] = []
		for column in range(columns):
			var long_offset := first_long + column * column_pitch
			var point := Vector2(long_offset, short_offset) if rows_along_x else Vector2(short_offset, long_offset)
			var probe_transform := Transform3D(Basis(Vector3.UP, yaw), Vector3(point.x, 0.0, point.y))
			if _region_is(probe_transform, footprint, 0.0, [STATE_FREE]):
				slots.append(point)
		if not slots.is_empty():
			# Centre outward, so a partly-filled row sits in the middle of its
			# run instead of hugging one end wall.
			var midpoint: Vector2 = slots[slots.size() / 2]
			slots.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(midpoint) < b.distance_squared_to(midpoint))
			open_slots.append(slots)
	if open_slots.is_empty():
		return placements
	# Pass two: deal the budget round-robin so every row fills evenly.
	var depth := 0
	while placements.size() < rules.max_pallets:
		var dealt := false
		for row_index in range(open_slots.size()):
			if placements.size() >= rules.max_pallets:
				break
			var slots: Array = open_slots[row_index]
			if depth >= slots.size():
				continue
			dealt = true
			var point: Vector2 = slots[depth]
			var short_offset := point.y if rows_along_x else point.x
			# Every gap between consecutive rows IS an aisle, so reaching
			# toward the room centre always lands the work side in walkable
			# space; the outermost rows reach into their wall clearance.
			var toward := signf(center_short - short_offset)
			if is_zero_approx(toward):
				toward = 1.0
			var probe_offset := Vector2(0.0, toward) if rows_along_x else Vector2(toward, 0.0)
			var probe: Vector2 = point + probe_offset * (span.y * 0.5 + CELL * 2.0)
			var scene: PackedScene = rules.pallet_scenes[rng.randi_range(0, rules.pallet_scenes.size() - 1)]
			var placement := _try_stamp_pallet(scene, footprints[scene], point, yaw, probe, existing + placements)
			if not placement.is_empty():
				placements.append(placement)
		if not dealt:
			break
		depth += 1
	return placements


## Cramped shells: pallets stand against solid walls, axis-aligned (no
## container-style wobble — a store room reads as deliberate), stepping along
## each wall face until the run leaves the wall or meets other furniture.
func _place_pallet_wall_line(anchors: Array[Dictionary], rules: FurnishRules, rng: RandomNumberGenerator, footprints: Dictionary, span: Vector2, existing: Array[Dictionary]) -> Array[Dictionary]:
	var placements: Array[Dictionary] = []
	var candidates := anchors.filter(func(anchor): return anchor["category"] == "wall")
	for index in range(candidates.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var held = candidates[index]
		candidates[index] = candidates[swap]
		candidates[swap] = held
	var step := span.x + rules.pallet_gap_meters
	for anchor in candidates:
		if placements.size() >= rules.max_pallets:
			break
		var normal: Vector2 = anchor["normal"]
		var along: Vector2 = anchor["along"]
		var yaw := atan2(normal.x, normal.y)
		# Centre of the wall face outward, alternating sides, so a run grows
		# symmetrically instead of drifting toward one corner.
		for slot in range(-2, 3):
			if placements.size() >= rules.max_pallets:
				break
			var scene: PackedScene = rules.pallet_scenes[rng.randi_range(0, rules.pallet_scenes.size() - 1)]
			var footprint: Vector2 = footprints[scene]
			var point: Vector2 = anchor["position"] + normal * (WALL_THICKNESS * 0.5 + footprint.y * 0.5 + rules.pallet_wall_clearance) + along * (slot * step)
			var probe: Vector2 = point + normal * (footprint.y * 0.5 + CELL * 2.0)
			var placement := _try_stamp_pallet(scene, footprint, point, yaw, probe, existing + placements)
			if not placement.is_empty():
				placements.append(placement)
	return placements


## One pallet fit attempt. Unlike crates there is no breathing-margin test:
## pallets are MEANT to stand shoulder to shoulder, and the row/line spacing
## already guarantees the gap. The footprint must be free floor and the stamp
## must not strand any earlier placement's reach probe.
func _try_stamp_pallet(scene: PackedScene, footprint: Vector2, point: Vector2, yaw: float, probe: Vector2, already_placed: Array[Dictionary]) -> Dictionary:
	var pallet_transform := Transform3D(Basis(Vector3.UP, yaw), Vector3(point.x, 0.0, point.y))
	if not _region_is(pallet_transform, footprint, 0.0, [STATE_FREE]):
		return {}
	_stamp_oriented_box(pallet_transform, footprint, 0.0, STATE_OCCUPIED, [STATE_FREE])
	var placement := {
		"kind": "pallet",
		"scene": scene,
		"transform": pallet_transform,
		"reach_probe": Vector3(probe.x, 0.0, probe.y),
	}
	var check: Array[Dictionary] = already_placed.duplicate()
	check.append(placement)
	if not _walkability_holds(check):
		_stamp_oriented_box(pallet_transform, footprint, 0.0, STATE_FREE, [STATE_OCCUPIED])
		return {}
	return placement


## Optional crop lock: cycle the authored item ids across the placed pallets,
## each admitting exactly one of them. With no ids authored the pallets stay
## open and specialize on whatever the town hauls in first.
func _assign_pallet_items(placements: Array[Dictionary], rules: FurnishRules) -> void:
	if rules.pallet_item_ids.is_empty():
		return
	for index in range(placements.size()):
		var item_id := str(rules.pallet_item_ids[index % rules.pallet_item_ids.size()])
		var overrides := {}
		for candidate in rules.pallet_item_ids:
			overrides[str(candidate)] = str(candidate) == item_id
		placements[index]["item_id"] = item_id
		placements[index]["storage_item_overrides"] = overrides


## World-space bounding rect of the main interior region — the room the
## pallet layout gets measured against.
func _main_region_rect() -> Rect2:
	if _main_region < 0:
		return Rect2()
	var min_cell := Vector2i(_grid_width, _grid_height)
	var max_cell := Vector2i(-1, -1)
	for y in range(_grid_height):
		for x in range(_grid_width):
			if _region_labels[y * _grid_width + x] != _main_region:
				continue
			min_cell.x = mini(min_cell.x, x)
			min_cell.y = mini(min_cell.y, y)
			max_cell.x = maxi(max_cell.x, x)
			max_cell.y = maxi(max_cell.y, y)
	if max_cell.x < 0:
		return Rect2()
	var from := _cell_center(min_cell) - Vector2.ONE * CELL * 0.5
	var to := _cell_center(max_cell) + Vector2.ONE * CELL * 0.5
	return Rect2(from, to - from)


func _place_containers(anchors: Array[Dictionary], rules: FurnishRules, rng: RandomNumberGenerator, existing: Array[Dictionary]) -> Array[Dictionary]:
	var placements: Array[Dictionary] = []
	if rules.container_scenes.is_empty():
		return placements
	var footprints := {}
	for scene in rules.container_scenes:
		footprints[scene] = _container_footprint(scene)
	var candidates := anchors.filter(func(anchor): return anchor["category"] == "wall")
	for index in range(candidates.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var held = candidates[index]
		candidates[index] = candidates[swap]
		candidates[swap] = held
	for anchor in candidates:
		if placements.size() >= rules.max_containers:
			break
		if rng.randf() > rules.container_chance:
			continue
		var scene: PackedScene = rules.container_scenes[rng.randi_range(0, rules.container_scenes.size() - 1)]
		var footprint: Vector2 = footprints[scene]
		var normal: Vector2 = anchor["normal"]
		var along: Vector2 = anchor["along"]
		var slide := rng.randf_range(-0.6, 0.6)
		var center: Vector2 = anchor["position"] + normal * (WALL_THICKNESS * 0.5 + footprint.y * 0.5 + 0.05) + along * slide
		var yaw := atan2(normal.x, normal.y) + deg_to_rad(rng.randf_range(-8.0, 8.0))
		var container_transform := Transform3D(Basis(Vector3.UP, yaw), Vector3(center.x, 0.0, center.y))
		if not _region_is(container_transform, footprint, 0.0, [STATE_FREE]):
			continue
		# Like beds: the margin ring may overlap the wall band behind it, but
		# other furniture must not crowd the reach side.
		if _region_touches(container_transform, footprint, CLUSTER_MARGIN, STATE_OCCUPIED):
			continue
		_stamp_oriented_box(container_transform, footprint, 0.0, STATE_OCCUPIED, [STATE_FREE])
		var probe: Vector2 = center + normal * (footprint.y * 0.5 + CLUSTER_MARGIN + CELL)
		var placement := {
			"kind": "container",
			"scene": scene,
			"transform": container_transform,
			"reach_probe": Vector3(probe.x, 0.0, probe.y),
			"container_type": rules.container_type,
		}
		if _include_starting_stock and rules.container_stock != null:
			placement["stock"] = rules.container_stock.roll(rng)
		var check: Array[Dictionary] = existing + placements
		check.append(placement)
		if not _walkability_holds(check):
			_stamp_oriented_box(container_transform, footprint, 0.0, STATE_FREE, [STATE_OCCUPIED])
			continue
		placements.append(placement)
	return placements


## A container wrapper's floor footprint comes from its exported collision
## shape — no per-scene footprint authoring, the physics box IS the truth.
func _container_footprint(scene: PackedScene) -> Vector2:
	var instance := scene.instantiate()
	var shape: Shape3D = instance.get("collision_shape")
	instance.free()
	if shape is BoxShape3D:
		return Vector2((shape as BoxShape3D).size.x, (shape as BoxShape3D).size.z)
	if shape is CylinderShape3D:
		var diameter := (shape as CylinderShape3D).radius * 2.0
		return Vector2(diameter, diameter)
	return Vector2(1.2, 1.2)


## Shelves mount on solid wall segments only (never doors or windows — that
## exclusion is structural, not a heuristic) at head height, so they never
## touch the floor grid or the navmesh.
func _place_shelves(anchors: Array[Dictionary], rules: FurnishRules, rng: RandomNumberGenerator, counter: Dictionary, claimed_wall_faces: Dictionary) -> Array[Dictionary]:
	var placements: Array[Dictionary] = []
	if rules.shelf_scenes.is_empty():
		return placements
	var counter_anchor_position := Vector2.INF
	if not counter.is_empty():
		counter_anchor_position = Vector2(counter["transform"].origin.x, counter["transform"].origin.z)
	for anchor in anchors:
		if placements.size() >= rules.max_shelves:
			break
		if anchor["category"] != "wall":
			continue
		var wall_face_key := str(anchor["wall_face_key"])
		if claimed_wall_faces.has(wall_face_key):
			continue
		var anchor_position: Vector2 = anchor["position"]
		# Leave the counter's own wall bay clean.
		if counter_anchor_position != Vector2.INF and anchor_position.distance_to(counter_anchor_position) < 2.5:
			continue
		if rng.randf() > rules.shelf_chance:
			continue
		var normal: Vector2 = anchor["normal"]
		var along: Vector2 = anchor["along"]
		var slide := rng.randf_range(-0.15, 0.15)
		var origin := anchor_position + normal * (WALL_THICKNESS * 0.5 + 0.03) + along * slide
		var yaw := atan2(normal.x, normal.y)
		claimed_wall_faces[wall_face_key] = true
		placements.append({
			"kind": "shelf",
			"scene": rules.shelf_scenes[rng.randi_range(0, rules.shelf_scenes.size() - 1)],
			"transform": Transform3D(Basis(Vector3.UP, yaw), Vector3(origin.x, rules.shelf_mount_height, origin.y)),
			"wall_face_key": wall_face_key,
		})
	return placements


## One guaranteed light marks the exterior of the primary ground-floor door.
## Prefer the exterior face of an adjacent solid wall. Compact shells whose
## door neighbors are windows fall back to the door piece beside its opening.
func _place_exterior_entry_light(walls: Array[Dictionary], anchors: Array[Dictionary], rules: FurnishRules, rng: RandomNumberGenerator, claimed_wall_faces: Dictionary) -> Dictionary:
	if rules.light_scenes.is_empty():
		return {}
	var door_anchors := anchors.filter(func(anchor): return anchor["category"] == "wall_door")
	door_anchors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
	for interior_anchor in door_anchors:
		var door_wall: Dictionary = {}
		for wall in walls:
			if wall["node"].get_instance_id() == int(interior_anchor["wall_node_id"]):
				door_wall = wall
				break
		if door_wall.is_empty():
			continue
		var exterior_normal: Vector2 = -(interior_anchor["normal"] as Vector2)
		var exterior_anchor := _adjacent_exterior_wall_anchor(door_wall, walls, exterior_normal)
		if exterior_anchor.is_empty():
			var exterior_side := -float(interior_anchor["side"])
			exterior_anchor = {
				"wall_face_key": _wall_face_key(door_wall, exterior_side),
				"position": _wall_mount_position(door_wall, Vector2((door_wall["transform"] as Transform3D).origin.x, (door_wall["transform"] as Transform3D).origin.z)),
				"normal": exterior_normal,
			}
		var wall_face_key := str(exterior_anchor["wall_face_key"])
		if claimed_wall_faces.has(wall_face_key):
			continue
		var anchor_position: Vector2 = exterior_anchor["position"]
		var normal: Vector2 = exterior_anchor["normal"]
		var origin := anchor_position + normal * (WALL_THICKNESS * 0.5 + 0.03)
		var yaw := atan2(normal.x, normal.y)
		claimed_wall_faces[wall_face_key] = true
		return {
			"kind": "light",
			"scene": rules.light_scenes[rng.randi_range(0, rules.light_scenes.size() - 1)],
			"transform": Transform3D(Basis(Vector3.UP, yaw), Vector3(origin.x, rules.light_mount_height, origin.y)),
			"wall_face_key": wall_face_key,
			"exterior_entry_light": true,
		}
	return {}


func _adjacent_exterior_wall_anchor(door_wall: Dictionary, walls: Array[Dictionary], exterior_normal: Vector2) -> Dictionary:
	var door_transform: Transform3D = door_wall["transform"]
	var door_center := Vector2(door_transform.origin.x, door_transform.origin.z)
	var door_along := Vector2(door_transform.basis.x.x, door_transform.basis.x.z).normalized()
	var door_half_width := float((door_wall["bounds"] as Vector3).x) * 0.5
	var best: Dictionary = {}
	var best_distance := INF
	for wall in walls:
		if wall["category"] != "wall":
			continue
		var wall_transform: Transform3D = wall["transform"]
		var wall_along := Vector2(wall_transform.basis.x.x, wall_transform.basis.x.z).normalized()
		if absf(door_along.dot(wall_along)) < 0.95:
			continue
		var wall_center := Vector2(wall_transform.origin.x, wall_transform.origin.z)
		var offset := wall_center - door_center
		var along_distance := absf(offset.dot(door_along))
		var normal_distance := absf(offset.dot(exterior_normal))
		var wall_half_width := float((wall["bounds"] as Vector3).x) * 0.5
		if along_distance < 0.1 or along_distance > door_half_width + wall_half_width + 0.35 or normal_distance > 0.35:
			continue
		if along_distance >= best_distance:
			continue
		var wall_normal3 := wall_transform.basis.z.normalized()
		var wall_normal := Vector2(wall_normal3.x, wall_normal3.z)
		var side := 1.0 if wall_normal.dot(exterior_normal) >= 0.0 else -1.0
		best = {
			"wall_face_key": _wall_face_key(wall, side),
			"position": wall_center,
			"normal": exterior_normal,
		}
		best_distance = along_distance
	return best


## Interior wall lights share the same one-item-per-face claims as shelves.
## Door pieces are valid light anchors, but their mount point is shifted beside
## the opening; window pieces remain excluded.
func _place_lights(anchors: Array[Dictionary], rules: FurnishRules, rng: RandomNumberGenerator, claimed_wall_faces: Dictionary) -> Array[Dictionary]:
	var placements: Array[Dictionary] = []
	if rules.light_scenes.is_empty():
		return placements
	var candidates := anchors.filter(func(anchor): return anchor["category"] == "wall" or anchor["category"] == "wall_door")
	for index in range(candidates.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var held = candidates[index]
		candidates[index] = candidates[swap]
		candidates[swap] = held
	var lit_positions: Array[Vector2] = []
	for anchor in candidates:
		if placements.size() >= rules.max_lights_per_level:
			break
		if rng.randf() > rules.light_chance:
			continue
		var wall_face_key := str(anchor["wall_face_key"])
		if claimed_wall_faces.has(wall_face_key):
			continue
		var anchor_position: Vector2 = anchor["mount_position"]
		var too_close := false
		for lit in lit_positions:
			if lit.distance_to(anchor_position) < rules.light_spacing_meters:
				too_close = true
				break
		if too_close:
			continue
		var normal: Vector2 = anchor["normal"]
		var origin := anchor_position + normal * (WALL_THICKNESS * 0.5 + 0.03)
		var yaw := atan2(normal.x, normal.y)
		lit_positions.append(anchor_position)
		claimed_wall_faces[wall_face_key] = true
		placements.append({
			"kind": "light",
			"scene": rules.light_scenes[rng.randi_range(0, rules.light_scenes.size() - 1)],
			"transform": Transform3D(Basis(Vector3.UP, yaw), Vector3(origin.x, rules.light_mount_height, origin.y)),
			"wall_face_key": wall_face_key,
		})
	return placements


## --- Walkability guarantee -----------------------------------------------------


## Flood-fill from the door cells over walkable states; every placement's
## reach probe must be reachable or the layout is rejected.
func _walkability_holds(placements: Array[Dictionary]) -> bool:
	var reached := _flood_from_doors()
	for placement in placements:
		if not placement.has("reach_probe"):
			continue
		var probe: Vector3 = placement["reach_probe"]
		var cell := _cell_at(Vector2(probe.x, probe.z))
		if not _in_grid(cell) or not reached[cell.y * _grid_width + cell.x]:
			return false
	return true


## Connected components over walkable cells, treating door corridors as
## separators: each room gets a label, and the largest is the main hall.
func _label_regions() -> void:
	_region_labels = PackedInt32Array()
	_region_labels.resize(_grid_width * _grid_height)
	_region_labels.fill(-1)
	var sizes := {}
	var next_label := 0
	for start_y in range(_grid_height):
		for start_x in range(_grid_width):
			var start := Vector2i(start_x, start_y)
			if _state(start) != STATE_FREE or _region_labels[start_y * _grid_width + start_x] != -1:
				continue
			var queue: Array[Vector2i] = [start]
			_region_labels[start_y * _grid_width + start_x] = next_label
			var size := 0
			var head := 0
			while head < queue.size():
				var cell := queue[head]
				head += 1
				size += 1
				for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var next: Vector2i = cell + offset
					if not _in_grid(next):
						continue
					var index: int = next.y * _grid_width + next.x
					if _region_labels[index] == -1 and _state(next) == STATE_FREE:
						_region_labels[index] = next_label
						queue.append(next)
			sizes[next_label] = size
			next_label += 1
	# Porches and stoops are real floor pieces OUTSIDE the walls; their
	# regions reach the grid border (interior rooms are ringed by wall
	# stamps and never touch it). Nothing may be furnished out there.
	_exterior_regions = {}
	for x in range(_grid_width):
		_mark_exterior(Vector2i(x, 0))
		_mark_exterior(Vector2i(x, _grid_height - 1))
	for y in range(_grid_height):
		_mark_exterior(Vector2i(0, y))
		_mark_exterior(Vector2i(_grid_width - 1, y))
	_main_region = -1
	var best_size := 0
	for label_value in sizes:
		if _exterior_regions.has(int(label_value)):
			continue
		if int(sizes[label_value]) > best_size:
			best_size = int(sizes[label_value])
			_main_region = int(label_value)


func _mark_exterior(cell: Vector2i) -> void:
	var label := _region_labels[cell.y * _grid_width + cell.x]
	if label != -1:
		_exterior_regions[label] = true


func _is_interior_region(label: int) -> bool:
	return label != -1 and not _exterior_regions.has(label)


func _region_of(point: Vector2) -> int:
	var cell := _cell_at(point)
	if not _in_grid(cell):
		return -1
	return _region_labels[cell.y * _grid_width + cell.x]


func _flood_from_doors() -> PackedByteArray:
	var reached := PackedByteArray()
	reached.resize(_grid_width * _grid_height)
	var queue: Array[Vector2i] = []
	for cell in _door_cells:
		if not reached[cell.y * _grid_width + cell.x]:
			reached[cell.y * _grid_width + cell.x] = 1
			queue.append(cell)
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + offset
			if not _in_grid(next):
				continue
			var index: int = next.y * _grid_width + next.x
			if reached[index] != 0:
				continue
			var state := _state(next)
			if state == STATE_FREE or state == STATE_WALK_ONLY:
				reached[index] = 1
				queue.append(next)
	return reached


## --- Grid helpers --------------------------------------------------------------


func _piece_rect(piece: Dictionary) -> Rect2:
	var piece_transform: Transform3D = piece["transform"]
	var bounds: Vector3 = piece["bounds"]
	# Floor pieces may be rotated; take the world-aligned extent of the box.
	var half_x := absf(piece_transform.basis.x.x) * bounds.x * 0.5 + absf(piece_transform.basis.z.x) * bounds.z * 0.5
	var half_z := absf(piece_transform.basis.x.z) * bounds.x * 0.5 + absf(piece_transform.basis.z.z) * bounds.z * 0.5
	var center := Vector2(piece_transform.origin.x, piece_transform.origin.z)
	return Rect2(center - Vector2(half_x, half_z), Vector2(half_x, half_z) * 2.0)


func _stamp_rect(rect: Rect2, state: int, only_from: Array) -> void:
	var from_cell := _cell_at(rect.position + Vector2.ONE * (CELL * 0.5))
	var to_cell := _cell_at(rect.end - Vector2.ONE * (CELL * 0.5))
	for y in range(maxi(from_cell.y, 0), mini(to_cell.y, _grid_height - 1) + 1):
		for x in range(maxi(from_cell.x, 0), mini(to_cell.x, _grid_width - 1) + 1):
			var cell := Vector2i(x, y)
			if only_from.is_empty() or _state(cell) in only_from:
				_set_state(cell, state)


func _stamp_oriented_box(box_transform: Transform3D, size: Vector2, margin: float, state: int, only_from: Array) -> void:
	for cell in _box_cells(box_transform, size, margin):
		if only_from.is_empty() or _state(cell) in only_from:
			_set_state(cell, state)


## True when every grid cell under the oriented box (plus margin) is in an
## allowed state. Cells hanging off the grid count as blocked — a footprint
## may never extend past the floor plan.
func _region_is(box_transform: Transform3D, size: Vector2, margin: float, allowed: Array) -> bool:
	var expected := _expected_box_cell_count(size, margin)
	var cells := _box_cells(box_transform, size, margin)
	if cells.size() < expected:
		return false
	for cell in cells:
		if not (_state(cell) in allowed):
			return false
	return true


## True when any cell under the oriented box (plus margin) holds the given
## state — for "nothing of kind X may crowd this" checks.
func _region_touches(box_transform: Transform3D, size: Vector2, margin: float, state: int) -> bool:
	for cell in _box_cells(box_transform, size, margin):
		if _state(cell) == state:
			return true
	return false


## Conservative lower bound on how many in-grid cells a fully-on-grid box
## covers; fewer means part of the box fell off the grid.
func _expected_box_cell_count(size: Vector2, margin: float) -> int:
	var half := size * 0.5 + Vector2.ONE * margin
	return int(floor(half.x * 2.0 / CELL - 1.0)) * int(floor(half.y * 2.0 / CELL - 1.0))


func _box_cells(box_transform: Transform3D, size: Vector2, margin: float) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var half := size * 0.5 + Vector2.ONE * margin
	var center := Vector2(box_transform.origin.x, box_transform.origin.z)
	var axis_x := Vector2(box_transform.basis.x.x, box_transform.basis.x.z).normalized()
	var axis_z := Vector2(box_transform.basis.z.x, box_transform.basis.z.z).normalized()
	var reach := half.x + half.y
	var from_cell := _cell_at(center - Vector2.ONE * reach)
	var to_cell := _cell_at(center + Vector2.ONE * reach)
	for y in range(maxi(from_cell.y, 0), mini(to_cell.y, _grid_height - 1) + 1):
		for x in range(maxi(from_cell.x, 0), mini(to_cell.x, _grid_width - 1) + 1):
			var cell := Vector2i(x, y)
			var offset := _cell_center(cell) - center
			if absf(offset.dot(axis_x)) <= half.x and absf(offset.dot(axis_z)) <= half.y:
				cells.append(cell)
	return cells


func _door_distance(point: Vector2) -> float:
	var best := INF
	for cell in _door_cells:
		best = minf(best, _cell_center(cell).distance_to(point))
	return best


func _count_state(state: int) -> int:
	var count := 0
	for value in _grid:
		if value == state:
			count += 1
	return count


func _vignette_footprint(scene: PackedScene) -> Vector2:
	var instance := scene.instantiate()
	var footprint: Vector2 = instance.get("footprint_meters") if instance.get("footprint_meters") != null else Vector2(4.0, 3.0)
	instance.free()
	return footprint


func _cell_at(point: Vector2) -> Vector2i:
	return Vector2i(int(floor((point.x - _grid_origin.x) / CELL)), int(floor((point.y - _grid_origin.y) / CELL)))


func _cell_center(cell: Vector2i) -> Vector2:
	return _grid_origin + Vector2(cell.x + 0.5, cell.y + 0.5) * CELL


func _in_grid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _grid_width and cell.y < _grid_height


func _state(cell: Vector2i) -> int:
	return _grid[cell.y * _grid_width + cell.x]


func _set_state(cell: Vector2i, state: int) -> void:
	_grid[cell.y * _grid_width + cell.x] = state
