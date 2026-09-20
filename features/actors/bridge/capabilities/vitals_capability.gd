extends "res://features/actors/bridge/capabilities/actor_capability.gd"

class_name VitalsCapability

## Public medical commands and the projected view of actor vitals. Registered
## humanoid commands mutate the injected GECS component before emitting signals.
## Both commands and simulation use VitalsStateMachine; WorldActor only delegates.
##
## Dependency shape follows StatsCapability: one typed handle acquired in
## `ready()`. Vitals reads Stats for toughness and healing rates; Stats never
## reads Vitals. Cross-capability reactions come from StatsCapability's
## `skill_level_changed` signal.

const COMA_BASE_FACTOR := 0.10
const COMA_TOUGHNESS_WEIGHT := 0.0075
const COMA_FACTOR_CAP := 0.85
const DYING_BASE_SECONDS := 20.0
const DYING_TOUGHNESS_SECONDS := 0.8

const RECOVERY_MULTIPLIER_GROUND := 1.0
const RECOVERY_MULTIPLIER_CAMP_BED := 4.0
const RECOVERY_MULTIPLIER_BED := 8.0

signal life_state_changed(previous_state: int, new_state: int)

# --- Durable vitals state ---------------------------------------------------

var life_state: int = NpcRules.LifeState.ALIVE

var max_hp := 100.0
var hp := 100.0

var base_max_blood := 0.0
var max_blood := 100.0
var blood := 100.0

var blunt_damage := 0.0
var open_cut_damage := 0.0
var bandaged_cut_damage := 0.0
var bleed_rate := 0.0
var bleed_burst_rate := 0.0

var recovery_multiplier := RECOVERY_MULTIPLIER_GROUND
var dying_timer_remaining := 0.0

# --- Internal ---------------------------------------------------------------

var _stats: StatsCapability
var _base_max_blood_for_toughness := 0.0
var _last_max_blood_toughness_level := -INF
# GameVitalsSystem owns periodic simulation. GameActorSyncSystem reflects its
# component each tick; public commands mutate that same component, not this view.
# Robots/quadbots keep their node-side death model (S5), so they stay self-driven.
var _system_owned := false
## Which death model this actor uses (HUMANOID = GECS-system-owned vitals; ROBOT = node-owned).
## The actor pushes this in as DATA at capability creation, so this capability never type-checks
## the actor's class (`is RobotActor`) — that back-edge kept the actor<->capability cycle alive.
var death_profile: int = CGameActorVitals.DeathProfile.HUMANOID
var fire_only_death := false
var held_externally_hold := false
# Injected by the GECS bridge; never retain a removed projection's component.
var _authority_ref: WeakRef


func _init() -> void:
	super._init(&"vitals")
	process_enabled = true


func ready() -> void:
	_stats = actor.get_capability(&"stats") as StatsCapability if actor != null else null
	if _stats != null and not _stats.skill_level_changed.is_connected(_on_skill_level_changed):
		_stats.skill_level_changed.connect(_on_skill_level_changed)
	_system_owned = death_profile == CGameActorVitals.DeathProfile.HUMANOID
	refresh_max_blood_from_toughness(true)
	recalculate_vitals()


func teardown() -> void:
	unbind_authoritative_state()
	if _stats != null and _stats.skill_level_changed.is_connected(_on_skill_level_changed):
		_stats.skill_level_changed.disconnect(_on_skill_level_changed)
	_stats = null
	super.teardown()


func process(delta: float) -> void:
	# Observer for system-owned (realized humanoid) actors: GameVitalsSystem ticks bleeding/dying/
	# recovery on the component; this node just reflects it. RobotActor owns its own oil tick.
	if _system_owned or death_profile == CGameActorVitals.DeathProfile.ROBOT:
		# RobotActor owns its hull/oil tick. Organic healing would refill oil
		# and revive an offline robot during QuadBotCharacter.super._process().
		return
	process_bleeding(delta)
	process_dying(delta)
	process_recovery(delta)

# ---------------------------------------------------------------------------
# Authoring / save injection
# ---------------------------------------------------------------------------

