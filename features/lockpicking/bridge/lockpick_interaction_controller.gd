extends Node

const SERVICE_ID := &"lockpick_interactions"
const PICKS := preload("res://features/lockpicking/sim/lockpick_rules.gd")

var _context: BootstrapContext
var _locks: Node
var _sessions := {}
var _targets := {}

func initialize(context: BootstrapContext) -> void:
	_context = context
	_locks = context.require(&"lockpicking")
	_locks.lock_changed.connect(_on_lock_changed)
	_locks.work_reset.connect(_on_work_reset)
	set_physics_process(false)
	for target in get_tree().get_nodes_in_group("lockpick_target"):
		register_target(target)

func register_target(target: Node) -> Dictionary:
	if not is_instance_valid(target) or not target.has_method("get_lockpick_record"):
		return {}
	var record: Dictionary = target.get_lockpick_record()
	var state: Dictionary = _locks.register_lock(record)
	if not state.is_empty():
		_targets[str(state.lock_id)] = weakref(target)
		if target.has_method("apply_lockpick_state"):
			target.apply_lockpick_state(state)
	return state

## Resolve only a currently realized projection, never retain it across frames.
func get_registered_target(lock_id: String) -> Node3D:
	var reference = _targets.get(lock_id)
	var target = reference.get_ref() if reference is WeakRef else null
	if not is_instance_valid(target) or target.is_queued_for_deletion() or not target.is_inside_tree():
		return null
	return target as Node3D

func can_pick(target: Node, actor: Node) -> bool:
	if not actor is WorldActor or not _actor_available(actor):
		return false
	var state := register_target(target)
	return not state.is_empty() and bool(state.is_locked) \
		and actor.get_skill_level(SkillRules.SUBTERFUGE_LOCKPICKING) >= float(state.minimum_skill) \
		and PICKS.find_pick(actor.inventory) != null

func request_pick(actor: WorldActor, target: Node3D, mode := "careful") -> bool:
	if not can_pick(target, actor) or actor.stable_id.is_empty():
		return false
	var interaction := actor.get_interaction()
	if interaction == null:
		return false
	var route := _approach_route(target, actor)
	if route.is_empty():
		return false
	cancel_actor(actor.stable_id)
	var state := register_target(target)
	var claim: Dictionary = _locks.claim(str(state.lock_id), actor.stable_id, actor.inventory, mode)
	if not claim.accepted:
		return false
	interaction._set_order(InteractionCapability.ORDER_TYPE_PICK_LOCK, true)
	var callback := _on_order_changed.bind(actor.stable_id)
	interaction.order_changed.connect(callback)
	_sessions[actor.stable_id] = {"actor": weakref(actor), "target": weakref(target),
		"lock_id": str(state.lock_id), "stack_id": str(claim.stack_id), "mode": mode,
		"route": route, "working": false, "elapsed": 0.0, "reported": false,
		"witness_check_remaining": 0.0,
		"order_callback": callback}
	actor._set_actor_move_target(route[0], false, float(_locks.settings.approach_tolerance) * 0.8)
	set_physics_process(true)
	return true

func cancel_actor(actor_id: String, message := "") -> void:
	var session: Dictionary = _sessions.get(actor_id, {})
	if session.is_empty():
		return
	_sessions.erase(actor_id)
	_locks.release(str(session.lock_id), actor_id)
	var actor = session.actor.get_ref()
	if is_instance_valid(actor) and not actor.is_queued_for_deletion():
		var interaction = actor.get_interaction()
		if interaction != null:
			if interaction.order_changed.is_connected(session.order_callback):
				interaction.order_changed.disconnect(session.order_callback)
			if interaction.current_order_type == InteractionCapability.ORDER_TYPE_PICK_LOCK:
				actor.stop_movement()
				interaction._set_order(InteractionCapability.ORDER_TYPE_NONE, false)
		if actor.has_method("set_lockpick_work_visual"):
			actor.set_lockpick_work_visual(false, Vector3.ZERO, 0.0, null)
		if not message.is_empty():
			actor.show_world_speech(message, 2.0)
	set_physics_process(not _sessions.is_empty())

func _physics_process(delta: float) -> void:
	for actor_id in _sessions.keys():
		_tick(str(actor_id), delta)

