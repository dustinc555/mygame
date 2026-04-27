extends "res://scripts/characters/humanoid_character.gd"

class_name MerchantHumanoid

@export var base_color := Color(0.62, 0.58, 0.26, 1.0)

var _assigned_traders: Dictionary = {}
var _pending_trader_ids: Dictionary = {}

@onready var body_mesh: MeshInstance3D = $BodyMesh

var _body_material := StandardMaterial3D.new()


func _ready() -> void:
	super._ready()
	_body_material.roughness = 0.9
	_body_material.albedo_color = base_color
	body_mesh.material_override = _body_material


func has_merchant_role() -> bool:
	return get_node_or_null("MerchantRole") is MerchantRole


func get_merchant_role() -> MerchantRole:
	return get_node_or_null("MerchantRole") as MerchantRole


func register_trader(member: PartyMember) -> void:
	_get_trader_slot(member)
	_pending_trader_ids[member.get_instance_id()] = true


func release_trader(member: PartyMember) -> void:
	_pending_trader_ids.erase(member.get_instance_id())
	_assigned_traders.erase(member.get_instance_id())


func resolve_trade(member: PartyMember) -> bool:
	if member == null:
		return false
	var actor_id := member.get_instance_id()
	if not _pending_trader_ids.has(actor_id):
		return false
	_pending_trader_ids.clear()
	return true


func get_interaction_position(member: PartyMember) -> Vector3:
	var slot_index := _get_trader_slot(member)
	var angle := TAU * float(slot_index) / 6.0
	return global_position + Vector3(cos(angle), 0.0, sin(angle)) * 1.5


func _get_trader_slot(member: PartyMember) -> int:
	var key := member.get_instance_id()
	if _assigned_traders.has(key):
		return _assigned_traders[key]
	for slot_index in range(6):
		if not _assigned_traders.values().has(slot_index):
			_assigned_traders[key] = slot_index
			return slot_index
	_assigned_traders[key] = 0
	return 0
