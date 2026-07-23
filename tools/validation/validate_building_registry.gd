extends SceneTree

const GECS_SCRIPT_PATH := "res://features/core/gecs_world_controller.gd"
const REGISTRY_SCRIPT_PATH := "res://features/world/sim/building_registry.gd"
const PROJECTION_BRIDGE_SCRIPT_PATH := "res://features/world/bridge/building_projection_bridge.gd"
const WORLD_BUILDING_SCRIPT_PATH := "res://features/world/projection/buildings/world_building.gd"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := Node.new()
	root.add_child(host)
	var context := BootstrapContext.new(host)
	var gecs = load(GECS_SCRIPT_PATH).new()
	host.add_child(gecs)
	context.register(&"gecs_world", gecs)
	gecs.initialize(context)
	var registry = load(REGISTRY_SCRIPT_PATH).new()
	host.add_child(registry)
	context.register(&"building_registry", registry)
	registry.initialize(context)
	var projection_bridge = load(PROJECTION_BRIDGE_SCRIPT_PATH).new()
	host.add_child(projection_bridge)
	context.register(&"building_projection_bridge", projection_bridge)
	projection_bridge.initialize(context)

	var home: Dictionary = registry.create_building(_record("building.home", "facility.housing", 6))
	var shop: Dictionary = registry.create_building(_record("building.shop", "facility.market", 4))
	_expect(not home.is_empty() and not shop.is_empty(), "registry should create records")
	_expect(registry.get_buildings_for_settlement("town.alpha").size() == 2, "settlement index should return both buildings")
	_expect(registry.get_buildings_for_facility("facility.housing").size() == 1, "facility index should return one building")
	_expect(registry.get_settlement_housing_capacity("town.alpha") == 10, "operational buildings should contribute housing")
	var settlement = load("res://features/settlements/bridge/settlement_controller.gd").new()
	host.add_child(settlement)
	settlement.set("building_registry", registry)
	settlement.set("settlement_states", {"town.alpha": {"settlement_id": "town.alpha", "faction_id": "FactionA"}})
	settlement.call("set_settlement_owner", "town.alpha", "FactionB", "validation")
	for building in registry.get_buildings_for_settlement("town.alpha"):
		_expect(str(building.get("owner_faction_id", "")) == "FactionB", "settlement ownership must update canonical building ownership")

	registry.update_building("building.shop", {"abandoned": true})
	_expect(registry.get_settlement_housing_capacity("town.alpha") == 6, "abandoned buildings should not contribute housing")
	registry.update_building("building.home", {"operational_state": "disabled"})
	_expect(registry.get_settlement_housing_capacity("town.alpha") == 0, "non-operational buildings should not contribute housing")
	var snapshot: Array = registry.get_settlement_building_snapshot("town.alpha")
	_expect(snapshot.size() == 2, "ledger snapshot should contain settlement buildings")
	if snapshot.size() == 2:
		_expect((snapshot[0] as Dictionary).has_all(["building_id", "type_id", "owner_faction_id", "access_state", "abandoned", "operational_state", "bed_count", "housing_capacity", "source"]), "ledger rows should expose required fields")

	registry._rebuild_from_gecs()
	_expect(registry.get_buildings_for_settlement("town.alpha").size() == 2, "registry should rebuild indexes from GECS")
	_expect(registry.get_settlement_housing_capacity("town.alpha") == 0, "rebuilt capacity index should preserve operational rules")

	var projection := StaticBody3D.new()
	projection.name = "AuthoredHome"
	projection.set_script(load(WORLD_BUILDING_SCRIPT_PATH))
	projection.set("building_id", "building.authored_home")
	projection.set("settlement_id", "town.alpha")
	projection.set("facility_id", "facility.housing")
	projection.set("building_type", "housing")
	projection.set("housing_capacity", 8)
	projection.transform = Transform3D(Basis.IDENTITY, Vector3(3.0, 0.0, 4.0))
	host.add_child(projection)
	_expect(projection_bridge.bind_projection(projection, true), "authored projection should seed a registry record")
	gecs._clear_world_entities()
	registry._rebuild_from_gecs()
	_expect(not registry.get_building("building.authored_home").is_empty(), "authored projection should re-seed records missing from an old save")
	_expect(registry.get_settlement_housing_capacity("town.alpha") == 8, "old-save reconciliation should restore authored housing")
	var inn := StaticBody3D.new()
	inn.name = "AuthoredInn"
	inn.set_script(load(WORLD_BUILDING_SCRIPT_PATH))
	inn.set("building_id", "building.authored_inn")
	inn.set("settlement_id", "town.alpha")
	inn.set("facility_id", "facility.inn")
	inn.set("building_type", "bar")
	inn.set("bed_count", 4)
	inn.set("housing_capacity", 4)
	host.add_child(inn)
	registry.create_building(_record("building.authored_inn", "facility.inn", 0))
	_expect(projection_bridge.bind_projection(inn, true), "authored inn should bind over a stale record")
	var inn_record: Dictionary = registry.get_building("building.authored_inn")
	_expect(int(inn_record.get("bed_count", 0)) == 4 and int(inn_record.get("housing_capacity", 0)) == 4, "authored composition should repair stale physical bed and housing counts")
	var restored_transform := Transform3D(Basis(Vector3.UP, 0.5), Vector3(9.0, 1.0, -2.0))
	registry.update_building("building.authored_home", {"world_transform": restored_transform})
	_expect(projection.global_transform.is_equal_approx(restored_transform), "registry transform must drive the authored projection")
	host.queue_free()
	_finish()


func _record(building_id: String, facility_id: String, capacity: int) -> Dictionary:
	return {
		"building_id": building_id,
		"settlement_id": "town.alpha",
		"facility_id": facility_id,
		"type_id": "home",
		"display_name": building_id,
		"owner_faction_id": "FactionA",
		"access_state": "private",
		"abandoned": false,
		"operational_state": "operational",
		"bed_count": 0,
		"housing_capacity": capacity,
		"world_transform": Transform3D(Basis.IDENTITY, Vector3(capacity, 0.0, 0.0)),
		"source": "authored",
		"catalog_id": "",
		"foundation_height": 0.0,
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("BUILDING_REGISTRY_VALIDATION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)
