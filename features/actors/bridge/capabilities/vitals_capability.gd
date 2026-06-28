extends "res://features/actors/bridge/capabilities/actor_capability.gd"

class_name VitalsCapability

## Owns one concern: actor vitals and life/death state.
##
## State lives here, not on the actor node. WorldActor exposes compatibility
## properties and thin delegations only.
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
# S4 FLIP: for realized humanoids the GECS GameVitalsSystem owns vitals and this capability is a
# read-only observer (GameActorSyncSystem reflects the component back onto our raw fields each tick).
# Robots/quadbots keep their node-side death model (S5), so they stay self-driven.
var _system_owned := false
## Which death model this actor uses (HUMANOID = GECS-system-owned vitals; ROBOT = node-owned).
## The actor pushes this in as DATA at capability creation, so this capability never type-checks
## the actor's class (`is RobotActor`) — that back-edge kept the actor<->capability cycle alive.
var death_profile: int = CGameActorVitals.DeathProfile.HUMANOID


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
	if _stats != null and _stats.skill_level_changed.is_connected(_on_skill_level_changed):
		_stats.skill_level_changed.disconnect(_on_skill_level_changed)
	_stats = null
	super.teardown()


func process(delta: float) -> void:
	# Observer for system-owned (realized humanoid) actors: GameVitalsSystem ticks bleeding/dying/
	# recovery on the component; this node just reflects it. Robots still self-drive here.
	if _system_owned:
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
	var next_state := clampi(value, NpcRules.LifeState.ALIVE, NpcRules.LifeState.DYING)
	_set_life_state(next_state)


func set_max_hp(value: float) -> void:
	var previous_max := maxf(max_hp, 1.0)
	var was_full := hp >= previous_max - 0.05
	max_hp = maxf(value, 1.0)
	if was_full:
		hp = max_hp
	else:
		hp = minf(hp, max_hp)
	recalculate_vitals()


func set_hp(value: float) -> void:
	hp = value
	var non_blunt_wounds := open_cut_damage + bandaged_cut_damage
	blunt_damage = maxf(0.0, max_hp - hp - non_blunt_wounds)
	recalculate_vitals()


func set_base_max_blood(value: float) -> void:
	base_max_blood = maxf(value, 0.0)
	_base_max_blood_for_toughness = 0.0
	refresh_max_blood_from_toughness(true)


func set_max_blood(value: float) -> void:
	var previous_max := maxf(max_blood, 1.0)
	var was_full := blood >= previous_max - 0.05
	max_blood = maxf(value, 1.0)
	_capture_base_max_blood_for_toughness()
	if was_full:
		blood = max_blood
	else:
		blood = clampf(blood, get_blood_death_point(), max_blood)
	recalculate_vitals()


func set_blood(value: float) -> void:
	blood = clampf(value, get_blood_death_point(), max_blood)
	recalculate_vitals()


func set_blunt_damage(value: float) -> void:
	blunt_damage = maxf(value, 0.0)
	recalculate_vitals()


func set_open_cut_damage(value: float) -> void:
	open_cut_damage = maxf(value, 0.0)
	recalculate_vitals()


func set_bandaged_cut_damage(value: float) -> void:
	bandaged_cut_damage = maxf(value, 0.0)
	recalculate_vitals()


func set_bleed_rate(value: float) -> void:
	bleed_rate = maxf(value, 0.0)


func set_bleed_burst_rate(value: float) -> void:
	bleed_burst_rate = maxf(value, 0.0)


func set_recovery_multiplier(value: float) -> void:
	recovery_multiplier = maxf(value, RECOVERY_MULTIPLIER_GROUND)

# ---------------------------------------------------------------------------
# Wounds / blood
# ---------------------------------------------------------------------------

func apply_resolved_damage(blunt_amount: float, cut_amount: float) -> void:
	blunt_damage += maxf(blunt_amount, 0.0)
	open_cut_damage += maxf(cut_amount, 0.0)
	recalculate_vitals()


func apply_blood_loss(amount: float) -> void:
	if amount <= 0.0 or life_state == NpcRules.LifeState.DEAD:
		return
	blood = VitalsMath.apply_blood_loss(blood, amount, max_blood)
	recalculate_vitals()


