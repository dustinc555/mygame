extends "res://addons/gecs/ecs/component.gd"

class_name CGameSettlementEvent

@export var event_id := ""
@export var settlement_id := ""
@export var event_type := ""
@export var absolute_minute := -1
@export var day := -1
@export var hour := -1
@export var minute := -1
@export var data: Dictionary = {}
