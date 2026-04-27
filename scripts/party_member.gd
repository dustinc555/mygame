extends "res://scripts/characters/humanoid_character.gd"

class_name PartyMember

@export var base_color := Color(0.7, 0.7, 0.7, 1.0)
@export var selected_color := Color(1.0, 0.88, 0.48, 1.0)
@export var focused_color := Color(1.0, 0.97, 0.7, 1.0)

var is_selected := false
var is_focused := false

@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var selection_ring: MeshInstance3D = $SelectionRing

var _body_material := StandardMaterial3D.new()
var _ring_material := StandardMaterial3D.new()


func _ready() -> void:
	super._ready()
	add_to_group("party_member")
	_body_material.roughness = 0.85
	_body_material.albedo_color = base_color
	body_mesh.material_override = _body_material
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	selection_ring.material_override = _ring_material
	_update_visuals()


func set_selected(value: bool) -> void:
	is_selected = value
	_update_visuals()


func set_focused(value: bool) -> void:
	is_focused = value
	_update_visuals()


func _update_visuals() -> void:
	var body_color := base_color
	if is_selected:
		body_color = base_color.lerp(selected_color, 0.4)
	if is_focused:
		body_color = body_color.lerp(focused_color, 0.45)
	_body_material.albedo_color = body_color
	selection_ring.visible = is_selected or is_focused
	if is_focused:
		_ring_material.albedo_color = focused_color
	elif is_selected:
		_ring_material.albedo_color = selected_color
	if _inspect_ring != null:
		_inspect_ring.visible = is_inspected and not is_selected and not is_focused
