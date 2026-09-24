extends RefCounted

## Jobs owns employment/grants and serializes patrols into its GECS component.
## This executor owns only live claims/movement. No facility gets a second scheduler.
const POST = preload("res://features/settlements/bridge/venues/facility_guard_post.gd")
const ACTORS_PER_FRAME := 4
const UPDATE_SECONDS := 0.25
const MAX_POST_CANDIDATES := 16

var patrols: Dictionary = {}
var dirty := false
var assignments: Dictionary = {}
var facility_employers: Dictionary = {}
var _employers_by_town: Dictionary = {}
var _actors_by_town: Dictionary = {}
var _order: Array[String] = []
var _cursor := 0
var _posts: Dictionary = {}
var _post_pools: Dictionary = {}
var _pools: Dictionary = {}
var _pool_cursors: Dictionary = {}
var _claims: Dictionary = {}
var _moves: Dictionary = {}
var _next_update: Dictionary = {}


func register_post(post: Node) -> void:
	if not is_instance_valid(post) or not post.is_inside_tree() or not post is POST:
		return
	_posts[post.get_instance_id()] = post
	_reindex_post(post)


func unregister_post(post: Node) -> void:
	var instance_id := post.get_instance_id()
	if not _posts.erase(instance_id):
		return
	_remove_from_pool(post)
	var worker: WorldActor = post.get_assigned_worker()
	if is_instance_valid(worker):
		release(worker.stable_id, worker)


func _reindex_post(post: Node) -> void:
	_remove_from_pool(post)
	var key: String = post.get_pool_key(facility_employers)
	if key.is_empty():
		return
	if not _pools.has(key):
		_pools[key] = []
	_pools[key].append(post)
	_post_pools[post.get_instance_id()] = key


func _remove_from_pool(post: Node) -> void:
	var instance_id := post.get_instance_id()
	var key := str(_post_pools.get(instance_id, ""))
	if _pools.has(key):
		(_pools[key] as Array).erase(post)
	_post_pools.erase(instance_id)


func set_settlement(settlement_id: String, state: Dictionary, population: Node) -> void:
	var owners: Dictionary = {}
	var facilities: Dictionary = state.get("facilities", {})
	var slots: Dictionary = state.get("assignment_slots", {})
	# Resolve employers from durable occupants, not live bodies (owners may be offscreen).
	for slot: Dictionary in slots.values():
		var facility_id := str(slot.get("facility_id", ""))
		var facility: Dictionary = facilities.get(facility_id, {})
		if bool(slot.get("filled", false)) and str(slot.get("role_id", "")) == str(facility.get("owner_role_id", "__none__")):
			owners[facility_id] = str(slot.get("occupant_actor_id", ""))
	if _employers_by_town.get(settlement_id, {}) != owners:
		for id: String in (_employers_by_town.get(settlement_id, {}) as Dictionary):
			facility_employers.erase(id)
		_employers_by_town[settlement_id] = owners
		facility_employers.merge(owners, true)
		for post: Node in _posts.values():
			_reindex_post(post)
	var current: Array[String] = []
	for slot: Dictionary in slots.values():
		var role_id := str(slot.get("role_id", ""))
		if str(slot.get("assignment_domain", "")) != "employment" or role_id not in ["guard", "mercenary"] or not bool(slot.get("filled", false)):
			continue
		var id := str(slot.get("occupant_actor_id", ""))
		if id.is_empty():
			continue
		var employer := str(owners.get(str(slot.get("facility_id", "")), ""))
		# Mercenaries serve their employer, never the town's public patrol pool.
		var town_guard := role_id == "guard" and str(slot.get("authority_scope", "")) == "settlement_authority"
		var pool := "town:" + settlement_id if town_guard else ("character:" + employer if not employer.is_empty() else "")
		if assignments.has(id) and assignments[id] != pool:
			release(id, _live_actor(population, id))
			patrols.erase(id)
			dirty = true
		assignments[id] = pool
		current.append(id)
		if not _order.has(id):
			_order.append(id)
	for id: String in _actors_by_town.get(settlement_id, []):
		if not current.has(id):
			release(id, _live_actor(population, id))
			assignments.erase(id)
			patrols.erase(id)
			_order.erase(id)
			_next_update.erase(id)
			dirty = true
	_actors_by_town[settlement_id] = current


func tick(jobs: Node, population: Node, minute: float, elapsed: float) -> void:
	for _index in range(mini(ACTORS_PER_FRAME, _order.size())):
		_cursor %= _order.size()
		var id := _order[_cursor]
		_cursor += 1
		if elapsed < float(_next_update.get(id, -1.0)):
			continue
		_next_update[id] = elapsed + UPDATE_SECONDS
		var actor := _live_actor(population, id)
		if not is_instance_valid(actor):
			release(id, null)
			continue
		step(actor, jobs, minute)


