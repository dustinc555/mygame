extends RefCounted

## Native Image cropping/resizing composes sparse discovery chunks into a tile
## mask. It never allocates a continent-sized image or visits all world cells.
const STATE := preload("res://features/world_map/sim/c_map_exploration_state.gd")

static func render(state: Resource, area: Rect2, pixels: int) -> Image:
	var result := Image.create(pixels, pixels, false, Image.FORMAT_L8)
	if state == null or not area.has_area():
		return result
	var lo := Vector2i((area.position / STATE.CHUNK_METERS).floor())
	var hi := Vector2i(((area.end - Vector2.ONE * 0.001) / STATE.CHUNK_METERS).floor())
	var coords: Array[Vector2i] = []
	if (hi.x - lo.x + 1) * (hi.y - lo.y + 1) > state.chunks.size():
		for key in state.chunks:
			var coord: Vector2i = STATE.chunk_coord(key)
			if coord.x >= lo.x and coord.y >= lo.y and coord.x <= hi.x and coord.y <= hi.y:
				coords.append(coord)
	else:
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var coord := Vector2i(x, y)
				if state.chunks.has(STATE.chunk_key(coord)):
					coords.append(coord)
	for coord in coords:
		var chunk_rect := Rect2(Vector2(coord) * STATE.CHUNK_METERS, Vector2.ONE * STATE.CHUNK_METERS)
		var overlap := area.intersection(chunk_rect)
		var source_rect := Rect2i((overlap.position - chunk_rect.position) / STATE.CELL_METERS, overlap.size / STATE.CELL_METERS)
		if not source_rect.has_area():
			continue
		var image: Image = state.chunk_image(coord).get_region(source_rect)
		var target := Vector2i(((overlap.position - area.position) / area.size * pixels).round())
		var size := Vector2i((overlap.size / area.size * pixels).round()).max(Vector2i.ONE)
		image.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
		result.blit_rect(image, Rect2i(Vector2i.ZERO, size), target)
	return result
