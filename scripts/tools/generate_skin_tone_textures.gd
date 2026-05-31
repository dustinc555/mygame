extends SceneTree

const SKIN_TEXTURE_BUILDER := preload("res://scripts/character_appearance/skin_texture_builder.gd")
const DETAIL_MIN := 0.42
const DETAIL_MAX := 1.7
const DEFAULT_RACE_IDS := ["human", "rustdead"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for race_id in _get_requested_race_ids():
		var output_dir := ProjectSettings.globalize_path(SKIN_TEXTURE_BUILDER.get_generated_skin_texture_dir(race_id))
		var error := DirAccess.make_dir_recursive_absolute(output_dir)
		if error != OK:
			push_error("Could not create generated skin texture directory: %s" % SKIN_TEXTURE_BUILDER.get_generated_skin_texture_dir(race_id))
			quit(1)
			return
		_generate_for_body_type(race_id, SKIN_TEXTURE_BUILDER.VISUAL_BODY_TYPE_MALE)
		_generate_for_body_type(race_id, SKIN_TEXTURE_BUILDER.VISUAL_BODY_TYPE_FEMALE)
	print("GENERATED_SKIN_TONE_TEXTURES_OK")
	quit(0)


func _get_requested_race_ids() -> Array[String]:
	var result: Array[String] = []
	for argument in OS.get_cmdline_args():
		var arg := str(argument)
		if not arg.begins_with("--skin-race="):
			continue
		var value := arg.substr("--skin-race=".length())
		for race_id_value in value.split(","):
			var race_id := SKIN_TEXTURE_BUILDER.normalize_race_id(str(race_id_value))
			if race_id == "all":
				return _default_race_ids()
			if not _is_supported_race_id(race_id):
				push_warning("Unsupported skin texture race id: %s" % race_id)
				continue
			if not result.has(race_id):
				result.append(race_id)
	if result.is_empty():
		return _default_race_ids()
	return result


func _default_race_ids() -> Array[String]:
	var result: Array[String] = []
	for race_id in DEFAULT_RACE_IDS:
		result.append(str(race_id))
	return result


func _is_supported_race_id(race_id: String) -> bool:
	return race_id == SKIN_TEXTURE_BUILDER.HUMAN_RACE_ID or race_id == SKIN_TEXTURE_BUILDER.RUSTDEAD_RACE_ID


func _generate_for_body_type(race_id: String, body_type: int) -> void:
	var source_texture: Texture2D = SKIN_TEXTURE_BUILDER.FEMALE_DARK_TEXTURE if body_type == SKIN_TEXTURE_BUILDER.VISUAL_BODY_TYPE_FEMALE else SKIN_TEXTURE_BUILDER.MALE_DARK_TEXTURE
	var base_image := _get_readable_image(source_texture)
	if base_image == null:
		push_error("Could not read base skin texture for race '%s' body type %d" % [race_id, body_type])
		quit(1)
		return
	_resize_to_working_size(base_image)
	var width := base_image.get_width()
	var height := base_image.get_height()
	var base_bytes := base_image.get_data()
	var mask := PackedFloat32Array()
	mask.resize(width * height)
	var average := _calculate_average_skin_color(base_image, mask, width, height)
	var tones: Array = SKIN_TEXTURE_BUILDER.get_skin_tones_for_race(race_id)
	for tone_index in range(tones.size()):
		var texture_image := _build_skin_image(race_id, body_type, tone_index, base_bytes, mask, average, width, height, tones[tone_index])
		var output_path := SKIN_TEXTURE_BUILDER.get_generated_skin_texture_path(race_id, body_type, tone_index)
		var save_error := texture_image.save_png(output_path)
		if save_error != OK:
			push_error("Could not save generated skin texture: %s" % output_path)
			quit(1)
			return
		print("generated %s" % output_path)


func _build_skin_image(race_id: String, body_type: int, tone_index: int, base_bytes: PackedByteArray, mask: PackedFloat32Array, average: Vector3, width: int, height: int, skin_color: Color) -> Image:
	var result_bytes := base_bytes.duplicate()
	var target := Vector3(clampf(skin_color.r, 0.0, 1.0), clampf(skin_color.g, 0.0, 1.0), clampf(skin_color.b, 0.0, 1.0))
	var is_rustdead := SKIN_TEXTURE_BUILDER.normalize_race_id(race_id) == SKIN_TEXTURE_BUILDER.RUSTDEAD_RACE_ID
	var seed := tone_index * 97 + body_type * 131
	var pixel_count := width * height
	for pixel_index in range(pixel_count):
		var skin_mask := mask[pixel_index]
		if skin_mask <= 0.001:
			continue
		var byte_index := pixel_index * 4
		var base_red := float(result_bytes[byte_index]) / 255.0
		var base_green := float(result_bytes[byte_index + 1]) / 255.0
		var base_blue := float(result_bytes[byte_index + 2]) / 255.0
		var recolored := _get_recolored_skin_pixel(Vector3(base_red, base_green, base_blue), average, target)
		if is_rustdead:
			var x := pixel_index % width
			var y := int(pixel_index / width)
			recolored = _get_rustdead_skin_pixel(recolored, x, y, seed)
		var recolored_red := clampf(recolored.x, 0.0, 1.0)
		var recolored_green := clampf(recolored.y, 0.0, 1.0)
		var recolored_blue := clampf(recolored.z, 0.0, 1.0)
		result_bytes[byte_index] = _float_to_byte(lerpf(base_red, recolored_red, skin_mask))
		result_bytes[byte_index + 1] = _float_to_byte(lerpf(base_green, recolored_green, skin_mask))
		result_bytes[byte_index + 2] = _float_to_byte(lerpf(base_blue, recolored_blue, skin_mask))
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, result_bytes)


