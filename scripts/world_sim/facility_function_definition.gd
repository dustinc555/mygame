extends Resource

class_name FacilityFunctionDefinition

@export var function_id := ""
@export var display_name := "Facility Function"
@export_enum("generic", "housing", "farm", "mine", "bar", "shop", "storage", "guard", "social", "police", "weapon_shop", "armor_shop", "travel_shop", "potion_shop", "tavern") var facility_type := "generic"
@export_multiline var description := ""
@export var default_food_production_per_day := 0.0
@export var default_food_consumption_per_day := 0.0
@export var default_storage_capacity_bonus := 0.0
@export var expected_staff_roles: PackedStringArray = PackedStringArray()
@export var expected_service_points: PackedStringArray = PackedStringArray()
@export var expected_activity_types: PackedStringArray = PackedStringArray()


func get_id() -> String:
	return function_id if not function_id.is_empty() else display_name
