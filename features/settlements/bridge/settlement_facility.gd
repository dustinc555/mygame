@icon("res://addons/world_authoring/icons/facility.svg")
extends Node3D

class_name SettlementFacility

@export var facility_id := ""
@export var display_name := "Facility"
@export_enum("generic", "housing", "farm", "mine", "bar", "shop", "storage", "guard", "social", "police", "weapon_shop", "armor_shop", "travel_shop", "potion_shop", "tavern", "keep") var facility_type := "generic"
@export var owner_faction_id := ""
@export var enabled := true
@export var food_production_per_day := 0.0
@export var food_consumption_per_day := 0.0
@export var storage_capacity_bonus := 0.0
@export var activity_points_root_path: NodePath
@export var linked_node_paths: Array[NodePath] = []


func _ready() -> void:
	add_to_group("settlement_facility")


## Everything inside a facility is the facility owner's property: spawned
## prop items resolve ownership by walking up to these instead of per-node
## stamping, so ownership follows staff turnover automatically.
func get_property_owner_faction() -> String:
	return owner_faction_id


## The person who personally owns the facility's goods (a bar's barkeeper);
## facilities without a personal owner stay faction-owned only.
func get_property_owner_character() -> HumanoidCharacter:
	return null


## Spawn stat bands by competence tier (SkillRules.TIER_*): guards roll
## martial stats trained-to-veteran and everything else
## beginner-to-intermediate; civilians roll beginner-to-intermediate across
## the board. Already-authored levels (anything above default) are never
## lowered.
const GUARD_MARTIAL_RANGE := Vector2i(SkillRules.TIER_TRAINED.x, SkillRules.TIER_VETERAN.y)
const CIVILIAN_RANGE := Vector2i(SkillRules.TIER_BEGINNER.x, SkillRules.TIER_INTERMEDIATE.y)
const MARTIAL_SKILL_IDS: Array[String] = [
	SkillRules.ATTRIBUTE_STRENGTH,
	SkillRules.ATTRIBUTE_DEXTERITY,
	SkillRules.ATTRIBUTE_TOUGHNESS,
	SkillRules.ATTRIBUTE_ENDURANCE,
	SkillRules.COMBAT_SWORDS_ONE_HANDED,
	SkillRules.COMBAT_AXES_ONE_HANDED,
	SkillRules.COMBAT_DAGGERS,
	SkillRules.COMBAT_SHIELDS,
	SkillRules.COMBAT_UNARMED,
]
const GENERAL_SKILL_IDS: Array[String] = [
	SkillRules.ATTRIBUTE_CHARISMA,
	SkillRules.MOVEMENT_RUNNING,
]


static func apply_guard_stat_tiers(actor: Node, rng: RandomNumberGenerator) -> void:
	_apply_stat_tier_rolls(actor, rng, GUARD_MARTIAL_RANGE, CIVILIAN_RANGE)


static func apply_civilian_stat_tiers(actor: Node, rng: RandomNumberGenerator) -> void:
	_apply_stat_tier_rolls(actor, rng, CIVILIAN_RANGE, CIVILIAN_RANGE)


static func _apply_stat_tier_rolls(actor: Node, rng: RandomNumberGenerator, martial_range: Vector2i, general_range: Vector2i) -> void:
	if actor == null or not actor.has_method("set_skill_level") or not actor.has_method("get_skill_level"):
		return
	for skill_id in MARTIAL_SKILL_IDS:
		_roll_stat_if_default(actor, rng, skill_id, martial_range)
	for skill_id in GENERAL_SKILL_IDS:
		_roll_stat_if_default(actor, rng, skill_id, general_range)


static func _roll_stat_if_default(actor: Node, rng: RandomNumberGenerator, skill_id: String, level_range: Vector2i) -> void:
	if int(actor.call("get_skill_level", skill_id)) > SkillRules.DEFAULT_LEVEL:
		return
	var t := (rng.randf() + rng.randf()) * 0.5
	actor.call("set_skill_level", skill_id, clampi(int(round(lerpf(float(level_range.x), float(level_range.y), t))), level_range.x, level_range.y))


