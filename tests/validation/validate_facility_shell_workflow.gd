extends "res://tests/validation/test_case.gd"

## Generic composition and authoring contracts, not a golden building design.
## Counts below describe controlled fixtures, never a production cottage layout.
const FACILITY_DIR := "res://features/settlements/resources/facilities"
const TOWN_TOOLS := "res://addons/world_authoring/town_tools.gd"
const FACILITY_TOOLS := "res://addons/world_authoring/facility_tools.gd"
const FACILITY_DOCK := "res://addons/world_authoring/facility_dock.gd"
const COMPOSITION = FacilityDefinition.FacilityComposition

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_catalog_and_templates()
	_validate_function_defaults()
	_validate_stable_identity_helper()
	_validate_runtime_stamping_and_empty_shell()
	_validate_plugin_contracts()
	_validate_construction_migration_contracts()
	_validate_ruler_desk_content()
	_validate_furniture_identity_stamping()
	_finish()


func _validate_catalog_and_templates() -> void:
	var enabled_count := 0
	var ids := {}
	for file in DirAccess.get_files_at(FACILITY_DIR):
		if not file.ends_with(".tres"):
			continue
		var definition := load(FACILITY_DIR.path_join(file)) as FacilityDefinition
		_expect(definition != null, "Facility catalog resource must load: " + file)
		if definition == null or not definition.catalog_enabled:
			continue
		enabled_count += 1
		var facility_id := definition.get_id()
		_expect(not facility_id.strip_edges().is_empty() and not ids.has(facility_id), "Enabled facility identities must be nonblank and unique: " + file)
		ids[facility_id] = true
		var scene := load(definition.scene_path) as PackedScene
		var facility := scene.instantiate() as SettlementFacilityInstance if scene != null else null
		_expect(facility != null, "%s must use a composed facility template" % facility_id)
		if facility == null:
			continue
		_expect(facility.composition == definition.composition, "%s template must match its catalog composition" % facility_id)
		var is_building := definition.composition == COMPOSITION.BUILDING
		_expect(facility.supports_building_shell() == is_building and facility.supports_furniture() == is_building, "%s authoring capabilities must follow composition" % facility_id)
		var slot: Node = facility.call("get_building_root")
		if is_building:
			_expect(slot != null, "%s must expose a building slot" % facility_id)
			if slot != null:
				_expect(slot.get_child_count() <= 1, "%s may author one shell or intentionally no shell" % facility_id)
				for shell in slot.get_children():
					_expect(shell is WorldBuilding, "%s shell must provide the real building contract" % facility_id)
			_expect(facility.get_node_or_null("Furniture") != null, "%s must have a Furniture root" % facility_id)
		else:
			_expect(slot == null or slot.get_child_count() == 0, "%s must not author a building shell" % facility_id)
			_expect(facility.get_node_or_null("Furniture") == null, "%s must not manufacture a Furniture root" % facility_id)
		if definition.composition == COMPOSITION.GENERATED:
			root.add_child(facility)
			if facility.has_method("get_editor_guide"):
				_expect(facility.call("get_editor_guide") == null, "Field editor boundary must never exist during gameplay")
			if facility_id == "field":
				# Ownership contract, not a particular field footprint or worker total.
				_expect(facility.count_role_slots("worker", "employment") == 0, "Field must not carry its own posts — farmers are town labour")
			root.remove_child(facility)
		elif definition.composition == COMPOSITION.SINGLE_OBJECT:
			root.add_child(facility)
			_expect(facility is SettlementSingleObjectFacility, "%s must use the generic single-object host" % facility_id)
			_expect(facility.get_child_count(false) == 0, "%s must remain one leaf in the authored scene tree" % facility_id)
			if facility is SettlementSingleObjectFacility:
				var realized_object: Node3D = facility.get_single_object()
				_expect(realized_object != null, "%s must realize its configured object internally" % facility_id)
				if realized_object != null:
					_expect(facility.get_children(true).has(realized_object) and not facility.get_children(false).has(realized_object), "Single-object realization must remain internal")
					var configured_position := Vector3(1.0, 2.0, 3.0)
					facility.object_property_overrides = {"position": configured_position}
					_expect(realized_object.position == configured_position, "single-object facility configuration must apply generically to its realized object")
			root.remove_child(facility)
		facility.free()
	_expect(enabled_count > 0, "Composition checks must exercise the enabled facility catalog")