func configure_initial_values(initial_max_hp: float, initial_hp: float, initial_base_max_blood: float, initial_max_blood: float, initial_blood: float, initial_life_state: int) -> void:
	max_hp = maxf(initial_max_hp, 1.0)
	hp = initial_hp
	base_max_blood = maxf(initial_base_max_blood, 0.0)
	max_blood = maxf(initial_max_blood, 1.0)
	blood = initial_blood
	life_state = initial_life_state
	_capture_base_max_blood_for_toughness()


func configure_vitals(config: Dictionary) -> void:
	set_max_hp(float(config.get("max_hp", max_hp)))
	set_hp(float(config.get("hp", hp)))
	set_base_max_blood(float(config.get("base_max_blood", base_max_blood)))
	set_max_blood(float(config.get("max_blood", max_blood)))
	set_blood(float(config.get("blood", blood)))
	set_life_state(int(config.get("life_state", life_state)))

# ---------------------------------------------------------------------------
# Direct state setters
# ---------------------------------------------------------------------------

func set_life_state(value: int) -> void:
	var previous := life_state
	var state = _command_state()
	var next := clampi(value, NpcRules.LifeState.ALIVE, NpcRules.LifeState.DYING)
	# Voluntary sleep/wake is requested through InteractionCapability and
	# validated by GameVitalsSystem. A projected rest assignment is not a
	# medical command and must not bypass that existing authority.
	if state != self and next in [NpcRules.LifeState.ALIVE, NpcRules.LifeState.ASLEEP]:
		_set_life_state(next)
		return
	state.life_state = next
	if state.life_state == NpcRules.LifeState.DEAD:
		state.dying_timer_remaining = 0.0
	_reflect_command_result(state, previous)


func set_max_hp(value: float) -> void:
	var state = _command_state()
	var previous_max := maxf(state.max_hp, 1.0)
	var was_full: bool = state.hp >= previous_max - 0.05
	state.max_hp = maxf(value, 1.0)
	state.hp = state.max_hp if was_full else minf(state.hp, state.max_hp)
	_recalculate_command_state(state)


func set_hp(value: float) -> void:
	var state = _command_state()
	state.hp = value
	state.blunt_damage = maxf(0.0, state.max_hp - state.hp - state.open_cut_damage - state.bandaged_cut_damage)
	_recalculate_command_state(state)


func set_base_max_blood(value: float) -> void:
	var state = _command_state()
	state.base_max_blood = maxf(value, 0.0)
	_base_max_blood_for_toughness = maxf(state.base_max_blood if state.base_max_blood > 0.0 else state.max_blood, 1.0)
	refresh_max_blood_from_toughness(true)


func set_max_blood(value: float) -> void:
	var state = _command_state()
	var was_full: bool = state.blood >= maxf(state.max_blood, 1.0) - 0.05
	state.max_blood = maxf(value, 1.0)
	state.blood = state.max_blood if was_full else clampf(state.blood, VitalsMath.blood_death_point(state.max_blood), state.max_blood)
	_recalculate_command_state(state)


func set_blood(value: float) -> void:
	var state = _command_state()
	state.blood = clampf(value, VitalsMath.blood_death_point(state.max_blood), state.max_blood)
	_recalculate_command_state(state)


func set_blunt_damage(value: float) -> void:
	var state = _command_state()
	state.blunt_damage = maxf(value, 0.0)
	_recalculate_command_state(state)


func set_open_cut_damage(value: float) -> void:
	var state = _command_state()
	state.open_cut_damage = maxf(value, 0.0)
	_recalculate_command_state(state)


func set_bandaged_cut_damage(value: float) -> void:
	var state = _command_state()
	state.bandaged_cut_damage = maxf(value, 0.0)
	_recalculate_command_state(state)


func set_bleed_rate(value: float) -> void:
	var state = _command_state()
	state.bleed_rate = maxf(value, 0.0)
	_reflect_command_result(state, life_state)


func set_bleed_burst_rate(value: float) -> void:
	var state = _command_state()
	state.bleed_burst_rate = maxf(value, 0.0)
	_reflect_command_result(state, life_state)


func set_recovery_multiplier(value: float) -> void:
	var state = _command_state()
	state.recovery_multiplier = maxf(value, RECOVERY_MULTIPLIER_GROUND)
	_reflect_command_result(state, life_state)

