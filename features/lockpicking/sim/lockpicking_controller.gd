extends Node

const SERVICE_ID := &"lockpicking"
const ENTITY := preload("res://addons/gecs/ecs/entity.gd")
const WORK := preload("res://features/lockpicking/sim/c_game_lock_work.gd")
const PICKS := preload("res://features/lockpicking/sim/lockpick_rules.gd")
const CHECK := preload("res://features/skills/resources/checks/lockpicking_check.tres")
# Keep the existing saved beat_elapsed scale; this is work, not wall time.
const ATTEMPT_WORK_UNITS := 2.0
@export var settings: Resource = preload("res://features/lockpicking/resources/lockpicking_settings.tres")

signal lock_changed(lock_id: String, state: Dictionary)
## Successful cage/container work only; DoorController owns door unlock events.
signal object_unlocked(lock_id: String)
signal work_reset

var _gecs: Node
var _doors: Node
# Leases are execution state, intentionally not saved; no live actor references.
var _claims := {}

func initialize(context: BootstrapContext) -> void:
	_gecs = context.require(&"gecs_world")
	_doors = context.get_optional(&"doors")
	if not _gecs.world_reindexed.is_connected(_on_world_reindexed):
		_gecs.world_reindexed.connect(_on_world_reindexed)

func register_lock(record: Dictionary) -> Dictionary:
	var id := str(record.get("lock_id", ""))
	if id.is_empty() or _gecs == null or _gecs.world == null:
		return {}
	var work = _component(id)
	if work == null:
		var entity = ENTITY.new()
		entity.id = "lock_work:%s" % id
		entity.name = "LockWork"
		work = WORK.new()
		work.lock_id = id
		work.door_id = str(record.get("door_id", ""))
		work.object_locked = bool(record.get("is_locked", true))
		work.difficulty = clampf(float(record.get("difficulty", 10.0)), 0.0, 100.0)
		work.minimum_skill = maxf(0.0, float(record.get("minimum_skill", 0.0)))
		_gecs.world.add_entity(entity, [work])
	return get_state(id)

func get_state(id: String) -> Dictionary:
	var work = _component(id)
	if work == null:
		return {}
	var locked: bool = work.object_locked
	if not work.door_id.is_empty():
		var door: Dictionary = _doors.get_door_state(work.door_id) if _doors != null else {}
		if door.is_empty():
			return {}
		locked = bool(door.get("is_locked", false))
		var revision := int(door.get("state_revision", 0))
		if work.door_revision != revision:
			_claims.erase(id)
			work.progress = 0.0
			work.beat_elapsed = 0.0
			work.door_revision = revision
	return {"lock_id": id, "is_locked": locked, "progress": float(work.progress),
		"difficulty": float(work.difficulty), "minimum_skill": float(work.minimum_skill),
		"check_sequence": int(work.check_sequence), "beat_elapsed": float(work.beat_elapsed)}

func claim(id: String, actor_id: String, inventory: InventoryData, mode: String) -> Dictionary:
	var state := get_state(id)
	var pick = PICKS.find_pick(inventory)
	if actor_id.is_empty() or mode not in ["careful", "rushed"] or state.is_empty() or not state.is_locked or pick == null:
		return {"accepted": false, "reason": "unavailable"}
	if _claims.has(id):
		return {"accepted": false, "reason": "busy"}
	_claims[id] = {"actor_id": actor_id, "stack_id": pick.stack_id, "mode": mode,
		"inventory_id": inventory.get_instance_id()}
	return {"accepted": true, "stack_id": pick.stack_id}

func release(id: String, actor_id: String) -> void:
	if str(_claims.get(id, {}).get("actor_id", "")) == actor_id:
		_claims.erase(id)

