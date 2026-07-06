extends SceneTree

## Proves the construction system: placing a building through the
## ConstructionRecords creates a durable settlement record for the placing
## faction, the ConstructionRealizer instantiates the scene at the recorded
## transform, a second nearby building JOINS the settlement (border radius
## grows), a distant one FOUNDS a new settlement, and placements dirty
## navigation tiles for re-bake. Run:
## godot --headless --path . --script res://tools/validation/validate_construction_placement.gd

const SCENE_PATH := "res://scenes/zones/rustwash_basin/rustwash_basin.tscn"
const MAX_SETUP_FRAMES := 600

var _failures: Array[String] = []


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	var scene: Node = (load(SCENE_PATH) as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	var construction: Node = null
	for _i in range(MAX_SETUP_FRAMES):
		await physics_frame
		construction = get_first_node_in_group("construction_records")
		if construction != null:
			break
	if construction == null:
		_fail("no ConstructionRecords")
		return
	var navigation := get_first_node_in_group("world_navigation_controller")

	# 1. First placement founds a player settlement.
	var first_transform := Transform3D(Basis(Vector3.UP, 0.4), Vector3(20.0, 0.4, -150.0))
	var first: Dictionary = construction.call("place_building", "woodbrick_house", first_transform, "Player")
	if first.is_empty():
		_fail("first placement returned no record")
		return
	var settlements: Dictionary = construction.call("get_settlements")
	if settlements.size() != 1:
		_fail("expected 1 settlement, got %d" % settlements.size())
		return
	var settlement: Dictionary = settlements[first["settlement_id"]]
	if settlement["faction_id"] != "Player":
		_fail("settlement faction %s != Player" % settlement["faction_id"])
	var founding_radius: float = settlement["radius"]
	print("CONSTRUCTION_TEST_OK founded settlement=%s radius=%.1f" % [settlement["settlement_id"], founding_radius])

	# 2. Realizer instantiated the scene at the recorded XZ; ground snap
	# re-solves Y against the live terrain (records store intent, terrain
	# owns height), so only XZ must match and Y must stay near the ground.
	await physics_frame
	await physics_frame
	await physics_frame
	await physics_frame
	var instance := current_scene.get_node_or_null(str(first["building_id"])) as Node3D
	if instance == null:
		_fail("building instance not realized in scene")
		return
	var xz_delta := Vector2(instance.global_position.x - first_transform.origin.x, instance.global_position.z - first_transform.origin.z)
	if xz_delta.length() > 0.1:
		_fail("realized XZ %s != recorded XZ %s" % [instance.global_position, first_transform.origin])
	if absf(instance.global_position.y - first_transform.origin.y) > 2.0:
		_fail("ground-snapped Y %.2f strayed too far from recorded %.2f" % [instance.global_position.y, first_transform.origin.y])
	print("CONSTRUCTION_TEST_OK realized %s at %s (ground-snapped)" % [first["building_id"], instance.global_position])

	# 3. Nearby placement joins the same settlement and grows the border.
	# 70m away: inside the 90m join radius, far enough that the border
	# (centroid distance 35m + margin) must exceed the 40m minimum.
	var second: Dictionary = construction.call("place_building", "woodbrick_house",
		Transform3D(Basis.IDENTITY, Vector3(90.0, 0.4, -150.0)), "Player")
	if second["settlement_id"] != first["settlement_id"]:
		_fail("nearby building founded a new settlement instead of joining")
	settlement = construction.call("get_settlement", first["settlement_id"])
	if settlement["radius"] <= founding_radius:
		_fail("border radius did not grow after join (%.1f <= %.1f)" % [settlement["radius"], founding_radius])
	print("CONSTRUCTION_TEST_OK joined settlement radius=%.1f" % settlement["radius"])

	# 4. Distant placement founds a second settlement.
	var third: Dictionary = construction.call("place_building", "woodbrick_house",
		Transform3D(Basis.IDENTITY, Vector3(-300.0, 0.4, -150.0)), "Player")
	if third["settlement_id"] == first["settlement_id"]:
		_fail("distant building joined instead of founding")
	settlements = construction.call("get_settlements")
	if settlements.size() != 2:
		_fail("expected 2 settlements, got %d" % settlements.size())
	print("CONSTRUCTION_TEST_OK distant placement founded %s" % third["settlement_id"])

	# 5. Placements dirtied navigation tiles (dynamic nav patching engaged).
	await physics_frame
	await physics_frame
	if navigation != null and int(navigation.call("pending_tile_count")) == 0 and not bool(navigation.call("is_baking")):
		_fail("navigation saw no dirty tiles after placements")
	else:
		print("CONSTRUCTION_TEST_OK navigation patching engaged")

	# 5b. Zoning: a FOREIGN faction cannot build inside the player town's
	# border (conquest, not construction, is how you take ground), but can
	# build outside it.
	var blocked: Dictionary = construction.call("can_place", Vector3(30.0, 0.4, -150.0), "Raiders")
	if bool(blocked["allowed"]):
		_fail("foreign faction allowed to build inside player zone")
	var rejected: Dictionary = construction.call("place_building", "woodbrick_house",
		Transform3D(Basis.IDENTITY, Vector3(30.0, 0.4, -150.0)), "Raiders")
	if not rejected.is_empty():
		_fail("place_building accepted a zoned-out foreign placement")
	var allowed: Dictionary = construction.call("can_place", Vector3(600.0, 0.4, -150.0), "Raiders")
	if not bool(allowed["allowed"]):
		_fail("foreign faction blocked far outside every zone")
	print("CONSTRUCTION_TEST_OK zoning blocks foreign builds inside the border")

	# 6. Records serialize to plain data.
	var serialized: Dictionary = construction.call("serialize_state")
	if not serialized.has("constructed_settlements") or serialized["constructed_settlements"].size() != 2:
		_fail("serialize_state missing settlements")
	else:
		print("CONSTRUCTION_TEST_OK serialize_state has %d settlements" % serialized["constructed_settlements"].size())
	_finish()


func _fail(message: String) -> void:
	_failures.append(message)
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("CONSTRUCTION_VALIDATION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("CONSTRUCTION_VALIDATION_FAILED count=%d" % _failures.size())
	quit(1)
