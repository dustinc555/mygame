extends "res://addons/gecs/ecs/component.gd"

class_name CGameJobProviderSlot

@export var slot_id := ""
@export var provider_id := ""
@export var job_index := -1
@export var slot_index := 0
@export var worker_actor_id := ""
@export var active := false
@export var accrued_interval_time := 0.0
@export var guard_shuffle_remaining := 0.0
@export var server_state := "idle"
@export var server_state_elapsed := 0.0
@export var server_order_text := ""
@export var last_work_blocker := ""
