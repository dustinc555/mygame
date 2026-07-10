@tool
extends Node3D

class_name FacilitySign

## Drag-and-forget facility sign: one furniture piece that renders whichever
## Sign_* model matches the facility it hangs in. At runtime it walks its
## ancestors for the owning SettlementFacility and swaps its model to the
## mapped sign (bar -> Sign_Pub); unmapped facility types and signs placed
## outside a facility keep the authored default. Sign icon textures always go
## through ModelRepairs (the icon lives in UV2 with a white-mask albedo).

const SIGNS_DIR := "res://assets/vendor/quaternius/fantasy_props_megakit/gltf"
const SIGN_BY_FACILITY_TYPE := {
	"bar": "Sign_Pub",
	"tavern": "Sign_Pub",
	"social": "Sign_Pub",
	"shop": "Sign_Food",
	"farm": "Sign_Food",
	"weapon_shop": "Sign_Armory",
	"armor_shop": "Sign_Armory_2",
	"potion_shop": "Sign_Potions",
}

@export var furniture_type := FurnitureRules.Type.DECOR
## Authored override wins over facility resolution (e.g. a specific sign on
## a generic building).
@export var sign_scene_override: PackedScene


func _ready() -> void:
	add_to_group(FurnitureRules.FURNITURE_GROUP)
	add_to_group("facility_sign")
	if Engine.is_editor_hint():
		_repair_current_model()
		return
	_resolve_and_apply_sign()


func _resolve_and_apply_sign() -> void:
	var sign_scene := sign_scene_override
	if sign_scene == null:
		var facility_type := _find_owning_facility_type()
		if SIGN_BY_FACILITY_TYPE.has(facility_type):
			sign_scene = load("%s/%s.gltf" % [SIGNS_DIR, SIGN_BY_FACILITY_TYPE[facility_type]]) as PackedScene
	if sign_scene != null:
		_swap_model(sign_scene)
	_repair_current_model()


func _find_owning_facility_type() -> String:
	var current := get_parent()
	while current != null:
		if current is SettlementFacility:
			return (current as SettlementFacility).facility_type
		current = current.get_parent()
	return ""


func _swap_model(sign_scene: PackedScene) -> void:
	var model := get_node_or_null("Model")
	if model != null:
		remove_child(model)
		model.free()
	var fresh := sign_scene.instantiate() as Node3D
	fresh.name = "Model"
	add_child(fresh)


func _repair_current_model() -> void:
	var model := get_node_or_null("Model") as Node3D
	if model != null:
		ModelRepairs.copy_uv2_to_uv_for_material(model, "MI_WoodenSign")