func force_kill() -> void:
	hp = get_death_point(max_hp)
	blood = get_blood_death_point()
	_enter_dead_state()


func force_unconscious() -> void:
	if life_state == NpcRules.LifeState.DEAD:
		return
	_enter_unconscious_state()


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
	hp = VitalsMath.hp_from_wounds(max_hp, get_total_wound_damage())
	if life_state == NpcRules.LifeState.DEAD:
		return
	var target := VitalsMath.resolve_life_state(life_state, hp, blood, max_hp, max_blood, _get_toughness())
	if target == NpcRules.LifeState.DYING:
		_enter_dying_state()
		return
	if target == NpcRules.LifeState.RECOVERY_COMA:
		_enter_recovery_coma_state()
		return
	if target == NpcRules.LifeState.UNCONSCIOUS:
		_enter_unconscious_state()
		return
	dying_timer_remaining = 0.0
	if target == NpcRules.LifeState.ALIVE:
		_set_life_state(NpcRules.LifeState.ALIVE)


func process_bleeding(delta: float) -> void:
	if life_state == NpcRules.LifeState.DEAD:
		return
	var total_bleed_rate := get_bleed_rate()
	if total_bleed_rate <= 0.0:
		return
	apply_blood_loss(VitalsMath.bleed_blood_loss(bleed_rate, bleed_burst_rate, delta))


func process_dying(delta: float) -> void:
	if life_state != NpcRules.LifeState.DYING:
		return
	if not _has_lethal_dying_vitals():
		_enter_recovery_coma_state()
		return
	dying_timer_remaining = maxf(0.0, dying_timer_remaining - delta)
	if dying_timer_remaining <= 0.0:
		_enter_dead_state()


func process_recovery(delta: float) -> void:
	if life_state == NpcRules.LifeState.DEAD:
		return
	if blunt_damage <= 0.0 and bandaged_cut_damage <= 0.0 and open_cut_damage <= 0.0 and bleed_burst_rate <= 0.0 and bleed_rate <= 0.0 and blood >= max_blood and not is_recoverable_downed_state():
		return
	# Preserve the original early-out: when there is no healing this tick, skip the wound update AND
	# the recalculate, exactly as before the VitalsMath extraction (recovery_step is pure and would
	# otherwise fall through to recalculate_vitals, which can transition a downed actor's life_state).
	if _get_healing_rate() * recovery_multiplier * delta <= 0.0:
		return
	var step := VitalsMath.recovery_step(blunt_damage, open_cut_damage, bandaged_cut_damage, bleed_rate, bleed_burst_rate, blood, max_blood, _get_healing_rate(), recovery_multiplier, delta)
	blunt_damage = step["blunt_damage"]
	open_cut_damage = step["open_cut_damage"]
	bandaged_cut_damage = step["bandaged_cut_damage"]
	bleed_rate = step["bleed_rate"]
	bleed_burst_rate = step["bleed_burst_rate"]
	blood = step["blood"]
	recalculate_vitals()


func _enter_unconscious_state() -> void:
	_set_life_state(NpcRules.LifeState.UNCONSCIOUS)


func _enter_recovery_coma_state() -> void:
	_set_life_state(NpcRules.LifeState.RECOVERY_COMA)


func _enter_dying_state() -> void:
	if life_state != NpcRules.LifeState.DYING:
		dying_timer_remaining = maxf(dying_timer_remaining, get_dying_seconds())
	_set_life_state(NpcRules.LifeState.DYING)


func _enter_dead_state() -> void:
	dying_timer_remaining = 0.0
	_set_life_state(NpcRules.LifeState.DEAD)


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
	var previous_max_blood := maxf(max_blood, 1.0)
	var was_full := blood >= previous_max_blood - 0.05
	max_blood = SkillRules.get_max_blood_for_toughness(_base_max_blood_for_toughness, toughness_level)
	if was_full:
		blood = max_blood
	else:
		blood = clampf(blood, get_blood_death_point(), max_blood)
	_last_max_blood_toughness_level = toughness_level
	recalculate_vitals()


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
