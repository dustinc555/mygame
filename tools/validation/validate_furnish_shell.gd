extends Node3D

## Headless furnish validator: instantiates a building shell, runs the
## FacilityFurnisher over several seeds, and reports what placed per seed —
## no zone or world load needed. Fails when a seed produces nothing or when
## the rules ask for a required kind (counter/cluster/utility) that never
## places on any seed,
## which is how an authoring gap like "the cell block cannot fit this shell"
## surfaces. --grid prints the ground-floor walkability grid so the failure
## is visible: # blocked, . interior free, , exterior free, o walk-only,
## D door seed.
##
## Run:
##   godot --headless --path . res://tools/validation/validate_furnish_shell.tscn \
##     -- --shell=res://features/world/projection/buildings/shells/modular/medium_brick_round_tower.tscn \
##        --rules=res://features/settlements/resources/furnishing/jail.tres --seeds=4 --grid

const FURNISHER := preload("res://features/world/projection/props/furnishing/facility_furnisher.gd")

var _shell_path := "res://features/world/projection/buildings/shells/modular/medium_brick_round_tower.tscn"
var _rules_path := "res://features/settlements/resources/furnishing/jail.tres"
var _seed_count := 4
var _dump_grid := false
var _probe_failed := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shell="):
			_shell_path = arg.get_slice("=", 1)
		elif arg.begins_with("--rules="):
			_rules_path = arg.get_slice("=", 1)
		elif arg.begins_with("--seeds="):
			_seed_count = maxi(1, int(arg.get_slice("=", 1)))
		elif arg == "--grid":
			_dump_grid = true
	var shell_scene := load(_shell_path) as PackedScene
	var rules := load(_rules_path) as FurnishRules
	if shell_scene == null or rules == null:
		push_error("validate_furnish_shell: failed to load shell '%s' or rules '%s'" % [_shell_path, _rules_path])
		get_tree().quit(1)
		return
	var shell := shell_scene.instantiate() as Node3D
	add_child(shell)
	await get_tree().process_frame
	var placed_kinds := {}
	var empty_seeds := 0
	for seed_value in range(1, _seed_count + 1):
		var furnisher = FURNISHER.new()
		var placements: Array[Dictionary] = furnisher.furnish(shell, rules, seed_value)
		var counts := {}
		for placement in placements:
			var kind := str(placement["kind"])
			counts[kind] = int(counts.get(kind, 0)) + 1
			placed_kinds[kind] = true
		var error := str(furnisher.last_error())
		print("seed %d: %d placements %s%s" % [seed_value, placements.size(), counts, "" if error.is_empty() else " ERROR: " + error])
		if placements.is_empty():
			empty_seeds += 1
	if _dump_grid:
		_print_ground_grid(shell, rules)
	_validate_impossible_required_utility(shell, rules)
	var missing: Array[String] = []
	if not rules.counter_scenes.is_empty() and not placed_kinds.has("counter"):
		missing.append("counter")
	if not rules.cluster_scenes.is_empty() and not placed_kinds.has("cluster"):
		missing.append("cluster")
	if not rules.utility_scenes.is_empty() and not placed_kinds.has("utility"):
		missing.append("utility")
	if empty_seeds > 0 or not missing.is_empty() or _probe_failed:
		print("FAIL validate_furnish_shell: %d empty seeds, kinds never placed: %s" % [empty_seeds, missing])
		get_tree().quit(1)
		return
	print("PASS validate_furnish_shell (%s + %s)" % [_shell_path.get_file(), _rules_path.get_file()])
	get_tree().quit()


func _validate_impossible_required_utility(shell: Node3D, rules: FurnishRules) -> void:
	if rules.utility_scenes.is_empty():
		return
	var utility := StaticBody3D.new()
	utility.set_script(load("res://features/world/projection/containers/world_container.gd"))
	var shape := BoxShape3D.new()
	shape.size = Vector3(100.0, 2.0, 100.0)
	utility.set("collision_shape", shape)
	var impossible_scene := PackedScene.new()
	if impossible_scene.pack(utility) != OK:
		utility.free()
		push_error("validate_furnish_shell: failed to pack impossible utility probe")
		_probe_failed = true
		return
	utility.free()
	var impossible_rules := rules.duplicate(true) as FurnishRules
	var utility_scenes: Array[PackedScene] = [impossible_scene]
	impossible_rules.utility_scenes = utility_scenes
	var furnisher = FURNISHER.new()
	var placements: Array[Dictionary] = furnisher.furnish(shell, impossible_rules, 1)
	if not placements.is_empty() or not str(furnisher.last_error()).begins_with("Required utility"):
		push_error("validate_furnish_shell: impossible required utility should fail furnishing loudly")
		_probe_failed = true


func _print_ground_grid(shell: Node3D, _rules: FurnishRules) -> void:
	var furnisher = FURNISHER.new()
	var pieces: Array[Dictionary] = furnisher._collect_pieces(shell)
	var level_ys: Array = furnisher._floor_level_ys(pieces)
	if level_ys.is_empty():
		print("grid: no floor levels")
		return
	var ground: float = level_ys[0]
	var floors: Array[Dictionary] = []
	var walls: Array[Dictionary] = []
	var blockers: Array[Dictionary] = []
	for piece in pieces:
		var category := str(piece["category"])
		var piece_y: float = (piece["transform"] as Transform3D).origin.y
		if category == "floor" and absf(piece_y - ground) < 0.5:
			floors.append(piece)
		elif (category == "wall" or category == "wall_door" or category == "wall_window") and absf(piece_y - ground) < 0.5:
			walls.append(piece)
		elif (category == "corner" or category == "overhang") and absf(piece_y - ground) < 0.5:
			blockers.append(piece)
	furnisher._build_grid(floors, walls, blockers)
	furnisher._label_regions()
	var door_cells := {}
	for cell in furnisher._door_cells:
		door_cells[cell] = true
	print("ground grid %dx%d (cell %.2fm):" % [furnisher._grid_width, furnisher._grid_height, furnisher.CELL])
	for y in range(furnisher._grid_height):
		var line := ""
		for x in range(furnisher._grid_width):
			var cell := Vector2i(x, y)
			if door_cells.has(cell):
				line += "D"
			elif furnisher._state(cell) == furnisher.STATE_BLOCKED:
				line += "#"
			elif furnisher._state(cell) == furnisher.STATE_WALK_ONLY:
				line += "o"
			elif furnisher._is_interior_region(furnisher._region_labels[y * furnisher._grid_width + x]):
				line += "."
			else:
				line += ","
		print(line)
