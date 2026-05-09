extends Resource

class_name ItemStatModifier

@export var stat_name := ""
@export var add := 0.0
@export var mul := 1.0


func to_modifier_dictionary() -> Dictionary:
	return {
		"stat": stat_name,
		"add": add,
		"mul": mul,
	}