func step(actor: WorldActor, jobs: Node, minute: float) -> void:
	var id := actor.stable_id
	var pool := str(assignments.get(id, ""))
	if pool.is_empty() or has_priority_activity(actor) or not jobs.can_execute_assignment_duty(actor):
		release(id, actor)
		return
	var post: Node = _claims.get(id)
	if not is_instance_valid(post) or not post.is_inside_tree() or _post_pools.get(post.get_instance_id(), "") != pool or not post.is_available_for(actor):
		release(id, actor)
		post = _choose_post(pool, actor, null, str((patrols.get(id, {}) as Dictionary).get("post_id", "")))
		if post == null:
			return
		_claim(id, actor, post, minute)
	var record: Dictionary = patrols.get(id, {})
	var target: Vector3 = post.get_work_position()
	# Never repath an unchanged commute on every tick. Navigation remains the actuator.
	if not post.is_worker_at_post(actor):
		if not actor.has_move_target() or not actor.get_move_target().is_equal_approx(target):
			_moves[id] = target
			actor.set_move_target(target, false)
		return
	_clear_move(id, actor)
	var facing: Vector3 = post.get_facing_direction()
	actor.look_at(actor.global_position + facing, Vector3.UP)
	if float(record.get("leave_minute", -1.0)) < 0.0:
		record["leave_minute"] = minute + post.hold_minutes
		patrols[id] = record
		dirty = true
	elif minute >= float(record.leave_minute):
		var next := _choose_post(pool, actor, post)
		if next != null:
			post.release_worker(actor)
			_claim(id, actor, next, minute)
		else:
			# A full pool holds safely, rather than crowding an occupied marker.
			record["leave_minute"] = minute + post.hold_minutes
			dirty = true


func _claim(id: String, actor: WorldActor, post: Node, _minute: float) -> void:
	post.claim_worker(actor)
	_claims[id] = post
	var previous: Dictionary = patrols.get(id, {})
	if str(previous.get("post_id", "")) != post.get_post_id():
		patrols[id] = {"post_id": post.get_post_id(), "leave_minute": -1.0}
		dirty = true


func _choose_post(pool: String, actor: WorldActor, exclude: Node, preferred := "") -> Node:
	var posts: Array = _pools.get(pool, [])
	if posts.is_empty():
		return null
	# Bounded discovery even when a town has hundreds of occupied spots.
	var start := int(_pool_cursors.get(pool, 0)) % posts.size()
	var fallback: Node
	for offset in range(mini(MAX_POST_CANDIDATES, posts.size())):
		var index := (start + offset) % posts.size()
		var post: Node = posts[index]
		_pool_cursors[pool] = index + 1
		if not is_instance_valid(post) or post == exclude or not post.is_available_for(actor):
			continue
		if preferred.is_empty() or post.get_post_id() == preferred:
			return post
		if fallback == null:
			fallback = post
	return fallback


func find_available_post(pool: String, actor: WorldActor, exclude: Node = null) -> Node:
	return _choose_post(pool, actor, exclude)


func release(id: String, actor: WorldActor) -> void:
	var post: Node = _claims.get(id)
	_claims.erase(id)
	if is_instance_valid(post):
		var worker: WorldActor = post.get_assigned_worker()
		if is_instance_valid(worker) and (worker == actor or worker.stable_id == id):
			post.release_worker(worker)
	if is_instance_valid(actor):
		_clear_move(id, actor)
	else:
		_moves.erase(id)


func _clear_move(id: String, actor: WorldActor) -> void:
	var target: Variant = _moves.get(id)
	_moves.erase(id)
	if target is Vector3 and not has_priority_activity(actor) and actor.has_move_target() and actor.get_move_target().is_equal_approx(target):
		actor._clear_actor_move_target()
		actor.velocity = Vector3.ZERO


static func has_priority_activity(actor: WorldActor) -> bool:
	if actor.life_state != NpcRules.LifeState.ALIVE or actor.is_in_combat() or actor.has_active_player_order():
		return true
	if actor.has_method("is_carrying_someone") and actor.call("is_carrying_someone"):
		return true
	var interaction = actor.get_interaction()
	return interaction != null and (interaction.is_law_custody_returning() or interaction.is_law_sentence_moving() or interaction.current_order_type == InteractionCapability.ORDER_TYPE_PLACE_IN_CELL)


func _live_actor(population: Node, id: String) -> WorldActor:
	if population == null:
		return null
	var actor = population.call("get_live_actor", id)
	return actor as WorldActor if is_instance_valid(actor) else null


func restore(state: Dictionary, population: Node) -> void:
	for id: String in _claims.keys():
		release(id, _live_actor(population, id))
	patrols = state.duplicate(true)
	_next_update.clear()
	dirty = false
