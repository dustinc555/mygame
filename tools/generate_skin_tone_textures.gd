extends SceneTree

const SKIN_TEXTURE_BUILDER := preload("res://features/actors/projection/appearance/skin_texture_builder.gd")
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
		var variants := [SKIN_TEXTURE_BUILDER.BODY_VARIANT_HEROIC]
		if race_id == SKIN_TEXTURE_BUILDER.HUMAN_RACE_ID:
			variants.append(SKIN_TEXTURE_BUILDER.BODY_VARIANT_REGULAR)
			variants.append(SKIN_TEXTURE_BUILDER.BODY_VARIANT_TEEN)
		for body_variant in variants:
			_generate_for_body_type(race_id, SKIN_TEXTURE_BUILDER.VISUAL_BODY_TYPE_MALE, body_variant)
			_generate_for_body_type(race_id, SKIN_TEXTURE_BUILDER.VISUAL_BODY_TYPE_FEMALE, body_variant)
	print("GENERATED_SKIN_TONE_TEXTURES_OK")
	quit(0)


func _get_requested_race_ids() -> Array[String]:
	var result: Array[String] = []
	for argument in OS.get_cmdline_user_args():
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


func _generate_for_body_type(race_id: String, body_type: int, body_variant: String) -> void:
	var source_texture_path: String = SKIN_TEXTURE_BUILDER.get_source_texture_path(body_type, body_variant)
	var source_texture := load(source_texture_path) as Texture2D
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
		var output_path := SKIN_TEXTURE_BUILDER.get_generated_skin_texture_path(race_id, body_type, tone_index, body_variant)
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
			recolored = _get_rustdead_skin_pixel(recolored, x, y, seed, tone_index)
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


func _get_rustdead_skin_pixel(color: Vector3, x: int, y: int, seed: int, tone_index: int) -> Vector3:
	var fx := float(x)
	var fy := float(y)
	var machine_ratio := _get_rustdead_machine_ratio(tone_index)
	var broad := _smooth_noise01(fx * 0.018, fy * 0.016, seed + 17)
	var pooled := _smooth_noise01(fx * 0.044 + 11.7, fy * 0.039 - 6.3, seed + 43)
	var ash_noise := _smooth_noise01(fx * 0.062 - 18.0, fy * 0.053 + 23.0, seed + 89)
	var fine := _noise01(x, y, seed + 191)
	var pore := _smooth_noise01(fx * 0.42 + 3.0, fy * 0.38 - 5.0, seed + 307)
	var bruise := _smoothstep(0.50, 0.86, broad)
	var raw_patch := _smoothstep(0.66, 0.93, pooled + (broad - 0.5) * 0.18)
	var ash := _smoothstep(0.58, 0.91, ash_noise)
	var machine_noise := 0.0
	var rust_noise := 0.0
	if machine_ratio > 0.001:
		machine_noise = _smooth_noise01(fx * 0.030 + 41.0, fy * 0.028 - 17.0, seed + 503)
		rust_noise = _smooth_noise01(fx * 0.075 - 3.0, fy * 0.068 + 19.0, seed + 541)
	var metal_patch := _smoothstep(0.50, 0.86, machine_noise + (ash_noise - 0.5) * 0.18) * machine_ratio
	var rust_patch := _smoothstep(0.56, 0.88, rust_noise) * machine_ratio
	var metal_color := Vector3(0.34, 0.33, 0.31).lerp(Vector3(0.72, 0.70, 0.66), clampf((machine_ratio - 0.45) / 0.43, 0.0, 1.0))
	var corpse := color
	corpse = corpse.lerp(Vector3(0.10, 0.025, 0.055), bruise * lerpf(0.36, 0.22, machine_ratio))
	corpse = corpse.lerp(Vector3(0.90, 0.036, 0.024), raw_patch * lerpf(0.30, 0.14, machine_ratio))
	corpse = corpse.lerp(Vector3(0.20, 0.15, 0.13), ash * lerpf(0.16, 0.30, machine_ratio))
	var vein := _get_rustdead_vein_mask(fx, fy, seed, machine_ratio, pooled, ash_noise)
	corpse = corpse.lerp(Vector3(0.06, 0.012, 0.035), vein * lerpf(0.34, 0.22, machine_ratio))
	corpse = corpse.lerp(metal_color, metal_patch * lerpf(0.58, 0.78, machine_ratio))
	corpse = corpse.lerp(Vector3(0.58, 0.21, 0.08), rust_patch * lerpf(0.30, 0.42, machine_ratio))
	var seam := _get_rustdead_machine_seam_mask(fx, fy, seed, machine_noise, rust_noise) * machine_ratio
	corpse = corpse.lerp(Vector3(0.025, 0.020, 0.018), seam * 0.78)
	var scratch := _get_rustdead_scratch_mask(x, y, seed, fine, broad)
	corpse = corpse.lerp(Vector3(1.0, 0.025, 0.012), scratch * lerpf(0.68, 0.34, machine_ratio))
	var speckle := lerpf(0.88, 1.13, fine)
	var pore_shadow := lerpf(0.94, 1.04, pore) * lerpf(1.0, 0.92 + machine_noise * 0.16, machine_ratio)
	return Vector3(corpse.x * speckle * pore_shadow, corpse.y * lerpf(0.74, 1.03, fine), corpse.z * lerpf(0.80, 1.06, fine))


