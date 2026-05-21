extends Resource

class_name SkillDefinition

@export var skill_id := ""
@export var display_name := "Skill"
@export var category_id := "misc"
@export var category_name := "Misc"
@export var sort_order := 0
@export var is_attribute := false
@export var default_level := 1
@export_multiline var description := ""
@export_multiline var training_hint := ""


func is_valid_definition() -> bool:
	return not skill_id.is_empty()
