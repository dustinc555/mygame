extends "res://scripts/characters/humanoid_character.gd"

class_name MerchantHumanoid

@export var base_color := Color(0.62, 0.58, 0.26, 1.0)
@export var selected_color := Color(1.0, 0.88, 0.48, 1.0)
@export var focused_color := Color(1.0, 0.97, 0.7, 1.0)

var _assigned_traders: Dictionary = {}
var _pending_trader_ids: Dictionary = {}

@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var selection_ring: MeshInstance3D = get_node_or_null("SelectionRing")

var _body_material := StandardMaterial3D.new()
var _ring_material := StandardMaterial3D.new()


func _ready() -> void:
	super._ready()
	_body_material.roughness = 0.9
	_body_material.albedo_color = base_color
	body_mesh.material_override = _body_material
	if selection_ring != null:
		_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		selection_ring.material_override = _ring_material
	_update_visuals()


func has_merchant_role() -> bool:
	return get_node_or_null("MerchantRole") is MerchantRole


func get_merchant_role() -> MerchantRole:
	return get_node_or_null("MerchantRole") as MerchantRole


func register_trader(member: HumanoidCharacter) -> void:
	_get_trader_slot(member)
	_pending_trader_ids[member.get_instance_id()] = true


func release_trader(member: HumanoidCharacter) -> void:
	_pending_trader_ids.erase(member.get_instance_id())
	_assigned_traders.erase(member.get_instance_id())


func resolve_trade(member: HumanoidCharacter) -> bool:
	if member == null:
		return false
	var actor_id := member.get_instance_id()
	if not _pending_trader_ids.has(actor_id):
		return false
	_pending_trader_ids.clear()
	return true


func get_interaction_position(member: HumanoidCharacter) -> Vector3:
	var slot_index := _get_trader_slot(member)
	var angle := TAU * float(slot_index) / 6.0
	return global_position + Vector3(cos(angle), 0.0, sin(angle)) * 1.5


func _get_trader_slot(member: HumanoidCharacter) -> int:
	var key := member.get_instance_id()
	if _assigned_traders.has(key):
		return _assigned_traders[key]
	for slot_index in range(6):
		if not _assigned_traders.values().has(slot_index):
			_assigned_traders[key] = slot_index
			return slot_index
	_assigned_traders[key] = 0
	return 0


func set_selected(value: bool) -> void:
	super.set_selected(value)
	_update_visuals()


func set_focused(value: bool) -> void:
	super.set_focused(value)
	_update_visuals()


func _update_visuals() -> void:
	var body_color := base_color
	if is_selected:
		body_color = base_color.lerp(selected_color, 0.4)
	if is_focused:
		body_color = body_color.lerp(focused_color, 0.45)
	_body_material.albedo_color = body_color
	if selection_ring != null:
		selection_ring.visible = is_selected or is_focused
		if is_focused:
			_ring_material.albedo_color = focused_color
		elif is_selected:
			_ring_material.albedo_color = selected_color
	if _inspect_ring != null:
		_inspect_ring.visible = is_inspected and not is_selected and not is_focused
