extends Resource

class_name PopulationRecordDefinition

@export var actor_id := ""
@export var stable_id := ""
@export var settlement_id := ""
@export var generation_source := "authored"
@export var generation_index := 0
@export var member_name := ""
@export var faction_id := ""
@export var squad_name := ""
@export var role_id := "party_member"
@export var party_id := ""
@export var player_party_member := false
@export var player_controllable := false
@export var projection_kind := "humanoid"
@export var hostile_faction_ids: PackedStringArray = PackedStringArray()
@export var combat_stance := 1
@export var base_color := Color(0.62, 0.62, 0.62, 1.0)
@export var skill_levels: Dictionary = {}
@export var traits: Dictionary = {}
@export var personality: Dictionary = {}
@export var life_state := 0
@export var hp := 100.0
@export var max_hp := 100.0
@export var blood := 5.0
@export var max_blood := 5.0
@export var base_attack_damage := 0.0
@export var base_dodge_chance := 0.0
@export var base_block_chance := 0.0
@export var realization_state := "ledger"
@export var ledger_activity_state := "routine"
@export var ledger_minutes_elapsed := 0
@export var ledger_work_minutes := 0
@export var ledger_rest_minutes := 0
@export var ledger_activity_minutes: Dictionary = {}
@export var last_ledger_absolute_minute := -1
@export var last_world_position := Vector3.ZERO
@export var last_world_position_initialized := false
@export var important := false
@export var appearance: Dictionary = {}
@export var equipment_slots: Dictionary = {}
@export var inventory_entries: Array = []


func get_id() -> String:
	return actor_id if not actor_id.is_empty() else stable_id


func to_record() -> Dictionary:
	var id := get_id().strip_edges()
	return {
		"actor_id": id,
		"stable_id": stable_id if not stable_id.strip_edges().is_empty() else id,
		"settlement_id": settlement_id,
		"generation_source": generation_source,
		"generation_index": generation_index,
		"member_name": member_name,
		"faction_id": faction_id,
		"squad_name": squad_name,
		"role_id": role_id,
		"party_id": party_id,
		"player_party_member": player_party_member,
		"player_controllable": player_controllable,
		"projection_kind": projection_kind,
		"hostile_faction_ids": Array(hostile_faction_ids),
		"combat_stance": combat_stance,
		"base_color": base_color,
		"skill_levels": skill_levels.duplicate(true),
		"traits": traits.duplicate(true),
		"personality": personality.duplicate(true),
		"life_state": life_state,
		"hp": hp,
		"max_hp": max_hp,
		"blood": blood,
		"max_blood": max_blood,
		"base_attack_damage": base_attack_damage,
		"base_dodge_chance": base_dodge_chance,
		"base_block_chance": base_block_chance,
		"realization_state": realization_state,
		"ledger_activity_state": ledger_activity_state,
		"ledger_minutes_elapsed": ledger_minutes_elapsed,
		"ledger_work_minutes": ledger_work_minutes,
		"ledger_rest_minutes": ledger_rest_minutes,
		"ledger_activity_minutes": ledger_activity_minutes.duplicate(true),
		"last_ledger_absolute_minute": last_ledger_absolute_minute,
		"last_world_position": last_world_position,
		"last_world_position_initialized": last_world_position_initialized,
		"important": important,
		"appearance": appearance.duplicate(true),
		"equipment_slots": equipment_slots.duplicate(true),
		"inventory_entries": inventory_entries.duplicate(true),
	}
