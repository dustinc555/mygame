extends Node

const FIELD_SPECS := [
	{"crop_id": "tomato", "dimensions": Vector2i(4, 4), "origin": Vector3(-13.0, 0.02, -2.0)},
	{"crop_id": "bell_pepper", "dimensions": Vector2i(4, 4), "origin": Vector3(-6.0, 0.02, -2.0)},
	{"crop_id": "eggplant", "dimensions": Vector2i(4, 4), "origin": Vector3(1.0, 0.02, -2.0)},
]

var _farm: Node


func _ready() -> void:
	call_deferred("_setup_scenario")


func get_authored_field_specs() -> Array:
	return FIELD_SPECS.duplicate(true)


func _setup_scenario(retries_remaining := 60) -> void:
	var context := BootstrapContext.active
	if context == null:
		if retries_remaining > 0:
			call_deferred("_setup_scenario", retries_remaining - 1)
		return
	_farm = context.get_optional(&"farming")
	_assign_party_to_town()
	_create_fields()


func _assign_party_to_town() -> void:
	var party_root := get_parent().get_node_or_null("PartyMembers")
	if party_root == null:
		return
	for actor in party_root.get_children():
		if actor is WorldActor:
			actor.set_meta("assigned_settlement_id", "granary_demo")


func _create_fields(retries_remaining := 30) -> void:
	if _farm == null:
		return
	var existing: Dictionary = _farm.get_plots()
	var retry_needed := false
	for spec in FIELD_SPECS:
		var expected_name := "%s Field" % str(spec.get("crop_id", "")).replace("_", " ").capitalize()
		var found := false
		for plot_value in existing.values():
			var plot: Dictionary = plot_value
			if str(plot.get("settlement_id", "")) == "granary_demo" and str(plot.get("display_name", "")) == expected_name:
				found = true
				_ensure_till_requests(plot)
				break
		if found:
			continue
		var dimensions: Vector2i = spec.get("dimensions", Vector2i(4, 4))
		var origin: Vector3 = spec.get("origin", Vector3.ZERO)
		var positions: Array[Vector3] = []
		for z in dimensions.y:
			for x in dimensions.x:
				positions.append(origin + Vector3(float(x) * 1.25, 0.0, float(z) * 1.25))
		var created: Dictionary = _farm.create_plot(positions, dimensions, str(spec.get("crop_id", "")), "Player", "granary_demo")
		if created.is_empty():
			retry_needed = true
		else:
			_ensure_till_requests(created)
	if retry_needed and retries_remaining > 0:
		call_deferred("_create_fields", retries_remaining - 1)


func _ensure_till_requests(plot: Dictionary) -> void:
	var plot_id := str(plot.get("plot_id", ""))
	for cell_key_value in (plot.get("cells", {}) as Dictionary).keys():
		var cell_key := str(cell_key_value)
		var cell: Dictionary = (plot.get("cells", {}) as Dictionary).get(cell_key_value, {})
		if str(cell.get("state", "")) == "untilled" and str(cell.get("requested_operation", "")).is_empty():
			_farm.request_cell_operation(plot_id, cell_key, "till")