## Bind a staff body to the ledger record the world-sim assigned to this slot, re-homing it under
## the given staff root. `actor` is either the worker's already-live body (claimed, e.g. a resident
## the full-town spawner realized) or a body the facility freshly built from the record. Either way
## we drop any orphan record the body was minted with and rebind it to the assigned record id, so
## one record maps to exactly one body and realization honors the world-sim assignment. Identity
## only — the facility's role prep (combat stance, faction, authority, role script) is left intact.
## Static so both facilities (SettlementFacilityInstance) and settlement roots (SettlementAnchor)
## can share it without a common base.
static func adopt_staff_record(actor: Node, worker_actor_id: String, slot_id: String, staff_root: Node = null) -> void:
	if actor == null or not is_instance_valid(actor) or worker_actor_id.strip_edges().is_empty():
		return
	if staff_root != null and is_instance_valid(staff_root) and actor.get_parent() != staff_root:
		var keep_transform := actor is Node3D
		var global_xform := (actor as Node3D).global_transform if keep_transform else Transform3D.IDENTITY
		if actor.get_parent() != null:
			actor.get_parent().remove_child(actor)
		staff_root.add_child(actor)
		if keep_transform:
			(actor as Node3D).global_transform = global_xform
	var tree := actor.get_tree()
	var pop := tree.get_first_node_in_group("population_controller") if tree != null else null
	if pop == null:
		return
	var minted_id := str(actor.get("stable_id")).strip_edges()
	if not minted_id.is_empty() and minted_id != worker_actor_id and pop.has_method("remove_actor_record"):
		pop.call("remove_actor_record", minted_id, false)
	actor.set("stable_id", worker_actor_id)
	actor.set_meta("actor_record_id", worker_actor_id)
	actor.set_meta("settlement_staff_slot_id", slot_id)
	if pop.has_method("mark_actor_realized"):
		pop.call("mark_actor_realized", actor, worker_actor_id)


## Resolve the already-live body for an assigned worker record, if it is currently realized
## (e.g. the full-town spawner realized it as a resident before staffing claimed it). Returns null
## when the worker is only a ledger record, in which case the facility builds a fresh body instead.
static func resolve_live_worker(actor: Node, worker_actor_id: String) -> Node:
	if actor == null or worker_actor_id.strip_edges().is_empty():
		return null
	var tree := actor.get_tree()
	var pop := tree.get_first_node_in_group("population_controller") if tree != null else null
	if pop == null or not pop.has_method("get_live_actor"):
		return null
	var live = pop.call("get_live_actor", worker_actor_id)
	return live if live != null and is_instance_valid(live) else null


func get_facility_id() -> String:
	return facility_id if not facility_id.is_empty() else str(name)


func get_facility_record(settlement_id := "") -> Dictionary:
	return {
		"facility_id": get_facility_id(),
		"settlement_id": settlement_id,
		"display_name": display_name if not display_name.is_empty() else get_facility_id().capitalize(),
		"facility_type": facility_type,
		"owner_faction_id": owner_faction_id,
		"enabled": enabled,
		"world_position": global_position,
		"food_production_per_day": food_production_per_day if enabled else 0.0,
		"food_consumption_per_day": food_consumption_per_day if enabled else 0.0,
		"storage_capacity_bonus": storage_capacity_bonus if enabled else 0.0,
		"activity_point_count": get_activity_points().size(),
		"job_provider_count": get_job_providers().size(),
		"bar_service_area_count": get_bar_service_areas().size(),
	}


func get_activity_points() -> Array:
	var points: Array = []
	var root := get_node_or_null(activity_points_root_path)
	if root == null:
		root = self
	_collect_activity_points(root, points)
	return points


func get_linked_nodes() -> Array:
	var nodes: Array = []
	for node_path in linked_node_paths:
		var node := get_node_or_null(node_path)
		if node != null:
			nodes.append(node)
	return nodes


func get_job_providers() -> Array:
	var providers: Array = []
	_collect_nodes_with_group(self, "job_provider", providers)
	for node in get_linked_nodes():
		_collect_nodes_with_group(node, "job_provider", providers)
	return providers


func get_bar_service_areas() -> Array:
	var service_areas: Array = []
	_collect_nodes_with_group(self, "bar_service_area", service_areas)
	for node in get_linked_nodes():
		_collect_nodes_with_group(node, "bar_service_area", service_areas)
	return service_areas


func _collect_activity_points(root: Node, points: Array) -> void:
	for child in root.get_children():
		if child != self and child.has_method("get_activity_record"):
			points.append(child)
		_collect_activity_points(child, points)


func _collect_nodes_with_group(root: Node, group_name: String, nodes: Array) -> void:
	if root == null:
		return
	if root.is_in_group(group_name) and not nodes.has(root):
		nodes.append(root)
	for child in root.get_children():
		_collect_nodes_with_group(child, group_name, nodes)