func advance(id: String, actor_id: String, inventory: InventoryData, skill: float, dexterity: float, delta: float) -> Dictionary:
	var state := get_state(id)
	var lease: Dictionary = _claims.get(id, {})
	if str(lease.get("actor_id", "")) != actor_id or lease.is_empty():
		return {"accepted": false, "reason": "not_claimed"}
	if state.is_empty() or not state.is_locked or skill < float(state.minimum_skill):
		release(id, actor_id)
		return {"accepted": false, "reason": "unavailable"}
	if inventory == null or inventory.get_instance_id() != lease.inventory_id or PICKS.find_pick(inventory, lease.stack_id) == null:
		release(id, actor_id)
		return {"accepted": false, "reason": "pick_missing"}
	if delta <= 0.0 or not is_finite(delta):
		return {"accepted": false, "reason": "invalid_time"}
	var work = _component(id)
	var rushed: bool = lease.mode == "rushed"
	var score := SkillCheckRules.get_assisted_score(CHECK, skill, dexterity)
	var competence := clampf(float(CHECK.chance_at_equal_level) + (score - work.difficulty) * float(CHECK.chance_per_level_delta), float(CHECK.minimum_success_chance), float(CHECK.maximum_success_chance))
	var speed: float = ATTEMPT_WORK_UNITS / settings.attempt_seconds(skill, rushed)
	var risk := clampf((1.0 - competence) * float(settings.rushed_risk if rushed else settings.careful_risk), 0.0, 0.95)
	var interval := ATTEMPT_WORK_UNITS
	# Elapsed attempt work is stored in normalized units so changing picker/mode
	# cannot reroll a check or reinterpret its already-earned fraction.
	var remaining := delta * speed
	var setbacks := 0
	var successes := 0
	var broke := false
	# Integrate at check boundaries, not render frames. Pausing or restarting
	# cannot reset a partly elapsed beat or reroll its deterministic result.
	while remaining > 0.000001 and work.progress < 1.0:
		var step := minf(remaining, maxf(0.0, interval - work.beat_elapsed))
		work.beat_elapsed += step
		remaining -= step
		if work.beat_elapsed >= interval - 0.000001:
			work.beat_elapsed = 0.0
			var rng := RandomNumberGenerator.new()
			rng.seed = abs(("%s:%d" % [id, work.check_sequence]).hash())
			work.check_sequence += 1
			if rng.randf() < risk:
				setbacks += 1
				var wear := float(settings.setback_wear) * rng.randf_range(0.75, 1.25) * (float(settings.rushed_wear) if rushed else 1.0)
				broke = bool(PICKS.apply_wear(inventory, lease.stack_id, wear).broke)
				if broke:
					break
			else:
				successes += 1
				work.progress = minf(1.0, work.progress + 1.0 / maxi(1, int(settings.successes_required)))
		if work.progress >= 1.0 - 0.000001:
			work.progress = 1.0
			break
	var complete: bool = work.progress >= 1.0 and not broke
	if complete:
		if work.door_id.is_empty():
			work.object_locked = false
		else:
			complete = _doors != null and bool(_doors.complete_lockpick(work.door_id, work.door_revision))
	if complete or broke:
		release(id, actor_id)
	var result := {"accepted": true, "complete": complete, "broke": broke,
		"setbacks": setbacks, "successes": successes, "progress": float(work.progress),
		"attempt_progress": clampf(float(work.beat_elapsed) / interval, 0.0, 1.0)}
	lock_changed.emit(id, get_state(id))
	if complete and work.door_id.is_empty():
		object_unlocked.emit(id)
	return result

func is_complete(id: String) -> bool:
	var work = _component(id)
	return work != null and work.progress >= 1.0

func relock(id: String) -> void:
	var work = _component(id)
	if work == null or not work.door_id.is_empty():
		return
	work.object_locked = true
	work.progress = 0.0
	work.beat_elapsed = 0.0
	_claims.erase(id)
	lock_changed.emit(id, get_state(id))

func _component(id: String):
	if _gecs == null or _gecs.world == null:
		return null
	var entity = _gecs.world.get_entity_by_id("lock_work:%s" % id)
	return entity.get_component(WORK) if is_instance_valid(entity) else null

func _on_world_reindexed() -> void:
	_claims.clear()
	work_reset.emit()
