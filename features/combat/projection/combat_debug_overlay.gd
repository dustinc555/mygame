extends Node3D

## Optional, bounded projection of authoritative combat targets. No work while off.
const COMBAT_NAVIGATION = preload("res://features/combat/bridge/combat_navigation.gd")
const REFRESH_SECONDS := 0.25
const VIEW_RADIUS := 80.0
const MAX_CANDIDATES := 128
const MAX_FIGHTERS := 32
const RING_SEGMENTS := 64
const PURSUIT_COLOR := Color(0.2, 0.85, 1.0, 0.9)
const BOUNDARY_COLOR := Color(1.0, 0.7, 0.15, 0.55)

# This shared Resource is runtime-editable; const property reads can be folded.
var _settings = preload("res://features/combat/resources/combat_pursuit_settings.tres")
var _enabled := false
var _remaining := 0.0
var _lines: MeshInstance3D
var _labels: Array[Label3D] = []

func _ready() -> void:
	set_enabled(false)

func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	visible = enabled
	set_process(enabled)
	_remaining = 0.0
	if not enabled:
		if _lines != null:
			(_lines.mesh as ArrayMesh).clear_surfaces()
		for label in _labels:
			label.hide()

func _process(delta: float) -> void:
	_remaining -= delta
	if _remaining > 0.0:
		return
	_remaining = REFRESH_SECONDS
	refresh()

func refresh() -> void:
	if not _enabled:
		return
	var query := BootstrapContext.service(ActorQueryController.SERVICE_ID) as ActorQueryController
	var gecs := BootstrapContext.service(GecsWorldController.SERVICE_ID) as GecsWorldController
	var camera := get_viewport().get_camera_3d()
	var records: Array = []
	if query != null and gecs != null and camera != null:
		for actor in query.get_nearby_actors_limited(camera.global_position, VIEW_RADIUS, MAX_CANDIDATES):
			var record := actor_record(actor as WorldActor, gecs)
			if not record.is_empty():
				records.append(record)
			if records.size() >= MAX_FIGHTERS:
				break
	draw_records(records)

func actor_record(actor: WorldActor, gecs: GecsWorldController) -> Dictionary:
	if not is_instance_valid(actor) or actor.is_queued_for_deletion() or actor.life_state != NpcRules.LifeState.ALIVE:
		return {}
	var entity = gecs.get_actor_entity(actor)
	if entity == null:
		return {}
	var state: CGameCombatState = entity.get_component(CGameCombatState)
	if state == null or state.system_target_actor_id.is_empty():
		return {}
	var target := gecs.get_actor_by_stable_id(state.system_target_actor_id) as WorldActor
	if not is_instance_valid(target) or target.is_queued_for_deletion() or target.life_state != NpcRules.LifeState.ALIVE:
		return {}
	var movement: CGameMovementState = entity.get_component(CGameMovementState)
	var action: CGameCombatAction = entity.get_component(CGameCombatAction)
	var config: CGameCombatConfig = entity.get_component(CGameCombatConfig)
	var status := "Finding position"
	if action != null and action.action_active:
		status = "Attacking"
	elif config != null and config.combat_stance == NpcRules.CombatStance.DEFENSIVE:
		status = "Defending"
	elif movement != null and movement.combat_settled:
		status = "In reach"
	elif Vector2(actor.velocity.x, actor.velocity.z).length_squared() > 0.04:
		status = "Chasing"
	elif movement != null and movement.system_movement_active:
		status = "Waiting for route"
	return {"actor_id": actor.stable_id, "target_id": state.system_target_actor_id,
		"from": actor.global_position - COMBAT_NAVIGATION.floor_origin_offset(actor),
		"to": target.global_position - COMBAT_NAVIGATION.floor_origin_offset(target),
		"status": status, "leashed": state.commanded_target_actor_id.is_empty() or not actor.player_party_member}

func draw_records(records: Array) -> void:
	if not _enabled:
		return
	if _lines == null:
		_lines = MeshInstance3D.new()
		_lines.name = "LeashLines"
		_lines.mesh = ArrayMesh.new()
		_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.vertex_color_use_as_albedo = true
		material.no_depth_test = true
		_lines.material_override = material
		add_child(_lines)
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var count := mini(records.size(), MAX_FIGHTERS)
	for i in range(count):
		var record: Dictionary = records[i]
		var from: Vector3 = record["from"]
		var to: Vector3 = record["to"]
		vertices.append(from + Vector3.UP * 0.15)
		vertices.append(to + Vector3.UP * 0.15)
		colors.append(PURSUIT_COLOR)
		colors.append(PURSUIT_COLOR)
		if record.leashed:
			for segment in range(RING_SEGMENTS):
				for endpoint in range(2):
					var angle := TAU * float(segment + endpoint) / float(RING_SEGMENTS)
					vertices.append(from + Vector3(cos(angle) * _settings.leash_distance, 0.15, sin(angle) * _settings.leash_distance))
					colors.append(BOUNDARY_COLOR)
		if _labels.size() <= i:
			var label := Label3D.new()
			label.name = "LeashLabel%d" % i
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.font_size = 28
			label.pixel_size = 0.008
			add_child(label)
			_labels.append(label)
		var label := _labels[i]
		label.position = from + Vector3.UP * 2.3
		var distance := Vector2(to.x - from.x, to.z - from.z).length()
		var limit := "%.0f m" % _settings.leash_distance if record.leashed else "player order"
		label.text = "%s\n%.1f / %s" % [record.status, distance, limit]
		label.modulate = PURSUIT_COLOR
		label.show()
	for i in range(count, _labels.size()):
		_labels[i].hide()
	var mesh := _lines.mesh as ArrayMesh
	mesh.clear_surfaces()
	if not vertices.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_COLOR] = colors
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
