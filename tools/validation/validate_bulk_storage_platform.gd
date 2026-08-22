extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_bulk_storage_platform.gd

const TOMATO = preload("res://features/inventory/resources/items/tomato.tres")
const CHILI_PEPPER = preload("res://features/inventory/resources/items/chili_pepper.tres")
const EGGPLANT = preload("res://features/inventory/resources/items/eggplant.tres")
const BELL_PEPPER = preload("res://features/inventory/resources/items/bell_pepper.tres")
const FRENCH_BEANS = preload("res://features/inventory/resources/items/french_beans.tres")
const BREAD = preload("res://features/inventory/resources/items/bread.tres")
const SILVER = preload("res://features/inventory/resources/items/silver.tres")

const PRODUCE_ITEMS: Array[ItemDefinition] = [
	TOMATO,
	CHILI_PEPPER,
	EGGPLANT,
	BELL_PEPPER,
	FRENCH_BEANS,
]

const STORAGE_MARKERS := {
	"food.tomato": "res://assets/icons/storage_markers/tomato.svg",
	"food.chili_pepper": "res://assets/icons/storage_markers/chili_pepper.svg",
	"food.eggplant": "res://assets/icons/storage_markers/eggplant.svg",
	"food.bell_pepper": "res://assets/icons/storage_markers/bell_pepper.svg",
	"food.french_beans": "res://assets/icons/storage_markers/french_beans.svg",
}

var failures: Array[String] = []
var _ecs_placeholder: Node


func _initialize() -> void:
	if not Engine.has_singleton("ECS"):
		_ecs_placeholder = Node.new()
		Engine.register_singleton("ECS", _ecs_placeholder)
	call_deferred("_run")


