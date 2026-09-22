extends GutTest

const SHELL := preload("res://features/world/projection/buildings/shells/modular/medium_wood_hall.tscn")
const FURNISHER := preload("res://features/world/projection/props/furnishing/facility_furnisher.gd")
const SHOP := preload("res://features/settlements/resources/furnishing/shop.tres")

func _shell() -> Node3D:
	var shell := SHELL.instantiate() as Node3D
	shell.set("building_id", "test.shop_furnishing")
	add_child_autofree(shell)
	return shell

func test_each_distinct_hall_entrance_gets_one_exterior_torch() -> void:
	var shell := _shell()
	var solver := FURNISHER.new()
	var placements := solver.furnish(shell, SHOP, 0)
	var exterior := placements.filter(func(p): return p.get("exterior_entry_light", false))
	# The real hall has two entrances, each authored with overlapping door
	# wall/trim pieces. Those are not four independent entrances.
	assert_eq(exterior.size(), 2)
	var front := exterior.filter(func(p): return p.transform.origin.z > 6.0)
	var back := exterior.filter(func(p): return p.transform.origin.z < -4.0)
	assert_eq(front.size(), 1, "Shopfront must not lose to the back door's alphabetical name")
	assert_eq(back.size(), 1)
	for light in exterior:
		assert_almost_eq(light.transform.origin.y, SHOP.light_mount_height, 0.01)

func test_shop_has_storage_shelves_and_private_bed_without_dining() -> void:
	var shell := _shell()
	for seed_value in [0, 1, 2, 5]:
		var solver := FURNISHER.new()
		var placements := solver.furnish(shell, SHOP, seed_value, true)
		assert_false(placements.is_empty(), solver.last_error())
		var containers := placements.filter(func(p): return p.kind == "container")
		var shelves := placements.filter(func(p): return p.kind == "shelf")
		var beds := placements.filter(func(p): return p.kind == "bed")
		assert_gt(containers.size(), 0, "seed %d: usable shop storage" % seed_value)
		assert_gt(shelves.size(), 0, "seed %d: wall shelving" % seed_value)
		assert_eq(beds.size(), 1)
		assert_true(beds.all(func(p): return p.transform.origin.y > 2.0))
		assert_false(placements.any(func(p): return p.kind == "cluster"))
		assert_false(containers.any(func(p): return p.has("stock")), "Furnishing must not create merchant goods")

func test_empty_light_pool_does_not_create_exterior_lights() -> void:
	var rules := SHOP.duplicate() as FurnishRules
	rules.light_scenes = []
	var placements := FURNISHER.new().furnish(_shell(), rules, 0)
	assert_false(placements.any(func(p): return p.kind == "light"))

func test_internal_door_is_not_an_exterior_light_candidate() -> void:
	var door := Node3D.new()
	add_child_autofree(door)
	var walls: Array[Dictionary] = [{"node": door, "category": "wall_door", "transform": Transform3D.IDENTITY, "bounds": Vector3(2, 3, 0.4)}]
	var anchors: Array[Dictionary] = [{"name": "InteriorDoor", "wall_node_id": door.get_instance_id(), "category": "wall_door", "side": 1.0, "position": Vector2.ZERO, "normal": Vector2.DOWN}]
	var solver := FURNISHER.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0
	assert_true(solver._place_exterior_entry_lights(walls, anchors, SHOP, rng, {}).is_empty())
	# With an exterior classification but no adjacent solid wall, mount beside
	# the door opening rather than silently omitting this entrance.
	solver._exterior_door_interior_sides[door.get_instance_id()] = 1.0
	var exterior := solver._place_exterior_entry_lights(walls, anchors, SHOP, rng, {})
	assert_eq(exterior.size(), 1)
	if exterior.is_empty():
		return
	assert_almost_eq(exterior[0].transform.origin.x, 0.7, 0.01)
	assert_lt(exterior[0].transform.origin.z, 0.0)

func test_shop_layout_repeats_without_accumulating_wall_claims() -> void:
	var shell := _shell()
	var solver := FURNISHER.new()
	var first := solver.furnish(shell, SHOP, 0)
	var repeated := solver.furnish(shell, SHOP, 0)
	assert_eq(first.size(), repeated.size())
	for index in mini(first.size(), repeated.size()):
		assert_eq(first[index].scene, repeated[index].scene)
		assert_eq(first[index].transform, repeated[index].transform)
