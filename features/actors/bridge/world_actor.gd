class_name WorldActor
extends CharacterBody3D

## Thin coordinator and movement actuator.
##
## Owns: lifecycle, capability registry, NavigationAgent3D actuation, move_and_slide.
## Everything else delegates to an ActorCapability or a child node.
## Do not add gameplay logic here — add a capability.

signal life_state_changed(previous_state: int, new_state: int)
signal died(actor: Node)
signal state_changed()
signal inventory_changed()

# ---------------------------------------------------------------------------
# Identity / faction fields and vitals compatibility properties.
# ---------------------------------------------------------------------------

@export var stable_id: String = ""
@export var actor_id: String = ""
@export var member_name: String = ""
@export var faction_name: String = ""
@export var squad_name: String = ""
@export var hostile_factions: PackedStringArray = PackedStringArray()
# World-sim squad membership stamp. The squad LOD swap looks realized members up by
# this id (is_faction_squad_realized / derealize / drive) — without it every LOD tick
# re-realizes the squad and duplicates its bodies endlessly.
@export var world_squad_id := ""

# Combat perception/config authored per actor. GameCombatStateSyncSystem mirrors these
# into C_GameCombatConfig each GECS tick; the component defaults are 0, so deleting any
# of these silently disables combat scanning (that regression shipped once — keep them).
@export var aggressive_scan_radius := NpcRules.AGGRO_RANGE
@export var assist_scan_radius := NpcRules.ASSIST_RANGE
@export var combat_witness_radius := NpcRules.COMBAT_WITNESS_RANGE
@export var combat_squad_assist_radius := NpcRules.SQUAD_ASSIST_RANGE
@export var combat_active_attack_slots := 3
@export var combat_consider_retarget_interval_seconds := 0.5
@export var combat_consider_retarget_jitter_seconds := 0.25

# Needs authoring; NeedsCapability owns the runtime state (see get_needs()).
# Live-forwarding: changing these before OR after the capability exists works.
var _authored_hunger_enabled := false
var _authored_fatigue_enabled := true
@export var hunger_enabled := false:
	get:
		var needs := get_needs()
		return needs.hunger_enabled if needs != null else _authored_hunger_enabled
	set(value):
		_authored_hunger_enabled = value
		var needs := get_needs()
		if needs != null:
			needs.hunger_enabled = value
@export var fatigue_enabled := true:
	get:
		var needs := get_needs()
		return needs.fatigue_enabled if needs != null else _authored_fatigue_enabled
	set(value):
		_authored_fatigue_enabled = value
		var needs := get_needs()
		if needs != null:
			needs.fatigue_enabled = value

# Assist toggles (party behavior bar + town staff defaults); persisted into
# population records, so they must exist as real properties.
@export var auto_heal_enabled := false
@export var auto_burn_rustdead_enabled := false

# Authored starting skills, owned by StatsCapability at runtime; buffered here so
# spawner scripts can assign before add_child (same pattern as the base stats).
var _pending_starting_skill_levels: Dictionary = {}
var starting_skill_levels: Dictionary:
	get:
		var stats := get_stats()
		return stats.starting_skill_levels if stats != null else _pending_starting_skill_levels
	set(value):
		_pending_starting_skill_levels = value if value != null else {}
		var stats := get_stats()
		if stats != null:
			stats.starting_skill_levels = _pending_starting_skill_levels

var hunger: float:
	get:
		var needs := get_needs()
		return needs.hunger if needs != null else 100.0
	set(value):
		var needs := get_needs()
		if needs != null:
			needs.hunger = clampf(value, 0.0, 100.0)

var fatigue: float:
	get:
		var needs := get_needs()
		return needs.fatigue if needs != null else 100.0
	set(value):
		var needs := get_needs()
		if needs != null:
			needs.fatigue = clampf(value, 0.0, 100.0)
@export var combat_stance: int = 0
@export var player_party_member: bool = false
## Authored starting equipment (Array of ItemDefinition or stock entries). Seeded
## into EquipmentCapability on ready. External code sets this before _ready.
@export var starting_equipment: Array = []

## Authored inventory config + starting items, read by InventoryCapability on ready.
@export var inventory_columns := 10
@export var inventory_rows := 4
@export var max_carry_weight := 60.0
@export var starting_items: Array = []

var _pending_life_state: int = NpcRules.LifeState.ALIVE
var _pending_max_hp: float = 100.0
var _pending_hp: float = 100.0
var _pending_base_max_blood: float = 0.0
var _pending_max_blood: float = 100.0
var _pending_blood: float = 100.0
var _pending_stats_config: Dictionary = {}

@export_range(0, 5, 1) var life_state: int = NpcRules.LifeState.ALIVE:
	get:
		var vitals := get_vitals()
		return vitals.life_state if vitals != null else _pending_life_state
	set(value):
		_pending_life_state = value
		var vitals := get_vitals()
		if vitals != null:
			vitals.set_life_state(value)

@export var max_hp: float = 100.0:
	get:
		var vitals := get_vitals()
		return vitals.max_hp if vitals != null else _pending_max_hp
	set(value):
		_pending_max_hp = maxf(value, 1.0)
		var vitals := get_vitals()
		if vitals != null:
			vitals.set_max_hp(value)

@export var hp: float = 100.0:
	get:
		var vitals := get_vitals()
		return vitals.hp if vitals != null else _pending_hp
	set(value):
		_pending_hp = value
		var vitals := get_vitals()
		if vitals != null:
			vitals.set_hp(value)

@export var base_max_blood: float = 0.0:
	get:
		var vitals := get_vitals()
		return vitals.base_max_blood if vitals != null else _pending_base_max_blood
	set(value):
		_pending_base_max_blood = maxf(value, 0.0)
		var vitals := get_vitals()
		if vitals != null:
			vitals.set_base_max_blood(value)

@export var max_blood: float = 100.0:
	get:
		var vitals := get_vitals()
		return vitals.max_blood if vitals != null else _pending_max_blood
	set(value):
		_pending_max_blood = maxf(value, 1.0)
		var vitals := get_vitals()
		if vitals != null:
			vitals.set_max_blood(value)

@export var blood: float = 100.0:
	get:
		var vitals := get_vitals()
		return vitals.blood if vitals != null else _pending_blood
	set(value):
		_pending_blood = value
		var vitals := get_vitals()
		if vitals != null:
			vitals.set_blood(value)

# Base combat/needs stats are owned by StatsCapability. These properties buffer values
# assigned before capabilities exist (spawner scripts configure actors before add_child)
# and forward once the capability is live — the same pattern as the vitals fields above.
# Defaults must match the StatsCapability declarations.
var base_attack_damage: float:
	get:
		var stats := get_stats()
		return stats.base_attack_damage if stats != null else float(_pending_stats_config.get("base_attack_damage", 18.0))
	set(value):
		_pending_stats_config["base_attack_damage"] = value
		var stats := get_stats()
		if stats != null:
			stats.base_attack_damage = value

var attack_range: float:
	get:
		var stats := get_stats()
		return stats.attack_range if stats != null else float(_pending_stats_config.get("attack_range", 1.15))
	set(value):
		_pending_stats_config["attack_range"] = value
		var stats := get_stats()
		if stats != null:
			stats.attack_range = value

var attack_cooldown_seconds: float:
	get:
		var stats := get_stats()
		return stats.attack_cooldown_seconds if stats != null else float(_pending_stats_config.get("attack_cooldown_seconds", 1.2))
	set(value):
		_pending_stats_config["attack_cooldown_seconds"] = value
		var stats := get_stats()
		if stats != null:
			stats.attack_cooldown_seconds = value

var attack_cut_ratio: float:
	get:
		var stats := get_stats()
		return stats.attack_cut_ratio if stats != null else float(_pending_stats_config.get("attack_cut_ratio", 0.05))
	set(value):
		_pending_stats_config["attack_cut_ratio"] = value
		var stats := get_stats()
		if stats != null:
			stats.attack_cut_ratio = value

var base_dodge_chance: float:
	get:
		var stats := get_stats()
		return stats.base_dodge_chance if stats != null else float(_pending_stats_config.get("base_dodge_chance", 0.08))
	set(value):
		_pending_stats_config["base_dodge_chance"] = value
		var stats := get_stats()
		if stats != null:
			stats.base_dodge_chance = value

var base_block_chance: float:
	get:
		var stats := get_stats()
		return stats.base_block_chance if stats != null else float(_pending_stats_config.get("base_block_chance", 0.06))
	set(value):
		_pending_stats_config["base_block_chance"] = value
		var stats := get_stats()
		if stats != null:
			stats.base_block_chance = value

var block_damage_multiplier: float:
	get:
		var stats := get_stats()
		return stats.block_damage_multiplier if stats != null else float(_pending_stats_config.get("block_damage_multiplier", 0.4))
	set(value):
		_pending_stats_config["block_damage_multiplier"] = value
		var stats := get_stats()
		if stats != null:
			stats.block_damage_multiplier = value

var hunger_drain_rate: float:
	get:
		var stats := get_stats()
		return stats.hunger_drain_rate if stats != null else float(_pending_stats_config.get("hunger_drain_rate", 0.08))
	set(value):
		_pending_stats_config["hunger_drain_rate"] = value
		var stats := get_stats()
		if stats != null:
			stats.hunger_drain_rate = value

var _current_blunt_damage: float:
	get:
		return get_blunt_damage()
	set(value):
		var vitals := get_vitals()
		if vitals != null:
			vitals.set_blunt_damage(value)

var _current_open_cut_damage: float:
	get:
		return get_open_cut_damage()
	set(value):
		var vitals := get_vitals()
		if vitals != null:
			vitals.set_open_cut_damage(value)

var _current_bandaged_cut_damage: float:
	get:
		return get_bandaged_cut_damage()
	set(value):
		var vitals := get_vitals()
		if vitals != null:
			vitals.set_bandaged_cut_damage(value)

var _bleed_rate: float:
	get:
		var vitals := get_vitals()
		return vitals.bleed_rate if vitals != null else 0.0
	set(value):
		var vitals := get_vitals()
		if vitals != null:
			vitals.set_bleed_rate(value)

