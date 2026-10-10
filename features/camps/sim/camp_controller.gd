extends Node

const SERVICE_ID := &"camps"
const RULES := preload("res://features/camps/sim/camp_rules.gd")
const LAYOUT := preload("res://features/camps/sim/camp_layout.gd")
const LAYOUT_VERSION := 4

signal layout_changed(camp_id: String)

var _context: BootstrapContext
var _gecs: Node
var _population: Node
var _time: Node
var _markers: Dictionary = {}
var _dirty: Dictionary = {}
var _due_by_id: Dictionary = {}
var _last_minute := -1
var _restoring := false

func initialize(context: BootstrapContext) -> void:
	_context = context
	_gecs = context.require(&"gecs_world")
	_population = context.require(&"population")
	_time = context.require(&"world_time")
	context.require(&"world_sim_squad").register_world_sim_plugin(self)
	_population.person_died.connect(_on_member_died)
	_gecs.world_reindexed.connect(_on_world_reindexed)

func get_world_sim_plugin_id() -> String:
	return "camps"

func register_marker(marker: Node3D) -> void:
	var id := str(marker.get("camp_id"))
	if id.is_empty() or marker.get("faction") == null or marker.get("camp_type") == null:
		push_error("Camp marker requires an ID, faction and camp type")
		return
	if _markers.has(id) and is_instance_valid(_markers[id]) and _markers[id] != marker:
		push_error("Duplicate camp ID: " + id)
		return
	_markers[id] = marker
	var factions := _context.require(&"faction")
	factions.call("register_faction", marker.get("faction"))
	if _gecs.get_camp_state(id).is_empty():
		_generate(marker)
	else:
		var state: Dictionary = _gecs.get_camp_state(id)
		var changed := _migrate_layout(state, int(marker.get("camp_size")))
		var roaming := maxf(10.0, float(marker.get("roaming_radius")))
		if changed or not is_equal_approx(float(state.operational_radius), roaming):
			state.operational_radius = roaming
			_gecs.upsert_camp_state(state)
			_refresh_squad_counts(state)
		if changed:
			layout_changed.emit(id)
	_dirty[id] = true

func _generate(marker: Node3D) -> void:
	var definition: Resource = marker.get("camp_type")
	var faction: Resource = marker.get("faction")
	var id := str(marker.get("camp_id"))
	var preset: Resource = marker.call("get_size_preset")
	var total := maxi(2, int(marker.call("get_population")))
	var squads := mini(clampi(int(marker.get("squad_count")), 1, 4), total - 1)
	var per_squad := mini(maxi(1, int(marker.get("squad_size"))), (total - 1) / squads)
	var residents := total - squads * per_squad
	var state := {
		"camp_id": id, "status": "occupied", "faction_id": faction.call("get_id"),
		"faction_path": faction.resource_path, "type_path": definition.resource_path,
		"position": marker.global_position, "camp_radius": float(preset.get("footprint_radius")),
		"camp_size": int(marker.get("camp_size")), "layout_version": LAYOUT_VERSION,
		"operational_radius": maxf(10.0, float(marker.get("roaming_radius"))),
		"population_limit": total, "resident_count": residents,
		"squad_count": squads, "squad_size": per_squad, "slots": [],
		"generation_index": 0, "seed": int(marker.get("generation_seed")),
		"replacement_due": -1.0, "replacement_interval": float(definition.get("replacement_days")) * 1440.0,
		"cleanup_delay": float(definition.get("cleanup_days")) * 1440.0,
		"cleared_at": -1.0, "furnishings": [], "patrol_sequence": {},
	}
	for index in total:
		var squad_id := "%s.patrol.%d" % [id, (index - residents) / per_squad] if index >= residents else ""
		state.slots.append({"actor_id": "", "squad_id": squad_id, "resident_index": index if squad_id.is_empty() else -1})
		_spawn_member(state, index)
	state.furnishings = _roll_layout(state, definition)
	_gecs.upsert_camp_state(state)
	_refresh_squad_counts(state)

