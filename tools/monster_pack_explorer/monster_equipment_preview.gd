extends Node
## Debug workbench state only. Uses real equipment rules and item definitions.
const MANIFEST_PATH := "res://assets/vendor/quaternius/bestiary_dungeon_monsters/equipment_manifest.json"
class PreviewWearer extends Node3D:
	var appearance_data := CharacterAppearanceData.new()
	var starting_equipment: Array = []
	var inventory := InventoryData.new()
	func get_equipment_slot_names() -> Array[String]:
		return ["head", "chest", "undershirt", "legs", "feet", "hands", "weapon", "offhand", "backpack"]

var equipment := EquipmentCapability.new()
var wearer := PreviewWearer.new()
var manifest: Dictionary = {}
var options: Dictionary = {}
var _loadouts: Dictionary = {}
var _model_name := ""
var _panel: VBoxContainer
var _projection: Node

func _ready() -> void:
	add_child(wearer)
	equipment.setup(wearer)
	equipment.ready()
	if FileAccess.file_exists(MANIFEST_PATH):
		var data = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
		if data is Dictionary: manifest = data

func setup_panel(panel: VBoxContainer) -> void:
	_panel = panel

func select_model(model_name: String, model: Node3D) -> void:
	if is_instance_valid(_projection):
		_projection.free()
	if not _model_name.is_empty():
		var saved := {}
		for slot in equipment.get_equipped_items():
			saved[slot] = equipment.get_equipped_item(slot).resource_path
		_loadouts[_model_name] = saved
	_model_name = model_name
	var data: Dictionary = manifest.get("models", {}).get(model_name + ".glb", {})
	var race_id := str(data.get("race_id", ""))
	var race := CharacterRaceDefinition.new()
	race.race_id = race_id
	wearer.appearance_data.character_race = race
	equipment.begin_equipment_update_batch()
	for slot in equipment.get_equipped_items().keys(): equipment.unequip_item_from_slot(slot)
	options.clear()
	# Skeleton variants share one race and therefore the same equipment choices.
	for candidate in manifest.get("models", {}).values():
		if str(candidate.get("race_id", "")) != race_id: continue
		for path in candidate.get("default_items", []):
			var item := load(str(path)) as ItemDefinition
			if item == null or not equipment.can_equip_item_to_slot(item, item.equip_slot): continue
			if not options.has(item.equip_slot): options[item.equip_slot] = []
			if not options[item.equip_slot].has(item): options[item.equip_slot].append(item)
	if _loadouts.has(model_name):
		for slot in _loadouts[model_name]:
			equipment.equip_item_to_slot(load(_loadouts[model_name][slot]), slot)
	else:
		for path in data.get("default_items", []):
			var item := load(str(path)) as ItemDefinition
			if item != null: equipment.equip_item_to_slot(item, item.equip_slot)
	equipment.end_equipment_update_batch()
	var script := load("res://features/actors/projection/bestiary/bestiary_equipment_projection.gd") as Script
	if script != null:
		_projection = script.new()
		model.add_child(_projection)
		_projection.configure(model, equipment, PackedStringArray(data.get("removable_meshes", [])))
	_rebuild_panel()

func _rebuild_panel() -> void:
	if _panel == null: return
	for child in _panel.get_children():
		_panel.remove_child(child)
		child.queue_free()
	for slot in wearer.get_equipment_slot_names():
		if not options.has(slot): continue
		var label := Label.new()
		label.text = str(slot).capitalize()
		_panel.add_child(label)
		var picker := OptionButton.new()
		picker.name = str(slot).capitalize() + "Picker"
		picker.fit_to_longest_item = false
		picker.add_item("None")
		var index := 1
		for item in options[slot]:
			picker.add_item(item.display_name)
			if equipment.get_equipped_item(slot) == item: picker.select(index)
			index += 1
		picker.item_selected.connect(func(selected: int): choose_item(slot, selected))
		_panel.add_child(picker)

func choose_item(slot: String, index: int) -> void:
	if not options.has(slot) or index < 0 or index > options[slot].size(): return
	if index == 0: equipment.unequip_item_from_slot(slot)
	else: equipment.equip_item_to_slot(options[slot][index - 1], slot)

func _exit_tree() -> void:
	equipment.teardown()
