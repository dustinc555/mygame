extends Node

class_name SettlementCensus

## World-sim population census: every settlement resident is a real
## PopulationController record, and a town's population is the count of its
## living records. Owns the born-settled seeding pass (day zero mints a
## record for every staff slot plus occupancy-driven surplus, honoring the
## definition's generation_seed and authored residents) and the daily growth
## tick (food/fear/housing-gated record minting plus fear decay). Backfill
## poaching lives with the slot truth in SettlementController; theatre
## realization picks from these records, so the crowd is the census.

const SERVICE_ID := &"settlement_census"

const GENERATED_SOURCE := "census"
const AUTHORED_SOURCE := "census_authored"
const FEAR_DECAY_PER_DAY := 0.05
## Overcrowded towns seed (and can grow) past housing by this factor at most.
const OVERCROWD_LIMIT := 1.25

var _context: BootstrapContext


func initialize(context: BootstrapContext) -> void:
	_context = context
	var world_time: Node = context.get_optional(WorldTimeController.SERVICE_ID)
	if world_time != null and world_time.has_signal("day_changed"):
		var day_changed := Callable(self, "_on_day_changed")
		if not world_time.is_connected("day_changed", day_changed):
			world_time.connect("day_changed", day_changed)


func _ready() -> void:
	add_to_group("settlement_census")


## --- Born settled -------------------------------------------------------------


func seed_settlement(settlement_id: String) -> void:
	var settlement := _settlement_controller()
	var population := _population_controller()
	if settlement == null or population == null:
		return
	var definition := settlement.get_settlement_definition(settlement_id) as SettlementDefinition
	if definition == null:
		return
	if not _census_records(population, settlement_id).is_empty():
		# Already seeded (this run or a loaded save) — reconcile the count only.
		_reconcile_population(settlement, population, settlement_id)
		return
	var state: Dictionary = settlement.get_settlement_state(settlement_id)
	var seeded_count := _compute_seed_count(state, definition)
	var generation_seed := _resolve_generation_seed(definition)
	var context := _generation_context(definition, generation_seed)
	var authored_count := _seed_authored_residents(population, settlement_id, definition, context)
	var generated_count: int = max(0, seeded_count - authored_count)
	population.call("ensure_generated_population", settlement_id, GENERATED_SOURCE, generated_count, context)
	_reconcile_population(settlement, population, settlement_id)
	settlement.bootstrap_staff_vacancies(settlement_id)


## Fill policy: occupancy scales the housing target — Sparse towns start
## half-filled with open slots (that is correct, not a bug), Populated towns
## start full, Overcrowded past the cap. Staffing then claims what exists.
func _compute_seed_count(state: Dictionary, definition: SettlementDefinition) -> int:
	var required_staff: int = max(0, int(state.get("population_required_staff", 0)))
	var housing_target: int = max(0, int(state.get("population_target", 0)))
	var base: int = maxi(housing_target, required_staff)
	var multiplier := definition.get_occupancy_multiplier()
	var seeded := clampi(int(round(float(base) * multiplier)), 0, int(ceil(float(base) * OVERCROWD_LIMIT)))
	if multiplier >= 1.0:
		seeded = maxi(seeded, required_staff)
	return seeded


func _seed_authored_residents(population: Node, settlement_id: String, definition: SettlementDefinition, context: Dictionary) -> int:
	var authored := 0
	for index in range(definition.authored_residents.size()):
		var entry := definition.authored_residents[index] as AuthoredResident
		if entry == null:
			continue
		var overrides := {}
		var character := entry.character
		if character != null and character.has_method("to_record"):
			overrides = character.call("to_record")
		if not entry.pinned_role_id.strip_edges().is_empty():
			overrides["role_id"] = entry.pinned_role_id.strip_edges()
		if not entry.stable_id.strip_edges().is_empty():
			overrides["actor_id"] = entry.stable_id.strip_edges()
			overrides["stable_id"] = entry.stable_id.strip_edges()
		var record: Dictionary = population.call("ensure_authored_record", settlement_id, AUTHORED_SOURCE, index + 1, context, overrides)
		if not record.is_empty():
			authored += 1
	return authored


