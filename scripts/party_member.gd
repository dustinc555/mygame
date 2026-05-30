extends "res://scripts/characters/humanoid_character.gd"

class_name PartyMember

@export var base_color := Color(0.7, 0.7, 0.7, 1.0)
@export var selected_color := Color(0.72, 0.74, 0.78, 0.34)
@export var focused_color := Color(1.0, 0.84, 0.26, 0.52)

@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var selection_ring: MeshInstance3D = $SelectionRing

var _body_material := StandardMaterial3D.new()


func _ready() -> void:
	player_party_member = true
	super._ready()
	_body_material.roughness = 0.85
	_body_material.albedo_color = base_color
	body_mesh.material_override = _body_material
	_disable_scene_selection_ring()
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
	if _inspect_ring != null:
		_inspect_ring.visible = is_inspected and not is_selected and not is_focused
	_update_ground_markers()


func _disable_scene_selection_ring() -> void:
	selection_ring.mesh = null
	selection_ring.material_override = null
	selection_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in selection_ring.get_children():
		child.queue_free()