var _bleed_burst_rate: float:
	get:
		var vitals := get_vitals()
		return vitals.bleed_burst_rate if vitals != null else 0.0
	set(value):
		var vitals := get_vitals()
		if vitals != null:
			vitals.set_bleed_burst_rate(value)

## Inventory is read directly as `actor.inventory` in many systems, so it is a
## computed proxy onto InventoryCapability (which owns the InventoryData).
var inventory: InventoryData:
	get:
		var inv := get_inventory()
		return inv.inventory if inv != null else null
	set(value):
		var inv := get_inventory()
		if inv != null:
			inv.inventory = value

var _migration_legal_status: ActorLegalStatus = ActorLegalStatus.new()

# ---------------------------------------------------------------------------
# Capability registry
# ---------------------------------------------------------------------------

var _capabilities: Dictionary = {}


func add_capability(cap: ActorCapability) -> void:
	_capabilities[cap.get_capability_id()] = cap


func get_capability(id: StringName) -> ActorCapability:
	return _capabilities.get(id)


func has_capability(id: StringName) -> bool:
	return _capabilities.has(id)

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _enter_tree() -> void:
	_create_actor_capabilities()
	for cap in _capabilities.values():
		(cap as ActorCapability).setup(self)


func _ready() -> void:
	_configure_world_actor_movement()
	for cap in _capabilities.values():
		(cap as ActorCapability).ready()
	var inv := get_inventory()
	if inv != null and not inv.inventory_changed.is_connected(_on_inventory_capability_changed):
		inv.inventory_changed.connect(_on_inventory_capability_changed)


## Re-emits the actor-level inventory_changed signal that external systems connect to.
func _on_inventory_capability_changed() -> void:
	inventory_changed.emit()


func _exit_tree() -> void:
	for cap in _capabilities.values():
		(cap as ActorCapability).teardown()
	_capabilities.clear()


func _process(delta: float) -> void:
	for cap in _capabilities.values():
		var c := cap as ActorCapability
		if c.enabled and c.process_enabled:
			c.process(delta)


func _physics_process(delta: float) -> void:
	process_world_actor_movement(delta)
	_process_active_order(delta)
	var needs := get_needs()
	if needs != null:
		var moving := Vector2(velocity.x, velocity.z).length_squared() > 0.01
		# Working = actively mining/scavenging at the node (main's _is_working):
		# drains FATIGUE_WORK_DRAIN through the needs capability's activity branch.
		var interaction := get_interaction()
		var working := interaction != null \
				and ((interaction.current_order_type == InteractionCapability.ORDER_TYPE_MINE and interaction.mining_active) \
					or (interaction.current_order_type == InteractionCapability.ORDER_TYPE_SCAVENGE and interaction.scavenging_active))
		needs.set_activity(moving, is_running_enabled() and moving, is_sitting(), working)
		if life_state == NpcRules.LifeState.ALIVE and moving:
			# Movement skill XP (main's rates): sprinting trains running + endurance;
			# hauling a body trains strength.
			if is_running_enabled():
				add_skill_xp(SkillRules.MOVEMENT_RUNNING, RUNNING_SKILL_XP_PER_SECOND * delta, "running")
				add_skill_xp(SkillRules.ATTRIBUTE_ENDURANCE, RUNNING_ENDURANCE_XP_PER_SECOND * delta, "running")
			var carry := get_carry()
			if carry != null and carry.is_carrying_someone():
				add_skill_xp(SkillRules.ATTRIBUTE_STRENGTH, CARRY_STRENGTH_XP_PER_SECOND * delta, "carrying")
		# Exhaustion breaks an active sprint (main's rule).
		if running and not can_continue_running():
			running = false
	for cap in _capabilities.values():
		var c := cap as ActorCapability
		if c.enabled and c.physics_process_enabled:
			c.physics_process(delta)


## Adds the universal capabilities every actor has. Subclasses override, call
## super(), then add their own. Stats are universal — robots have them too
## (combat reads dexterity/toughness off every actor).
func _create_actor_capabilities() -> void:
	var stats := StatsCapability.new()
	if not _pending_stats_config.is_empty():
		stats.configure_base_stats(_pending_stats_config)
	if not _pending_starting_skill_levels.is_empty():
		stats.starting_skill_levels = _pending_starting_skill_levels
	add_capability(stats)
	var vitals := VitalsCapability.new()
	vitals.configure_initial_values(
		_pending_max_hp,
		_pending_hp,
		_pending_base_max_blood,
		_pending_max_blood,
		_pending_blood,
		_pending_life_state
	)
	# DATA push (not a class-check): tell vitals which death model to use, and OBSERVE its
	# life-state signal to re-emit our node signals. This keeps VitalsCapability free of any
	# WorldActor/RobotActor reference (breaks the actor<->capability cycle edge).
	vitals.death_profile = get_death_profile()
	vitals.life_state_changed.connect(_on_vitals_life_state_changed)
	add_capability(vitals)
	# Hand the carry capability its sibling vitals (eligibility reads life state)
	# and OBSERVE its carry_changed signal to re-emit our node state_changed. Same
	# inversion as vitals above: the capability never references this actor's class.
	var carry := CarryCapability.new()
	carry.bind_vitals(vitals)
	carry.carry_changed.connect(_on_carry_changed)
	add_capability(carry)
	# Needs reads attribute-modified rates from stats and life state from vitals
	# through bound typed handles (same inversion as carry above).
	var needs := NeedsCapability.new()
	needs.bind_stats(stats)
	needs.bind_vitals(vitals)
	needs.configure_enabled(_authored_hunger_enabled, _authored_fatigue_enabled)
	add_capability(needs)
	add_capability(CustodyCapability.new())
	var interaction := InteractionCapability.new()
	interaction.order_changed.connect(_on_order_changed)
	add_capability(interaction)
	# Inventory before Equipment: equipment seeds non-equippable starting items
	# into the inventory capability, so inventory must be ready first.
	add_capability(InventoryCapability.new())
	add_capability(EquipmentCapability.new())


## Typed accessor for the stats capability. Returns null only if absent.
func get_stats() -> StatsCapability:
	return get_capability(&"stats") as StatsCapability


## Typed accessor for the vitals capability. Returns null only if absent.
func get_vitals() -> VitalsCapability:
	return get_capability(&"vitals") as VitalsCapability


## Which death model this actor uses, so GECS systems can branch by DATA (a typed
## virtual call) instead of by live-node class (`actor is RobotActor` — a truth-rule
## violation). Base actors are humanoids; RobotActor overrides this.
func get_death_profile() -> int:
	return CGameActorVitals.DeathProfile.HUMANOID


## Re-emit the vitals capability's life-state change as this actor's node signals. Observing the
## capability (instead of the capability reaching up into us) inverts the dependency: the node
## depends on the capability, never the reverse.
func _on_vitals_life_state_changed(previous_state: int, next_state: int) -> void:
	life_state_changed.emit(previous_state, next_state)
	if next_state == NpcRules.LifeState.DEAD:
		died.emit(self)
	state_changed.emit()


## Re-emit the carry capability's relationship change as this actor's state_changed.
## Inverts the dependency (actor observes capability) so CarryCapability never
## reaches up into this node's class -- the last edge of the actor cycle.
func _on_carry_changed() -> void:
	state_changed.emit()


## Typed accessor for the carry capability. Returns null only if absent.
func get_carry() -> CarryCapability:
	return get_capability(&"carry") as CarryCapability


## Typed accessor for the custody capability. Returns null only if absent.
func get_custody() -> CustodyCapability:
	return get_capability(&"custody") as CustodyCapability


## Typed accessor for the equipment capability. Returns null only if absent.
func get_equipment() -> EquipmentCapability:
	return get_capability(&"equipment") as EquipmentCapability


## Typed accessor for the inventory capability. Returns null only if absent.
func get_inventory() -> InventoryCapability:
	return get_capability(&"inventory") as InventoryCapability


func get_inventory_for_display() -> InventoryData:
	var inv := get_inventory()
	return inv.get_inventory_for_display() if inv != null else null


func is_displaying_work_inventory() -> bool:
	var inv := get_inventory()
	return inv != null and inv.is_displaying_work_inventory()

# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------

const NAVIGATION_MIN_HORIZONTAL_WAYPOINT_DISTANCE_SQUARED := 0.0025
const SNEAK_MOVE_SPEED_MULTIPLIER := 0.5

@export var move_speed := 3.2
@export var run_speed := 5.5
@export var acceleration := 10.0
@export var floor_snap_distance := 0.9
@export var max_walkable_slope_degrees := 55.0
@export var move_target_vertical_tolerance := 0.75
@export var use_navigation_pathing := true
@export var navigation_agent_radius := 0.45
@export var navigation_agent_height := 2.0
@export var navigation_path_desired_distance := 0.75
@export var navigation_target_desired_distance := 0.6
@export var navigation_path_height_offset := 0.9
@export var navigation_unreachable_tolerance := 2.0
@export var navigation_reachable_vertical_tolerance := 2.0
@export var navigation_neighbor_distance := 2.4
@export var navigation_max_neighbors := 8
@export var navigation_time_horizon_agents := 0.7
@export var stuck_check_seconds := 2.0
@export var stuck_min_progress := 0.12
@export var stuck_repath_attempt_limit := 8

var gravity := ProjectSettings.get_setting("physics/3d/default_gravity") as float

var _navigation_agent: NavigationAgent3D
var _move_target: Vector3 = Vector3.ZERO
var _has_move_target: bool = false
var running: bool = false
var sneaking: bool = false

var _navigation_target_synced := false
var _navigation_synced_target := Vector3.ZERO
var _navigation_query_grace_remaining := 0.0
var _navigation_zero_waypoint_blocked := false
var _avoidance_velocity := Vector3.ZERO
var _has_avoidance_velocity := false
var _stuck_origin := Vector3.ZERO
var _stuck_target_distance := INF
var _stuck_seconds := 0.0
var _stuck_repath_attempts := 0

