extends SceneTree

const CANYON_DEFINITION_PATH := "res://features/world_sim/resources/settlements/canyon.tres"
const KEEP_DEFINITION_PATH := "res://features/settlements/resources/facilities/keep.tres"
const KEEP_RULES_PATH := "res://features/settlements/resources/furnishing/keep.tres"
const TOWN_TOOLS_PATH := "res://addons/world_authoring/town_tools.gd"
const DEFAULT_SHELL := "res://features/world/projection/buildings/shells/modular/medium_wood_hall.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var canyon_definition := load(CANYON_DEFINITION_PATH) as SettlementDefinition
	var keep_definition := load(KEEP_DEFINITION_PATH) as FacilityDefinition
	var keep_rules := load(KEEP_RULES_PATH) as FurnishRules
	var town_tools := load(TOWN_TOOLS_PATH)
	var town := (load("res://features/settlements/bridge/settlement_town.tscn") as PackedScene).instantiate()
	town.name = "Canyon"
	town.set("settlement_definition", canyon_definition)
	root.add_child(town)
	var keep_scene := load(keep_definition.scene_path) as PackedScene
	var keep := keep_scene.instantiate() if keep_scene != null else null
	_expect(keep != null, "Keep catalog template must instantiate")
	if keep == null:
		_finish()
		return
	town_tools._apply_facility_identity(keep, town, keep_definition)
	town.add_child(keep)
	_expect(keep.name == "Keep", "Add Facility must name the first Canyon Keep 'Keep'")
	_expect(str(keep.get("facility_id")) == "canyon.keep", "Canyon Keep facility_id must be canyon.keep")
	_expect(str(keep.get("building_id")) == "canyon.keep.building", "Canyon Keep building_id must be canyon.keep.building")
	_expect(str(keep.call("get_property_owner_faction")) == canyon_definition.get_faction_id(), "Canyon Keep must inherit Canyon's faction")
	var shell := keep.get_node_or_null("BuildingSlot/CurrentBuilding")
	_expect(shell != null and shell.scene_file_path == DEFAULT_SHELL, "Canyon Keep must begin with the global default shell")
	if shell != null:
		_expect(str(shell.get("building_id")) == "canyon.keep.building", "Default shell must receive Canyon Keep building identity")
		_expect(str(shell.get("settlement_id")) == "canyon", "Default shell must receive Canyon settlement identity")
		_expect(str(shell.get("facility_id")) == "canyon.keep", "Default shell must receive Canyon Keep facility identity")
		_expect(str(shell.get("building_type")) == "keep", "Default shell must receive Keep function type")
		_expect(str(shell.get("owner_faction_id")) == canyon_definition.get_faction_id(), "Default shell must receive Canyon owner faction")
	var furniture := keep.get_node_or_null("Furniture")
	_expect(furniture != null and furniture.get_child_count() == 0, "New Canyon Keep must start unfurnished")
	_expect(keep_rules.required_cluster_scenes.size() == 1, "Keep Furnish must require one ruler office")
	_expect(keep_rules.utility_scenes.is_empty(), "Keep Furnish must not generate guard stand spots")
	_expect(keep.get_node_or_null("GuardPosts/GuardPost") != null and keep.get_node_or_null("GuardPosts/GuardPost2") != null, "New Canyon Keep must retain authored guard stand spots")
	var second := keep_scene.instantiate()
	town_tools._apply_facility_identity(second, town, keep_definition)
	town.add_child(second)
	_expect(second.name == "Keep2", "Second Canyon Keep must be named Keep2")
	_expect(str(second.get("facility_id")) == "canyon.keep2", "Second Canyon Keep ID must be canyon.keep2")
	town.queue_free()
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("CANYON_ADD_KEEP_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("CANYON_ADD_KEEP_FAILED count=%d" % _failures.size())
	quit(1)