## Authored non-zero = reproducible town (testing, canon places); zero rolls
## a fresh seed per new game. Rolled seeds persist implicitly: the minted
## records ARE the outcome, saved with the world.
func _resolve_generation_seed(definition: SettlementDefinition) -> int:
	if definition.generation_seed != 0:
		return definition.generation_seed
	return randi()


func _generation_context(definition: SettlementDefinition, generation_seed: int) -> Dictionary:
	var faction := definition.faction_definition
	return {
		"role_id": "resident",
		"faction_id": definition.get_faction_id(),
		"squad_name": definition.get_staff_squad_name(),
		"member_name_prefix": "Resident",
		"generation_seed": generation_seed,
		"population_name_profile": definition.get_population_name_profile(),
		"population_appearance_profile": faction.get("population_appearance_profile") if faction != null else null,
	}


## --- Daily tick ----------------------------------------------------------------


func _on_day_changed(_day_index: int) -> void:
	var settlement := _settlement_controller()
	var population := _population_controller()
	if settlement == null or population == null:
		return
	for state_value in settlement.get_all_settlement_states():
		var state: Dictionary = state_value
		var settlement_id := str(state.get("settlement_id", ""))
		if settlement_id.is_empty():
			continue
		var definition := settlement.get_settlement_definition(settlement_id) as SettlementDefinition
		if definition == null:
			continue
		if float(state.get("fear", 0.0)) > 0.0:
			settlement.adjust_fear(settlement_id, -FEAR_DECAY_PER_DAY, "daily_decay")
		var growth := _compute_daily_growth(state, definition)
		if growth > 0:
			var context := _generation_context(definition, _resolve_generation_seed(definition))
			var current_residents: int = _resident_record_count(population, settlement_id)
			population.call("ensure_generated_population", settlement_id, GENERATED_SOURCE, current_residents + growth, context)
		_reconcile_population(settlement, population, settlement_id)


## How many new residents (births/arrivals) a settlement gains today.
## state carries: "population", "population_target" (housing cap), "fear"
## (0-1), "food_ratio" (0-1), "pressure_state" ("supplied"/"hungry"/
## "starving"), "wealth", "supplies". definition carries
## population_growth_per_day (authored base rate) and
## get_occupancy_multiplier(). Return 0 to stall growth.
@warning_ignore("unused_parameter")
func _compute_daily_growth(state: Dictionary, definition: SettlementDefinition) -> int:
	# TODO(human)
	return 0


## --- Record accounting ----------------------------------------------------------


func _reconcile_population(settlement: SettlementController, population: Node, settlement_id: String) -> void:
	var alive := int(population.call("count_alive_records_for_settlement", settlement_id))
	var state: Dictionary = settlement.get_settlement_state(settlement_id)
	if alive != int(state.get("population", -1)):
		settlement.set_population_total(settlement_id, alive, "census_reconcile")


func _census_records(population: Node, settlement_id: String) -> Array:
	var result: Array = []
	for record_value in population.call("get_records_for_settlement", settlement_id):
		if not (record_value is Dictionary):
			continue
		var source := str((record_value as Dictionary).get("generation_source", ""))
		if source == GENERATED_SOURCE or source == AUTHORED_SOURCE:
			result.append(record_value)
	return result


func _resident_record_count(population: Node, settlement_id: String) -> int:
	var count := 0
	for record_value in _census_records(population, settlement_id):
		var record: Dictionary = record_value
		if str(record.get("role_id", "resident")) != "resident":
			continue
		if int(record.get("life_state", 0)) == NpcRules.LifeState.DEAD:
			continue
		count += 1
	return count


## --- Service resolution -----------------------------------------------------------


func _settlement_controller() -> SettlementController:
	if _context == null:
		return null
	return _context.get_optional(SettlementController.SERVICE_ID) as SettlementController


func _population_controller() -> Node:
	if _context == null:
		return null
	return _context.get_optional(&"population")
