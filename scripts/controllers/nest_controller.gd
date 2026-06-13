extends Node

class_name NestController

const NEST_STATE_ID := "nests"
const RUSTDEAD_NEST_TYPE := preload("res://resources/world_sim/nests/rustdead.tres")
const RUSTDEAD_RACE := preload("res://resources/character_races/rustdead.tres")
const APPEARANCE_DATA_SCRIPT := preload("res://scripts/character_appearance/character_appearance_data.gd")
const HUMAN_MALE_BODY_ARCHETYPE := preload("res://resources/character_body_archetypes/human_male.tres")
const HUMAN_FEMALE_BODY_ARCHETYPE := preload("res://resources/character_body_archetypes/human_female.tres")
const RUSTDEAD_TIER_LIBRARY := preload("res://scripts/characters/rustdead_tier_library.gd")
const AI_JOB_SCRIPT := preload("res://scripts/ai/ai_job.gd")
const AI_PATROL_STEP_SCRIPT := preload("res://scripts/ai/steps/ai_patrol_step.gd")
const AI_NEST_ASSAULT_STEP_SCRIPT := preload("res://scripts/ai/steps/ai_nest_assault_step.gd")
const TWISTED_SCRAP_HEAP_SCENE := preload("res://scenes/world/resource_nodes/scrap_pile_variant_2_node.tscn")
const SCRAP_PILE_SCENE := preload("res://scenes/world/resource_nodes/scrap_pile_node.tscn")
const HALF_BURIED_ROBOT_WRECK_SCENE := preload("res://scenes/world/resource_nodes/half_buried_robot_wreck_node.tscn")

const PEASANT_TUNIC := preload("res://resources/items/peasant_tunic.tres")
const PEASANT_TROUSERS := preload("res://resources/items/peasant_trousers.tres")
const PEASANT_SHOES := preload("res://resources/items/peasant_shoes.tres")
const RANGER_JERKIN := preload("res://resources/items/ranger_jerkin.tres")
const RANGER_LEGGINGS := preload("res://resources/items/ranger_leggings.tres")
const RANGER_BOOTS := preload("res://resources/items/ranger_boots.tres")
const RANGER_HOOD := preload("res://resources/items/ranger_hood.tres")
const NOBLE_DOUBLET := preload("res://resources/items/noble_doublet.tres")
const NOBLE_SLEEVES := preload("res://resources/items/noble_sleeves.tres")
const NOBLE_TROUSERS := preload("res://resources/items/noble_trousers.tres")
const NOBLE_SHOES := preload("res://resources/items/noble_shoes.tres")
const WIZARD_ROBES := preload("res://resources/items/wizard_robes.tres")
const WIZARD_SLEEVES := preload("res://resources/items/wizard_sleeves.tres")
const WIZARD_TROUSERS := preload("res://resources/items/wizard_trousers.tres")
const WIZARD_SHOES := preload("res://resources/items/wizard_shoes.tres")
const KNIGHT_GREAVES := preload("res://resources/items/knight_greaves.tres")
const KNIGHT_SABATONS := preload("res://resources/items/knight_sabatons.tres")

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

var root_scene: Node
var world_time: Node
var settlement_controller: Node
var faction_controller: Node
var actor_query_controller: Node
var _nest_types_by_id: Dictionary = {}
var _markers_by_id: Dictionary = {}
var _nest_states: Dictionary = {}
var _nest_index := 0
var _runtime_spawned_marker_ids: Dictionary = {}
var _maintenance_remaining := 0.0
var _runtime_seed := 0
var _initialized := false


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	_ensure_runtime_seed()
	set_process(true)
	call_deferred("_try_initialize")


func _ready() -> void:
	add_to_group("nest_controller")
	set_process(true)
	if root_scene == null:
		root_scene = get_tree().current_scene
	_ensure_runtime_seed()
	call_deferred("_try_initialize")


func _process(delta: float) -> void:
	if not _initialized:
		_try_initialize()
		return
	_maintenance_remaining -= delta
	if _maintenance_remaining > 0.0:
		return
	_maintenance_remaining = maxf(maintenance_interval_seconds, 0.1)
	_maintain_active_nests()


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
	world_time = get_parent().get_node_or_null("WorldTimeController")
	settlement_controller = get_parent().get_node_or_null("SettlementController")
	faction_controller = get_parent().get_node_or_null("FactionController")
	actor_query_controller = get_parent().get_node_or_null("ActorQueryController")
	if world_time == null or settlement_controller == null:
		return
	_register_nest_types()
	_register_nest_factions()
	refresh_from_gecs_state()
	_collect_markers()
	_ensure_marker_states()
	_spawn_active_nest_runtimes()
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
	state["patrol_squad_count"] = int(nest_type.call("get_patrol_squad_count", size_id))
	state["patrol_squad_ids"] = []
	state["attack_squad_ids"] = []
	state["actor_ids"] = []
	state["visual_scene_index"] = _pick_visual_scene_index(nest_type, rng)
	state["scrap_pile_specs"] = _create_scrap_pile_specs(marker, rng)
	_clear_nest_scrap_runtime(marker)
	state["last_attack_roll_day"] = day_index


