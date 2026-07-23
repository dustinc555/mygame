extends SceneTree

const DEFAULT_SHELL := "res://features/world/projection/buildings/shells/modular/medium_wood_hall.tscn"
const FACILITY_IDS := ["bar", "jail", "keep", "house"]
const FACILITY_DIR := "res://features/settlements/resources/facilities"
const TOWN_TOOLS := "res://addons/world_authoring/town_tools.gd"
const FACILITY_TOOLS := "res://addons/world_authoring/facility_tools.gd"
const FACILITY_DOCK := "res://addons/world_authoring/facility_dock.gd"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_catalog_and_templates()
	_validate_stable_identity_helper()
	_validate_runtime_stamping_and_empty_shell()
	_validate_plugin_contracts()
	_validate_construction_migration_contracts()
	_finish()


func _validate_catalog_and_templates() -> void:
	for facility_id in FACILITY_IDS:
		var definition := load("%s/%s.tres" % [FACILITY_DIR, facility_id]) as Resource
		_expect(definition != null and definition.catalog_enabled, "%s must be catalog-enabled" % facility_id)
		_expect(definition != null and int(definition.shell_policy) == 0, "%s must use the global default shell policy" % facility_id)
		var scene := load(definition.scene_path) as PackedScene
		var facility := scene.instantiate() if scene != null else null
		_expect(facility != null and facility.has_method("get_building_root"), "%s must use a composed facility template" % facility_id)
		if facility == null:
			continue
		var slot: Node = facility.call("get_building_root")
		var shell: Node = slot.get_child(0) if slot != null and slot.get_child_count() == 1 else null
		_expect(shell != null and shell.scene_file_path == DEFAULT_SHELL, "%s must author medium_wood_hall as CurrentBuilding" % facility_id)
		_expect(facility.get_node_or_null("Furniture") != null, "%s must have a Furniture root" % facility_id)
		if facility_id == "bar":
			_expect(str(facility.door_access_policy) == "public" and facility.door_schedule_enabled and facility.door_initial_state == "open" and facility.doors_keep_open_during_hours, "Bar must explicitly author its public scheduled door policy")
		elif facility_id == "keep":
			_expect(str(facility.door_access_policy) == "private", "Keep must explicitly remain owner-private")
		facility.free()
	var field := load("%s/field.tres" % FACILITY_DIR) as Resource
	_expect(field != null and not field.catalog_enabled, "Field must be excluded from Add Facility")


func _validate_stable_identity_helper() -> void:
	var tools := load(TOWN_TOOLS)
	var parent := Node.new()
	var first: Dictionary = tools.call("facility_identity_for", parent, "canyon", "keep")
	_expect(first == {"node_name": "Keep", "facility_id": "canyon.keep", "building_id": "canyon.keep.building"}, "first Keep identity must derive from FacilityDefinition.get_id()")
	var existing := Node.new()
	existing.name = "Keep"
	parent.add_child(existing)
	var second: Dictionary = tools.call("facility_identity_for", parent, "canyon", "keep")
	_expect(second == {"node_name": "Keep2", "facility_id": "canyon.keep2", "building_id": "canyon.keep2.building"}, "second Keep identity must be deterministic")
	parent.free()


func _validate_runtime_stamping_and_empty_shell() -> void:
	var town := (load("res://features/settlements/bridge/settlement_town.tscn") as PackedScene).instantiate()
	town.set("settlement_definition", load("res://features/world_sim/resources/settlements/canyon.tres"))
	var house := (load("res://features/settlements/bridge/settlement_house.tscn") as PackedScene).instantiate()
	house.name = "House"
	house.facility_id = "canyon.house"
	house.building_id = "canyon.house.building"
	house.owner_faction_id = "ValidationFaction"
	town.add_child(house)
	house.stamp_building_identity()
	var slot: Node = house.call("get_building_root")
	var shell: Node = slot.get_child(0)
	_expect(shell.building_id == "canyon.house.building", "shell must receive building identity")
	_expect(shell.facility_id == "canyon.house", "shell must receive facility identity")
	_expect(shell.settlement_id == "canyon", "shell must receive settlement identity")
	_expect(shell.building_type == "housing", "neutral shell generic type must not leak into an assigned facility")
	_expect(shell.owner_faction_id == "ValidationFaction", "shell must receive effective facility owner")
	_expect(shell.access_state == "private", "shell must receive facility door access policy")
	_expect(not shell.public_schedule_enabled and shell.public_open_hour == 8 and shell.public_close_hour == 21, "shell must receive facility door schedule policy")
	_expect(shell.housing_capacity == 2, "housing capacity must come from House composition")
	slot.remove_child(shell)
	shell.free()
	house.call("_repair_authoring_tree")
	_expect(slot.get_child_count() == 0, "an empty BuildingSlot must remain valid and not regenerate")
	town.free()

	var neutral := (load(DEFAULT_SHELL) as PackedScene).instantiate()
	_expect(neutral.building_id.is_empty() and neutral.facility_id.is_empty() and neutral.settlement_id.is_empty(), "neutral shell must not author durable identity")
	_expect(neutral.building_type == "generic" and neutral.owner_faction_id.is_empty() and neutral.housing_capacity == 0, "neutral shell must not author function, owner, or housing semantics")
	neutral.free()


