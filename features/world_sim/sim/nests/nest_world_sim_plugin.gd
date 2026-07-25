extends Node

class_name NestWorldSimPlugin

const NEST_STATE_ID := "nests"
const RUSTDEAD_NEST_TYPE := preload("res://features/world_sim/resources/nests/rustdead.tres")
const RUSTDEAD_RACE := preload("res://features/actors/resources/character_races/rustdead.tres")
const APPEARANCE_DATA_SCRIPT := preload("res://features/actors/resources/character_appearance/character_appearance_data.gd")
const HUMAN_MALE_BODY_ARCHETYPE := preload("res://features/actors/resources/character_body_archetypes/human_male.tres")
const HUMAN_FEMALE_BODY_ARCHETYPE := preload("res://features/actors/resources/character_body_archetypes/human_female.tres")
const RUSTDEAD_TIER_LIBRARY := preload("res://features/actors/projection/rustdead/rustdead_tier_library.gd")
const AI_JOB_SCRIPT := preload("res://features/ai/bridge/ai_job.gd")
const AI_PATROL_STEP_SCRIPT := preload("res://features/ai/bridge/steps/ai_patrol_step.gd")
const AI_NEST_ASSAULT_STEP_SCRIPT := preload("res://features/ai/bridge/steps/ai_nest_assault_step.gd")
const TWISTED_SCRAP_HEAP_SCENE := preload("res://features/world/bridge/resource_nodes/scrap_pile_variant_2_node.tscn")
const SCRAP_PILE_SCENE := preload("res://features/world/bridge/resource_nodes/scrap_pile_node.tscn")
const HALF_BURIED_ROBOT_WRECK_SCENE := preload("res://features/world/bridge/resource_nodes/half_buried_robot_wreck_node.tscn")

const PEASANT_TUNIC := preload("res://features/inventory/resources/items/peasant_tunic.tres")
const PEASANT_TROUSERS := preload("res://features/inventory/resources/items/peasant_trousers.tres")
const PEASANT_SHOES := preload("res://features/inventory/resources/items/peasant_shoes.tres")
const RANGER_JERKIN := preload("res://features/inventory/resources/items/ranger_jerkin.tres")
const RANGER_LEGGINGS := preload("res://features/inventory/resources/items/ranger_leggings.tres")
const RANGER_BOOTS := preload("res://features/inventory/resources/items/ranger_boots.tres")
const RANGER_HOOD := preload("res://features/inventory/resources/items/ranger_hood.tres")
const NOBLE_DOUBLET := preload("res://features/inventory/resources/items/noble_doublet.tres")
const NOBLE_SLEEVES := preload("res://features/inventory/resources/items/noble_sleeves.tres")
const NOBLE_TROUSERS := preload("res://features/inventory/resources/items/noble_trousers.tres")
const NOBLE_SHOES := preload("res://features/inventory/resources/items/noble_shoes.tres")
const WIZARD_ROBES := preload("res://features/inventory/resources/items/wizard_robes.tres")
const WIZARD_SLEEVES := preload("res://features/inventory/resources/items/wizard_sleeves.tres")
const WIZARD_TROUSERS := preload("res://features/inventory/resources/items/wizard_trousers.tres")
const WIZARD_SHOES := preload("res://features/inventory/resources/items/wizard_shoes.tres")
const KNIGHT_GREAVES := preload("res://features/inventory/resources/items/knight_greaves.tres")
const KNIGHT_SABATONS := preload("res://features/inventory/resources/items/knight_sabatons.tres")

const VISUAL_BODY_TYPE_MALE := 2
const VISUAL_BODY_TYPE_FEMALE := 3
const NEST_ACTOR_ROOT_NAME := "NestActors"
const NEST_VISUAL_NAME := "ActiveNestVisual"
const NEST_SCRAP_ROOT_NAME := "NestScrapPiles"
const NEST_PATROL_SOURCE_ID := "nest_patrol"
const NEST_ASSAULT_SOURCE_ID := "nest_assault"
const RUSTDEAD_SMALL_SCRAP_COUNT_RANGE := Vector2i(3, 5)
const RUSTDEAD_MEDIUM_SCRAP_COUNT_RANGE := Vector2i(5, 8)
const RUSTDEAD_LARGE_SCRAP_COUNT_RANGE := Vector2i(7, 11)
const RUSTDEAD_SCRAP_MIN_RADIUS := 8.0
const RUSTDEAD_SCRAP_MAX_RADIUS := 18.0
const RUSTDEAD_SCRAP_MIN_SEPARATION := 4.5
const MINUTES_PER_DAY := 24 * 60
const DEFAULT_MAINTENANCE_INTERVAL_SECONDS := 1.0
const DEFAULT_RESPAWN_COOLDOWN_DAYS := 7
## Hysteresis keeps squad LOD from thrashing on the world-sim tick.
const NEST_LOD_HYSTERESIS := 40.0

const SCRAP_SIZE_SMALL := "small"
const SCRAP_SIZE_MEDIUM := "medium"
const SCRAP_SIZE_LARGE := "large"

const RUSTDEAD_CHEST_ITEMS := [PEASANT_TUNIC, RANGER_JERKIN, NOBLE_DOUBLET, WIZARD_ROBES]
const RUSTDEAD_HAND_ITEMS := [NOBLE_SLEEVES, WIZARD_SLEEVES]
const RUSTDEAD_LEG_ITEMS := [PEASANT_TROUSERS, RANGER_LEGGINGS, NOBLE_TROUSERS, WIZARD_TROUSERS, KNIGHT_GREAVES]
const RUSTDEAD_FEET_ITEMS := [PEASANT_SHOES, RANGER_BOOTS, NOBLE_SHOES, WIZARD_SHOES, KNIGHT_SABATONS]
const RUSTDEAD_HEAD_ITEMS := [RANGER_HOOD]

@export var nest_type_definitions: Array[Resource] = [RUSTDEAD_NEST_TYPE]
@export var default_initial_activation_chance := 0.5
@export var minimum_initial_active_nests := 0
@export var repopulation_weekday_interval := 7
@export var maintenance_interval_seconds := DEFAULT_MAINTENANCE_INTERVAL_SECONDS
@export_range(1, 32, 1) var nest_maintenance_budget_per_tick := 8

var root_scene: Node
var _context: BootstrapContext
var world_time: Node
var settlement_controller: Node
var faction_controller: Node
var actor_query_controller: Node
var _nest_types_by_id: Dictionary = {}
var _markers_by_id: Dictionary = {}
var _nest_states: Dictionary = {}
var _nest_index := 0
var _realized_squad_actor_ids: Dictionary = {}
var _maintenance_remaining := 0.0
var _runtime_seed := 0
var _initialized := false


func initialize(context: BootstrapContext) -> void:
	_context = context
	root_scene = context.root_scene
	_ensure_runtime_seed()
	call_deferred("_try_initialize")


func _ready() -> void:
	add_to_group("nest_world_sim_plugin")
	if root_scene == null:
		root_scene = get_tree().current_scene
	_ensure_runtime_seed()
	call_deferred("_try_initialize")


func world_sim_tick(delta: float, _bridge: Node, _squads: Array, _reference: Vector3, _radius: float) -> void:
	if not _initialized:
		_try_initialize()
		return
	_maintenance_remaining -= delta
	if _maintenance_remaining > 0.0:
		return
	_maintenance_remaining = maxf(maintenance_interval_seconds, 0.1)
	_maintain_active_markers()


func serialize_state() -> Dictionary:
	_sync_nest_state_to_gecs()
	return _current_nest_state()


func apply_serialized_state(state: Dictionary) -> void:
	if state.is_empty():
		refresh_from_gecs_state()
		return
	_nest_index = int(state.get("nest_index", _nest_index))
	_nest_states = (state.get("nest_states", _nest_states) as Dictionary).duplicate(true)
	_sync_nest_state_to_gecs()


func refresh_from_gecs_state() -> void:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_nest_state"):
		return
	var state: Dictionary = bridge.call("get_nest_state")
	if state.is_empty():
		return
	_nest_index = int(state.get("nest_index", _nest_index))
	_nest_states = (state.get("nest_states", _nest_states) as Dictionary).duplicate(true)


func sync_nest_state() -> void:
	_sync_nest_state_to_gecs()


func get_world_sim_plugin_id() -> String:
	return "nests"


func get_debug_summary() -> Dictionary:
	return {
		"marker_count": _markers_by_id.size(),
		"active_count": _count_active_nests(),
		"nest_states": _nest_states.duplicate(true),
	}


