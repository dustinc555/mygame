extends Resource

class_name SkillCatalog

@export var definitions: Array[Resource] = []


func get_definitions() -> Array[SkillDefinition]:
	var typed_definitions: Array[SkillDefinition] = []
	for definition in definitions:
		if definition is SkillDefinition and (definition as SkillDefinition).is_valid_definition():
			typed_definitions.append(definition as SkillDefinition)
	typed_definitions.sort_custom(_sort_definitions)
	return typed_definitions


func get_definition(skill_id: String) -> SkillDefinition:
	for definition in definitions:
		if definition is SkillDefinition and (definition as SkillDefinition).skill_id == skill_id:
			return definition as SkillDefinition
	return null


func _sort_definitions(a: SkillDefinition, b: SkillDefinition) -> bool:
	if a.category_id == b.category_id:
		if a.sort_order == b.sort_order:
			return a.skill_id < b.skill_id
		return a.sort_order < b.sort_order
	if a.is_attribute != b.is_attribute:
		return a.is_attribute
	return a.category_id < b.category_id
