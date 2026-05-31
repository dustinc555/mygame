extends RefCounted

class_name SkinTextureBuilder

const VISUAL_BODY_TYPE_MALE := 2
const VISUAL_BODY_TYPE_FEMALE := 3
const GENERATED_TEXTURE_MAX_SIZE := 768
const HUMAN_RACE_ID := "human"
const RUSTDEAD_RACE_ID := "rustdead"
const GENERATED_SKIN_TEXTURE_ROOT := "res://assets/generated/character_skin"
const SKIN_HUE_TARGET := 0.073
const SKIN_HUE_SOFT_START := 0.045
const SKIN_HUE_MAX_DISTANCE := 0.105
const SKIN_SATURATION_MIN := 0.12
const SKIN_SATURATION_FULL := 0.22
const SKIN_VALUE_MIN := 0.075
const SKIN_VALUE_FULL := 0.18

const MALE_DARK_TEXTURE: Texture2D = preload("res://assets/vendor/quaternius/universal_base_characters/base_characters/T_Superhero_Male_Dark.png")
const FEMALE_DARK_TEXTURE: Texture2D = preload("res://assets/vendor/quaternius/universal_base_characters/base_characters/T_Superhero_Female_Dark_BaseColor.png")
const NATURAL_SKIN_TONES := [
	Color(0.94, 0.78, 0.66, 1.0),
	Color(0.88, 0.68, 0.54, 1.0),
	Color(0.80, 0.58, 0.43, 1.0),
	Color(0.74, 0.45, 0.31, 1.0),
	Color(0.66, 0.43, 0.30, 1.0),
	Color(0.58, 0.38, 0.27, 1.0),
	Color(0.49, 0.31, 0.22, 1.0),
	Color(0.40, 0.25, 0.18, 1.0),
	Color(0.32, 0.20, 0.15, 1.0),
	Color(0.25, 0.15, 0.11, 1.0),
]
const RUSTDEAD_SKIN_TONES := [
	Color(0.82, 0.30, 0.24, 1.0),
	Color(0.74, 0.22, 0.18, 1.0),
	Color(0.64, 0.19, 0.16, 1.0),
	Color(0.56, 0.15, 0.14, 1.0),
	Color(0.49, 0.13, 0.13, 1.0),
	Color(0.43, 0.11, 0.12, 1.0),
	Color(0.37, 0.10, 0.11, 1.0),
	Color(0.31, 0.08, 0.10, 1.0),
	Color(0.25, 0.07, 0.09, 1.0),
	Color(0.19, 0.055, 0.075, 1.0),
]

static var _skin_profiles: Dictionary = {}
static var _texture_cache: Dictionary = {}


static func apply_custom_skin_materials(root: Node, race_id: String, body_type: int, skin_color: Color) -> bool:
	if root == null:
		return false
	var skin_texture := get_skin_texture(race_id, body_type, skin_color)
	if skin_texture == null:
		return false
	return _apply_skin_texture(root, skin_texture)


static func has_custom_skin_materials(root: Node) -> bool:
	if root == null:
		return false
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		if _is_skin_visual(mesh_instance) and _mesh_has_surface_override(mesh_instance):
			return true
	for child in root.get_children():
		if has_custom_skin_materials(child):
			return true
	return false


static func build_skin_texture(race_id: String, body_type: int, skin_color: Color) -> Texture2D:
	return get_skin_texture(race_id, body_type, skin_color)


static func get_skin_texture(race_id: String, body_type: int, skin_color: Color) -> Texture2D:
	var tone_index := get_nearest_skin_tone_index(skin_color, race_id)
	var path := get_generated_skin_texture_path(race_id, body_type, tone_index)
	if path.is_empty():
		push_warning("Missing race id for generated skin texture lookup.")
		return null
	if _texture_cache.has(path):
		return _texture_cache[path] as Texture2D
	var texture := load(path) as Texture2D
	if texture == null:
		push_warning("Missing generated skin texture for race '%s': %s. Run res://scripts/tools/generate_skin_tone_textures.gd." % [normalize_race_id(race_id), path])
		return null
	_texture_cache[path] = texture
	return texture


static func get_generated_skin_texture_dir(race_id: String) -> String:
	var normalized_race_id := normalize_race_id(race_id)
	if normalized_race_id.is_empty():
		return ""
	return "%s/%s" % [GENERATED_SKIN_TEXTURE_ROOT, normalized_race_id]


