extends "res://tests/validation/test_case.gd"

## Run through test_host.tscn, NOT --script (the real GECS autoload must exist).
## Production bootstrap/baker/PartyMember bodies; no manual system stepping,
## steering, slot injection, attack-speed overrides, or healing during combat.
## High authored max_hp keeps unarmed actors alive without changing attack timing.
## This is a movement/obstruction proof, not a deterministic damage-roll test.
const NAV_FIXTURE := "res://tests/validation/helpers/navigation_fixture.gd"
const WELL_SCENE := "res://features/world/projection/props/water/well_1.tscn"
const HEALTH_RESERVE := 100000.0
const CONTACT_EPSILON := 0.04 # meters; tolerate physical contact, not penetration.
const SETTLE_SECONDS := 1.0
const TOTAL_TIMEOUT_SECONDS := 360.0

var _world: Node3D
var _gecs: GecsWorldController
var _floor: StaticBody3D
var _well: StaticBody3D
var _wall: StaticBody3D
var _actors: Array[WorldActor] = []
var _attackers: Array[WorldActor] = []
var _target: WorldActor
var _previous: Dictionary = {}
var _impacts: Array[Dictionary] = []
var _failures: Array[String] = []
var _case := "setup"
var _completed: Array[String] = []
var _started_ms := 0
var _trace_ms := 0
var _finishing := false
var _fixture_error := false

func _initialize() -> void:
	_started_ms = Time.get_ticks_msec()
	_run.call_deferred()

func _process(_delta: float) -> void:
	if _started_ms > 0 and not _finishing and Time.get_ticks_msec() - _started_ms > int(TOTAL_TIMEOUT_SECONDS * 1000.0):
		print("COMBAT_NAV_RUNTIME_TIMEOUT " + JSON.stringify({"case": _case, "actors": _snapshots()}))
		quit(1)

func _run() -> void:
	_world = load(NAV_FIXTURE).new()
	_world.name = "CombatNavigationRuntime"
	root.add_child(_world)
	current_scene = _world
	_floor = _world.add_floor()
	_well = load(WELL_SCENE).instantiate()
	_well.position = Vector3(6, 0, 0)
	_world.add_child(_well)
	# A bounded wall detour complements the exact production well. A real door
	# and stairs are deliberately left to their existing dedicated validators.
	_wall = _world.add_floor(Vector3(8, 3, 0.5), Vector3(-6, 1.5, 10))
	_wall.name = "SolidWall"
	_wall.get_child(0).name = "CollisionShape3D"
	if not await _world.boot():
		await _setup_failed("Shared navigation bootstrap/bake did not become ready")
		return
	_gecs = BootstrapContext.service(GecsWorldController.SERVICE_ID) as GecsWorldController
	if _gecs == null:
		await _setup_failed("Normal bootstrap did not provide GECS")
		return
	var resolution := _gecs.find_child("GameCombatResolutionSystem", true, false)
	if resolution == null or not resolution.has_signal("impact_resolved"):
		await _setup_failed("Normal GECS resolution system is unavailable")
		return
	resolution.connect("impact_resolved", _on_impact)
	# Prove fixture connectivity separately: missing preparation is not a
	# behavioral RED. Physics/footprint checks below still reject stale routes.
	for route in [[Vector3(-7, 0, -10), Vector3(0, 0, -10)], [Vector3(2, 0, 0), Vector3(10, 0, 0)], [Vector3(-6, 0, 7), Vector3(-6, 0, 13)]]:
		if not await _world.wait_until(func() -> bool: return _world.path_reaches(route[0], route[1]), 5.0):
			var map := _world.get_world_3d().navigation_map
			print("COMBAT_NAV_FIXTURE_PATH ", NavigationServer3D.map_get_path(map, route[0], route[1], true), " regions=", NavigationServer3D.map_get_regions(map), " closest=", NavigationServer3D.map_get_closest_point(map, route[1]))
			await _setup_failed("No connected fixture route: %s -> %s" % [route[0], route[1]])
			return
	print("COMBAT_NAV_RUNTIME_READY " + JSON.stringify({"well": WELL_SCENE, "health": HEALTH_RESERVE, "timing": "unchanged", "navigation_iteration": NavigationServer3D.map_get_iteration_id(_world.get_world_3d().navigation_map)}))
	var selected := OS.get_environment("COMBAT_NAV_CASE")
	if selected.is_empty() or selected == "aligned_2v1":
		await _open_spacing()
	if not _fixture_error and (selected.is_empty() or selected == "well_pursuit"):
		await _pursuit("well_pursuit", Vector3(2, 0, 0), Vector3.LEFT, Vector3(10, 0, 0), _well, 0)
	if not _fixture_error and (selected.is_empty() or selected == "wall_pursuit"):
		await _pursuit("wall_pursuit", Vector3(-6, 0, 7), Vector3.FORWARD, Vector3(-6, 0, 13), _wall, 2)
	if not _fixture_error and (selected.is_empty() or selected == "five_attackers_three_slots"):
		await _five_attackers()
	if not _fixture_error and (selected.is_empty() or selected == "mutual_reposition"):
		await _mutual_reposition()
	await _finish()

