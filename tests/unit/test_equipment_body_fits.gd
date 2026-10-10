extends GutTest

const VISUAL = preload("res://features/inventory/resources/items/equipment_visual_definition.gd")
const ITEM = preload("res://features/inventory/resources/items/item_definition.gd")
const BODY = preload("res://features/actors/resources/character_body_archetypes/character_body_archetype_definition.gd")

var source: PackedScene
var fitted: PackedScene
var visual: Resource

func before_each() -> void:
	source = _scene("Original")
	fitted = _scene("Fitted")
	assert_eq(ResourceSaver.save(fitted, "user://equipment_fit_test.tscn"), OK)
	visual = VISUAL.new()
	visual.body_archetype_id = "test.body"
	visual.visual_scene = source
	visual.surface_offset_ratio = 0.02
	visual.equipped_transform.origin = Vector3(1, 2, 3)
	var fits: Dictionary[String, String] = {"res://test/body.glb": "user://equipment_fit_test.tscn"}
	visual.set("body_fits", fits)

func after_each() -> void:
	DirAccess.remove_absolute("user://equipment_fit_test.tscn")

func test_exact_body_fit_replaces_mesh_without_legacy_inflation() -> void:
	var resolved: Resource = visual.for_body_scene("res://test/body.glb")
	assert_eq(resolved.visual_scene.resource_path, "user://equipment_fit_test.tscn")
	assert_eq(resolved.surface_offset_ratio, 0.0)
	assert_eq(resolved.equipped_transform, visual.equipped_transform)
	assert_same(visual.visual_scene, source, "selection must not mutate the shared source")
	assert_eq(visual.surface_offset_ratio, 0.02)

func test_unknown_body_keeps_the_authored_fallback() -> void:
	assert_same(visual.for_body_scene("res://test/other.glb"), visual)
	assert_same(visual.for_body_scene(""), visual)

func test_repeated_fits_share_the_native_scene_resource() -> void:
	var a: Resource = visual.for_body_scene("res://test/body.glb")
	var b: Resource = visual.for_body_scene("res://test/body.glb")
	assert_same(a.visual_scene, b.visual_scene)

func test_fit_stays_loaded_between_equipment_instances() -> void:
	var resolved: Resource = visual.for_body_scene("res://test/body.glb")
	var scene_ref: WeakRef = weakref(resolved.visual_scene)
	var instance: Node = resolved.visual_scene.instantiate()
	instance.free()
	resolved = null
	assert_not_null(scene_ref.get_ref(), "A shared-skeleton copy must not release and reload its fitted source every swap")
	var again: Resource = visual.for_body_scene("res://test/body.glb")
	assert_same(again.visual_scene, scene_ref.get_ref())
	again = null
	visual = null
	assert_null(scene_ref.get_ref(), "Fitted resources leave with their owning item definition")

func test_item_selection_uses_both_archetype_and_actual_body_scene() -> void:
	var body: Resource = BODY.new()
	body.archetype_id = "test.body"
	var item: Resource = ITEM.new()
	item.equipped_visuals.append(visual)
	assert_same(item.get_equipment_visual_for_body_archetype(body), visual)
	var resolved: Resource = item.get_equipment_visual_for_body_archetype(body, "res://test/body.glb")
	assert_eq(resolved.visual_scene.resource_path, "user://equipment_fit_test.tscn")
	assert_same(item.get_equipped_scene_for_body_archetype(body, "res://test/body.glb"), resolved.visual_scene)
	body.archetype_id = "other.body"
	assert_null(item.get_equipment_visual_for_body_archetype(body, "res://test/body.glb"))

func test_missing_fit_reports_the_asset_error_and_preserves_the_fallback() -> void:
	visual.body_fits["res://test/body.glb"] = "user://missing_equipment_fit.tscn"
	assert_same(visual.for_body_scene("res://test/body.glb"), visual)
	assert_push_error("Equipment fit cannot be loaded: user://missing_equipment_fit.tscn")
	assert_same(visual.visual_scene, source)

func test_fitted_visual_retains_authored_coverage_and_layer() -> void:
	visual.visual_layer = "armor"
	visual.visual_coverage = "legs"
	visual.visual_notes = "Keep the cuff opening"
	var resolved: Resource = visual.for_body_scene("res://test/body.glb")
	assert_eq(resolved.visual_layer, "armor")
	assert_eq(resolved.visual_coverage, "legs")
	assert_eq(resolved.visual_notes, "Keep the cuff opening")

func test_quaternius_clothes_keep_original_models_on_every_human_build() -> void:
	var ids := ["knight_cuirass", "knight_gambeson", "knight_greaves", "noble_doublet", "noble_trousers", "peasant_trousers", "peasant_tunic", "ranger_jerkin", "ranger_leggings", "wizard_trousers"]
	for id: String in ids:
		var item := load("res://features/inventory/resources/items/" + id + ".tres") as ItemDefinition
		assert_not_null(item)
		if item == null: continue
		for sex: String in ["male", "female"]:
			var body: Resource = load("res://features/actors/resources/character_body_archetypes/human_" + sex + ".tres")
			var original: Resource = item.get_equipment_visual_for_body_archetype(body)
			assert_not_null(original, id + " " + sex)
			if original == null: continue
			assert_true(original.body_fits.is_empty(), "Rejected replacement meshes must not override " + id)
			assert_true(original.visual_scene.resource_path.begins_with("res://assets/vendor/quaternius/"), "Keep the original vendor garment")
			for build: String in ["regular", "heroic", "teen"]:
				var body_scene: PackedScene = body.get(build + "_visual_scene")
				var resolved: Resource = item.get_equipment_visual_for_body_archetype(body, body_scene.resource_path)
				assert_same(resolved, original, id + " " + sex + " " + build)
				assert_same(item.get_equipped_scene_for_body_archetype(body, body_scene.resource_path), original.visual_scene)

func _scene(label: String) -> PackedScene:
	var node := Node3D.new()
	node.name = label
	var scene := PackedScene.new()
	assert_eq(scene.pack(node), OK)
	node.free()
	return scene
