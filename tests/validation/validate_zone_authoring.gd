extends SceneTree

## Focused authoring proof in an isolated scene, never the mutable Rustwash map.
## The actual dock is constructed; later placement checks round-trip its nodes.
const DOCK_PATH := "res://addons/world_authoring/zone_dock.gd"
const RESOURCE_AUTHORING_PATH := "res://addons/world_authoring/resource_authoring.gd"
var _failures: Array[String] = []

class AuthoringFixture extends RefCounted:
	func get_resource_catalog() -> Array:
		return []

	func get_zone_towns(_zone: Node) -> Array:
		return []

	func get_zone_resources(_zone: Node) -> Array:
		return []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not FileAccess.file_exists(DOCK_PATH):
		_expect(false, "Zone selection needs a real tabbed authoring dock")
	else:
		var dock = load(DOCK_PATH).new()
		dock.setup(AuthoringFixture.new())
		root.add_child(dock)
		var zone := Node3D.new()
		zone.name = "AuthoringProof"
		root.add_child(zone)
		dock.set_zone(zone)
		await process_frame
		var tabs := dock.find_child("WorkspaceTabs", true, false) as TabContainer
		_expect(tabs != null, "Zone dock exposes an identifiable tabbed workspace")
		if tabs != null:
			var titles: Array[String] = []
			for index in range(tabs.get_tab_count()):
				titles.append(tabs.get_tab_title(index))
			_expect(titles == ["Overview", "Towns", "Resources"], "Zone tabs are Overview, Towns and Resources, without empty future tools")
		var heading := dock.find_child("ZoneHeading", true, false) as Label
		_expect(heading != null and heading.text.contains("AuthoringProof"), "Current editing zone stays obvious")
		var search := dock.find_child("ResourceSearch", true, false) as LineEdit
		_expect(search != null, "Resource catalog is searchable")
		var place := dock.find_child("PlaceResource", true, false) as Button
		_expect(place != null and place.disabled, "Empty resource catalog cannot arm an invalid placement")
		dock.free()
		zone.free()
	_validate_resource_creation()
	_validate_zone_tool_surface()
	for failure in _failures:
		push_error(failure)
	print("ZONE_AUTHORING %s failures=%d" % ["PASS" if _failures.is_empty() else "FAIL", _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _validate_resource_creation() -> void:
	if not FileAccess.file_exists(RESOURCE_AUTHORING_PATH):
		_expect(false, "Resource placement needs one tested catalog and UndoRedo authoring boundary")
		return
	var authoring := load(RESOURCE_AUTHORING_PATH) as Script
	var catalog: Array = authoring.load_catalog()
	var type_ids := {}
	for definition: Resource in catalog:
		var type_id := str(definition.get("deposit_type_id"))
		_expect(not type_id.strip_edges().is_empty() and not type_ids.has(type_id), "Catalog resource type IDs are nonblank and unique")
		type_ids[type_id] = true
	for required in ["copper", "iron", "scrap_pile", "twisted_scrap_heap", "robot_wreck"]:
		_expect(type_ids.has(required), "Catalog includes the existing resource: " + required)
	var zone := Node3D.new()
	zone.name = "IsolatedResourcePlacement"
	zone.position = Vector3(60.0, 2.0, -40.0)
	zone.rotation.y = 0.4
	root.add_child(zone)
	var undo := UndoRedo.new()
	var placed: Array[Node] = []
	var ids := {}
	for definition: Resource in catalog:
		var target := Transform3D(Basis(Vector3.UP, 0.8), Vector3(72.0, 3.0, -28.0))
		var node: Node3D = authoring.place_resource(zone, zone, definition, target, undo)
		_expect(node != null, "Existing resource scene places successfully")
		if node == null:
			continue
		placed.append(node)
		_expect(node.get_parent() == zone and node.owner == zone, "Deposit saves directly with the zone, without a required field group")
		_expect(node.global_transform.is_equal_approx(target), "Placement preserves the world transform under a transformed zone")
		var id := str(node.get("resource_node_id"))
		_expect(not id.is_empty() and not ids.has(id), "Each placed deposit gets a unique stable ID")
		ids[id] = true
		_expect(node.get("deposit_definition") == definition, "Placed node uses the same authoritative definition as the browser")
		undo.undo()
		_expect(node.get_parent() == null, "Undo removes the placed deposit")
		undo.redo()
		_expect(node.get_parent() == zone and str(node.get("resource_node_id")) == id, "Redo restores the same deposit identity")
	if not placed.is_empty():
		var original := placed[0]
		var original_id := str(original.get("resource_node_id"))
		var duplicate := original.duplicate()
		zone.add_child(duplicate)
		duplicate.owner = zone
		_expect(authoring.repair_duplicate_ids(zone, undo) == 1, "Ordinary scene-tree duplication receives one new deposit ID")
		_expect(str(original.get("resource_node_id")) == original_id, "Duplication never changes the original deposit's saved identity")
		_expect(str(duplicate.get("resource_node_id")) != original_id, "Duplicated deposits cannot share stock with the original")
		var repaired_id := str(duplicate.get("resource_node_id"))
		undo.undo()
		_expect(str(original.get("resource_node_id")) == original_id and str(duplicate.get("resource_node_id")) == original_id, "ID repair participates in UndoRedo")
		undo.redo()
		_expect(str(duplicate.get("resource_node_id")) == repaired_id, "ID repair redo restores the same new durable identity")
		zone.remove_child(duplicate)
		duplicate.free()
		undo.clear_history()
	var packed := PackedScene.new()
	_expect(packed.pack(zone) == OK, "Placed deposits pack with their zone")
	var restored := packed.instantiate()
	_expect(restored.get_child_count() == placed.size(), "Zone save restores every placed resource")
	for node in restored.get_children():
		_expect(ids.has(str(node.get("resource_node_id"))), "Saved deposit identity survives scene round trip")
	restored.free()
	undo.clear_history()
	undo.free()
	zone.free()

func _validate_zone_tool_surface() -> void:
	var script := load("res://addons/world_authoring/zone_tools.gd") as Script
	var methods: Array[String] = []
	for method in script.get_script_method_list():
		methods.append(str(method.name))
	for method_name in ["wants_dock", "dock_control", "begin_resource_placement", "set_resource_definition_property", "apply_changes"]:
		_expect(methods.has(method_name), "Zone tool connects the real editor workflow: %s" % method_name)