func _spawn_case(label: String, center: Vector3, approach: Vector3, count: int) -> bool:
	await _release_actors()
	_case = label
	_impacts.clear()
	print("COMBAT_NAV_RUNTIME_CASE_BEGIN " + label)
	_target = _spawn("defender", center, false)
	_target.combat_active_attack_slots = 3
	for index in range(count):
		_attackers.append(_spawn("attacker_%d" % index, center + approach * (3.5 + float(index) * 1.5), true))
	var ready: bool = await _world.wait_until(func() -> bool:
		for actor in _actors:
			if not actor.is_on_floor() or _gecs.get_actor_entity(actor) == null:
				return false
			var vitals = _component(actor, CGameActorVitals)
			if vitals == null or vitals.max_hp < HEALTH_RESERVE:
				return false
		return true
	, 5.0)
	if not ready:
		_fixture_error = true
		_fail("FIXTURE_ERROR: actors did not ground/register with authored health")
		return false
	for actor in _actors:
		_previous[actor.stable_id] = actor.global_position
	return true

func _spawn(suffix: String, floor_point: Vector3, player: bool) -> WorldActor:
	var actor: WorldActor = _world.add_actor("combat.nav.%s.%s" % [_case, suffix], floor_point + Vector3.UP, player)
	actor.max_hp = HEALTH_RESERVE
	actor.hp = HEALTH_RESERVE
	actor.faction_name = "NavigationAttackers" if player else "NavigationDefender"
	actor.hostile_factions = PackedStringArray()
	# PASSIVE prevents uncommanded acquisition, not the production exact attack
	# command or incoming exchange response. The defender has no locomotion order
	# until pursuit begins; it remains a normal colliding, attackable body.
	actor.set_combat_stance(NpcRules.CombatStance.PASSIVE)
	actor.global_position = actor.get_floor_aligned_origin_position(floor_point)
	_actors.append(actor)
	return actor

func _command_attack(actors: Array[WorldActor]) -> void:
	for actor in actors:
		_expect(actor.assign_attack_target(_target), "public attack accepted: " + actor.stable_id)

func _open_spacing() -> void:
	if not await _spawn_case("aligned_2v1", Vector3(0, 0, -10), Vector3.LEFT, 2):
		return
	var before := _failures.size()
	var defender_start := _target.global_position
	var rear_start := _attackers[1].global_position
	_command_attack(_attackers)
	_expect(await _stable(func() -> bool: return _engaged(_attackers) and _clear_bodies(), 24.0), "both aligned attackers must physically settle in separate reachable fighting positions")
	_expect(_flat(_attackers[1].global_position, rear_start) > 2.0, "rear attacker must actually approach")
	_expect(absf(_attackers[1].global_position.z - defender_start.z) >= _radius(_attackers[1]), "rear attacker develops an open side rather than queues behind the front")
	_expect(_flat(_target.global_position, defender_start) <= 0.35, "stationary defender must not be used to manufacture fan-out")
	_expect(await _stable(func() -> bool: return _each_resolved(_attackers, 0), 12.0, 0.0), "each attacker reaches a real attributed resolution at native attack timing (misses allowed)")
	await _free_target_and_check()
	_end_case(before)

