extends SceneTree
## Validates that a SettlementField is a real worksite: it seeds one owned farm
## plot from its authored footprint, employs field hands, honours a painted
## (sparse) shape, and never double-seeds when the seed pass runs again.
## Run: godot --headless --path . --script res://tools/validation/validate_field_facility.gd

const FIELD_SCENE := "res://features/settlements/bridge/settlement_field.tscn"
const FARM_CONTROLLER := "res://features/farming/sim/farm_controller.gd"
const SETTLEMENT_ID := "field_validation_town"

class FakeGecs:
	extends Node
	signal world_reindexed
	var states := {}
	func upsert_farm_plot_state(state: Dictionary) -> Dictionary:
		states[str(state.get("plot_id", ""))] = state.duplicate(true)
		return states[str(state.get("plot_id", ""))].duplicate(true)
	func get_farm_plot_states() -> Dictionary:
		return states.duplicate(true)
	func remove_farm_plot_state(plot_id: String) -> void:
		states.erase(plot_id)
	func upsert_farm_water_source_state(state: Dictionary) -> Dictionary:
		return state.duplicate(true)
	func get_farm_water_source_states() -> Dictionary:
		return {}

class FakeTime:
	extends Node
	signal minute_changed(absolute_minute: int, day: int, hour: int, minute: int)
	var absolute_minute := 0
	func get_absolute_minute() -> int:
		return absolute_minute

class FakeTerritory:
	extends Node
	func get_build_permission(_position: Vector3, _faction_id := "") -> Dictionary:
		return {"can_build": true}
	func get_build_permissions(positions: Array, _faction_id := "") -> Array[Dictionary]:
		var permissions: Array[Dictionary] = []
		for _position in positions:
			permissions.append({"can_build": true})
		return permissions

## Stands in for the town. It must really be a SettlementAnchor: the facility
## resolves its settlement by ancestor CLASS, not by duck-typing, and an anchor
## with no definition falls back to its node name for the id.
class FakeTown:
	extends SettlementAnchor

var _failures: Array[String] = []
var _farm: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var context := BootstrapContext.new(root, null)
	var gecs := FakeGecs.new()
	var time := FakeTime.new()
	var territory := FakeTerritory.new()
	root.add_child(gecs)
	root.add_child(time)
	root.add_child(territory)
	context.register(&"gecs_world", gecs)
	context.register(&"world_time", time)
	context.register(&"territory", territory)
	_farm = load(FARM_CONTROLLER).new()
	root.add_child(_farm)
	context.register(&"farming", _farm)
	_farm.initialize(context)
	BootstrapContext.active = context

	await _check_rectangle_field(gecs)
	await _check_painted_field(gecs)
	await _check_no_double_seed(gecs)
	await _check_employment(gecs)
	_check_town_farmer_demand()
	await _check_typed_stores()
	_check_no_phantom_food()
	_finish()


func _instance_field(faction: String, dimensions: Vector2i, painted: PackedVector2Array, crop := "auto") -> Node3D:
	var town := FakeTown.new()
	town.name = SETTLEMENT_ID
	root.add_child(town)
	var field := (load(FIELD_SCENE) as PackedScene).instantiate() as Node3D
	field.set("owner_faction_id", faction)
	field.set("facility_id", "%s.field" % SETTLEMENT_ID)
	field.set("dimensions", dimensions)
	field.set("cell_coordinates", painted)
	field.set("crop_policy_id", crop)
	town.add_child(field)
	return field


## Synchronous teardown: queue_free lands at end of frame, so the next town
## would be added while this one still holds the name — and a SettlementAnchor
## derives its settlement id from its node name.
func _despawn(field: Node) -> void:
	var town := field.get_parent()
	if town == null:
		return
	root.remove_child(town)
	town.free()


func _plots_for(gecs, settlement_id: String) -> Array:
	var found: Array = []
	for state_value in gecs.states.values():
		if str((state_value as Dictionary).get("settlement_id", "")) == settlement_id:
			found.append(state_value)
	return found


