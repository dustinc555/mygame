@tool
extends Resource

class_name FacilityRoleSlotDefinition

@export var slot_id := ""
@export var role: FacilityRoleDefinition
@export var named_character: CharacterRecordDefinition
@export var character_type_id := ""
@export var display_name := ""
@export_range(0, 10, 1) var population_cost := 1
@export_range(0.0, 365.0, 0.25) var replacement_delay_days := 7.0
@export var authority_scope := "facility_staff"


func to_slot_spec(facility_id: String) -> Dictionary:
	var local_slot_id := slot_id.strip_edges().to_lower()
	var role_id := role.get_id() if role != null else ""
	if local_slot_id.is_empty() or role_id.is_empty():
		push_error("FacilityRoleSlotDefinition requires stable slot_id and role")
		return {}
	var actor_id := named_character.actor_id.strip_edges() if named_character != null else ""
	var character_path := named_character.resource_path if named_character != null else ""
	var effective_display_name := display_name.strip_edges()
	if effective_display_name.is_empty() and named_character != null:
		effective_display_name = named_character.member_name.strip_edges()
	if effective_display_name.is_empty():
		effective_display_name = role.get_display_name()
	var effective_type_id := character_type_id.strip_edges().to_lower()
	if effective_type_id.is_empty():
		effective_type_id = role.default_character_type_id.strip_edges().to_lower()
	return {
		"slot_id": "%s.%s" % [facility_id.strip_edges(), local_slot_id],
		"assignment_domain": role.assignment_domain,
		"assignment_exclusivity_group": role.assignment_exclusivity_group,
		"role_id": role_id,
		"uses_settlement_jobs": role.uses_settlement_jobs,
		"allowed_job_entry_ids": role.allowed_job_entry_ids,
		"preferred_actor_id": actor_id,
		"preferred_character_path": character_path,
		"character_type_id": effective_type_id,
		"display_name": effective_display_name,
		"population_cost": maxi(0, population_cost),
		"replacement_delay_days": maxf(0.0, replacement_delay_days),
		"authority_scope": authority_scope.strip_edges(),
	}
