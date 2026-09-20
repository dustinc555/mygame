extends SceneTree
const PROJECTION = preload("res://features/actors/projection/bestiary/bestiary_equipment_projection.gd")

class Owner extends Node3D:
	var appearance_data := CharacterAppearanceData.new()
	var starting_equipment: Array = []
	var inventory := InventoryData.new()
	var equipment := EquipmentCapability.new()
	func get_equipment() -> EquipmentCapability: return equipment
	func get_equipment_slot_names() -> Array[String]: return ["head", "chest", "hands", "legs", "feet", "weapon"]
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/vendor/quaternius/bestiary_dungeon_monsters/equipment_manifest.json"))
	var controller = load("res://features/inventory/bridge/party_inventory_controller.gd").new()
	var source := Owner.new()
	var receiver := Owner.new()
	root.add_child(source)
	root.add_child(receiver)
	source.equipment.setup(source)
	receiver.equipment.setup(receiver)
	var human := CharacterRaceDefinition.new()
	human.race_id = "human"
	receiver.appearance_data.character_race = human
	var verified: Array = []
	for entry in manifest.items:
		var item := load(entry.path) as ItemDefinition
		var race := CharacterRaceDefinition.new()
		race.race_id = entry.race
		source.appearance_data.character_race = race
		var model: Node3D = load("res://assets/vendor/quaternius/bestiary_dungeon_monsters/glb/" + entry.source_model).instantiate()
		source.add_child(model)
		var projection := PROJECTION.new()
		model.add_child(projection)
		projection.configure(model, source.equipment, PackedStringArray(manifest.models[entry.source_model].removable_meshes))
		var id := "loot." + str(item.item_id)
		source.equipment.equip_item_to_slot(item, item.equip_slot, id)
		_check(projection._slot_visuals.has(item.equip_slot), "actual item mounts: " + item.item_id)
		_check(item.icon != null, "item has a loadable SVG: " + item.item_id)
		if not item.compatible_races.is_empty():
			_check(not receiver.equipment.can_equip_item_to_slot(item, item.equip_slot), "human cannot wear restricted item")
		var skeleton := AnimationRetargetLib.find_skeleton(model)
		var pose := skeleton.get_bone_pose_rotation(1)
		# Real inventory transfer boundary, including full-container refusal.
		receiver.inventory.use_weight = true
		receiver.inventory.max_weight = 0.0
		controller._on_inventory_unequip_requested(source, item.equip_slot, receiver, Vector2i.ZERO)
		_check(source.equipment.get_equipped_item(item.equip_slot) == item, "failed transfer retains source item")
		_check(projection._slot_visuals.has(item.equip_slot), "failed transfer retains gear visual")
		receiver.inventory.use_weight = false
		controller._on_inventory_unequip_requested(source, item.equip_slot, receiver, Vector2i.ZERO)
		_check(source.equipment.get_equipped_item(item.equip_slot) == null, "loot removes equipped item")
		_check(not projection._slot_visuals.has(item.equip_slot), "loot removes visible item synchronously")
		_check(receiver.inventory.entries.size() == 1, "loot creates exactly one destination entry")
		if receiver.inventory.entries.size() == 1:
			_check(receiver.inventory.entries[0].stack_id == id, "loot preserves stack identity")
			_check(receiver.inventory.entries[0].definition == item, "loot preserves item definition")
		_check(skeleton.get_bone_pose_rotation(1).is_equal_approx(pose), "looting leaves pose intact")
		projection.refresh()
		_check(projection._slot_visuals.is_empty(), "refresh does not resurrect looted equipment")
		for mesh_name in manifest.models[entry.source_model].removable_meshes:
			var mesh := model.find_child(mesh_name, true, false) as MeshInstance3D
			_check(mesh != null and not mesh.visible, "bundled equipment stays hidden")
		verified.append(item.item_id)
		receiver.inventory.entries.clear()
		model.free()
	source.equipment.teardown()
	receiver.equipment.teardown()
	source.free()
	receiver.free()
	controller.free()
	var file := FileAccess.open("user://bestiary-item-loot-verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(verified))
	_check(not manifest.items.is_empty() and verified.size() == manifest.items.size(), "every manifest item must be verified")
	var seen_ids := {}
	for item_id in verified:
		_check(not seen_ids.has(item_id), "manifest item IDs must be unique")
		seen_ids[item_id] = true
	file.close()
	for failure in failures: push_error(failure)
	print("BESTIARY_ITEM_LOOT_OK count=" + str(verified.size()) if failures.is_empty() else "BESTIARY_ITEM_LOOT_FAILED")
	quit(0 if failures.is_empty() else 1)
func _check(value: bool, message: String) -> void:
	if not value: failures.append(message)