func _validate_function_defaults() -> void:
	# Deliberately nondefault, test-owned values; production balancing stays free.
	var function := FacilityFunctionDefinition.new()
	function.function_id = "fixture_function"
	function.display_name = "Fixture Function"
	function.facility_type = "storage"
	function.default_housing_capacity = 7
	function.default_storage_capacity_bonus = 19.5
	var generic := SettlementFacilityInstance.new()
	generic.facility_function = function
	_expect(generic.facility_type == function.facility_type and generic.display_name == function.display_name, "Assigning a function must apply its type and default label")
	_expect(generic.housing_capacity == function.default_housing_capacity, "Assigning a function must apply its housing default")
	_expect(is_equal_approx(generic.storage_capacity_bonus, function.default_storage_capacity_bonus), "Assigning a function must apply its storage default")
	generic.display_name = "Authored Name"
	generic.housing_capacity = 11
	generic.storage_capacity_bonus = 3.5
	generic.facility_function = function
	_expect(generic.display_name == "Authored Name" and generic.housing_capacity == 11 and is_equal_approx(generic.storage_capacity_bonus, 3.5), "Reapplying a function must preserve explicit author overrides")
	generic.free()


func _validate_stable_identity_helper() -> void:
	var tools := load(TOWN_TOOLS)
	var parent := Node.new()
	var first: Dictionary = tools.call("facility_identity_for", parent, "fixture_town", "workshop")
	_expect(first == {"node_name": "Workshop", "facility_id": "fixture_town.workshop", "building_id": "fixture_town.workshop.building"}, "first facility identity must derive from the supplied catalog ID")
	var existing := Node.new()
	existing.name = "Workshop"
	parent.add_child(existing)
	var second: Dictionary = tools.call("facility_identity_for", parent, "fixture_town", "workshop")
	_expect(second == {"node_name": "Workshop2", "facility_id": "fixture_town.workshop2", "building_id": "fixture_town.workshop2.building"}, "second facility identity must be deterministic and collision-free")
	parent.free()


func _validate_runtime_stamping_and_empty_shell() -> void:
	var town := (load("res://features/settlements/bridge/settlement_town.tscn") as PackedScene).instantiate()
	var settlement := SettlementDefinition.new()
	settlement.settlement_id = "fixture_town"
	town.set("settlement_definition", settlement)
	var facility := _fixture_facility()
	facility.facility_id = "fixture_town.workshop"
	facility.building_id = "fixture_town.workshop.building"
	facility.facility_type = "storage"
	facility.owner_faction_id = "ValidationFaction"
	facility.housing_capacity = 7
	facility.door_open_hour = 5
	facility.door_close_hour = 23
	town.add_child(facility)
	var slot := facility.get_building_root()
	var shell := WorldBuilding.new()
	slot.add_child(shell)
	# Both policy states and nondefault hours must copy, not match by coincidence.
	for policy in ["public", "private"]:
		facility.door_access_policy = policy
		facility.door_schedule_enabled = policy == "public"
		facility.stamp_building_identity()
		_expect(shell.building_id == facility.building_id, "shell must receive building identity")
		_expect(shell.facility_id == facility.facility_id, "shell must receive facility identity")
		_expect(shell.settlement_id == settlement.settlement_id, "shell must receive settlement identity")
		_expect(shell.building_type == facility.facility_type, "neutral shell generic type must not leak into an assigned facility")
		_expect(shell.owner_faction_id == facility.owner_faction_id, "shell must receive effective facility owner")
		_expect(shell.access_state == policy, "shell must receive facility door access policy")
		_expect(shell.public_schedule_enabled == facility.door_schedule_enabled and shell.public_open_hour == facility.door_open_hour and shell.public_close_hour == facility.door_close_hour, "shell must receive facility door schedule policy")
		_expect(shell.housing_capacity == facility.housing_capacity, "housing capacity must come from the facility configuration")
	# _repair_authoring_tree is a no-op off-tree; exercise its real precondition.
	town.remove_child(facility)
	town.free()
	root.add_child(facility)
	_expect(facility.is_inside_tree() and facility.auto_create_standard_roots, "Empty-shell fixture must enter the real repair lifecycle")
	slot.remove_child(shell)
	shell.free()
	facility.call("_repair_authoring_tree")
	_expect(slot.get_child_count() == 0, "an empty BuildingSlot must remain valid and not regenerate")
	root.remove_child(facility)
	facility.free()


