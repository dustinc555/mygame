extends SceneTree
## Isolated component round-trip; clock integration lives in validate_well_recharge.
var _ecs_placeholder: Node
var failures: Array[String] = []
func _init() -> void:
	if not Engine.has_singleton("ECS"):
		_ecs_placeholder = Node.new()
		Engine.register_singleton("ECS", _ecs_placeholder)
	call_deferred("_run")
func _run() -> void:
	var script = load("res://features/farming/sim/c_game_farm_water_source_state.gd")
	var component = script.new()
	var input := {
		"source_id": "river_barrel", "settlement_id": "river_town", "source_kind": "well",
		"world_position": Vector3(7, 2, 9), "owner_faction_name": "River", "public_water_access": true,
		"capacity": 73.25, "current_water": 42.5, "reserved_incoming_water": 12.0,
		"reserved_outgoing_water": 7.5, "renewable": false,
		"recharge_per_world_minute": 0.125, "last_processed_minute": 42.75,
	}
	component.apply_state(input)
	var restored = script.new()
	restored.apply_state(component.to_state())
	_expect(restored != component and restored.to_state() == input, "every durable field round-trips on a distinct component, including nondefault capacity and fractional clock")
	component.apply_state({"capacity": 10.0, "current_water": 3.0, "reserved_incoming_water": 99.0, "reserved_outgoing_water": 99.0})
	var limited: Dictionary = component.to_state()
	_expect(limited.current_water == 3.0 and limited.reserved_incoming_water == 7.0 and limited.reserved_outgoing_water == 3.0, "reservations cannot exceed free capacity or existing water")
	component.apply_state({"current_water": 50.0})
	_expect(component.to_state().current_water == 10.0 and component.to_state().reserved_incoming_water == 0.0, "overfull source clamps and clears impossible incoming reservation")
	component.apply_state({"capacity": -1.0, "current_water": -2.0, "reserved_incoming_water": -3.0, "reserved_outgoing_water": -4.0, "recharge_per_world_minute": -1.0, "last_processed_minute": -1.0})
	limited = component.to_state()
	for field in ["capacity", "current_water", "reserved_incoming_water", "reserved_outgoing_water", "recharge_per_world_minute", "last_processed_minute"]:
		_expect(limited[field] == 0.0, "%s clamps negative input" % field)
	component = null
	restored = null
	if _ecs_placeholder != null:
		Engine.unregister_singleton("ECS")
		_ecs_placeholder.free()
	for failure in failures: push_error(failure)
	print("FARMING_WATER_STATE_OK" if failures.is_empty() else "FARMING_WATER_STATE_FAILED")
	quit(0 if failures.is_empty() else 1)
func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
