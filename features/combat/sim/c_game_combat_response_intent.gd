extends "res://addons/gecs/ecs/component.gd"

class_name CGameCombatResponseIntent

enum Kind {
	SOCIAL_DEFENSE,
	LAW_ENFORCEMENT,
	PRIVATE_DEFENSE,
}

@export var intent_id := ""
@export var sequence := 0
@export var kind := Kind.SOCIAL_DEFENSE
@export var responder_actor_id := ""
@export var target_actor_id := ""
@export var authority_id := ""
@export var response_depth := 0
@export var remaining_ticks := 0
