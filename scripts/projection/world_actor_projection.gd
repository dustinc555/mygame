extends Node3D

class_name WorldActorProjection

const SELECTED_COLOR := Color(0.28, 0.78, 1.0, 1.0)
const SELECTION_RING_MAJOR_RADIUS := 1.12
const SELECTION_RING_TUBE_RADIUS := 0.075
const SELECTION_RING_TUBE_CENTER_Y := 0.06
const SELECTION_RING_MAJOR_SEGMENTS := 96
const SELECTION_RING_TUBE_SEGMENTS := 10

var actor_id := ""
var projection_kind := ""
var body_projection: Node
var _selection_area: Area3D
var _selection_ring: MeshInstance3D
var _selection_ring_material := StandardMaterial3D.new()


func setup(target_actor_id: String, target_projection_kind: String, body_script: Script) -> void:
	actor_id = target_actor_id
	projection_kind = target_projection_kind
	name = "ActorProjection_%s" % _safe_node_name(actor_id)
	set_meta("actor_id", actor_id)
	add_to_group("world_actor_projection")
	add_to_group("projected_world_actor")
	if projection_kind == "humanoid":
		add_to_group("projected_humanoid_actor")
		add_to_group("humanoid_projection_actor")
	_ensure_selection_nodes()
	_set_body_script(body_script)


func apply_projection_snapshot(record: Dictionary, equipment_slots: Dictionary, combat_state: Dictionary = {}) -> void:
	var record_actor_id := str(record.get("actor_id", record.get("stable_id", actor_id))).strip_edges()
	if not record_actor_id.is_empty():
		actor_id = record_actor_id
		set_meta("actor_id", actor_id)
	var world_position := _record_world_position(record)
	global_position = world_position
	if bool(record.get("world_facing_yaw_initialized", false)):
		rotation.y = float(record.get("world_facing_yaw", rotation.y))
	visible = int(record.get("life_state", 0)) >= 0
	if body_projection != null:
		body_projection.apply_projection_snapshot(record, equipment_slots, combat_state)


func set_selected(selected: bool) -> void:
	_ensure_selection_nodes()
	if _selection_ring != null:
		_selection_ring.visible = selected


func get_body_projection() -> Node:
	return body_projection


func get_projection_debug_state() -> Dictionary:
	var body_state: Dictionary = body_projection.get_projection_debug_state() if body_projection != null and body_projection.has_method("get_projection_debug_state") else {}
	return {
		"actor_id": actor_id,
		"projection_kind": projection_kind,
		"body_state": body_state,
	}


func _set_body_script(body_script: Script) -> void:
	if body_projection != null:
		remove_child(body_projection)
		body_projection.queue_free()
	body_projection = null
	if body_script == null:
		return
	var body = body_script.new()
	if not (body is Node) or not body.has_method("apply_projection_snapshot"):
		if body is Node:
			(body as Node).queue_free()
		return
	body_projection = body as Node
	body_projection.name = "BodyProjection"
	add_child(body_projection)


func _ensure_selection_nodes() -> void:
	if _selection_area == null:
		_selection_area = Area3D.new()
		_selection_area.name = "SelectionHitArea"
		_selection_area.input_ray_pickable = true
		_selection_area.set_meta("actor_id", actor_id)
		_selection_area.add_to_group("projected_world_actor_hit_area")
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		var shape := CapsuleShape3D.new()
		shape.radius = 0.55
		shape.height = 1.8
		collision.shape = shape
		collision.position = Vector3(0.0, 0.95, 0.0)
		_selection_area.add_child(collision)
		add_child(_selection_area)
	if _selection_ring == null:
		_selection_ring = MeshInstance3D.new()
		_selection_ring.name = "SelectionRing"
		_selection_ring.mesh = _make_selection_ring_mesh()
		_selection_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_selection_ring.material_override = _selection_ring_material
		_selection_ring.visible = false
		_setup_selection_ring_material()
		add_child(_selection_ring)
	if _selection_area != null:
		_selection_area.set_meta("actor_id", actor_id)


func _setup_selection_ring_material() -> void:
	_selection_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_selection_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_selection_ring_material.no_depth_test = false
	_selection_ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_selection_ring_material.emission_enabled = true
	_selection_ring_material.emission_energy_multiplier = 1.35
	_selection_ring_material.albedo_color = SELECTED_COLOR
	_selection_ring_material.emission = SELECTED_COLOR


func _make_selection_ring_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for major_index in range(SELECTION_RING_MAJOR_SEGMENTS):
		var major_angle := TAU * float(major_index) / float(SELECTION_RING_MAJOR_SEGMENTS)
		var radial_direction := Vector3(cos(major_angle), 0.0, sin(major_angle))
		for tube_index in range(SELECTION_RING_TUBE_SEGMENTS):
			var tube_angle := TAU * float(tube_index) / float(SELECTION_RING_TUBE_SEGMENTS)
			var tube_cos := cos(tube_angle)
			var tube_sin := sin(tube_angle)
			vertices.append(radial_direction * (SELECTION_RING_MAJOR_RADIUS + SELECTION_RING_TUBE_RADIUS * tube_cos) + Vector3.UP * (SELECTION_RING_TUBE_CENTER_Y + SELECTION_RING_TUBE_RADIUS * tube_sin))
			normals.append((radial_direction * tube_cos + Vector3.UP * tube_sin).normalized())
	for major_index in range(SELECTION_RING_MAJOR_SEGMENTS):
		var next_major_index := (major_index + 1) % SELECTION_RING_MAJOR_SEGMENTS
		for tube_index in range(SELECTION_RING_TUBE_SEGMENTS):
			var next_tube_index := (tube_index + 1) % SELECTION_RING_TUBE_SEGMENTS
			var current := major_index * SELECTION_RING_TUBE_SEGMENTS + tube_index
			var next_tube := major_index * SELECTION_RING_TUBE_SEGMENTS + next_tube_index
			var next_major := next_major_index * SELECTION_RING_TUBE_SEGMENTS + tube_index
			var next_both := next_major_index * SELECTION_RING_TUBE_SEGMENTS + next_tube_index
			indices.append(current)
			indices.append(next_major)
			indices.append(next_tube)
			indices.append(next_tube)
			indices.append(next_major)
			indices.append(next_both)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _record_world_position(record: Dictionary) -> Vector3:
	var position = record.get("last_world_position", record.get("world_position", Vector3.ZERO))
	return position if position is Vector3 else Vector3.ZERO


func _safe_node_name(value: String) -> String:
	var result := value.strip_edges()
	for character in [".", ":", "/", "\\", " "]:
		result = result.replace(character, "_")
	return result if not result.is_empty() else "unknown"
