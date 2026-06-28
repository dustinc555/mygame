extends "res://features/actors/projection/humanoid/humanoid_character.gd"

class_name PartyMember

const SELECTION_RING_VISUAL = preload("res://features/actors/projection/selection_ring_visual.gd")

@export var base_color := Color(0.7, 0.7, 0.7, 1.0)
@export var selected_color := Color(0.28, 0.78, 1.0, 1.0)
@export var focused_color := Color(0.95, 0.78, 0.26, 1.0)

@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var selection_ring: MeshInstance3D = $SelectionRing

var _body_material := StandardMaterial3D.new()
var _ring_material := StandardMaterial3D.new()


func _init() -> void:
	# Player party humans always track hunger; class default, not per-scene authoring.
	hunger_enabled = true
	# Party members fight who attacks them or who the player orders — they never
	# initiate on faction hostility alone and never pursue.
	combat_stance = NpcRules.CombatStance.DEFENSIVE


func _ready() -> void:
	player_party_member = true
	super._ready()
	_body_material.roughness = 0.85
	_body_material.albedo_color = base_color
	body_mesh.material_override = _body_material
	_setup_selection_ring()
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
	SELECTION_RING_VISUAL.apply_state(selection_ring, _ring_material, is_selected, is_focused, selected_color, focused_color)
	if _inspect_ring != null:
		_inspect_ring.visible = is_inspected and not is_selected and not is_focused
	_update_ground_markers()


func _setup_selection_ring() -> void:
	SELECTION_RING_VISUAL.setup_ring(selection_ring, _ring_material)


## Extends the base inspect-ring seating with this member's selection ring.
func _update_ground_markers() -> void:
	super._update_ground_markers()
	if selection_ring != null and is_instance_valid(selection_ring) and selection_ring.visible:
		_seat_ground_marker(selection_ring, _selection_marker_height())
