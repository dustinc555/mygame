extends SceneTree

const DEFAULT_SHELL := "res://features/world/projection/buildings/shells/modular/medium_wood_hall.tscn"
const HOUSE_SHELL := "res://features/world/projection/buildings/shells/modular/small_wood_cottage.tscn"
const HOME_FUNCTION := "res://features/world_sim/resources/facility_functions/home.tres"
const HOME_RULES := "res://features/settlements/resources/furnishing/housing.tres"
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
	_validate_house_shell_shape()
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
		var expected_shell := HOUSE_SHELL if facility_id == "house" else DEFAULT_SHELL
		_expect(shell != null and shell.scene_file_path == expected_shell, "%s must author its expected CurrentBuilding shell" % facility_id)
		_expect(facility.get_node_or_null("Furniture") != null, "%s must have a Furniture root" % facility_id)
		if facility_id == "house":
			_expect(definition.get_display_name() == "Home" and definition.get_id() == "house", "Home must keep the stable house catalog ID")
			_expect(definition.function != null and definition.function.resource_path == HOME_FUNCTION, "Home catalog entry must expose the Home function")
			_expect(str(facility.get("display_name")) == "Home" and str(facility.get("facility_type")) == "housing", "Home template must expose its plugin-facing identity")
			_expect((facility.get("facility_function") as Resource).resource_path == HOME_FUNCTION, "Home template must author its function")
			_expect(int(facility.get("housing_capacity")) == 2, "Home function must provide capacity for two residents")
		elif facility_id == "bar":
			_expect(str(facility.door_access_policy) == "public" and facility.door_schedule_enabled and facility.door_initial_state == "open" and facility.doors_keep_open_during_hours, "Bar must explicitly author its public scheduled door policy")
		elif facility_id == "keep":
			_expect(str(facility.door_access_policy) == "private", "Keep must explicitly remain owner-private")
		facility.free()
	var field := load("%s/field.tres" % FACILITY_DIR) as Resource
	_expect(field != null and not field.catalog_enabled, "Field must be excluded from Add Facility")
	_validate_home_function_and_recipe()


func _validate_home_function_and_recipe() -> void:
	var home := load(HOME_FUNCTION) as Resource
	_expect(home != null and str(home.get("function_id")) == "home" and str(home.get("display_name")) == "Home", "Facility function picker must discover Home")
	_expect(home != null and str(home.get("facility_type")) == "housing" and int(home.get("default_housing_capacity")) == 2, "Home function must define housing capacity")
	var generic := (load("res://features/settlements/bridge/settlement_facility_instance.gd") as Script).new() as Node
	generic.set("housing_capacity", 0)
	generic.set("facility_function", home)
	_expect(str(generic.get("facility_type")) == "housing" and int(generic.get("housing_capacity")) == 2, "Assigning Home in the plugin must apply housing defaults")
	generic.free()
	var rules := load(HOME_RULES) as Resource
	_expect(rules != null and int(rules.get("min_beds")) == 2 and int(rules.get("min_shelves")) == 2 and int(rules.get("min_lights")) == 2, "Home furnishing must require one bed per resident, shelves, and torches")
	var utility_scenes: Array = rules.get("utility_scenes") if rules != null else []
	var required_clusters: Array = rules.get("required_cluster_scenes") if rules != null else []
	_expect(utility_scenes.size() == 1 and (utility_scenes[0] as Resource).resource_path.ends_with("chest_wood.tscn"), "Home furnishing must require storage")
	_expect(required_clusters.size() == 1 and (required_clusters[0] as Resource).resource_path.ends_with("table_cluster_4.tscn"), "Home furnishing must require a dining set")
	var dining := (required_clusters[0] as PackedScene).instantiate() if not required_clusters.is_empty() else null
	_expect(dining != null and dining.get_node_or_null("Table") != null and dining.get_node_or_null("ChairSouthLeft") != null and dining.get_node_or_null("ChairSouthRight") != null and dining.get_node_or_null("ChairNorthLeft") != null, "Home dining set must contain a table and chairs")
	if dining != null:
		dining.free()


