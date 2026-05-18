extends Node

class_name BleedSplotchController

@export var enabled := true
@export var max_splotches := 250
@export var dry_seconds := 75.0
@export var raycast_height := 2.0
@export var raycast_depth := 5.0

var root_scene: Node
var _splotch_root: Node3D
var _rng := RandomNumberGenerator.new()
var _textures: Array[Texture2D] = []
var _splotches: Array[Dictionary] = []


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	_ensure_splotch_root()


func _ready() -> void:
	_rng.randomize()
	add_to_group("bleed_splotch_controller")
	if root_scene == null:
		root_scene = get_tree().current_scene
	_ensure_splotch_root()
	_generate_textures()


func _process(delta: float) -> void:
	if _splotches.is_empty():
		return
	for index in range(_splotches.size() - 1, -1, -1):
		var entry := _splotches[index]
		var decal := entry.get("node", null) as Decal
		if decal == null or not is_instance_valid(decal):
			_splotches.remove_at(index)
			continue
		entry["age"] = float(entry.get("age", 0.0)) + delta
		var dry_t := clampf(float(entry["age"]) / maxf(dry_seconds, 0.001), 0.0, 1.0)
		var fresh := entry.get("fresh", Color(0.46, 0.015, 0.01, 0.92)) as Color
		var dried := entry.get("dried", Color(0.13, 0.025, 0.018, 0.82)) as Color
		decal.modulate = fresh.lerp(dried, dry_t)


func spawn_hit_splash(source: Node3D, fluid: Resource, cut_damage: float) -> void:
	if not enabled or source == null or cut_damage <= 0.0:
		return
	var severity := clampf(cut_damage / 24.0, 0.0, 1.0)
	var count := 1 + int(severity >= 0.45) + int(severity >= 0.8)
	for index in range(count):
		var radius := _rng.randf_range(0.28, 0.52) * lerpf(0.75, 1.45, severity)
		var offset := _rng.randf_range(0.08, 0.62) * lerpf(0.85, 1.35, severity)
		_spawn_splotch(source, fluid, radius, offset)


func spawn_bleed_drip(source: Node3D, fluid: Resource, severity: float) -> void:
	if not enabled or source == null:
		return
	var clamped_severity := clampf(severity, 0.0, 1.0)
	var radius := _rng.randf_range(0.13, 0.27) * lerpf(0.8, 1.35, clamped_severity)
	var offset := _rng.randf_range(0.05, 0.38)
	_spawn_splotch(source, fluid, radius, offset)


func spawn_bleed_pool(source: Node3D, fluid: Resource, severity: float) -> void:
	if not enabled or source == null:
		return
	var clamped_severity := clampf(severity, 0.0, 1.0)
	var radius := _rng.randf_range(0.36, 0.72) * lerpf(0.85, 1.55, clamped_severity)
	_spawn_splotch(source, fluid, radius, 0.14)


func _ensure_splotch_root() -> void:
	if _splotch_root != null and is_instance_valid(_splotch_root):
		return
	if root_scene == null:
		return
	_splotch_root = root_scene.get_node_or_null("BleedSplotches") as Node3D
	if _splotch_root != null:
		return
	_splotch_root = Node3D.new()
	_splotch_root.name = "BleedSplotches"
	root_scene.add_child(_splotch_root)


