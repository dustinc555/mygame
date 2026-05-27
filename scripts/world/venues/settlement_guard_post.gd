@tool
extends "res://scripts/world/venues/bar_guard_post.gd"

class_name SettlementGuardPost


func _ready() -> void:
	super._ready()
	add_to_group("settlement_guard_post")
