extends GutTest

const FURNITURE := "res://features/world/projection/props/furniture/"
const LEGACY := "res://features/world/projection/containers/"

class CatalogTools extends "res://addons/world_authoring/facility_tools.gd":
	func _init(_editor: EditorPlugin = null) -> void: pass

func test_storage_type_change_preserves_existing_contents_and_identity() -> void:
	var container := WorldContainer.new()
	container.container_id = "storage.test"
	container.inventory = InventoryData.new(7, 5, 0.0, false)
	var food := ItemDefinition.new()
	food.item_id = "food.test"
	assert_true(container.inventory.add_item_count(food, 1))
	var entry = container.inventory.entries[0]
	container.container_type = "weapons"
	assert_eq(container.container_type, "weapons")
	assert_eq(container.container_id, "storage.test")
	assert_same(container.inventory.entries[0], entry)
	assert_false(container.can_accept_item_count(food, 1))
	var sword := ItemDefinition.new()
	sword.item_id = "equipment.test_sword"
	sword.equip_slot = ItemDefinition.EQUIP_SLOT_WEAPON
	assert_true(container.can_accept_item_count(sword, 1))
	container.allowed_item_ids = PackedStringArray(["equipment.other"])
	assert_false(container.can_accept_item_count(sword, 1))
	container.free()

func test_storage_type_roundtrip_preserves_policy() -> void:
	var container := WorldContainer.new()
	container.hydrate_container_policy_from_gecs("weapons", PackedStringArray(["sword"]))
	assert_eq(container.container_type, "weapons")
	assert_eq(container.allowed_item_ids, PackedStringArray(["sword"]))
	container.container_type = "general"
	assert_eq(container.container_kind, "storage")
	container.free()

func test_offscreen_weapons_acceptance_preserves_general_routing() -> void:
	var controller := InventoryStockController.new()
	var component := CGameInventoryContainer.new()
	component.container_type = "weapons"
	component.container_kind = "storage"
	controller._containers_by_id["test"] = {"component": component}
	var sword := ItemDefinition.new()
	sword.item_id = "equipment.test_sword"
	sword.equip_slot = ItemDefinition.EQUIP_SLOT_WEAPON
	assert_true(controller._container_accepts_definition("test", sword))
	var food := ItemDefinition.new()
	food.item_id = "food.test"
	assert_false(controller._container_accepts_definition("test", food))
	component.allowed_item_ids = PackedStringArray(["other"])
	assert_false(controller._container_accepts_definition("test", sword))
	component.allowed_item_ids = PackedStringArray()
	component.container_type = "general"
	assert_true(controller._container_accepts_definition("test", sword), "Adding Weapons must not invalidate existing general storage")
	controller.free()

func test_editor_and_runtime_use_identical_admission() -> void:
	var tools := CatalogTools.new()
	var container := WorldContainer.new()
	var tool := ItemDefinition.new()
	tool.item_id = "equipment.axe"
	tool.equip_slot = ItemDefinition.EQUIP_SLOT_WEAPON
	tool.tool_tags = PackedStringArray(["chop"])
	for type_id in WorldContainer.CONTAINER_TYPES:
		container.container_type = type_id
		assert_eq(tools._item_matches_container_type(tool, type_id), container.can_accept_item_count(tool, 1), type_id)
	container.free()

func test_all_sign_choices_resolve_to_existing_models() -> void:
	var sign := FacilitySign.new()
	for type_id in FacilitySign.SIGN_MODELS:
		sign.sign_type = type_id
		assert_eq(sign.get_sign_scene().resource_path.get_file(), str(FacilitySign.SIGN_MODELS[type_id]) + ".gltf")
	sign.free()

func test_catalog_lists_physical_containers_not_purpose_aliases() -> void:
	var tools := CatalogTools.new()
	var paths: Array = []
	for row in tools.get_furniture_catalog(): paths.append(str(row.path).get_file())
	for file in ["barrel_container.tscn", "weapon_chest_container.tscn", "seed_barrel.tscn", "seed_sack.tscn", "tool_chest.tscn"]:
		assert_false(paths.has(file), file)
	for file in ["barrel.tscn", "barrel_dark.tscn", "chest_wood.tscn", "crate_wooden.tscn"]:
		assert_true(paths.has(file), file)


func test_legacy_barrel_uses_real_mesh_without_capacity_change() -> void:
	var barrel = load(LEGACY + "barrel_container.tscn").instantiate()
	assert_eq(barrel.inventory_columns, 7)
	assert_eq(barrel.inventory_rows, 5)
	assert_true(barrel.visual_scene.resource_path.ends_with("Barrel.gltf"))
	barrel.free()

func test_sign_selection_updates_model_and_can_return_to_auto() -> void:
	var sign = load(FURNITURE + "facility_sign.tscn").instantiate()
	add_child_autofree(sign)
	sign.set("sign_type", "blacksmith")
	await get_tree().process_frame
	assert_true(sign.get_node("Model").scene_file_path.ends_with("Sign_Blacksmith.gltf"))
	var selected_model = sign.get_node("Model")
	sign.set("sign_type", "blacksmith")
	await get_tree().process_frame
	assert_same(sign.get_node("Model"), selected_model, "Unchanged selection must not rebuild")
	sign.set("sign_type", "auto")
	await get_tree().process_frame
	assert_true(sign.get_node("Model").scene_file_path.ends_with("Sign_Pub.gltf"))

func test_sign_override_remains_authoritative() -> void:
	var sign = load(FURNITURE + "facility_sign.tscn").instantiate()
	add_child_autofree(sign)
	sign.sign_scene_override = load("res://assets/vendor/quaternius/fantasy_props_megakit/gltf/Sign_Food.gltf")
	sign.set("sign_type", "blacksmith")
	await get_tree().process_frame
	assert_true(sign.get_node("Model").scene_file_path.ends_with("Sign_Food.gltf"))
	sign.sign_scene_override = null
	await get_tree().process_frame
	assert_true(sign.get_node("Model").scene_file_path.ends_with("Sign_Blacksmith.gltf"))

func test_rugs_have_cloth_and_pattern_material_in_thumbnail_source() -> void:
	for file in ["rug_round.tscn", "rug_1.tscn"]:
		var rug = load(FURNITURE + file).instantiate()
		var visuals := Node3D.new()
		preload("res://addons/world_authoring/scene_thumbnail.gd")._copy_meshes(rug, Transform3D.IDENTITY, visuals)
		assert_gt(visuals.get_child_count(), 0)
		for mesh in visuals.get_children():
			var material = mesh.get_active_material(0)
			assert_true(material is ShaderMaterial, file)
			if material is ShaderMaterial:
				assert_not_null(material.get_shader_parameter("cloth_texture"))
				assert_not_null(material.get_shader_parameter("cloth_normal"))
		rug.free()
		visuals.free()