func _get_rustdead_machine_ratio(tone_index: int) -> float:
	if tone_index >= 7:
		return 0.88
	if tone_index >= 4:
		return 0.52
	if tone_index >= 2:
		return 0.22
	return 0.0


func _get_rustdead_vein_mask(x: float, y: float, seed: int, machine_ratio: float, gate: float, warp_source: float) -> float:
	if gate < lerpf(0.58, 0.48, machine_ratio):
		return 0.0
	var warp := (warp_source - 0.5) * lerpf(9.0, 4.0, machine_ratio)
	var band := absf(fmod(x * 0.70 + y * 1.45 + float(seed) * 0.37 + warp, 34.0) - 17.0)
	return (1.0 - _smoothstep(0.45, lerpf(2.8, 2.0, machine_ratio), band)) * _smoothstep(0.58, 0.86, gate)


func _get_rustdead_machine_seam_mask(x: float, y: float, seed: int, gate: float, warp_source: float) -> float:
	if gate < 0.54:
		return 0.0
	var warp := (warp_source - 0.5) * 7.0
	var diagonal := absf(fmod(x * 1.12 - y * 0.74 + float(seed) * 0.19 + warp, 44.0) - 22.0)
	var vertical := absf(fmod(x * 0.42 + y * 1.85 + float(seed) * 0.11 - warp, 57.0) - 28.5)
	return maxf(1.0 - _smoothstep(0.55, 2.4, diagonal), 1.0 - _smoothstep(0.45, 2.1, vertical)) * _smoothstep(0.54, 0.86, gate)


func _get_rustdead_scratch_mask(x: int, y: int, seed: int, scratch_gate: float, warp_source: float) -> float:
	var fx := float(x)
	var fy := float(y)
	if scratch_gate < 0.76:
		return 0.0
	var warp := (warp_source - 0.5) * 6.0
	var band := absf(fmod(fx * 2.8 + fy * 4.7 + float(seed) * 3.3 + warp, 51.0) - 25.5)
	return (1.0 - _smoothstep(0.55, 2.2, band)) * _smoothstep(0.76, 0.94, scratch_gate)


func _smooth_noise01(x: float, y: float, seed: int) -> float:
	var floor_x: float = floor(x)
	var floor_y: float = floor(y)
	var x0 := int(floor_x)
	var y0 := int(floor_y)
	var tx: float = x - floor_x
	var ty: float = y - floor_y
	var sx: float = tx * tx * (3.0 - 2.0 * tx)
	var sy: float = ty * ty * (3.0 - 2.0 * ty)
	var a: float = _noise01(x0, y0, seed)
	var b: float = _noise01(x0 + 1, y0, seed)
	var c: float = _noise01(x0, y0 + 1, seed)
	var d: float = _noise01(x0 + 1, y0 + 1, seed)
	return lerpf(lerpf(a, b, sx), lerpf(c, d, sx), sy)


func _noise01(x: int, y: int, seed: int) -> float:
	var value := x * 374761393 + y * 668265263 + seed * 1442695041
	value = (value ^ (value >> 13)) * 1274126177
	value = value ^ (value >> 16)
	return float(value & 0x7fffffff) / 2147483647.0


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
