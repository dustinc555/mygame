extends "res://addons/gecs/ecs/component.gd"

class_name CGameWorldSimSquad

## A squad that exists in the world sim as cheap data with a real world-space
## position. Any owner (nest/town/faction) can create one. While outside the LOD
## ring it is advanced O(1) by WorldSimSquadController; the realize/derealize swap
## to live bodies is a later step. The owner sets the objective (per-faction
## behavior); the mover just transports toward target_position.

@export var squad_id := ""
@export var owner_id := ""
@export var owner_kind := ""
@export var faction_id := ""
@export var objective := "patrol"
@export var target_settlement_id := ""
@export var position := Vector3.ZERO
@export var target_position := Vector3.ZERO
@export var home_position := Vector3.ZERO
@export var patrol_radius := 40.0
@export var move_speed := 3.0
@export var member_count := 0
@export var state := "active"
## Encounter phase, set when the squad reaches a target and an encounter begins.
## "" = not in an encounter (travelling/patrolling); "demand"/"fight"/"aftermath" =
## driven by EncounterController through its grace windows. phase_timer counts down the
## current window; decision holds the defender leaning ("comply"/"refuse") then the
## fight verdict ("won"/"lost").
@export var phase := ""
@export var phase_timer := 0.0
@export var decision := ""


func apply_record(source: Dictionary) -> void:
	squad_id = str(source.get("squad_id", squad_id))
	owner_id = str(source.get("owner_id", owner_id))
	owner_kind = str(source.get("owner_kind", owner_kind))
	faction_id = str(source.get("faction_id", faction_id))
	objective = str(source.get("objective", objective))
	target_settlement_id = str(source.get("target_settlement_id", target_settlement_id))
	position = source.get("position", position)
	target_position = source.get("target_position", target_position)
	home_position = source.get("home_position", home_position)
	patrol_radius = maxf(float(source.get("patrol_radius", patrol_radius)), 0.0)
	move_speed = maxf(float(source.get("move_speed", move_speed)), 0.0)
	member_count = maxi(int(source.get("member_count", member_count)), 0)
	state = str(source.get("state", state))
	phase = str(source.get("phase", phase))
	phase_timer = maxf(float(source.get("phase_timer", phase_timer)), 0.0)
	decision = str(source.get("decision", decision))


func to_record() -> Dictionary:
	return {
		"squad_id": squad_id,
		"owner_id": owner_id,
		"owner_kind": owner_kind,
		"faction_id": faction_id,
		"objective": objective,
		"target_settlement_id": target_settlement_id,
		"position": position,
		"target_position": target_position,
		"home_position": home_position,
		"patrol_radius": patrol_radius,
		"move_speed": move_speed,
		"member_count": member_count,
		"state": state,
		"phase": phase,
		"phase_timer": phase_timer,
		"decision": decision,
	}
