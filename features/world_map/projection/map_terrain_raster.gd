extends RefCounted

## Immutable terrain-image snapshots and a world-space spatial index. Rendering
## is pure CPU work on Images; workers never access live Nodes or Terrain3D.
const INDEX_METERS := 1024.0
var _patches: Dictionary = {}
var _bins: Dictionary = {}

func set_patch(id: String, area: Rect2, height: Image, color: Image, control: Image = null) -> void:
	remove_patch(id)
	if height == null or height.is_empty() or not area.has_area():
		return
	# Terrain3D stores control flags as uint32 bits in an RF image; converting
	# its float values would lose those bits. Bit 2 marks authored holes.
	var flags := control.get_data().to_int32_array() if control != null else PackedInt32Array()
	var record := {"id": id, "area": area, "height": height.duplicate(), "color": color.duplicate() if color != null else null, "control": flags}
	_patches[id] = record
	for coord in _area_bins(area):
		var ids: Dictionary = _bins.get(coord, {})
		ids[id] = true
		_bins[coord] = ids

func remove_patch(id: String) -> void:
	if not _patches.has(id):
		return
	for coord in _area_bins(_patches[id]["area"]):
		var ids: Dictionary = _bins.get(coord, {})
		ids.erase(id)
		if ids.is_empty():
			_bins.erase(coord)
	_patches.erase(id)

func get_bounds() -> Rect2:
	var bounds := Rect2()
	for record in _patches.values():
		bounds = bounds.merge(record["area"]) if bounds.has_area() else record["area"]
	return bounds

func snapshot(area: Rect2) -> Dictionary:
	var result := {}
	var candidates := {}
	var lo := _bin(area.position)
	var hi := _bin(area.end)
	if (hi.x - lo.x + 1) * (hi.y - lo.y + 1) > _bins.size():
		for id in _patches:
			if area.intersects(_patches[id]["area"], true):
				candidates[id] = true
	else:
		for coord in _area_bins(area):
			for id in _bins.get(coord, {}):
				candidates[id] = true
	for id in candidates:
		var record: Dictionary = _patches[id]
		for coord in _area_bins(record["area"]):
			var records: Array = result.get(coord, [])
			records.append(record)
			result[coord] = records
	return result

static func render(area: Rect2, pixels: int, snapshot_data: Dictionary, style: Dictionary) -> Image:
	var image := Image.create(pixels, pixels, false, Image.FORMAT_RGBA8)
	var step := area.size.x / float(pixels)
	# Sample once, including a one-pixel gutter for seamless hillshade. Keep
	# dictionaries and spatial lookups OUT of the inner pixel loops.
	var stride := pixels + 2
	var heights := PackedFloat32Array()
	heights.resize(stride * stride)
	heights.fill(NAN)
	var colors := PackedColorArray()
	colors.resize(stride * stride)
	colors.fill(Color.WHITE)
	var records := {}
	for bin: Array in snapshot_data.values():
		for record: Dictionary in bin:
			records[record["id"]] = record
	for record: Dictionary in records.values():
		var patch: Rect2 = record["area"]
		var height: Image = record["height"]
		var paint: Image = record["color"]
		var flags: PackedInt32Array = record["control"]
		var lo := Vector2i(((patch.position - area.position) / step + Vector2.ONE * 0.5).ceil()).clamp(Vector2i.ZERO, Vector2i.ONE * stride)
		var hi := Vector2i(((patch.end - area.position) / step + Vector2.ONE * 0.5).ceil()).clamp(Vector2i.ZERO, Vector2i.ONE * stride)
		var height_scale := Vector2(height.get_size()) / patch.size
		var paint_size := paint.get_size() if paint != null else Vector2i.ONE
		for y in range(lo.y, hi.y):
			var world_y := area.position.y + (y - 0.5) * step - patch.position.y
			var hy := clampi(floori(world_y * height_scale.y), 0, height.get_height() - 1)
			var hy_next := mini(hy + 1, height.get_height() - 1)
			var fy := clampf(world_y * height_scale.y - hy, 0, 1)
			var cy := clampi(floori(world_y / patch.size.y * paint_size.y), 0, paint_size.y - 1)
			for x in range(lo.x, hi.x):
				var world_x := area.position.x + (x - 0.5) * step - patch.position.x
				var hx := clampi(floori(world_x * height_scale.x), 0, height.get_width() - 1)
				var source_index := hy * height.get_width() + hx
				if source_index < flags.size() and (flags[source_index] & 4) != 0:
					continue
				var index := y * stride + x
				var hx_next := mini(hx + 1, height.get_width() - 1)
				var fx := clampf(world_x * height_scale.x - hx, 0, 1)
				var upper := lerpf(height.get_pixel(hx, hy).r, height.get_pixel(hx_next, hy).r, fx)
				var lower := lerpf(height.get_pixel(hx, hy_next).r, height.get_pixel(hx_next, hy_next).r, fx)
				heights[index] = lerpf(upper, lower, fy)
				if paint != null:
					colors[index] = paint.get_pixel(clampi(floori(world_x / patch.size.x * paint_size.x), 0, paint_size.x - 1), cy)
	var land: Color = style.get("land", Color("b6a27c"))
	var strength: float = style.get("relief", 0.85)
	var interval: float = style.get("contour", 20.0)
	var sun := Vector3(-0.55, 0.8, -0.4).normalized()
	for y in range(pixels):
		for x in range(pixels):
			var index := (y + 1) * stride + x + 1
			var h := heights[index]
			if not is_finite(h):
				continue
			var color := colors[index]
			# Paint is a multiplicative tint, including compressed near-whites.
			# A threshold here produces false white patches in neutral terrain.
			color *= land
			var east := heights[index + 1]
			var west := heights[index - 1]
			var south := heights[index + stride]
			var north := heights[index - stride]
			var dx := (east if is_finite(east) else h) - (west if is_finite(west) else h)
			var dy := (south if is_finite(south) else h) - (north if is_finite(north) else h)
			var normal := Vector3(-dx, 2.0 * step, -dy).normalized()
			var illumination := 1.0 + (normal.dot(sun) - 0.75) * strength
			color *= clampf(illumination, 0.35, 1.2)
			if interval > 0.0 and step < interval:
				var contour_distance := absf(fposmod(h + interval * 0.5, interval) - interval * 0.5)
				var width := clampf(Vector2(dx, dy).length() * 0.12, 0.12, interval * 0.08)
				var ink := 1.0 - smoothstep(0.0, width, contour_distance)
				color = color.lerp(Color("554d3c"), ink * 0.2)
			if bool(style.get("ocean_enabled", false)) and h < float(style.get("ocean_height", 0.0)):
				var depth := float(style.get("ocean_height", 0.0)) - h
				var water: Color = style.get("ocean", Color("668c92"))
				color = water.lightened(0.16 * exp(-depth / 10.0))
			color.a = 1.0
			image.set_pixel(x, y, color)
	return image


static func _bin(position: Vector2) -> Vector2i:
	return Vector2i((position / INDEX_METERS).floor())

static func _area_bins(area: Rect2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var lo := _bin(area.position)
	var hi := _bin(area.end - Vector2.ONE * 0.001)
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			result.append(Vector2i(x, y))
	return result