# ---------------------------------------------------------------------------
# Wounds / blood
# ---------------------------------------------------------------------------

func apply_resolved_damage(blunt_amount: float, cut_amount: float) -> void:
	var state = _command_state()
	state.blunt_damage += maxf(blunt_amount, 0.0)
	state.open_cut_damage += maxf(cut_amount, 0.0)
	_recalculate_command_state(state)


func apply_blood_loss(amount: float) -> void:
	var state = _command_state()
	if amount <= 0.0 or state.life_state == NpcRules.LifeState.DEAD:
		return
	state.blood = VitalsMath.apply_blood_loss(state.blood, amount, state.max_blood)
	_recalculate_command_state(state)


func force_kill() -> void:
	var previous := life_state
	var state = _command_state()
	if state.life_state == NpcRules.LifeState.DEAD:
		return
	state.hp = VitalsMath.death_point(state.max_hp)
	state.blunt_damage = maxf(0.0, state.max_hp - state.hp - state.open_cut_damage - state.bandaged_cut_damage)
	state.blood = VitalsMath.blood_death_point(state.max_blood)
	state.dying_timer_remaining = 0.0
	state.life_state = NpcRules.LifeState.UNCONSCIOUS if state.fire_only_death else NpcRules.LifeState.DEAD
	_reflect_command_result(state, previous)


func force_unconscious() -> void:
	var previous := life_state
	var state = _command_state()
	if state.life_state == NpcRules.LifeState.DEAD:
		return
	state.life_state = NpcRules.LifeState.UNCONSCIOUS
	_reflect_command_result(state, previous)


func get_total_wound_damage() -> float:
	return VitalsMath.total_wound_damage(blunt_damage, open_cut_damage, bandaged_cut_damage)


func get_bleed_rate() -> float:
	return bleed_rate + bleed_burst_rate

# ---------------------------------------------------------------------------
# Thresholds
# ---------------------------------------------------------------------------

func get_coma_point(part_max_health: float = -1.0) -> float:
	var basis := part_max_health if part_max_health > 0.0 else max_hp
	return VitalsMath.coma_point(basis, _get_toughness())


func get_death_point(part_max_health: float = -1.0) -> float:
	var basis := part_max_health if part_max_health > 0.0 else max_hp
	return VitalsMath.death_point(basis)


func get_blood_death_point() -> float:
	return VitalsMath.blood_death_point(max_blood)


func get_dying_seconds() -> float:
	return VitalsMath.dying_seconds(_get_toughness())


func get_base_max_blood() -> float:
	_capture_base_max_blood_for_toughness()
	return _base_max_blood_for_toughness

# ---------------------------------------------------------------------------
# State resolution
# ---------------------------------------------------------------------------

func recalculate_vitals() -> void:
	_recalculate_command_state(_command_state())


func process_bleeding(delta: float) -> void:
	var previous := life_state
	var state = _command_state()
	VitalsStateMachine.process_bleeding(state, _get_toughness(), delta)
	_reflect_command_result(state, previous)


func process_dying(delta: float) -> void:
	var previous := life_state
	var state = _command_state()
	VitalsStateMachine.process_dying(state, delta)
	_reflect_command_result(state, previous)


func process_recovery(delta: float) -> void:
	var previous := life_state
	var state = _command_state()
	VitalsStateMachine.process_recovery(state, _get_toughness(), _get_healing_rate(), delta)
	_reflect_command_result(state, previous)


## Registration/load bind the canonical component. Robots retain their own death model.
func bind_authoritative_state(component: CGameActorVitals) -> void:
	if component == null or death_profile == CGameActorVitals.DeathProfile.ROBOT:
		return
	if _authority_ref != null and _authority_ref.get_ref() == component:
		return
	if not component.vitals_seeded:
		for field in CGameActorVitals.DURABLE_FIELDS:
			component.set(field, get(field))
		component.vitals_seeded = true
	component.fire_only_death = fire_only_death
	_authority_ref = weakref(component)
	if component.base_max_blood > 0.0:
		_base_max_blood_for_toughness = component.base_max_blood
	_reflect_command_result(component, life_state)
	# Tier/loaded skills may have been applied before registration. Reconcile
	# the shared toughness formula once, preserving injured blood quantities.
	if component.life_state != NpcRules.LifeState.DEAD:
		refresh_max_blood_from_toughness(true)


