extends "res://tests/validation/test_case.gd"

## Registry/ownership/realization and per-placement local navigation revisions
## on a controlled static world. place_building accepts an already solved
## transform: this deliberately does not claim preview/terrain-ray coverage.
var _world: Node3D
var _navigation: Node
var _construction: Node
var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_world = load("res://tests/validation/helpers/navigation_fixture.gd").new()
	root.add_child(_world)
	current_scene = _world
	_world.add_floor(Vector3(1024, 1, 64), Vector3(128, -0.5, -150))
	_expect(await _world.boot(), "controlled world navigation must settle before placement")
	_navigation = _world.navigation
	_construction = BootstrapContext.service(&"construction")
	if _construction == null:
		_construction = get_first_node_in_group("construction_controller")
	_expect(_construction != null and _navigation != null and _navigation.baked_tile_count() > 1, "real construction and tiled navigation services required")
	if _construction != null and _navigation != null:
		await _placements()
	_world.dispose()
	await process_frame
	print("CONSTRUCTION_VALIDATION_%s" % ("OK" if _failures.is_empty() else "FAILED"))
	quit(0 if _failures.is_empty() else 1)

func _placements() -> void:
	var first := await _place(Transform3D(Basis(Vector3.UP, 0.4), Vector3(20, 0.4, -150)))
	if first.is_empty():
		return
	var settlements: Dictionary = _construction.get_settlements()
	_expect(settlements.size() == 1, "first placement founds one settlement")
	var settlement: Dictionary = _construction.get_settlement(first.settlement_id)
	_expect(settlement.faction_id == "Player", "founding faction owns the settlement")
	var founding_radius: float = settlement.radius
	var second := await _place(Transform3D(Basis.IDENTITY, Vector3(90, 0.4, -150)))
	if second.is_empty():
		return
	_expect(second.settlement_id == first.settlement_id, "nearby building joins the same settlement")
	settlement = _construction.get_settlement(first.settlement_id)
	_expect(settlement.radius > founding_radius, "nearby placement grows settlement bounds")
	var third := await _place(Transform3D(Basis.IDENTITY, Vector3(-300, 0.4, -150)))
	if third.is_empty():
		return
	_expect(third.settlement_id != first.settlement_id and _construction.get_settlements().size() == 2, "distant placement founds another settlement")
	var before := _revisions()
	var denied: Dictionary = _construction.can_place(Vector3(30, 0.4, -150), "Raiders")
	_expect(not denied.allowed, "foreign faction denied inside territory")
	var rejected: Dictionary = _construction.place_building("medium_wood_l_hall", Transform3D(Basis.IDENTITY, Vector3(30, 0.4, -150)), "Raiders")
	_expect(rejected.is_empty(), "foreign placement refused without records")
	_expect(_revisions() == before and _navigation.is_idle(), "rejected placement causes no navigation work")
	_expect(_construction.can_place(Vector3(600, 0.4, -150), "Raiders").allowed, "foreign construction allowed outside territory")
	var registry = BootstrapContext.service(&"building_registry")
	_expect(registry != null and registry.get_buildings_for_settlement(first.settlement_id).size() == 2, "canonical registry indexes both joined buildings")
	_expect(not _construction.get_settlement(first.settlement_id).has("buildings"), "settlement does not duplicate building authority")

func _revisions() -> Dictionary:
	var result := {}
	for coord in _navigation._tiles:
		result[coord] = _navigation._tiles[coord].requested_revision
	return result

func _place(transform: Transform3D) -> Dictionary:
	_expect(_navigation.is_idle(), "placement starts from settled navigation")
	var before := _revisions()
	var record: Dictionary = _construction.place_building("medium_wood_l_hall", transform, "Player")
	_expect(not record.is_empty(), "placement returns a canonical record")
	if record.is_empty():
		return {}
	await physics_frame
	await physics_frame
	var instance := _world.get_node_or_null(str(record.building_id)) as Node3D
	_expect(instance != null, "constructed building realized under the world")
	if instance == null:
		return {}
	_expect(instance.global_transform.is_equal_approx(transform), "realizer preserves exact committed transform")
	var expected := {}
	var pipeline = load("res://features/core/navigation/world_nav_bake_pipeline.gd")
	for body in instance.find_children("*", "StaticBody3D", true, false):
		for coord in pipeline.affected_tile_coords(_navigation._static_body_world_bounds(body), _navigation.settings):
			expected[coord] = true
	var changed := 0
	for coord in before:
		if _navigation._tiles[coord].requested_revision > before[coord]:
			changed += 1
			_expect(expected.has(coord), "placement must not dirty unrelated tile %s" % coord)
	_expect(changed > 0 and changed < before.size(), "this placement changes a nonempty bounded subset of tile revisions")
	_expect(await _world.wait_ready(), "local placement bake completes")
	for coord in before:
		var tile = _navigation._tiles[coord]
		_expect(tile.installed_revision == tile.requested_revision, "current local revision must be installed")
	print("CONSTRUCTION_TILE_PROOF building=%s changed=%d total=%d" % [record.building_id, changed, before.size()])
	return record

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)