func _tick(actor_id: String, delta: float) -> void:
	var session: Dictionary = _sessions.get(actor_id, {})
	if session.is_empty():
		return
	var actor = session.actor.get_ref() as WorldActor
	var target = session.target.get_ref() as Node3D
	if not _actor_available(actor) or not is_instance_valid(target) or target.is_queued_for_deletion() or not target.is_inside_tree():
		cancel_actor(actor_id)
		return
	if actor.get_interaction().current_order_type != InteractionCapability.ORDER_TYPE_PICK_LOCK:
		cancel_actor(actor_id)
		return
	var pick = PICKS.find_pick(actor.inventory, str(session.stack_id))
	if pick == null:
		cancel_actor(actor_id, "No usable lockpick.")
		return
	var route: Array = session.route
	var destination: Vector3 = route[0]
	var flat_distance := Vector2(actor.global_position.x - destination.x, actor.global_position.z - destination.z).length()
	var close: bool = flat_distance <= float(_locks.settings.approach_tolerance) and absf(actor.global_position.y - destination.y) <= actor.move_target_vertical_tolerance
	if not session.working:
		session.elapsed += delta
		if session.elapsed > float(_locks.settings.approach_timeout_seconds):
			cancel_actor(actor_id, "Cannot reach the lock.")
			return
		if not close:
			return
		if route.size() > 1:
			route.pop_front()
			actor._set_actor_move_target(route[0], false, float(_locks.settings.approach_tolerance) * 0.8)
			return
		actor._clear_actor_move_target()
		actor.velocity = Vector3.ZERO
		session.working = true
	elif not close:
		cancel_actor(actor_id)
		return
	var contact: Vector3 = target.get_lockpick_contact(actor)
	actor._face_world_position(contact)
	if not session.reported:
		session.witness_check_remaining -= delta
		if session.witness_check_remaining <= 0.0:
			session.witness_check_remaining = maxf(0.05, float(_locks.settings.witness_check_interval_seconds))
			_report_attempt(actor, target, session)
			# Law callbacks can interrupt work synchronously. Never revive its pose
			# or advance a cancelled claim after another order takes ownership.
			if _sessions.get(actor_id, {}) != session:
				return
			if not _actor_available(actor) or not is_instance_valid(target) or target.is_queued_for_deletion():
				cancel_actor(actor_id)
				return
	var result: Dictionary = _locks.advance(str(session.lock_id), actor_id, actor.inventory,
		actor.get_skill_level(SkillRules.SUBTERFUGE_LOCKPICKING), actor.get_skill_level(SkillRules.ATTRIBUTE_DEXTERITY), delta)
	if not result.accepted:
		cancel_actor(actor_id)
		return
	if result.setbacks > 0:
		if not result.broke:
			actor.show_world_speech("The pick slips.", 1.5)
	if result.broke:
		cancel_actor(actor_id, "Lockpick broke.")
		return
	if result.complete:
		actor.add_skill_xp(SkillRules.SUBTERFUGE_LOCKPICKING, SkillRules.get_chance_check_xp(0.5, true), "lockpicking")
		if target.has_method("on_lockpick_completed"):
			target.on_lockpick_completed(actor)
		cancel_actor(actor_id, "Unlocked.")
		return
	if actor.has_method("set_lockpick_work_visual"):
		actor.set_lockpick_work_visual(true, contact, float(result.progress), pick.definition, float(result.attempt_progress))

func _approach_route(target: Node3D, actor: WorldActor) -> Array[Vector3]:
	var route: Array[Vector3] = []
	if target.has_method("get_interaction_route"):
		for point in target.get_interaction_route(actor):
			if point is Vector3 and point.is_finite():
				route.append(point)
	var final: Vector3 = target.get_lockpick_position(actor)
	if not final.is_finite():
		return []
	if not route.is_empty():
		route.pop_back()
	route.append(final)
	return route

func _actor_available(actor: WorldActor) -> bool:
	return is_instance_valid(actor) and not actor.is_queued_for_deletion() and actor.is_inside_tree() \
		and actor.life_state == NpcRules.LifeState.ALIVE and not actor.is_in_cell_custody() \
		and not actor.is_in_combat() and actor.get_carry().get_carrier() == null \
		and not actor.get_carry().is_carrying_someone()

func _report_attempt(actor: WorldActor, target: Node, session: Dictionary) -> void:
	if session.reported:
		return
	var law := _context.get_optional(&"law_order")
	if law != null and actor is HumanoidCharacter:
		var report: Dictionary = law.report_lockpicking_if_witnessed(actor, target)
		session.reported = not report.is_empty()

func _on_order_changed(_order: int, _player: bool, actor_id: String) -> void:
	cancel_actor(actor_id)

func _on_lock_changed(id: String, state: Dictionary) -> void:
	var reference = _targets.get(id)
	var target = reference.get_ref() if reference is WeakRef else null
	if is_instance_valid(target) and target.has_method("apply_lockpick_state"):
		target.apply_lockpick_state(state)

func _on_work_reset() -> void:
	for actor_id in _sessions.keys():
		cancel_actor(str(actor_id))
	for id in _targets:
		_on_lock_changed(str(id), _locks.get_state(str(id)))

func _exit_tree() -> void:
	if is_instance_valid(_locks):
		for actor_id in _sessions.keys():
			cancel_actor(str(actor_id))
