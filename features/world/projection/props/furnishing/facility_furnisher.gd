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
var _region_labels := PackedInt32Array()
var _main_region := -1
var _exterior_regions := {}
var _last_error := ""


func last_error() -> String:
	return _last_error


## Returns an array of placements:
##   {"scene": PackedScene, "transform": Transform3D (building-local), "kind": String}
## Every storey is furnished: the ground floor gets counter + table clusters +
## shelves, upper floors get beds + shelves.
## Empty array + last_error() on failure.
func furnish(building: Node3D, rules: FurnishRules, seed_value: int) -> Array[Dictionary]:
	_last_error = ""
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
	return placements


## One storey: build the walkability grid from THIS level's floors and walls
## (walls have their origin at their base, so a wall belongs to the level
## whose floor plane it stands on — foundation and other storeys' walls never
## leak in), place the level's archetypes, and lift everything to floor
## height at the end.
func _furnish_level(pieces: Array[Dictionary], rules: FurnishRules, rng: RandomNumberGenerator, level_index: int, floor_y: float) -> Array[Dictionary]:
	var floors: Array[Dictionary] = []
	var walls: Array[Dictionary] = []
	var stair_pieces: Array[Dictionary] = []
	for piece in pieces:
		var category: String = piece["category"]
		var piece_y: float = (piece["transform"] as Transform3D).origin.y
		if category == "floor" and absf(piece_y - floor_y) < 0.5:
			floors.append(piece)
		elif (category == "wall" or category == "wall_door" or category == "wall_window") and absf(piece_y - floor_y) < 0.5:
			walls.append(piece)
		elif category == "stairs" and piece_y > floor_y - 3.6 and piece_y < floor_y + 0.5:
			# A stair run blocks the level it starts on AND feeds the level it
			# arrives at (its footprint marks the upper stairwell mouth).
			stair_pieces.append(piece)
	if floors.is_empty():
		if level_index == 0:
			_last_error = "Shell has no ground-floor floor pieces."
		return []
	_build_grid(floors, walls)
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
	var placements: Array[Dictionary] = []
	if level_index == 0:
		var counter := _place_counter(anchors, rules, rng)
		if not counter.is_empty():
			placements.append(counter)
		placements.append_array(_place_clusters(rules, rng, placements))
		placements.append_array(_place_shelves(anchors, rules, rng, counter))
	else:
		placements.append_array(_place_beds(anchors, rules, rng))
		placements.append_array(_place_shelves(anchors, rules, rng, {}))
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


func _build_grid(floors: Array[Dictionary], walls: Array[Dictionary]) -> void:
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
	_door_cells.clear()
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
			if not _in_grid(cell) or _state(cell) == STATE_BLOCKED:
				continue
			# Interior faces only — a porch under an exterior wall face is
			# walkable floor, but nothing mounts or stands out there.
			if not _is_interior_region(_region_of(probe)):
				continue
			anchors.append({
				"name": str(wall["node"].name) + ("+" if side > 0.0 else "-"),
				"category": wall["category"],
				"position": center,
				"normal": normal,
				"along": Vector2(wall_transform.basis.x.x, wall_transform.basis.x.z).normalized(),
			})
	return anchors


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
	if rules.cluster_scenes.is_empty():
		return placements
	var footprints := {}
	for scene in rules.cluster_scenes:
		footprints[scene] = _vignette_footprint(scene)
	var free_area := _count_state(STATE_FREE) * CELL * CELL
	var target := clampi(int(free_area / maxf(rules.square_meters_per_cluster, 1.0)), 1, rules.max_clusters)
	var placed := 0
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
	for cell in candidates:
		if placed >= target:
			break
		if _state(cell) != STATE_FREE:
			continue
		var scene: PackedScene = rules.cluster_scenes[rng.randi_range(0, rules.cluster_scenes.size() - 1)]
		var footprint: Vector2 = footprints[scene]
		var yaw := (PI * 0.5) * rng.randi_range(0, 3) + deg_to_rad(rng.randf_range(-5.0, 5.0))
		var origin := _cell_center(cell)
		var cluster_transform := Transform3D(Basis(Vector3.UP, yaw), Vector3(origin.x, 0.0, origin.y))
		# The furniture itself needs free floor; the breathing margin around
		# it may border walk corridors — people walking past a table is fine,
		# a table standing IN the corridor is not.
		if not _region_is(cluster_transform, footprint, 0.0, [STATE_FREE]):
			continue
		if not _region_is(cluster_transform, footprint, CLUSTER_MARGIN, [STATE_FREE, STATE_WALK_ONLY]):
			continue
		_stamp_oriented_box(cluster_transform, footprint, 0.0, STATE_OCCUPIED, [STATE_FREE])
		var probe := origin + Vector2(cos(yaw), -sin(yaw)) * (footprint.x * 0.5 + CLUSTER_MARGIN + CELL)
		var placement := {
			"kind": "cluster",
			"scene": scene,
			"transform": cluster_transform,
			"reach_probe": Vector3(probe.x, 0.0, probe.y),
		}
		# Every probe placed so far must survive this stamp — a new cluster
		# may not wall off the counter or an earlier cluster.
		var all_placed: Array[Dictionary] = existing + placements
		all_placed.append(placement)
		if not _walkability_holds(all_placed):
			_stamp_oriented_box(cluster_transform, footprint, 0.0, STATE_FREE, [STATE_OCCUPIED])
			continue
		placements.append(placement)
		placed += 1
	return placements


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


## Shelves mount on solid wall segments only (never doors or windows — that
## exclusion is structural, not a heuristic) at head height, so they never
## touch the floor grid or the navmesh.
func _place_shelves(anchors: Array[Dictionary], rules: FurnishRules, rng: RandomNumberGenerator, counter: Dictionary) -> Array[Dictionary]:
	var placements: Array[Dictionary] = []
	if rules.shelf_scenes.is_empty():
		return placements
	var counter_anchor_position := Vector2.INF
	if not counter.is_empty():
		counter_anchor_position = Vector2(counter["transform"].origin.x, counter["transform"].origin.z)
	for anchor in anchors:
		if anchor["category"] != "wall":
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
		placements.append({
			"kind": "shelf",
			"scene": rules.shelf_scenes[rng.randi_range(0, rules.shelf_scenes.size() - 1)],
			"transform": Transform3D(Basis(Vector3.UP, yaw), Vector3(origin.x, rules.shelf_mount_height, origin.y)),
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
