extends Node
class_name BestiaryEquipmentProjection

## Disposable view of EquipmentCapability. Never owns items, stacks, or the model.
const MOUNT_HELPER = preload("res://features/actors/projection/equipment_mount_helper.gd")
const CLOTHING_FITTER = preload("res://features/actors/projection/appearance/clothing_fitter.gd")
const RIGID_BACK_FITTER = preload("res://features/actors/projection/appearance/rigid_back_fitter.gd")
var _model: Node3D
var _equipment: EquipmentCapability
var _body_archetype: Resource
var _skeleton: Skeleton3D
var _removable_meshes := PackedStringArray()
var _slot_visuals: Dictionary = {}
var _clothing_fit_errors: Dictionary[String, String] = {}

func get_clothing_fit_error(slot: String) -> String:
	return _clothing_fit_errors.get(slot, "")

func configure(model: Node3D, equipment: EquipmentCapability, removable_meshes: PackedStringArray, body_archetype: Resource = null) -> void:
	_disconnect()
	_clear_visuals()
	_model = model
	_equipment = equipment
	_body_archetype = body_archetype
	_removable_meshes = removable_meshes.duplicate()
	_skeleton = _find_skeleton(model) if is_instance_valid(model) else null
	if _equipment != null:
		_equipment.equipment_changed.connect(_on_equipment_changed)
	refresh()

func _exit_tree() -> void:
	_disconnect()
	_clothing_fit_errors.clear()
	# The model may itself be exiting; freeing its children synchronously here
	# mutates a locked child list. Hide immediately and defer destruction.
	for visual in _slot_visuals.values():
		if is_instance_valid(visual):
			visual.hide()
			visual.queue_free()
	_slot_visuals.clear()

func _disconnect() -> void:
	if _equipment != null and _equipment.equipment_changed.is_connected(_on_equipment_changed):
		_equipment.equipment_changed.disconnect(_on_equipment_changed)
	_equipment = null

func _clear_visuals() -> void:
	_clothing_fit_errors.clear()
	for visual in _slot_visuals.values():
		if is_instance_valid(visual): visual.free()
	_slot_visuals.clear()

func refresh() -> void:
	_clear_visuals()
	if not is_instance_valid(_model): return
	_hide_bundled_meshes(_model)
	if _equipment == null: return
	for slot in _equipment.get_equipped_items():
		_refresh_slot(str(slot))

func _on_equipment_changed(changed_slots: Array) -> void:
	if changed_slots.is_empty():
		refresh()
		return
	for slot in changed_slots:
		_refresh_slot(str(slot))

func _refresh_slot(slot: String) -> void:
	_clothing_fit_errors.erase(slot)
	var previous: Node = _slot_visuals.get(slot)
	if is_instance_valid(previous): previous.free()
	_slot_visuals.erase(slot)
	if _equipment == null: return
	var item := _equipment.get_equipped_item(slot)
	if item == null: return
	if not is_instance_valid(_skeleton):
		if item.has_clothing_binding():
			_clothing_fit_errors[slot] = "Clothing requires a live body skeleton"
		return
	var visual: Node3D
	if slot == "weapon" or slot == "offhand":
		var profile: Resource = _body_archetype.get("grip_socket_profile") if _body_archetype != null else null
		visual = MOUNT_HELPER.new(profile, _body_archetype).mount(_skeleton, slot, item)
	else:
		visual = _mount_clothing(item, slot)
	if visual != null: _slot_visuals[slot] = visual

func _hide_bundled_meshes(node: Node) -> void:
	if node == self: return
	if node is MeshInstance3D and (_removable_meshes.has(str(node.name)) or _removable_meshes.has(str(_model.get_path_to(node)))):
		(node as MeshInstance3D).hide()
	for child in node.get_children(): _hide_bundled_meshes(child)

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null: return found
	return null