func _fixture_facility() -> SettlementFacilityInstance:
	var facility := SettlementFacilityInstance.new()
	for root_name in [str(facility.building_root_path), "Furniture"]:
		var container := Node3D.new()
		container.name = root_name
		facility.add_child(container)
	return facility


func _validate_plugin_contracts() -> void:
	_expect(load(FACILITY_TOOLS) != null, "facility_tools.gd must compile")
	_expect(load(FACILITY_DOCK) != null, "facility_dock.gd must compile")
	var tools_text := FileAccess.get_file_as_string(FACILITY_TOOLS)
	var dock_text := FileAccess.get_file_as_string(FACILITY_DOCK)
	var dock := (load(FACILITY_DOCK) as Script).new() as Control
	var function_paths: Array = dock.call("_scan_function_paths")
	_expect(not function_paths.is_empty(), "Facility dock must discover current function resources")
	for path in function_paths:
		_expect(load(path) is FacilityFunctionDefinition, "Discovered function must load: " + str(path))
	dock.free()
	var facility_tools := (load(FACILITY_TOOLS) as Script).new(null) as RefCounted
	var shell_paths: Array = facility_tools.call("get_shell_catalog")
	_expect(not shell_paths.is_empty(), "Shell picker must discover current building shells")
	for path in shell_paths:
		var packed := load(path) as PackedScene
		var neutral := packed.instantiate() as WorldBuilding if packed != null else null
		_expect(neutral != null, "Shell catalog entry must instantiate a WorldBuilding: " + str(path))
		if neutral == null:
			continue
		_expect(neutral.building_id.is_empty() and neutral.facility_id.is_empty() and neutral.settlement_id.is_empty(), "neutral shell must not author durable identity: " + str(path))
		_expect(neutral.building_type == "generic" and neutral.owner_faction_id.is_empty() and neutral.housing_capacity == 0, "neutral shell must not author function, owner, or housing semantics: " + str(path))
		neutral.free()
	facility_tools.call("teardown")
	# Existing structural lint only; this is not native editor UndoRedo proof.
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
	_expect(tools_text.count("supports_furniture") >= 2, "all furniture entry points must use the generic facility composition capability")
	var town_tools_text := FileAccess.get_file_as_string(TOWN_TOOLS)
	_expect(town_tools_text.contains("definition.catalog_enabled"), "TownTools catalog must filter disabled definitions")
	_expect(town_tools_text.count("_apply_facility_identity(facility, town, definition)") == 2, "direct-file and live add paths must share facility identity helper")