func _pursuit(label: String, center: Vector3, approach: Vector3, goal: Vector3, blocker: StaticBody3D, axis: int) -> void:
	if not await _spawn_case(label, center, approach, 2):
		return
	var before := _failures.size()
	_command_attack(_attackers)
	var initial := await _stable(func() -> bool: return _engaged(_attackers) and _clear_bodies() and _each_resolved(_attackers, 0), 24.0)
	_expect(initial, "both pursuers must first fight at the original location")
	if initial:
		var starts: Dictionary = {}
		for actor in _attackers:
			starts[actor.stable_id] = actor.global_position
		var destination := _target.get_floor_aligned_origin_position(goal)
		_target.set_move_target(destination, true)
		_expect(_target.has_active_player_order(), "defender receives an actual replacing public movement order")
		var crossed: Dictionary = {}
		var reached := await _stable(func() -> bool:
			for actor in _attackers:
				if actor.global_position[axis] > blocker.global_position[axis] + 0.3:
					crossed[actor.stable_id] = true
			return not _target.has_move_target() and _flat(_target.global_position, destination) <= _target.navigation_target_desired_distance + 0.05 and _engaged(_attackers) and _clear_bodies()
		, 30.0)
		_expect(reached, "defender and BOTH pursuers must finish around the solid obstacle, not stall at its edge")
		for actor in _attackers:
			_expect(crossed.has(actor.stable_id) and _flat(actor.global_position, starts[actor.stable_id]) > 3.0, "each pursuer physically crosses to the far side: " + actor.stable_id)
		var impact_cursor := _impacts.size()
		_expect(await _stable(func() -> bool: return _each_resolved(_attackers, impact_cursor), 12.0, 0.0), "both pursuers resume actual attributed resolution after the target moves")
	await _free_target_and_check()
	_end_case(before)

func _five_attackers() -> void:
	# Stage three legitimate occupants before adding two contenders, so the
	# named fifth actor is deterministically a waiter rather than racing a slot.
	if not await _spawn_case("five_attackers_three_slots", Vector3(0, 0, -10), Vector3.LEFT, 3):
		return
	var before := _failures.size()
	_command_attack(_attackers)
	var first_three: Array[WorldActor] = _attackers.duplicate()
	_expect(await _stable(func() -> bool: return _engaged(first_three) and _clear_bodies(), 24.0), "three original attackers occupy the configured three slots")
	var waiters: Array[WorldActor] = []
	for index in range(2):
		var actor := _spawn("late_attacker_%d" % index, Vector3(-7 - index * 1.5, 0, -10), true)
		_attackers.append(actor)
		waiters.append(actor)
	_expect(await _world.wait_until(func() -> bool: return _gecs.get_actor_entity(waiters[0]) != null and _gecs.get_actor_entity(waiters[1]) != null and waiters[0].is_on_floor() and waiters[1].is_on_floor(), 4.0), "late attackers ground and register normally")
	_command_attack(waiters)
	_expect(await _stable(func() -> bool:
		if not _engaged(first_three) or not _clear_bodies():
			return false
		for actor in waiters:
			var slot = _component(actor, CGameCombatSlotState)
			var action = _component(actor, CGameCombatAction)
			if slot == null or action == null or slot.slot_state != CGameCombatSlotState.FightState.WAITING or slot.slot_index >= 0 or not slot.position_valid:
				return false
			if _flat(actor.global_position, slot.wait_position) > 0.35 or _flat(actor.global_position, _target.global_position) <= actor.get_attack_range() + 0.3 or action.action_sequence != 0:
				return false
		return true
	, 24.0, 2.0), "fourth and fifth attackers physically wait outside fighting range, without overlap or attacks")
	await _free_target_and_check()
	_end_case(before)

