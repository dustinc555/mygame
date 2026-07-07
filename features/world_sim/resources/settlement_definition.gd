@tool
extends Resource

class_name SettlementDefinition

@export var settlement_id := ""
@export var display_name := "Settlement"
@export var faction_definition: Resource
@export var behavior_profile: Resource
@export var personality_profile: Resource
@export var law_profile: Resource
@export var population_name_profile: Resource
# Compatibility default for older authored scenes. SettlementPlacement.world_transform is the canonical world placement for new worlds.
@export var world_position := Vector3.ZERO
@export_enum("Depopulated", "Sparse", "Populated", "Overcrowded") var occupancy_state := 2
@export var starting_food := 60.0
@export var max_food := 160.0
@export var known_settlement_ids: PackedStringArray = PackedStringArray()
@export var default_target_settlement_id := ""
@export var raid_squad_template: Resource
@export var defense_squad_template: Resource

@export_group("Staffing")
@export_range(0, 24, 1) var guard_count := 0
@export_range(0, 24, 1) var guard_post_count := 0
@export var guard_name := "Town Guard"
@export var staff_stable_id_prefix := ""
@export var staff_squad_name := ""
@export var use_settlement_population_for_guards := true

@export_group("Realization")
## "" inherits the realization default; otherwise one of
## full_town / important_plus_near / near_player.
@export var actor_realization_policy := ""

@export_group("Population Seeding")
## 0 randomizes per new game; any other value makes generation deterministic
## (used for testing and for towns that should be the same place every run).
@export var generation_seed := 0
## AuthoredResident entries: hand-authored characters the generator seeds
## first, filling the remaining slots and surplus around them.
@export var authored_residents: Array[Resource] = []

@export_group("Economy Seeds")
@export var starting_wealth := 0.0
@export var starting_supplies := 0.0
@export var population_growth_per_day := 0.0


func get_id() -> String:
	return settlement_id if not settlement_id.is_empty() else display_name


func get_faction_id() -> String:
	return str(faction_definition.call("get_id")) if faction_definition != null and faction_definition.has_method("get_id") else ""


func get_behavior_profile() -> Resource:
	return behavior_profile if behavior_profile != null else _faction_profile("get_behavior_profile", "behavior_profile")


func get_personality_profile() -> Resource:
	return personality_profile if personality_profile != null else _faction_profile("get_personality_profile", "personality_profile")


func get_law_profile() -> Resource:
	return law_profile if law_profile != null else _faction_profile("get_law_profile", "law_profile")


func get_population_name_profile() -> Resource:
	return population_name_profile if population_name_profile != null else _faction_profile("get_population_name_profile", "population_name_profile")


func get_actor_realization_policy() -> String:
	return actor_realization_policy.strip_edges()


func get_guard_name() -> String:
	return guard_name if not guard_name.strip_edges().is_empty() else "Town Guard"


func get_staff_stable_id_prefix() -> String:
	if not staff_stable_id_prefix.strip_edges().is_empty():
		return staff_stable_id_prefix
	return "npc.%s.town_guard" % get_id()


func get_staff_squad_name() -> String:
	return staff_squad_name if not staff_squad_name.strip_edges().is_empty() else display_name


## Deterministic when authored non-zero; otherwise the caller rolls (and
## persists) a per-run seed so replays differ but saves stay stable.
func resolve_generation_seed() -> int:
	return generation_seed


func get_occupancy_multiplier() -> float:
	match occupancy_state:
		0:
			return 0.25
		1:
			return 0.5
		3:
			return 1.25
		_:
			return 1.0


func get_occupancy_label() -> String:
	match occupancy_state:
		0:
			return "Depopulated"
		1:
			return "Sparse"
		3:
			return "Overcrowded"
		_:
			return "Populated"


func _faction_profile(method_name: String, property_name: String) -> Resource:
	if faction_definition == null:
		return null
	if faction_definition.has_method(method_name):
		return faction_definition.call(method_name) as Resource
	return faction_definition.get(property_name) as Resource
