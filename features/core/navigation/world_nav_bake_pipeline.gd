extends RefCounted

class_name WorldNavBakePipeline

## Shared world navmesh bake pipeline: tile grid math, per-tile baking, and
## the on-disk navcache format. Used by three callers with identical results:
## - WorldNavigationController (runtime bakes + cache loading)
## - tools/bake_world_navcache.gd (headless CLI bake)
## - the world_authoring editor plugin's "Bake World Nav" button
##
## Cache layout, deterministic per world scene:
##   <world scene dir>/navcache/manifest.json
##   <world scene dir>/navcache/tile_<x>_<z>.res
## The manifest records the bake settings; a mismatch at load invalidates the
## whole cache (runtime falls back to a fresh bake).

const POSTPROCESS := preload("res://features/core/navigation/navigation_mesh_postprocess.gd")

const CACHE_DIR_NAME := "navcache"
const MANIFEST_VERSION := 3

## Recast silently returns an EMPTY mesh past roughly 4096 heightfield cells
## per side; tile_size is clamped so a tile can never cross it.
const MAX_BAKE_CELLS_PER_SIDE := 3200.0
## Recast erodes agent_radius from every bake boundary, which would leave a
## gap at every tile seam and make each tile a pathing island. Each tile is
## baked with this many EXTRA cells around it (NavigationMesh.border_size
## trims them back), so polygons reach flush to the true tile edge and
## neighbors stitch. Must exceed one full terrain source quad (~1m) plus
## agent erosion plus slack.
const TILE_BORDER_CELLS := 24
const TERRAIN_REGION_SIZE_FALLBACK := 256.0
## Physics layer 4 (value 8) is reserved for runtime-only door blockers and
## layer 5 (value 16) for click-only door panels. Actors collide with the
## blocker, nothing collides with the panel, and doorway portals always remain
## in the baked navigation mesh. Every other layer bakes, matching the
## pre-door pipeline (furniture such as beds carves nav from layer 3).
const NAV_BAKED_COLLISION_MASK := 0xFFFFFFFF & ~(8 | 16)


static func build_template(settings: WorldNavigationSettings, tiled: bool) -> NavigationMesh:
	var mesh := NavigationMesh.new()
	mesh.agent_radius = settings.agent_radius
	mesh.agent_height = settings.agent_height
	mesh.agent_max_slope = settings.agent_max_slope
	mesh.agent_max_climb = settings.agent_max_climb
	mesh.cell_size = settings.cell_size
	mesh.cell_height = settings.cell_height
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = NAV_BAKED_COLLISION_MASK
	mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	if tiled:
		# border_size is world units: trim exactly the erosion border added
		# around the tile so polygons end flush at the true tile edge.
		mesh.border_size = settings.cell_size * TILE_BORDER_CELLS
	return mesh


static func clamped_tile_size(settings: WorldNavigationSettings) -> float:
	return minf(settings.tile_size, settings.cell_size * MAX_BAKE_CELLS_PER_SIDE)


static func tile_coord(position: Vector3, tile_size: float) -> Vector2i:
	return Vector2i(int(floorf(position.x / tile_size)), int(floorf(position.z / tile_size)))


## Every tile overlapping actual terrain region data across all terrains.
static func enumerate_world_tiles(terrains: Array, settings: WorldNavigationSettings) -> Array[Vector2i]:
	var tile := clamped_tile_size(settings)
	var seen := {}
	for terrain in terrains:
		if not is_instance_valid(terrain):
			continue
		var region_world := _terrain_region_world_size(terrain)
		var data: Object = terrain.get("data")
		if data == null or not data.has_method("get_region_locations"):
			continue
		for location in data.call("get_region_locations"):
			var region_origin: Vector2 = Vector2(location.x, location.y) * region_world
			var lo := Vector2i(int(floorf(region_origin.x / tile)), int(floorf(region_origin.y / tile)))
			var hi := Vector2i(int(ceilf((region_origin.x + region_world) / tile)) - 1, int(ceilf((region_origin.y + region_world) / tile)) - 1)
			for x in range(lo.x, hi.x + 1):
				for z in range(lo.y, hi.y + 1):
					seen[Vector2i(x, z)] = true
	var result: Array[Vector2i] = []
	for coord in seen:
		result.append(coord)
	return result