func _get_recolored_skin_pixel(base_color: Vector3, average: Vector3, target: Vector3) -> Vector3:
	var detail_red := clampf(base_color.x / maxf(average.x, 0.001), DETAIL_MIN, DETAIL_MAX)
	var detail_green := clampf(base_color.y / maxf(average.y, 0.001), DETAIL_MIN, DETAIL_MAX)
	var detail_blue := clampf(base_color.z / maxf(average.z, 0.001), DETAIL_MIN, DETAIL_MAX)
	return Vector3(
		clampf(target.x * detail_red, 0.0, 1.0),
		clampf(target.y * detail_green, 0.0, 1.0),
		clampf(target.z * detail_blue, 0.0, 1.0)
	)


func _get_rustdead_skin_pixel(color: Vector3, x: int, y: int, seed: int) -> Vector3:
	var large_cell_x := int(floor(float(x) / 31.0))
	var large_cell_y := int(floor(float(y) / 31.0))
	var medium_cell_x := int(floor(float(x) / 13.0))
	var medium_cell_y := int(floor(float(y) / 13.0))
	var bruise := _smoothstep(0.48, 0.93, _noise01(large_cell_x, large_cell_y, seed + 17))
	var raw_patch := _smoothstep(0.70, 0.98, _noise01(medium_cell_x, medium_cell_y, seed + 43))
	var ash := _smoothstep(0.55, 0.96, _noise01(medium_cell_x + 19, medium_cell_y - 7, seed + 89))
	var fine := _noise01(x, y, seed + 191)
	var corpse := color
	corpse = corpse.lerp(Vector3(0.12, 0.028, 0.06), bruise * 0.42)
	corpse = corpse.lerp(Vector3(0.95, 0.035, 0.025), raw_patch * 0.36)
	corpse = corpse.lerp(Vector3(0.18, 0.13, 0.12), ash * 0.18)
	var scratch := _get_rustdead_scratch_mask(x, y, seed)
	corpse = corpse.lerp(Vector3(1.0, 0.025, 0.012), scratch * 0.72)
	var speckle := lerpf(0.88, 1.12, fine)
	return Vector3(corpse.x * speckle, corpse.y * lerpf(0.72, 1.02, fine), corpse.z * lerpf(0.78, 1.05, fine))


