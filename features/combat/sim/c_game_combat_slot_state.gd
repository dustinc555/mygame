extends "res://addons/gecs/ecs/component.gd"

class_name CGameCombatSlotState

enum FightState {
	NONE,
	MOVE_TO_TARGET,
	SEEKING_SLOT,
	FIGHTING,
	WAITING,
}

@export var slot_state := FightState.NONE
@export var slot_target_actor_id := ""
@export var slot_index := -1
@export var wait_index := -1
@export var slot_angle := 0.0
@export var pair_anchor_position := Vector3.ZERO
@export var pair_axis := Vector3.RIGHT
@export var slot_position := Vector3.ZERO
@export var wait_position := Vector3.ZERO
@export var engage_distance := 1.0
@export var min_pair_distance := 0.85
@export var max_pair_distance := 1.22
@export var leash_distance := 1.8
@export var state_seconds := 0.0
@export var tempo_actor_id := ""
@export var tempo_wait_remaining := 0.0

# Projection-local route/reservation scratch. Revalidated after load or LOD;
# a saved slot ID never proves that a live standing position is still usable.
var position_valid := false
var position_target_origin := Vector3.ZERO
var position_recheck_remaining := 0.0
var position_search_cursor := 0


func clear() -> void:
	slot_state = FightState.NONE
	slot_target_actor_id = ""
	slot_index = -1
	wait_index = -1
	slot_angle = 0.0
	pair_anchor_position = Vector3.ZERO
	pair_axis = Vector3.RIGHT
	slot_position = Vector3.ZERO
	wait_position = Vector3.ZERO
	engage_distance = 1.0
	min_pair_distance = 0.85
	max_pair_distance = 1.22
	leash_distance = 1.8
	state_seconds = 0.0
	tempo_actor_id = ""
	tempo_wait_remaining = 0.0
	position_valid = false
	position_target_origin = Vector3.ZERO
	position_recheck_remaining = 0.0
	position_search_cursor = 0


func is_active() -> bool:
	return slot_state == FightState.FIGHTING


func is_waiting() -> bool:
	return slot_state == FightState.WAITING