func get_patrol_destination(actor: Node3D, job) -> Vector3:
	if actor == null or job == null:
		return Vector3.ZERO
	var marker_id := str(job.data.get("marker_id", ""))
	var marker := _markers_by_id.get(marker_id, null) as NestPlacementMarker
	if marker == null or not is_instance_valid(marker):
		return actor.global_position
	var state: Dictionary = _nest_states.get(marker_id, {})
	var nest_type := _get_nest_type(str(state.get("nest_type_id", "")))
	var radius := float(nest_type.get("wander_radius")) if nest_type != null else 500.0
	var pick_index := int(job.data.get("patrol_pick_index", 0))
	job.data["patrol_pick_index"] = pick_index + 1
	var actor_id := _actor_id(actor)
	var rng := _make_rng("patrol:%s:%s:%d" % [marker_id, actor_id, pick_index])
	var angle := rng.randf_range(0.0, TAU)
	var distance := sqrt(rng.randf()) * radius
	return marker.global_position + Vector3(cos(angle) * distance, 0.6, sin(angle) * distance)


func assign_assault_target(actor: HumanoidCharacter, job) -> bool:
	if actor == null or job == null:
		return false
	var target_id := str(job.data.get("target_settlement_id", ""))
	var target_anchor: Node3D = null
	if settlement_controller != null and settlement_controller.has_method("get_settlement_anchor"):
		target_anchor = settlement_controller.call("get_settlement_anchor", target_id) as Node3D
	if target_anchor == null:
		return false
	var residents: Array = target_anchor.call("get_resident_characters") if target_anchor.has_method("get_resident_characters") else []
	var best_target: HumanoidCharacter = null
	var best_distance := INF
	for resident_value in residents:
		var resident := resident_value as HumanoidCharacter
		if resident == null or not is_instance_valid(resident) or resident.life_state != NpcRules.LifeState.ALIVE:
			continue
		var distance := actor.global_position.distance_squared_to(resident.global_position)
		if distance < best_distance:
			best_distance = distance
			best_target = resident
	if best_target == null:
		return false
	return actor.assign_attack_target(best_target, false, true, true)


func get_assault_target_position(job) -> Vector3:
	if job == null:
		return Vector3.ZERO
	return job.data.get("target_position", Vector3.ZERO) if job.data.get("target_position", Vector3.ZERO) is Vector3 else Vector3.ZERO


func _try_initialize() -> void:
	if _initialized or root_scene == null or not is_inside_tree():
		return
	if _context == null:
		return
	world_time = _context.get_optional(WorldTimeController.SERVICE_ID)
	settlement_controller = _context.get_optional(SettlementController.SERVICE_ID)
	faction_controller = _context.get_optional(FactionController.SERVICE_ID)
	actor_query_controller = _context.get_optional(ActorQueryController.SERVICE_ID)
	if world_time == null or settlement_controller == null:
		return
	_register_nest_types()
	_register_nest_factions()
	refresh_from_gecs_state()
	_collect_markers()
	_ensure_marker_states()
	_spawn_active_nest_static_runtimes()
	_connect_time_signals()
	_sync_nest_state_to_gecs()
	_initialized = true


func _connect_time_signals() -> void:
	var day_changed_callable := Callable(self, "_on_day_changed")
	if world_time.has_signal("day_changed") and not world_time.is_connected("day_changed", day_changed_callable):
		world_time.connect("day_changed", day_changed_callable)


func _register_nest_types() -> void:
	_nest_types_by_id.clear()
	for definition in nest_type_definitions:
		if definition == null:
			continue
		var type_id := _resource_id(definition)
		if type_id.is_empty():
			continue
		_nest_types_by_id[type_id] = definition


func _register_nest_factions() -> void:
	if faction_controller == null or not faction_controller.has_method("register_faction"):
		return
	for definition in _nest_types_by_id.values():
		var faction_definition := definition.get("faction_definition") as Resource
		if faction_definition != null:
			faction_controller.call("register_faction", faction_definition)


func _collect_markers() -> void:
	_markers_by_id.clear()
	for node in get_tree().get_nodes_in_group("nest_placement_marker"):
		var marker := node as NestPlacementMarker
		if marker == null:
			continue
		var marker_id := marker.get_marker_id()
		if marker_id.is_empty():
			continue
		_markers_by_id[marker_id] = marker


func _ensure_marker_states() -> void:
	var changed := false
	for marker_id_value in _markers_by_id.keys():
		var marker_id := str(marker_id_value)
		if _nest_states.has(marker_id):
			continue
		_nest_states[marker_id] = _create_initial_marker_state(_markers_by_id[marker_id])
		changed = true
	if changed:
		changed = _ensure_minimum_initial_active_nests() or changed
	if changed:
		_sync_nest_state_to_gecs()


func _create_initial_marker_state(marker: NestPlacementMarker) -> Dictionary:
	var marker_id := marker.get_marker_id()
	var state := _base_marker_state(marker)
	var nest_type := _pick_nest_type(marker, _make_rng("initial_type:%s" % marker_id))
	if nest_type == null:
		return state
	var activation_chance := marker.get_activation_chance(float(nest_type.get("default_initial_activation_chance")))
	var activation_rng := _make_rng("initial_active:%s" % marker_id)
	if activation_rng.randf() > activation_chance:
		return state
	_activate_marker_state(state, marker, nest_type, _make_rng("initial_state:%s" % marker_id), _get_day_index())
	return state


func _ensure_minimum_initial_active_nests() -> bool:
	var minimum_count := _get_minimum_initial_active_nests()
	if minimum_count <= 0 or _count_active_nests() >= minimum_count:
		return false
	var candidates: Array[String] = []
	for marker_id_value in _markers_by_id.keys():
		var marker_id := str(marker_id_value)
		var state: Dictionary = _nest_states.get(marker_id, {}) if _nest_states.get(marker_id, {}) is Dictionary else {}
		if bool(state.get("active", false)) or int(state.get("destroyed_day", -1)) >= 0:
			continue
		if _pick_nest_type(_markers_by_id[marker_id], _make_rng("minimum_candidate_type:%s" % marker_id)) != null:
			candidates.append(marker_id)
	_shuffle_marker_ids(candidates, _make_rng("minimum_initial_active_nests"))
	var changed := false
	for marker_id in candidates:
		if _count_active_nests() >= minimum_count:
			break
		var marker := _markers_by_id.get(marker_id, null) as NestPlacementMarker
		if marker == null:
			continue
		var nest_type := _pick_nest_type(marker, _make_rng("minimum_type:%s" % marker_id))
		if nest_type == null:
			continue
		var state: Dictionary = _nest_states.get(marker_id, _base_marker_state(marker))
		_activate_marker_state(state, marker, nest_type, _make_rng("minimum_state:%s" % marker_id), _get_day_index())
		_nest_states[marker_id] = state
		changed = true
	return changed