static func get_generated_skin_texture_path(race_id: String, body_type: int, tone_index: int) -> String:
	var texture_dir := get_generated_skin_texture_dir(race_id)
	if texture_dir.is_empty():
		return ""
	var body_id := "female" if _normalize_body_type(body_type) == VISUAL_BODY_TYPE_FEMALE else "male"
	return "%s/%s_skin_tone_%02d.png" % [texture_dir, body_id, clampi(tone_index, 0, get_skin_tone_count(race_id) - 1)]


static func normalize_race_id(race_id: String) -> String:
	var normalized := race_id.strip_edges().to_lower()
	if normalized.is_empty() or normalized.contains("/") or normalized.contains("\\") or normalized.contains(".."):
		return ""
	return normalized


static func get_nearest_skin_tone(color: Color) -> Color:
	return NATURAL_SKIN_TONES[get_nearest_skin_tone_index(color)]


static func get_nearest_skin_tone_index(color: Color, race_id := HUMAN_RACE_ID) -> int:
	var normalized_color := normalize_skin_color(color)
	var tones: Array = get_skin_tones_for_race(race_id)
	var best_index := 0
	var best_distance := INF
	for index in range(tones.size()):
		var tone: Color = tones[index]
		var distance := _get_color_distance_squared(normalized_color, tone)
		if distance < best_distance:
			best_distance = distance
			best_index = index
	return best_index


static func get_skin_tones_for_race(race_id: String) -> Array:
	if normalize_race_id(race_id) == RUSTDEAD_RACE_ID:
		return RUSTDEAD_SKIN_TONES
	return NATURAL_SKIN_TONES


static func get_skin_tone_count(race_id: String) -> int:
	return max(1, get_skin_tones_for_race(race_id).size())


static func normalize_skin_color(color: Color) -> Color:
	return Color(clampf(color.r, 0.0, 1.0), clampf(color.g, 0.0, 1.0), clampf(color.b, 0.0, 1.0), 1.0)


static func get_skin_mask_at_uv(body_type: int, uv: Vector2) -> float:
	var profile := _get_skin_profile(body_type)
	if profile.is_empty():
		return 0.0
	var width := int(profile["width"])
	var height := int(profile["height"])
	var x := clampi(int(round(clampf(uv.x, 0.0, 1.0) * float(width - 1))), 0, width - 1)
	var y := clampi(int(round(clampf(uv.y, 0.0, 1.0) * float(height - 1))), 0, height - 1)
	var mask: PackedFloat32Array = profile["mask"]
	return mask[y * width + x]


static func _get_readable_image(texture: Texture2D) -> Image:
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null:
		return null
	if image.is_compressed():
		var error := image.decompress()
		if error != OK:
			return null
	image.convert(Image.FORMAT_RGBA8)
	if image.has_mipmaps():
		image.clear_mipmaps()
	return image


static func _get_skin_profile(body_type: int) -> Dictionary:
	var normalized_body_type := _normalize_body_type(body_type)
	if _skin_profiles.has(normalized_body_type):
		return _skin_profiles[normalized_body_type]
	var source_texture := FEMALE_DARK_TEXTURE if normalized_body_type == VISUAL_BODY_TYPE_FEMALE else MALE_DARK_TEXTURE
	var base_image := _get_readable_image(source_texture)
	if base_image == null:
		return {}
	_resize_to_working_size(base_image)
	var width := base_image.get_width()
	var height := base_image.get_height()
	if width <= 0 or height <= 0:
		return {}
	var mask := PackedFloat32Array()
	mask.resize(width * height)
	_calculate_skin_mask(base_image, mask, width, height)
	var profile := {
		"mask": mask,
		"width": width,
		"height": height,
	}
	_skin_profiles[normalized_body_type] = profile
	return profile


static func _resize_to_working_size(image: Image) -> void:
	var width := image.get_width()
	var height := image.get_height()
	var max_dimension := maxi(width, height)
	if max_dimension <= GENERATED_TEXTURE_MAX_SIZE:
		return
	var scale := float(GENERATED_TEXTURE_MAX_SIZE) / float(max_dimension)
	var next_width := maxi(1, int(round(float(width) * scale)))
	var next_height := maxi(1, int(round(float(height) * scale)))
	image.resize(next_width, next_height, Image.INTERPOLATE_BILINEAR)
	if image.has_mipmaps():
		image.clear_mipmaps()


static func _calculate_skin_mask(base_image: Image, mask: PackedFloat32Array, width: int, height: int) -> void:
	for y in range(height):
		for x in range(width):
			mask[y * width + x] = _get_skin_mask(base_image.get_pixel(x, y))


