extends SceneTree

## Validates the world_authoring Town concept: icon, plugin registration,
## and the New Town scene-generation path (template expands into a
## standalone per-town scene with the canonical child roots).
## Uses load() at runtime, not preload: --script mode cannot compile
## GECS preload chains at parse time.

const TOWN_ICON_PATH := "res://addons/world_authoring/icons/town.svg"
const SETTLEMENT_TOWN_SCRIPT_PATH := "res://features/settlements/bridge/settlement_town.gd"
const TOWN_TEMPLATE_PATH := "res://features/settlements/bridge/settlement_town.tscn"
const TOWN_TOOLS_PATH := "res://addons/world_authoring/town_tools.gd"
const ZONE_TOOLS_PATH := "res://addons/world_authoring/zone_tools.gd"
const PLACEMENT_GHOST_PATH := "res://addons/world_authoring/placement_ghost.gd"
const PLUGIN_SCRIPT_PATH := "res://addons/world_authoring/plugin.gd"
const SETTLEMENT_DEFINITION_SCRIPT_PATH := "res://features/world_sim/resources/settlement_definition.gd"
const ROUND_TRIP_PATH := "user://validate_town_authoring_round_trip.tscn"
const HOUSE_SCENE_PATH := "res://features/world/projection/buildings/shells/modular/woodbrick_house.tscn"
## Towns are minimal by design: a bare root. Facilities are direct town
## children (flat model, 2026-07-07) — no container roots at all.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_icon()
	_validate_plugin_registration()
	_validate_template_is_minimal()
	_validate_new_town_round_trip()
	_validate_facility_add_remove()
	_validate_minimal_definition()
	_finish()


## Towns never carry debug hover text or the legacy root anatomy.
func _validate_template_is_minimal() -> void:
	var template_text := _read_text(TOWN_TEMPLATE_PATH)
	for forbidden in ["StateLabel", "Storage", "ActivityPoints", "GuardPosts", "Territory", "Residents", "Facilities"]:
		if template_text.contains(forbidden):
			_fail("Town template must stay minimal; found forbidden node: %s" % forbidden)
	var tools_text := _read_text(TOWN_TOOLS_PATH)
	if tools_text.contains("StateLabel"):
		_fail("Town tools must not author StateLabel debug text")


