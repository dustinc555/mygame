extends "res://addons/gecs/ecs/component.gd"

class_name CGameActorIdentity

@export var actor_id := ""
@export var stable_id := ""
@export var member_name := ""
@export var role_id := "resident"
@export var authority_scopes: PackedStringArray = PackedStringArray()
@export var important := false