func _spawn_member(state: Dictionary, slot_index: int) -> void:
	var faction: Resource = load(str(state.faction_path))
	var definition: Resource = load(str(state.type_path))
	var slot: Dictionary = state.slots[slot_index]
	state.generation_index = int(state.generation_index) + 1
	var context := {
		"population_appearance_profile": faction.call("get_character_realizer"),
		"population_name_profile": faction.get("population_name_profile"),
		"character_type": definition.get("warrior_type"), "race_weights": faction.get("race_weights"),
		"faction_id": state.faction_id, "squad_name": slot.squad_id,
		"role_id": "camp_leader" if slot_index == 0 else "camp_warrior",
		"available_for_work": false, "combat_stance": NpcRules.CombatStance.AGGRESSIVE,
		"spawn_position": state.position, "generation_seed": state.seed,
	}
	var record: Dictionary = _population.ensure_authored_record(str(state.camp_id), "camp", int(state.generation_index), context, {})
	if not record.is_empty():
		slot.actor_id = record.actor_id

func _roll_layout(state: Dictionary, definition: Resource) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(state.camp_id)) ^ int(state.seed)
	var layout: Array = []
	var preset: Resource = definition.call("get_size_preset", int(state.get("camp_size", 1)))
	for recipe in definition.get("furnishings"):
		if recipe == null or recipe.get("scene") == null:
			continue
		var purpose := str(recipe.get("purpose"))
		var count := rng.randi_range(int(recipe.get("minimum")), maxi(int(recipe.get("minimum")), int(recipe.get("maximum"))))
		if purpose != "center":
			count = ceili(count * float(preset.get("furnishing_multiplier")))
		count = maxi(count, ceili(float(recipe.get("per_resident")) * int(state.resident_count)))
		var pool: Resource = recipe.get("stock_pool")
		var capacity: InventoryData
		if pool != null:
			var prototype: Node = recipe.get("scene").instantiate()
			if prototype is WorldContainer:
				capacity = InventoryData.new(prototype.inventory_columns, prototype.inventory_rows, 0.0, false)
			prototype.free()
		for index in count:
			var stocks: Array = []
			if pool != null:
				if capacity != null:
					capacity.entries.clear()
				for stock in pool.call("roll", rng, capacity):
					stocks.append({"item_path": stock.item_definition.resource_path, "quantity": stock.quantity})
			layout.append({"id": "%s.furniture.%d" % [state.camp_id, layout.size()], "scene": recipe.get("scene").resource_path, "purpose": purpose, "offset": Vector3.ZERO, "yaw": 0.0, "stock": stocks})
	return LAYOUT.arrange(layout, float(state.camp_radius), float(definition.get("seating_radius")), hash(str(state.camp_id)) ^ int(state.seed))

func _migrate_layout(state: Dictionary, size: int) -> bool:
	if int(state.get("layout_version", 0)) >= LAYOUT_VERSION and int(state.get("camp_size", 1)) == size:
		return false
	if int(state.get("layout_version", 0)) == 3 and int(state.get("camp_size", 1)) == size:
		# Repair facing without moving furniture, resetting residents or rerolling loot.
		LAYOUT.orient_seats(state.furnishings)
		state.layout_version = LAYOUT_VERSION
		return true
	var definition: Resource = load(str(state.type_path))
	var preset: Resource = definition.call("get_size_preset", size)
	var radius := float(preset.get("footprint_radius"))
	# Reposition existing identities only: never regenerate roster, containers or loot.
	state.furnishings = LAYOUT.arrange(state.furnishings, radius, float(definition.get("seating_radius")), hash(str(state.camp_id)) ^ int(state.seed), true)
	state.camp_radius = radius
	state["camp_size"] = size
	state["layout_version"] = LAYOUT_VERSION
	# Unloaded residents must not return at the obsolete, far-spread transforms.
	for slot in state.slots:
		if not str(slot.squad_id).is_empty():
			continue
		var record: Dictionary = _population.get_actor_record(str(slot.actor_id))
		if not record.is_empty() and int(record.get("life_state", 0)) != NpcRules.LifeState.DEAD:
			_population.update_actor_record(str(slot.actor_id), {"last_world_transform_initialized": false})
	return true