func _mount_clothing(item: ItemDefinition, slot: String) -> Node3D:
	var body_scene_path := _model.scene_file_path
	var scene := item.get_equipped_scene_for_body_archetype(_body_archetype, body_scene_path)
	if scene == null:
		if item.has_clothing_binding():
			_clothing_fit_errors[slot] = "No compatible clothing source/body profile for %s" % body_scene_path
		return null
	var instance := scene.instantiate()
	if not instance is Node3D:
		instance.free()
		if item.has_clothing_binding():
			_clothing_fit_errors[slot] = "Clothing source must be a Node3D scene"
		return null
	var source := instance as Node3D
	var item_transform := item.equipped_transform
	var variant := item.get_equipment_visual_for_body_archetype(_body_archetype, body_scene_path)
	if variant != null: item_transform = variant.get("equipped_transform")
	var binding: Resource = variant.get("clothing_binding") if variant != null else null
	var rigid_back: bool = variant is EquipmentVisualDefinition and variant.rigid_back_fit
	if binding != null or rigid_back:
		var profile: Resource = _body_archetype.get_wardrobe_profile(body_scene_path) if _body_archetype != null else null
		var result := RIGID_BACK_FITTER.fit(source, variant, _skeleton, _model) if rigid_back else CLOTHING_FITTER.fit(source, binding, profile, _skeleton)
		source.free()
		if not result.error.is_empty():
			_clothing_fit_errors[slot] = result.error
			return null
		var fitted: Node3D = result.visual
		fitted.name = "Equipped%sVisual" % slot.capitalize()
		fitted.transform = _relative_transform(_model, _skeleton) * item_transform
		_model.add_child(fitted)
		var fitted_meshes: Array[MeshInstance3D] = []
		_collect_meshes(fitted, fitted_meshes)
		for mesh in fitted_meshes:
			# Preserve the fitter's target-named inverse binds, not source rests.
			mesh.skeleton = mesh.get_path_to(_skeleton)
		return fitted
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(source, meshes)
	var visual := Node3D.new()
	visual.name = "Equipped%sVisual" % slot.capitalize()
	_model.add_child(visual)
	for mesh in meshes:
		if mesh.mesh == null: continue
		var source_skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if source_skeleton == null:
			push_warning("Skipping unskinned bestiary clothing mesh: %s" % mesh.name)
			continue
		var skin := _remap_skin(mesh, source_skeleton)
		if skin == null: continue
		# Preserve authored mesh-to-armature coordinates, not wrapper-root offsets.
		# The target armature transform supplies model scale/orientation exactly once.
		var mesh_to_skeleton := _relative_transform(source, source_skeleton).affine_inverse() * _relative_transform(source, mesh)
		var copy := mesh.duplicate(0) as MeshInstance3D
		for child in copy.get_children(): child.free()
		visual.add_child(copy)
		copy.transform = _relative_transform(_model, _skeleton) * item_transform * mesh_to_skeleton
		copy.skin = skin
		copy.skeleton = copy.get_path_to(_skeleton)
	source.free()
	if visual.get_child_count() == 0:
		visual.free()
		return null
	return visual

func _remap_skin(mesh: MeshInstance3D, source_skeleton: Skeleton3D) -> Skin:
	var source_skin := mesh.skin
	if source_skin == null: source_skin = source_skeleton.create_skin_from_rest_transforms()
	var skin := source_skin.duplicate() as Skin
	for binding in skin.get_bind_count():
		var bone_name := skin.get_bind_name(binding)
		if bone_name == &"":
			var source_index := skin.get_bind_bone(binding)
			if source_index < 0 or source_index >= source_skeleton.get_bone_count(): return null
			bone_name = source_skeleton.get_bone_name(source_index)
		var target_index := _skeleton.find_bone(bone_name)
		if target_index < 0:
			push_warning("Clothing bone %s is absent on target; refusing invalid skin" % bone_name)
			return null
		skin.set_bind_name(binding, bone_name)
		skin.set_bind_bone(binding, target_index)
	return skin

func _relative_transform(root: Node3D, node: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D: result = (current as Node3D).transform * result
		current = current.get_parent()
	return result

func _collect_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D: meshes.append(node as MeshInstance3D)
	for child in node.get_children(): _collect_meshes(child, meshes)
