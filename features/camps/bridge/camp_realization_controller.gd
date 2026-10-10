extends Node

const SERVICE_ID := &"camp_realization"
const RULES := preload("res://features/camps/sim/camp_rules.gd")
const ROUTINE_STEP := preload("res://features/camps/bridge/camp_routine_step.gd")
const MAX_SPAWNS_PER_TICK := 4

var _context: BootstrapContext
var _gecs: Node
var _population: Node
var _realizer: Node
var _lod: Node
var _furniture: Dictionary = {}
var _actors: Dictionary = {}
var _spawn_budget := 0
var _restore_pending := false
var _squad_targets: Dictionary = {}

func initialize(context: BootstrapContext) -> void:
	_context = context
	_gecs = context.require(&"gecs_world")
	_population = context.require(&"population")
	_realizer = context.require(&"population_character_realizer")
	_lod = context.require(&"population_realization")
	_gecs.world_reindexed.connect(_on_world_reindexed)
	_context.require(&"camps").layout_changed.connect(_on_layout_changed)

func update_lod_swap(_bridge: Node, squads: Array, anchors: Array[Vector3], radius: float) -> Dictionary:
	var realized: Dictionary = {}
	if _restore_pending:
		return realized
	_spawn_budget = MAX_SPAWNS_PER_TICK
	var camps: Dictionary = _gecs.get_camp_states()
	var squad_by_id: Dictionary = {}
	var live_squads: Dictionary = {}
	for actor in _actors.values():
		if is_instance_valid(actor) and int(actor.life_state) != NpcRules.LifeState.DEAD:
			live_squads[str(actor.get_meta("world_squad_id", ""))] = true
	_squad_targets.clear()
	var active_squads: Dictionary = {}
	for squad in squads:
		if str(squad.get("owner_kind", "")) == "camp":
			var squad_id := str(squad.squad_id)
			squad_by_id[squad_id] = squad
			_squad_targets[squad_id] = squad.target_position
			var was_realized := live_squads.has(squad_id)
			var threshold := float(_lod.get_exit_radius()) if was_realized else radius
			active_squads[squad_id] = bool(_lod.should_keep_realized("squad:" + squad_id, _near(squad.position, anchors, threshold), was_realized))
	var wanted: Dictionary = {}
	for id in camps:
		var state: Dictionary = camps[id]
		var near := _near(state.position, anchors, radius + float(state.camp_radius))
		var keep := bool(_lod.should_keep_realized("camp:" + str(id), near, _furniture.has(id)))
		if keep and str(state.status) != "empty":
			_ensure_furniture(state)
		else:
			_remove_furniture(str(id))
		var definition: Resource = load(str(state.type_path))
		var records: Dictionary = {}
		var resident_order: Dictionary = {}
		for slot in state.slots:
			if not keep and not bool(active_squads.get(str(slot.squad_id), false)):
				continue
			var record: Dictionary = _gecs.get_population_presence(str(slot.actor_id))
			if record.is_empty() or int(record.get("life_state", 0)) == NpcRules.LifeState.DEAD:
				continue
			records[str(slot.actor_id)] = record
			if str(slot.squad_id).is_empty():
				resident_order[str(slot.actor_id)] = resident_order.size()
		for slot in state.slots:
			var actor_id := str(slot.actor_id)
			var record: Dictionary = records.get(actor_id, {})
			if record.is_empty():
				continue
			var squad_id := str(slot.squad_id)
			var position: Vector3 = state.position
			var active := keep
			if not squad_id.is_empty():
				var squad: Dictionary = squad_by_id.get(squad_id, {})
				if squad.is_empty():
					continue
				position = squad.position
				active = bool(active_squads.get(squad_id, false))
			if not active:
				continue
			wanted[actor_id] = true
			var actor := _population.get_live_actor(actor_id) as Node3D
			if actor == null and _spawn_budget > 0:
				_spawn_budget -= 1
				# Offscreen travel changes position, never identity, inventory or health.
				if not squad_id.is_empty():
					var offset := _member_offset(actor_id)
					_population.update_actor_record(actor_id, {"last_world_position": _ground(position + offset), "last_world_position_initialized": true, "last_world_transform_initialized": false})
				elif not bool(record.get("last_world_transform_initialized", false)):
					_population.update_actor_record(actor_id, {"last_world_position": _ground(position + _resident_offset(state, int(slot.resident_index))), "last_world_position_initialized": true})
				actor = _realizer.realize_record_actor(actor_id, _context.root_scene) as Node3D
			if actor == null:
				continue
			actor.set_meta("camp_id", id)
			actor.set_meta("world_squad_id", squad_id)
			_actors[actor_id] = actor
			if not squad_id.is_empty():
				realized[squad_id] = true
			_assign_routine(actor, state, slot, definition, squad_by_id.get(squad_id, {}), int(resident_order.get(actor_id, -1)), resident_order.size())
	for actor_id in _actors.keys():
		var actor = _actors[actor_id]
		if not is_instance_valid(actor):
			_actors.erase(actor_id)
			continue
		if int(actor.get("life_state")) == NpcRules.LifeState.DEAD:
			# Corpse retention/loot belongs to the shared population realization system.
			_actors.erase(actor_id)
			continue
		if not wanted.has(actor_id):
			_population.unregister_actor(actor)
			actor.queue_free()
			_actors.erase(actor_id)
	var centers: Dictionary = {}
	var counts: Dictionary = {}
	for actor in _actors.values():
		var squad_id := str(actor.get_meta("world_squad_id", ""))
		if realized.has(squad_id):
			centers[squad_id] = centers.get(squad_id, Vector3.ZERO) + actor.global_position
			counts[squad_id] = int(counts.get(squad_id, 0)) + 1
	for squad_id in centers:
		var squad: Dictionary = squad_by_id[squad_id]
		squad.position = centers[squad_id] / int(counts[squad_id])
		_gecs.upsert_world_sim_squad(squad)
	return realized