func _mutual_reposition() -> void:
	var before := _failures.size()
	# Force an ordinary flank with live nearby bodies, then release those
	# bodies as after a crowd disperses. Never inject slot/cursor/steering state.
	# Prior code kept rotating both destinations: ~11 laps, no impacts in 18s.
	for bearing in [0.0, PI / 2.0]:
		var direction := Vector3(cos(bearing), 0.0, sin(bearing))
		var center := Vector3(0, 0, -10)
		# Unique durable identities keep the rotated trial a fresh encounter,
		# rather than realizing the first trial's wounds/actions/reservations.
		var label := "mutual_reposition_x" if bearing == 0.0 else "mutual_reposition_z"
		if not await _spawn_case(label, center + direction * 2.0, -direction, 1):
			return
		var a: WorldActor = _attackers[0]
		var b: WorldActor = _target
		var blockers: Array[WorldActor] = [
			_spawn("front_a", center + direction, false),
			_spawn("front_b", center - direction * 0.5, false),
		]
		_expect(await _world.wait_until(func() -> bool:
			return _gecs.get_actor_entity(blockers[0]) != null and _gecs.get_actor_entity(blockers[1]) != null and blockers[0].is_on_floor() and blockers[1].is_on_floor()
		, 4.0), "flank blockers ground/register")
		_expect(a.assign_attack_target(b) and b.assign_attack_target(a), "both duelists receive real attack commands")
		_expect(await _world.wait_until(func() -> bool:
			return _component(a, CGameCombatSlotState).position_valid and _component(b, CGameCombatSlotState).position_valid
		, 4.0), "both duelists reserve initial approaches")
		for actor in [a, b]:
			var slot = _component(actor, CGameCombatSlotState)
			_expect(absf(slot.pair_axis.dot(direction)) < 0.9, "nearby bodies must genuinely force an initial flank")
		for blocker in blockers:
			_actors.erase(blocker)
			blocker.queue_free()
		await process_frame
		var previous_angle := atan2(a.global_position.z - b.global_position.z, a.global_position.x - b.global_position.x)
		var angular_travel := 0.0
		var settled_since := -1
		var settled := false
		var deadline := Time.get_ticks_msec() + 18000
		while Time.get_ticks_msec() < deadline:
			await physics_frame
			_observe()
			var angle := atan2(a.global_position.z - b.global_position.z, a.global_position.x - b.global_position.x)
			angular_travel += absf(wrapf(angle - previous_angle, -PI, PI))
			previous_angle = angle
			if _clear_bodies() and Vector2(a.velocity.x, a.velocity.z).length() < 0.15 and Vector2(b.velocity.x, b.velocity.z).length() < 0.15:
				if settled_since < 0:
					settled_since = Time.get_ticks_msec()
				settled = settled or Time.get_ticks_msec() - settled_since >= 1000
			else:
				settled_since = -1
		var resolved_a := false
		var resolved_b := false
		for impact in _impacts:
			resolved_a = resolved_a or (impact.attacker == a.stable_id and impact.target == b.stable_id)
			resolved_b = resolved_b or (impact.attacker == b.stable_id and impact.target == a.stable_id)
		_expect(angular_travel < TAU * 1.5, "mutual repositioning may briefly circle, not repeat tight laps")
		_expect(settled and _clear_bodies(), "duel must settle without overlapping")
		_expect(resolved_a and resolved_b, "both duelists must resolve attacks at unchanged native timing")
		print("COMBAT_NAV_MUTUAL_REPOSITION " + JSON.stringify({"bearing": bearing, "angular_turns": angular_travel / TAU, "settled": settled, "both_resolved": resolved_a and resolved_b}))
	_case = "mutual_reposition"
	_end_case(before)


func _engaged(actors: Array[WorldActor]) -> bool:
	if not is_instance_valid(_target):
		return false
	for actor in actors:
		var slot = _component(actor, CGameCombatSlotState)
		var state = _component(actor, CGameCombatState)
		if slot == null or state == null or state.system_target_actor_id != _target.stable_id or slot.slot_target_actor_id != _target.stable_id:
			return false
		if slot.slot_state != CGameCombatSlotState.FightState.FIGHTING or not slot.position_valid or _flat(actor.global_position, slot.slot_position) > 0.35:
			return false
		# Independent body/range/obstruction oracle, not can_strike() calling itself.
		if _flat(actor.global_position, _target.global_position) > actor.get_attack_range() + 0.18 or absf(actor.global_position.y - _target.global_position.y) > 0.3:
			return false
		var query := PhysicsRayQueryParameters3D.create(_shape(actor).global_position, _shape(_target).global_position, 1 | 4 | 8)
		query.exclude = [actor.get_rid(), _target.get_rid(), _floor.get_rid()]
		query.hit_from_inside = true
		if not _world.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			return false
	return true

func _clear_bodies() -> bool:
	# Initial crowd bumps are allowed. This is required only for the sustained
	# settled window, never used as a pair-distance assertion every approach frame.
	for i in range(_actors.size()):
		for j in range(i + 1, _actors.size()):
			if _flat(_actors[i].global_position, _actors[j].global_position) < _radius(_actors[i]) + _radius(_actors[j]) - CONTACT_EPSILON:
				return false
	return true

