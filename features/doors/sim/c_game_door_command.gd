extends "res://addons/gecs/ecs/component.gd"

class_name CGameDoorCommand

enum Action {
	OPEN,
	CLOSE,
	LOCK,
	UNLOCK,
	LOCKPICK,
}

enum Phase {
	APPROACHING,
	PERFORMING,
	RESOLVED,
	FAILED,
	CANCELLED,
}

@export var command_id := ""
@export var door_id := ""
@export var actor_id := ""
@export var action := Action.OPEN
@export var phase := Phase.APPROACHING
@export var expected_state_revision := -1
@export var remaining_seconds := 0.0
@export var lockpick_skill_level := 0.0
@export var assisting_attribute_level := 0.0
@export var actor_faction_id := ""
@export var actor_key_ids := PackedStringArray()
@export var has_required_lockpick := false
@export var from_inside := false
@export var result_code := ""
@export var result_chance := 0.0
@export var result_roll := -1.0
@export var result_xp := 0.0
@export var lockpick_broke := false