func world_sim_tick(_dt: float, _bridge: Node, squads: Array, _reference: Vector3, _radius: float) -> void:
	if _restoring:
		return
	var now := float(_time.get("total_world_minutes"))
	var minute := floori(now)
	if minute != _last_minute:
		_last_minute = minute
		for id in _due_by_id:
			if now >= float(_due_by_id[id]):
				_dirty[id] = true
	var ids := _dirty.keys()
	# Bounded lifecycle work; death signals prioritize their own camp immediately.
	for id in ids.slice(0, 8):
		_dirty.erase(id)
		advance_camp(str(id), now)
	if not ids.is_empty():
		squads = _gecs.get_world_sim_squads()
	for squad in squads:
		if str(squad.get("owner_kind", "")) != "camp" or int(squad.get("member_count", 0)) == 0:
			continue
		var position: Vector3 = squad.position
		if position.distance_to(squad.target_position) <= 3.0:
			squad.target_position = get_patrol_target(squad)
			_gecs.upsert_world_sim_squad(squad)

func advance_camp(id: String, now: float) -> void:
	var state: Dictionary = _gecs.get_camp_state(id)
	if state.is_empty():
		return
	var survivors := 0
	var vacant: Array[int] = []
	for index in state.slots.size():
		var record: Dictionary = _population.get_actor_record(str(state.slots[index].actor_id))
		if not record.is_empty() and int(record.get("life_state", 0)) != NpcRules.LifeState.DEAD:
			survivors += 1
		else:
			vacant.append(index)
	var previous_status := str(state.status)
	var replacements: int = RULES.advance_lifecycle(state, survivors, now)
	for index in replacements:
		_spawn_member(state, vacant[index])
	_gecs.upsert_camp_state(state)
	_refresh_squad_counts(state)
	_due_by_id.erase(id)
	if str(state.status) == "cleared":
		_due_by_id[id] = float(state.cleared_at) + float(state.cleanup_delay)
	elif str(state.status) == "occupied" and float(state.replacement_due) >= 0.0:
		_due_by_id[id] = float(state.replacement_due)
	if previous_status != "empty" and str(state.status) == "empty":
		for entry in state.furnishings:
			if str(entry.purpose) != "container":
				continue
			# Only abandoned contents disappear; looted stacks now have other hosts.
			for stack in _gecs.get_inventory_stacks(str(entry.id)):
				_gecs.remove_item_stack_entity(str(stack.stack_id))
			_gecs.remove_inventory_container_entity(str(entry.id))

func _refresh_squad_counts(state: Dictionary) -> void:
	var counts: Dictionary = {}
	for slot in state.slots:
		var id := str(slot.squad_id)
		if id.is_empty():
			continue
		if not counts.has(id):
			counts[id] = 0
		var record: Dictionary = _population.get_actor_record(str(slot.actor_id))
		if not record.is_empty() and int(record.get("life_state", 0)) != NpcRules.LifeState.DEAD:
			counts[id] += 1
	var existing: Dictionary = {}
	for record in _gecs.get_world_sim_squads():
		if str(record.get("owner_id", "")) == str(state.camp_id):
			existing[str(record.squad_id)] = record
	for id in counts:
		var squad: Dictionary = existing.get(id, {})
		if squad.is_empty():
			var definition: Resource = load(str(state.type_path))
			squad = {"squad_id": id, "owner_id": state.camp_id, "owner_kind": "camp", "faction_id": state.faction_id, "objective": "patrol", "position": state.position, "home_position": state.position, "target_position": state.position, "patrol_radius": state.operational_radius, "move_speed": definition.get("patrol_speed")}
		squad.patrol_radius = state.operational_radius
		if squad.target_position.distance_to(squad.home_position) > float(state.operational_radius):
			squad.target_position = squad.home_position
		squad.member_count = counts[id]
		_gecs.upsert_world_sim_squad(squad)