func _check_rectangle_field(gecs) -> void:
	gecs.states.clear()
	var field := _instance_field("Farmers", Vector2i(4, 3), PackedVector2Array(), "tomato")
	await process_frame
	await process_frame
	var plots := _plots_for(gecs, SETTLEMENT_ID)
	if plots.size() != 1:
		_fail("Rectangle field should seed exactly 1 plot, got %d" % plots.size())
		_despawn(field)
		return
	var plot: Dictionary = plots[0]
	var cells: Dictionary = plot.get("cells", {})
	if cells.size() != 12:
		_fail("4x3 field should seed 12 cells, got %d" % cells.size())
	if str(plot.get("owner_faction_id", "")) != "Farmers":
		_fail("Field plot must inherit its facility's owner faction, got '%s'" % str(plot.get("owner_faction_id", "")))
	if str(plot.get("settlement_id", "")) != SETTLEMENT_ID:
		_fail("Field plot must carry the town's settlement id, got '%s'" % str(plot.get("settlement_id", "")))
	if str(plot.get("crop_policy_id", "")) != "tomato":
		_fail("Authored crop should reach the plot policy, got '%s'" % str(plot.get("crop_policy_id", "")))
	# auto_till_on_seed is what makes a fresh field start being worked without a
	# player hoe gesture.
	var tilling := 0
	for cell_value in cells.values():
		if str((cell_value as Dictionary).get("requested_operation", "")) == "till":
			tilling += 1
	if tilling != 12:
		_fail("Every fresh cell should request tilling, got %d of 12" % tilling)
	_despawn(field)


func _check_painted_field(gecs) -> void:
	gecs.states.clear()
	# An L: a painted field must seed only the cells drawn, not its bounding box.
	var painted := PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(2, 0),
		Vector2(0, 1),
		Vector2(0, 2),
	])
	var field := _instance_field("Farmers", Vector2i(3, 3), painted, "auto")
	await process_frame
	await process_frame
	var plots := _plots_for(gecs, SETTLEMENT_ID)
	if plots.size() != 1:
		_fail("Painted field should seed exactly 1 plot, got %d" % plots.size())
		_despawn(field)
		return
	var plot: Dictionary = plots[0]
	var cells: Dictionary = plot.get("cells", {})
	if cells.size() != 5:
		_fail("Painted L should seed its 5 drawn cells, not its 9-cell box; got %d" % cells.size())
	for expected_key in ["0:0", "1:0", "2:0", "0:1", "0:2"]:
		if not cells.has(expected_key):
			_fail("Painted field missing cell %s" % expected_key)
	if cells.has("2:2"):
		_fail("Painted field seeded a cell that was never drawn (2:2)")
	if str(plot.get("crop_policy_id", "")) != "auto":
		_fail("Auto policy should survive onto the plot, got '%s'" % str(plot.get("crop_policy_id", "")))
	_despawn(field)


func _check_no_double_seed(gecs) -> void:
	gecs.states.clear()
	var field := _instance_field("Farmers", Vector2i(3, 2), PackedVector2Array(), "wheat")
	await process_frame
	await process_frame
	var first := _plots_for(gecs, SETTLEMENT_ID).size()
	# Re-entering the seed pass (a deferred retry, a re-ready) must adopt rather
	# than mint a second field on the same ground.
	field.call("_seed_plot", 3)
	await process_frame
	await process_frame
	var second := _plots_for(gecs, SETTLEMENT_ID).size()
	if first != 1 or second != 1:
		_fail("Re-running the seed pass must not create a second plot (%d -> %d)" % [first, second])
	_despawn(field)


