extends SceneTree

const START_REQUEST_SCRIPT := preload("res://scripts/sim/battle/combat_encounter_start_request.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	_validate_strict_intents()
	_validate_round_trip_contract()
	_validate_party_only_side_is_allowed()
	_validate_live_refs_are_rejected()
	_finish()


func _validate_strict_intents() -> void:
	var expected := ["attack", "defend", "flee", "guard", "raid", "debug"]
	_expect(START_REQUEST_SCRIPT.intent_values() == expected, "Encounter start intents are the approved strict set")
	_expect(START_REQUEST_SCRIPT.is_valid_intent("raid"), "Encounter start accepts approved intent")
	_expect(not START_REQUEST_SCRIPT.is_valid_intent("ambush"), "Encounter start rejects unapproved intent")
	var request = _request_from_source(_valid_request_source())
	request.initial_intent = "ambush"
	_expect(not request.validation_errors().is_empty(), "Invalid intent fails request validation")


func _validate_round_trip_contract() -> void:
	var request = _request_from_source(_valid_request_source())
	var errors: Array[String] = request.validation_errors()
	_expect(errors.is_empty(), "Valid encounter start request passes validation: %s" % str(errors))
	var record: Dictionary = request.to_dictionary()
	_expect(str(record.get("encounter_id", "")) == "encounter:validation:start_contract", "Request preserves encounter_id")
	_expect(str(record.get("initial_intent", "")) == "debug", "Request preserves initial_intent")
	_expect(str(record.get("resolution_policy", "")) == "hold_engaged", "Request preserves resolution_policy")
	_expect(str(record.get("source_type", "")) == "debug_1v1", "Request preserves source_type")
	_expect(record.get("encounter_center", null) is Vector3, "Request preserves encounter_center")
	_expect(record.get("visibility_flags", {}) is Dictionary, "Request exposes visibility_flags")
	_expect(record.get("projection_flags", {}) is Dictionary, "Request exposes projection_flags")
	_expect(record.get("leash_context", {}) is Dictionary, "Request preserves optional leash_context")
	_expect(record.get("raid_context", {}) is Dictionary, "Request preserves optional raid_context")
	var sides: Array = record.get("sides", []) if record.get("sides", []) is Array else []
	_expect(sides.size() == 2, "Request preserves two encounter sides")
	if sides.size() >= 2 and sides[0] is Dictionary and sides[1] is Dictionary:
		var side_a: Dictionary = sides[0]
		var side_b: Dictionary = sides[1]
		_expect(bool(side_a.get("player_owned", false)), "Request supports one player-owned side")
		_expect(str(side_a.get("party_id", "")) == "player_party", "Player side preserves party_id")
		_expect(_string_array(side_b.get("role_markers", [])).has("raider"), "Hostile side preserves role marker")
		var members: Array = side_a.get("member_refs", []) if side_a.get("member_refs", []) is Array else []
		_expect(members.size() == 2, "Side preserves stable member refs")
		if members.size() >= 2 and members[0] is Dictionary and members[1] is Dictionary:
			_expect(str((members[0] as Dictionary).get("member_id", "")) == "player.mira", "Dictionary member ref keeps member_id")
			_expect(str((members[1] as Dictionary).get("member_id", "")) == "player.tomas", "String member ref normalizes to member_id")


func _validate_party_only_side_is_allowed() -> void:
	var source := _valid_request_source()
	var sides: Array = source.get("sides", [])
	if sides.size() > 0 and sides[0] is Dictionary:
		var side: Dictionary = sides[0]
		side.erase("squad_id")
		side["member_refs"] = []
		sides[0] = side
		source["sides"] = sides
	var request = _request_from_source(source)
	_expect(request.validation_errors().is_empty(), "Contract allows a party-id side before adapter resolution")


func _validate_live_refs_are_rejected() -> void:
	var live_node := Node.new()
	var node_source := _valid_request_source()
	node_source["leash_context"] = {"actor_ref": live_node}
	var node_request = _request_from_source(node_source)
	_expect(not node_request.validation_errors().is_empty(), "Request rejects live Node references")
	live_node.free()
	var path_source := _valid_request_source()
	path_source["guard_context"] = {"post_path": NodePath("../GuardPost")}
	var path_request = _request_from_source(path_source)
	_expect(not path_request.validation_errors().is_empty(), "Request rejects NodePath references")
	var member_node := Node.new()
	var member_source := _valid_request_source()
	var sides: Array = member_source.get("sides", [])
	if sides.size() > 0 and sides[0] is Dictionary:
		var side: Dictionary = sides[0]
		side["member_refs"] = [{"member_id": member_node}]
		sides[0] = side
		member_source["sides"] = sides
	var member_request = _request_from_source(member_source)
	_expect(not member_request.validation_errors().is_empty(), "Request rejects live refs in member identifiers")
	member_node.free()


func _request_from_source(source: Dictionary):
	var request = START_REQUEST_SCRIPT.new()
	request.call("apply_dictionary", source)
	return request


func _valid_request_source() -> Dictionary:
	return {
		"encounter_id": "encounter:validation:start_contract",
		"initial_intent": "debug",
		"resolution_policy": "hold_engaged",
		"source_type": "debug_1v1",
		"encounter_center": Vector3(2.0, 0.0, -3.0),
		"projection_importance": "important",
		"visibility_flags": {"force_visible": true},
		"projection_flags": {"important": true},
		"leash_context": {"chase_radius": 24.0},
		"raid_context": {"raid_id": "raid.validation"},
		"sides": [
			{
				"side_id": "player",
				"faction_id": "Player",
				"party_id": "player_party",
				"squad_id": "player.squad",
				"player_owned": true,
				"role_markers": ["player_party"],
				"member_refs": [
					{"member_id": "player.mira", "actor_id": "player.mira"},
					"player.tomas",
				],
				"starting_position": Vector3.ZERO,
			},
			{
				"side_id": "raiders",
				"faction_id": "Raiders",
				"squad_id": "raider.squad",
				"role_markers": ["hostile", "raider"],
				"member_refs": ["raider.001", "raider.002"],
				"starting_position": Vector3(4.0, 0.0, 0.0),
			},
		],
	}


func _string_array(value) -> Array[String]:
	var result: Array[String] = []
	if not (value is Array) and not (value is PackedStringArray):
		return result
	for entry in value:
		var text := str(entry).strip_edges()
		if not text.is_empty():
			result.append(text)
	return result


func _finish() -> void:
	if _failures.is_empty():
		print("COMBAT_ENCOUNTER_START_CONTRACT_VALIDATION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
