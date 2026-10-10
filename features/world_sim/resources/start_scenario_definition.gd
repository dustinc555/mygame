@tool
extends Resource

class_name StartScenarioDefinition

## Initial conditions for a new game only. Saved population records take over
## after creation; editing this resource never resets an existing campaign.
@export var scenario_id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var squad_name := ""
@export var faction_id := "Player"
@export var characters: Array[CharacterRecordDefinition] = []
## Metres in the owning WorldRoot's local coordinates (standalone scene otherwise).
@export var spawn_position := Vector3.ZERO
@export_range(0.1, 20.0, 0.1, "or_greater", "suffix:m") var member_spacing_meters := 1.8
@export var member_colors := PackedColorArray()
@export var hostile_faction_ids := PackedStringArray()
@export var combat_stance: NpcRules.CombatStance = NpcRules.CombatStance.DEFENSIVE

func validation_error() -> String:
	if scenario_id.strip_edges().is_empty():
		return "Start scenario needs an ID."
	if squad_name.strip_edges().is_empty() or squad_name.strip_edges().to_lower() in ["all", "default"]:
		return "Start scenario needs a named squad."
	if faction_id.strip_edges().is_empty():
		return "Start scenario needs a faction."
	if characters.is_empty():
		return "Start scenario needs at least one character."
	if not spawn_position.is_finite() or not is_finite(member_spacing_meters) or member_spacing_meters <= 0.0:
		return "Start scenario needs a finite position and positive member spacing."
	var seen := {}
	for character in characters:
		if character == null or character.actor_id.strip_edges().is_empty():
			return "Every starting character needs an actor ID."
		var actor_id := character.actor_id.strip_edges()
		if seen.has(actor_id):
			return "Starting character appears twice: %s" % actor_id
		seen[actor_id] = true
	return ""

func create_records(world_transform := Transform3D.IDENTITY) -> Array[Dictionary]:
	var error := validation_error()
	if not error.is_empty():
		push_error(error)
		return []
	var records: Array[Dictionary] = []
	for index in characters.size():
		var record := characters[index].to_record()
		var offset := Vector3(0.0, 0.0, (float(index) - float(characters.size() - 1) * 0.5) * member_spacing_meters)
		var position: Vector3 = world_transform * (spawn_position + offset)
		record.merge({
			"stable_id": record["actor_id"], "party_id": PartyManager.PLAYER_PARTY_ID,
			"actor_script_path": "res://features/core/party/party_member.gd",
			"faction_id": faction_id.strip_edges(), "squad_name": squad_name.strip_edges(),
			"hostile_faction_ids": Array(hostile_faction_ids), "combat_stance": combat_stance,
			"role_id": "player_party", "life_state": NpcRules.LifeState.ALIVE,
			"realization_state": "ledger", "last_world_position": position,
			"last_world_position_initialized": true, "important": true,
		}, true)
		if index < member_colors.size():
			record["base_color"] = member_colors[index]
		records.append(record)
	return records