## Add/Remove Facility edit the town's own scene file; prove the surgery
## round-trips through disk.
func _validate_facility_add_remove() -> void:
	var tools := load(TOWN_TOOLS_PATH)
	if tools == null:
		_fail("Missing town_tools.gd")
		return
	var template := load(TOWN_TEMPLATE_PATH) as PackedScene
	var town := template.instantiate()
	town.name = "FacilityRoundTripTown"
	town.scene_file_path = ""
	var packed := PackedScene.new()
	packed.pack(town)
	town.free()
	ResourceSaver.save(packed, ROUND_TRIP_PATH)
	if not bool(tools.call("add_facility_to_town_scene", ROUND_TRIP_PATH, HOUSE_SCENE_PATH, Transform3D(Basis(), Vector3(4.0, 0.0, -6.0)))):
		_fail("add_facility_to_town_scene failed")
		return
	var with_facility := ResourceLoader.load(ROUND_TRIP_PATH, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var reloaded := with_facility.instantiate()
	var facility := reloaded.get_node_or_null("WoodbrickHouse") as Node3D
	if facility == null:
		_fail("Added facility missing from saved town scene")
	elif facility.position.distance_to(Vector3(4.0, 0.0, -6.0)) > 0.001:
		_fail("Added facility lost its local position")
	reloaded.free()
	if not bool(tools.call("remove_facility_from_town_scene", ROUND_TRIP_PATH, "WoodbrickHouse")):
		_fail("remove_facility_from_town_scene failed")
		return
	var without_facility := ResourceLoader.load(ROUND_TRIP_PATH, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var stripped := without_facility.instantiate()
	if stripped.get_node_or_null("WoodbrickHouse") != null:
		_fail("Removed facility still present in saved town scene")
	stripped.free()
	DirAccess.remove_absolute(ROUND_TRIP_PATH)


func _validate_icon() -> void:
	var icon_bytes := FileAccess.get_file_as_bytes(TOWN_ICON_PATH)
	var image := Image.new()
	if icon_bytes.size() == 0 or image.load_svg_from_buffer(icon_bytes) != OK:
		_fail("town.svg should exist and load as SVG image data")
	var town_script_text := _read_text(SETTLEMENT_TOWN_SCRIPT_PATH)
	if not town_script_text.contains("@icon(\"%s\")" % TOWN_ICON_PATH):
		_fail("SettlementTown should declare the town editor icon")


func _validate_plugin_registration() -> void:
	var plugin_text := _read_text(PLUGIN_SCRIPT_PATH)
	if not plugin_text.contains("town_tools.gd"):
		_fail("world_authoring plugin should register the town tool context")
	if not plugin_text.contains("zone_tools.gd"):
		_fail("world_authoring plugin should register the zone tool context")
	var zone_tools_text := _read_text(ZONE_TOOLS_PATH)
	# Towns are inline zone children (2026-07-07 decision): the zone scene is
	# the single source of truth, no per-town .tscn is ever written.
	if zone_tools_text.contains("towns/%s.tscn"):
		_fail("Add Town must not write per-town scene files (towns are inline zone children)")
	if not zone_tools_text.contains("_add_inline_town"):
		_fail("Add Town should build the town as plain nodes under the zone's Towns root")
	if not zone_tools_text.contains("scene_file_path = \"\""):
		_fail("Add Town should expand the template into plain nodes, not an inherited instance")
	var ghost_text := _read_text(PLACEMENT_GHOST_PATH)
	if not ghost_text.contains("terrain_ray"):
		_fail("Placement ghost should use the shared placement solver terrain ray")
	var town_tools_text := _read_text(TOWN_TOOLS_PATH)
	if not town_tools_text.contains("FACILITIES_DIR"):
		_fail("Facility catalog should be scanned from FacilityDefinition resources, not hardcoded")


func _validate_new_town_round_trip() -> void:
	var template := load(TOWN_TEMPLATE_PATH) as PackedScene
	if template == null:
		_fail("Missing settlement_town.tscn template")
		return
	var town := template.instantiate()
	town.name = "RoundTripTown"
	town.scene_file_path = ""
	var packed := PackedScene.new()
	if packed.pack(town) != OK:
		_fail("New Town pack of the template instance failed")
		town.free()
		return
	town.free()
	if ResourceSaver.save(packed, ROUND_TRIP_PATH) != OK:
		_fail("New Town save of the packed town scene failed")
		return
	var reloaded := load(ROUND_TRIP_PATH) as PackedScene
	if reloaded == null:
		_fail("Saved town scene failed to reload")
		return
	var state := reloaded.get_state()
	# Flat model: a fresh town is exactly one bare SettlementTown root.
	if state.get_node_count() != 1:
		_fail("Saved town scene should be a bare SettlementTown root (facilities are direct children added later)")
	var reloaded_town := reloaded.instantiate()
	var town_script := reloaded_town.get_script() as Script
	if town_script == null or town_script.resource_path != SETTLEMENT_TOWN_SCRIPT_PATH:
		_fail("Saved town scene root should keep the SettlementTown script")
	reloaded_town.free()
	DirAccess.remove_absolute(ROUND_TRIP_PATH)


func _validate_minimal_definition() -> void:
	var definition_script := load(SETTLEMENT_DEFINITION_SCRIPT_PATH) as Script
	if definition_script == null:
		_fail("Missing settlement_definition.gd")
		return
	var definition: Resource = definition_script.new()
	definition.set("settlement_id", "round_trip_town")
	definition.set("display_name", "Round Trip Town")
	definition.set("world_position", Vector3(1.0, 2.0, 3.0))
	if str(definition.get("settlement_id")) != "round_trip_town":
		_fail("SettlementDefinition should accept a minimal settlement_id")
	if Vector3(definition.get("world_position")) != Vector3(1.0, 2.0, 3.0):
		_fail("SettlementDefinition should accept a world_position")


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Missing text file: %s" % path)
		return ""
	return file.get_as_text()


func _finish() -> void:
	if _failures.is_empty():
		print("TOWN_AUTHORING_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("TOWN_AUTHORING_FAILED count=%d" % _failures.size())
	quit(1)


func _fail(message: String) -> void:
	_failures.append(message)
