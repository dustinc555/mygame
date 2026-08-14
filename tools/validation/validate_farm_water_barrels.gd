extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_farm_water_barrels.gd

const GAME_HUD_SCENE = preload("res://features/ui/projection/game_hud.tscn")
const WATER_BARRELS_SCENE = preload("res://features/farming/projection/farm_water_cistern.tscn")
const FARM_WORK_BRIDGE = preload("res://features/farming/bridge/farm_work_bridge.gd")
const WATER_SOURCE_SCRIPT_PATH := "res://features/farming/projection/farm_water_source.gd"

class FakeGecs:
	extends Node
	signal world_reindexed
	var water_states: Dictionary = {}
	func get_farm_water_source_states() -> Dictionary:
		return water_states.duplicate(true)
	func upsert_farm_water_source_state(state: Dictionary) -> Dictionary:
		water_states[str(state.get("source_id", ""))] = state.duplicate(true)
		return state.duplicate(true)

class FakeTime:
	extends Node
	func get_absolute_minute() -> int:
		return 10

class FakeFarm:
	extends Node
	signal water_source_changed(source_id: String, state: Dictionary)
	var gecs: FakeGecs
	var draw_calls := 0
	func register_water_source(state: Dictionary) -> Dictionary:
		var source_id := str(state.get("source_id", ""))
		if not gecs.water_states.has(source_id):
			gecs.upsert_farm_water_source_state(state)
		return (gecs.water_states.get(source_id, {}) as Dictionary).duplicate(true)
	func get_water_source(source_id: String) -> Dictionary:
		return (gecs.water_states.get(source_id, {}) as Dictionary).duplicate(true)
	func draw_water_source(source_id: String, requested: float, authorization: Dictionary) -> float:
		draw_calls += 1
		var state: Dictionary = gecs.water_states.get(source_id, {})
		if str(authorization.get("source_id", "")) != source_id or str(authorization.get("owner_faction_name", "")) != str(state.get("owner_faction_name", "")):
			return 0.0
		var owns_source := str(authorization.get("actor_faction_name", "")) == str(state.get("owner_faction_name", "")) or bool(authorization.get("owner_access_approved", false))
		if not owns_source and not bool(authorization.get("theft_approved", false)):
			return 0.0
		var drawn := minf(requested, float(state.get("current_water", 0.0)))
		state["current_water"] = float(state.get("current_water", 0.0)) - drawn
		gecs.upsert_farm_water_source_state(state)
		water_source_changed.emit(source_id, state)
		return drawn

class FakeOwnership:
	extends Node
	var allow_take := true
	var requests := 0
	func request_take_item(_actor: Node, _target) -> bool:
		requests += 1
		return allow_take

class FakeActor:
	extends Node3D
	var faction_name := ""

class FakeActorlessWaterSource:
	extends Node3D
	var actorless_draw_calls := 0
	func draw_water(_requested: float) -> float:
		actorless_draw_calls += 1
		return 5.0

var failures: Array[String] = []
var _ecs_placeholder: Node