## The expanded bake volume for one tile (erosion border included).
static func tile_bake_aabb(coord: Vector2i, settings: WorldNavigationSettings) -> AABB:
	var tile := clamped_tile_size(settings)
	var border := settings.cell_size * TILE_BORDER_CELLS
	var origin := Vector3(coord.x * tile - border, -settings.tile_height * 0.5, coord.y * tile - border)
	return AABB(origin, Vector3(tile + border * 2.0, settings.tile_height, tile + border * 2.0))


## Bakes one tile. Thread-safe: reads terrain data and the duplicated
## geometry only; touches no scene-tree state.
static func bake_tile(template: NavigationMesh, coord: Vector2i, settings: WorldNavigationSettings, terrains: Array, geometry: NavigationMeshSourceGeometryData3D) -> NavigationMesh:
	var aabb := tile_bake_aabb(coord, settings)
	var nav_mesh: NavigationMesh = template.duplicate()
	nav_mesh.filter_baking_aabb = AABB(Vector3.ZERO - aabb.size * 0.5, aabb.size)
	nav_mesh.filter_baking_aabb_offset = aabb.get_center()
	for terrain in terrains:
		if not is_instance_valid(terrain):
			continue
		var faces: PackedVector3Array = terrain.generate_nav_mesh_source_geometry(aabb, settings.require_navigable_paint)
		if not faces.is_empty():
			geometry.add_faces(faces, Transform3D.IDENTITY)
	# Bounds anchors: the generator derives its heightfield bounds from the
	# geometry extents, which wobble per tile and make the border trim land
	# off the tile edge (leaving seam gaps). Two tiny corner triangles pin
	# every tile's bounds to the exact expanded box so cell grids align and
	# edges end flush at the tile border. They sit inside the trimmed border,
	# so they never appear in the final mesh. Nudged inward so the filter
	# AABB cannot cull them on the boundary.
	var bounds_min := aabb.position + Vector3(0.05, 0.05, 0.05)
	var bounds_max := aabb.position + aabb.size - Vector3(0.05, 0.05, 0.05)
	geometry.add_faces(PackedVector3Array([
		bounds_min, bounds_min + Vector3(0.01, 0.0, 0.0), bounds_min + Vector3(0.0, 0.0, 0.01),
		bounds_max, bounds_max - Vector3(0.01, 0.0, 0.0), bounds_max - Vector3(0.0, 0.0, 0.01),
	]), Transform3D.IDENTITY)
	if geometry.has_data():
		NavigationServer3D.bake_from_source_geometry_data(nav_mesh, geometry)
		if settings.postprocess_enabled:
			POSTPROCESS.apply(nav_mesh)
	return nav_mesh


## --- Cache I/O ----------------------------------------------------------------


static func cache_dir_for_scene(scene_path: String) -> String:
	if scene_path.is_empty():
		return ""
	return scene_path.get_base_dir() + "/" + CACHE_DIR_NAME


static func tile_cache_path(cache_dir: String, coord: Vector2i) -> String:
	return "%s/tile_%d_%d.res" % [cache_dir, coord.x, coord.y]


static func settings_signature(settings: WorldNavigationSettings) -> Dictionary:
	return {
		"version": MANIFEST_VERSION,
		"agent_radius": settings.agent_radius,
		"agent_height": settings.agent_height,
		"agent_max_slope": settings.agent_max_slope,
		"agent_max_climb": settings.agent_max_climb,
		"cell_size": settings.cell_size,
		"cell_height": settings.cell_height,
		"tile_size": settings.tile_size,
		"tile_height": settings.tile_height,
		"require_navigable_paint": settings.require_navigable_paint,
		"postprocess_enabled": settings.postprocess_enabled,
		"tile_border_cells": TILE_BORDER_CELLS,
	}


static func save_manifest(cache_dir: String, settings: WorldNavigationSettings, tile_count: int) -> bool:
	DirAccess.make_dir_recursive_absolute(cache_dir)
	var manifest := settings_signature(settings)
	manifest["tile_count"] = tile_count
	var file := FileAccess.open(cache_dir + "/manifest.json", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(manifest, "\t"))
	return true


