extends "res://addons/gecs/ecs/component.gd"

class_name CGameCombatEvent

enum Type {
	ATTACK_STARTED,
	RESPONSE_AUTHORIZED,
	RESPONSE_REVOKED,
}

enum Audience {
	SOCIAL,
	SETTLEMENT_AUTHORITY,
	EXPLICIT_ACTORS,
}

@export var event_id := ""
@export var sequence := 0
@export var type := Type.ATTACK_STARTED
@export var audience := Audience.SOCIAL
@export var attacker_actor_id := ""
@export var protected_actor_id := ""
@export var target_actor_id := ""
@export var encounter_id := ""
@export var authority_id := ""
@export var authority_faction_id := ""
@export var settlement_id := ""
@export var origin := Vector3.ZERO
@export var radius := 0.0
@export var response_depth := 0
@export var response_kind := 0
@export var authorized_response := false
@export var explicit_responder_actor_ids: PackedStringArray = PackedStringArray()
