@tool
extends Resource

class_name FacilityRoleDefinition

@export var role_id := ""
@export var display_name := "Role"
@export_enum("employment", "residence") var assignment_domain := "employment"
## "default" delegates role-to-type selection to the effective CharacterTypeSet.
@export var default_character_type_id := "default"
@export_enum("employment", "residence") var assignment_exclusivity_group := "employment"
@export var uses_settlement_jobs := false
## Empty means every JobSystem category the actor is otherwise eligible for.
@export var allowed_job_entry_ids := PackedStringArray()


func get_id() -> String:
	return role_id.strip_edges().to_lower()


func get_display_name() -> String:
	return display_name if not display_name.strip_edges().is_empty() else get_id().capitalize()