func _validate_construction_migration_contracts() -> void:
	# Existing structural lint; actual save/load is covered by the GECS validator.
	var world_text := FileAccess.get_file_as_string("res://features/core/gecs_world_controller.gd")
	var realizer_text := FileAccess.get_file_as_string("res://features/settlements/bridge/construction_realizer.gd")
	_expect(world_text.contains("\"woodbrick_house\": \"medium_wood_l_hall\""), "load boundary must migrate woodbrick_house")
	_expect(world_text.find("_migrate_loaded_construction_catalog_ids(entities)") < world_text.find("_clear_world_entities()"), "construction catalog migration must run at deserialize boundary")
	_expect(realizer_text.contains("cannot realize unknown catalog id") and not realizer_text.contains("UNKNOWN_CATALOG_FALLBACK_SCENE"), "unknown construction IDs must fail instead of realizing a false fallback shell")
	_expect(realizer_text.contains("registry_rebuilt.connect(_reconcile_realized_records)"), "constructed projections must reconcile after save load")
	var projection_text := FileAccess.get_file_as_string("res://features/world/bridge/building_projection_bridge.gd")
	_expect(projection_text.contains("if not bool(_imports_seed_by_id.get(clean_id, false))"), "constructed registry rebuilds must remain owned by ConstructionRealizer")



# Consolidates the former source-only ruler desk validator using live scene data.
func _validate_ruler_desk_content() -> void:
	var packed := load("res://features/world/projection/props/furniture/ruler_planning_desk.tscn") as PackedScene
	_expect(packed != null, "Ruler desk scene and all item resources must load")
	if packed == null:
		return
	var desk := packed.instantiate()
	_expect(desk.has_method("supports_facility_role") and desk.supports_facility_role("ruler"), "Desk must expose its ruler workstation capability")
	_expect(desk.get_node_or_null("BodyCollision") is CollisionShape3D, "Desk must retain authored collision")
	var surface := desk.get_node_or_null("TabletopSurface")
	_expect(surface != null and str(surface.get("surface_id")) == "ruler_desk", "Desk surface needs its stable authored ID")
	var expected_required := {"ledger": "town_ledger.tres", "map": "town_map.tres"}
	var required := {}
	var ids := {}
	if surface != null:
		for slot in surface.get_children():
			var id := str(slot.get("slot_id"))
			_expect(not id.strip_edges().is_empty() and not ids.has(id), "Desk slots must have nonblank unique IDs")
			ids[id] = true
			var item := slot.get("required_item") as Resource
			if item != null:
				required[id] = item.resource_path.get_file()
			else:
				var options: Array = slot.get("optional_items")
				_expect(not options.is_empty() and options.all(func(option): return option != null), "Optional desk slots must contain loadable item resources")
		_expect(required == expected_required, "Desk must author exactly its real ledger and map required items")
		for id in ["candle", "drink", "scroll", "book_left", "book_right"]:
			_expect(ids.has(id), "Desk missing optional slot " + id)
	for removed in ["PlanningMap", "OpenLedger", "BookStack", "LooseOrders", "Inkwell", "Book_Stack"]:
		_expect(desk.find_child(removed, true, false) == null, "Desk must not contain obsolete baked item " + removed)
	desk.free()

func _validate_furniture_identity_stamping() -> void:
	# The real editor manager is abstract outside editor startup. Exercise the
	# production stable-ID stamping seam here, not a fake undo implementation.
	var tools = load(FACILITY_TOOLS).new(null)
	var facility := _fixture_facility()
	facility.set("facility_id", "authoring.stamp")
	var chest := (load("res://features/world/projection/props/furniture/chest_wood.tscn") as PackedScene).instantiate()
	chest.name = "AuthoredChest"
	facility.get_node("Furniture").add_child(chest)
	tools._stamp_furniture_ids(chest, facility)
	var stable_id := str(chest.get("container_id"))
	_expect(not stable_id.is_empty() and stable_id.begins_with("authoring.stamp"), "Generated storage must receive a facility-scoped durable identity")
	tools._stamp_furniture_ids(chest, facility)
	_expect(str(chest.get("container_id")) == stable_id, "Repeated stamping must retain the same durable identity")
	facility.free()
	tools.teardown()


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