static func _get_skin_mask(pixel: Color) -> float:
	if pixel.a <= 0.001:
		return 0.0
	var max_channel := maxf(pixel.r, maxf(pixel.g, pixel.b))
	var min_channel := minf(pixel.r, minf(pixel.g, pixel.b))
	if max_channel <= 0.001:
		return 0.0
	var saturation := (max_channel - min_channel) / max_channel
	var value := max_channel
	if saturation < SKIN_SATURATION_MIN or value < SKIN_VALUE_MIN:
		return 0.0
	if pixel.r <= pixel.b or pixel.g <= pixel.b * 0.82:
		return 0.0
	var hue := _get_hue(pixel.r, pixel.g, pixel.b, max_channel, min_channel)
	var hue_distance := _get_hue_distance(hue, SKIN_HUE_TARGET)
	var hue_weight := 1.0 - _smoothstep(SKIN_HUE_SOFT_START, SKIN_HUE_MAX_DISTANCE, hue_distance)
	var saturation_weight := _smoothstep(SKIN_SATURATION_MIN, SKIN_SATURATION_FULL, saturation)
	var value_weight := _smoothstep(SKIN_VALUE_MIN, SKIN_VALUE_FULL, value)
	return clampf(minf(hue_weight, minf(saturation_weight, value_weight)), 0.0, 1.0)


static func _get_hue(red: float, green: float, blue: float, max_channel: float, min_channel: float) -> float:
	var delta := max_channel - min_channel
	if delta <= 0.00001:
		return 0.0
	var hue := 0.0
	if red == max_channel:
		hue = (green - blue) / delta
	elif green == max_channel:
		hue = ((blue - red) / delta) + 2.0
	else:
		hue = ((red - green) / delta) + 4.0
	return wrapf(hue / 6.0, 0.0, 1.0)


static func _get_hue_distance(left: float, right: float) -> float:
	var distance := absf(left - right)
	return minf(distance, 1.0 - distance)


static func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	if edge0 == edge1:
		return 0.0
	var x := clampf((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func _get_color_distance_squared(left: Color, right: Color) -> float:
	var red := left.r - right.r
	var green := left.g - right.g
	var blue := left.b - right.b
	return red * red + green * green + blue * blue


static func _normalize_body_type(body_type: int) -> int:
	return VISUAL_BODY_TYPE_FEMALE if body_type == VISUAL_BODY_TYPE_FEMALE else VISUAL_BODY_TYPE_MALE


static func _apply_skin_texture(root: Node, skin_texture: Texture2D) -> bool:
	var did_apply := false
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		if _is_skin_visual(mesh_instance):
			did_apply = _apply_skin_texture_to_mesh(mesh_instance, skin_texture) or did_apply
	for child in root.get_children():
		did_apply = _apply_skin_texture(child, skin_texture) or did_apply
	return did_apply


static func _apply_skin_texture_to_mesh(mesh_instance: MeshInstance3D, skin_texture: Texture2D) -> bool:
	if mesh_instance.mesh == null:
		return false
	var did_apply := false
	for surface_index in range(mesh_instance.mesh.get_surface_count()):
		var source_material := mesh_instance.mesh.surface_get_material(surface_index)
		if not _is_skin_surface(mesh_instance, source_material):
			continue
		var custom_material: Material
		if source_material is BaseMaterial3D:
			custom_material = (source_material as BaseMaterial3D).duplicate(true)
			(custom_material as BaseMaterial3D).albedo_texture = skin_texture
			(custom_material as BaseMaterial3D).albedo_color = Color.WHITE
		else:
			var fallback_material := StandardMaterial3D.new()
			fallback_material.albedo_texture = skin_texture
			fallback_material.roughness = 0.86
			custom_material = fallback_material
		mesh_instance.set_surface_override_material(surface_index, custom_material)
		did_apply = true
	return did_apply


static func _is_skin_visual(mesh_instance: MeshInstance3D) -> bool:
	var node_name := str(mesh_instance.name).to_lower()
	if node_name.contains("superhero"):
		return true
	if mesh_instance.mesh == null:
		return false
	for surface_index in range(mesh_instance.mesh.get_surface_count()):
		if _is_skin_surface(mesh_instance, mesh_instance.mesh.surface_get_material(surface_index)):
			return true
	return false


static func _is_skin_surface(mesh_instance: MeshInstance3D, material: Material) -> bool:
	var node_name := str(mesh_instance.name).to_lower()
	if node_name.contains("superhero"):
		return true
	return material != null and str(material.resource_name).to_lower().contains("superhero")


static func _mesh_has_surface_override(mesh_instance: MeshInstance3D) -> bool:
	for surface_index in range(mesh_instance.get_surface_override_material_count()):
		if mesh_instance.get_surface_override_material(surface_index) != null:
			return true
	return false