func _shuffle_marker_ids(marker_ids: Array[String], rng: RandomNumberGenerator) -> void:
	for index in range(marker_ids.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var value := marker_ids[index]
		marker_ids[index] = marker_ids[swap_index]
		marker_ids[swap_index] = value


func _base_marker_state(marker: NestPlacementMarker) -> Dictionary:
	return {
		"marker_id": marker.get_marker_id(),
		"region_id": marker.get_region_id(),
		"active": false,
		"nest_type_id": "",
		"size_id": marker.get_size_id(),
		"destroyed_day": -1,
		"next_repopulation_day": -1,
		"population_target": 0,
		"patrol_squad_count": 0,
		"patrol_squad_ids": [],
		"patrol_squad_member_counts": {},
		"guard_squad_id": "",
		"guard_count": 0,
		"attack_squad_ids": [],
		"actor_ids": [],
		"visual_scene_index": -1,
		"scrap_pile_specs": [],
		"last_attack_roll_day": -1,
	}


func _activate_marker_state(state: Dictionary, marker: NestPlacementMarker, nest_type: Resource, rng: RandomNumberGenerator, day_index: int) -> void:
	var size_id := marker.get_size_id()
	var population_range: Vector2i = nest_type.call("get_population_range", size_id)
	var population_target := rng.randi_range(population_range.x, population_range.y)
	state["active"] = true
	state["nest_type_id"] = _resource_id(nest_type)
	state["size_id"] = size_id
	state["destroyed_day"] = -1
	state["next_repopulation_day"] = -1
	state["population_target"] = population_target
	# alive_count is the surviving headcount the world tracks for this nest. It starts at the
	# rolled target, drops as the player kills rustdead (kills are permanent until repopulation),
	# and is what a re-realized nest respawns — so walking away and back doesn't resurrect anyone.
	state["alive_count"] = population_target
	state["patrol_squad_count"] = int(nest_type.call("get_patrol_squad_count", size_id))
	state["patrol_squad_ids"] = []
	state["patrol_squad_member_counts"] = {}
	state["guard_squad_id"] = ""
	state["guard_count"] = 0
	state["attack_squad_ids"] = []
	state["actor_ids"] = []
	state["visual_scene_index"] = _pick_visual_scene_index(nest_type, rng)
	state["scrap_pile_specs"] = _create_scrap_pile_specs(marker, rng)
	_clear_nest_scrap_runtime(marker)
	state["last_attack_roll_day"] = day_index
	_register_world_sim_squads(marker, state)


## Seed this nest's patrol squads into the world-sim squad layer. These GECS records own
## offscreen patrol truth; live bodies exist only while each squad dot is near the player.
func _register_world_sim_squads(marker: NestPlacementMarker, state: Dictionary) -> void:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("upsert_world_sim_squad"):
		return
	var marker_id := marker.get_marker_id()
	var home := marker.global_position
	var faction_id := str(state.get("nest_type_id", "nest"))
	var nest_type := _get_nest_type(str(state.get("nest_type_id", "")))
	var count := int(state.get("patrol_squad_count", 0))
	var member_counts := _roll_patrol_squad_member_counts(marker, state)
	var patrol_squad_ids: Array = []
	var patrol_total := 0
	for i in range(count):
		var squad_id := _nest_patrol_squad_id(marker_id, i)
		var member_count := int(member_counts.get(squad_id, 0))
		patrol_squad_ids.append(squad_id)
		patrol_total += member_count
		_ensure_nest_squad_people(marker_id, state, nest_type, squad_id, member_count, home)
		bridge.upsert_world_sim_squad({
			"squad_id": squad_id,
			"owner_id": marker_id,
			"owner_kind": "nest",
			"faction_id": faction_id,
			"objective": "patrol",
			"position": home,
			"target_position": home,
			"home_position": home,
			"patrol_radius": 45.0,
			"move_speed": 3.0,
			"member_count": member_count,
			"state": "active",
		})
		if bridge.has_method("log_world_event"):
			bridge.log_world_event("rustdead", "patrol squad %s mustered at nest %s" % [squad_id, marker_id], {})
	var guard_count := maxi(0, int(state.get("population_target", 0)) - patrol_total)
	var guard_squad_id := _nest_guard_squad_id(marker_id)
	if guard_count > 0:
		_ensure_nest_squad_people(marker_id, state, nest_type, guard_squad_id, guard_count, home)
		bridge.upsert_world_sim_squad({
			"squad_id": guard_squad_id,
			"owner_id": marker_id,
			"owner_kind": "nest",
			"faction_id": faction_id,
			"objective": "guard",
			"position": home,
			"target_position": home,
			"home_position": home,
			"patrol_radius": 0.0,
			"move_speed": 0.0,
			"member_count": guard_count,
			"state": "active",
		})
	state["patrol_squad_ids"] = patrol_squad_ids
	state["patrol_squad_member_counts"] = member_counts
	state["guard_squad_id"] = guard_squad_id if guard_count > 0 else ""
	state["guard_count"] = guard_count


func _roll_patrol_squad_member_counts(marker: NestPlacementMarker, state: Dictionary) -> Dictionary:
	var nest_type := _get_nest_type(str(state.get("nest_type_id", "")))
	if nest_type == null:
		return {}
	var marker_id := marker.get_marker_id()
	var size_id := str(state.get("size_id", marker.get_size_id()))
	var squad_count := maxi(0, int(state.get("patrol_squad_count", 0)))
	var total_count := maxi(0, int(state.get("population_target", 0)))
	var patrol_size_range: Vector2i = nest_type.call("get_patrol_squad_size_range", size_id)
	var patrol_total := mini(total_count, squad_count * patrol_size_range.y)
	var remaining_patrol := patrol_total
	var result := {}
	for squad_index in range(squad_count):
		var squad_id := _nest_patrol_squad_id(marker_id, squad_index)
		var squads_left := squad_count - int(squad_index)
		var min_remaining_after := maxi(squads_left - 1, 0) * patrol_size_range.x
		var available_for_squad := maxi(remaining_patrol - min_remaining_after, 0)
		if available_for_squad <= 0:
			result[squad_id] = 0
			continue
		var squad_min := patrol_size_range.x if remaining_patrol >= patrol_size_range.x else 1
		var squad_size := clampi(ceili(float(remaining_patrol) / float(maxi(squads_left, 1))), squad_min, patrol_size_range.y)
		squad_size = mini(squad_size, available_for_squad)
		result[squad_id] = squad_size
		remaining_patrol -= squad_size
	return result


func _spawn_active_nest_static_runtimes() -> void:
	for marker_id_value in _nest_states.keys():
		var marker_id := str(marker_id_value)
		var marker := _markers_by_id.get(marker_id, null) as NestPlacementMarker
		if marker == null:
			continue
		var state: Dictionary = _nest_states[marker_id]
		if bool(state.get("active", false)):
			_spawn_static_runtime_for_state(marker, state)
			_nest_states[marker_id] = state


func _spawn_static_runtime_for_state(marker: NestPlacementMarker, state: Dictionary) -> bool:
	var had_visual := marker.get_node_or_null(NEST_VISUAL_NAME) != null
	var had_scrap := marker.get_node_or_null(NEST_SCRAP_ROOT_NAME) != null
	_spawn_nest_visual(marker, state)
	_spawn_nest_scrap_piles(marker, state)
	var changed := not had_visual and marker.get_node_or_null(NEST_VISUAL_NAME) != null
	changed = changed or (not had_scrap and marker.get_node_or_null(NEST_SCRAP_ROOT_NAME) != null)
	if changed:
		_sync_nest_state_to_gecs()
	return changed


func _reissue_patrol_jobs_for_marker(marker_id: String) -> void:
	var marker := _markers_by_id.get(marker_id, null) as NestPlacementMarker
	if marker == null or not is_instance_valid(marker):
		return
	var state: Dictionary = _nest_states.get(marker_id, {})
	if state.is_empty() or not bool(state.get("active", false)):
		return
	_reissue_patrol_jobs(marker, state)


func _spawn_nest_visual(marker: NestPlacementMarker, state: Dictionary) -> void:
	if marker.get_node_or_null(NEST_VISUAL_NAME) != null:
		return
	var nest_type := _get_nest_type(str(state.get("nest_type_id", "")))
	if nest_type == null:
		return
	var visual_scene_index := int(state.get("visual_scene_index", -1))
	if visual_scene_index < 0:
		visual_scene_index = _pick_visual_scene_index(nest_type, _make_rng("visual_scene:%s" % marker.get_marker_id()))
		state["visual_scene_index"] = visual_scene_index
		_sync_nest_state_to_gecs()
	var visual_scene: PackedScene = null
	if nest_type.has_method("get_visual_scene"):
		visual_scene = nest_type.call("get_visual_scene", visual_scene_index) as PackedScene
	if visual_scene == null:
		return
	var visual := visual_scene.instantiate()
	if visual == null:
		return
	visual.name = NEST_VISUAL_NAME
	marker.add_child(visual)
	if visual is Node3D:
		var visual_3d := visual as Node3D
		visual_3d.position = Vector3.ZERO
		visual_3d.rotation = Vector3.ZERO


func _pick_visual_scene_index(nest_type: Resource, rng: RandomNumberGenerator) -> int:
	if nest_type == null or not nest_type.has_method("get_visual_scene_count"):
		return -1
	var scene_count := int(nest_type.call("get_visual_scene_count"))
	if scene_count <= 0:
		return -1
	return rng.randi_range(0, scene_count - 1)


func _spawn_nest_scrap_piles(marker: NestPlacementMarker, state: Dictionary) -> void:
	if str(state.get("nest_type_id", "")) != "rustdead":
		return
	if marker.get_node_or_null(NEST_SCRAP_ROOT_NAME) != null:
		return
	var specs: Array = state.get("scrap_pile_specs", []) if state.get("scrap_pile_specs", []) is Array else []
	if specs.is_empty():
		specs = _create_scrap_pile_specs(marker, _make_rng("scrap_specs:%s" % marker.get_marker_id()))
		state["scrap_pile_specs"] = specs
	var scrap_root := Node3D.new()
	scrap_root.name = NEST_SCRAP_ROOT_NAME
	marker.add_child(scrap_root)
	for index in range(specs.size()):
		var spec: Dictionary = specs[index] if specs[index] is Dictionary else {}
		var size_id := str(spec.get("size_id", SCRAP_SIZE_SMALL))
		var nest_size_id := str(state.get("size_id", SCRAP_SIZE_SMALL))
		var scene := _scrap_scene_for_size(size_id)
		if scene == null:
			continue
		var pile := scene.instantiate() as ScavengingResourceNode
		if pile == null:
			continue
		var scrap_id := str(spec.get("scrap_id", "%s.scrap.%02d" % [marker.get_marker_id(), index + 1]))
		pile.name = scrap_id.replace(".", "_")
		pile.resource_node_id = scrap_id
		pile.position = spec.get("offset", Vector3.ZERO) if spec.get("offset", Vector3.ZERO) is Vector3 else Vector3.ZERO
		pile.rotation.y = float(spec.get("yaw", 0.0))
		_configure_nest_scrap_pile(pile, size_id, nest_size_id)
		scrap_root.add_child(pile)


func _clear_nest_scrap_runtime(marker: NestPlacementMarker) -> void:
	var scrap_root := marker.get_node_or_null(NEST_SCRAP_ROOT_NAME)
	if scrap_root != null:
		scrap_root.queue_free()


func _create_scrap_pile_specs(marker: NestPlacementMarker, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var nest_size_id := marker.get_size_id()
	var count_range := _scrap_count_range_for_nest_size(nest_size_id)
	var count := rng.randi_range(count_range.x, count_range.y)
	var guaranteed_small_index := rng.randi_range(0, count - 1)
	var guaranteed_medium_index := _pick_unique_index(rng, count, [guaranteed_small_index])
	var guaranteed_large_indices: Array[int] = []
	if nest_size_id == SCRAP_SIZE_MEDIUM:
		guaranteed_large_indices.append(_pick_unique_index(rng, count, [guaranteed_small_index, guaranteed_medium_index]))
	elif nest_size_id == SCRAP_SIZE_LARGE:
		guaranteed_large_indices.append(_pick_unique_index(rng, count, [guaranteed_small_index, guaranteed_medium_index]))
		guaranteed_large_indices.append(_pick_unique_index(rng, count, [guaranteed_small_index, guaranteed_medium_index, guaranteed_large_indices[0]]))
	var offsets: Array[Vector3] = []
	var specs: Array[Dictionary] = []
	for index in range(count):
		var size_id := SCRAP_SIZE_SMALL
		if guaranteed_large_indices.has(index):
			size_id = SCRAP_SIZE_LARGE
		elif index == guaranteed_medium_index:
			size_id = SCRAP_SIZE_MEDIUM if nest_size_id != SCRAP_SIZE_SMALL else _pick_medium_or_larger_scrap_size(rng)
		elif index == guaranteed_small_index:
			size_id = SCRAP_SIZE_SMALL
		else:
			size_id = _pick_weighted_scrap_size(rng, nest_size_id)
		var offset := _pick_scrap_offset(rng, offsets)
		offsets.append(offset)
		specs.append({
			"scrap_id": "%s.scrap.%02d" % [marker.get_marker_id(), index + 1],
			"size_id": size_id,
			"offset": offset,
			"yaw": rng.randf_range(0.0, TAU),
		})
	return specs


func _scrap_count_range_for_nest_size(nest_size_id: String) -> Vector2i:
	match nest_size_id:
		SCRAP_SIZE_MEDIUM:
			return RUSTDEAD_MEDIUM_SCRAP_COUNT_RANGE
		SCRAP_SIZE_LARGE:
			return RUSTDEAD_LARGE_SCRAP_COUNT_RANGE
		_:
			return RUSTDEAD_SMALL_SCRAP_COUNT_RANGE


func _pick_unique_index(rng: RandomNumberGenerator, count: int, used_indices: Array) -> int:
	if count <= 1:
		return 0
	for attempt in range(16):
		var candidate := rng.randi_range(0, count - 1)
		if not used_indices.has(candidate):
			return candidate
	for index in range(count):
		if not used_indices.has(index):
			return index
	return 0


func _pick_scrap_offset(rng: RandomNumberGenerator, existing_offsets: Array[Vector3]) -> Vector3:
	var fallback := Vector3.ZERO
	for attempt in range(18):
		var angle := rng.randf_range(0.0, TAU)
		var distance := rng.randf_range(RUSTDEAD_SCRAP_MIN_RADIUS, RUSTDEAD_SCRAP_MAX_RADIUS)
		var candidate := Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		fallback = candidate
		var separated := true
		for existing in existing_offsets:
			if Vector2(candidate.x - existing.x, candidate.z - existing.z).length() < RUSTDEAD_SCRAP_MIN_SEPARATION:
				separated = false
				break
		if separated:
			return candidate
	return fallback


func _pick_weighted_scrap_size(rng: RandomNumberGenerator, nest_size_id: String) -> String:
	var roll := rng.randf()
	match nest_size_id:
		SCRAP_SIZE_MEDIUM:
			if roll < 0.45:
				return SCRAP_SIZE_SMALL
			if roll < 0.82:
				return SCRAP_SIZE_MEDIUM
			return SCRAP_SIZE_LARGE
		SCRAP_SIZE_LARGE:
			if roll < 0.22:
				return SCRAP_SIZE_SMALL
			if roll < 0.58:
				return SCRAP_SIZE_MEDIUM
			return SCRAP_SIZE_LARGE
		_:
			if roll < 0.75:
				return SCRAP_SIZE_SMALL
			if roll < 0.95:
				return SCRAP_SIZE_MEDIUM
			return SCRAP_SIZE_LARGE


func _pick_medium_or_larger_scrap_size(rng: RandomNumberGenerator) -> String:
	return SCRAP_SIZE_MEDIUM if rng.randf() < 0.85 else SCRAP_SIZE_LARGE


func _scrap_scene_for_size(size_id: String) -> PackedScene:
	match size_id:
		SCRAP_SIZE_MEDIUM:
			return SCRAP_PILE_SCENE
		SCRAP_SIZE_LARGE:
			return HALF_BURIED_ROBOT_WRECK_SCENE
		_:
			return TWISTED_SCRAP_HEAP_SCENE


func _configure_nest_scrap_pile(pile: ScavengingResourceNode, size_id: String, nest_size_id: String) -> void:
	pile.randomize_charges_on_ready = true
	pile.show_charge_count = false
	match size_id:
		SCRAP_SIZE_MEDIUM:
			pile.pile_size = ScavengingResourceNode.PileSize.MEDIUM
			pile.scavenging_difficulty = 12
			pile.scavenge_noise_radius = 12.0
			pile.slot_distance = 3.1
			pile.scale = Vector3.ONE * 0.9
		SCRAP_SIZE_LARGE:
			pile.pile_size = ScavengingResourceNode.PileSize.LARGE
			pile.scavenging_difficulty = 24
			pile.scavenge_noise_radius = 16.0
			pile.slot_distance = 3.4
			pile.scale = Vector3.ONE
		_:
			pile.pile_size = ScavengingResourceNode.PileSize.SMALL
			pile.scavenging_difficulty = 8
			pile.scavenge_noise_radius = 9.0
			pile.slot_distance = 2.7
			pile.scale = Vector3.ONE * 0.72
	_apply_nest_size_scrap_rewards(pile, nest_size_id)


func _apply_nest_size_scrap_rewards(pile: ScavengingResourceNode, nest_size_id: String) -> void:
	var bonus := _nest_size_bonus(nest_size_id)
	if bonus <= 0:
		return
	pile.scavenging_difficulty += bonus * 4
	pile.robotics_difficulty += bonus * 4
	pile.scavenge_noise_radius += float(bonus) * 2.0
	pile.min_useful_chance = clampf(pile.min_useful_chance + float(bonus) * 0.02, 0.0, 0.35)
	pile.max_useful_chance = clampf(pile.max_useful_chance + float(bonus) * 0.04, 0.0, 0.95)
	pile.base_rare_chance = clampf(pile.base_rare_chance + float(bonus) * 0.025, 0.0, 0.45)
	pile.max_rare_chance = clampf(pile.max_rare_chance + float(bonus) * 0.08, 0.0, 0.55)


func _nest_size_bonus(nest_size_id: String) -> int:
	match nest_size_id:
		SCRAP_SIZE_MEDIUM:
			return 1
		SCRAP_SIZE_LARGE:
			return 2
		_:
			return 0


func is_nest_squad_realized(squad_id: String) -> bool:
	return _realized_squad_actor_ids.has(squad_id)


func is_world_sim_squad_realized(squad_id: String) -> bool:
	return is_nest_squad_realized(squad_id)


func update_lod_swap(bridge: Node, squads: Array, reference: Vector3, radius: float) -> Dictionary:
	var realized_map: Dictionary = {}
	for record in squads:
		if str(record.get("owner_kind", "")) != "nest":
			continue
		var squad_id := str(record.get("squad_id", ""))
		if squad_id.is_empty():
			continue
		var position: Vector3 = record.get("position", Vector3.ZERO)
		var realized := is_nest_squad_realized(squad_id)
		if realized and _live_nest_squad_actors(squad_id).is_empty():
			var dead_survivors := derealize_nest_squad(squad_id)
			realized = false
			record["member_count"] = dead_survivors
			_update_state_squad_count(str(record.get("owner_id", "")), squad_id, dead_survivors)
			if bridge.has_method("remove_world_sim_squad"):
				bridge.remove_world_sim_squad(squad_id)
			_check_destroyed_from_squad_counts(str(record.get("owner_id", "")))
			realized_map[squad_id] = false
			continue
		var threshold := radius + (NEST_LOD_HYSTERESIS if realized else 0.0)
		var near := _flat_distance(position, reference) <= threshold
		if near and not realized and int(record.get("member_count", 0)) > 0:
			realize_nest_squad(record)
			realized = is_nest_squad_realized(squad_id)
			if realized and bridge.has_method("log_world_event"):
				bridge.log_world_event("rustdead", "nest squad %s realized" % squad_id, {})
		elif not near and realized:
			var survivors := derealize_nest_squad(squad_id)
			realized = false
			record["member_count"] = survivors
			_update_state_squad_count(str(record.get("owner_id", "")), squad_id, survivors)
			if survivors <= 0:
				if bridge.has_method("remove_world_sim_squad"):
					bridge.remove_world_sim_squad(squad_id)
				_check_destroyed_from_squad_counts(str(record.get("owner_id", "")))
			elif bridge.has_method("upsert_world_sim_squad"):
				bridge.upsert_world_sim_squad(record)
		if realized:
			record["position"] = drive_realized_squad(record)
			if bridge.has_method("upsert_world_sim_squad"):
				bridge.upsert_world_sim_squad(record)
		realized_map[squad_id] = realized
	return realized_map


func realize_nest_squad(record: Dictionary) -> void:
	var squad_id := str(record.get("squad_id", ""))
	var marker_id := str(record.get("owner_id", ""))
	if squad_id.is_empty() or marker_id.is_empty() or is_nest_squad_realized(squad_id):
		return
	var marker := _markers_by_id.get(marker_id, null) as NestPlacementMarker
	var state: Dictionary = _nest_states.get(marker_id, {})
	if marker == null or state.is_empty() or not bool(state.get("active", false)):
		return
	var nest_type := _get_nest_type(str(state.get("nest_type_id", "")))
	if nest_type == null:
		return
	_spawn_static_runtime_for_state(marker, state)
	var actor_ids: Array = state.get("actor_ids", []) if state.get("actor_ids", []) is Array else []
	var squad_actor_ids: Array = []
	var count := maxi(0, int(record.get("member_count", 0)))
	var origin: Vector3 = record.get("position", marker.global_position)
	var population := _get_population_controller()
	var person_ids_by_squad: Dictionary = state.get("person_ids_by_squad", {})
	var person_ids: Array = (person_ids_by_squad.get(squad_id, []) as Array).duplicate()
	if person_ids.is_empty() and population != null and population.has_method("get_actor_record"):
		for actor_id_value in actor_ids:
			var prior_record: Dictionary = population.call("get_actor_record", str(actor_id_value))
			if str(prior_record.get("squad_name", "")) == squad_id:
				person_ids.append(str(actor_id_value))
	var living_person_ids: Array = []
	for actor_id_value in person_ids:
		var actor_id := str(actor_id_value)
		var person_record: Dictionary = population.call("get_actor_record", actor_id) if population != null and population.has_method("get_actor_record") else {}
		if person_record.is_empty() or int(person_record.get("life_state", NpcRules.LifeState.ALIVE)) != NpcRules.LifeState.DEAD:
			living_person_ids.append(actor_id)
	while living_person_ids.size() < count:
		var sequence := int(state.get("next_person_sequence", 0)) + 1
		state["next_person_sequence"] = sequence
		var actor_id := "nest.%s.%s.person.%06d" % [str(state.get("marker_id", marker.get_marker_id())), _stable_id_slug(squad_id), sequence]
		person_ids.append(actor_id)
		living_person_ids.append(actor_id)
	person_ids_by_squad[squad_id] = person_ids
	state["person_ids_by_squad"] = person_ids_by_squad
	for member_index in range(mini(count, living_person_ids.size())):
		var actor_id := str(living_person_ids[member_index])
		var actor := _spawn_nest_actor(marker, state, nest_type, squad_id, member_index + 1, origin, actor_id)
		if actor == null:
			continue
		if not actor_ids.has(actor.stable_id):
			actor_ids.append(actor.stable_id)
		squad_actor_ids.append(actor.stable_id)
		if str(record.get("objective", "")) == "attack":
			call_deferred("_request_assault_job_for_actor", actor.stable_id, marker_id, str(record.get("target_settlement_id", "")), record.get("target_position", marker.global_position))
	state["actor_ids"] = actor_ids
	_realized_squad_actor_ids[squad_id] = squad_actor_ids
	_nest_states[marker_id] = state
	call_deferred("_reissue_patrol_jobs_for_marker", marker_id)
	_sync_nest_state_to_gecs()


func derealize_nest_squad(squad_id: String) -> int:
	var actor_ids: Array = _realized_squad_actor_ids.get(squad_id, []) if _realized_squad_actor_ids.get(squad_id, []) is Array else []
	var survivors := 0
	var marker_id := _marker_id_from_squad_id(squad_id)
	var state: Dictionary = _nest_states.get(marker_id, {})
	var population := _get_population_controller()
	for actor_id_value in actor_ids:
		var actor := _find_actor_by_id(str(actor_id_value)) as HumanoidCharacter
		if actor != null and is_instance_valid(actor):
			if actor.life_state != NpcRules.LifeState.DEAD:
				survivors += 1
			if population != null and population.has_method("unregister_actor"):
				population.call("unregister_actor", actor)
			actor.queue_free()
	_realized_squad_actor_ids.erase(squad_id)
	if not state.is_empty():
		_nest_states[marker_id] = state
		_sync_nest_state_to_gecs()
	return survivors


func drive_realized_squad(record: Dictionary) -> Vector3:
	var actors := _live_nest_squad_actors(str(record.get("squad_id", "")))
	if actors.is_empty():
		return record.get("position", Vector3.ZERO)
	var sum := Vector3.ZERO
	for actor in actors:
		sum += actor.global_position
	return sum / float(actors.size())


func _spawn_nest_actor(marker: NestPlacementMarker, state: Dictionary, nest_type: Resource, squad_id: String, member_index: int, spawn_origin := Vector3.INF, actor_id := "") -> HumanoidCharacter:
	var actor_script := nest_type.get("actor_script") as Script
	if actor_script == null:
		return null
	var actor := actor_script.new() as HumanoidCharacter
	if actor == null:
		return null
	var marker_id := str(state.get("marker_id", marker.get_marker_id()))
	if actor_id.is_empty():
		actor_id = "nest.%s.%s.%03d" % [marker_id, _stable_id_slug(squad_id), member_index]
	actor.name = actor_id.replace(".", "_")
	actor.member_name = "Rustdead" if str(state.get("nest_type_id", "")) == "rustdead" else "Nest Spawn %03d" % member_index
	actor.stable_id = actor_id
	actor.faction_name = str(nest_type.call("get_faction_id")) if nest_type.has_method("get_faction_id") else ""
	actor.squad_name = squad_id
	actor.world_squad_id = squad_id
	actor.hostile_factions = _non_nest_hostile_factions(actor.faction_name)
	actor.combat_stance = NpcRules.CombatStance.AGGRESSIVE
	var origin := marker.global_position if spawn_origin == Vector3.INF else spawn_origin
	actor.position = _spawn_position_near_origin(origin, marker_id, squad_id, member_index)
	actor.rotation.y = _make_rng("actor_yaw:%s:%s:%d" % [marker_id, squad_id, member_index]).randf_range(0.0, TAU)
	if str(state.get("nest_type_id", "")) == "rustdead":
		_configure_rustdead_actor(actor, marker_id, member_index)
	_add_basic_actor_children(actor, Color(0.42, 0.08, 0.07, 1.0))
	var population := _get_population_controller()
	var existing_record: Dictionary = population.call("get_actor_record", actor_id) if population != null and population.has_method("get_actor_record") else {}
	if not existing_record.is_empty() and population.has_method("apply_record_to_actor"):
		population.call("apply_record_to_actor", actor, existing_record)
	_ensure_actor_root().add_child(actor)
	if actor.has_method("request_spawn_grounding_refresh"):
		actor.call("request_spawn_grounding_refresh", 8)
	return actor


func _configure_rustdead_actor(actor: HumanoidCharacter, marker_id: String, member_index: int) -> void:
	var rng := _make_rng("rustdead_actor:%s:%d" % [marker_id, member_index])
	var body_type := VISUAL_BODY_TYPE_FEMALE if member_index % 3 == 1 else VISUAL_BODY_TYPE_MALE
	var marker_state: Dictionary = _nest_states.get(marker_id, {})
	var nest_size_id := str(marker_state.get("size_id", SCRAP_SIZE_SMALL))
	var tier := RUSTDEAD_TIER_LIBRARY.pick_tier_for_nest_size(nest_size_id, rng)
	actor.member_name = str(tier.get("display_name")) if tier != null else "Rustdead"
	if actor.has_method("set_rustdead_tier_definition"):
		actor.call("set_rustdead_tier_definition", tier)
	actor.appearance_data = _make_appearance(RUSTDEAD_RACE, body_type, RUSTDEAD_TIER_LIBRARY.pick_skin_color(tier, rng))
	RUSTDEAD_TIER_LIBRARY.apply_hair_for_tier(actor.appearance_data, tier, rng, body_type)
	actor.starting_skill_levels = RUSTDEAD_TIER_LIBRARY.roll_skill_levels(tier, rng)
	actor.starting_equipment = _rustdead_clothes(rng, member_index)
	actor.max_hp = RUSTDEAD_TIER_LIBRARY.roll_max_hp(tier, rng)
	actor.hp = actor.max_hp
	actor.base_attack_damage = 12.0 + float(member_index % 3) * 0.5
	actor.attack_cut_ratio = 0.05
	actor.base_dodge_chance = 0.025
	actor.base_block_chance = 0.0
	actor.attack_cooldown_seconds = 1.45
	actor.move_speed = 2.55
	actor.aggressive_scan_radius = 18.0
	actor.assist_scan_radius = 18.0
	actor.combat_squad_assist_radius = 80.0


func _spawn_position_near_origin(origin: Vector3, marker_id: String, squad_id: String, member_index: int) -> Vector3:
	var rng := _make_rng("spawn_position:%s:%s:%d" % [marker_id, squad_id, member_index])
	var angle := rng.randf_range(0.0, TAU)
	var distance := rng.randf_range(3.0, 9.0)
	return origin + Vector3(cos(angle) * distance, 0.6, sin(angle) * distance)


func _maintain_active_markers() -> void:
	var changed := false
	var marker_ids := _nest_states.keys()
	if marker_ids.is_empty():
		return
	var budget := mini(maxi(1, int(nest_maintenance_budget_per_tick)), marker_ids.size())
	var processed := 0
	while processed < budget:
		if _nest_index >= marker_ids.size():
			_nest_index = 0
		var marker_id := str(marker_ids[_nest_index])
		_nest_index += 1
		processed += 1
		var marker := _markers_by_id.get(marker_id, null) as NestPlacementMarker
		if marker == null:
			continue
		var state: Dictionary = _nest_states[marker_id]
		if not bool(state.get("active", false)):
			continue
		if _spawn_static_runtime_for_state(marker, state):
			changed = true
		_nest_states[marker_id] = state
	if changed:
		_sync_nest_state_to_gecs()


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _reissue_patrol_jobs(marker: NestPlacementMarker, state: Dictionary) -> void:
	var patrol_squad_ids: Array = state.get("patrol_squad_ids", []) if state.get("patrol_squad_ids", []) is Array else []
	var patrol_leader_ids := _patrol_leader_ids_by_squad(state, patrol_squad_ids)
	for actor in _live_nest_actors(state):
		if actor == null or not is_instance_valid(actor) or actor.life_state != NpcRules.LifeState.ALIVE:
			continue
		if actor.get_current_combat_target() != null:
			continue
		if actor.has_active_ai_job_from_source(NEST_PATROL_SOURCE_ID) or actor.has_active_ai_job_from_source(NEST_ASSAULT_SOURCE_ID):
			continue
		if not patrol_squad_ids.has(actor.world_squad_id):
			continue
		if str(patrol_leader_ids.get(actor.world_squad_id, "")) != actor.stable_id:
			continue
		actor.request_ai_job(_make_patrol_job(actor, marker, state))


func _patrol_leader_ids_by_squad(state: Dictionary, patrol_squad_ids: Array) -> Dictionary:
	var leaders := {}
	for actor_id_value in state.get("actor_ids", []):
		var actor := _find_actor_by_id(str(actor_id_value)) as HumanoidCharacter
		if actor == null or not is_instance_valid(actor) or actor.life_state != NpcRules.LifeState.ALIVE:
			continue
		if patrol_squad_ids.has(actor.world_squad_id) and not leaders.has(actor.world_squad_id):
			leaders[actor.world_squad_id] = actor.stable_id
	return leaders


func _make_patrol_job(actor: HumanoidCharacter, marker: NestPlacementMarker, _state: Dictionary):
	var job = AI_JOB_SCRIPT.new()
	job.job_type = AI_JOB_SCRIPT.JobType.PATROL
	job.priority = AI_JOB_SCRIPT.priority_for_type(job.job_type)
	job.source_id = NEST_PATROL_SOURCE_ID
	job.source = self
	job.target = marker
	job.target_id = marker.get_marker_id()
	job.package_id = "nest_patrol:%s" % marker.get_marker_id()
	job.debug_label = "Patrol Nest"
	job.debug_reason = "Nest squad patrol"
	job.origin_position = marker.global_position
	job.data = {
		"marker_id": marker.get_marker_id(),
		"squad_id": actor.world_squad_id,
		"arrival_distance": 3.0,
		"pause_min_seconds": 5.0,
		"pause_max_seconds": 14.0,
	}
	job.steps = [AI_PATROL_STEP_SCRIPT.new()]
	return job


func _make_assault_job(_actor: HumanoidCharacter, marker: NestPlacementMarker, _state: Dictionary, target_settlement_id: String, target_position: Vector3):
	var job = AI_JOB_SCRIPT.new()
	job.job_type = AI_JOB_SCRIPT.JobType.NEST_ASSAULT
	job.priority = AI_JOB_SCRIPT.priority_for_type(job.job_type)
	job.source_id = NEST_ASSAULT_SOURCE_ID
	job.source = self
	job.target = settlement_controller.call("get_settlement_anchor", target_settlement_id) if settlement_controller != null and settlement_controller.has_method("get_settlement_anchor") else null
	job.target_id = target_settlement_id
	job.package_id = "nest_assault:%s:%s" % [marker.get_marker_id(), target_settlement_id]
	job.debug_label = "Attack Settlement"
	job.debug_reason = "Nest attack squad"
	job.origin_position = marker.global_position
	job.data = {
		"marker_id": marker.get_marker_id(),
		"target_settlement_id": target_settlement_id,
		"target_position": target_position,
		"arrival_distance": 8.0,
	}
	job.steps = [AI_NEST_ASSAULT_STEP_SCRIPT.new()]
	return job


func _on_day_changed(day_index: int) -> void:
	_process_daily_attack_rolls(day_index)
	if repopulation_weekday_interval > 0 and day_index > 0 and day_index % repopulation_weekday_interval == 0:
		_process_weekly_repopulation(day_index)


func _process_daily_attack_rolls(day_index: int) -> void:
	var changed := false
	for marker_id_value in _nest_states.keys():
		var marker_id := str(marker_id_value)
		var state: Dictionary = _nest_states[marker_id]
		if not bool(state.get("active", false)) or int(state.get("last_attack_roll_day", -1)) == day_index:
			continue
		state["last_attack_roll_day"] = day_index
		var marker := _markers_by_id.get(marker_id, null) as NestPlacementMarker
		var nest_type := _get_nest_type(str(state.get("nest_type_id", "")))
		if marker == null or nest_type == null:
			_nest_states[marker_id] = state
			changed = true
			continue
		var attack_rng := _make_rng("daily_attack:%s:%d" % [marker_id, day_index])
		if attack_rng.randf() <= float(nest_type.get("daily_attack_chance")):
			_start_settlement_attack(marker, state, nest_type, day_index, attack_rng)
		_nest_states[marker_id] = state
		changed = true
	if changed:
		_sync_nest_state_to_gecs()


func _start_settlement_attack(marker: NestPlacementMarker, state: Dictionary, nest_type: Resource, day_index: int, rng: RandomNumberGenerator) -> bool:
	var target := _find_attack_target_settlement(marker.global_position, float(nest_type.get("attack_radius")), str(nest_type.call("get_faction_id")))
	if target.is_empty():
		return false
	var target_position := _settlement_defense_position(target, marker.global_position)
	var size_range: Vector2i = nest_type.call("get_attack_squad_size_range", str(state.get("size_id", "small")))
	var count := rng.randi_range(size_range.x, size_range.y)
	var squad_id := "nest:%s:attack:%03d" % [marker.get_marker_id(), day_index]
	var attack_squad_ids: Array = state.get("attack_squad_ids", []) if state.get("attack_squad_ids", []) is Array else []
	attack_squad_ids.append(squad_id)
	state["attack_squad_ids"] = attack_squad_ids
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("upsert_world_sim_squad"):
		_ensure_nest_squad_people(marker.get_marker_id(), state, nest_type, squad_id, count, marker.global_position)
		bridge.upsert_world_sim_squad({
			"squad_id": squad_id,
			"owner_id": marker.get_marker_id(),
			"owner_kind": "nest",
			"faction_id": str(state.get("nest_type_id", "nest")),
			"objective": "attack",
			"target_settlement_id": target,
			"position": marker.global_position,
			"target_position": target_position,
			"home_position": marker.global_position,
			"patrol_radius": 0.0,
			"move_speed": 3.0,
			"member_count": count,
			"state": "active",
		})
	return true


func _ensure_nest_squad_people(marker_id: String, state: Dictionary, nest_type: Resource, squad_id: String, count: int, spawn_position: Vector3) -> void:
	var population := _get_population_controller()
	if population == null or nest_type == null or not population.has_method("ensure_generated_population"):
		return
	var faction = nest_type.get("faction_definition")
	var realizer := faction.call("get_character_realizer") as Resource if faction != null and faction.has_method("get_character_realizer") else null
	var name_profile := faction.call("get_population_name_profile") as Resource if faction != null and faction.has_method("get_population_name_profile") else null
	if realizer == null or name_profile == null:
		return
	var records: Array = population.call("ensure_generated_population", marker_id, squad_id, count, {
		"faction_id": str(nest_type.call("get_faction_id")) if nest_type.has_method("get_faction_id") else "",
		"squad_name": squad_id,
		"role_id": "nest_member",
		"population_appearance_profile": realizer,
		"population_name_profile": name_profile,
		"combat_stance": NpcRules.CombatStance.AGGRESSIVE,
		"spawn_position": spawn_position,
	})
	var person_ids: Array = []
	for record_value in records:
		if record_value is Dictionary:
			person_ids.append(str((record_value as Dictionary).get("actor_id", "")))
	var person_ids_by_squad: Dictionary = state.get("person_ids_by_squad", {})
	person_ids_by_squad[squad_id] = person_ids
	state["person_ids_by_squad"] = person_ids_by_squad


func ensure_nest_squad_people_for_record(record: Dictionary) -> void:
	var marker_id := str(record.get("owner_id", ""))
	var state: Dictionary = _nest_states.get(marker_id, {})
	if state.is_empty():
		return
	var nest_type := _get_nest_type(str(state.get("nest_type_id", "")))
	_ensure_nest_squad_people(marker_id, state, nest_type, str(record.get("squad_id", "")), int(record.get("member_count", 0)), record.get("position", Vector3.ZERO))
	_nest_states[marker_id] = state
	_sync_nest_state_to_gecs()


func _request_assault_job_for_actor(actor_id: String, marker_id: String, target_settlement_id: String, target_position: Vector3) -> void:
	var actor := _find_actor_by_id(actor_id) as HumanoidCharacter
	var marker := _markers_by_id.get(marker_id, null) as NestPlacementMarker
	var state: Dictionary = _nest_states.get(marker_id, {})
	if actor == null or marker == null or state.is_empty() or not bool(state.get("active", false)):
		return
	if actor.life_state != NpcRules.LifeState.ALIVE or actor.get_current_combat_target() != null:
		return
	actor.request_ai_job(_make_assault_job(actor, marker, state, target_settlement_id, target_position))


func _process_weekly_repopulation(day_index: int) -> void:
	var changed := false
	for marker_id_value in _markers_by_id.keys():
		var marker_id := str(marker_id_value)
		var marker := _markers_by_id[marker_id] as NestPlacementMarker
		var state: Dictionary = _nest_states.get(marker_id, _base_marker_state(marker))
		if bool(state.get("active", false)):
			continue
		var next_day := int(state.get("next_repopulation_day", -1))
		if next_day >= 0 and day_index < next_day:
			continue
		var nest_type := _pick_nest_type(marker, _make_rng("weekly_type:%s:%d" % [marker_id, day_index]))
		if nest_type == null:
			continue
		var activation_chance := marker.get_activation_chance(float(nest_type.get("default_initial_activation_chance")))
		if _make_rng("weekly_active:%s:%d" % [marker_id, day_index]).randf() > activation_chance:
			continue
		_activate_marker_state(state, marker, nest_type, _make_rng("weekly_state:%s:%d" % [marker_id, day_index]), day_index)
		_nest_states[marker_id] = state
		_spawn_static_runtime_for_state(marker, state)
		changed = true
	if changed:
		_sync_nest_state_to_gecs()


func _mark_nest_destroyed(state: Dictionary, marker: NestPlacementMarker, day_index: int) -> void:
	var nest_type := _get_nest_type(str(state.get("nest_type_id", "")))
	var existing_squad_ids := _nest_squad_ids_for_marker(marker.get_marker_id())
	var cooldown_days := DEFAULT_RESPAWN_COOLDOWN_DAYS
	if nest_type != null:
		cooldown_days = int(nest_type.get("respawn_cooldown_days"))
	cooldown_days = marker.get_respawn_cooldown_days(cooldown_days)
	state["active"] = false
	state["destroyed_day"] = day_index
	state["next_repopulation_day"] = day_index + cooldown_days
	state["actor_ids"] = []
	state["patrol_squad_ids"] = []
	state["patrol_squad_member_counts"] = {}
	state["guard_squad_id"] = ""
	state["guard_count"] = 0
	state["attack_squad_ids"] = []
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("remove_world_sim_squad"):
		for squad_id in existing_squad_ids:
			bridge.remove_world_sim_squad(squad_id)
	for squad_id in existing_squad_ids:
		derealize_nest_squad(squad_id)
	var visual := marker.get_node_or_null(NEST_VISUAL_NAME)
	if visual != null:
		visual.queue_free()


func _find_attack_target_settlement(origin: Vector3, radius: float, nest_faction_id: String) -> String:
	if settlement_controller == null or not settlement_controller.has_method("get_all_settlement_states"):
		return ""
	var best_id := ""
	var best_distance_squared := INF
	var radius_squared := radius * radius
	for state_value in settlement_controller.call("get_all_settlement_states"):
		if not (state_value is Dictionary):
			continue
		var state: Dictionary = state_value
		var settlement_id := str(state.get("settlement_id", ""))
		var faction_id := str(state.get("faction_id", ""))
		if settlement_id.is_empty() or faction_id == nest_faction_id:
			continue
		var position := _settlement_world_position(settlement_id, state, origin)
		var distance_squared := origin.distance_squared_to(position)
		if distance_squared <= radius_squared and distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_id = settlement_id
	return best_id


func _settlement_world_position(settlement_id: String, state: Dictionary, fallback: Vector3) -> Vector3:
	var state_position = state.get("world_position", null)
	if state_position is Vector3:
		return state_position
	if settlement_controller != null and settlement_controller.has_method("get_settlement_anchor"):
		var anchor := settlement_controller.call("get_settlement_anchor", settlement_id) as Node3D
		if anchor != null:
			return anchor.global_position
	return fallback


func _settlement_defense_position(settlement_id: String, fallback: Vector3) -> Vector3:
	if settlement_controller == null or not settlement_controller.has_method("get_settlement_anchor"):
		return fallback
	var anchor := settlement_controller.call("get_settlement_anchor", settlement_id) as Node3D
	if anchor != null and anchor.has_method("get_spawn_position"):
		return anchor.call("get_spawn_position", "defense")
	return anchor.global_position if anchor != null else fallback


func _nest_patrol_squad_id(marker_id: String, squad_index: int) -> String:
	return "nest:%s:patrol:%d" % [marker_id, squad_index]


func _nest_guard_squad_id(marker_id: String) -> String:
	return "nest:%s:guard" % marker_id


func _marker_id_from_squad_id(squad_id: String) -> String:
	var parts := squad_id.split(":")
	return str(parts[1]) if parts.size() >= 3 and parts[0] == "nest" else ""


func _nest_squad_ids_for_marker(marker_id: String) -> Array[String]:
	var result: Array[String] = []
	var state: Dictionary = _nest_states.get(marker_id, {}) if _nest_states.get(marker_id, {}) is Dictionary else {}
	for squad_id_value in state.get("patrol_squad_ids", []):
		result.append(str(squad_id_value))
	var guard_squad_id := str(state.get("guard_squad_id", ""))
	if not guard_squad_id.is_empty():
		result.append(guard_squad_id)
	for squad_id_value in state.get("attack_squad_ids", []):
		result.append(str(squad_id_value))
	return result


func _update_state_squad_count(marker_id: String, squad_id: String, survivors: int) -> void:
	if marker_id.is_empty():
		return
	var state: Dictionary = _nest_states.get(marker_id, {})
	if state.is_empty():
		return
	if squad_id == str(state.get("guard_squad_id", "")):
		state["guard_count"] = maxi(0, survivors)
		if survivors <= 0:
			state["guard_squad_id"] = ""
	else:
		var patrol_counts: Dictionary = state.get("patrol_squad_member_counts", {}) if state.get("patrol_squad_member_counts", {}) is Dictionary else {}
		if patrol_counts.has(squad_id):
			if survivors <= 0:
				patrol_counts.erase(squad_id)
				var patrol_ids: Array = state.get("patrol_squad_ids", []) if state.get("patrol_squad_ids", []) is Array else []
				patrol_ids.erase(squad_id)
				state["patrol_squad_ids"] = patrol_ids
			else:
				patrol_counts[squad_id] = survivors
			state["patrol_squad_member_counts"] = patrol_counts
		else:
			var attack_ids: Array = state.get("attack_squad_ids", []) if state.get("attack_squad_ids", []) is Array else []
			if survivors <= 0:
				attack_ids.erase(squad_id)
			state["attack_squad_ids"] = attack_ids
	state["alive_count"] = _count_state_squad_members(state)
	_nest_states[marker_id] = state
	_sync_nest_state_to_gecs()


func _count_state_squad_members(state: Dictionary) -> int:
	var total := maxi(0, int(state.get("guard_count", 0)))
	var patrol_counts: Dictionary = state.get("patrol_squad_member_counts", {}) if state.get("patrol_squad_member_counts", {}) is Dictionary else {}
	for count_value in patrol_counts.values():
		total += maxi(0, int(count_value))
	return total


func _check_destroyed_from_squad_counts(marker_id: String) -> void:
	var marker := _markers_by_id.get(marker_id, null) as NestPlacementMarker
	var state: Dictionary = _nest_states.get(marker_id, {})
	if marker == null or state.is_empty() or not bool(state.get("active", false)):
		return
	if _count_state_squad_members(state) <= 0:
		_mark_nest_destroyed(state, marker, _get_day_index())
		_nest_states[marker_id] = state
		_sync_nest_state_to_gecs()


func _live_nest_squad_actors(squad_id: String) -> Array[HumanoidCharacter]:
	var result: Array[HumanoidCharacter] = []
	var actor_ids: Array = _realized_squad_actor_ids.get(squad_id, []) if _realized_squad_actor_ids.get(squad_id, []) is Array else []
	for actor_id_value in actor_ids:
		var actor := _find_actor_by_id(str(actor_id_value)) as HumanoidCharacter
		if actor != null and is_instance_valid(actor) and actor.life_state != NpcRules.LifeState.DEAD:
			result.append(actor)
	return result


func _stable_id_slug(value: String) -> String:
	return value.replace(":", ".").replace("/", ".").replace(" ", "_")


func _has_live_nest_actors(state: Dictionary) -> bool:
	return not _live_nest_actors(state).is_empty()


func _live_nest_actors(state: Dictionary) -> Array[HumanoidCharacter]:
	var result: Array[HumanoidCharacter] = []
	for actor_id_value in state.get("actor_ids", []):
		var actor := _find_actor_by_id(str(actor_id_value)) as HumanoidCharacter
		if actor != null and is_instance_valid(actor) and actor.life_state != NpcRules.LifeState.DEAD:
			result.append(actor)
	return result


func _find_actor_by_id(actor_id: String) -> Node:
	if actor_id.is_empty():
		return null
	if actor_query_controller != null and actor_query_controller.has_method("get_actor_by_stable_id"):
		var actor := actor_query_controller.call("get_actor_by_stable_id", actor_id) as Node
		if actor != null:
			return actor
	return null


func _pick_nest_type(marker: NestPlacementMarker, rng: RandomNumberGenerator) -> Resource:
	var candidates: Array[Resource] = []
	var total_weight := 0.0
	for type_id in marker.get_allowed_nest_type_ids():
		var definition := _get_nest_type(type_id)
		if definition == null:
			continue
		candidates.append(definition)
		total_weight += maxf(float(definition.get("selection_weight")), 0.0)
	if candidates.is_empty():
		return null
	if candidates.size() == 1 or total_weight <= 0.0:
		return candidates[0]
	var roll := rng.randf_range(0.0, total_weight)
	var cursor := 0.0
	for definition in candidates:
		cursor += maxf(float(definition.get("selection_weight")), 0.0)
		if roll <= cursor:
			return definition
	return candidates[candidates.size() - 1]


func _get_nest_type(type_id: String) -> Resource:
	return _nest_types_by_id.get(type_id, null) as Resource


func _ensure_actor_root() -> Node3D:
	var root := root_scene.get_node_or_null(NEST_ACTOR_ROOT_NAME) as Node3D
	if root != null:
		return root
	root = Node3D.new()
	root.name = NEST_ACTOR_ROOT_NAME
	root_scene.add_child(root)
	return root


func _non_nest_hostile_factions(nest_faction_id: String) -> PackedStringArray:
	var result := PackedStringArray()
	if faction_controller != null and faction_controller.has_method("get_faction_ids"):
		for faction_id_value in faction_controller.call("get_faction_ids"):
			var faction_id := str(faction_id_value)
			if not faction_id.is_empty() and faction_id != nest_faction_id:
				result.append(faction_id)
	if not result.has("Player") and nest_faction_id != "Player":
		result.append("Player")
	return result


func _make_appearance(race: Resource, body_type: int, skin_color: Color) -> Resource:
	var appearance = APPEARANCE_DATA_SCRIPT.new()
	appearance.character_race = race
	appearance.visual_body_type = body_type
	appearance.body_archetype = HUMAN_FEMALE_BODY_ARCHETYPE if body_type == VISUAL_BODY_TYPE_FEMALE else HUMAN_MALE_BODY_ARCHETYPE
	appearance.skin_color_customized = true
	appearance.skin_color = skin_color
	return appearance


func _rustdead_clothes(rng: RandomNumberGenerator, member_index: int) -> Array[Resource]:
	match member_index:
		1:
			return []
		2:
			return [_pick_item(RUSTDEAD_LEG_ITEMS, rng)]
		3:
			return [_pick_item(RUSTDEAD_LEG_ITEMS, rng), _pick_item(RUSTDEAD_FEET_ITEMS, rng)]
	var clothes: Array[Resource] = []
	if rng.randf() < 0.32:
		clothes.append(_pick_item(RUSTDEAD_CHEST_ITEMS, rng))
	if rng.randf() < 0.24:
		clothes.append(_pick_item(RUSTDEAD_HAND_ITEMS, rng))
	if rng.randf() < 0.68:
		clothes.append(_pick_item(RUSTDEAD_LEG_ITEMS, rng))
	if rng.randf() < 0.42:
		clothes.append(_pick_item(RUSTDEAD_FEET_ITEMS, rng))
	if rng.randf() < 0.12:
		clothes.append(_pick_item(RUSTDEAD_HEAD_ITEMS, rng))
	return clothes


func _pick_item(pool: Array, rng: RandomNumberGenerator) -> Resource:
	return pool[rng.randi_range(0, pool.size() - 1)] as Resource


func _add_basic_actor_children(actor: HumanoidCharacter, color: Color) -> void:
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.transform = Transform3D(Basis(), Vector3(0.0, 0.95, 0.0))
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.4
	capsule_shape.height = 1.1
	collision.shape = capsule_shape
	actor.add_child(collision)

	var body := MeshInstance3D.new()
	body.name = "BodyMesh"
	body.transform = Transform3D(Basis(), Vector3(0.0, 0.95, 0.0))
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = 0.4
	body.mesh = capsule_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	body.material_override = material
	actor.add_child(body)


func _make_rng(purpose: String) -> RandomNumberGenerator:
	_ensure_runtime_seed()
	var rng := RandomNumberGenerator.new()
	rng.seed = maxi(1, absi(("%d:%d:%s" % [_get_world_seed(), _runtime_seed, purpose]).hash()))
	return rng


func _ensure_runtime_seed() -> void:
	if _runtime_seed > 0:
		return
	_runtime_seed = maxi(1, absi(("%d:%d:%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec(), get_instance_id()]).hash()))


func _get_minimum_initial_active_nests() -> int:
	var result := minimum_initial_active_nests
	var world_loader := root_scene.get_node_or_null("WorldLoader") if root_scene != null else null
	if world_loader != null:
		var definition = world_loader.get("world_definition")
		if definition != null:
			var value = definition.get("minimum_initial_active_nests")
			if value != null:
				result = int(value)
	return maxi(0, result)


func _get_world_seed() -> int:
	var world_loader := root_scene.get_node_or_null("WorldLoader") if root_scene != null else null
	if world_loader != null:
		var definition = world_loader.get("world_definition")
		if definition != null:
			var value = definition.get("random_seed")
			if value != null:
				return int(value)
	return 1


func _get_day_index() -> int:
	return int(world_time.call("get_day_index")) if world_time != null and world_time.has_method("get_day_index") else 0


func _actor_id(actor: Node) -> String:
	if actor == null:
		return ""
	var stable_id = actor.get("stable_id")
	if stable_id != null and not str(stable_id).strip_edges().is_empty():
		return str(stable_id).strip_edges()
	return str(actor.get_instance_id())


func _resource_id(resource: Resource) -> String:
	if resource != null and resource.has_method("get_id"):
		return str(resource.call("get_id")).strip_edges()
	return ""


func _count_active_nests() -> int:
	var count := 0
	for state in _nest_states.values():
		if state is Dictionary and bool((state as Dictionary).get("active", false)):
			count += 1
	return count


func _current_nest_state() -> Dictionary:
	return {
		"state_id": NEST_STATE_ID,
		"nest_index": _nest_index,
		"nest_states": _nest_states.duplicate(true),
	}


func _sync_nest_state_to_gecs() -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("upsert_nest_state"):
		bridge.call("upsert_nest_state", _current_nest_state())


func _get_population_controller() -> Node:
	return _context.get_optional(PopulationController.SERVICE_ID) if _context != null else null


func _get_gecs_world() -> Node:
	return _context.get_optional(GecsWorldController.SERVICE_ID) if _context != null else null
