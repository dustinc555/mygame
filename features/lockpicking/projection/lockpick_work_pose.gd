extends Node
## Temporary work prop only. The shared authored fixing clip owns both arms.
## Does not modify equipment or inventory.
const MOUNT := preload("res://features/actors/projection/equipment_mount_helper.gd")
var _body: HumanoidBodyProjection

var _item: ItemDefinition
var _skeleton: Skeleton3D
var _prop: Node3D
var _hidden: Array[Dictionary] = []

func configure(body: HumanoidBodyProjection) -> void:
	_body = body
	set_process(false)

func set_work(active: bool, item: ItemDefinition) -> void:
	if not active or item == null:
		clear()
		_item = null
		return
	if item != _item or not is_instance_valid(_prop) or _skeleton != _body.get_skeleton():
		clear()
		_item = item
		_attach()

func is_working() -> bool:
	return is_instance_valid(_prop) and not _prop.is_queued_for_deletion()

func _attach() -> void:
	_skeleton = _body.get_skeleton()
	if _skeleton == null:
		return
	hide_held_equipment()
	var mount = MOUNT.new(_body._get_grip_socket_profile(), _body.get_resolved_body_archetype())
	_prop = mount.mount(_skeleton, "weapon", _item)
	if _prop == null:
		clear()
		return
	_prop.name = "ActionLockpickVisual"

func clear() -> void:
	set_process(false)
	if is_working():
		_prop.hide()
		_prop.queue_free()
	_prop = null
	for record in _hidden:
		var node = record.node.get_ref()
		if is_instance_valid(node): node.visible = record.visible
	_hidden.clear()


func _exit_tree() -> void:
	clear()

func hide_held_equipment() -> void:
	if not is_instance_valid(_skeleton) or _item == null:
		return
	for node in _skeleton.find_children("Equipped*Visual", "Node3D", true, false):
		if node.name not in [&"EquippedWeaponVisual", &"EquippedOffhandVisual"]:
			continue
		var known := false
		for record in _hidden:
			if record.node.get_ref() == node: known = true
		if not known: _hidden.append({"node": weakref(node), "visible": node.visible})
		node.hide()
