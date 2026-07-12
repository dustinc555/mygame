extends SceneTree

## Doors inside reusable shells author no door_id; the owning WorldBuilding
## mints one per placement at ready time. This proves every shipped shell ends
## up with uniquely identified doors — an ID-less door is silent decoration
## the door system never hears about (the originally shipped bug).
## Uses load() at runtime: --script mode cannot compile GECS preload chains.

const SHELL_PATHS := [
	"res://features/world/projection/buildings/shells/modular/woodbrick_shop_medium.tscn",
	"res://features/world/projection/buildings/shells/modular/woodbrick_house.tscn",
]
const EXPECTED_MINIMUM_DOORS := 3

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var seen_door_ids := {}
	var total_doors := 0
	for path in SHELL_PATHS:
		var scene := load(path) as PackedScene
		if scene == null:
			_fail("Missing shell scene: %s" % path)
			continue
		var shell := scene.instantiate() as Node3D
		get_root().add_child(shell)
		await process_frame
		await process_frame
		var shell_doors := 0
		for door in get_nodes_in_group("world_door"):
			if not shell.is_ancestor_of(door):
				continue
			shell_doors += 1
			var door_id := str(door.get("door_id"))
			if door_id.is_empty():
				_fail("%s: door %s has no minted door_id" % [path, shell.get_path_to(door)])
			elif seen_door_ids.has(door_id):
				_fail("%s: duplicate door_id '%s'" % [path, door_id])
			seen_door_ids[door_id] = true
			if str(door.get("building_id")).is_empty():
				_fail("%s: door %s has no building_id" % [path, shell.get_path_to(door)])
		if shell_doors == 0:
			_fail("%s: shell contains no doors" % path)
		total_doors += shell_doors
		shell.free()
		await process_frame
	if total_doors < EXPECTED_MINIMUM_DOORS:
		_fail("Expected at least %d doors across shells, found %d" % [EXPECTED_MINIMUM_DOORS, total_doors])
	if _failed:
		quit(1)
		return
	print("DOOR_IDENTITY_OK doors=%d" % total_doors)
	quit()


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
