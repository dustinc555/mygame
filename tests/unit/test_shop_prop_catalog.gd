extends GutTest

const FURNITURE := "res://features/world/projection/props/furniture/"
const STORAGE := {
	"cabinet": Vector2i(8, 5),
	"dresser_1": Vector2i(7, 5),
	"workbench_drawers": Vector2i(4, 3),
	"nightstand_drawer": Vector2i(4, 3),
	"nightstand_shelf": Vector2i(4, 4),
	"bookcase_1": Vector2i(8, 6),
	"bookcase_2": Vector2i(8, 6),
	"shelf_small": Vector2i(6, 3),
	"shelf_arch": Vector2i(6, 5),
	"crate_metal": Vector2i(6, 5),
	"farm_crate_empty": Vector2i(5, 3),
}

class CatalogTools extends "res://addons/world_authoring/facility_tools.gd":
	func _init(_editor: EditorPlugin = null) -> void: pass

func test_storage_props_are_catalogued_real_containers_with_configurable_admission() -> void:
	var catalog := CatalogTools.new().get_furniture_catalog()
	var paths: Array = catalog.map(func(row): return row.path)
	for id in STORAGE:
		var path := FURNITURE + str(id) + ".tscn"
		assert_true(ResourceLoader.exists(path), path)
		if not ResourceLoader.exists(path):
			continue
		assert_has(paths, path)
		var container = load(path).instantiate()
		assert_true(container is WorldContainer, id)
		assert_eq(Vector2i(container.inventory_columns, container.inventory_rows), STORAGE[id])
		assert_not_null(container.visual_scene)
		assert_true(container.collision_shape is BoxShape3D)
		var item := ItemDefinition.new()
		item.item_id = "food.test"
		assert_true(container.can_accept_item_count(item, 1))
		container.container_type = "weapons"
		assert_false(container.can_accept_item_count(item, 1))
		container.free()

func test_storage_visuals_and_colliders_share_a_grounded_origin() -> void:
	for id in STORAGE:
		var container = load(FURNITURE + str(id) + ".tscn").instantiate()
		var visuals := Node3D.new()
		preload("res://addons/world_authoring/scene_thumbnail.gd")._copy_meshes(container, Transform3D.IDENTITY, visuals)
		var bounds := AABB()
		var first := true
		for child in visuals.get_children():
			var mesh := child as MeshInstance3D
			if mesh == null or mesh.mesh == null:
				continue
			var mesh_bounds: AABB = mesh.transform * mesh.get_aabb()
			bounds = mesh_bounds if first else bounds.merge(mesh_bounds)
			first = false
		assert_false(first, id + " has rendered geometry")
		assert_almost_eq(bounds.position.y, 0.0, 0.002, id + " sits on the floor")
		assert_almost_eq(bounds.size, container.collision_shape.size, Vector3.ONE * 0.002, id + " collision matches model")
		assert_almost_eq(container.collision_transform.origin.y, bounds.size.y * 0.5, 0.002, id)
		visuals.free()
		container.free()

func test_decor_and_item_displays_are_in_the_normal_furniture_catalog() -> void:
	var catalog := CatalogTools.new().get_furniture_catalog()
	var paths: Array = catalog.map(func(row): return row.path)
	for id in ["desk", "peg_rack", "rope_1", "rope_2", "rope_3"]:
		assert_has(paths, FURNITURE + id + ".tscn")

func test_open_shelves_and_crates_cannot_lock() -> void:
	for id in ["bookcase_1", "bookcase_2", "shelf_small", "shelf_arch", "nightstand_shelf", "farm_crate_empty"]:
		var path := FURNITURE + str(id) + ".tscn"
		assert_true(ResourceLoader.exists(path), path)
		if ResourceLoader.exists(path):
			var container = load(path).instantiate()
			assert_false(container.supports_locking, id)
			container.free()

func test_rope_variants_author_real_items_and_have_preview_geometry() -> void:
	for number in range(1, 4):
		var path := FURNITURE + "rope_%d.tscn" % number
		assert_true(ResourceLoader.exists(path), path)
		if not ResourceLoader.exists(path):
			continue
		var rope = load(path).instantiate()
		assert_true(rope is TabletopItemSpawner)
		var slot := rope.get_node("Rope") as TabletopItemSlot
		assert_not_null(slot.required_item)
		assert_eq(slot.required_item.item_id, "material.rope_%d" % number)
		var inventory := InventoryData.new(6, 6, 0.0, false)
		assert_true(inventory.add_item_count(slot.required_item, 1))
		var visuals := Node3D.new()
		preload("res://addons/world_authoring/scene_thumbnail.gd")._copy_meshes(rope, Transform3D.IDENTITY, visuals)
		assert_gt(visuals.get_child_count(), 0)
		visuals.free()
		rope.free()

func test_chair_seated_facing_respects_placement_and_parent_rotation() -> void:
	# Core seating behavior, independent of any town's authored furniture.
	var parent := Node3D.new()
	add_child_autofree(parent)
	var chair := load(FURNITURE + "chair_1.tscn").instantiate() as SittableSeat
	parent.add_child(chair)
	for placement in [
		{"parent_yaw": 0.0, "chair_yaw": 0.0, "facing": Vector3.BACK},
		{"parent_yaw": 0.0, "chair_yaw": 90.0, "facing": Vector3.RIGHT},
		{"parent_yaw": 90.0, "chair_yaw": 90.0, "facing": Vector3.FORWARD},
		{"parent_yaw": -90.0, "chair_yaw": 0.0, "facing": Vector3.LEFT},
	]:
		parent.rotation_degrees.y = placement.parent_yaw
		chair.rotation_degrees.y = placement.chair_yaw
		var facing := Basis.from_euler(chair.get_seat_rotation()) * Vector3.FORWARD
		assert_almost_eq(facing, placement.facing, Vector3.ONE * 0.001)
	chair.seated_yaw_offset_degrees = 0.0
	parent.rotation = Vector3.ZERO
	chair.rotation = Vector3.ZERO
	assert_almost_eq(Basis.from_euler(chair.get_seat_rotation()) * Vector3.FORWARD, Vector3.FORWARD, Vector3.ONE * 0.001, "Authored facing offset remains configurable")
