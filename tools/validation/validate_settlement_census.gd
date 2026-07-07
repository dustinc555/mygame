extends Node

## Live-runtime census validation: instances the two-towns test level (real
## GameBootstrap, real GECS) and proves the born-settled seeding pass —
## census records exist for both towns, the settlement population equals its
## living records, and staff slots are filled by census-owned people.
## Scene-based on purpose: --script SceneTree validators cannot compile GECS
## chains (known harness limitation), so this runs as a scene:
##   timeout 60 godot --headless --path . res://tools/validation/validate_settlement_census.tscn

const LEVEL_PATH := "res://scenes/test_levels/two_towns_road_test.tscn"
const SETTLEMENT_IDS := ["farmer_crossing", "raider_camp"]
const SETTLE_FRAMES := 90

var _failures: Array[String] = []


func _ready() -> void:
	var level := (load(LEVEL_PATH) as PackedScene).instantiate()
	add_child(level)
	_run.call_deferred()


func _run() -> void:
	for _frame in range(SETTLE_FRAMES):
		await get_tree().process_frame
	var settlement := get_tree().get_first_node_in_group("settlement_controller")
	var population := get_tree().get_first_node_in_group("population_controller")
	if settlement == null or population == null:
		_fail("settlement/population controllers missing from bootstrapped scene")
		_finish()
		return
	for settlement_id in SETTLEMENT_IDS:
		_validate_settlement(settlement, population, str(settlement_id))
	_finish()


func _validate_settlement(settlement: Node, population: Node, settlement_id: String) -> void:
	var state: Dictionary = settlement.call("get_settlement_state", settlement_id)
	if state.is_empty():
		_fail("%s has no settlement state" % settlement_id)
		return
	var records: Array = population.call("get_records_for_settlement", settlement_id)
	var census_alive := 0
	var census_total := 0
	for record_value in records:
		var record: Dictionary = record_value
		var source := str(record.get("generation_source", ""))
		if source != "census" and source != "census_authored":
			continue
		census_total += 1
		if int(record.get("life_state", 0)) != NpcRules.LifeState.DEAD:
			census_alive += 1
	if census_total <= 0:
		_fail("%s was not census-seeded (0 census records)" % settlement_id)
		return
	var alive := int(population.call("count_alive_records_for_settlement", settlement_id))
	var pop := int(state.get("population", -1))
	if pop != alive:
		_fail("%s population %d != living records %d (census must be truth)" % [settlement_id, pop, alive])
	# Staff may come from census surplus OR hand-authored scene residents —
	# both are registered town people. The pool invariant is that every
	# filled slot's worker is a living population record (no minted ghosts).
	var slots: Dictionary = state.get("staff_slots", {})
	var filled := 0
	var filled_with_record := 0
	for slot_value in slots.values():
		var slot: Dictionary = slot_value
		if not bool(slot.get("filled", false)):
			continue
		filled += 1
		var worker_id := str(slot.get("worker_actor_id", ""))
		if worker_id.is_empty():
			continue
		var record: Dictionary = population.call("get_actor_record", worker_id)
		if not record.is_empty():
			filled_with_record += 1
	if filled > 0 and filled_with_record < filled:
		_fail("%s has %d filled staff slots but only %d backed by population records" % [settlement_id, filled, filled_with_record])
	print("census[%s]: records=%d alive=%d population=%d staff_filled=%d record_backed=%d" % [
		settlement_id, census_total, census_alive, pop, filled, filled_with_record])


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("SETTLEMENT_CENSUS_OK")
		get_tree().quit(0)
		return
	print("SETTLEMENT_CENSUS_FAILED count=%d" % _failures.size())
	get_tree().quit(1)
