@tool
extends Resource

class_name FacilityDefinition

## Catalog entry for a placeable settlement facility. The world_authoring
## Town tools scan a directory of these to build the placement catalog, and
## the authoring preview reads role slots from the facility scene template to
## compute a town's day-zero demand table. Adding a facility type is
## authoring a .tres, never editing plugin code.
##
## The gameplay function (economy rates and venue capabilities) stays on the linked
## FacilityFunctionDefinition. scene_path is a facility function/composition
## template, never a neutral building shell.

enum ShellPolicy {
	DEFAULT,
	NONE,
}

@export var facility_id := ""
@export var display_name := ""
@export_file("*.tscn") var scene_path := ""
@export var icon: Texture2D
@export var catalog_enabled := true
## New compositions receive the one global default shell unless explicitly
## authored as shell-less. No facility owns a shell path.
@export_enum("Default", "None") var shell_policy: int = ShellPolicy.DEFAULT
## FacilityFunctionDefinition this composition provides.
@export var function: Resource
@export_enum("shell", "housing") var category := "shell"
func get_id() -> String:
	if not facility_id.strip_edges().is_empty():
		return facility_id
	return scene_path.get_file().get_basename()


func get_display_name() -> String:
	if not display_name.strip_edges().is_empty():
		return display_name
	return get_id().capitalize()


func get_category() -> String:
	var function_definition := function as FacilityFunctionDefinition
	if function_definition != null:
		return function_definition.facility_type
	return category


func get_default_assignment_slot_specs() -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	if scene_path.is_empty():
		return specs
	var scene := load(scene_path) as PackedScene
	var facility := scene.instantiate() if scene != null else null
	if facility != null and facility.has_method("get_assignment_slot_specs"):
		for slot in facility.call("get_assignment_slot_specs"):
			specs.append((slot as Dictionary).duplicate(true))
	if facility != null:
		facility.free()
	return specs


func get_total_assignment_demand() -> int:
	var total := 0
	for slot in get_default_assignment_slot_specs():
		total += maxi(0, int(slot.get("population_cost", 1)))
	return total