func unbind_authoritative_state() -> void:
	_authority_ref = null


func _command_state():
	var component = _authority_ref.get_ref() if _authority_ref != null else null
	return component if component != null else self


func _recalculate_command_state(state) -> void:
	var previous := life_state
	VitalsStateMachine.recalculate(state, _get_toughness())
	_reflect_command_result(state, previous)


func _reflect_command_result(state, previous: int) -> void:
	if state != self:
		state.copy_durable_state_to(self)
	var next_state := life_state
	life_state = previous
	_set_life_state(next_state)


func _set_life_state(next_state: int) -> void:
	if life_state == next_state:
		return
	var previous_state := life_state
	life_state = next_state
	# Emit only our own signal. The actor OBSERVES this (connected in _create_actor_capabilities)
	# and re-emits its node signals (life_state_changed/died/state_changed) — so this capability
	# holds no reference to the actor class, cutting the actor<->capability cycle edge.
	life_state_changed.emit(previous_state, life_state)


func _has_lethal_dying_vitals() -> bool:
	return VitalsMath.has_lethal_dying_vitals(hp, blood, max_hp, max_blood)

# ---------------------------------------------------------------------------
# Life state helpers
# ---------------------------------------------------------------------------

func get_life_state_label() -> String:
	return NpcRules.get_life_state_label(life_state)


func get_health_vital_label() -> String:
	return "Health"


func get_vital_fluid_label() -> String:
	return "Blood"


func get_vital_fluid_bar_color(fallback_color: Color) -> Color:
	return fallback_color


func get_vital_fluid_glow_color(fallback_color: Color) -> Color:
	return fallback_color


func get_vital_fluid_blink_strength() -> float:
	return 0.0


func get_vital_fluid_blink_speed() -> float:
	return 0.0


func get_vital_fluid_blink_color(fallback_color: Color) -> Color:
	return fallback_color


func is_downed_state() -> bool:
	return is_life_state_downed(life_state)


func is_recoverable_downed_state() -> bool:
	return is_life_state_recoverable_downed(life_state)


func is_dead_or_dying_state() -> bool:
	return is_life_state_dead_or_dying(life_state)


static func is_life_state_downed(state: int) -> bool:
	return state == NpcRules.LifeState.UNCONSCIOUS \
		or state == NpcRules.LifeState.RECOVERY_COMA \
		or state == NpcRules.LifeState.DYING


static func is_life_state_recoverable_downed(state: int) -> bool:
	return VitalsMath.is_recoverable_downed(state)


static func is_life_state_dead_or_dying(state: int) -> bool:
	return state == NpcRules.LifeState.DEAD or state == NpcRules.LifeState.DYING

# ---------------------------------------------------------------------------
# Toughness link
# ---------------------------------------------------------------------------

func refresh_max_blood_from_toughness(force := false) -> void:
	_capture_base_max_blood_for_toughness()
	var toughness_level := _get_toughness()
	if not force and is_equal_approx(toughness_level, _last_max_blood_toughness_level):
		return
	var state = _command_state()
	var was_full: bool = state.blood >= maxf(state.max_blood, 1.0) - 0.05
	state.max_blood = SkillRules.get_max_blood_for_toughness(_base_max_blood_for_toughness, toughness_level)
	state.blood = state.max_blood if was_full else clampf(state.blood, VitalsMath.blood_death_point(state.max_blood), state.max_blood)
	_last_max_blood_toughness_level = toughness_level
	_recalculate_command_state(state)


func _on_skill_level_changed(skill_id: String) -> void:
	if skill_id == SkillRules.ATTRIBUTE_TOUGHNESS:
		refresh_max_blood_from_toughness(true)


func _capture_base_max_blood_for_toughness() -> void:
	if _base_max_blood_for_toughness > 0.0:
		return
	_base_max_blood_for_toughness = maxf(base_max_blood if base_max_blood > 0.0 else max_blood, 1.0)


func _get_toughness() -> float:
	return _stats.get_stat_value("toughness") if _stats != null else 0.0


func _get_healing_rate() -> float:
	return _stats.get_stat_value("healing_rate") if _stats != null else NpcRules.BASE_HEAL_RATE
