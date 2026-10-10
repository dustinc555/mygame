extends "res://addons/gecs/ecs/component.gd"

class_name CGameCombatEncounter

@export var encounter_id := ""
@export var sequence := 0
@export var origin := Vector3.ZERO
@export var remaining_ticks := 0
@export var root_aggressor_actor_id := ""
@export var root_defender_actor_id := ""
@export var aggressor_side_actor_ids: PackedStringArray = PackedStringArray()
@export var defender_side_actor_ids: PackedStringArray = PackedStringArray()
@export var committed_actor_ids: PackedStringArray = PackedStringArray()
@export var aggression_target_by_actor: Dictionary = {}
## Rights belong to the attacked party/squad, not transient tactical sides.
## They expire with this encounter and survive the original victim going down.
@export var defense_group_pairs: Dictionary = {}
@export var aggression_records: Dictionary = {}
@export var disengaged_targets_by_actor: Dictionary = {}
## Local aid is directed at an attacker, independent of a battle's two sides.
## A third party can be attacked without becoming allied to either old side.
@export var assistance_targets_by_actor: Dictionary = {}


func side_of(actor_id: String) -> int:
	if aggressor_side_actor_ids.has(actor_id):
		return 1
	if defender_side_actor_ids.has(actor_id):
		return 2
	return 0


func add_to_side(actor_id: String, side: int) -> void:
	if actor_id.is_empty() or side == 0:
		return
	remove_actor(actor_id)
	var members := aggressor_side_actor_ids if side == 1 else defender_side_actor_ids
	members.append(actor_id)
	members.sort()
	if side == 1:
		aggressor_side_actor_ids = members
	else:
		defender_side_actor_ids = members


func mark_committed(actor_id: String) -> void:
	if not actor_id.is_empty() and not committed_actor_ids.has(actor_id):
		committed_actor_ids.append(actor_id)
		committed_actor_ids.sort()


func mark_aggression(attacker_actor_id: String, target_actor_id: String, context: Dictionary = {}) -> bool:
	var key := "%s|%s|%s" % [attacker_actor_id, target_actor_id, context.get("legal_reason", "")]
	var previous: Dictionary = aggression_records.get(key, {})
	if attacker_actor_id.is_empty() or target_actor_id.is_empty() or (not previous.is_empty() and (previous.get("settled_factions", []) as Array).is_empty()):
		return false
	aggression_target_by_actor[attacker_actor_id] = target_actor_id
	var record := context.duplicate(true)
	record.merge({"pair_key": key, "attacker_actor_id": attacker_actor_id, "protected_actor_id": target_actor_id, "origin": origin, "encounter_id": encounter_id}, true)
	aggression_records[key] = record
	return true


func remove_actor(actor_id: String) -> void:
	var aggressors := aggressor_side_actor_ids
	var defenders := defender_side_actor_ids
	var committed := committed_actor_ids
	if aggressors.has(actor_id):
		aggressors.remove_at(aggressors.find(actor_id))
	if defenders.has(actor_id):
		defenders.remove_at(defenders.find(actor_id))
	if committed.has(actor_id):
		committed.remove_at(committed.find(actor_id))
	aggressor_side_actor_ids = aggressors
	defender_side_actor_ids = defenders
	committed_actor_ids = committed
	aggression_target_by_actor.erase(actor_id)