func _near(position: Vector3, anchors: Array[Vector3], radius: float) -> bool:
	for anchor in anchors:
		var delta := position - anchor
		delta.y = 0.0
		if delta.length_squared() <= radius * radius:
			return true
	return false

func _ensure_furniture(state: Dictionary) -> void:
	var id := str(state.camp_id)
	if _furniture.has(id) and is_instance_valid(_furniture[id]):
		return
	var root := Node3D.new()
	root.name = "CampFurniture_" + id.validate_node_name()
	_context.root_scene.add_child(root)
	_furniture[id] = root
	for entry in state.furnishings:
		var scene := load(str(entry.scene)) as PackedScene
		if scene == null:
			continue
		var node := scene.instantiate() as Node3D
		if node == null:
			continue
		node.set_meta("camp_purpose", entry.purpose)
		node.set_meta("camp_furniture_id", entry.id)
		if node is WorldContainer:
			node.container_id = str(entry.id)
			node.owner_faction_name = str(state.faction_id)
			node.supports_locking = false
			node.contributes_to_town_stock = false
			node.starting_items.clear()
			for stock in entry.stock:
				var item := InventoryStock.new()
				item.item_definition = load(str(stock.item_path)) as ItemDefinition
				item.quantity = int(stock.quantity)
				node.starting_items.append(item)
		if node is FacilityGuardPost:
			node.post_id = str(entry.id)
			node.guard_scope = "Private Security"
			node.employer_actor_id = str(state.camp_id)
		root.add_child(node)
		node.global_position = _ground(state.position + entry.offset)
		node.rotation.y = float(entry.yaw)

func _remove_furniture(id: String) -> void:
	var root = _furniture.get(id)
	if is_instance_valid(root):
		root.queue_free()
	_furniture.erase(id)

func _on_layout_changed(id: String) -> void:
	var state: Dictionary = _gecs.get_camp_state(id)
	for entry in state.furnishings:
		var node := _get_furniture(id, str(entry.id)) as Node3D
		if node != null:
			node.global_position = _ground(state.position + entry.offset)
			node.rotation.y = float(entry.yaw)
	for slot in state.slots:
		if not str(slot.squad_id).is_empty():
			continue
		var actor = _population.get_live_actor(str(slot.actor_id))
		if not is_instance_valid(actor) or int(actor.life_state) == NpcRules.LifeState.DEAD:
			continue
		var entity = _gecs.get_actor_entity(actor)
		var ai = entity.get_component(CGameAiState) if entity != null else null
		# Active combat/player orders retain physical authority; routines walk home.
		if ai != null and ai.active_job != null and str(ai.active_job.package_id) == "camp_routine":
			ai.finish_job(AiTaskStep.StepStatus.CANCELLED)