func _initialize() -> void:
	if not Engine.has_singleton("ECS"):
		_ecs_placeholder = Node.new()
		Engine.register_singleton("ECS", _ecs_placeholder)
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene_root := Node3D.new()
	root.add_child(scene_root)
	var hud := GAME_HUD_SCENE.instantiate() as CanvasLayer
	scene_root.add_child(hud)
	var context := BootstrapContext.new(scene_root, hud)
	var gecs := FakeGecs.new()
	var time := FakeTime.new()
	var farm := FakeFarm.new()
	var ownership := FakeOwnership.new()
	farm.gecs = gecs
	for service in [gecs, time, farm, ownership]:
		scene_root.add_child(service)
	context.register(&"gecs_world", gecs)
	context.register(&"world_time", time)
	context.register(&"farming", farm)
	context.register(&"ownership", ownership)
	BootstrapContext.active = context

	var barrels = WATER_BARRELS_SCENE.instantiate()
	barrels.source_id = "validation.water_barrels"
	barrels.renewable = false
	barrels.capacity = 80.0
	barrels.current_water = 80.0
	var has_owner_property := _has_property(barrels, "owner_faction_name")
	_expect(has_owner_property, "water barrels author durable ownership")
	if has_owner_property:
		barrels.set("owner_faction_name", "Player")
	scene_root.add_child(barrels)
	await process_frame
	barrels.call("_bind_durable_state")

	_expect(barrels.get_node_or_null("AuthoredBucket") == null, "water barrels contain no decorative fake bucket")
	_expect(barrels.find_children("*", "Label3D", true, false).is_empty(), "idle water barrels contain no world-space metrics")
	var water_source_script := FileAccess.get_file_as_string(WATER_SOURCE_SCRIPT_PATH)
	_expect(not water_source_script.contains("func draw_water("), "water source exposes no actorless ownership bypass")
	_expect(barrels.has_method("get_details_panel_data_at"), "water barrels expose authored details-panel data")
	if barrels.has_method("get_details_panel_data_at"):
		var data: Dictionary = barrels.call("get_details_panel_data_at", barrels.global_position)
		_expect(str(data.get("title", "")) == "Water Barrels", "water-barrel details use a player-facing title")
		_expect(str(data.get("state", "")) == "Full", "full water barrels use a player-facing state")
		_expect(str(data.get("subtitle", "")) == "Owned by Player", "water-barrel details identify their owner")
		_expect(bool(data.get("show_resource_bar", false)), "finite water is shown in the details panel")
		_expect(str(data.get("resource_label", "")) == "Water" and str(data.get("resource_value_text", "")) == "80 / 80", "water amount is named and written clearly in details")

	var details_script = load("res://features/ui/bridge/humanoid_details_controller.gd")
	var details = details_script.new()
	scene_root.add_child(details)
	details.initialize(context)
	await process_frame
	details.inspect_target_at(barrels, barrels.global_position)
	details.call("_update_panel")
	var base := "HudLayout/BottomHud/InspectorSlot/HumanoidDetailsPanel/Margin/DetailsVBox/"
	var name_label := hud.get_node(base + "HeaderRow/Name") as Label
	var faction_label := hud.get_node(base + "Faction") as Label
	var growth_row := hud.get_node(base + "FarmGrowthRow") as Control
	var water_row := hud.get_node(base + "FarmHydrationRow") as Control
	var water_label := hud.get_node(base + "FarmHydrationRow/HydrationLabel") as Label
	var water_value := hud.get_node(base + "FarmHydrationRow/HydrationBarFrame/HydrationBarStack/HydrationValue") as Label
	var action_row := hud.get_node(base + "ActionRow") as Control
	_expect(name_label.text == "Water Barrels", "clicking the barrels opens Water Barrels details")
	_expect(faction_label.visible and faction_label.text == "Owned by Player", "barrel ownership appears in details")
	_expect(not growth_row.visible and water_row.visible, "barrel details show only the relevant resource bar")
	_expect(water_label.text == "Water" and water_value.text == "80 / 80", "barrel details render the authored Water amount")
	_expect(not action_row.visible, "water amount is not rendered as a fake action")

	var owner := FakeActor.new()
	owner.faction_name = "Player"
	var outsider := FakeActor.new()
	outsider.faction_name = "Other"
	scene_root.add_child(owner)
	scene_root.add_child(outsider)
	var actorless_source := FakeActorlessWaterSource.new()
	var work_bridge = FARM_WORK_BRIDGE.new()
	scene_root.add_child(actorless_source)
	scene_root.add_child(work_bridge)
	var refill_actor_key := owner.get_instance_id()
	work_bridge.set("_assignments", {
		refill_actor_key: {"actor": owner, "water_source": actorless_source, "automatic": true},
	})
	work_bridge.call("_complete_refill", refill_actor_key)
	var remaining_assignments: Dictionary = work_bridge.get("_assignments")
	_expect(actorless_source.actorless_draw_calls == 0 and not remaining_assignments.has(refill_actor_key), "worker refill fails closed instead of using an actorless water-draw fallback")
	_expect(barrels.has_method("draw_water_for_actor"), "water draws pass through ownership enforcement")
	if barrels.has_method("draw_water_for_actor"):
		var owner_result: Dictionary = barrels.call("draw_water_for_actor", 5.0, owner)
		_expect(is_equal_approx(float(owner_result.get("drawn", 0.0)), 5.0) and ownership.requests == 0, "the owner can take water without a theft check")
		ownership.allow_take = false
		var calls_before_denial := farm.draw_calls
		var denied: Dictionary = barrels.call("draw_water_for_actor", 5.0, outsider)
		_expect(is_equal_approx(float(denied.get("drawn", -1.0)), 0.0) and ownership.requests == 1, "a non-owner water draw is routed through the theft system")
		_expect(farm.draw_calls == calls_before_denial, "caught theft cannot remove water")
		ownership.allow_take = true
		var stolen: Dictionary = barrels.call("draw_water_for_actor", 5.0, outsider)
		_expect(is_equal_approx(float(stolen.get("drawn", 0.0)), 5.0) and ownership.requests == 2, "an undetected non-owner draw remains a theft attempt before water is removed")
		var empty_state: Dictionary = gecs.water_states[barrels.source_id]
		empty_state["current_water"] = 0.0
		gecs.upsert_farm_water_source_state(empty_state)
		farm.water_source_changed.emit(barrels.source_id, empty_state)
		ownership.allow_take = false
		var requests_before_empty_draw := ownership.requests
		var empty_result: Dictionary = barrels.call("draw_water_for_actor", 5.0, outsider)
		_expect(is_equal_approx(float(empty_result.get("drawn", -1.0)), 0.0) and ownership.requests == requests_before_empty_draw, "an empty source cannot create a theft attempt when no water can be taken")

	BootstrapContext.active = null
	scene_root.free()
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _has_property(value: Object, property_name: String) -> bool:
	for property in value.get_property_list() if value != null else []:
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _finish() -> void:
	if _ecs_placeholder != null:
		Engine.unregister_singleton("ECS")
		_ecs_placeholder.free()
		_ecs_placeholder = null
	if failures.is_empty():
		print("FARM_WATER_BARRELS_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FARM_WATER_BARRELS_FAILED count=%d" % failures.size())
	quit(1)
