extends SceneTree

const DESK_PATH := "res://features/world/projection/props/furniture/ruler_planning_desk.tscn"

var _failed := false


func _init() -> void:
	var text := FileAccess.get_file_as_string(DESK_PATH)
	_assert(not text.is_empty(), "Ruler planning desk must exist")
	for required in ["Desk.gltf", "shop_counter.gd", "BodyCollision", "TabletopSurface"]:
		_assert(text.contains(required), "Ruler desk lost furniture/workstation part %s" % required)
	for removed in ["PlanningMap", "OpenLedger", "BookStack", "LooseOrders", "Inkwell", "Book_Stack"]:
		_assert(not text.contains(removed), "Baked desk prop must be removed: %s" % removed)
	_assert(text.contains("surface_id = \"ruler_desk\""), "Desk surface needs a stable ID")
	_assert(text.count("required_item = ") == 2, "Desk must have exactly two required slots")
	_assert(text.contains("slot_id = \"ledger\"") and text.contains("town_ledger.tres"), "Required ledger slot is missing")
	_assert(text.contains("slot_id = \"map\"") and text.contains("town_map.tres"), "Required map slot is missing")
	for slot_id in ["candle", "drink", "scroll", "book_left", "book_right"]:
		_assert(text.contains("slot_id = \"%s\"" % slot_id), "Missing authored optional slot %s" % slot_id)
	_assert(text.contains("book_1.tres") and text.contains("book_2.tres") and text.contains("book_3.tres"), "Desk must roll individual book models")
	_assert(text.contains("facility_role_ids = Array[String]([\"ruler\"]"), "Ruler desk must advertise the ruler facility role")
	var keep_scene := FileAccess.get_file_as_string("res://features/settlements/bridge/settlement_keep.tscn")
	var keep_rules := FileAccess.get_file_as_string("res://features/settlements/resources/furnishing/keep.tres")
	var office := FileAccess.get_file_as_string("res://features/world/projection/props/furnishing/vignettes/ruler_office.tscn")
	_assert(not keep_scene.contains("ruler_planning_desk.tscn"), "Empty Keep template must not directly instance the ruler desk")
	_assert(keep_rules.contains("ruler_office.tscn"), "Keep furnish recipe must require the ruler office vignette")
	_assert(office.contains("ruler_planning_desk.tscn") and office.contains("ruler_seat.tscn"), "Ruler office must compose the desk and ruler seat")
	if _failed:
		quit(1)
		return
	print("RULER_PLANNING_DESK_OK")
	quit()


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
