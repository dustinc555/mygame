@tool
extends Resource

class_name FactionDefinition

@export var faction_id := ""
@export var display_name := "Faction"
@export_multiline var description := ""
## Unique emblem shown wherever this faction is listed (Factions dock, pickers).
@export var icon: Texture2D
@export var primary_color := Color.WHITE
@export var default_hostile_faction_ids: PackedStringArray = PackedStringArray()
@export var starting_war_faction_ids: PackedStringArray = PackedStringArray()
@export var open_access := true
@export_range(-100, 100, 1) var accepted_reputation_threshold := 0
@export var permanently_hostile := false
## World-sim faction config (editor-driven). Whether this faction seeds nests, and
## which zones it is active in (empty = active everywhere).
@export var spawns_nests := false
@export var active_zone_ids: PackedStringArray = PackedStringArray()
## How this faction manifests live bodies when one of its world-sim squads realizes
## near the player. member_actor_script = the character spawner type (a HumanoidCharacter
## script — generic humanoid, rustdead, etc.), attached in the editor like a race spawner.
@export var member_actor_script: Script
@export_range(1, 20, 1) var default_squad_size := 4
## Aggregate fitness of this faction's squads (endurance + run), 1.0 ≈ a civilian walk.
## Drives world-sim march speed; raids are hard-capped below the player's run so they
## never feel cheaty. (Stands in for the squad's endurance/run aggregate until realized
## bodies carry per-member stats.)
@export_range(0.5, 1.6, 0.05) var squad_march_fitness := 1.0
## Settlements this faction owns (editor-authored, faction-side list).
@export var owned_settlement_ids: PackedStringArray = PackedStringArray()
@export var behavior_profile: Resource
@export var personality_profile: Resource
@export var law_profile: Resource
@export var population_name_profile: Resource
## Appearance profile for this faction's realized squad members (race/skin/clothes), so a
## manifested raider looks like a raider instead of a nameless default body.
@export var population_appearance_profile: Resource


func get_id() -> String:
	return faction_id if not faction_id.is_empty() else display_name


func is_hostile_to(other_faction_id: String) -> bool:
	return not other_faction_id.is_empty() and default_hostile_faction_ids != null and default_hostile_faction_ids.has(other_faction_id)


func does_spawn_nests() -> bool:
	return spawns_nests


func is_active_in_zone(zone_id: String) -> bool:
	return active_zone_ids == null or active_zone_ids.is_empty() or active_zone_ids.has(zone_id)


func get_member_actor_script() -> Script:
	return member_actor_script


func get_default_squad_size() -> int:
	return maxi(1, default_squad_size)


func get_squad_march_fitness() -> float:
	return squad_march_fitness


func get_behavior_profile() -> Resource:
	return behavior_profile


func get_personality_profile() -> Resource:
	return personality_profile


func get_law_profile() -> Resource:
	return law_profile


func get_population_name_profile() -> Resource:
	return population_name_profile
