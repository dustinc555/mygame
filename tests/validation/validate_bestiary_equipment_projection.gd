extends SceneTree

const PROJECTION_PATH := "res://features/actors/projection/bestiary/bestiary_equipment_projection.gd"
var failures: Array[String] = []

class Wearer extends Node:
	var starting_equipment: Array = []
	var inventory := InventoryData.new()
	func get_equipment_slot_names() -> Array[String]: return ["weapon", "chest"]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var humanoid_script := load("res://features/actors/projection/humanoid/humanoid_body_projection.gd") as GDScript
	_check(humanoid_script != null and humanoid_script.can_instantiate(), "shared mount consumer loads in runtime with autoloads")
	if not ResourceLoader.exists(PROJECTION_PATH):
		push_error("Reusable bestiary projection is missing")
		quit(1)
		return
	var model := Node3D.new()
	root.add_child(model)
	var skeleton := Skeleton3D.new()
	model.add_child(skeleton)
	skeleton.add_bone("hand_r")
	var bundled := MeshInstance3D.new()
	bundled.name = "BundledSword"
	skeleton.add_child(bundled)
	var wearer := Wearer.new()
	var equipment := EquipmentCapability.new()
	equipment.setup(wearer)
	var item := ItemDefinition.new()
	item.equip_slot = "weapon"
	var wrapper := Node3D.new()
	var grip := Marker3D.new()
	grip.name = "GripPoint_Primary"
	grip.position = Vector3(0.2, 0.4, -0.3)
	wrapper.add_child(grip)
	grip.owner = wrapper
	item.equipped_scene = PackedScene.new()
	item.equipped_scene.pack(wrapper)
	wrapper.free()
	var projection: Node = load(PROJECTION_PATH).new()
	model.add_child(projection)
	projection.configure(model, equipment, PackedStringArray(["BundledSword"]))
	_check(not bundled.visible, "bundled removable mesh hidden even when unequipped")
	equipment.equip_item_to_slot(item, "weapon", "real-stack")
	var visual := skeleton.find_child("EquippedWeaponVisual", true, false) as Node3D
	_check(visual != null, "capability equip signal creates actual equipped scene")
	if visual != null:
		var mounted := visual.get_child(0) as Node3D
		_check((mounted.transform * mounted.get_node("GripPoint_Primary").transform).is_equal_approx(item.equipped_transform), "item grip is aligned using inverse authored marker")
	var removed := equipment.unequip_item_from_slot("weapon")
	_check(removed == item, "unequip returns same item")
	_check(skeleton.find_child("EquippedWeaponVisual", true, false) == null, "unequip removes visual synchronously")
	_check(not bundled.visible, "unequip does not restore vendor sword")
	_test_clothing(projection, model, skeleton, equipment)
	# Reconfigure disconnects the previous capability and clears derived visuals.
	var other := EquipmentCapability.new()
	other.setup(wearer)
	projection.configure(model, other, PackedStringArray(["BundledSword"]))
	equipment.equip_item_to_slot(item, "weapon")
	_check(skeleton.find_child("EquippedWeaponVisual", true, false) == null, "old capability disconnected after reconfigure")
	other.equip_item_to_slot(item, "weapon")
	_check(skeleton.find_child("EquippedWeaponVisual", true, false) != null, "new capability connected")
	projection.free()
	var exiting_visual := skeleton.find_child("EquippedWeaponVisual", true, false) as Node3D
	_check(exiting_visual == null or not exiting_visual.visible, "teardown hides gear immediately")
	await process_frame
	_check(skeleton.find_child("EquippedWeaponVisual", true, false) == null, "projection teardown removes its gear without deleting model")
	other.teardown()
	equipment.teardown()
	wearer.free()
	model.free()
	for failure in failures: push_error(failure)
	print("BESTIARY_EQUIPMENT_PROJECTION_OK" if failures.is_empty() else "BESTIARY_EQUIPMENT_PROJECTION_FAILED")
	quit(0 if failures.is_empty() else 1)

func _test_clothing(projection: Node, model: Node3D, skeleton: Skeleton3D, equipment: EquipmentCapability) -> void:
	skeleton.add_bone("spine")
	skeleton.position = Vector3(0.3, 0.7, -0.2)
	var source := Node3D.new()
	source.position = Vector3(10, 20, 30)
	var armature := Node3D.new()
	armature.position = Vector3(2, 3, 4)
	source.add_child(armature)
	armature.owner = source
	var source_skeleton := Skeleton3D.new()
	armature.add_child(source_skeleton)
	source_skeleton.owner = source
	# Deliberately opposite order: numeric bind 0 must become target spine 1.
	source_skeleton.add_bone("spine")
	source_skeleton.add_bone("hand_r")
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.name = "AuthoredArmor"
	mesh.position = Vector3(0.1, 0.2, 0.3)
	mesh.skin = Skin.new()
	mesh.skin.add_bind(0, Transform3D(Basis.IDENTITY, Vector3(0, -1, 0)))
	source_skeleton.add_child(mesh)
	mesh.owner = source
	mesh.skeleton = NodePath("..")
	var armor := ItemDefinition.new()
	armor.equip_slot = "chest"
	armor.equipped_scene = PackedScene.new()
	armor.equipped_scene.pack(source)
	var original_skin := mesh.skin
	var expected := skeleton.transform * mesh.transform
	source.free()
	equipment.equip_item_to_slot(armor, "chest", "armor-stack")
	var visual := model.find_child("EquippedChestVisual", true, false)
	_check(visual != null, "actual clothing scene projected")
	if visual != null:
		var copy := visual.get_child(0) as MeshInstance3D
		_check(copy.transform.is_equal_approx(expected), "cloth preserves mesh-to-armature transform without wrapper double transform")
		_check(copy.get_node(copy.skeleton) == skeleton, "cloth uses the live target skeleton")
		_check(copy.skin.get_bind_bone(0) == 1 and copy.skin.get_bind_name(0) == &"spine", "skin binding remapped by bone name")
		_check(copy.skin.get_bind_pose(0) == original_skin.get_bind_pose(0), "inverse bind pose preserved")
		_check(original_skin.get_bind_bone(0) == 0, "source skin never mutated")
	equipment.unequip_item_from_slot("chest")
	_check(model.find_child("EquippedChestVisual", true, false) == null, "loot unequip removes clothing")
	projection.refresh()

func _check(value: bool, message: String) -> void:
	if not value: failures.append(message)