func _spawn_splotch(source: Node3D, fluid: Resource, radius: float, offset_radius: float) -> void:
	_ensure_splotch_root()
	if _splotch_root == null or _textures.is_empty():
		return
	var offset_direction := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0))
	if offset_direction.length_squared() > 0.0001:
		offset_direction = offset_direction.normalized()
	var target_position := source.global_position + offset_direction * offset_radius * _rng.randf_range(0.25, 1.0)
	var placement := _get_ground_placement(target_position, source)
	if placement.is_empty():
		return
	var normal := placement.get("normal", Vector3.UP) as Vector3
	var decal := Decal.new()
	decal.name = "BleedSplotch"
	decal.size = Vector3(radius, 0.12, radius)
	decal.texture_albedo = _textures[_rng.randi_range(0, _textures.size() - 1)]
	var fresh := _get_fluid_color(fluid, "fresh_color", Color(0.46, 0.015, 0.01, 0.92))
	var dried := _get_fluid_color(fluid, "dried_color", Color(0.13, 0.025, 0.018, 0.82))
	decal.modulate = fresh
	_splotch_root.add_child(decal)
	var hit_position := placement.get("position", target_position) as Vector3
	decal.global_transform = Transform3D(_get_surface_basis(normal, _rng.randf_range(0.0, TAU)), hit_position + normal * 0.035)
	_splotches.append({
		"node": decal,
		"age": 0.0,
		"fresh": fresh,
		"dried": dried,
	})
	_trim_splotches()


func _get_ground_placement(world_position: Vector3, source: Node3D) -> Dictionary:
	var world := source.get_world_3d()
	if world == null:
		return {}
	var ray_start := world_position + Vector3.UP * raycast_height
	var ray_end := world_position - Vector3.UP * raycast_depth
	var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	if source is CollisionObject3D:
		query.exclude = [(source as CollisionObject3D).get_rid()]
	var result := world.direct_space_state.intersect_ray(query)
	if result.is_empty():
		return {}
	return {
		"position": result.get("position", world_position),
		"normal": result.get("normal", Vector3.UP),
	}


func _get_surface_basis(normal: Vector3, yaw: float) -> Basis:
	var y_axis := normal.normalized()
	if y_axis.length_squared() <= 0.0001:
		y_axis = Vector3.UP
	var x_axis := y_axis.cross(Vector3.FORWARD)
	if x_axis.length_squared() <= 0.0001:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized().rotated(y_axis, yaw)
	var z_axis := x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis).orthonormalized()


func _get_fluid_color(fluid: Resource, property_name: String, fallback: Color) -> Color:
	if fluid == null:
		return fallback
	var value = fluid.get(property_name)
	if value is Color:
		return value
	return fallback


func _trim_splotches() -> void:
	while _splotches.size() > max_splotches:
		var oldest: Dictionary = _splotches.pop_front()
		var decal := oldest.get("node", null) as Decal
		if decal != null and is_instance_valid(decal):
			decal.queue_free()


func _generate_textures() -> void:
	if not _textures.is_empty():
		return
	for texture_index in range(6):
		_textures.append(_create_splotch_texture(texture_index))


func _create_splotch_texture(texture_index: int) -> Texture2D:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = 31013 + texture_index * 7919
	var lobes: Array[Dictionary] = []
	var lobe_count := local_rng.randi_range(5, 9)
	for _lobe_index in range(lobe_count):
		lobes.append({
			"center": Vector2(local_rng.randf_range(-0.34, 0.34), local_rng.randf_range(-0.34, 0.34)),
			"radius": local_rng.randf_range(0.28, 0.62),
			"weight": local_rng.randf_range(0.62, 1.0),
		})
	for y in range(64):
		for x in range(64):
			var uv := Vector2((float(x) + 0.5) / 64.0, (float(y) + 0.5) / 64.0) * 2.0 - Vector2.ONE
			var alpha := 0.0
			for lobe in lobes:
				var center := lobe["center"] as Vector2
				var lobe_radius := float(lobe["radius"])
				var distance_ratio := uv.distance_to(center) / maxf(lobe_radius, 0.001)
				var blob := clampf(1.0 - distance_ratio, 0.0, 1.0)
				blob = blob * blob * (3.0 - 2.0 * blob)
				alpha = maxf(alpha, blob * float(lobe["weight"]))
			alpha = pow(alpha, 0.82)
			if alpha < 0.035:
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.0))
			else:
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(alpha * 0.95, 0.0, 1.0)))
	return ImageTexture.create_from_image(image)
