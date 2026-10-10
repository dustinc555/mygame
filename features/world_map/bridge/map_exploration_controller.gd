extends Node

## Owns party knowledge, stored directly on a GECS entity. No second save file
## and no all-population scans. Only the small realized party is sampled.
const SERVICE_ID := &"map_exploration"
const STATE := preload("res://features/world_map/sim/c_map_exploration_state.gd")
const ENTITY := preload("res://addons/gecs/ecs/entity.gd")
const DEFAULT_SETTINGS := preload("res://features/world_map/resources/default_world_map_settings.tres")
const SAMPLE_SECONDS := 0.2

signal discovery_changed(chunks: Array)
signal knowledge_changed
signal state_replaced

var state: Resource
var settings: Resource = DEFAULT_SETTINGS
var world_root: Node
var observers: Array[Vector2] = []
var party_markers: Array[Dictionary] = []
var feature_source: RefCounted
var _gecs: Node
var _party: Node
var _world_id := ""
var _elapsed := 0.0
var _last_positions: Dictionary = {}

func initialize(context: BootstrapContext) -> void:
	_gecs = context.get_optional(GecsWorldController.SERVICE_ID)
	_party = context.root_scene.get_node_or_null("PartyManager")
	world_root = context.root_scene
	var ancestor := world_root
	while ancestor != null:
		if ancestor.has_method("get_world_id"):
			world_root = ancestor
			break
		ancestor = ancestor.get_parent()
	_world_id = str(world_root.call("get_world_id")) if world_root.has_method("get_world_id") else str(world_root.name)
	if world_root.get("map_settings") is Resource:
		settings = world_root.get("map_settings")
	if is_instance_valid(_gecs):
		_gecs.world_reindexed.connect(_bind_state)
	if is_instance_valid(_party):
		_party.party_member_added.connect(_on_party_changed)
		_party.party_member_removed.connect(_on_party_changed)
	_bind_state()

func _bind_state() -> void:
	state = null
	_last_positions.clear()
	observers.clear()
	party_markers.clear()
	if not is_instance_valid(_gecs) or _gecs.world == null:
		return
	for entity in _gecs.world.query.with_all([STATE]).execute():
		var candidate = entity.get_component(STATE)
		if candidate.world_id == _world_id:
			state = candidate
			break
	if state == null:
		var entity := ENTITY.new()
		entity.name = "MapExploration"
		entity.id = "map_exploration:%s:player_party" % _world_id
		var initial := STATE.new()
		initial.world_id = _world_id
		_gecs.world.add_entity(entity, [initial])
		state = entity.get_component(STATE)
	state_replaced.emit()

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= SAMPLE_SECONDS:
		_elapsed = 0.0
		observe_party()

func _on_party_changed(_member: Node) -> void:
	_last_positions.clear()
	# Defer until PartyManager has completed its membership transition.
	observe_party.call_deferred()

func observe_party() -> void:
	observers.clear()
	party_markers.clear()
	if state == null or not is_instance_valid(_party):
		return
	var seen := {}
	var changed: Array[Vector2i] = []
	var moved := false
	for member in _party.party_members:
		if not is_instance_valid(member) or member.is_queued_for_deletion():
			continue
		var position := Vector2(member.global_position.x, member.global_position.z)
		party_markers.append({"world": position, "label": str(member.member_name), "kind": "party"})
		if member.life_state != NpcRules.LifeState.ALIVE:
			continue
		observers.append(position)
		var id: int = member.get_instance_id()
		seen[id] = true
		if _last_positions.has(id) and position.distance_squared_to(_last_positions[id]) < 16.0:
			continue
		_last_positions[id] = position
		moved = true
		for coord in state.reveal_circle(position, clampf(settings.reveal_radius_meters, 16.0, 1000.0)):
			if not changed.has(coord):
				changed.append(coord)
	for id in _last_positions.keys():
		if not seen.has(id):
			_last_positions.erase(id)
	if not changed.is_empty():
		discovery_changed.emit(changed)
	if moved:
		refresh_observed_features()

func is_observed(position: Vector2) -> bool:
	var radius: float = clampf(settings.reveal_radius_meters, 16.0, 1000.0)
	for observer in observers:
		if position.distance_squared_to(observer) <= radius * radius:
			return true
	return false

func refresh_observed_features() -> void:
	if state == null or feature_source == null:
		return
	var changed := false
	var current := {}
	for observer in observers:
		for record in feature_source.features_near(observer, settings.reveal_radius_meters):
			var id := str(record["id"])
			current[id] = true
			if state.known_features.get(id, {}) != record:
				state.known_features[id] = record.duplicate(true)
				changed = true
	# A disappeared building/road is forgotten only when its old place is seen.
	for id in state.known_features.keys():
		var record: Dictionary = state.known_features[id]
		if is_observed(record.get("world", Vector2.ZERO)) and not current.has(id):
			state.known_features.erase(id)
			changed = true
	if changed:
		knowledge_changed.emit()