func _stable(predicate: Callable, seconds: float, hold := SETTLE_SECONDS) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	var since := -1
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		_observe()
		if predicate.call():
			if since < 0:
				since = Time.get_ticks_msec()
			if Time.get_ticks_msec() - since >= int(hold * 1000.0):
				return true
		else:
			since = -1
	print("COMBAT_NAV_RUNTIME_DEADLINE " + JSON.stringify({"case": _case, "actors": _snapshots()}))
	return false

func _observe() -> void:
	for actor in _actors:
		if not is_instance_valid(actor):
			continue
		_expect(actor.life_state == NpcRules.LifeState.ALIVE, "fixture actor must remain alive: " + actor.stable_id)
		var shape := _shape(actor)
		var query := PhysicsShapeQueryParameters3D.new()
		# Contact margins can report touching bodies as overlapping. Apply the
		# same small tolerance to both endpoint and swept-body assertions.
		var sweep_shape := shape.shape.duplicate() as CapsuleShape3D
		sweep_shape.radius = maxf(sweep_shape.radius - CONTACT_EPSILON, 0.01)
		sweep_shape.height = maxf(sweep_shape.height - 2.0 * CONTACT_EPSILON, 2.0 * sweep_shape.radius)
		query.shape = sweep_shape
		query.transform = shape.global_transform
		query.collision_mask = 1 | 4 | 8
		query.exclude = [actor.get_rid(), _floor.get_rid()]
		for hit in _world.get_world_3d().direct_space_state.intersect_shape(query, 32):
			_expect(hit.collider != _well and hit.collider != _wall, "physical body overlaps solid obstacle: " + actor.stable_id)
		var old: Vector3 = _previous.get(actor.stable_id, actor.global_position)
		query.transform.origin += old - actor.global_position
		query.motion = actor.global_position - old
		var excluded: Array[RID] = [_floor.get_rid()]
		for other in _actors:
			excluded.append(other.get_rid())
		query.exclude = excluded
		var fractions := _world.get_world_3d().direct_space_state.cast_motion(query)
		_expect(fractions.size() == 2 and fractions[0] >= 1.0, "swept physical capsule must not pass through a blocker: " + actor.stable_id)
		# Segment tests also catch transform teleporting completely through a
		# collider between samples. Use the exact well's authored cylindrical rim.
		var a := Vector2(old.x - _well.global_position.x, old.z - _well.global_position.z)
		var b := Vector2(actor.global_position.x - _well.global_position.x, actor.global_position.z - _well.global_position.z)
		var closest := Geometry2D.get_closest_point_to_segment(Vector2.ZERO, a, b)
		var rim := _well.get_node("CollisionShape3D").shape as CylinderShape3D
		_expect(closest.length() >= rim.radius + _radius(actor) - CONTACT_EPSILON, "swept body must not cross well footprint: " + actor.stable_id)
		var wall_shape := _wall.get_node("CollisionShape3D").shape as BoxShape3D
		var half := wall_shape.size * 0.5
		# Center sweep through the wall's actual footprint (capsule overlap is
		# checked above); no inflated square-corner approximation of the capsule.
		var bounds := AABB(_wall.global_position - half, wall_shape.size)
		var from := Vector3(old.x, _wall.global_position.y, old.z)
		var to := Vector3(actor.global_position.x, _wall.global_position.y, actor.global_position.z)
		_expect(bounds.intersects_segment(from, to) == null, "swept body must not cross wall footprint: " + actor.stable_id)
		_previous[actor.stable_id] = actor.global_position
	if is_instance_valid(_target):
		var reservations := 0
		for actor in _attackers:
			var slot = _component(actor, CGameCombatSlotState)
			if slot != null and slot.position_valid and slot.slot_index >= 0 and slot.slot_target_actor_id == _target.stable_id:
				reservations += 1
		_expect(reservations <= _target.combat_active_attack_slots, "active reservations must never exceed the defender's authored slot cap")
	if Time.get_ticks_msec() >= _trace_ms:
		_trace_ms = Time.get_ticks_msec() + 1000
		print("COMBAT_NAV_RUNTIME_TRACE " + JSON.stringify({"case": _case, "actors": _snapshots()}))