func _assign_routine(actor: Node3D, state: Dictionary, slot: Dictionary, definition: Resource, squad: Dictionary, resident_ordinal: int, living_residents: int) -> void:
	var clock := _context.require(&"world_time")
	var minute := int(clock.get("total_world_minutes"))
	var hour := (minute / 60) % 24
	var routine: String = RULES.routine(resident_ordinal, living_residents, hour, not squad.is_empty(), float(definition.get("night_watch_fraction")))
	var entity = _gecs.get_actor_entity(actor)
	var ai = entity.get_component(CGameAiState) if entity != null else null
	if ai == null:
		return
	if int(actor.get("life_state")) == NpcRules.LifeState.ASLEEP:
		if routine != "sleep":
			actor.call("wake_up_from_rest", false)
		return
	if int(actor.get("life_state")) != NpcRules.LifeState.ALIVE:
		return
	var rotation_slot := minute / maxi(1, int(definition.get("guard_rotation_minutes")))
	var objective := "%s:%s:%d" % [state.camp_id, routine, rotation_slot if routine != "patrol" else 0]
	if ai.active_job != null and str(ai.active_job.objective_id) == objective:
		return
	if ai.active_job != null and (ai.active_job.is_combat() or ai.active_job.issued_by_player):
		return
	var job := AiJob.new()
	job.job_type = AiJob.JobType.PATROL if routine == "patrol" else AiJob.JobType.GUARD_POST
	job.priority = AiJob.priority_for_type(job.job_type)
	job.package_id = "camp_routine"
	job.source_id = str(state.camp_id)
	job.source = self
	job.objective_id = objective
	job.debug_label = "Camp " + routine
	job.data = {"routine": routine, "camp_id": state.camp_id, "squad_id": slot.squad_id, "destination": _ground(state.position + _resident_offset(state, int(slot.resident_index))), "seat_id": "", "post_id": ""}
	if routine == "sleep":
		job.data["camp_center"] = state.position
		job.data["camp_radius"] = state.camp_radius
	if routine == "guard" or routine == "sit":
		var choices: Array = []
		for entry in state.furnishings:
			if str(entry.purpose) == ("guard" if routine == "guard" else "seat"):
				choices.append(entry)
		if not choices.is_empty():
			var ordinal := maxi(0, resident_ordinal)
			ordinal = ordinal / 3 if routine == "sit" else ordinal - ordinal / 3
			var index := (ordinal + rotation_slot) % choices.size()
			var chosen: Dictionary = choices[index]
			if routine == "sit":
				chosen = {}
				for attempt in choices.size():
					var candidate: Dictionary = choices[(index + attempt) % choices.size()]
					var seat := _get_furniture(str(state.camp_id), str(candidate.id)) as SittableSeat
					if seat != null and (not seat.is_occupied() or seat.get_sitter() == actor):
						chosen = candidate
						break
			if routine == "guard":
				for attempt in choices.size():
					var candidate: Dictionary = choices[(index + attempt) % choices.size()]
					var post := _get_furniture(str(state.camp_id), str(candidate.id)) as FacilityGuardPost
					if post != null and post.is_available_for(actor):
						chosen = candidate
						job.data.post_id = str(candidate.id)
						break
			if not chosen.is_empty():
				job.data.destination = _ground(state.position + chosen.offset)
				job.data.seat_id = str(chosen.id) if routine == "sit" else ""
				job.data.facing = float(chosen.yaw)
	job.steps = [ROUTINE_STEP.new()]
	if ai.active_job != null:
		if str(ai.active_job.package_id) != "camp_routine" and not job.should_replace(ai.active_job, actor):
			return
		ai.finish_job(AiTaskStep.StepStatus.CANCELLED)
	job.status = AiJob.JobStatus.RUNNING
	job.job_id = "%s:%s" % [objective, str(slot.actor_id)]
	var driver := AiLimboJobDriver.new()
	driver.setup(actor, job)
	actor.add_child(driver)
	_gecs.set_actor_ai_job(actor, job, driver)