func _get_rustdead_scratch_mask(x: int, y: int, seed: int) -> float:
	var scratch_gate := _noise01(int(floor(float(x) / 23.0)), int(floor(float(y) / 9.0)), seed + 251)
	if scratch_gate < 0.78:
		return 0.0
	var band := absf(fmod(float(x * 3 + y * 5 + seed * 11), 47.0) - 23.5)
	return 1.0 - _smoothstep(0.45, 1.9, band)


func _noise01(x: int, y: int, seed: int) -> float:
	var value := sin(float(x) * 12.9898 + float(y) * 78.233 + float(seed) * 37.719) * 43758.5453
	return value - floor(value)


func _get_readable_image(texture: Texture2D) -> Image:
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


func _resize_to_working_size(image: Image) -> void:
	var width := image.get_width()
	var height := image.get_height()
	var max_dimension := maxi(width, height)
	if max_dimension <= SKIN_TEXTURE_BUILDER.GENERATED_TEXTURE_MAX_SIZE:
		return
	var scale := float(SKIN_TEXTURE_BUILDER.GENERATED_TEXTURE_MAX_SIZE) / float(max_dimension)
	var next_width := maxi(1, int(round(float(width) * scale)))
	var next_height := maxi(1, int(round(float(height) * scale)))
	image.resize(next_width, next_height, Image.INTERPOLATE_BILINEAR)
	if image.has_mipmaps():
		image.clear_mipmaps()


func _calculate_average_skin_color(base_image: Image, mask: PackedFloat32Array, width: int, height: int) -> Vector3:
	var total := Vector3.ZERO
	var weight := 0.0
	for y in range(height):
		for x in range(width):
			var pixel := base_image.get_pixel(x, y)
			var skin_mask := _get_skin_mask(pixel)
			mask[y * width + x] = skin_mask
			if skin_mask <= 0.001:
				continue
			total += Vector3(pixel.r, pixel.g, pixel.b) * skin_mask
			weight += skin_mask
	if weight <= 0.001:
		return Vector3(0.58, 0.38, 0.27)
	return total / weight


func _get_skin_mask(pixel: Color) -> float:
	if pixel.a <= 0.001:
		return 0.0
	var max_channel := maxf(pixel.r, maxf(pixel.g, pixel.b))
	var min_channel := minf(pixel.r, minf(pixel.g, pixel.b))
	if max_channel <= 0.001:
		return 0.0
	var saturation := (max_channel - min_channel) / max_channel
	var value := max_channel
	if saturation < SKIN_TEXTURE_BUILDER.SKIN_SATURATION_MIN or value < SKIN_TEXTURE_BUILDER.SKIN_VALUE_MIN:
		return 0.0
	if pixel.r <= pixel.b or pixel.g <= pixel.b * 0.82:
		return 0.0
	var hue := _get_hue(pixel.r, pixel.g, pixel.b, max_channel, min_channel)
	var hue_distance := _get_hue_distance(hue, SKIN_TEXTURE_BUILDER.SKIN_HUE_TARGET)
	var hue_weight := 1.0 - _smoothstep(SKIN_TEXTURE_BUILDER.SKIN_HUE_SOFT_START, SKIN_TEXTURE_BUILDER.SKIN_HUE_MAX_DISTANCE, hue_distance)
	var saturation_weight := _smoothstep(SKIN_TEXTURE_BUILDER.SKIN_SATURATION_MIN, SKIN_TEXTURE_BUILDER.SKIN_SATURATION_FULL, saturation)
	var value_weight := _smoothstep(SKIN_TEXTURE_BUILDER.SKIN_VALUE_MIN, SKIN_TEXTURE_BUILDER.SKIN_VALUE_FULL, value)
	return clampf(minf(hue_weight, minf(saturation_weight, value_weight)), 0.0, 1.0)


func _get_hue(red: float, green: float, blue: float, max_channel: float, min_channel: float) -> float:
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


func _get_hue_distance(left: float, right: float) -> float:
	var distance := absf(left - right)
	return minf(distance, 1.0 - distance)


func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	if edge0 == edge1:
		return 0.0
	var x := clampf((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _float_to_byte(value: float) -> int:
	return clampi(int(round(clampf(value, 0.0, 1.0) * 255.0)), 0, 255)
