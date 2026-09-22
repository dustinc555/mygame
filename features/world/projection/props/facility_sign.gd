@tool
extends Node3D

class_name FacilitySign

## One placeable sign, with the same selection in the editor and game.
## Auto resolves only its ancestors, never scans or rebuilds the town.
## Sign icon textures use UV2 with a white-mask albedo.

const SIGNS_DIR := "res://assets/vendor/quaternius/fantasy_props_megakit/gltf"
const GENERAL_TRADE_SIGN := preload("res://features/world/projection/props/models/general_trade_sign.tscn")
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
const SIGN_MODELS := {
	"tavern": "Sign_Pub",
	"food": "Sign_Food",
	"weapons": "Sign_Armory",
	"armor": "Sign_Armory_2",
	"potions": "Sign_Potions",
	"blacksmith": "Sign_Blacksmith",
}

@export var furniture_type := FurnitureRules.Type.DECOR
## Auto follows the owning facility when mounted. Explicit types travel with
## the sign when it is moved elsewhere; the selected model is disposable.
@export_enum("auto", "general_trade", "tavern", "food", "weapons", "armor", "potions", "blacksmith") var sign_type := "auto":
	set(value):
		if sign_type == value:
			return
		sign_type = value
		_queue_refresh()
## Authored override wins over facility resolution (e.g. a specific sign on
## a generic building).
@export var sign_scene_override: PackedScene:
	set(value):
		if sign_scene_override == value:
			return
		sign_scene_override = value
		_queue_refresh()

var _refresh_pending := false
var _applied_scene: PackedScene


func _notification(what: int) -> void:
	if what == NOTIFICATION_PARENTED or what == NOTIFICATION_ENTER_TREE:
		_queue_refresh()


func _queue_refresh() -> void:
	if not is_inside_tree() or _refresh_pending:
		return
	_refresh_pending = true
	call_deferred("_resolve_and_apply_sign")


func _ready() -> void:
	add_to_group(FurnitureRules.FURNITURE_GROUP)
	add_to_group("facility_sign")
	_resolve_and_apply_sign()


func _resolve_and_apply_sign() -> void:
	_refresh_pending = false
	if not is_inside_tree():
		return
	var sign_scene := get_sign_scene()
	if sign_scene == _applied_scene and get_node_or_null("Model") != null:
		return
	_swap_model(sign_scene)
	_applied_scene = sign_scene
	_repair_current_model()


func get_sign_scene() -> PackedScene:
	if sign_scene_override != null:
		return sign_scene_override
	if sign_type == "general_trade":
		return GENERAL_TRADE_SIGN
	var model_name := str(SIGN_MODELS.get(sign_type, "Sign_Pub"))
	if sign_type == "auto":
		model_name = str(SIGN_BY_FACILITY_TYPE.get(_find_owning_facility_type(), "Sign_Pub"))
	return load("%s/%s.gltf" % [SIGNS_DIR, model_name]) as PackedScene


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