func _on_impact(attacker_id: String, target_id: String, sequence: int, outcome: String, damage: float) -> void:
	_impacts.append({"attacker": attacker_id, "target": target_id, "sequence": sequence, "outcome": outcome, "damage": damage, "ms": Time.get_ticks_msec()})

func _each_resolved(actors: Array[WorldActor], from_index: int) -> bool:
	for actor in actors:
		var seen := false
		for index in range(from_index, _impacts.size()):
			var impact := _impacts[index]
			if impact.attacker == actor.stable_id and impact.target == _target.stable_id:
				seen = true
		if not seen:
			return false
	return true

func _free_target_and_check() -> void:
	var id := _target.stable_id
	var weak: WeakRef = weakref(_target)
	_actors.erase(_target)
	_target.queue_free()
	_target = null
	_expect(await _stable(func() -> bool:
		if weak.get_ref() != null:
			return false
		for actor in _attackers:
			var state = _component(actor, CGameCombatState)
			var slot = _component(actor, CGameCombatSlotState)
			var action = _component(actor, CGameCombatAction)
			var movement = _component(actor, CGameMovementState)
			if state == null or slot == null or action == null or movement == null:
				return false
			if state.commanded_target_actor_id == id or state.system_target_actor_id == id or state.current_target_actor_id == id or slot.slot_target_actor_id == id or action.action_active or movement.system_movement_active:
				return false
			if Vector2(actor.velocity.x, actor.velocity.z).length() > 0.15:
				return false
		return true
	, 5.0), "freed target releases exact intent, slot, action and physical movement without stale references")

func _component(actor: WorldActor, script: Script):
	var entity = _gecs.get_actor_entity(actor)
	return entity.get_component(script) if entity != null else null

func _shape(actor: WorldActor) -> CollisionShape3D:
	return actor.get_node("CollisionShape3D") as CollisionShape3D

func _radius(actor: WorldActor) -> float:
	var shape := _shape(actor)
	var capsule := shape.shape as CapsuleShape3D
	return capsule.radius * maxf(shape.global_basis.get_scale().x, shape.global_basis.get_scale().z)

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _snapshots() -> Array:
	var result: Array = []
	for actor in _actors:
		if not is_instance_valid(actor):
			continue
		var slot = _component(actor, CGameCombatSlotState) if _gecs != null else null
		var state = _component(actor, CGameCombatState) if _gecs != null else null
		var action = _component(actor, CGameCombatAction) if _gecs != null else null
		result.append({"id": actor.stable_id, "position": actor.global_position, "velocity": actor.velocity, "life": actor.life_state, "target": state.system_target_actor_id if state != null else "", "slot_state": slot.slot_state if slot != null else -1, "position_valid": slot.position_valid if slot != null else false, "destination": slot.slot_position if slot != null else Vector3.ZERO, "action_sequence": action.action_sequence if action != null else -1})
	return result

func _expect(ok: bool, message: String) -> void:
	if not ok:
		_fail(message)

func _fail(message: String) -> void:
	var qualified := _case + ": " + message
	if not _failures.has(qualified):
		_failures.append(qualified)
		print("COMBAT_NAV_RUNTIME_ASSERTION_FAILED " + qualified)

func _end_case(before: int) -> void:
	_completed.append(_case)
	print("COMBAT_NAV_RUNTIME_CASE_END " + JSON.stringify({"case": _case, "ok": _failures.size() == before, "impacts": _impacts}))

func _release_actors() -> void:
	for actor in _actors:
		if is_instance_valid(actor):
			actor.queue_free()
	_actors.clear()
	_attackers.clear()
	_target = null
	_previous.clear()
	await process_frame
	await process_frame

func _setup_failed(message: String) -> void:
	_fixture_error = true
	_fail("FIXTURE_ERROR: " + message)
	await _finish()

func _finish() -> void:
	_finishing = true
	await _release_actors()
	if is_instance_valid(_world):
		_world.dispose()
		await process_frame
	if not _fixture_error:
		_expect(_completed.size() == (5 if OS.get_environment("COMBAT_NAV_CASE").is_empty() else 1), "all selected runtime scenarios completed")
	var status := "FIXTURE_ERROR" if _fixture_error else ("OK" if _failures.is_empty() else "FAILED")
	print("COMBAT_NAV_RUNTIME_" + status + " " + JSON.stringify({"cases": _completed, "failures": _failures}))
	quit(2 if _fixture_error else (0 if _failures.is_empty() else 1))