## System-set movement bridge from GameCombatMovementSystem.
## Stores the last system frame so the actor can apply it in _tick_movement.
var _system_move_active: bool = false
var _system_move_target: Vector3 = Vector3.ZERO
var _system_desired_velocity: Vector3 = Vector3.ZERO
var _system_look_target: Vector3 = Vector3.ZERO
var _system_move_settled: bool = false
var _system_collision_focus_id: int = 0
var _system_collision_exception_focus_id: int = 0
var _system_collision_exception_peer: CollisionObject3D

## System-set combat bridge from GameCombatResolutionSystem.
var _system_combat_action_active: bool = false
var _system_combat_reaction_remaining: float = 0.0
var _system_combat_cooldown_remaining: float = 0.0
var _system_combat_focus_id: int = 0
var _system_target_id: int = 0

# Movement/labor XP rates (main's values).
const RUNNING_SKILL_XP_PER_SECOND := 0.35
const RUNNING_ENDURANCE_XP_PER_SECOND := 0.05
const CARRY_STRENGTH_XP_PER_SECOND := 0.1


func set_move_target(target: Vector3, issued_by_player: bool = true) -> void:
	if is_in_cell_custody():
		return
	var interaction := get_interaction()
	if interaction != null:
		# Ambient movement (staff post loops, patrol steps, schedules) yields to an
		# active priority order — a guard hauling a prisoner must not be tugged back
		# to their post; the loop resumes when the order completes. Player commands
		# always win (explicit intent).
		if not issued_by_player:
			var order := interaction.current_order_type
			var carry := get_carry()
			var carrying_someone := carry != null and carry.is_carrying_someone()
			if carrying_someone or (order != InteractionCapability.ORDER_TYPE_NONE and order != InteractionCapability.ORDER_TYPE_MOVE):
				return
		interaction._set_order(InteractionCapability.ORDER_TYPE_MOVE, issued_by_player)
	_active_player_order = issued_by_player
	_set_actor_move_target(target)


func stop_movement() -> void:
	_clear_actor_move_target()
	velocity = Vector3.ZERO


## Returns whether the mode change was accepted. Sneaking and running are
## mutually exclusive; enabling one clears the other.
func set_running_enabled(enabled: bool) -> bool:
	running = enabled
	if enabled:
		sneaking = false
	return true


func is_running_enabled() -> bool:
	return running and can_continue_running()


## Exhausted actors cannot keep sprinting (main's rule): once EXHAUSTED, running
## locks out until fatigue recovers above the lockout threshold.
func can_continue_running() -> bool:
	if life_state != NpcRules.LifeState.ALIVE:
		return false
	if get_fatigue_stage() < NpcRules.FatigueStage.EXHAUSTED:
		return true
	return fatigue > NpcRules.FATIGUE_RUN_LOCKOUT_THRESHOLD


func set_sneaking_enabled(enabled: bool) -> bool:
	sneaking = enabled
	if enabled:
		running = false
	return true


func is_sneaking() -> bool:
	return sneaking


## Called by GameCombatMovementSystem each GECS tick.
func set_system_movement_bridge(
	_process_frame: int,
	is_active: bool,
	move_target: Vector3,
	desired_velocity: Vector3,
	look_target: Vector3,
	settled: bool,
	collision_focus_id: int
) -> void:
	_system_move_active = is_active
	_system_move_target = move_target
	_system_desired_velocity = desired_velocity
	_system_look_target = look_target
	_system_move_settled = settled
	_system_collision_focus_id = collision_focus_id


## Called by GameCombatResolutionSystem each GECS tick.
func set_system_combat_bridge(
	_process_frame: int,
	action_active: bool,
	reaction_remaining: float,
	cooldown_remaining: float,
	focus_id: int
) -> void:
	_system_combat_action_active = action_active
	_system_combat_reaction_remaining = reaction_remaining
	_system_combat_cooldown_remaining = cooldown_remaining
	_system_combat_focus_id = focus_id


## Called by GameCombatTargetingSystem each GECS tick.
# Personal grudges (instance_id -> true) and the last actor that directly attacked us.
# Written by combat/targeting capabilities and law-order flows, mirrored into
# C_GameCombatState by GameCombatStateSyncSystem so GECS targeting honors grudges.
var _personal_hostile_ids: Dictionary = {}
var _last_direct_attacker_id := 0


func set_system_target_bridge(target_id: int, _process_frame: int) -> void:
	_system_target_id = target_id


# Law/authority role markers. Group-based on purpose: the law controller and
# building alarm checks select responders by role across the whole scene.
const SETTLEMENT_AUTHORITY_GROUP := "settlement_authority"
const PRIVATE_SECURITY_GROUP := "private_security"
const FACTION_SOLDIER_GROUP := "faction_soldier"


func set_settlement_authority(value: bool) -> void:
	if value:
		add_to_group(SETTLEMENT_AUTHORITY_GROUP)
	else:
		remove_from_group(SETTLEMENT_AUTHORITY_GROUP)


func is_settlement_authority() -> bool:
	return is_in_group(SETTLEMENT_AUTHORITY_GROUP)


func set_private_security(value: bool) -> void:
	if value:
		add_to_group(PRIVATE_SECURITY_GROUP)
	else:
		remove_from_group(PRIVATE_SECURITY_GROUP)


func is_private_security() -> bool:
	return is_in_group(PRIVATE_SECURITY_GROUP)


func set_faction_soldier(value: bool) -> void:
	if value:
		add_to_group(FACTION_SOLDIER_GROUP)
	else:
		remove_from_group(FACTION_SOLDIER_GROUP)


func is_faction_soldier() -> bool:
	return is_in_group(FACTION_SOLDIER_GROUP)


func mark_hostile(other: Node) -> void:
	if other == null or other == self:
		return
	# Value is the expiry tick: every exchange refreshes it (live fights never
	# decay), and stale grudges lapse — see NpcRules.COMBAT_GRUDGE_SECONDS.
	_personal_hostile_ids[other.get_instance_id()] = Time.get_ticks_msec() + int(NpcRules.COMBAT_GRUDGE_SECONDS * 1000.0)


## Prunes expired grudges and returns the live set (instance_id -> expiry ticks).
func get_active_grudges() -> Dictionary:
	var now := Time.get_ticks_msec()
	if not _personal_hostile_ids.is_empty():
		var expired: Array = []
		for key in _personal_hostile_ids:
			if int(_personal_hostile_ids[key]) <= now:
				expired.append(key)
		for key in expired:
			_personal_hostile_ids.erase(key)
	return _personal_hostile_ids


func is_hostile_to(other: Node) -> bool:
	var other_actor := other as WorldActor
	if other_actor == null or other_actor == self:
		return false
	if is_protected_from_combat() or other_actor.is_protected_from_combat():
		return false
	if int(_personal_hostile_ids.get(other_actor.get_instance_id(), 0)) > Time.get_ticks_msec():
		return true
	return hostile_factions.has(other_actor.faction_name)


func has_hostility_with(other: Node) -> bool:
	var other_actor := other as WorldActor
	if other_actor == null:
		return false
	return is_hostile_to(other_actor) or other_actor.is_hostile_to(self)


## Player/AI attack order. The GECS targeting system owns actual target choice;
## an order records a personal grudge so targeting immediately treats the mark as
## hostile and acquires it by proximity. A dedicated focus-fire order component is
## the eventual richer home for this.
func assign_attack_target(target_actor: Node, _issued_by_player: bool = true, _notify_target: bool = true, _notify_allies: bool = true) -> bool:
	if target_actor == null or target_actor == self or not is_instance_valid(target_actor):
		return false
	mark_hostile(target_actor)
	# An attack command ends whatever interaction order was running AND releases the
	# player-order combat suppression — otherwise a lingering order keeps targeting
	# suppressed and the attack silently never happens.
	var interaction := get_interaction()
	if interaction != null:
		interaction.begin_combat_order()
	_active_player_order = false
	return true


func clear_personal_hostility(other: Node) -> void:
	if other == null:
		return
	_personal_hostile_ids.erase(other.get_instance_id())


func clear_all_personal_hostility() -> void:
	_personal_hostile_ids.clear()
	_last_direct_attacker_id = 0


# Returns the BASE attack range, not get_stat_value("attack_range"): the GECS combat
# slot/movement geometry was tuned against base range (this method did not exist while
# those systems were built). Feeding weapon-modified range here stalls the approach —
# fighters freeze outside engage distance (verified 2026-07-01). Weapon reach belongs
# in a deliberate retune of slot geometry, not a silent behavior flip through this hook.
func get_attack_range() -> float:
	return attack_range


## Legacy coordinator alias; the shared target concept is now the system target.
func get_shared_combat_target() -> Node:
	return get_current_combat_target()


## Node-side exchange readiness is superseded by the GECS slot system; the base actor
## never volunteers for coordinator-driven exchanges (pre-migration base behavior).
func is_ready_for_combat_exchange(_target: Node) -> bool:
	return false


# --- Attack presentation hooks, driven by GameCombatResolutionSystem ----------------
# The base actor has no visual body: subclasses with body projections override these.
# The defaults keep sim timing intact with no animation.

func get_system_combat_attack_spec() -> Dictionary:
	return {}


func on_system_combat_attack_started(_target_actor: Node, _animation_names: PackedStringArray) -> float:
	return 0.0


func play_system_combat_action_clip(_animation_name: String) -> float:
	return 0.0


## Victim-side presentation for a resolved attack; subclasses with body
## projections play reaction clips and notices. Returns reaction seconds.
func play_system_combat_hit_reaction(_attacker: Node, _outcome: String, _attack_id: String, _hit_reaction_names: PackedStringArray, _is_critical: bool, _has_shield_block: bool, _can_actively_defend: bool, _final_damage: float) -> float:
	return 0.0


## Ragdoll is a projection concern; subclasses with physical bones override.
func is_ragdoll_active() -> bool:
	return false


