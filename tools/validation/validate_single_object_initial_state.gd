extends SceneTree
## Authored single-object properties must exist before the child's _ready snapshot.
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var facility = load("res://features/settlements/bridge/settlement_tank.tscn").instantiate()
	facility.facility_id = "validation.water_tank"
	facility.object_property_overrides = {"assigned_liquid_id": "water", "current_liters": 23.0}
	root.add_child(facility)
	var tank = facility.get_single_object()
	var authored: Dictionary = tank.get_authored_liquid_state()
	if str(authored.get("assigned_liquid_id", "")) != "water" or not is_equal_approx(float(authored.get("current_liters", 0.0)), 23.0):
		failures.append("tank snapshots authored water assignment and liters before durable binding")
	if str(authored.get("liquid_container_id", "")) != "validation.water_tank.container":
		failures.append("tank snapshots its final stable identity before durable binding")
	facility.free()
	for failure in failures:
		push_error(failure)
	print("SINGLE_OBJECT_INITIAL_STATE_OK" if failures.is_empty() else "SINGLE_OBJECT_INITIAL_STATE_FAILED")
	quit(0 if failures.is_empty() else 1)