func get_patrol_target(squad: Dictionary) -> Vector3:
	var state: Dictionary = _gecs.get_camp_state(str(squad.owner_id))
	if state.is_empty():
		return squad.position
	var id := str(squad.squad_id)
	var sequence := int(state.patrol_sequence.get(id, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) ^ int(state.seed) ^ sequence
	state.patrol_sequence[id] = sequence + 1
	_gecs.upsert_camp_state(state)
	var faction: Resource = load(str(state.faction_path))
	return RULES.patrol_target(squad.position, squad.home_position, float(squad.patrol_radius), _settlement_buffers(), float(faction.get("settlement_approach_chance")), rng)

func _settlement_buffers() -> Array:
	var result: Array = []
	for state in _gecs.get_settlement_states().values():
		result.append({"position": state.get("world_position", Vector3.ZERO), "radius": maxf(20.0, float(state.get("radius", 60.0))) + 15.0})
	return result

func update_lod_swap(bridge: Node, squads: Array, anchors: Array[Vector3], radius: float) -> Dictionary:
	var projection := _context.get_optional(&"camp_realization")
	if _restoring:
		return {}
	var realized: Dictionary = projection.call("update_lod_swap", bridge, squads, anchors, radius) if projection != null else {}
	for squad in squads:
		if str(squad.get("owner_kind", "")) != "camp" or bool(realized.get(str(squad.squad_id), false)):
			continue
		var near := false
		for anchor in anchors:
			if anchor.distance_squared_to(squad.position) < radius * radius:
				near = true
		if not near:
			resolve_offscreen_skirmish(squad)
	return realized


func resolve_offscreen_skirmish(squad: Dictionary) -> void:
	var combat := _context.get_optional(&"faction_world_sim")
	if combat == null or int(squad.get("member_count", 0)) <= 0:
		return
	# A retained live member means physical combat still owns consequences.
	for record in _population.get_records_for_squad(str(squad.squad_id)):
		if _population.get_live_actor(str(record.actor_id)) != null:
			return
	var state: Dictionary = _gecs.get_camp_state(str(squad.owner_id))
	var cooldowns: Dictionary = state.get("skirmish_after", {})
	var now := float(_time.get("total_world_minutes"))
	if now < float(cooldowns.get(str(squad.squad_id), -1.0)):
		return
	var factions := _context.require(&"faction")
	for town in _gecs.get_settlement_states().values():
		if not factions.are_hostile(str(squad.faction_id), str(town.faction_id)):
			continue
		var delta: Vector3 = squad.position - town.get("world_position", Vector3.ZERO)
		delta.y = 0.0
		var range_limit := maxf(20.0, float(town.get("radius", 60.0)))
		if delta.length_squared() > range_limit * range_limit:
			continue
		var definition: Resource = load(str(state.type_path))
		cooldowns[str(squad.squad_id)] = now + float(definition.get("skirmish_cooldown_hours")) * 60.0
		state["skirmish_after"] = cooldowns
		_gecs.upsert_camp_state(state)
		var outcome: Dictionary = combat.roll_raid(int(squad.member_count), str(town.settlement_id))
		_population.apply_offscreen_squad_casualties(str(squad.squad_id), int(outcome.survivors), squad.position)
		squad.member_count = int(outcome.survivors)
		squad.target_position = squad.home_position
		_gecs.upsert_world_sim_squad(squad)
		_gecs.log_world_event("camp", "%s patrol fought near %s" % [str(squad.faction_id), str(town.get("display_name", town.settlement_id))], {"squad_id": squad.squad_id, "survivors": outcome.survivors})
		return

func _on_member_died(actor_id: String) -> void:
	if _restoring:
		return
	var record: Dictionary = _population.get_actor_record(actor_id)
	var id := str(record.get("settlement_id", ""))
	if not _gecs.get_camp_state(id).is_empty():
		# Clear at the death timestamp, not the player's next visit.
		advance_camp(id, float(_time.get("total_world_minutes")))

func _on_world_reindexed() -> void:
	_restoring = true
	_dirty.clear()
	_due_by_id.clear()
	_finish_restore.call_deferred()

func _finish_restore() -> void:
	_restoring = false
	_last_minute = -1
	for id in _gecs.get_camp_states():
		var state: Dictionary = _gecs.get_camp_state(str(id))
		if _migrate_layout(state, int(state.get("camp_size", 1))):
			_gecs.upsert_camp_state(state)
			layout_changed.emit(str(id))
		_dirty[id] = true
	for marker in _markers.values():
		if is_instance_valid(marker):
			register_marker(marker)