## The live node this actor is currently fighting, resolved from the system target
## assigned by GameCombatTargetingSystem. Null when disengaged.
func get_current_combat_target() -> Node:
	if _system_target_id == 0:
		return null
	var target := instance_from_id(_system_target_id)
	if target == null or not is_instance_valid(target):
		return null
	# The bridge can hold a stale id after the fight ends (targeting only re-evaluates
	# DUE entities). A downed/dead target is not combat — treating it as such locks
	# the order dispatcher (guards frozen mid-arrest, unable to walk to the body).
	var target_actor := target as WorldActor
	if target_actor != null and target_actor.life_state != NpcRules.LifeState.ALIVE:
		return null
	return target as Node


## True when the combat systems currently have this actor engaged with a live target.
## Semantics preserved from the pre-capability API ("has an active combat target");
## the target now arrives from GameCombatTargetingSystem via the _system_target_id bridge.
func is_in_combat() -> bool:
	return get_current_combat_target() != null


## Real movement actuator (ported from the pre-migration WorldActor). Nav-driven
## locomotion with acceleration, RVO avoidance, and stuck detection.
func process_world_actor_movement(delta: float) -> void:
	var carry := get_carry()
	if carry != null and carry.is_carried():
		velocity = Vector3.ZERO
		return
	# While the projection simulates ragdoll bones, the character body must not
	# move_and_slide underneath them.
	if is_ragdoll_active():
		return
	# Downed/asleep actors never self-move: the downed path disables the main
	# collision (mask 0), so running gravity + move_and_slide here would free-fall
	# the body through the world.
	if life_state != NpcRules.LifeState.ALIVE:
		velocity = Vector3.ZERO
		return
	# Seated actors hold their seat; standing up happens through the order system.
	if is_sitting():
		velocity = Vector3.ZERO
		return
	# Jailed actors do not self-move: the cell owns their position until release
	# (escapes/releases go through exit_cell_custody, never through navigation).
	if is_in_cell_custody():
		velocity = Vector3.ZERO
		return
	# Player orders outrank combat: while one is active the nav path drives, and the
	# GECS targeting system (which reads player_order_active off the config component)
	# drops this actor's target so combat AI resumes only after the order completes.
	if life_state == NpcRules.LifeState.ALIVE and not _active_player_order and (_system_move_active or is_in_combat()):
		process_system_combat_movement(delta)
		return
	_ensure_navigation_agent()
	_apply_floor_motion(delta)
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var desired_direction := Vector3.ZERO
	if _has_move_target:
		desired_direction = _get_move_direction(delta)
		if desired_direction.length_squared() > 0.0001:
			var target_speed := _get_actor_move_speed()
			horizontal_velocity = horizontal_velocity.lerp(desired_direction * target_speed, minf(1.0, acceleration * delta))
			look_at(global_position + desired_direction, Vector3.UP)
		else:
			horizontal_velocity = horizontal_velocity.lerp(Vector3.ZERO, minf(1.0, acceleration * delta))
	else:
		horizontal_velocity = horizontal_velocity.lerp(Vector3.ZERO, minf(1.0, acceleration * delta))
	if _should_apply_avoidance(desired_direction):
		_navigation_agent.max_speed = maxf(_get_actor_move_speed(), 0.0)
		_navigation_agent.velocity = horizontal_velocity
		if _has_avoidance_velocity:
			horizontal_velocity.x = _avoidance_velocity.x
			horizontal_velocity.z = _avoidance_velocity.z
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	move_and_slide()
	rotation.x = lerp_angle(rotation.x, 0.0, minf(1.0, 10.0 * delta))
	rotation.z = lerp_angle(rotation.z, 0.0, minf(1.0, 10.0 * delta))
	_update_stuck_state(delta, desired_direction)


