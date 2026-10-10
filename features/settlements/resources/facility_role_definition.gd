@tool
extends Resource

class_name FacilityRoleDefinition

const WORK_SCHEDULE = preload("res://features/settlements/resources/work_schedule.gd")

@export var role_id := ""
@export var display_name := "Role"
@export_enum("employment", "residence", "custody") var assignment_domain := "employment"
## "default" delegates role-to-type selection to the effective CharacterTypeSet.
@export var default_character_type_id := "default"
@export_enum("employment", "residence", "custody") var assignment_exclusivity_group := "employment"
@export var uses_settlement_jobs := false
## Shared by town occupations and facility staff. Override for night shifts;
## door opening hours do not determine employment hours.
@export var work_schedule: WORK_SCHEDULE = preload("res://features/settlements/resources/default_work_schedule.tres")
## Empty means every JobSystem category the actor is otherwise eligible for.
@export var allowed_job_entry_ids := PackedStringArray()
## Optional durable skill used when a town batch chooses the best available
## unemployed resident for this occupation.
@export var preferred_skill_id := ""


func get_id() -> String:
	return role_id.strip_edges().to_lower()


func get_work_schedule_record() -> Dictionary:
	var schedule := work_schedule if work_schedule != null else preload("res://features/settlements/resources/default_work_schedule.tres")
	return schedule.to_record()


func get_display_name() -> String:
	return display_name if not display_name.strip_edges().is_empty() else get_id().capitalize()
