extends "res://addons/gecs/ecs/component.gd"

## Durable party knowledge. Fixed world-space cells, not UI pixels or terrain
## region IDs: changing the atlas size/resolution never moves explored ground.
## Cell layout is save-format version 1; change it only with a save migration.
const CELL_METERS := 8.0
const CHUNK_CELLS := 32
const CHUNK_METERS := CELL_METERS * CHUNK_CELLS

@export var world_id := ""
@export var format_version := 1
@export var chunks: Dictionary = {}
@export var known_features: Dictionary = {}

func reveal_circle(center: Vector2, radius: float) -> Array[Vector2i]:
	var changed: Array[Vector2i] = []
	if not center.is_finite() or not is_finite(radius) or radius <= 0.0:
		return changed
	var lo := Vector2i((center - Vector2.ONE * radius).floor() / CELL_METERS) - Vector2i.ONE
	var hi := Vector2i((center + Vector2.ONE * radius).ceil() / CELL_METERS) + Vector2i.ONE
	var touched := {}
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var cell := Vector2i(x, y)
			var distance := ((Vector2(cell) + Vector2.ONE * 0.5) * CELL_METERS).distance_to(center)
			var value := int(clampf((radius - distance) / CELL_METERS, 0.0, 1.0) * 255.0)
			if value <= 0:
				continue
			var coord := _chunk_for_cell(cell)
			var key := chunk_key(coord)
			var bytes: PackedByteArray = touched.get(key, chunks.get(key, PackedByteArray()))
			if bytes.is_empty():
				bytes.resize(CHUNK_CELLS * CHUNK_CELLS)
			var index := posmod(cell.y, CHUNK_CELLS) * CHUNK_CELLS + posmod(cell.x, CHUNK_CELLS)
			if value <= bytes[index]:
				continue
			bytes[index] = value
			touched[key] = bytes
			if not changed.has(coord):
				changed.append(coord)
	for key in touched:
		chunks[key] = touched[key]
	return changed

func is_discovered(position: Vector2) -> bool:
	return coverage_at(position) >= 128

func coverage_at(position: Vector2) -> int:
	if not position.is_finite():
		return 0
	var cell := Vector2i((position / CELL_METERS).floor())
	var bytes: PackedByteArray = chunks.get(chunk_key(_chunk_for_cell(cell)), PackedByteArray())
	if bytes.size() != CHUNK_CELLS * CHUNK_CELLS:
		return 0
	return bytes[posmod(cell.y, CHUNK_CELLS) * CHUNK_CELLS + posmod(cell.x, CHUNK_CELLS)]

func chunk_image(coord: Vector2i) -> Image:
	var bytes: PackedByteArray = chunks.get(chunk_key(coord), PackedByteArray())
	if bytes.size() != CHUNK_CELLS * CHUNK_CELLS:
		bytes.resize(CHUNK_CELLS * CHUNK_CELLS)
	return Image.create_from_data(CHUNK_CELLS, CHUNK_CELLS, false, Image.FORMAT_L8, bytes)

func to_state() -> Dictionary:
	return {"world_id": world_id, "format_version": format_version, "chunks": chunks.duplicate(true), "known_features": known_features.duplicate(true)}

func apply_state(source: Dictionary) -> void:
	world_id = str(source.get("world_id", ""))
	format_version = int(source.get("format_version", 1))
	chunks = {}
	var raw = source.get("chunks", {})
	if raw is Dictionary and format_version == 1:
		for key in raw:
			var bytes = raw[key]
			if bytes is PackedByteArray and bytes.size() == CHUNK_CELLS * CHUNK_CELLS:
				chunks[str(key)] = bytes.duplicate()
	var features = source.get("known_features", {})
	known_features = features.duplicate(true) if features is Dictionary else {}

static func chunk_key(coord: Vector2i) -> String:
	return "%d:%d" % [coord.x, coord.y]

static func chunk_coord(key: String) -> Vector2i:
	var parts := key.split(":")
	return Vector2i(int(parts[0]), int(parts[1])) if parts.size() == 2 else Vector2i.ZERO

static func _chunk_for_cell(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / CHUNK_CELLS), floori(float(cell.y) / CHUNK_CELLS))