func _spawn_active_nest_runtimes() -> void:
	for marker_id_value in _nest_states.keys():
		var marker_id := str(marker_id_value)
		var marker := _markers_by_id.get(marker_id, null) as NestPlacementMarker
		if marker == null:
			continue
		var state: Dictionary = _nest_states[marker_id]
		if bool(state.get("active", false)):
			_spawn_runtime_for_state(marker, state)
			_nest_states[marker_id] = state


func _spawn_runtime_for_state(marker: NestPlacementMarker, state: Dictionary) -> void:
	_spawn_nest_visual(marker, state)
	_spawn_nest_scrap_piles(marker, state)
	if _runtime_spawned_marker_ids.has(marker.get_marker_id()):
		return
	if _has_live_nest_actors(state):
		_runtime_spawned_marker_ids[marker.get_marker_id()] = true
		call_deferred("_reissue_patrol_jobs_for_marker", marker.get_marker_id())
		return
	_spawn_patrol_population(marker, state)
	_runtime_spawned_marker_ids[marker.get_marker_id()] = true
	call_deferred("_reissue_patrol_jobs_for_marker", marker.get_marker_id())
	_sync_nest_state_to_gecs()


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


func _spawn_patrol_population(marker: NestPlacementMarker, state: Dictionary) -> void:
	var nest_type := _get_nest_type(str(state.get("nest_type_id", "")))
	if nest_type == null:
		return
	var size_id := str(state.get("size_id", marker.get_size_id()))
	var patrol_squad_count: int = maxi(1, int(state.get("patrol_squad_count", 1)))
	var total_count: int = maxi(1, int(state.get("population_target", 1)))
	var patrol_size_range: Vector2i = nest_type.call("get_patrol_squad_size_range", size_id)
	var patrol_total: int = mini(total_count, patrol_squad_count * patrol_size_range.y)
	var remaining_patrol: int = patrol_total
	var patrol_squad_ids: Array = []
	var actor_ids: Array = state.get("actor_ids", []) if state.get("actor_ids", []) is Array else []
	for squad_index in range(patrol_squad_count):
		var squad_id := "%s.patrol.%02d" % [str(state.get("marker_id", marker.get_marker_id())), squad_index + 1]
		patrol_squad_ids.append(squad_id)
		var squads_left: int = patrol_squad_count - int(squad_index)
		var min_remaining_after: int = maxi(squads_left - 1, 0) * patrol_size_range.x
		var available_for_squad: int = maxi(remaining_patrol - min_remaining_after, 0)
		if available_for_squad <= 0:
			continue
		var squad_min: int = patrol_size_range.x if remaining_patrol >= patrol_size_range.x else 1
		var squad_size: int = clampi(ceili(float(remaining_patrol) / float(maxi(squads_left, 1))), squad_min, patrol_size_range.y)
		squad_size = mini(squad_size, available_for_squad)
		for member_index in range(squad_size):
			var actor := _spawn_nest_actor(marker, state, nest_type, squad_id, actor_ids.size() + 1)
			if actor != null:
				actor_ids.append(actor.stable_id)
			remaining_patrol -= 1
			if remaining_patrol <= 0:
				break
		if remaining_patrol <= 0:
			break
	var guard_squad_id := "%s.nest" % str(state.get("marker_id", marker.get_marker_id()))
	while actor_ids.size() < total_count:
		var guard_actor := _spawn_nest_actor(marker, state, nest_type, guard_squad_id, actor_ids.size() + 1)
		if guard_actor == null:
			break
		actor_ids.append(guard_actor.stable_id)
	state["patrol_squad_ids"] = patrol_squad_ids
	state["actor_ids"] = actor_ids