func _run() -> void:
	var scene_root := Node3D.new()
	root.add_child(scene_root)
	var platform_scene := load("res://features/world/projection/containers/bulk_storage_platform.tscn") as PackedScene
	_expect(platform_scene != null, "storage platform scene loads through Godot's real resource boundary")
	if platform_scene == null:
		_finish()
		return
	var platform = platform_scene.instantiate()
	platform.container_id = "validation.bulk_storage"
	platform.owner_faction_name = "Player"
	scene_root.add_child(platform)
	await process_frame

	_expect(platform.is_in_group("world_container"), "storage platform uses the durable world-container inventory path")
	_expect(platform.is_in_group(FurnitureRules.FURNITURE_GROUP), "storage platform is ordinary furniture")
	_expect(platform.get_owner_faction_name() == "Player", "storage platform supports faction ownership")
	_expect(platform.get_displayed_item_count() == 0, "empty platform displays no fake stock")
	_expect(platform.get_displayed_visual_count() == 0, "empty platform has no representative meshes")
	_expect(platform.display_profiles.size() >= PRODUCE_ITEMS.size(), "platform has reusable display profiles for every farm produce type")
	for item in PRODUCE_ITEMS:
		_expect(STORAGE_MARKERS.has(item.item_id) and ResourceLoader.exists(STORAGE_MARKERS[item.item_id]), "%s has a dedicated crate marker SVG" % item.display_name)

	_expect(platform.inventory.add_item_count(TOMATO, 1), "platform inventory stores the ordinary Tomato item directly")
	await process_frame
	_expect(platform.get_displayed_item_count() == 1, "display reads the authoritative inventory quantity")
	_expect(platform.get_displayed_visual_count() == 1, "one tomato creates one partial physical crate")

	platform.deposit_item_count(TOMATO, 19)
	await process_frame
	_expect(platform.get_displayed_item_count() == 20, "contained crate entries preserve exact commodity quantity")
	_expect(platform.get_displayed_visual_count() == 1, "20 tomatoes still fit the first 30-unit crate")
	_expect(_positions_are_unique(platform.get_display_slot_positions()), "display positions are deterministic authored slots, not overlapping clutter")

	platform.deposit_item_count(TOMATO, 30)
	await process_frame
	var positions: Array = platform.get_display_slot_positions()
	_expect(platform.get_displayed_item_count() == 50, "platform preserves all 50 authoritative tomatoes")
	_expect(platform.get_displayed_visual_count() == 2, "50 tomatoes render as two physical crates at 30 per crate")
	_expect(platform.inventory.entries.size() == 2 and platform.inventory.entries[0].count == 30 \
			and platform.inventory.entries[1].count == 20, "each authoritative platform stack maps to one physical crate")
	_expect(_distinct_layer_count(positions) == 1, "two tomato crates occupy one deterministic layer")
	_expect(_positions_fit_display(positions), "all representative food stays inside the usable platform surface")
	var display_root := platform.get_node("DisplayRoot")
	_expect(display_root.get_child_count() == 1, "full tomato stock uses one crate-mesh batch with material-projected markers")
	var crate_meshes := display_root.get_node_or_null("CrateMeshes") as MultiMeshInstance3D
	_expect(crate_meshes != null and crate_meshes.multimesh.instance_count == 2, "imported closed-crate mesh batch has two physical crates")
	_expect(crate_meshes != null and crate_meshes.material_override is ShaderMaterial, "crate batch projects markers through its surface material instead of floating label geometry")
	_expect(display_root.get_node_or_null("FrontLabels") == null and display_root.get_node_or_null("BackLabels") == null, "crate display creates no detached marker planes")
	_expect(_display_has_marker(display_root, STORAGE_MARKERS["food.tomato"]), "crate representatives show the tomato marker on front and back")

	platform.withdraw_item_count(TOMATO, 50)
	await process_frame
	for item in PRODUCE_ITEMS:
		platform.deposit_item_count(item, 1)
		await process_frame
		_expect(platform.get_displayed_visual_count() == 1, "%s produces one representative crate" % item.display_name)
		_expect(_display_has_marker(display_root, STORAGE_MARKERS[item.item_id]), "%s crate uses its matching front-and-back marker" % item.display_name)
		platform.withdraw_item_count(item, 1)
		await process_frame

	var unsupported_added: bool = platform.inventory.add_item_count(BREAD, 1)
	_expect(not unsupported_added, "platform rejects unsupported items at the authoritative inventory boundary")
	if unsupported_added:
		platform.inventory.remove_item_count(BREAD, 1)
	var silver_added: bool = platform.inventory.add_item_count(SILVER, 1)
	_expect(not silver_added, "platform rejects unsupported currency through the direct mutation path")
	if silver_added:
		platform.inventory.remove_item_count(SILVER, 1)
	_expect(platform.get_displayed_item_count() == 0 and platform.get_displayed_visual_count() == 0, "clearing real inventory clears every representative visual")
	_expect(display_root.get_child_count() == 0, "clearing real inventory removes every representative crate")

	var test_scene := load("res://scenes/test_levels/bulk_storage_test.tscn") as PackedScene
	_expect(test_scene != null, "standalone bulk-storage test level loads")
	if test_scene != null:
		var fixture := test_scene.instantiate()
		# The validator supplies only the ECS parse placeholder, not the production
		# bootstrap services. Remove GameBootstrap, then exercise every fixture's
		# real _ready/deferred seeding path inside the active SceneTree.
		var bootstrap := fixture.get_node_or_null("GameBootstrap")
		if bootstrap != null:
			fixture.remove_child(bootstrap)
			bootstrap.free()
		scene_root.add_child(fixture)
		for _frame in 12:
			await process_frame
		var platforms := fixture.get_node("StoragePlatforms").get_children()
		_expect(platforms.size() == 7, "test level includes two transfer targets and five full produce references")
		_expect(platforms[0].owner_faction_name == "Player" and platforms[1].owner_faction_name == "Market Ward", "test level demonstrates distinct faction ownership")
		_expect(platforms[0].inventory.entries.is_empty() and platforms[1].inventory.entries.is_empty(), "both transfer-target platforms start empty at runtime")
		_expect(platforms[2].get_stored_item_count(TOMATO) == 50, "tomato reference seeds 50 authoritative contained tomatoes at runtime")
		_expect(platforms[2].get_displayed_item_count() == 50 and platforms[2].get_displayed_visual_count() == 2, "tomato reference projects two physical crates")
		_expect(platforms[2].get_node("DisplayRoot").get_child_count() == 1, "full-stock reference builds one material-labeled crate batch")
		if platforms.size() >= PRODUCE_ITEMS.size() + 2:
			for index in PRODUCE_ITEMS.size():
				var reference = platforms[index + 2]
				var item := PRODUCE_ITEMS[index]
				_expect(reference.get_stored_item_count(item) == 50, "%s reference seeds 50 authoritative contained items" % item.display_name)
				_expect(_display_has_marker(reference.get_node("DisplayRoot"), STORAGE_MARKERS[item.item_id]), "%s reference displays its matching crate marker" % item.display_name)
		var ada = fixture.get_node("PartyMembers/Ada")
		var bram = fixture.get_node("PartyMembers/Bram")
		_expect(ada.faction_name == "Player" and bram.faction_name == "Market Ward", "each provisioned character matches a demonstrated platform faction")
		_expect(ada.inventory != null and ada.inventory.count_item(TOMATO) == 25, "Ada's runtime inventory seeds 25 tomatoes")
		_expect(bram.inventory != null and bram.inventory.count_item(CHILI_PEPPER) == 25, "Bram's runtime inventory seeds 25 chili peppers")
		scene_root.remove_child(fixture)
		fixture.free()

	scene_root.free()
	_finish()


func _positions_are_unique(positions: Array) -> bool:
	var seen: Dictionary = {}
	for value in positions:
		var position := value as Vector3
		var key := "%0.3f:%0.3f:%0.3f" % [position.x, position.y, position.z]
		if seen.has(key):
			return false
		seen[key] = true
	return true


func _distinct_layer_count(positions: Array) -> int:
	var layers: Dictionary = {}
	for value in positions:
		layers[snappedf((value as Vector3).y, 0.001)] = true
	return layers.size()


func _positions_fit_display(positions: Array) -> bool:
	for value in positions:
		var position := value as Vector3
		if absf(position.x) > 0.31 or absf(position.z) > 0.34:
			return false
	return true


func _display_has_marker(display_root: Node, expected_path: String) -> bool:
	if display_root == null:
		return false
	var crates := display_root.get_node_or_null("CrateMeshes") as MultiMeshInstance3D
	if crates == null or not (crates.material_override is ShaderMaterial):
		return false
	var texture := (crates.material_override as ShaderMaterial).get_shader_parameter("label_texture") as Texture2D
	return texture != null and texture.resource_path == expected_path


func _highest_display_top(positions: Array, unit_height: float) -> float:
	var highest := 0.0
	for value in positions:
		highest = maxf(highest, (value as Vector3).y + unit_height)
	return highest


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if _ecs_placeholder != null:
		Engine.unregister_singleton("ECS")
		_ecs_placeholder.free()
		_ecs_placeholder = null
	if failures.is_empty():
		print("BULK_STORAGE_PLATFORM_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("BULK_STORAGE_PLATFORM_FAILED count=%d" % failures.size())
	quit(1)
