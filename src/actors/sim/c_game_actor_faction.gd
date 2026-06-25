extends "res://addons/gecs/ecs/component.gd"

class_name CGameActorFaction

@export var faction_id := ""
@export var squad_name := ""
@export var hostile_faction_ids: PackedStringArray = PackedStringArray()
@export var combat_stance := 0
@export var player_party_member := false
