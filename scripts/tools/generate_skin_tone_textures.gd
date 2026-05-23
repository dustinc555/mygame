extends SceneTree

const SKIN_TEXTURE_BUILDER := preload("res://scripts/character_appearance/skin_texture_builder.gd")
const DETAIL_MIN := 0.42
const DETAIL_MAX := 1.7


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var output_dir := ProjectSettings.globalize_path(SKIN_TEXTURE_BUILDER.get_generated_skin_texture_dir(SKIN_TEXTURE_BUILDER.HUMAN_RACE_ID))
	var error := DirAccess.make_dir_recursive_absolute(output_dir)
	if error != OK:
		push_error("Could not create generated skin texture directory: %s" % SKIN_TEXTURE_BUILDER.get_generated_skin_texture_dir(SKIN_TEXTURE_BUILDER.HUMAN_RACE_ID))
		quit(1)
		return
	_generate_for_body_type(SKIN_TEXTURE_BUILDER.VISUAL_BODY_TYPE_MALE)
	_generate_for_body_type(SKIN_TEXTURE_BUILDER.VISUAL_BODY_TYPE_FEMALE)
	print("GENERATED_SKIN_TONE_TEXTURES_OK")
	quit(0)


func _generate_for_body_type(body_type: int) -> void:
	var source_texture: Texture2D = SKIN_TEXTURE_BUILDER.FEMALE_DARK_TEXTURE if body_type == SKIN_TEXTURE_BUILDER.VISUAL_BODY_TYPE_FEMALE else SKIN_TEXTURE_BUILDER.MALE_DARK_TEXTURE
	var base_image := _get_readable_image(source_texture)
	if base_image == null:
		push_error("Could not read base skin texture for body type %d" % body_type)
		quit(1)
		return
	_resize_to_working_size(base_image)
	var width := base_image.get_width()
	var height := base_image.get_height()
	var base_bytes := base_image.get_data()
	var mask := PackedFloat32Array()
	mask.resize(width * height)
	var average := _calculate_average_skin_color(base_image, mask, width, height)
	var tones: Array = SKIN_TEXTURE_BUILDER.NATURAL_SKIN_TONES
	for tone_index in range(tones.size()):
		var texture_image := _build_skin_image(base_bytes, mask, average, width, height, tones[tone_index])
		var output_path := SKIN_TEXTURE_BUILDER.get_generated_skin_texture_path(SKIN_TEXTURE_BUILDER.HUMAN_RACE_ID, body_type, tone_index)
		var save_error := texture_image.save_png(output_path)
		if save_error != OK:
			push_error("Could not save generated skin texture: %s" % output_path)
			quit(1)
			return
		print("generated %s" % output_path)


func _build_skin_image(base_bytes: PackedByteArray, mask: PackedFloat32Array, average: Vector3, width: int, height: int, skin_color: Color) -> Image:
	var result_bytes := base_bytes.duplicate()
	var target := Vector3(clampf(skin_color.r, 0.0, 1.0), clampf(skin_color.g, 0.0, 1.0), clampf(skin_color.b, 0.0, 1.0))
	var pixel_count := width * height
	for pixel_index in range(pixel_count):
		var skin_mask := mask[pixel_index]
		if skin_mask <= 0.001:
			continue
		var byte_index := pixel_index * 4
		var base_red := float(result_bytes[byte_index]) / 255.0
		var base_green := float(result_bytes[byte_index + 1]) / 255.0
		var base_blue := float(result_bytes[byte_index + 2]) / 255.0
		var detail_red := clampf(base_red / maxf(average.x, 0.001), DETAIL_MIN, DETAIL_MAX)
		var detail_green := clampf(base_green / maxf(average.y, 0.001), DETAIL_MIN, DETAIL_MAX)
		var detail_blue := clampf(base_blue / maxf(average.z, 0.001), DETAIL_MIN, DETAIL_MAX)
		var recolored_red := clampf(target.x * detail_red, 0.0, 1.0)
		var recolored_green := clampf(target.y * detail_green, 0.0, 1.0)
		var recolored_blue := clampf(target.z * detail_blue, 0.0, 1.0)
		result_bytes[byte_index] = _float_to_byte(lerpf(base_red, recolored_red, skin_mask))
		result_bytes[byte_index + 1] = _float_to_byte(lerpf(base_green, recolored_green, skin_mask))
		result_bytes[byte_index + 2] = _float_to_byte(lerpf(base_blue, recolored_blue, skin_mask))
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, result_bytes)


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