func _validate_plugin_contracts() -> void:
	_expect(load(FACILITY_TOOLS) != null, "facility_tools.gd must compile")
	_expect(load(FACILITY_DOCK) != null, "facility_dock.gd must compile")
	var tools_text := FileAccess.get_file_as_string(FACILITY_TOOLS)
	var dock_text := FileAccess.get_file_as_string(FACILITY_DOCK)
	_expect(not tools_text.contains("func _swap_facility_node"), "raw facility swap path must be deleted")
	_expect(tools_text.contains("facility.stamp_building_node_identity(fresh)"), "fresh shell swap must stamp facility identity")
	_expect(tools_text.contains("Remove Facility Shell"), "No Shell removal must use UndoRedo")
	_expect(tools_text.contains("_append_clear_furniture_undo"), "swap and No Shell must share furniture cleanup")
	_expect(tools_text.contains("get_node_or_null(\"GuardPosts\")") and tools_text.contains("GUARD_POST_SCENE.instantiate()"), "hand-placed guard stand spots must remain under GuardPosts")
	_expect(dock_text.contains("button_pressed = true"), "Clear old furniture default must remain true")
	_expect(dock_text.contains("no_shell.text = \"No Shell\""), "shell picker must expose No Shell")
	_expect(dock_text.contains("_section_title(\"Door Policy\")") and dock_text.contains("Private (owner)") and dock_text.contains("Initial State") and dock_text.contains("Door Default") and dock_text.contains("Discovered Doors"), "Facility dock must expose visible door policy and discovered doors")
	_expect(not dock_text.contains("_cluster_browser") and not dock_text.contains("_build_cluster_column") and not dock_text.contains("_section_title(\"Clusters\")"), "manual facility authoring must not expose cluster controls")
	_expect(not tools_text.contains("\"res://features/world/projection/props/furnishing/vignettes\","), "manual furniture catalog must not scan furnisher vignettes")
	_expect(tools_text.contains("node is FurnitureVignette") and not tools_text.contains("bool(node.get(\"unpack_on_furnish\"))"), "editor furnish must use typed vignette unpacking")
	var town_tools_text := FileAccess.get_file_as_string(TOWN_TOOLS)
	_expect(town_tools_text.contains("definition.catalog_enabled"), "TownTools catalog must filter disabled definitions")
	_expect(town_tools_text.count("_apply_facility_identity(facility, town, definition)") == 2, "direct-file and live add paths must share facility identity helper")


func _validate_construction_migration_contracts() -> void:
	var world_text := FileAccess.get_file_as_string("res://features/core/gecs_world_controller.gd")
	var realizer_text := FileAccess.get_file_as_string("res://features/settlements/bridge/construction_realizer.gd")
	_expect(world_text.contains("\"woodbrick_house\": \"medium_wood_l_hall\""), "load boundary must migrate woodbrick_house")
	_expect(world_text.find("_migrate_loaded_construction_catalog_ids(entities)") < world_text.find("_clear_world_entities()"), "construction catalog migration must run at deserialize boundary")
	_expect(realizer_text.contains("cannot realize unknown catalog id") and not realizer_text.contains("UNKNOWN_CATALOG_FALLBACK_SCENE"), "unknown construction IDs must fail instead of realizing a false fallback shell")
	_expect(realizer_text.contains("registry_rebuilt.connect(_reconcile_realized_records)"), "constructed projections must reconcile after save load")
	var projection_text := FileAccess.get_file_as_string("res://features/world/bridge/building_projection_bridge.gd")
	_expect(projection_text.contains("if not bool(_imports_seed_by_id.get(clean_id, false))"), "constructed registry rebuilds must remain owned by ConstructionRealizer")
	var placeable := load("res://features/settlements/resources/buildings/medium_wood_l_hall_placeable.tres") as Resource
	_expect(placeable != null and str(placeable.get("type_id")) == "housing" and int(placeable.get("housing_capacity")) == 2, "player construction housing assignment must remain separate from neutral shell metadata")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("FACILITY_SHELL_WORKFLOW_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("FACILITY_SHELL_WORKFLOW_FAILED count=%d" % _failures.size())
	quit(1)