## Returns true when a cache exists and was baked with matching settings.
static func manifest_matches(cache_dir: String, settings: WorldNavigationSettings) -> bool:
	if cache_dir.is_empty() or not FileAccess.file_exists(cache_dir + "/manifest.json"):
		return false
	var file := FileAccess.open(cache_dir + "/manifest.json", FileAccess.READ)
	if file == null:
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return false
	var expected := settings_signature(settings)
	for key in expected:
		if not parsed.has(key) or not is_equal_approx_variant(parsed[key], expected[key]):
			return false
	return true


static func is_equal_approx_variant(a, b) -> bool:
	if a is float and b is float:
		return is_equal_approx(a, b)
	if (a is float and b is int) or (a is int and b is float):
		return is_equal_approx(float(a), float(b))
	return a == b


static func save_tile(cache_dir: String, coord: Vector2i, nav_mesh: NavigationMesh) -> bool:
	DirAccess.make_dir_recursive_absolute(cache_dir)
	return ResourceSaver.save(nav_mesh, tile_cache_path(cache_dir, coord), ResourceSaver.FLAG_COMPRESS) == OK


## Returns null when the tile has no cache entry.
static func load_tile(cache_dir: String, coord: Vector2i) -> NavigationMesh:
	var path := tile_cache_path(cache_dir, coord)
	if not ResourceLoader.exists(path):
		return null
	# CACHE_MODE_IGNORE: a stale in-memory copy of a previously loaded tile
	# must not shadow a newer bake on disk.
	return ResourceLoader.load(path, "NavigationMesh", ResourceLoader.CACHE_MODE_IGNORE) as NavigationMesh


## --- Debug/preview mesh builders (shared by runtime Nav Debug and the
## --- editor bake tool's preview toggles) ---------------------------------------


static func build_navmesh_debug_mesh(nav_mesh: NavigationMesh) -> ArrayMesh:
	var vertices: PackedVector3Array = nav_mesh.get_vertices()
	var triangles := PackedVector3Array()
	# The bake quantizes Y to cell_height (0.1), so navmesh polygons can sit up
	# to a full cell BELOW the walkable surface; modular floor visuals add a
	# little more on top. The lift must clear both or the preview renders just
	# beneath floor panels and reads as "nav missing on floors".
	var lift := Vector3(0.0, 0.2, 0.0)
	for p in range(nav_mesh.get_polygon_count()):
		var polygon: PackedInt32Array = nav_mesh.get_polygon(p)
		for i in range(1, polygon.size() - 1):
			triangles.append(vertices[polygon[0]] + lift)
			triangles.append(vertices[polygon[i]] + lift)
			triangles.append(vertices[polygon[i + 1]] + lift)
	if triangles.is_empty():
		return null
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = triangles
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func build_tile_frame_mesh(coord: Vector2i, tile_size: float) -> ArrayMesh:
	var x0 := coord.x * tile_size
	var z0 := coord.y * tile_size
	var y := 0.6
	var lines := PackedVector3Array([
		Vector3(x0, y, z0), Vector3(x0 + tile_size, y, z0),
		Vector3(x0 + tile_size, y, z0), Vector3(x0 + tile_size, y, z0 + tile_size),
		Vector3(x0 + tile_size, y, z0 + tile_size), Vector3(x0, y, z0 + tile_size),
		Vector3(x0, y, z0 + tile_size), Vector3(x0, y, z0),
	])
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = lines
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


static func debug_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## Tile coordinates present in a navcache directory (parsed from filenames).
static func cached_tile_coords(cache_dir: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var dir := DirAccess.open(cache_dir)
	if dir == null:
		return result
	for file_name in dir.get_files():
		if not file_name.begins_with("tile_") or not file_name.ends_with(".res"):
			continue
		var parts := file_name.trim_prefix("tile_").trim_suffix(".res").split("_")
		if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			result.append(Vector2i(int(parts[0]), int(parts[1])))
	return result


static func _terrain_region_world_size(terrain: Node) -> float:
	var region_size := float(terrain.get("region_size")) if terrain.get("region_size") != null else TERRAIN_REGION_SIZE_FALLBACK
	var spacing_value = terrain.get("vertex_spacing")
	var spacing := float(spacing_value) if spacing_value != null else 1.0
	return region_size * spacing
