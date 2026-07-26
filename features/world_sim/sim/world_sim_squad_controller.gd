extends Node

class_name WorldSimSquadController

const SERVICE_ID := &"world_sim_squad"

## The cheap world-sim "mover" for squads. On a timer (NOT every frame) it advances
## each CGameWorldSimSquad record toward its target_position by simple math — O(1)
## per squad, no live bodies. On arrival it re-targets per objective. Source of
## truth is the GECS records; this just transports them. The realize/derealize swap
## to live actors when a squad enters the LOD ring is a later step.

const TICK_INTERVAL := 0.5
const ARRIVAL_EPSILON := 2.0

var _initialized := false
var _context: BootstrapContext
var _tick_remaining := 0.0
var _rng := RandomNumberGenerator.new()
var _world_sim_plugins: Array[Node] = []


func initialize(context: BootstrapContext) -> void:
	_context = context
	_initialized = true


func _ready() -> void:
	add_to_group("world_sim_squad_controller")
	_rng.randomize()
	_initialized = true


func register_world_sim_plugin(plugin: Node) -> void:
	if plugin == null or _world_sim_plugins.has(plugin):
		return
	_world_sim_plugins.append(plugin)


func get_world_sim_plugin(plugin_id: String) -> Node:
	for plugin in _world_sim_plugins:
		if plugin != null and is_instance_valid(plugin) and plugin.has_method("get_world_sim_plugin_id") and str(plugin.call("get_world_sim_plugin_id")) == plugin_id:
			return plugin
	return null


func get_world_sim_plugins() -> Array[Node]:
	var result: Array[Node] = []
	for plugin in _world_sim_plugins:
		if plugin != null and is_instance_valid(plugin):
			result.append(plugin)
	return result


func _process(delta: float) -> void:
	if not _initialized:
		return
	_tick_remaining -= delta
	if _tick_remaining > 0.0:
		return
	_tick_remaining = TICK_INTERVAL
	_advance_squads(TICK_INTERVAL)


func _advance_squads(dt: float) -> void:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_world_sim_squads"):
		return
	var squads: Array = bridge.get_world_sim_squads()
	_prune_removed_squad_retention(squads)
	var anchors := _lod_anchors()
	var reference: Vector3 = anchors[0] if not anchors.is_empty() else Vector3.INF
	var radius := _lod_radius()
	for plugin in get_world_sim_plugins():
		if plugin.has_method("world_sim_tick"):
			plugin.call("world_sim_tick", dt, bridge, squads, reference, radius)
	# Always on: a raid squad manifests as real characters whenever the player is in range
	# and folds back to data (kills kept) when they leave. No longer behind a debug toggle.
	var realized: Dictionary = _update_lod_swap(bridge, squads, anchors, radius)
	for record in squads:
		if int(record.get("member_count", 0)) <= 0:
			continue
		# Freeze a squad's dot while it has live bodies (keyed by nest owner OR faction
		# squad id), so the data dot doesn't wander away from the realized actors.
		if bool(realized.get(str(record.get("owner_id", "")), false)) or bool(realized.get(str(record.get("squad_id", "")), false)):
			continue
		_advance_one(bridge, record, dt)


## Realize squads (owners) inside the LOD ring into live bodies, derealize those
## outside it. Whole-nest granularity, reusing nest's own spawn/reconcile. Returns
## owner_id -> realized so the mover can freeze realized squads.
func _update_lod_swap(bridge: Node, squads: Array, anchors: Array[Vector3], radius: float) -> Dictionary:
	var realized_map: Dictionary = {}
	if anchors.is_empty():
		return realized_map
	for plugin in get_world_sim_plugins():
		if not plugin.has_method("update_lod_swap"):
			continue
		var plugin_realized: Dictionary = plugin.call("update_lod_swap", bridge, squads, anchors, radius)
		for key in plugin_realized.keys():
			realized_map[str(key)] = bool(plugin_realized[key])
	var faction_ctrl := _faction_world_sim_controller()
	if faction_ctrl != null:
		for record in squads:
			if str(record.get("owner_kind", "")) != "faction":
				continue
			var squad_id := str(record.get("squad_id", ""))
			var position: Vector3 = record.get("position", Vector3.ZERO)
			var faction_real := bool(faction_ctrl.is_faction_squad_realized(squad_id)) if faction_ctrl.has_method("is_faction_squad_realized") else false
			var threshold := _exit_lod_radius() if faction_real else radius
			var near_faction := _is_near_any_anchor(position, anchors, threshold)
			var keep_faction := _should_keep_realized("squad:%s" % squad_id, near_faction, faction_real)
			if keep_faction and not faction_real and faction_ctrl.has_method("realize_faction_squad"):
				faction_ctrl.realize_faction_squad(record)
				faction_real = true
				if bridge.has_method("log_world_event"):
					bridge.log_world_event("faction", "%s squad realized — bodies on the ground" % str(record.get("faction_id", "")), {})
			elif not keep_faction and faction_real and faction_ctrl.has_method("derealize_faction_squad"):
				var survivors := int(faction_ctrl.derealize_faction_squad(squad_id))
				faction_real = false
				record["member_count"] = survivors
				if survivors <= 0:
					if bridge.has_method("remove_world_sim_squad"):
						bridge.remove_world_sim_squad(squad_id)
					if bridge.has_method("log_world_event"):
						bridge.log_world_event("faction", "%s squad wiped out" % str(record.get("faction_id", "")), {})
				elif bridge.has_method("upsert_world_sim_squad"):
					bridge.upsert_world_sim_squad(record)
			if faction_real and faction_ctrl.has_method("drive_realized_squad"):
				# Realized squads MARCH for real: order the live bodies toward the target town
				# and track the data dot to their centroid, so the map dot follows them and the
				# range check derealizes them correctly as they leave the player behind.
				record["position"] = faction_ctrl.drive_realized_squad(record)
				if bridge.has_method("upsert_world_sim_squad"):
					bridge.upsert_world_sim_squad(record)
			realized_map[squad_id] = faction_real
	return realized_map