## Real fields publish FarmController work. They own no pseudo staff or ambient
## stand-around points from the May placeholder system.
func _check_employment(gecs) -> void:
	gecs.states.clear()
	var field := _instance_field("Farmers", Vector2i(3, 2), PackedVector2Array(), "wheat")
	await process_frame
	await process_frame
	# Farming is town labour: a farmer works any field in the settlement, so the
	# field must NOT carry posts that would chain a worker to one plot.
	if not field.has_method("count_role_slots"):
		_fail("Field facility lost its role slot API")
	elif int(field.call("count_role_slots", "worker", "employment")) > 0:
		_fail("Field must not carry its own employment slots — farmer demand is town-level")
	var points := field.get_node_or_null("ActivityPoints")
	if points != null:
		_fail("Field must not retain pseudo farm activity points")
	if str(field.get("facility_type")) != "farm":
		_fail("Field facility_type must stay 'farm', got '%s'" % str(field.get("facility_type")))
	_despawn(field)


## Field size is physical workload, not permission to manufacture occupations.
func _check_town_farmer_demand() -> void:
	var town = load("res://features/settlements/bridge/settlement_town.gd").new()
	town.name = "FarmerDemandTown"
	root.add_child(town)
	var facilities := Node3D.new()
	facilities.name = "Facilities"
	town.add_child(facilities)
	for expectation in [{"dims": Vector2i(6, 4), "farmers": 0}, {"dims": Vector2i(10, 6), "farmers": 0}]:
		for child in facilities.get_children():
			facilities.remove_child(child)
			child.free()
		var field := (load(FIELD_SCENE) as PackedScene).instantiate()
		field.set("dimensions", expectation["dims"])
		facilities.add_child(field)
		var farmers := 0
		for slot in town.get_assignment_slot_specs():
			if str((slot as Dictionary).get("role_id", "")) == "farmer":
				farmers += 1
		if farmers != int(expectation["farmers"]):
			_fail("A %s field should want %d farmers, town asked for %d" % [str(expectation["dims"]), int(expectation["farmers"]), farmers])
	root.remove_child(town)
	town.free()


## Raw/player-built furniture stays empty. Developer/world generation supplies
## one-time starter recipes through the granary rules.
func _check_typed_stores() -> void:
	for expectation in [
		{"scene": "res://features/world/projection/props/furniture/seed_sack.tscn", "stock": "res://features/settlements/resources/furnishing/granary_seed_stock.tres", "kind": "farm_seed", "tag": "seed."},
		{"scene": "res://features/world/projection/props/furniture/tool_chest.tscn", "stock": "res://features/settlements/resources/furnishing/granary_tool_stock.tres", "kind": "tool_store", "tag": "tool."},
	]:
		var store := (load(str(expectation["scene"])) as PackedScene).instantiate()
		store.name = str(expectation["scene"]).get_file().get_basename()
		root.add_child(store)
		await process_frame
		await process_frame
		if str(store.get("container_kind")) != str(expectation["kind"]):
			_fail("%s must declare container_kind '%s'" % [store.name, str(expectation["kind"])])
		var inventory = store.get("inventory")
		if inventory != null and not inventory.entries.is_empty():
			_fail("%s raw/player-built furniture must start empty" % store.name)
		var rng := RandomNumberGenerator.new()
		rng.seed = 1
		var stock: Array = (load(str(expectation["stock"])) as ContainerStockTable).roll(rng)
		var matching := 0
		for entry in stock:
			if entry != null and entry.item_definition != null and str(entry.item_definition.item_id).begins_with(str(expectation["tag"])):
					matching += 1
		if matching < 1:
			_fail("%s developer starter recipe is empty" % store.name)
		root.remove_child(store)
		store.free()


## The farm sim grows real crops; the facility function must not also mint
## abstract food, or the town harvests twice.
func _check_no_phantom_food() -> void:
	var function := load("res://features/world_sim/resources/facility_functions/field.tres")
	if function == null:
		_fail("Field facility function missing")
		return
	var outputs: Array = function.get("food_outputs_per_day")
	if not outputs.is_empty():
		_fail("Field function still mints %d abstract food output(s) alongside real crops" % outputs.size())


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	BootstrapContext.active = null
	if _failures.is_empty():
		print("FIELD_FACILITY_OK")
	else:
		print("FIELD_FACILITY_FAILED count=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
