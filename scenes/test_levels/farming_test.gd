extends Node3D

var _farm: Node
var _world_time: Node


func _ready() -> void:
	call_deferred("_setup_farming_test")


func _setup_farming_test() -> void:
	var context := BootstrapContext.active
	if context == null:
		return
	_farm = context.get_optional(&"farming")
	_world_time = context.get_optional(&"world_time")
	_assign_test_city_members()
	%AdvanceTime.pressed.connect(_advance_time)
	%Rain.pressed.connect(_apply_rain)
	_create_starter_plot()


func _assign_test_city_members() -> void:
	var party_root := get_node_or_null("PartyMembers")
	if party_root == null:
		return
	for actor in party_root.get_children():
		if str(actor.get("faction_name")) == "Player":
			actor.set_meta("assigned_settlement_id", "farming_test")


func _create_starter_plot() -> void:
	if _farm == null or not _farm.get_plots().is_empty():
		return
	var positions: Array[Vector3] = []
	for z in 3:
		for x in 4:
			positions.append(Vector3(2.0 + float(x) * 1.25, 0.02, -3.0 + float(z) * 1.25))
	var plot: Dictionary = _farm.create_plot(positions, Vector2i(4, 3), "", "Player", "farming_test", {"1:1": "rock"})
	# Preworked test fixture: these cells use the real till-work transition so the
	# scene demonstrates connected soil growing through physical completion.
	for cell_key in ["1:0", "2:0", "3:0", "3:1", "3:2"]:
		var request: Dictionary = _farm.request_cell_operation(str(plot.get("plot_id", "")), cell_key, "till")
		var cell: Dictionary = (request.get("cells", {}) as Dictionary).get(cell_key, {})
		_farm.apply_work(str(plot.get("plot_id", "")), cell_key, "till", 999.0, 0.0, int(cell.get("request_revision", -1)))

func _advance_time() -> void:
	if _world_time != null:
		_world_time.advance_hours(12.0)


func _apply_rain() -> void:
	if _farm != null:
		_farm.apply_rain(12.0)
