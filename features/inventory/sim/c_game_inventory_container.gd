extends "res://addons/gecs/ecs/component.gd"

class_name CGameInventoryContainer

@export var container_id := ""
@export var owner_actor_id := ""
@export var settlement_id := ""
@export var facility_id := ""
@export var container_kind := ""
@export var contributes_to_town_stock := false
@export var next_stack_sequence := 1
@export var columns := 0
@export var rows := 0
@export var max_weight := 0.0
@export var accepts_input := true
@export var is_world_container := false
@export var is_job_work_inventory := false
