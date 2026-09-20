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
const PLACEMENT_SOLVER_PATH := "res://features/settlements/bridge/building_placement_solver.gd"
const PLUGIN_SCRIPT_PATH := "res://addons/world_authoring/plugin.gd"
const SETTLEMENT_DEFINITION_SCRIPT_PATH := "res://features/world_sim/resources/settlement_definition.gd"
var ROUND_TRIP_PATH := "user://validate_town_authoring_round_trip_%d.tscn" % OS.get_process_id()
const KEEP_DEFINITION_PATH := "res://features/settlements/resources/facilities/keep.tres"
const SINGLE_OBJECT_FACILITY_PATHS := [
	"res://features/settlements/bridge/settlement_tank.tscn",
	"res://features/settlements/bridge/settlement_well_1.tscn",
]
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
	_validate_single_object_placement_preview_collision()
	await _validate_placement_preview_ray_runtime()
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
	var keep_definition := load(KEEP_DEFINITION_PATH) as Resource
	if not bool(tools.call("add_facility_to_town_scene", ROUND_TRIP_PATH, keep_definition, Transform3D(Basis(), Vector3(4.0, 0.0, -6.0)))):
		_fail("add_facility_to_town_scene failed")
		return
	var with_facility := ResourceLoader.load(ROUND_TRIP_PATH, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var reloaded := with_facility.instantiate()
	var facility := reloaded.get_node_or_null("Keep") as Node3D
	if facility == null:
		_fail("Added facility missing from saved town scene")
	elif facility.position.distance_to(Vector3(4.0, 0.0, -6.0)) > 0.001:
		_fail("Added facility lost its local position")
	reloaded.free()
	if not bool(tools.call("remove_facility_from_town_scene", ROUND_TRIP_PATH, "Keep")):
		_fail("remove_facility_from_town_scene failed")
		return
	var without_facility := ResourceLoader.load(ROUND_TRIP_PATH, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var stripped := without_facility.instantiate()
	if stripped.get_node_or_null("Keep") != null:
		_fail("Removed facility still present in saved town scene")
	stripped.free()
	DirAccess.remove_absolute(ROUND_TRIP_PATH)


## Placement previews must never raycast against themselves. Single-object
## facilities realize their colliders as internal children, so this guards the
## exact Add Facility regression that pulled Tank and Well toward the camera.
func _validate_single_object_placement_preview_collision() -> void:
	var ghost := (load(PLACEMENT_GHOST_PATH) as Script).new(null) as RefCounted
	var solver := load(PLACEMENT_SOLVER_PATH) as Script
	var ghost_text := _read_text(PLACEMENT_GHOST_PATH)
	if not ghost_text.contains("excluded_roots: Array[Node] = [_preview]"):
		_fail("Placement ray must explicitly exclude its preview root")
	for scene_path in SINGLE_OBJECT_FACILITY_PATHS:
		var scene := load(scene_path) as PackedScene
		var preview := scene.instantiate() as Node3D if scene != null else null
		if preview == null:
			_fail("Single-object placement preview must instantiate: %s" % scene_path)
			continue
		if not ghost.has_method("_mount_preview"):
			_fail("Placement ghost must mount previews before disabling their internal colliders")
			preview.free()
			continue
		ghost.call("_mount_preview", root, preview)
		var colliders: Array[Node] = []
		_collect_colliders(preview, colliders)
		if colliders.is_empty():
			_fail("Single-object placement preview must contain collision: %s" % scene_path)
		else:
			for collider in colliders:
				var excluded_roots: Array[Node] = [preview]
				if not bool(solver.call("collider_belongs_to_excluded_root", collider, excluded_roots)):
					_fail("Placement solver must reject every preview collider: %s" % scene_path)
				if collider is CollisionObject3D and ((collider as CollisionObject3D).collision_layer != 0 or (collider as CollisionObject3D).collision_mask != 0):
					_fail("Placement preview collision object stayed active: %s" % scene_path)
				if collider is CollisionShape3D and not (collider as CollisionShape3D).disabled:
					_fail("Placement preview collision shape stayed active: %s" % scene_path)
		root.remove_child(preview)
		preview.free()


## Reproduces the camera-pull bug with an active preview collider physically
## between the ray origin and terrain. The solver must skip the whole preview
## subtree and return the actual ground body behind it.
func _validate_placement_preview_ray_runtime() -> void:
	var solver := load(PLACEMENT_SOLVER_PATH) as Script
	var world := Node3D.new()
	root.add_child(world)
	var preview := Node3D.new()
	world.add_child(preview)
	var preview_body := StaticBody3D.new()
	preview_body.position = Vector3(0.0, 2.0, 0.0)
	preview.add_child(preview_body)
	var preview_shape := CollisionShape3D.new()
	var preview_box := BoxShape3D.new()
	preview_box.size = Vector3(4.0, 0.5, 4.0)
	preview_shape.shape = preview_box
	preview_body.add_child(preview_shape)

	var terrain_body := StaticBody3D.new()
	terrain_body.position = Vector3(0.0, -0.25, 0.0)
	world.add_child(terrain_body)
	var terrain_shape := CollisionShape3D.new()
	var terrain_box := BoxShape3D.new()
	terrain_box.size = Vector3(20.0, 0.5, 20.0)
	terrain_shape.shape = terrain_box
	terrain_body.add_child(terrain_shape)

	await physics_frame
	await physics_frame
	var space := world.get_world_3d().direct_space_state
	var from := Vector3(0.0, 5.0, 0.0)
	var to := Vector3(0.0, -5.0, 0.0)
	var raw_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if raw_hit.get("collider") != preview_body:
		_fail("Placement regression setup must hit the preview before terrain")
	var excluded_roots: Array[Node] = [preview]
	var terrain_hit: Dictionary = solver.call("terrain_ray", space, from, to, excluded_roots)
	if terrain_hit.get("collider") != terrain_body:
		_fail("Placement ray did not skip the active preview collider and reach terrain")
	world.queue_free()
	await process_frame


func _collect_colliders(node: Node, output: Array[Node]) -> void:
	if node is CollisionObject3D or node is CollisionShape3D:
		output.append(node)
	for child in node.get_children(true):
		_collect_colliders(child, output)


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
	if FileAccess.file_exists(ROUND_TRIP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ROUND_TRIP_PATH))
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