func _spawn_nest_actor(marker: NestPlacementMarker, state: Dictionary, nest_type: Resource, squad_id: String, member_index: int) -> HumanoidCharacter:
	var actor_script := nest_type.get("actor_script") as Script
	if actor_script == null:
		return null
	var actor := actor_script.new() as HumanoidCharacter
	if actor == null:
		return null
	var marker_id := str(state.get("marker_id", marker.get_marker_id()))
	var actor_id := "nest.%s.%03d" % [marker_id, member_index]
	actor.name = actor_id.replace(".", "_")
	actor.member_name = "Rustdead" if str(state.get("nest_type_id", "")) == "rustdead" else "Nest Spawn %03d" % member_index
	actor.stable_id = actor_id
	actor.faction_name = str(nest_type.call("get_faction_id")) if nest_type.has_method("get_faction_id") else ""
	actor.squad_name = squad_id
	actor.world_squad_id = squad_id
	actor.hostile_factions = _non_nest_hostile_factions(actor.faction_name)
	actor.combat_stance = NpcRules.CombatStance.AGGRESSIVE
	actor.position = _spawn_position_near_marker(marker, marker_id, member_index)
	actor.rotation.y = _make_rng("actor_yaw:%s:%d" % [marker_id, member_index]).randf_range(0.0, TAU)
	if str(state.get("nest_type_id", "")) == "rustdead":
		_configure_rustdead_actor(actor, marker_id, member_index)
	_add_basic_actor_children(actor, Color(0.42, 0.08, 0.07, 1.0))
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
	actor.visual_body_type = body_type
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


func _spawn_position_near_marker(marker: NestPlacementMarker, marker_id: String, member_index: int) -> Vector3:
	var rng := _make_rng("spawn_position:%s:%d" % [marker_id, member_index])
	var angle := rng.randf_range(0.0, TAU)
	var distance := rng.randf_range(3.0, 9.0)
	return marker.global_position + Vector3(cos(angle) * distance, 0.6, sin(angle) * distance)


func _maintain_active_nests() -> void:
	var changed := false
	for marker_id_value in _nest_states.keys():
		var marker_id := str(marker_id_value)
		var marker := _markers_by_id.get(marker_id, null) as NestPlacementMarker
		if marker == null:
			continue
		var state: Dictionary = _nest_states[marker_id]
		if not bool(state.get("active", false)):
			continue
		if _runtime_spawned_marker_ids.has(marker_id) and not _has_live_nest_actors(state):
			_mark_nest_destroyed(state, marker, _get_day_index())
			_nest_states[marker_id] = state
			changed = true
			continue
		_spawn_runtime_for_state(marker, state)
		_reissue_patrol_jobs(marker, state)
		_nest_states[marker_id] = state
	if changed:
		_sync_nest_state_to_gecs()


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
	var squad_id := "%s.attack.%03d" % [marker.get_marker_id(), day_index]
	var attack_squad_ids: Array = state.get("attack_squad_ids", []) if state.get("attack_squad_ids", []) is Array else []
	var actor_ids: Array = state.get("actor_ids", []) if state.get("actor_ids", []) is Array else []
	attack_squad_ids.append(squad_id)
	for index in range(count):
		var actor := _spawn_nest_actor(marker, state, nest_type, squad_id, actor_ids.size() + 1)
		if actor == null:
			continue
		actor_ids.append(actor.stable_id)
		call_deferred("_request_assault_job_for_actor", actor.stable_id, marker.get_marker_id(), target, target_position)
	state["attack_squad_ids"] = attack_squad_ids
	state["actor_ids"] = actor_ids
	return true


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
		_runtime_spawned_marker_ids.erase(marker_id)
		_spawn_runtime_for_state(marker, state)
		changed = true
	if changed:
		_sync_nest_state_to_gecs()


func _mark_nest_destroyed(state: Dictionary, marker: NestPlacementMarker, day_index: int) -> void:
	var nest_type := _get_nest_type(str(state.get("nest_type_id", "")))
	var cooldown_days := DEFAULT_RESPAWN_COOLDOWN_DAYS
	if nest_type != null:
		cooldown_days = int(nest_type.get("respawn_cooldown_days"))
	cooldown_days = marker.get_respawn_cooldown_days(cooldown_days)
	state["active"] = false
	state["destroyed_day"] = day_index
	state["next_repopulation_day"] = day_index + cooldown_days
	state["actor_ids"] = []
	state["patrol_squad_ids"] = []
	state["attack_squad_ids"] = []
	_runtime_spawned_marker_ids.erase(marker.get_marker_id())
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
	for node in get_tree().get_nodes_in_group("humanoid_character"):
		if str(node.get("stable_id")) == actor_id:
			return node
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
	capsule_shape.radius = 0.45
	capsule_shape.height = 1.1
	collision.shape = capsule_shape
	actor.add_child(collision)

	var body := MeshInstance3D.new()
	body.name = "BodyMesh"
	body.transform = Transform3D(Basis(), Vector3(0.0, 0.95, 0.0))
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = 0.45
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


func _get_gecs_world() -> Node:
	if not is_inside_tree():
		return null
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("GecsWorldController")
		if local != null:
			return local
	return get_tree().get_first_node_in_group("gecs_world_controller")