func _apply_floor_motion(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
		apply_floor_snap()


func _get_actor_move_speed() -> float:
	if sneaking:
		return move_speed * SNEAK_MOVE_SPEED_MULTIPLIER
	return run_speed if running else move_speed


# Soft-body crowd model: actors live on their own physics layer so rays and areas
# still find them, but their mask excludes that layer — actors never hard-collide
# with EACH OTHER (no capsule wedging in melee piles; separation steering and the
# combat ring slots own spacing). They still hard-collide with the world (layer 1).
const ACTOR_COLLISION_LAYER := 1 << 1
const ACTOR_COLLISION_MASK := 1


func _configure_world_actor_movement() -> void:
	floor_snap_length = floor_snap_distance
	floor_max_angle = deg_to_rad(max_walkable_slope_degrees)
	collision_layer = ACTOR_COLLISION_LAYER
	collision_mask = ACTOR_COLLISION_MASK
	add_to_group("world_actor")
	_ensure_navigation_agent()
	_sync_party_membership_group()


func _ensure_navigation_agent() -> void:
	if _navigation_agent != null and is_instance_valid(_navigation_agent):
		return
	_navigation_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if _navigation_agent == null:
		_navigation_agent = NavigationAgent3D.new()
		_navigation_agent.name = "NavigationAgent3D"
		add_child(_navigation_agent)
	_configure_navigation_agent()


func _configure_navigation_agent() -> void:
	_navigation_agent.radius = navigation_agent_radius
	_navigation_agent.height = navigation_agent_height
	_navigation_agent.path_desired_distance = navigation_path_desired_distance
	_navigation_agent.target_desired_distance = _get_move_target_arrival_distance()
	_navigation_agent.path_height_offset = navigation_path_height_offset
	_navigation_agent.avoidance_enabled = navigation_avoidance_enabled
	_navigation_agent.neighbor_distance = navigation_neighbor_distance
	_navigation_agent.max_neighbors = navigation_max_neighbors
	_navigation_agent.max_speed = move_speed
	_navigation_agent.time_horizon_agents = navigation_time_horizon_agents
	_navigation_agent.keep_y_velocity = false
	_navigation_agent.simplify_path = false
	if not _navigation_agent.velocity_computed.is_connected(_on_navigation_velocity_computed):
		_navigation_agent.velocity_computed.connect(_on_navigation_velocity_computed)


func _set_actor_move_target(target: Vector3) -> void:
	var target_changed := not _has_move_target or _move_target.distance_squared_to(target) > 0.0025
	_move_target = target
	_has_move_target = true
	if not target_changed:
		return
	_navigation_target_synced = false
	_navigation_query_grace_remaining = 0.25
	_navigation_zero_waypoint_blocked = false
	_has_avoidance_velocity = false
	_stuck_repath_attempts = 0
	_reset_stuck_tracking()


func _get_move_direction(delta: float) -> Vector3:
	if _is_close_to_move_target():
		_finish_actor_move_target()
		return Vector3.ZERO
	if use_navigation_pathing and _navigation_agent != null and _has_navigation_data():
		return _get_navigation_move_direction(delta)
	_navigation_query_grace_remaining = maxf(0.0, _navigation_query_grace_remaining - delta)
	if _navigation_query_grace_remaining <= 0.0:
		_fail_actor_move_target()
	return Vector3.ZERO


func _get_navigation_move_direction(delta: float) -> Vector3:
	_navigation_zero_waypoint_blocked = false
	_sync_navigation_target_if_needed()
	if _navigation_agent.is_navigation_finished():
		if _is_close_to_move_target():
			_finish_actor_move_target()
		elif _is_navigation_final_position_close_enough():
			return _get_navigation_point_move_direction(_navigation_agent.get_final_position())
		else:
			_fail_actor_move_target()
		return Vector3.ZERO
	var next_path_position := _navigation_agent.get_next_path_position()
	if not _is_navigation_final_position_close_enough():
		_navigation_query_grace_remaining = maxf(0.0, _navigation_query_grace_remaining - delta)
		if _navigation_query_grace_remaining <= 0.0:
			_fail_actor_move_target()
		return Vector3.ZERO
	return _get_navigation_path_move_direction(next_path_position)


func _get_navigation_path_move_direction(next_path_position: Vector3) -> Vector3:
	var direct_direction := _get_navigation_point_move_direction(next_path_position)
	if direct_direction.length_squared() > 0.0001:
		return direct_direction
	var path := _navigation_agent.get_current_navigation_path()
	var path_index := maxi(0, _navigation_agent.get_current_navigation_path_index())
	for index in range(path_index, path.size()):
		var to_point := path[index] - global_position
		to_point.y = 0.0
		if to_point.length_squared() > NAVIGATION_MIN_HORIZONTAL_WAYPOINT_DISTANCE_SQUARED:
			return to_point.normalized()
	_navigation_zero_waypoint_blocked = true
	return Vector3.ZERO


func _get_navigation_point_move_direction(point: Vector3) -> Vector3:
	var to_point := point - global_position
	to_point.y = 0.0
	if to_point.length_squared() <= 0.0001:
		return Vector3.ZERO
	return to_point.normalized()


func _sync_navigation_target_if_needed() -> void:
	_navigation_agent.target_desired_distance = _get_move_target_arrival_distance()
	if _navigation_target_synced and _navigation_synced_target.distance_squared_to(_move_target) <= 0.0025:
		return
	_navigation_agent.target_position = _move_target
	_navigation_synced_target = _move_target
	_navigation_target_synced = true
	_navigation_query_grace_remaining = 0.25
	_reset_stuck_tracking()


## Combat approach/positioning actuation driven by GameCombatMovementSystem through
## set_system_movement_bridge(). Replaces navigation-agent movement while this actor
## has a live combat target, so fighters close distance and face their opponent.
func process_system_combat_movement(delta: float) -> void:
	_apply_floor_motion(delta)
	_update_system_movement_collision_exception(_system_move_active, _system_collision_focus_id)
	if _system_move_active:
		velocity.x = 0.0 if _system_move_settled else _system_desired_velocity.x
		velocity.z = 0.0 if _system_move_settled else _system_desired_velocity.z
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	_face_system_movement_target()
	move_and_slide()
	rotation.x = lerp_angle(rotation.x, 0.0, minf(1.0, 10.0 * delta))
	rotation.z = lerp_angle(rotation.z, 0.0, minf(1.0, 10.0 * delta))


# GameCombatMovementSystem supplies look_target; the current combat target covers the
# gap when it is zero. No capability reference here — WorldActor -> CombatCapability
# would close a dependency cycle through combat_coordinator.
func _face_system_movement_target() -> void:
	var look_position := _system_look_target
	if look_position == Vector3.ZERO:
		var target := get_current_combat_target() as Node3D
		if target != null:
			look_position = target.global_position
	look_position.y = global_position.y
	if global_position.distance_squared_to(look_position) > 0.0001:
		look_at(look_position, Vector3.UP)


# While actively moving into a fight slot, ignore collision with the focused opponent so
# fighters can settle into attack range instead of shoving each other around.
func _update_system_movement_collision_exception(active: bool, focus_id: int) -> void:
	if active and focus_id != 0 and focus_id == _system_collision_exception_focus_id and _system_collision_exception_peer != null and is_instance_valid(_system_collision_exception_peer):
		return
	var next_peer: CollisionObject3D = null
	if active and focus_id != 0:
		var focus := instance_from_id(focus_id) as CollisionObject3D
		if focus != null and focus != self and is_instance_valid(focus):
			next_peer = focus
	if next_peer == _system_collision_exception_peer:
		return
	_clear_system_movement_collision_exception()
	if next_peer != null:
		add_collision_exception_with(next_peer)
		_system_collision_exception_focus_id = focus_id
		_system_collision_exception_peer = next_peer


func _clear_system_movement_collision_exception() -> void:
	if _system_collision_exception_peer != null:
		if is_instance_valid(_system_collision_exception_peer):
			remove_collision_exception_with(_system_collision_exception_peer)
		_system_collision_exception_peer = null
	_system_collision_exception_focus_id = 0


## Camera/follow anchor. Subclasses with ragdolls may return a bone anchor instead.
func get_follow_anchor_position() -> Vector3:
	return global_position


func _reset_stuck_tracking() -> void:
	_stuck_origin = global_position
	_stuck_target_distance = _get_stuck_target_distance()
	_stuck_seconds = 0.0


func _get_stuck_target_distance() -> float:
	if not _has_move_target:
		return INF
	return _horizontal_distance(global_position, _move_target)


func _has_made_stuck_progress() -> bool:
	if _horizontal_distance(global_position, _stuck_origin) >= stuck_min_progress:
		return true
	var target_distance := _get_stuck_target_distance()
	if _stuck_target_distance < INF and target_distance <= _stuck_target_distance - stuck_min_progress:
		return true
	return false


func _horizontal_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()


func _get_move_target_arrival_distance() -> float:
	return navigation_target_desired_distance


func _get_navigation_stuck_arrival_distance() -> float:
	return _get_move_target_arrival_distance()


func _has_navigation_data() -> bool:
	return NavigationServer3D.map_get_iteration_id(_navigation_agent.get_navigation_map()) > 0


func _is_close_to_move_target() -> bool:
	var to_target := _move_target - global_position
	return _horizontal_distance(global_position, _move_target) <= _get_move_target_arrival_distance() and absf(to_target.y) <= move_target_vertical_tolerance


func _is_close_to_navigation_point_from(from: Vector3, point: Vector3, vertical_tolerance: float, horizontal_tolerance: float = -1.0) -> bool:
	var effective_horizontal_tolerance := _get_move_target_arrival_distance() if horizontal_tolerance < 0.0 else horizontal_tolerance
	return _horizontal_distance(from, point) <= effective_horizontal_tolerance and absf(from.y - point.y) <= vertical_tolerance


func _is_navigation_final_position_close_enough() -> bool:
	if _navigation_agent == null:
		return false
	var final_position := _navigation_agent.get_final_position()
	return _is_close_to_navigation_point_from(final_position, _move_target, navigation_reachable_vertical_tolerance, navigation_unreachable_tolerance)


func _finish_actor_move_target() -> void:
	_clear_actor_move_target()
	# Order fulfilled: release the player-order hold so combat AI resumes.
	_active_player_order = false
	_clear_move_order_state()
	_on_actor_move_target_reached()


func _fail_actor_move_target() -> void:
	_clear_actor_move_target()
	_active_player_order = false
	_clear_move_order_state()
	_on_actor_move_target_unreachable()


func _clear_move_order_state() -> void:
	var interaction := get_interaction()
	if interaction != null and interaction.current_order_type == InteractionCapability.ORDER_TYPE_MOVE:
		interaction.current_order_type = InteractionCapability.ORDER_TYPE_NONE


func _should_apply_avoidance(desired_direction: Vector3) -> bool:
	return _navigation_agent != null and _navigation_agent.avoidance_enabled and _has_move_target and desired_direction.length_squared() > 0.0001


func _update_stuck_state(delta: float, desired_direction: Vector3) -> void:
	if not _has_move_target or desired_direction.length_squared() <= 0.0001:
		if _navigation_zero_waypoint_blocked:
			_stuck_seconds += delta
			if _stuck_seconds >= stuck_check_seconds:
				_handle_navigation_stuck()
			return
		_reset_stuck_tracking()
		return
	if _has_made_stuck_progress():
		_reset_stuck_tracking()
		_stuck_repath_attempts = 0
		return
	_stuck_seconds += delta
	if _stuck_seconds < stuck_check_seconds:
		return
	_handle_navigation_stuck()


func _handle_navigation_stuck() -> void:
	if _is_close_to_navigation_point_from(global_position, _move_target, move_target_vertical_tolerance, _get_navigation_stuck_arrival_distance()):
		_finish_actor_move_target()
		return
	if _is_navigation_final_position_close_enough() and _stuck_repath_attempts < stuck_repath_attempt_limit:
		_navigation_target_synced = false
		_stuck_repath_attempts += 1
		_reset_stuck_tracking()
		return
	_fail_actor_move_target()


func _on_navigation_velocity_computed(safe_velocity: Vector3) -> void:
	_avoidance_velocity = safe_velocity
	_has_avoidance_velocity = true


## Virtual hooks for subclasses / capabilities to react to arrival.
func _on_actor_move_target_reached() -> void:
	pass


func _on_actor_move_target_unreachable() -> void:
	pass

# ---------------------------------------------------------------------------
# Downed collision / nav-avoidance — actuator physics concern (called by the
# body projection's ragdoll/downed path through the typed actor handle).
# ---------------------------------------------------------------------------

@export var navigation_avoidance_enabled := true

var _stored_collision_shape: Shape3D
var _stored_collision_transform := Transform3D.IDENTITY
var _stored_collision_disabled := false
var _stored_collision_layer := 1
var _stored_collision_mask := 1
var _stored_navigation_avoidance_enabled := true
var _downed_collision_applied := false


func _get_main_collision_shape() -> CollisionShape3D:
	return get_node_or_null("CollisionShape3D") as CollisionShape3D


func _get_navigation_avoidance_enabled() -> bool:
	if _navigation_agent != null and is_instance_valid(_navigation_agent):
		return _navigation_agent.avoidance_enabled
	return navigation_avoidance_enabled


func _set_navigation_avoidance_enabled(enabled: bool) -> void:
	navigation_avoidance_enabled = enabled
	if _navigation_agent != null and is_instance_valid(_navigation_agent):
		_navigation_agent.avoidance_enabled = enabled


func _apply_downed_collision_shape() -> void:
	var collision_shape := _get_main_collision_shape()
	if collision_shape == null:
		return
	if not _downed_collision_applied:
		_stored_collision_shape = collision_shape.shape
		_stored_collision_transform = collision_shape.transform
		_stored_collision_disabled = collision_shape.disabled
		_stored_collision_layer = collision_layer
		_stored_collision_mask = collision_mask
		_stored_navigation_avoidance_enabled = _get_navigation_avoidance_enabled()
	collision_shape.disabled = true
	collision_layer = 0
	collision_mask = 0
	_downed_collision_applied = true
	_set_navigation_avoidance_enabled(false)


func _restore_downed_collision_shape() -> void:
	var collision_shape := _get_main_collision_shape()
	if _downed_collision_applied and collision_shape != null:
		collision_shape.shape = _stored_collision_shape
		collision_shape.transform = _stored_collision_transform
		collision_shape.disabled = _stored_collision_disabled
		collision_layer = _stored_collision_layer
		collision_mask = _stored_collision_mask
	_downed_collision_applied = false
	_set_navigation_avoidance_enabled(_stored_navigation_avoidance_enabled)

# ---------------------------------------------------------------------------
# Player order tracking (read by ai_utility_adapter)
# ---------------------------------------------------------------------------

var _active_player_order: bool = false


func is_player_party_member() -> bool:
	return player_party_member


func set_player_party_member(value: bool) -> void:
	player_party_member = value
	_sync_party_membership_group()


func _sync_party_membership_group() -> void:
	if player_party_member:
		add_to_group("party_member")
	else:
		remove_from_group("party_member")


func has_active_player_order() -> bool:
	return _active_player_order


func set_active_player_order(active: bool) -> void:
	_active_player_order = active

# ---------------------------------------------------------------------------
# Capability alias (legacy name used by subclasses)
# ---------------------------------------------------------------------------

func get_actor_capability(id: StringName) -> ActorCapability:
	return get_capability(id)

# ---------------------------------------------------------------------------
# Stub interface — will move to capabilities as the migration progresses.
# These exist so subclasses compile during Phase 0.
# ---------------------------------------------------------------------------

# MIGRATION STUB: move to PerceptionCapability.
func can_participate_in_perception() -> bool:
	return false


# MIGRATION STUB: move to PerceptionCapability.
func get_stealth_sample_positions() -> Array[Vector3]:
	return [global_position]


# MIGRATION STUB: move to PerceptionCapability.
func get_perception_eye_position() -> Vector3:
	return global_position


# MIGRATION STUB: move to PerceptionCapability.
func get_stealth_light_sample_position() -> Vector3:
	return global_position


# MIGRATION STUB: move to PerceptionCapability.
func get_perception_forward_vector() -> Vector3:
	return -global_transform.basis.z


# ---------------------------------------------------------------------------
# Stats / skills — typed delegation to StatsCapability (Phase 1, real)
# ---------------------------------------------------------------------------

func get_stat_value(stat_name: String, include_secondary_modifiers: bool = true) -> float:
	var stats := get_stats()
	return stats.get_stat_value(stat_name, include_secondary_modifiers) if stats != null else 0.0


func get_skill_level(skill_id: String) -> int:
	var stats := get_stats()
	return stats.get_skill_level(skill_id) if stats != null else 0


# ---------------------------------------------------------------------------
# Combat loadout authoring (node -> CGameCombatLoadout, typed).
# The bridge pushes SOURCE stats here; GameCombatScoreSystem derives the packed
# scores via CombatMath. Faithful port of the clean-HEAD damage-base model with
# zero reflection. See architecture/combat/ARCHITECTURE.md.
# ---------------------------------------------------------------------------
const COMBAT_BODY_TOUGHNESS_BASE_WEIGHT := 0.025
const COMBAT_LEGACY_CHANCE_TO_SCORE := 220.0
const COMBAT_BODY_WEAPON_BLUNT_BASE := 2.5
const COMBAT_BODY_WEAPON_CUT_BASE := 0.0


func write_combat_loadout(loadout: CGameCombatLoadout) -> void:
	if loadout == null:
		return
	var equipment := get_equipment()
	var weapon_item: ItemDefinition = equipment.get_equipped_item(ItemDefinition.EQUIP_SLOT_WEAPON) if equipment != null else null
	var offhand_item: ItemDefinition = equipment.get_equipped_item(ItemDefinition.EQUIP_SLOT_OFFHAND) if equipment != null else null
	var toughness := get_stat_value("toughness")
	var bases := _resolve_combat_damage_bases(weapon_item, toughness)
	var weapon_skill_id := _resolve_combat_weapon_skill_id(weapon_item)
	loadout.weapon_skill_id = weapon_skill_id
	loadout.weapon_skill_level = float(get_skill_level(weapon_skill_id))
	loadout.shields_skill_level = float(get_skill_level(SkillRules.COMBAT_SHIELDS))
	loadout.strength = get_stat_value("strength")
	loadout.dexterity = get_stat_value("dexterity")
	loadout.toughness = toughness
	loadout.blunt_base = float(bases.get("blunt_base", 0.0))
	loadout.cut_base = float(bases.get("cut_base", 0.0))
	loadout.has_shield = _is_combat_shield(offhand_item)
	loadout.weapon_parry_bonus = _resolve_combat_parry_bonus(weapon_item)
	loadout.shield_block_bonus = _resolve_combat_shield_block_bonus(offhand_item)
	loadout.block_damage_multiplier = clampf(get_stat_value("block_damage_multiplier"), 0.0, 1.0)
	loadout.dirty = true


func _resolve_combat_damage_bases(weapon_item: ItemDefinition, toughness: float) -> Dictionary:
	var equipment := get_equipment()
	if weapon_item != null and equipment != null:
		# Explicit per-weapon blunt/cut base, scaled by attack_damage stat modifiers.
		if equipment.has_item_stat_modifier(weapon_item, "blunt_base") or equipment.has_item_stat_modifier(weapon_item, "cut_base"):
			var damage_multiplier := _combat_damage_stat_multiplier()
			return {
				"blunt_base": maxf(0.0, equipment.get_item_stat_value(weapon_item, "blunt_base", 0.0)) * damage_multiplier,
				"cut_base": maxf(0.0, equipment.get_item_stat_value(weapon_item, "cut_base", 0.0)) * damage_multiplier,
			}
		# Legacy weapons: single attack_damage stat split by cut_ratio.
		var weapon_total_base := maxf(0.0, get_stat_value("attack_damage"))
		var weapon_cut_ratio := clampf(get_stat_value("cut_ratio"), 0.0, 1.0)
		return {"blunt_base": weapon_total_base * (1.0 - weapon_cut_ratio), "cut_base": weapon_total_base * weapon_cut_ratio}
	# Unarmed: body-weapon profile, conditioned by toughness (body_weapons.md).
	var body_multiplier := (1.0 + toughness * COMBAT_BODY_TOUGHNESS_BASE_WEIGHT) * _combat_damage_stat_multiplier()
	return {
		"blunt_base": COMBAT_BODY_WEAPON_BLUNT_BASE * body_multiplier,
		"cut_base": COMBAT_BODY_WEAPON_CUT_BASE * body_multiplier,
	}


func _combat_damage_stat_multiplier() -> float:
	var stats := get_stats()
	var base_value := maxf(stats.base_attack_damage if stats != null else 18.0, 0.001)
	return maxf(0.0, get_stat_value("attack_damage") / base_value)


func _resolve_combat_parry_bonus(weapon_item: ItemDefinition) -> float:
	var explicit := get_stat_value("weapon_parry_bonus")
	if explicit > 0.0:
		return explicit
	var equipment := get_equipment()
	if weapon_item == null or equipment == null:
		return 0.0
	return maxf(0.0, equipment.get_item_stat_value(weapon_item, "block_chance", 0.0) * COMBAT_LEGACY_CHANCE_TO_SCORE)


func _resolve_combat_shield_block_bonus(offhand_item: ItemDefinition) -> float:
	var explicit := get_stat_value("shield_block_bonus")
	if explicit > 0.0:
		return explicit
	var equipment := get_equipment()
	if offhand_item == null or equipment == null:
		return 0.0
	return maxf(0.0, equipment.get_item_stat_value(offhand_item, "block_chance", 0.0) * COMBAT_LEGACY_CHANCE_TO_SCORE)


func _resolve_combat_weapon_skill_id(weapon_item: ItemDefinition) -> String:
	if weapon_item == null:
		return SkillRules.COMBAT_UNARMED
	var descriptor := "%s %s" % [weapon_item.display_name.to_lower(), weapon_item.resource_path.to_lower()]
	if descriptor.contains("dagger"):
		return SkillRules.COMBAT_DAGGERS
	if descriptor.contains("axe"):
		return SkillRules.COMBAT_AXES_ONE_HANDED
	if descriptor.contains("sword"):
		return SkillRules.COMBAT_SWORDS_ONE_HANDED
	return SkillRules.COMBAT_SWORDS_ONE_HANDED


func _is_combat_shield(offhand_item: ItemDefinition) -> bool:
	if offhand_item == null:
		return false
	var grip := offhand_item.grip_profile as EquipmentGripProfile
	return grip != null and grip.grip_class_id == EquipmentGripProfile.GRIP_CLASS_OFFHAND_SHIELD


func set_skill_level(skill_id: String, level: int, clear_xp := true) -> void:
	var stats := get_stats()
	if stats != null:
		stats.set_skill_level(skill_id, level, clear_xp)


func add_skill_xp(skill_id: String, amount: float, reason := "") -> int:
	var stats := get_stats()
	return stats.add_skill_xp(skill_id, amount, reason) if stats != null else 0


func get_skill_entry_snapshot(skill_id: String) -> Dictionary:
	var stats := get_stats()
	return stats.get_skill_entry_snapshot(skill_id) if stats != null else {}


# Perception convenience reads — resolve through the stats layer.
func get_stealth_skill_level() -> float:
	return get_stat_value("stealth")


func get_perception_skill_level() -> float:
	return get_stat_value("perception")


# MIGRATION STUB: move to LawCapability.
func get_legal_status() -> ActorLegalStatus:
	return _migration_legal_status


func is_law_prisoner() -> bool:
	return _migration_legal_status != null and _migration_legal_status.is_prisoner


func is_protected_from_combat() -> bool:
	return is_in_cell_custody() or is_law_prisoner()


func is_in_cell_custody() -> bool:
	var custody := get_custody()
	return custody != null and custody.is_contained()


func get_cell_custody_target() -> Node:
	var custody := get_custody()
	return custody.get_container() if custody != null else null


func enter_cell_custody(cell, cell_position: Vector3, cell_rotation: Vector3) -> void:
	# Custody ends whatever the prisoner was doing: orders, movement, combat grudges
	# (the law controller also clears hostility on both sides at custody time).
	var interaction := get_interaction()
	if interaction != null:
		interaction.begin_combat_order()
	_clear_actor_move_target()
	_active_player_order = false
	var custody := get_custody()
	if custody != null:
		custody.set_container(cell)
	global_position = cell_position
	global_rotation = cell_rotation
	velocity = Vector3.ZERO
	_on_enter_custody()


func exit_cell_custody(exit_position: Vector3, exit_rotation: Vector3) -> void:
	_on_exit_custody()
	var custody := get_custody()
	if custody != null:
		custody.set_container(null)
	global_position = exit_position
	global_rotation = exit_rotation
	velocity = Vector3.ZERO


func _on_enter_custody() -> void:
	pass


func _on_exit_custody() -> void:
	pass


# ---------------------------------------------------------------------------
# Equipment — typed delegation to EquipmentCapability
# ---------------------------------------------------------------------------

func get_equipped_item(slot_name: String) -> ItemDefinition:
	var equipment := get_equipment()
	return equipment.get_equipped_item(slot_name) if equipment != null else null


func equip_item_to_slot(definition: ItemDefinition, slot_name: String) -> ItemDefinition:
	var equipment := get_equipment()
	return equipment.equip_item_to_slot(definition, slot_name) if equipment != null else null


func unequip_item_from_slot(slot_name: String) -> ItemDefinition:
	var equipment := get_equipment()
	return equipment.unequip_item_from_slot(slot_name) if equipment != null else null


func get_equipped_weight() -> float:
	var equipment := get_equipment()
	return equipment.get_equipped_weight() if equipment != null else 0.0


## Base actor exposes no equipment slots; humanoids override with their slot list.
func get_equipment_slot_names() -> Array[String]:
	return []


func get_equipment_slot_label(slot_name: String) -> String:
	return slot_name.capitalize()


# MIGRATION STUB: move to BodyProjection child node.
func get_body_projection() -> BodyProjection:
	return null


# MIGRATION STUB: move to BodyProjection child node.
func get_character_visual_root() -> Node3D:
	return null


# MIGRATION STUB: move to BodyProjection child node.
func get_resolved_body_archetype() -> Resource:
	return null


# MIGRATION STUB: move to BodyProjection child node.
func get_resolved_visual_body_type() -> int:
	return 0


# MIGRATION STUB: move to WorldText/Presentation child node.
func show_world_notice(_text: String, _color: Color = Color.WHITE, _duration: float = 1.5) -> void:
	pass


# MIGRATION STUB: move to WorldText/Presentation child node.
func show_world_speech(_text: String, _duration: float = 2.0) -> void:
	pass


func get_vital_fluid_label() -> String:
	var vitals := get_vitals()
	return vitals.get_vital_fluid_label() if vitals != null else "Blood"


func get_health_vital_label() -> String:
	var vitals := get_vitals()
	return vitals.get_health_vital_label() if vitals != null else "Health"


func get_vital_fluid_bar_color(fallback_color: Color) -> Color:
	var vitals := get_vitals()
	return vitals.get_vital_fluid_bar_color(fallback_color) if vitals != null else fallback_color


func get_vital_fluid_glow_color(fallback_color: Color) -> Color:
	var vitals := get_vitals()
	return vitals.get_vital_fluid_glow_color(fallback_color) if vitals != null else fallback_color


func get_vital_fluid_blink_strength() -> float:
	var vitals := get_vitals()
	return vitals.get_vital_fluid_blink_strength() if vitals != null else 0.0


func get_vital_fluid_blink_speed() -> float:
	var vitals := get_vitals()
	return vitals.get_vital_fluid_blink_speed() if vitals != null else 0.0


func get_vital_fluid_blink_color(fallback_color: Color) -> Color:
	var vitals := get_vitals()
	return vitals.get_vital_fluid_blink_color(fallback_color) if vitals != null else fallback_color


func get_life_state_label() -> String:
	var vitals := get_vitals()
	return vitals.get_life_state_label() if vitals != null else NpcRules.get_life_state_label(life_state)


## Typed accessor for the needs capability. Returns null only if absent.
func get_needs() -> NeedsCapability:
	return get_capability(&"needs") as NeedsCapability


func shows_hunger_vital() -> bool:
	var needs := get_needs()
	return needs != null and needs.hunger_enabled


func get_hunger_stage() -> int:
	var needs := get_needs()
	return needs.hunger_stage if needs != null else NpcRules.HungerStage.WELL_NOURISHED


func get_hunger_stage_label() -> String:
	var needs := get_needs()
	return needs.get_hunger_stage_label() if needs != null else ""


func shows_fatigue_vital() -> bool:
	var needs := get_needs()
	return needs != null and needs.fatigue_enabled


func get_fatigue_stage() -> int:
	var needs := get_needs()
	return needs.fatigue_stage if needs != null else NpcRules.FatigueStage.WELL_RESTED


func get_fatigue_stage_label() -> String:
	var needs := get_needs()
	return needs.get_fatigue_stage_label() if needs != null else ""


func spend_fatigue(amount: float) -> void:
	var needs := get_needs()
	if needs != null and amount > 0.0:
		needs.apply_fatigue_delta(-amount)


# --- Player interaction surface (behavior bar, right-click menus) -------------------

func set_combat_stance(value: int) -> void:
	combat_stance = clampi(value, NpcRules.CombatStance.AGGRESSIVE, NpcRules.CombatStance.PASSIVE)
	state_changed.emit()


func is_auto_heal_enabled() -> bool:
	return auto_heal_enabled and life_state == NpcRules.LifeState.ALIVE


func set_auto_heal_enabled(value: bool) -> void:
	auto_heal_enabled = value
	state_changed.emit()


func is_auto_burn_rustdead_enabled() -> bool:
	return auto_burn_rustdead_enabled and life_state == NpcRules.LifeState.ALIVE


func set_auto_burn_rustdead_enabled(value: bool) -> void:
	auto_burn_rustdead_enabled = value
	state_changed.emit()


## Rustdead override these two: they only die to fire.
func requires_fire_to_die() -> bool:
	return false


func can_be_destroyed_by_cinder() -> bool:
	return false


## Base actors have no wound model; HumanoidCharacter overrides with vitals.
func can_receive_bandage() -> bool:
	return false


## Authored conversation content; the right-click menu offers "Talk To" when set.
@export var conversation_definition: Resource


func has_conversation_definition() -> bool:
	return conversation_definition != null


func get_conversation_definition() -> Resource:
	return conversation_definition


# Talk-order handshake: the interaction flow registers an approaching party member,
# and the conversation trigger resolves it when they arrive.
var _pending_talker_ids: Dictionary = {}


func register_talker(member: Node) -> void:
	if member != null and is_instance_valid(member):
		_pending_talker_ids[member.get_instance_id()] = true


func resolve_talk(member: Node) -> bool:
	if member == null:
		return false
	if not _pending_talker_ids.has(member.get_instance_id()):
		return false
	_pending_talker_ids.clear()
	return true


# --- Player order state machine ------------------------------------------------------
# InteractionCapability owns the per-order logic (walk to X, then do Y); it reads and
# writes this state on the actor and the dispatcher below advances the active order
# each physics tick. Signals are re-emitted here for UI and venue observers.

signal mining_changed
signal scavenging_changed
signal container_reached(member, container)
signal trade_target_reached(member, target)
signal conversation_target_reached(member, target)
signal center_notice_requested(text, color)

@export var interact_distance := 1.8

## Mirror the carry capability's carried body for order-flow reads.
var _carried_character: Node:
	get:
		var carry := get_carry()
		return carry.get_carried_character() if carry != null else null
	set(_value):
		pass


## Typed accessor for the interaction capability. Returns null only if absent.
func get_interaction() -> InteractionCapability:
	return get_capability(&"interaction") as InteractionCapability


## Player orders suppress combat until completed (see _process_active_order release).
func _on_order_changed(order_type: int, issued_by_player: bool) -> void:
	if issued_by_player and order_type != InteractionCapability.ORDER_TYPE_NONE:
		_active_player_order = true
		# A player order is an explicit disengage: drop all grudges so the member
		# doesn't boomerang back to an old enemy when the order completes. Attack
		# commands re-add their own grudge (assign_attack_target marks it before
		# begin_combat_order emits a non-player NONE, which skips this branch).
		clear_all_personal_hostility()


func get_current_order_type() -> int:
	var interaction := get_interaction()
	return interaction.current_order_type if interaction != null else InteractionCapability.ORDER_TYPE_NONE


## Advances the active order. Combat suspends orders (except the resume/release
## bookkeeping); the capability's process_* functions own arrival and execution.
func _process_active_order(delta: float) -> void:
	var interaction := get_interaction()
	if interaction == null:
		return
	if interaction.current_order_type == InteractionCapability.ORDER_TYPE_NONE:
		if interaction.order_was_player_issued:
			interaction.order_was_player_issued = false
			_active_player_order = false
		return
	if life_state != NpcRules.LifeState.ALIVE or is_in_combat():
		return
	match interaction.current_order_type:
		InteractionCapability.ORDER_TYPE_MINE:
			interaction.process_mining(delta)
		InteractionCapability.ORDER_TYPE_SCAVENGE:
			interaction.process_scavenging(delta)
		InteractionCapability.ORDER_TYPE_OPEN_CONTAINER:
			interaction.process_container_interaction()
		InteractionCapability.ORDER_TYPE_TRADE:
			interaction.process_trade_interaction()
		InteractionCapability.ORDER_TYPE_TALK:
			interaction.process_conversation_interaction()
		InteractionCapability.ORDER_TYPE_HEAL:
			interaction.process_heal_interaction()
		InteractionCapability.ORDER_TYPE_FINISH_OFF:
			interaction.process_finish_off_interaction()
		InteractionCapability.ORDER_TYPE_CARRY:
			interaction.process_carry_interaction()
		InteractionCapability.ORDER_TYPE_SLEEP:
			interaction.process_sleep_interaction()
		InteractionCapability.ORDER_TYPE_PLACE_IN_BED:
			interaction.process_place_in_bed_interaction()
		InteractionCapability.ORDER_TYPE_PLACE_IN_CELL:
			interaction.process_place_in_cell_interaction()
		InteractionCapability.ORDER_TYPE_PLACE_IN_FURNACE:
			interaction.process_place_in_furnace_interaction()
		InteractionCapability.ORDER_TYPE_SIT:
			interaction.process_seat_interaction()
		InteractionCapability.ORDER_TYPE_PICKUP_ITEM:
			interaction.process_pickup_interaction()


## Carry pickup actuation, called by the interaction capability at arrival.
## Releases whoever this actor is carrying (cell placement, forced drops).
## The capability owns the state and signals both sides via carry_changed.
func _detach_carried_character() -> void:
	var carry := get_carry()
	if carry != null:
		carry.drop()


func _attach_carried_character(target: Node) -> void:
	var carry := get_carry()
	var target_actor := target as WorldActor
	var target_carry := target_actor.get_carry() if target_actor != null else null
	if carry == null or target_carry == null:
		return
	carry.begin_carry(target_carry, target_actor.faction_name == faction_name)


## Close enough to interact with a downed body (bandage, carry, finish off).
func _is_close_enough_to_downed_interaction_target(target_character: Node, extra_distance: float = 0.0) -> bool:
	var target_node := target_character as Node3D
	if target_node == null or not is_instance_valid(target_node):
		return false
	var anchor := (target_character as WorldActor).get_follow_anchor_position() if target_character is WorldActor else target_node.global_position
	var offset := anchor - global_position
	var vertical := absf(offset.y)
	offset.y = 0.0
	return offset.length() <= interact_distance + extra_distance and vertical <= move_target_vertical_tolerance + 0.9


# --- Venue/world-content actor surface (seats, beds, jails, jobs, mining) -----------

const CONTAINMENT_SIZE_SMALL := 0
const CONTAINMENT_SIZE_MEDIUM := 1


## Aligns the actor origin so the collision bottom rests on a floor point
## (seats/beds place actors by floor contact, not by origin).
func get_floor_aligned_origin_position(floor_position: Vector3) -> Vector3:
	return Vector3(floor_position.x, floor_position.y - get_collision_bottom_local_y(), floor_position.z)


func get_collision_bottom_local_y() -> float:
	var collision_shape := _get_main_collision_shape()
	if collision_shape == null or collision_shape.shape == null:
		return 0.0
	var shape := collision_shape.shape
	var bottom := 0.0
	if shape is CapsuleShape3D:
		bottom = -(shape as CapsuleShape3D).height * 0.5
	elif shape is BoxShape3D:
		bottom = -(shape as BoxShape3D).size.y * 0.5
	elif shape is SphereShape3D:
		bottom = -(shape as SphereShape3D).radius
	return collision_shape.transform.origin.y + bottom


func wake_up_from_rest(show_notice: bool = true) -> void:
	var interaction := get_interaction()
	if interaction != null:
		interaction.wake_up_from_rest(show_notice)


func is_sitting() -> bool:
	var interaction := get_interaction()
	return interaction.is_sitting if interaction != null else false


func get_current_seat_target() -> Node:
	var interaction := get_interaction()
	var seat: Node = interaction.current_seat_target if interaction != null else null
	return seat if seat != null and is_instance_valid(seat) else null


func is_imprisonable() -> bool:
	return true


func get_containment_size_class() -> int:
	return CONTAINMENT_SIZE_MEDIUM


func get_assigned_mining_node() -> Node:
	var interaction := get_interaction()
	var mining_node: Node = interaction.current_mining_node if interaction != null else null
	return mining_node if mining_node != null and is_instance_valid(mining_node) else null


## Work-progress surface consumed by the party HUD progress bars.
func is_actively_mining() -> bool:
	var interaction := get_interaction()
	return interaction != null and interaction.mining_active


func get_mining_progress_ratio() -> float:
	var interaction := get_interaction()
	if interaction == null or interaction.current_mining_node == null:
		return 0.0
	return interaction.get_stored_mining_progress(interaction.current_mining_node)


func is_actively_scavenging() -> bool:
	var interaction := get_interaction()
	return interaction != null and interaction.scavenging_active


func get_scavenging_progress_ratio() -> float:
	var interaction := get_interaction()
	if interaction == null or interaction.current_scavenging_node == null:
		return 0.0
	return interaction.get_stored_scavenging_progress(interaction.current_scavenging_node)


## Law-movement façades (jail custody return walk, sentence delivery walk) —
## consumed by LawOrderController and SettlementJail via has_method.
func assign_law_custody_return_target(target_position: Vector3) -> void:
	var interaction := get_interaction()
	if interaction != null:
		interaction.assign_law_custody_return_target(target_position)


func assign_law_sentence_move_target(target_position: Vector3) -> void:
	var interaction := get_interaction()
	if interaction != null:
		interaction.assign_law_sentence_move_target(target_position)


func stop_mining_assignment() -> void:
	var interaction := get_interaction()
	if interaction != null:
		interaction.stop_mining_assignment()


# Job-provider assignment: state only for now. The runtime AI-job request that used
# to accompany assignment (ai_brain work jobs) is pending its own restoration; the
# provider bookkeeping and UI status must not crash meanwhile.
var _active_job_provider: Node
var _active_job_label := ""


func begin_job_assignment(provider: Node, job_label: String, _work_inventory = null, _request_runtime_job := true) -> void:
	_active_job_provider = provider
	_active_job_label = job_label
	state_changed.emit()


func end_job_assignment() -> void:
	_active_job_provider = null
	_active_job_label = ""
	state_changed.emit()


func get_active_job_provider() -> Node:
	return _active_job_provider if _active_job_provider != null and is_instance_valid(_active_job_provider) else null


func get_job_status_text() -> String:
	if _active_job_provider != null and is_instance_valid(_active_job_provider) and _active_job_provider.has_method("get_provider_name"):
		return "Working for %s" % _active_job_provider.get_provider_name()
	if _active_job_provider != null:
		return "Working"
	return ""


# Order façades: the right-click menu and venue flows call these on the actor.

func assign_carry_target(target_character: Node, issued_by_player: bool = true) -> void:
	var interaction := get_interaction()
	if interaction != null:
		interaction.assign_carry_target(target_character, issued_by_player)


func assign_heal_target(target_character: Node, issued_by_player: bool = true) -> void:
	var interaction := get_interaction()
	if interaction != null:
		interaction.assign_heal_target(target_character, issued_by_player)


func assign_finish_off_target(target_character: Node, issued_by_player: bool = true) -> void:
	var interaction := get_interaction()
	if interaction != null:
		interaction.assign_finish_off_target(target_character, issued_by_player)


func assign_sleep_target(bed: Node, issued_by_player: bool = true) -> void:
	var interaction := get_interaction()
	if interaction != null:
		interaction.assign_sleep_target(bed, issued_by_player)


func assign_seat_target(seat: Node, issued_by_player: bool = true) -> void:
	var interaction := get_interaction()
	if interaction != null:
		interaction.assign_seat_target(seat, issued_by_player)


func assign_open_container(container: Node, issued_by_player: bool = true) -> void:
	var interaction := get_interaction()
	if interaction != null:
		interaction.assign_open_container(container, issued_by_player)


func assign_trade_target(target_character: Node, issued_by_player: bool = true) -> void:
	var interaction := get_interaction()
	if interaction != null:
		interaction.assign_trade_target(target_character, issued_by_player)


func assign_conversation_target(target_character: Node, issued_by_player: bool = true) -> void:
	var interaction := get_interaction()
	if interaction != null:
		interaction.assign_conversation_target(target_character, issued_by_player)


func assign_mining_resource(resource_node: Node, issued_by_player: bool = true) -> void:
	var interaction := get_interaction()
	if interaction != null:
		interaction.assign_mining_resource(resource_node, issued_by_player)


func assign_scavenging_resource(resource_node: Node, issued_by_player: bool = true) -> void:
	var interaction := get_interaction()
	if interaction != null:
		interaction.assign_scavenging_resource(resource_node, issued_by_player)


func assign_pickup_item(world_item: Node, issued_by_player: bool = true) -> void:
	var interaction := get_interaction()
	if interaction != null:
		interaction.assign_pickup_item(world_item, issued_by_player)


func assign_place_carried_in_bed_target(bed: Node, issued_by_player: bool = true) -> void:
	var interaction := get_interaction()
	if interaction != null:
		interaction.assign_place_carried_in_bed_target(bed, issued_by_player)


func assign_place_carried_in_cell_target(cell: Node, issued_by_player: bool = true) -> void:
	var interaction := get_interaction()
	if interaction != null:
		interaction.assign_place_carried_in_cell_target(cell, issued_by_player)


func assign_place_carried_in_furnace_target(furnace: Node, issued_by_player: bool = true) -> void:
	var interaction := get_interaction()
	if interaction != null:
		interaction.assign_place_carried_in_furnace_target(furnace, issued_by_player)


func get_total_wound_damage() -> float:
	var vitals := get_vitals()
	return vitals.get_total_wound_damage() if vitals != null else 0.0


func get_bleed_rate() -> float:
	var vitals := get_vitals()
	return vitals.get_bleed_rate() if vitals != null else 0.0


func get_open_cut_damage() -> float:
	var vitals := get_vitals()
	return vitals.open_cut_damage if vitals != null else 0.0


func get_bandaged_cut_damage() -> float:
	var vitals := get_vitals()
	return vitals.bandaged_cut_damage if vitals != null else 0.0


func get_blunt_damage() -> float:
	var vitals := get_vitals()
	return vitals.blunt_damage if vitals != null else 0.0


func get_death_point(_actor_max_hp: float) -> float:
	var vitals := get_vitals()
	return vitals.get_death_point(_actor_max_hp) if vitals != null else -maxf(_actor_max_hp, 1.0)


func get_coma_point(_part_max_health: float = -1.0) -> float:
	var vitals := get_vitals()
	return vitals.get_coma_point(_part_max_health) if vitals != null else 0.0


func get_blood_death_point() -> float:
	var vitals := get_vitals()
	return vitals.get_blood_death_point() if vitals != null else -maxf(max_blood, 1.0)


func get_dying_seconds() -> float:
	var vitals := get_vitals()
	return vitals.get_dying_seconds() if vitals != null else 20.0


func get_base_max_blood() -> float:
	var vitals := get_vitals()
	return vitals.get_base_max_blood() if vitals != null else maxf(_pending_base_max_blood if _pending_base_max_blood > 0.0 else _pending_max_blood, 1.0)


func refresh_max_blood_from_toughness() -> void:
	var vitals := get_vitals()
	if vitals != null:
		vitals.refresh_max_blood_from_toughness(true)


func is_downed_state() -> bool:
	var vitals := get_vitals()
	return vitals.is_downed_state() if vitals != null else VitalsCapability.is_life_state_downed(life_state)


func is_recoverable_downed_state() -> bool:
	var vitals := get_vitals()
	return vitals.is_recoverable_downed_state() if vitals != null else VitalsCapability.is_life_state_recoverable_downed(life_state)


func is_dead_or_dying_state() -> bool:
	var vitals := get_vitals()
	return vitals.is_dead_or_dying_state() if vitals != null else VitalsCapability.is_life_state_dead_or_dying(life_state)


func force_kill(_attacker: Node = null) -> void:
	var vitals := get_vitals()
	if vitals != null:
		vitals.force_kill()


func force_unconscious() -> void:
	var vitals := get_vitals()
	if vitals != null:
		vitals.force_unconscious()


func _recalculate_vitals() -> void:
	var vitals := get_vitals()
	if vitals != null:
		vitals.recalculate_vitals()


func _apply_blood_loss(amount: float) -> void:
	var vitals := get_vitals()
	if vitals != null:
		vitals.apply_blood_loss(amount)


func _process_bleeding(delta: float) -> void:
	var vitals := get_vitals()
	if vitals != null:
		vitals.process_bleeding(delta)


func _process_dying(delta: float) -> void:
	var vitals := get_vitals()
	if vitals != null:
		vitals.process_dying(delta)


func _process_recovery(delta: float) -> void:
	var vitals := get_vitals()
	if vitals != null:
		vitals.process_recovery(delta)


func _clear_actor_move_target() -> void:
	_has_move_target = false
	_navigation_target_synced = false
	_navigation_query_grace_remaining = 0.0
	_navigation_zero_waypoint_blocked = false
	_has_avoidance_velocity = false
	_reset_stuck_tracking()
	if _navigation_agent != null and is_instance_valid(_navigation_agent):
		_navigation_agent.velocity = Vector3.ZERO