func get_patrol_destination(_actor: Node3D, job) -> Vector3:
	return _ground(_squad_targets.get(str(job.data.squad_id), job.data.destination))

func get_camp_seat(job, actor: Node = null) -> Node:
	var preferred := _get_furniture(str(job.data.camp_id), str(job.data.seat_id)) as SittableSeat
	if preferred != null and (not preferred.is_occupied() or preferred.get_sitter() == actor):
		return preferred
	# Resolve contention when the step actually starts, not while queuing a job.
	# Unstarted/cancelled jobs must never leave a reservation behind.
	var root = _furniture.get(str(job.data.camp_id))
	if is_instance_valid(root):
		for child in root.get_children():
			if child is SittableSeat and (not child.is_occupied() or child.get_sitter() == actor):
				return child
	return null

func get_camp_post(job) -> FacilityGuardPost:
	return _get_furniture(str(job.data.camp_id), str(job.data.get("post_id", ""))) as FacilityGuardPost

func _get_furniture(camp_id: String, furniture_id: String) -> Node:
	var root = _furniture.get(camp_id)
	if is_instance_valid(root):
		for child in root.get_children():
			if str(child.get_meta("camp_furniture_id", "")) == furniture_id:
				return child
	return null

func request_sleep(actor: Node) -> void:
	_gecs.request_actor_rest_state(str(actor.get_meta("actor_record_id", "")), NpcRules.LifeState.ASLEEP)

func _member_offset(id: String) -> Vector3:
	var angle := float(posmod(hash(id), 360)) * PI / 180.0
	return Vector3(cos(angle), 0, sin(angle)) * 1.5

func _resident_offset(state: Dictionary, index: int) -> Vector3:
	var angle := TAU * maxi(0, index) / maxi(1, int(state.resident_count))
	return Vector3(cos(angle), 0, sin(angle)) * float(state.camp_radius) * 0.5

func _ground(position: Vector3) -> Vector3:
	var root := _context.root_scene as Node3D
	if root == null or not root.is_inside_tree():
		return position
	var query := PhysicsRayQueryParameters3D.create(position + Vector3.UP * 30.0, position - Vector3.UP * 50.0, 1)
	var hit := root.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if not hit.is_empty() else position

func _on_world_reindexed() -> void:
	_restore_pending = true
	for id in _furniture.keys():
		_remove_furniture(str(id))
	_finish_restore.call_deferred()

func _finish_restore() -> void:
	# Population's earlier deferred callback hydrates these actors first.
	for actor_id in _actors.keys():
		var actor = _actors[actor_id]
		if not is_instance_valid(actor):
			continue
		var record: Dictionary = _population.get_actor_record(str(actor_id))
		if record.is_empty():
			# Loading an older save discards bodies created after that snapshot.
			_population.unregister_actor(actor)
			actor.queue_free()
			_actors.erase(actor_id)
			continue
		if not record.is_empty():
			# Migration invalidates old resident transforms even when a body survived load.
			if not bool(record.get("last_world_transform_initialized", false)):
				var state: Dictionary = _gecs.get_camp_state(str(actor.get_meta("camp_id", "")))
				for slot in state.get("slots", []):
					if str(slot.actor_id) == str(actor_id) and str(slot.squad_id).is_empty():
						var position := _ground(state.position + _resident_offset(state, int(slot.resident_index)))
						record = _population.update_actor_record(str(actor_id), {"last_world_position": position, "last_world_position_initialized": true})
						break
			_realizer.restore_record_transform(actor, record)
			var entity = _gecs.get_actor_entity(actor)
			var ai = entity.get_component(CGameAiState) if entity != null else null
			if ai != null and ai.active_job != null and str(ai.active_job.package_id) == "camp_routine":
				ai.finish_job(AiTaskStep.StepStatus.CANCELLED)
	_restore_pending = false