func _lod_anchors() -> Array[Vector3]:
	var result: Array[Vector3] = []
	var controller := _realization_controller()
	if controller == null or not controller.has_method("get_realization_anchor_positions"):
		return result
	for value in controller.call("get_realization_anchor_positions"):
		if value is Vector3:
			result.append(value)
	return result


func _is_near_any_anchor(position: Vector3, anchors: Array[Vector3], radius: float) -> bool:
	var radius_squared := radius * radius
	for anchor in anchors:
		var offset := position - anchor
		offset.y = 0.0
		if offset.length_squared() <= radius_squared:
			return true
	return false


func _should_keep_realized(cache_key: String, near: bool, realized: bool) -> bool:
	var controller := _realization_controller()
	return bool(controller.call("should_keep_realized", cache_key, near, realized)) if controller != null and controller.has_method("should_keep_realized") else near


func _prune_removed_squad_retention(squads: Array) -> void:
	var controller := _realization_controller()
	if controller == null or not controller.has_method("prune_realization_retention"):
		return
	var active_keys := {}
	for record in squads:
		active_keys["squad:%s" % str(record.get("squad_id", ""))] = true
	controller.call("prune_realization_retention", "squad:", active_keys)


func _lod_radius() -> float:
	var controller := _realization_controller()
	if controller != null:
		if controller.has_method("get_entry_radius"):
			return float(controller.call("get_entry_radius"))
	return 120.0


func _exit_lod_radius() -> float:
	var controller := _realization_controller()
	return float(controller.call("get_exit_radius")) if controller != null and controller.has_method("get_exit_radius") else _lod_radius() + 25.0


func _realization_controller() -> Node:
	return _context.get_optional(PopulationRealizationController.SERVICE_ID) if _context != null else null


func _faction_world_sim_controller() -> Node:
	return _context.get_optional(FactionWorldSimController.SERVICE_ID) if _context != null else null


func _log_event(category: String, message: String) -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("log_world_event"):
		bridge.log_world_event(category, message, {})


func _advance_one(bridge: Node, record: Dictionary, dt: float) -> void:
	# A squad mid-encounter is owned by EncounterController (it counts down the grace
	# windows and resolves). The mover stops transporting it until the encounter clears
	# the phase and hands it back (objective="return").
	if not str(record.get("phase", "")).is_empty():
		return
	var objective := str(record.get("objective", "patrol"))
	var position: Vector3 = record.get("position", Vector3.ZERO)
	var target: Vector3 = record.get("target_position", position)
	var to_target := target - position
	to_target.y = 0.0
	if to_target.length() <= ARRIVAL_EPSILON:
		match objective:
			"patrol":
				record["target_position"] = _patrol_point(record)
			"attack":
				# Arrived at the target — hand off to EncounterController, which runs the
				# demand -> fight -> aftermath grace windows. We just flip into the demand
				# phase; the encounter clears it back to "return" when it resolves.
				record["phase"] = "demand"
				record["decision"] = ""
				record["phase_timer"] = 0.0
			"return":
				# Home again — the raid is resolved; retire the squad.
				if bridge.has_method("remove_world_sim_squad"):
					bridge.remove_world_sim_squad(str(record.get("squad_id", "")))
				return
			_:
				return
	else:
		var speed := float(record.get("move_speed", 3.0))
		record["position"] = position + to_target.normalized() * speed * dt
	bridge.upsert_world_sim_squad(record)


func _patrol_point(record: Dictionary) -> Vector3:
	var home: Vector3 = record.get("home_position", record.get("position", Vector3.ZERO))
	var radius := float(record.get("patrol_radius", 40.0))
	var angle := _rng.randf() * TAU
	var distance := sqrt(_rng.randf()) * radius
	return home + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)


func _get_gecs_world() -> Node:
	return _context.get_optional(GecsWorldController.SERVICE_ID) if _context != null else null