func _validate_house_shell_shape() -> void:
	var cottage := (load(HOUSE_SHELL) as PackedScene).instantiate() as Node3D
	var pieces := cottage.get_node("Pieces")
	var category_counts := {}
	for child in pieces.get_children():
		var category := str(child.get("category"))
		category_counts[category] = int(category_counts.get(category, 0)) + 1
	_expect(int(category_counts.get("floor", 0)) == 24, "House shell must use the complete 10x8 rounded floor")
	_expect(int(category_counts.get("roof", 0)) == 54, "House shell must use a sealed rounded deck plus its complete wooden roof")
	_expect(int(category_counts.get("overhang", 0)) == 4, "House shell must use four curved wood-brick corners")
	_expect(int(category_counts.get("foundation", 0)) == 10, "House shell must use a complete below-floor foundation ring")
	_expect(int(category_counts.get("wall_window", 0)) == 3, "House shell must have exactly three windows")
	_expect(int(category_counts.get("shutter", 0)) == 0, "House shell must not add shutters to its flat windows")
	for window_name in ["FrontWindowWall", "EastWindowWall", "WestWindowWall"]:
		_expect(str(pieces.get_node(window_name).get("piece_id")) == "wall_woodbrick_window_wide_flat", "%s must use a flat square opening" % window_name)
	for frame_name in ["FrontWindowFrame", "EastWindowFrame", "WestWindowFrame"]:
		_expect(str(pieces.get_node(frame_name).get("piece_id")) == "window_frame_wide_flat", "%s must use a flat square frame" % frame_name)
	for corner_name in ["CornerBackEast", "CornerBackWest", "CornerFrontWest", "CornerFrontEast"]:
		_expect(str(pieces.get_node(corner_name).get("piece_id")) == "overhang_wood_brick_corner_front", "%s must use the jail-style curved corner" % corner_name)
	for corner_fill_name in ["FloorWedgeBackEast", "FloorHalfBackEast", "FloorWedgeBackWest", "FloorHalfBackWest", "FloorWedgeFrontWest", "FloorHalfFrontWest", "FloorWedgeFrontEast", "FloorHalfFrontEast", "RoofWedgeBackEast", "RoofHalfBackEast", "RoofWedgeBackWest", "RoofHalfBackWest", "RoofWedgeFrontWest", "RoofHalfFrontWest", "RoofWedgeFrontEast", "RoofHalfFrontEast"]:
		_expect(pieces.get_node_or_null(corner_fill_name) != null, "House rounded surface missing %s" % corner_fill_name)
	var roof_center_count := 0
	var roof_corner_count := 0
	for child in pieces.get_children():
		roof_center_count += 1 if str(child.get("piece_id")) == "roof_wooden_2x_1_center" else 0
		roof_corner_count += 1 if str(child.get("piece_id")) == "roof_wooden_2x_1_corner" else 0
	_expect(roof_center_count == 14 and roof_corner_count == 4, "House must use fourteen wooden roof centers and four wooden roof corners")
	for cap_name in ["RoofCapBackFarWest", "RoofCapMiddleFarWest", "RoofCapFrontFarWest", "RoofCapBackWest", "RoofCapMiddleWest", "RoofCapFrontWest", "RoofCapBackEast", "RoofCapMiddleEast", "RoofCapFrontEast", "RoofCapBackFarEast", "RoofCapMiddleFarEast", "RoofCapFrontFarEast"]:
		_expect(pieces.get_node_or_null(cap_name) != null, "House roof cap missing %s" % cap_name)
	var cap_rows := {-2: 0, 0: 0, 2: 0}
	for child in pieces.get_children():
		if child.name.begins_with("RoofCap"):
			var row := roundi(child.position.z)
			cap_rows[row] = int(cap_rows.get(row, 0)) + 1
	_expect(cap_rows == {-2: 4, 0: 4, 2: 4}, "House roof cap must seal all three rows through the wooden slopes")
	_expect(pieces.get_node_or_null("RoofOutline") == null and pieces.get_node_or_null("RoofSeal") == null, "House must delete the failed mansard roof")
	_expect(is_equal_approx(pieces.get_node("EastWindowWall").position.x, 4.9) and is_equal_approx(pieces.get_node("WestWindowWall").position.x, -4.9), "House width must remain exactly ten meters")
	_expect(is_equal_approx(pieces.get_node("FrontWindowWall").position.z, 3.9) and is_equal_approx(pieces.get_node("BackWallEast").position.z, -3.9), "House depth must remain exactly eight meters")
	_expect(pieces.get_node("FoundationFrontDoor").position.y < pieces.get_node("FoundationFrontEast").position.y, "House doorway foundation must stay lowered below the stair threshold")
	var door_frame := pieces.get_node("FrontDoorFrame")
	_expect(bool(door_frame.get("disable_model_collision")) and bool(door_frame.get("strip_model_collision_shapes")), "House door frame must not seal the runtime nav opening")
	cottage.free()


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
	var dock := (load(FACILITY_DOCK) as Script).new() as Control
	_expect(Array(dock.call("_scan_function_paths")).has(HOME_FUNCTION), "Facility dock function picker must scan Home")
	dock.free()
	var facility_tools := (load(FACILITY_TOOLS) as Script).new(null) as RefCounted
	_expect(Array(facility_tools.call("get_shell_catalog")).has(HOUSE_SHELL), "Facility shell picker must scan Small Wood Cottage")
	facility_tools.call("teardown")
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
	_expect(tools_text.contains("_stamp_furniture_ids") and tools_text.contains("node.set(\"container_id\""), "generated containers must receive stable facility-scoped IDs before placement")
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
