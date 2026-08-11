@tool
class_name BuildingPlacementSolver
extends RefCounted

## Terrain-conforming building placement math, shared by every placement
## surface: the runtime Building Placer ghost and the editor town authoring
## tools. Pure static functions over an explicit PhysicsDirectSpaceState3D —
## no scene lookups, no records access. Zoning/faction rules stay with
## ConstructionController.can_place(); callers combine that with slope_ok.

const MAX_SLOPE_DEG := 15.0
## Above this raise the building is presumed on a foundation, which
## flattens: orient flat instead of following terrain normal.
const FOUNDATION_FLAT_Y_OFFSET := 0.5
const MIN_FOOTPRINT_HITS := 3
const FOOTPRINT_RAY_REACH := 30.0
const SCREEN_RAY_LENGTH := 2000.0
const TERRAIN_RAY_RETRIES := 6


## Full placement solution for a ground point: oriented transform plus slope
## validity for the building footprint.
static func solve(space: PhysicsDirectSpaceState3D, ground_position: Vector3, footprint: Vector2, yaw: float, y_offset: float) -> Dictionary:
	var sample := sample_footprint_normal(space, ground_position, footprint)
	var normal: Vector3 = sample["normal"]
	if y_offset > FOUNDATION_FLAT_Y_OFFSET:
		normal = Vector3.UP
	var slope_ok: bool = int(sample["hits"]) >= MIN_FOOTPRINT_HITS and Vector3(sample["normal"]).angle_to(Vector3.UP) <= deg_to_rad(MAX_SLOPE_DEG)
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	forward = (forward - normal * forward.dot(normal)).normalized()
	var basis := Basis(normal.cross(forward), normal, forward)
	return {
		"transform": Transform3D(basis, ground_position + Vector3(0.0, y_offset, 0.0)),
		"normal": normal,
		"slope_ok": slope_ok,
		"hits": int(sample["hits"]),
	}


## Re-solves an authored/serialized transform against the live terrain:
## keeps the authored XZ position and yaw, recomputes ground Y and surface
## tilt, then restores the intentional raise (foundation_height). Returns {}
## when no terrain lies under the authored origin (caller keeps the
## authored transform).
static func snap_to_terrain(space: PhysicsDirectSpaceState3D, authored: Transform3D, footprint: Vector2, foundation_height := 0.0) -> Dictionary:
	var from := authored.origin + Vector3(0.0, FOOTPRINT_RAY_REACH, 0.0)
	var to := authored.origin - Vector3(0.0, FOOTPRINT_RAY_REACH * 2.0, 0.0)
	var hit := terrain_ray(space, from, to)
	if hit.is_empty():
		return {}
	var yaw := atan2(authored.basis.z.x, authored.basis.z.z)
	return solve(space, hit["position"], footprint, yaw, foundation_height)


## XZ footprint estimate from the merged visual bounds, for nodes without an
## authored footprint_size definition.
static func estimate_footprint(node: Node3D) -> Vector2:
	var bounds: Variant = _merge_visual_bounds(node)
	if bounds == null:
		return Vector2(2.0, 2.0)
	var size := (bounds as AABB).size
	return Vector2(maxf(size.x, 0.5), maxf(size.z, 0.5))


static func _merge_visual_bounds(node: Node) -> Variant:
	var merged: Variant = null
	if node is VisualInstance3D and node.is_inside_tree():
		var visual := node as VisualInstance3D
		merged = visual.global_transform * visual.get_aabb()
	for child in node.get_children():
		var child_bounds: Variant = _merge_visual_bounds(child)
		if child_bounds == null:
			continue
		merged = child_bounds if merged == null else (merged as AABB).merge(child_bounds as AABB)
	return merged


## Averaged terrain normal across the footprint: center + 4 edge offsets,
## using the physics hit normals. Fewer than MIN_FOOTPRINT_HITS hits means
## the footprint hangs off the terrain.
static func sample_footprint_normal(space: PhysicsDirectSpaceState3D, ground_position: Vector3, footprint: Vector2) -> Dictionary:
	var half := footprint * 0.5
	var normal_sum := Vector3.ZERO
	var hits := 0
	for offset in [Vector2.ZERO, Vector2(half.x, 0), Vector2(-half.x, 0), Vector2(0, half.y), Vector2(0, -half.y)]:
		var from := ground_position + Vector3(offset.x, FOOTPRINT_RAY_REACH, offset.y)
		var result := terrain_ray(space, from, ground_position + Vector3(offset.x, -FOOTPRINT_RAY_REACH, offset.y))
		if not result.is_empty():
			normal_sum += result["normal"]
			hits += 1
	if hits == 0:
		return {"normal": Vector3.UP, "hits": 0}
	return {"normal": normal_sum.normalized(), "hits": hits}


## Mouse ray to TERRAIN only.
static func terrain_hit_from_screen(camera: Camera3D, screen_position: Vector2) -> Dictionary:
	if camera == null:
		return {}
	var space := camera.get_world_3d().direct_space_state
	var from := camera.project_ray_origin(screen_position)
	var to := from + camera.project_ray_normal(screen_position) * SCREEN_RAY_LENGTH
	return terrain_ray(space, from, to)


## Ray to TERRAIN only: hits whose collider belongs to a building piece or an
## actor are excluded and the ray re-cast.
static func terrain_ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var exclude: Array[RID] = []
	for _attempt in range(TERRAIN_RAY_RETRIES):
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = exclude
		var result := space.intersect_ray(query)
		if result.is_empty():
			return {}
		if is_terrain_collider(result.get("collider")):
			return result
		exclude.append(result["rid"])
	return {}


static func is_terrain_collider(collider) -> bool:
	if is_native_terrain_collider(collider):
		return true
	if collider is CharacterBody3D:
		return false
	var walker := collider as Node
	while walker != null:
		if walker is ModularBuildingPiece or walker.is_in_group("world_building") or walker.is_in_group("modular_building_piece"):
			return false
		walker = walker.get_parent()
	return true


## Terrain3D physics hits vary by engine/addon version: some return the live
## extension node, while others return a non-Node PhysicsServer wrapper.
static func is_native_terrain_collider(collider) -> bool:
	if collider == null:
		return true
	if collider is Object and collider.is_class("Terrain3D"):
		return true
	return not (collider is Node)
