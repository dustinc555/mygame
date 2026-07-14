@tool
extends RefCounted

## Pure marker-math for modular building piece snapping. No editor or plugin
## dependencies so it is unit-testable headless; building_tools.gd delegates
## every pairing/scoring/transform decision here.

const SNAP_DISTANCE_METERS := 0.55
## Balcony rails snap by horizontal proximity (they must lift from terrain
## height onto an elevated deck edge), so they get a cell-scale catch radius.
const RAIL_SNAP_CATCH_DISTANCE := 1.2


static func markers_compatible(source_marker: Node, target_marker: Node) -> bool:
	var source_type := str(source_marker.get("connector_type"))
	var target_type := str(target_marker.get("connector_type"))
	var source_accepts: PackedStringArray = source_marker.get("accepts_types")
	var target_accepts: PackedStringArray = target_marker.get("accepts_types")
	if not (source_accepts.has(target_type) or target_accepts.has(source_type)):
		return false
	# Balcony rails pair translate-only, so orientation is part of validity: a
	# rail may only bind an edge it lies along (marker Z axes both point into
	# their cell). Rotating the piece changes which edges qualify, which is
	# what lets Rot 90 walk a corner balcony around a cell deterministically.
	if is_rail_edge_pair(source_marker, target_marker):
		var source_axis := (source_marker as Node3D).global_transform.basis.z
		var target_axis := (target_marker as Node3D).global_transform.basis.z
		return source_axis.normalized().dot(target_axis.normalized()) > 0.9
	return true


static func is_rail_edge_pair(source_marker: Node, target_marker: Node) -> bool:
	return str(source_marker.get("connector_type")) == "balcony_rail" and str(target_marker.get("connector_type")) == "floor_edge"


## Any pairing initiated by a balcony connector (rail->floor_edge,
## rail_end->rail_end, rail_bottom->wall_top) shares the balcony catch rules.
static func is_balcony_pair(source_marker: Node, target_marker: Node) -> bool:
	return str(source_marker.get("connector_type")).begins_with("balcony_rail") or str(target_marker.get("connector_type")).begins_with("balcony_rail")


## Insert pairs (door/window) adopt the full target frame instead of a
## translate-only delta.
static func align_transform_pair(source_marker: Node, target_marker: Node) -> bool:
	var source_type := str(source_marker.get("connector_type"))
	var target_type := str(target_marker.get("connector_type"))
	return (source_type == "window_insert" and target_type == "window_socket") or (source_type == "window_socket" and target_type == "window_insert") or (source_type == "door_insert" and target_type == "door_socket") or (source_type == "door_socket" and target_type == "door_insert")


static func new_piece_snap_score(source_marker: Node, target_marker: Node) -> float:
	var source_type := str(source_marker.get("connector_type"))
	var target_type := str(target_marker.get("connector_type"))
	var target_id := str(target_marker.get("snap_id"))
	if align_transform_pair(source_marker, target_marker):
		return 0.0
	if is_balcony_pair(source_marker, target_marker):
		return 0.0
	if source_type == "wall_bottom" and target_type == "floor_edge":
		return 0.0 if target_id == "south" else 5.0
	return 10.0


static func piece_snap_transform(piece: Node3D, source_marker: Node, target_marker: Node) -> Transform3D:
	var snapped_transform := piece.global_transform
	var source_marker_3d := source_marker as Node3D
	var target_marker_3d := target_marker as Node3D
	if source_marker_3d == null or target_marker_3d == null:
		return snapped_transform
	if align_transform_pair(source_marker, target_marker):
		var source_local_transform := piece.global_transform.affine_inverse() * source_marker_3d.global_transform
		return target_marker_3d.global_transform * source_local_transform.affine_inverse()
	snapped_transform.origin += target_marker_3d.global_position - source_marker_3d.global_position
	return snapped_transform


## Nearest compatible marker pairing. Returns {} or {transform, distance}.
static func find_best_snap(piece: Node3D, candidate_markers: Array, max_distance: float) -> Dictionary:
	if piece == null or not piece.has_method("get_snap_markers"):
		return {}
	var best_distance := INF
	var best_transform := Transform3D.IDENTITY
	var found := false
	for source_marker in piece.call("get_snap_markers"):
		if not (source_marker is Node3D):
			continue
		for target_marker in candidate_markers:
			if not markers_compatible(source_marker, target_marker):
				continue
			var delta := (target_marker as Node3D).global_position - (source_marker as Node3D).global_position
			var balcony_pair := is_balcony_pair(source_marker, target_marker)
			# Balcony pairs catch by horizontal proximity: the spawn ghost
			# drops pieces at terrain height, so a rail must be able to lift
			# several meters onto the deck edge / rail end / wall top above the
			# cursor. The small vertical weight still prefers the nearest
			# candidate when floors are stacked.
			var distance := (Vector2(delta.x, delta.z).length() + absf(delta.y) * 0.2) if balcony_pair else delta.length()
			var allowed_distance := RAIL_SNAP_CATCH_DISTANCE if balcony_pair else max_distance
			if distance <= allowed_distance and distance < best_distance:
				best_distance = distance
				best_transform = piece_snap_transform(piece, source_marker, target_marker)
				found = true
	if found:
		return {"transform": best_transform, "distance": best_distance}
	return {}
